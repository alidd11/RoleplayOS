--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local GamepassController = {}
function GamepassController:Init(_context: any) end
function GamepassController:Start() end
function GamepassController:Prompt(gamepassId: number): (boolean, string?)
	if gamepassId <= 0 then
		return false, "GAMEPASS_NOT_CONFIGURED"
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamepassId)
	return true, nil
end
function GamepassController:Destroy() end
return GamepassController
