--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ProgressionController = { connections = {} }
local C = {
	Surface = Color3.fromRGB(14, 20, 30),
	Raised = Color3.fromRGB(21, 29, 42),
	Border = Color3.fromRGB(52, 66, 88),
	Text = Color3.fromRGB(244, 247, 252),
	Muted = Color3.fromRGB(151, 163, 184),
	Accent = Color3.fromRGB(91, 156, 255),
	Track = Color3.fromRGB(33, 43, 59),
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function progressBar(parent: Instance, position: UDim2, size: UDim2): Frame
	local track = Instance.new("Frame")
	track.BackgroundColor3 = C.Track
	track.BorderSizePixel = 0
	track.Position = position
	track.Size = size
	track.ClipsDescendants = true
	track.Parent = parent
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = C.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, 4)
	return fill
end

function ProgressionController:Init(context: any)
	self.context = context
	self.expanded = false
end

function ProgressionController:_motionEnabled(): boolean
	local settings = self.context.Controllers.SettingsController:Get()
	return not settings or settings.InterfaceMotion ~= false
end

function ProgressionController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSProgression"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local card = Instance.new("TextButton")
	card.Name = "ProgressionCard"
	card.AutoButtonColor = false
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -88)
	card.Size = UDim2.fromOffset(330, 56)
	card.BackgroundColor3 = C.Surface
	card.BorderSizePixel = 0
	card.Text = ""
	card.Parent = gui
	self.card = card
	corner(card, 11)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Transparency = 0.15
	stroke.Parent = card

	self.teamLabel = label(card, "PUBLIC ROLE", 10, true)
	self.teamLabel.Position = UDim2.fromOffset(14, 6)
	self.teamLabel.Size = UDim2.new(1, -120, 0, 17)
	self.teamLabel.TextColor3 = C.Accent
	self.levelLabel = label(card, "Level 1", 15, true)
	self.levelLabel.Position = UDim2.fromOffset(14, 20)
	self.levelLabel.Size = UDim2.fromOffset(120, 20)
	self.xpLabel = label(card, "0 / 100 XP", 11, false)
	self.xpLabel.AnchorPoint = Vector2.new(1, 0)
	self.xpLabel.Position = UDim2.new(1, -14, 0, 22)
	self.xpLabel.Size = UDim2.fromOffset(180, 18)
	self.xpLabel.TextColor3 = C.Muted
	self.xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	self.fill = progressBar(card, UDim2.new(0, 14, 1, -10), UDim2.new(1, -28, 0, 4))

	local panel = Instance.new("Frame")
	panel.Name = "RoleCatalogue"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -152)
	panel.Size = UDim2.fromOffset(360, 360)
	panel.BackgroundColor3 = C.Surface
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 13)
	local panelStroke = stroke:Clone()
	panelStroke.Parent = panel
	local title = label(panel, "Public progression", 17, true)
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -36, 0, 25)
	local copy = label(panel, "Every public role remains visible.", 11, false)
	copy.Position = UDim2.fromOffset(18, 39)
	copy.Size = UDim2.new(1, -36, 0, 20)
	copy.TextColor3 = C.Muted
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, 68)
	scroll.Size = UDim2.new(1, -28, 1, -82)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = C.Border
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll
	self.panel = panel
	self.list = scroll
	card.Activated:Connect(function()
		self.expanded = not self.expanded
		panel.Visible = self.expanded
	end)
end

function ProgressionController:_renderRoles(roles: { any })
	for _, child in self.list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for _, role in roles do
		local item = Instance.new("Frame")
		item.BackgroundColor3 = C.Raised
		item.BorderSizePixel = 0
		item.Size = UDim2.new(1, -5, 0, 58)
		item.Parent = self.list
		corner(item, 9)
		local name = label(item, role.Name, 12, true)
		name.Position = UDim2.fromOffset(12, 7)
		name.Size = UDim2.new(1, -100, 0, 20)
		local level = label(item, "LV " .. tostring(role.Progression.Level), 10, true)
		level.AnchorPoint = Vector2.new(1, 0)
		level.Position = UDim2.new(1, -12, 0, 8)
		level.Size = UDim2.fromOffset(70, 18)
		level.TextColor3 = C.Accent
		level.TextXAlignment = Enum.TextXAlignment.Right
		local fill = progressBar(item, UDim2.new(0, 12, 1, -17), UDim2.new(1, -24, 0, 5))
		fill.Size = UDim2.fromScale(role.Progression.Progress, 1)
	end
end

function ProgressionController:Render(data: any?)
	self.gui.Enabled = data ~= nil and data.Visible == true
	if not self.gui.Enabled or not data then
		return
	end
	local progression = data.Overall
	self.teamLabel.Text = string.upper(data.Team.Name) .. "  ·  PUBLIC PROGRESSION"
	self.levelLabel.Text = "Level " .. tostring(progression.Level)
	self.xpLabel.Text =
		string.format("%d / %d XP", progression.CurrentLevelXP, progression.RequiredLevelXP)
	local target = UDim2.fromScale(progression.Progress, 1)
	if self:_motionEnabled() then
		TweenService:Create(
			self.fill,
			TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = target }
		):Play()
	else
		self.fill.Size = target
	end
	self:_renderRoles(data.Roles)
end

function ProgressionController:Refresh()
	local response =
		self.context.Controllers.NetworkController:Request("GetPublicProgressionHud", {})
	self:Render(if response.Success then response.Data else nil)
end

function ProgressionController:Start()
	self:_mount()
	local event = self.context.Controllers.NetworkController:ResolveEvent("ProgressionChanged")
	if event then
		table.insert(
			self.connections,
			event.OnClientEvent:Connect(function(data)
				self:Render(data)
				if data.Grant then
					self.context.Controllers.NotificationController:Show(
						"+" .. tostring(data.Grant.Amount) .. " XP",
						data.Grant.LevelsGained > 0 and "Level up" or "Progression"
					)
				end
			end)
		)
	end
	table.insert(
		self.connections,
		Players.LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
			self:Refresh()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.CharacterChanged.Event:Connect(function()
			self:Refresh()
		end)
	)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Progression", function(layout)
		self.panel.Visible = false
		self.expanded = false
		self.card.AnchorPoint = if layout.Vehicle then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
		self.card.Position = if layout.Vehicle
			then UDim2.new(0.5, 0, 0, 12)
			else UDim2.new(0.5, 0, 1, -(layout.HotbarBottom + 22))
		self.card.Size = if layout.Vehicle
			then UDim2.fromOffset(if layout.Compact then 210 else 280, 48)
			else UDim2.fromOffset(if layout.Compact then 260 else 330, 56)
		-- The catalogue sits directly above the card and scrolls, so it is given
		-- whatever height is left inside the usable area instead of a fixed one
		-- that ran off the top of short or heavily inset screens.
		local catalogueBase = layout.HotbarBottom + 84
		self.panel.Position = UDim2.new(0.5, 0, 1, -catalogueBase)
		self.panel.Size = UDim2.fromOffset(
			if layout.Compact then 300 else 360,
			math.clamp(layout.SafeViewport.Y - catalogueBase - 12, 120, 360)
		)
	end)
	self:Refresh()
end

function ProgressionController:Destroy()
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

return ProgressionController
