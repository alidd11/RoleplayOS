--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
-- Critical, because it is the only writer of a newly bought pass. Stepping over
-- it leaves a server that looks healthy, honours every pass bought earlier, and
-- silently takes Robux for every pass bought on it without delivering one.
local GamepassService = { Critical = true, connections = {}, running = false, purchased = {} }
function GamepassService:Init(context: any)
	self.context = context
	self.changedEvent = context.Network:RegisterEvent("GamepassOwnershipChanged")
end
-- Records a completed purchase and grants it at once.
function GamepassService:Grant(player: Player, definition: any)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return
	end
	local key = tostring(definition.GamepassId)
	local seen = self.purchased[player.UserId]
	if not seen then
		seen = {}
		self.purchased[player.UserId] = seen
	end
	seen[key] = true
	if session.Profile.GamepassCache[key] ~= true then
		session.Profile.GamepassCache[key] = true
		self.context.Services:Get("DataService"):MarkDirty(player)
		self.changedEvent:FireClient(player, { GamepassId = definition.GamepassId, Owned = true })
	end
	-- Logged so a refund dispute is answered from the record rather than from
	-- memory.
	self.context.Logger:Info("Gamepass purchased", {
		UserId = player.UserId,
		Player = player.Name,
		GamepassId = definition.GamepassId,
		Name = definition.Name,
	})
end

function GamepassService:Refresh(player: Player, definition: any): (boolean, string?)
	if definition.GamepassId == 0 then
		return false, "GAMEPASS_NOT_CONFIGURED"
	end
	local ok, owned = pcall(
		MarketplaceService.UserOwnsGamePassAsync,
		MarketplaceService,
		player.UserId,
		definition.GamepassId
	)
	if not ok then
		return false, "OWNERSHIP_CHECK_FAILED"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if session then
		local ownershipKey = tostring(definition.GamepassId)
		local seen = self.purchased[player.UserId]
		if seen and seen[ownershipKey] and not owned then
			-- A pass bought in this session is not taken away by a later check
			-- answering false, because the overwhelmingly likely reason for that
			-- answer is Roblox's own cache still being behind. Wrongly revoking
			-- something somebody paid for minutes ago is far worse than being
			-- slow to notice a genuine refund, which the next session catches.
			return true, nil
		end
		if session.Profile.GamepassCache[ownershipKey] ~= owned then
			session.Profile.GamepassCache[ownershipKey] = owned
			self.context.Services:Get("DataService"):MarkDirty(player)
			self.changedEvent:FireClient(player, {
				GamepassId = definition.GamepassId,
				Owned = owned,
			})
		end
	end
	return owned, nil
end

-- Roblox rate limits ownership checks per server in the same way it limits group
-- lookups, and there are fifteen passes here. Checking them back to back meant
-- fifteen web calls per joining player at once, and a server filling up made
-- hundreds within seconds, at which point the throttle answers every one of them
-- with a failure and nobody's purchases are recognised.
--
-- Spaced and jittered so that players joining together do not line their checks
-- up with each other. Nothing is waiting on this: a pass that resolves a second
-- later is invisible, whereas a throttled one reads as unowned.
function GamepassService:RefreshAll(player: Player)
	local spacing = self.context.Configuration.Groups.WarmSpacingSeconds or 0.6
	for _, definition in self.context.Configuration.Gamepasses do
		if not self.running or not player.Parent then
			return
		end
		self:Refresh(player, definition)
		task.wait(spacing * (0.5 + math.random()))
	end
end

function GamepassService:Start()
	self.running = true
	table.insert(
		self.connections,
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(
			function(player, gamepassId, purchased)
				if not purchased then
					return
				end
				for _, definition in self.context.Configuration.Gamepasses do
					if definition.GamepassId == gamepassId then
						-- Granted from this signal, not from an ownership check.
						--
						-- Roblox caches UserOwnsGamePassAsync, and that cache can
						-- still answer false for up to a minute after a purchase
						-- completes. Asking it here, which is what this did, meant
						-- the likeliest answer at the one moment it is asked is that
						-- the player who has just paid does not own the thing they
						-- paid for. They then have to rejoin to get it, or ask for
						-- their money back.
						--
						-- This signal is raised by MarketplaceService on the server,
						-- not by the client, so it is trustworthy, and it is
						-- authoritative about the purchase in a way the cache is not
						-- yet.
						self:Grant(player, definition)
					end
				end
			end
		)
	)
	local function refreshWhenReady(player: Player)
		task.spawn(function()
			local deadline = os.clock() + 15
			while
				player.Parent
				and not self.context.Services:Get("DataService"):GetSession(player)
				and os.clock() < deadline
			do
				task.wait(0.1)
			end
			if player.Parent then
				self:RefreshAll(player)
			end
		end)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(refreshWhenReady))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			-- The record only exists to stop a stale ownership check undoing a
			-- purchase within the session it happened in, so it goes with the
			-- session rather than growing for the life of the server.
			self.purchased[player.UserId] = nil
		end)
	)
	for _, player in Players:GetPlayers() do
		refreshWhenReady(player)
	end
end
function GamepassService:GetPromptMetadata(definitionId: string): any?
	local item = self.context.Configuration.Gamepasses[definitionId]
	if not item then
		return nil
	end
	return { GamepassId = item.GamepassId, Name = item.Name, Description = item.Description }
end
function GamepassService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end
return GamepassService
