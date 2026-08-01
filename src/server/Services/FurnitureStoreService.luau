--!strict
local HttpService = game:GetService("HttpService")
local FurnitureStoreService = {}
function FurnitureStoreService:Init(context: any)
	self.context = context
end
function FurnitureStoreService:Start() end
function FurnitureStoreService:Purchase(
	player: Player,
	characterId: string,
	storeId: string,
	definitionId: string
): (any?, string?)
	local store = self.context.Configuration.FurnitureStores[storeId]
	local definition = self.context.Configuration.Furniture[definitionId]
	if not store or not definition or not table.find(store.FurnitureIds, definitionId) then
		return nil, "ITEM_NOT_SOLD_HERE"
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	if not access.Allowed then
		return nil, access.ReasonCode
	end
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Amount = definition.Price,
		Direction = "Debit",
		ReasonCode = "FURNITURE_PURCHASE",
		Description = "Furniture purchase: " .. definition.Name,
		RelatedEntityId = definitionId,
		Metadata = {},
	})
	if not paid then
		return nil, reason
	end
	return self.context.Services:Get("FurnitureService"):AddOwned(player, characterId, definitionId)
end
function FurnitureStoreService:Destroy() end
return FurnitureStoreService
