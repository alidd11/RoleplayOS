--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local Utils = {}

-- The cluster's geometry, in one place.
--
-- The size was written twice once, here and again in the layout binding, and the
-- two disagreed the moment the dial needed a taller panel: the binding reset it
-- to the old height, so the dial centre sat below the panel and the bottom of the
-- needle rendered outside it. Everything is placed from this size and the dial
-- centre below, so the ticks, the numerals, the needle, the readout and the
-- tell-tales cannot drift apart when one of them is adjusted.
-- Whether this game has a fuel system at all. Read once: it decides both the
-- cluster's height and whether the strip is built, and those two must not be
-- able to disagree.
local FUEL_ENABLED = Config.VehicleData.FuelEnabled

-- The strip and its legend take the bottom twenty six pixels. Without a fuel
-- system that would be an empty band under the tell-tales, so the cluster simply
-- ends above it rather than reserving space for something that is not drawn.
local CLUSTER_SIZE = if FUEL_ENABLED then Vector2.new(300, 242) else Vector2.new(300, 210)

-- A car's speedometer, not a half-circle progress meter.
--
-- The previous dial swept a flat 180 degrees, due left to due right through the
-- top, with the readout in the middle. Two things were wrong with it, and both
-- are what "cartoonish" was pointing at.
--
-- The first is the sweep. No car draws a semicircle: a real dial opens at the
-- bottom and wraps around past the horizontal, roughly 250 degrees, which is why
-- zero sits at the lower left rather than due west. The second is that the arc
-- carried no numbers at all. A speedometer with unlabelled ticks is a decoration
-- of a speedometer -- you cannot read a speed off it, which is the entire job.
--
-- Zero degrees is straight up, so the sweep runs from the lower left, up over the
-- top, and down to the lower right, leaving the bottom open for the tell-tales.
local DIAL_CENTRE = Vector2.new(150, 124)
local DIAL_RADIUS = 92
local SWEEP_START = -125
local SWEEP_ARC = 250

-- The needle is an outer band rather than a spoke from the hub.
--
-- A full-length needle sweeps straight through the middle of the dial, and the
-- middle of the dial is where the digital readout lives: at 58 mph the needle
-- was drawn through the "58". Every modern cluster that puts a number inside its
-- dial solves this the same way, by starting the needle outside the readout, so
-- the two occupy rings that never meet.
local NEEDLE_INNER = 50
local NEEDLE_OUTER = 88

-- How often the cluster reads the chassis, and how quickly the needle catches up
-- with what it read.
--
-- These were one number. The loop sampled every 0.08s and wrote the needle's
-- rotation straight from the sample, so the needle advanced in twelve visible
-- steps a second -- it ticked round the dial like a clock's second hand rather
-- than sweeping. That stepping is most of what separates a gauge from a readout:
-- a real needle has mass, so it lags its input slightly and always moves
-- continuously.
--
-- Sampling stays at 12.5Hz, because reading the chassis and rewriting six labels
-- every frame is waste. The needle is now animated separately on every frame,
-- easing toward whatever the last sample asked for.
local SAMPLE_INTERVAL = 0.08

-- Time constant of that easing, in seconds: roughly how long the needle takes to
-- cover the first two thirds of a gap. Low enough to feel responsive on the
-- throttle, high enough to absorb the jitter in a chassis velocity reading.
local NEEDLE_TAU = 0.11

-- Majors every third tick. With the sweep divided into 22, that lands them on 0,
-- 20, 40 ... 140, which is a UK speedometer's face rather than an arbitrary
-- division of whatever top speed the chassis claims.
local MAJOR_EVERY = 3
local NUMERAL_RADIUS = DIAL_RADIUS - 30

-- The tachometer, as a ring of ticks concentric with the speed dial and just
-- outside it.
--
-- A-Chassis has always published RPM. It used to drive the speed needle, which
-- was wrong, and removing that left the value going nowhere -- the chassis
-- reporting engine speed to an instrument that had stopped listening. A car
-- solves this with a second dial, and on a cluster this size a second full dial
-- does not fit, so the revs become a ring around the first one. Reading revs off
-- a ring is what most modern clusters do anyway.
--
-- No numerals on it. The useful information in a tacho at a glance is how close
-- the needle is to the red, not the precise figure, and printing a second set of
-- numbers around the outside of a dial that already has eight would clutter it.
local TACHO_OUTER = 101
local TACHO_LENGTH = 5
local TACHO_SEGMENTS = 30

-- Revs move far faster than road speed, so the ring chases its target harder
-- than the needle does. Damped all the same: an undamped ring flickers between
-- adjacent ticks at idle.
local TACHO_TAU = 0.06

-- Places a point on the dial by its position along the sweep. Roblox rotates
-- about an object's centre, so anything that must stay upright -- a numeral --
-- has to be positioned by trigonometry rather than by rotating a frame.
local function dialPoint(t: number, radius: number): (number, number)
	local radians = math.rad(SWEEP_START + SWEEP_ARC * t)
	return DIAL_CENTRE.X + radius * math.sin(radians), DIAL_CENTRE.Y - radius * math.cos(radians)
end

-- The chassis publishes its live state in a folder of values. Searched under
-- the seat and then the vehicle model, because forks disagree on where it sits,
-- and absent entirely on a vehicle without a chassis.
-- Does this folder hold chassis telemetry, or does it just share the name?
--
-- Plugins keep their own state in a folder called Values too. The Honda carries
-- three: the chassis's, and one each for two halves of a lighting addon. Only
-- one of them knows how fast the bike is going.
local function isTelemetry(folder: Instance, settings: any): boolean
	for _, name in settings.VelocityValueNames or {} do
		if folder:FindFirstChild(name) then
			return true
		end
	end
	return folder:FindFirstChild(settings.RpmValueName or "RPM") ~= nil
		or folder:FindFirstChild(settings.GearValueName or "Gear") ~= nil
end

local function readValue(folder: Folder?, name: string): any?
	local item = if folder then folder:FindFirstChild(name) else nil
	return if item and item:IsA("ValueBase") then (item :: any).Value else nil
end

local function readFirstValue(folder: Folder?, names: { string }?): any?
	for _, name in names or {} do
		local value = readValue(folder, name)
		if value ~= nil then
			return value
		end
	end
	return nil
end

local function ancestorAttribute(instance: Instance, name: string): any?
	local current: Instance? = instance
	while current do
		local value = current:GetAttribute(name)
		if value ~= nil then
			return value
		end
		current = current.Parent
	end
	return nil
end

-- Walks a path of child names from the vehicle down to a value.
--
-- The lighting addon keeps its state as BoolValues nested in the model rather
-- than in the chassis's Values folder, so these cannot go through readFirstValue.
-- Returns nil where any step is missing, which is the normal case: an ELS van
-- carries a different lighting kit from a civilian car, and a vehicle without
-- this addon must leave the lamps dark rather than pretend they are off.
local function readPath(vehicle: Instance?, candidates: { { string } }): boolean?
	for _, path in candidates do
		local node: Instance? = vehicle
		for _, name in path do
			if not node then
				break
			end
			node = node:FindFirstChild(name)
		end
		if node and node:IsA("ValueBase") then
			local value = (node :: any).Value
			return if type(value) == "boolean" then value else value ~= nil and value ~= 0
		end
	end
	return nil
end

local function readsOn(value: any): boolean
	if type(value) == "boolean" then
		return value
	elseif type(value) == "number" then
		return value ~= 0
	elseif type(value) == "string" then
		local normalised = string.lower(value)
		return normalised ~= ""
			and normalised ~= "0"
			and normalised ~= "false"
			and normalised ~= "off"
			and normalised ~= "released"
	end
	return false
end

-- How fast the vehicle is actually going, from whichever source can tell.
--
-- The published value was trusted whenever it existed, and existing was the only
-- test it had to pass. A-Chassis creates its Velocity as a Vector3Value at zero
-- and writes it from a LocalScript, so a chassis whose Drive script has not
-- started - or is running for somebody else - leaves a perfectly valid Vector3
-- sitting at 0,0,0. typeof said Vector3, the function returned zero, and the
-- fallback below it could never be reached. A speedometer reading a confident
-- nought is indistinguishable from a broken one, which is what it looked like.
--
-- Measured on a moving Peugeot: published 0,0,0 while the seat's own assembly
-- reported real motion.
--
-- The seat's assembly velocity is the reading that cannot lie. It is used
-- whenever the chassis has nothing to say, and the chassis is preferred only
-- when it says something, because a chassis that reports properly is smoothed
-- and gear-aware in a way raw physics is not.
local IDLE_STUDS_PER_SECOND = 0.5

local function horizontalStuds(value: Vector3): number
	return Vector3.new(value.X, 0, value.Z).Magnitude
end

local function speedMph(seat: VehicleSeat, values: Folder?): number
	local seatStuds = horizontalStuds(seat.AssemblyLinearVelocity)
	local published = readFirstValue(values, Config.Chassis.VelocityValueNames)
	if typeof(published) == "Vector3" then
		local publishedStuds = horizontalStuds(published)
		-- Believed unless it claims stationary while the vehicle plainly is not.
		if publishedStuds > IDLE_STUDS_PER_SECOND or seatStuds <= IDLE_STUDS_PER_SECOND then
			return publishedStuds * Config.VehicleData.StudsPerSecondToMph
		end
	end
	return seatStuds * Config.VehicleData.StudsPerSecondToMph
end

-- An instrument palette, not a HUD one.
--
-- The cluster read as cartoonish and the colour was most of why. A saturated
-- blue needle, a bright green fuel bar and coloured pills behind every tell-tale
-- is the palette of a game overlay. A car's cluster is monochrome until
-- something needs attention: white numerals, grey ticks, and colour reserved for
-- amber when a system intervenes and red when something is wrong. Restraint is
-- what makes the two colours that remain mean anything.
local C = {
	Panel = Color3.fromRGB(8, 12, 19),
	-- The dark end of the scale: a driver aid the vehicle does not have.
	Track = Color3.fromRGB(58, 64, 74),
	-- Unlit ticks and the empty part of the fuel strip, one step lighter than
	-- Track. These were the same colour, and at noon the unswept half of the dial
	-- vanished into a bright road: dark grey on dark tarmac is fine, dark grey on
	-- a sunlit pavement is nothing at all. Lifting them and giving every tick a
	-- black halo below is what makes the arc hold on both grounds.
	Unlit = Color3.fromRGB(104, 113, 128),
	-- Swept ticks and the needle. Near-white rather than blue: a needle is a
	-- pointer, and a coloured pointer reads as a progress bar.
	Live = Color3.fromRGB(232, 238, 246),
	Warn = Color3.fromRGB(232, 162, 42),
	-- The redline band before the engine reaches it: dark enough to read as a
	-- marking on the dial face rather than a lamp that is already lit.
	RedlineIdle = Color3.fromRGB(104, 44, 42),
	-- Indicators and the headlight lamp are green, main beam is blue. Not a
	-- decision: those are the colours every car on the road uses, and a driver
	-- reads them without looking.
	Indicator = Color3.fromRGB(86, 198, 110),
	Beam = Color3.fromRGB(96, 154, 255),
	Danger = Color3.fromRGB(214, 68, 62),
	Text = Color3.fromRGB(246, 249, 253),
	Muted = Color3.fromRGB(126, 138, 156),
	-- Fuel is only interesting when it is low, so it is the same grey as
	-- everything else until the existing low-fuel logic turns it amber.
	Fuel = Color3.fromRGB(176, 186, 200),
}

local function label(parent: Instance, font: Enum.Font, size: number, colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = ""
	item.TextColor3 = colour
	item.TextSize = size
	-- Carried by every label, because there is no panel behind them any more and
	-- a readout has to survive both a bright sky and a dark road.
	item.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	-- 0.45 was not enough at noon: the muted labels sat on a sunlit road with
	-- almost no separation. This is a halo rather than an outline, so it darkens
	-- the pixel behind the glyph without thickening the glyph itself.
	item.TextStrokeTransparency = 0.25
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

Utils.FUEL_ENABLED = FUEL_ENABLED
Utils.CLUSTER_SIZE = CLUSTER_SIZE
Utils.DIAL_CENTRE = DIAL_CENTRE
Utils.DIAL_RADIUS = DIAL_RADIUS
Utils.SWEEP_START = SWEEP_START
Utils.SWEEP_ARC = SWEEP_ARC
Utils.NEEDLE_INNER = NEEDLE_INNER
Utils.NEEDLE_OUTER = NEEDLE_OUTER
Utils.SAMPLE_INTERVAL = SAMPLE_INTERVAL
Utils.NEEDLE_TAU = NEEDLE_TAU
Utils.MAJOR_EVERY = MAJOR_EVERY
Utils.NUMERAL_RADIUS = NUMERAL_RADIUS
Utils.TACHO_OUTER = TACHO_OUTER
Utils.TACHO_LENGTH = TACHO_LENGTH
Utils.TACHO_SEGMENTS = TACHO_SEGMENTS
Utils.TACHO_TAU = TACHO_TAU
Utils.C = C
Utils.dialPoint = dialPoint
Utils.isTelemetry = isTelemetry
Utils.readValue = readValue
Utils.readFirstValue = readFirstValue
Utils.ancestorAttribute = ancestorAttribute
Utils.readPath = readPath
Utils.readsOn = readsOn
Utils.horizontalStuds = horizontalStuds
Utils.speedMph = speedMph
Utils.label = label

return Utils
