--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local RadioController = { connections = {} }
local ACTION = "RoleplayOSToggleRadio"
local C = {
	Body = Color3.fromRGB(12, 17, 23),
	Panel = Color3.fromRGB(24, 32, 43),
	Card = Color3.fromRGB(34, 44, 58),
	Text = Color3.fromRGB(244, 247, 250),
	Muted = Color3.fromRGB(158, 171, 191),
	Green = Color3.fromRGB(62, 180, 116),
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
	if not snapshot then
		text(self.content, "Radio unavailable", 16, true).Size = UDim2.new(1, 0, 0, 28)
		text(self.content, "Report for duty to access operational channels.", 12).Position =
			UDim2.fromOffset(0, 38)
		return
	end
	local channels = Instance.new("Frame")
	channels.BackgroundTransparency = 1
	channels.Size = UDim2.new(1, 0, 0, 38)
	channels.Parent = self.content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = channels
	for _, channel in snapshot.Channels do
		local item = button(channels, channel.Name)
		item.Size = UDim2.fromOffset(92, 34)
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
	local log = Instance.new("ScrollingFrame")
	log.BackgroundColor3 = C.Panel
	log.BorderSizePixel = 0
	log.CanvasSize = UDim2.new()
	log.AutomaticCanvasSize = Enum.AutomaticSize.Y
	log.ScrollBarThickness = 3
	log.Position = UDim2.fromOffset(0, 48)
	log.Size = UDim2.new(1, 0, 1, -112)
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
		local line = text(log, string.format("%s  %s", entry.Callsign, entry.Message), 11)
		line.Size = UDim2.new(1, 0, 0, 32)
	end
	local input = Instance.new("TextBox")
	input.BackgroundColor3 = C.Card
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Transmit on " .. tostring(snapshot.CurrentChannelId)
	input.PlaceholderColor3 = C.Muted
	input.Text = ""
	input.TextColor3 = C.Text
	input.TextSize = 12
	input.Position = UDim2.fromOffset(0, -1)
	input.Size = UDim2.new(1, -74, 0, 42)
	input.Parent = self.content
	corner(input, 10)
	local transmit = button(self.content, "SEND")
	transmit.BackgroundColor3 = C.Green
	transmit.Position = UDim2.new(1, -66, 0, -1)
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
	local function toggle(_, state)
		if state == Enum.UserInputState.Begin then
			self:_setOpen(not self.open)
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(ACTION, toggle, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ACTION, "RADIO")
	ContextActionService:SetDescription(ACTION, "Open or close your operational radio.")
	self.watchedTools = setmetatable({}, { __mode = "k" })
	local function watchTool(tool: Instance)
		if not tool:IsA("Tool") or tool.Name ~= "Radio" or self.watchedTools[tool] then
			return
		end
		self.watchedTools[tool] = true
		table.insert(self.connections, tool.Equipped:Connect(function()
			self:_setOpen(true)
		end))
		table.insert(self.connections, tool.Unequipped:Connect(function()
			self:_setOpen(false)
		end))
	end
	local backpack = Players.LocalPlayer:WaitForChild("Backpack")
	for _, item in backpack:GetChildren() do
		watchTool(item)
	end
	table.insert(self.connections, backpack.ChildAdded:Connect(watchTool))
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			for _, item in character:GetChildren() do
				watchTool(item)
			end
			table.insert(self.connections, character.ChildAdded:Connect(watchTool))
		end)
	)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSRadio"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 38
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(1, 0)
	-- Zenith's intended placement is a compact right-side panel beneath Roblox's
	-- top UI, not a bottom-hotbar overlay. CoreUISafeInsets protects the panel
	-- from the platform chrome; the additional offset leaves visual breathing
	-- room below the Roblox top bar.
	body.Position = UDim2.new(1, -18, 0, 72)
	body.Size = UDim2.fromOffset(350, 330)
	body.BackgroundColor3 = C.Body
	body.BorderSizePixel = 0
	body.Visible = false
	body.Parent = gui
	corner(body, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(75, 91, 108)
	stroke.Parent = body
	self.body = body
	local header = text(body, "RADIO", 18, true)
	header.Position = UDim2.fromOffset(18, 14)
	header.Size = UDim2.fromOffset(150, 26)
	local callsign = text(body, "Operational channel", 10)
	callsign.Position = UDim2.fromOffset(18, 39)
	callsign.Size = UDim2.new(1, -36, 0, 18)
	callsign.TextColor3 = C.Muted
	local close = button(body, "×")
	close.Position = UDim2.new(1, -45, 0, 12)
	close.Size = UDim2.fromOffset(30, 28)
	close.Activated:Connect(function()
		self:_setOpen(false)
	end)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(18, 68)
	content.Size = UDim2.new(1, -36, 1, -82)
	content.Parent = body
	self.content = content
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
	ContextActionService:UnbindAction(ACTION)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.body and self.body.Parent then
		self.body.Parent:Destroy()
	end
end

return RadioController
