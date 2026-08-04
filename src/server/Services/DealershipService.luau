--!strict
local HttpService = game:GetService("HttpService")
local DealershipService = {}
function DealershipService:Init(context: any)
	self.context = context
end
function DealershipService:Start() end

-- What this dealership has for sale, as the player standing at it sees it.
--
-- Resolved on the server so the forecourt cannot be made to advertise a price or
-- an unlock the purchase would then refuse. A locked vehicle is still listed
-- where the access rule says to display it, because a showroom that hides what
-- you cannot yet afford gives a player no reason to earn anything.
function DealershipService:Catalogue(player: Player, terminalId: string): (any?, string?)
	local terminal, terminalReason =
		self.context.Services:Get("VehicleService"):AuthoriseDealershipTerminal(player, terminalId)
	if not terminal then
		return nil, terminalReason
	end
	local dealership = self.context.Configuration.Dealerships[terminal.DealershipId]
	if not dealership then
		return nil, "DEALERSHIP_NOT_FOUND"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	local balance = character and character.Economy and character.Economy.Bank or 0
	local owned = {}
	for _, vehicle in self.context.Services:Get("VehicleOwnershipService"):List(player) do
		owned[vehicle.DefinitionId] = true
	end

	-- What this forecourt sells: everything under the folders it covers, plus
	-- anything named outright. Built as a set so a car matching both appears once.
	local catalogue = self.context.Services:Get("VehicleCatalogueService")
	local selling = {}
	for _, definitionId in dealership.VehicleIds or {} do
		selling[definitionId] = true
	end
	for definitionId, definition in self.context.Configuration.Vehicles do
		for _, prefix in dealership.IncludePaths or {} do
			if catalogue:MatchesPath(definition, prefix) then
				selling[definitionId] = true
				break
			end
		end
	end

	local rows = {}
	for definitionId in selling do
		local definition = self.context.Configuration.Vehicles[definitionId]
		if not definition then
			continue
		end
		local access =
			self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
		if not access.Allowed and definition.Access and not definition.Access.DisplayWhenLocked then
			continue
		end
		-- A gamepass named on the access rule is offered for purchase rather than
		-- being a dead end, in the same way the vendors do it.
		local gamepassId = if not access.Allowed and definition.Access
			then definition.Access.GamepassId
			else nil
		table.insert(rows, {
			DefinitionId = definitionId,
			Name = definition.Name,
			Price = definition.Price,
			Colours = definition.Colours,
			Category = definition.Category,
			Locked = not access.Allowed,
			LockedReason = if access.Allowed then nil else access.ReasonCode,
			GamepassId = gamepassId,
			Owned = owned[definitionId] == true,
			Affordable = (definition.Price or 0) <= balance,
		})
	end
	return {
		DealershipId = terminal.DealershipId,
		Name = dealership.Name,
		TerminalId = terminalId,
		CharacterId = characterId,
		Balance = balance,
		Vehicles = rows,
	},
		nil
end
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
	if not dealership or not definition then
		return nil, "VEHICLE_NOT_SOLD_HERE"
	end
	-- Sold here if named outright or if its folder is one this forecourt covers.
	-- The showroom is built from the same rule, so anything visible is buyable.
	local sold = table.find(dealership.VehicleIds or {}, definitionId) ~= nil
	if not sold then
		local catalogue = self.context.Services:Get("VehicleCatalogueService")
		for _, prefix in dealership.IncludePaths or {} do
			if catalogue:MatchesPath(definition, prefix) then
				sold = true
				break
			end
		end
	end
	if not sold then
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
