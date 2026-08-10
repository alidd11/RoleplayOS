--!strict

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

-- Roblox's unified top bar is a 36px band on an unscaled desktop client and
-- carries 32px square icon controls inside it, leaving a 2px gutter above and
-- below. The world menu toggle mirrors those proportions so it reads as one of
-- the native controls; the responsive binding rescales them whenever Roblox
-- reports a taller band (touch, high DPI, VR).
local NATIVE_BAND_HEIGHT = 36
local NATIVE_CONTROL_SIZE = 32
-- Gap Roblox leaves between adjacent top-bar clusters.
local NATIVE_CONTROL_GAP = 8

local App = {}
local COLOURS = {
	Canvas = Color3.fromRGB(15, 20, 28),
	Sidebar = Color3.fromRGB(18, 24, 34),
	Surface = Color3.fromRGB(24, 31, 43),
	SurfaceRaised = Color3.fromRGB(31, 40, 55),
	Border = Color3.fromRGB(56, 68, 88),
	Text = Color3.fromRGB(240, 244, 251),
	Muted = Color3.fromRGB(174, 184, 201),
	Accent = Color3.fromRGB(91, 156, 255),
	-- Fill for primary buttons. The accent is a good colour for text, strokes and
	-- indicators against the dark canvas, and a poor one behind white label text:
	-- that pairing measures about two and a half to one, well under the four and
	-- a half a body label needs. This is the same hue, dark enough to carry it.
	AccentFill = Color3.fromRGB(31, 95, 208),
	AccentSoft = Color3.fromRGB(25, 51, 88),
	Success = Color3.fromRGB(84, 211, 142),
	Warning = Color3.fromRGB(245, 188, 78),
	Danger = Color3.fromRGB(244, 104, 112),
}

local ROLE_PRESENTATION = {
	Civilian = { Icon = "CIV", Colour = Color3.fromRGB(91, 156, 255), Label = "PUBLIC LIFE" },
	Police = { Icon = "POL", Colour = Color3.fromRGB(72, 132, 224), Label = "POLICING" },
	Ambulance = { Icon = "AMB", Colour = Color3.fromRGB(80, 190, 133), Label = "AMBULANCE" },
	Fire = { Icon = "FIRE", Colour = Color3.fromRGB(231, 92, 82), Label = "FIRE & RESCUE" },
	Highways = { Icon = "HWY", Colour = Color3.fromRGB(238, 174, 67), Label = "HIGHWAYS" },
	Transport = { Icon = "BUS", Colour = Color3.fromRGB(148, 108, 219), Label = "TRANSPORT" },
	Prison = { Icon = "HMP", Colour = Color3.fromRGB(167, 117, 75), Label = "PRISON SERVICE" },
	Control = { Icon = "CTL", Colour = Color3.fromRGB(50, 190, 188), Label = "FORCE CONTROL" },
}

local function rolePresentation(role: any): any
	local key = role.DepartmentId or role.Id
	return ROLE_PRESENTATION[key]
		or { Icon = "ROLE", Colour = COLOURS.Accent, Label = "PUBLIC SERVICE" }
end

local corner: (Instance, number) -> ()
local stroke: (Instance, Color3?, number?) -> ()
local cachedAvatarDescription: HumanoidDescription? = nil

local function portraitPreview(
	parent: Instance,
	accent: Color3,
	uniform: any?,
	isCurrent: (() -> boolean)?
): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "AvatarPreview"
	viewport.BackgroundColor3 = Color3.fromRGB(28, 36, 49)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.6, -0.45, -1)
	viewport.Parent = parent
	corner(viewport, 12)
	stroke(viewport, accent, 0.68)

	local wash = Instance.new("UIGradient")
	wash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 75, 99)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(27, 35, 48)),
	})
	wash.Rotation = 90
	wash.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.15, 7.6), Vector3.new(0, 1.05, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Parent = viewport

	task.spawn(function()
		local ok, modelOrError = pcall(function()
			if not cachedAvatarDescription then
				cachedAvatarDescription =
					Players:GetHumanoidDescriptionFromUserId(Players.LocalPlayer.UserId)
			end
			local description = cachedAvatarDescription:Clone()
			if uniform then
				local shirt = tonumber(uniform.ShirtTemplate)
				local trousers = tonumber(uniform.TrousersTemplate)
				if shirt and shirt > 0 then
					description.Shirt = shirt
				end
				if trousers and trousers > 0 then
					description.Pants = trousers
				end
			end
			return Players:CreateHumanoidModelFromDescriptionAsync(
				description,
				Enum.HumanoidRigType.R15
			)
		end)
		if not ok or typeof(modelOrError) ~= "Instance" then
			return
		end
		local model = modelOrError :: Model
		if not viewport.Parent or (isCurrent and not isCurrent()) then
			model:Destroy()
			return
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CastShadow = false
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end
		model:PivotTo(CFrame.Angles(0, math.rad(180), 0))
		model.Parent = world
	end)

	return viewport
end

local function tileGrid(
	parent: Instance,
	itemCount: number,
	itemHeight: number,
	columns: number
): Frame
	local gap = 14
	local rows = math.max(1, math.ceil(itemCount / columns))
	local grid = Instance.new("Frame")
	grid.Name = "PortraitGrid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, rows * itemHeight + (rows - 1) * gap)
	grid.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		grid.LayoutOrder = nextOrder
	end
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.CellSize = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, itemHeight)
	layout.Parent = grid
	return grid
end

corner = function(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

stroke = function(parent: Instance, colour: Color3?, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = colour or COLOURS.Border
	value.Transparency = transparency or 0
	value.Parent = parent
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3?,
	bold: boolean?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextSize = size
	item.TextColor3 = colour or COLOURS.Text
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function pressable(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function motionEnabled(): boolean
		local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
		return not gui or gui:GetAttribute("RoleplayOSInterfaceMotion") ~= false
	end
	button.MouseButton1Down:Connect(function()
		if not motionEnabled() then
			scale.Scale = 0.97
			return
		end
		TweenService
			:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 0.97,
			})
			:Play()
	end)
	button.MouseButton1Up:Connect(function()
		if not motionEnabled() then
			scale.Scale = 1
			return
		end
		TweenService
			:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)
end

local function button(parent: Instance, label: string, primary: boolean?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = if primary then COLOURS.AccentFill else COLOURS.SurfaceRaised
	item.Font = Enum.Font.GothamBold
	item.Text = label
	item.TextSize = 14
	item.TextColor3 = COLOURS.Text
	item.Size = UDim2.fromOffset(170, 44)
	item.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		item.LayoutOrder = nextOrder
	end
	corner(item, 10)
	stroke(item, if primary then COLOURS.Accent else COLOURS.Border, if primary then 0.55 else 0)
	pressable(item)
	return item
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
		then
			child:Destroy()
		end
	end
	container:SetAttribute("RoleplayOSNextLayoutOrder", 0)
end

local function elevate(container: Instance, zIndex: number)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = zIndex
		end
	end
end

local function card(parent: Instance, height: number): Frame
	local item = Instance.new("Frame")
	item.BackgroundColor3 = COLOURS.Surface
	item.BorderSizePixel = 0
	item.Size = UDim2.new(1, 0, 0, height)
	item.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		item.LayoutOrder = nextOrder
	end
	corner(item, 12)
	stroke(item)
	local surfaceGradient = Instance.new("UIGradient")
	surfaceGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 41, 57)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 29, 41)),
	})
	surfaceGradient.Rotation = 90
	surfaceGradient.Parent = item
	return item
end

local function input(parent: Instance, placeholder: string): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = COLOURS.Canvas
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = COLOURS.Muted
	item.Text = ""
	item.TextColor3 = COLOURS.Text
	item.TextSize = 15
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Size = UDim2.new(1, 0, 0, 46)
	item.Parent = parent
	corner(item, 9)
	stroke(item)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = item
	return item
end

function App.mount(context: any): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOS"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	-- The visual canvas deliberately renders behind Roblox's top bar and device
	-- cutouts. Interactive content is positioned inside the safe region by the
	-- responsive binding below, so the experience stays full bleed without
	-- competing with native Roblox controls.
	gui.IgnoreGuiInset = true
	-- Set ScreenInsets after the legacy IgnoreGuiInset compatibility property;
	-- assigning the legacy property may otherwise rewrite the inset mode.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the gameplay HUD (minimap, needs, progression) which would otherwise
	-- draw over the menu, but below the controls overlay at 90.
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local menuToggleGui = Instance.new("ScreenGui")
	menuToggleGui.Name = "RoleplayOSMenuToggle"
	menuToggleGui:SetAttribute("RoleplayOSManagedUI", true)
	menuToggleGui.ResetOnSpawn = false
	menuToggleGui.ScreenInsets = Enum.ScreenInsets.None
	menuToggleGui.ClipToDeviceSafeArea = true
	-- Keep the control above the menu canvas as well as the gameplay HUD. It is
	-- both the opener and the always-available close/back action.
	menuToggleGui.DisplayOrder = 60
	menuToggleGui.Parent = gui.Parent
	-- Keep the explicit MENU label the player asked for, while matching the height
	-- and baseline of Roblox's native top-bar controls.
	local menuToggle = Instance.new("TextButton")
	menuToggle.Name = "OpenMenu"
	menuToggle.Size = UDim2.fromOffset(NATIVE_CONTROL_SIZE, NATIVE_CONTROL_SIZE)
	menuToggle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	menuToggle.BackgroundTransparency = 0.5
	menuToggle.BorderSizePixel = 0
	menuToggle.AutoButtonColor = true
	menuToggle.Text = "MENU"
	menuToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	menuToggle.TextSize = 14
	menuToggle.Font = Enum.Font.GothamBold
	menuToggle.Visible = false
	menuToggle.Selectable = true
	menuToggle.Parent = menuToggleGui
	local menuToggleCorner = Instance.new("UICorner")
	menuToggleCorner.CornerRadius = UDim.new(0, NATIVE_CONTROL_SIZE / 2)
	menuToggleCorner.Parent = menuToggle
	-- A dedicated non-interactive backdrop extends above the legacy GUI origin.
	-- This keeps the visual treatment full bleed even on clients which still
	-- apply the historical top-bar offset to an inset-free ScreenGui.
	local bleedBackdrop = Instance.new("Frame")
	bleedBackdrop.Name = "FullBleedBackdrop"
	bleedBackdrop.BackgroundColor3 = COLOURS.Canvas
	bleedBackdrop.BorderSizePixel = 0
	bleedBackdrop.ZIndex = -10
	bleedBackdrop.Parent = gui
	local bleedGradient = Instance.new("UIGradient")
	bleedGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 27, 38)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 18, 27)),
	})
	bleedGradient.Rotation = 28
	bleedGradient.Parent = bleedBackdrop

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.Name = "Root"
	root.BackgroundColor3 = COLOURS.Canvas
	root.BorderSizePixel = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 30, 42)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(17, 24, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 27)),
	})
	gradient.Rotation = 28
	gradient.Parent = root

	local loadingOverlay = Instance.new("Frame")
	loadingOverlay.Name = "LoadingExperience"
	loadingOverlay.Size = UDim2.fromScale(1, 1)
	loadingOverlay.BackgroundColor3 = COLOURS.Canvas
	loadingOverlay.BorderSizePixel = 0
	loadingOverlay.ZIndex = 100
	loadingOverlay.Parent = gui
	-- A low-contrast edge wash suggests emergency lighting without putting two
	-- obvious pulsing shapes behind the title. The centre remains calm and legible.
	for index, definition in
		{
			{ Colour = Color3.fromRGB(25, 76, 150), Left = true, Delay = 0 },
			{ Colour = Color3.fromRGB(120, 31, 45), Left = false, Delay = 1.1 },
		}
	do
		local glow = Instance.new("Frame")
		glow.Name = if index == 1 then "BlueEdgeWash" else "RedEdgeWash"
		glow.AnchorPoint = Vector2.new(if definition.Left then 0 else 1, 0)
		glow.Position = UDim2.fromScale(if definition.Left then 0 else 1, 0)
		glow.Size = UDim2.fromScale(0.42, 1)
		glow.BackgroundColor3 = definition.Colour
		glow.BackgroundTransparency = 0
		glow.BorderSizePixel = 0
		glow.ZIndex = 100
		glow.Parent = loadingOverlay
		local edgeGradient = Instance.new("UIGradient")
		edgeGradient.Color = ColorSequence.new(definition.Colour)
		edgeGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.84),
			NumberSequenceKeypoint.new(1, 1),
		})
		edgeGradient.Rotation = if definition.Left then 0 else 180
		edgeGradient.Parent = glow
		-- A restrained static wash reads as emergency-service branding without
		-- flashing behind text or spending render time while this overlay is hidden.
	end
	local loadingTitle =
		text(loadingOverlay, "EMERGENCY RESPONSE: PORTSMOUTH", 25, COLOURS.Text, true)
	loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingTitle.Position = UDim2.fromScale(0.5, 0.44)
	loadingTitle.Size = UDim2.new(1, -48, 0, 38)
	loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
	loadingTitle.ZIndex = 101
	local loadingStatus = text(loadingOverlay, "Preparing your profile…", 14, COLOURS.Muted)
	loadingStatus.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingStatus.Position = UDim2.fromScale(0.5, 0.51)
	loadingStatus.Size = UDim2.new(1, -48, 0, 26)
	loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
	loadingStatus.ZIndex = 101
	local loadingBar = Instance.new("Frame")
	loadingBar.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingBar.Position = UDim2.fromScale(0.5, 0.57)
	loadingBar.Size = UDim2.fromOffset(260, 3)
	loadingBar.BackgroundColor3 = COLOURS.Border
	loadingBar.BorderSizePixel = 0
	loadingBar.ZIndex = 101
	loadingBar.Parent = loadingOverlay
	local loadingFill = Instance.new("Frame")
	loadingFill.Size = UDim2.fromScale(0.16, 1)
	loadingFill.BackgroundColor3 = COLOURS.Accent
	loadingFill.BorderSizePixel = 0
	loadingFill.ZIndex = 102
	loadingFill.Parent = loadingBar
	local loadingTween = TweenService:Create(
		loadingFill,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.84, 0) }
	)
	loadingTween:Play()
	local function finishLoading()
		loadingTween:Cancel()
		loadingOverlay.Visible = false
	end
	-- Named for what it does rather than for giving up. A player who reaches for
	-- this is not impatient, they are stuck, and "Skip loading" tells them they
	-- are about to miss something rather than that they can get out.
	local skipLoading = button(loadingOverlay, "Continue anyway", false)
	skipLoading.AnchorPoint = Vector2.new(0.5, 1)
	skipLoading.Position = UDim2.new(0.5, 0, 1, -30)
	skipLoading.Size = UDim2.fromOffset(190, 44)
	skipLoading.ZIndex = 103
	skipLoading.Activated:Connect(function()
		finishLoading()
	end)

	-- Retrying is the thing that actually fixes this, and there was no way to do
	-- it short of rejoining the server.
	local retryLoading = button(loadingOverlay, "Retry", true)
	retryLoading.AnchorPoint = Vector2.new(0.5, 1)
	retryLoading.Position = UDim2.new(0.5, 0, 1, -82)
	retryLoading.Size = UDim2.fromOffset(190, 44)
	retryLoading.ZIndex = 103
	retryLoading.Visible = false
	retryLoading.Activated:Connect(function()
		retryLoading.Active = false
		retryLoading.Text = "Retrying…"
		loadingStatus.Text = "Reconnecting to the server…"
		loadingStatus.TextColor3 = COLOURS.Muted
		task.spawn(function()
			local response = context.Controllers.StartMenuController:Refresh()
			retryLoading.Text = "Retry"
			retryLoading.Active = true
			if response.Success then
				finishLoading()
				return
			end
			loadingStatus.Text = "Could not reach the server."
			loadingStatus.TextColor3 = COLOURS.Danger
		end)
	end)

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 250, 1, 0)
	sidebar.BackgroundColor3 = COLOURS.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = root
	-- Divides the bar from the content beneath it. Authored for a sidebar down the
	-- left, where it was a hairline on the right edge; in the bar layout that put
	-- a one pixel tick in the top corner and left the bar with no edge at all.
	local sidebarStroke = Instance.new("Frame")
	sidebarStroke.AnchorPoint = Vector2.new(0, 1)
	sidebarStroke.Position = UDim2.fromScale(0, 1)
	sidebarStroke.Size = UDim2.new(1, 0, 0, 1)
	sidebarStroke.BackgroundColor3 = COLOURS.Border
	sidebarStroke.BorderSizePixel = 0
	sidebarStroke.Parent = sidebar

	local brand = text(sidebar, game.Name, 21, COLOURS.Text, true)
	brand.Position = UDim2.fromOffset(26, 20)
	brand.Size = UDim2.new(1, -52, 0, 42)
	brand.TextSize = 17
	brand.TextTruncate = Enum.TextTruncate.None
	brand.TextWrapped = true
	local version = text(sidebar, "POWERED BY ROLEPLAYOS  ·  0.1", 10, COLOURS.Muted, true)
	version.Position = UDim2.fromOffset(27, 66)
	version.Size = UDim2.fromOffset(180, 18)

	local navigation = Instance.new("Frame")
	navigation.BackgroundTransparency = 1
	navigation.Position = UDim2.fromOffset(18, 112)
	navigation.Size = UDim2.new(1, -36, 0, 190)
	navigation.Parent = sidebar
	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 7)
	navLayout.Parent = navigation

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(250, 0)
	content.Size = UDim2.new(1, -250, 1, 0)
	content.Parent = root

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(44, 30)
	header.Size = UDim2.new(1, -88, 0, 76)
	header.Parent = content
	local pageTitle = text(header, "Play", 30, COLOURS.Text, true)
	pageTitle.Size = UDim2.new(1, -220, 0, 40)
	local pageDescription = text(header, "Choose who you want to be today.", 14, COLOURS.Muted)
	pageDescription.Position = UDim2.fromOffset(0, 41)
	pageDescription.Size = UDim2.new(1, -220, 0, 24)
	local status = text(header, "●  CONNECTING", 11, COLOURS.Warning, true)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, 0, 0, 9)
	status.Size = UDim2.fromOffset(190, 28)
	status.TextXAlignment = Enum.TextXAlignment.Right

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(44, 118)
	scroll.Size = UDim2.new(1, -88, 1, -146)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = COLOURS.Border
	scroll.Parent = content
	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Padding = UDim.new(0, 14)
	flow.Parent = scroll

	local menuData: any = nil
	local selectedStoreCategory: string? = nil
	-- Seeded from the character the player last used, which the server already
	-- sends and nothing read. Without it a returning player picks the same
	-- character again on every join before they can do anything else.
	local selectedCharacterId: string? = nil
	local dismissToWorld: () -> ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function updateMenuToggleAppearance(isOpen: boolean)
		menuToggle.Text = "MENU"
		menuToggle:SetAttribute("AccessibilityLabel", if isOpen then "Close menu" else "Open menu")
	end
	local function setMenuOpen(isOpen: boolean)
		playerGui:SetAttribute("RoleplayOSMenuOpen", isOpen)
		menuToggle.Visible = true
		updateMenuToggleAppearance(isOpen)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not isOpen)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not isOpen)
		end)
	end
	playerGui:GetAttributeChangedSignal("RoleplayOSMenuOpen"):Connect(function()
		updateMenuToggleAppearance(playerGui:GetAttribute("RoleplayOSMenuOpen") == true)
	end)
	local function interfaceMotionEnabled(): boolean
		local settings = context.Controllers.SettingsController:Get()
		return not settings or settings.InterfaceMotion ~= false
	end

	local function openFromWorld()
		setMenuOpen(true)
		gui.Enabled = true
		context.Controllers.StartMenuController:Refresh()
		root.Position = UDim2.fromOffset(0, 0)
		root.BackgroundTransparency = 0
		if interfaceMotionEnabled() then
			root.Position = UDim2.fromOffset(0, 8)
			root.BackgroundTransparency = 1
			TweenService:Create(
				root,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0 }
			):Play()
		end
	end

	menuToggle.Activated:Connect(function()
		if playerGui:GetAttribute("RoleplayOSMenuOpen") == true and gui.Enabled then
			dismissToWorld()
		else
			openFromWorld()
		end
	end)

	local function showModal()
		local currentLayout = context.Controllers.UIOrchestrator:GetLayout()
		-- Sized against the usable area rather than the raw viewport: this canvas
		-- is deliberately full bleed, so a modal measured against the whole screen
		-- would run under a notch, island or home indicator.
		local safeViewport = currentLayout.SafeViewport
		local shortViewport = safeViewport.Y < 520
		local shade = Instance.new("TextButton")
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.25
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 20
		shade.Parent = root
		local modal = Instance.new("Frame")
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.Position = UDim2.fromScale(0.5, 0.5)
		modal.Size = UDim2.fromOffset(
			math.min(460, safeViewport.X - 32),
			if shortViewport then math.min(326, safeViewport.Y - 24) else 465
		)
		modal.BackgroundColor3 = COLOURS.Surface
		modal.BorderSizePixel = 0
		modal.ZIndex = 21
		modal.Parent = shade
		corner(modal, 15)
		stroke(modal)
		local modalPadding = Instance.new("UIPadding")
		local modalInset = if shortViewport then 16 else 26
		modalPadding.PaddingTop = UDim.new(0, modalInset)
		modalPadding.PaddingBottom = UDim.new(0, modalInset)
		modalPadding.PaddingLeft = UDim.new(0, modalInset)
		modalPadding.PaddingRight = UDim.new(0, modalInset)
		modalPadding.Parent = modal
		local modalFlow = Instance.new("UIListLayout")
		modalFlow.SortOrder = Enum.SortOrder.LayoutOrder
		modalFlow.Padding = UDim.new(0, if shortViewport then 6 else 12)
		modalFlow.Parent = modal
		local title = text(modal, "Create a character", 24, COLOURS.Text, true)
		title.LayoutOrder = 1
		title.Size = UDim2.new(1, 0, 0, if shortViewport then 30 else 36)
		title.TextSize = if shortViewport then 20 else 24
		local copy = text(
			modal,
			"Build a civilian identity. You can customise appearance later.",
			13,
			COLOURS.Muted
		)
		copy.LayoutOrder = 2
		copy.Size = UDim2.new(1, 0, 0, if shortViewport then 30 else 38)
		copy.TextWrapped = true
		local firstName = input(modal, "First name")
		local lastName = input(modal, "Last name")
		local dateOfBirth = input(modal, "Date of birth  ·  YYYY-MM-DD")
		firstName.LayoutOrder = 3
		lastName.LayoutOrder = 4
		dateOfBirth.LayoutOrder = 5
		if shortViewport then
			firstName.Size = UDim2.new(1, 0, 0, 40)
			lastName.Size = UDim2.new(1, 0, 0, 40)
			dateOfBirth.Size = UDim2.new(1, 0, 0, 40)
		end
		local errorLabel = text(modal, "", 12, COLOURS.Danger)
		errorLabel.LayoutOrder = 6
		errorLabel.Size = UDim2.new(1, 0, 0, if shortViewport then 20 else 24)
		local actions = Instance.new("Frame")
		actions.LayoutOrder = 7
		actions.BackgroundTransparency = 1
		actions.Size = UDim2.new(1, 0, 0, if shortViewport then 42 else 46)
		actions.Parent = modal
		local cancel = button(actions, "Cancel", false)
		cancel.Size = UDim2.new(0.5, -6, 1, 0)
		local create = button(actions, "Create character", true)
		create.Position = UDim2.new(0.5, 6, 0, 0)
		create.Size = UDim2.new(0.5, -6, 1, 0)
		cancel.Activated:Connect(function()
			shade:Destroy()
		end)
		create.Activated:Connect(function()
			create.Text = "Creating…"
			local response = context.Controllers.CharacterController:Create({
				FirstName = firstName.Text,
				LastName = lastName.Text,
				DateOfBirth = dateOfBirth.Text,
			})
			if response.Success then
				shade:Destroy()
				context.Controllers.StartMenuController:Refresh()
			else
				errorLabel.Text = response.Message
				create.Text = "Create character"
			end
		end)
		elevate(modal, 22)
		if interfaceMotionEnabled() and not shortViewport then
			modal.Size = UDim2.fromOffset(438, 442)
			modal.BackgroundTransparency = 1
			TweenService
				:Create(
					modal,
					TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
					{
						Size = UDim2.fromOffset(460, 465),
						BackgroundTransparency = 0,
					}
				)
				:Play()
		end
	end

	local function showDutySelection(role: any, dutyProfile: any)
		local shade = Instance.new("TextButton")
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.25
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 20
		shade.Parent = root
		local modal = Instance.new("Frame")
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.Position = UDim2.fromScale(0.5, 0.5)
		-- Clamped, like every other modal here. Fixed at 390 tall it was already
		-- flush to both edges of a four hundred pixel phone before the top bar,
		-- and it grows by a button for every spawn point, so the Cancel control
		-- was pushed off screen at a station with more than a couple. This is the
		-- last step before a player actually reaches the game.
		local safe = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
		modal.Size = UDim2.fromOffset(math.min(480, safe.X - 32), math.min(390, safe.Y - 32))
		modal.BackgroundColor3 = COLOURS.Surface
		modal.BorderSizePixel = 0
		modal.ZIndex = 21
		modal.Parent = shade
		corner(modal, 15)
		stroke(modal)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 26)
		padding.PaddingBottom = UDim.new(0, 26)
		padding.PaddingLeft = UDim.new(0, 26)
		padding.PaddingRight = UDim.new(0, 26)
		padding.Parent = modal
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = modal
		local title = text(modal, "Start " .. role.Name, 23, COLOURS.Text, true)
		title.LayoutOrder = 1
		title.Size = UDim2.new(1, 0, 0, 34)
		local copy =
			text(modal, "Choose exactly where you want to report for duty.", 13, COLOURS.Muted)
		copy.LayoutOrder = 2
		copy.Size = UDim2.new(1, 0, 0, 30)
		local spawnOptions = role.Spawns or {}
		local modalHeight = math.min(520, math.max(390, 250 + #spawnOptions * 58))
		modal.Size =
			UDim2.fromOffset(math.min(480, safe.X - 32), math.min(modalHeight, safe.Y - 32))
		for index, spawnOption in spawnOptions do
			local displayName = string.gsub(spawnOption.SpawnId, "(%l)(%u)", "%1 %2")
			local choice = button(modal, spawnOption.StationName .. "  ·  " .. displayName, false)
			choice.LayoutOrder = 10 + index
			choice.Size = UDim2.new(1, 0, 0, 48)
			choice.Activated:Connect(function()
				choice.Text = "Starting duty…"
				local response = context.Controllers.DutyController:Begin({
					DutyProfileId = dutyProfile.ProfileId,
					RoleId = role.Id,
					StationId = spawnOption.StationId,
					SpawnId = spawnOption.SpawnId,
				})
				if response.Success then
					shade:Destroy()
					dismissToWorld()
				else
					choice.Text = spawnOption.StationName .. "  ·  " .. displayName
				end
			end)
		end
		local cancel = button(modal, "Cancel", false)
		cancel.LayoutOrder = 100
		cancel.Size = UDim2.new(1, 0, 0, 44)
		cancel.Activated:Connect(function()
			shade:Destroy()
		end)
		elevate(modal, 22)
	end

	local renderPlay: () -> ()
	local renderCommunity: () -> ()
	local renderCareers: () -> ()
	local renderJobs: () -> ()
	local renderStore: () -> ()
	local renderTutorials: () -> ()
	local renderSettings: () -> ()
	local renderControls: () -> ()
	local currentRender: (() -> ())? = nil
	local function shortLandscape(): boolean
		local viewport = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
		return viewport.X > viewport.Y and viewport.Y < 720
	end
	local function portraitCardColumns(): number
		local width = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		if width >= 1180 then
			return 4
		elseif width >= 840 then
			return 3
		elseif width >= 560 then
			return 2
		end
		return 1
	end
	-- Bumped by every render. A page that asks the server for anything yields,
	-- and clearing the container before the yield does not help: two renders both
	-- clear, both wait, and then both append, so the page appears twice. After a
	-- yield a render checks it is still the current one and gives up if not.
	local renderGeneration = 0
	dismissToWorld = function()
		setMenuOpen(false)
		if not interfaceMotionEnabled() then
			gui.Enabled = false
			return
		end
		TweenService:Create(
			root,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.17, function()
			gui.Enabled = false
		end)
	end

	local function sectionHeading(titleValue: string, subtitle: string)
		local compact = shortLandscape()
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.new(1, 0, 0, if compact then 42 else 54)
		wrapper.Parent = scroll
		local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		wrapper.LayoutOrder = nextOrder
		local titleItem = text(wrapper, titleValue, 17, COLOURS.Text, true)
		titleItem.Size = UDim2.new(1, 0, 0, if compact then 23 else 28)
		titleItem.TextSize = if compact then 16 else 17
		local subtitleItem = text(wrapper, subtitle, 13, COLOURS.Muted)
		subtitleItem.Position = UDim2.fromOffset(0, if compact then 23 else 29)
		subtitleItem.Size = UDim2.new(1, 0, 0, if compact then 17 else 20)
		subtitleItem.TextSize = if compact then 11 else 13
	end

	renderPlay = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Players"
		pageDescription.Text = "Choose who you want to be today."
		sectionHeading(
			"Your characters",
			"Civilian lives keep their own money, vehicles and property."
		)
		local landscape = shortLandscape()
		local function enterCivilian(characterId: string)
			local spawnId = "CityCivilian"
			for _, role in menuData.Roles do
				if role.Id == "Civilian" and role.Spawns[1] then
					spawnId = role.Spawns[1].SpawnId
				end
			end
			-- EnterCivilian requires the server session's ActiveCharacterId to
			-- match the card being used. Selecting here also makes switching
			-- between civilian identities deterministic instead of relying on a
			-- previous session selection.
			local selected = context.Controllers.CharacterController:Select(characterId)
			if not selected.Success then
				return
			end
			local response = context.Controllers.DutyController:EnterCivilian(characterId, spawnId)
			if response.Success then
				dismissToWorld()
			end
		end
		if not menuData or #menuData.Characters == 0 then
			local empty = card(scroll, if landscape then 108 else 150)
			local titleItem = text(empty, "Start your first story", 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(20, if landscape then 13 else 18)
			titleItem.Size = UDim2.new(1, -210, 0, 28)
			local copy =
				text(empty, "Create a civilian identity to enter the city.", 13, COLOURS.Muted)
			copy.Position = UDim2.fromOffset(20, if landscape then 42 else 50)
			copy.Size = UDim2.new(1, -210, 0, 50)
			copy.TextWrapped = true
			local create = button(empty, "Create character", true)
			create.AnchorPoint = Vector2.new(1, 0.5)
			create.Position = UDim2.new(1, -20, 0.5, 0)
			create.Activated:Connect(showModal)
		else
			local columns = portraitCardColumns()
			local tileHeight = if landscape then 258 else 284
			local canCreate = menuData.EmptySlots > 0
			local characterGrid = tileGrid(
				scroll,
				#menuData.Characters + (if canCreate then 1 else 0),
				tileHeight,
				columns
			)
			for _, character in menuData.Characters do
				local item = card(characterGrid, tileHeight)
				item.ClipsDescendants = true
				local selected = selectedCharacterId == character.CharacterId
				local selectedRail = Instance.new("Frame")
				selectedRail.BackgroundColor3 = if selected then COLOURS.Success else COLOURS.Accent
				selectedRail.BorderSizePixel = 0
				selectedRail.Size = UDim2.new(1, 0, 0, 4)
				selectedRail.Parent = item
				local preview = portraitPreview(
					item,
					COLOURS.Accent,
					character.PreviewAppearance,
					function()
						return item.Parent == characterGrid
					end
				)
				preview.Position = UDim2.fromOffset(12, 14)
				preview.Size = UDim2.new(1, -24, 0, if landscape then 112 else 132)
				local name = text(item, character.FullName, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(16, if landscape then 134 else 156)
				name.Size = UDim2.new(1, -32, 0, 27)
				local dob = text(item, "Born " .. character.DateOfBirth, 12, COLOURS.Muted)
				dob.Position = UDim2.fromOffset(16, if landscape then 160 else 182)
				dob.Size = UDim2.new(1, -32, 0, 22)
				local identity = text(item, "CIVILIAN CHARACTER", 11, COLOURS.Accent, true)
				identity.Position = UDim2.fromOffset(16, if landscape then 183 else 205)
				identity.Size = UDim2.new(1, -32, 0, 18)
				local choose = button(item, if selected then "Enter city" else "Choose", selected)
				choose.AnchorPoint = Vector2.new(0, 1)
				choose.Position = UDim2.new(0, 16, 1, -14)
				choose.Size = UDim2.new(1, -32, 0, 42)
				if
					selected
					and Players.LocalPlayer.Team
					and Players.LocalPlayer.Team.Name == "Civilian"
				then
					choose.Position = UDim2.new(0, 16, 1, -14)
					choose.Size = UDim2.new(1, -32, 0, 36)
					local saveOutfit = button(item, "Save current outfit", false)
					saveOutfit.AnchorPoint = Vector2.new(0, 1)
					saveOutfit.Position = UDim2.new(0, 16, 1, -56)
					saveOutfit.Size = UDim2.new(1, -32, 0, 30)
					saveOutfit.TextSize = 11
					saveOutfit.Activated:Connect(function()
						saveOutfit.Text = "Saving…"
						local response =
							context.Controllers.CharacterController:SaveCurrentAppearance(
								character.CharacterId
							)
						if response.Success then
							context.Controllers.NotificationController:Show(
								"This civilian now keeps the current Roblox avatar outfit.",
								"Outfit saved"
							)
							context.Controllers.StartMenuController:Refresh()
						else
							saveOutfit.Text = "Save current outfit"
						end
					end)
				end
				choose.Activated:Connect(function()
					if selected then
						enterCivilian(character.CharacterId)
						return
					end
					local response =
						context.Controllers.CharacterController:Select(character.CharacterId)
					if response.Success then
						selectedCharacterId = character.CharacterId
						context.Controllers.NotificationController:Show(
							"Character selected.",
							"Ready"
						)
						renderPlay()
					end
				end)
			end
			if canCreate then
				local createCard = card(characterGrid, tileHeight)
				createCard.ClipsDescendants = true
				local createPreview = Instance.new("Frame")
				createPreview.BackgroundColor3 = COLOURS.SurfaceRaised
				createPreview.BorderSizePixel = 0
				createPreview.Position = UDim2.fromOffset(12, 14)
				createPreview.Size = UDim2.new(1, -24, 0, if landscape then 112 else 132)
				createPreview.Parent = createCard
				corner(createPreview, 12)
				stroke(createPreview, COLOURS.Accent, 0.62)
				local plus = text(createPreview, "+", 42, COLOURS.Accent, true)
				plus.Size = UDim2.fromScale(1, 1)
				plus.TextXAlignment = Enum.TextXAlignment.Center
				local createTitle = text(createCard, "New character", 17, COLOURS.Text, true)
				createTitle.Position = UDim2.fromOffset(16, if landscape then 134 else 156)
				createTitle.Size = UDim2.new(1, -32, 0, 27)
				local createCopy =
					text(createCard, "Create another civilian identity.", 13, COLOURS.Muted)
				createCopy.Position = UDim2.fromOffset(16, if landscape then 163 else 185)
				createCopy.Size = UDim2.new(1, -32, 0, 40)
				createCopy.TextWrapped = true
				local create = button(createCard, "Create character", false)
				create.AnchorPoint = Vector2.new(0, 1)
				create.Position = UDim2.new(0, 16, 1, -14)
				create.Size = UDim2.new(1, -32, 0, 42)
				create.Activated:Connect(showModal)
			end
		end
	end

	renderCareers = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Emergency services"
		pageDescription.Text = "Join a department, report for duty and start your next shift."

		local roles = menuData and menuData.Roles or {}
		local landscape = shortLandscape()
		local careerGeneration = renderGeneration
		local visibleCount = 0
		for _, role in roles do
			if role.Visible and role.Id ~= "Civilian" and role.DepartmentId ~= "Civilian" then
				visibleCount += 1
			end
		end

		sectionHeading(
			"Departments",
			string.format("%d roles available in this server.", visibleCount)
		)
		local columns = portraitCardColumns()
		local tileHeight = if landscape then 262 else 286
		local roleGrid = tileGrid(scroll, visibleCount, tileHeight, columns)
		if visibleCount == 0 then
			local empty = card(roleGrid, tileHeight)
			local emptyTitle = text(empty, "No roles available", 18, COLOURS.Text, true)
			emptyTitle.Position = UDim2.fromOffset(20, 22)
			emptyTitle.Size = UDim2.new(1, -40, 0, 30)
			local emptyCopy = text(
				empty,
				"This server has not made any departments available yet.",
				13,
				COLOURS.Muted
			)
			emptyCopy.Position = UDim2.fromOffset(20, 56)
			emptyCopy.Size = UDim2.new(1, -40, 0, 52)
			emptyCopy.TextWrapped = true
		end
		for _, role in roles do
			if role.Visible and role.Id ~= "Civilian" and role.DepartmentId ~= "Civilian" then
				local presentation = rolePresentation(role)
				local item = card(roleGrid, tileHeight)
				item.Name = "Career_" .. tostring(role.Id)
				item.ClipsDescendants = true
				local rail = Instance.new("Frame")
				rail.BackgroundColor3 = presentation.Colour
				rail.BackgroundTransparency = if role.Locked then 0.42 else 0
				rail.BorderSizePixel = 0
				rail.Size = UDim2.new(1, 0, 0, 4)
				rail.Parent = item
				local preview = portraitPreview(
					item,
					presentation.Colour,
					role.PreviewUniform,
					function()
						return renderGeneration == careerGeneration and item.Parent == roleGrid
					end
				)
				preview.Position = UDim2.fromOffset(12, 14)
				preview.Size = UDim2.new(1, -24, 0, if landscape then 102 else 118)
				if role.Locked then
					preview.ImageTransparency = 0.28
				end
				local departmentBadge = Instance.new("Frame")
				departmentBadge.BackgroundColor3 = presentation.Colour
				departmentBadge.BackgroundTransparency = 0.82
				departmentBadge.BorderSizePixel = 0
				departmentBadge.Position = UDim2.fromOffset(16, if landscape then 127 else 143)
				departmentBadge.Size = UDim2.fromOffset(34, 34)
				departmentBadge.Parent = item
				corner(departmentBadge, 8)
				stroke(departmentBadge, presentation.Colour, 0.48)
				local badgeText =
					text(departmentBadge, presentation.Icon, 10, presentation.Colour, true)
				badgeText.Size = UDim2.fromScale(1, 1)
				badgeText.TextXAlignment = Enum.TextXAlignment.Center
				local category = text(item, presentation.Label, 10, presentation.Colour, true)
				category.Position = UDim2.fromOffset(58, if landscape then 126 else 142)
				category.Size = UDim2.new(1, -144, 0, 16)
				local access = text(
					item,
					if role.Locked then "LOCKED" else "AVAILABLE",
					10,
					if role.Locked then COLOURS.Muted else COLOURS.Success,
					true
				)
				access.AnchorPoint = Vector2.new(1, 0)
				access.Position = UDim2.new(1, -16, 0, if landscape then 126 else 142)
				access.Size = UDim2.fromOffset(70, 16)
				access.TextXAlignment = Enum.TextXAlignment.Right
				local name = text(item, role.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(58, if landscape then 142 else 158)
				name.Size = UDim2.new(1, -74, 0, 28)
				name.TextWrapped = true
				name.TextTruncate = Enum.TextTruncate.None
				-- What this row can tell the player that the others cannot.
				--
				-- Every unlocked role used to read "Cleared to report for duty." in
				-- green, which is the same sentence on every row a player can
				-- actually use. A line repeated on every row carries no information,
				-- and it was competing for attention with the locked rows, which are
				-- the only ones that genuinely need reading. The button beside it
				-- already says the role is available.
				--
				-- Where they would start is the thing they are about to be asked for,
				-- so it is what the line says instead.
				local detailText = role.LockMessage
				if not role.Locked then
					local spawns = role.Spawns or {}
					if #spawns == 1 then
						detailText = "Reports from " .. tostring(spawns[1].StationName)
					elseif #spawns > 1 then
						detailText = string.format("%d places to report", #spawns)
					else
						detailText = ""
					end
				end
				local detail = text(item, detailText, 12, COLOURS.Muted)
				detail.Position = UDim2.fromOffset(16, if landscape then 169 else 185)
				detail.Size = UDim2.new(1, -32, 0, 30)
				detail.TextWrapped = true
				detail.TextYAlignment = Enum.TextYAlignment.Top
				detail.TextTruncate = Enum.TextTruncate.None

				local actionLabel = "Report for duty"
				if role.Locked then
					actionLabel = if role.Action == "PromptGamepass"
						then "Unlock role"
						elseif role.Action == "OpenApplication" then "View application"
						else "View requirements"
				end
				local action = button(item, actionLabel, false)
				action.AnchorPoint = Vector2.new(0, 1)
				action.Position = UDim2.new(0, 16, 1, -14)
				action.Size = UDim2.new(1, -32, 0, 42)
				if not role.Locked then
					action.BackgroundColor3 = presentation.Colour:Lerp(COLOURS.Surface, 0.78)
					action.TextColor3 = presentation.Colour:Lerp(Color3.new(1, 1, 1), 0.28)
					local actionStroke = action:FindFirstChildOfClass("UIStroke")
					if actionStroke then
						actionStroke.Color = presentation.Colour
						actionStroke.Transparency = 0.5
					end
				elseif role.Action ~= "PromptGamepass" then
					action.TextColor3 = COLOURS.Muted
				end
				action.Selectable = true
				action.Activated:Connect(function()
					if role.Locked then
						if role.Action == "PromptGamepass" then
							local gamepassId = tonumber(role.GamepassId)
							if not gamepassId or gamepassId <= 0 then
								context.Controllers.NotificationController:Show(
									"This pass is not available for purchase yet.",
									"Pass unavailable"
								)
								return
							end
							local prompted, promptError =
								context.Controllers.GamepassController:Prompt(gamepassId)
							if not prompted then
								context.Controllers.NotificationController:Show(
									promptError or "The Roblox purchase prompt could not be opened.",
									"Purchase unavailable"
								)
							end
							return
						end
						context.Controllers.NotificationController:Show(
							role.LockMessage,
							if role.Action == "OpenApplication"
								then "Application required"
								else "Access required"
						)
						return
					end
					if not role.DepartmentId then
						context.Controllers.NotificationController:Show(
							"Select Civilian from the Play screen.",
							"Public role"
						)
						return
					end
					local dutyProfile = nil
					for _, profile in menuData.DutyProfiles or {} do
						if profile.DepartmentId == role.DepartmentId then
							dutyProfile = profile
							break
						end
					end
					if not dutyProfile or not role.Spawns or #role.Spawns == 0 then
						context.Controllers.NotificationController:Show(
							"No valid duty profile or station is available.",
							"Duty unavailable"
						)
						return
					end
					showDutySelection(role, dutyProfile)
				end)
			end
		end
	end

	renderJobs = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Civilian jobs"
		pageDescription.Text =
			"Choose civilian employment systems when they are installed in this experience."
		sectionHeading(
			"Employment catalogue",
			"These are safe framework slots for future job systems; no job is granted from this menu alone."
		)
		local jobs = {}
		for _, job in menuData and menuData.Jobs or {} do
			table.insert(jobs, job)
		end
		table.sort(jobs, function(a, b)
			return tostring(a.Name) < tostring(b.Name)
		end)
		if #jobs == 0 then
			local empty = card(scroll, 112)
			local copy =
				text(empty, "No civilian job systems are installed yet.", 14, COLOURS.Muted)
			copy.Position = UDim2.fromOffset(20, 20)
			copy.Size = UDim2.new(1, -40, 0, 28)
			return
		end
		local columns = portraitCardColumns()
		local grid = tileGrid(scroll, #jobs, 156, columns)
		for _, job in jobs do
			local item = card(grid, 156)
			local rail = Instance.new("Frame")
			rail.BackgroundColor3 = COLOURS.Accent
			rail.BorderSizePixel = 0
			rail.Size = UDim2.new(1, 0, 0, 3)
			rail.Parent = item
			local title = text(item, tostring(job.Name), 16, COLOURS.Text, true)
			title.Position = UDim2.fromOffset(16, 18)
			title.Size = UDim2.new(1, -32, 0, 24)
			local access = tostring(job.Class) == "Public" and "PUBLIC EMPLOYMENT"
				or "APPLICATION ROLE"
			local detail = text(
				item,
				access .. "  ·  £" .. tostring(job.BaseWage or 0) .. " base wage",
				11,
				true
			)
			detail.Position = UDim2.fromOffset(16, 51)
			detail.Size = UDim2.new(1, -32, 0, 20)
			detail.TextColor3 = if access == "PUBLIC EMPLOYMENT"
				then COLOURS.Success
				else COLOURS.Warning
			local jobStatus = text(item, "Job system not installed", 11, COLOURS.Muted)
			jobStatus.Position = UDim2.fromOffset(16, 82)
			jobStatus.Size = UDim2.new(1, -32, 0, 22)
			local comingSoon = button(item, "COMING SOON", false)
			comingSoon.Position = UDim2.new(1, -126, 1, -44)
			comingSoon.Size = UDim2.fromOffset(110, 30)
			comingSoon.TextSize = 10
			comingSoon.TextColor3 = COLOURS.Muted
			comingSoon.Selectable = false
		end
	end

	renderStore = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Store"
		pageDescription.Text = "Optional access and upgrades for this experience."
		sectionHeading(
			"RoleplayOS passes",
			"Purchases are handled by Roblox. Your access refreshes automatically."
		)
		if not menuData or not menuData.Gamepasses then
			local loading = card(scroll, 90)
			local loadingCopy = text(loading, "Loading available passes…", 14, COLOURS.Muted)
			loadingCopy.Position = UDim2.fromOffset(20, 0)
			loadingCopy.Size = UDim2.new(1, -40, 1, 0)
			return
		end

		local safeWidth = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		local columns = if safeWidth >= 1180
			then 4
			else if safeWidth >= 840 then 3 else if safeWidth >= 560 then 2 else 1
		local categories = {}
		local categoryOrder = {}
		for _, pass in menuData.Gamepasses do
			if not categories[pass.Category] then
				categories[pass.Category] = {}
				table.insert(categoryOrder, pass.Category)
			end
			table.insert(categories[pass.Category], pass)
		end
		if selectedStoreCategory and not categories[selectedStoreCategory] then
			selectedStoreCategory = nil
		end
		local categoryBar = Instance.new("ScrollingFrame")
		categoryBar.Name = "ProductCategories"
		categoryBar.BackgroundColor3 = COLOURS.Surface
		categoryBar.BorderSizePixel = 0
		categoryBar.Size = UDim2.new(1, 0, 0, 58)
		categoryBar.AutomaticCanvasSize = Enum.AutomaticSize.X
		categoryBar.CanvasSize = UDim2.new()
		categoryBar.ScrollBarThickness = 0
		categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
		categoryBar.Parent = scroll
		local categoryOrderIndex = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", categoryOrderIndex)
		categoryBar.LayoutOrder = categoryOrderIndex
		corner(categoryBar, 12)
		stroke(categoryBar)
		local categoryPadding = Instance.new("UIPadding")
		categoryPadding.PaddingLeft = UDim.new(0, 8)
		categoryPadding.PaddingRight = UDim.new(0, 8)
		categoryPadding.PaddingTop = UDim.new(0, 7)
		categoryPadding.PaddingBottom = UDim.new(0, 7)
		categoryPadding.Parent = categoryBar
		local categoryLayout = Instance.new("UIListLayout")
		categoryLayout.FillDirection = Enum.FillDirection.Horizontal
		categoryLayout.Padding = UDim.new(0, 8)
		categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
		categoryLayout.Parent = categoryBar
		local tabs = { "All" }
		for _, category in categoryOrder do
			table.insert(tabs, tostring(category))
		end
		for _, category in tabs do
			local selected = (category == "All" and selectedStoreCategory == nil)
				or selectedStoreCategory == category
			local tab = button(categoryBar, category, selected)
			tab.Size = UDim2.fromOffset(math.max(116, 32 + #category * 8), 44)
			tab.Activated:Connect(function()
				selectedStoreCategory = if category == "All" then nil else category
				renderStore()
			end)
		end
		for _, category in categoryOrder do
			if selectedStoreCategory and tostring(category) ~= selectedStoreCategory then
				continue
			end
			local passes = categories[category]
			local section = Instance.new("Frame")
			section.Name = "StoreSection_" .. tostring(category)
			section.BackgroundTransparency = 1
			section.Size = UDim2.new(1, 0, 0, 54)
			section.Parent = scroll
			local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
			scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
			section.LayoutOrder = nextOrder
			local categoryTitle = text(section, tostring(category), 18, COLOURS.Text, true)
			categoryTitle.Position = UDim2.fromOffset(2, 0)
			categoryTitle.Size = UDim2.new(1, -4, 0, 26)
			local categoryCopy = text(
				section,
				string.format("%d %s", #passes, if #passes == 1 then "option" else "options"),
				11,
				COLOURS.Muted
			)
			categoryCopy.Position = UDim2.fromOffset(2, 25)
			categoryCopy.Size = UDim2.new(1, -4, 0, 18)
			local passGrid = Instance.new("Frame")
			passGrid.Name = "Products"
			passGrid.BackgroundTransparency = 1
			passGrid.Position = UDim2.fromOffset(0, 52)
			passGrid.Size = UDim2.fromScale(1, 0)
			passGrid.Parent = section
			local passLayout = Instance.new("UIGridLayout")
			passLayout.SortOrder = Enum.SortOrder.LayoutOrder
			passLayout.CellPadding = UDim2.fromOffset(14, 14)
			passLayout.CellSize = UDim2.new(1 / columns, -14 * (columns - 1) / columns, 0, 250)
			passLayout.Parent = passGrid
			local function updateSectionHeight()
				local contentHeight = passLayout.AbsoluteContentSize.Y
				passGrid.Size = UDim2.new(1, 0, 0, contentHeight)
				section.Size = UDim2.new(1, 0, 0, 52 + contentHeight)
			end
			passLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSectionHeight)
			for _, pass in passes do
				local item = card(passGrid, 250)
				item.ClipsDescendants = true
				local artwork = Instance.new("Frame")
				artwork.Position = UDim2.fromOffset(12, 12)
				artwork.Size = UDim2.new(1, -24, 0, 78)
				artwork.BackgroundColor3 = if pass.Owned
					then Color3.fromRGB(22, 60, 50)
					else Color3.fromRGB(27, 43, 68)
				artwork.BorderSizePixel = 0
				artwork.Parent = item
				corner(artwork, 10)
				local artworkGradient = Instance.new("UIGradient")
				artworkGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, artwork.BackgroundColor3),
					ColorSequenceKeypoint.new(1, COLOURS.SurfaceRaised),
				})
				artworkGradient.Rotation = 18
				artworkGradient.Parent = artwork
				local imageId = tonumber(
					pass.ImageAssetId or pass.IconAssetId or pass.ImageId or pass.IconImageId
				)
				if imageId and imageId > 0 then
					local image = Instance.new("ImageLabel")
					image.BackgroundTransparency = 1
					image.Size = UDim2.fromScale(1, 1)
					image.Image = "rbxassetid://" .. tostring(imageId)
					image.ScaleType = Enum.ScaleType.Crop
					image.Parent = artwork
					corner(image, 10)
				else
					local monogram = text(
						artwork,
						string.upper(string.sub(pass.Name, 1, 2)),
						25,
						if pass.Owned then COLOURS.Success else COLOURS.Accent,
						true
					)
					monogram.Size = UDim2.fromScale(1, 1)
					monogram.TextXAlignment = Enum.TextXAlignment.Center
				end
				local name = text(item, pass.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(16, 98)
				name.Size = UDim2.new(1, -32, 0, 25)
				name.TextWrapped = true
				name.TextTruncate = Enum.TextTruncate.None
				local description = text(item, pass.Description, 12, COLOURS.Muted)
				description.Position = UDim2.fromOffset(16, 126)
				description.Size = UDim2.new(1, -32, 0, 40)
				description.TextWrapped = true
				description.TextYAlignment = Enum.TextYAlignment.Top
				description.TextTruncate = Enum.TextTruncate.AtEnd
				local price = tonumber(pass.PriceInRobux or pass.Price)
				local stateCopy = if pass.Owned
					then "OWNED"
					elseif price and price > 0 then string.format("R$ %d", price)
					elseif pass.Configured then "VIEW PRICE"
					else "NOT CONFIGURED"
				local state = text(
					item,
					stateCopy,
					10,
					if pass.Owned then COLOURS.Success else COLOURS.Accent,
					true
				)
				state.Position = UDim2.fromOffset(16, 170)
				state.Size = UDim2.new(1, -32, 0, 18)
				local actionLabel = if pass.Owned
					then "Owned"
					elseif not pass.Configured then "Unavailable"
					elseif not pass.AvailableInServer then "Public servers only"
					else "View pass"
				local purchase =
					button(item, actionLabel, not pass.Owned and pass.AvailableInServer)
				purchase.AnchorPoint = Vector2.new(0, 1)
				purchase.Position = UDim2.new(0, 16, 1, -14)
				purchase.Size = UDim2.new(1, -32, 0, 40)
				purchase.Selectable = pass.Configured and pass.AvailableInServer and not pass.Owned
				purchase.Active = purchase.Selectable
				if purchase.Active then
					purchase.Activated:Connect(function()
						if pass.PurchaseType == "DeveloperProduct" then
							MarketplaceService:PromptProductPurchase(
								Players.LocalPlayer,
								pass.ProductId
							)
						else
							context.Controllers.GamepassController:Prompt(pass.GamepassId)
						end
					end)
				else
					purchase.BackgroundColor3 = COLOURS.SurfaceRaised
					purchase.TextColor3 = if pass.Owned then COLOURS.Success else COLOURS.Muted
				end
			end
			updateSectionHeight()
		end
	end

	local tutorials = {
		{
			Title = "Starting your character",
			Summary = "Create an identity, choose a role and enter Portsmouth.",
			Body = "Create or select a civilian character under Players. Careers then shows every public and whitelisted role available to you. Locked cards explain the exact requirement.",
		},
		{
			Title = "Emergency calls",
			Summary = "Learn how calls reach Control, MDT and responding units.",
			Body = "Use the phone to contact 999. Control creates and grades an incident, assigns available units and updates its status. Relevant emergency teams receive the server-local call through their MDT.",
		},
		{
			Title = "Police and custody",
			Summary = "Understand cautions, arrest, transport and booking.",
			Body = "Police tools are server-authorised. Officers caution and restrain a nearby player, transport them to custody and complete booking. Charges determine the custody duration and persistent record.",
		},
		{
			Title = "Vehicles and dealerships",
			Summary = "Buy, spawn and keep your registered vehicles.",
			Body = "Visit a dealership prompt to browse civilian vehicles. Owned vehicles retain their registration. Service depots show vehicles allowed by your current role, rank and division.",
		},
		{
			Title = "Controls and accessibility",
			Summary = "See the correct inputs for your current device.",
			Body = "Open Controls for keyboard, touch, gamepad, console and VR bindings. Roblox prompts remain the authority for contextual interactions such as dealerships and dispatch seats.",
		},
	}

	renderTutorials = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Tutorials"
		pageDescription.Text = "Learn each system before starting your roleplay."
		sectionHeading("Game guides", "Short, practical explanations of the live systems.")
		local utilities = card(scroll, 78)
		local controls = button(utilities, "Controls", false)
		controls.Position = UDim2.fromOffset(18, 17)
		controls.Size = UDim2.new(0.5, -27, 0, 44)
		controls.Activated:Connect(renderControls)
		local settings = button(utilities, "Settings", false)
		settings.Position = UDim2.new(0.5, 9, 0, 17)
		settings.Size = UDim2.new(0.5, -27, 0, 44)
		settings.Activated:Connect(renderSettings)
		local compactTutorials = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X < 650
		for index, tutorial in tutorials do
			local item = card(scroll, if compactTutorials then 166 else 124)
			local number = text(item, string.format("%02d", index), 13, COLOURS.Accent, true)
			number.Position = UDim2.fromOffset(20, 18)
			number.Size = UDim2.fromOffset(34, 24)
			local titleItem = text(item, tutorial.Title, 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(58, 16)
			titleItem.Size = UDim2.new(1, if compactTutorials then -76 else -230, 0, 28)
			local summary = text(item, tutorial.Summary, 13, COLOURS.Muted)
			summary.Position = UDim2.fromOffset(58, 44)
			summary.Size = UDim2.new(1, if compactTutorials then -76 else -250, 0, 54)
			summary.TextWrapped = true
			local open = button(item, "Open guide", false)
			open.AnchorPoint = if compactTutorials then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			open.Position = if compactTutorials
				then UDim2.new(0, 18, 1, -14)
				else UDim2.new(1, -18, 0.5, 0)
			open.Size = if compactTutorials
				then UDim2.new(1, -36, 0, 40)
				else UDim2.fromOffset(150, 42)
			open.Activated:Connect(function()
				local shade = Instance.new("TextButton")
				shade.Text = ""
				shade.AutoButtonColor = false
				shade.BackgroundColor3 = Color3.new(0, 0, 0)
				shade.BackgroundTransparency = 0.2
				shade.Size = UDim2.fromScale(1, 1)
				shade.ZIndex = 20
				shade.Parent = root
				local guide = card(shade, 300)
				guide.AnchorPoint = Vector2.new(0.5, 0.5)
				guide.Position = UDim2.fromScale(0.5, 0.5)
				local guideViewport = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
				guide.Size = UDim2.fromOffset(
					math.min(520, guideViewport.X - 32),
					math.min(300, guideViewport.Y - 32)
				)
				guide.ZIndex = 21
				local guideTitle = text(guide, tutorial.Title, 23, COLOURS.Text, true)
				guideTitle.Position = UDim2.fromOffset(28, 24)
				guideTitle.Size = UDim2.new(1, -56, 0, 36)
				local guideBody = text(guide, tutorial.Body, 15, COLOURS.Muted)
				guideBody.Position = UDim2.fromOffset(28, 70)
				guideBody.Size = UDim2.new(1, -56, 0, 140)
				guideBody.TextWrapped = true
				guideBody.TextYAlignment = Enum.TextYAlignment.Top
				local close = button(guide, "Close", true)
				close.AnchorPoint = Vector2.new(1, 1)
				close.Position = UDim2.new(1, -28, 1, -24)
				close.Size = UDim2.fromOffset(140, 42)
				close.Activated:Connect(function()
					shade:Destroy()
				end)
				elevate(guide, 22)
			end)
		end
	end

	renderSettings = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Advanced settings"
		pageDescription.Text = "Accessible, responsive controls for this experience."
		sectionHeading(
			"Interface and accessibility",
			"Roblox-native volume, graphics and controls remain in the Roblox menu."
		)
		local settings = context.Controllers.SettingsController:Get()
		if not settings then
			local unavailable = card(scroll, 80)
			local message = text(unavailable, "Settings are still loading.", 14, COLOURS.Muted)
			message.Position = UDim2.fromOffset(18, 18)
			message.Size = UDim2.new(1, -36, 0, 40)
			return
		end
		local function settingRow(
			titleValue: string,
			description: string,
			buttonText: string,
			onActivate: () -> ()
		)
			local row = card(scroll, 88)
			local titleItem = text(row, titleValue, 15, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(18, 12)
			titleItem.Size = UDim2.new(1, -210, 0, 25)
			local detail = text(row, description, 12, COLOURS.Muted)
			detail.Position = UDim2.fromOffset(18, 39)
			detail.Size = UDim2.new(1, -210, 0, 32)
			detail.TextWrapped = true
			local action = button(row, buttonText, false)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -16, 0.5, 0)
			action.Size = UDim2.fromOffset(160, 40)
			action.Activated:Connect(onActivate)
		end
		settingRow(
			"Interface scale",
			"Combines with your Roblox preferred text size.",
			settings.InterfaceScale,
			function()
				local nextValue = if settings.InterfaceScale == "Small"
					then "Standard"
					elseif settings.InterfaceScale == "Standard" then "Large"
					else "Small"
				context.Controllers.SettingsController:Update("InterfaceScale", nextValue)
				renderSettings()
			end
		)
		for _, definition in
			{
				{
					"Interface motion",
					"Interface transitions and button motion.",
					"InterfaceMotion",
				},
				{
					"High contrast",
					"Increases scene contrast and reduces colour wash.",
					"HighContrast",
				},
				{
					"Reduced effects",
					"Disables decorative particles, trails and beams locally.",
					"ReducedEffects",
				},
				{
					"Camera shake",
					"Allows game camera shake effects when implemented.",
					"CameraShake",
				},
				{ "Gameplay hints", "Shows contextual help and onboarding prompts.", "ShowHints" },
			}
		do
			local key = definition[3]
			settingRow(
				definition[1],
				definition[2],
				settings[key] and "Enabled" or "Disabled",
				function()
					context.Controllers.SettingsController:Update(key, not settings[key])
					renderSettings()
				end
			)
		end
	end

	-- Controls as an ordinary page rather than an overlay. It was the one item in
	-- the sidebar that opened something else entirely, which made it read as a
	-- different product from the four either side of it.
	renderControls = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Controls"
		pageDescription.Text = "Every action, and what it is bound to on your device."
		local controller = context.Controllers.ControlsController
		local data = controller:List()
		local order = data.ModeOrder
		local labels = data.ModeLabels
		local selected = controller:DetectedMode()

		local rowsHolder: Frame
		local modeButtons: { [string]: TextButton } = {}

		local function paint()
			for mode, item in modeButtons do
				local active = mode == selected
				item.BackgroundColor3 = if active then COLOURS.Accent else COLOURS.Canvas
				item.TextColor3 = if active then COLOURS.Text else COLOURS.Muted
			end
			for _, child in rowsHolder:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			for index, control in data.Controls do
				local row = Instance.new("Frame")
				row.LayoutOrder = index
				row.Size = UDim2.new(1, 0, 0, 42)
				-- Banded rather than bordered. A list this long reads faster when
				-- the eye can follow a stripe across to the binding.
				row.BackgroundColor3 = if index % 2 == 0 then COLOURS.Canvas else COLOURS.Surface
				row.BorderSizePixel = 0
				row.Parent = rowsHolder
				corner(row, 8)
				local action = text(row, tostring(control.Action), 14, COLOURS.Text)
				action.Position = UDim2.fromOffset(16, 0)
				action.Size = UDim2.new(0.5, -16, 1, 0)
				local binding =
					text(row, tostring(control[selected] or "—"), 14, COLOURS.Accent, true)
				binding.Position = UDim2.new(0.5, 4, 0, 0)
				binding.Size = UDim2.new(0.5, -20, 1, 0)
			end
		end

		sectionHeading("Your device", "Bindings change with what you are playing on.")
		local switcher = card(scroll, 62)
		local switcherLayout = Instance.new("UIListLayout")
		switcherLayout.FillDirection = Enum.FillDirection.Horizontal
		switcherLayout.Padding = UDim.new(0, 8)
		switcherLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		switcherLayout.Parent = switcher
		local switcherPadding = Instance.new("UIPadding")
		switcherPadding.PaddingLeft = UDim.new(0, 12)
		switcherPadding.PaddingRight = UDim.new(0, 12)
		switcherPadding.Parent = switcher
		for index, mode in order do
			local item = Instance.new("TextButton")
			item.AutoButtonColor = false
			item.BackgroundColor3 = COLOURS.Canvas
			item.BorderSizePixel = 0
			item.Font = Enum.Font.GothamBold
			item.LayoutOrder = index
			item.Text = tostring(labels[mode] or mode)
			item.TextColor3 = COLOURS.Muted
			item.TextSize = 11
			item.Size = UDim2.new(1 / #order, -6, 0, 38)
			item.Parent = switcher
			corner(item, 9)
			pressable(item)
			modeButtons[mode] = item
			item.Activated:Connect(function()
				selected = mode
				paint()
			end)
		end

		sectionHeading("Controls", "Held actions are marked where they differ.")
		local listCard = card(scroll, 0)
		listCard.AutomaticSize = Enum.AutomaticSize.Y
		local listPadding = Instance.new("UIPadding")
		listPadding.PaddingTop = UDim.new(0, 10)
		listPadding.PaddingBottom = UDim.new(0, 10)
		listPadding.PaddingLeft = UDim.new(0, 10)
		listPadding.PaddingRight = UDim.new(0, 10)
		listPadding.Parent = listCard
		rowsHolder = Instance.new("Frame")
		rowsHolder.BackgroundTransparency = 1
		rowsHolder.Size = UDim2.fromScale(1, 0)
		rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
		rowsHolder.Parent = listCard
		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.Padding = UDim.new(0, 4)
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Parent = rowsHolder

		paint()
	end

	-- Three questions, in the order somebody actually asks them: where am I, where
	-- else can I go, and what about my own community.
	--
	-- The page used to open on a tall block of marketing copy, carried two
	-- headings both called "Your server", and left the servers you could actually
	-- join below the fold. Nothing here is decoration: the status strip answers
	-- the first question in one line so the rest of the page can be the answer to
	-- the second.
	renderCommunity = function()
		renderGeneration += 1
		local generation = renderGeneration
		clear(scroll)
		pageTitle.Text = "Servers"
		pageDescription.Text = "Move between official sessions without losing your place."
		local server = menuData and menuData.Server
		local kind = server and server.Kind or "Public"
		local community = server and server.Community

		local KIND_LABEL = {
			Public = "PUBLIC SERVER",
			Whitelisted = "WHITELISTED SERVER",
			Private = "PRIVATE SERVER",
			Reserved = "RESERVED SERVER",
		}
		local KIND_BLURB = {
			Public = "Open to everyone. Teams and passes are available here.",
			Whitelisted = "Entry is restricted, and services are held by group rank.",
			Private = "Run by its owner, to their own standards.",
			Reserved = "A dedicated instance of this experience.",
		}

		-- The servers the team runs, at the top. This is what almost everybody
		-- opens this page for, so nothing goes above it: not a status strip, not
		-- an explanation of what a community is.
		local officialResponse =
			context.Controllers.NetworkController:Request("GetOfficialServers", {})
		-- Another page was opened while that was in flight, so this one is stale
		-- and its container now belongs to whatever replaced it.
		if generation ~= renderGeneration then
			return
		end
		local officialRows = if officialResponse.Success
				and type(officialResponse.Data) == "table"
			then officialResponse.Data.Servers
			else nil
		if type(officialRows) == "table" and #officialRows > 0 then
			sectionHeading(
				"Official servers",
				"Choose the environment that matches how you want to play."
			)
			for _, entry in officialRows do
				local row = card(scroll, 118)
				local here = entry.Current == true
				local marker = Instance.new("Frame")
				marker.BackgroundColor3 = if here then COLOURS.Success else COLOURS.Accent
				marker.BorderSizePixel = 0
				marker.Position = UDim2.fromOffset(0, 16)
				marker.Size = UDim2.fromOffset(5, 86)
				marker.Parent = row
				local tier = text(
					row,
					if here then "CURRENT SESSION" else "OFFICIAL SERVER",
					11,
					if here then COLOURS.Success else COLOURS.Accent,
					true
				)
				tier.Position = UDim2.fromOffset(22, 16)
				tier.Size = UDim2.new(1, -190, 0, 16)
				local name = text(row, tostring(entry.Name), 21, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(22, 34)
				name.Size = UDim2.new(1, -190, 0, 28)
				local blurb = text(row, tostring(entry.Description or ""), 12, COLOURS.Muted)
				blurb.Position = UDim2.fromOffset(22, 66)
				blurb.Size = UDim2.new(1, -210, 0, 38)
				blurb.TextWrapped = true
				local join = Instance.new("TextButton")
				join.AutoButtonColor = false
				join.AnchorPoint = Vector2.new(1, 0.5)
				join.Position = UDim2.new(1, -20, 0.5, 0)
				join.Size = UDim2.fromOffset(140, 48)
				join.BackgroundColor3 = if here then COLOURS.SurfaceRaised else COLOURS.AccentFill
				join.BorderSizePixel = 0
				join.Font = Enum.Font.GothamBold
				join.Text = if here then "YOU ARE HERE" else "JOIN"
				join.TextColor3 = if here then COLOURS.Muted else COLOURS.Text
				join.TextSize = 13
				join.Active = not here
				join.Parent = row
				corner(join, 10)
				if not here then
					pressable(join)
				end
				join.Activated:Connect(function()
					if here then
						return
					end
					join.Active = false
					join.Text = "CONNECTING…"
					local response = context.Controllers.NetworkController:Request(
						"JoinOfficialServer",
						{ ServerId = entry.Id }
					)
					-- A teleport that works never comes back here, so anything
					-- arriving at this point is a refusal worth showing.
					join.Active = true
					join.Text = "JOIN"
					context.Controllers.NotificationController:Show(response.Message, "Servers")
				end)
			end
		end

		-- Where you are now, below the servers you might go to instead. It is
		-- context rather than an action, so it does not take the top of the page.
		sectionHeading("This server", "What you have joined, and what that allows.")
		local whereCard = card(scroll, 96)
		local accent = Instance.new("Frame")
		accent.BackgroundColor3 = if kind == "Public" then COLOURS.Accent else COLOURS.Success
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(0, 18)
		accent.Size = UDim2.fromOffset(4, 60)
		accent.Parent = whereCard
		local kindLabel = text(whereCard, KIND_LABEL[kind] or "SERVER", 11, COLOURS.Accent, true)
		kindLabel.Position = UDim2.fromOffset(20, 18)
		kindLabel.Size = UDim2.new(1, -40, 0, 18)
		local whereName = text(
			whereCard,
			(community and community.Name)
				or (server and server.AccessGroupName)
				or "Emergency Response: Portsmouth",
			19,
			COLOURS.Text,
			true
		)
		whereName.Position = UDim2.fromOffset(20, 38)
		whereName.Size = UDim2.new(1, -40, 0, 26)
		local whereBlurb = text(whereCard, KIND_BLURB[kind] or "", 12, COLOURS.Muted)
		whereBlurb.Position = UDim2.fromOffset(20, 64)
		whereBlurb.Size = UDim2.new(1, -40, 0, 18)
	end

	local activeNav: TextButton? = nil
	-- isAction entries run their callback without taking the selected-page
	-- highlight, so overlays like Controls do not blank the content area.
	local function addNav(labelValue: string, render: () -> (), isAction: boolean?)
		local item = Instance.new("TextButton")
		item.AutoButtonColor = false
		item.BackgroundColor3 = COLOURS.Sidebar
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamMedium
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 14
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Size = UDim2.new(1, 0, 0, 44)
		item.Parent = navigation
		corner(item, 9)
		local itemPadding = Instance.new("UIPadding")
		itemPadding.PaddingLeft = UDim.new(0, 14)
		itemPadding.Parent = item
		pressable(item)
		item.Activated:Connect(function()
			if isAction then
				render()
				return
			end
			if activeNav then
				activeNav.BackgroundColor3 = COLOURS.Sidebar
				activeNav.TextColor3 = COLOURS.Muted
			end
			activeNav = item
			currentRender = render
			item.BackgroundColor3 = COLOURS.AccentSoft
			item.TextColor3 = COLOURS.Text
			render()
		end)
		return item
	end

	local playNav = addNav("Players", renderPlay)
	addNav("Services", renderCareers)
	addNav("Civilian jobs", renderJobs)
	addNav("Store", renderStore)
	addNav("Servers", renderCommunity)
	addNav("Help", renderTutorials)
	activeNav = playNav
	currentRender = renderPlay
	playNav.BackgroundColor3 = COLOURS.AccentSoft
	playNav.TextColor3 = COLOURS.Text

	local profile = card(sidebar, 68)
	profile.AnchorPoint = Vector2.new(0, 1)
	profile.Position = UDim2.new(0, 18, 1, -20)
	profile.Size = UDim2.new(1, -36, 0, 68)
	local playerName = text(profile, Players.LocalPlayer.DisplayName, 14, COLOURS.Text, true)
	playerName.Position = UDim2.fromOffset(14, 11)
	playerName.Size = UDim2.new(1, -28, 0, 24)
	local environment = text(profile, "Development environment", 11, COLOURS.Muted)
	environment.Position = UDim2.fromOffset(14, 35)
	environment.Size = UDim2.new(1, -28, 0, 20)

	local function navCount(): number
		local count = 0
		for _, item in navigation:GetChildren() do
			if item:IsA("TextButton") then
				count += 1
			end
		end
		return math.max(1, count)
	end
	local lastResponsiveKey: string? = nil

	context.Controllers.UIOrchestrator:Bind("DeveloperDashboard", function(layout)
		local safeTop = layout.NativeTop
		local navItems = navCount()
		bleedBackdrop.Position = UDim2.fromOffset(0, -safeTop)
		bleedBackdrop.Size = UDim2.new(1, 0, 1, safeTop)
		-- Size the toggle from the band Roblox actually reports rather than the
		-- floor-clamped NativeTop, so it matches the height of the native controls
		-- instead of the taller safe region our own panels reserve.
		local reportedBand = math.floor(GuiService.TopbarInset.Height + 0.5)
		local nativeBand = if reportedBand > 0 then reportedBand else NATIVE_BAND_HEIGHT
		-- Roblox's reported top-bar inset includes breathing room around the actual
		-- controls. Using the entire inset made this control visibly taller and
		-- shifted it above the native cluster on scaled displays.
		local controlSize = math.clamp(math.floor(nativeBand * 0.78 + 0.5), 32, 52)
		local menuWidth = math.floor(controlSize * 1.72 + 0.5)
		menuToggle.Size = UDim2.fromOffset(menuWidth, controlSize)
		menuToggleCorner.CornerRadius = UDim.new(0, math.floor(controlSize * 0.34 + 0.5))
		-- Sit immediately right of the native control cluster. NativeLeft is the
		-- measured left edge of the region Roblox leaves free, so trust it when it
		-- is reported and fall back to the historical estimate only when Roblox
		-- reports no inset. Without this the toggle can render underneath Roblox's
		-- own top-bar buttons and become unreachable.
		local nativeControlWidth = if layout.NativeLeft > 0
			then layout.NativeLeft
			else (if layout.Compact then 224 else 360)
		menuToggle.Position = UDim2.fromOffset(
			math.min(
				nativeControlWidth + NATIVE_CONTROL_GAP,
				math.max(NATIVE_CONTROL_GAP, layout.Viewport.X - menuWidth - NATIVE_CONTROL_GAP)
			),
			-- Centre within the native band, never above the screen edge.
			math.max(0, math.floor((nativeBand - controlSize) / 2))
		)
		-- Compact already accounts for a short landscape phone, so the height is
		-- not tested again here.
		-- One navigation language on every device: a top bar mirrors Roblox's
		-- established menu pattern and avoids presenting desktop players with a
		-- completely different sidebar information architecture.
		local horizontal = true
		local narrow = layout.SafeViewport.X < 600
		local safeLeft = layout.SafeLeft
		local safeRight = layout.SafeRight
		if horizontal then
			local barHeight = safeTop + (if narrow then 112 else 82)
			sidebar.Size = UDim2.new(1, 0, 0, barHeight)
			content.Position = UDim2.fromOffset(0, barHeight)
			content.Size = UDim2.new(1, 0, 1, -barHeight)
			-- In this stacked layout the title shares its row with Roblox's own
			-- controls, which sit at the top left. safeLeft only describes a
			-- device cutout, so clearing that alone left the title underneath
			-- them in portrait, where the control cluster is proportionally much
			-- wider. NativeLeft is where Roblox reports its controls end.
			local headerLeft = math.max(safeLeft, layout.NativeLeft) + 18
			brand.Position = UDim2.fromOffset(headerLeft, safeTop + 8)
			brand.Size = UDim2.fromOffset(
				if narrow
					then math.max(80, layout.SafeViewport.X - headerLeft - safeRight - 18)
					else 270,
				30
			)
			brand.TextSize = 14
			brand.TextWrapped = false
			brand.TextTruncate = Enum.TextTruncate.AtEnd
			version.Position = UDim2.fromOffset(headerLeft + 1, safeTop + 37)
			-- Wide enough for the navigation to share the title's row, so it
			-- starts past the title rather than at a fixed offset that could
			-- land on top of it once the title has been pushed right.
			local navLeft = headerLeft + 282
			navigation.Position = if narrow
				then UDim2.fromOffset(safeLeft + 18, safeTop + 66)
				else UDim2.fromOffset(navLeft, safeTop + 18)
			navigation.Size = if narrow
				then UDim2.new(1, -(36 + safeLeft + safeRight), 0, 38)
				else UDim2.new(1, -(navLeft + 18 + safeRight), 0, 46)
			navLayout.FillDirection = Enum.FillDirection.Horizontal
			navLayout.Padding = UDim.new(0, 6)
			for _, item in navigation:GetChildren() do
				if item:IsA("TextButton") then
					item.Size = UDim2.new(1 / navItems, -5, 1, 0)
					-- Never below twelve. These are the only way to move around the menu, and
					-- ten pixels on the smallest screen is where they are least readable and
					-- most needed.
					item.TextSize = if narrow then 12 else 13
					item.TextXAlignment = Enum.TextXAlignment.Center
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new()
					end
				end
			end
			profile.Visible = false
			local contentWidth = math.min(1680, math.max(280, layout.SafeViewport.X - 48))
			local contentLeft = safeLeft + math.max(20, (layout.SafeViewport.X - contentWidth) / 2)
			header.Position = UDim2.fromOffset(contentLeft, 6)
			header.Size = UDim2.fromOffset(contentWidth, 28)
			pageTitle.Visible = false
			pageDescription.Visible = false
			status.Position = UDim2.fromScale(1, 0)
			scroll.Position = UDim2.fromOffset(contentLeft, 38)
			scroll.Size = UDim2.new(0, contentWidth, 1, -(46 + layout.SafeBottom))
		else
			-- The sidebar hugs the left edge, so it absorbs the left reserve and
			-- the content pane starts after it. Only the sidebar needs to know.
			sidebar.Size = UDim2.new(0, 250 + safeLeft, 1, 0)
			content.Position = UDim2.fromOffset(250 + safeLeft, 0)
			content.Size = UDim2.new(1, -(250 + safeLeft), 1, 0)
			brand.Position = UDim2.fromOffset(safeLeft + 26, safeTop + 20)
			brand.Size = UDim2.new(1, -(52 + safeLeft), 0, 42)
			brand.TextSize = 17
			brand.TextWrapped = true
			brand.TextTruncate = Enum.TextTruncate.None
			version.Position = UDim2.fromOffset(safeLeft + 27, safeTop + 66)
			navigation.Position = UDim2.fromOffset(safeLeft + 18, safeTop + 112)
			navigation.Size = UDim2.new(1, -(36 + safeLeft), 0, navItems * 44 + (navItems - 1) * 7)
			navLayout.FillDirection = Enum.FillDirection.Vertical
			navLayout.Padding = UDim.new(0, 7)
			for _, item in navigation:GetChildren() do
				if item:IsA("TextButton") then
					item.Size = UDim2.new(1, 0, 0, 44)
					item.TextSize = 14
					item.TextXAlignment = Enum.TextXAlignment.Left
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new(0, 14)
					end
				end
			end
			profile.Visible = true
			pageTitle.Visible = true
			header.Position = UDim2.fromOffset(44, safeTop + 30)
			header.Size = UDim2.new(1, -(88 + safeRight), 0, 76)
			pageTitle.TextSize = 30
			pageDescription.Visible = true
			status.Position = UDim2.new(1, -safeRight, 0, 9)
			scroll.Position = UDim2.fromOffset(44, safeTop + 118)
			scroll.Size = UDim2.new(1, -(88 + safeRight), 1, -(safeTop + 146 + layout.SafeBottom))
		end
		-- Cards have genuinely different compositions at these breakpoints, not
		-- merely different widths. Repaint only when a breakpoint changes so a
		-- phone rotation or window resize never leaves desktop cards squeezed into
		-- a mobile column, without doing work on every viewport-size signal.
		local responsiveKey = string.format(
			"%d:%s",
			portraitCardColumns(),
			if shortLandscape() then "short" else "standard"
		)
		if lastResponsiveKey and responsiveKey ~= lastResponsiveKey and currentRender then
			task.defer(currentRender)
		end
		lastResponsiveKey = responsiveKey
	end)

	context.Events.StartMenuChanged.Event:Connect(function(data)
		menuData = data
		if not selectedCharacterId and type(data.LastCharacterId) == "string" then
			-- Only when nothing is chosen yet, so a refresh never moves a choice
			-- the player has just made out from under them.
			for _, character in data.Characters or {} do
				if character.CharacterId == data.LastCharacterId then
					selectedCharacterId = data.LastCharacterId
					break
				end
			end
		end
		brand.Text = data.Framework.GameName
		version.Visible = data.Framework.ShowRoleplayOSMark
		status.Text = "●  ONLINE  ·  " .. string.upper(data.Server.Kind)
		status.TextColor3 = COLOURS.Success
		finishLoading()
		if currentRender then
			currentRender()
		end
	end)
	-- Paint immediately so the menu is on screen while the first request is still
	-- in flight. The StartMenuChanged handler above fills in real data on success.
	setMenuOpen(true)
	renderPlay()
	task.spawn(function()
		local response = context.Controllers.StartMenuController:Refresh()
		if response.Success then
			return
		end
		status.Text = "●  CONNECTION ERROR"
		status.TextColor3 = COLOURS.Danger
		-- The overlay comes down on failure too.
		--
		-- It was hidden in exactly one place, inside the handler that fires only
		-- when the first request succeeds. So a player whose request failed was
		-- left on a full screen cover, at ZIndex 100, with the progress bar still
		-- sliding back and forth for ever, while this very message was written to
		-- a label underneath it. The only way out was a button labelled "Skip
		-- loading", which reads like an impatience shortcut rather than the exit
		-- from a broken state.
		--
		-- This is the first twenty seconds of the game for everybody and the only
		-- screen a new player has seen, so it is the worst place in the interface
		-- to say nothing.
		loadingStatus.Text = "Could not reach the server."
		loadingStatus.TextColor3 = COLOURS.Danger
		retryLoading.Visible = true
		context.Controllers.NotificationController:Show(
			"Could not reach the server. Reopen the menu to retry, or rejoin if it keeps failing.",
			"Error"
		)
	end)

	if interfaceMotionEnabled() then
		root.Position = UDim2.fromOffset(0, 12)
		root.BackgroundTransparency = 1
		TweenService
			:Create(root, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 0,
			})
			:Play()
	end
	context.Controllers.SettingsController:Apply()
	return gui
end

return table.freeze(App)
