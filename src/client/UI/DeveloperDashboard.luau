--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
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
	Canvas = Color3.fromRGB(7, 10, 16),
	Sidebar = Color3.fromRGB(11, 15, 23),
	Surface = Color3.fromRGB(16, 21, 31),
	SurfaceRaised = Color3.fromRGB(21, 28, 41),
	Border = Color3.fromRGB(42, 52, 70),
	Text = Color3.fromRGB(240, 244, 251),
	Muted = Color3.fromRGB(142, 154, 176),
	Accent = Color3.fromRGB(91, 156, 255),
	AccentSoft = Color3.fromRGB(25, 51, 88),
	Success = Color3.fromRGB(84, 211, 142),
	Warning = Color3.fromRGB(245, 188, 78),
	Danger = Color3.fromRGB(244, 104, 112),
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, colour: Color3?, transparency: number?)
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
	item.BackgroundColor3 = if primary then COLOURS.Accent else COLOURS.SurfaceRaised
	item.Font = Enum.Font.GothamBold
	item.Text = label
	item.TextSize = 14
	item.TextColor3 = COLOURS.Text
	item.Size = UDim2.fromOffset(170, 44)
	item.Parent = parent
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
	corner(item, 12)
	stroke(item)
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
	menuToggleGui.DisplayOrder = 5
	menuToggleGui.Parent = gui.Parent
	-- The toggle is styled as an extra Roblox top-bar control rather than an
	-- experience button: a square, fully rounded, icon-only pill on the same
	-- translucent black as the native unibar, with no outline. Its size, radius
	-- and glyph size are recomputed from the measured top-bar band by the
	-- responsive binding below so it tracks whatever height Roblox reports on
	-- the current device.
	local menuToggle = Instance.new("TextButton")
	menuToggle.Name = "OpenMenu"
	menuToggle.Size = UDim2.fromOffset(NATIVE_CONTROL_SIZE, NATIVE_CONTROL_SIZE)
	menuToggle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	menuToggle.BackgroundTransparency = 0.5
	menuToggle.BorderSizePixel = 0
	menuToggle.AutoButtonColor = true
	menuToggle.Font = Enum.Font.GothamMedium
	menuToggle.Text = "☰"
	menuToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	menuToggle.TextSize = NATIVE_CONTROL_SIZE * 0.5
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 12, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 20, 32)),
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 12, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 20, 32)),
	})
	gradient.Rotation = 28
	gradient.Parent = root

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 250, 1, 0)
	sidebar.BackgroundColor3 = COLOURS.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = root
	local sidebarStroke = Instance.new("Frame")
	sidebarStroke.AnchorPoint = Vector2.new(1, 0)
	sidebarStroke.Position = UDim2.fromScale(1, 0)
	sidebarStroke.Size = UDim2.new(0, 1, 1, 0)
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
	flow.Padding = UDim.new(0, 14)
	flow.Parent = scroll

	local menuData: any = nil
	local selectedCharacterId: string? = nil
	local dismissToWorld: () -> ()
	local function interfaceMotionEnabled(): boolean
		local settings = context.Controllers.SettingsController:Get()
		return not settings or settings.InterfaceMotion ~= false
	end

	local function openFromWorld()
		gui.Enabled = true
		menuToggle.Visible = false
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

	menuToggle.Activated:Connect(openFromWorld)

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
		modal.Size = UDim2.fromOffset(480, 390)
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
		layout.Parent = modal
		local title = text(modal, "Start " .. role.Name, 23, COLOURS.Text, true)
		title.Size = UDim2.new(1, 0, 0, 34)
		local copy =
			text(modal, "Choose exactly where you want to report for duty.", 13, COLOURS.Muted)
		copy.Size = UDim2.new(1, 0, 0, 30)
		for _, spawnOption in role.Spawns or {} do
			local displayName = string.gsub(spawnOption.SpawnId, "(%l)(%u)", "%1 %2")
			local choice = button(modal, spawnOption.StationName .. "  ·  " .. displayName, false)
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
		cancel.Size = UDim2.new(1, 0, 0, 44)
		cancel.Activated:Connect(function()
			shade:Destroy()
		end)
		elevate(modal, 22)
	end

	local renderPlay: () -> ()
	local renderCommunity: () -> ()
	local renderCareers: () -> ()
	local renderSettings: () -> ()
	local renderControls: () -> ()
	dismissToWorld = function()
		if not interfaceMotionEnabled() then
			gui.Enabled = false
			menuToggle.Visible = true
			return
		end
		TweenService:Create(
			root,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.17, function()
			gui.Enabled = false
			menuToggle.Visible = true
		end)
	end

	local function sectionHeading(titleValue: string, subtitle: string)
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.new(1, 0, 0, 54)
		wrapper.Parent = scroll
		local titleItem = text(wrapper, titleValue, 19, COLOURS.Text, true)
		titleItem.Size = UDim2.new(1, 0, 0, 28)
		local subtitleItem = text(wrapper, subtitle, 13, COLOURS.Muted)
		subtitleItem.Position = UDim2.fromOffset(0, 29)
		subtitleItem.Size = UDim2.new(1, 0, 0, 20)
	end

	renderPlay = function()
		clear(scroll)
		pageTitle.Text = "Play"
		pageDescription.Text = "Choose who you want to be today."
		sectionHeading(
			"Your characters",
			"Civilian lives keep their own money, vehicles and property."
		)
		if not menuData or #menuData.Characters == 0 then
			local empty = card(scroll, 150)
			local titleItem = text(empty, "Start your first story", 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(20, 18)
			titleItem.Size = UDim2.new(1, -210, 0, 28)
			local copy =
				text(empty, "Create a civilian identity to enter the city.", 13, COLOURS.Muted)
			copy.Position = UDim2.fromOffset(20, 50)
			copy.Size = UDim2.new(1, -210, 0, 50)
			copy.TextWrapped = true
			local create = button(empty, "Create character", true)
			create.AnchorPoint = Vector2.new(1, 0.5)
			create.Position = UDim2.new(1, -20, 0.5, 0)
			create.Activated:Connect(showModal)
		else
			for _, character in menuData.Characters do
				local item = card(scroll, 92)
				local avatar = Instance.new("Frame")
				avatar.Position = UDim2.fromOffset(18, 18)
				avatar.Size = UDim2.fromOffset(56, 56)
				avatar.BackgroundColor3 = COLOURS.AccentSoft
				avatar.Parent = item
				corner(avatar, 28)
				local initials =
					text(avatar, string.sub(character.FullName, 1, 1), 22, COLOURS.Accent, true)
				initials.Size = UDim2.fromScale(1, 1)
				initials.TextXAlignment = Enum.TextXAlignment.Center
				local name = text(item, character.FullName, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(90, 20)
				name.Size = UDim2.new(1, -280, 0, 27)
				local dob = text(item, "Born " .. character.DateOfBirth, 12, COLOURS.Muted)
				dob.Position = UDim2.fromOffset(90, 48)
				dob.Size = UDim2.new(1, -280, 0, 22)
				local choose = button(item, "Choose", selectedCharacterId == character.CharacterId)
				choose.AnchorPoint = Vector2.new(1, 0.5)
				choose.Position = UDim2.new(1, -18, 0.5, 0)
				choose.Size = UDim2.fromOffset(132, 42)
				choose.Activated:Connect(function()
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
			if menuData.EmptySlots > 0 then
				local create = button(scroll, "+  New character", false)
				create.Size = UDim2.new(1, 0, 0, 48)
				create.Activated:Connect(showModal)
			end
		end
		sectionHeading("Enter the city", "Public civilian play is always available.")
		local enter = card(scroll, 108)
		local titleItem = text(enter, "Civilian", 18, COLOURS.Text, true)
		titleItem.Position = UDim2.fromOffset(20, 18)
		titleItem.Size = UDim2.new(1, -210, 0, 28)
		local copy = text(
			enter,
			"Explore, work, build a career and create your own story.",
			13,
			COLOURS.Muted
		)
		copy.Position = UDim2.fromOffset(20, 49)
		copy.Size = UDim2.new(1, -210, 0, 40)
		local action =
			button(enter, selectedCharacterId and "Enter city" or "Choose a character", true)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -20, 0.5, 0)
		action.Activated:Connect(function()
			if not selectedCharacterId then
				context.Controllers.NotificationController:Show(
					"Choose or create a character first.",
					"Character required"
				)
				return
			end
			local spawnId = "CityCivilian"
			for _, role in menuData.Roles do
				if role.Id == "Civilian" and role.Spawns[1] then
					spawnId = role.Spawns[1].SpawnId
				end
			end
			local response =
				context.Controllers.DutyController:EnterCivilian(selectedCharacterId, spawnId)
			if response.Success then
				dismissToWorld()
			end
		end)
	end

	renderCareers = function()
		clear(scroll)
		pageTitle.Text = "Careers"
		pageDescription.Text = "Every path is visible. Requirements are always clear."
		sectionHeading(
			"Roles and departments",
			"Restricted careers explain exactly how to unlock them."
		)
		for _, role in menuData and menuData.Roles or {} do
			if role.Visible then
				local item = card(scroll, 96)
				local badge = Instance.new("Frame")
				badge.Position = UDim2.fromOffset(18, 19)
				badge.Size = UDim2.fromOffset(58, 58)
				badge.BackgroundColor3 = if role.Locked
					then Color3.fromRGB(45, 38, 27)
					else COLOURS.AccentSoft
				badge.Parent = item
				corner(badge, 12)
				local icon = text(
					badge,
					if role.Locked then "◇" else "✓",
					23,
					if role.Locked then COLOURS.Warning else COLOURS.Accent,
					true
				)
				icon.Size = UDim2.fromScale(1, 1)
				icon.TextXAlignment = Enum.TextXAlignment.Center
				local name = text(item, role.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(91, 18)
				name.Size = UDim2.new(1, -280, 0, 28)
				local detail = text(
					item,
					role.Locked and role.LockMessage or "Available now",
					12,
					role.Locked and COLOURS.Muted or COLOURS.Success
				)
				detail.Position = UDim2.fromOffset(91, 47)
				detail.Size = UDim2.new(1, -280, 0, 28)
				local action = button(
					item,
					role.Locked
							and (role.Action == "OpenApplication" and "View application" or "View access")
						or "Select",
					not role.Locked
				)
				action.AnchorPoint = Vector2.new(1, 0.5)
				action.Position = UDim2.new(1, -18, 0.5, 0)
				action.Size = UDim2.fromOffset(150, 42)
				action.Activated:Connect(function()
					if role.Locked then
						context.Controllers.NotificationController:Show(
							role.LockMessage,
							"Access required"
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

	renderSettings = function()
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
		pageTitle.Text = "Community"
		pageDescription.Text = "Where you are playing, and where else you can."
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
		local officialRows = if officialResponse.Success
				and type(officialResponse.Data) == "table"
			then officialResponse.Data.Servers
			else nil
		if type(officialRows) == "table" and #officialRows > 0 then
			sectionHeading("Official servers", "Run by the team. Pick one and play.")
			for _, entry in officialRows do
				local row = card(scroll, 104)
				local here = entry.Current == true
				local marker = Instance.new("Frame")
				marker.BackgroundColor3 = if here then COLOURS.Success else COLOURS.Accent
				marker.BorderSizePixel = 0
				marker.Position = UDim2.fromOffset(0, 18)
				marker.Size = UDim2.fromOffset(4, 68)
				marker.Parent = row
				local tier = text(row, "WHITELISTED", 10, COLOURS.Accent, true)
				tier.Position = UDim2.fromOffset(22, 16)
				tier.Size = UDim2.new(1, -190, 0, 16)
				local name = text(row, tostring(entry.Name), 20, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(22, 34)
				name.Size = UDim2.new(1, -190, 0, 28)
				local blurb = text(row, tostring(entry.Description or ""), 12, COLOURS.Muted)
				blurb.Position = UDim2.fromOffset(22, 62)
				blurb.Size = UDim2.new(1, -190, 0, 30)
				blurb.TextWrapped = true
				local join = Instance.new("TextButton")
				join.AutoButtonColor = false
				join.AnchorPoint = Vector2.new(1, 0.5)
				join.Position = UDim2.new(1, -20, 0.5, 0)
				join.Size = UDim2.fromOffset(140, 48)
				join.BackgroundColor3 = if here then COLOURS.Canvas else COLOURS.Accent
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

		-- Your own community, last, because it applies to the fewest people.
		if kind == "Private" and not community then
			sectionHeading("Your community", "Link this server to a Roblox group you own.")
			local setup = card(scroll, 132)
			local copy = text(
				setup,
				"Members, staff permissions and access policies follow the group.",
				12,
				COLOURS.Muted
			)
			copy.Position = UDim2.fromOffset(20, 16)
			copy.Size = UDim2.new(1, -40, 0, 20)
			local groupIdInput = Instance.new("TextBox")
			groupIdInput.BackgroundColor3 = COLOURS.Canvas
			groupIdInput.BorderSizePixel = 0
			groupIdInput.ClearTextOnFocus = false
			groupIdInput.Font = Enum.Font.Gotham
			groupIdInput.PlaceholderColor3 = COLOURS.Muted
			groupIdInput.PlaceholderText = "Roblox group ID"
			groupIdInput.Position = UDim2.fromOffset(20, 46)
			groupIdInput.Size = UDim2.new(1, -212, 0, 44)
			groupIdInput.Text = ""
			groupIdInput.TextColor3 = COLOURS.Text
			groupIdInput.TextSize = 14
			groupIdInput.Parent = setup
			corner(groupIdInput, 10)
			local createCommunity = button(setup, "Create community", true)
			createCommunity.AnchorPoint = Vector2.new(1, 0)
			createCommunity.Position = UDim2.new(1, -20, 0, 46)
			createCommunity.Size = UDim2.fromOffset(172, 44)
			createCommunity.Activated:Connect(function()
				local groupId = tonumber(groupIdInput.Text)
				if not groupId or groupId <= 0 or groupId % 1 ~= 0 then
					context.Controllers.NotificationController:Show(
						"Enter the numeric ID of a Roblox group you own.",
						"Group required"
					)
					return
				end
				createCommunity.Text = "Creating…"
				local response = context.Controllers.CommunityController:CreatePrivate(groupId)
				if response.Success then
					context.Controllers.StartMenuController:Refresh()
				else
					createCommunity.Text = "Create community"
				end
			end)
			local note = text(
				setup,
				"You must own the group. Everyone joining still needs to be a member of the host community.",
				11,
				COLOURS.Muted
			)
			note.Position = UDim2.fromOffset(20, 98)
			note.Size = UDim2.new(1, -40, 0, 20)
			note.TextWrapped = true
		elseif kind == "Public" then
			sectionHeading("Your own community", "Private servers can run to their own rules.")
			local hint = card(scroll, 74)
			local hintCopy = text(
				hint,
				"Start a private server for this experience, then set it up from this page.",
				13,
				COLOURS.Muted
			)
			hintCopy.Position = UDim2.fromOffset(20, 0)
			hintCopy.Size = UDim2.new(1, -40, 1, 0)
			hintCopy.TextWrapped = true
		end
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
			item.BackgroundColor3 = COLOURS.AccentSoft
			item.TextColor3 = COLOURS.Text
			render()
		end)
		return item
	end

	local playNav = addNav("Play", renderPlay)
	addNav("Careers", renderCareers)
	addNav("Community", renderCommunity)
	addNav("Controls", function()
		renderControls()
	end)
	addNav("Settings", renderSettings)
	activeNav = playNav
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
		local controlSize =
			math.floor(nativeBand * (NATIVE_CONTROL_SIZE / NATIVE_BAND_HEIGHT) + 0.5)
		menuToggle.Size = UDim2.fromOffset(controlSize, controlSize)
		menuToggleCorner.CornerRadius = UDim.new(0, controlSize / 2)
		menuToggle.TextSize = math.floor(controlSize * 0.5 + 0.5)
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
				math.max(NATIVE_CONTROL_GAP, layout.Viewport.X - controlSize - NATIVE_CONTROL_GAP)
			),
			-- Centre within the native band, never above the screen edge.
			math.max(0, math.floor((nativeBand - controlSize) / 2))
		)
		-- Compact already accounts for a short landscape phone, so the height is
		-- not tested again here.
		local horizontal = layout.Compact
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
			brand.TextSize = 15
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
					item.TextXAlignment = Enum.TextXAlignment.Center
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new()
					end
				end
			end
			profile.Visible = false
			header.Position = UDim2.fromOffset(safeLeft + 20, 10)
			header.Size = UDim2.new(1, -(40 + safeLeft + safeRight), 0, 54)
			pageTitle.TextSize = 24
			pageDescription.Visible = false
			status.Position = UDim2.new(1, -safeRight, 0, 3)
			scroll.Position = UDim2.fromOffset(safeLeft + 20, 68)
			scroll.Size = UDim2.new(1, -(40 + safeLeft + safeRight), 1, -(76 + layout.SafeBottom))
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
					item.TextXAlignment = Enum.TextXAlignment.Left
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new(0, 14)
					end
				end
			end
			profile.Visible = true
			header.Position = UDim2.fromOffset(44, safeTop + 30)
			header.Size = UDim2.new(1, -(88 + safeRight), 0, 76)
			pageTitle.TextSize = 30
			pageDescription.Visible = true
			status.Position = UDim2.new(1, -safeRight, 0, 9)
			scroll.Position = UDim2.fromOffset(44, safeTop + 118)
			scroll.Size = UDim2.new(1, -(88 + safeRight), 1, -(safeTop + 146 + layout.SafeBottom))
		end
	end)

	context.Events.StartMenuChanged.Event:Connect(function(data)
		menuData = data
		brand.Text = data.Framework.GameName
		version.Visible = data.Framework.ShowRoleplayOSMark
		status.Text = "●  ONLINE  ·  " .. string.upper(data.Server.Kind)
		status.TextColor3 = COLOURS.Success
		renderPlay()
	end)
	-- Paint immediately so the menu is on screen while the first request is still
	-- in flight. The StartMenuChanged handler above fills in real data on success.
	renderPlay()
	task.spawn(function()
		local response = context.Controllers.StartMenuController:Refresh()
		if not response.Success then
			status.Text = "●  CONNECTION ERROR"
			status.TextColor3 = COLOURS.Danger
		end
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
