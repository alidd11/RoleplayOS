--!strict
local HttpService = game:GetService("HttpService")
-- `buying` marks a purchase that has been paid for and not yet finished.
--
-- Creating the vehicle reaches DataStore, which can wait on request budget for
-- longer than the network layer waits for the handler. The player is charged,
-- then told the request timed out, then presses buy again: without this the
-- second attempt is accepted and takes a second payment for a second car while
-- the first is still being made.
local DealershipService = { buying = {} }
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
	-- Balance, not Bank. A character's account is { Balance, Cash, Transactions },
	-- so reading Bank was always nil and the forecourt told every player they
	-- could afford nothing while the purchase itself would have gone through.
	local balance = character and character.Economy and character.Economy.Balance or 0
	local owned = {}
	for _, vehicle in self.context.Services:Get("VehicleOwnershipService"):List(player) do
		owned[vehicle.DefinitionId] = true
	end

	local rows = {}
	for _, definitionId in dealership.VehicleIds or {} do
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
	if not table.find(dealership.VehicleIds or {}, definitionId) then
		return nil, "VEHICLE_NOT_SOLD_HERE"
	end
	-- A service vehicle is issued from a depot, never sold. Buying one produced a
	-- paid for car that SpawnOwned then refused forever, with no refund, because
	-- it only refunds when creation itself fails.
	if definition.Category == "Service" then
		return nil, "VEHICLE_NOT_SOLD_HERE"
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	if not access.Allowed then
		return nil, access.ReasonCode
	end
	if self.buying[player.UserId] then
		return nil, "PURCHASE_IN_PROGRESS"
	end
	self.buying[player.UserId] = true
	local vehicle, creationError =
		self:_purchase(player, characterId, definitionId, colour, definition)
	self.buying[player.UserId] = nil
	return vehicle, creationError
end

function DealershipService:_purchase(
	player: Player,
	characterId: string,
	definitionId: string,
	colour: any,
	definition: any
): (any?, string?)
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
	-- A free vehicle is granted without a transaction. The economy rejects an
	-- amount of zero as not positive, which is right for a payment and wrong for
	-- a promotion: sending one would refuse the purchase with a code nobody could
	-- act on rather than handing over the car.
	if (definition.Price or 0) > 0 then
		local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, transaction)
		if not paid then
			return nil, reason
		end
	end
	local vehicle, creationError = self.context.Services
		:Get("VehicleOwnershipService")
		:Create(player, characterId, definitionId, colour, "CityGarage")
	if not vehicle then
		self.context.Logger:Error(
			"Paid vehicle creation failed",
			{ TransactionId = transaction.TransactionId, Error = creationError }
		)
		if (definition.Price or 0) > 0 then
			local refunded, refundError =
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
			if not refunded then
				-- The refund's answer was being discarded. A player who switched
				-- character or left during the creation attempt fails
				-- CHARACTER_NOT_ACTIVE here, and their money was simply gone with
				-- nothing written down: the error above reports the car, not the
				-- cash. This is the line that answers them.
				self.context.Logger:Error("Vehicle refund failed; the player is owed", {
					UserId = player.UserId,
					CharacterId = characterId,
					Amount = definition.Price,
					Vehicle = definitionId,
					TransactionId = transaction.TransactionId,
					Error = tostring(refundError),
				})
			end
		end
	end
	return vehicle, creationError
end
function DealershipService:Destroy() end
return DealershipService
