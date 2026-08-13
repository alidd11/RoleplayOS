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

local function removePath(rootInstance, path)
	local current = rootInstance
	for index, segment in path do
		local child = current:FindFirstChild(segment)
		if not child then
			return false
		end
		if index == #path then
			child:Destroy()
			return true
		end
		current = child
	end
	return false
end

local function sanitiseImportedVehicle(template, definitionId)
	local removed = 0
	local function remove(path)
		if removePath(template, path) then
			removed += 1
		end
	end

	-- These optional plugins target a different model hierarchy than the
	-- supplied vehicles. Leaving them in a stored template creates repeating
	-- runtime errors as soon as every player spawns the vehicle.
	if definitionId == "HondaADV160" then
		for _, path in
			{
				{ "Tuner", "Plugins", "Kickstand" },
				{ "Tuner", "Plugins", "LightAddon" },
				{ "Tuner", "Plugins", "AC6C_Style_Gauges" },
				{ "Tuner", "Plugins", "AC6_Sounds" },
				{ "Tuner", "Plugins", "EPICLIGHTS_V4" },
			}
		do
			remove(path)
		end
	elseif definitionId == "CorollaTaxi" then
		for _, path in
			{
				{ "DriveSeat", "Pickup" },
				{ "DriveSeat", "SirenControl" },
				{ "SmeersLightsHandler" },
				{ "AC6_FE_Sounds" },
			}
		do
			remove(path)
		end
	end

	local blockedAudio = {
		["10652911149"] = true,
		["10652911247"] = true,
		["11503290062"] = true,
		["370689846"] = true,
	}
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("Sound") then
			local id = string.match(descendant.SoundId, "%d+")
			if id and blockedAudio[id] then
				descendant:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

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
		if definitionId == "HondaADV160" then
			for _, descendant in template:GetDescendants() do
				if descendant:IsA("LocalScript") and descendant.Name == "Wheelie" then
					local sourceText = descendant.Source
					local marker = "while wait(clock) do"
					if not string.find(sourceText, "RoleplayOSWheelieInput", 1, true) then
						local mobileBridge = [[

	-- RoleplayOS mobile bridge. Keyboard T and gamepad input above remain intact.
	local function readRoleplayOSWheelie()
		local mobile = bike:GetAttribute("RoleplayOSWheelieInput")
		if type(mobile) == "boolean" then
			KeyWhel = mobile
			WheelieInput = if mobile then 1 else 0
		end
	end
]]
						local at = string.find(sourceText, marker, 1, true)
						if at then
							descendant.Source = string.sub(sourceText, 1, at - 1)
								.. mobileBridge
								.. string.sub(sourceText, at)
							local loopMarker = "while wait(clock) do\n"
							local loopAt = string.find(descendant.Source, loopMarker, 1, true)
							if loopAt then
								descendant.Source = string.sub(
									descendant.Source,
									1,
									loopAt + #loopMarker - 1
								) .. "\n\treadRoleplayOSWheelie()" .. string.sub(
									descendant.Source,
									loopAt + #loopMarker
								)
							end
						end
					end
				end
			end
		end
		local sanitisedCount = sanitiseImportedVehicle(template, definitionId)
		if sanitisedCount > 0 then
			print("ROLEPLAYOS_VEHICLE_SANITISED", definitionId, sanitisedCount)
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
