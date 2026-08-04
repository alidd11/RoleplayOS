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

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- Occupancy lives in a memory store rather than a data store: it is worth
-- nothing a minute from now, it is written every few seconds by every instance,
-- and a data store would be the wrong tool at that rate for something disposable.
local OCCUPANCY_MAP = "RoleplayOSOfficialOccupancy"

local OfficialServerService = { codes = {}, reserving = {} }

function OfficialServerService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.OfficialServers
	self.instances = {}
	local ok, map = pcall(MemoryStoreService.GetHashMap, MemoryStoreService, OCCUPANCY_MAP)
	self.occupancy = if ok then map else nil
	if not self.occupancy then
		self.context.Logger:Warning(
			"No memory store, so instances cannot see how full each other are",
			{}
		)
	end
end

function OfficialServerService:_occupancyKey(serverId: string, index: number): string
	return serverId .. ":" .. tostring(index)
end

-- How many people are on an instance, or nil when nobody has said recently.
-- Silence is treated as empty rather than full: an instance that has not
-- reported is far more likely to be one that has never started than one that is
-- full and has stopped talking.
function OfficialServerService:_occupantsOf(serverId: string, index: number): number
	if not self.occupancy then
		return 0
	end
	local ok, value =
		pcall(self.occupancy.GetAsync, self.occupancy, self:_occupancyKey(serverId, index))
	return if ok and type(value) == "number" then value else 0
end

-- Stored beside the communities rather than in a store of its own. The key is
-- prefixed so it cannot collide with a community id.
function OfficialServerService:_storageKey(serverId: string): string
	return "officialserver:" .. serverId
end

-- Picks an instance of an official server with room in it, opening another when
-- every existing one is full.
--
-- A reserved server has a hard player cap and a teleport into a full one simply
-- fails, so a single instance meant being turned away at exactly the times the
-- community most wanted to play. Instances are tried in order, so everybody
-- gathers in the first one and later ones open only under real pressure rather
-- than scattering people across half empty worlds.
function OfficialServerService:_pickInstance(serverId: string): (string?, number?, string?)
	local data = self.context.Services:Get("DataService")
	local stored, storeError = data:GetCommunity(self:_storageKey(serverId))
	if storeError then
		-- "No record" and "could not read" arrive the same way, and treating an
		-- outage as the former reserves a brand new server that nobody else can
		-- find. Several servers doing that at once is exactly the scattering this
		-- whole mechanism exists to prevent.
		self.context.Logger:Warning(
			"Could not read the official server record",
			{ ServerId = serverId, Error = tostring(storeError) }
		)
		return nil, nil, "OFFICIAL_SERVER_UNAVAILABLE"
	end
	local codes = {}
	if type(stored) == "table" then
		if type(stored.Instances) == "table" then
			codes = stored.Instances
		elseif type(stored.AccessCode) == "string" then
			-- Written before instances existed. The single code is instance one.
			codes = { stored.AccessCode }
		end
	end

	local capacity = self.settings.MaximumPlayersPerInstance or 30
	for index, code in codes do
		if type(code) == "string" and code ~= "" then
			if self:_occupantsOf(serverId, index) < capacity then
				self.codes[serverId] = code
				return code, index, nil
			end
		end
	end

	if #codes >= (self.settings.MaximumInstances or 6) then
		-- Refused rather than opening yet another. Past this the community is
		-- split too thin for the roleplay any of them came for.
		return nil, nil, "OFFICIAL_SERVER_FULL"
	end

	local ok, fresh = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok or type(fresh) ~= "string" or fresh == "" then
		self.context.Logger:Error(
			"Could not reserve an official server instance",
			{ ServerId = serverId, Error = tostring(fresh) }
		)
		return nil, nil, "OFFICIAL_SERVER_UNAVAILABLE"
	end

	-- Appended under UpdateAsync, so two servers opening an overflow at the same
	-- moment both keep their instance instead of one silently replacing the
	-- other and stranding whoever was sent there.
	local saved = data:UpdateCommunity(self:_storageKey(serverId), function(existing)
		local record = if type(existing) == "table" then existing else {}
		local list = if type(record.Instances) == "table"
			then record.Instances
			elseif type(record.AccessCode) == "string" then { record.AccessCode }
			else {}
		table.insert(list, fresh)
		record.ServerId = serverId
		record.Instances = list
		record.AccessCode = list[1]
		record.UpdatedAt = os.time()
		return record
	end)
	local list = if type(saved) == "table" and type(saved.Instances) == "table"
		then saved.Instances
		else { fresh }
	-- The index this code ended up at, which may not be the end if another
	-- server appended at the same time.
	for index, code in list do
		if code == fresh then
			self.codes[serverId] = fresh
			return fresh, index, nil
		end
	end
	self.codes[serverId] = fresh
	return fresh, #list, nil
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
			-- A reserved server cannot read the access code that opened it, so
			-- requiring one here meant the entry a player was standing in never
			-- knew itself and always offered to send them where they already were.
			Current = here ~= "" and self:_isHere(entry.Id),
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
	local code, index, reason = self:_pickInstance(serverId)
	if not code then
		return nil, reason
	end
	-- Saved and released before the teleport, not after.
	--
	-- A teleport is faster than a data store round trip. Leaving normally defers
	-- the final save, so the destination was reached while this server still held
	-- the profile lease, and it refused the load and kicked. The lease then sat
	-- there for its full duration, which locked the player out of every server
	-- including the one they came from: clicking join was close to a guaranteed
	-- two minute lockout.
	--
	-- Releasing first also means the destination reads the state as it was when
	-- they left rather than as it was at the last autosave.
	local data = self.context.Services:Get("DataService")
	local released, releaseReason = data:Save(player, true)
	if not released then
		self.context.Logger:Warning("Could not release the profile before a teleport", {
			ServerId = serverId,
			UserId = player.UserId,
			Error = tostring(releaseReason),
		})
		-- Going anyway would hand the destination a lease it cannot take, so the
		-- player is told to try again while they still have a working session
		-- here rather than being sent somewhere that will refuse them.
		return nil, "PROFILE_BUSY"
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	-- Carried so the destination knows which entry it is without having to work
	-- it back from an access code it cannot see.
	options:SetTeleportData({ OfficialServerId = serverId, InstanceIndex = index })
	local ok, problem =
		pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		self.context.Logger:Error(
			"Official server teleport failed",
			{ ServerId = serverId, UserId = player.UserId, Error = tostring(problem) }
		)
		-- The session was released for a journey that did not happen, so it is
		-- taken back. Without this the player stays here with no profile and
		-- every later action fails for a reason nobody could work out.
		if player:IsDescendantOf(Players) then
			data:Load(player)
		end
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
	-- A teleport that is accepted can still fail on arrival: a full instance, a
	-- restricted place, a flood check. The profile was released before the
	-- journey, so a player left behind by one of those has no session at all and
	-- every later action fails for a reason nobody could work out. This is the
	-- only signal Roblox gives for it.
	self.teleportFailed = TeleportService.TeleportInitFailed:Connect(
		function(player, result, message)
			self.context.Logger:Error("Teleport failed after being accepted", {
				UserId = player.UserId,
				Result = tostring(result),
				Message = tostring(message),
			})
			if player:IsDescendantOf(Players) then
				self.context.Services:Get("DataService"):Load(player)
			end
		end
	)
	self:_publishOccupancy()
end

-- Tells the other servers how full this one is.
--
-- Nothing else can find this out: a server cannot see inside another, so an
-- instance that never reports is one nobody will ever route around, and the
-- overflow would never open no matter how full this got.
--
-- Published with a lifetime several times the interval, so one missed beat
-- reads as slightly stale rather than as an empty server that everybody is then
-- sent into.
function OfficialServerService:_publishOccupancy()
	if not self.occupancy then
		return
	end
	self.publishing = true
	task.spawn(function()
		while self.publishing do
			local entry = self:CurrentEntry()
			local index = self.currentInstanceIndex
			if entry and index then
				local ok, problem = pcall(
					self.occupancy.SetAsync,
					self.occupancy,
					self:_occupancyKey(entry.Id, index),
					#Players:GetPlayers(),
					self.settings.OccupancyLifetimeSeconds or 45
				)
				if not ok then
					self.context.Logger:Warning(
						"Could not publish occupancy",
						{ ServerId = entry.Id, Instance = index, Error = tostring(problem) }
					)
				end
			end
			task.wait(self.settings.OccupancyHeartbeatSeconds or 12)
		end
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
			-- The instance number travels with the teleport for the same reason
			-- the entry does: a reserved server cannot see which of its own
			-- instances it is, and occupancy has to be reported per instance.
			local index = if type(teleportData) == "table"
				then tonumber(teleportData.InstanceIndex)
				else nil
			self.currentInstanceIndex = index or 1
			self.context.Logger:Info(
				"Serving an official server",
				{ ServerId = id, Instance = self.currentInstanceIndex }
			)
		end
	end
end

function OfficialServerService:Destroy()
	self.publishing = false
	if self.teleportFailed then
		self.teleportFailed:Disconnect()
	end
	if self.connection then
		self.connection:Disconnect()
	end
	table.clear(self.codes)
	table.clear(self.reserving)
end

return OfficialServerService
