--!strict

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedsController = {}

local function bar(parent: Instance, name: string, colour: Color3, x: number): Frame
	local container = Instance.new("Frame")
	container.Position = UDim2.fromScale(x, 0)
	container.Size = UDim2.fromScale(0.48, 1)
	container.BackgroundColor3 = Color3.fromRGB(19, 24, 34)
	container.BorderSizePixel = 0
	container.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = container
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = container
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 9
	label.ZIndex = 2
	label.Parent = container
	return container
end

function NeedsController:Init(context: any)
	self.context = context
end

function NeedsController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSNeeds"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = Instance.new("Frame")
	hud.AnchorPoint = Vector2.new(0.5, 1)
	hud.Position = UDim2.new(0.5, 0, 1, -64)
	hud.Size = UDim2.fromOffset(270, 15)
	hud.BackgroundTransparency = 1
	hud.Parent = gui
	self.stamina = bar(hud, "STAMINA", Color3.fromRGB(67, 175, 255), 0)
	self.hunger = bar(hud, "HUNGER", Color3.fromRGB(255, 174, 66), 0.52)
	self.hud = hud
	local blur = Instance.new("BlurEffect")
	blur.Name = "RoleplayOSHungerBlur"
	blur.Size = 0
	blur.Parent = Lighting
	self.blur = blur
	local remote = ReplicatedStorage.RoleplayOS.Network.Remotes:WaitForChild("NeedsChanged")
	self.connection = remote.OnClientEvent:Connect(function(state)
		self.stamina.Fill.Size = UDim2.fromScale(math.clamp(state.Stamina / 100, 0, 1), 1)
		self.hunger.Fill.Size = UDim2.fromScale(math.clamp(state.Hunger / 100, 0, 1), 1)
		self.blur.Size = math.clamp((20 - state.Hunger) * 0.6, 0, 12)
	end)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Needs", function(layout)
		self.blur.Enabled = not layout.VR
		self.hud.AnchorPoint = if layout.Vehicle then Vector2.new(0, 1) else Vector2.new(0.5, 1)
		self.hud.Position = if layout.Vehicle
			then UDim2.new(0, 18, 1, -18)
			else UDim2.new(0.5, 0, 1, -layout.HotbarBottom)
		self.hud.Size = if layout.Vehicle
			then UDim2.fromOffset(if layout.Compact then 164 else 220, 14)
			else UDim2.fromOffset(if layout.Compact then 224 else 270, 15)
	end)
	ContextActionService:BindAction("RoleplayOSSprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
			task.spawn(function()
				self.context.Controllers.NetworkController:Request(
					"SetSprintState",
					{ Sprinting = inputState == Enum.UserInputState.Begin }
				)
			end)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("RoleplayOSSprint", "RUN")
	ContextActionService:SetDescription(
		"RoleplayOSSprint",
		"Hold to sprint while travelling on foot."
	)
end

function NeedsController:Destroy()
	ContextActionService:UnbindAction("RoleplayOSSprint")
	if self.connection then
		self.connection:Disconnect()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.blur then
		self.blur:Destroy()
	end
end

return NeedsController
