--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Registration = require(ReplicatedStorage.RoleplayOS.Shared.RegistrationGenerator)
local VehicleOwnershipService = { registrations = {} }
function VehicleOwnershipService:Init(context: any)
	self.context = context
end
function VehicleOwnershipService:Start() end

function VehicleOwnershipService:_generate(): string
	local registration
	repeat
		registration = Registration.generate()
	until not self.registrations[registration]
	self.registrations[registration] = true
	return registration
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
	for _, player in game:GetService("Players"):GetPlayers() do
		local session = self.context.Services:Get("DataService"):GetSession(player)
		for _, character in if session then session.Profile.Characters else {} do
			for _, vehicle in character.Vehicles do
				if vehicle.Registration == registration then
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
		})
	end
	return result
end

function VehicleOwnershipService:GrantStarter(player: Player, characterId: string): (any?, string?)
	local settings = self.context.Configuration.VehicleSpawning
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
		return existing, nil
	end
	local registration = self:_generate()
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
	if RunService:IsStudio() then
		return normalised, nil
	end
	local ok, result = pcall(
		TextService.FilterStringAsync,
		TextService,
		normalised,
		player.UserId,
		Enum.TextFilterContext.PublicChat
	)
	if not ok then
		return nil, "TEXT_FILTER_UNAVAILABLE"
	end
	local filteredOk, filtered = pcall(result.GetNonChatStringForBroadcastAsync, result)
	if not filteredOk or filtered ~= normalised or string.find(filtered, "#", 1, true) then
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
	local vehicle = self:_find(player, vehicleId)
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
	local previousWasCustom = vehicle.CustomRegistration == true
	self.registrations[vehicle.Registration] = nil
	vehicle.Registration = registration
	vehicle.CustomRegistration = true
	self.registrations[registration] = true
	if previousWasCustom and previousRegistration ~= registration then
		self.context.Services
			:Get("DataService")
			:ReleaseCustomRegistration(previousRegistration, player.UserId, vehicle.VehicleId)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
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
	local registration = self:_generate()
	local vehicle = {
		VehicleId = HttpService:GenerateGUID(false),
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
	return vehicle, nil
end
function VehicleOwnershipService:Destroy()
	table.clear(self.registrations)
end
return VehicleOwnershipService
