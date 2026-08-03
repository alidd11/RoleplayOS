--!strict

-- Command and control map surface for the MDT.
--
-- Static geometry (roads, points of interest) is read from tagged workspace
-- instances and rebuilt only when asked. Live overlays (incidents, units) are
-- redrawn from the dispatch snapshot, which is server-authoritative: the client
-- never decides where a unit or an incident is.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)

local TacticalMap = {}
TacticalMap.__index = TacticalMap

local C = {
	Surface = Color3.fromRGB(9, 21, 34),
	Grid = Color3.fromRGB(20, 44, 66),
	Road = Color3.fromRGB(56, 78, 102),
	RoadEdge = Color3.fromRGB(84, 116, 148),
	Text = Color3.fromRGB(238, 244, 251),
	Muted = Color3.fromRGB(146, 162, 184),
	Accent = Color3.fromRGB(27, 137, 191),
}

-- Grade 1/2/3 in the familiar UK response-grade colours.
local PRIORITY: { [string]: Color3 } = {
	Immediate = Color3.fromRGB(233, 66, 74),
	Prompt = Color3.fromRGB(240, 173, 51),
	Routine = Color3.fromRGB(83, 170, 226),
}

local STATUS: { [string]: Color3 } = {
	Available = Color3.fromRGB(88, 206, 138),
	Assigned = Color3.fromRGB(240, 173, 51),
	OnScene = Color3.fromRGB(83, 170, 226),
	Unavailable = Color3.fromRGB(132, 146, 166),
}

-- Control needs the whole picture, but a region-sized world drawn whole leaves
-- every road a few thousandths of the surface wide and every label on top of
-- its neighbour. Closer levels follow the officer and keep the geometry
-- readable. A radius of zero means the whole mapped area.
local ZOOM = {
	{ Name = "REGION", Radius = 0 },
	{ Name = "DISTRICT", Radius = 2600 },
	{ Name = "LOCAL", Radius = 800 },
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextSize = size
	item.TextColor3 = C.Text
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

function TacticalMap.new(parent: Instance)
	local self = setmetatable({}, TacticalMap)
	self.settings = Config.Minimap
	-- Control opens on the whole picture; an officer can close in from there.
	self.zoomIndex = 1
	self.roads = {}
	self.points = {}

	local root = Instance.new("Frame")
	root.Name = "TacticalMap"
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent
	self.root = root

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundColor3 = C.Surface
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.Size = UDim2.new(1, -190, 1, 0)
	canvas.Parent = root
	corner(canvas, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Grid
	stroke.Parent = canvas
	self.canvas = canvas

	local static = Instance.new("Frame")
	static.Name = "Static"
	static.BackgroundTransparency = 1
	static.Size = UDim2.fromScale(1, 1)
	static.Parent = canvas
	self.static = static

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Parent = canvas
	self.overlay = overlay

	local empty = label(canvas, "NO MAPPED AREA", 12, true)
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.fromOffset(300, 40)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextColor3 = C.Muted
	self.empty = empty

	local side = Instance.new("Frame")
	side.Name = "Legend"
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Size = UDim2.new(0, 178, 1, 0)
	side.BackgroundTransparency = 1
	side.Parent = root
	self.side = side

	local heading = label(side, "LIVE PICTURE", 11, true)
	heading.Position = UDim2.fromOffset(4, 2)
	heading.Size = UDim2.new(1, -8, 0, 18)
	heading.TextColor3 = C.Accent

	local counts = label(side, "", 11)
	counts.Position = UDim2.fromOffset(4, 22)
	counts.Size = UDim2.new(1, -8, 0, 34)
	counts.TextWrapped = true
	counts.TextYAlignment = Enum.TextYAlignment.Top
	counts.TextColor3 = C.Muted
	self.counts = counts

	-- Zoom controls sit with the legend rather than over the map, so they never
	-- cover the picture they change.
	local zoomRow = Instance.new("Frame")
	zoomRow.Name = "Zoom"
	zoomRow.BackgroundTransparency = 1
	zoomRow.Position = UDim2.fromOffset(4, 62)
	zoomRow.Size = UDim2.new(1, -8, 0, 26)
	zoomRow.Parent = side
	self.zoomButtons = {}
	for index, level in ZOOM do
		local option = Instance.new("TextButton")
		option.AutoButtonColor = false
		option.BackgroundColor3 = C.Grid
		option.BorderSizePixel = 0
		option.Font = Enum.Font.GothamBold
		option.Text = string.sub(level.Name, 1, 3)
		option.TextColor3 = C.Text
		option.TextSize = 9
		option.Size = UDim2.new(1 / #ZOOM, -4, 1, 0)
		option.Position = UDim2.new((index - 1) / #ZOOM, 2, 0, 0)
		option.Parent = zoomRow
		corner(option, 6)
		option.Activated:Connect(function()
			self.zoomIndex = index
			self:_paintZoom()
			self:Redraw()
		end)
		self.zoomButtons[index] = option
	end

	local key = Instance.new("Frame")
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromOffset(4, 94)
	key.Size = UDim2.new(1, -8, 1, -98)
	key.Parent = side
	local keyLayout = Instance.new("UIListLayout")
	keyLayout.Padding = UDim.new(0, 5)
	keyLayout.Parent = key

	local function keyRow(colour: Color3, name: string, shape: string)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 17)
		row.Parent = key
		local swatch = Instance.new("Frame")
		swatch.Size =
			UDim2.fromOffset(if shape == "unit" then 9 else 10, if shape == "unit" then 9 else 10)
		swatch.Position = UDim2.fromOffset(0, 4)
		swatch.BackgroundColor3 = colour
		swatch.BorderSizePixel = 0
		swatch.Parent = row
		corner(swatch, if shape == "unit" then 5 else 2)
		local name2 = label(row, name, 10)
		name2.Position = UDim2.fromOffset(16, 0)
		name2.Size = UDim2.new(1, -16, 1, 0)
		name2.TextColor3 = C.Muted
	end

	keyRow(PRIORITY.Immediate, "GRADE 1  IMMEDIATE", "call")
	keyRow(PRIORITY.Prompt, "GRADE 2  PROMPT", "call")
	keyRow(PRIORITY.Routine, "GRADE 3  ROUTINE", "call")
	keyRow(STATUS.Available, "UNIT AVAILABLE", "unit")
	keyRow(STATUS.Assigned, "UNIT ASSIGNED", "unit")
	keyRow(STATUS.OnScene, "UNIT ON SCENE", "unit")
	keyRow(STATUS.Unavailable, "UNIT UNAVAILABLE", "unit")
	keyRow(C.Accent, "POINT OF INTEREST", "call")

	self:_paintZoom()
	return self
end

function TacticalMap:_paintZoom()
	for index, option in self.zoomButtons do
		option.BackgroundColor3 = if index == self.zoomIndex then C.Accent else C.Grid
	end
end

function TacticalMap:_bounds(): BasePart?
	for _, item in CollectionService:GetTagged(self.settings.BoundsTag) do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			return item
		end
	end
	return nil
end

function TacticalMap:_marker(
	parent: Instance,
	point: MapProjection.Point,
	size: number,
	colour: Color3,
	round: boolean,
	zIndex: number
): Frame
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(point.X, point.Y)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = colour
	dot.BorderSizePixel = 0
	dot.ZIndex = zIndex
	dot.Parent = parent
	corner(dot, if round then math.floor(size / 2) else 2)
	return dot
end

-- Collects the tagged geometry. This is the only pass proportional to the size
-- of the world, so it is separated from drawing and run only when asked.
function TacticalMap:Rebuild()
	self.roads = {}
	self.points = {}
	for _, item in CollectionService:GetTagged(self.settings.RoadTag) do
		if item:IsA("BasePart") then
			table.insert(self.roads, item)
		end
	end
	for _, item in CollectionService:GetTagged(self.settings.PointTag) do
		if item:IsA("BasePart") or item:IsA("Attachment") then
			table.insert(self.points, item)
		end
	end
	self:Redraw()
end

-- Where the view is centred. The region view frames the whole mapped area;
-- closer levels follow the officer carrying the terminal.
function TacticalMap:_centre(bounds: BasePart): Vector3
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if ZOOM[self.zoomIndex].Radius > 0 and root and root:IsA("BasePart") then
		return root.Position
	end
	return bounds.Position
end

-- Projects a world position for the current zoom. The region view clamps, so
-- everything appears somewhere; closer levels return nil outside the window so
-- the caller can skip rather than pin it to an edge.
function TacticalMap:_place(
	position: Vector3,
	bounds: BasePart,
	centre: Vector3
): MapProjection.Point?
	local radius = ZOOM[self.zoomIndex].Radius
	if radius <= 0 then
		return MapProjection.project(position, bounds.CFrame, bounds.Size)
	end
	return MapProjection.window(position, centre, radius)
end

function TacticalMap:_footprint(partSize: Vector3, bounds: BasePart): MapProjection.Point
	local radius = ZOOM[self.zoomIndex].Radius
	if radius <= 0 then
		return MapProjection.footprint(partSize, bounds.Size, 0.002)
	end
	return MapProjection.windowFootprint(partSize, radius, 0.006)
end

function TacticalMap:_drawStatic(bounds: BasePart, centre: Vector3)
	self.static:ClearAllChildren()
	local drawn = 0
	for _, item in self.roads do
		if drawn >= self.settings.MaximumRoads then
			break
		end
		-- Streaming can remove a part after it was collected.
		local point = if item.Parent then self:_place(item.Position, bounds, centre) else nil
		if point then
			drawn += 1
			local footprint = self:_footprint(item.Size, bounds)
			local road = Instance.new("Frame")
			road.AnchorPoint = Vector2.new(0.5, 0.5)
			road.Position = UDim2.fromScale(point.X, point.Y)
			road.Size = UDim2.fromScale(footprint.X, footprint.Y)
			road.Rotation = -item.Orientation.Y + bounds.Orientation.Y
			road.BackgroundColor3 = C.Road
			road.BorderSizePixel = 0
			road.ZIndex = 2
			road.Parent = self.static
			corner(road, 2)
			local edge = Instance.new("UIStroke")
			edge.Color = C.RoadEdge
			edge.Transparency = 0.55
			edge.Thickness = 1
			edge.Parent = road
		end
	end
	local points = 0
	for _, item in self.points do
		if points >= self.settings.MaximumPoints then
			break
		end
		local position: Vector3? = nil
		if item.Parent and item:IsA("BasePart") then
			position = item.Position
		elseif item.Parent and item:IsA("Attachment") then
			position = item.WorldPosition
		end
		local point = if position then self:_place(position, bounds, centre) else nil
		if point then
			points += 1
			local colour = item:GetAttribute("MinimapColour")
			local dot = self:_marker(
				self.static,
				point,
				7,
				if typeof(colour) == "Color3" then colour else C.Accent,
				false,
				3
			)
			local caption = item:GetAttribute("MinimapLabel")
			-- Labels are omitted on the region view, where they would overlap
			-- into an unreadable mass.
			if
				typeof(caption) == "string"
				and caption ~= ""
				and ZOOM[self.zoomIndex].Radius > 0
			then
				local text = label(dot, caption, 9)
				text.Position = UDim2.fromOffset(9, -4)
				text.Size = UDim2.fromOffset(120, 15)
				text.ZIndex = 3
				text.TextColor3 = C.Muted
			end
		end
	end
end

function TacticalMap:_drawOverlay(bounds: BasePart, centre: Vector3)
	self.overlay:ClearAllChildren()
	local snapshot = self.snapshot
	local calls = if type(snapshot) == "table" and type(snapshot.Calls) == "table"
		then snapshot.Calls
		else {}
	local units = if type(snapshot) == "table" and type(snapshot.Units) == "table"
		then snapshot.Units
		else {}
	local plotted = 0
	for _, call in calls do
		local position = MapProjection.deserialise(call.Position)
		local point = if position then self:_place(position, bounds, centre) else nil
		if point then
			plotted += 1
			local colour = PRIORITY[call.Priority] or PRIORITY.Routine
			-- A halo keeps a live incident readable against road geometry.
			local halo = self:_marker(self.overlay, point, 20, colour, true, 5)
			halo.BackgroundTransparency = 0.72
			local dot = self:_marker(self.overlay, point, 10, colour, true, 6)
			local caption =
				label(dot, string.upper(tostring(call.IncidentType or "INCIDENT")), 9, true)
			caption.Position = UDim2.fromOffset(12, -5)
			caption.Size = UDim2.fromOffset(150, 16)
			caption.ZIndex = 6
			caption.TextColor3 = colour
		end
	end
	local located = 0
	for _, unit in units do
		local position = MapProjection.deserialise(unit.Position)
		local point = if position then self:_place(position, bounds, centre) else nil
		if point then
			located += 1
			local colour = STATUS[unit.Status] or STATUS.Unavailable
			local dot = self:_marker(self.overlay, point, 9, colour, true, 7)
			local edge = Instance.new("UIStroke")
			edge.Color = Color3.fromRGB(10, 20, 32)
			edge.Thickness = 1.5
			edge.Parent = dot
			local caption = label(dot, tostring(unit.Callsign or "?"), 9, true)
			caption.Position = UDim2.fromOffset(11, -5)
			caption.Size = UDim2.fromOffset(90, 16)
			caption.ZIndex = 7
			caption.TextColor3 = colour
		end
	end
	self.counts.Text = string.format(
		"%s\n%d incident%s (%d shown)\n%d unit%s (%d shown)",
		ZOOM[self.zoomIndex].Name,
		#calls,
		if #calls == 1 then "" else "s",
		plotted,
		#units,
		if #units == 1 then "" else "s",
		located
	)
end

-- Redraws both layers at the current zoom without recollecting the world.
function TacticalMap:Redraw()
	local bounds = self:_bounds()
	self.empty.Visible = bounds == nil
	if not bounds then
		self.static:ClearAllChildren()
		self.overlay:ClearAllChildren()
		self.counts.Text = "No mapped area."
		return
	end
	local centre = self:_centre(bounds)
	self:_drawStatic(bounds, centre)
	self:_drawOverlay(bounds, centre)
end

-- Stores the latest server picture and redraws the live layer.
function TacticalMap:Update(snapshot: any)
	self.snapshot = snapshot
	local bounds = self:_bounds()
	if not bounds then
		self.counts.Text = "No mapped area."
		return
	end
	self:_drawOverlay(bounds, self:_centre(bounds))
end

function TacticalMap:SetVisible(visible: boolean)
	self.root.Visible = visible
end

function TacticalMap:SetSize(size: UDim2, position: UDim2)
	self.root.Size = size
	self.root.Position = position
end

function TacticalMap:Destroy()
	self.root:Destroy()
end

return TacticalMap
