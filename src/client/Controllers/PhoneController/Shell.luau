--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Utils = require(script.Parent.Utils)

local C = Utils.C
local DESIGN = Utils.DESIGN
local corner = Utils.corner
local label = Utils.label
local button = Utils.button
local input = Utils.input

return function(PhoneController)
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
		close.Size = UDim2.fromOffset(36, 36)
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

		-- Dock: four emergency/communication apps on the first row, with the taxi
		-- service deliberately placed beneath 999 so it cannot be mistaken for an
		-- emergency control on small screens.
		local dock = Instance.new("Frame")
		dock.AnchorPoint = Vector2.new(0.5, 1)
		dock.Position = UDim2.new(0.5, 0, 1, -26)
		dock.Size = UDim2.new(1, -28, 0, 136)
		dock.BackgroundColor3 = Color3.fromRGB(38, 46, 62)
		dock.BackgroundTransparency = 0.32
		dock.BorderSizePixel = 0
		dock.Parent = screen
		corner(dock, 22)
		self.dock = dock
		local apps = {
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
			{ Page = "Taxi", Glyph = "TAXI", Name = "Taxi", Colour = Color3.fromRGB(246, 190, 47) },
		}
		for index, app in apps do
			local tile = self:_appIcon(dock, app)
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			local row = if index <= 4 then 1 else 2
			local column = if index <= 4 then index else index - 4
			tile.Position = UDim2.fromScale((column - 0.5) / 4, if row == 1 then 0.31 else 0.72)
		end

		-- Home indicator. Tapping it returns to the home screen, which is the
		-- gesture equivalent available with a cursor.
		local indicator = button(screen, "")
		indicator.AnchorPoint = Vector2.new(0.5, 1)
		indicator.Position = UDim2.new(0.5, 0, 1, -2)
		-- The visible bar is the 5px pill drawn inside; the button around it is what
		-- a finger actually has to hit. At 124x5 the target was the bar itself, which
		-- is smaller than any real fingertip.
		indicator.Size = UDim2.fromOffset(148, 26)
		indicator.BackgroundTransparency = 1
		local indicatorBar = Instance.new("Frame")
		indicatorBar.AnchorPoint = Vector2.new(0.5, 0.5)
		indicatorBar.Position = UDim2.fromScale(0.5, 0.5)
		indicatorBar.Size = UDim2.fromOffset(124, 5)
		indicatorBar.BackgroundColor3 = Color3.fromRGB(226, 232, 242)
		indicatorBar.BackgroundTransparency = 0.25
		indicatorBar.BorderSizePixel = 0
		indicatorBar.Parent = indicator
		corner(indicatorBar, 3)
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
				body.Size =
					UDim2.fromOffset(286, math.min(520, math.max(280, layout.SafeViewport.Y - 90)))
			else
				body.AnchorPoint = Vector2.new(1, 1)
				body.Position = UDim2.new(1, -(layout.RightReserve + 18), 1, -76)
				-- Held at the design size and scaled via UIScale, the same as the
				-- Compact branch above, rather than resized directly: every icon,
				-- label and the dock inside are authored in fixed pixels against
				-- that 326x610 canvas, so shrinking body.Size instead stretched
				-- the frame's own bounds while those children stayed put. UIScale
				-- scales around the frame's AnchorPoint, so the bottom-right
				-- anchor above still holds as it shrinks.
				--
				-- Scale with the screen rather than sitting at a fixed size: a handset
				-- that reads well on a laptop is overbearing on a large monitor. The
				-- 76 pixel bottom anchor plus a top margin are left free.
				local height = math.clamp(layout.SafeViewport.Y * 0.54, 400, 610)
				height = math.min(height, layout.SafeViewport.Y - 94)
				body.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
				self.bodyScale.Scale = height / DESIGN.Y
			end
			launcher.AnchorPoint = if layout.Vehicle then Vector2.new(0, 1) else Vector2.new(1, 1)
			launcher.Position = if layout.Vehicle
				then UDim2.new(0, 18, 1, -layout.HotbarBottom)
				else UDim2.new(1, -18, 1, -layout.HotbarBottom)
		end)
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

	-- A rounded-square app tile with its label beneath, as on a home screen.
	-- Returns the tile so the caller decides where it sits.
	function PhoneController:_appIcon(parent: Instance, app: any): Frame
		local tile = Instance.new("Frame")
		tile.BackgroundTransparency = 1
		-- Keep the touch target stable while reserving one clear, single line for
		-- the app name. iPhone labels do not wrap into a second line inside the
		-- icon grid; they scale down slightly and truncate only as a last resort.
		tile.Size = UDim2.fromOffset(60, 76)
		tile.Parent = parent

		local glyph = Instance.new("TextButton")
		glyph.AutoButtonColor = false
		glyph.BackgroundColor3 = app.Colour
		glyph.BorderSizePixel = 0
		glyph.Font = Enum.Font.GothamBold
		glyph.Text = app.Glyph
		glyph.TextColor3 = Color3.fromRGB(255, 255, 255)
		glyph.TextSize = if #app.Glyph > 2 then 12 else 24
		glyph.Size = UDim2.fromOffset(50, 50)
		glyph.Position = UDim2.fromOffset(2, 0)
		glyph.TextWrapped = false
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextYAlignment = Enum.TextYAlignment.Center
		glyph.Parent = tile
		-- Roblox has no squircle, so a generous radius is the closest match.
		corner(glyph, 14)
		local glyphScale = Instance.new("UIScale")
		glyphScale.Parent = glyph
		glyph.MouseButton1Down:Connect(function()
			TweenService:Create(
				glyphScale,
				TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{
					Scale = 0.96,
				}
			):Play()
		end)
		glyph.MouseButton1Up:Connect(function()
			TweenService:Create(
				glyphScale,
				TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{
					Scale = 1,
				}
			):Play()
		end)
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
		name.Position = UDim2.fromOffset(-3, 52)
		name.Size = UDim2.new(1, 6, 0, 16)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.TextWrapped = false
		name.TextScaled = true
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local nameConstraint = Instance.new("UITextSizeConstraint")
		nameConstraint.MinTextSize = 7
		nameConstraint.MaxTextSize = 9
		nameConstraint.Parent = name
		return tile
	end

	-- Home screen: a four-column grid of apps.

	-- Home screen: a four-column grid of apps.
	function PhoneController:_renderHome()
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.fromScale(1, 1)
		grid.Parent = self.content
		local layout = Instance.new("UIGridLayout")
		-- Percentage cells keep four apps inside the available content width even
		-- when the handset is docked beside a vehicle HUD or rendered on a small
		-- phone. The offset leaves a small, consistent gutter between touch targets.
		layout.CellSize = UDim2.new(0.25, -10, 0, 76)
		layout.CellPadding = UDim2.fromOffset(6, 10)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for order, app in
			{
				{
					Page = "Call",
					Glyph = "☎",
					Name = "Phone",
					Colour = Color3.fromRGB(52, 199, 89),
				},
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
			list.ScrollBarThickness = 6
			list.Parent = self.content
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 8)
			layout.Parent = list
			for _, contact in contacts do
				local row = button(list, contact.Name .. "\n" .. contact.Number)
				row.Size = UDim2.new(1, -4, 0, 60)
				row.TextYAlignment = Enum.TextYAlignment.Center
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
				local empty =
					label(list, "No other active characters are online in this server.", 12)
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
			history.ScrollBarThickness = 6
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
				row.Size = UDim2.new(1, -4, 0, 66)
				row.Parent = history
				corner(row, 10)
				local body = label(row, record.Body, 10)
				body.Position = UDim2.fromOffset(10, 6)
				body.Size = UDim2.new(1, -20, 0, 38)
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.TextWrapped = true
				local peer = if record.Direction == "Outgoing"
					then record.ToNumber
					else record.FromNumber
				local meta = label(row, record.Direction .. "  ·  " .. peer, 8)
				meta.Position = UDim2.fromOffset(10, 48)
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

	-- Mirrors the lock-screen clock. Uses the player's local time, since the
	-- handset belongs to the character rather than to the server.
	function PhoneController:_updateClock()
		if self.statusTime then
			self.statusTime.Text = os.date("%H:%M")
		end
	end
end
