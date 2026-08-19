--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

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

local SpeedometerController = { connections = {}, seat = nil, accumulator = 0 }
function SpeedometerController:Init(context: any)
	self.context = context
	self.settings = Config.Chassis
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

-- The chassis's own values folder.
--
-- This used to take whatever FindFirstChild returned for the name, and that
-- walks the tree in its own order and stops at the first hit. On the Honda it
-- stopped at the lighting addon's folder every time: no Velocity, no RPM, no
-- Gear, no PBrake. So the cluster fell back to reading the seat's own assembly
-- velocity, the gear and rev counter had nothing to show, and the handbrake
-- badge could never light because the value it watches was in a folder nobody
-- was looking at. The two vehicles that did work only worked because they
-- happen to carry one Values folder each.
--
-- Nearest wins where telemetry is present, so a seat-level folder still beats a
-- deeper one, but a folder that cannot answer the question is never chosen over
-- one that can.
function SpeedometerController:_chassisValues(seat: BasePart): Folder?
	local settings = self.settings
	local name = settings.ValuesFolderName
	local nearby = { seat:FindFirstChild(name), seat.Parent and seat.Parent:FindFirstChild(name) }
	for _, candidate in nearby do
		if candidate and candidate:IsA("Folder") and isTelemetry(candidate, settings) then
			return candidate
		end
	end
	local vehicle = seat:FindFirstAncestorOfClass("Model")
	if not vehicle then
		return nil
	end
	local fallback: Folder? = nil
	for _, descendant in vehicle:GetDescendants() do
		if descendant.Name == name and descendant:IsA("Folder") then
			if isTelemetry(descendant, settings) then
				return descendant
			end
			fallback = fallback or descendant
		end
	end
	-- Nothing published telemetry. The caller copes: speed falls back to the
	-- seat's assembly velocity and the rest of the cluster stays blank, which is
	-- the honest reading for a vehicle that reports nothing.
	return fallback
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

function SpeedometerController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSSpeedometer"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 12
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Cluster"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = UDim2.fromOffset(CLUSTER_SIZE.X, CLUSTER_SIZE.Y)
	-- No panel behind it. A cluster in a car is not a card laid over the
	-- windscreen: the instruments sit on the world and the black rectangle was
	-- taking a sixth of the screen to hold six things that can hold themselves.
	--
	-- Legibility moves onto the parts instead. Every label carries a dark text
	-- stroke, which is what keeps a white readout on a bright sky and a dark road
	-- both readable, and is the reason a background was there in the first place.
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	-- A round dial with a needle, built out of rotated frames.
	--
	-- Roblox has no arc primitive, so the arc is a ring of thin frames anchored at
	-- their centre on the dial's centre and rotated into place, each drawing only a
	-- short mark at its far end. The needle is the same trick with one long frame.
	self.segments = {}
	local count = self.settings.SweepSegments
	local topSpeed = self.settings.TopSpeedMph
	for index = 1, count do
		local t = (index - 1) / math.max(count - 1, 1)
		local major = (index - 1) % MAJOR_EVERY == 0

		local spoke = Instance.new("Frame")
		spoke.Name = "Tick" .. index
		-- Twice the radius tall and anchored at its middle, so the frame's centre
		-- sits exactly on the dial's centre.
		--
		-- The first version was half as tall and anchored at its base, on the
		-- assumption that rotation pivots about the anchor point. It does not: it
		-- pivots about the object's centre, so every tick swept a circle of half
		-- the radius, centred half a radius too high. Anchoring at the middle
		-- makes the two the same point, which is correct either way round.
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.BackgroundTransparency = 1
		spoke.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y)
		-- Hairlines. Three pixels wide with rounded ends is a dash; a tick is a
		-- line. Majors are longer and a touch heavier, which is what lets the eye
		-- read a speed off the arc without counting.
		spoke.Size = UDim2.fromOffset(if major then 2 else 1, DIAL_RADIUS * 2)
		spoke.Rotation = SWEEP_START + SWEEP_ARC * t
		spoke.Parent = frame
		local mark = Instance.new("Frame")
		mark.BackgroundColor3 = C.Unlit
		mark.BorderSizePixel = 0
		mark.Size = UDim2.new(1, 0, 0, if major then 12 else 6)
		mark.Parent = spoke
		-- Frames take no text stroke, so the halo that keeps the labels readable on
		-- a bright road has to be a UIStroke here. Thin and mostly transparent: it
		-- is a shadow under the tick, not an outline around it.
		local halo = Instance.new("UIStroke")
		halo.Color = Color3.fromRGB(0, 0, 0)
		halo.Thickness = 1
		halo.Transparency = 0.55
		halo.Parent = mark
		-- No corner radius. A rounded tick is a lozenge, and a cluster does not
		-- have lozenges on it.
		self.segments[index] = mark

		-- The number against the major tick, inboard of the arc and upright.
		if major then
			-- White, not the muted grey the rest of the furniture uses. These are the
			-- dial's face rather than a caption, and grey numerals on a bright road
			-- were unreadable at noon.
			local numeral = label(frame, Enum.Font.GothamMedium, 11, C.Text)
			numeral.Name = "Mark" .. index
			numeral.AnchorPoint = Vector2.new(0.5, 0.5)
			local x, y = dialPoint(t, NUMERAL_RADIUS)
			numeral.Position = UDim2.fromOffset(x, y)
			numeral.Size = UDim2.fromOffset(34, 13)
			numeral.TextXAlignment = Enum.TextXAlignment.Center
			numeral.Text = tostring(math.floor(topSpeed * t + 0.5))
		end
	end

	-- The tacho ring. Same rotated-frame construction as the speed ticks, at a
	-- larger radius and a shorter mark.
	--
	-- The redline is drawn permanently rather than only appearing once the engine
	-- reaches it, because that is what the band on a real dial is for: it tells you
	-- where the limit is before you get there.
	self.tachoSegments = {}
	self.tachoRedline = {}
	local redlineFrom = self.settings.RedlineBand
	for index = 1, TACHO_SEGMENTS do
		local t = (index - 1) / (TACHO_SEGMENTS - 1)
		local spoke = Instance.new("Frame")
		spoke.Name = "Rev" .. index
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.BackgroundTransparency = 1
		spoke.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y)
		spoke.Size = UDim2.fromOffset(2, TACHO_OUTER * 2)
		spoke.Rotation = SWEEP_START + SWEEP_ARC * t
		spoke.Parent = frame
		local mark = Instance.new("Frame")
		mark.BorderSizePixel = 0
		mark.Size = UDim2.new(1, 0, 0, TACHO_LENGTH)
		mark.Parent = spoke
		local halo = Instance.new("UIStroke")
		halo.Color = Color3.fromRGB(0, 0, 0)
		halo.Thickness = 1
		halo.Transparency = 0.55
		halo.Parent = mark
		local inRedline = t >= redlineFrom
		self.tachoRedline[index] = inRedline
		mark.BackgroundColor3 = if inRedline then C.RedlineIdle else C.Unlit
		self.tachoSegments[index] = mark
	end

	-- Same construction as the ticks: a frame centred on the pivot, twice the
	-- needle's reach, with only the band between NEEDLE_INNER and NEEDLE_OUTER
	-- drawn. Rotating it swings that band round the dial without it ever crossing
	-- the readout in the middle.
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.BackgroundTransparency = 1
	needle.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y)
	needle.Size = UDim2.fromOffset(2, NEEDLE_OUTER * 2)
	needle.Rotation = SWEEP_START
	needle.ZIndex = 3
	needle.Parent = frame
	local needleArm = Instance.new("Frame")
	needleArm.Name = "Arm"
	needleArm.BackgroundColor3 = C.Live
	needleArm.BorderSizePixel = 0
	needleArm.Size = UDim2.fromScale(1, (NEEDLE_OUTER - NEEDLE_INNER) / (NEEDLE_OUTER * 2))
	needleArm.ZIndex = 3
	needleArm.Parent = needle
	self.needle, self.needleArm = needle, needleArm

	-- No hub. A hub is the cap over the spindle a full-length needle turns on, and
	-- this needle does not reach the centre, so a disc there is a dot in the middle
	-- of the number for no reason.

	local speed = label(frame, Enum.Font.RobotoMono, 38, C.Text)
	speed.Name = "Speed"
	speed.Text = "0"
	speed.AnchorPoint = Vector2.new(0.5, 0.5)
	speed.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y - 14)
	speed.Size = UDim2.fromOffset(120, 44)
	speed.TextXAlignment = Enum.TextXAlignment.Center
	self.speed = speed

	local unit = label(frame, Enum.Font.GothamBold, 11, C.Muted)
	unit.Text = "MPH"
	unit.AnchorPoint = Vector2.new(0.5, 0.5)
	unit.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y + 16)
	unit.Size = UDim2.fromOffset(70, 13)
	unit.TextXAlignment = Enum.TextXAlignment.Center

	-- Selected gear, stacked under the readout the way a cluster stacks it, as a
	-- bare numeral. It had a rounded plate behind it, and a rounded box around a
	-- number is the thing that reads as a mobile game rather than a dashboard.
	local gear = label(frame, Enum.Font.GothamBold, 19, C.Text)
	gear.Name = "Gear"
	gear.Text = "N"
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y + 42)
	gear.Size = UDim2.fromOffset(60, 22)
	gear.TextXAlignment = Enum.TextXAlignment.Center
	self.gear = gear

	local plate = label(frame, Enum.Font.GothamMedium, 10, C.Muted)
	plate.Name = "Registration"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.fromScale(0.5, 0)
	plate.Size = UDim2.fromOffset(240, 13)
	plate.TextXAlignment = Enum.TextXAlignment.Center
	self.plate = plate

	-- Driver aid tell-tales, in the open bottom of the dial, which is the row a
	-- real cluster keeps them in.
	--
	-- A-Chassis has published ABS and TCS from the start - whether the system is
	-- fitted, and whether it is intervening right now - and none of it was on
	-- screen. Three states, because two would lose the distinction that matters: a
	-- dark lamp means not fitted, dim means fitted and watching, lit amber means it
	-- is working this instant. Amber rather than the cluster's white because amber
	-- is what a car uses for "a system is intervening".
	local TELLTALE_Y = DIAL_CENTRE.Y + 72
	local function telltale(name: string, text: string, offsetX: number, size: number): TextLabel
		local mark = label(frame, Enum.Font.GothamBold, size, C.Muted)
		mark.Name = name
		mark.Text = text
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromOffset(offsetX, TELLTALE_Y)
		mark.Size = UDim2.fromOffset(42, 22)
		mark.TextXAlignment = Enum.TextXAlignment.Center
		return mark
	end
	self.abs = telltale("ABS", "ABS", DIAL_CENTRE.X - 44, 12)
	self.tcs = telltale("TCS", "TC", DIAL_CENTRE.X + 44, 12)

	-- Headlight and main beam, flanking the driver aids. Green and blue, which is
	-- what every car uses and what a driver recognises without reading.
	--
	-- Lettered rather than drawn. The real symbols are the same lamp shape twice
	-- and differ only in whether the beam lines slope, which at twelve pixels in a
	-- Roblox font came out as two identical glyphs sitting either side of the dial
	-- -- accurate to the standard and useless to look at. LO and HI cannot be
	-- confused with each other at any size, and the colours still carry the
	-- convention.
	self.headlight = telltale("Headlight", "LO", DIAL_CENTRE.X - 84, 12)
	self.mainBeam = telltale("MainBeam", "HI", DIAL_CENTRE.X + 84, 12)

	-- The indicators, out at the sides of the dial clear of the tacho ring, which
	-- is where a cluster puts them. Arrows rather than words: an indicator lamp has
	-- never carried text, and a driver checking one is not reading.
	self.indicatorLeft = telltale("IndicatorLeft", "◀", DIAL_CENTRE.X - 122, 15)
	self.indicatorLeft.Position = UDim2.fromOffset(DIAL_CENTRE.X - 122, DIAL_CENTRE.Y)
	self.indicatorRight = telltale("IndicatorRight", "▶", DIAL_CENTRE.X + 122, 15)
	self.indicatorRight.Position = UDim2.fromOffset(DIAL_CENTRE.X + 122, DIAL_CENTRE.Y)

	-- The parking brake lamp, drawn the way a car draws it: a P inside a ring. It
	-- was a filled disc that turned solid red, which reads as a button rather than
	-- a warning lamp. The ring stays and only its colour changes, which is what a
	-- real lamp does when it lights.
	local handbrake = telltale("Handbrake", "P", DIAL_CENTRE.X, 13)
	handbrake.Size = UDim2.fromOffset(22, 22)
	local handbrakeStroke = Instance.new("UIStroke")
	handbrakeStroke.Color = C.Muted
	handbrakeStroke.Thickness = 1.5
	handbrakeStroke.Transparency = 0.35
	handbrakeStroke.Parent = handbrake
	-- Restores the ring. Stripping the badge frames took this corner radius with
	-- them and left the lamp as a red rectangle.
	Instance.new("UICorner", handbrake).CornerRadius = UDim.new(1, 0)
	self.handbrake, self.handbrakeStroke = handbrake, handbrakeStroke

	-- Built only where fuel is a system. A gauge that reads the same figure for a
	-- whole session is the decoration this cluster was cleared of, and a permanent
	-- 100% would be worse than nothing at all.
	if FUEL_ENABLED then
		-- Fuel, as a strip under the dial. Short, square-ended and grey: a wide bright
		-- green pill is a health bar, and a car's fuel gauge is neither wide nor green
		-- until it is nearly empty.
		local fuelTrack = Instance.new("Frame")
		fuelTrack.Name = "Fuel"
		fuelTrack.AnchorPoint = Vector2.new(0.5, 0.5)
		fuelTrack.Position = UDim2.fromOffset(DIAL_CENTRE.X, 220)
		fuelTrack.Size = UDim2.fromOffset(132, 5)
		fuelTrack.BackgroundColor3 = C.Unlit
		fuelTrack.BorderSizePixel = 0
		fuelTrack.Parent = frame
		local fuelFill = Instance.new("Frame")
		fuelFill.Name = "Fill"
		fuelFill.BackgroundColor3 = C.Fuel
		fuelFill.BorderSizePixel = 0
		fuelFill.Size = UDim2.fromScale(1, 1)
		fuelFill.Parent = fuelTrack
		local fuelHalo = Instance.new("UIStroke")
		fuelHalo.Color = Color3.fromRGB(0, 0, 0)
		fuelHalo.Thickness = 1
		fuelHalo.Transparency = 0.5
		fuelHalo.Parent = fuelTrack
		self.fuelFill = fuelFill
		local fuelMark = label(frame, Enum.Font.GothamBold, 9, C.Muted)
		fuelMark.Name = "FuelMark"
		fuelMark.Text = "FUEL"
		fuelMark.AnchorPoint = Vector2.new(0.5, 0.5)
		fuelMark.Position = UDim2.fromOffset(DIAL_CENTRE.X, 234)
		fuelMark.Size = UDim2.fromOffset(170, 12)
		fuelMark.TextXAlignment = Enum.TextXAlignment.Center
		self.fuelTrack, self.fuelMark = fuelTrack, fuelMark
	end

	self.gui, self.frame = gui, frame
	-- Ambient display, scaled with the rest of it so the readout keeps its
	-- proportions on a phone as well as a large monitor.
	local frameScale = Instance.new("UIScale")
	frameScale.Parent = frame
	self.frameScale = frameScale
end

-- Lights the tacho ring up to a fraction of the redline.
--
-- Unlit ticks keep the dark red of the band where they fall inside it, so the
-- redline stays visible as a marking on the face at idle. Lit ticks go white,
-- and red once past the band -- the same convention the speed dial uses, which
-- is what makes the two rings read as one instrument.
function SpeedometerController:_paintTacho(fraction: number)
	local count = #self.tachoSegments
	local lit = math.clamp(math.floor(fraction * count + 0.5), 0, count)
	if lit == self.tachoLit then
		return
	end
	self.tachoLit = lit
	for index, segment in self.tachoSegments do
		local inRedline = self.tachoRedline[index]
		if index > lit then
			segment.BackgroundColor3 = if inRedline then C.RedlineIdle else C.Unlit
		else
			segment.BackgroundColor3 = if inRedline then C.Danger else C.Live
		end
	end
end

-- Shows or hides the whole ring.
--
-- A vehicle that publishes no engine speed gets no tacho rather than a ring
-- frozen at zero, which would read as an engine that is not running.
function SpeedometerController:_setTachoVisible(visible: boolean)
	if self.tachoVisible == visible then
		return
	end
	self.tachoVisible = visible
	for _, segment in self.tachoSegments do
		local spoke = segment.Parent :: Frame
		spoke.Visible = visible
	end
end

-- Moves the needle and the number one frame closer to the last sample.
--
-- Exponential easing rather than a fixed step per frame, so the needle covers a
-- large gap quickly and a small one gently, which is how a real one behaves. The
-- alpha is derived from dt through exp rather than used directly, because a
-- constant fraction per frame would make the needle settle at a different speed
-- on a 144Hz screen than on a 30Hz one.
--
-- The number is driven from the same eased value as the needle rather than from
-- the raw sample. That is deliberate: a digital readout that jumps to 58 while
-- the needle is still passing 40 reads as two instruments disagreeing.
function SpeedometerController:_animate(dt: number)
	local target = self.targetMph
	-- Nothing sampled yet. Drawing a zero here would make the needle wind up from
	-- the end stop on the first frame after the cluster appears.
	if target == nil then
		return
	end
	local shown = self.shownMph
	if shown == nil then
		-- First sample since getting in. Start where the vehicle already is.
		shown = target
	end
	shown += (target - shown) * (1 - math.exp(-dt / NEEDLE_TAU))
	-- Snapped once it is within a twentieth of a mph, so the needle actually
	-- comes to rest instead of creeping toward the target forever and rewriting
	-- two properties every frame of a parked car.
	if math.abs(target - shown) < 0.05 then
		shown = target
	end
	self.shownMph = shown

	-- Capped at three digits for the label only. The needle clamps separately in
	-- _paintSweep, so a vehicle above the dial's range parks the needle at the end
	-- stop while the number keeps counting, exactly as a real cluster does.
	self:_setText(self.speed, tostring(math.min(math.floor(shown + 0.5), 999)))
	self:_paintSweep(shown / math.max(self.settings.TopSpeedMph, 1))

	-- The rev ring, on its own shorter time constant.
	local targetRpm = self.targetRpm
	if targetRpm == nil then
		self:_setTachoVisible(false)
	else
		self:_setTachoVisible(true)
		local shownRpm = self.shownRpm
		if shownRpm == nil then
			shownRpm = targetRpm
		end
		shownRpm += (targetRpm - shownRpm) * (1 - math.exp(-dt / TACHO_TAU))
		if math.abs(targetRpm - shownRpm) < 1 then
			shownRpm = targetRpm
		end
		self.shownRpm = shownRpm
		self:_paintTacho(shownRpm / math.max(self.settings.Redline, 1))
	end
end

-- Puts the needle where the vehicle already is, without sweeping to it.
--
-- Getting into a moving car should not show the needle winding up from zero: the
-- car was doing forty before the cluster appeared, and animating that is the
-- gauge lying about the first half second.
function SpeedometerController:_snapToSeat()
	self.targetMph = nil
	self.shownMph = nil
	self.targetRpm = nil
	self.shownRpm = nil
	-- Forces the next _setTachoVisible through, since the new vehicle may not have
	-- a tachometer where the last one did.
	self.tachoVisible = nil
	self.tachoLit = nil
end

function SpeedometerController:_setText(item: TextLabel, text: string)
	if item.Text ~= text then
		item.Text = text
	end
end

-- Lights the sweep to a fraction of its length, warming through amber to red as
-- it fills.
--
-- The thresholds are speeds, not fractions of the dial. They were 0.68 and 0.86
-- of top speed -- amber at 95mph, red at 120 -- which is a rev counter's logic
-- applied to a speedometer: a redline marks a mechanical limit and a speedometer
-- has none, so the colours meant nothing. Now amber is the national speed limit,
-- above which the driver is speeding wherever they happen to be, and red is where
-- a traffic stop stops being a ticket.
function SpeedometerController:_paintSweep(fraction: number)
	local count = #self.segments
	local lit = math.clamp(math.floor(fraction * count + 0.5), 0, count)
	local top = math.max(self.settings.TopSpeedMph, 1)
	-- The same thresholds expressed as positions along the sweep, so a tick and
	-- the needle cannot disagree about where amber starts.
	local warnAt = self.settings.WarnAboveMph / top
	local dangerAt = self.settings.DangerAboveMph / top
	-- The needle moves before the early exit below, and follows the true fraction
	-- rather than the lit tick count. Behind that exit it would only move when a
	-- whole tick lit, which is the one thing a needle must not do: a dial that
	-- jumps in twenty second steps reads worse than the bar it replaced.
	self.needle.Rotation = SWEEP_START + SWEEP_ARC * math.clamp(fraction, 0, 1)
	self.needleArm.BackgroundColor3 = if fraction > dangerAt
		then C.Danger
		elseif fraction > warnAt then C.Warn
		else C.Live
	if lit == self.lit then
		return
	end
	self.lit = lit
	for index, segment in self.segments do
		if index > lit then
			-- Unlit, not Track. Track is the darker "system not fitted" grey, and
			-- painting the unswept half of the dial with it undid the daylight
			-- legibility fix the moment the first sample arrived: the ticks were
			-- built light and then immediately repainted dark here.
			segment.BackgroundColor3 = C.Unlit
		elseif index > count * dangerAt then
			segment.BackgroundColor3 = C.Danger
		elseif index > count * warnAt then
			segment.BackgroundColor3 = C.Warn
		else
			segment.BackgroundColor3 = C.Live
		end
	end
end

-- The chassis's own gauge, removed wherever it turns up.
--
-- The spawner already takes this frame out of the vehicle, and that ought to be
-- the end of it. It is done again here because the kit hands its interface to the
-- driver at seat time and the two are not reliably ordered: whichever copy the
-- client ends up holding, this catches it. Destroyed rather than hidden -- hiding
-- was the old workaround and it left the script behind it running, writing a
-- needle and a speed into an invisible frame for the whole drive.
local STOCK_GAUGE_FRAMES = { "AC6_Stock_Gauges", "AC6C_Style_Gauges", "FH5_Gauge" }

function SpeedometerController:_stripStockGauges()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiObject") and table.find(STOCK_GAUGE_FRAMES, descendant.Name) then
			descendant:Destroy()
		end
	end
end

function SpeedometerController:_watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	table.insert(
		self.connections,
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			self.seat = if humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat")
				then humanoid.SeatPart
				else nil
			self.frame.Visible = self.seat ~= nil
			-- Deferred, because the kit parents its interface after the seat change.
			if self.seat then
				self:_stripStockGauges()
				task.delay(0.4, function()
					self:_stripStockGauges()
				end)
				task.delay(1.5, function()
					self:_stripStockGauges()
				end)
			end
			-- Discards the previous vehicle's needle position, so the first sample
			-- in this one is adopted rather than swept to.
			self:_snapToSeat()
			-- The chassis's own gauge strip used to be hidden here on the way in and
			-- put back on the way out, because it parented a second speedometer into
			-- the driver's PlayerGui reading the same number in a different typeface.
			-- The spawner now removes that frame from the vehicle outright, so there
			-- is nothing left to hide and the script behind it is no longer running.
		end)
	)
end

function SpeedometerController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Speedometer", function(layout)
		local touch = layout.InputMode == "Touch"
		local compactTouch = touch and layout.Compact
		self.frameScale.Scale = if compactTouch
			then math.min(layout.HudScale, 0.62)
			else layout.HudScale
		self.frame.AnchorPoint = Vector2.new(0.5, 1)
		-- Sits directly above the equipped tools.
		--
		-- This used to measure from HotbarBottom, which a vehicle inflates to 112 to
		-- clear the driving pedals. The pedals are touch-only, so on a desktop that
		-- reserve protects nothing: the cluster hung about fifty pixels above the
		-- tools with a band of empty screen beneath it. ToolbarBottom is the tools
		-- bar on its own, so the gap below the dial is now the ten pixels intended
		-- rather than ten plus a reserve for controls that were never drawn.
		--
		-- Touch still measures from HotbarBottom and adds the pedal height, because
		-- there the controls genuinely are on screen. Every touch device, not just
		-- the compact ones -- a tablet has pedals too, and the old test sent it down
		-- the desktop path and put the cluster underneath them.
		--
		-- UIScale pivots about the AnchorPoint, not the authored origin, so the
		-- anchored bottom edge stays put at any scale and needs no compensation.
		-- The previous code compensated anyway, which pushed compact screens too
		-- high by however much the scale differed from one.
		local bottomGap = if touch
			then layout.HotbarBottom + Config.DrivingControls.PedalSize + 24
			else layout.ToolbarBottom + 10
		self.frame.Position = UDim2.new(0.5, 0, 1, -bottomGap)
		-- One authored size, scaled by the interface factor, rather than a second
		-- set of measurements for compact screens that has to be kept in step.
		self.frame.Size = UDim2.fromOffset(CLUSTER_SIZE.X, CLUSTER_SIZE.Y)
	end)
	local player = Players.LocalPlayer
	if player.Character then
		self:_watch(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self.seat = nil
			self.frame.Visible = false
			self:_watch(character)
		end)
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(dt)
			local seat = self.seat
			if not seat then
				return
			end
			-- Every frame, regardless of whether the chassis was read this one. The
			-- needle's smoothness is the whole point of the split.
			self:_animate(dt)

			self.accumulator += dt
			if self.accumulator < SAMPLE_INTERVAL then
				return
			end
			-- Subtracted rather than zeroed, so a long frame does not throw away the
			-- overshoot and slowly drift the sample rate.
			self.accumulator -= SAMPLE_INTERVAL
			local values = self:_chassisValues(seat)
			-- Unrounded, and only a target. The animation step below owns what is
			-- actually drawn; rounding here would quantise the needle to whole mph
			-- and put back a coarser version of the stepping this replaced.
			self.targetMph = speedMph(seat, values)
			-- nil rather than zero where the chassis reports nothing, so the ring can
			-- tell "no tachometer fitted" apart from "engine idling".
			local rpm = readValue(values, self.settings.RpmValueName)
			self.targetRpm = if type(rpm) == "number" then math.max(rpm, 0) else nil

			-- The chassis knows its own gear, including reverse and each ratio,
			-- which throttle direction alone cannot tell apart. Fall back to
			-- throttle only where no chassis is present.
			local gear = readValue(values, self.settings.GearValueName)
			self:_setText(
				self.gear,
				if type(gear) == "number"
					then (if gear < 0 then "R" elseif gear == 0 then "N" else tostring(gear))
					elseif type(gear) == "string" and gear ~= "" then gear
					else (if seat.ThrottleFloat < -0.05
						then "R"
						elseif math.abs(seat.ThrottleFloat) > 0.05 then "D"
						else "N")
			)

			-- An unregistered vehicle shows nothing rather than a placeholder.
			-- "NO PLATE" reads as a fault the driver ought to do something about,
			-- when it only means this car was not spawned through the framework.
			local registration = seat:GetAttribute("RoleplayOSRegistration")
			-- Walked all the way up, like the fuel reading beneath. The odometer is
			-- written on the vehicle model and a seat is often two or three levels
			-- inside it, so checking only the seat and its immediate parent found
			-- nothing on exactly the vehicles that keep their seat in a subassembly.
			local mileage = ancestorAttribute(seat, "RoleplayOSMileage")
			local plated = type(registration) == "string" and registration ~= ""
			self.plate.Visible = plated
			if plated then
				self:_setText(
					self.plate,
					if type(mileage) == "number"
						then string.format("%s  ·  %.1f MI", registration, mileage)
						else registration :: string
				)
			end

			-- RoleplayOS fuel is authoritative. Existing authoring vehicles can
			-- still expose a chassis value for display; if neither exists the gauge
			-- reads unknown rather than silently disappearing.
			--
			-- Skipped entirely where the game has no fuel system, because then the
			-- strip was never built and there is nothing to write to.
			if FUEL_ENABLED then
				local fuel = ancestorAttribute(seat, "RoleplayOSFuel")
				if type(fuel) ~= "number" then
					for _, name in self.settings.FuelValueNames or {} do
						fuel = ancestorAttribute(seat, name)
						if type(fuel) == "number" then
							break
						end
					end
				end
				if type(fuel) ~= "number" then
					fuel = readFirstValue(values, self.settings.FuelValueNames)
				end
				self.fuelTrack.Visible = true
				self.fuelMark.Visible = true
				if type(fuel) == "number" then
					local level = fuel :: number
					if level >= 0 and level <= 1 then
						level *= 100
					end
					self:_setText(
						self.fuelMark,
						string.format("FUEL %d%%", math.floor(level + 0.5))
					)
					self.fuelFill.Size = UDim2.fromScale(math.clamp(level / 100, 0, 1), 1)
					self.fuelFill.BackgroundColor3 = if level <= 10
						then C.Danger
						elseif level <= 25 then C.Warn
						else C.Fuel
				else
					self:_setText(self.fuelMark, "FUEL --")
					self.fuelFill.Size = UDim2.fromScale(0, 1)
					self.fuelFill.BackgroundColor3 = C.Muted
				end
			end

			local handbrakeState = ancestorAttribute(seat, "RoleplayOSHandbrake")
			if handbrakeState == nil then
				for _, name in self.settings.HandbrakeValueNames or {} do
					handbrakeState = ancestorAttribute(seat, name)
					if handbrakeState ~= nil then
						break
					end
				end
			end
			if handbrakeState == nil then
				handbrakeState = readFirstValue(values, self.settings.HandbrakeValueNames)
			end
			local handbrakeOn = readsOn(handbrakeState)
			local handbrakeColour = if handbrakeOn then C.Danger else C.Muted
			self.handbrake.TextColor3 = handbrakeColour
			self.handbrakeStroke.Color = handbrakeColour

			-- Fitted, and intervening. Read straight from the chassis, so a vehicle
			-- that publishes neither leaves both lamps dark rather than pretending.
			-- Takes only the glyph now. The badge frame it used to fill is a bare
			-- container with nothing to paint.
			local function telltaleState(
				mark: TextLabel,
				fittedNames: { string },
				activeNames: { string }
			)
				local fitted = readsOn(readFirstValue(values, fittedNames))
				local active = readsOn(readFirstValue(values, activeNames))
				-- Only the glyph changes. Filling the box behind it was what made an
				-- intervening system look like a pressed button.
				mark.TextColor3 = if active then C.Warn elseif fitted then C.Muted else C.Track
				mark.TextTransparency = if active then 0 elseif fitted then 0.15 else 0.55
			end
			telltaleState(self.abs, self.settings.AbsValueNames, self.settings.AbsActiveValueNames)
			telltaleState(self.tcs, self.settings.TcsValueNames, self.settings.TcsActiveValueNames)

			-- The lighting addon's lamps.
			--
			-- Read straight off the BoolValues its own handler writes, so the cluster
			-- follows the indicators the driver is actually using rather than a second
			-- set of state that could disagree with the lamps on the car.
			local vehicle = seat:FindFirstAncestorOfClass("Model")
			local paths = self.settings.LightStatePaths
			local function lamp(mark: TextLabel, state: boolean?, lit: Color3)
				-- nil means this vehicle has no such lamp. Dark and fully faded, which
				-- is different from fitted-but-off: a van with a different lighting kit
				-- should not show a headlight tell-tale it cannot drive.
				if state == nil then
					mark.TextColor3 = C.Track
					mark.TextTransparency = 0.72
					return
				end
				mark.TextColor3 = if state then lit else C.Muted
				mark.TextTransparency = if state then 0 else 0.5
			end

			-- Hazards drive both arrows, because that is what pressing them does.
			local hazards = readPath(vehicle, paths.Hazards) == true
			lamp(
				self.indicatorLeft,
				if hazards then true else readPath(vehicle, paths.IndicatorLeft),
				C.Indicator
			)
			lamp(
				self.indicatorRight,
				if hazards then true else readPath(vehicle, paths.IndicatorRight),
				C.Indicator
			)
			lamp(self.headlight, readPath(vehicle, paths.Headlight), C.Indicator)
			lamp(self.mainBeam, readPath(vehicle, paths.MainBeam), C.Beam)
		end)
	)
end

function SpeedometerController:Destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
end
return SpeedometerController
