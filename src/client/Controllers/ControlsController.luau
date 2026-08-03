--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

type InputMode = "KeyboardMouse" | "Gamepad" | "Touch" | "VR"
type Control = {
	Action: string,
	KeyboardMouse: string,
	Gamepad: string,
	Touch: string,
	VR: string,
}

local ACTION_NAME = "RoleplayOSToggleControls"
local CONTROLS: { Control } = {
	{
		Action = "Move",
		KeyboardMouse = "W A S D",
		Gamepad = "Left stick",
		Touch = "Left thumbstick",
		VR = "Left stick",
	},
	{
		Action = "Look / turn",
		KeyboardMouse = "Mouse",
		Gamepad = "Right stick",
		Touch = "Drag right side",
		VR = "Head movement / right stick",
	},
	{
		Action = "Jump",
		KeyboardMouse = "Space",
		Gamepad = "A / Cross",
		Touch = "Jump button",
		VR = "A / Cross",
	},
	{
		Action = "Interact",
		KeyboardMouse = "E",
		Gamepad = "X / Square",
		Touch = "Tap prompt",
		VR = "X / Square",
	},
	{
		Action = "Sprint",
		KeyboardMouse = "Hold Left Shift",
		Gamepad = "Hold L3",
		Touch = "Hold RUN",
		VR = "Hold L3",
	},
	{
		Action = "Use equipped tool",
		KeyboardMouse = "Left click",
		Gamepad = "Right trigger",
		Touch = "Tap use button",
		VR = "Right trigger",
	},
	{
		Action = "Open phone",
		KeyboardMouse = "P",
		Gamepad = "Y / Triangle",
		Touch = "PHONE button",
		VR = "Y / Triangle",
	},
	{
		Action = "Open MDT (on duty)",
		KeyboardMouse = "M",
		Gamepad = "View / Select",
		Touch = "MDT button",
		VR = "View / Select",
	},
	{
		Action = "Close phone / MDT",
		KeyboardMouse = "Esc or close button",
		Gamepad = "B / Circle or close button",
		Touch = "Close button",
		VR = "B / Circle or close button",
	},
	{
		Action = "Show these controls",
		KeyboardMouse = "F1",
		Gamepad = "D-pad Down",
		Touch = "CONTROLS button",
		VR = "D-pad Down",
	},
}

local MODE_LABELS: { [InputMode]: string } = {
	KeyboardMouse = "KEYBOARD & MOUSE",
	Gamepad = "GAMEPAD",
	Touch = "TOUCH",
	VR = "VR",
}

local MODE_HINTS: { [InputMode]: string } = {
	KeyboardMouse = "F1  CONTROLS",
	Gamepad = "D-PAD DOWN  CONTROLS",
	Touch = "?  CONTROLS",
	VR = "D-PAD DOWN  CONTROLS",
}

local ControlsController = {
	connections = {},
	mode = "KeyboardMouse" :: InputMode,
	open = false,
	previousSelection = nil :: GuiObject?,
	openedAt = 0,
	-- The launcher is kept mounted so mode hints stay current, but it is not shown
	-- during play; the start menu's Controls entry and F1 / D-pad Down open it.
	launcherEnabled = false,
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function textLabel(parent: Instance, text: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(224, 230, 240)
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function isGamepad(inputType: Enum.UserInputType): boolean
	return string.find(inputType.Name, "Gamepad", 1, true) == 1
end

function ControlsController:Init(context: any)
	self.context = context
end

function ControlsController:_detectMode(inputType: Enum.UserInputType?): InputMode
	if VRService.VREnabled then
		return "VR"
	elseif inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType and isGamepad(inputType) then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "KeyboardMouse"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "KeyboardMouse"
end

function ControlsController:_renderRows()
	for _, child in self.rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, control in CONTROLS do
		local row = Instance.new("Frame")
		row.Name = "Control" .. tostring(index)
		row.Size = UDim2.new(1, -8, 0, 48)
		row.BackgroundColor3 = if index % 2 == 0
			then Color3.fromRGB(31, 39, 53)
			else Color3.fromRGB(25, 32, 45)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.ZIndex = 12
		row.Parent = self.rows
		corner(row, 7)

		local action = textLabel(row, control.Action, 14)
		action.Position = UDim2.fromOffset(14, 0)
		action.Size = UDim2.new(0.47, -14, 1, 0)
		action.Font = Enum.Font.GothamMedium
		action.ZIndex = 13

		local mapping = textLabel(row, control[self.mode], 14)
		mapping.Position = UDim2.new(0.47, 4, 0, 0)
		mapping.Size = UDim2.new(0.53, -18, 1, 0)
		mapping.TextColor3 = Color3.fromRGB(126, 200, 255)
		mapping.ZIndex = 13
	end
end

function ControlsController:_setMode(mode: InputMode)
	if self.mode == mode and self.modeLabel.Text ~= "" then
		return
	end
	self.mode = mode
	self.modeLabel.Text = MODE_LABELS[mode]
	self.launcher.Text = MODE_HINTS[mode]
	self:_renderRows()
end

function ControlsController:_setOpen(value: boolean)
	self.open = value
	if value then
		self.openedAt = os.clock()
	end
	self.backdrop.Visible = value
	self.launcher.Visible = self.launcherEnabled and not value
	self.backdrop.Modal = value
	if value then
		self.previousSelection = GuiService.SelectedObject
		if self.mode == "Gamepad" or self.mode == "VR" then
			GuiService.SelectedObject = self.closeButton
		end
	elseif
		GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.backdrop)
	then
		local previousSelection = self.previousSelection
		GuiService.SelectedObject = if previousSelection and previousSelection.Parent
			then previousSelection
			else nil
	end
end

function ControlsController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSControls"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.DisplayOrder = 90
	gui.IgnoreGuiInset = false
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local launcher = Instance.new("TextButton")
	launcher.Name = "ControlsLauncher"
	launcher.AnchorPoint = Vector2.new(1, 0)
	launcher.Position = UDim2.new(1, -18, 0, 14)
	launcher.Size = UDim2.fromOffset(150, 38)
	launcher.BackgroundColor3 = Color3.fromRGB(20, 27, 39)
	launcher.BorderSizePixel = 0
	launcher.Font = Enum.Font.GothamBold
	launcher.TextColor3 = Color3.fromRGB(234, 240, 249)
	launcher.TextSize = 13
	launcher.Selectable = true
	launcher.Visible = self.launcherEnabled
	launcher.Parent = gui
	corner(launcher, 9)
	self.launcher = launcher

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.fromRGB(4, 7, 12)
	backdrop.BackgroundTransparency = 0.22
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = gui
	self.backdrop = backdrop

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 610)
	panel.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop
	corner(panel, 14)
	self.panel = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(73, 91, 117)
	stroke.Transparency = 0.25
	stroke.Parent = panel

	local title = textLabel(panel, "CONTROLS & HELP", 23)
	title.Position = UDim2.fromOffset(22, 16)
	title.Size = UDim2.new(1, -110, 0, 32)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.ZIndex = 12

	local modeLabel = textLabel(panel, "", 12)
	modeLabel.Position = UDim2.fromOffset(23, 50)
	modeLabel.Size = UDim2.new(1, -46, 0, 22)
	modeLabel.Font = Enum.Font.GothamBold
	modeLabel.TextColor3 = Color3.fromRGB(126, 200, 255)
	modeLabel.ZIndex = 12
	self.modeLabel = modeLabel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 16)
	closeButton.Size = UDim2.fromOffset(70, 36)
	closeButton.BackgroundColor3 = Color3.fromRGB(40, 51, 68)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "CLOSE"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 12
	closeButton.Selectable = true
	closeButton.ZIndex = 12
	closeButton.Parent = panel
	corner(closeButton, 8)
	self.closeButton = closeButton

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Mappings"
	rows.Position = UDim2.fromOffset(18, 82)
	rows.Size = UDim2.new(1, -36, 1, -128)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.CanvasSize = UDim2.new()
	rows.ScrollBarImageColor3 = Color3.fromRGB(126, 200, 255)
	rows.ScrollBarThickness = 5
	rows.ScrollingDirection = Enum.ScrollingDirection.Y
	rows.Selectable = true
	rows.ZIndex = 12
	rows.Parent = panel
	self.rows = rows
	closeButton.NextSelectionDown = rows
	rows.NextSelectionUp = closeButton

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 5)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows

	local note = textLabel(
		panel,
		"Prompts and action buttons update automatically where Roblox provides native device support.",
		12
	)
	note.Position = UDim2.new(0, 22, 1, -39)
	note.Size = UDim2.new(1, -44, 0, 25)
	note.TextColor3 = Color3.fromRGB(162, 173, 192)
	note.ZIndex = 12

	table.insert(
		self.connections,
		launcher.Activated:Connect(function()
			self:_setOpen(true)
		end)
	)
	table.insert(
		self.connections,
		closeButton.Activated:Connect(function()
			self:_setOpen(false)
		end)
	)
	table.insert(
		self.connections,
		backdrop.Activated:Connect(function()
			-- The press that opened this panel can land on the backdrop as it
			-- appears; ignore dismissals that arrive in that same interaction.
			if os.clock() - (self.openedAt or 0) < 0.25 then
				return
			end
			self:_setOpen(false)
		end)
	)
end

function ControlsController:Open()
	-- Start runs concurrently with the interface mount, so the panel may not exist
	-- yet on a very early click.
	if not self.backdrop then
		return
	end
	self:_setOpen(true)
end

function ControlsController:Start()
	self:_mount()
	self:_setMode(self:_detectMode(UserInputService:GetLastInputType()))
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType)
			self:_setMode(self:_detectMode(inputType))
		end)
	)
	table.insert(
		self.connections,
		VRService:GetPropertyChangedSignal("VREnabled"):Connect(function()
			self:_setMode(self:_detectMode(UserInputService:GetLastInputType()))
		end)
	)
	ContextActionService:BindActionAtPriority(ACTION_NAME, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_setOpen(not self.open)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.F1, Enum.KeyCode.DPadDown)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Controls", function(layout)
		self.launcher.Position = UDim2.new(1, -layout.RightReserve, 0, 14)
		self.launcher.Size = UDim2.fromOffset(if layout.Compact then 112 else 150, 38)
		local maximumWidth = if layout.VR then 520 else 620
		local maximumHeight = if layout.VR then 500 else 610
		self.panel.Size = UDim2.fromOffset(
			math.clamp(layout.Viewport.X - 28, 300, maximumWidth),
			math.clamp(layout.Viewport.Y - 34, 360, maximumHeight)
		)
	end)
end

function ControlsController:Destroy()
	ContextActionService:UnbindAction(ACTION_NAME)
	if self.unbindLayout then
		self.unbindLayout()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.gui then
		self.gui:Destroy()
	end
end

return ControlsController
