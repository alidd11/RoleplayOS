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
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(2, 7, 13)
	scrim.BackgroundTransparency = 0.28
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Parent = gui
	scrim.Activated:Connect(function()
		self:_close()
	end)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.72, 0.72)
	panel.BackgroundColor3 = C.surface
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(330, 390)
	sizeConstraint.MaxSize = Vector2.new(920, 650)
	sizeConstraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, R.shell)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.border
	stroke.Transparency = S.transparency
	stroke.Thickness = S.thickness
	stroke.Parent = panel
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 92)
	header.BackgroundColor3 = C.raised
	header.BorderSizePixel = 0
	header.Parent = panel
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, R.shell)
	headerCorner.Parent = header
	local accent = Instance.new("Frame")
	accent.Position = UDim2.fromOffset(0, 90)
	accent.Size = UDim2.new(1, 0, 0, 2)
	accent.BackgroundColor3 = C.accent
	accent.BorderSizePixel = 0
	accent.Parent = header
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.new(1, -92, 0, 34)
	title.Font = Enum.Font.GothamBold
	title.Text = tostring(response.Data.Name or "Vehicles")
	title.TextColor3 = C.text
	title.TextSize = T.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(24, 47)
	subtitle.Size = UDim2.new(1, -92, 0, 24)
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Buy a vehicle, or take one of yours out"
	subtitle.TextColor3 = C.muted
	subtitle.TextSize = T.body
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = header
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = C.raised
	close.Text = "×"
	close.TextColor3 = C.text
	close.TextSize = T.title
	close.Parent = header
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, R.control)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		self:_close()
	end)
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 112)
	list.Size = UDim2.new(1, -40, 1, -132)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = Tokens.Scroll.barThickness
	list.Parent = panel
	local vehicles = response.Data.Vehicles or {}
	if #vehicles == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, -6, 0, 180)
		empty.BackgroundColor3 = C.raised
		empty.BorderSizePixel = 0
		empty.Parent = list
		local emptyCorner = Instance.new("UICorner")
		emptyCorner.CornerRadius = UDim.new(0, R.card)
		emptyCorner.Parent = empty
		local emptyTitle = Instance.new("TextLabel")
		emptyTitle.BackgroundTransparency = 1
		emptyTitle.Position = UDim2.fromOffset(20, 43)
		emptyTitle.Size = UDim2.new(1, -40, 0, 32)
		emptyTitle.Font = Enum.Font.GothamBold
		emptyTitle.Text = "No vehicles available"
		emptyTitle.TextColor3 = Color3.fromRGB(238, 243, 249)
		emptyTitle.TextSize = 18
		emptyTitle.Parent = empty
		local emptyBody = Instance.new("TextLabel")
		emptyBody.BackgroundTransparency = 1
		emptyBody.Position = UDim2.fromOffset(30, 78)
		emptyBody.Size = UDim2.new(1, -60, 0, 54)
		emptyBody.Font = Enum.Font.Gotham
		emptyBody.Text =
			"Your garage is empty or its vehicle models are unavailable. Try again after selecting a character."
		emptyBody.TextWrapped = true
		emptyBody.TextColor3 = Color3.fromRGB(145, 164, 187)
		emptyBody.TextSize = 13
		emptyBody.Parent = empty
	end
	-- Cards rather than rows.
	--
	-- This was a list of names with a spawn button, which was all it could be:
	-- the menu only ever contained cars the player already owned. It is a
	-- forecourt now, so a card has to answer what the car looks like, what it
	-- costs and whether you already have one, and the same card is the place you
	-- buy it and the place you take it out afterwards.
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local function resizeCells()
		local width = list.AbsoluteSize.X
		if width <= 0 then
			return
		end
		-- Whole pixels, with the remainder left in the gutter. Fractional cells
		-- round up past the container and cost a column.
		local columns = if width >= 860 then 3 elseif width >= 560 then 2 else 1
		local cell = math.floor((width - 12 * (columns - 1) - 6) / columns)
		grid.CellSize = UDim2.fromOffset(cell, math.floor(cell * 0.86))
	end
	resizeCells()
	table.insert(
		self.connections,
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeCells)
	)

	local previews = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
	for order, definition in vehicles do
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
			-- Framed off the diagonal rather than the longest edge, and viewed
			-- from a front three quarter. A factor of one and a half put a car in
			-- the middle distance and made every card look like a thumbnail of a
			-- thumbnail.
			local distance = math.sqrt(size.X * size.X + size.Z * size.Z) * 0.62
			camera.CFrame = CFrame.lookAt(
				centre.Position + Vector3.new(distance, distance * 0.34, distance),
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
