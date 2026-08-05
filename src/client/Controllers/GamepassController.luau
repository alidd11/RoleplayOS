--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GamepassController = {}
function GamepassController:Init(context: any)
	self.context = context
	self.purchaseConnection = nil
end
function GamepassController:Start()
	self.purchaseConnection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, _gamepassId, purchased)
			if player ~= Players.LocalPlayer or not purchased then
				return
			end
			-- The server confirms ownership and writes the cache. Give that callback
			-- a moment to complete, then request a fresh server-authored menu model.
			task.delay(0.75, function()
				self.context.Controllers.StartMenuController:Refresh()
			end)
		end
	)
end
function GamepassController:Prompt(gamepassId: number): (boolean, string?)
	if gamepassId <= 0 then
		return false, "GAMEPASS_NOT_CONFIGURED"
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamepassId)
	return true, nil
end
function GamepassController:Destroy()
	if self.purchaseConnection then
		self.purchaseConnection:Disconnect()
		self.purchaseConnection = nil
	end
end
return GamepassController
