--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SpeedometerController = { connections = {}, seat = nil, accumulator = 0 }
function SpeedometerController:Init(context: any)
	self.context = context
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
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -18)
	frame.Size = UDim2.fromOffset(190, 72)
	frame.BackgroundColor3 = Color3.fromRGB(7, 12, 19)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
	local speed = Instance.new("TextLabel")
	speed.Position = UDim2.fromOffset(14, 8)
	speed.Size = UDim2.fromOffset(104, 42)
	speed.BackgroundTransparency = 1
	speed.Font = Enum.Font.RobotoMono
	speed.Text = "000"
	speed.TextColor3 = Color3.fromRGB(244, 248, 252)
	speed.TextSize = 34
	speed.TextXAlignment = Enum.TextXAlignment.Right
	speed.Parent = frame
	local unit = Instance.new("TextLabel")
	unit.Position = UDim2.fromOffset(124, 20)
	unit.Size = UDim2.fromOffset(50, 22)
	unit.BackgroundTransparency = 1
	unit.Font = Enum.Font.GothamBold
	unit.Text = "MPH"
	unit.TextColor3 = Color3.fromRGB(83, 170, 255)
	unit.TextSize = 11
	unit.Parent = frame
	local gear = Instance.new("TextLabel")
	gear.Position = UDim2.fromOffset(16, 52)
	gear.Size = UDim2.fromOffset(94, 14)
	gear.BackgroundTransparency = 1
	gear.Font = Enum.Font.Gotham
	gear.Text = "P  ·  READY"
	gear.TextColor3 = Color3.fromRGB(144, 158, 177)
	gear.TextSize = 10
	gear.TextXAlignment = Enum.TextXAlignment.Left
	gear.Parent = frame
	local fuel = Instance.new("TextLabel")
	fuel.AnchorPoint = Vector2.new(1, 0)
	fuel.Position = UDim2.new(1, -16, 0, 52)
	fuel.Size = UDim2.fromOffset(70, 14)
	fuel.BackgroundTransparency = 1
	fuel.Font = Enum.Font.RobotoMono
	fuel.Text = "FUEL --"
	fuel.TextColor3 = Color3.fromRGB(144, 158, 177)
	fuel.TextSize = 10
	fuel.TextXAlignment = Enum.TextXAlignment.Right
	fuel.Parent = frame
	self.gui, self.frame, self.speed, self.gear, self.fuel = gui, frame, speed, gear, fuel
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
		self.frame.AnchorPoint = Vector2.new(0.5, 1)
		self.frame.Position = UDim2.new(0.5, 0, 1, -18)
		self.frame.Size =
			UDim2.fromOffset(if layout.Compact then 158 else 190, if layout.Compact then 62 else 72)
		local detailY = if layout.Compact then 43 else 52
		self.gear.Position = UDim2.fromOffset(16, detailY)
		self.fuel.Position = UDim2.new(1, -16, 0, detailY)
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
			self.speed.Text = string.format("%03d", math.min(mph, 999))
			self.gear.Text = (
				if seat.ThrottleFloat < -0.05
					then "R"
					elseif math.abs(seat.ThrottleFloat) > 0.05 then "D"
					else "N"
			)
				.. "  ·  "
				.. (seat:GetAttribute("RoleplayOSRegistration") or "VEHICLE")
			local fuel = seat:GetAttribute("RoleplayOSFuel")
			if type(fuel) == "number" then
				self.fuel.Text = string.format("FUEL %d%%", math.floor(fuel + 0.5))
				self.fuel.TextColor3 = if fuel <= 10
					then Color3.fromRGB(255, 101, 101)
					else Color3.fromRGB(144, 158, 177)
			else
				self.fuel.Text = "FUEL --"
				self.fuel.TextColor3 = Color3.fromRGB(144, 158, 177)
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
