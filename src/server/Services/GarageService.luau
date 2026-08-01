--!strict
local GarageService = {}
function GarageService:Init(context: any)
	self.context = context
end
function GarageService:Start() end
function GarageService:List(
	player: Player,
	characterId: string,
	garageId: string
): ({ any }?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	local result = {}
	for _, vehicle in character.Vehicles do
		if vehicle.StoredGarageId == garageId then
			table.insert(result, {
				VehicleId = vehicle.VehicleId,
				DefinitionId = vehicle.DefinitionId,
				Registration = vehicle.Registration,
				Colour = vehicle.Colour,
				Condition = vehicle.Condition,
				Fuel = vehicle.Fuel,
			})
		end
	end
	return result, nil
end
function GarageService:Destroy() end
return GarageService
