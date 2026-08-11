--!strict

-- Throttle and brake pedals for touch players.
--
-- Roblox gives a touch driver the same thumbstick it gives a pedestrian, which
-- steers and accelerates on one control and cannot hold full throttle while
-- steering. These are separate pedals, so a phone player can do both at once.
--
-- Reliability across chassis forks is the difficulty here, since they disagree
-- on where input is read. Rather than detecting which fork this is, the pedals
-- satisfy both contracts at once: the seat's own throttle, which Roblox and
-- most chassis read, and the chassis's own input value where one exists. The
-- value is written every frame while a pedal is held, because Roblox's control
-- module writes the same property from the thumbstick and the last write in a
-- frame wins.
--
-- Where neither contract reaches the chassis the pedals cannot work, and that
-- is reported rather than left as a silent dead control.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local DrivingControlsController = {
	connections = {},
	throttle = 0,
	-- Weak keyed, so a destroyed vehicle does not keep its seat alive here.
	valuesBySeat = setmetatable({}, { __mode = "k" }),
}

local function pedal(parent: Instance, name: string, glyph: string, colour: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.AutoButtonColor = false
	item.BackgroundColor3 = colour
	item.BackgroundTransparency = 0.25
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = glyph
	item.TextColor3 = Color3.fromRGB(240, 245, 252)
	item.TextSize = 14
	item.Visible = false
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = item
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(86, 108, 140)
	stroke.Transparency = 0.4
	stroke.Parent = item
	local grooves = Instance.new("Frame")
	grooves.Name = "PedalGrooves"
	grooves.AnchorPoint = Vector2.new(0.5, 0)
	grooves.BackgroundTransparency = 1
	grooves.Position = UDim2.new(0.5, 0, 0, 13)
	grooves.Size = UDim2.new(0.62, 0, 0, 34)
	grooves.Parent = item
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 5)
	list.Parent = grooves
	for _ = 1, 4 do
		local ridge = Instance.new("Frame")
		ridge.BackgroundColor3 = Color3.fromRGB(210, 220, 232)
		ridge.BackgroundTransparency = 0.35
		ridge.BorderSizePixel = 0
		ridge.Size = UDim2.new(1, 0, 0, 3)
		ridge.Parent = grooves
		Instance.new("UICorner", ridge).CornerRadius = UDim.new(1, 0)
	end
	return item
end

function DrivingControlsController:Init(context: any)
	self.context = context
	self.settings = Config.DrivingControls
	self.chassis = Config.Chassis
	self.heldFor = 0
end

function DrivingControlsController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSDrivingControls"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	-- Above the ambient display, below any device the player opens: a pedal
	-- must not sit over the terminal while it is being read.
	gui.DisplayOrder = 12
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	self.accelerate = pedal(gui, "Accelerate", "ACCEL", Color3.fromRGB(30, 92, 56))
	self.brake = pedal(gui, "Brake", "BRAKE", Color3.fromRGB(104, 40, 46))
	self.accelerate.TextYAlignment = Enum.TextYAlignment.Bottom
	self.brake.TextYAlignment = Enum.TextYAlignment.Bottom
	self.accelerate.TextStrokeTransparency = 0.65
	self.brake.TextStrokeTransparency = 0.65

	-- Roblox replaces its normal mobile jump control while a humanoid occupies a
	-- VehicleSeat. Provide an explicit, familiar exit control so a touch player
	-- is never trapped in a car. The server-replicated restraint attribute is the
	-- sole exception: a cuffed detainee cannot use this to escape transport.
	self.exit = pedal(gui, "ExitVehicle", "EXIT", Color3.fromRGB(34, 48, 68))
	self.exit.TextSize = 13
	table.insert(
		self.connections,
		self.exit.Activated:Connect(function()
			local player = Players.LocalPlayer
			if player:GetAttribute("RoleplayOSCuffed") == true then
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.SeatPart then
				humanoid.Sit = false
				humanoid.Jump = true
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	)

	local scale = Instance.new("UIScale")
	scale.Parent = gui
	self.scale = scale

	self:_bindPedal(self.accelerate, 1)
	self:_bindPedal(self.brake, -1)
end

-- Held rather than tapped, so a pedal releases when the finger lifts anywhere
-- rather than leaving the vehicle accelerating.
function DrivingControlsController:_bindPedal(button: TextButton, direction: number)
	local function press(inputObject: InputObject)
		if
			inputObject.UserInputType == Enum.UserInputType.Touch
			or inputObject.UserInputType == Enum.UserInputType.MouseButton1
		then
			self.throttle = direction
			button.BackgroundTransparency = 0.05
		end
	end
	local function release(inputObject: InputObject)
		if
			inputObject.UserInputType == Enum.UserInputType.Touch
			or inputObject.UserInputType == Enum.UserInputType.MouseButton1
		then
			if self.throttle == direction then
				self.throttle = 0
			end
			button.BackgroundTransparency = 0.25
		end
	end
	table.insert(self.connections, button.InputBegan:Connect(press))
	table.insert(self.connections, button.InputEnded:Connect(release))
end

function DrivingControlsController:_seat(): VehicleSeat?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return if seat and seat:IsA("VehicleSeat") and seat.Occupant == humanoid then seat else nil
end

-- Finds the chassis input values, wherever in the vehicle they are kept.
--
-- This looked in exactly two places: on the seat, and on the seat's immediate
-- parent. That is enough only when the seat is a direct child of the vehicle,
-- which is true of the bike and not of the cars -- their seat hangs off a Body
-- folder, so the parent searched was Body and the values one level above it were
-- never found. The pedals then wrote a throttle nobody read, and a phone player
-- could sit in a car and go nowhere while the same pedals worked on a bike.
--
-- Resolved from the whole vehicle now: walk up to the model the seat belongs to
-- and search it, so the layout of the fork stops mattering. Cached per seat
-- because this runs on every frame the pedal is held and a recursive search of a
-- two-hundred-part car is not something to repeat sixty times a second.
function DrivingControlsController:_values(seat: VehicleSeat): Instance?
	local cached = self.valuesBySeat[seat]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		if (cached :: Instance).Parent then
			return cached :: Instance
		end
	end
	local name = self.chassis.ValuesFolderName
	local found: Instance? = seat:FindFirstChild(name)
	if not found then
		-- The outermost model the seat sits inside, which is the vehicle.
		local root: Instance = seat
		while root.Parent and root.Parent ~= workspace do
			root = root.Parent
		end
		if root ~= seat then
			found = root:FindFirstChild(name, true)
		end
	end
	self.valuesBySeat[seat] = found or false
	return found
end

-- Both input contracts are satisfied rather than betting on one. A chassis
-- either reads the seat's throttle or keeps its own input values; writing both
-- costs nothing and removes the need to know which fork this is. A chassis that
-- writes its own values every frame simply overwrites ours, which is harmless.
-- Writes one value if the chassis keeps one by that name.
local function write(values: Instance, name: string, value: number)
	local target = values:FindFirstChild(name)
	if target and target:IsA("ValueBase") then
		(target :: any).Value = value
	end
end

function DrivingControlsController:_apply(seat: VehicleSeat, throttle: number)
	-- A dry tank is nought throttle whatever the pedal says. The server has
	-- already cut the engine and zeroed the seat, and this closes the last route
	-- in: the touch pedals write the chassis's input value directly, so without
	-- it a phone player could still drive a car with no fuel in it.
	local fuel = seat:GetAttribute("RoleplayOSFuel")
	if type(fuel) == "number" and fuel <= 0 then
		throttle = 0
	end
	seat.ThrottleFloat = throttle
	local values = self:_values(seat)
	if not values then
		return
	end
	write(values, self.chassis.ThrottleValueName, throttle)
	-- Steering is mirrored from the seat rather than from a control of ours,
	-- because we do not draw one: turning comes from Roblox's own thumbstick on a
	-- phone, from A and D on a keyboard, and from a stick on a gamepad, and all
	-- three land on VehicleSeat.Steer. A chassis that keeps its own steering value
	-- never saw any of them, so a car could be given throttle from our pedals and
	-- still not turn. Names default here rather than in the configuration so this
	-- works on a fork nobody has written an entry for yet.
	write(values, self.chassis.SteerValueName or "Steer", seat.Steer)
end

-- A pedal held with no change in speed means the chassis takes its input
-- somewhere neither contract reaches. That is a property of the fork, not
-- something the player can act on, so it is reported once to the log for
-- whoever is fitting the chassis rather than shown on screen.
function DrivingControlsController:_watchForNoResponse(seat: VehicleSeat, delta: number)
	if self.reported then
		return
	end
	local speed = seat.AssemblyLinearVelocity.Magnitude
	if speed > 4 then
		self.reported = true
		return
	end
	self.heldFor = (self.heldFor or 0) + delta
	if self.heldFor < self.settings.NoResponseSeconds then
		return
	end
	self.reported = true
	warn(
		"RoleplayOS driving pedals produced no movement: this chassis reads input "
			.. "elsewhere, so set DrivingControls.Enabled to false and use its own "
			.. "touch controls, or point ThrottleValueName at the value it reads."
	)
end

function DrivingControlsController:Start()
	self:_mount()
	if not self.settings.Enabled then
		return
	end
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"DrivingControls",
		function(layout)
			-- Only a touch driver needs pedals; a keyboard or pad already has
			-- them, and a passenger is not driving.
			local shown = self.settings.Enabled
				and layout.InputMode == "Touch"
				and layout.State == "Driver"
			self.accelerate.Visible = shown
			self.brake.Visible = shown
			self.exit.Visible = layout.InputMode == "Touch"
				and layout.Vehicle
				and Players.LocalPlayer:GetAttribute("RoleplayOSCuffed") ~= true
			self.scale.Scale = layout.HudScale
			local size = self.settings.PedalSize
			local pedalWidth = math.floor(size * 0.7)
			local pedalHeight = size
			local hotbarHalfWidth = if layout.Compact then 82 else 118
			local bottom = layout.SafeBottom + 12
			-- The hotbar is the fixed centre reference: brake immediately to its
			-- left, accelerator immediately to its right. This remains symmetrical
			-- on phones regardless of a notch or Roblox's thumbstick safe region.
			self.accelerate.Size = UDim2.fromOffset(pedalWidth, pedalHeight)
			self.brake.Size = UDim2.fromOffset(pedalWidth, pedalHeight)
			self.accelerate.AnchorPoint = Vector2.new(0, 1)
			self.brake.AnchorPoint = Vector2.new(1, 1)
			self.accelerate.Position = UDim2.new(0.5, hotbarHalfWidth, 1, -bottom)
			self.brake.Position = UDim2.new(0.5, -hotbarHalfWidth, 1, -bottom)
			self.exit.Size = UDim2.fromOffset(58, 58)
			self.exit.AnchorPoint = Vector2.new(0, 1)
			self.exit.Position = UDim2.new(
				0.5,
				hotbarHalfWidth + math.floor((pedalWidth - 58) / 2),
				1,
				-(bottom + pedalHeight + 10)
			)
		end
	)
	table.insert(
		self.connections,
		Players.LocalPlayer:GetAttributeChangedSignal("RoleplayOSCuffed"):Connect(function()
			local layout = self.context.Controllers.UIOrchestrator:GetLayout()
			self.exit.Visible = layout.InputMode == "Touch"
				and layout.Vehicle
				and Players.LocalPlayer:GetAttribute("RoleplayOSCuffed") ~= true
		end)
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(delta)
			-- Runs whenever seated, not only while one of our pedals is down.
			--
			-- It used to give up immediately unless our own touch pedal was held,
			-- which meant the bridge into the chassis existed for that pedal and
			-- for nothing else. Every other way of driving -- the keyboard, a
			-- gamepad, Roblox's own touch thumbstick -- sets the seat's throttle
			-- and steering and was never carried across, so a chassis keeping its
			-- input in its own values folder ignored all of them.
			--
			-- Whoever is not seated still pays only a seat lookup per frame, and a
			-- driver pays two value writes on top, which is nothing next to what
			-- the chassis itself does each step.
			local seat = self:_seat()
			if not seat then
				self.throttle = 0
				self.heldFor = 0
				return
			end
			-- Our pedal wins while it is held; otherwise take whatever the device
			-- the player is actually using has put on the seat.
			local throttle = if self.throttle ~= 0 then self.throttle else seat.Throttle
			self:_apply(seat, throttle)
			if throttle == 0 then
				self.heldFor = 0
			else
				self:_watchForNoResponse(seat, delta)
			end
		end)
	)
end

function DrivingControlsController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return DrivingControlsController
