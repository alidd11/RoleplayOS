-- Run once from the Studio Command Bar while NOT play-testing.
-- Moves only configured native player SpawnLocations. Vehicle SpawnPoints,
-- map geometry and unrelated SpawnLocations are deliberately left alone.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local root = Workspace:FindFirstChild("RoleplayOSMapSpawns")
if not root then
	root = Instance.new("Folder")
	root.Name = "RoleplayOSMapSpawns"
	root.Parent = Workspace
end

local definitions = {
	CityCivilian = { Department = "Civilian", Name = "CityCivilian" },
	PoliceLockerRoom = { Department = "Police", Name = "PoliceLockerRoom" },
	PoliceVehicleBay = { Department = "Police", Name = "PoliceVehicleBay" },
	AmbulanceLockerRoom = { Department = "Ambulance", Name = "AmbulanceLockerRoom" },
	FireLockerRoom = { Department = "Fire", Name = "FireLockerRoom" },
	ControlRoom = { Department = "Control", Name = "ControlRoom" },
	TransportDepot = { Department = "Transport", Name = "TransportDepot" },
	HighwaysDepot = { Department = "Highways", Name = "HighwaysDepot" },
	PrisonStaff = { Department = "Prison", Name = "PrisonStaff" },
}

local departments =
	{ "Civilian", "Police", "Ambulance", "Fire", "Control", "Transport", "Highways", "Prison" }
local folders = {}
for _, departmentName in departments do
	local folder = root:FindFirstChild(departmentName)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = departmentName
		folder.Parent = root
	end
	folders[departmentName] = folder
end

local candidates = {}
for _, instance in Workspace:GetDescendants() do
	if instance:IsA("SpawnLocation") then
		table.insert(candidates, instance)
	end
end

local seen = {}
local moved = 0
local missing = {}
local duplicates = {}
for _, instance in candidates do
	local spawnId = instance:GetAttribute("SpawnId")
	local definition = definitions[spawnId]
	if definition then
		if seen[spawnId] then
			table.insert(duplicates, instance:GetFullName())
		else
			seen[spawnId] = true
			instance.Name = definition.Name
			instance:SetAttribute("RoleplayOSSpawnPad", true)
			instance:SetAttribute("RoleplayOSDepartment", definition.Department)
			instance.AllowTeamChangeOnTouch = false
			instance.Neutral = false
			CollectionService:AddTag(instance, "RoleplayOSSpawnPad")
			local destination = folders[definition.Department]
			if instance.Parent ~= destination then
				instance.Parent = destination
			end
			moved += 1
		end
	end
end

for spawnId in definitions do
	if not seen[spawnId] then
		table.insert(missing, spawnId)
	end
end

print(
	"ROLEPLAYOS_SPAWNS_ORGANISED",
	"moved=" .. moved,
	"missing=" .. #missing,
	"duplicates=" .. #duplicates
)
if #missing > 0 then
	warn("Missing configured spawn IDs", table.concat(missing, ", "))
end
if #duplicates > 0 then
	warn("Duplicate configured spawn pads", table.concat(duplicates, ", "))
end
