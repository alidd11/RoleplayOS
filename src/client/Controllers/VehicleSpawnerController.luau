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

-- Frames a preview model in a viewport, from the vehicle's own front three
-- quarter. Shared by the grid card and the detail view so they cannot disagree
-- about which way a car is pointing.
local function frameVehicle(stage: ViewportFrame, model: Instance, closeness: number)
	local shown = model:Clone()
	shown.Parent = stage
	local camera = Instance.new("Camera")
	camera.Parent = stage
	stage.CurrentCamera = camera
	local centre, size = shown:GetBoundingBox()
	local distance = math.sqrt(size.X * size.X + size.Z * size.Z) * closeness
	-- These models are imported and do not agree on which way is forwards, so a
	-- fixed corner showed some nose on and the rest reversing towards the camera.
	-- The drive seat faces the way the car does, and survives the stripping
	-- because it is a part rather than a script.
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
	return shown
end

-- The vehicle itself, opened by clicking its card.
--
-- Colour moved here from the grid. On a card it was three squares under a price
-- competing with the buy button; here it is the decision the screen is about,
-- which matters because the choice is permanent - the record keeps it and
-- nothing in the game resprays - and because buying the same car again in
-- another colour is a normal thing to want.
function VehicleSpawnerController:_details(spawnerId: string, definition: any, onChanged: () -> ())
	if not self.gui then
		return
	end
	local existing = self.gui:FindFirstChild("VehicleDetails")
	if existing then
		existing:Destroy()
	end
	local owned = definition.Owned == true and definition.VehicleId ~= nil
	local forSale = definition.ForSale == true

	local scrim = Instance.new("TextButton")
	scrim.Name = "VehicleDetails"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Tokens.Scrim.colour
	scrim.BackgroundTransparency = Tokens.Scrim.transparency
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.ZIndex = 30
	scrim.Parent = self.gui
	scrim.Activated:Connect(function()
		scrim:Destroy()
	end)

	local sheet = Instance.new("Frame")
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.fromScale(0.5, 0.5)
	sheet.Size = UDim2.fromScale(0.62, 0.72)
	sheet.BackgroundColor3 = C.surface
	sheet.BorderSizePixel = 0
	sheet.ZIndex = 31
	sheet.Parent = scrim
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(340, 380)
	bounds.MaxSize = Vector2.new(880, 620)
	bounds.Parent = sheet
	local edge = Instance.new("UIStroke")
	edge.Color = C.border
	edge.Transparency = S.transparency
	edge.Thickness = S.thickness
	edge.Parent = sheet

	local stage = Instance.new("ViewportFrame")
	stage.Size = UDim2.fromScale(1, 0.52)
	stage.BackgroundColor3 = C.canvas
	stage.BorderSizePixel = 0
	stage.Ambient = Color3.fromRGB(180, 190, 205)
	stage.LightColor = Color3.fromRGB(255, 255, 255)
	stage.ZIndex = 31
	stage.Parent = sheet
	local previews = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
	local model = previews and previews:FindFirstChild(tostring(definition.Id))
	if model then
		frameVehicle(stage, model, 0.58)
	end

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(34, 34)
	close.BackgroundColor3 = C.raised
	close.BorderSizePixel = 0
	close.Font = Tokens.Font.bold
	close.Text = "×"
	close.TextColor3 = C.text
	close.TextSize = T.title
	close.ZIndex = 32
	close.Parent = sheet
	close.Activated:Connect(function()
		scrim:Destroy()
	end)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 24, 0.52, 16)
	name.Size = UDim2.new(1, -48, 0, 28)
	name.Font = Tokens.Font.bold
	name.Text = tostring(definition.Name)
	name.TextColor3 = C.text
	name.TextSize = T.title
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 31
	name.Parent = sheet

	local headline = Instance.new("TextLabel")
	headline.BackgroundTransparency = 1
	headline.Position = UDim2.new(0, 24, 0.52, 46)
	headline.Size = UDim2.new(1, -48, 0, 24)
	headline.Font = Tokens.Font.bold
	headline.TextColor3 = C.text
	headline.TextSize = T.subtitle
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.ZIndex = 31
	headline.Parent = sheet

	local facts = Instance.new("TextLabel")
	facts.BackgroundTransparency = 1
	facts.Position = UDim2.new(0, 24, 0.52, 72)
	facts.Size = UDim2.new(1, -48, 0, 22)
	facts.Font = Tokens.Font.regular
	facts.TextColor3 = C.muted
	facts.TextSize = T.dense
	facts.TextXAlignment = Enum.TextXAlignment.Left
	facts.ZIndex = 31
	facts.Parent = sheet

	if owned then
		headline.Text = "REG " .. tostring(definition.Registration or "--")
		local parts = {}
		if type(definition.Colour) == "string" then
			table.insert(parts, string.upper(definition.Colour))
		end
		if type(definition.Fuel) == "number" then
			table.insert(parts, string.format("FUEL %d%%", math.floor(definition.Fuel)))
		end
		if type(definition.Condition) == "number" then
			table.insert(parts, string.format("CONDITION %d%%", math.floor(definition.Condition)))
		end
		if type(definition.Mileage) == "number" then
			table.insert(parts, string.format("%d MILES", math.floor(definition.Mileage)))
		end
		table.insert(parts, if definition.Insured then "INSURED" else "UNINSURED")
		table.insert(parts, if definition.Taxed then "TAXED" else "UNTAXED")
		facts.Text = table.concat(parts, "  •  ")
	else
		headline.Text = "£" .. formatMoney(definition.Price or 0)
		facts.Text = "Choose a colour. It is kept on the vehicle's record, and buying "
			.. "this car again gives you a second one with its own registration."
		facts.TextWrapped = true
		facts.Size = UDim2.new(1, -48, 0, 40)
	end

	local chosenColour = (definition.Colours and definition.Colours[1]) or "Default"
	if forSale and type(definition.Colours) == "table" then
		local swatchLabel = Instance.new("TextLabel")
		swatchLabel.BackgroundTransparency = 1
		swatchLabel.Position = UDim2.new(0, 24, 0.52, 118)
		swatchLabel.Size = UDim2.new(1, -48, 0, 18)
		swatchLabel.Font = Tokens.Font.bold
		swatchLabel.Text = "COLOUR  •  " .. string.upper(chosenColour)
		swatchLabel.TextColor3 = C.muted
		swatchLabel.TextSize = T.section
		swatchLabel.TextXAlignment = Enum.TextXAlignment.Left
		swatchLabel.ZIndex = 31
		swatchLabel.Parent = sheet

		local strokes = {}
		for index, colour in definition.Colours do
			local swatch = Instance.new("TextButton")
			swatch.Name = "Colour_" .. colour
			swatch.Position = UDim2.new(0, 24 + (index - 1) * 46, 0.52, 142)
			swatch.Size = UDim2.fromOffset(40, 40)
			swatch.BackgroundColor3 = paintFor(colour)
			swatch.BorderSizePixel = 0
			swatch.Text = ""
			swatch.AutoButtonColor = false
			swatch.ZIndex = 31
			swatch.Parent = sheet
			local ring = Instance.new("UIStroke")
			ring.Color = if colour == chosenColour then C.accent else C.border
			ring.Thickness = if colour == chosenColour then 3 else 1
			ring.Parent = swatch
			strokes[colour] = ring
			swatch.Activated:Connect(function()
				chosenColour = colour
				swatchLabel.Text = "COLOUR  •  " .. string.upper(colour)
				for other, ringed in strokes do
					ringed.Color = if other == colour then C.accent else C.border
					ringed.Thickness = if other == colour then 3 else 1
				end
			end)
		end
	end

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, -18)
	action.Size = UDim2.new(1, -48, 0, 44)
	action.BackgroundColor3 = if definition.Locked then C.raised else C.accentFill
	action.BorderSizePixel = 0
	action.Font = Tokens.Font.bold
	action.TextColor3 = if definition.Locked then C.muted else C.text
	action.TextSize = T.button
	action.Text = if definition.Locked
		then "REQUIRES ITS GAME PASS"
		elseif owned then "SPAWN THIS VEHICLE"
		else "BUY"
	action.ZIndex = 31
	action.Parent = sheet
	action.Activated:Connect(function()
		if definition.Locked then
			return
		end
		action.Active = false
		if owned then
			action.Text = "SPAWNING…"
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
			action.Active = true
			action.Text = "SPAWN THIS VEHICLE"
			return
		end
		action.Text = "BUYING…"
		local bought = self.context.Controllers.NetworkController:Request("PurchaseVehicle", {
			DefinitionId = definition.Id,
			Colour = chosenColour,
		})
		self.context.Controllers.NotificationController:Show(bought.Message, "Vehicles")
		if bought.Success then
			scrim:Destroy()
			onChanged()
		else
			action.Active = true
			action.Text = "BUY"
		end
	end)

	if owned then
		local plate = Instance.new("TextButton")
		plate.AnchorPoint = Vector2.new(1, 1)
		plate.Position = UDim2.new(1, -24, 1, -70)
		plate.Size = UDim2.fromOffset(120, 32)
		plate.BackgroundColor3 = C.raised
		plate.BorderSizePixel = 0
		plate.Font = Tokens.Font.bold
		plate.Text = "CHANGE PLATE"
		plate.TextColor3 = C.muted
		plate.TextSize = T.button
		plate.ZIndex = 31
		plate.Parent = sheet
		plate.Activated:Connect(function()
			scrim:Destroy()
			self:_customPlate(
				spawnerId,
				definition.VehicleId,
				tostring(definition.Registration or ""),
				function()
					onChanged()
				end
			)
		end)
	end
end

-- One forecourt tile. Split out of the panel so a filter can rebuild the grid
-- without rebuilding the screen around it.
--
-- The whole tile is the button. Colour and the rest of the detail moved into the
-- sheet behind it, because three swatches and a price and an action competing
-- inside a card this size is how a forecourt turns into a form.
function VehicleSpawnerController:_card(
	list: Instance,
	definition: any,
	spawnerId: string,
	previews: Instance?,
	order: number,
	onChanged: () -> ()
)
	local owned = definition.Owned == true and definition.VehicleId ~= nil
	local card = Instance.new("TextButton")
	card.Name = tostring(definition.Id)
	card.LayoutOrder = order
	card.BackgroundColor3 = C.raised
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = list

	local stage = Instance.new("ViewportFrame")
	stage.Size = UDim2.fromScale(1, 0.62)
	stage.BackgroundColor3 = C.surface
	stage.BorderSizePixel = 0
	stage.Ambient = Color3.fromRGB(180, 190, 205)
	stage.LightColor = Color3.fromRGB(255, 255, 255)
	stage.Parent = card
	local model = previews and previews:FindFirstChild(tostring(definition.Id))
	if model then
		frameVehicle(stage, model, 0.62)
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
	name.Position = UDim2.new(0, 14, 0.62, 10)
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
	detail.Position = UDim2.new(0, 14, 0.62, 34)
	detail.Size = UDim2.new(1, -100, 0, 22)
	detail.Font = Tokens.Font.bold
	detail.TextColor3 = C.text
	detail.TextSize = T.subtitle
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	detail.Text = if owned
		then "REG " .. tostring(definition.Registration or "--")
		else "£" .. formatMoney(definition.Price or 0)
	if owned then
		detail.Font = Tokens.Font.regular
		detail.TextColor3 = C.muted
		detail.TextSize = T.dense
	end
	detail.Parent = card

	-- A word rather than a button, since the tile itself is the button.
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.new(1, -14, 0.62, 34)
	hint.Size = UDim2.fromOffset(80, 22)
	hint.Font = Tokens.Font.bold
	hint.TextColor3 = if definition.Locked then C.muted else C.accent
	hint.TextSize = T.button
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = if definition.Locked then "LOCKED" elseif owned then "SPAWN" else "BUY"
	hint.Parent = card

	local ring = Instance.new("UIStroke")
	ring.Color = C.border
	ring.Transparency = S.transparency
	ring.Thickness = S.thickness
	ring.Parent = card
	card.MouseEnter:Connect(function()
		ring.Color = C.accent
	end)
	card.MouseLeave:Connect(function()
		ring.Color = C.border
	end)

	card.Activated:Connect(function()
		self:_details(spawnerId, definition, onChanged)
	end)
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
			self:_card(list, definition, spawnerId, previews, shown, function()
				self:_open(spawnerId)
			end)
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
