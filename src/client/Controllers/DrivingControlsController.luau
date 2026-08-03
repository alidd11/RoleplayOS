--!strict

-- Throttle and brake pedals for touch players.
--
-- Roblox gives a touch driver the same thumbstick it gives a pedestrian, which
-- steers and accelerates on one control and cannot hold full throttle while
-- steering. These are separate pedals, so a phone player can do both at once.
--
-- The pedals drive the seat's own throttle rather than talking to the chassis,
-- so they work with any chassis, or none. The value is written every frame
-- while a pedal is held: Roblox's own control module writes the same property
-- from the thumbstick, and whichever writes last in a frame wins.

local ContextActionService = game:GetService("ContextActionService")
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
			self.accelerate.Size = UDim2.fromOffset(size, size)
			self.brake.Size = UDim2.fromOffset(size, math.floor(size * 0.62))
			self.accelerate.AnchorPoint = Vector2.new(1, 1)
			self.brake.AnchorPoint = Vector2.new(1, 1)
			-- Accelerator under the thumb, brake stacked above it, both inside
			-- the strip reserved on the right while driving.
			self.accelerate.Position = UDim2.new(1, -right, 1, -bottom)
			self.brake.Position = UDim2.new(1, -right, 1, -(bottom + size + 12))
		end
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function()
			if self.throttle == 0 then
				return
			end
			local seat = self:_seat()
			if seat then
				seat.ThrottleFloat = self.throttle
			else
				-- The player left the seat while holding a pedal.
				self.throttle = 0
			end
		end)
	)
end

function DrivingControlsController:Destroy()
	ContextActionService:UnbindAction("RoleplayOSDrivingControls")
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
