--!strict

-- Which parts of a vehicle are its warning lights, and which circuit each one
-- belongs to.
--
-- One copy, required by both sides. The server decides whether to tag a vehicle
-- as having lights and the client decides what to flash on it, and those were
-- two separate implementations of the same idea. When they disagree the result
-- is a tagged vehicle with nothing lighting up, which is indistinguishable from
-- the feature being broken.
local VehicleLights = {}

local function matches(name: string, patterns: { string }): boolean
	local lowered = string.lower(name)
	for _, pattern in patterns do
		if string.find(lowered, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Does this look like a lamp, or like the bracket holding one?
--
-- Matching the model a part sits in is what makes an unhelpfully named bulb
-- findable, but a lightbar model also contains its own housing, mounts and trim.
-- Without this the black plastic shell of the bar would strobe along with the
-- bulbs.
--
-- A lamp emits, or is made of a material that glows, or is a saturated colour.
-- A dark grey bracket is none of those.
local function looksLikeLamp(part: BasePart): boolean
	if part:FindFirstChildWhichIsA("Light") then
		return true
	end
	-- Neon only. Glass used to count, and the one large glass part on a lightbar
	-- is its clear outer lens, which covers the bulbs: treating it as a lamp
	-- turned the whole dome solid neon and hid everything underneath it.
	if part.Material == Enum.Material.Neon then
		return true
	end
	local colour = part.Color
	local brightest = math.max(colour.R, colour.G, colour.B)
	local dullest = math.min(colour.R, colour.G, colour.B)
	-- Either strongly coloured, or close to white. Housings are neither.
	return brightest > 0.45 and (brightest - dullest > 0.2 or dullest > 0.75)
end

-- The part's own name, then the name of everything between it and the vehicle.
--
-- Kits do not name individual bulbs after the bar they sit in: the lightbars
-- here hold parts called LBR1, HL1 and Rear inside a model called Lightbar, so
-- reading only the part's own name found nothing on any emergency vehicle.
--
-- Exclusions apply at every level, so a part inside a Headlights model is
-- excluded and so is a headlight sitting loose inside a Lights model.
function VehicleLights.isLightPart(settings: any, part: BasePart, root: Instance): boolean
	if part:GetAttribute("RoleplayOSLight") == false then
		return false
	end
	if part:GetAttribute("RoleplayOSLight") == true then
		return true
	end
	-- The whole chain is walked, with no early exit on a match.
	--
	-- Breaking out as soon as something matched meant that when the part's own
	-- name matched, no ancestor was ever examined, so a bulb called LED inside a
	-- model called Headlights was accepted and strobed blue on a response. An
	-- exclusion anywhere between the part and the vehicle now wins, which is the
	-- behaviour the comment always claimed.
	local node: Instance? = part
	local named = false
	while node and node ~= root do
		if matches(node.Name, settings.ExcludedNamePatterns) then
			return false
		end
		if matches(node.Name, settings.LightNamePatterns) then
			named = true
		end
		node = node.Parent
	end
	if not named then
		return false
	end
	-- Named in its own right is enough. Named only by an ancestor has to look
	-- like a lamp, for the housing reason above.
	if matches(part.Name, settings.LightNamePatterns) then
		return true
	end
	return looksLikeLamp(part)
end

-- Whether the part sits ahead of the vehicle's centre, or nil if that cannot be
-- worked out.
--
-- The reference frame is built from two different things on purpose.
--
-- Which way the car faces comes from its driving seat. GetPivot was used for
-- this and it is not safe to: a model with no PrimaryPart and no authored pivot
-- reports world-axis rotation, frozen from however the template happened to be
-- oriented when it was saved. A fleet exported facing world X would have had
-- every one of its cars split left and right instead of front and rear, with
-- FRONT BLUE lighting the driver's side. A seat is always fitted facing the way
-- the car drives, which is the one part of a vehicle that cannot be mounted
-- sideways and still work.
--
-- Where the middle is comes from the bounding box rather than from the seat or
-- the pivot. Both of those sit forward of centre in a van or an appliance, which
-- pushes parts that are genuinely in front into the rear half.
--
-- Roblox looks down negative Z, so a negative Z is towards the front.
local function isAtFront(part: BasePart, root: Instance): boolean?
	local ok, box, orientation = pcall(function()
		local model = root :: any
		local centre = model:GetBoundingBox()
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
			or model:FindFirstChildWhichIsA("Seat", true)
		return centre, if seat then seat.CFrame - seat.CFrame.Position else nil
	end)
	if not ok or typeof(box) ~= "CFrame" then
		return nil
	end
	-- No seat is no answer rather than a guess. Falling back to the box's own
	-- rotation would reintroduce exactly the world-axis problem above, and a
	-- silently wrong circuit is worse than an unassigned one.
	if typeof(orientation) ~= "CFrame" then
		return nil
	end
	local reference = CFrame.new(box.Position) * orientation
	return reference:PointToObjectSpace(part.Position).Z < 0
end

local function isRed(colour: Color3): boolean
	return colour.R > 0.4 and colour.R > colour.G * 1.6 and colour.R > colour.B * 1.6
end

-- Which circuit a light belongs to.
--
-- Three sources, in order of how much they can be trusted:
--
-- 1. The RoleplayOSLightCircuit attribute, which somebody set deliberately.
-- 2. The configured name patterns, for kits that name their parts usefully.
-- 3. Where the part actually is on the vehicle, and what colour it already is.
--
-- The third is what makes this work on the vehicles in this place, whose bulbs
-- are called things like LBR1 and HL1. A part's position and its lens colour
-- are facts about the model rather than a convention somebody has to follow, so
-- front, rear and the rear reds resolve without anybody naming anything.
--
-- The specialised circuits are deliberately left to the first two. Alley
-- lights, grille lights, scene lights and spots cannot be told apart from each
-- other by position, and guessing would put a takedown on the grille button.
function VehicleLights.circuitFor(settings: any, part: BasePart, root: Instance): string?
	local explicit = part:GetAttribute("RoleplayOSLightCircuit")
	if type(explicit) == "string" and settings.Circuits[explicit] then
		return explicit
	end
	for circuit, patterns in settings.Circuits do
		if matches(part.Name, patterns) then
			return circuit
		end
	end
	local front = isAtFront(part, root)
	if front == nil then
		return nil
	end
	if isRed(part.Color) then
		-- A red lens at the back is the rear reds. At the front it is a fire
		-- appliance's forward reds, which run with the blues rather than apart
		-- from them, so it stays on the front circuit.
		return if front then "FrontBlue" else "RearReds"
	end
	return if front then "FrontBlue" else "RearBlue"
end

-- Which Sound in a vehicle answers to which siren tone.
--
-- Imported ELS kits name their tones differently and inconsistently in case, so
-- a tone is a list of names to try rather than one. This lived only on the
-- client, which played the sounds, while the server decided which tones to
-- offer from a table of ids it never used - so a vehicle could be offered a
-- tone it had no sound for, and denied one it did. Both sides read this now.
-- Named for what the vehicles call them.
--
-- These were Phaser and Horn, mapped onto sounds the kits name Priority and
-- Airhorn, so the panel offered a tone by one name while the car's own dash
-- legend beside it read another. The tone is whatever the vehicle calls it.
VehicleLights.SirenAliases = {
	Wail = { "Wail" },
	Yelp = { "Yelp" },
	Priority = { "Priority", "Phaser" },
	Airhorn = { "Airhorn", "Horn" },
}

-- The order a control head steps through, and the one tone that is momentary.
--
-- An airhorn is held, not selected: every kit sounds it while the key is down
-- and stops on release. It was in the rotation and looped, which turned the
-- horn into a tone that blared until something else was picked.
VehicleLights.SirenCycle = { "Wail", "Yelp", "Priority" }
VehicleLights.MomentaryTone = "Airhorn"

-- Vehicles that light and sound themselves.
--
-- An imported ELS kit runs its own patterns over its own lamps, and the siren
-- boxes that ship beside them run their own keyboard script over their own
-- sounds. Anything this framework does to such a vehicle is a second owner of
-- the same instances, and two owners of one Sound is a siren that stops
-- whenever the other one spoke last. Asking whether the vehicle brought a kit
-- is how the framework knows to leave it alone.
-- A kit counts only when it actually drives lamps. Several civilian cars in the
-- fleet carry the remote with an empty LightsParent, left behind by whoever
-- built them from a police model, and an inert kit is not a reason for this
-- framework to stop lighting a vehicle it otherwise would.
function VehicleLights.ownKit(model: Instance): RemoteFunction?
	local remote = model:FindFirstChild("EasyLS_Remote", true)
	if not (remote and remote:IsA("RemoteFunction")) then
		return nil
	end
	local parent = remote:FindFirstChild("LightsParent")
	if parent and parent:IsA("ObjectValue") and parent.Value then
		return remote
	end
	return nil
end

-- The lamps a kit flashes, for watching rather than for driving.
--
-- EasyLS keeps its stage in a local and offers no way to ask for it: the remote
-- answers GetBinds and nothing else. What it does do is set Transparency on
-- these parts several times a second while a pattern runs, so whether the bar is
-- moving is the one honest reading of whether the lights are on, and it is the
-- same one the officer is going by.
function VehicleLights.kitLamps(model: Instance, limit: number): { BasePart }
	local remote = VehicleLights.ownKit(model)
	local parent = remote and remote:FindFirstChild("LightsParent")
	local root = if parent and parent:IsA("ObjectValue") then parent.Value else nil
	local lamps = {}
	if not root then
		return lamps
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(lamps, descendant)
			if #lamps >= limit then
				break
			end
		end
	end
	return lamps
end

-- Where a kit keeps its siren sounds, if it brought any.
function VehicleLights.sirenRack(model: Instance): Instance?
	local rack = model:FindFirstChild("Siren", true)
	if not rack then
		return nil
	end
	for _, child in rack:GetChildren() do
		if child:IsA("Sound") then
			return rack
		end
	end
	return nil
end

-- The Sound in this vehicle for a tone, if it has one.
function VehicleLights.sirenSound(model: Instance, tone: string): Sound?
	local aliases = VehicleLights.SirenAliases[tone]
	if not aliases then
		return nil
	end
	local sounds: { [string]: Sound } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Sound") then
			sounds[string.lower(descendant.Name)] = descendant
		end
	end
	for _, name in aliases do
		local sound = sounds[string.lower(name)]
		if sound then
			return sound
		end
	end
	return nil
end

-- The tones this vehicle can actually sound.
--
-- Offering a tone the vehicle cannot play is a button that does nothing, and
-- withholding one it can is a siren nobody can reach. Asking the vehicle is the
-- only answer that is right for every kit.
function VehicleLights.availableTones(model: Instance): { [string]: boolean }
	local available = {}
	for tone in VehicleLights.SirenAliases do
		available[tone] = VehicleLights.sirenSound(model, tone) ~= nil
	end
	return available
end

return table.freeze(VehicleLights)
