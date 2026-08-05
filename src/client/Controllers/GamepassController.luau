--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GamepassController = {}
function GamepassController:Init(context: any)
	self.context = context
	self.purchaseConnection = nil
	self.ownershipConnection = nil
	self.refreshGeneration = 0
end
function GamepassController:_scheduleRefresh()
	self.refreshGeneration += 1
	local generation = self.refreshGeneration
	task.delay(1.25, function()
		if generation ~= self.refreshGeneration then
			return
		end
		self.context.Controllers.StartMenuController:Refresh()
	end)
end
function GamepassController:Start()
	local changed =
		self.context.Controllers.NetworkController:ResolveEvent("GamepassOwnershipChanged")
	if changed then
		self.ownershipConnection = changed.OnClientEvent:Connect(function()
			self:_scheduleRefresh()
		end)
	end
	self.purchaseConnection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, _gamepassId, purchased)
			if player ~= Players.LocalPlayer or not purchased then
				return
			end
			-- The ownership event normally schedules this first. Keep the purchase
			-- signal as a fallback when Roblox's ownership lookup is delayed.
			self:_scheduleRefresh()
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
	if self.ownershipConnection then
		self.ownershipConnection:Disconnect()
		self.ownershipConnection = nil
	end
end
return GamepassController
