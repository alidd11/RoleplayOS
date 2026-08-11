--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local PhoneController = { connections = {}, activeCall = nil }
local PHONE_ACTION = "RoleplayOSTogglePhone"
-- The size the handset's screen contents are measured against. Other layouts
-- vary the body's height, but the compact one scales this shape to fit rather
-- than reshaping it.
local DESIGN = Vector2.new(326, 610)
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
	item.TextYAlignment = Enum.TextYAlignment.Center
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
	item.TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	item.Parent = parent
	corner(item, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = item
	return item
end

local function money(value: any): string
	local amount = math.floor(tonumber(value) or 0)
	local formatted = tostring(math.abs(amount))
	while true do
		local changed
		formatted, changed = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		if changed == 0 then
			break
		end
	end
	return (if amount < 0 then "-£" else "£") .. formatted
end

function PhoneController:Init(context: any)
	self.context = context
	self.page = "Home"
	self.watchedTools = setmetatable({}, { __mode = "k" })
end

-- Announces that a full device is on screen. The ambient heads-up display
-- occupies the same corner as the handset, so it stands down rather than
-- fighting it for space; layering alone would leave it visibly underneath.
function PhoneController:_announce(open: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("RoleplayOSPhoneOpen", open)
		playerGui:SetAttribute(
			"RoleplayOSDeviceOpen",
			open or playerGui:GetAttribute("RoleplayOSMDTOpen") == true
		)
	end
end

function PhoneController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSPhone"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 40
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	-- The handset is opened by activating the Phone tool in the toolbar, the way
	-- a real one is taken out of a pocket, so there is no on-screen launcher
	-- competing with the rest of the interface for the corner. The button is
	-- kept unparented purely so gamepad focus has somewhere to return to.
	local launcher = button(gui, "PHONE", C.Body)
	launcher.Size = UDim2.fromOffset(112, 38)
	launcher.Visible = false
	launcher.Parent = nil
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

	local body = Instance.new("Frame")
	body.Name = "Phone"
	body.AnchorPoint = Vector2.new(1, 1)
	body.Position = UDim2.new(1, -18, 1, -76)
	body.Size = UDim2.fromOffset(326, 610)
	body.BackgroundColor3 = C.Body
	body.BorderSizePixel = 0
	body.SelectionGroup = true
	body.Visible = false
	self:_announce(false)
	body.Parent = gui
	corner(body, 34)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(72, 82, 98)
	stroke.Thickness = 2
	stroke.Parent = body
	self.body = body
	local bodyScale = Instance.new("UIScale")
	bodyScale.Parent = body
	self.bodyScale = bodyScale

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
	-- Status bar: clock on the left of the island, indicators on the right, as
	-- on the device being imitated. The clock follows in-game UK time rather
	-- than a fixed marketing time.
	local time = label(screen, "09:41", 11, true)
	time.Position = UDim2.fromOffset(20, 11)
	time.Size = UDim2.fromOffset(58, 18)
	time.TextXAlignment = Enum.TextXAlignment.Center
	self.statusTime = time
	local indicators = label(screen, "▮▮▮  ᯤ  ▰", 10, true)
	indicators.AnchorPoint = Vector2.new(1, 0)
	indicators.Position = UDim2.new(1, -20, 0, 11)
	indicators.Size = UDim2.fromOffset(74, 18)
	indicators.TextXAlignment = Enum.TextXAlignment.Right
	local close = button(screen, "×")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 34)
	close.Size = UDim2.fromOffset(28, 24)
	close.BackgroundTransparency = 0.35
	self.close = close

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

	local function show(page: string)
		self.page = page
		self:_render()
	end
	self.show = show

	-- Dock: four pinned apps on a translucent rounded slab, sitting above the
	-- home indicator rather than filling the bottom edge.
	local dock = Instance.new("Frame")
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Position = UDim2.new(0.5, 0, 1, -26)
	dock.Size = UDim2.new(1, -28, 0, 74)
	dock.BackgroundColor3 = Color3.fromRGB(38, 46, 62)
	dock.BackgroundTransparency = 0.32
	dock.BorderSizePixel = 0
	dock.Parent = screen
	corner(dock, 22)
	self.dock = dock
	for index, app in
		{
			{ Page = "Call", Glyph = "☎", Name = "Phone", Colour = Color3.fromRGB(52, 199, 89) },
			{
				Page = "Messages",
				Glyph = "✉",
				Name = "Messages",
				Colour = Color3.fromRGB(48, 176, 199),
			},
			{
				Page = "Contacts",
				Glyph = "●",
				Name = "Contacts",
				Colour = Color3.fromRGB(120, 132, 158),
			},
			{ Page = "Emergency", Glyph = "999", Name = "SOS", Colour = C.Red },
			{ Page = "Taxi", Glyph = "🚕", Name = "Taxi", Colour = Color3.fromRGB(246, 190, 47) },
			{ Page = "Taxi", Glyph = "T", Name = "Taxi", Colour = Color3.fromRGB(246, 190, 47) },
		}
	do
		local tile = self:_appIcon(dock, app)
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromScale((index - 0.5) / 4, 0.5)
	end

	-- Home indicator. Tapping it returns to the home screen, which is the
	-- gesture equivalent available with a cursor.
	local indicator = button(screen, "")
	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Position = UDim2.new(0.5, 0, 1, -8)
	indicator.Size = UDim2.fromOffset(124, 5)
	indicator.BackgroundColor3 = Color3.fromRGB(226, 232, 242)
	indicator.BackgroundTransparency = 0.25
	corner(indicator, 3)
	indicator.Activated:Connect(function()
		show("Home")
	end)
	launcher.Activated:Connect(function()
		body.Visible = not body.Visible
		self:_announce(body.Visible)
		if body.Visible then
			self:Refresh()
		end
	end)
	close.Activated:Connect(function()
		body.Visible = false
		self:_announce(false)
	end)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Phone", function(layout)
		if layout.Compact then
			body.AnchorPoint = Vector2.new(0.5, 0.5)
			body.Position = UDim2.fromScale(0.5, 0.5)
			-- Scaled to fit rather than stretched to fill. The screen's contents
			-- are laid out against a fixed handset size, so stretching the body
			-- to the viewport would leave the dock, icons and status bar spread
			-- across a shape they were never measured for.
			body.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
			self.bodyScale.Scale =
				self.context.Controllers.UIOrchestrator:FitScale(layout, DESIGN, 24)
		elseif layout.Vehicle then
			self.bodyScale.Scale = 1
			body.AnchorPoint = Vector2.new(0, 0.5)
			body.Position = UDim2.new(0, 18, 0.5, 0)
			body.Size = UDim2.fromOffset(286, math.min(520, layout.SafeViewport.Y - 90))
		else
			self.bodyScale.Scale = 1
			body.AnchorPoint = Vector2.new(1, 1)
			body.Position = UDim2.new(1, -(layout.RightReserve + 18), 1, -76)
			-- Scale with the screen rather than sitting at a fixed size: a handset
			-- that reads well on a laptop is overbearing on a large monitor. The
			-- aspect ratio is held so it stays phone-shaped at any height, and the
			-- 76 pixel bottom anchor plus a top margin are left free.
			local height = math.clamp(layout.SafeViewport.Y * 0.54, 400, 610)
			height = math.min(height, layout.SafeViewport.Y - 94)
			body.Size = UDim2.fromOffset(math.floor(height * 0.535), math.floor(height))
		end
		launcher.AnchorPoint = if layout.Vehicle then Vector2.new(0, 1) else Vector2.new(1, 1)
		launcher.Position = if layout.Vehicle
			then UDim2.new(0, 18, 1, -layout.HotbarBottom)
			else UDim2.new(1, -18, 1, -layout.HotbarBottom)
	end)
end

function PhoneController:_renderTaxi()
	local taxi = self.phoneData and self.phoneData.Taxi
	local title = label(self.content, if taxi then "ACTIVE BOOKING" else "BOOK A TAXI", 13, true)
	title.Size = UDim2.new(1, 0, 0, 24)
	local hint = label(
		self.content,
		if taxi then taxi.Pickup .. "  →  " .. taxi.Dropoff else "Licensed local taxi service",
		9
	)
	hint.Position = UDim2.fromOffset(0, 28)
	hint.Size = UDim2.new(1, 0, 0, 30)
	hint.TextColor3 = C.Muted
	if taxi then
		local details = label(
			self.content,
			string.format(
				"%s  ·  £%d\n%s",
				taxi.State,
				taxi.Fare,
				taxi.DriverName or "Waiting for a driver"
			),
			11,
			true
		)
		details.Position = UDim2.fromOffset(0, 70)
		details.Size = UDim2.new(1, 0, 0, 52)
		local isDriver = taxi.IsDriver == true
		local canComplete = isDriver and taxi.State == "Accepted"
		local action = button(
			self.content,
			if canComplete
				then "COMPLETE RIDE"
				elseif taxi.State == "Completed" then "CLOSE"
				else "CANCEL BOOKING",
			if canComplete then C.Green elseif taxi.State == "Completed" then C.Card else C.Red
		)
		action.Position = UDim2.fromOffset(0, 132)
		action.Size = UDim2.new(1, 0, 0, 42)
		action.Activated:Connect(function()
			if canComplete then
				local response = self.context.Controllers.NetworkController:Request(
					"TaxiComplete",
					{ RequestId = taxi.RequestId }
				)
				self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
			elseif taxi.State ~= "Completed" then
				local response = self.context.Controllers.NetworkController:Request(
					"TaxiCancel",
					{ RequestId = taxi.RequestId }
				)
				self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
			end
			self:Refresh()
		end)
		return
	end
	local pickup = input(self.content, "Pickup point")
	pickup.Position = UDim2.fromOffset(0, 68)
	pickup.Size = UDim2.new(1, 0, 0, 42)
	local dropoff = input(self.content, "Drop-off point")
	dropoff.Position = UDim2.fromOffset(0, 118)
	dropoff.Size = UDim2.new(1, 0, 0, 42)
	local bandTitle = label(self.content, "FARE BAND", 8, true)
	bandTitle.Position = UDim2.fromOffset(0, 174)
	bandTitle.Size = UDim2.new(1, 0, 0, 16)
	bandTitle.TextColor3 = C.Muted
	local selected = "Local"
	local bands = {
		{ Id = "Local", Text = "LOCAL  ·  £8" },
		{ Id = "City", Text = "CITY  ·  £14" },
		{ Id = "Long", Text = "LONG  ·  £22" },
	}
	for index, band in bands do
		local choice = button(self.content, band.Text, if index == 1 then C.Blue else C.Card)
		choice.Position = UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 196)
		choice.Size = UDim2.new(1 / 3, -8, 0, 38)
		choice.Activated:Connect(function()
			selected = band.Id
			for _, child in self.content:GetChildren() do
				if child:IsA("TextButton") and child:GetAttribute("TaxiBand") == true then
					child.BackgroundColor3 = if child == choice then C.Blue else C.Card
				end
			end
		end)
		choice:SetAttribute("TaxiBand", true)
	end
	local request = button(self.content, "REQUEST TAXI", C.Green)
	request.Position = UDim2.fromOffset(0, 248)
	request.Size = UDim2.new(1, 0, 0, 44)
	request.Activated:Connect(function()
		if pickup.Text == "" or dropoff.Text == "" then
			self.context.Controllers.NotificationController:Show(
				"Enter both pickup and drop-off points.",
				"Taxi"
			)
			return
		end
		request.Active = false
		local response = self.context.Controllers.NetworkController:Request("TaxiRequest", {
			Pickup = pickup.Text,
			Dropoff = dropoff.Text,
			Band = selected,
		})
		self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
		request.Active = true
		if response.Success then
			self:Refresh()
		end
	end)
	if self.phoneData and self.phoneData.TaxiDriverRequest then
		local driverRequest = self.phoneData.TaxiDriverRequest
		local accept = button(self.content, "ACCEPT DRIVER REQUEST", C.Green)
		accept.Position = UDim2.fromOffset(0, 306)
		accept.Size = UDim2.new(1, 0, 0, 44)
		accept.Activated:Connect(function()
			local response = self.context.Controllers.NetworkController:Request(
				"TaxiAccept",
				{ RequestId = driverRequest.RequestId }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Taxi")
			if response.Success then
				self:Refresh()
			end
		end)
	end
end

function PhoneController:_toggleTorch()
	self.flashlightEnabled = not self.flashlightEnabled
	local response = self.context.Controllers.NetworkController:Request(
		"PhoneToggleFlashlight",
		{ Enabled = self.flashlightEnabled }
	)
	if not response.Success then
		-- The server refuses unless the handset is actually equipped, so the
		-- local state must follow the server rather than the button press.
		self.flashlightEnabled = false
	end
	self.context.Controllers.NotificationController:Show(response.Message, "Phone")
end

-- A rounded-square app tile with its label beneath, as on a home screen.
-- Returns the tile so the caller decides where it sits.
function PhoneController:_appIcon(parent: Instance, app: any): Frame
	local tile = Instance.new("Frame")
	tile.BackgroundTransparency = 1
	tile.Size = UDim2.fromOffset(54, 68)
	tile.Parent = parent

	local glyph = Instance.new("TextButton")
	glyph.AutoButtonColor = true
	glyph.BackgroundColor3 = app.Colour
	glyph.BorderSizePixel = 0
	glyph.Font = Enum.Font.GothamBold
	glyph.Text = app.Glyph
	glyph.TextColor3 = Color3.fromRGB(255, 255, 255)
	glyph.TextSize = if #app.Glyph > 2 then 15 else 24
	glyph.Size = UDim2.fromOffset(50, 50)
	glyph.Position = UDim2.fromOffset(2, 0)
	glyph.Parent = tile
	-- Roblox has no squircle, so a generous radius is the closest match.
	corner(glyph, 14)
	glyph.Activated:Connect(function()
		-- An app either opens a page or performs an action in place, as the
		-- torch does; it never does both.
		if app.Action then
			app.Action(glyph)
			return
		end
		self.show(app.Page)
	end)

	local name = label(tile, app.Name, 9)
	name.Position = UDim2.fromOffset(0, 52)
	name.Size = UDim2.new(1, 0, 0, 14)
	name.TextXAlignment = Enum.TextXAlignment.Center
	return tile
end

-- Home screen: a four-column grid of apps.
function PhoneController:_renderHome()
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1)
	grid.Parent = self.content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(54, 68)
	layout.CellPadding = UDim2.fromOffset(16, 14)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, app in
		{
			{ Page = "Call", Glyph = "☎", Name = "Phone", Colour = Color3.fromRGB(52, 199, 89) },
			{
				Page = "Messages",
				Glyph = "✉",
				Name = "Messages",
				Colour = Color3.fromRGB(48, 176, 199),
			},
			{
				Page = "Contacts",
				Glyph = "●",
				Name = "Contacts",
				Colour = Color3.fromRGB(120, 132, 158),
			},
			{
				Page = "Bank",
				Glyph = "£",
				Name = "Bank",
				Colour = Color3.fromRGB(24, 91, 181),
			},
			{
				Name = "Torch",
				Glyph = "✦",
				Colour = Color3.fromRGB(95, 98, 107),
				Action = function()
					self:_toggleTorch()
				end,
			},
			{ Page = "Emergency", Glyph = "999", Name = "SOS", Colour = C.Red },
		}
	do
		local tile = self:_appIcon(grid, app)
		tile.LayoutOrder = order
	end
end

function PhoneController:_renderBank()
	local bank = self.phoneData and self.phoneData.Bank
	if not bank then
		local empty = label(self.content, "Banking is temporarily unavailable.", 12)
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.TextColor3 = C.Muted
		return
	end
	local balanceCard = Instance.new("Frame")
	balanceCard.BackgroundColor3 = Color3.fromRGB(24, 65, 137)
	balanceCard.BorderSizePixel = 0
	balanceCard.Size = UDim2.new(1, 0, 0, 92)
	balanceCard.Parent = self.content
	corner(balanceCard, 16)
	local caption = label(balanceCard, "AVAILABLE BALANCE", 9, true)
	caption.Position = UDim2.fromOffset(14, 12)
	caption.Size = UDim2.new(1, -28, 0, 14)
	caption.TextColor3 = Color3.fromRGB(173, 204, 255)
	local balance = label(balanceCard, money(bank.Balance), 25, true)
	balance.Position = UDim2.fromOffset(14, 28)
	balance.Size = UDim2.new(1, -28, 0, 34)
	local cash = label(balanceCard, "Cash carried  " .. money(bank.Cash), 9)
	cash.Position = UDim2.fromOffset(14, 66)
	cash.Size = UDim2.new(1, -28, 0, 14)
	cash.TextColor3 = Color3.fromRGB(173, 204, 255)

	-- By username. A phone number is something a player has to be told before
	-- they can be paid and nothing in the game tells them one; a username is on
	-- the nameplate above the person they are standing next to.
	local recipient = input(self.content, "Recipient username")
	recipient.Position = UDim2.fromOffset(0, 104)
	recipient.Size = UDim2.new(0.61, -4, 0, 42)
	recipient.TextYAlignment = Enum.TextYAlignment.Center
	recipient.AutomaticSize = Enum.AutomaticSize.None
	local amount = input(self.content, "Amount")
	amount.Position = UDim2.new(0.61, 4, 0, 104)
	amount.Size = UDim2.new(0.39, -4, 0, 42)
	amount.TextYAlignment = Enum.TextYAlignment.Center
	amount.AutomaticSize = Enum.AutomaticSize.None
	local send = button(self.content, "SEND MONEY", C.Blue)
	send.Position = UDim2.fromOffset(0, 154)
	send.Size = UDim2.new(1, 0, 0, 40)
	send.Activated:Connect(function()
		if not send.Active then
			return
		end
		-- Parenthesised, and the stripping narrowed.
		--
		-- This was tonumber(string.gsub(...)). gsub returns the string AND the
		-- number of substitutions, and as the last argument of a call both are
		-- passed, so the count arrived as tonumber's base. Zero and one are both
		-- outside the legal two to thirty six, so every amount raised, clean or
		-- not, on the first line of the handler before anything else ran. The
		-- button did nothing, said nothing, and no transfer request has ever left
		-- this client.
		--
		-- The old pattern also deleted the decimal point rather than rejecting it,
		-- which would have turned ten pounds fifty into one thousand and fifty. It
		-- now removes only spacing, the pound sign and thousands commas, and
		-- anything left that is not a digit is refused by the check below.
		local cleaned = (string.gsub(amount.Text, "[%s£,]", ""))
		local numericAmount = if string.match(cleaned, "^%d+$") then tonumber(cleaned) else nil
		if not numericAmount or numericAmount <= 0 then
			self.context.Controllers.NotificationController:Show(
				"Enter a whole-pound amount greater than zero.",
				"Bank"
			)
			return
		end
		send.Active = false
		send.Text = "SENDING…"
		local response = self.context.Controllers.NetworkController:Request(
			"PhoneTransferFunds",
			{ Recipient = recipient.Text, Amount = numericAmount }
		)
		self.context.Controllers.NotificationController:Show(response.Message, "Bank")
		if response.Success then
			amount.Text = ""
			recipient.Text = ""
			self:Refresh()
			return
		end
		send.Active = true
		send.Text = "SEND MONEY"
	end)

	local activityTitle = label(self.content, "RECENT ACTIVITY", 9, true)
	activityTitle.Position = UDim2.fromOffset(2, 208)
	activityTitle.Size = UDim2.new(1, -4, 0, 16)
	activityTitle.TextColor3 = C.Muted
	local history = Instance.new("ScrollingFrame")
	history.BackgroundTransparency = 1
	history.BorderSizePixel = 0
	history.Position = UDim2.fromOffset(0, 230)
	history.Size = UDim2.new(1, 0, 1, -230)
	history.AutomaticCanvasSize = Enum.AutomaticSize.Y
	history.CanvasSize = UDim2.new()
	history.ScrollBarThickness = 2
	history.Parent = self.content
	local historyLayout = Instance.new("UIListLayout")
	historyLayout.Padding = UDim.new(0, 7)
	historyLayout.Parent = history
	local transactions = bank.Transactions or {}
	for _, transaction in transactions do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = C.Card
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -4, 0, 48)
		row.Parent = history
		corner(row, 10)
		local description = label(row, tostring(transaction.Description), 9, true)
		description.Position = UDim2.fromOffset(10, 6)
		description.Size = UDim2.new(1, -100, 0, 18)
		description.TextTruncate = Enum.TextTruncate.AtEnd
		local transactionAmount = label(
			row,
			(if transaction.Direction == "Credit" then "+" else "−") .. money(transaction.Amount),
			10,
			true
		)
		transactionAmount.AnchorPoint = Vector2.new(1, 0)
		transactionAmount.Position = UDim2.new(1, -10, 0, 7)
		transactionAmount.Size = UDim2.fromOffset(82, 18)
		transactionAmount.TextXAlignment = Enum.TextXAlignment.Right
		transactionAmount.TextColor3 = if transaction.Direction == "Credit" then C.Green else C.Text
		local timestamp =
			label(row, os.date("%d %b · %H:%M", tonumber(transaction.Timestamp) or os.time()), 8)
		timestamp.Position = UDim2.fromOffset(10, 27)
		timestamp.Size = UDim2.new(1, -20, 0, 14)
		timestamp.TextColor3 = C.Muted
	end
	if #transactions == 0 then
		local empty = label(history, "No transactions yet.", 10)
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.TextColor3 = C.Muted
	end
end

function PhoneController:_clear()
	for _, child in self.content:GetChildren() do
		child:Destroy()
	end
end

function PhoneController:_render()
	self:_clear()
	self.heading.Text = self.page
	-- The home screen is the app grid itself, so the heading and dock only make
	-- sense inside an app, exactly as on the device.
	local home = self.page == "Home"
	self.heading.Visible = not home
	self.number.Visible = not home
	self.dock.Visible = home
	self.content.Position = if home then UDim2.fromOffset(14, 48) else UDim2.fromOffset(14, 112)
	self.content.Size = if home then UDim2.new(1, -28, 1, -158) else UDim2.new(1, -28, 1, -134)
	if self.page == "Home" then
		self:_renderHome()
	elseif self.page == "Bank" then
		self:_renderBank()
	elseif self.page == "Contacts" then
		local contacts = if self.phoneData then self.phoneData.Contacts else {}
		local list = Instance.new("ScrollingFrame")
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Size = UDim2.fromScale(1, 1)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ScrollBarThickness = 2
		list.Parent = self.content
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.Parent = list
		for _, contact in contacts do
			local row = button(list, contact.Name .. "\n" .. contact.Number)
			row.Size = UDim2.new(1, -4, 0, 54)
			row.Activated:Connect(function()
				local response = self.context.Controllers.NetworkController:Request(
					"PhonePlaceCall",
					{ Number = contact.Number }
				)
				if response.Success then
					self.activeCall = response.Data
					self:_renderCall()
				end
			end)
		end
		if #contacts == 0 then
			local empty = label(list, "No other active characters are online in this server.", 12)
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.TextColor3 = C.Muted
		end
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
	elseif self.page == "Taxi" then
		self:_renderTaxi()
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

-- Mirrors the lock-screen clock. Uses the player's local time, since the
-- handset belongs to the character rather than to the server.
function PhoneController:_updateClock()
	if self.statusTime then
		self.statusTime.Text = os.date("%H:%M")
	end
end

function PhoneController:Refresh()
	self:_updateClock()
	local response = self.context.Controllers.NetworkController:Request("GetPhone", {})
	if response.Success then
		self.phoneData = response.Data
		local navigation = self.context.Controllers.MinimapController
		local taxi = response.Data.Taxi
		local driverRequest = response.Data.TaxiDriverRequest
		if taxi and taxi.IsDriver == true and taxi.PickupPosition then
			navigation:SetWaypoint(taxi.PickupPosition, "PICKUP")
		elseif driverRequest and driverRequest.PickupPosition then
			navigation:SetWaypoint(driverRequest.PickupPosition, "PICKUP")
		else
			navigation:ClearWaypoint()
		end
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
	local function updateShortcutLabel(lastInputType: Enum.UserInputType)
		if tostring(lastInputType):find("Gamepad") then
			local key = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonY)
			local image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonY)
			self.launcher.Text = if image == ""
				then "PHONE  ·  " .. (if key == "" then "Y" else key)
				else "PHONE"
			self.shortcutGlyph.Image = image
			self.shortcutGlyph.Visible = image ~= ""
		else
			self.launcher.Text = "PHONE  ·  P"
			self.shortcutGlyph.Visible = false
		end
	end
	local function togglePhone(
		_actionName: string,
		inputState: Enum.UserInputState,
		inputObject: InputObject
	): Enum.ContextActionResult
		if
			inputState == Enum.UserInputState.Begin
			and inputObject.KeyCode == Enum.KeyCode.ButtonB
		then
			if not self.body.Visible then
				return Enum.ContextActionResult.Pass
			end
			self.body.Visible = false
			self:_announce(false)
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		if
			inputState ~= Enum.UserInputState.Begin
			or self.hasCharacter ~= true
			or self.vehicleMode == true
			or UserInputService:GetFocusedTextBox() ~= nil
		then
			return Enum.ContextActionResult.Pass
		end
		self.body.Visible = not self.body.Visible
		self:_announce(self.body.Visible)
		if self.body.Visible then
			self:Refresh()
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = self.close
			end
		elseif
			GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.body)
		then
			GuiService.SelectedObject = nil
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(
		PHONE_ACTION,
		togglePhone,
		false,
		Enum.KeyCode.P,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(PHONE_ACTION, "PHONE")
	ContextActionService:SetDescription(PHONE_ACTION, "Open or close your phone.")
	updateShortcutLabel(UserInputService:GetLastInputType())
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(updateShortcutLabel)
	)
	local event = self.context.Controllers.NetworkController:ResolveEvent("PhoneChanged")
	local function watchTool(tool: Instance)
		if tool:IsA("Tool") and tool.Name == "Phone" and not self.watchedTools[tool] then
			self.watchedTools[tool] = true
			local function open()
				self.body.Visible = true
				self:_announce(true)
				self:Refresh()
			end
			-- Selecting the handset in the toolbar is what takes it out, so the
			-- screen comes up on Equipped. Activated alone was not enough: it only
			-- fires when an already equipped tool is clicked in the world, so
			-- picking the slot appeared to do nothing.
			table.insert(self.connections, tool.Equipped:Connect(open))
			table.insert(self.connections, tool.Activated:Connect(open))
			table.insert(
				self.connections,
				tool.Unequipped:Connect(function()
					-- Putting the handset away closes it, so the screen cannot be
					-- left open while the character is holding something else.
					self.body.Visible = false
					self:_announce(false)
				end)
			)
		end
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
	if event then
		table.insert(
			self.connections,
			event.OnClientEvent:Connect(function(update)
				if update.Kind == "TaxiRequest" or update.Kind == "TaxiStatus" then
					self.page = "Taxi"
					self.body.Visible = true
					self:_announce(true)
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						if update.Message then update.Message.Body else "Taxi update received.",
						"Taxi"
					)
				elseif update.Kind == "Text" then
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						"New message received.",
						"Messages"
					)
				elseif update.Kind == "BankTransfer" then
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						string.format("%s received from %s.", money(update.Amount), update.From),
						"Bank"
					)
				elseif update.Kind == "Call" then
					self.activeCall = if update.Call.State == "Ended" then nil else update.Call
					self.body.Visible = true
					self:_announce(true)
					if self.activeCall then
						self:_renderCall()
					else
						self:_render()
					end
				end
			end)
		)
	end
	table.insert(
		self.connections,
		self.context.Events.CharacterChanged.Event:Connect(function()
			self.hasCharacter = true
			self.launcher.Visible = false
			self:Refresh()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.VehicleModeChanged.Event:Connect(function(active)
			self.vehicleMode = active
			self.launcher.Visible = false
			if active then
				self.body.Visible = false
				self:_announce(false)
			end
		end)
	)
end

function PhoneController:Destroy()
	ContextActionService:UnbindAction(PHONE_ACTION)
	if self.unbindLayout then
		self.unbindLayout()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.gui then
		self.gui:Destroy()
	end
end

return PhoneController
