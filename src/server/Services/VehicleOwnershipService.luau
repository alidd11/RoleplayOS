--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registration = require(ReplicatedStorage.RoleplayOS.Shared.RegistrationGenerator)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)
local VehicleOwnershipService = { registrations = {} }
function VehicleOwnershipService:Init(context: any)
	self.context = context
end
function VehicleOwnershipService:Start() end

function VehicleOwnershipService:_vehicleDefinition(definitionId: string): any?
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinition then
		return validator:GetVehicleDefinition(definitionId)
	end
	return self.context.Configuration.Vehicles[definitionId]
end

function VehicleOwnershipService:_allocate(player: Player, vehicleId: string): (string?, string?)
	for _ = 1, 12 do
		local registration = Registration.generate()
		if not self.registrations[registration] then
			local reserved, reason = self.context.Services
				:Get("DataService")
				:ReserveCustomRegistration(registration, player.UserId, vehicleId)
			if reserved then
				self.registrations[registration] = true
				return registration, nil
			elseif reason ~= "REGISTRATION_ALREADY_USED" then
				return nil, reason
			end
		end
	end
	return nil, "REGISTRATION_ALLOCATION_FAILED"
end

function VehicleOwnershipService:_find(player: Player, vehicleId: string): (any?, any?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	for _, character in if session then session.Profile.Characters else {} do
		for _, vehicle in character.Vehicles do
			if vehicle.VehicleId == vehicleId then
				return vehicle, character
			end
		end
	end
	return nil, nil
end

function VehicleOwnershipService:GetByRegistration(registration: string): (any?, Player?)
	registration = string.upper(registration)
	for _, player in game:GetService("Players"):GetPlayers() do
		local session = self.context.Services:Get("DataService"):GetSession(player)
		for _, character in if session then session.Profile.Characters else {} do
			for _, vehicle in character.Vehicles do
				if string.upper(vehicle.Registration) == registration then
					return vehicle, player
				end
			end
		end
	end
	return nil, nil
end

function VehicleOwnershipService:List(player: Player): { any }
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	local result = {}
	for _, vehicle in if character then character.Vehicles else {} do
		local definition = self:_vehicleDefinition(vehicle.DefinitionId)
		table.insert(result, {
			VehicleId = vehicle.VehicleId,
			DefinitionId = vehicle.DefinitionId,
			Name = if definition then definition.Name else vehicle.DefinitionId,
			Registration = vehicle.Registration,
			Colour = vehicle.Colour,
			Category = "Civilian",
			CustomRegistration = vehicle.CustomRegistration == true,
			Mileage = vehicle.Mileage,
			Fuel = vehicle.Fuel,
			Condition = vehicle.Condition,
			Insured = vehicle.Insured,
			Taxed = vehicle.Taxed,
		})
	end
	return result
end

-- Writes a running vehicle's fuel and odometer back onto the owner's profile.
--
-- Both fields already existed in the persisted record and in List, and nothing
-- ever set either of them: a car came back from the garage with the fuel it was
-- created with, however far it had been driven. Called from the spawner's burn
-- loop rather than on every tick of it, so the profile is only marked dirty when
-- a figure actually moved.
--
-- Silent where the vehicle is not owned by anybody, which is the normal case for
-- a service vehicle: those are issued rather than owned, so there is no record to
-- update and no fault in that.
function VehicleOwnershipService:RecordTelemetry(
	player: Player,
	vehicleId: string,
	fuel: number?,
	mileage: number?
): boolean
	local vehicle = self:_find(player, vehicleId)
	if not vehicle then
		return false
	end
	local changed = false
	if type(fuel) == "number" and vehicle.Fuel ~= fuel then
		vehicle.Fuel = math.clamp(fuel, 0, 100)
		changed = true
	end
	if type(mileage) == "number" and vehicle.Mileage ~= mileage then
		-- Never decreases. An odometer that can be wound back is a data fault, and
		-- a bad reading from a physics glitch should not permanently reduce it.
		vehicle.Mileage = math.max(vehicle.Mileage or 0, mileage)
		changed = true
	end
	if changed then
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
	return changed
end

function VehicleOwnershipService:GrantStarter(player: Player, characterId: string): (any?, string?)
	local settings = self.context.Configuration.VehicleData
	-- No starter car configured is a deliberate state, not a failure. The car this
	-- named was retired and nothing replaces it yet, so Create was being handed a
	-- nil definition and returning INVALID_VEHICLE_SELECTION. That warned on every
	-- character creation and left a pending flag which then retried, and warned
	-- again, on every selection - for work that was never outstanding.
	local starterId = settings.StarterDefinitionId
	if type(starterId) ~= "string" or starterId == "" then
		return nil, "NO_STARTER_CONFIGURED"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	if character.StarterVehicleGranted == true then
		for _, vehicle in character.Vehicles do
			if vehicle.DefinitionId == settings.StarterDefinitionId then
				return vehicle, nil
			end
		end
		return nil, "STARTER_ALREADY_GRANTED"
	end
	for _, vehicle in character.Vehicles do
		if vehicle.DefinitionId == settings.StarterDefinitionId then
			character.StarterVehicleGranted = true
			self.context.Services:Get("DataService"):MarkDirty(player)
			return vehicle, nil
		end
	end
	local vehicle, reason = self:Create(
		player,
		characterId,
		settings.StarterDefinitionId,
		settings.StarterColour,
		settings.StarterGarageId
	)
	if not vehicle then
		return nil, reason
	end
	character.StarterVehicleGranted = true
	self.context.Services:Get("DataService"):MarkDirty(player)
	return vehicle, nil
end

-- Buys a vehicle from a forecourt.
--
-- Everything that makes a vehicle real - allocating a registration, writing the
-- record, indexing it for the MDT - already lived in Create. What was missing
-- was the half that takes the money, so the catalogue had prices, the
-- dealership had a list of what it sells, and there was no way to buy any of
-- it: the only car anybody could own was the free starter grant.
--
-- Charged before the record is created and not after. Create allocates a
-- registration and touches the search index, and undoing that on a failed
-- payment is harder than simply not doing it.
function VehicleOwnershipService:Purchase(
	player: Player,
	definitionId: string,
	colour: string
): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local definition = self:_vehicleDefinition(definitionId)
	if not definition or definition.Category ~= "Civilian" then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	-- A fleet vehicle is issued by a job rather than owned, and the taxi is the
	-- one already on the forecourt list, so this is not hypothetical.
	if definition.Fleet == true then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	if type(definition.Colours) ~= "table" or not table.find(definition.Colours, colour) then
		return nil, "INVALID_VEHICLE_SELECTION"
	end
	-- Gamepass vehicles are still bought with cash; the pass is what admits them
	-- to the forecourt at all. Re-evaluated here rather than trusted from the
	-- menu, which is a client's view of the world.
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	if not access.Allowed then
		return nil, access.ReasonCode
	end
	local price = definition.Price
	if type(price) ~= "number" or price < 0 then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Amount = price,
		Direction = "Debit",
		ReasonCode = "VEHICLE_PURCHASE",
		Description = "Vehicle purchase: " .. tostring(definition.Name or definitionId),
		RelatedEntityId = definitionId,
		Metadata = { Colour = colour },
	})
	if not paid then
		return nil, reason
	end
	local garageId = definition.GarageId or self.context.Configuration.VehicleData.StarterGarageId
	local vehicle, createReason = self:Create(player, characterId, definitionId, colour, garageId)
	if vehicle then
		return vehicle, nil
	end
	local refunded, refundReason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Amount = price,
		Direction = "Credit",
		ReasonCode = "VEHICLE_PURCHASE_REFUND",
		Description = "Refund for an undelivered vehicle purchase",
		RelatedEntityId = definitionId,
		Metadata = { PurchaseFailure = createReason },
	})
	if not refunded then
		self.context.Logger:Error("Vehicle purchase refund failed", {
			UserId = player.UserId,
			CharacterId = characterId,
			DefinitionId = definitionId,
			Amount = price,
			PurchaseFailure = createReason,
			RefundFailure = refundReason,
		})
		return nil, "VEHICLE_PURCHASE_REFUND_FAILED"
	end
	return nil, createReason or "VEHICLE_CREATION_FAILED"
end

function VehicleOwnershipService:GetOrCreateTeamRegistration(
	player: Player,
	teamName: string,
	definitionId: string
): (string?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or not self:_vehicleDefinition(definitionId) then
		return nil, "INVALID_TEAM_VEHICLE"
	end
	local key = teamName .. ":" .. definitionId
	local existing = session.Profile.TeamVehicleRegistrations[key]
	if type(existing) == "string" then
		local marker = "team:" .. tostring(player.UserId) .. ":" .. key
		local reserved, reason = self.context.Services
			:Get("DataService")
			:ReserveCustomRegistration(existing, player.UserId, marker)
		if not reserved then
			return nil, reason
		end
		return existing, nil
	end
	local marker = "team:" .. tostring(player.UserId) .. ":" .. key
	local registration, reason = self:_allocate(player, marker)
	if not registration then
		return nil, reason
	end
	session.Profile.TeamVehicleRegistrations[key] = registration
	self.context.Services:Get("DataService"):MarkDirty(player)
	return registration, nil
end

function VehicleOwnershipService:_moderate(player: Player, proposed: string): (string?, string?)
	local settings = self.context.Configuration.VehicleIdentity
	local normalised = string.upper(proposed):gsub("[^A-Z0-9 ]", ""):gsub("%s+", " ")
	normalised = string.match(normalised, "^%s*(.-)%s*$") or ""
	if
		#normalised < settings.MinimumRegistrationLength
		or #normalised > settings.MaximumRegistrationLength
	then
		return nil, "INVALID_REGISTRATION_LENGTH"
	end
	local filtered, reason =
		TextFilter.forBroadcast(normalised, player.UserId, Enum.TextFilterContext.PublicChat)
	if not filtered then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	-- Any rewrite or hash means the plate was moderated, so reject rather than
	-- silently registering a censored variant.
	if filtered ~= normalised or string.find(filtered, "#", 1, true) then
		return nil, "REGISTRATION_NOT_PERMITTED"
	end
	return normalised, nil
end

function VehicleOwnershipService:SetCustomRegistration(
	player: Player,
	vehicleId: string,
	proposed: string
): (any?, string?)
	local pass = self.context.Configuration.Gamepasses.CustomRegistration
	local owned, ownershipReason =
		self.context.Services:Get("GamepassService"):Refresh(player, pass)
	if not owned then
		return nil, ownershipReason or "GAMEPASS_REQUIRED"
	end
	local vehicle, character = self:_find(player, vehicleId)
	if not vehicle then
		return nil, "VEHICLE_NOT_OWNED"
	end
	local registration, reason = self:_moderate(player, proposed)
	if not registration then
		return nil, reason
	end
	local existing = self:GetByRegistration(registration)
	if existing and existing.VehicleId ~= vehicle.VehicleId then
		return nil, "REGISTRATION_ALREADY_USED"
	end
	local reserved, reserveReason = self.context.Services
		:Get("DataService")
		:ReserveCustomRegistration(registration, player.UserId, vehicle.VehicleId)
	if not reserved then
		return nil, reserveReason
	end
	local previousRegistration = vehicle.Registration
	self.registrations[vehicle.Registration] = nil
	vehicle.Registration = registration
	vehicle.CustomRegistration = true
	self.registrations[registration] = true
	if previousRegistration ~= registration then
		self.context.Services
			:Get("DataService")
			:ReleaseCustomRegistration(previousRegistration, player.UserId, vehicle.VehicleId)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services
		:Get("VehiclePlateService")
		:RefreshOwned(player.UserId, vehicle.VehicleId, registration)
	self.context.Services
		:Get("RecordIndexService")
		:ScheduleVehicle(player, character, vehicle, previousRegistration)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Vehicle.CustomRegistrationSet",
		Target = vehicle.VehicleId,
		Metadata = { Registration = registration },
	})
	return { VehicleId = vehicle.VehicleId, Registration = registration }, nil
end
function VehicleOwnershipService:Create(
	player: Player,
	characterId: string,
	definitionId: string,
	colour: string,
	garageId: string
): (any?, string?)
	local definition = self:_vehicleDefinition(definitionId)
	if not definition or not table.find(definition.Colours, colour) then
		return nil, "INVALID_VEHICLE_SELECTION"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	local vehicleId = HttpService:GenerateGUID(false)
	local registration, registrationReason = self:_allocate(player, vehicleId)
	if not registration then
		return nil, registrationReason
	end
	local vehicle = {
		VehicleId = vehicleId,
		OwnerCharacterId = characterId,
		DefinitionId = definitionId,
		Registration = registration,
		Colour = colour,
		Mileage = 0,
		Fuel = 100,
		Condition = 100,
		Insured = false,
		Taxed = false,
		StoredGarageId = garageId,
	}
	table.insert(character.Vehicles, vehicle)
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("RecordIndexService"):ScheduleVehicle(player, character, vehicle, nil)
	return vehicle, nil
end
function VehicleOwnershipService:Destroy()
	table.clear(self.registrations)
end
return VehicleOwnershipService
