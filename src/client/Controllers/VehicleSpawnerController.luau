--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tokens = require(script.Parent.Parent.UI.DesignTokens)
local C, R, T, S = Tokens.Colour, Tokens.Radius, Tokens.Text, Tokens.Stroke

-- Thousands separated, because a price is read at a glance and 28000 and 280000
-- are the same shape until the digits are counted.
local function formatMoney(amount: number): string
	local grouped = tostring(math.floor(math.max(amount, 0)))
	while true do
		local replaced
		grouped, replaced = string.gsub(grouped, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return grouped
end

-- The swatch colour for a name in a vehicle's Colours list. An unrecognised name
-- shows as the panel's own grey rather than as black, which would read as a
-- deliberate choice of paint.
local PAINT = {
	Black = Color3.fromRGB(24, 26, 30),
	White = Color3.fromRGB(233, 236, 241),
	Silver = Color3.fromRGB(176, 182, 190),
	Grey = Color3.fromRGB(116, 122, 130),
	Red = Color3.fromRGB(178, 38, 42),
	Blue = Color3.fromRGB(38, 82, 178),
	Yellow = Color3.fromRGB(226, 190, 62),
	Police = Color3.fromRGB(240, 244, 250),
}
local function paintFor(colour: string): Color3
	return PAINT[colour] or Color3.fromRGB(96, 104, 116)
end

local VehicleSpawnerController = { connections = {}, promptConnections = {} }

function VehicleSpawnerController:Init(context: any)
	self.context = context
end

function VehicleSpawnerController:_close()
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

function VehicleSpawnerController:_customPlate(
	spawnerId: string,
	vehicleId: string,
	current: string,
	onSaved: (string) -> ()
)
	if not self.gui then
		return
	end
	local dialog = Instance.new("Frame")
	dialog.Name = "CustomRegistration"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.fromOffset(360, 220)
	dialog.BackgroundColor3 = Color3.fromRGB(13, 23, 36)
	dialog.BorderSizePixel = 0
	dialog.ZIndex = 20
	dialog.Parent = self.gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(290, 210)
	constraint.MaxSize = Vector2.new(360, 220)
	constraint.Parent = dialog
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, R.panel)
	corner.Parent = dialog
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.border
	stroke.Transparency = S.transparency
	stroke.Thickness = S.thickness
	stroke.Parent = dialog
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.Text = "CUSTOM REGISTRATION"
	title.TextColor3 = C.text
	title.TextSize = T.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 21
	title.Parent = dialog
	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(20, 61)
	input.Size = UDim2.new(1, -40, 0, 54)
	input.BackgroundColor3 = C.raised
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Tokens.Font.bold
	input.PlaceholderText = "AB12 CDE"
	input.Text = current
	input.TextColor3 = C.text
	input.PlaceholderColor3 = C.muted
	input.TextSize = 18
	input.TextYAlignment = Enum.TextYAlignment.Center
	input.ZIndex = 21
	input.Parent = dialog
	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, R.control)
	inputCorner.Parent = input
	local cancel = Instance.new("TextButton")
	cancel.Position = UDim2.new(0, 20, 1, -64)
	cancel.Size = UDim2.new(0.5, -25, 0, 44)
	cancel.BackgroundColor3 = C.raised
	cancel.BorderSizePixel = 0
	cancel.Font = Tokens.Font.bold
	cancel.Text = "CANCEL"
	cancel.TextColor3 = C.text
	cancel.TextSize = T.button
	cancel.ZIndex = 21
	cancel.Parent = dialog
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, R.control)
	cancelCorner.Parent = cancel
	local save = cancel:Clone()
	save.Position = UDim2.new(0.5, 5, 1, -64)
	save.BackgroundColor3 = C.accentFill
	save.Text = "SAVE"
	save.Parent = dialog
	cancel.Activated:Connect(function()
		dialog:Destroy()
	end)
	save.Activated:Connect(function()
		save.Active = false
		save.Text = "CHECKING…"
		local response = self.context.Controllers.NetworkController:Request(
			"SetCustomVehicleRegistration",
			{ SpawnerId = spawnerId, VehicleId = vehicleId, Registration = input.Text }
		)
		self.context.Controllers.NotificationController:Show(response.Message, "Vehicles")
		if response.Success then
			local registration = tostring(response.Data.Registration)
			onSaved(registration)
			dialog:Destroy()
		else
			save.Active = true
			save.Text = "SAVE"
		end
	end)
	input:CaptureFocus()
end

-- One forecourt card. Split out of the panel so a filter can rebuild the grid
-- without rebuilding the screen around it.
function VehicleSpawnerController:_card(
	list: Instance,
	definition: any,
	spawnerId: string,
	previews: Instance?,
	order: number
)
	local owned = definition.Owned == true and definition.VehicleId ~= nil
	local forSale = definition.ForSale == true
	local card = Instance.new("Frame")
	card.Name = tostring(definition.Id)
	card.LayoutOrder = order
	card.BackgroundColor3 = C.raised
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = list

	-- The car itself, rendered live from the showroom copy the server
	-- publishes. No artwork to upload and it cannot fall out of step with the
	-- model, which a screenshot would.
	local stage = Instance.new("ViewportFrame")
	stage.Size = UDim2.fromScale(1, 0.5)
	stage.BackgroundColor3 = C.surface
	stage.BorderSizePixel = 0
	stage.Ambient = Color3.fromRGB(180, 190, 205)
	stage.LightColor = Color3.fromRGB(255, 255, 255)
	stage.Parent = card
	local model = previews and previews:FindFirstChild(tostring(definition.Id))
	if model then
		local shown = model:Clone()
		shown.Parent = stage
		local camera = Instance.new("Camera")
		camera.Parent = stage
		stage.CurrentCamera = camera
		local centre, size = shown:GetBoundingBox()
		-- Framed off the diagonal rather than the longest edge. A factor of one
		-- and a half put a car in the middle distance and made every card look
		-- like a thumbnail of a thumbnail.
		local distance = math.sqrt(size.X * size.X + size.Z * size.Z) * 0.62
		-- Viewed from the front, which is decided by the vehicle rather than by
		-- the world axes: these models are imported and do not agree on which way
		-- is forwards, so a fixed corner showed some of them nose on and the rest
		-- reversing towards the camera. The drive seat faces the way the car
		-- does, and survives the stripping because it is a part rather than a
		-- script.
		local seat = shown:FindFirstChildWhichIsA("VehicleSeat", true)
		local forward = if seat then seat.CFrame.LookVector else Vector3.new(0, 0, -1)
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude < 0.05 then
			forward = Vector3.new(0, 0, -1)
		end
		forward = forward.Unit
		local side = Vector3.new(-forward.Z, 0, forward.X)
		camera.CFrame = CFrame.lookAt(
			centre.Position
				+ forward * distance
				+ side * (distance * 0.72)
				+ Vector3.new(0, distance * 0.34, 0),
			centre.Position - Vector3.new(0, size.Y * 0.08, 0)
		)
	else
		local absent = Instance.new("TextLabel")
		absent.BackgroundTransparency = 1
		absent.Size = UDim2.fromScale(1, 1)
		absent.Font = Tokens.Font.bold
		absent.Text = string.upper(string.sub(tostring(definition.Name), 1, 2))
		absent.TextColor3 = C.muted
		absent.TextSize = 34
		absent.Parent = stage
	end

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 14, 0.5, 8)
	name.Size = UDim2.new(1, -28, 0, 22)
	name.Font = Tokens.Font.bold
	name.Text = tostring(definition.Name)
	name.TextColor3 = C.text
	name.TextSize = T.subtitle
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = card

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.new(0, 14, 0.5, 30)
	detail.Size = UDim2.new(1, -28, 0, 20)
	detail.Font = Tokens.Font.regular
	detail.TextColor3 = C.muted
	detail.TextSize = T.dense
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	if owned then
		-- What somebody deciding which of their own cars to take actually
		-- wants: which one it is, and whether it is roadworthy.
		local parts = { "REG " .. tostring(definition.Registration or "--") }
		if type(definition.Fuel) == "number" then
			table.insert(parts, string.format("FUEL %d%%", math.floor(definition.Fuel)))
		end
		if type(definition.Condition) == "number" then
			table.insert(parts, string.format("COND %d%%", math.floor(definition.Condition)))
		end
		if definition.Insured ~= nil then
			table.insert(parts, if definition.Insured then "INSURED" else "UNINSURED")
		end
		detail.Text = table.concat(parts, "  •  ")
	elseif forSale then
		detail.Text = "£" .. formatMoney(definition.Price or 0)
		detail.TextColor3 = C.text
		detail.Font = Tokens.Font.bold
		detail.TextSize = T.subtitle
	end
	detail.Parent = card

	-- Colour is chosen before buying, because the record keeps it and there
	-- is no respray anywhere in the game to change it afterwards.
	local chosenColour = (definition.Colours and definition.Colours[1]) or "Default"
	local swatchButtons = {}
	if forSale and not owned and type(definition.Colours) == "table" then
		for index, colour in definition.Colours do
			local swatch = Instance.new("TextButton")
			swatch.Name = "Colour_" .. colour
			swatch.Position = UDim2.new(0, 14 + (index - 1) * 26, 0.5, 54)
			swatch.Size = UDim2.fromOffset(22, 22)
			swatch.BackgroundColor3 = paintFor(colour)
			swatch.BorderSizePixel = 0
			swatch.Text = ""
			swatch.AutoButtonColor = false
			swatch.Parent = card
			local edge = Instance.new("UIStroke")
			edge.Color = if colour == chosenColour then C.accent else C.border
			edge.Thickness = if colour == chosenColour then 2 else 1
			edge.Parent = swatch
			swatchButtons[colour] = edge
			swatch.Activated:Connect(function()
				chosenColour = colour
				for other, edging in swatchButtons do
					edging.Color = if other == colour then C.accent else C.border
					edging.Thickness = if other == colour then 2 else 1
				end
			end)
		end
	end

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -10)
	button.Size = UDim2.new(1, -28, 0, 34)
	button.BackgroundColor3 = if definition.Locked then C.raised else C.accentFill
	button.BorderSizePixel = 0
	button.Font = Tokens.Font.bold
	button.TextColor3 = if definition.Locked then C.muted else C.text
	button.TextSize = T.button
	button.Text = if definition.Locked then "REQUIREMENTS" elseif owned then "SPAWN" else "BUY"
	button.Parent = card

	button.Activated:Connect(function()
		if definition.Locked then
			self.context.Controllers.NotificationController:Show(
				"This vehicle needs its game pass.",
				"Vehicles"
			)
			return
		end
		button.Active = false
		if owned then
			button.Text = "SPAWNING…"
			local spawned = self.context.Controllers.NetworkController:Request("SpawnVehicle", {
				SpawnerId = spawnerId,
				DefinitionId = definition.Id,
				VehicleId = definition.VehicleId,
			})
			if spawned.Success then
				self:_close()
				return
			end
			self.context.Controllers.NotificationController:Show(spawned.Message, "Vehicles")
			button.Active = true
			button.Text = "SPAWN"
			return
		end
		button.Text = "BUYING…"
		local bought = self.context.Controllers.NetworkController:Request("PurchaseVehicle", {
			DefinitionId = definition.Id,
			Colour = chosenColour,
		})
		self.context.Controllers.NotificationController:Show(bought.Message, "Vehicles")
		button.Active = true
		if bought.Success then
			-- Reopened rather than patched in place, so the new car appears in
			-- the owned half with its issued registration exactly as the server
			-- recorded it.
			self:_open(spawnerId)
		else
			button.Text = "BUY"
		end
	end)

	if owned then
		local plateButton = Instance.new("TextButton")
		plateButton.Name = "CustomPlate"
		plateButton.AnchorPoint = Vector2.new(1, 0)
		plateButton.Position = UDim2.new(1, -14, 0.5, 6)
		plateButton.Size = UDim2.fromOffset(66, 26)
		plateButton.BackgroundColor3 = C.surface
		plateButton.BorderSizePixel = 0
		plateButton.Font = Tokens.Font.bold
		plateButton.Text = "PLATE"
		plateButton.TextColor3 = C.muted
		plateButton.TextSize = T.button
		plateButton.Parent = card
		plateButton.Activated:Connect(function()
			self:_customPlate(
				spawnerId,
				definition.VehicleId,
				tostring(definition.Registration or ""),
				function(registration)
					definition.Registration = registration
					self:_open(spawnerId)
				end
			)
		end)
	end
end

-- Which entries a filter admits. Kept beside the tabs it drives so a new tab
-- cannot be added without saying what it means.
local FILTERS = {
	{ Id = "All", Label = "ALL" },
	{ Id = "ForSale", Label = "FOR SALE" },
	{ Id = "Owned", Label = "MY VEHICLES" },
}

local function passesFilter(definition: any, filter: string): boolean
	if filter == "ForSale" then
		return definition.ForSale == true
	elseif filter == "Owned" then
		return definition.Owned == true and definition.VehicleId ~= nil
	end
	return true
end

function VehicleSpawnerController:_open(spawnerId: string)
	local response = self.context.Controllers.NetworkController:Request("GetVehicleSpawnerMenu", {
		SpawnerId = spawnerId,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Vehicles")
		return
	end
	self:_close()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSVehicleSpawner"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 35
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	-- Full screen, and square, so this reads as the same product as the team
	-- board rather than as a dialog that happens to list cars. A forecourt is
	-- browsed rather than acknowledged, and the old 920 pixel box fitted three
	-- cards with the rest below the fold.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = C.canvas
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 96)
	header.BackgroundColor3 = C.surface
	header.BorderSizePixel = 0
	header.Parent = panel
	local accent = Instance.new("Frame")
	accent.Position = UDim2.new(0, 0, 1, -2)
	accent.Size = UDim2.new(1, 0, 0, 2)
	accent.BackgroundColor3 = C.accent
	accent.BorderSizePixel = 0
	accent.Parent = header

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(28, 18)
	title.Size = UDim2.new(1, -120, 0, 32)
	title.Font = Tokens.Font.bold
	title.Text = tostring(response.Data.Name or "Vehicles")
	title.TextColor3 = C.text
	title.TextSize = T.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(28, 50)
	subtitle.Size = UDim2.new(1, -120, 0, 22)
	subtitle.Font = Tokens.Font.regular
	subtitle.Text = "Buy a vehicle, or take one of yours out"
	subtitle.TextColor3 = C.muted
	subtitle.TextSize = T.body
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = header

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -24, 0, 24)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = C.raised
	close.BorderSizePixel = 0
	close.Font = Tokens.Font.bold
	close.Text = "×"
	close.TextColor3 = C.text
	close.TextSize = T.title
	close.Parent = header
	close.Activated:Connect(function()
		self:_close()
	end)

	-- Filters, because a forecourt that stocks everything and also holds your own
	-- cars is two lists in one and the answer to "where is mine" should not be
	-- scrolling.
	local filterRow = Instance.new("Frame")
	filterRow.Position = UDim2.fromOffset(28, 104)
	filterRow.Size = UDim2.new(1, -56, 0, 34)
	filterRow.BackgroundTransparency = 1
	filterRow.Parent = panel
	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.Padding = UDim.new(0, 8)
	filterLayout.Parent = filterRow

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(28, 150)
	list.Size = UDim2.new(1, -56, 1, -178)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = Tokens.Scroll.barThickness
	list.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(14, 14)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	local function resizeCells()
		local width = list.AbsoluteSize.X
		if width <= 0 then
			return
		end
		-- Whole pixels with the remainder left in the gutter. Fractional cells
		-- round up past the container and cost a whole column.
		local columns = if width >= 1500
			then 5
			elseif width >= 1180 then 4
			elseif width >= 860 then 3
			elseif width >= 560 then 2
			else 1
		local cell = math.floor((width - 14 * (columns - 1) - 8) / columns)
		grid.CellSize = UDim2.fromOffset(cell, math.floor(cell * 0.92))
	end
	resizeCells()
	table.insert(
		self.connections,
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeCells)
	)

	local vehicles = response.Data.Vehicles or {}
	local activeFilter = "All"
	local chips: { [string]: TextButton } = {}
	local renderCards

	local function paintChips()
		for id, chip in chips do
			local on = id == activeFilter
			chip.BackgroundColor3 = if on then C.accentFill else C.raised
			chip.TextColor3 = if on then C.text else C.muted
		end
	end

	for order, filter in FILTERS do
		local chip = Instance.new("TextButton")
		chip.Name = filter.Id
		chip.LayoutOrder = order
		chip.Size = UDim2.fromOffset(if filter.Id == "Owned" then 132 else 104, 34)
		chip.BackgroundColor3 = C.raised
		chip.BorderSizePixel = 0
		chip.Font = Tokens.Font.bold
		chip.Text = filter.Label
		chip.TextColor3 = C.muted
		chip.TextSize = T.button
		chip.Parent = filterRow
		chips[filter.Id] = chip
		chip.Activated:Connect(function()
			if activeFilter == filter.Id then
				return
			end
			activeFilter = filter.Id
			paintChips()
			renderCards()
			list.CanvasPosition = Vector2.zero
		end)
	end
	paintChips()

	renderCards = function()
		for _, child in list:GetChildren() do
			if not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end
		local previews = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
		local shown = 0
		for _, definition in vehicles do
			if not passesFilter(definition, activeFilter) then
				continue
			end
			shown += 1
			self:_card(list, definition, spawnerId, previews, shown)
		end
		if shown == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "Empty"
			empty.LayoutOrder = 1
			empty.BackgroundColor3 = C.raised
			empty.BorderSizePixel = 0
			empty.Font = Tokens.Font.regular
			empty.Text = if activeFilter == "Owned"
				then "You do not own a vehicle yet."
				else "Nothing is for sale here."
			empty.TextColor3 = C.muted
			empty.TextSize = T.body
			empty.TextWrapped = true
			empty.Parent = list
		end
	end
	renderCards()
end

local function spawnerFor(prompt: ProximityPrompt): Instance?
	local current = prompt.Parent
	while current and current ~= workspace do
		if type(current:GetAttribute("SpawnerId")) == "string" then
			return current
		end
		current = current.Parent
	end
	return nil
end

function VehicleSpawnerController:_bind(prompt: ProximityPrompt)
	if self.promptConnections[prompt] then
		return
	end
	local spawner = spawnerFor(prompt)
	if not spawner then
		return
	end
	local spawnerId = spawner:GetAttribute("SpawnerId")
	if type(spawnerId) ~= "string" or spawnerId == "" then
		return
	end
	self.promptConnections[prompt] = prompt.Triggered:Connect(function()
		-- On a client, this signal represents the local player's completed
		-- interaction. Do not depend on the optional player argument: its shape
		-- differs between client and server prompt signals, which previously made
		-- a visible E prompt complete without ever opening the interface.
		self:_open(spawnerId)
	end)
end

function VehicleSpawnerController:Start()
	local folder = workspace:WaitForChild("RoleplayOSVehicleFacilities", 20)
	if not folder then
		return
	end
	for _, instance in folder:GetDescendants() do
		if instance:IsA("ProximityPrompt") then
			self:_bind(instance)
		end
	end
	table.insert(
		self.connections,
		folder.DescendantAdded:Connect(function(instance)
			if instance:IsA("ProximityPrompt") then
				task.defer(function()
					self:_bind(instance)
				end)
			end
		end)
	)
end

function VehicleSpawnerController:Destroy()
	self:_close()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for prompt, connection in self.promptConnections do
		connection:Disconnect()
		self.promptConnections[prompt] = nil
	end
	table.clear(self.connections)
	table.clear(self.promptConnections)
end

return VehicleSpawnerController
