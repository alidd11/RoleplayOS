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
	["11503290062"] = true,
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

-- Never quarantined, whatever else matches below.
--
-- The rider pose belongs to the vehicle we import: how somebody sits on a bike
-- is part of the bike, and a kit that ships its own animation should keep it.
-- Nothing in RoleplayOS touches character animation, so if this pass takes the
-- vehicle's animation content there is nothing left to put a rider on the seat
-- and they stand bolt upright over it.
--
-- Chassis words are here for the same reason in the other direction: removing
-- the tuner, the motors or the collision handling stops the thing being
-- drivable at all. This list only ever protects, so a word that matches too
-- much costs one uncleaned script rather than a broken vehicle.
local PROTECTED_WORDS = {
	"anim",
	"pose",
	"rider",
	"seat",
	"tuner",
	"initialize",
	"chassis",
	"motor",
	"anticollide",
	"drive",
}

-- Judged on the instance itself, not on where it happens to live.
--
-- Walking up the ancestors instead would protect everything inside the Tuner
-- folder, which is exactly where a kit keeps its plugins -- including the broken
-- ones this pass exists to remove.
local function holdsAnimation(instance)
	if instance:IsA("Animation") or instance:IsA("AnimationController") then
		return true
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Animation") or descendant:IsA("AnimationController") then
			return true
		end
	end
	return false
end

local function isProtected(instance)
	-- Anything holding animation content stays, whatever it is called. This is
	-- the guarantee that the rider pose survives the clean-up.
	if holdsAnimation(instance) then
		return true
	end
	local name = string.lower(instance.Name)
	for _, word in PROTECTED_WORDS do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function shouldQuarantine(instance)
	local vehicle = vehicleRoot(instance)
	if not vehicle then
		return false
	end
	if isProtected(instance) then
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
		-- Named individually because these are the ones actually throwing.
		--
		-- SmeersLightsHandler is the loud one: it reads Body.Brakes and
		-- Body.Reverse, neither of which exists on this chassis, and it does so on
		-- a loop -- the console fills with the same two errors several times a
		-- second for as long as the vehicle exists. RoleplayOS owns emergency
		-- lighting, so nothing is lost by removing it.
		--
		-- Kickstand reads Body.Kickstand, which also does not exist, and it copies
		-- itself into PlayerGui, so it throws from two places at once.
		--
		-- The AC6C gauge cluster is a second speedometer. RoleplayOS draws its own,
		-- so this one is both broken -- it reads a Dash that is not there -- and
		-- redundant even when it works.
		if
			name == "smeerslightshandler"
			or name == "kickstand"
			or string.find(name, "ac6c", 1, true) ~= nil
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
