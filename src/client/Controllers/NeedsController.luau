--!strict

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

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
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = Instance.new("Frame")
	hud.AnchorPoint = Vector2.new(0.5, 1)
	hud.Position = UDim2.new(0.5, 0, 1, -64)
	hud.Size = UDim2.fromOffset(270, 15)
	hud.BackgroundTransparency = 1
	hud.Parent = gui
	local hudScale = Instance.new("UIScale")
	hudScale.Parent = hud
	self.hudScale = hudScale
	self.stamina = bar(hud, "STAMINA", Color3.fromRGB(67, 175, 255), 0)
	self.hunger = bar(hud, "HUNGER", Color3.fromRGB(255, 174, 66), 0.52)
	self.hud = hud
	local blur = Instance.new("BlurEffect")
	blur.Name = "RoleplayOSHungerBlur"
	blur.Size = 0
	blur.Parent = Lighting
	self.blur = blur
	-- The live feed is optional: the bars must still mount and lay out even if the
	-- server has not registered the event, otherwise the HUD never appears at all.
	local remote = self.context.Controllers.NetworkController:ResolveEvent("NeedsChanged")
	if remote then
		self.connection = remote.OnClientEvent:Connect(function(state)
			self.stamina.Fill.Size = UDim2.fromScale(math.clamp(state.Stamina / 100, 0, 1), 1)
			self.hunger.Fill.Size = UDim2.fromScale(math.clamp(state.Hunger / 100, 0, 1), 1)
			self.blur.Size = math.clamp((20 - state.Hunger) * 0.6, 0, 12)
		end)
	end
	-- A purpose-built control rather than the generic touch button, so touch
	-- players get a sprint pad sized and placed like the rest of the interface
	-- instead of one Roblox positions for us. Shown only on touch, since a
	-- keyboard or pad player already has a binding.
	local sprintPad = Instance.new("TextButton")
	sprintPad.Name = "SprintPad"
	sprintPad.AnchorPoint = Vector2.new(1, 1)
	sprintPad.AutoButtonColor = false
	sprintPad.BackgroundColor3 = Color3.fromRGB(22, 30, 44)
	sprintPad.BackgroundTransparency = 0.2
	sprintPad.BorderSizePixel = 0
	sprintPad.Font = Enum.Font.GothamBold
	sprintPad.Text = "RUN"
	sprintPad.TextColor3 = Color3.fromRGB(238, 244, 252)
	sprintPad.TextSize = 13
	sprintPad.Size = UDim2.fromOffset(84, 84)
	sprintPad.Visible = false
	sprintPad.Parent = gui
	local padScale = Instance.new("UIScale")
	padScale.Parent = sprintPad
	self.padScale = padScale
	local padCorner = Instance.new("UICorner")
	padCorner.CornerRadius = UDim.new(0, 42)
	padCorner.Parent = sprintPad
	local padStroke = Instance.new("UIStroke")
	padStroke.Color = Color3.fromRGB(78, 100, 132)
	padStroke.Transparency = 0.35
	padStroke.Parent = sprintPad
	self.sprintPad = sprintPad

	local function setSprinting(sprinting: boolean)
		sprintPad.BackgroundColor3 = if sprinting
			then Color3.fromRGB(46, 104, 168)
			else Color3.fromRGB(22, 30, 44)
		task.spawn(function()
			local response = self.context.Controllers.NetworkController:Request(
				"SetSprintState",
				{ Sprinting = sprinting }
			)
			-- The reply was being thrown away, so a refused sprint looked exactly
			-- like a dead key. Only a refusal to start is worth saying: failing to
			-- stop running is not something anybody needs telling about, and the
			-- pad colour is corrected either way.
			if not response.Success and sprinting then
				sprintPad.BackgroundColor3 = Color3.fromRGB(22, 30, 44)
				if response.Message ~= "" then
					self.context.Controllers.NotificationController:Show(response.Message, "Needs")
				end
			end
		end)
	end

	-- Hold to run, matching the key and pad bindings. InputEnded rather than
	-- Activated, so lifting a finger anywhere reliably stops the sprint instead
	-- of leaving the character running.
	sprintPad.InputBegan:Connect(function(inputObject)
		if
			inputObject.UserInputType == Enum.UserInputType.Touch
			or inputObject.UserInputType == Enum.UserInputType.MouseButton1
		then
			setSprinting(true)
		end
	end)
	sprintPad.InputEnded:Connect(function(inputObject)
		if
			inputObject.UserInputType == Enum.UserInputType.Touch
			or inputObject.UserInputType == Enum.UserInputType.MouseButton1
		then
			setSprinting(false)
		end
	end)

	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Needs", function(layout)
		self.blur.Enabled = not layout.VR
		self.hudScale.Scale = layout.HudScale
		self.padScale.Scale = layout.HudScale
		self.hud.AnchorPoint = if layout.Vehicle then Vector2.new(0, 1) else Vector2.new(0.5, 1)
		self.hud.Position = if layout.Vehicle
			then UDim2.new(0, 18, 1, -18)
			else UDim2.new(0.5, 0, 1, -layout.HotbarBottom)
		self.hud.Size = if layout.Vehicle
			then UDim2.fromOffset(if layout.Compact then 164 else 220, 14)
			else UDim2.fromOffset(if layout.Compact then 224 else 270, 15)
		-- Only touch players need an on-screen control, and never while driving,
		-- where the pad would sit over the vehicle controls.
		self.sprintPad.Visible = layout.InputMode == "Touch" and not layout.Vehicle
		self.sprintPad.Size =
			UDim2.fromOffset(if layout.Compact then 76 else 84, if layout.Compact then 76 else 84)
		-- The minimap occupies the right edge at mid height, so the pad sits below
		-- it rather than under it. Clearing the minimap's own height keeps the two
		-- apart on a phone, where the screen is short and both want that corner.
		self.sprintPad.Position =
			UDim2.new(1, -(layout.RightReserve + 14), 1, -(layout.HotbarBottom + 40))
	end)
	ContextActionService:BindAction("RoleplayOSSprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
			setSprinting(inputState == Enum.UserInputState.Begin)
		end
		return Enum.ContextActionResult.Sink
		-- No generic touch button: the sprint pad above replaces it. Both shift
		-- keys are bound, since a player may hold either.
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
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
