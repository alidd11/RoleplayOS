--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local VRService = game:GetService("VRService")

local EXIT_ACTION = "RoleplayOSExitCCTV"
local NAVIGATE_ACTION = "RoleplayOSNavigateCCTV"
local CCTVController = { connections = {}, cameras = {}, index = 1, viewing = false }

local function button(parent: Instance, text: string): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = Color3.fromRGB(18, 26, 38)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(240, 245, 252)
	item.TextSize = 12
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = item
	return item
end

function CCTVController:Init(context: any)
	self.context = context
end

function CCTVController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCCTV"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 18
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -24)
	bar.Size = UDim2.fromOffset(620, 64)
	bar.BackgroundColor3 = Color3.fromRGB(8, 13, 21)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar
	local previous = button(bar, "‹ PREVIOUS")
	previous.Position = UDim2.fromOffset(12, 12)
	previous.Size = UDim2.fromOffset(120, 40)
	local nextButton = button(bar, "NEXT ›")
	nextButton.Position = UDim2.new(1, -252, 0, 12)
	nextButton.Size = UDim2.fromOffset(120, 40)
	local exit = button(bar, "EXIT CCTV")
	exit.Position = UDim2.new(1, -122, 0, 12)
	exit.Size = UDim2.fromOffset(110, 40)
	exit.BackgroundColor3 = Color3.fromRGB(136, 39, 48)
	self.exitButton = exit
	local name = Instance.new("TextLabel")
	name.Name = "CameraName"
	name.Position = UDim2.fromOffset(142, 8)
	name.Size = UDim2.fromOffset(214, 48)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.fromRGB(240, 245, 252)
	name.TextSize = 14
	name.TextWrapped = true
	name.Parent = bar
	self.cameraName = name
	table.insert(
		self.connections,
		previous.Activated:Connect(function()
			self.index = if self.index <= 1 then #self.cameras else self.index - 1
			self:_apply()
		end)
	)
	table.insert(
		self.connections,
		nextButton.Activated:Connect(function()
			self.index = if self.index >= #self.cameras then 1 else self.index + 1
			self:_apply()
		end)
	)
	table.insert(
		self.connections,
		exit.Activated:Connect(function()
			self:Exit()
		end)
	)
end

function CCTVController:_apply()
	local item = self.cameras[self.index]
	if not item then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local position = Vector3.new(table.unpack(item.Position))
	local lookAt = Vector3.new(table.unpack(item.LookAt))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, lookAt)
	self.cameraName.Text = "● LIVE  ·  " .. tostring(item.Name)
end

function CCTVController:Open()
	if VRService.VREnabled then
		self.context.Controllers.NotificationController:Show(
			"CCTV viewing is unavailable in VR because it uses a fixed scripted camera.",
			"VR comfort"
		)
		return
	end
	local response = self.context.Controllers.NetworkController:Request("GetCCTVCameras", {})
	if not response.Success or #(response.Data or {}) == 0 then
		self.context.Controllers.NotificationController:Show(
			response.Message ~= "" and response.Message or "No CCTV cameras are configured.",
			"CCTV"
		)
		return
	end
	self.cameras = response.Data
	self.index = 1
	self.viewing = true
	self.gui.Enabled = true
	self:_apply()
	GuiService.SelectedObject = self.exitButton
end

function CCTVController:Exit()
	self.viewing = false
	self.gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function CCTVController:Start()
	self:_mount()
	ContextActionService:BindActionAtPriority(EXIT_ACTION, function(_, inputState)
		if self.viewing and inputState == Enum.UserInputState.Begin then
			self:Exit()
		end
		return if self.viewing then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end, false, 3000, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(EXIT_ACTION, "EXIT CCTV")
	ContextActionService:SetDescription(EXIT_ACTION, "Return to your character camera.")
	ContextActionService:BindActionAtPriority(NAVIGATE_ACTION, function(_, inputState, input)
		if not self.viewing then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			if input.KeyCode == Enum.KeyCode.ButtonL1 then
				self.index = if self.index <= 1 then #self.cameras else self.index - 1
			else
				self.index = if self.index >= #self.cameras then 1 else self.index + 1
			end
			self:_apply()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(NAVIGATE_ACTION, "CHANGE CCTV")
	ContextActionService:SetDescription(
		NAVIGATE_ACTION,
		"Use the shoulder buttons to change camera."
	)
end

function CCTVController:Destroy()
	ContextActionService:UnbindAction(EXIT_ACTION)
	ContextActionService:UnbindAction(NAVIGATE_ACTION)
	self:Exit()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return CCTVController
