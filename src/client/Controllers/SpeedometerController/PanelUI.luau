--!strict
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local FUEL_ENABLED = Utils.FUEL_ENABLED
local CLUSTER_SIZE = Utils.CLUSTER_SIZE
local DIAL_CENTRE = Utils.DIAL_CENTRE
local DIAL_RADIUS = Utils.DIAL_RADIUS
local SWEEP_START = Utils.SWEEP_START
local SWEEP_ARC = Utils.SWEEP_ARC
local NEEDLE_INNER = Utils.NEEDLE_INNER
local NEEDLE_OUTER = Utils.NEEDLE_OUTER
local MAJOR_EVERY = Utils.MAJOR_EVERY
local NUMERAL_RADIUS = Utils.NUMERAL_RADIUS
local TACHO_OUTER = Utils.TACHO_OUTER
local TACHO_LENGTH = Utils.TACHO_LENGTH
local TACHO_SEGMENTS = Utils.TACHO_SEGMENTS
local C = Utils.C
local dialPoint = Utils.dialPoint
local label = Utils.label

return function(SpeedometerController)
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
		local function telltale(
			name: string,
			text: string,
			offsetX: number,
			size: number
		): TextLabel
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
end
