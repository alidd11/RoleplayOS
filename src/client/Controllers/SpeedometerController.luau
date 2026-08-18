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
local CLUSTER_SIZE = Vector2.new(300, 222)

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
local DIAL_CENTRE = Vector2.new(150, 112)
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

-- Majors every third tick. With the sweep divided into 22, that lands them on 0,
-- 20, 40 ... 140, which is a UK speedometer's face rather than an arbitrary
-- division of whatever top speed the chassis claims.
local MAJOR_EVERY = 3
local NUMERAL_RADIUS = DIAL_RADIUS - 30

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
	local TELLTALE_Y = DIAL_CENTRE.Y + 64
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
	self.abs = telltale("ABS", "ABS", DIAL_CENTRE.X - 52, 12)
	self.tcs = telltale("TCS", "TC", DIAL_CENTRE.X + 52, 12)

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

	-- Fuel, as a strip under the dial. Short, square-ended and grey: a wide bright
	-- green pill is a health bar, and a car's fuel gauge is neither wide nor green
	-- until it is nearly empty.
	local fuelTrack = Instance.new("Frame")
	fuelTrack.Name = "Fuel"
	fuelTrack.AnchorPoint = Vector2.new(0.5, 0.5)
	fuelTrack.Position = UDim2.fromOffset(DIAL_CENTRE.X, 196)
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
	fuelMark.Position = UDim2.fromOffset(DIAL_CENTRE.X, 210)
	fuelMark.Size = UDim2.fromOffset(170, 12)
	fuelMark.TextXAlignment = Enum.TextXAlignment.Center
	self.fuelTrack, self.fuelMark = fuelTrack, fuelMark

	self.gui, self.frame = gui, frame
	-- Ambient display, scaled with the rest of it so the readout keeps its
	-- proportions on a phone as well as a large monitor.
	local frameScale = Instance.new("UIScale")
	frameScale.Parent = frame
	self.frameScale = frameScale
end

function SpeedometerController:_setText(item: TextLabel, text: string)
	if item.Text ~= text then
		item.Text = text
	end
end

-- Lights the sweep to a fraction of its length, warming through amber to red as
-- it fills, the way a cluster shades its upper range.
function SpeedometerController:_paintSweep(fraction: number)
	local count = #self.segments
	local lit = math.clamp(math.floor(fraction * count + 0.5), 0, count)
	-- The needle moves before the early exit below, and follows the true fraction
	-- rather than the lit tick count. Behind that exit it would only move when a
	-- whole tick lit, which is the one thing a needle must not do: a dial that
	-- jumps in twenty second steps reads worse than the bar it replaced.
	self.needle.Rotation = SWEEP_START + SWEEP_ARC * math.clamp(fraction, 0, 1)
	self.needleArm.BackgroundColor3 = if fraction > 0.86
		then C.Danger
		elseif fraction > 0.68 then C.Warn
		else C.Live
	if lit == self.lit then
		return
	end
	self.lit = lit
	for index, segment in self.segments do
		if index > lit then
			segment.BackgroundColor3 = C.Track
		elseif index > count * 0.86 then
			segment.BackgroundColor3 = C.Danger
		elseif index > count * 0.68 then
			segment.BackgroundColor3 = C.Warn
		else
			segment.BackgroundColor3 = C.Live
		end
	end
end

-- The chassis's own gauge, which it hands to the driver whether or not the game
-- already has one.
--
-- A-Chassis carries a frame called AC6_Stock_Gauges holding a tacho, a speedo, a
-- gear readout and a Speed button, and parents it into the driver's PlayerGui on
-- mounting. So an officer got two speedometers: this cluster, and the kit's own
-- strip along the bottom of the screen reading the same number in a different
-- typeface. Two readouts of one value is not a richer dashboard, it is a game
-- that looks like it was assembled rather than designed.
--
-- Hidden rather than destroyed, and only while this cluster is up, because the
-- frame belongs to the vehicle and its scripts keep writing to it. Put back the
-- moment the driver gets out, so nothing is permanently taken from the kit.
local STOCK_GAUGE_NAMES = { "AC6_Stock_Gauges", "Gauges_AC6", "DigitalGauges" }

function SpeedometerController:_setStockGaugesVisible(visible: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiObject") then
			for _, name in STOCK_GAUGE_NAMES do
				if descendant.Name == name then
					descendant.Visible = visible
					break
				end
			end
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
			local driving = self.seat ~= nil
			self.frame.Visible = driving
			-- Deferred on the way in, because the chassis parents its gauge after
			-- the seat changes and hiding it before it arrives does nothing.
			if driving then
				task.delay(0.35, function()
					if self.seat ~= nil then
						self:_setStockGaugesVisible(false)
					end
				end)
			else
				self:_setStockGaugesVisible(true)
			end
		end)
	)
end

function SpeedometerController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Speedometer", function(layout)
		local compactTouch = layout.InputMode == "Touch" and layout.Compact
		self.frameScale.Scale = if compactTouch
			then math.min(layout.HudScale, 0.62)
			else layout.HudScale
		self.frame.AnchorPoint = Vector2.new(0.5, 1)
		-- Clear of Roblox's toolbar rather than pinned to the bottom edge, which
		-- put the readout underneath the equipped tools. The needs bars move to
		-- the left while driving, so the bottom centre is free for this.
		-- UIScale changes the rendered footprint around the frame's authored
		-- origin. On compact touch screens compensate vertically so the visual
		-- bottom, rather than the unscaled 176px box, sits directly above the
		-- hotbar. X remains an exact 0.5 screen anchor.
		self.frame.Position = UDim2.new(
			0.5,
			0,
			1,
			-(if compactTouch then layout.SafeBottom + 86 else layout.HotbarBottom + 14)
		)
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
			self.accumulator += dt
			if self.accumulator < 0.08 then
				return
			end
			self.accumulator = 0
			local seat = self.seat
			if not seat then
				return
			end
			local values = self:_chassisValues(seat)
			local mph = math.floor(speedMph(seat, values) + 0.5)
			-- Assigned only on change. A property write replicates and dirties
			-- layout even when the value is identical, and at this refresh rate a
			-- car standing still would otherwise rewrite the whole cluster
			-- twelve times a second for nothing.
			self:_setText(self.speed, tostring(math.min(mph, 999)))

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
			local mileage = seat:GetAttribute("RoleplayOSMileage")
			if type(mileage) ~= "number" and seat.Parent then
				mileage = seat.Parent:GetAttribute("RoleplayOSMileage")
			end
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

			-- Road speed, always.
			--
			-- This used to prefer engine speed wherever the chassis published it,
			-- falling back to road speed only on a vehicle that reported no RPM. That
			-- was defensible while the arc was an unlabelled sweep, because an
			-- unlabelled arc means whatever you say it means.
			--
			-- It is not defensible now. The dial's face is printed 0, 20, 40 ... 140
			-- and those numerals are generated from TopSpeedMph, so a needle driven by
			-- rpm/Redline points at "80" while the van is doing thirty. A gauge that
			-- disagrees with its own numbers is worse than no gauge, and every vehicle
			-- in this game is A-Chassis, which does publish RPM -- so that was the
			-- normal case, not the edge case. The tachometer this used to be belongs
			-- on a second dial, not on the one labelled MPH.
			self:_paintSweep(mph / math.max(self.settings.TopSpeedMph, 1))

			-- RoleplayOS fuel is authoritative. Existing authoring vehicles can
			-- still expose a chassis value for display; if neither exists the gauge
			-- remains visible as unknown rather than silently disappearing.
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
			local metered = type(fuel) == "number"
			self.fuelTrack.Visible = true
			self.fuelMark.Visible = true
			if metered then
				local level = fuel :: number
				if level >= 0 and level <= 1 then
					level *= 100
				end
				self:_setText(self.fuelMark, string.format("FUEL %d%%", math.floor(level + 0.5)))
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
