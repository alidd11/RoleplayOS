-- Run once from the Roblox Studio Command Bar while not play-testing.
-- Moves known-broken imported ELS/control code out of Workspace without deleting it.

local ServerStorage = game:GetService("ServerStorage")

local quarantine = ServerStorage:FindFirstChild("RoleplayOSLegacyVehicleQuarantine")
if not quarantine then
	quarantine = Instance.new("Folder")
	quarantine.Name = "RoleplayOSLegacyVehicleQuarantine"
	quarantine.Parent = ServerStorage
end

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
	while current and current.Parent ~= workspace do
		current = current.Parent
	end
	if current and current:IsA("Model") and current:FindFirstChildWhichIsA("VehicleSeat", true) then
		return current
	end
	return nil
end

local function shouldQuarantine(instance)
	local vehicle = vehicleRoot(instance)
	if not vehicle then
		return false
	end
	if instance:IsA("Sound") and INVALID_SOUND_IDS[assetId(instance.SoundId)] then
		return true
	end
	if
		not (instance:IsA("LuaSourceContainer") or instance:IsA("Folder") or instance:IsA("Model"))
	then
		return false
	end
	local current = instance
	while current and current ~= vehicle do
		local name = string.lower(current.Name)
		if name == "sirencontrol" or name == "old" or string.find(name, "easyls", 1, true) then
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
for _, descendant in workspace:GetDescendants() do
	if shouldQuarantine(descendant) then
		table.insert(candidates, descendant)
	end
end

-- Move only the highest selected ancestor; moving its selected descendants too
-- would flatten the original hierarchy and make restoration ambiguous.
table.sort(candidates, function(a, b)
	return #a:GetFullName() < #b:GetFullName()
end)
local moved = 0
for _, instance in candidates do
	if instance:IsDescendantOf(workspace) then
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
			local source = instance:GetFullName()
			instance:SetAttribute("RoleplayOSOriginalPath", source)
			instance.Name = string.format("%04d_%s", moved + 1, instance.Name)
			instance.Parent = quarantine
			moved += 1
		end
	end
end

print(string.format("RoleplayOS quarantined %d broken legacy vehicle control roots", moved))
