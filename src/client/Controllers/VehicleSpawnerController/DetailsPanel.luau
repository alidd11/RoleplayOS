--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(script.Parent.Utils)

local Tokens = Utils.Tokens
local C, T, S = Utils.C, Utils.T, Utils.S
local formatMoney = Utils.formatMoney
local frameVehicle = Utils.frameVehicle

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

return function(VehicleSpawnerController)
	-- The vehicle itself, opened by clicking its card.
	--
	-- Colour moved here from the grid. On a card it was three squares under a price
	-- competing with the buy button; here it is the decision the screen is about,
	-- which matters because the choice is permanent - the record keeps it and
	-- nothing in the game resprays - and because buying the same car again in
	-- another colour is a normal thing to want.
	function VehicleSpawnerController:_details(
		spawnerId: string,
		definition: any,
		onChanged: () -> ()
	)
		if not self.gui then
			return
		end
		local existing = self.gui:FindFirstChild("VehicleDetails")
		if existing then
			existing:Destroy()
		end
		local owned = definition.Owned == true and definition.VehicleId ~= nil
		local issued = definition.Spawnable == true
		local forSale = definition.ForSale == true and not issued

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
				table.insert(
					parts,
					string.format("CONDITION %d%%", math.floor(definition.Condition))
				)
			end
			if type(definition.Mileage) == "number" then
				table.insert(parts, string.format("%d MILES", math.floor(definition.Mileage)))
			end
			table.insert(parts, if definition.Insured then "INSURED" else "UNINSURED")
			table.insert(parts, if definition.Taxed then "TAXED" else "UNTAXED")
			facts.Text = table.concat(parts, "  •  ")
		elseif issued then
			headline.Text = string.upper(tostring(definition.DivisionId or "FLEET"))
			facts.Text = "Issued to your unit. It keeps the same registration every time "
				.. "you take it out."
			facts.TextWrapped = true
			facts.Size = UDim2.new(1, -48, 0, 40)
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
			elseif owned or issued then "SPAWN THIS VEHICLE"
			else "BUY"
		action.ZIndex = 31
		action.Parent = sheet
		action.Activated:Connect(function()
			if definition.Locked then
				return
			end
			action.Active = false
			if owned or issued then
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
end
