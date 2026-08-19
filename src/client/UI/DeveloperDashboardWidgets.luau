--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Config = require(game:GetService("ReplicatedStorage").RoleplayOS.Config.Config)
local Tokens = require(script.Parent.DesignTokens)

local Widgets = {}
local activeAudioFeedback: any = nil

function Widgets.setAudioFeedback(value: any)
	activeAudioFeedback = value
end

-- The menu's palette, taken from the shared token set rather than restated.
--
-- These were sixteen literals that happened to be a lighter blue than every
-- other surface in the game, which is why the start menu and the terminals have
-- never looked like the same product. DesignTokens is the one place a colour is
-- decided; this table stays only because the names here read better at the call
-- sites than the token names would, and because two of them are derived rather
-- than taken.
local COLOURS = {
	Canvas = Tokens.Colour.canvas,
	-- One step between canvas and surface, for a rail that has to separate from
	-- both. Derived because the token set has no such step: its three panels
	-- never needed one.
	Sidebar = Tokens.Colour.surface:Lerp(Tokens.Colour.canvas, 0.5),
	Surface = Tokens.Colour.surface,
	SurfaceRaised = Tokens.Colour.raised,
	Border = Tokens.Colour.border,
	Text = Tokens.Colour.text,
	Muted = Tokens.Colour.muted,
	Accent = Tokens.Colour.accent,
	-- Fill for primary buttons. The accent is a good colour for text, strokes and
	-- indicators against the dark canvas, and a poor one behind white label text:
	-- that pairing measures about two and a half to one, well under the four and
	-- a half a body label needs. This is the same hue, dark enough to carry it.
	AccentFill = Tokens.Colour.accentFill,
	-- A tinted surface for a selected row, between raised and the filled accent.
	AccentSoft = Tokens.Colour.raised:Lerp(Tokens.Colour.accentFill, 0.45),
	Success = Tokens.Colour.success,
	Warning = Tokens.Colour.warning,
	Danger = Tokens.Colour.danger,
}

local ROLE_PRESENTATION = {
	Civilian = { Icon = "CIV", Colour = COLOURS.Accent, Label = "PUBLIC LIFE" },
	Police = { Icon = "POL", Colour = Color3.fromRGB(72, 132, 224), Label = "POLICING" },
	Ambulance = { Icon = "AMB", Colour = Color3.fromRGB(80, 190, 133), Label = "AMBULANCE" },
	Fire = { Icon = "FIRE", Colour = Color3.fromRGB(231, 92, 82), Label = "FIRE & RESCUE" },
	Highways = { Icon = "HWY", Colour = Color3.fromRGB(238, 174, 67), Label = "HIGHWAYS" },
	Transport = { Icon = "BUS", Colour = Color3.fromRGB(148, 108, 219), Label = "TRANSPORT" },
	Prison = { Icon = "HMP", Colour = Color3.fromRGB(167, 117, 75), Label = "PRISON SERVICE" },
	Control = { Icon = "CTL", Colour = Color3.fromRGB(50, 190, 188), Label = "FORCE CONTROL" },
}

-- Uploaded through the Roblox Creator Dashboard. Keep these IDs in one small
-- presentation map so replacing artwork never touches role-access logic.
-- Image ids, not decal ids.
--
-- Uploading a picture to Roblox creates a Decal wrapping an Image, and the id
-- shown in the dashboard is the Decal's. An ImageLabel cannot render that, so
-- every tile fetched its artwork, failed, and drew the empty background colour
-- behind it: nine blank cards from nine perfectly good uploads. These are the
-- Texture ids read out of each Decal, which is what the label actually wants.
--
-- To add one: insert the decal in Studio, read its Texture property, and put
-- that id here. The decal id from the Creator Dashboard will not work.
-- Roles that are civilian work rather than an emergency service. They keep every
-- bit of their machinery - team, uniform, loadout, access - and only move which
-- page offers them.
local CIVILIAN_JOB_ROLE_IDS = {
	TransportOperator = true,
}

-- The order services appear in on Play.
--
-- Config.Roles is a hash, so the server sends them in whatever order Luau
-- happens to walk it, and that order is not stable between runs. The grid was
-- therefore shuffling the emergency services around for no reason a player
-- could see. This lists the ones whose position is a deliberate decision;
-- anything absent sorts after them by name, so a new role lands somewhere
-- predictable without having to be named here first.
local ROLE_DISPLAY_ORDER = {
	PoliceFrontline = 1,
	RoadsPolicingOfficer = 2,
	ArmedResponseOfficer = 3,
	Paramedic = 4,
	Firefighter = 5,
	DogSupportOfficer = 6,
	Controller = 7,
	HighwayPatrolOfficer = 8,
	PrisonOfficer = 9,
	PCSO = 10,
}

-- The tile artwork now lives in Config, so the preloader warms exactly what
-- these tiles ask for. It was duplicated here, and the two drifted: the preload
-- list still held the Decal ids these were before they were re-uploaded as
-- Images, wrapped in a thumbnail size Roblox does not serve.

local function roleTileImageUri(role: any): string?
	local tiles = Config.RoleTileImages
	local assetId = tiles[role.DepartmentId] or tiles[role.Id]
	if not assetId then
		return nil
	end
	-- Used directly, because these are Image ids now.
	--
	-- This used to wrap them in rbxthumb://type=Asset, which was a sound
	-- workaround while the ids above were Decals: an ImageLabel cannot render a
	-- Decal id, and asking for its thumbnail at least produced a picture. The ids
	-- are the underlying Images now, and the wrapper became the thing breaking
	-- them - a thumbnail of an Image is not a thing Roblox serves, so every tile
	-- fetched, failed and drew its background colour. Two fixes for one bug, each
	-- undoing the other.
	return assetId
end

local function rolePresentation(role: any): any
	local key = role.DepartmentId or role.Id
	return ROLE_PRESENTATION[key]
		or { Icon = "ROLE", Colour = COLOURS.Accent, Label = "PUBLIC SERVICE" }
end

local corner: (Instance, number) -> ()
local stroke: (Instance, Color3?, number?) -> ()
local cachedAvatarDescription: HumanoidDescription? = nil

-- `placeholder` names what to show when the uniform has no clothing configured.
--
-- Passing nil keeps the old behaviour of falling back to the player's own
-- avatar, which is right for a civilian character: their own clothes are their
-- look. It is wrong for a role. Every service uniform in the configuration
-- still has empty shirt and trouser IDs, so a role preview built the player's
-- current outfit and presented it as the uniform: the firefighter and the
-- paramedic showed the same person in the same clothes, and so did the civilian
-- card next to them. A preview that shows the same thing whatever it previews
-- is worse than no preview, because it looks like an answer.
--
-- It also skips building the avatar at all in that case. A departments page
-- holds ten of these, and ten rigged R15 models were being assembled and
-- rendered on a phone to show the same wrong outfit ten times.
local function portraitPreview(
	parent: Instance,
	accent: Color3,
	uniform: any?,
	isCurrent: (() -> boolean)?,
	placeholder: string?
): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "AvatarPreview"
	viewport.BackgroundColor3 = COLOURS.SurfaceRaised
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.6, -0.45, -1)
	viewport.Parent = parent
	corner(viewport, 12)
	stroke(viewport, accent, 0.68)

	local wash = Instance.new("UIGradient")
	wash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOURS.Border),
		ColorSequenceKeypoint.new(1, COLOURS.SurfaceRaised),
	})
	wash.Rotation = 90
	wash.Parent = viewport

	local configuredShirt = tonumber(uniform and uniform.ShirtTemplate) or 0
	local configuredTrousers = tonumber(uniform and uniform.TrousersTemplate) or 0
	if placeholder and configuredShirt <= 0 and configuredTrousers <= 0 then
		local mark = Instance.new("TextLabel")
		mark.BackgroundTransparency = 1
		mark.Font = Enum.Font.GothamBold
		mark.Text = placeholder
		mark.TextColor3 = accent
		mark.TextTransparency = 0.25
		mark.TextScaled = false
		mark.TextTruncate = Enum.TextTruncate.AtEnd
		local markBounds = Instance.new("UITextSizeConstraint")
		markBounds.MinTextSize = 12
		markBounds.MaxTextSize = 18
		markBounds.Parent = mark
		mark.Size = UDim2.fromScale(0.62, 0.42)
		mark.Position = UDim2.fromScale(0.19, 0.29)
		mark.Parent = viewport
		return viewport
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.15, 7.6), Vector3.new(0, 1.05, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Parent = viewport

	task.spawn(function()
		local ok, modelOrError = pcall(function()
			if not cachedAvatarDescription then
				cachedAvatarDescription =
					Players:GetHumanoidDescriptionFromUserId(Players.LocalPlayer.UserId)
			end
			local description = cachedAvatarDescription:Clone()
			if configuredShirt > 0 then
				description.Shirt = configuredShirt
			end
			if configuredTrousers > 0 then
				description.Pants = configuredTrousers
			end
			return Players:CreateHumanoidModelFromDescriptionAsync(
				description,
				Enum.HumanoidRigType.R15
			)
		end)
		if not ok or typeof(modelOrError) ~= "Instance" then
			return
		end
		local model = modelOrError :: Model
		if not viewport.Parent or (isCurrent and not isCurrent()) then
			model:Destroy()
			return
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CastShadow = false
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end
		model:PivotTo(CFrame.Angles(0, math.rad(180), 0))
		model.Parent = world
	end)

	return viewport
end

local TILE_GAP = 14
local TILE_GAP_COMPACT = 10
-- A tile that has grown to fill a tall page still has to look like a poster
-- rather than a column, so height is capped against the width it was given as
-- well as in absolute terms.
local TILE_MAX_ASPECT = 1.6
local TILE_MAX_HEIGHT = 520
local TILE_MIN_HEIGHT = 168

type TileGridOptions = {
	Name: string?,
	Count: number,
	-- Preferred column count. The grid balances it against how many tiles there
	-- actually are, so this is a ceiling rather than the answer.
	Columns: number,
	-- Fixed tile height. Omitted, the grid divides the page up instead.
	Height: number?,
	MinHeight: number?,
}

-- Eleven roles over six columns is a row of six and a row of five, which reads
-- as a row that ran out rather than as a grid. Rows are counted from the
-- preferred width first and the columns are then spread back over them, so the
-- last row is never short by more than one tile.
local function balancedColumns(count: number, preferred: number): number
	local columns = math.clamp(preferred, 1, math.max(1, count))
	local rows = math.max(1, math.ceil(count / columns))
	return math.max(1, math.ceil(count / rows))
end

-- Cells are measured in whole pixels taken from the grid, not in fractions of
-- it.
--
-- The scale form - one column wide with the gutters subtracted back off - adds
-- up to exactly the container in exact arithmetic and to fractionally more than
-- it once each cell has been rounded to a whole pixel. UIGridLayout then fits
-- one fewer cell per row than FillDirectionMaxCells allows, which is what left
-- the last column's width as a black strip down the right of the Play page
-- while the row above it ran edge to edge.
--
-- AbsoluteSize is zero for the frame the grid is built in, and changes again on
-- every resize and whenever a scrollbar appears, so the split is recomputed
-- from the signal rather than read once at build time.
local function tileGrid(parent: Instance, options: TileGridOptions): Frame
	local grid = Instance.new("Frame")
	grid.Name = options.Name or "PortraitGrid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, options.Height or TILE_MIN_HEIGHT)
	grid.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		grid.LayoutOrder = nextOrder
	end
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Parent = grid

	local minimumHeight = options.MinHeight or TILE_MIN_HEIGHT
	local function apply()
		-- Width from the grid, height from the page it sits in: the grid is as
		-- wide as the cells may actually be, which is the parent minus whatever
		-- a visible scrollbar has taken, while only the parent knows how much
		-- page there is to divide up.
		local width = grid.AbsoluteSize.X
		local page = if parent:IsA("GuiObject") then parent.AbsoluteSize.Y else 0
		if width <= 0 then
			return
		end
		local gap = if width < 720 then TILE_GAP_COMPACT else TILE_GAP
		local columns = balancedColumns(options.Count, options.Columns)
		local rows = math.max(1, math.ceil(options.Count / columns))
		local cellWidth = math.max(1, math.floor((width - gap * (columns - 1)) / columns))
		-- Whole pixels that do not divide evenly go into the gutters, so the row
		-- reaches both edges instead of ending in a sliver of empty page.
		local slack = width - cellWidth * columns - gap * (columns - 1)
		local gutter = gap + (if columns > 1 then math.floor(slack / (columns - 1)) else 0)
		local cellHeight = options.Height
		if not cellHeight then
			local usable = page - gap * (rows - 1)
			local ceiling = math.max(
				minimumHeight,
				math.min(TILE_MAX_HEIGHT, math.floor(cellWidth * TILE_MAX_ASPECT))
			)
			cellHeight = math.clamp(math.floor(usable / rows), minimumHeight, ceiling)
		end
		layout.FillDirectionMaxCells = columns
		layout.CellPadding = UDim2.fromOffset(gutter, gap)
		layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
		grid.Size = UDim2.new(1, 0, 0, rows * cellHeight + (rows - 1) * gap)
	end

	apply()
	local sizeChanged = grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	grid.Destroying:Connect(function()
		sizeChanged:Disconnect()
	end)
	if parent:IsA("GuiObject") then
		local pageChanged = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
		grid.Destroying:Connect(function()
			pageChanged:Disconnect()
		end)
	end
	return grid
end

-- Square corners, by choice.
--
-- Every surface asked for its own radius and got one, which is how the menu came
-- to hold eight of them. Rather than pick a winner, the panels are square: it
-- suits a police interface better than rounded cards do, it removes the question
-- entirely, and it means the artwork on a role poster reaches the corner instead
-- of being clipped away from it.
--
-- The radius argument is kept so callers do not all have to change, and so this
-- is one line to reverse.
local SQUARE_SURFACES = true

corner = function(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, if SQUARE_SURFACES then 0 else radius)
	value.Parent = parent
end

stroke = function(parent: Instance, colour: Color3?, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = colour or COLOURS.Border
	value.Transparency = transparency or 0
	value.Parent = parent
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3?,
	bold: boolean?,
	truncate: Enum.TextTruncate?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextSize = size
	item.TextColor3 = colour or COLOURS.Text
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = truncate or Enum.TextTruncate.None
	item.Parent = parent
	return item
end

-- keepColour leaves the background alone and animates the scale only.
--
-- This captures the colour a control was built with and writes it back on every
-- hover and release, which is right for a button whose colour never changes and
-- wrong for one that carries a selected state: the bottom navigation set its
-- chosen tab to the accent and the first hover painted it straight back to the
-- unselected surface. Play looked selected purely because nobody had touched it
-- yet.
local function pressable(button: GuiButton, keepColour: boolean?)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local baseColour = button.BackgroundColor3
	local hoverColour = baseColour:Lerp(Color3.new(1, 1, 1), 0.06)
	local pressed = false
	local hovered = false
	local function motionEnabled(): boolean
		local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
		return not gui or gui:GetAttribute("RoleplayOSInterfaceMotion") ~= false
	end
	local function setPressed(value: boolean)
		pressed = value
		local targetScale = value and 0.97 or 1
		local targetColour = if value
			then baseColour
			else if hovered then hoverColour else baseColour
		if not motionEnabled() then
			scale.Scale = targetScale
			if not keepColour then
				button.BackgroundColor3 = targetColour
			end
			return
		end
		TweenService:Create(
			scale,
			TweenInfo.new(
				if value then 0.1 else 0.14,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out
			),
			{ Scale = targetScale }
		):Play()
		if not keepColour then
			TweenService:Create(
				button,
				TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundColor3 = targetColour }
			):Play()
		end
	end
	button.MouseEnter:Connect(function()
		hovered = true
		if not pressed then
			setPressed(false)
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		if not pressed then
			setPressed(false)
		end
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			setPressed(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			setPressed(false)
		end
	end)
end

-- plain drops the outline and the press animation. The role tiles' call to
-- action wants neither: it is a full width bar under a poster, where a stroke
-- reads as a second border against the card's own edge and a scale on press
-- makes the whole tile appear to wobble.
local function button(
	parent: Instance,
	label: string,
	primary: boolean?,
	plain: boolean?
): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = if primary then COLOURS.AccentFill else COLOURS.SurfaceRaised
	item.Font = Enum.Font.GothamBold
	item.Text = label
	item.TextSize = 13
	item.TextColor3 = COLOURS.Text
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.TextWrapped = false
	item.Selectable = true
	item.Size = UDim2.fromOffset(170, 40)
	item.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		item.LayoutOrder = nextOrder
	end
	corner(item, 8)
	if not plain then
		stroke(
			item,
			if primary then COLOURS.Accent else COLOURS.Border,
			if primary then 0.55 else 0
		)
		pressable(item)
	end
	item.Activated:Connect(function()
		if activeAudioFeedback then
			activeAudioFeedback:ButtonClick()
		end
	end)
	return item
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
		then
			child:Destroy()
		end
	end
	container:SetAttribute("RoleplayOSNextLayoutOrder", 0)
end

local function card(parent: Instance, height: number): Frame
	local item = Instance.new("Frame")
	item.BackgroundColor3 = COLOURS.Surface
	item.BorderSizePixel = 0
	item.Size = UDim2.new(1, 0, 0, height)
	item.Parent = parent
	if parent:IsA("ScrollingFrame") then
		local nextOrder = (parent:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		parent:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		item.LayoutOrder = nextOrder
	end
	corner(item, 9)
	stroke(item, COLOURS.Border, 0.18)
	local surfaceGradient = Instance.new("UIGradient")
	surfaceGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOURS.SurfaceRaised),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 27, 38)),
	})
	surfaceGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.34),
	})
	surfaceGradient.Rotation = 90
	surfaceGradient.Parent = item
	return item
end

-- Height of the name band across the bottom of a poster, and of the same band
-- when it also carries a line of detail under the name.
local POSTER_FOOTER_HEIGHT = 52
local POSTER_FOOTER_HEIGHT_DETAILED = 66
-- Between the poster and the action beneath it.
local POSTER_ACTION_GAP = 8

type PosterTileOptions = {
	Id: string,
	Image: string?,
	-- Shown in place of artwork that does not exist. A department mark reads as
	-- a card waiting for its picture; an empty rectangle reads as a card that
	-- failed to load one.
	Monogram: string?,
	Title: string,
	Detail: string?,
	Accent: Color3,
	ActionLabel: string,
	ActionMuted: boolean?,
	ActionHeight: number,
}

-- One tile for every poster grid in the menu.
--
-- Play and Civilian Jobs offer the same thing - somewhere to go and be - and
-- were two independent piles of layout code that had already drifted into a
-- wall of posters on one page and a list of rows on the other. Building both
-- from here is what stops that happening again.
--
-- Everything inside the cell is sized against the cell rather than in pixels,
-- so the grid can resize its cells on a viewport change without any of this
-- being rebuilt.
local function posterTile(parent: Instance, options: PosterTileOptions): (Frame, TextButton)
	local cell = Instance.new("Frame")
	cell.Name = "RoleCell_" .. options.Id
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Parent = parent
	-- The cell holds two things rather than one. The poster keeps the card
	-- styling; the cell itself is only a column, so the action below sits
	-- outside the artwork instead of on top of it.
	local poster = card(cell, 0)
	poster.Name = "RoleTile_" .. options.Id
	poster.Size = UDim2.new(1, 0, 1, -(options.ActionHeight + POSTER_ACTION_GAP))
	poster.ClipsDescendants = true
	local artwork = Instance.new("ImageLabel")
	artwork.Name = "RoleArtwork"
	artwork.BackgroundColor3 = COLOURS.SurfaceRaised
	artwork.BorderSizePixel = 0
	artwork.Position = UDim2.fromScale(0, 0)
	artwork.Size = UDim2.fromScale(1, 1)
	artwork.Image = options.Image or ""
	artwork.ImageColor3 = Color3.new(1, 1, 1)
	artwork.ScaleType = Enum.ScaleType.Crop
	artwork.ZIndex = 3
	artwork.Parent = poster
	-- Matches the card's own radius so the crop follows its corners.
	corner(artwork, 9)
	if not options.Image and options.Monogram then
		local monogram = text(artwork, options.Monogram, 34, options.Accent, true)
		monogram.AnchorPoint = Vector2.new(0.5, 0.5)
		monogram.Position = UDim2.fromScale(0.5, 0.4)
		monogram.Size = UDim2.fromScale(0.76, 0.34)
		monogram.TextXAlignment = Enum.TextXAlignment.Center
		monogram.TextScaled = true
		monogram.TextTransparency = 0.42
		monogram.ZIndex = 4
		local monogramBounds = Instance.new("UITextSizeConstraint")
		monogramBounds.MinTextSize = 14
		monogramBounds.MaxTextSize = 42
		monogramBounds.Parent = monogram
	end
	local artworkShade = Instance.new("Frame")
	artworkShade.Name = "ArtworkShade"
	artworkShade.BackgroundColor3 = COLOURS.Canvas
	artworkShade.BackgroundTransparency = 0.36
	artworkShade.BorderSizePixel = 0
	artworkShade.Position = artwork.Position
	artworkShade.Size = artwork.Size
	artworkShade.ZIndex = 5
	artworkShade.Parent = poster
	corner(artworkShade, 9)
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Color = ColorSequence.new(COLOURS.Canvas)
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.95),
		NumberSequenceKeypoint.new(0.58, 0.7),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	shadeGradient.Rotation = 90
	shadeGradient.Parent = artworkShade
	local footerHeight = if options.Detail
		then POSTER_FOOTER_HEIGHT_DETAILED
		else POSTER_FOOTER_HEIGHT
	local footer = Instance.new("Frame")
	footer.Name = "RoleFooter"
	footer.BackgroundColor3 = COLOURS.Surface
	footer.BackgroundTransparency = 0.12
	footer.BorderSizePixel = 0
	footer.Position = UDim2.new(0, 0, 1, -footerHeight)
	footer.Size = UDim2.new(1, 0, 0, footerHeight)
	footer.ZIndex = 10
	footer.Parent = poster
	corner(footer, 9)
	-- The whole band, because nothing shares it now. "Frontline Policing" and
	-- "Police Community Support Officer" were both losing their ends to a button
	-- parked on the same line.
	local title = text(footer, options.Title, 16, COLOURS.Text, true)
	title.Position = if options.Detail then UDim2.fromOffset(14, 6) else UDim2.fromOffset(14, 0)
	title.Size = if options.Detail then UDim2.new(1, -28, 0, 34) else UDim2.new(1, -28, 1, 0)
	title.TextWrapped = true
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 11
	if options.Detail then
		local detail = text(footer, options.Detail, 12, COLOURS.Muted)
		detail.Position = UDim2.fromOffset(14, 38)
		detail.Size = UDim2.new(1, -28, 0, 20)
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		detail.ZIndex = 11
	end
	local action = button(cell, options.ActionLabel, false, true)
	action.Name = "RoleAction_" .. options.Id
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.fromScale(0, 1)
	action.Size = UDim2.new(1, 0, 0, options.ActionHeight)
	-- Roblox's own interface font. This is the one control a player meets before
	-- they have agreed to anything the game does, so it reads better as part of
	-- the platform than as this game's own lettering.
	action.Font = Enum.Font.BuilderSansBold
	action.TextSize = 14
	action.TextColor3 = if options.ActionMuted then COLOURS.Muted else options.Accent
	return cell, action
end

local function input(parent: Instance, placeholder: string): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = COLOURS.Canvas
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = COLOURS.Muted
	item.Text = ""
	item.TextColor3 = COLOURS.Text
	item.TextSize = 15
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Size = UDim2.new(1, 0, 0, 46)
	item.Parent = parent
	corner(item, 9)
	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = COLOURS.Border
	inputStroke.Transparency = 0
	inputStroke.Parent = item
	item.Focused:Connect(function()
		TweenService:Create(
			inputStroke,
			TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Color = COLOURS.Accent, Thickness = 1.5 }
		):Play()
	end)
	item.FocusLost:Connect(function()
		TweenService:Create(
			inputStroke,
			TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Color = COLOURS.Border, Thickness = 1 }
		):Play()
	end)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = item
	return item
end

return {
	colours = COLOURS,
	civilianJobRoleIds = CIVILIAN_JOB_ROLE_IDS,
	roleDisplayOrder = ROLE_DISPLAY_ORDER,
	roleTileImageUri = roleTileImageUri,
	rolePresentation = rolePresentation,
	portraitPreview = portraitPreview,
	corner = corner,
	stroke = stroke,
	balancedColumns = balancedColumns,
	tileGrid = tileGrid,
	text = text,
	pressable = pressable,
	button = button,
	clear = clear,
	card = card,
	posterTile = posterTile,
	input = input,
}
