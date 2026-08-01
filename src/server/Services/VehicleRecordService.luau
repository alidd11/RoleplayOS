--!strict
local Players = game:GetService("Players")
local VehicleRecordService = {}
function VehicleRecordService:Init(context: any)
	self.context = context
end
function VehicleRecordService:Start() end
function VehicleRecordService:Search(query: string): { any }
	local results = {}
	for _, player in Players:GetPlayers() do
		local session = self.context.Services:Get("DataService"):GetSession(player)
		if session then
			for _, character in session.Profile.Characters do
				for _, vehicle in character.Vehicles do
					if string.find(string.lower(vehicle.Registration), query, 1, true) then
						table.insert(results, {
							VehicleId = vehicle.VehicleId,
							Registration = vehicle.Registration,
							DefinitionId = vehicle.DefinitionId,
							OwnerCharacterId = vehicle.OwnerCharacterId,
							Flags = {},
						})
					end
				end
			end
		end
	end
	return results
end
function VehicleRecordService:Destroy() end
return VehicleRecordService
