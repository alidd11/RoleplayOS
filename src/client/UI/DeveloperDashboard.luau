--!strict

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local TooltipSystem = require(script.Parent.TooltipSystem)
local AssetPreloader = require(script.Parent.Parent.Systems.AssetPreloader)
local AudioFeedback = require(script.Parent.Parent.Systems.AudioFeedback)

-- Roblox's unified top bar is a 36px band on an unscaled desktop client and
-- carries 32px square icon controls inside it, leaving a 2px gutter above and
-- below. The world menu toggle mirrors those proportions so it reads as one of
-- the native controls; the responsive binding rescales them whenever Roblox
-- reports a taller band (touch, high DPI, VR).
local NATIVE_BAND_HEIGHT = 36
local NATIVE_CONTROL_SIZE = 32
-- Gap Roblox leaves between adjacent top-bar clusters.
local NATIVE_CONTROL_GAP = 8
-- Beyond this the page stops growing and centres instead. A line of text
-- stretched the full width of a large monitor is harder to read, not easier.
local MAXIMUM_CONTENT_WIDTH = 1680
-- How many top-bar heights Roblox's own control cluster spans: the logo, then
-- the pill holding the menu, chat and microphone buttons. Used only as a floor
-- when Roblox reports no inset of its own, so our controls are never drawn
-- underneath its own.

local App = {}
local activeAudioFeedback: any = nil
local activeMountGui: ScreenGui? = nil
local COLOURS = {
	Canvas = Color3.fromRGB(17, 22, 40),
	Sidebar = Color3.fromRGB(19, 25, 43),
	Surface = Color3.fromRGB(25, 32, 52),
	SurfaceRaised = Color3.fromRGB(34, 43, 69),
	Border = Color3.fromRGB(65, 78, 112),
	Text = Color3.fromRGB(240, 244, 251),
	Muted = Color3.fromRGB(174, 184, 201),
	Accent = Color3.fromRGB(91, 156, 255),
	-- Fill for primary buttons. The accent is a good colour for text, strokes and
	-- indicators against the dark canvas, and a poor one behind white label text:
	-- that pairing measures about two and a half to one, well under the four and
	-- a half a body label needs. This is the same hue, dark enough to carry it.
	AccentFill = Color3.fromRGB(31, 95, 208),
	AccentSoft = Color3.fromRGB(25, 51, 88),
	Success = Color3.fromRGB(84, 211, 142),
	Warning = Color3.fromRGB(245, 188, 78),
	Danger = Color3.fromRGB(244, 104, 112),
}

local ROLE_PRESENTATION = {
	Civilian = { Icon = "CIV", Colour = Color3.fromRGB(91, 156, 255), Label = "PUBLIC LIFE" },
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

local ROLE_TILE_ASSET_IDS = {
	Police = "rbxassetid://108952619314292",
	Ambulance = "rbxassetid://82458182331259",
	Fire = "rbxassetid://129231885538259",
	Civilian = "rbxassetid://90347985847798",
	Highways = "rbxassetid://113273816836442",
	Transport = "rbxassetid://123377791263414",
	RoyaltyMail = "rbxassetid://132576980521526",
	Cashier = "rbxassetid://104308905863825",
	ComingSoon = "rbxassetid://112525022208467",
}

local function roleTileImageUri(role: any): string?
	local assetId = ROLE_TILE_ASSET_IDS[role.DepartmentId] or ROLE_TILE_ASSET_IDS[role.Id]
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
	viewport.BackgroundColor3 = Color3.fromRGB(28, 36, 49)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.6, -0.45, -1)
	viewport.Parent = parent
	corner(viewport, 12)
	stroke(viewport, accent, 0.68)

	local wash = Instance.new("UIGradient")
	wash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 75, 99)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(27, 35, 48)),
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

local function pressable(button: GuiButton)
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
			button.BackgroundColor3 = targetColour
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
		TweenService:Create(
			button,
			TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundColor3 = targetColour }
		):Play()
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

local function button(parent: Instance, label: string, primary: boolean?): TextButton
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
	stroke(item, if primary then COLOURS.Accent else COLOURS.Border, if primary then 0.55 else 0)
	pressable(item)
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 35, 48)),
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
	artwork.BackgroundColor3 = Color3.fromRGB(28, 38, 68)
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
	artworkShade.BackgroundColor3 = Color3.fromRGB(10, 16, 34)
	artworkShade.BackgroundTransparency = 0.36
	artworkShade.BorderSizePixel = 0
	artworkShade.Position = artwork.Position
	artworkShade.Size = artwork.Size
	artworkShade.ZIndex = 5
	artworkShade.Parent = poster
	corner(artworkShade, 9)
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Color = ColorSequence.new(Color3.fromRGB(8, 14, 32))
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
	footer.BackgroundColor3 = Color3.fromRGB(13, 20, 43)
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
	local action = button(cell, options.ActionLabel, false)
	action.Name = "RoleAction_" .. options.Id
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.fromScale(0, 1)
	action.Size = UDim2.new(1, 0, 0, options.ActionHeight)
	action.TextSize = 12
	action.TextColor3 = if options.ActionMuted then COLOURS.Muted else options.Accent
	local actionStroke = action:FindFirstChildOfClass("UIStroke")
	if actionStroke then
		actionStroke.Color = options.Accent
	end
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

function App.mount(context: any): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if activeMountGui and activeMountGui.Parent then
		return activeMountGui
	end

	local function removeStaleLayer(name: string)
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	-- A Rojo sync or a client-script restart can rerun mount without resetting
	-- PlayerGui. Remove only the exact RoleplayOS layers so old dashboards cannot
	-- stack on top of the new one while unrelated HUD systems remain untouched.
	removeStaleLayer("RoleplayOS")
	removeStaleLayer("RoleplayOSMenuToggle")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOS"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	-- The visual canvas deliberately renders behind Roblox's top bar and device
	-- cutouts. Interactive content is positioned inside the safe region by the
	-- responsive binding below, so the experience stays full bleed without
	-- competing with native Roblox controls.
	gui.IgnoreGuiInset = true
	-- Set ScreenInsets after the legacy IgnoreGuiInset compatibility property;
	-- assigning the legacy property may otherwise rewrite the inset mode.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the gameplay HUD (minimap, needs, progression) which would otherwise
	-- draw over the menu, but below the controls overlay at 90.
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	activeMountGui = gui
	gui.Destroying:Connect(function()
		if activeMountGui == gui then
			activeMountGui = nil
		end
	end)
	local configuration = context.Configuration
	if not configuration then
		local roleplayOS = ReplicatedStorage:WaitForChild("RoleplayOS")
		local configFolder = roleplayOS:WaitForChild("Config")
		configuration = require(configFolder:WaitForChild("Config"))
	end
	local preloader = AssetPreloader.new({ Configuration = configuration })
	local ModalSystem = require(script.Parent.ModalSystem)
	local sharedModalSystem = context.Systems and context.Systems.ModalSystem
	local modalSystem = sharedModalSystem or ModalSystem.new(context)
	local ownsModalSystem = sharedModalSystem == nil
	local CharacterCreator = require(script.Parent.CharacterCreator)
	local characterCreator = CharacterCreator.new(context)
	local sharedAudioFeedback = context.Systems and context.Systems.AudioFeedback
	local audioFeedback: any = sharedAudioFeedback
	local ownsAudioFeedback = false
	if not audioFeedback then
		ownsAudioFeedback = true
		local audioOk, audioResult = pcall(AudioFeedback.new, context)
		if audioOk then
			audioFeedback = audioResult
		else
			warn("[RoleplayOS] Optional audio feedback unavailable: " .. tostring(audioResult))
		end
	end
	activeAudioFeedback = audioFeedback
	gui.Destroying:Connect(function()
		preloader:Destroy()
		characterCreator:Destroy()
		if ownsModalSystem then
			modalSystem:Destroy()
		end
		if ownsAudioFeedback and audioFeedback then
			audioFeedback:Destroy()
		end
		if activeAudioFeedback == audioFeedback then
			activeAudioFeedback = nil
		end
	end)

	local menuToggleGui = Instance.new("ScreenGui")
	menuToggleGui.Name = "RoleplayOSMenuToggle"
	menuToggleGui:SetAttribute("RoleplayOSManagedUI", true)
	menuToggleGui.ResetOnSpawn = false
	-- Roblox's TopbarSafeInsets rectangle begins immediately after the native
	-- logo/chat/voice cluster and changes with voice chat, device orientation,
	-- safe areas and CoreGui visibility. Mounting the button in that rectangle
	-- makes its (0, 0) origin the first genuinely available top-bar position;
	-- estimating the cluster width in gameplay coordinates caused the mobile
	-- button to drift down and overlap the radio/header.
	-- This is an interactive control, so keep it inside Roblox's reported
	-- top-bar safe area. The dashboard canvas itself may remain full-bleed, but
	-- a guessed pixel offset is not stable across phones, notches, voice chat,
	-- or hidden CoreGui controls.
	menuToggleGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	menuToggleGui.ClipToDeviceSafeArea = true
	-- Keep the control above the menu canvas as well as the gameplay HUD. It is
	-- both the opener and the always-available close/back action.
	menuToggleGui.DisplayOrder = 60
	menuToggleGui.Parent = gui.Parent
	-- Keep a compact text label, but place it in the same top row as Roblox's
	-- native controls. A wide desktop pill or a second-row mobile button makes
	-- the experience look like it has two competing navigation systems.
	local menuToggle = Instance.new("TextButton")
	menuToggle.Name = "OpenMenu"
	menuToggle.Size = UDim2.fromOffset(64, NATIVE_CONTROL_SIZE)
	menuToggle.BackgroundColor3 = Color3.fromRGB(27, 31, 58)
	menuToggle.BackgroundTransparency = 0.06
	menuToggle.BorderSizePixel = 0
	menuToggle.AutoButtonColor = true
	menuToggle.Text = "MENU"
	menuToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	menuToggle.TextSize = 14
	menuToggle.Font = Enum.Font.GothamBold
	menuToggle.Visible = false
	menuToggle.Selectable = true
	menuToggle.Parent = menuToggleGui
	-- Match the final topbar layout from the first frame. Starting at (8, 8)
	-- caused a visible hop before the responsive binding corrected it, so this
	-- mirrors the centred position the binding settles on.
	menuToggle.Position = UDim2.fromOffset(NATIVE_CONTROL_GAP, 11)
	local menuToggleCorner = Instance.new("UICorner")
	menuToggleCorner.CornerRadius = UDim.new(0, NATIVE_CONTROL_SIZE / 2)
	menuToggleCorner.Parent = menuToggle
	local menuToggleStroke = Instance.new("UIStroke")
	menuToggleStroke.Color = Color3.fromRGB(96, 106, 171)
	menuToggleStroke.Transparency = 0.32
	menuToggleStroke.Parent = menuToggle
	-- A dedicated non-interactive backdrop extends above the legacy GUI origin.
	-- This keeps the visual treatment full bleed even on clients which still
	-- apply the historical top-bar offset to an inset-free ScreenGui.
	local bleedBackdrop = Instance.new("Frame")
	bleedBackdrop.Name = "FullBleedBackdrop"
	bleedBackdrop.BackgroundColor3 = COLOURS.Canvas
	bleedBackdrop.BorderSizePixel = 0
	bleedBackdrop.ZIndex = -10
	bleedBackdrop.Parent = gui
	local bleedGradient = Instance.new("UIGradient")
	bleedGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 35, 70)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(28, 25, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 21, 42)),
	})
	bleedGradient.Rotation = 28
	bleedGradient.Parent = bleedBackdrop

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.Name = "Root"
	root.BackgroundColor3 = COLOURS.Canvas
	root.BorderSizePixel = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 48, 96)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(35, 32, 78)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 29, 58)),
	})
	gradient.Rotation = 28
	gradient.Parent = root
	-- Keep the canvas alive without turning it into a screensaver. Two oversized,
	-- low-contrast washes drift behind the UI so the empty areas feel intentional
	-- and the blue/purple brand treatment remains visible when artwork is sparse.
	local ambientBlue = Instance.new("Frame")
	ambientBlue.Name = "AmbientBlue"
	ambientBlue.AnchorPoint = Vector2.new(0.5, 0.5)
	ambientBlue.Position = UDim2.fromScale(0.12, 0.2)
	ambientBlue.Size = UDim2.fromScale(0.8, 0.9)
	ambientBlue.BackgroundColor3 = Color3.fromRGB(32, 92, 190)
	ambientBlue.BackgroundTransparency = 0.94
	ambientBlue.BorderSizePixel = 0
	ambientBlue.ZIndex = -1
	ambientBlue.Parent = root
	local ambientBlueGradient = Instance.new("UIGradient")
	ambientBlueGradient.Color = ColorSequence.new(Color3.fromRGB(45, 118, 235))
	ambientBlueGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.6, 0.74),
		NumberSequenceKeypoint.new(1, 1),
	})
	ambientBlueGradient.Rotation = 24
	ambientBlueGradient.Parent = ambientBlue
	local ambientPurple = Instance.new("Frame")
	ambientPurple.Name = "AmbientPurple"
	ambientPurple.AnchorPoint = Vector2.new(0.5, 0.5)
	ambientPurple.Position = UDim2.fromScale(0.9, 0.78)
	ambientPurple.Size = UDim2.fromScale(0.72, 0.82)
	ambientPurple.BackgroundColor3 = Color3.fromRGB(126, 78, 220)
	ambientPurple.BackgroundTransparency = 0.95
	ambientPurple.BorderSizePixel = 0
	ambientPurple.ZIndex = -1
	ambientPurple.Parent = root
	local ambientPurpleGradient = Instance.new("UIGradient")
	ambientPurpleGradient.Color = ColorSequence.new(Color3.fromRGB(151, 94, 238))
	ambientPurpleGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.62, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	ambientPurpleGradient.Rotation = 202
	ambientPurpleGradient.Parent = ambientPurple

	local loadingOverlay = Instance.new("Frame")
	loadingOverlay.Name = "LoadingExperience"
	loadingOverlay.Size = UDim2.fromScale(1, 1)
	loadingOverlay.BackgroundColor3 = COLOURS.Canvas
	loadingOverlay.BorderSizePixel = 0
	loadingOverlay.ZIndex = 100
	loadingOverlay.Parent = gui
	-- A low-contrast edge wash suggests emergency lighting without putting two
	-- obvious pulsing shapes behind the title. The centre remains calm and legible.
	for index, definition in
		{
			{ Colour = Color3.fromRGB(25, 76, 150), Left = true, Delay = 0 },
			{ Colour = Color3.fromRGB(120, 31, 45), Left = false, Delay = 1.1 },
		}
	do
		local glow = Instance.new("Frame")
		glow.Name = if index == 1 then "BlueEdgeWash" else "RedEdgeWash"
		glow.AnchorPoint = Vector2.new(if definition.Left then 0 else 1, 0)
		glow.Position = UDim2.fromScale(if definition.Left then 0 else 1, 0)
		glow.Size = UDim2.fromScale(0.42, 1)
		glow.BackgroundColor3 = definition.Colour
		glow.BackgroundTransparency = 0
		glow.BorderSizePixel = 0
		glow.ZIndex = 100
		glow.Parent = loadingOverlay
		local edgeGradient = Instance.new("UIGradient")
		edgeGradient.Color = ColorSequence.new(definition.Colour)
		edgeGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.84),
			NumberSequenceKeypoint.new(1, 1),
		})
		edgeGradient.Rotation = if definition.Left then 0 else 180
		edgeGradient.Parent = glow
		-- A restrained static wash reads as emergency-service branding without
		-- flashing behind text or spending render time while this overlay is hidden.
	end
	local loadingTitle =
		text(loadingOverlay, "EMERGENCY RESPONSE: PORTSMOUTH", 25, COLOURS.Text, true)
	loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingTitle.Position = UDim2.fromScale(0.5, 0.44)
	loadingTitle.Size = UDim2.new(1, -48, 0, 38)
	loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
	loadingTitle.ZIndex = 101
	local loadingStatus = text(loadingOverlay, "Preparing your profile…", 14, COLOURS.Muted)
	loadingStatus.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingStatus.Position = UDim2.fromScale(0.5, 0.51)
	loadingStatus.Size = UDim2.new(1, -48, 0, 26)
	loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
	loadingStatus.ZIndex = 101
	local loadingBar = Instance.new("Frame")
	loadingBar.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingBar.Position = UDim2.fromScale(0.5, 0.57)
	loadingBar.Size = UDim2.fromOffset(260, 3)
	loadingBar.BackgroundColor3 = COLOURS.Border
	loadingBar.BorderSizePixel = 0
	loadingBar.ZIndex = 101
	loadingBar.Parent = loadingOverlay
	local loadingFill = Instance.new("Frame")
	loadingFill.Name = "ProgressBar"
	loadingFill.Size = UDim2.fromScale(0, 1)
	loadingFill.BackgroundColor3 = COLOURS.Accent
	loadingFill.BorderSizePixel = 0
	loadingFill.ZIndex = 102
	loadingFill.Parent = loadingBar
	local preloaderInteractive = false
	local loadingFinished = false
	local continueLoading: TextButton? = nil
	local preloaderProgressConnection: RBXScriptConnection? = nil
	local preloaderPhaseConnection: RBXScriptConnection? = nil
	local function interfaceMotionEnabled(): boolean
		local settings = context.Controllers.SettingsController:Get()
		return not settings or settings.InterfaceMotion ~= false
	end
	task.spawn(function()
		if not interfaceMotionEnabled() then
			return
		end
		TweenService:Create(
			gradient,
			TweenInfo.new(18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Offset = Vector2.new(0.28, 0.08) }
		):Play()
		TweenService:Create(
			ambientBlue,
			TweenInfo.new(16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.2, 0.28) }
		):Play()
		TweenService:Create(
			ambientPurple,
			TweenInfo.new(20, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.78, 0.68) }
		):Play()
	end)

	local function updateLoadingStatus(progress: number)
		local statusText = if progress < 0.2
			then "Connecting to server…"
			elseif progress < 0.4 then "Loading vehicles…"
			elseif progress < 0.6 then "Loading equipment…"
			elseif progress < 0.8 then "Preparing menu…"
			elseif progress < 1 then "Finalizing…"
			else "Ready"
		loadingStatus.Text = statusText
		loadingFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	local function finishLoading(force: boolean?)
		if loadingFinished then
			return
		end
		if not force and not preloaderInteractive then
			return
		end
		loadingFinished = true
		if preloaderProgressConnection then
			preloaderProgressConnection:Disconnect()
			preloaderProgressConnection = nil
		end
		if preloaderPhaseConnection then
			preloaderPhaseConnection:Disconnect()
			preloaderPhaseConnection = nil
		end
		preloaderInteractive = true
		if continueLoading then
			continueLoading:Destroy()
			continueLoading = nil
		end
		loadingFill.Size = UDim2.fromScale(1, 1)
		loadingStatus.Text = "Ready"
		loadingStatus.TextColor3 = COLOURS.Muted
		loadingOverlay.BackgroundTransparency = 1
		loadingOverlay.Visible = false
		gui.Enabled = true
		root.Visible = true
	end
	preloaderProgressConnection = preloader.onProgress.Event:Connect(updateLoadingStatus)
	preloaderPhaseConnection = preloader.onPhaseChange.Event:Connect(function(phase: string)
		if loadingFinished then
			return
		end
		if phase == "interactive" then
			preloaderInteractive = true
			loadingOverlay.BackgroundTransparency = 0.6
			continueLoading = button(loadingOverlay, "Continue", true)
			continueLoading.AnchorPoint = Vector2.new(0.5, 1)
			continueLoading.Position = UDim2.new(0.5, 0, 1, -30)
			continueLoading.Size = UDim2.fromOffset(190, 44)
			continueLoading.ZIndex = 103
			continueLoading.Activated:Connect(function()
				if continueLoading then
					continueLoading:Destroy()
					continueLoading = nil
				end
				finishLoading(true)
				if audioFeedback then
					audioFeedback:ButtonClick()
				end
			end)
		elseif phase == "complete" then
			finishLoading()
		end
	end)

	-- Retrying is the thing that actually fixes this, and there was no way to do
	-- it short of rejoining the server.
	local retryLoading = button(loadingOverlay, "Retry", true)
	retryLoading.AnchorPoint = Vector2.new(0.5, 1)
	retryLoading.Position = UDim2.new(0.5, 0, 1, -82)
	retryLoading.Size = UDim2.fromOffset(190, 44)
	retryLoading.ZIndex = 103
	retryLoading.Visible = false
	retryLoading.Activated:Connect(function()
		retryLoading.Active = false
		retryLoading.Text = "Retrying…"
		loadingStatus.Text = "Reconnecting to the server…"
		loadingStatus.TextColor3 = COLOURS.Muted
		task.spawn(function()
			local response = context.Controllers.StartMenuController:Refresh()
			retryLoading.Text = "Retry"
			retryLoading.Active = true
			if response.Success then
				finishLoading()
				return
			end
			loadingStatus.Text = "Could not reach the server."
			loadingStatus.TextColor3 = COLOURS.Danger
			if audioFeedback then
				audioFeedback:Error()
			end
			-- Does not force-finish. A failed retry means the server is still
			-- unreachable, so the honest state is the retry screen staying up with
			-- the button re-enabled, not a menu the player can open with no working
			-- session behind it. Silently promoting past a confirmed failure here is
			-- what caused a player to be dropped into gameplay immediately after
			-- being told the connection failed.
		end)
	end)
	preloader:Start()

	-- Safety net only, not a substitute for the preloader actually finishing.
	--
	-- AssetPreloader now catches its own errors and guarantees it reaches
	-- "interactive"/"complete" even when preloading throws, so this should rarely
	-- if ever fire. It exists for the one case that isn't the preloader's fault:
	-- something else in startup hangs before Start() even runs. Fifteen seconds is
	-- long enough that it will not pre-empt a legitimate slow load, and it never
	-- fires while the retry screen is already up and offering the player a real,
	-- honest way forward.
	task.delay(15, function()
		if not loadingOverlay or not loadingOverlay.Parent or not loadingOverlay.Visible then
			return
		end
		if retryLoading.Visible then
			return
		end
		warn(
			"[RoleplayOS] Startup exceeded 15s without the asset preloader reporting "
				.. "interactive. Promoting to interactive without confirmation; this "
				.. "indicates a real startup bug and should be investigated rather than "
				.. "relied on."
		)
		finishLoading(true)
	end)

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 250, 1, 0)
	sidebar.BackgroundColor3 = COLOURS.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = root
	-- Divides the bar from the content beneath it. Authored for a sidebar down the
	-- left, where it was a hairline on the right edge; in the bar layout that put
	-- a one pixel tick in the top corner and left the bar with no edge at all.
	local sidebarStroke = Instance.new("Frame")
	sidebarStroke.AnchorPoint = Vector2.new(0, 1)
	sidebarStroke.Position = UDim2.fromScale(0, 1)
	sidebarStroke.Size = UDim2.new(1, 0, 0, 1)
	sidebarStroke.BackgroundColor3 = COLOURS.Border
	sidebarStroke.BorderSizePixel = 0
	sidebarStroke.Parent = sidebar

	local brand = text(sidebar, game.Name, 21, COLOURS.Text, true)
	-- The Roblox top bar already identifies the experience. Repeating the game
	-- name inside the dashboard consumed the most valuable part of the compact
	-- header and pushed the useful announcement down.
	brand.Visible = false
	brand.Position = UDim2.fromOffset(26, 20)
	brand.Size = UDim2.new(1, -52, 0, 42)
	brand.TextSize = 17
	brand.TextTruncate = Enum.TextTruncate.None
	brand.TextWrapped = true
	local brandTextConstraint = Instance.new("UITextSizeConstraint")
	brandTextConstraint.MinTextSize = 10
	brandTextConstraint.MaxTextSize = 17
	brandTextConstraint.Parent = brand

	local navigation = Instance.new("Frame")
	navigation.BackgroundTransparency = 1
	navigation.Position = UDim2.fromOffset(18, 112)
	navigation.Size = UDim2.new(1, -36, 0, 190)
	navigation.Parent = sidebar
	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 7)
	navLayout.Parent = navigation
	-- The old Portsmouth experience kept the product navigation at the bottom,
	-- where it stayed available while the large role artwork carried the page.
	-- Keep the original navigation instance as the responsive source of truth,
	-- but render the player-facing controls in a dedicated dock below.
	local bottomDock = Instance.new("Frame")
	bottomDock.Name = "BottomNavigation"
	bottomDock.AnchorPoint = Vector2.new(0.5, 1)
	bottomDock.BackgroundColor3 = Color3.fromRGB(20, 25, 49)
	bottomDock.BackgroundTransparency = 0.08
	bottomDock.BorderSizePixel = 0
	bottomDock.ZIndex = 20
	bottomDock.Parent = root
	corner(bottomDock, 16)
	stroke(bottomDock, COLOURS.Border, 0.12)
	local bottomDockPadding = Instance.new("UIPadding")
	bottomDockPadding.PaddingLeft = UDim.new(0, 8)
	bottomDockPadding.PaddingRight = UDim.new(0, 8)
	bottomDockPadding.PaddingTop = UDim.new(0, 8)
	bottomDockPadding.PaddingBottom = UDim.new(0, 8)
	bottomDockPadding.Parent = bottomDock
	local bottomDockLayout = Instance.new("UIListLayout")
	bottomDockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bottomDockLayout.FillDirection = Enum.FillDirection.Horizontal
	bottomDockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomDockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bottomDockLayout.Padding = UDim.new(0, 8)
	bottomDockLayout.Parent = bottomDock

	local announcementMessages = {
		"Please read the rules before entering Portsmouth",
		"Choose a role, then report for duty",
		"Need help? Open Help for controls and guides",
		"Play fair, keep scenes realistic, and respect other players",
	}
	local announcementIndex = 1
	local announcement =
		text(root, announcementMessages[announcementIndex], 12, COLOURS.Muted, true)
	announcement.Name = "Announcement"
	announcement.AnchorPoint = Vector2.new(0.5, 0)
	announcement.BackgroundColor3 = Color3.fromRGB(31, 25, 48)
	announcement.BackgroundTransparency = 0.12
	announcement.BorderSizePixel = 0
	announcement.TextXAlignment = Enum.TextXAlignment.Center
	announcement.Size = UDim2.fromOffset(420, 28)
	announcement.ZIndex = 18
	announcement.Parent = root
	corner(announcement, 14)
	stroke(announcement, Color3.fromRGB(126, 91, 189), 0.5)
	task.spawn(function()
		while announcement.Parent do
			task.wait(10)
			if not announcement.Parent then
				break
			end
			announcementIndex = announcementIndex % #announcementMessages + 1
			announcement.Text = announcementMessages[announcementIndex]
		end
	end)

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(250, 0)
	content.Size = UDim2.new(1, -250, 1, 0)
	content.Parent = root

	-- A thin status strip where a title block used to be.
	--
	-- The block spent 76 pixels restating the tab the player had just pressed -
	-- "Play. Choose who you want to be today." - and on a phone it was already
	-- hidden, so the space was dead on the device with least of it. The one thing
	-- in it worth keeping is whether the server is actually up, which is now the
	-- whole strip. pageTitle and pageDescription stay as instances because every
	-- render function sets them; they are simply never shown.
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(44, 16)
	header.Size = UDim2.new(1, -88, 0, 24)
	header.Parent = content
	local pageTitle = text(header, "Play", 30, COLOURS.Text, true)
	pageTitle.Size = UDim2.new(1, -220, 0, 40)
	pageTitle.Visible = false
	local pageDescription = text(header, "Choose who you want to be today.", 14, COLOURS.Muted)
	pageDescription.Position = UDim2.fromOffset(0, 41)
	pageDescription.Size = UDim2.new(1, -220, 0, 24)
	pageDescription.Visible = false
	local status = text(header, "●  CONNECTING", 11, COLOURS.Warning, true)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.fromScale(1, 0)
	status.Size = UDim2.fromOffset(190, 24)
	status.TextXAlignment = Enum.TextXAlignment.Right

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(44, 48)
	scroll.Size = UDim2.new(1, -88, 1, -76)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = COLOURS.Border
	scroll.Parent = content
	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Padding = UDim.new(0, 14)
	flow.Parent = scroll

	local menuData: any = nil
	local selectedStoreCategory: string? = nil
	-- Seeded from the character the player last used, which the server already
	-- sends and nothing read. Without it a returning player picks the same
	-- character again on every join before they can do anything else.
	local selectedCharacterId: string? = nil
	-- Civilian is the only team with character creation. Other teams use the
	-- player's existing character and change uniform/loadout through locker-room
	-- clickers, so their team selection should never open the character editor.
	local selectedTeamId: string? = nil
	-- The menu gates only the first entry. Once the server has accepted a
	-- character or duty entry, a refreshed menu snapshot must not trap the player.
	local hasEnteredWorld = false
	local dismissToWorld: () -> ()
	TooltipSystem:Init(context)
	local function updateMenuToggleAppearance(isOpen: boolean)
		menuToggle.Text = "MENU"
		menuToggle.TextTruncate = Enum.TextTruncate.AtEnd
		menuToggle:SetAttribute("AccessibilityLabel", if isOpen then "Close menu" else "Open menu")
	end
	local function setMenuOpen(isOpen: boolean)
		playerGui:SetAttribute("RoleplayOSMenuOpen", isOpen)
		menuToggle.Visible = true
		updateMenuToggleAppearance(isOpen)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not isOpen)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not isOpen)
		end)
	end
	playerGui:GetAttributeChangedSignal("RoleplayOSMenuOpen"):Connect(function()
		updateMenuToggleAppearance(playerGui:GetAttribute("RoleplayOSMenuOpen") == true)
	end)
	local function openFromWorld()
		setMenuOpen(true)
		gui.Enabled = true
		context.Controllers.StartMenuController:Refresh()
		root.Position = UDim2.fromOffset(0, 0)
		root.BackgroundTransparency = 0
		if interfaceMotionEnabled() then
			root.Position = UDim2.fromOffset(0, 8)
			root.BackgroundTransparency = 1
			TweenService:Create(
				root,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0 }
			):Play()
		end
	end

	menuToggle.Activated:Connect(function()
		if playerGui:GetAttribute("RoleplayOSMenuOpen") == true and gui.Enabled then
			dismissToWorld()
		else
			openFromWorld()
		end
		if audioFeedback then
			audioFeedback:ButtonClick()
		end
	end)

	local function showCharacterCreationModal(previousError: string?)
		local form = Instance.new("Frame")
		form.Name = "CharacterCreationForm"
		form.Size = UDim2.fromScale(1, 0)
		form.AutomaticSize = Enum.AutomaticSize.Y
		form.BackgroundTransparency = 1
		form.BorderSizePixel = 0
		local creationFlow = Instance.new("UIListLayout")
		creationFlow.SortOrder = Enum.SortOrder.LayoutOrder
		creationFlow.Padding = UDim.new(0, 8)
		creationFlow.Parent = form
		local copy = text(
			form,
			"Name your civilian and set a date of birth. You choose how they look next, "
				.. "and that look is set once.",
			13,
			COLOURS.Muted
		)
		copy.LayoutOrder = 1
		copy.Size = UDim2.new(1, 0, 0, 34)
		copy.TextWrapped = true
		local firstName = input(form, "First name")
		firstName.LayoutOrder = 2
		local lastName = input(form, "Last name")
		lastName.LayoutOrder = 3
		local dateOfBirth = input(form, "Date of birth  ·  YYYY-MM-DD")
		dateOfBirth.LayoutOrder = 4
		local errorLabel = text(form, previousError or "", 12, COLOURS.Danger)
		errorLabel.LayoutOrder = 5
		errorLabel.Size = UDim2.new(1, 0, 0, 28)
		errorLabel.TextWrapped = true
		modalSystem:Open({
			Title = "Create Civilian Character",
			Body = form,
			Actions = {
				{ Label = "Cancel", Primary = false, Callback = function() end },
				{
					Label = "Create civilian character",
					Primary = true,
					Callback = function()
						local response = context.Controllers.CharacterController:Create({
							FirstName = firstName.Text,
							LastName = lastName.Text,
							DateOfBirth = dateOfBirth.Text,
						})
						if response.Success then
							if audioFeedback then
								audioFeedback:Success()
							end
							context.Controllers.StartMenuController:Refresh()
							-- Straight into the creator while the character is new
							-- and its appearance is still free to author. Returning
							-- to the menu first would leave the one unpaid edit
							-- behind a button most players would never press.
							local newId = response.Data and response.Data.CharacterId
							if type(newId) == "string" then
								task.defer(function()
									characterCreator:Open(newId, function()
										context.Controllers.StartMenuController:Refresh()
									end)
								end)
							end
						else
							task.defer(function()
								showCharacterCreationModal(response.Message)
							end)
						end
					end,
				},
			},
			Width = 460,
			Dismissable = true,
		})
	end

	local function showDutySelection(role: any, dutyProfile: any)
		local body = Instance.new("Frame")
		body.Name = "DutySpawnOptions"
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = body
		local copy =
			text(body, "Choose exactly where you want to report for duty.", 13, COLOURS.Muted)
		copy.LayoutOrder = 1
		copy.Size = UDim2.new(1, 0, 0, 30)
		copy.TextWrapped = true
		local spawnOptions = if type(role.Spawns) == "table" then role.Spawns else {}
		local validSpawnCount = 0
		for _, spawnOption in spawnOptions do
			if type(spawnOption) ~= "table" then
				continue
			end
			local spawnId = if type(spawnOption.SpawnId) == "string"
				then spawnOption.SpawnId
				else ""
			if spawnId == "" then
				continue
			end
			local stationName = if type(spawnOption.StationName) == "string"
					and spawnOption.StationName ~= ""
				then spawnOption.StationName
				else "Station"
			local displayName = if type(spawnOption.DisplayName) == "string"
					and spawnOption.DisplayName ~= ""
				then spawnOption.DisplayName
				else string.gsub(spawnId, "_", " ")
			local choiceText = stationName .. "  ·  " .. displayName
			local choice = button(body, choiceText, false)
			TooltipSystem:Attach(choice, choiceText)
			validSpawnCount += 1
			choice.LayoutOrder = 10 + validSpawnCount
			choice.Size = UDim2.new(1, 0, 0, 48)
			choice.Activated:Connect(function()
				choice.Text = "Starting duty…"
				local response = context.Controllers.DutyController:Begin({
					DutyProfileId = dutyProfile.ProfileId,
					RoleId = role.Id,
					StationId = spawnOption.StationId,
					SpawnId = spawnId,
				})
				if response.Success then
					if audioFeedback then
						audioFeedback:Success()
					end
					modalSystem:Close()
					dismissToWorld()
				else
					choice.Text = choiceText
				end
			end)
		end
		if validSpawnCount == 0 then
			modalSystem:Open({
				Title = "Duty unavailable",
				Body = "No valid spawn point is configured for this role.",
				Actions = { { Label = "Close", Primary = true, Callback = function() end } },
				Width = 460,
				Dismissable = true,
			})
			return
		end
		if audioFeedback then
			audioFeedback:PanelOpen()
		end
		modalSystem:Open({
			Title = "Start " .. role.Name,
			Body = body,
			Actions = { { Label = "Cancel", Primary = false, Callback = function() end } },
			Width = 480,
			Dismissable = true,
		})
	end

	local renderPlay: () -> ()
	local function activateRole(role: any)
		if role.Locked then
			if role.Action == "PromptGamepass" then
				local gamepassId = tonumber(role.GamepassId)
				if not gamepassId or gamepassId <= 0 then
					context.Controllers.NotificationController:Show(
						"This pass is not available for purchase yet.",
						"Pass unavailable"
					)
					if audioFeedback then
						audioFeedback:Error()
					end
					return
				end
				local prompted, promptError =
					context.Controllers.GamepassController:Prompt(gamepassId)
				if not prompted then
					context.Controllers.NotificationController:Show(
						promptError or "The Roblox purchase prompt could not be opened.",
						"Purchase unavailable"
					)
					if audioFeedback then
						audioFeedback:Error()
					end
				end
				return
			end
			context.Controllers.NotificationController:Show(
				role.LockMessage,
				if role.Action == "OpenApplication"
					then "Application required"
					else "Access required"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
			selectedTeamId = "Civilian"
			renderPlay()
			scroll.CanvasPosition = Vector2.zero
			return
		end
		if not role.DepartmentId then
			context.Controllers.NotificationController:Show(
				"Select Civilian from the Play screen.",
				"Public role"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		local dutyProfile = nil
		for _, profile in menuData and menuData.DutyProfiles or {} do
			if profile.DepartmentId == role.DepartmentId then
				dutyProfile = profile
				break
			end
		end
		if not dutyProfile or not role.Spawns or #role.Spawns == 0 then
			context.Controllers.NotificationController:Show(
				"No valid duty profile or station is available.",
				"Duty unavailable"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		selectedTeamId = role.DepartmentId or role.Id
		showDutySelection(role, dutyProfile)
	end

	local renderCommunity: () -> ()
	local renderCareers: () -> ()
	local renderJobs: () -> ()
	local renderStore: () -> ()
	local renderTutorials: () -> ()
	local renderSettings: () -> ()
	local renderControls: () -> ()
	local currentRender: (() -> ())? = nil
	local selectBottomNav: ((string) -> ())? = nil
	local function shortLandscape(): boolean
		-- SafeViewport can retain the simulator's device-safe padding while the
		-- actual viewport has already rotated. Use the live viewport for the
		-- orientation decision so a phone cannot accidentally take the tall
		-- desktop header branch after a landscape switch.
		local camera = workspace.CurrentCamera
		local viewport = if camera
			then camera.ViewportSize
			else context.Controllers.UIOrchestrator:GetLayout().Viewport
		-- Desktop Studio and laptop clients can report a content height below 720
		-- after Roblox's own top bar is excluded. Require the short axis to be
		-- genuinely phone-sized as well, otherwise desktop uses the phone row and
		-- drops MENU into the page header.
		return viewport.X > viewport.Y and viewport.X < 1000 and viewport.Y < 600
	end
	local function narrowViewport(): boolean
		local safe = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
		return safe.X < 720 or safe.Y < 500
	end
	local function portraitCardColumns(): number
		local width = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		if shortLandscape() then
			return if width >= 980 then 2 else 1
		elseif width >= 1600 then
			return 4
		elseif width >= 1280 then
			return 3
		elseif width >= 720 then
			return 2
		end
		return 1
	end
	-- Play and Civilian Jobs are the same grid of the same tile, so they ask one
	-- place how wide a poster should be. Two copies of this is how the two pages
	-- came to look like different products in the first place.
	--
	-- This is a preference rather than the column count: the grid divides it back
	-- over however many tiles the server actually offers, so a row is never left
	-- short.
	local function posterColumns(): number
		local width = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		if shortLandscape() then
			return 5
		elseif width >= 1280 then
			-- 1280 rather than something wider because that is where an ordinary
			-- laptop sits, and a laptop is where most of this is played.
			return 6
		elseif width >= 1100 then
			return 5
		elseif width >= 900 then
			return 4
		end
		return portraitCardColumns()
	end
	local function posterActionHeight(): number
		return if shortLandscape() then 30 else 34
	end
	-- Below this a poster stops being readable, so a page too short to hold the
	-- grid scrolls rather than shrinking its tiles any further.
	local function posterMinimumHeight(): number
		return if shortLandscape() then 176 else 208
	end
	-- Bumped by every render. A page that asks the server for anything yields,
	-- and clearing the container before the yield does not help: two renders both
	-- clear, both wait, and then both append, so the page appears twice. After a
	-- yield a render checks it is still the current one and gives up if not.
	local renderGeneration = 0
	dismissToWorld = function()
		if not hasEnteredWorld then
			local activeCharacter = menuData and menuData.ActiveCharacterId
			local hasCharacter = (type(activeCharacter) == "string" and activeCharacter ~= "")
				or (type(selectedCharacterId) == "string" and selectedCharacterId ~= "")
			local duty = context.Controllers.DutyController.active
			local hasDuty = type(duty) == "table" and type(duty.DepartmentId) == "string"
			if not hasCharacter and not hasDuty then
				context.Controllers.NotificationController:Show(
					"Create or select a character before entering the city.",
					"Character required"
				)
				if audioFeedback then
					audioFeedback:Error()
				end
				setMenuOpen(true)
				return
			end
			hasEnteredWorld = true
		end
		setMenuOpen(false)
		if not interfaceMotionEnabled() then
			gui.Enabled = false
			return
		end
		TweenService:Create(
			root,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.17, function()
			gui.Enabled = false
		end)
	end

	-- A heading that is the first thing on a page is not rendered at all.
	--
	-- The navigation bar already names the page, and it names it in the one place
	-- the player just pressed, highlighted. Repeating "Departments" under a lit
	-- "Services" tab told nobody anything they did not know two seconds ago, and
	-- the title with its subtitle cost 42 pixels of a landscape phone's roughly
	-- 260 pixels of visible list: a sixth of the page, spent on a label.
	--
	-- Later headings are kept, because those genuinely separate one block from
	-- the next rather than restating where the player is.
	--
	-- Detected from the layout counter, which clear() resets to zero for each
	-- page, so this stays correct as pages are added or reordered rather than
	-- depending on a list of which headings happen to be first today.
	local function sectionHeading(titleValue: string, subtitle: string)
		if (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) == 0 then
			return
		end
		local compact = shortLandscape()
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.new(1, 0, 0, if compact then 42 else 54)
		wrapper.Parent = scroll
		local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		wrapper.LayoutOrder = nextOrder
		local titleItem = text(wrapper, titleValue, 17, COLOURS.Text, true)
		titleItem.Size = UDim2.new(1, 0, 0, if compact then 23 else 28)
		titleItem.TextSize = if compact then 16 else 17
		local subtitleItem = text(wrapper, subtitle, 13, COLOURS.Muted)
		subtitleItem.Position = UDim2.fromOffset(0, if compact then 23 else 29)
		subtitleItem.Size = UDim2.new(1, 0, 0, if compact then 17 else 20)
		subtitleItem.TextSize = if compact then 11 else 13
	end

	renderPlay = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Play"
		pageDescription.Text = if selectedTeamId == "Civilian"
			then "Create or choose a civilian character, then enter the city."
			else "Choose a service or step into civilian life."
		-- Do not render the old role/job layout while the server payload is still
		-- arriving. A single explicit loading state prevents the first-frame flash
		-- that made the retired UX appear to be active.
		if not menuData then
			local loading = card(scroll, if shortLandscape() then 86 else 104)
			local loadingCopy = text(loading, "Loading Portsmouth…", 17, COLOURS.Text, true)
			loadingCopy.Position = UDim2.fromOffset(20, 16)
			loadingCopy.Size = UDim2.new(1, -40, 0, 26)
			local loadingDetail = text(loading, "Preparing roles and characters", 13, COLOURS.Muted)
			loadingDetail.Position = UDim2.fromOffset(20, 48)
			loadingDetail.Size = UDim2.new(1, -40, 0, 20)
			return
		end
		if selectedTeamId ~= nil then
			-- The way back out of a department, on the page the player is stuck
			-- on. The Play tab clears the same filter, but a player who has
			-- drilled into a service is looking at this page rather than at the
			-- dock, and a filtered list with no visible way back reads as the
			-- menu having broken rather than as a filter having been applied.
			--
			-- First in the page, so it is above the tiles that are being filtered
			-- rather than below them.
			local back = button(scroll, "←  ALL TEAMS", false)
			back.Size = UDim2.new(
				0,
				if shortLandscape() then 148 else 180,
				0,
				if shortLandscape() then 32 else 38
			)
			back.TextSize = 12
			back.TextColor3 = COLOURS.Accent
			local backStroke = back:FindFirstChildOfClass("UIStroke")
			if backStroke then
				backStroke.Color = COLOURS.Accent
			end
			back.Activated:Connect(function()
				selectedTeamId = nil
				renderPlay()
				scroll.CanvasPosition = Vector2.zero
			end)
		end
		local availableRoles = {}
		local civilianRoles = {}
		local serviceRoles = {}
		for _, role in menuData.Roles or {} do
			if
				role.Visible
				and (selectedTeamId == nil or role.Id == selectedTeamId or role.DepartmentId == selectedTeamId)
				-- Driving a bus is a job somebody does, not a service that answers
				-- calls. It sat between Armed Response and the Prison Service on the
				-- strength of having a team and a uniform, which is how it is built
				-- rather than what it is. Jobs offers it instead, and nothing about
				-- joining it changes. Still reachable here if the player has drilled
				-- into Transport directly.
				and not (selectedTeamId == nil and CIVILIAN_JOB_ROLE_IDS[role.Id])
			then
				if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
					table.insert(civilianRoles, role)
				else
					table.insert(serviceRoles, role)
				end
			end
		end
		-- Civilian stays at the front: it is where a player without a character
		-- has to go, and burying it under the services is how somebody ends up
		-- trying to join a team they have no identity for.
		table.sort(serviceRoles, function(a, b)
			local orderA = ROLE_DISPLAY_ORDER[a.Id] or math.huge
			local orderB = ROLE_DISPLAY_ORDER[b.Id] or math.huge
			if orderA == orderB then
				return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
			end
			return orderA < orderB
		end)
		for _, role in civilianRoles do
			table.insert(availableRoles, role)
		end
		for _, role in serviceRoles do
			table.insert(availableRoles, role)
		end
		-- Says which of the two lists is on screen. Filtered down to one service
		-- the page had gone on calling itself "Start playing" over three policing
		-- roles, which is what made the filter look like a fault rather than a
		-- filter.
		sectionHeading(
			if selectedTeamId == "Civilian"
				then "Civilian"
				elseif selectedTeamId ~= nil then "Selected service"
				else "Start playing",
			if selectedTeamId == "Civilian"
				then "Your character and civilian identity."
				elseif selectedTeamId ~= nil then "Use All teams for the full list."
				else "Choose a service or step into civilian life."
		)
		if #availableRoles > 0 then
			-- Portrait tiles with artwork, a dark lower label band and a full
			-- width action beneath, as the old Portsmouth Play screen had.
			local roleActionHeight = posterActionHeight()
			-- Height comes from the page rather than from a table of pixel
			-- heights per breakpoint.
			--
			-- Those heights were chosen against one window and were wrong in
			-- every other one: on a desktop monitor the two rows finished about
			-- three fifths of the way down and left a band of empty canvas
			-- between the last poster and the navigation dock. Dividing up what
			-- the scrolling frame actually measures puts the whole section on one
			-- page at any size, and where the page is too short to hold it - a
			-- phone, mostly - the minimum keeps the posters legible and the
			-- section scrolls instead.
			--
			-- Drilled into a team the grid shares the page with the character
			-- list, so there it takes a poster's worth of height and leaves the
			-- rest to the characters.
			local focusedTeam = selectedTeamId ~= nil
			local roleGrid = tileGrid(scroll, {
				Name = "RoleGrid",
				Count = #availableRoles,
				Columns = posterColumns(),
				Height = if focusedTeam then (if shortLandscape() then 214 else 312) else nil,
				MinHeight = posterMinimumHeight(),
			})
			-- Characters are the first decision on Play. Keep the role posters below
			-- them so a new player never has to scroll past every department to create
			-- their identity.
			roleGrid.LayoutOrder = 50
			for _, role in availableRoles do
				local presentation = rolePresentation(role)
				local isCivilianRole = role.Id == "Civilian" or role.DepartmentId == "Civilian"
				local _, open = posterTile(roleGrid, {
					Id = tostring(role.Id),
					Image = roleTileImageUri(role),
					Monogram = presentation.Icon,
					Title = tostring(role.Name),
					Accent = presentation.Colour,
					ActionLabel = if role.Locked
						then "REQUIREMENTS"
						elseif isCivilianRole then "CHARACTERS"
						else "JOIN",
					ActionMuted = role.Locked,
					ActionHeight = roleActionHeight,
				})
				open.Activated:Connect(function()
					activateRole(role)
				end)
			end
		end
		if selectedTeamId ~= "Civilian" then
			return
		end
		sectionHeading(
			"Civilian characters",
			"Create your civilian identity here. Team uniforms are selected separately in locker rooms."
		)
		local landscape = shortLandscape()
		local compactViewport = context.Controllers.UIOrchestrator:GetLayout().Viewport
		local compactEmptyCard = compactViewport.X < 1000 or compactViewport.Y < 500
		local function enterCivilian(characterId: string)
			local spawnId: string? = nil
			for _, role in menuData and menuData.Roles or {} do
				if role.Id == "Civilian" then
					for _, spawn in role.Spawns or {} do
						if type(spawn.SpawnId) == "string" and spawn.SpawnId ~= "" then
							spawnId = spawn.SpawnId
							break
						end
					end
				end
				if spawnId then
					break
				end
			end
			if not spawnId then
				context.Controllers.NotificationController:Show(
					"No civilian spawn is configured on this server.",
					"Civilian unavailable"
				)
				if audioFeedback then
					audioFeedback:Error()
				end
				return
			end
			-- EnterCivilian requires the server session's ActiveCharacterId to
			-- match the card being used. Selecting here also makes switching
			-- between civilian identities deterministic instead of relying on a
			-- previous session selection.
			local selected = context.Controllers.CharacterController:Select(characterId)
			if not selected.Success then
				return
			end
			local response = context.Controllers.DutyController:EnterCivilian(characterId, spawnId)
			if response.Success then
				if audioFeedback then
					audioFeedback:Success()
				end
				dismissToWorld()
			end
		end
		if not menuData or #menuData.Characters == 0 then
			local empty =
				card(scroll, if compactEmptyCard then 164 else if landscape then 108 else 150)
			local titleItem = text(empty, "Start your first story", 18, COLOURS.Text, true)
			titleItem.Position =
				UDim2.fromOffset(20, if compactEmptyCard then 14 else if landscape then 13 else 18)
			titleItem.Size = UDim2.new(
				1,
				if compactEmptyCard then -40 else if landscape then -218 else -40,
				0,
				if compactEmptyCard then 28 else if landscape then 34 else 28
			)
			titleItem.TextSize = if compactEmptyCard or landscape then 16 else 18
			titleItem.TextWrapped = compactEmptyCard or landscape
			titleItem.TextTruncate = Enum.TextTruncate.None
			local copy =
				text(empty, "Create a civilian identity to enter the city.", 13, COLOURS.Muted)
			copy.Position =
				UDim2.fromOffset(20, if compactEmptyCard then 45 else if landscape then 42 else 50)
			copy.Size = UDim2.new(
				1,
				if compactEmptyCard then -40 else if landscape then -218 else -40,
				0,
				if compactEmptyCard then 42 else if landscape then 44 else 50
			)
			copy.TextWrapped = true
			copy.TextTruncate = Enum.TextTruncate.None
			local create = button(empty, "Create character", true)
			create.AnchorPoint = if compactEmptyCard then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			create.Position = if compactEmptyCard
				then UDim2.new(0, 20, 1, -14)
				else UDim2.new(1, -20, 0.5, 0)
			create.Size = if compactEmptyCard then UDim2.new(1, -40, 0, 40) else create.Size
			create.Activated:Connect(function()
				showCharacterCreationModal()
			end)
		else
			local columns = portraitCardColumns()
			-- Landscape turns the card on its side rather than shrinking it.
			--
			-- Stacking a portrait above its text needs height, and height is the one
			-- thing a phone held sideways has none of: the list is about 174 pixels
			-- tall, so a 258 card was taller than the area it scrolled inside and its
			-- lower half was never on screen. Width is the plentiful axis, so the
			-- portrait moves beside the text instead of above it and the whole card
			-- fits, with the next one showing beneath to say the list continues.
			local tileHeight = if landscape then 150 else 284
			local extraSlotPass = nil
			for _, pass in menuData.Gamepasses or {} do
				if pass.Id == "ExtraCharacterSlot" and pass.PurchaseType == "DeveloperProduct" then
					extraSlotPass = pass
					break
				end
			end
			local canCreate = menuData.EmptySlots > 0
			local canOfferExtraSlot = not canCreate
				and extraSlotPass ~= nil
				and extraSlotPass.Owned ~= true
			local characterGrid = tileGrid(scroll, {
				Name = "CharacterGrid",
				Count = #menuData.Characters + (if canCreate or canOfferExtraSlot then 1 else 0),
				Columns = columns,
				Height = tileHeight,
			})
			for _, character in menuData.Characters do
				local item = card(characterGrid, tileHeight)
				item.ClipsDescendants = true
				local selected = selectedCharacterId == character.CharacterId
				local selectedRail = Instance.new("Frame")
				selectedRail.BackgroundColor3 = if selected then COLOURS.Success else COLOURS.Accent
				selectedRail.BorderSizePixel = 0
				selectedRail.Size = UDim2.new(1, 0, 0, 4)
				selectedRail.Parent = item
				local preview = portraitPreview(
					item,
					COLOURS.Accent,
					character.PreviewAppearance,
					function()
						return item.Parent == characterGrid
					end
				)
				-- Beside the text in landscape, above it in portrait.
				local textLeft = if landscape then 124 else 16
				local textInset = if landscape then -140 else -32
				preview.Position = UDim2.fromOffset(12, 12)
				preview.Size = if landscape
					then UDim2.fromOffset(100, 126)
					else UDim2.new(1, -24, 0, 132)
				local name = text(item, character.FullName, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(textLeft, if landscape then 14 else 156)
				name.Size = UDim2.new(1, textInset, 0, 27)
				local dob = text(item, "Born " .. character.DateOfBirth, 12, COLOURS.Muted)
				dob.Position = UDim2.fromOffset(textLeft, if landscape then 40 else 182)
				dob.Size = UDim2.new(1, textInset, 0, 22)
				local identity = text(item, "CIVILIAN CHARACTER", 11, COLOURS.Accent, true)
				identity.Position = UDim2.fromOffset(textLeft, if landscape then 62 else 205)
				identity.Size = UDim2.new(1, textInset, 0, 18)
				-- A fixed label restating what the card plainly is. It goes first when
				-- the buttons need the room, which in landscape they do.
				identity.Visible = not landscape
				local choose = button(item, if selected then "Enter city" else "Choose", selected)
				choose.AnchorPoint = Vector2.new(0, 1)
				choose.Position = UDim2.new(0, textLeft, 1, -12)
				choose.Size = UDim2.new(1, textInset, 0, if landscape then 34 else 42)
				if
					selected
					and Players.LocalPlayer.Team
					and Players.LocalPlayer.Team.Name == "Civilian"
				then
					choose.Position = UDim2.new(0, textLeft, 1, -12)
					choose.Size = UDim2.new(1, textInset, 0, if landscape then 30 else 36)
					local saveOutfit = button(item, "Save outfit", false)
					saveOutfit.AnchorPoint = Vector2.new(0, 1)
					-- Sat at the same height as the date of birth and the identity line
					-- and drew straight over them, slicing "Born" in half. It stacks above
					-- the choose button now, in space the text no longer claims.
					-- Two actions share this row: keep the Roblox outfit, or author one in
					-- the creator. Stacking them would push the row into the date of birth
					-- on a phone held sideways, so they sit side by side instead.
					local actionRow = if landscape then -46 else -56
					local actionHeight = if landscape then 28 else 30
					local actionSize = UDim2.new(0.5, textInset / 2 - 4, 0, actionHeight)
					saveOutfit.Position = UDim2.new(0, textLeft, 1, actionRow)
					saveOutfit.Size = actionSize
					saveOutfit.TextSize = 11
					saveOutfit.Activated:Connect(function()
						saveOutfit.Text = "Saving…"
						local response =
							context.Controllers.CharacterController:SaveCurrentAppearance(
								character.CharacterId
							)
						if response.Success then
							context.Controllers.NotificationController:Show(
								"This civilian now keeps the current Roblox avatar outfit.",
								"Outfit saved"
							)
							context.Controllers.StartMenuController:Refresh()
						else
							saveOutfit.Text = "Save outfit"
							if audioFeedback then
								audioFeedback:Error()
							end
						end
					end)
					local editLook = button(item, "Edit look", false)
					editLook.AnchorPoint = Vector2.new(0, 1)
					editLook.Position = UDim2.new(0.5, textLeft + textInset / 2 + 4, 1, actionRow)
					editLook.Size = actionSize
					editLook.TextSize = 11
					editLook.Activated:Connect(function()
						editLook.Text = "Checking\u{2026}"
						local state = context.Controllers.CharacterController:AppearanceEditState(
							character.CharacterId
						)
						editLook.Text = "Edit look"
						if not state.Success then
							if audioFeedback then
								audioFeedback:Error()
							end
							return
						end
						local editState = state.Data or {}
						if editState.CanEdit then
							characterCreator:Open(character.CharacterId, function()
								context.Controllers.StartMenuController:Refresh()
							end, editState)
							return
						end
						-- Locked with no edit in hand. The product is the only way back in,
						-- so offer it rather than reporting a dead end the player cannot act on.
						local product = nil
						for _, pass in menuData and menuData.Gamepasses or {} do
							if
								pass.Id == "CharacterAppearanceEdit"
								and pass.PurchaseType == "DeveloperProduct"
							then
								product = pass
								break
							end
						end
						if product and product.ProductId then
							MarketplaceService:PromptProductPurchase(
								Players.LocalPlayer,
								product.ProductId
							)
						else
							context.Controllers.NotificationController:Show(
								"Appearance edits are not on sale on this server yet.",
								"Edit unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
						end
					end)
				end
				choose.Activated:Connect(function()
					if selected then
						enterCivilian(character.CharacterId)
						return
					end
					local response =
						context.Controllers.CharacterController:Select(character.CharacterId)
					if response.Success then
						selectedCharacterId = character.CharacterId
						if menuData then
							menuData.ActiveCharacterId = character.CharacterId
						end
						context.Controllers.StartMenuController:Refresh()
						context.Controllers.NotificationController:Show(
							"Character selected.",
							"Ready"
						)
						if audioFeedback then
							audioFeedback:Success()
						end
						renderPlay()
					end
				end)
			end
			if canCreate or canOfferExtraSlot then
				local createCard = card(characterGrid, tileHeight)
				createCard.ClipsDescendants = true
				local createPreview = Instance.new("Frame")
				createPreview.BackgroundColor3 = COLOURS.SurfaceRaised
				createPreview.BorderSizePixel = 0
				createPreview.Position = UDim2.fromOffset(12, 14)
				createPreview.Size = if landscape
					then UDim2.fromOffset(112, 112)
					else UDim2.new(1, -24, 0, 132)
				createPreview.Parent = createCard
				corner(createPreview, 12)
				stroke(createPreview, COLOURS.Accent, 0.62)
				local plus =
					text(createPreview, if canCreate then "+" else "★", 42, COLOURS.Accent, true)
				plus.Size = UDim2.fromScale(1, 1)
				plus.TextXAlignment = Enum.TextXAlignment.Center
				local createTitle = text(
					createCard,
					if canCreate then "New character" else "Extra character slot",
					17,
					COLOURS.Text,
					true
				)
				createTitle.Position = if landscape
					then UDim2.fromOffset(136, 16)
					else UDim2.fromOffset(16, 156)
				createTitle.Size = if landscape
					then UDim2.new(1, -152, 0, 27)
					else UDim2.new(1, -32, 0, 27)
				local createCopy = text(
					createCard,
					if canCreate
						then "Create one separate civilian identity."
						else "Unlock one additional identity with a one-time purchase.",
					13,
					COLOURS.Muted
				)
				createCopy.Position = if landscape
					then UDim2.fromOffset(136, 46)
					else UDim2.fromOffset(16, 185)
				createCopy.Size = if landscape
					then UDim2.new(1, -152, 0, 38)
					else UDim2.new(1, -32, 0, 40)
				createCopy.TextWrapped = true
				local create = button(
					createCard,
					if canCreate then "Create character" else "UNLOCK SLOT",
					not canCreate
				)
				create.AnchorPoint = Vector2.new(0, 1)
				create.Position = if landscape
					then UDim2.new(0, 136, 1, -14)
					else UDim2.new(0, 16, 1, -14)
				create.Size = if landscape
					then UDim2.new(1, -152, 0, 34)
					else UDim2.new(1, -32, 0, 42)
				create.Activated:Connect(function()
					if canCreate then
						showCharacterCreationModal()
					elseif extraSlotPass and extraSlotPass.ProductId then
						MarketplaceService:PromptProductPurchase(
							Players.LocalPlayer,
							extraSlotPass.ProductId
						)
					end
				end)
			end
		end
	end

	renderCareers = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Emergency services"
		pageDescription.Text = "Join a department, report for duty and start your next shift."

		local roles = menuData and menuData.Roles or {}
		local visibleCount = 0
		for _, role in roles do
			if role.Visible and role.Id ~= "Civilian" and role.DepartmentId ~= "Civilian" then
				visibleCount += 1
			end
		end

		sectionHeading(
			"Departments",
			string.format("%d roles available in this server.", visibleCount)
		)
		-- This is intentionally a roster, not a grid of product cards. A full-width
		-- list gives every service the same visual weight and keeps the action in a
		-- predictable place on touch devices.
		local tileHeight = if narrowViewport() then 88 else 112
		local roleGrid = Instance.new("Frame")
		roleGrid.Name = "ServiceRoster"
		roleGrid.BackgroundTransparency = 1
		roleGrid.Size = UDim2.fromScale(1, 0)
		roleGrid.AutomaticSize = Enum.AutomaticSize.Y
		roleGrid.Parent = scroll
		local rosterLayout = Instance.new("UIListLayout")
		rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rosterLayout.Padding = UDim.new(0, 4)
		rosterLayout.Parent = roleGrid
		if visibleCount == 0 then
			local empty = card(roleGrid, tileHeight)
			local emptyTitle = text(empty, "No roles available", 18, COLOURS.Text, true)
			emptyTitle.Position = UDim2.fromOffset(20, 22)
			emptyTitle.Size = UDim2.new(1, -40, 0, 30)
			local emptyCopy = text(
				empty,
				"This server has not made any departments available yet.",
				13,
				COLOURS.Muted
			)
			emptyCopy.Position = UDim2.fromOffset(20, 56)
			emptyCopy.Size = UDim2.new(1, -40, 0, 52)
			emptyCopy.TextWrapped = true
		end
		for _, role in roles do
			if role.Visible and role.Id ~= "Civilian" and role.DepartmentId ~= "Civilian" then
				local presentation = rolePresentation(role)
				local item = Instance.new("Frame")
				item.Size = UDim2.new(1, 0, 0, tileHeight)
				item.BackgroundColor3 = COLOURS.Surface
				item.BackgroundTransparency = if role.Locked then 0.2 else 0.06
				item.BorderSizePixel = 0
				item.Parent = roleGrid
				item.Name = "Career_" .. tostring(role.Id)
				item.ClipsDescendants = true
				local rail = Instance.new("Frame")
				rail.BackgroundColor3 = presentation.Colour
				rail.BackgroundTransparency = if role.Locked then 0.5 else 0
				rail.BorderSizePixel = 0
				rail.Size = UDim2.new(0, 4, 1, 0)
				rail.Parent = item
				-- A small department mark is more honest and more useful than a
				-- giant empty avatar viewport. It also prevents uniform thumbnails
				-- from dominating the menu on a phone.
				local mark = Instance.new("Frame")
				mark.BackgroundColor3 = presentation.Colour
				mark.BackgroundTransparency = if role.Locked then 0.72 else 0.82
				mark.BorderSizePixel = 0
				mark.Position = UDim2.fromOffset(18, if narrowViewport() then 20 else 28)
				mark.Size = UDim2.fromOffset(
					if narrowViewport() then 48 else 56,
					if narrowViewport() then 48 else 56
				)
				mark.Parent = item
				corner(mark, 10)
				stroke(mark, presentation.Colour, 0.32)
				local markText = text(
					mark,
					presentation.Icon,
					if narrowViewport() then 13 else 15,
					presentation.Colour,
					true
				)
				markText.Size = UDim2.fromScale(1, 1)
				markText.TextXAlignment = Enum.TextXAlignment.Center
				markText.TextYAlignment = Enum.TextYAlignment.Center
				local textLeft = if narrowViewport() then 70 else 78
				local actionReserve = if narrowViewport() then 144 else 156
				local textInset = -textLeft - actionReserve
				local category = text(item, presentation.Label, 12, presentation.Colour, true)
				category.Position = UDim2.fromOffset(textLeft, if narrowViewport() then 12 else 18)
				category.Size = UDim2.new(1, textInset, 0, 18)
				local access = text(
					item,
					if role.Locked then "LOCKED" else "AVAILABLE",
					12,
					if role.Locked then COLOURS.Muted else COLOURS.Success,
					true
				)
				access.AnchorPoint = Vector2.new(1, 0)
				access.Position =
					UDim2.new(1, -actionReserve, 0, if narrowViewport() then 12 else 18)
				access.Size = UDim2.fromOffset(actionReserve, 16)
				access.TextXAlignment = Enum.TextXAlignment.Right
				local name =
					text(item, role.Name, if narrowViewport() then 17 else 20, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(textLeft, if narrowViewport() then 34 else 42)
				name.Size = UDim2.new(1, textInset, 0, 27)
				name.TextWrapped = true
				name.TextTruncate = Enum.TextTruncate.None
				-- What this row can tell the player that the others cannot.
				--
				-- Every unlocked role used to read "Cleared to report for duty." in
				-- green, which is the same sentence on every row a player can
				-- actually use. A line repeated on every row carries no information,
				-- and it was competing for attention with the locked rows, which are
				-- the only ones that genuinely need reading. The button beside it
				-- already says the role is available.
				--
				-- Where they would start is the thing they are about to be asked for,
				-- so it is what the line says instead.
				local detailText = role.LockMessage
				if not role.Locked then
					local spawns = role.Spawns or {}
					if #spawns == 1 then
						detailText = "Reports from " .. tostring(spawns[1].StationName)
					elseif #spawns > 1 then
						detailText = string.format("%d places to report", #spawns)
					else
						detailText = ""
					end
				end
				local detail = text(item, detailText, 12, COLOURS.Muted)
				detail.Position = UDim2.fromOffset(textLeft, if narrowViewport() then 62 else 76)
				detail.Size = UDim2.new(1, textInset, 0, 20)
				detail.TextSize = if narrowViewport() then 13 else 14
				detail.TextWrapped = true
				detail.TextYAlignment = Enum.TextYAlignment.Top
				detail.TextTruncate = Enum.TextTruncate.None

				local actionLabel = "Report for duty"
				if role.Locked then
					actionLabel = if role.Action == "PromptGamepass"
						then "Unlock role"
						elseif role.Action == "OpenApplication" then "View application"
						else "View requirements"
				end
				local action = button(item, actionLabel, false)
				action.AnchorPoint = Vector2.new(1, 0.5)
				action.Position = UDim2.new(1, -14, 0.5, 0)
				action.Size =
					UDim2.fromOffset(actionReserve - 14, if narrowViewport() then 28 else 30)
				action.TextSize = if narrowViewport() then 12 else 14
				action.BackgroundTransparency = 1
				action.TextColor3 = if role.Locked then COLOURS.Muted else presentation.Colour
				local actionStroke = action:FindFirstChildOfClass("UIStroke")
				if actionStroke then
					actionStroke.Transparency = 1
				end
				local divider = Instance.new("Frame")
				divider.BackgroundColor3 = COLOURS.Border
				divider.BackgroundTransparency = 0.68
				divider.BorderSizePixel = 0
				divider.Position = UDim2.new(0, 18, 1, -1)
				divider.Size = UDim2.new(1, -36, 0, 1)
				divider.Parent = item
				if not role.Locked then
					action.Text = "JOIN  →"
				elseif role.Action ~= "PromptGamepass" then
					action.Text = "REQUIREMENTS  →"
				end
				action.Selectable = true
				action.Activated:Connect(function()
					if role.Locked then
						if role.Action == "PromptGamepass" then
							local gamepassId = tonumber(role.GamepassId)
							if not gamepassId or gamepassId <= 0 then
								context.Controllers.NotificationController:Show(
									"This pass is not available for purchase yet.",
									"Pass unavailable"
								)
								if audioFeedback then
									audioFeedback:Error()
								end
								return
							end
							local prompted, promptError =
								context.Controllers.GamepassController:Prompt(gamepassId)
							if not prompted then
								context.Controllers.NotificationController:Show(
									promptError or "The Roblox purchase prompt could not be opened.",
									"Purchase unavailable"
								)
								if audioFeedback then
									audioFeedback:Error()
								end
							end
							return
						end
						context.Controllers.NotificationController:Show(
							role.LockMessage,
							if role.Action == "OpenApplication"
								then "Application required"
								else "Access required"
						)
						if audioFeedback then
							audioFeedback:Error()
						end
						return
					end
					if not role.DepartmentId then
						context.Controllers.NotificationController:Show(
							"Select Civilian from the Play screen.",
							"Public role"
						)
						if audioFeedback then
							audioFeedback:Error()
						end
						return
					end
					local dutyProfile = nil
					for _, profile in menuData.DutyProfiles or {} do
						if profile.DepartmentId == role.DepartmentId then
							dutyProfile = profile
							break
						end
					end
					if not dutyProfile or not role.Spawns or #role.Spawns == 0 then
						context.Controllers.NotificationController:Show(
							"No valid duty profile or station is available.",
							"Duty unavailable"
						)
						if audioFeedback then
							audioFeedback:Error()
						end
						return
					end
					showDutySelection(role, dutyProfile)
				end)
			end
		end
	end

	renderJobs = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Civilian jobs"
		pageDescription.Text = "Pick up work that is available in the city today."
		sectionHeading("Civilian jobs", "Only fully connected civilian jobs appear here.")
		-- Civilian work that is built as a role rather than as a Job entry.
		--
		-- These join through the same duty flow as any service, so they are drawn
		-- from menuData.Roles and handed to activateRole exactly as the Play page
		-- would have. Listing them here is a statement about what they are, not a
		-- second way of joining them.
		local jobRoles = {}
		for _, role in menuData and menuData.Roles or {} do
			if role.Visible and CIVILIAN_JOB_ROLE_IDS[role.Id] then
				table.insert(jobRoles, role)
			end
		end
		local jobs = {}
		for _, job in pairs(menuData and menuData.Jobs or {}) do
			-- A catalogue entry is a promise: it must have a working join path.
			-- Do not show future/application placeholders as if they were playable.
			if tostring(job.Id) == "TaxiDriver" then
				table.insert(jobs, job)
			end
		end
		-- One grid of one tile, whichever of the two payloads the work arrived in.
		--
		-- A player weighing up driving a bus against driving a taxi is choosing
		-- between two jobs. That one is configured as a role with a team and the
		-- other as a catalogue entry is a fact about the configuration, and
		-- letting it show had turned this page into a card followed by a list of
		-- rows, sharing nothing with each other or with the Play grid the same
		-- player had just come from.
		local entryCount = #jobRoles + #jobs
		if entryCount == 0 then
			local empty = card(scroll, if shortLandscape() then 110 else 132)
			local title = text(empty, "No work is available yet", 17, COLOURS.Text, true)
			title.Position = UDim2.fromOffset(20, 18)
			title.Size = UDim2.new(1, -40, 0, 26)
			local copy = text(
				empty,
				"New civilian systems will appear here when they are ready to play.",
				13,
				COLOURS.Muted
			)
			copy.Position = UDim2.fromOffset(20, 50)
			copy.Size = UDim2.new(1, -40, 0, 42)
			copy.TextWrapped = true
			return
		end
		local actionHeight = posterActionHeight()
		local jobGrid = tileGrid(scroll, {
			Name = "CivilianJobGrid",
			Count = entryCount,
			Columns = posterColumns(),
			MinHeight = posterMinimumHeight(),
		})
		for _, role in jobRoles do
			local presentation = rolePresentation(role)
			local _, join = posterTile(jobGrid, {
				Id = tostring(role.Id),
				Image = roleTileImageUri(role),
				Monogram = presentation.Icon,
				Title = tostring(role.Name),
				Detail = if role.Locked
					then tostring(role.LockMessage or "Requirements not met")
					else presentation.Label,
				Accent = presentation.Colour,
				ActionLabel = if role.Locked then "REQUIREMENTS" else "JOIN",
				ActionMuted = role.Locked,
				ActionHeight = actionHeight,
			})
			join.Activated:Connect(function()
				activateRole(role)
			end)
		end
		for _, job in jobs do
			local isTaxi = tostring(job.Id) == "TaxiDriver"
			local access = if tostring(job.Class) == "Public"
				then "PUBLIC EMPLOYMENT"
				else "APPLICATION ROLE"
			local hasActiveCharacter = type(menuData and menuData.ActiveCharacterId) == "string"
				and menuData.ActiveCharacterId ~= ""
			-- What the button says when it is not mid-flight. Every path that
			-- gives up puts this back, so a refused shift never leaves the tile
			-- offering a different action from the one it opened with.
			local idleActionText = if hasActiveCharacter then "START SHIFT" else "ENTER CITY"
			local _, action = posterTile(jobGrid, {
				Id = tostring(job.Id),
				Image = roleTileImageUri(job),
				-- Catalogue work has no uploaded artwork, so the tile carries the
				-- opening of the job's own name where a department mark would sit.
				Monogram = string.upper(string.sub(tostring(job.Name), 1, 4)),
				Title = tostring(job.Name),
				Detail = access .. "  ·  £" .. tostring(job.BaseWage or 0) .. " base wage",
				Accent = COLOURS.Success,
				ActionLabel = idleActionText,
				ActionMuted = not isTaxi,
				ActionHeight = actionHeight,
			})
			action.Selectable = isTaxi
			if isTaxi then
				action.Activated:Connect(function()
					action.Active = false
					action.Text = if hasActiveCharacter then "STARTING…" else "ENTERING CITY…"
					if not hasActiveCharacter then
						local characterId = selectedCharacterId
							or (menuData and menuData.LastCharacterId)
						if
							not characterId
							and menuData
							and menuData.Characters
							and #menuData.Characters == 1
						then
							characterId = menuData.Characters[1].CharacterId
						end
						if not characterId then
							context.Controllers.NotificationController:Show(
								"Create a civilian character before starting work.",
								"Taxi unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
							action.Active = true
							action.Text = idleActionText
							return
						end
						local selected = context.Controllers.CharacterController:Select(characterId)
						local entered = if selected.Success
							then (function()
								local civilianSpawnId: string? = nil
								for _, role in menuData and menuData.Roles or {} do
									if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
										for _, spawn in role.Spawns or {} do
											if
												type(spawn.SpawnId) == "string"
												and spawn.SpawnId ~= ""
											then
												civilianSpawnId = spawn.SpawnId
												break
											end
										end
									end
									if civilianSpawnId then
										break
									end
								end
								if not civilianSpawnId then
									return { Success = false }
								end
								return context.Controllers.DutyController:EnterCivilian(
									characterId,
									civilianSpawnId
								)
							end)()
							else selected
						if not entered.Success then
							context.Controllers.NotificationController:Show(
								"Select a civilian character before starting work.",
								"Taxi unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
							action.Active = true
							action.Text = idleActionText
							return
						end
					end
					local response =
						context.Controllers.NetworkController:Request("TaxiStartShift", {})
					context.Controllers.NotificationController:Show(response.Message, "Taxi")
					if response.Success then
						dismissToWorld()
					else
						action.Active = true
						action.Text = idleActionText
						if audioFeedback then
							audioFeedback:Error()
						end
					end
				end)
			end
		end
	end

	renderStore = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Store"
		pageDescription.Text = "Optional access and upgrades for this experience."
		sectionHeading(
			"RoleplayOS passes",
			"Purchases are handled by Roblox. Your access refreshes automatically."
		)
		if not menuData or not menuData.Gamepasses then
			local loading = card(scroll, 90)
			local loadingCopy = text(loading, "Loading available passes…", 14, COLOURS.Muted)
			loadingCopy.Position = UDim2.fromOffset(20, 0)
			loadingCopy.Size = UDim2.new(1, -40, 1, 0)
			return
		end

		local safeWidth = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		local columns = if safeWidth >= 1180
			then 4
			else if safeWidth >= 840 then 3 else if safeWidth >= 560 then 2 else 1
		local categories = {}
		local categoryOrder = {}
		for _, pass in menuData.Gamepasses do
			if not categories[pass.Category] then
				categories[pass.Category] = {}
				table.insert(categoryOrder, pass.Category)
			end
			table.insert(categories[pass.Category], pass)
		end
		if selectedStoreCategory and not categories[selectedStoreCategory] then
			selectedStoreCategory = nil
		end
		local categoryBar = Instance.new("ScrollingFrame")
		categoryBar.Name = "ProductCategories"
		categoryBar.BackgroundColor3 = COLOURS.Surface
		categoryBar.BorderSizePixel = 0
		categoryBar.Size = UDim2.new(1, 0, 0, 58)
		categoryBar.AutomaticCanvasSize = Enum.AutomaticSize.X
		categoryBar.CanvasSize = UDim2.new()
		-- The row does scroll, and with no scrollbar there was nothing to say so.
		-- The last category simply appeared sliced off at the panel edge, which
		-- reads as a broken layout rather than as more to reach.
		categoryBar.ScrollBarThickness = 6
		categoryBar.ScrollBarImageTransparency = 0.4
		categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
		categoryBar.Parent = scroll
		local categoryOrderIndex = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", categoryOrderIndex)
		categoryBar.LayoutOrder = categoryOrderIndex
		corner(categoryBar, 12)
		stroke(categoryBar)
		local categoryPadding = Instance.new("UIPadding")
		categoryPadding.PaddingLeft = UDim.new(0, 8)
		categoryPadding.PaddingRight = UDim.new(0, 8)
		categoryPadding.PaddingTop = UDim.new(0, 7)
		categoryPadding.PaddingBottom = UDim.new(0, 7)
		categoryPadding.Parent = categoryBar
		local categoryLayout = Instance.new("UIListLayout")
		categoryLayout.FillDirection = Enum.FillDirection.Horizontal
		categoryLayout.Padding = UDim.new(0, 8)
		categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
		categoryLayout.Parent = categoryBar
		local tabs = { "All" }
		for _, category in categoryOrder do
			table.insert(tabs, tostring(category))
		end
		for _, category in tabs do
			local selected = (category == "All" and selectedStoreCategory == nil)
				or selectedStoreCategory == category
			local tab = button(categoryBar, category, selected)
			tab.Size = UDim2.fromOffset(math.max(116, 32 + #category * 8), 44)
			tab.Activated:Connect(function()
				selectedStoreCategory = if category == "All" then nil else category
				renderStore()
			end)
		end
		for _, category in categoryOrder do
			if selectedStoreCategory and tostring(category) ~= selectedStoreCategory then
				continue
			end
			local passes = categories[category]
			local section = Instance.new("Frame")
			section.Name = "StoreSection_" .. tostring(category)
			section.BackgroundTransparency = 1
			section.Size = UDim2.new(1, 0, 0, 54)
			section.Parent = scroll
			local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
			scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
			section.LayoutOrder = nextOrder
			local categoryTitle = text(section, tostring(category), 18, COLOURS.Text, true)
			categoryTitle.Position = UDim2.fromOffset(2, 0)
			categoryTitle.Size = UDim2.new(1, -4, 0, 26)
			local categoryCopy = text(
				section,
				string.format("%d %s", #passes, if #passes == 1 then "option" else "options"),
				11,
				COLOURS.Muted
			)
			categoryCopy.Position = UDim2.fromOffset(2, 25)
			categoryCopy.Size = UDim2.new(1, -4, 0, 18)
			local passGrid = Instance.new("Frame")
			passGrid.Name = "Products"
			passGrid.BackgroundTransparency = 1
			passGrid.Position = UDim2.fromOffset(0, 52)
			passGrid.Size = UDim2.fromScale(1, 0)
			passGrid.Parent = section
			local passLayout = Instance.new("UIGridLayout")
			passLayout.SortOrder = Enum.SortOrder.LayoutOrder
			passLayout.CellPadding = UDim2.fromOffset(14, 14)
			passLayout.CellSize = UDim2.new(1 / columns, -14 * (columns - 1) / columns, 0, 250)
			passLayout.Parent = passGrid
			local function updateSectionHeight()
				local contentHeight = passLayout.AbsoluteContentSize.Y
				passGrid.Size = UDim2.new(1, 0, 0, contentHeight)
				section.Size = UDim2.new(1, 0, 0, 52 + contentHeight)
			end
			passLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSectionHeight)
			for _, pass in passes do
				local item = card(passGrid, 250)
				item.ClipsDescendants = true
				local artwork = Instance.new("Frame")
				artwork.Position = UDim2.fromOffset(12, 12)
				artwork.Size = UDim2.new(1, -24, 0, 78)
				artwork.BackgroundColor3 = if pass.Owned
					then Color3.fromRGB(22, 60, 50)
					else Color3.fromRGB(27, 43, 68)
				artwork.BorderSizePixel = 0
				artwork.Parent = item
				corner(artwork, 10)
				local artworkGradient = Instance.new("UIGradient")
				artworkGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, artwork.BackgroundColor3),
					ColorSequenceKeypoint.new(1, COLOURS.SurfaceRaised),
				})
				artworkGradient.Rotation = 18
				artworkGradient.Parent = artwork
				local imageId = tonumber(
					pass.ImageAssetId or pass.IconAssetId or pass.ImageId or pass.IconImageId
				)
				if imageId and imageId > 0 then
					local image = Instance.new("ImageLabel")
					image.BackgroundTransparency = 1
					image.Size = UDim2.fromScale(1, 1)
					image.Image = "rbxassetid://" .. tostring(imageId)
					image.ScaleType = Enum.ScaleType.Crop
					image.Parent = artwork
					corner(image, 10)
				else
					local shape = Instance.new("Frame")
					shape.AnchorPoint = Vector2.new(0.5, 0.5)
					shape.Position = UDim2.fromScale(0.5, 0.5)
					shape.Size = UDim2.fromOffset(42, 42)
					shape.Rotation = -12
					shape.BackgroundColor3 = if pass.Owned then COLOURS.Success else COLOURS.Accent
					shape.BackgroundTransparency = 0.28
					shape.BorderSizePixel = 0
					shape.Parent = artwork
					corner(shape, 12)
					local detail = Instance.new("Frame")
					detail.AnchorPoint = Vector2.new(0.5, 0.5)
					detail.Position = UDim2.fromScale(0.5, 0.5)
					detail.Size = UDim2.fromOffset(68, 2)
					detail.Rotation = 35
					detail.BackgroundColor3 = COLOURS.Text
					detail.BackgroundTransparency = 0.7
					detail.BorderSizePixel = 0
					detail.Parent = artwork
				end
				local name = text(item, pass.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(16, 98)
				name.Size = UDim2.new(1, -32, 0, 25)
				name.TextWrapped = true
				name.TextWrapped = false
				name.TextTruncate = Enum.TextTruncate.AtEnd
				TooltipSystem:Attach(name, pass.Name)
				local description = text(item, pass.Description, 12, COLOURS.Muted)
				description.Position = UDim2.fromOffset(16, 126)
				description.Size = UDim2.new(1, -32, 0, 40)
				description.TextWrapped = true
				description.TextYAlignment = Enum.TextYAlignment.Top
				description.TextTruncate = Enum.TextTruncate.AtEnd
				TooltipSystem:Attach(description, pass.Description)
				local price = tonumber(pass.PriceInRobux or pass.Price)
				local stateCopy = if pass.Owned
					then "OWNED"
					elseif price and price > 0 then string.format("R$ %d", price)
					elseif pass.Configured then "VIEW PRICE"
					else "NOT CONFIGURED"
				local state = text(
					item,
					stateCopy,
					10,
					if pass.Owned then COLOURS.Success else COLOURS.Accent,
					true
				)
				state.Position = UDim2.fromOffset(16, 170)
				state.Size = UDim2.new(1, -32, 0, 18)
				local actionLabel = if pass.Owned
					then "Owned"
					elseif not pass.Configured then "Unavailable"
					elseif not pass.AvailableInServer then "Public servers only"
					else "View pass"
				local purchase =
					button(item, actionLabel, not pass.Owned and pass.AvailableInServer)
				purchase.AnchorPoint = Vector2.new(0, 1)
				purchase.Position = UDim2.new(0, 16, 1, -14)
				purchase.Size = UDim2.new(1, -32, 0, 40)
				purchase.Selectable = pass.Configured and pass.AvailableInServer and not pass.Owned
				purchase.Active = purchase.Selectable
				if purchase.Active then
					purchase.Activated:Connect(function()
						if pass.PurchaseType == "DeveloperProduct" then
							MarketplaceService:PromptProductPurchase(
								Players.LocalPlayer,
								pass.ProductId
							)
						else
							context.Controllers.GamepassController:Prompt(pass.GamepassId)
						end
					end)
				else
					purchase.BackgroundColor3 = COLOURS.SurfaceRaised
					purchase.TextColor3 = if pass.Owned then COLOURS.Success else COLOURS.Muted
				end
			end
			updateSectionHeight()
		end
	end

	local tutorials = {
		{
			Title = "Starting your character",
			Summary = "Create an identity, choose a role and enter Portsmouth.",
			Body = "Create or select a civilian character under Players. Careers then shows every public and whitelisted role available to you. Locked cards explain the exact requirement.",
		},
		{
			Title = "Emergency calls",
			Summary = "Learn how calls reach Control, MDT and responding units.",
			Body = "Use the phone to contact 999. Control creates and grades an incident, assigns available units and updates its status. Relevant emergency teams receive the server-local call through their MDT.",
		},
		{
			Title = "Police and custody",
			Summary = "Understand cautions, arrest, transport and booking.",
			Body = "Police tools are server-authorised. Officers caution and restrain a nearby player, transport them to custody and complete booking. Charges determine the custody duration and persistent record.",
		},
		{
			Title = "Vehicles and dealerships",
			Summary = "Buy, spawn and keep your registered vehicles.",
			Body = "Visit a dealership prompt to browse civilian vehicles. Owned vehicles retain their registration. Service depots show vehicles allowed by your current role, rank and division.",
		},
		{
			Title = "Controls and accessibility",
			Summary = "See the correct inputs for your current device.",
			Body = "Open Controls for keyboard, touch, gamepad, console and VR bindings. Roblox prompts remain the authority for contextual interactions such as dealerships and dispatch seats.",
		},
	}

	renderTutorials = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Tutorials"
		pageDescription.Text = "Learn each system before starting your roleplay."
		sectionHeading("Game guides", "Short, practical explanations of the live systems.")
		local utilities = card(scroll, 78)
		local controls = button(utilities, "Controls", false)
		controls.Position = UDim2.fromOffset(18, 17)
		controls.Size = UDim2.new(0.5, -27, 0, 44)
		controls.Activated:Connect(renderControls)
		local settings = button(utilities, "Settings", false)
		settings.Position = UDim2.new(0.5, 9, 0, 17)
		settings.Size = UDim2.new(0.5, -27, 0, 44)
		settings.Activated:Connect(renderSettings)
		local compactTutorials = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X < 650
		for index, tutorial in tutorials do
			local item = card(scroll, if compactTutorials then 166 else 124)
			local number = text(item, string.format("%02d", index), 13, COLOURS.Accent, true)
			number.Position = UDim2.fromOffset(20, 18)
			number.Size = UDim2.fromOffset(34, 24)
			local titleItem = text(item, tutorial.Title, 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(58, 16)
			titleItem.Size = UDim2.new(1, if compactTutorials then -76 else -230, 0, 28)
			local summary = text(item, tutorial.Summary, 13, COLOURS.Muted)
			summary.Position = UDim2.fromOffset(58, 44)
			summary.Size = UDim2.new(1, if compactTutorials then -76 else -250, 0, 54)
			summary.TextWrapped = true
			local open = button(item, "Open guide", false)
			open.AnchorPoint = if compactTutorials then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			open.Position = if compactTutorials
				then UDim2.new(0, 18, 1, -14)
				else UDim2.new(1, -18, 0.5, 0)
			open.Size = if compactTutorials
				then UDim2.new(1, -36, 0, 40)
				else UDim2.fromOffset(150, 42)
			open.Activated:Connect(function()
				local guideViewport = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
				modalSystem:Open({
					Title = tutorial.Title,
					Body = tutorial.Body,
					Actions = { { Label = "Close", Primary = true, Callback = function() end } },
					Width = math.min(520, guideViewport.X - 32),
					Height = math.min(300, guideViewport.Y - 32),
					Dismissable = true,
				})
			end)
		end
	end

	renderSettings = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Advanced settings"
		pageDescription.Text = "Accessible, responsive controls for this experience."
		sectionHeading(
			"Interface and accessibility",
			"Roblox-native volume, graphics and controls remain in the Roblox menu."
		)
		local settings = context.Controllers.SettingsController:Get()
		if not settings then
			local unavailable = card(scroll, 80)
			local message = text(unavailable, "Settings are still loading.", 14, COLOURS.Muted)
			message.Position = UDim2.fromOffset(18, 18)
			message.Size = UDim2.new(1, -36, 0, 40)
			return
		end
		local function settingRow(
			titleValue: string,
			description: string,
			buttonText: string,
			onActivate: () -> ()
		)
			local row = card(scroll, 88)
			local titleItem = text(row, titleValue, 15, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(18, 12)
			titleItem.Size = UDim2.new(1, -210, 0, 25)
			local detail = text(row, description, 12, COLOURS.Muted)
			detail.Position = UDim2.fromOffset(18, 39)
			detail.Size = UDim2.new(1, -210, 0, 32)
			detail.TextWrapped = true
			local action = button(row, buttonText, false)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -16, 0.5, 0)
			action.Size = UDim2.fromOffset(160, 40)
			action.Activated:Connect(onActivate)
		end
		settingRow(
			"Interface scale",
			"Combines with your Roblox preferred text size.",
			settings.InterfaceScale,
			function()
				local nextValue = if settings.InterfaceScale == "Small"
					then "Standard"
					elseif settings.InterfaceScale == "Standard" then "Large"
					else "Small"
				context.Controllers.SettingsController:Update("InterfaceScale", nextValue)
				renderSettings()
			end
		)
		for _, definition in
			{
				{
					"Interface motion",
					"Interface transitions and button motion.",
					"InterfaceMotion",
				},
				{
					"High contrast",
					"Increases scene contrast and reduces colour wash.",
					"HighContrast",
				},
				{
					"Reduced effects",
					"Disables decorative particles, trails and beams locally.",
					"ReducedEffects",
				},
				{
					"Camera shake",
					"Allows game camera shake effects when implemented.",
					"CameraShake",
				},
				{ "Gameplay hints", "Shows contextual help and onboarding prompts.", "ShowHints" },
			}
		do
			local key = definition[3]
			settingRow(
				definition[1],
				definition[2],
				settings[key] and "Enabled" or "Disabled",
				function()
					context.Controllers.SettingsController:Update(key, not settings[key])
					renderSettings()
				end
			)
		end
	end

	-- Controls as an ordinary page rather than an overlay. It was the one item in
	-- the sidebar that opened something else entirely, which made it read as a
	-- different product from the four either side of it.
	renderControls = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Controls"
		pageDescription.Text = "Every action, and what it is bound to on your device."
		local controller = context.Controllers.ControlsController
		local data = controller:List()
		local order = data.ModeOrder
		local labels = data.ModeLabels
		local selected = controller:DetectedMode()

		local rowsHolder: Frame
		local modeButtons: { [string]: TextButton } = {}

		local function paint()
			for mode, item in modeButtons do
				local active = mode == selected
				item.BackgroundColor3 = if active then COLOURS.Accent else COLOURS.Canvas
				item.TextColor3 = if active then COLOURS.Text else COLOURS.Muted
			end
			for _, child in rowsHolder:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			for index, control in data.Controls do
				local row = Instance.new("Frame")
				row.LayoutOrder = index
				row.Size = UDim2.new(1, 0, 0, 42)
				-- Banded rather than bordered. A list this long reads faster when
				-- the eye can follow a stripe across to the binding.
				row.BackgroundColor3 = if index % 2 == 0 then COLOURS.Canvas else COLOURS.Surface
				row.BorderSizePixel = 0
				row.Parent = rowsHolder
				corner(row, 8)
				local action = text(row, tostring(control.Action), 14, COLOURS.Text)
				action.Position = UDim2.fromOffset(16, 0)
				action.Size = UDim2.new(0.5, -16, 1, 0)
				local binding =
					text(row, tostring(control[selected] or "—"), 14, COLOURS.Accent, true)
				binding.Position = UDim2.new(0.5, 4, 0, 0)
				binding.Size = UDim2.new(0.5, -20, 1, 0)
			end
		end

		sectionHeading("Your device", "Bindings change with what you are playing on.")
		local switcher = card(scroll, 62)
		local switcherLayout = Instance.new("UIListLayout")
		switcherLayout.FillDirection = Enum.FillDirection.Horizontal
		switcherLayout.Padding = UDim.new(0, 8)
		switcherLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		switcherLayout.Parent = switcher
		local switcherPadding = Instance.new("UIPadding")
		switcherPadding.PaddingLeft = UDim.new(0, 12)
		switcherPadding.PaddingRight = UDim.new(0, 12)
		switcherPadding.Parent = switcher
		for index, mode in order do
			local item = Instance.new("TextButton")
			item.AutoButtonColor = false
			item.BackgroundColor3 = COLOURS.Canvas
			item.BorderSizePixel = 0
			item.Font = Enum.Font.GothamBold
			item.LayoutOrder = index
			item.Text = tostring(labels[mode] or mode)
			item.TextColor3 = COLOURS.Muted
			item.TextSize = 11
			item.Size = UDim2.new(1 / #order, -6, 0, 38)
			item.Parent = switcher
			corner(item, 9)
			pressable(item)
			modeButtons[mode] = item
			item.Activated:Connect(function()
				selected = mode
				paint()
			end)
		end

		sectionHeading("Controls", "Held actions are marked where they differ.")
		local listCard = card(scroll, 0)
		listCard.AutomaticSize = Enum.AutomaticSize.Y
		local listPadding = Instance.new("UIPadding")
		listPadding.PaddingTop = UDim.new(0, 10)
		listPadding.PaddingBottom = UDim.new(0, 10)
		listPadding.PaddingLeft = UDim.new(0, 10)
		listPadding.PaddingRight = UDim.new(0, 10)
		listPadding.Parent = listCard
		rowsHolder = Instance.new("Frame")
		rowsHolder.BackgroundTransparency = 1
		rowsHolder.Size = UDim2.fromScale(1, 0)
		rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
		rowsHolder.Parent = listCard
		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.Padding = UDim.new(0, 4)
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Parent = rowsHolder

		paint()
	end

	-- Three questions, in the order somebody actually asks them: where am I, where
	-- else can I go, and what about my own community.
	--
	-- The page used to open on a tall block of marketing copy, carried two
	-- headings both called "Your server", and left the servers you could actually
	-- join below the fold. Nothing here is decoration: the status strip answers
	-- the first question in one line so the rest of the page can be the answer to
	-- the second.
	renderCommunity = function()
		renderGeneration += 1
		local generation = renderGeneration
		clear(scroll)
		pageTitle.Text = "Servers"
		pageDescription.Text = "Move between official sessions without losing your place."
		local server = menuData and menuData.Server
		local kind = server and server.Kind or "Public"
		local community = server and server.Community

		local KIND_LABEL = {
			Public = "PUBLIC SERVER",
			Whitelisted = "WHITELISTED SERVER",
			Private = "PRIVATE SERVER",
			Reserved = "RESERVED SERVER",
		}
		local KIND_BLURB = {
			Public = "Open to everyone. Teams and passes are available here.",
			Whitelisted = "Entry is restricted, and services are held by group rank.",
			Private = "Run by its owner, to their own standards.",
			Reserved = "A dedicated instance of this experience.",
		}

		-- The servers the team runs, at the top. This is what almost everybody
		-- opens this page for, so nothing goes above it: not a status strip, not
		-- an explanation of what a community is.
		local officialResponse =
			context.Controllers.NetworkController:Request("GetOfficialServers", {})
		-- Another page was opened while that was in flight, so this one is stale
		-- and its container now belongs to whatever replaced it.
		if generation ~= renderGeneration then
			return
		end
		local officialRows = if officialResponse.Success
				and type(officialResponse.Data) == "table"
			then officialResponse.Data.Servers
			else nil
		if type(officialRows) == "table" and #officialRows > 0 then
			sectionHeading(
				"Official servers",
				"Choose the environment that matches how you want to play."
			)
			for _, entry in officialRows do
				local row = card(scroll, 118)
				local here = entry.Current == true
				local marker = Instance.new("Frame")
				marker.BackgroundColor3 = if here then COLOURS.Success else COLOURS.Accent
				marker.BorderSizePixel = 0
				marker.Position = UDim2.fromOffset(0, 16)
				marker.Size = UDim2.fromOffset(5, 86)
				marker.Parent = row
				local tier = text(
					row,
					if here then "CURRENT SESSION" else "OFFICIAL SERVER",
					11,
					if here then COLOURS.Success else COLOURS.Accent,
					true
				)
				tier.Position = UDim2.fromOffset(22, 16)
				tier.Size = UDim2.new(1, -190, 0, 16)
				local name = text(row, tostring(entry.Name), 21, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(22, 34)
				name.Size = UDim2.new(1, -190, 0, 28)
				local blurb = text(row, tostring(entry.Description or ""), 12, COLOURS.Muted)
				blurb.Position = UDim2.fromOffset(22, 66)
				blurb.Size = UDim2.new(1, -210, 0, 38)
				blurb.TextWrapped = true
				local join = Instance.new("TextButton")
				join.AutoButtonColor = false
				join.AnchorPoint = Vector2.new(1, 0.5)
				join.Position = UDim2.new(1, -20, 0.5, 0)
				join.Size = UDim2.fromOffset(140, 48)
				join.BackgroundColor3 = if here then COLOURS.SurfaceRaised else COLOURS.AccentFill
				join.BorderSizePixel = 0
				join.Font = Enum.Font.GothamBold
				join.Text = if here then "YOU ARE HERE" else "JOIN"
				join.TextColor3 = if here then COLOURS.Muted else COLOURS.Text
				join.TextSize = 13
				join.Active = not here
				join.Parent = row
				corner(join, 10)
				if not here then
					pressable(join)
				end
				join.Activated:Connect(function()
					if here then
						return
					end
					join.Active = false
					join.Text = "CONNECTING…"
					local response = context.Controllers.NetworkController:Request(
						"JoinOfficialServer",
						{ ServerId = entry.Id }
					)
					-- A teleport that works never comes back here, so anything
					-- arriving at this point is a refusal worth showing.
					join.Active = true
					join.Text = "JOIN"
					context.Controllers.NotificationController:Show(response.Message, "Servers")
					if not response.Success and audioFeedback then
						audioFeedback:Error()
					end
				end)
			end
		end

		-- Where you are now, below the servers you might go to instead. It is
		-- context rather than an action, so it does not take the top of the page.
		sectionHeading("This server", "What you have joined, and what that allows.")
		local whereCard = card(scroll, 96)
		local accent = Instance.new("Frame")
		accent.BackgroundColor3 = if kind == "Public" then COLOURS.Accent else COLOURS.Success
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(0, 18)
		accent.Size = UDim2.fromOffset(4, 60)
		accent.Parent = whereCard
		local kindLabel = text(whereCard, KIND_LABEL[kind] or "SERVER", 11, COLOURS.Accent, true)
		kindLabel.Position = UDim2.fromOffset(20, 18)
		kindLabel.Size = UDim2.new(1, -40, 0, 18)
		local whereName = text(
			whereCard,
			(community and community.Name)
				or (server and server.AccessGroupName)
				or "Emergency Response: Portsmouth",
			19,
			COLOURS.Text,
			true
		)
		whereName.Position = UDim2.fromOffset(20, 38)
		whereName.Size = UDim2.new(1, -40, 0, 26)
		local whereBlurb = text(whereCard, KIND_BLURB[kind] or "", 12, COLOURS.Muted)
		whereBlurb.Position = UDim2.fromOffset(20, 64)
		whereBlurb.Size = UDim2.new(1, -40, 0, 18)
	end

	local activeNav: TextButton? = nil
	-- isAction entries run their callback without taking the selected-page
	-- highlight, so overlays like Controls do not blank the content area.
	local function addNav(labelValue: string, render: () -> (), isAction: boolean?)
		local item = Instance.new("TextButton")
		item.AutoButtonColor = false
		item.BackgroundColor3 = COLOURS.Sidebar
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamMedium
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 14
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Size = UDim2.new(1, 0, 0, 40)
		item.Parent = navigation
		corner(item, 8)
		local itemPadding = Instance.new("UIPadding")
		itemPadding.PaddingLeft = UDim.new(0, 14)
		itemPadding.Parent = item
		pressable(item)
		item.Activated:Connect(function()
			if isAction then
				render()
				return
			end
			if activeNav then
				activeNav.BackgroundColor3 = COLOURS.Sidebar
				activeNav.TextColor3 = COLOURS.Muted
			end
			activeNav = item
			currentRender = render
			item.BackgroundColor3 = COLOURS.AccentSoft
			item.TextColor3 = COLOURS.Text
			render()
		end)
		return item
	end

	local playNav = addNav("Play", renderPlay)
	-- Civilian Jobs sits beside Play because it is somewhere to go and be, not
	-- something to buy. Without it the taxi shift has no entry point anywhere in
	-- the client. It is named for who the work is for: next to five emergency
	-- services, "Jobs" read as the place a player would look for a police job.
	addNav("Civilian Jobs", renderJobs)
	addNav("Store", renderStore)
	addNav("Servers", renderCommunity)
	addNav("Help", renderTutorials)
	navigation.Visible = false
	activeNav = playNav
	currentRender = renderPlay
	playNav.BackgroundColor3 = COLOURS.AccentSoft
	playNav.TextColor3 = COLOURS.Text

	local profile = card(sidebar, 68)
	profile.AnchorPoint = Vector2.new(0, 1)
	profile.Position = UDim2.new(0, 18, 1, -20)
	profile.Size = UDim2.new(1, -36, 0, 68)
	local playerName = text(profile, Players.LocalPlayer.DisplayName, 14, COLOURS.Text, true)
	playerName.Position = UDim2.fromOffset(14, 11)
	playerName.Size = UDim2.new(1, -28, 0, 24)
	local environment = text(profile, "Development environment", 11, COLOURS.Muted)
	environment.Position = UDim2.fromOffset(14, 35)
	environment.Size = UDim2.new(1, -28, 0, 20)

	local bottomNavItems: { [string]: TextButton } = {}
	local bottomNavRenders: { [string]: () -> () } = {}
	-- Run when the tab is pressed, and deliberately not stored as part of the
	-- render: currentRender is replayed on every server refresh and on every
	-- breakpoint change, so anything that resets what the player is looking at
	-- has to hang off the press instead of off the page.
	local bottomNavEnters: { [string]: () -> () } = {}
	local bottomNavOrder = 0
	-- Play is the single role-selection route. The dock only exposes the four
	-- destinations players need during a session; departments are filtered and
	-- joined from the Play screen itself.
	local bottomNavCount = 5
	selectBottomNav = function(key: string)
		local item = bottomNavItems[key]
		local render = bottomNavRenders[key]
		if not item or not render then
			return
		end
		for _, other in bottomNavItems do
			other.BackgroundColor3 = Color3.fromRGB(24, 31, 43)
			other.TextColor3 = COLOURS.Muted
		end
		item.BackgroundColor3 = Color3.fromRGB(82, 53, 142)
		item.TextColor3 = COLOURS.Text
		local enter = bottomNavEnters[key]
		if enter then
			enter()
		end
		currentRender = render
		render()
	end
	local function addBottomNav(
		labelValue: string,
		render: () -> (),
		key: string,
		onEnter: (() -> ())?
	)
		bottomNavOrder += 1
		local item = Instance.new("TextButton")
		item.Name = key .. "Tab"
		item.AutoButtonColor = false
		item.BackgroundColor3 = Color3.fromRGB(24, 31, 43)
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamBold
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 13
		-- Every tab gets an equal fifth of the dock, and the words are not of
		-- equal length: "Civilian Jobs" wants about ninety pixels and its share on
		-- a phone is nearer sixty. The dock is two lines tall, so the label uses
		-- the second one rather than running out over the tab beside it.
		item.TextWrapped = true
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.LayoutOrder = bottomNavOrder
		item.Size = UDim2.new(1 / bottomNavCount, -10, 1, 0)
		item.Selectable = true
		item.ZIndex = 21
		item.Parent = bottomDock
		corner(item, 10)
		stroke(item, COLOURS.Border, 0.25)
		pressable(item)
		bottomNavItems[key] = item
		bottomNavRenders[key] = render
		if onEnter then
			bottomNavEnters[key] = onEnter
		end
		item.Activated:Connect(function()
			if selectBottomNav then
				selectBottomNav(key)
			end
		end)
	end
	-- The same route names and callbacks are used by the compact dock and the
	-- desktop fallback sidebar, so changing page selection never leaves one of
	-- them highlighting a different destination.
	-- Pressing Play always lands on the full team list.
	--
	-- Joining a department leaves the page filtered to that department's own
	-- roles, and nothing was clearing that: a player who pressed JOIN on the
	-- Roads Policing Unit and then cancelled the station picker was left on a
	-- Play page offering the three policing roles and no route back to Civilian
	-- or to any other service. Rejoining the game was the only way out. The tab
	-- is the escape hatch a player reaches for first, so it clears the filter
	-- before rendering; the back control on the page itself is the other half.
	addBottomNav("Play", renderPlay, "Play", function()
		selectedTeamId = nil
	end)
	-- The label changes; the key does not. It is what the dock highlights by and
	-- what the desktop fallback matches on.
	addBottomNav("Civilian Jobs", renderJobs, "Jobs")
	addBottomNav("Store", renderStore, "Store")
	addBottomNav("Servers", renderCommunity, "Servers")
	addBottomNav("Help", renderTutorials, "Help")
	local defaultDockItem = bottomNavItems.Play
	if defaultDockItem then
		defaultDockItem.BackgroundColor3 = Color3.fromRGB(82, 53, 142)
		defaultDockItem.TextColor3 = COLOURS.Text
	end

	local function navCount(): number
		local count = 0
		for _, item in navigation:GetChildren() do
			if item:IsA("TextButton") then
				count += 1
			end
		end
		return math.max(1, count)
	end
	local lastResponsiveKey: string? = nil

	context.Controllers.UIOrchestrator:Bind("DeveloperDashboard", function(layout)
		local safeTop = layout.NativeTop
		local navItems = navCount()
		bleedBackdrop.Position = UDim2.fromOffset(0, -safeTop)
		bleedBackdrop.Size = UDim2.new(1, 0, 1, safeTop)
		-- Size the toggle from the band Roblox actually reports. Its position is
		-- deliberately relative to TopbarSafeInsets above, never to the gameplay
		-- viewport or a guessed native-cluster width.
		local reportedBand = math.floor(GuiService.TopbarInset.Height + 0.5)
		local nativeBand = if reportedBand > 0 then reportedBand else NATIVE_BAND_HEIGHT
		-- Sized and centred against Roblox's own controls rather than filling the
		-- band.
		--
		-- Measured on a running client: the native band is 58 high, its controls
		-- end at x=208, and a TopbarSafeInsets origin of (0, 0) already resolves
		-- to exactly 208 -- so the horizontal position was never the problem and
		-- adding NativeLeft here would double-count it, which is what the note
		-- about the 248px cluster guess was warning against.
		--
		-- The vertical was wrong. At 0.78 of the band the button came out 45 high
		-- against Roblox's ~36, and a fixed 2px gutter pinned it to the top of the
		-- row, so it read as taller than the native controls and sitting above
		-- them. Matching their proportion and centring it in the band puts the two
		-- on the same line at the same weight, which is what makes it look native
		-- rather than bolted on.
		local controlSize = math.clamp(math.floor(nativeBand * 0.62 + 0.5), 28, 44)
		local menuWidth = math.floor(controlSize * 1.9 + 0.5)
		menuToggle.Size = UDim2.fromOffset(math.clamp(menuWidth, 58, 78), controlSize)
		menuToggleCorner.CornerRadius = UDim.new(0, math.floor(controlSize * 0.34 + 0.5))
		local bandGap = math.max(0, math.floor((nativeBand - controlSize) / 2 + 0.5))
		menuToggle.Position = UDim2.fromOffset(NATIVE_CONTROL_GAP, bandGap)
		-- Compact already accounts for a short landscape phone, so the height is
		-- not tested again here.
		-- One navigation language on every device: a top bar mirrors Roblox's
		-- established menu pattern and avoids presenting desktop players with a
		-- completely different sidebar information architecture.
		local horizontal = true
		local narrow = layout.SafeViewport.X < 720
		-- Landscape phones have a short usable height but a wide viewport. Keep
		-- their header in a dedicated compact row instead of applying desktop
		-- title/navigation offsets that overlap on-screen controls.
		local compactLandscape = layout.SafeViewport.Y < 500
			and layout.SafeViewport.X > layout.SafeViewport.Y
		local safeLeft = layout.SafeLeft
		local safeRight = layout.SafeRight
		if horizontal then
			-- On a landscape phone Roblox's native controls consume the whole first
			-- row. Give the product identity and tabs their own row below it instead
			-- of placing the title into the native logo/chat/microphone cluster.
			-- Tall enough to actually contain the row, and no taller.
			--
			-- Measured on a running client at 1365x768: the band ended at y=38
			-- while the navigation row ran to y=50, so the tabs sat twelve pixels
			-- over the top of the content beneath them. On a narrow screen it was
			-- worse -- the title occupied 38..68 and the tabs 44..76, overlapping
			-- each other as well as the content, because both were positioned from
			-- the band top with no regard for the other's height.
			--
			-- These are now derived from what the row holds rather than picked, so
			-- the band shrinks and the overlap goes at the same time: the content
			-- below gains the twelve pixels it was losing plus the reduction.
			local barHeight = safeTop + (if narrow then 64 else if compactLandscape then 42 else 36)
			sidebar.Size = UDim2.new(1, 0, 0, barHeight)
			content.Position = UDim2.fromOffset(0, barHeight)
			content.Size = UDim2.new(1, 0, 1, -barHeight)
			-- In this stacked layout the title shares its row with Roblox's own
			-- controls, which sit at the top left. safeLeft only describes a
			-- device cutout, so clearing that alone left the title underneath
			-- them in portrait, where the control cluster is proportionally much
			-- wider. NativeLeft is where Roblox reports its controls end.
			local headerLeft = if compactLandscape
				then safeLeft + 18
				else math.max(safeLeft, layout.NativeLeft) + 18
			-- Keep the product name directly below Roblox's native control band.
			-- It should read as the experience identity, not compete with Roblox's
			-- own logo, chat and microphone controls.
			brand.Position = UDim2.fromOffset(
				headerLeft,
				if narrow then safeTop + 6 elseif compactLandscape then safeTop + 6 else safeTop + 8
			)
			brand.Size = UDim2.fromOffset(
				if compactLandscape
					then math.max(160, layout.SafeViewport.X - headerLeft - safeRight - 36)
					elseif narrow then math.max(
						80,
						layout.SafeViewport.X - headerLeft - safeRight - 18
					)
					else 270,
				30
			)
			brand.TextSize = 14
			brand.TextWrapped = false
			brand.TextScaled = false
			brand.TextTruncate = Enum.TextTruncate.AtEnd
			local brandBounds = brand:FindFirstChildOfClass("UITextSizeConstraint")
			if not brandBounds then
				brandBounds = Instance.new("UITextSizeConstraint")
				brandBounds.Parent = brand
			end
			brandBounds.MinTextSize = 10
			brandBounds.MaxTextSize = 17
			TooltipSystem:Attach(brand, brand.Text)
			-- Wide enough for the navigation to share the title's row, so it
			-- starts past the title rather than at a fixed offset that could
			-- land on top of it once the title has been pushed right.
			-- The title reserves less of the row on a short screen. It is decorative
			-- and already truncates, while the tabs beside it are the only way to
			-- move around the menu, and they were the thing being squeezed.
			local navLeft = headerLeft + 282
			navigation.Position = if narrow
				then UDim2.fromOffset(safeLeft + 18, safeTop + 32)
				elseif compactLandscape then UDim2.fromOffset(headerLeft, safeTop + 8)
				else UDim2.fromOffset(navLeft, safeTop + 4)
			navigation.Size = if narrow
				then UDim2.new(1, -(36 + safeLeft + safeRight), 0, 28)
				elseif compactLandscape then UDim2.new(
					1,
					-(headerLeft + safeRight + 18),
					0,
					28
				)
				else UDim2.new(1, -(navLeft + 18 + safeRight), 0, 28)
			navLayout.FillDirection = Enum.FillDirection.Horizontal
			navLayout.Padding = UDim.new(0, 6)
			for _, item in navigation:GetChildren() do
				if item:IsA("TextButton") then
					item.Size = UDim2.new(1 / navItems, -5, 1, 0)
					-- Shrink the label into its slot rather than letting it run out of one.
					--
					-- Every tab gets an equal share of the bar, but the words are not of
					-- equal length. "Civilian jobs" wants about ninety pixels and its share
					-- on a landscape phone is nearer eighty, so it overflowed and ran into
					-- "Services" next to it: the highlight of one ending underneath the text
					-- of the other. It read as a broken menu before the player had pressed
					-- anything.
					--
					-- Scaled to fit rather than truncated, because "Civilian j..." is not a
					-- usable label either. The floor is what stops the fit being achieved by
					-- making the text unreadable: below about nine pixels these stop being
					-- legible on a phone, and they are the only way around the menu.
					item.TextScaled = false
					item.TextTruncate = Enum.TextTruncate.AtEnd
					local bounds = item:FindFirstChildOfClass("UITextSizeConstraint")
					if not bounds then
						bounds = Instance.new("UITextSizeConstraint")
						bounds.Parent = item
					end
					bounds.MinTextSize = 10
					bounds.MaxTextSize = if narrow then 11 else 12
					item.TextXAlignment = Enum.TextXAlignment.Center
					TooltipSystem:Attach(item, item.Text)
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new()
					end
				end
			end
			profile.Visible = false
			-- Width taken from the parent rather than computed from SafeViewport.
			--
			-- The list is a child of a frame that already spans the screen, so a
			-- scale width with pixel margins is exactly the usable area by
			-- construction. Deriving an absolute width from SafeViewport instead
			-- meant the answer was only as good as that measurement, and when the
			-- two disagreed the list came up short and left a band of empty screen
			-- down the right of every page while the navigation above it ran the
			-- full width. Nothing here depends on that number any more.
			local marginLeft = safeLeft + 24
			local marginRight = safeRight + 24
			local available = layout.Viewport.X - marginLeft - marginRight
			local dockHeight = if narrow then 62 else 76
			bottomDock.Visible = true
			-- The rotating tip was creating a second header row on desktop. Keep the
			-- menu control in Roblox's top band and let the page content start directly
			-- beneath it; guidance remains available in Help.
			announcement.Visible = false
			bottomDock.Position = UDim2.new(0.5, 0, 1, -(layout.SafeBottom + 14))
			bottomDock.Size = UDim2.new(1, -(marginLeft + marginRight), 0, dockHeight)
			bottomDockPadding.PaddingLeft = UDim.new(0, if narrow then 5 else 8)
			bottomDockPadding.PaddingRight = UDim.new(0, if narrow then 5 else 8)
			bottomDockPadding.PaddingTop = UDim.new(0, if narrow then 5 else 8)
			bottomDockPadding.PaddingBottom = UDim.new(0, if narrow then 5 else 8)
			for _, item in bottomNavItems do
				item.TextSize = if narrow then 12 else 14
			end
			announcement.Position = UDim2.new(0.5, 0, 0, safeTop + 2)
			announcement.Size = UDim2.fromOffset(if narrow then 260 else 420, 28)
			pageTitle.Visible = false
			pageDescription.Visible = false
			status.Position = UDim2.fromScale(1, 0)
			if available > MAXIMUM_CONTENT_WIDTH then
				-- On a display wide enough for it, a centred column reads better than
				-- one line of text stretched across a metre of monitor.
				local centred = math.floor((layout.Viewport.X - MAXIMUM_CONTENT_WIDTH) / 2)
				header.Position = UDim2.fromOffset(centred, 6)
				header.Size = UDim2.fromOffset(MAXIMUM_CONTENT_WIDTH, 28)
				scroll.Position = UDim2.fromOffset(centred, 38)
				scroll.Size = UDim2.new(
					0,
					MAXIMUM_CONTENT_WIDTH,
					1,
					-(46 + layout.SafeBottom + dockHeight + 12)
				)
			else
				header.Position = UDim2.fromOffset(marginLeft, 6)
				header.Size = UDim2.new(1, -(marginLeft + marginRight), 0, 28)
				scroll.Position = UDim2.fromOffset(marginLeft, 38)
				scroll.Size = UDim2.new(
					1,
					-(marginLeft + marginRight),
					1,
					-(46 + layout.SafeBottom + dockHeight + 12)
				)
			end
		else
			bottomDock.Visible = false
			announcement.Visible = false
			-- The sidebar hugs the left edge, so it absorbs the left reserve and
			-- the content pane starts after it. Only the sidebar needs to know.
			sidebar.Size = UDim2.new(0, 250 + safeLeft, 1, 0)
			content.Position = UDim2.fromOffset(250 + safeLeft, 0)
			content.Size = UDim2.new(1, -(250 + safeLeft), 1, 0)
			brand.Position = UDim2.fromOffset(safeLeft + 26, safeTop + 20)
			brand.Size = UDim2.new(1, -(52 + safeLeft), 0, 42)
			brand.TextSize = 17
			brand.TextScaled = false
			brand.TextWrapped = true
			brand.TextTruncate = Enum.TextTruncate.None
			navigation.Position = UDim2.fromOffset(safeLeft + 18, safeTop + 112)
			navigation.Size = UDim2.new(1, -(36 + safeLeft), 0, navItems * 44 + (navItems - 1) * 7)
			navLayout.FillDirection = Enum.FillDirection.Vertical
			navLayout.Padding = UDim.new(0, 7)
			for _, item in navigation:GetChildren() do
				if item:IsA("TextButton") then
					item.Size = UDim2.new(1, 0, 0, 44)
					item.TextSize = 14
					item.TextXAlignment = Enum.TextXAlignment.Left
					local padding = item:FindFirstChildOfClass("UIPadding")
					if padding then
						padding.PaddingLeft = UDim.new(0, 14)
					end
				end
			end
			profile.Visible = true
			-- Desktop used to restore the title block that compact hides. Both now
			-- show the same status strip, so a page looks like itself whatever it
			-- is opened on, and the seventy pixels go to the content instead.
			pageTitle.Visible = false
			pageDescription.Visible = false
			header.Position = UDim2.fromOffset(44, safeTop + 16)
			header.Size = UDim2.new(1, -(88 + safeRight), 0, 24)
			status.Position = UDim2.new(1, -safeRight, 0, 0)
			scroll.Position = UDim2.fromOffset(44, safeTop + 48)
			scroll.Size = UDim2.new(1, -(88 + safeRight), 1, -(safeTop + 76 + layout.SafeBottom))
		end
		-- Cards have genuinely different compositions at these breakpoints, not
		-- merely different widths. Repaint only when a breakpoint changes so a
		-- phone rotation or window resize never leaves desktop cards squeezed into
		-- a mobile column, without doing work on every viewport-size signal.
		local responsiveKey = string.format(
			"%d:%s",
			portraitCardColumns(),
			if shortLandscape() then "short" else "standard"
		)
		if lastResponsiveKey and responsiveKey ~= lastResponsiveKey and currentRender then
			task.defer(currentRender)
		end
		lastResponsiveKey = responsiveKey
	end)

	context.Events.StartMenuChanged.Event:Connect(function(data)
		menuData = data
		if not selectedCharacterId and type(data.LastCharacterId) == "string" then
			-- Only when nothing is chosen yet, so a refresh never moves a choice
			-- the player has just made out from under them.
			for _, character in data.Characters or {} do
				if character.CharacterId == data.LastCharacterId then
					selectedCharacterId = data.LastCharacterId
					break
				end
			end
		end
		local gameName = data.Framework.GameName
		brand.Text = gameName
		status.Text = "●  Online  ·  " .. data.Server.Kind
		status.TextColor3 = COLOURS.Success
		finishLoading()
		if currentRender then
			currentRender()
		end
	end)
	context.Events.CharacterChanged.Event:Connect(function(characterId)
		if type(characterId) ~= "string" or characterId == "" then
			return
		end
		selectedCharacterId = characterId
		if menuData then
			menuData.ActiveCharacterId = characterId
		end
	end)
	-- Paint immediately so the menu is on screen while the first request is still
	-- in flight. The StartMenuChanged handler above fills in real data on success.
	setMenuOpen(true)
	renderPlay()
	task.spawn(function()
		local response = context.Controllers.StartMenuController:Refresh()
		if response.Success then
			return
		end
		status.Text = "●  CONNECTION ERROR"
		status.TextColor3 = COLOURS.Danger
		-- The overlay comes down on failure too.
		--
		-- It was hidden in exactly one place, inside the handler that fires only
		-- when the first request succeeds. So a player whose request failed was
		-- left on a full screen cover, at ZIndex 100, with the progress bar still
		-- sliding back and forth for ever, while this very message was written to
		-- a label underneath it. The only way out was a button labelled "Skip
		-- loading", which reads like an impatience shortcut rather than the exit
		-- from a broken state.
		--
		-- This is the first twenty seconds of the game for everybody and the only
		-- screen a new player has seen, so it is the worst place in the interface
		-- to say nothing.
		loadingStatus.Text = "Could not reach the server."
		loadingStatus.TextColor3 = COLOURS.Danger
		retryLoading.Visible = true
		context.Controllers.NotificationController:Show(
			"Could not reach the server. Reopen the menu to retry, or rejoin if it keeps failing.",
			"Error"
		)
		if audioFeedback then
			audioFeedback:Error()
		end
	end)

	if interfaceMotionEnabled() then
		root.Position = UDim2.fromOffset(0, 12)
		root.BackgroundTransparency = 1
		TweenService
			:Create(root, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 0,
			})
			:Play()
	end
	context.Controllers.SettingsController:Apply()
	return gui
end

return table.freeze(App)
