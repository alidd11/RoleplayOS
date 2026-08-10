--!strict

local Players = game:GetService("Players")
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
	self.expanded = false
end

function RadioController:_setExpanded(expanded: boolean)
	self.expanded = expanded
	if self.content then
		self.content.Visible = expanded
	end
	if self.callsignInput then
		self.callsignInput.Visible = expanded
	end
	if self.close then
		self.close.Text = if expanded then "×" else "+"
	end
	if self.body then
		self.body.Size = if expanded then UDim2.fromOffset(364, 360) else UDim2.fromOffset(248, 58)
	end
end

function RadioController:_setOpen(open: boolean)
	self.open = open
	if self.body then
		self.body.Visible = open
	end
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
	if not snapshot then
		text(self.content, "Radio unavailable", 16, true).Size = UDim2.new(1, 0, 0, 28)
		text(self.content, "Report for duty to access operational channels.", 12).Position =
			UDim2.fromOffset(0, 38)
		return
	end
	local channels = Instance.new("Frame")
	channels.Name = "ChannelStrip"
	channels.BackgroundTransparency = 1
	channels.Size = UDim2.new(1, -92, 0, 34)
	channels.Parent = self.content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = channels
	for _, channel in snapshot.Channels do
		local item = button(channels, channel.Name)
		item.Size = UDim2.fromOffset(104, 34)
		item.BackgroundColor3 = if channel.Id == snapshot.CurrentChannelId then C.Green else C.Card
		item.Activated:Connect(function()
			local response = self.context.Controllers.NetworkController:Request("RadioSetChannel", {
				ChannelId = channel.Id,
			})
			if response.Success then
				self.snapshot = response.Data
				self:_render()
			end
		end)
	end
	local panic = button(self.content, "PANIC")
	panic.Name = "Panic"
	panic.BackgroundColor3 = C.Immediate
	panic.Position = UDim2.new(1, -84, 0, 0)
	panic.Size = UDim2.fromOffset(84, 34)
	panic.Activated:Connect(function()
		local response = self.context.Controllers.NetworkController:Request("RadioPanic", {})
		self.context.Controllers.NotificationController:Show(response.Message, "RADIO PANIC")
	end)
	local log = Instance.new("ScrollingFrame")
	log.Name = "MessageLog"
	log.BackgroundColor3 = C.Panel
	log.BorderSizePixel = 0
	log.CanvasSize = UDim2.new()
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollBarThickness = 3
	log.Position = UDim2.fromOffset(0, 44)
	log.Size = UDim2.new(1, 0, 1, -98)
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
	for _, entry in snapshot.Messages do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 38)
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
	input.Position = UDim2.new(0, 0, 1, -42)
	input.Size = UDim2.new(1, -74, 0, 42)
	input.Parent = self.content
	corner(input, 10)
	local transmit = button(self.content, "SEND")
	transmit.Name = "Transmit"
	transmit.BackgroundColor3 = C.Green
	transmit.Position = UDim2.new(1, -66, 1, -42)
	transmit.Size = UDim2.fromOffset(66, 42)
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
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(1, 0)
	-- Zenith's intended placement is a compact right-side panel beneath Roblox's
	-- top UI, not a bottom-hotbar overlay. CoreUISafeInsets protects the panel
	-- from the platform chrome; the additional offset leaves visual breathing
	-- room below the Roblox top bar.
	body.Position = UDim2.new(1, -18, 0, 72)
	body.Size = UDim2.fromOffset(364, 360)
	body.BackgroundColor3 = C.Body
	body.BorderSizePixel = 0
	body.Visible = false
	body.Parent = gui
	corner(body, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = body
	self.body = body
	local header = text(body, "RADIO", 18, true)
	header.Position = UDim2.fromOffset(18, 12)
	header.Size = UDim2.fromOffset(150, 26)
	local callsign = text(body, "Operational channel", 10)
	callsign.Position = UDim2.fromOffset(18, 37)
	callsign.Size = UDim2.new(1, -36, 0, 18)
	callsign.TextColor3 = C.Muted
	local close = button(body, "×")
	close.Position = UDim2.new(1, -45, 0, 12)
	close.Size = UDim2.fromOffset(30, 28)
	close.Activated:Connect(function()
		self:_setExpanded(not self.expanded)
	end)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(18, 88)
	content.Size = UDim2.new(1, -36, 1, -82)
	content.Parent = body
	self.content = content
	content.Visible = false
	self.header = header
	self.callsign = callsign
	self.close = close
	local callsignInput = Instance.new("TextBox")
	callsignInput.Name = "CallsignInput"
	callsignInput.BackgroundColor3 = C.Card
	callsignInput.BorderSizePixel = 0
	callsignInput.ClearTextOnFocus = false
	callsignInput.Font = Enum.Font.GothamBold
	callsignInput.PlaceholderText = "Enter callsign"
	callsignInput.PlaceholderColor3 = C.Muted
	callsignInput.TextColor3 = C.Text
	callsignInput.TextSize = 11
	callsignInput.Text = ""
	callsignInput.Position = UDim2.fromOffset(18, 58)
	callsignInput.Size = UDim2.fromOffset(120, 24)
	callsignInput.Visible = false
	callsignInput.Parent = body
	corner(callsignInput, 6)
	callsignInput.FocusLost:Connect(function(enterPressed)
		if not enterPressed or callsignInput.Text == "" then
			return
		end
		local response = self.context.Controllers.NetworkController:Request("RadioSetCallsign", {
			Callsign = callsignInput.Text,
		})
		if response.Success then
			callsignInput.Text = response.Data.Callsign
			self:refresh()
		else
			self.context.Controllers.NotificationController:Show(response.Message, "Callsign")
		end
	end)
	self.callsignInput = callsignInput
	self.bodyScale = Instance.new("UIScale")
	self.bodyScale.Parent = body
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Radio", function(layout)
		callsignInput.Visible = self.expanded
		if layout.Compact then
			body.AnchorPoint = Vector2.new(0, 0)
			body.Position = UDim2.fromOffset(10, layout.NativeTop + 10)
			body.Size = if self.expanded
				then UDim2.fromOffset(364, 360)
				else UDim2.fromOffset(248, 58)
			self.bodyScale.Scale =
				self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(248, 58), 20)
		else
			body.AnchorPoint = Vector2.new(0, 0)
			body.Position = UDim2.fromOffset(18, layout.NativeTop + 18)
			body.Size = if self.expanded
				then UDim2.fromOffset(364, 360)
				else UDim2.fromOffset(248, 58)
			self.bodyScale.Scale = math.clamp(
				math.min(layout.SafeViewport.X / 1200, layout.SafeViewport.Y / 760),
				0.82,
				1
			)
		end
	end)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function(duty)
			self:_setOpen(duty ~= nil)
		end)
	)
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
	if self.unbindLayout then
		self.unbindLayout()
	end
end

return RadioController
