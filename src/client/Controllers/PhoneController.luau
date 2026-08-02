--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PhoneController = { connections = {}, activeCall = nil }
local C = {
	Body = Color3.fromRGB(9, 12, 18),
	Screen = Color3.fromRGB(18, 24, 35),
	Card = Color3.fromRGB(30, 39, 54),
	Text = Color3.fromRGB(247, 249, 253),
	Muted = Color3.fromRGB(158, 171, 191),
	Blue = Color3.fromRGB(77, 151, 255),
	Green = Color3.fromRGB(53, 199, 111),
	Red = Color3.fromRGB(239, 75, 86),
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function label(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
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

local function button(parent: Instance, value: string, colour: Color3?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = colour or C.Card
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.Parent = parent
	corner(item, 10)
	return item
end

local function input(parent: Instance, placeholder: string, multiline: boolean?): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = C.Card
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.MultiLine = multiline == true
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = C.Muted
	item.Text = ""
	item.TextColor3 = C.Text
	item.TextSize = 12
	item.TextWrapped = multiline == true
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Top
	item.Parent = parent
	corner(item, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = item
	return item
end

function PhoneController:Init(context: any)
	self.context = context
	self.page = "Home"
end

function PhoneController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSPhone"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local launcher = button(gui, "PHONE  ·  P", C.Body)
	launcher.AnchorPoint = Vector2.new(1, 1)
	launcher.Position = UDim2.new(1, -18, 1, -88)
	launcher.Size = UDim2.fromOffset(112, 38)
	launcher.Visible = false
	self.launcher = launcher

	local body = Instance.new("Frame")
	body.Name = "Phone"
	body.AnchorPoint = Vector2.new(1, 1)
	body.Position = UDim2.new(1, -18, 1, -76)
	body.Size = UDim2.fromOffset(326, 610)
	body.BackgroundColor3 = C.Body
	body.BorderSizePixel = 0
	body.Visible = false
	body.Parent = gui
	corner(body, 34)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(72, 82, 98)
	stroke.Thickness = 2
	stroke.Parent = body
	self.body = body

	local screen = Instance.new("Frame")
	screen.Position = UDim2.fromOffset(7, 7)
	screen.Size = UDim2.new(1, -14, 1, -14)
	screen.BackgroundColor3 = C.Screen
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.Parent = body
	corner(screen, 28)
	self.screen = screen
	local island = Instance.new("Frame")
	island.AnchorPoint = Vector2.new(0.5, 0)
	island.Position = UDim2.new(0.5, 0, 0, 10)
	island.Size = UDim2.fromOffset(92, 22)
	island.BackgroundColor3 = Color3.new()
	island.BorderSizePixel = 0
	island.Parent = screen
	corner(island, 12)
	local time = label(screen, "09:41", 10, true)
	time.Position = UDim2.fromOffset(18, 12)
	time.Size = UDim2.fromOffset(55, 18)
	local close = button(screen, "×")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(28, 24)

	local heading = label(screen, "Phone", 24, true)
	heading.Position = UDim2.fromOffset(18, 48)
	heading.Size = UDim2.new(1, -36, 0, 34)
	self.heading = heading
	local number = label(screen, "Select a character", 10)
	number.Position = UDim2.fromOffset(18, 81)
	number.Size = UDim2.new(1, -36, 0, 18)
	number.TextColor3 = C.Muted
	self.number = number

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 112)
	content.Size = UDim2.new(1, -28, 1, -174)
	content.Parent = screen
	self.content = content

	local dock = Instance.new("Frame")
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Position = UDim2.new(0.5, 0, 1, -10)
	dock.Size = UDim2.new(1, -28, 0, 48)
	dock.BackgroundColor3 = Color3.fromRGB(27, 35, 49)
	dock.BackgroundTransparency = 0.08
	dock.BorderSizePixel = 0
	dock.Parent = screen
	corner(dock, 16)
	local home = button(dock, "HOME")
	home.Position = UDim2.fromOffset(5, 5)
	home.Size = UDim2.new(0.25, -7, 1, -10)
	local dial = button(dock, "CALL")
	dial.Position = UDim2.new(0.25, 2, 0, 5)
	dial.Size = UDim2.new(0.25, -7, 1, -10)
	local messages = button(dock, "TEXT")
	messages.Position = UDim2.new(0.5, 2, 0, 5)
	messages.Size = UDim2.new(0.25, -7, 1, -10)
	local emergency = button(dock, "999", C.Red)
	emergency.Position = UDim2.new(0.75, 2, 0, 5)
	emergency.Size = UDim2.new(0.25, -7, 1, -10)
	local function show(page: string)
		self.page = page
		self:_render()
	end
	home.Activated:Connect(function()
		show("Home")
	end)
	dial.Activated:Connect(function()
		show("Call")
	end)
	messages.Activated:Connect(function()
		show("Messages")
	end)
	emergency.Activated:Connect(function()
		show("Emergency")
	end)
	launcher.Activated:Connect(function()
		body.Visible = not body.Visible
		if body.Visible then
			self:Refresh()
		end
	end)
	close.Activated:Connect(function()
		body.Visible = false
	end)
end

function PhoneController:_clear()
	for _, child in self.content:GetChildren() do
		child:Destroy()
	end
end

function PhoneController:_render()
	self:_clear()
	self.heading.Text = self.page
	if self.page == "Home" then
		local greeting = label(self.content, "Connected to RoleplayOS Mobile", 16, true)
		greeting.Size = UDim2.new(1, 0, 0, 48)
		local copy = label(
			self.content,
			"Call or message players currently in this server. For emergencies, use the dedicated 999 service.",
			11
		)
		copy.Position = UDim2.fromOffset(0, 58)
		copy.Size = UDim2.new(1, 0, 0, 80)
		copy.TextColor3 = C.Muted
	elseif self.page == "Call" then
		local number = input(self.content, "07xxx xxx xxx")
		number.Size = UDim2.new(1, 0, 0, 48)
		local call = button(self.content, "CALL", C.Green)
		call.Position = UDim2.fromOffset(0, 60)
		call.Size = UDim2.new(1, 0, 0, 44)
		call.Activated:Connect(function()
			local response = self.context.Controllers.NetworkController:Request(
				"PhonePlaceCall",
				{ Number = number.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Phone")
			if response.Success then
				self.activeCall = response.Data
				self:_renderCall()
			end
		end)
	elseif self.page == "Messages" then
		local number = input(self.content, "Recipient number")
		number.Size = UDim2.new(1, 0, 0, 46)
		local message = input(self.content, "Write a message", true)
		message.Position = UDim2.fromOffset(0, 56)
		message.Size = UDim2.new(1, 0, 0, 120)
		local send = button(self.content, "SEND MESSAGE", C.Blue)
		send.Position = UDim2.fromOffset(0, 188)
		send.Size = UDim2.new(1, 0, 0, 44)
		send.Activated:Connect(function()
			local response = self.context.Controllers.NetworkController:Request(
				"PhoneSendText",
				{ Number = number.Text, Message = message.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Messages")
			if response.Success then
				message.Text = ""
				self:Refresh()
			end
		end)
		local history = Instance.new("ScrollingFrame")
		history.BackgroundTransparency = 1
		history.BorderSizePixel = 0
		history.Position = UDim2.fromOffset(0, 244)
		history.Size = UDim2.new(1, 0, 1, -244)
		history.AutomaticCanvasSize = Enum.AutomaticSize.Y
		history.CanvasSize = UDim2.new()
		history.ScrollBarThickness = 2
		history.Parent = self.content
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 7)
		layout.Parent = history
		local messages = if self.phoneData then self.phoneData.Messages else {}
		for index = #messages, math.max(1, #messages - 19), -1 do
			local record = messages[index]
			local row = Instance.new("Frame")
			row.BackgroundColor3 = if record.Direction == "Outgoing" then C.Blue else C.Card
			row.BackgroundTransparency = if record.Direction == "Outgoing" then 0.15 else 0
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -4, 0, 50)
			row.Parent = history
			corner(row, 10)
			local body = label(row, record.Body, 10)
			body.Position = UDim2.fromOffset(10, 6)
			body.Size = UDim2.new(1, -20, 0, 24)
			local peer = if record.Direction == "Outgoing"
				then record.ToNumber
				else record.FromNumber
			local meta = label(row, record.Direction .. "  ·  " .. peer, 8)
			meta.Position = UDim2.fromOffset(10, 31)
			meta.Size = UDim2.new(1, -20, 0, 13)
			meta.TextColor3 = C.Muted
		end
	elseif self.page == "Emergency" then
		local warning = label(self.content, "999 EMERGENCY", 16, true)
		warning.Size = UDim2.new(1, 0, 0, 30)
		warning.TextColor3 = C.Red
		local summary = input(self.content, "What is happening?", true)
		summary.Position = UDim2.fromOffset(0, 38)
		summary.Size = UDim2.new(1, 0, 0, 98)
		local location = input(self.content, "Exact location")
		location.Position = UDim2.fromOffset(0, 146)
		location.Size = UDim2.new(1, 0, 0, 46)
		local send = button(self.content, "CALL 999", C.Red)
		send.Position = UDim2.fromOffset(0, 204)
		send.Size = UDim2.new(1, 0, 0, 46)
		send.Activated:Connect(function()
			local response = self.context.Controllers.NetworkController:Request(
				"PhoneEmergency",
				{ Summary = summary.Text, Location = location.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "999")
		end)
	end
end

function PhoneController:_renderCall()
	self:_clear()
	self.heading.Text = "Call"
	local call = self.activeCall
	if not call then
		return
	end
	local localUserId = Players.LocalPlayer.UserId
	local other = if call.CallerUserId == localUserId
		then call.RecipientNumber
		else call.CallerNumber
	local number = label(self.content, other, 22, true)
	number.Position = UDim2.fromOffset(0, 60)
	number.Size = UDim2.new(1, 0, 0, 34)
	number.TextXAlignment = Enum.TextXAlignment.Center
	local state = label(self.content, call.State, 12)
	state.Position = UDim2.fromOffset(0, 100)
	state.Size = UDim2.new(1, 0, 0, 24)
	state.TextColor3 = C.Muted
	state.TextXAlignment = Enum.TextXAlignment.Center
	if call.State == "Ringing" and call.RecipientUserId == localUserId then
		local answer = button(self.content, "ANSWER", C.Green)
		answer.Position = UDim2.fromOffset(0, 155)
		answer.Size = UDim2.new(1, 0, 0, 46)
		answer.Activated:Connect(function()
			self.context.Controllers.NetworkController:Request(
				"PhoneAnswerCall",
				{ CallId = call.CallId }
			)
		end)
	end
	local finish = button(self.content, "END CALL", C.Red)
	finish.Position = UDim2.fromOffset(0, 216)
	finish.Size = UDim2.new(1, 0, 0, 46)
	finish.Activated:Connect(function()
		self.context.Controllers.NetworkController:Request("PhoneEndCall", { CallId = call.CallId })
	end)
end

function PhoneController:Refresh()
	local response = self.context.Controllers.NetworkController:Request("GetPhone", {})
	if response.Success then
		self.phoneData = response.Data
		self.number.Text = response.Data.Number
		self.activeCall = response.Data.ActiveCall
		if self.activeCall then
			self:_renderCall()
		else
			self:_render()
		end
	else
		self.number.Text = response.Message
		self:_render()
	end
end

function PhoneController:Start()
	self:_mount()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(inputObject, processed)
			if
				not processed
				and inputObject.KeyCode == Enum.KeyCode.P
				and self.launcher.Visible
			then
				self.body.Visible = not self.body.Visible
				if self.body.Visible then
					self:Refresh()
				end
			end
		end)
	)
	local event = self.context.Controllers.NetworkController.remotes:WaitForChild("PhoneChanged")
	table.insert(
		self.connections,
		event.OnClientEvent:Connect(function(update)
			if update.Kind == "Text" then
				self:Refresh()
				self.context.Controllers.NotificationController:Show(
					"New message received.",
					"Messages"
				)
			elseif update.Kind == "Call" then
				self.activeCall = if update.Call.State == "Ended" then nil else update.Call
				self.body.Visible = true
				if self.activeCall then
					self:_renderCall()
				else
					self:_render()
				end
			end
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.CharacterChanged.Event:Connect(function()
			self.launcher.Visible = true
			self:Refresh()
		end)
	)
end

function PhoneController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.gui then
		self.gui:Destroy()
	end
end

return PhoneController
