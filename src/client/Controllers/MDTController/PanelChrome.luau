--!strict

local Players = game:GetService("Players")
local TacticalMap = require(script.Parent.Parent.Parent.UI.TacticalMap)
local Utils = require(script.Parent.Utils)
local C = Utils.C
local corner = Utils.corner
local text = Utils.text
local button = Utils.button

return function(MDTController)
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
		-- A fraction of the viewport, not a fixed size, so it still fits a small
		-- screen -- but 0.86/0.82 read as "the whole screen" on anything roomier
		-- than that, which is not what a tablet sitting in an officer's hand should
		-- look like. The 720x470 floor is unchanged: that is the smallest this can
		-- be and still hold the home grid without its tiles overlapping.
		chassis.Size = UDim2.fromScale(0.58, 0.6)
		chassis.BackgroundColor3 = Color3.fromRGB(8, 11, 17)
		chassis.BorderSizePixel = 0
		chassis.SelectionGroup = true
		chassis.Visible = false
		chassis.Parent = gui
		corner(chassis, 22)
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = Vector2.new(720, 470)
		constraint.MaxSize = Vector2.new(860, 600)
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
		-- Narrower than the old 232: at three per row, three cells plus their two
		-- gaps has to clear comfortably inside the home area even at the chassis's
		-- 720-wide floor, not sit within a pixel of it. 232 left three cells and
		-- two 14px gaps equal to the available width at some sizes, which rounded
		-- down to two columns instead of three depending on the viewport.
		homeGrid.CellSize = UDim2.fromOffset(200, 90)
		homeGrid.CellPadding = UDim2.fromOffset(14, 14)
		homeGrid.SortOrder = Enum.SortOrder.LayoutOrder
		-- Capped at three rather than left to fill the shell's width. Unlimited,
		-- the row simply grew with the terminal -- four cards stretched into one
		-- wide strip on anything wider than a phone -- and every card added after
		-- this one would have kept widening it rather than starting a new row.
		homeGrid.FillDirectionMaxCells = 3
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
		local modalCopy = text(
			warrantModal,
			"The reason is filtered and the action is written to the audit log.",
			10
		)
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
end
