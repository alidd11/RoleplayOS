--!strict
local HttpService = game:GetService("HttpService")
local PropertyService = { holdingsByProperty = {} }
function PropertyService:Init(context: any)
	self.context = context
end
function PropertyService:Start() end
function PropertyService:Acquire(
	player: Player,
	characterId: string,
	propertyId: string,
	holdingType: string
): (any?, string?)
	local definition = self.context.Configuration.Properties[propertyId]
	if not definition or (holdingType ~= "Owned" and holdingType ~= "Rented") then
		return nil, "INVALID_PROPERTY_REQUEST"
	end
	if self.holdingsByProperty[propertyId] then
		return nil, "PROPERTY_UNAVAILABLE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	local price = holdingType == "Owned" and definition.PurchasePrice or definition.RentPrice
	if not price then
		return nil, "HOLDING_TYPE_UNAVAILABLE"
	end
	local transaction = {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Amount = price,
		Direction = "Debit",
		ReasonCode = holdingType == "Owned" and "PROPERTY_PURCHASE" or "PROPERTY_RENT",
		Description = holdingType .. " property: " .. definition.Name,
		RelatedEntityId = propertyId,
		Metadata = {},
	}
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, transaction)
	if not paid then
		return nil, reason
	end
	local holding = {
		PropertyId = propertyId,
		CharacterId = characterId,
		HoldingType = holdingType,
		StartedAt = os.time(),
		RentDueAt = holdingType == "Rented" and os.time() + 604800 or nil,
		AccessCharacterIds = {},
	}
	self.holdingsByProperty[propertyId] = holding
	table.insert(character.Properties, holding)
	self.context.Services:Get("DataService"):MarkDirty(player)
	return holding, nil
end
function PropertyService:Destroy()
	table.clear(self.holdingsByProperty)
end
return PropertyService
