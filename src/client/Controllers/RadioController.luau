--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TerminalTheme = require(script.Parent.Parent.UI.OperationalTerminalTheme)

local RadioController = { connections = {} }
local C = {
	Body = TerminalTheme.Surface,
	Panel = TerminalTheme.Raised,
	Card = Color3.fromRGB(20, 45, 67),
	Text = TerminalTheme.Text,
	Muted = TerminalTheme.Muted,
	Green = TerminalTheme.Secure,
	Accent = TerminalTheme.Accent,
	Border = TerminalTheme.Border,
	Immediate = TerminalTheme.Immediate,
}

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
	item.TextWrapped = true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = C.Card
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.Parent = parent
	corner(item, 9)
	return item
end

function RadioController:Init(context: any)
	self.context = context
	self.open = false
	self.snapshot = nil
	self.vehicleMode = false
	-- The radio is an always-available operational surface while on duty, but
	-- "available" is not the same as "occupying the screen".
	--
	-- It had no collapsed state at all, and a 300 by 320 panel on a landscape
	-- phone is most of the height of the world: it sat over the stamina and
	-- hunger bars and the hotbar, and its own transmit box fell off the bottom
	-- edge. A player could see the game around it but could not use the parts it
	-- was standing on.
	--
	-- Collapsed it is a single bar naming the channel, which is the only part
	-- that matters when nothing is happening, and one press opens it.
	self.collapsed = false
	-- Set from the first layout: a phone starts collapsed, a desktop with room
	-- to spare starts open.
	self.collapseChosen = false
	-- A full-screen device borrows the whole screen. The radio is not dismissed
	-- while one is open, it is hidden, and comes back when the device closes.
	self.deviceOpen = false
	self.callsignEditable = false
	self.muted = false
end

function RadioController:_showCallsignModal()
	if not self.gui or self.callsignModal then
		return
	end
	local shade = Instance.new("TextButton")
	shade.Name = "CallsignModalShade"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 20
	shade.Parent = self.gui
	local modal = Instance.new("Frame")
	modal.Name = "CallsignModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(330, 218)
	modal.BackgroundColor3 = C.Body
	modal.BorderSizePixel = 0
	modal.ZIndex = 21
	modal.Parent = shade
	corner(modal, 10)
	local outline = Instance.new("UIStroke")
	outline.Color = C.Border
	outline.Thickness = 1.5
	outline.Parent = modal
	local title = text(modal, "UNIT CALLSIGN", 17, true)
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 26)
	local copy = text(modal, "Enter the callsign used by this crew member.", 11)
	copy.TextColor3 = C.Muted
	copy.Position = UDim2.fromOffset(20, 48)
	copy.Size = UDim2.new(1, -40, 0, 20)
	local input = Instance.new("TextBox")
	input.Name = "CallsignInput"
	input.BackgroundColor3 = C.Card
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.GothamBold
	input.PlaceholderText = "e.g. PC 1013"
	input.PlaceholderColor3 = C.Muted
	input.Text = if self.snapshot and self.snapshot.Callsign then self.snapshot.Callsign else ""
	input.TextColor3 = C.Text
	input.TextSize = 14
	input.Position = UDim2.fromOffset(20, 80)
	input.Size = UDim2.new(1, -40, 0, 42)
	input.ZIndex = 22
	input.Parent = modal
	corner(input, 7)
	local cancel = button(modal, "CANCEL")
	cancel.Position = UDim2.new(0, 20, 1, -55)
	cancel.Size = UDim2.new(0.5, -25, 0, 36)
	cancel.ZIndex = 22
	local save = button(modal, "SAVE CALLSIGN")
	save.Position = UDim2.new(0.5, 5, 1, -55)
	save.Size = UDim2.new(0.5, -25, 0, 36)
	save.BackgroundColor3 = C.Green
	save.ZIndex = 22
	local function close()
		if shade.Parent then
			shade:Destroy()
		end
		self.callsignModal = nil
	end
	cancel.Activated:Connect(close)
	save.Activated:Connect(function()
		if input.Text == "" then
			return
		end
		save.Text = "SAVING…"
		local response = self.context.Controllers.NetworkController:Request("RadioSetCallsign", {
			Callsign = input.Text,
		})
		if response.Success then
			close()
			self:refresh()
		else
			save.Text = "SAVE CALLSIGN"
			self.context.Controllers.NotificationController:Show(response.Message, "Callsign")
		end
	end)
	self.callsignModal = shade
	input:CaptureFocus()
end

-- The body is shown when the radio is on duty AND no full-screen device has
-- borrowed the screen. Kept in one place because two independent things hide it.
function RadioController:_applyVisibility()
	if self.body then
		self.body.Visible = self.open and not self.deviceOpen
	end
end

-- Whether an MDT or CCTV view currently owns the screen.
--
-- The listeners for these called _setOpen(self.open), which re-set the value it
-- already had and therefore did nothing at all. The radio stayed on top of the
-- terminal it was covering: it sits at DisplayOrder 38 against the MDT's 35, so
-- it took the terminal's search box and the whole left column of its results.
function RadioController:_refreshDeviceState()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	self.deviceOpen = playerGui:GetAttribute("RoleplayOSMDTOpen") == true
		or playerGui:GetAttribute("RoleplayOSCCTVOpen") == true
	self:_applyVisibility()
end

function RadioController:_setCollapsed(collapsed: boolean)
	self.collapsed = collapsed
	if self.collapseIcon then
		self.collapseIcon.Text = if collapsed then "\u{25B8}" else "\u{25BE}"
	end
	if self.lastLayout and self.resize then
		self.resize(self.lastLayout)
	end
end

function RadioController:_setOpen(open: boolean)
	self.open = open
	self:_applyVisibility()
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if gui then
		gui:SetAttribute("RoleplayOSRadioOpen", open)
	end
	if open then
		self:refresh()
	end
end

function RadioController:_render()
	if not self.content then
		return
	end
	for _, child in self.content:GetChildren() do
		child:Destroy()
	end
	local snapshot = self.snapshot
	if self.header then
		local channelName = if snapshot
			then (function()
				for _, channel in snapshot.Channels do
					if channel.Id == snapshot.CurrentChannelId then
						return channel.Name
					end
				end
				return tostring(snapshot.CurrentChannelId)
			end)()
			else "OFF DUTY"
		self.header.Text = "RADIO  ·  " .. channelName
		self.callsign.Text = if snapshot
			then "UNIT " .. tostring(snapshot.Callsign or "UNASSIGNED")
			else "Operational channel"
	end
	if self.editCallsign then
		-- Recorded rather than shown directly: whether the control is available
		-- is decided here, whether there is room for it is decided by the layout.
		self.callsignEditable = true
		self.editCallsign.Visible = not self.collapsed
	end
	-- Collapsed wins. A refresh arriving while the panel is shut must not
	-- reopen its body underneath the closed header.
	self.content.Visible = self.open and not self.collapsed
	if not snapshot then
		text(self.content, "Radio unavailable", 16, true).Size = UDim2.new(1, 0, 0, 28)
		text(self.content, "Report for duty to access operational channels.", 12).Position =
			UDim2.fromOffset(0, 38)
		return
	end
	local channelBar = Instance.new("Frame")
	channelBar.Name = "ZenithTopBar"
	channelBar.BackgroundTransparency = 1
	channelBar.Size = UDim2.new(1, 0, 0, 34)
	channelBar.Parent = self.content
	local function channelAt(offset: number): any?
		local current = 1
		for index, channel in snapshot.Channels do
			if channel.Id == snapshot.CurrentChannelId then
				current = index
				break
			end
		end
		return snapshot.Channels[((current - 1 + offset) % #snapshot.Channels) + 1]
	end
	local function chooseChannel(offset: number)
		local channel = channelAt(offset)
		if not channel then
			return
		end
		local response = self.context.Controllers.NetworkController:Request("RadioSetChannel", {
			ChannelId = channel.Id,
		})
		if response.Success then
			self.snapshot = response.Data
			self:_render()
		end
	end
	local previous = button(channelBar, "‹")
	previous.Size = UDim2.fromOffset(22, 30)
	previous.Activated:Connect(function()
		chooseChannel(-1)
	end)
	local channelName = tostring(snapshot.CurrentChannelId)
	for _, channel in snapshot.Channels do
		if channel.Id == snapshot.CurrentChannelId then
			channelName = tostring(channel.Name)
			break
		end
	end
	local channelTitle = button(channelBar, channelName)
	channelTitle.Position = UDim2.fromOffset(28, 0)
	channelTitle.Size = UDim2.fromOffset(100, 30)
	channelTitle.BackgroundColor3 = C.Green
	channelTitle.Activated:Connect(function()
		chooseChannel(1)
	end)
	local nextChannel = button(channelBar, "›")
	nextChannel.Position = UDim2.fromOffset(134, 0)
	nextChannel.Size = UDim2.fromOffset(22, 30)
	nextChannel.Activated:Connect(function()
		chooseChannel(1)
	end)
	local mute = button(channelBar, "MIC")
	mute.Position = UDim2.fromOffset(162, 0)
	mute.Size = UDim2.fromOffset(44, 30)
	mute.Activated:Connect(function()
		self.muted = not self.muted
		mute.Text = if self.muted then "MUTED" else "MIC"
		mute.BackgroundColor3 = if self.muted then C.Card else C.Accent
	end)
	local panic = button(channelBar, "PANIC")
	panic.Name = "Panic"
	panic.Position = UDim2.fromOffset(214, 0)
	panic.Size = UDim2.fromOffset(54, 30)
	panic.BackgroundColor3 = C.Immediate
	panic.Activated:Connect(function()
		local response = self.context.Controllers.NetworkController:Request("RadioPanic", {})
		if response.Success and self.panicSound then
			self.panicSound:Play()
		end
		self.context.Controllers.NotificationController:Show(response.Message, "RADIO PANIC")
	end)
	local log = Instance.new("ScrollingFrame")
	log.Name = "MessageLog"
	log.BackgroundColor3 = C.Panel
	log.BackgroundTransparency = 0.14
	log.BorderSizePixel = 0
	log.CanvasSize = UDim2.new()
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollBarThickness = 3
	log.Position = UDim2.fromOffset(0, 38)
	log.Size = UDim2.new(1, 0, 1, -82)
	log.Parent = self.content
	corner(log, 10)
	local logLayout = Instance.new("UIListLayout")
	logLayout.Padding = UDim.new(0, 5)
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Parent = log
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = log
	if #snapshot.Messages == 0 then
		local empty = text(log, "No traffic on this channel", 11)
		empty.LayoutOrder = 1
		empty.Size = UDim2.new(1, 0, 0, 32)
		empty.TextColor3 = C.Muted
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
	for _, entry in snapshot.Messages do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 34)
		row.Parent = log
		local line = text(row, string.format("%s  %s", entry.Callsign, entry.Message), 11)
		line.Size = UDim2.new(1, 0, 1, -7)
		local separator = Instance.new("Frame")
		separator.BackgroundColor3 = C.Border
		separator.BackgroundTransparency = 0.35
		separator.BorderSizePixel = 0
		separator.Position = UDim2.new(0, 0, 1, -1)
		separator.Size = UDim2.new(1, 0, 0, 1)
		separator.Parent = row
	end
	local input = Instance.new("TextBox")
	input.Name = "TransmitBox"
	input.BackgroundColor3 = C.Card
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Transmit on " .. tostring(snapshot.CurrentChannelId)
	input.PlaceholderColor3 = C.Muted
	input.Text = ""
	input.TextColor3 = C.Text
	input.TextSize = 12
	input.Position = UDim2.new(0, 0, 1, -34)
	input.Size = UDim2.new(1, -62, 0, 34)
	input.Parent = self.content
	corner(input, 10)
	local transmit = button(self.content, "SEND")
	transmit.Name = "Transmit"
	transmit.BackgroundColor3 = C.Green
	transmit.Position = UDim2.new(1, -56, 1, -34)
	transmit.Size = UDim2.fromOffset(56, 34)
	transmit.Activated:Connect(function()
		if input.Text == "" then
			return
		end
		local response = self.context.Controllers.NetworkController:Request("RadioTransmit", {
			Message = input.Text,
		})
		if response.Success then
			input.Text = ""
			self:refresh()
		else
			self.context.Controllers.NotificationController:Show(response.Message, "Radio")
		end
	end)
end

function RadioController:refresh()
	local response = self.context.Controllers.NetworkController:Request("GetRadioSnapshot", {})
	if response.Success then
		self.snapshot = response.Data
	else
		self.snapshot = nil
		if self.open and response.Message and response.Message ~= "" then
			self.context.Controllers.NotificationController:Show(response.Message, "Radio")
		end
	end
	self:_render()
end

function RadioController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSRadio"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 38
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local panicSound = Instance.new("Sound")
	panicSound.Name = "PanicConfirmation"
	-- This is the panic-button tone from the imported Zenith radio package,
	-- rather than the generic bank/robbery alarm used by other systems.
	panicSound.SoundId = "rbxassetid://1826283298"
	panicSound.Volume = 0.35
	panicSound.Parent = SoundService
	self.panicSound = panicSound
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(1, 0)
	-- The radio stays as a compact left-side panel beneath Roblox's top UI,
	-- matching the native chat/control cluster rather than the bottom hotbar.
	-- CoreUISafeInsets protects it from platform chrome and device cutouts.
	body.Position = UDim2.new(1, -18, 0, 72)
	body.Size = UDim2.fromOffset(300, 320)
	body.BackgroundColor3 = C.Body
	body.BackgroundTransparency = 0.12
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.Visible = false
	body.Parent = gui
	corner(body, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = body
	self.body = body
	local header = text(body, "RADIO", 16, true)
	header.Position = UDim2.fromOffset(14, 10)
	header.Size = UDim2.fromOffset(150, 26)
	local callsign = text(body, "Operational channel", 10)
	callsign.Position = UDim2.fromOffset(14, 33)
	callsign.Size = UDim2.new(1, -36, 0, 18)
	callsign.TextColor3 = C.Muted
	-- The header doubles as the collapse control, so the bar you can see when it
	-- is shut is the same thing you press to open it. Stops short of the EDIT
	-- button so that stays pressable.
	local collapseToggle = Instance.new("TextButton")
	collapseToggle.BackgroundTransparency = 1
	collapseToggle.Text = ""
	collapseToggle.Position = UDim2.fromOffset(0, 0)
	collapseToggle.Size = UDim2.new(1, -70, 0, 46)
	collapseToggle.ZIndex = 3
	collapseToggle.Parent = body
	collapseToggle.Activated:Connect(function()
		self:_setCollapsed(not self.collapsed)
	end)
	local collapseIcon = text(body, "\u{25BE}", 14, true)
	collapseIcon.AnchorPoint = Vector2.new(1, 0)
	collapseIcon.Position = UDim2.new(1, -68, 0, 12)
	collapseIcon.Size = UDim2.fromOffset(18, 24)
	collapseIcon.TextColor3 = C.Muted
	collapseIcon.ZIndex = 2
	self.collapseIcon = collapseIcon
	local editCallsign = button(body, "EDIT")
	editCallsign.AnchorPoint = Vector2.new(1, 0)
	editCallsign.Position = UDim2.new(1, -14, 0, 12)
	editCallsign.Size = UDim2.fromOffset(48, 24)
	editCallsign.TextSize = 10
	editCallsign.Visible = false
	editCallsign.Activated:Connect(function()
		self:_showCallsignModal()
	end)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 76)
	content.Size = UDim2.new(1, -28, 1, -88)
	content.Parent = body
	self.content = content
	content.Visible = true
	self.header = header
	self.callsign = callsign
	self.editCallsign = editCallsign
	self.bodyScale = Instance.new("UIScale")
	self.bodyScale.Parent = body
	self.resize = function(layout)
		self.lastLayout = layout
		-- A phone opens collapsed, a desktop opens ready to use. Decided once, so
		-- a later layout signal never reopens a panel the player has just shut.
		if not self.collapseChosen then
			self.collapseChosen = true
			self.collapsed = layout.Compact or layout.InputMode == "Touch"
			if self.collapseIcon then
				self.collapseIcon.Text = if self.collapsed then "\u{25B8}" else "\u{25BE}"
			end
		end
		-- Smaller where there is less room, rather than the same panel everywhere
		-- shrunk until its text is unreadable.
		local footprint = if layout.Compact then Vector2.new(268, 236) else Vector2.new(300, 320)
		local collapsedHeight = 46
		local expanded = not self.collapsed
		content.Visible = self.open and expanded
		content.Position = UDim2.fromOffset(14, 76)
		content.Size = UDim2.new(1, -28, 1, -88)
		self.callsign.Visible = expanded
		self.editCallsign.Visible = expanded and self.callsignEditable == true
		body.AnchorPoint = Vector2.new(0, 0)
		-- No inset is added here. This ScreenGui is mounted with CoreUISafeInsets,
		-- so its own origin is already inside the region Roblox leaves free; adding
		-- SafeLeft and NativeTop on top of that applied the cutout and the top bar
		-- a second time and pushed the panel about fifty pixels further down than
		-- intended, which is what drove its transmit box off the bottom edge.
		body.Position = UDim2.fromOffset(12, 12)
		body.Size = UDim2.fromOffset(footprint.X, if expanded then footprint.Y else collapsedHeight)
		if layout.Compact then
			-- Fitted against the height actually left below the panel's own top
			-- margin. FitScale against the raw footprint returned 1.0 here, so
			-- nothing shrank and a 320-tall panel stood on a 371-tall screen.
			local available = Vector2.new(footprint.X, math.max(1, footprint.Y + 24))
			self.bodyScale.Scale =
				self.context.Controllers.UIOrchestrator:FitScale(layout, available, 24)
		else
			self.bodyScale.Scale = math.clamp(
				math.min(layout.SafeViewport.X / 1200, layout.SafeViewport.Y / 760),
				0.82,
				1
			)
		end
	end
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Radio", self.resize)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function(duty)
			self:_setOpen(duty ~= nil)
			if duty ~= nil then
				-- Duty and the server radio snapshot can arrive on adjacent frames.
				-- Retry after the duty state has settled so the panel cannot remain
				-- stuck in its empty/off-duty state.
				task.delay(0.35, function()
					if self.open then
						self:refresh()
					end
				end)
			end
		end)
	)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSMDTOpen"):Connect(function()
			self:_refreshDeviceState()
		end)
	)
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSCCTVOpen"):Connect(function()
			self:_refreshDeviceState()
		end)
	)
	-- Read once at startup as well as on change: joining straight into a seat
	-- with a terminal already open would otherwise leave the radio on top of it
	-- until the player happened to close and reopen the device.
	self:_refreshDeviceState()
	local initial = self.context.Controllers.NetworkController:Request("GetRadioSnapshot", {})
	if initial.Success then
		self.snapshot = initial.Data
		self:_setOpen(true)
	end
	local event = self.context.Controllers.NetworkController:ResolveEvent("RadioChanged")
	if event then
		table.insert(
			self.connections,
			event.OnClientEvent:Connect(function(update)
				if update.Kind == "Snapshot" then
					self.snapshot = update.Data
				else
					self:refresh()
				end
				if self.open then
					self:_render()
				end
			end)
		)
	end
	self:_render()
end

function RadioController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.body and self.body.Parent then
		self.body.Parent:Destroy()
	end
	if self.panicSound then
		self.panicSound:Destroy()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
end

return RadioController
