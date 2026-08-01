--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registration = require(ReplicatedStorage.RoleplayOS.Shared.RegistrationGenerator)
local VehicleOwnershipService = { registrations = {} }
function VehicleOwnershipService:Init(context: any)
	self.context = context
end
function VehicleOwnershipService:Start() end
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
	local registration
	repeat
		registration = Registration.generate()
	until not self.registrations[registration]
	self.registrations[registration] = true
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
