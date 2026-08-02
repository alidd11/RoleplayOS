--!strict
local HttpService = game:GetService("HttpService")
local DealershipService = {}
function DealershipService:Init(context: any)
	self.context = context
end
function DealershipService:Start() end
function DealershipService:Purchase(
	player: Player,
	terminalId: string,
	characterId: string,
	dealershipId: string,
	definitionId: string,
	colour: string
): (any?, string?)
	local terminal, terminalReason =
		self.context.Services:Get("VehicleService"):AuthoriseDealershipTerminal(player, terminalId)
	if not terminal then
		return nil, terminalReason
	end
	if terminal.DealershipId ~= dealershipId then
		return nil, "DEALERSHIP_TERMINAL_MISMATCH"
	end
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
		self.context.Services:Get("EconomyService"):Apply(player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = characterId,
			Amount = definition.Price,
			Direction = "Credit",
			ReasonCode = "VEHICLE_PURCHASE_REFUND",
			Description = "Automatic refund: " .. definition.Name,
			RelatedEntityId = transaction.TransactionId,
			Metadata = {},
		})
	end
	return vehicle, creationError
end
function DealershipService:Destroy() end
return DealershipService
