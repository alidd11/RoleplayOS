-- Run once from the Roblox Studio Command Bar while NOT play-testing.
-- Permanently removes only the known broken third-party ELS/controller roots.
-- Physical lamps, meshes and vehicle chassis remain for RoleplayOS to adopt.

local ServerStorage = game:GetService("ServerStorage")

local INVALID_SOUND_IDS = {
	["0"] = true,
	["188608071"] = true,
	["201887209"] = true,
	["370689846"] = true,
	["1340357965"] = true,
	["1424721819"] = true,
	["10652911149"] = true,
	["10652911247"] = true,
	["100763417929561"] = true,
	["127281808730042"] = true,
	["129205600734760"] = true,
	["140158048016993"] = true,
}

local function assetId(value)
	return string.match(value or "", "%d+")
end

local function vehicleRoot(instance)
	local current = instance
	while current and current.Parent ~= workspace and current.Parent ~= ServerStorage do
		current = current.Parent
	end
	if current and current:IsA("Model") and current:FindFirstChildWhichIsA("VehicleSeat", true) then
		return current
	end
	return nil
end

local function isBrokenLegacyControl(instance)
	local vehicle = vehicleRoot(instance)
	if not vehicle then
		return false
	end
	if instance:IsA("Sound") and INVALID_SOUND_IDS[assetId(instance.SoundId)] then
		return true
	end
	if
		not instance:IsA("LuaSourceContainer")
		and not instance:IsA("Folder")
		and not instance:IsA("Model")
	then
		return false
	end
	local current = instance
	while current and current ~= vehicle do
		local name = string.lower(current.Name)
		if
			name == "sirencontrol"
			or name == "old"
			or name == "smoke_fe"
			or name == "ac6_fe_sounds"
			or name == "brakeheat_fe"
			or string.find(name, "easyls", 1, true)
		then
			return true
		end
		current = current.Parent
	end
	if instance:IsA("LuaSourceContainer") then
		local path = string.lower(instance:GetFullName())
		return string.find(path, ".body.lightbar.", 1, true) ~= nil
			or string.find(path, ".body.lights.", 1, true) ~= nil
			or string.find(path, ".lights.handler", 1, true) ~= nil
			or string.find(path, ".binsystem.", 1, true) ~= nil
	end
	return false
end

local candidates = {}
local roots = { workspace }
local templates = ServerStorage:FindFirstChild("RoleplayOSVehicleTemplates")
if templates then
	table.insert(roots, templates)
end
for _, root in roots do
	for _, descendant in root:GetDescendants() do
		if isBrokenLegacyControl(descendant) then
			table.insert(candidates, descendant)
		end
	end
end

table.sort(candidates, function(a, b)
	return #a:GetFullName() < #b:GetFullName()
end)

local removed = 0
for _, instance in candidates do
	if instance:IsDescendantOf(workspace) or instance:IsDescendantOf(ServerStorage) then
		local selectedAncestor = false
		local ancestor = instance.Parent
		while ancestor and ancestor ~= workspace do
			if table.find(candidates, ancestor) then
				selectedAncestor = true
				break
			end
			ancestor = ancestor.Parent
		end
		if not selectedAncestor then
			instance:Destroy()
			removed += 1
		end
	end
end

local oldQuarantine = ServerStorage:FindFirstChild("RoleplayOSLegacyVehicleQuarantine")
local removedQuarantine = oldQuarantine ~= nil
if oldQuarantine then
	oldQuarantine:Destroy()
end

print(
	string.format(
		"ROLEPLAYOS_LEGACY_ELS_REMOVED roots=%d oldQuarantine=%s",
		removed,
		tostring(removedQuarantine)
	)
)
