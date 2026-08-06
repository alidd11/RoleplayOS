--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

-- The cluster's geometry, in one place.
--
-- The size was written twice, once when the panel was built and again in the
-- layout binding, and the two disagreed the moment the dial needed a taller
-- panel: the binding reset it to the old height, so the dial centre sat below
-- the panel and the hub and the bottom of the needle rendered outside it.
local CLUSTER_SIZE = Vector2.new(320, 176)

-- A half dial rather than a full round one.
--
-- A car's rev counter sweeps past the horizontal and dips below its own centre,
-- which needs height this panel does not have without pushing the readout into
-- the hotbar. A semicircle spends all of its arc above the pivot, so the whole
-- gauge fits the space and every tick stays inside the panel.
--
-- Zero is straight up, so the sweep runs from due left to due right through the
-- top. Every part of the dial is placed from this centre and radius, so the
-- ticks, the needle and the hub cannot drift apart when one is adjusted.
local DIAL_CENTRE = Vector2.new(100, 138)
local DIAL_RADIUS = 74
local SWEEP_START = -90
local SWEEP_ARC = 180

local SpeedometerController = { connections = {}, seat = nil, accumulator = 0 }
function SpeedometerController:Init(context: any)
	self.context = context
	self.settings = Config.Chassis
end

-- The chassis publishes its live state in a folder of values. Searched under
-- the seat and then the vehicle model, because forks disagree on where it sits,
-- and absent entirely on a vehicle without a chassis.
function SpeedometerController:_chassisValues(seat: BasePart): Folder?
	local name = self.settings.ValuesFolderName
	local found = seat:FindFirstChild(name)
	if not found and seat.Parent then
		found = seat.Parent:FindFirstChild(name)
	end
	return if found and found:IsA("Folder") then found else nil
end

local function readValue(folder: Folder?, name: string): any?
	local item = if folder then folder:FindFirstChild(name) else nil
	return if item and item:IsA("ValueBase") then (item :: any).Value else nil
end

local C = {
	Panel = Color3.fromRGB(8, 12, 19),
	Track = Color3.fromRGB(28, 36, 48),
	Live = Color3.fromRGB(96, 178, 255),
	Warn = Color3.fromRGB(245, 176, 66),
	Danger = Color3.fromRGB(247, 92, 96),
	Text = Color3.fromRGB(244, 248, 252),
	Muted = Color3.fromRGB(138, 152, 172),
	Fuel = Color3.fromRGB(104, 205, 148),
}

local function label(parent: Instance, font: Enum.Font, size: number, colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = ""
	item.TextColor3 = colour
	item.TextSize = size
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
	frame.BackgroundColor3 = C.Panel
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 16)
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(46, 60, 80)
	edge.Transparency = 0.35
	edge.Parent = frame

	-- A round dial with a needle, built out of rotated frames.
	--
	-- Roblox has no arc primitive, so the arc is a ring of thin frames anchored
	-- at their base to the dial centre and rotated into place: rotation happens
	-- about the anchor point, so a frame as tall as the radius puts its far end
	-- exactly where the tick belongs. The needle is the same trick with one long
	-- frame.
	--
	-- This replaced a straight bar of segments. The bar was honest about the
	-- engine's limits and read as a progress bar rather than an instrument, and
	-- an instrument is the thing a driving game wants: you should be able to take
	-- the speed in from the needle's angle without reading the number.
	self.segments = {}
	local count = self.settings.SweepSegments
	for index = 1, count do
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
		spoke.Size = UDim2.fromOffset(3, DIAL_RADIUS * 2)
		spoke.Rotation = SWEEP_START + SWEEP_ARC * ((index - 1) / math.max(count - 1, 1))
		spoke.Parent = frame
		local mark = Instance.new("Frame")
		mark.BackgroundColor3 = C.Track
		mark.BorderSizePixel = 0
		mark.Size = UDim2.new(1, 0, 0, if index % 5 == 1 then 14 else 8)
		mark.Parent = spoke
		Instance.new("UICorner", mark).CornerRadius = UDim.new(1, 0)
		self.segments[index] = mark
	end

	-- Same construction as the ticks: a frame centred on the pivot, twice as long
	-- as the needle, with only its upper half drawn. Rotating it therefore swings
	-- the visible half out from the centre rather than about some other point.
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.BackgroundTransparency = 1
	needle.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y)
	needle.Size = UDim2.fromOffset(4, (DIAL_RADIUS - 14) * 2)
	needle.Rotation = SWEEP_START
	needle.ZIndex = 3
	needle.Parent = frame
	local needleArm = Instance.new("Frame")
	needleArm.Name = "Arm"
	needleArm.BackgroundColor3 = C.Live
	needleArm.BorderSizePixel = 0
	needleArm.Size = UDim2.fromScale(1, 0.5)
	needleArm.ZIndex = 3
	needleArm.Parent = needle
	Instance.new("UICorner", needleArm).CornerRadius = UDim.new(1, 0)
	self.needle, self.needleArm = needle, needleArm

	local hub = Instance.new("Frame")
	hub.Name = "Hub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.BackgroundColor3 = C.Track
	hub.BorderSizePixel = 0
	hub.Position = UDim2.fromOffset(DIAL_CENTRE.X, DIAL_CENTRE.Y)
	hub.Size = UDim2.fromOffset(14, 14)
	hub.ZIndex = 4
	hub.Parent = frame
	Instance.new("UICorner", hub).CornerRadius = UDim.new(1, 0)

	local speed = label(frame, Enum.Font.RobotoMono, 40, C.Text)
	speed.Name = "Speed"
	speed.Text = "0"
	speed.Position = UDim2.fromOffset(DIAL_CENTRE.X - 66, DIAL_CENTRE.Y - 62)
	speed.Size = UDim2.fromOffset(132, 42)
	speed.TextXAlignment = Enum.TextXAlignment.Center
	self.speed = speed

	local unit = label(frame, Enum.Font.GothamBold, 12, C.Muted)
	unit.Text = "MPH"
	unit.Position = UDim2.fromOffset(DIAL_CENTRE.X - 45, DIAL_CENTRE.Y - 17)
	unit.Size = UDim2.fromOffset(90, 14)
	unit.TextXAlignment = Enum.TextXAlignment.Center

	-- Gear badge, as a cluster shows the selected gear rather than spelling it.
	local gearBadge = Instance.new("Frame")
	gearBadge.Name = "Gear"
	gearBadge.AnchorPoint = Vector2.new(1, 0)
	gearBadge.Position = UDim2.new(1, -18, 0, 22)
	gearBadge.Size = UDim2.fromOffset(50, 50)
	gearBadge.BackgroundColor3 = C.Track
	gearBadge.BorderSizePixel = 0
	gearBadge.Parent = frame
	Instance.new("UICorner", gearBadge).CornerRadius = UDim.new(0, 11)
	local gear = label(gearBadge, Enum.Font.GothamBold, 22, C.Text)
	gear.Text = "N"
	gear.Size = UDim2.fromScale(1, 1)
	gear.TextXAlignment = Enum.TextXAlignment.Center
	self.gear = gear

	local plate = label(frame, Enum.Font.GothamMedium, 10, C.Muted)
	plate.Name = "Registration"
	plate.AnchorPoint = Vector2.new(1, 0)
	plate.Position = UDim2.new(1, -18, 0, 84)
	plate.Size = UDim2.fromOffset(108, 15)
	plate.TextXAlignment = Enum.TextXAlignment.Right
	self.plate = plate

	local fuelTrack = Instance.new("Frame")
	fuelTrack.Name = "Fuel"
	fuelTrack.AnchorPoint = Vector2.new(1, 0)
	fuelTrack.Position = UDim2.new(1, -18, 0, 128)
	fuelTrack.Size = UDim2.fromOffset(108, 9)
	fuelTrack.BackgroundColor3 = C.Track
	fuelTrack.BorderSizePixel = 0
	fuelTrack.Parent = frame
	Instance.new("UICorner", fuelTrack).CornerRadius = UDim.new(1, 0)
	local fuelFill = Instance.new("Frame")
	fuelFill.Name = "Fill"
	fuelFill.BackgroundColor3 = C.Fuel
	fuelFill.BorderSizePixel = 0
	fuelFill.Size = UDim2.fromScale(1, 1)
	fuelFill.Parent = fuelTrack
	Instance.new("UICorner", fuelFill).CornerRadius = UDim.new(1, 0)
	self.fuelFill = fuelFill
	local fuelMark = label(frame, Enum.Font.GothamBold, 9, C.Muted)
	fuelMark.Text = "FUEL"
	fuelMark.AnchorPoint = Vector2.new(1, 0)
	fuelMark.Position = UDim2.new(1, -18, 0, 108)
	fuelMark.Size = UDim2.fromOffset(108, 13)
	fuelMark.TextXAlignment = Enum.TextXAlignment.Right
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
		end)
	)
end

function SpeedometerController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Speedometer", function(layout)
		self.frameScale.Scale = layout.HudScale
		self.frame.AnchorPoint = Vector2.new(0.5, 1)
		-- Clear of Roblox's toolbar rather than pinned to the bottom edge, which
		-- put the readout underneath the equipped tools. The needs bars move to
		-- the left while driving, so the bottom centre is free for this.
		self.frame.Position = UDim2.new(0.5, 0, 1, -(layout.HotbarBottom + 14))
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
			local mph = math.floor(seat.AssemblyLinearVelocity.Magnitude * 0.626 + 0.5)
			-- Assigned only on change. A property write replicates and dirties
			-- layout even when the value is identical, and at this refresh rate a
			-- car standing still would otherwise rewrite the whole cluster
			-- twelve times a second for nothing.
			self:_setText(self.speed, tostring(math.min(mph, 999)))

			-- The chassis knows its own gear, including reverse and each ratio,
			-- which throttle direction alone cannot tell apart. Fall back to
			-- throttle only where no chassis is present.
			local values = self:_chassisValues(seat)
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

			-- The sweep follows engine speed where the chassis reports it, since
			-- that is what a cluster shows, and road speed otherwise.
			local rpm = readValue(values, self.settings.RpmValueName)
			self:_paintSweep(
				if type(rpm) == "number" and rpm > 0
					then rpm / math.max(self.settings.Redline, 1)
					else mph / math.max(self.settings.TopSpeedMph, 1)
			)

			-- A vehicle that reports no fuel level hides the gauge rather than
			-- drawing it empty. An empty bar labelled FUEL says the tank is dry,
			-- which is a different claim from "this car has no fuel system" and
			-- the one thing a driver would act on.
			local fuel = seat:GetAttribute("RoleplayOSFuel")
			local metered = type(fuel) == "number"
			self.fuelTrack.Visible = metered
			self.fuelMark.Visible = metered
			if metered then
				local level = fuel :: number
				self:_setText(self.fuelMark, string.format("FUEL %d%%", math.floor(level + 0.5)))
				self.fuelFill.Size = UDim2.fromScale(math.clamp(level / 100, 0, 1), 1)
				self.fuelFill.BackgroundColor3 = if level <= 10
					then C.Danger
					elseif level <= 25 then C.Warn
					else C.Fuel
			end
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
