--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GamepassService = { connections = {}, running = false }
function GamepassService:Init(context: any)
	self.context = context
	self.changedEvent = context.Network:RegisterEvent("GamepassOwnershipChanged")
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
						self:Refresh(player, definition)
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
