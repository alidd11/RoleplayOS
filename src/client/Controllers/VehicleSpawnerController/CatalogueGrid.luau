--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)

local Tokens = Utils.Tokens
local C, T, S = Utils.C, Utils.T, Utils.S
local formatMoney = Utils.formatMoney
local frameVehicle = Utils.frameVehicle

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

return function(VehicleSpawnerController)
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
		-- Issued rather than bought. A department vehicle belongs to the unit, so
		-- this terminal takes one out and there is nothing to pay: without this the
		-- police bay offered its whole fleet at zero pounds with a buy button that
		-- the server then refused, because a service vehicle is not for sale.
		local issued = definition.Spawnable == true
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
			elseif issued then string.upper(tostring(definition.DivisionId or "FLEET"))
			else "£" .. formatMoney(definition.Price or 0)
		if owned or issued then
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
		hint.Text = if definition.Locked then "LOCKED" elseif owned or issued then "SPAWN" else "BUY"
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

	function VehicleSpawnerController:_open(spawnerId: string)
		local response =
			self.context.Controllers.NetworkController:Request("GetVehicleSpawnerMenu", {
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
		-- Above the HUD, below the menu.
		--
		-- At 35 this sat under the radio at 38 and the phone at 40, which was
		-- survivable while it was a small dialog and absurd once it went full screen:
		-- the radio drew straight down the middle of the forecourt. A screen that
		-- takes over the whole display belongs above every panel that decorates the
		-- world and below the start menu, which takes over harder still.
		gui.DisplayOrder = 45
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
end
