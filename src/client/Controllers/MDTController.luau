--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Coalescer = require(ReplicatedStorage.RoleplayOS.Shared.Coalescer)
local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local TacticalMap = require(script.Parent.Parent.UI.TacticalMap)
local TerminalTheme = require(script.Parent.Parent.UI.OperationalTerminalTheme)

local MDTController = { connections = {} }
local MDT_ACTION = "RoleplayOSToggleMDT"
-- Tall enough to hit with a thumb. FitScale never scales a panel up, so this
-- is a ceiling as well as the authored size.
local UNIT_STATUS_ROW_HEIGHT = 44

-- The map shares GetDispatchSnapshot with the dispatch board on this same
-- client, so it takes half of that endpoint's one-per-second refill.
local MAP_REFRESH_INTERVAL = 2
-- The incident list is the tight one. MDTGetIncidents refills at a quarter per
-- second, so four dispatch changes in a row would empty it for sixteen seconds
-- and refuse the officer's own searches for the rest of them. This leaves most
-- of the bucket to the officer and still keeps the list current.
local INCIDENT_REFRESH_INTERVAL = 6
local C = TerminalTheme

local DEPARTMENT_UI = {
	Police = {
		Title = "FORCE CONTROL  ·  OPERATIONAL MDT",
		Subtitle = "POLICE CONTROL / INTELLIGENCE & DISPATCH  ·  RESTRICTED",
		Accent = Color3.fromRGB(72, 132, 224),
		Tiles = {
			{ "Incidents", "Review live calls, attending units and scene updates.", "Incident" },
			{ "People", "Search person records, warnings and warrants.", "Person" },
			{ "Vehicles", "Look up registrations, keepers and vehicle markers.", "Vehicle" },
			{ "Units & map", "See active units, incidents and locations.", "Map" },
		},
	},
	Ambulance = {
		Title = "AMBULANCE EOC  ·  OPERATIONAL CAD",
		Subtitle = "EMERGENCY OPERATIONS CENTRE / RESPONSE & HANDOVER  ·  RESTRICTED",
		Accent = Color3.fromRGB(74, 198, 139),
		Tiles = {
			{
				"Emergency calls",
				"Review triaged incidents and allocate response crews.",
				"Incident",
			},
			{
				"Patient records",
				"Search person details and relevant safety information.",
				"Person",
			},
			{ "Response vehicles", "Check vehicle details and operational markers.", "Vehicle" },
			{ "Crews & map", "Track response locations and multi-agency incidents.", "Map" },
		},
	},
	Fire = {
		Title = "FIRE CONTROL  ·  MOBILISING CAD",
		Subtitle = "FIRE CONTROL / APPLIANCE & INCIDENT MANAGEMENT  ·  RESTRICTED",
		Accent = Color3.fromRGB(235, 104, 76),
		Tiles = {
			{ "Mobilisations", "Review incidents and appliance attendance status.", "Incident" },
			{ "Risk information", "Search people and operational safety information.", "Person" },
			{ "Appliances", "Check vehicle details and response resources.", "Vehicle" },
			{ "Incident map", "Share locations and multi-agency situational awareness.", "Map" },
		},
	},
	Control = {
		Title = "JOINT CONTROL  ·  INCIDENT BOARD",
		Subtitle = "MULTI-AGENCY CONTROL / DISPATCH & INFORMATION SHARING  ·  RESTRICTED",
		Accent = Color3.fromRGB(50, 190, 188),
		Tiles = {
			{
				"Live incidents",
				"Create, assign and monitor active emergency calls.",
				"Incident",
			},
			{
				"Resolved CAD archive",
				"Review closed calls and retained incident records.",
				"Resolved",
			},
			{ "People records", "Search operational information shared with control.", "Person" },
			{ "Vehicles", "Check registrations, keepers and markers.", "Vehicle" },
			{ "Multi-agency map", "Coordinate units, incidents and partner activity.", "Map" },
		},
	},
}

local function departmentUI(departmentId: string?): any
	return DEPARTMENT_UI[departmentId or ""] or DEPARTMENT_UI.Control
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function text(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
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

local function button(parent: Instance, value: string): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = C.Raised
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.Parent = parent
	corner(item, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = item
	item.MouseButton1Down:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 0.97,
			})
			:Play()
	end)
	item.MouseButton1Up:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)
	return item
end

function MDTController:Init(context: any)
	self.context = context
	self.recordType = "Home"
	self.allowed = false
	self.canWriteWarrants = false
	self.selectedRecord = nil
end

function MDTController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSMDT"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.Enabled = false
	-- Above the HUD, below the menu, for the same reason the forecourt is: a
	-- terminal that fills the screen must not have the radio and the phone drawn
	-- through the middle of it.
	gui.DisplayOrder = 45
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local launcher = button(gui, "MDT  ·  M")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(0, 0.5)
	launcher.Position = UDim2.new(0, 18, 0.62, 0)
	launcher.Size = UDim2.fromOffset(96, 38)
	launcher.Visible = false
	self.launcher = launcher
	local shortcutGlyph = Instance.new("ImageLabel")
	shortcutGlyph.Name = "ControllerGlyph"
	shortcutGlyph.AnchorPoint = Vector2.new(1, 0.5)
	shortcutGlyph.Position = UDim2.new(1, -10, 0.5, 0)
	shortcutGlyph.Size = UDim2.fromOffset(20, 20)
	shortcutGlyph.BackgroundTransparency = 1
	shortcutGlyph.Visible = false
	shortcutGlyph.Parent = launcher
	self.shortcutGlyph = shortcutGlyph

	-- The terminal is presented as a rugged landscape tablet: an outer chassis
	-- carrying the bezel, status bar and home indicator, and an inner screen
	-- that everything else parents into. Splitting them this way means the
	-- screen keeps its own coordinate space, so page content is laid out
	-- against the display rather than against the casing around it.
	local chassis = Instance.new("Frame")
	chassis.Name = "Terminal"
	chassis.AnchorPoint = Vector2.new(0.5, 0.5)
	chassis.Position = UDim2.fromScale(0.5, 0.5)
	chassis.Size = UDim2.fromScale(0.86, 0.82)
	chassis.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
	chassis.BorderSizePixel = 0
	chassis.SelectionGroup = true
	chassis.Visible = false
	chassis.Parent = gui
	corner(chassis, 22)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(720, 470)
	constraint.MaxSize = Vector2.new(1120, 720)
	constraint.Parent = chassis
	self.constraint = constraint
	local scale = Instance.new("UIScale")
	scale.Parent = chassis
	self.scale = scale
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(74, 88, 110)
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = chassis
	-- Visibility, sizing and scaling act on the whole device.
	self.shell = chassis

	local statusBar = Instance.new("Frame")
	statusBar.Name = "StatusBar"
	statusBar.BackgroundTransparency = 1
	statusBar.Position = UDim2.fromOffset(18, 6)
	statusBar.Size = UDim2.new(1, -36, 0, 22)
	statusBar.Parent = chassis
	local statusClock = text(statusBar, "09:41", 11, true)
	statusClock.Size = UDim2.fromOffset(60, 22)
	self.statusClock = statusClock
	local statusName = text(statusBar, "RoleplayOS MDT", 11, true)
	statusName.AnchorPoint = Vector2.new(0.5, 0)
	statusName.Position = UDim2.fromScale(0.5, 0)
	statusName.Size = UDim2.fromOffset(200, 22)
	statusName.TextXAlignment = Enum.TextXAlignment.Center
	statusName.TextColor3 = C.Muted
	local statusIcons = text(statusBar, "▮▮▮  ᯤ  ▰", 10, true)
	statusIcons.AnchorPoint = Vector2.new(1, 0)
	statusIcons.Position = UDim2.fromScale(1, 0)
	statusIcons.Size = UDim2.fromOffset(80, 22)
	statusIcons.TextXAlignment = Enum.TextXAlignment.Right
	statusIcons.TextColor3 = C.Muted

	local shell = Instance.new("Frame")
	shell.Name = "Screen"
	shell.Position = UDim2.fromOffset(12, 30)
	shell.Size = UDim2.new(1, -24, 1, -50)
	shell.BackgroundColor3 = C.Surface
	shell.BorderSizePixel = 0
	shell.ClipsDescendants = true
	shell.Parent = chassis
	corner(shell, 14)

	local homeIndicator = Instance.new("Frame")
	homeIndicator.AnchorPoint = Vector2.new(0.5, 1)
	homeIndicator.Position = UDim2.new(0.5, 0, 1, -7)
	homeIndicator.Size = UDim2.fromOffset(132, 5)
	homeIndicator.BackgroundColor3 = Color3.fromRGB(150, 166, 190)
	homeIndicator.BackgroundTransparency = 0.35
	homeIndicator.BorderSizePixel = 0
	homeIndicator.Parent = chassis
	corner(homeIndicator, 3)
	local classification = Instance.new("Frame")
	classification.Size = UDim2.new(1, 0, 0, 4)
	classification.BackgroundColor3 = C.Classification
	classification.BorderSizePixel = 0
	classification.Parent = shell

	local title = text(shell, "FORCE CONTROL  ·  OPERATIONAL MDT", 16, true)
	title.Position = UDim2.fromOffset(22, 15)
	title.Size = UDim2.new(1, -110, 0, 24)
	self.serviceTitle = title
	local subtitle = text(shell, "COMMAND & CONTROL / RECORDS GATEWAY  ·  RESTRICTED", 10)
	subtitle.Position = UDim2.fromOffset(22, 39)
	subtitle.Size = UDim2.new(1, -110, 0, 18)
	subtitle.TextColor3 = C.Muted
	self.serviceSubtitle = subtitle
	local secure = text(shell, "●  SECURE SESSION", 9, true)
	secure.AnchorPoint = Vector2.new(1, 0)
	secure.Position = UDim2.new(1, -104, 0, 42)
	secure.Size = UDim2.fromOffset(150, 16)
	secure.TextXAlignment = Enum.TextXAlignment.Right
	secure.TextColor3 = C.Secure
	self.secureLabel = secure
	local close = button(shell, "CLOSE")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 15)
	-- Interactive controls are 44 tall from here down.
	--
	-- FitScale is clamped to a maximum of one, so a control authored below 44
	-- is below 44 on every device there is -- it can only ever be scaled down
	-- from what is written here. These were 30 and 34, which is under the size
	-- a fingertip reliably hits, and this terminal is used one-handed in a car.
	--
	-- The room was already there: this row ends at 114 and the search box below
	-- it starts at 119.
	close.Size = UDim2.fromOffset(76, 44)
	self.close = close

	-- No tab rail: pages are chosen from the home screen, and a single HOME
	-- control returns there. Four permanent tabs cost a row of screen on a
	-- device that is already small on a phone, and duplicated what the home
	-- screen already offers.
	local homeTab = button(shell, "\u{2302}  HOME")
	homeTab.Position = UDim2.fromOffset(22, 70)
	homeTab.Size = UDim2.fromOffset(104, 44)
	self.homeTab = homeTab

	-- The officer's own status, on every page.
	--
	-- Dispatch could attach a unit to a call and nothing could ever say the unit
	-- had arrived, so every car on the board read as still driving to it however
	-- long it had been at the scene. The endpoint for this has been registered
	-- and rate limited on the server all along with nothing anywhere calling it.
	--
	-- Beside HOME rather than on a page of its own, because an officer pulling up
	-- outside should be one press away from saying so, not three.
	local statusStrip = Instance.new("Frame")
	statusStrip.Name = "UnitStatus"
	statusStrip.BackgroundTransparency = 1
	statusStrip.Position = UDim2.fromOffset(134, 70)
	statusStrip.Size = UDim2.new(1, -156, 0, UNIT_STATUS_ROW_HEIGHT)
	statusStrip.Visible = false
	statusStrip.Parent = shell
	self.statusStrip = statusStrip
	local statusRow = Instance.new("UIListLayout")
	statusRow.FillDirection = Enum.FillDirection.Horizontal
	statusRow.Padding = UDim.new(0, 8)
	statusRow.SortOrder = Enum.SortOrder.LayoutOrder
	statusRow.VerticalAlignment = Enum.VerticalAlignment.Center
	statusRow.Parent = statusStrip

	self.unitStatusButtons = {}

	-- The home screen the terminal opens on, and the only way into a page. Each
	-- card says what its page is for, so an officer who has just picked the
	-- terminal up is not required to already know where to look.
	local home = Instance.new("Frame")
	home.Name = "Home"
	home.BackgroundTransparency = 1
	home.Position = UDim2.fromOffset(22, 124)
	home.Size = UDim2.new(1, -44, 1, -146)
	home.Parent = shell
	self.home = home
	local homeGrid = Instance.new("UIGridLayout")
	homeGrid.CellSize = UDim2.fromOffset(232, 96)
	homeGrid.CellPadding = UDim2.fromOffset(14, 14)
	homeGrid.SortOrder = Enum.SortOrder.LayoutOrder
	homeGrid.Parent = home

	local input = Instance.new("TextBox")
	input.BackgroundColor3 = C.Raised
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Search name or registration"
	input.PlaceholderColor3 = C.Muted
	input.Text = ""
	input.TextColor3 = C.Text
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = Enum.TextYAlignment.Center
	input.Position = UDim2.fromOffset(22, 119)
	-- Shortened to stop the SEARCH button standing on it.
	--
	-- The box ran to 0.62 of the width less 12, and the button is anchored to
	-- its right edge at less 22 and is 86 wide, so all 86 of it sat inside the
	-- box. Every device, not a phone problem: the officer was typing underneath
	-- a button. The box now stops four pixels short of where the button begins.
	input.Size = UDim2.new(0.62, -134, 0, 42)
	input.Parent = shell
	corner(input, 9)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.Parent = input
	self.input = input
	local search = button(shell, "SEARCH")
	search.AnchorPoint = Vector2.new(1, 0)
	search.Position = UDim2.new(0.62, -22, 0, 119)
	search.Size = UDim2.fromOffset(86, 42)
	search.BackgroundColor3 = C.Accent
	self.searchAction = search

	local status = text(shell, "Enter at least two characters.", 11)
	status.Position = UDim2.fromOffset(22, 170)
	status.Size = UDim2.new(0.62, -44, 0, 20)
	status.TextColor3 = C.Muted
	self.status = status
	local results = Instance.new("ScrollingFrame")
	results.BackgroundTransparency = 1
	results.BorderSizePixel = 0
	results.Position = UDim2.fromOffset(22, 200)
	results.Size = UDim2.new(0.62, -34, 1, -222)
	results.AutomaticCanvasSize = Enum.AutomaticSize.Y
	results.CanvasSize = UDim2.new()
	results.ScrollBarThickness = 6
	results.Parent = shell
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = results
	self.results = results

	local detail = Instance.new("Frame")
	detail.Position = UDim2.new(0.62, 0, 0, 73)
	detail.Size = UDim2.new(0.38, -22, 1, -95)
	detail.BackgroundColor3 = C.Raised
	detail.BorderSizePixel = 0
	detail.Parent = shell
	corner(detail, 11)
	self.detail = detail

	local map = TacticalMap.new(shell)
	map:SetSize(UDim2.new(1, -44, 1, -136), UDim2.fromOffset(22, 119))
	self.map = map
	local detailTitle = text(detail, "RECORD PREVIEW", 11, true)
	detailTitle.Position = UDim2.fromOffset(16, 14)
	detailTitle.Size = UDim2.new(1, -32, 0, 20)
	detailTitle.TextColor3 = C.Accent
	local detailName = text(detail, "Select a search result", 18, true)
	detailName.Position = UDim2.fromOffset(16, 45)
	detailName.Size = UDim2.new(1, -32, 0, 48)
	detailName.TextWrapped = true
	local detailMeta = text(detail, "Verified operational information will appear here.", 11)
	detailMeta.Position = UDim2.fromOffset(16, 104)
	detailMeta.Size = UDim2.new(1, -32, 1, -174)
	detailMeta.TextWrapped = true
	detailMeta.TextYAlignment = Enum.TextYAlignment.Top
	detailMeta.TextColor3 = C.Muted
	self.detailTitle = detailTitle
	self.detailName = detailName
	self.detailMeta = detailMeta
	local warrantAction = button(detail, "ISSUE WARRANT")
	warrantAction.AnchorPoint = Vector2.new(0, 1)
	warrantAction.Position = UDim2.new(0, 16, 1, -16)
	warrantAction.Size = UDim2.new(0.5, -20, 0, 40)
	warrantAction.BackgroundColor3 = C.Accent
	warrantAction.Visible = false
	self.warrantAction = warrantAction
	local revokeAction = button(detail, "REVOKE WARRANT")
	revokeAction.AnchorPoint = Vector2.new(1, 1)
	revokeAction.Position = UDim2.new(1, -16, 1, -16)
	revokeAction.Size = UDim2.new(0.5, -20, 0, 40)
	revokeAction.BackgroundColor3 = Color3.fromRGB(148, 55, 65)
	revokeAction.Visible = false
	self.revokeAction = revokeAction
	local noteInput = Instance.new("TextBox")
	noteInput.Name = "OperationalNoteInput"
	noteInput.Position = UDim2.new(0, 16, 1, -64)
	noteInput.Size = UDim2.new(1, -112, 0, 40)
	noteInput.BackgroundColor3 = C.Surface
	noteInput.BorderSizePixel = 0
	noteInput.ClearTextOnFocus = false
	noteInput.Font = Enum.Font.Gotham
	noteInput.PlaceholderText = "Add operational note…"
	noteInput.PlaceholderColor3 = C.Muted
	noteInput.TextColor3 = C.Text
	noteInput.TextSize = 11
	noteInput.TextXAlignment = Enum.TextXAlignment.Left
	noteInput.TextYAlignment = Enum.TextYAlignment.Center
	noteInput.Visible = false
	noteInput.Parent = detail
	corner(noteInput, 8)
	local notePadding = Instance.new("UIPadding")
	notePadding.PaddingLeft = UDim.new(0, 10)
	notePadding.PaddingRight = UDim.new(0, 10)
	notePadding.Parent = noteInput
	local addNote = button(detail, "ADD NOTE")
	addNote.AnchorPoint = Vector2.new(1, 0)
	addNote.Position = UDim2.new(1, -16, 1, -64)
	addNote.Size = UDim2.fromOffset(82, 40)
	addNote.BackgroundColor3 = C.Accent
	addNote.TextSize = 9
	addNote.Visible = false
	self.noteInput = noteInput
	self.addNote = addNote

	local warrantModal = Instance.new("Frame")
	warrantModal.Name = "WarrantModal"
	warrantModal.AnchorPoint = Vector2.new(0.5, 0.5)
	warrantModal.Position = UDim2.fromScale(0.5, 0.5)
	warrantModal.Size = UDim2.fromOffset(440, 286)
	warrantModal.BackgroundColor3 = C.Surface
	warrantModal.BorderSizePixel = 0
	warrantModal.Visible = false
	warrantModal.ZIndex = 20
	warrantModal.Parent = shell
	corner(warrantModal, 12)
	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = C.Border
	modalStroke.Parent = warrantModal
	local modalTitle = text(warrantModal, "ISSUE WARRANT", 15, true)
	modalTitle.Position = UDim2.fromOffset(20, 17)
	modalTitle.Size = UDim2.new(1, -40, 0, 24)
	modalTitle.ZIndex = 21
	local modalCopy =
		text(warrantModal, "The reason is filtered and the action is written to the audit log.", 10)
	modalCopy.Position = UDim2.fromOffset(20, 43)
	modalCopy.Size = UDim2.new(1, -40, 0, 30)
	modalCopy.TextWrapped = true
	modalCopy.TextColor3 = C.Muted
	modalCopy.ZIndex = 21
	local reasonInput = Instance.new("TextBox")
	reasonInput.Position = UDim2.fromOffset(20, 82)
	reasonInput.Size = UDim2.new(1, -40, 0, 76)
	reasonInput.BackgroundColor3 = C.Raised
	reasonInput.BorderSizePixel = 0
	reasonInput.ClearTextOnFocus = false
	reasonInput.Font = Enum.Font.Gotham
	reasonInput.MultiLine = true
	reasonInput.PlaceholderText = "Operational reason"
	reasonInput.PlaceholderColor3 = C.Muted
	reasonInput.Text = ""
	reasonInput.TextColor3 = C.Text
	reasonInput.TextSize = 12
	reasonInput.TextWrapped = true
	reasonInput.TextXAlignment = Enum.TextXAlignment.Left
	reasonInput.TextYAlignment = Enum.TextYAlignment.Top
	reasonInput.ZIndex = 21
	reasonInput.Parent = warrantModal
	corner(reasonInput, 8)
	local reasonPadding = Instance.new("UIPadding")
	reasonPadding.PaddingTop = UDim.new(0, 10)
	reasonPadding.PaddingLeft = UDim.new(0, 10)
	reasonPadding.PaddingRight = UDim.new(0, 10)
	reasonPadding.Parent = reasonInput
	local expiryInput = Instance.new("TextBox")
	expiryInput.Position = UDim2.fromOffset(20, 168)
	expiryInput.Size = UDim2.new(1, -40, 0, 38)
	expiryInput.BackgroundColor3 = C.Raised
	expiryInput.BorderSizePixel = 0
	expiryInput.ClearTextOnFocus = false
	expiryInput.Font = Enum.Font.Gotham
	expiryInput.PlaceholderText = "Expiry in days (blank for no expiry)"
	expiryInput.PlaceholderColor3 = C.Muted
	expiryInput.Text = ""
	expiryInput.TextColor3 = C.Text
	expiryInput.TextSize = 11
	expiryInput.TextYAlignment = Enum.TextYAlignment.Center
	expiryInput.ZIndex = 21
	expiryInput.Parent = warrantModal
	corner(expiryInput, 8)
	local cancelWarrant = button(warrantModal, "CANCEL")
	cancelWarrant.Position = UDim2.fromOffset(20, 224)
	cancelWarrant.Size = UDim2.fromOffset(110, 42)
	cancelWarrant.ZIndex = 21
	local confirmWarrant = button(warrantModal, "ISSUE WARRANT")
	confirmWarrant.AnchorPoint = Vector2.new(1, 0)
	confirmWarrant.Position = UDim2.new(1, -20, 0, 224)
	confirmWarrant.Size = UDim2.fromOffset(150, 42)
	confirmWarrant.BackgroundColor3 = C.Accent
	confirmWarrant.ZIndex = 21
	self.warrantModal = warrantModal
	self.warrantReason = reasonInput
	self.warrantExpiry = expiryInput

	local function setOpen(open: boolean)
		if open and not self.allowed then
			return
		end
		local actuallyOpen = open and self.allowed == true
		chassis.Visible = actuallyOpen
		-- The ambient heads-up display stands down while a full device is on
		-- screen rather than showing through it.
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			playerGui:SetAttribute("RoleplayOSMDTOpen", actuallyOpen)
			playerGui:SetAttribute(
				"RoleplayOSDeviceOpen",
				actuallyOpen or playerGui:GetAttribute("RoleplayOSPhoneOpen") == true
			)
		end
		if actuallyOpen then
			-- Map geometry is static, so rebuild on open rather than per refresh.
			self.map:Rebuild()
			self:RefreshMap()
		end
	end
	self.setOpen = setOpen
	launcher.Activated:Connect(function()
		setOpen(not chassis.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	warrantAction.Activated:Connect(function()
		if self.canWriteWarrants and self.selectedRecord then
			warrantModal.Visible = true
			reasonInput:CaptureFocus()
		end
	end)
	revokeAction.Activated:Connect(function()
		self:_revokeWarrant()
	end)
	addNote.Activated:Connect(function()
		self:_addOperationalNote()
	end)
	cancelWarrant.Activated:Connect(function()
		warrantModal.Visible = false
	end)
	confirmWarrant.Activated:Connect(function()
		self:_issueWarrant()
	end)
	homeTab.Activated:Connect(function()
		self.recordType = "Home"
		self:_renderTabs()
	end)
	search.Activated:Connect(function()
		self:_performSearch()
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_performSearch()
		end
	end)
	self:_buildHome()
	self:_renderTabs()
end

function MDTController:_renderTabs()
	-- Nothing to return to from the home screen itself, so the control only
	-- appears once the officer has opened a page.
	self.homeTab.Visible = self.recordType ~= "Home"
	-- The status strip shares that row, so it takes the space back on the home
	-- screen rather than sitting behind a gap where the control used to be.
	if self.statusStrip then
		local afterHome = self.homeTab.Visible
		self.statusStrip.Position = UDim2.fromOffset(if afterHome then 134 else 22, 70)
		-- Same height as where the strip is built. Written in two places, so it
		-- is written once and read twice rather than being kept in step by hand.
		self.statusStrip.Size =
			UDim2.new(1, if afterHome then -156 else -44, 0, UNIT_STATUS_ROW_HEIGHT)
	end
	-- Home and the map each replace the records surface rather than sharing it,
	-- so the search controls cannot be used against a page that has no search.
	local mapping = self.recordType == "Map"
	local home = self.recordType == "Home"
	local records = not mapping and not home
	self.input.Visible = records
	self.searchAction.Visible = records
	self.status.Visible = records
	self.results.Visible = records
	self.detail.Visible = records
	self.home.Visible = home
	self.map:SetVisible(mapping)
end

-- One home tile: a titled card describing what the page is for, so the terminal
-- explains itself rather than relying on four unlabelled tabs.
function MDTController:_homeTile(order: number, name: string, detail: string, page: string)
	local tile = button(self.home, "")
	tile.LayoutOrder = order
	tile.BackgroundColor3 = C.Raised
	corner(tile, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Transparency = 0.4
	stroke.Parent = tile
	local title = text(tile, name, 16, true)
	title.Position = UDim2.fromOffset(16, 16)
	title.Size = UDim2.new(1, -32, 0, 24)
	local body = text(tile, detail, 11)
	body.Position = UDim2.fromOffset(16, 42)
	body.Size = UDim2.new(1, -32, 0, 40)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = C.Muted
	tile.Activated:Connect(function()
		self.recordType = page
		self:_renderTabs()
		if page == "Map" then
			self:RefreshMap()
		elseif page == "Incident" then
			self:_performSearch()
		end
	end)
end

function MDTController:_buildHome()
	for _, child in self.home:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	for order, tile in departmentUI(self.departmentId).Tiles do
		self:_homeTile(order, tile[1], tile[2], tile[3])
	end
end

-- Pulls a fresh server snapshot. The map only ever renders what the server
-- reports, so an unauthorised duty simply sees an empty picture.
-- Mirrors the tablet's status clock. Local time, like the handset: the device
-- belongs to the officer carrying it.
function MDTController:_updateClock()
	if self.statusClock then
		self.statusClock.Text = os.date("%H:%M")
	end
end

function MDTController:RefreshMap()
	self:_updateClock()
	if self.recordType ~= "Map" then
		return
	end
	local response = self.context.Controllers.NetworkController:Request("GetDispatchSnapshot", {})
	self.map:Update(if response.Success then response.Data else nil)
end

function MDTController:_renderResults(items: { any })
	self.selectedRecord = nil
	self.warrantAction.Visible = false
	self.revokeAction.Visible = false
	for _, child in self.results:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if #items == 0 then
		self.detailName.Text = "No matching records"
		self.detailMeta.Text =
			"Check the spelling or try a broader search. Searches require at least two characters."
	end
	for _, record in items do
		local row = button(self.results, "")
		row.BackgroundColor3 = C.Raised
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -5, 0, 62)
		row.Parent = self.results
		corner(row, 9)
		local primary = text(
			row,
			record.FullName or record.Registration or record.Title or "Unknown record",
			13,
			true
		)
		primary.Position = UDim2.fromOffset(14, 10)
		primary.Size = UDim2.new(1, -28, 0, 20)
		-- Names come from player records and have no length limit, so a long one
		-- ran on under the VIEW control at the end of its own row.
		primary.TextTruncate = Enum.TextTruncate.AtEnd
		local secondary = text(
			row,
			record.DateOfBirth and ("Date of birth  ·  " .. record.DateOfBirth)
				or record.Title and ("Incident  ·  " .. tostring(record.Status or "Unknown"))
				or ("Vehicle  ·  " .. tostring(record.DefinitionId or "Unknown")),
			10
		)
		secondary.Position = UDim2.fromOffset(14, 33)
		secondary.Size = UDim2.new(1, -28, 0, 18)
		secondary.TextTruncate = Enum.TextTruncate.AtEnd
		secondary.TextColor3 = C.Muted
		local open = text(row, "VIEW  ›", 9, true)
		open.AnchorPoint = Vector2.new(1, 0.5)
		open.Position = UDim2.new(1, -14, 0.5, 0)
		open.Size = UDim2.fromOffset(60, 18)
		open.TextXAlignment = Enum.TextXAlignment.Right
		open.TextColor3 = C.Accent
		row.Activated:Connect(function()
			self.selectedRecord = record
			self.warrantAction.Visible = record.FullName ~= nil and self.canWriteWarrants
			self.revokeAction.Visible = record.FullName ~= nil
				and self.canWriteWarrants
				and #(record.Warrants or {}) > 0
			self.revokeAction.Text = "REVOKE WARRANT"
			self.revokeConfirmationId = nil
			self.detailTitle.Text = if record.FullName
				then "PERSON RECORD"
				elseif record.Title then "INCIDENT RECORD"
				else "VEHICLE RECORD"
			self.detailName.Text = record.FullName
				or record.Registration
				or record.Title
				or "Unknown record"
			if record.FullName and record.AccessProfile == "Emergency" then
				self.detailMeta.Text = string.format(
					"DATE OF BIRTH\n%s\n\nACCESS PROFILE\nEmergency service identity view\n\nPolice, custody and driving-enforcement records are restricted.",
					tostring(record.DateOfBirth or "Not recorded")
				)
			elseif record.FullName and record.AccessProfile == "Highways" then
				local licences = {}
				for licenceId, value in record.Licences or {} do
					if value then
						table.insert(licences, tostring(licenceId))
					end
				end
				self.detailMeta.Text = string.format(
					"DATE OF BIRTH\n%s\n\nLICENCES\n%s\n\nDRIVING POINTS\n%d\n\nACCESS PROFILE\nRoad-safety view",
					tostring(record.DateOfBirth or "Not recorded"),
					if #licences > 0 then table.concat(licences, ", ") else "None recorded",
					record.DrivingRecord and record.DrivingRecord.Points or 0
				)
			elseif record.FullName then
				local licences = {}
				for licenceId, value in record.Licences or {} do
					if value then
						table.insert(licences, tostring(licenceId))
					end
				end
				local bookings = record.CustodyRecord and record.CustodyRecord.Bookings or {}
				local warrants = {}
				for _, warrant in record.Warrants or {} do
					table.insert(warrants, tostring(warrant.Reason or "Active warrant"))
				end
				self.detailMeta.Text = string.format(
					"DATE OF BIRTH\n%s\n\nLICENCES\n%s\n\nDRIVING POINTS · %d   CUSTODY BOOKINGS · %d\n\nFLAGS\n%s\n\nACTIVE WARRANTS\n%s",
					tostring(record.DateOfBirth or "Not recorded"),
					if #licences > 0 then table.concat(licences, ", ") else "None recorded",
					record.DrivingRecord and record.DrivingRecord.Points or 0,
					#bookings,
					if #(record.Flags or {}) > 0
						then table.concat(record.Flags, ", ")
						else "No active flags",
					if #warrants > 0 then table.concat(warrants, "\n") else "None"
				)
			elseif record.Title then
				self.detailMeta.Text = string.format(
					"STATUS\n%s\n\nTYPE\n%s\n\nLOCATION\n%s\n\nPRIORITY\n%s\n\nCREATED\n%s\n\nUNITS\n%s",
					tostring(record.Status or "Unknown"),
					tostring(record.IncidentType or "General"),
					tostring(record.Location or "Not recorded"),
					tostring(record.Priority or "Not recorded"),
					os.date("!%Y-%m-%d %H:%M UTC", record.CreatedAt or 0),
					if #(record.UnitIds or {}) > 0
						then table.concat(record.UnitIds, ", ")
						else "None recorded"
				)
			else
				self.detailMeta.Text = string.format(
					"REGISTRATION\n%s\n\nVEHICLE TYPE\n%s\n\nOWNER RECORD\n%s\n\nFLAGS\n%s",
					tostring(record.Registration or "Unknown"),
					tostring(record.DefinitionId or "Unknown"),
					tostring(record.OwnerCharacterId or "Unavailable"),
					if #(record.Flags or {}) > 0
						then table.concat(record.Flags, ", ")
						else "No active flags"
				)
			end
		end)
	end
end

function MDTController:_issueWarrant()
	local record = self.selectedRecord
	if not record or not self.canWriteWarrants then
		return
	end
	local days = tonumber(self.warrantExpiry.Text)
	if self.warrantExpiry.Text ~= "" and (not days or days < 1 or days > 365) then
		self.status.Text = "Expiry must be between 1 and 365 days."
		return
	end
	local response = self.context.Controllers.NetworkController:Request("MDTCreateWarrant", {
		CharacterId = record.CharacterId,
		Reason = self.warrantReason.Text,
		ExpiresAt = days and (os.time() + math.floor(days) * 86400) or nil,
	})
	self.status.Text = response.Message
	if response.Success then
		self.warrantModal.Visible = false
		self.warrantReason.Text = ""
		self.warrantExpiry.Text = ""
		self:_performSearch()
	end
end

function MDTController:_revokeWarrant()
	local record = self.selectedRecord
	local warrant = record and (record.Warrants or {})[1]
	if not record or not warrant or not self.canWriteWarrants then
		return
	end
	if self.revokeConfirmationId ~= warrant.WarrantId then
		self.revokeConfirmationId = warrant.WarrantId
		self.revokeAction.Text = "CONFIRM REVOKE"
		task.delay(5, function()
			if self.revokeConfirmationId == warrant.WarrantId then
				self.revokeConfirmationId = nil
				self.revokeAction.Text = "REVOKE WARRANT"
			end
		end)
		return
	end
	self.revokeConfirmationId = nil
	local response = self.context.Controllers.NetworkController:Request("MDTRevokeWarrant", {
		CharacterId = record.CharacterId,
		WarrantId = warrant.WarrantId,
	})
	self.status.Text = response.Message
	if response.Success then
		self:_performSearch()
	end
end

function MDTController:_performSearch()
	-- Home and the map have no record type to search. Their controls are hidden,
	-- so this is unreachable today, but sending the page name as a record type
	-- would be rejected by the server and reported to the officer as a failed
	-- search rather than as a page that simply has none.
	if
		self.recordType ~= "Person"
		and self.recordType ~= "Vehicle"
		and self.recordType ~= "Incident"
		and self.recordType ~= "Resolved"
	then
		return
	end
	self.status.Text = "Searching secure records…"
	local response = if self.recordType == "Incident" or self.recordType == "Resolved"
		then self.context.Controllers.NetworkController:Request("MDTGetIncidents", {
			Page = 1,
			ResolvedOnly = self.recordType == "Resolved",
		})
		else self:Search(self.recordType, self.input.Text, 1)
	if response.Success then
		local items = response.Data.Items or {}
		self.status.Text = string.format("%d result%s", #items, if #items == 1 then "" else "s")
		self:_renderResults(items)
	else
		self.status.Text = response.Message
	end
end

-- Paints the strip from a status the server has confirmed.
function MDTController:_renderUnitStatusChoices(statuses: { string })
	for _, control in self.unitStatusButtons do
		control:Destroy()
	end
	table.clear(self.unitStatusButtons)
	local labelsByDepartment = {
		Police = {
			Available = "AVAILABLE",
			Assigned = "EN ROUTE",
			OnScene = "ON SCENE",
			Unavailable = "UNAVAILABLE",
		},
		Ambulance = {
			Available = "AVAILABLE",
			Assigned = "MOBILISED",
			OnScene = "ON SCENE",
			Unavailable = "AT HANDOVER",
		},
		Fire = {
			Available = "AVAILABLE",
			Assigned = "MOBILISED",
			OnScene = "AT INCIDENT",
			Unavailable = "UNAVAILABLE",
		},
		Control = {
			Available = "AVAILABLE",
			Assigned = "ALLOCATING",
			OnScene = "MONITORING",
			Unavailable = "UNAVAILABLE",
		},
	}
	local labels = labelsByDepartment[self.departmentId or ""] or labelsByDepartment.Control
	for index, status in statuses do
		local label = labels[status] or string.gsub(status, "([a-z])([A-Z])", "%1 %2"):upper()
		local control = button(self.statusStrip, label)
		control.LayoutOrder = index
		control.Size = UDim2.fromOffset(112, UNIT_STATUS_ROW_HEIGHT)
		control.Activated:Connect(function()
			self:SetUnitStatus(status)
		end)
		self.unitStatusButtons[status] = control
	end
	self:_renderUnitStatus(self.unitStatus)
end

function MDTController:_renderUnitStatus(status: string?)
	self.unitStatus = status
	self.statusStrip.Visible = status ~= nil
	for id, control in self.unitStatusButtons do
		local selected = id == status
		control.BackgroundColor3 = if selected then C.Accent else C.Raised
		control.TextColor3 = if selected then C.Text else C.Muted
	end
end

function MDTController:SetUnitStatus(status: string)
	if status == self.unitStatus then
		return
	end
	local response = self.context.Controllers.NetworkController:Request(
		"DispatchSetUnitStatus",
		{ Status = status }
	)
	if response.Success then
		-- Painted from the server's answer rather than from the press, so a status
		-- the server declined is never left showing as though it took.
		self:_renderUnitStatus(response.Data and response.Data.Status or status)
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Unit status")
	end
end

function MDTController:RefreshAccess()
	local response = self.context.Controllers.NetworkController:Request("GetMDTAccess", {})
	self.allowed = response.Success and response.Data.Allowed == true
	self.departmentId = if self.allowed then response.Data.DepartmentId else nil
	local service = departmentUI(self.departmentId)
	if self.serviceTitle then
		self.serviceTitle.Text = service.Title
		self.serviceSubtitle.Text = service.Subtitle
	end
	if self.classification then
		self.classification.BackgroundColor3 = if self.allowed
			then service.Accent
			else C.Classification
	end
	self:_buildHome()
	self:_renderUnitStatusChoices(if self.allowed then response.Data.UnitStatuses or {} else {})
	self.canWriteWarrants = self.allowed
		and table.find(response.Data.Permissions or {}, "WarrantWrite") ~= nil
	if self.allowed then
		self.secureLabel.Text = "●  "
			.. tostring(response.Data.DepartmentId or "AUTHORISED"):upper()
	end
	-- A unit only exists while the officer is on duty, so going off duty takes
	-- the strip away rather than leaving a stale status on screen.
	self:_renderUnitStatus(if self.allowed then response.Data.UnitStatus else nil)
	self.gui.Enabled = self.allowed
	-- The MDT is a persistent UX surface, not an equipment item. Emergency
	-- departments do not need an authored Tool in their loadout just to access
	-- their authorised terminal; the compact launcher remains available beside
	-- the other service controls and the M shortcut still works.
	self.launcher.Visible = self.allowed
	if not self.allowed then
		self.setOpen(false)
	end
	if self.warrantAction then
		self.warrantAction.Visible = self.selectedRecord ~= nil and self.canWriteWarrants
	end
	if self.revokeAction then
		self.revokeAction.Visible = self.selectedRecord ~= nil
			and self.canWriteWarrants
			and #((self.selectedRecord and self.selectedRecord.Warrants) or {}) > 0
	end
end

function MDTController:Start()
	self:_mount()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSCCTVOpen"):Connect(function()
			if playerGui:GetAttribute("RoleplayOSCCTVOpen") == true and self.shell.Visible then
				self.setOpen(false)
			end
		end)
	)
	local function updateShortcutLabel(lastInputType: Enum.UserInputType)
		if tostring(lastInputType):find("Gamepad") then
			local key = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonSelect)
			local image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonSelect)
			self.launcher.Text = if image == ""
				then "MDT  ·  " .. (if key == "" then "VIEW" else key)
				else "MDT"
			self.shortcutGlyph.Image = image
			self.shortcutGlyph.Visible = image ~= ""
		else
			self.launcher.Text = "MDT  ·  M"
			self.shortcutGlyph.Visible = false
		end
	end
	local function toggleMDT(
		_actionName: string,
		inputState: Enum.UserInputState,
		inputObject: InputObject
	): Enum.ContextActionResult
		if
			inputState == Enum.UserInputState.Begin
			and inputObject.KeyCode == Enum.KeyCode.ButtonB
		then
			if self.warrantModal.Visible then
				self.warrantModal.Visible = false
				GuiService.SelectedObject = self.warrantAction
				return Enum.ContextActionResult.Sink
			elseif self.shell.Visible then
				self.setOpen(false)
				GuiService.SelectedObject = self.launcher
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end
		if
			inputState ~= Enum.UserInputState.Begin
			or not self.allowed
			or UserInputService:GetFocusedTextBox() ~= nil
		then
			return Enum.ContextActionResult.Pass
		end
		self.setOpen(not self.shell.Visible)
		if self.shell.Visible and UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.close
		elseif
			GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.shell)
		then
			GuiService.SelectedObject = self.launcher
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(
		MDT_ACTION,
		toggleMDT,
		false,
		Enum.KeyCode.M,
		Enum.KeyCode.ButtonSelect,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(MDT_ACTION, "MDT")
	ContextActionService:SetDescription(MDT_ACTION, "Open or close the data terminal.")
	updateShortcutLabel(UserInputService:GetLastInputType())
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(updateShortcutLabel)
	)
	local watchedTools = {}
	local function watchTool(tool: Instance)
		if
			not tool:IsA("Tool")
			or (tool.Name ~= "MDT" and tool:GetAttribute("RoleplayOSToolId") ~= "MDT")
			or watchedTools[tool]
		then
			return
		end
		watchedTools[tool] = true
		local function open()
			if self.allowed then
				self.setOpen(true)
			end
		end
		table.insert(self.connections, tool.Equipped:Connect(open))
		table.insert(self.connections, tool.Activated:Connect(open))
		table.insert(
			self.connections,
			tool.Unequipped:Connect(function()
				self.setOpen(false)
			end)
		)
	end
	local backpack = Players.LocalPlayer:WaitForChild("Backpack")
	for _, item in backpack:GetChildren() do
		watchTool(item)
	end
	table.insert(self.connections, backpack.ChildAdded:Connect(watchTool))
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			table.insert(self.connections, character.ChildAdded:Connect(watchTool))
		end)
	)
	-- Only the refreshes the server triggers are coalesced. An officer typing a
	-- search or switching tabs still goes straight out, because that is the
	-- player asking rather than dispatch telling.
	self.incidentRefresh = Coalescer.new(INCIDENT_REFRESH_INTERVAL, function()
		self:_performSearch()
	end)
	self.mapRefresh = Coalescer.new(MAP_REFRESH_INTERVAL, function()
		self:RefreshMap()
	end)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			self:RefreshAccess()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.DispatchChanged.Event:Connect(function(update)
			if not self.allowed then
				return
			end
			if update.Kind == "CallCreated" then
				self.context.Controllers.NotificationController:Show(
					"A new relevant dispatch call is available in MDT incidents.",
					"MDT update"
				)
			end
			if self.recordType == "Incident" and self.shell.Visible then
				self.incidentRefresh:Request()
			end
		end)
	)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("MDT", function(layout)
		-- While driving the minimap moves to the left edge and the needs bars to
		-- the bottom left, so the launcher stacks directly beneath the minimap
		-- rather than sharing either position. The offset is derived from the
		-- minimap's own height so the two cannot drift into each other.
		-- Derived from the minimap's own configured footprint rather than a copy
		-- of its numbers, so resizing that panel moves this out of the way too.
		local minimap = Config.Minimap
		local minimapBottom = minimap.VehicleAnchorY
			+ (minimap.CompactPanelSize.Y / 2 * layout.HudScale)
				/ math.max(layout.Viewport.Y, 1)
		self.launcher.AnchorPoint = Vector2.new(0, 0)
		self.launcher.Position = if layout.Vehicle
			then UDim2.new(0, 18, minimapBottom, 12)
			-- On foot, keep the persistent terminal affordance in the same safe
			-- top-left rail as the radio instead of placing it at a fixed fraction
			-- of the viewport. That fixed 62% position was effectively invisible on
			-- tall displays and looked like the MDT had not been issued.
			else UDim2.fromOffset(18, layout.NativeTop + 58)
		-- The shell never shrinks below its minimum size, so it is scaled against
		-- the usable area on every device class. Measuring the raw viewport
		-- instead let the terminal spill under the top bar and device cutouts.
		self.scale.Scale =
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(720, 470), 24)
		-- Closed on getting into a vehicle, not on every layout publish.
		--
		-- This ran on each publish, and the orchestrator publishes whenever the
		-- last input type changes, which on a mouse is constantly. Pressing M in a
		-- car reopened the terminal and the next mouse movement shut it again, so
		-- an officer could not re-read the call they were driving to. Closing it
		-- once on the way in keeps the windscreen clear without making the
		-- terminal unusable for the whole journey.
		if layout.Vehicle ~= self.inVehicle then
			self.inVehicle = layout.Vehicle
			if layout.Vehicle then
				self.setOpen(false)
			end
		end
	end)
	-- Dispatch pushes a change event whenever a call or unit moves state, so the
	-- map follows the live picture without polling.
	table.insert(
		self.connections,
		self.context.Events.DispatchChanged.Event:Connect(function()
			if self.shell.Visible then
				self.mapRefresh:Request()
			end
		end)
	)
	self:RefreshAccess()
end

function MDTController:Search(recordType: string, query: string, page: number?): any
	return self.context.Controllers.NetworkController:Request(
		"MDTSearch",
		{ Type = recordType, Query = query, Page = page or 1 }
	)
end

function MDTController:Destroy()
	ContextActionService:UnbindAction(MDT_ACTION)
	if self.incidentRefresh then
		self.incidentRefresh:Cancel()
	end
	if self.mapRefresh then
		self.mapRefresh:Cancel()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.map then
		self.map:Destroy()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return MDTController
