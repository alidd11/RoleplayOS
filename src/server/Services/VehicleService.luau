--!strict
local ServerStorage = game:GetService("ServerStorage")
local VehicleService = { active = {} }
function VehicleService:Init(context: any)
	self.context = context
end
function VehicleService:Start() end

function VehicleService:_plate(part: BasePart, registration: string)
	local gui = part:FindFirstChild("RoleplayOSRegistration")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "RoleplayOSRegistration"
		gui.Face = Enum.NormalId.Front
		gui.PixelsPerStud = 80
		gui.Parent = part
		local text = Instance.new("TextLabel")
		text.Name = "Registration"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(244, 204, 45)
		text.BorderSizePixel = 0
		text.Font = Enum.Font.RobotoMono
		text.TextColor3 = Color3.fromRGB(12, 15, 18)
		text.TextScaled = true
		text.Parent = gui
	end
	local label = gui:FindFirstChild("Registration")
	if label and label:IsA("TextLabel") then
		label.Text = registration
	end
end

function VehicleService:_applyIdentity(model: Model, vehicle: any, ownerUserId: number)
	model:SetAttribute("RoleplayOSVehicleId", vehicle.VehicleId)
	model:SetAttribute("RoleplayOSRegistration", vehicle.Registration)
	model:SetAttribute("RoleplayOSOwnerUserId", ownerUserId)
	model:SetAttribute("RoleplayOSOwnerCharacterId", vehicle.OwnerCharacterId)
	local matched = false
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and table.find(
				self.context.Configuration.VehicleIdentity.PlatePartNames,
				descendant.Name
			)
		then
			matched = true
			self:_plate(descendant, vehicle.Registration)
		end
	end
	if matched then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		return
	end
	local _, size = model:GetBoundingBox()
	for _, direction in { -1, 1 } do
		local plate = Instance.new("Part")
		plate.Name = "RegistrationPlate"
		plate.Size = Vector3.new(2.4, 0.55, 0.08)
		plate.CanCollide = false
		plate.Massless = true
		plate.CFrame = root.CFrame
			* CFrame.new(0, -size.Y * 0.25, direction * size.Z * 0.5)
			* CFrame.Angles(0, if direction == 1 then math.pi else 0, 0)
		plate.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = plate
		weld.Parent = plate
		self:_plate(plate, vehicle.Registration)
	end
end
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
	self:_applyIdentity(model, owned, player.UserId)
	model.Parent = workspace
	self.active[vehicleId] = model
	return model, nil
end

function VehicleService:SpawnTeam(
	player: Player,
	definitionId: string,
	spawnPart: BasePart
): (Model?, string?)
	local team = player.Team
	local duty = self.context.Services:Get("DutyService"):Get(player)
	local definition = self.context.Configuration.Vehicles[definitionId]
	if not team or not duty or not definition then
		return nil, "TEAM_VEHICLE_NOT_AUTHORISED"
	end
	local registration, reason = self.context.Services
		:Get("VehicleOwnershipService")
		:GetOrCreateTeamRegistration(player, team.Name, definitionId)
	if not registration then
		return nil, reason
	end
	local models = ServerStorage.RoleplayOSAssets:FindFirstChild("Vehicles")
	local template = models and models:FindFirstChild(definition.ModelName)
	if not template or not template:IsA("Model") then
		return nil, "VEHICLE_MODEL_UNAVAILABLE"
	end
	local vehicleId = string.format("TEAM:%d:%s:%s", player.UserId, team.Name, definitionId)
	if self.active[vehicleId] then
		return nil, "VEHICLE_NOT_AVAILABLE"
	end
	local model = template:Clone()
	model:PivotTo(spawnPart.CFrame)
	self:_applyIdentity(model, {
		VehicleId = vehicleId,
		Registration = registration,
		OwnerCharacterId = nil,
	}, player.UserId)
	model:SetAttribute("RoleplayOSTeamVehicle", true)
	model:SetAttribute("RoleplayOSTeamName", team.Name)
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
