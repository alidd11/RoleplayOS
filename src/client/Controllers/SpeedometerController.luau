--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

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
	frame.Size = UDim2.fromOffset(272, 108)
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

	-- A segmented sweep rather than a needle. Roblox has no arc primitive, and a
	-- bar of discrete segments is both honest about that and closer to the
	-- instrument clusters modern cars actually ship.
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.BackgroundTransparency = 1
	sweep.Position = UDim2.fromOffset(16, 12)
	sweep.Size = UDim2.new(1, -32, 0, 6)
	sweep.Parent = frame
	local sweepLayout = Instance.new("UIListLayout")
	sweepLayout.FillDirection = Enum.FillDirection.Horizontal
	sweepLayout.Padding = UDim.new(0, 2)
	sweepLayout.Parent = sweep
	self.segments = {}
	local count = self.settings.SweepSegments
	for index = 1, count do
		local segment = Instance.new("Frame")
		segment.BackgroundColor3 = C.Track
		segment.BorderSizePixel = 0
		segment.LayoutOrder = index
		segment.Size = UDim2.new(1 / count, -2, 1, 0)
		segment.Parent = sweep
		Instance.new("UICorner", segment).CornerRadius = UDim.new(0, 2)
		self.segments[index] = segment
	end

	local speed = label(frame, Enum.Font.RobotoMono, 44, C.Text)
	speed.Name = "Speed"
	speed.Text = "0"
	speed.Position = UDim2.fromOffset(16, 22)
	speed.Size = UDim2.fromOffset(132, 50)
	speed.TextXAlignment = Enum.TextXAlignment.Right
	self.speed = speed

	local unit = label(frame, Enum.Font.GothamBold, 12, C.Muted)
	unit.Text = "MPH"
	unit.Position = UDim2.fromOffset(154, 44)
	unit.Size = UDim2.fromOffset(46, 16)
	unit.TextXAlignment = Enum.TextXAlignment.Left

	-- Gear badge, as a cluster shows the selected gear rather than spelling it.
	local gearBadge = Instance.new("Frame")
	gearBadge.Name = "Gear"
	gearBadge.AnchorPoint = Vector2.new(1, 0)
	gearBadge.Position = UDim2.new(1, -16, 0, 26)
	gearBadge.Size = UDim2.fromOffset(44, 44)
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
	plate.Position = UDim2.fromOffset(16, 80)
	plate.Size = UDim2.fromOffset(150, 14)
	plate.TextXAlignment = Enum.TextXAlignment.Left
	self.plate = plate

	local fuelTrack = Instance.new("Frame")
	fuelTrack.Name = "Fuel"
	fuelTrack.AnchorPoint = Vector2.new(1, 0)
	fuelTrack.Position = UDim2.new(1, -16, 0, 82)
	fuelTrack.Size = UDim2.fromOffset(90, 8)
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
	fuelMark.Position = UDim2.new(1, -110, 0, 79)
	fuelMark.Size = UDim2.fromOffset(34, 14)
	fuelMark.TextXAlignment = Enum.TextXAlignment.Right

	self.gui, self.frame = gui, frame
	-- Ambient display, scaled with the rest of it so the readout keeps its
	-- proportions on a phone as well as a large monitor.
	local frameScale = Instance.new("UIScale")
	frameScale.Parent = frame
	self.frameScale = frameScale
end

-- Lights the sweep to a fraction of its length, warming through amber to red as
-- it fills, the way a cluster shades its upper range.
function SpeedometerController:_paintSweep(fraction: number)
	local count = #self.segments
	local lit = math.clamp(math.floor(fraction * count + 0.5), 0, count)
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
		self.frame.Position = UDim2.new(0.5, 0, 1, -(layout.HotbarBottom + 8))
		-- One authored size, scaled by the interface factor, rather than a second
		-- set of measurements for compact screens that has to be kept in step.
		self.frame.Size = UDim2.fromOffset(272, 108)
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
			self.speed.Text = tostring(math.min(mph, 999))

			-- The chassis knows its own gear, including reverse and each ratio,
			-- which throttle direction alone cannot tell apart. Fall back to
			-- throttle only where no chassis is present.
			local values = self:_chassisValues(seat)
			local gear = readValue(values, self.settings.GearValueName)
			self.gear.Text = if type(gear) == "number"
				then (if gear < 0 then "R" elseif gear == 0 then "N" else tostring(gear))
				elseif type(gear) == "string" and gear ~= "" then gear
				else (if seat.ThrottleFloat < -0.05
					then "R"
					elseif math.abs(seat.ThrottleFloat) > 0.05 then "D"
					else "N")
			self.plate.Text = tostring(seat:GetAttribute("RoleplayOSRegistration") or "NO PLATE")

			-- The sweep follows engine speed where the chassis reports it, since
			-- that is what a cluster shows, and road speed otherwise.
			local rpm = readValue(values, self.settings.RpmValueName)
			self:_paintSweep(
				if type(rpm) == "number" and rpm > 0
					then rpm / math.max(self.settings.Redline, 1)
					else mph / math.max(self.settings.TopSpeedMph, 1)
			)

			local fuel = seat:GetAttribute("RoleplayOSFuel")
			if type(fuel) == "number" then
				self.fuelFill.Size = UDim2.fromScale(math.clamp(fuel / 100, 0, 1), 1)
				self.fuelFill.BackgroundColor3 = if fuel <= 10
					then Color3.fromRGB(247, 92, 96)
					elseif fuel <= 25 then Color3.fromRGB(245, 176, 66)
					else Color3.fromRGB(104, 205, 148)
			else
				self.fuelFill.Size = UDim2.fromScale(0, 1)
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
