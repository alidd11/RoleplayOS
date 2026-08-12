-- Run once from the Studio Command Bar while NOT play-testing.
-- Converts the parked Workspace cars into inert ServerStorage templates.
assert(
	not game:GetService("RunService"):IsRunning(),
	"Stop the play test before installing vehicles"
)

local ServerStorage = game:GetService("ServerStorage")
local config = require(game.ReplicatedStorage.RoleplayOS.Config.Config)
local root = ServerStorage:FindFirstChild("RoleplayOSVehicleTemplates") or Instance.new("Folder")
root.Name = "RoleplayOSVehicleTemplates"
root.Parent = ServerStorage

local installedBySource = {}
local function findSource(definition)
	local sourcePath = definition.WorkspaceSourcePath
	if type(sourcePath) == "table" then
		local current = workspace
		for _, segment in sourcePath do
			current = current:FindFirstChild(segment)
			if not current then
				return nil
			end
		end
		return current
	end
	local sourceName = definition.WorkspaceModelName
	return type(sourceName) == "string" and workspace:FindFirstChild(sourceName) or nil
end

for definitionId, definition in config.Vehicles do
	local sourceName = definition.WorkspaceModelName
	local source = findSource(definition)
	if source and source:IsA("Model") and type(definition.AssetPath) == "table" then
		local parent = root
		for index = 1, #definition.AssetPath - 1 do
			local segment = definition.AssetPath[index]
			local folder = parent:FindFirstChild(segment) or Instance.new("Folder")
			folder.Name = segment
			folder.Parent = parent
			parent = folder
		end
		local finalName = definition.AssetPath[#definition.AssetPath]
		local old = parent:FindFirstChild(finalName)
		if old then
			old:Destroy()
		end
		local template = source:Clone()
		template.Name = finalName
		-- The taxi package includes a colour mutator and its own plate writers.
		-- RoleplayOS owns both concerns, so leave the chassis/audio scripts intact
		-- but remove those two competing writers before the template is stored.
		if definitionId == "CorollaTaxi" then
			for _, descendant in template:GetDescendants() do
				if
					descendant.Name == "policecarcolor"
					or descendant.Name == "LicensePlateGenerator"
				then
					descendant:Destroy()
				end
			end
			for _, plateName in { "front", "rear" } do
				local plate = template:FindFirstChild(plateName, true)
				if plate then
					plate:SetAttribute("RoleplayOSPlate", true)
					for _, child in plate:GetDescendants() do
						if
							child:IsA("TextLabel")
							or child:IsA("TextButton")
							or child:IsA("TextBox")
						then
							child:SetAttribute("RoleplayOSPlateText", true)
						end
					end
				end
			end
		end
		template:SetAttribute("RoleplayOSVehicleTemplate", true)
		template:SetAttribute("RoleplayOSDefinitionId", definitionId)
		template.Parent = parent
		installedBySource[source] = (installedBySource[source] or 0) + 1
		print("ROLEPLAYOS_VEHICLE_INSTALLED", definitionId, sourceName, template:GetFullName())
	end
end

for source, count in installedBySource do
	print("ROLEPLAYOS_VEHICLE_SOURCE_REMOVED", source.Name, "templates", count)
	source:Destroy()
end

print("ROLEPLAYOS_VEHICLE_INSTALL_COMPLETE")
