--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registration = require(ReplicatedStorage.RoleplayOS.Shared.RegistrationGenerator)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)
local VehicleOwnershipService = {
	registrations = {},
	registrationUpdates = {},
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function VehicleOwnershipService:Init(context: any)
	self.context = context
end

function VehicleOwnershipService:Start()
	self.running = true
end

function VehicleOwnershipService:_vehicleDefinition(definitionId: string): any?
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinition then
		return validator:GetVehicleDefinition(definitionId)
	end
	return self.context.Configuration.Vehicles[definitionId]
end

function VehicleOwnershipService:_allocate(player: Player, vehicleId: string): (string?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
	for _ = 1, 12 do
		if not self.running or not playerIsCurrent(player) then
			return nil, "PLAYER_UNAVAILABLE"
		end
		local registration = Registration.generate()
		if not self.registrations[registration] then
			local reserved, reason = self.context.Services
				:Get("DataService")
				:ReserveCustomRegistration(registration, player.UserId, vehicleId)
			if reserved then
				if not self.running or not playerIsCurrent(player) then
					self.context.Services
						:Get("DataService")
						:ReleaseCustomRegistration(registration, player.UserId, vehicleId)
					return nil, "PLAYER_UNAVAILABLE"
				end
				self.registrations[registration] = true
				return registration, nil
			elseif not self.running or not playerIsCurrent(player) then
				return nil, "PLAYER_UNAVAILABLE"
			elseif reason ~= "REGISTRATION_ALREADY_USED" then
				return nil, reason
			end
		end
	end
	return nil, "REGISTRATION_ALLOCATION_FAILED"
end

function VehicleOwnershipService:_releaseRegistration(
	player: Player,
	registration: string,
	vehicleId: string
)
	self.registrations[registration] = nil
	self.context.Services
		:Get("DataService")
		:ReleaseCustomRegistration(registration, player.UserId, vehicleId)
end

function VehicleOwnershipService:_recordVehicle(
	player: Player,
	character: any,
	characterId: string,
	definitionId: string,
	colour: string,
	garageId: string,
	vehicleId: string,
	registration: string
): any
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
	local indexed, indexError = pcall(function()
		self.context.Services
			:Get("RecordIndexService")
			:ScheduleVehicle(player, character, vehicle, nil)
	end)
	if not indexed then
		self.context.Logger:Warning("Vehicle MDT indexing could not be scheduled", {
			VehicleId = vehicleId,
			Error = tostring(indexError),
		})
	end
	return vehicle
end

function VehicleOwnershipService:_find(player: Player, vehicleId: string): (any?, any?)
	if not self.running or not playerIsCurrent(player) then
		return nil, nil
	end
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
	if not self.running or not playerIsCurrent(player) then
		return {}
	end
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
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
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
	local currentSession = self.context.Services:Get("DataService"):GetSession(player)
	local currentCharacter = currentSession and currentSession.Profile.Characters[characterId]
	if
		not self.running
		or not playerIsCurrent(player)
		or currentSession ~= session
		or currentCharacter ~= character
	then
		return nil, "PLAYER_UNAVAILABLE"
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
-- Reserve the registration before charging. Registration allocation is the
-- persistent step most likely to fail during an outage; once it succeeds, the
-- active character is revalidated, payment is taken, and the ownership record
-- is inserted without another yielding allocation step.
function VehicleOwnershipService:Purchase(
	player: Player,
	definitionId: string,
	colour: string
): (any?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local definition = self:_vehicleDefinition(definitionId)
	if not definition or definition.Category ~= "Civilian" then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	if definition.Fleet == true then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	if type(definition.Colours) ~= "table" or not table.find(definition.Colours, colour) then
		return nil, "INVALID_VEHICLE_SELECTION"
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
	if not access.Allowed then
		return nil, access.ReasonCode
	end
	local price = definition.Price
	if type(price) ~= "number" or price < 0 then
		return nil, "VEHICLE_NOT_FOR_SALE"
	end
	if character.Economy.Balance < price then
		return nil, "INSUFFICIENT_FUNDS"
	end

	-- Registration allocation is the only expected fallible persistent step in
	-- creating an owned vehicle. Reserve it before taking money, so an outage
	-- cannot debit the player and then discover that the vehicle cannot exist.
	local vehicleId = HttpService:GenerateGUID(false)
	local registration, registrationReason = self:_allocate(player, vehicleId)
	if not registration then
		return nil, registrationReason
	end

	-- Allocation yielded through DataStore work. Re-check the active character
	-- before charging so a character switch or disconnect cannot pay from stale
	-- state and attach the vehicle to a character that is no longer active.
	session = data:GetSession(player)
	if
		not self.running
		or not playerIsCurrent(player)
		or not session
		or session.ActiveCharacterId ~= characterId
	then
		self:_releaseRegistration(player, registration, vehicleId)
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	character = session.Profile.Characters[characterId]
	if not character then
		self:_releaseRegistration(player, registration, vehicleId)
		return nil, "CHARACTER_NOT_ACTIVE"
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
		self:_releaseRegistration(player, registration, vehicleId)
		return nil, reason
	end

	local garageId = definition.GarageId or self.context.Configuration.VehicleData.StarterGarageId
	local vehicle = self:_recordVehicle(
		player,
		character,
		characterId,
		definitionId,
		colour,
		garageId,
		vehicleId,
		registration
	)
	return vehicle, nil
end

function VehicleOwnershipService:GetOrCreateTeamRegistration(
	player: Player,
	teamName: string,
	definitionId: string
): (string?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	if not session or not self:_vehicleDefinition(definitionId) then
		return nil, "INVALID_TEAM_VEHICLE"
	end
	local key = teamName .. ":" .. definitionId
	local existing = session.Profile.TeamVehicleRegistrations[key]
	if type(existing) == "string" then
		local marker = "team:" .. tostring(player.UserId) .. ":" .. key
		local reserved, reason = data:ReserveCustomRegistration(existing, player.UserId, marker)
		if not self.running or not playerIsCurrent(player) then
			return nil, "PLAYER_UNAVAILABLE"
		end
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
	local currentSession = data:GetSession(player)
	if not self.running or not playerIsCurrent(player) or currentSession ~= session then
		self:_releaseRegistration(player, registration, marker)
		return nil, "PLAYER_UNAVAILABLE"
	end
	local current = session.Profile.TeamVehicleRegistrations[key]
	if type(current) == "string" then
		self:_releaseRegistration(player, registration, marker)
		return current, nil
	end
	session.Profile.TeamVehicleRegistrations[key] = registration
	data:MarkDirty(player)
	return registration, nil
end

function VehicleOwnershipService:_moderate(player: Player, proposed: string): (string?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
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
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
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
	proposed: string,
	spawnerId: string?
): (any?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
	if not spawnerId or spawnerId == "" or #spawnerId > 64 then
		return nil, "CIVILIAN_FACILITY_REQUIRED"
	end
	if self.registrationUpdates[vehicleId] then
		return nil, "REGISTRATION_UPDATE_IN_PROGRESS"
	end
	self.registrationUpdates[vehicleId] = true
	local ok, result, resultReason = pcall(function(): (any?, string?)
		local pass = self.context.Configuration.Gamepasses.CustomRegistration
		local owned, ownershipReason =
			self.context.Services:Get("GamepassService"):Refresh(player, pass)
		if not self.running or not playerIsCurrent(player) then
			return nil, "PLAYER_UNAVAILABLE"
		end
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
		vehicle, character = self:_find(player, vehicleId)
		if not vehicle then
			return nil, "VEHICLE_NOT_OWNED"
		end
		local previousRegistration = vehicle.Registration
		local existing = self:GetByRegistration(registration)
		if existing and existing.VehicleId ~= vehicle.VehicleId then
			return nil, "REGISTRATION_ALREADY_USED"
		end
		local data = self.context.Services:Get("DataService")
		local reserved, reserveReason =
			data:ReserveCustomRegistration(registration, player.UserId, vehicle.VehicleId)
		if not reserved then
			return nil, reserveReason
		end

		-- The network endpoint checks the civilian facility before entering this
		-- method, but the gamepass lookup, text filter and registration reservation
		-- above can all yield. Revalidate proximity and facility authority after
		-- those waits and immediately before the live ownership record is changed.
		local authorised, facilityReason = self.context.Services
			:Get("VehicleSpawnerService")
			:AuthoriseCivilianFacility(player, spawnerId)
		if not authorised then
			if registration ~= previousRegistration then
				self:_releaseRegistration(player, registration, vehicleId)
			end
			return nil, facilityReason
		end

		local currentVehicle, currentCharacter = self:_find(player, vehicleId)
		if not currentVehicle then
			if registration ~= previousRegistration then
				self:_releaseRegistration(player, registration, vehicleId)
			end
			return nil, "PLAYER_UNAVAILABLE"
		end
		if currentVehicle.Registration ~= previousRegistration then
			if currentVehicle.Registration == registration then
				return {
					VehicleId = currentVehicle.VehicleId,
					Registration = currentVehicle.Registration,
				},
					nil
			end
			if registration ~= previousRegistration then
				self:_releaseRegistration(player, registration, vehicleId)
			end
			return nil, "REGISTRATION_UPDATE_CONFLICT"
		end
		vehicle = currentVehicle
		character = currentCharacter

		self.registrations[vehicle.Registration] = nil
		vehicle.Registration = registration
		vehicle.CustomRegistration = true
		self.registrations[registration] = true
		if previousRegistration ~= registration then
			data:ReleaseCustomRegistration(previousRegistration, player.UserId, vehicle.VehicleId)
		end
		data:MarkDirty(player)
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
	end)
	self.registrationUpdates[vehicleId] = nil
	if not ok then
		error(result)
	end
	return result, resultReason
end

function VehicleOwnershipService:Create(
	player: Player,
	characterId: string,
	definitionId: string,
	colour: string,
	garageId: string
): (any?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PLAYER_UNAVAILABLE"
	end
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
	local currentSession = self.context.Services:Get("DataService"):GetSession(player)
	local currentCharacter = currentSession and currentSession.Profile.Characters[characterId]
	if
		not self.running
		or not playerIsCurrent(player)
		or currentSession ~= session
		or currentCharacter ~= character
	then
		self:_releaseRegistration(player, registration, vehicleId)
		return nil, "PLAYER_UNAVAILABLE"
	end
	return self:_recordVehicle(
		player,
		character,
		characterId,
		definitionId,
		colour,
		garageId,
		vehicleId,
		registration
	),
		nil
end
function VehicleOwnershipService:Destroy()
	self.running = false
	table.clear(self.registrationUpdates)
	table.clear(self.registrations)
end
return VehicleOwnershipService
