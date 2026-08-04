--!strict

-- The stall a vendor opens.
--
-- Opened by the server when a proximity prompt is triggered, so the panel only
-- ever appears where a vendor actually is. The catalogue is sent with the open
-- rather than requested afterwards, which keeps the stall to one round trip and
-- means the prices shown are the ones the server just resolved.

local Players = game:GetService("Players")

local DESIGN = Vector2.new(360, 420)

local C = {
	Panel = Color3.fromRGB(12, 16, 24),
	Raised = Color3.fromRGB(24, 32, 45),
	Accent = Color3.fromRGB(96, 178, 255),
	Text = Color3.fromRGB(238, 244, 250),
	Muted = Color3.fromRGB(142, 156, 176),
	Money = Color3.fromRGB(104, 205, 148),
	Pass = Color3.fromRGB(245, 196, 88),
}

local VendorController = { connections = {}, rows = {}, rowConnections = {} }

function VendorController:Init(context: any)
	self.context = context
end

local function label(parent: Instance, text: string, size: number, colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.Text = text
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
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
	panel.BackgroundColor3 = C.Panel
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = label(panel, "", 20, C.Text)
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -80, 0, 24)
	local subtitle = label(panel, "", 12, C.Muted)
	subtitle.Position = UDim2.fromOffset(20, 40)
	subtitle.Size = UDim2.new(1, -80, 0, 16)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = C.Raised
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.Text = "✕"
	close.TextColor3 = C.Text
	close.TextSize = 18
	close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Items"
	list.Position = UDim2.fromOffset(14, 70)
	list.Size = UDim2.new(1, -28, 1, -122)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local status = label(panel, "", 12, C.Muted)
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 20, 1, -18)
	status.Size = UDim2.new(1, -40, 0, 30)
	status.TextWrapped = true

	self.gui, self.panel, self.scale = gui, panel, scale
	self.title, self.subtitle, self.list, self.status = title, subtitle, list, status

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

-- One row per item. The button says what will happen, since "Buy" on something
-- already owned and "Buy" on something needing Robux are different actions and
-- a player should not have to press one to find out which it was.
function VendorController:_row(item: any, order: number)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 56)
	row.BackgroundColor3 = C.Raised
	row.BorderSizePixel = 0
	row.Parent = self.list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
	self.rows[#self.rows + 1] = row

	local name = label(row, tostring(item.Name), 15, C.Text)
	name.Font = Enum.Font.GothamBold
	name.Position = UDim2.fromOffset(14, 9)
	name.Size = UDim2.new(1, -150, 0, 18)

	local detail = if item.Owned == true
		then "Included with your pass"
		elseif item.Price then string.format("£%d", item.Price)
		else "Requires a pass"
	local price = label(row, detail, 12, if item.Owned == true then C.Pass else C.Money)
	price.Position = UDim2.fromOffset(14, 29)
	price.Size = UDim2.new(1, -150, 0, 16)

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -12, 0.5, 0)
	action.Size = UDim2.fromOffset(112, 40)
	action.BackgroundColor3 = if item.Owned == true then C.Pass else C.Accent
	action.BorderSizePixel = 0
	action.Font = Enum.Font.GothamBold
	action.Text = if item.Owned == true then "COLLECT" elseif item.Price then "BUY" else "GET PASS"
	action.TextColor3 = C.Panel
	action.TextSize = 13
	action.Parent = row
	Instance.new("UICorner", action).CornerRadius = UDim.new(0, 10)

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
		self.status.Text = response.Message or "That could not be bought."
		return
	end
	local data = response.Data
	-- The server answers a pass item the player does not own by naming the pass
	-- rather than refusing, and that is where the Roblox purchase prompt belongs:
	-- it is the only path in the game that opens one.
	if data and data.Kind == "Gamepass" and data.Owned == false then
		self.context.Controllers.GamepassController:Prompt(data.GamepassId)
		self.status.Text = "Complete the purchase, then collect it here."
		return
	end
	if data and data.Kind == "Food" then
		self.status.Text = "Eaten."
		return
	end
	self.status.Text = "Added to your backpack."
end

function VendorController:Open(snapshot: any)
	if not self.gui then
		return
	end
	self.vendorId = snapshot.VendorId
	self.title.Text = tostring(snapshot.Name or "Shop")
	self.subtitle.Text = tostring(snapshot.Subtitle or "")
	self.status.Text = ""
	self:_clear()
	for index, item in snapshot.Items or {} do
		self:_row(item, index)
	end
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
