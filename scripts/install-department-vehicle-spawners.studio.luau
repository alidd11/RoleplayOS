-- Run once from the Studio Command Bar while NOT play-testing.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local root = Workspace:FindFirstChild("RoleplayOSVehicleFacilities")
if not root then
	root = Instance.new("Folder")
	root.Name = "RoleplayOSVehicleFacilities"
	root.Parent = Workspace
end

local anchors = {}
for _, instance in Workspace:GetDescendants() do
	if instance:IsA("BasePart") then
		local spawnId = instance:GetAttribute("SpawnId")
		if type(spawnId) == "string" then
			anchors[spawnId] = instance
		end
		anchors[instance.Name] = anchors[instance.Name] or instance
	end
end

local definitions = {
	{ "Civilian", "CityDealership", "Civilian vehicles", "CityCivilian", nil, nil, Vector3.new(18, 0, 0) },
	{ "Police", "PoliceFrontline", "Frontline fleet", "PoliceVehicleBay", "Police", "Frontline", Vector3.new(18, 0, -24) },
	{ "Police", "PoliceArmedResponse", "Armed response fleet", "PoliceVehicleBay", "Police", "ArmedResponse", Vector3.new(18, 0, 0) },
	{ "Police", "PoliceRoadsPolicing", "Roads policing fleet", "PoliceVehicleBay", "Police", "RoadsPolicing", Vector3.new(18, 0, 24) },
	{ "Ambulance", "AmbulanceFleet", "Ambulance fleet", "AmbulanceLockerRoom", "Ambulance", nil, Vector3.new(18, 0, 0) },
	{ "Fire", "FireFleet", "Fire fleet", "FireLockerRoom", "Fire", nil, Vector3.new(18, 0, 0) },
	{ "Transport", "TransportFleet", "Transport fleet", "TransportDepot", "Transport", nil, Vector3.new(18, 0, 0) },
	{ "Highways", "HighwaysFleet", "Highways fleet", "HighwaysDepot", "Highways", nil, Vector3.new(18, 0, 0) },
	{ "Prison", "PrisonFleet", "Prison fleet", "PrisonStaff", "Prison", nil, Vector3.new(18, 0, 0) },
}

local created = 0
for _, definition in definitions do
	local departmentName, spawnerId, displayName, anchorId, departmentId, divisionId, offset = table.unpack(definition)
	local department = root:FindFirstChild(departmentName)
	if not department then
		department = Instance.new("Folder")
		department.Name = departmentName
		department.Parent = root
	end
	local spawner = department:FindFirstChild(spawnerId)
	if not spawner then
		spawner = Instance.new("Model")
		spawner.Name = spawnerId
		spawner.Parent = department
		created += 1
	end
	spawner:SetAttribute("SpawnerId", spawnerId)
	spawner:SetAttribute("DisplayName", displayName)
	spawner:SetAttribute("DepartmentId", departmentId)
	spawner:SetAttribute("DivisionId", divisionId)
	CollectionService:AddTag(spawner, "RoleplayOSVehicleSpawner")

	local interaction = spawner:FindFirstChild("InteractionPoint")
	if not interaction then
		interaction = Instance.new("Part")
		interaction.Name = "InteractionPoint"
		interaction.Size = Vector3.new(3, 4, 3)
		interaction.Anchored = true
		interaction.CanCollide = false
		interaction.Transparency = 0.35
		interaction.Color = Color3.fromRGB(30, 98, 160)
		interaction.Parent = spawner
	end
	local prompt = interaction:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = interaction
	end
	prompt.ActionText = "Open vehicles"
	prompt.ObjectText = displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false

	local points = spawner:FindFirstChild("SpawnPoints")
	if not points then
		points = Instance.new("Folder")
		points.Name = "SpawnPoints"
		points.Parent = spawner
	end
	local bay = points:FindFirstChild("Bay01")
	if not bay then
		bay = Instance.new("Part")
		bay.Name = "Bay01"
		bay.Size = Vector3.new(12, 0.4, 24)
		bay.Anchored = true
		bay.CanCollide = false
		bay.Transparency = 0.72
		bay.Color = Color3.fromRGB(71, 167, 255)
		bay.Parent = points
	end

	local anchor = anchors[anchorId]
	if anchor then
		interaction.CFrame = anchor.CFrame * CFrame.new(offset + Vector3.new(0, 2, 0))
		bay.CFrame = anchor.CFrame * CFrame.new(offset + Vector3.new(0, 0.3, -28))
	else
		warn("Vehicle spawner has no matching anchor", spawnerId, anchorId)
	end
end

print("ROLEPLAYOS_DEPARTMENT_SPawners_READY", created)
