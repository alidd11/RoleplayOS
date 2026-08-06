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

local DrivingControlsController = { connections = {}, throttle = 0 }

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
	item.TextSize = 22
	item.Visible = false
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = item
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(86, 108, 140)
	stroke.Transparency = 0.4
	stroke.Parent = item
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

	self.accelerate = pedal(gui, "Accelerate", "▲", Color3.fromRGB(30, 92, 56))
	self.brake = pedal(gui, "Brake", "▼", Color3.fromRGB(104, 40, 46))

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

-- Both input contracts are satisfied rather than betting on one. A chassis
-- either reads the seat's throttle or keeps its own input values; writing both
-- costs nothing and removes the need to know which fork this is. A chassis that
-- writes its own values every frame simply overwrites ours, which is harmless.
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
	local values = seat:FindFirstChild(self.chassis.ValuesFolderName)
		or (seat.Parent and seat.Parent:FindFirstChild(self.chassis.ValuesFolderName))
	if not values then
		return
	end
	local target = values:FindFirstChild(self.chassis.ThrottleValueName)
	if target and target:IsA("ValueBase") then
		(target :: any).Value = throttle
	end
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
			self.scale.Scale = layout.HudScale
			local size = self.settings.PedalSize
			local right = layout.SafeRight + 20
			local bottom = layout.HotbarBottom + 16
			-- Side by side as a pedal box, brake to the left of the accelerator as
			-- in a car. Both stay on the right: the left of the screen belongs to
			-- Roblox's steering thumbstick, and a brake placed under the steering
			-- thumb would be pressed by accident constantly.
			self.accelerate.Size = UDim2.fromOffset(size, size)
			self.brake.Size = UDim2.fromOffset(math.floor(size * 0.82), size)
			self.accelerate.AnchorPoint = Vector2.new(1, 1)
			self.brake.AnchorPoint = Vector2.new(1, 1)
			self.accelerate.Position = UDim2.new(1, -right, 1, -bottom)
			self.brake.Position = UDim2.new(1, -(right + size + 14), 1, -bottom)
		end
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(delta)
			-- Cheapest possible exit first. This runs every frame for every
			-- player, including everyone on a keyboard who will never press a
			-- pedal, so it must not search the character before it knows there is
			-- anything to do.
			if self.throttle == 0 then
				self.heldFor = 0
				return
			end
			local seat = self:_seat()
			if not seat then
				-- The player left the seat while holding a pedal.
				self.throttle = 0
				self.heldFor = 0
				return
			end
			self:_apply(seat, self.throttle)
			self:_watchForNoResponse(seat, delta)
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
