--!strict

-- The in-game character creator.
--
-- A character's appearance is authored here once, when it is created, and then
-- fixed. Reopening it later is a purchase, which is why this closes by writing
-- through SetAuthoredAppearance rather than saving as it goes: a half-finished
-- look must not consume the edit.
--
-- Preview is applied locally and never sent. A HumanoidDescription written on
-- the client changes only what this player sees, so trying items on costs
-- nothing, needs no round trip, and cannot be observed by anybody else. The
-- authoritative write happens once, on Save, and the server re-derives what was
-- actually worn rather than trusting the payload.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local COLOURS = {
	Canvas = Color3.fromHex("#0F141C"),
	Surface = Color3.fromHex("#181F2B"),
	SurfaceRaised = Color3.fromHex("#1F2837"),
	Text = Color3.fromHex("#F0F4FB"),
	Muted = Color3.fromHex("#AEB8C9"),
	Border = Color3.fromHex("#38455C"),
	Accent = Color3.fromHex("#5B9CFF"),
	AccentFill = Color3.fromHex("#1F5FD0"),
	Danger = Color3.fromHex("#F46870"),
}

-- Roblox's own skin palette, so a character made here sits alongside avatars
-- made on the website rather than looking like it came from somewhere else.
local SKIN_TONES = {
	"f8d8b0",
	"eec1a2",
	"d8a888",
	"cc8e69",
	"b1740a",
	"a6653f",
	"8c5a3b",
	"6b4423",
	"4a2f1a",
	"f2c7a3",
	"e0b08c",
	"c68642",
}

-- Body proportions the creator exposes, bounded to the same ranges the server
-- accepts so the interface cannot offer a value that will be refused on save.
local BODY_SLIDERS = {
	{ Field = "HeightScale", Label = "HEIGHT", Minimum = 0.9, Maximum = 1.05 },
	{ Field = "WidthScale", Label = "BUILD", Minimum = 0.7, Maximum = 1 },
	{ Field = "HeadScale", Label = "HEAD", Minimum = 0.95, Maximum = 1.05 },
	{ Field = "ProportionScale", Label = "PROPORTION", Minimum = 0, Maximum = 1 },
	{ Field = "BodyTypeScale", Label = "BODY TYPE", Minimum = 0, Maximum = 1 },
}

local CharacterCreator = {}
CharacterCreator.__index = CharacterCreator

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, colour: Color3?, transparency: number?)
	local item = Instance.new("UIStroke")
	item.Color = colour or COLOURS.Border
	item.Transparency = transparency or 0.6
	item.Thickness = 1
	item.Parent = parent
	return item
end

local function label(parent: Instance, text: string, size: number, colour: Color3, bold: boolean?)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = text
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

function CharacterCreator.new(context: any)
	local self = setmetatable({}, CharacterCreator)
	self.context = context
	self.connections = {}
	-- What the player has chosen so far, in the shape the server accepts.
	self.draft = {}
	self.categories = {}
	self.activeCategory = nil
	self.onFinished = nil
	return self
end

-- Applies the draft to the local character so the player sees themselves change.
--
-- Client only and deliberately so: this is a fitting room, not a commitment.
-- Failures are swallowed because a single unavailable item should not stop the
-- rest of the outfit previewing.
function CharacterCreator:_preview()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return
	end
	for field, value in self.draft do
		pcall(function()
			if string.find(field, "Color") then
				(description :: any)[field] = Color3.fromHex(value)
			else
				(description :: any)[field] = value
			end
		end)
	end
	pcall(function()
		humanoid:ApplyDescription(description)
	end)
end

function CharacterCreator:_setField(field: string, value: any)
	self.draft[field] = value
	self:_preview()
end

-- One selectable catalogue item.
function CharacterCreator:_itemTile(parent: Instance, item: any)
	local tile = Instance.new("TextButton")
	tile.Name = tostring(item.Id)
	tile.AutoButtonColor = false
	tile.BackgroundColor3 = COLOURS.SurfaceRaised
	tile.BorderSizePixel = 0
	tile.Text = ""
	tile.Parent = parent
	corner(tile, 10)
	local outline = stroke(tile, COLOURS.Border, 0.7)

	local thumb = Instance.new("ImageLabel")
	thumb.BackgroundTransparency = 1
	thumb.Size = UDim2.new(1, -12, 1, -26)
	thumb.Position = UDim2.fromOffset(6, 6)
	thumb.Image = string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", item.Id)
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.Parent = tile

	local name = label(tile, item.Name, 10, COLOURS.Muted)
	name.Size = UDim2.new(1, -10, 0, 18)
	name.Position = UDim2.new(0, 5, 1, -20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextXAlignment = Enum.TextXAlignment.Center

	table.insert(
		self.connections,
		tile.Activated:Connect(function()
			-- Selecting the item already worn takes it off, which is the only way
			-- to remove an accessory once one has been chosen.
			if self.draft[item.Field] == tostring(item.Id) then
				self.draft[item.Field] = nil
			else
				self.draft[item.Field] = tostring(item.Id)
			end
			self:_preview()
			self:_paintSelection(parent, item.Field)
		end)
	)
	return tile, outline
end

-- Marks whichever tile in the open category is currently worn.
function CharacterCreator:_paintSelection(grid: Instance, field: string)
	local worn = self.draft[field]
	for _, child in grid:GetChildren() do
		if child:IsA("TextButton") then
			local selected = worn ~= nil and child.Name == worn
			local outline = child:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Color = if selected then COLOURS.Accent else COLOURS.Border
				outline.Transparency = if selected then 0 else 0.7
			end
			child.BackgroundColor3 = if selected then COLOURS.AccentFill else COLOURS.SurfaceRaised
		end
	end
end

function CharacterCreator:_loadCategory(categoryId: string, keyword: string?)
	self.activeCategory = categoryId
	local grid = self.grid
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	self.status.Text = "Loading…"
	task.spawn(function()
		local response = self.context.Controllers.NetworkController:Request("SearchAvatarCatalog", {
			CategoryId = categoryId,
			Keyword = keyword or "",
		})
		if self.activeCategory ~= categoryId then
			return
		end
		if not response.Success or type(response.Data) ~= "table" then
			self.status.Text = response.Message ~= "" and response.Message or "Nothing found."
			return
		end
		local items = response.Data.Items or {}
		self.status.Text = if #items == 0 then "Nothing found." else ""
		for _, item in items do
			self:_itemTile(grid, item)
		end
		self:_paintSelection(grid, response.Data.Field)
	end)
end

function CharacterCreator:_buildSkinRow(parent: Instance)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = parent
	local flow = Instance.new("UIListLayout")
	flow.FillDirection = Enum.FillDirection.Horizontal
	flow.Padding = UDim.new(0, 6)
	flow.Parent = row
	for _, hex in SKIN_TONES do
		local swatch = Instance.new("TextButton")
		swatch.Size = UDim2.fromOffset(26, 26)
		swatch.BackgroundColor3 = Color3.fromHex(hex)
		swatch.BorderSizePixel = 0
		swatch.AutoButtonColor = false
		swatch.Text = ""
		swatch.Parent = row
		corner(swatch, 13)
		stroke(swatch, COLOURS.Border, 0.5)
		table.insert(
			self.connections,
			swatch.Activated:Connect(function()
				-- One tone across every limb. Roblox allows a different colour per
				-- body part, but a creator that exposes six pickers invites a
				-- character with a green arm, which is not what this is for.
				for _, field in
					{
						"HeadColor",
						"TorsoColor",
						"LeftArmColor",
						"RightArmColor",
						"LeftLegColor",
						"RightLegColor",
					}
				do
					self.draft[field] = hex
				end
				self:_preview()
			end)
		)
	end
	return row
end

function CharacterCreator:_buildSlider(parent: Instance, definition: any)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 34)
	holder.Parent = parent

	local caption = label(holder, definition.Label, 10, COLOURS.Muted, true)
	caption.Size = UDim2.new(1, 0, 0, 12)

	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.Text = ""
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.fromOffset(0, 18)
	track.BackgroundColor3 = COLOURS.Border
	track.BorderSizePixel = 0
	track.Parent = holder
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COLOURS.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.Parent = track
	corner(fill, 3)

	local function setFromX(x: number)
		local absolute = track.AbsolutePosition.X
		local width = math.max(1, track.AbsoluteSize.X)
		local alpha = math.clamp((x - absolute) / width, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		local value = definition.Minimum + (definition.Maximum - definition.Minimum) * alpha
		self:_setField(definition.Field, value)
	end

	table.insert(
		self.connections,
		track.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				setFromX(input.Position.X)
			end
		end)
	)
	return holder
end

-- Opens the creator. `onFinished(saved)` is called once, whichever way it closes.
function CharacterCreator:Open(characterId: string, onFinished: ((boolean) -> ())?, editState: any?)
	self:Close()
	self.characterId = characterId
	self.onFinished = onFinished
	self.editState = editState
	self.draft = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCharacterCreator"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 60
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = COLOURS.Canvas
	root.BorderSizePixel = 0
	root.Parent = gui
	self.root = root

	local header = Instance.new("Frame")
	header.BackgroundColor3 = COLOURS.Surface
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 46)
	header.Parent = root
	self.header = header

	local title = label(header, "CREATE YOUR LOOK", 15, COLOURS.Text, true)
	title.Position = UDim2.fromOffset(20, 0)
	title.Size = UDim2.new(1, -240, 1, 0)

	-- A first look is free and final; a later one is bought. Saying which applies
	-- before anything is chosen matters, because the save is what spends the edit
	-- and by then the player has already done the work.
	local hintCopy = if editState and editState.CostsCredit
		then "Editing this look will use one of your appearance edits when you save."
		else "Choose how this character looks. This is set once."
	local hint = label(header, hintCopy, 11, COLOURS.Muted)
	hint.Position = UDim2.fromOffset(20, 26)
	hint.Size = UDim2.new(1, -240, 0, 14)
	self.hint = hint

	local save = Instance.new("TextButton")
	save.AnchorPoint = Vector2.new(1, 0.5)
	save.Position = UDim2.new(1, -16, 0.5, 0)
	save.Size = UDim2.fromOffset(112, 32)
	save.BackgroundColor3 = COLOURS.AccentFill
	save.BorderSizePixel = 0
	save.Font = Enum.Font.GothamBold
	save.Text = "SAVE LOOK"
	save.TextColor3 = COLOURS.Text
	save.TextSize = 12
	save.Parent = header
	corner(save, 8)
	self.saveButton = save

	local cancel = Instance.new("TextButton")
	cancel.AnchorPoint = Vector2.new(1, 0.5)
	cancel.Position = UDim2.new(1, -136, 0.5, 0)
	cancel.Size = UDim2.fromOffset(86, 32)
	cancel.BackgroundColor3 = COLOURS.SurfaceRaised
	cancel.BorderSizePixel = 0
	cancel.Font = Enum.Font.GothamBold
	cancel.Text = "CANCEL"
	cancel.TextColor3 = COLOURS.Muted
	cancel.TextSize = 12
	cancel.Parent = header
	corner(cancel, 8)

	-- Category rail. Becomes a horizontal strip on a compact screen, where there
	-- is width to spend but no height.
	local rail = Instance.new("ScrollingFrame")
	rail.BackgroundColor3 = COLOURS.Surface
	rail.BorderSizePixel = 0
	rail.ScrollBarThickness = 3
	rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rail.CanvasSize = UDim2.new()
	rail.Parent = root
	self.rail = rail
	local railFlow = Instance.new("UIListLayout")
	railFlow.Padding = UDim.new(0, 4)
	railFlow.Parent = rail
	self.railFlow = railFlow

	local grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = root
	self.grid = grid
	local gridFlow = Instance.new("UIGridLayout")
	gridFlow.CellSize = UDim2.fromOffset(92, 104)
	gridFlow.CellPadding = UDim2.fromOffset(8, 8)
	gridFlow.Parent = grid
	self.gridFlow = gridFlow

	-- Deliberately not a child of the grid. Loading a category clears the grid,
	-- so a status line living inside it would be destroyed by the very call that
	-- then writes "Loading…" to it.
	local status = label(root, "", 12, COLOURS.Muted)
	status.Size = UDim2.new(1, -32, 0, 20)
	self.status = status

	-- Body and skin, which need no catalogue and so are always available even if
	-- the catalogue is down.
	local body = Instance.new("Frame")
	body.BackgroundColor3 = COLOURS.Surface
	body.BorderSizePixel = 0
	body.Parent = root
	self.body = body
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 12)
	bodyPad.PaddingLeft = UDim.new(0, 14)
	bodyPad.PaddingRight = UDim.new(0, 14)
	bodyPad.Parent = body
	local bodyFlow = Instance.new("UIListLayout")
	bodyFlow.Padding = UDim.new(0, 8)
	bodyFlow.Parent = body

	local skinCaption = label(body, "SKIN", 10, COLOURS.Muted, true)
	skinCaption.Size = UDim2.new(1, 0, 0, 12)
	self:_buildSkinRow(body)
	for _, definition in BODY_SLIDERS do
		self:_buildSlider(body, definition)
	end

	table.insert(
		self.connections,
		cancel.Activated:Connect(function()
			self:_finish(false)
		end)
	)
	table.insert(
		self.connections,
		save.Activated:Connect(function()
			self:_save()
		end)
	)

	-- Responsive layout, driven by the orchestrator rather than by reading the
	-- viewport here, so this panel follows the same breakpoints as everything else.
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"CharacterCreator",
		function(layout)
			local compact = layout.Compact
			local headerHeight = if compact then 40 else 46
			header.Size = UDim2.new(1, 0, 0, headerHeight)
			title.TextSize = if compact then 13 else 15
			hint.Visible = not compact

			if compact then
				-- Categories run across the top, body controls along the bottom, and
				-- the grid takes what is left. A phone has width and no height.
				rail.Size = UDim2.new(1, 0, 0, 34)
				rail.Position = UDim2.fromOffset(0, headerHeight)
				railFlow.FillDirection = Enum.FillDirection.Horizontal
				rail.AutomaticCanvasSize = Enum.AutomaticSize.X
				body.Size = UDim2.new(1, 0, 0, 150)
				body.Position = UDim2.new(0, 0, 1, -150)
				grid.Position = UDim2.fromOffset(8, headerHeight + 38)
				grid.Size = UDim2.new(1, -16, 1, -(headerHeight + 38 + 150 + 8))
				gridFlow.CellSize = UDim2.fromOffset(78, 90)
				self.status.Position = UDim2.fromOffset(16, headerHeight + 18)
			else
				rail.Size = UDim2.new(0, 150, 1, -headerHeight)
				rail.Position = UDim2.fromOffset(0, headerHeight)
				railFlow.FillDirection = Enum.FillDirection.Vertical
				rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
				local bodyWidth = if layout.Breakpoint == "Tablet" then 220 else 260
				body.Size = UDim2.new(0, bodyWidth, 1, -headerHeight)
				body.Position = UDim2.new(1, -bodyWidth, 0, headerHeight)
				grid.Position = UDim2.fromOffset(162, headerHeight + 26)
				grid.Size = UDim2.new(1, -(162 + bodyWidth + 16), 1, -(headerHeight + 34))
				gridFlow.CellSize = UDim2.fromOffset(92, 104)
				self.status.Position = UDim2.fromOffset(162, headerHeight + 6)
			end
		end
	)

	self:_loadCategories()

	if self.context.Controllers.SettingsController then
		local settings = self.context.Controllers.SettingsController:Get()
		if not settings or settings.InterfaceMotion ~= false then
			root.BackgroundTransparency = 1
			TweenService:Create(
				root,
				TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 0 }
			):Play()
		end
	end
end

function CharacterCreator:_loadCategories()
	task.spawn(function()
		local response =
			self.context.Controllers.NetworkController:Request("GetAvatarCatalogCategories", {})
		if not self.rail or not self.rail.Parent then
			return
		end
		if not response.Success or type(response.Data) ~= "table" then
			self.status.Text = "The catalogue is unavailable. Skin and body still work."
			return
		end
		self.categories = response.Data.Categories or {}
		for index, category in self.categories do
			local tab = Instance.new("TextButton")
			tab.Name = category.Id
			tab.AutoButtonColor = false
			tab.Size = UDim2.new(1, -8, 0, 30)
			tab.BackgroundColor3 = COLOURS.SurfaceRaised
			tab.BorderSizePixel = 0
			tab.Font = Enum.Font.GothamBold
			tab.Text = string.upper(category.Id)
			tab.TextColor3 = COLOURS.Muted
			tab.TextSize = 11
			tab.LayoutOrder = index
			tab.Parent = self.rail
			corner(tab, 7)
			table.insert(
				self.connections,
				tab.Activated:Connect(function()
					for _, sibling in self.rail:GetChildren() do
						if sibling:IsA("TextButton") then
							sibling.BackgroundColor3 = COLOURS.SurfaceRaised
							sibling.TextColor3 = COLOURS.Muted
						end
					end
					tab.BackgroundColor3 = COLOURS.AccentFill
					tab.TextColor3 = COLOURS.Text
					self:_loadCategory(category.Id)
				end)
			)
		end
		local first = self.categories[1]
		if first then
			local tab = self.rail:FindFirstChild(first.Id)
			if tab and tab:IsA("TextButton") then
				tab.BackgroundColor3 = COLOURS.AccentFill
				tab.TextColor3 = COLOURS.Text
			end
			self:_loadCategory(first.Id)
		end
	end)
end

function CharacterCreator:_save()
	if self.saving then
		return
	end
	if next(self.draft) == nil then
		self.status.Text = "Choose something first."
		return
	end
	self.saving = true
	self.saveButton.Text = "SAVING…"
	task.spawn(function()
		local response = self.context.Controllers.NetworkController:Request(
			"SetAuthoredAppearance",
			{ CharacterId = self.characterId, Appearance = self.draft }
		)
		self.saving = false
		if not self.saveButton or not self.saveButton.Parent then
			return
		end
		self.saveButton.Text = "SAVE LOOK"
		if response.Success then
			self:_finish(true)
			return
		end
		self.status.Text = response.Message
		self.context.Controllers.NotificationController:Show(response.Message, "Appearance")
	end)
end

function CharacterCreator:_finish(saved: boolean)
	local callback = self.onFinished
	self.onFinished = nil
	self:Close()
	if callback then
		callback(saved)
	end
end

function CharacterCreator:Close()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
		self.unbindLayout = nil
	end
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
	self.saving = false
	self.activeCategory = nil
end

function CharacterCreator:Destroy()
	self:Close()
end

return CharacterCreator
