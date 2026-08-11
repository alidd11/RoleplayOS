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
for definitionId, definition in config.Vehicles do
	local sourceName = definition.WorkspaceModelName
	local source = type(sourceName) == "string" and workspace:FindFirstChild(sourceName) or nil
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
