--!strict

-- The official servers people join from the Communities section.
--
-- Nothing teleported anywhere before this: the section could list communities
-- and had no way to send anybody to one.
--
-- Each official server is a Roblox reserved server. It is reserved once, its
-- access code is kept, and every later join is sent to that same code, so
-- everybody choosing Portsmouth lands in the same Portsmouth rather than in
-- whichever instance matchmaking happened to spin up. The code outlives the
-- server it belongs to, so an empty one starts fresh and keeps its identity.
--
-- Reserving and teleporting are both server side only, which is why this lives
-- here and the client merely asks.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local OfficialServerService = { codes = {}, reserving = {} }

function OfficialServerService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.OfficialServers
end

-- Stored beside the communities rather than in a store of its own. The key is
-- prefixed so it cannot collide with a community id.
function OfficialServerService:_storageKey(serverId: string): string
	return "officialserver:" .. serverId
end

-- The access code for an official server, reserving one the first time it is
-- asked for. Reserved under UpdateAsync so two servers asking at the same moment
-- cannot each reserve one and split the community permanently in half.
function OfficialServerService:_code(serverId: string): (string?, string?)
	local cached = self.codes[serverId]
	if type(cached) == "string" and cached ~= "" then
		return cached, nil
	end
	-- One reservation at a time per server, so a burst of joins on a cold entry
	-- does not each start their own.
	if self.reserving[serverId] then
		local deadline = os.clock() + 10
		while self.reserving[serverId] and os.clock() < deadline do
			task.wait(0.1)
		end
		local settled = self.codes[serverId]
		if type(settled) == "string" and settled ~= "" then
			return settled, nil
		end
	end
	self.reserving[serverId] = true

	local data = self.context.Services:Get("DataService")
	local stored = data:GetCommunity(self:_storageKey(serverId))
	if
		type(stored) == "table"
		and type(stored.AccessCode) == "string"
		and stored.AccessCode ~= ""
	then
		self.codes[serverId] = stored.AccessCode
		self.reserving[serverId] = nil
		return stored.AccessCode, nil
	end

	local ok, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok or type(code) ~= "string" or code == "" then
		self.reserving[serverId] = nil
		self.context.Logger:Error(
			"Could not reserve an official server",
			{ ServerId = serverId, Error = tostring(code) }
		)
		return nil, "OFFICIAL_SERVER_UNAVAILABLE"
	end

	-- Written under UpdateAsync so a code reserved elsewhere at the same moment
	-- wins and this one is discarded, rather than the two overwriting each other
	-- and leaving players split across both.
	local saved = data:UpdateCommunity(self:_storageKey(serverId), function(existing)
		if type(existing) == "table" and type(existing.AccessCode) == "string" then
			return existing
		end
		return { ServerId = serverId, AccessCode = code, ReservedAt = os.time() }
	end)
	local settled = if type(saved) == "table" and type(saved.AccessCode) == "string"
		then saved.AccessCode
		else code
	self.codes[serverId] = settled
	self.reserving[serverId] = nil
	return settled, nil
end

-- The player is not consulted: every official server is open to anyone the
-- experience already let in, and the whitelist is the front door rather than a
-- gate on each entry.
function OfficialServerService:List(): { any }
	local rows = {}
	if self.settings.Enabled ~= true then
		return rows
	end
	local here = game.PrivateServerId
	for _, entry in self.settings.Entries do
		table.insert(rows, {
			Id = entry.Id,
			Name = entry.Name,
			Description = entry.Description,
			Order = entry.Order or 100,
			-- Known only once a code has been reserved on this server, which is
			-- enough to grey out the entry a player is already standing in.
			Current = here ~= "" and self.codes[entry.Id] ~= nil and self:_isHere(entry.Id),
		})
	end
	table.sort(rows, function(a, b)
		if a.Order == b.Order then
			return a.Name < b.Name
		end
		return a.Order < b.Order
	end)
	return rows
end

-- The official server entry this server is serving, or nil on the public place.
-- Everything that differs between the tiers is read from here, so a server's
-- identity is decided in one place rather than inferred separately by each
-- service that cares.
function OfficialServerService:CurrentEntry(): any?
	if type(self.currentServerId) ~= "string" then
		return nil
	end
	return self.settings.Entries[self.currentServerId]
end

-- The group this server requires, when it requires one. The public place
-- requires none, which is what makes it public.
function OfficialServerService:RequiredGroupLinkId(): string?
	local entry = self:CurrentEntry()
	local linkId = entry and entry.RequiredGroupLinkId
	return if type(linkId) == "string" then linkId else nil
end

-- Whether this server is the official server with that id. PrivateServerId is
-- the instance, and the access code is the door to it, so the two are compared
-- through what was stored rather than directly.
function OfficialServerService:_isHere(serverId: string): boolean
	return game.PrivateServerId ~= "" and self.currentServerId == serverId
end

function OfficialServerService:Join(player: Player, serverId: any): (any?, string?)
	if self.settings.Enabled ~= true then
		return nil, "OFFICIAL_SERVERS_DISABLED"
	end
	if type(serverId) ~= "string" or not self.settings.Entries[serverId] then
		return nil, "OFFICIAL_SERVER_NOT_FOUND"
	end
	if self:_isHere(serverId) then
		return nil, "ALREADY_ON_THIS_SERVER"
	end
	local code, reason = self:_code(serverId)
	if not code then
		return nil, reason
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	-- Carried so the destination knows which entry it is without having to work
	-- it back from an access code it cannot see.
	options:SetTeleportData({ OfficialServerId = serverId })
	local ok, problem =
		pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		self.context.Logger:Error(
			"Official server teleport failed",
			{ ServerId = serverId, UserId = player.UserId, Error = tostring(problem) }
		)
		return nil, "TELEPORT_FAILED"
	end
	return { ServerId = serverId }, nil
end

function OfficialServerService:Start()
	if self.settings.Enabled ~= true then
		return
	end
	-- Which official server this one is, taken from the data the teleport carried.
	-- A reserved server has no other way to know: the access code that opened it
	-- is not readable from inside.
	self:_adopt()
	self.connection = Players.PlayerAdded:Connect(function(player)
		self:_learnFrom(player)
	end)
end

-- Players already present when this service starts carry the same teleport data
-- as any later arrival, and on a reserved server the first of them is usually
-- already in before Start runs.
function OfficialServerService:_adopt()
	for _, player in Players:GetPlayers() do
		self:_learnFrom(player)
	end
end

function OfficialServerService:_learnFrom(player: Player)
	if self.currentServerId or game.PrivateServerId == "" then
		return
	end
	do
		local ok, data = pcall(player.GetJoinData, player)
		local teleportData = if ok and type(data) == "table" then data.TeleportData else nil
		local id = if type(teleportData) == "table" then teleportData.OfficialServerId else nil
		if type(id) == "string" and self.settings.Entries[id] then
			self.currentServerId = id
			self.context.Logger:Info("Serving an official server", { ServerId = id })
		end
	end
end

function OfficialServerService:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end
	table.clear(self.codes)
	table.clear(self.reserving)
end

return OfficialServerService
