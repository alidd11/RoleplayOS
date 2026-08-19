--!strict

-- The stall a vendor opens.
--
-- Opened by the server when a proximity prompt is triggered, so the panel only
-- ever appears where a vendor actually is. The catalogue is sent with the open
-- rather than requested afterwards, which keeps the stall to one round trip and
-- means the prices shown are the ones the server just resolved.

local Players = game:GetService("Players")

local DesignTokens = require(script.Parent.Parent.UI.DesignTokens)

local DESIGN = Vector2.new(360, 420)

local C = DesignTokens.Colour

local VendorController = { connections = {}, rows = {}, rowConnections = {} }

function VendorController:Init(context: any)
	self.context = context
end

local function label(parent: Instance, text: string, size: number, colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = DesignTokens.Font.regular
	item.Text = text
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

function VendorController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSVendor"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Stall"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	panel.BackgroundColor3 = C.surface
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, DesignTokens.Radius.shell)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.border
	stroke.Transparency = DesignTokens.Stroke.transparency
	stroke.Thickness = DesignTokens.Stroke.thickness
	stroke.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = label(panel, "", DesignTokens.Text.title, C.text)
	title.Font = DesignTokens.Font.bold
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -80, 0, 24)
	local subtitle = label(panel, "", DesignTokens.Text.dense, C.muted)
	subtitle.Position = UDim2.fromOffset(20, 40)
	subtitle.Size = UDim2.new(1, -80, 0, 16)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = C.raised
	close.BorderSizePixel = 0
	close.Font = DesignTokens.Font.bold
	close.Text = "×"
	close.TextColor3 = C.text
	close.TextSize = 18
	close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, DesignTokens.Radius.control)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Items"
	list.Position = UDim2.fromOffset(14, 70)
	list.Size = UDim2.new(1, -28, 1, -122)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = DesignTokens.Scroll.barThickness
	list.ScrollBarImageTransparency = DesignTokens.Scroll.barTransparency
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, DesignTokens.Spacing.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- An empty stall (every item hidden as EmergencyRestricted, or a definition
	-- with no items) used to render as a bare panel with nothing in it and no
	-- explanation, which reads as broken rather than as "nothing here for you".
	local empty =
		label(list, "Nothing on offer for you right now.", DesignTokens.Text.body, C.muted)
	empty.LayoutOrder = -1
	empty.Size = UDim2.new(1, 0, 0, 40)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextWrapped = true
	empty.Visible = false

	local status = label(panel, "", DesignTokens.Text.dense, C.muted)
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 20, 1, -18)
	status.Size = UDim2.new(1, -40, 0, 30)
	status.TextWrapped = true

	self.gui, self.panel, self.scale = gui, panel, scale
	self.title, self.subtitle, self.list, self.status, self.empty =
		title, subtitle, list, status, empty

	table.insert(
		self.connections,
		close.Activated:Connect(function()
			self:Close()
		end)
	)
end

function VendorController:_clear()
	for _, connection in self.rowConnections do
		connection:Disconnect()
	end
	table.clear(self.rowConnections)
	for _, row in self.rows do
		row:Destroy()
	end
	table.clear(self.rows)
end

-- What a row's state actually means, kept in one place so the detail text, its
-- colour and the button beneath it can never drift apart from each other.
--
-- Owned/free reads as a small win (success), a price is neutral information
-- rather than a state (text), and "you need the pass first" is the one row
-- asking the player to go and do something else before it will work (warning)
-- - the same traffic-light vocabulary DesignTokens already defines, applied to
-- a stall row instead of a status light.
local function rowState(item: any): (string, Color3, Color3, string)
	if item.Owned == true then
		return "Included with your pass", C.success, C.success, "COLLECT"
	elseif item.Price then
		return string.format("£%d", item.Price), C.text, C.accent, "BUY"
	end
	return "Requires a pass", C.warning, C.warning, "GET PASS"
end

-- One row per item. The button says what will happen, since "Buy" on something
-- already owned and "Buy" on something needing Robux are different actions and
-- a player should not have to press one to find out which it was.
function VendorController:_row(item: any, order: number)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 56)
	row.BackgroundColor3 = C.raised
	row.BorderSizePixel = 0
	row.Parent = self.list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, DesignTokens.Radius.card)
	self.rows[#self.rows + 1] = row

	local name = label(row, tostring(item.Name), DesignTokens.Text.subtitle, C.text)
	name.Font = DesignTokens.Font.bold
	name.Position = UDim2.fromOffset(14, 9)
	name.Size = UDim2.new(1, -160, 0, 18)
	-- The 160 reserved on the right is the action button. Item names come from
	-- configuration and a long one ran straight under it.
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local detailText, detailColour, buttonColour, buttonText = rowState(item)
	local price = label(row, detailText, DesignTokens.Text.dense, detailColour)
	price.Position = UDim2.fromOffset(14, 29)
	price.Size = UDim2.new(1, -160, 0, 16)

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -12, 0.5, 0)
	action.Size = UDim2.fromOffset(122, 40)
	action.BackgroundColor3 = buttonColour
	action.BorderSizePixel = 0
	action.Font = DesignTokens.Font.bold
	action.Text = buttonText
	action.TextColor3 = C.canvas
	action.TextSize = DesignTokens.Text.button
	action.Parent = row
	Instance.new("UICorner", action).CornerRadius = UDim.new(0, DesignTokens.Radius.control)

	-- Kept with the row rather than in the controller's list. A stall reopened a
	-- hundred times would otherwise leave a hundred dead connections per item
	-- behind, since the rows are destroyed and the connections were not.
	table.insert(
		self.rowConnections,
		action.Activated:Connect(function()
			self:_purchase(item, action)
		end)
	)
end

function VendorController:_setStatus(text: string, tone: string?)
	self.status.Text = text
	self.status.TextColor3 = if tone == "Success"
		then C.success
		elseif tone == "Error" then C.danger
		else C.muted
end

function VendorController:_purchase(item: any, button: TextButton)
	local original = button.Text
	button.Active = false
	button.Text = "…"
	local response = self.context.Controllers.NetworkController:Request("PurchaseFromVendor", {
		VendorId = self.vendorId,
		ItemId = item.Id,
	})
	button.Active = true
	button.Text = original
	if not response.Success then
		self:_setStatus(response.Message or "That could not be bought.", "Error")
		return
	end
	local data = response.Data
	-- The server answers a pass item the player does not own by naming the pass
	-- rather than refusing, and that is where the Roblox purchase prompt belongs:
	-- it is the only path in the game that opens one.
	if data and data.Kind == "Gamepass" and data.Owned == false then
		self.context.Controllers.GamepassController:Prompt(data.GamepassId)
		self:_setStatus("Complete the purchase, then collect it here.", nil)
		return
	end
	if data and data.Kind == "Food" then
		self:_setStatus("Eaten.", "Success")
		return
	end
	self:_setStatus("Added to your backpack.", "Success")
end

function VendorController:Open(snapshot: any)
	if not self.gui then
		return
	end
	self.vendorId = snapshot.VendorId
	self.title.Text = tostring(snapshot.Name or "Shop")
	self.subtitle.Text = tostring(snapshot.Subtitle or "")
	self:_setStatus("", nil)
	self:_clear()
	local items = snapshot.Items or {}
	for index, item in items do
		self:_row(item, index)
	end
	self.empty.Visible = #items == 0
	self.gui.Enabled = true
end

function VendorController:Close()
	if self.gui then
		self.gui.Enabled = false
	end
	self:_clear()
end

function VendorController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Vendor", function(layout)
		self.scale.Scale = self.context.Controllers.UIOrchestrator:FitScale(layout, DESIGN, 40)
	end)
	local opened = self.context.Controllers.NetworkController:ResolveEvent("VendorOpened")
	if opened then
		table.insert(
			self.connections,
			opened.OnClientEvent:Connect(function(snapshot)
				if type(snapshot) == "table" then
					self:Open(snapshot)
				end
			end)
		)
	end
end

function VendorController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return VendorController
