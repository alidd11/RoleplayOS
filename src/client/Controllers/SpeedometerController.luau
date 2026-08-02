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
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
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
	gear.Size = UDim2.new(1, -32, 0, 14)
	gear.BackgroundTransparency = 1
	gear.Font = Enum.Font.Gotham
	gear.Text = "P  ·  READY"
	gear.TextColor3 = Color3.fromRGB(144, 158, 177)
	gear.TextSize = 10
	gear.TextXAlignment = Enum.TextXAlignment.Left
	gear.Parent = frame
	self.gui, self.frame, self.speed, self.gear = gui, frame, speed, gear
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
end
return SpeedometerController
