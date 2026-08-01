--!strict
local HttpService = game:GetService("HttpService")
local DealershipService = {}
function DealershipService:Init(context: any)
	self.context = context
end
function DealershipService:Start() end
function DealershipService:Purchase(
	player: Player,
	characterId: string,
	dealershipId: string,
	definitionId: string,
	colour: string
): (any?, string?)
	local dealership = self.context.Configuration.Dealerships[dealershipId]
	local definition = self.context.Configuration.Vehicles[definitionId]
	if not dealership or not definition or not table.find(dealership.VehicleIds, definitionId) then
		return nil, "VEHICLE_NOT_SOLD_HERE"
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	if not access.Allowed then
		return nil, access.ReasonCode
	end
	local transaction = {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Amount = definition.Price,
		Direction = "Debit",
		ReasonCode = "VEHICLE_PURCHASE",
		Description = "Vehicle purchase: " .. definition.Name,
		RelatedEntityId = definitionId,
		Metadata = {},
	}
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, transaction)
	if not paid then
		return nil, reason
	end
	local vehicle, creationError = self.context.Services
		:Get("VehicleOwnershipService")
		:Create(player, characterId, definitionId, colour, "CityGarage")
	if not vehicle then
		self.context.Logger:Error(
			"Paid vehicle creation failed",
			{ TransactionId = transaction.TransactionId, Error = creationError }
		)
	end
	return vehicle, creationError
end
function DealershipService:Destroy() end
return DealershipService
