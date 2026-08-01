--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GamepassService = {}
function GamepassService:Init(context: any)
	self.context = context
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
		session.Profile.GamepassCache[tostring(definition.GamepassId)] = owned
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
	return owned, nil
end
function GamepassService:Start()
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
	Players.PlayerRemoving:Connect(function() end)
end
function GamepassService:GetPromptMetadata(definitionId: string): any?
	local item = self.context.Configuration.Gamepasses[definitionId]
	if not item then
		return nil
	end
	return { GamepassId = item.GamepassId, Name = item.Name, Description = item.Description }
end
function GamepassService:Destroy() end
return GamepassService
