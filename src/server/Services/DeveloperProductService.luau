--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- The sole owner of ProcessReceipt. Consumable grants are recorded in the
-- mode-scoped profile before Roblox is told the purchase was delivered.
local DeveloperProductService = { Critical = true }

function DeveloperProductService:Init(context: any)
	self.context = context
	self.products = {}
	for _, definition in context.Configuration.Custody.PublicEarlyRelease.Products do
		if type(definition.ProductId) == "number" and definition.ProductId > 0 then
			self.products[definition.ProductId] = definition
		end
	end
end

function DeveloperProductService:_process(receipt: any): Enum.ProductPurchaseDecision
	local definition = self.products[receipt.ProductId]
	if not definition then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Public and whitelisted profiles are deliberately separate. A receipt that
	-- arrives in another mode waits until the purchaser joins a public server.
	if self.context.Services:Get("ServerModeService"):Kind() ~= "Public" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local dataService = self.context.Services:Get("DataService")
	local session = player and dataService:GetSession(player)
	if not player or not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(receipt.PurchaseId)
	local consumables = session.Profile.Consumables
	local processed = consumables.ProcessedDeveloperReceipts
	if processed[receiptId] == nil then
		local previousCredits =
			math.max(0, math.floor(tonumber(consumables.EarlyReleaseCredits) or 0))
		consumables.EarlyReleaseCredits = previousCredits + definition.Credits
		processed[receiptId] = {
			ProductId = receipt.ProductId,
			Credits = definition.Credits,
			GrantedAt = os.time(),
		}
		dataService:MarkDirty(player)
		local saved, reason = dataService:Save(player)
		if not saved then
			consumables.EarlyReleaseCredits = previousCredits
			processed[receiptId] = nil
			dataService:MarkDirty(player)
			self.context.Logger:Error("Developer product grant could not be persisted", {
				PlayerId = receipt.PlayerId,
				PurchaseId = receiptId,
				Reason = reason,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "DeveloperProduct.EarlyReleaseCreditsGranted",
			Target = tostring(player.UserId),
			Metadata = { ProductId = receipt.ProductId, Credits = definition.Credits },
		})
	end

	-- A purchase made while sentenced is immediately useful. If spawning fails,
	-- the durable credit remains available for a later manual retry.
	local custodyService = self.context.Services:Get("CustodyService")
	if custodyService:HasActiveSentence(player) then
		local released = custodyService:UseEarlyReleaseCredit(player, receiptId)
		if released then
			dataService:Save(player)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function DeveloperProductService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, result = pcall(function()
			return self:_process(receipt)
		end)
		if not ok then
			self.context.Logger:Error("Developer product receipt failed", {
				ProductId = receipt.ProductId,
				PlayerId = receipt.PlayerId,
				Error = tostring(result),
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end
end

function DeveloperProductService:Destroy() end

return DeveloperProductService
