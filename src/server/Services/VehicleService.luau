--!strict
local ServerStorage = game:GetService("ServerStorage")
local VehicleService = { active = {} }
function VehicleService:Init(context: any)
	self.context = context
end
function VehicleService:Start() end
function VehicleService:Spawn(
	player: Player,
	vehicleId: string,
	spawnPart: BasePart
): (Model?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local owned
	for _, vehicle in character.Vehicles do
		if vehicle.VehicleId == vehicleId then
			owned = vehicle
		end
	end
	if not owned or self.active[vehicleId] then
		return nil, "VEHICLE_NOT_AVAILABLE"
	end
	local models = ServerStorage.RoleplayOSAssets:FindFirstChild("Vehicles")
	local template = models
		and models:FindFirstChild(self.context.Configuration.Vehicles[owned.DefinitionId].ModelName)
	if not template or not template:IsA("Model") then
		return nil, "VEHICLE_MODEL_UNAVAILABLE"
	end
	local model = template:Clone()
	model:PivotTo(spawnPart.CFrame)
	model.Parent = workspace
	self.active[vehicleId] = model
	return model, nil
end
function VehicleService:Destroy()
	for _, model in self.active do
		model:Destroy()
	end
	table.clear(self.active)
end
return VehicleService
