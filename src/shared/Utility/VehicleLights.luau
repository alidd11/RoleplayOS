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

-- Whether the part sits ahead of the vehicle's centre, or nil if that cannot
-- be worked out.
--
-- Roblox looks down negative Z, so a negative Z is towards the front.
local function isAtFront(part: BasePart, root: Instance): boolean?
	local ok, pivot = pcall(function()
		return (root :: any):GetPivot()
	end)
	if not ok then
		return nil
	end
	return pivot:PointToObjectSpace(part.Position).Z < 0
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

return table.freeze(VehicleLights)
