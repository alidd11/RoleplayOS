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
		local definition = self.context.Configuration.Vehicles[vehicle.DefinitionId]
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

function VehicleOwnershipService:GrantStarter(player: Player, characterId: string): (any?, string?)
	local settings = self.context.Configuration.VehicleData
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

function VehicleOwnershipService:GetOrCreateTeamRegistration(
	player: Player,
	teamName: string,
	definitionId: string
): (string?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or not self.context.Configuration.Vehicles[definitionId] then
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
	local definition = self.context.Configuration.Vehicles[definitionId]
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
