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
	{
		"Civilian",
		"CityDealership",
		"Civilian vehicles",
		"CityCivilian",
		nil,
		nil,
		Vector3.new(18, 0, 0),
	},
	-- One terminal for the whole force rather than one per unit.
	--
	-- Splitting it by division meant four prompts standing in a row doing the
	-- same job, and a vehicle tagged for one unit was invisible at the others'.
	-- Leaving DivisionId unset here offers every police vehicle at the single
	-- terminal, and the eight bays below are what stops two cars being handed
	-- the same patch of ground.
	{
		"Police",
		"PoliceFleet",
		"Police fleet",
		"PoliceLockerRoom",
		"Police",
		nil,
		Vector3.new(62, 0, 0),
		8,
	},
	{
		"Ambulance",
		"AmbulanceFleet",
		"Ambulance fleet",
		"AmbulanceLockerRoom",
		"Ambulance",
		nil,
		Vector3.new(18, 0, 0),
	},
	{ "Fire", "FireFleet", "Fire fleet", "FireLockerRoom", "Fire", nil, Vector3.new(18, 0, 0) },
	{
		"Transport",
		"TransportFleet",
		"Transport fleet",
		"TransportDepot",
		"Transport",
		nil,
		Vector3.new(18, 0, 0),
	},
	{
		"Highways",
		"HighwaysFleet",
		"Highways fleet",
		"HighwaysDepot",
		"Highways",
		nil,
		Vector3.new(18, 0, 0),
	},
	{
		"Prison",
		"PrisonFleet",
		"Prison fleet",
		"PrisonStaff",
		"Prison",
		nil,
		Vector3.new(18, 0, 0),
	},
}

local created = 0

-- Taxi vehicles operate from the shared Transport facility. Remove the old
-- civilian-side TaxiFleet when this installer is rerun so there is only one
-- authoritative taxi spawner in the place.
local legacyCivilian = root:FindFirstChild("Civilian")
local legacyTaxi = legacyCivilian and legacyCivilian:FindFirstChild("TaxiFleet")
if legacyTaxi then
	legacyTaxi:Destroy()
end

for _, definition in definitions do
	local departmentName, spawnerId, displayName, anchorId, departmentId, divisionId, offset, bayCount =
		table.unpack(definition)
	bayCount = bayCount or 1
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
	local anchor = anchors[anchorId]
	if not anchor then
		warn("Vehicle spawner has no matching anchor", spawnerId, anchorId)
		continue
	end
	interaction.CFrame = anchor.CFrame * CFrame.new(offset + Vector3.new(0, 2, 0))

	-- Four across on a fourteen stud pitch and two deep on a twenty eight stud
	-- pitch. A bay is twelve by twenty four, so those pitches leave a margin on
	-- both axes and a car on one bay stays outside the clearance box of the
	-- next. Anything past eight simply continues the pattern.
	for index = 1, bayCount do
		local column = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local bayId = string.format("Bay%02d", index)
		local bay = points:FindFirstChild(bayId)
		if not bay then
			bay = Instance.new("Part")
			bay.Name = bayId
			bay.Size = Vector3.new(12, 0.4, 24)
			bay.Anchored = true
			bay.CanCollide = false
			bay.Transparency = 0.72
			bay.Color = Color3.fromRGB(71, 167, 255)
			bay.Parent = points
		end
		local spread = if bayCount > 1
			then Vector3.new(column * 14 - 21, 0, row * -28)
			else Vector3.zero
		bay.CFrame = anchor.CFrame * CFrame.new(offset + Vector3.new(0, 0.3, -28) + spread)
	end
end

print("ROLEPLAYOS_DEPARTMENT_SPawners_READY", created)
