--!strict

-- Command and control map surface for the MDT.
--
-- Static geometry (roads, points of interest) is read from tagged workspace
-- instances and rebuilt only when asked. Live overlays (incidents, units) are
-- redrawn from the dispatch snapshot, which is server-authoritative: the client
-- never decides where a unit or an incident is.

local CollectionService = game:GetService("CollectionService")
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

	local key = Instance.new("Frame")
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromOffset(4, 62)
	key.Size = UDim2.new(1, -8, 1, -66)
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

	return self
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

-- Rebuilds road and point-of-interest geometry. Static between map edits, so
-- this is deliberately not called on the live refresh path.
function TacticalMap:Rebuild()
	self.static:ClearAllChildren()
	local bounds = self:_bounds()
	self.empty.Visible = bounds == nil
	if not bounds then
		return
	end
	local roads = 0
	for _, item in CollectionService:GetTagged(self.settings.RoadTag) do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			roads += 1
			if roads > self.settings.MaximumRoads then
				break
			end
			local point = MapProjection.project(item.Position, bounds.CFrame, bounds.Size)
			local footprint = MapProjection.footprint(item.Size, bounds.Size, 0.003)
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
	for _, item in CollectionService:GetTagged(self.settings.PointTag) do
		local position: Vector3? = nil
		if item:IsA("BasePart") then
			position = item.Position
		elseif item:IsA("Attachment") then
			position = item.WorldPosition
		end
		if position then
			points += 1
			if points > self.settings.MaximumPoints then
				break
			end
			local point = MapProjection.project(position, bounds.CFrame, bounds.Size)
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
			if typeof(caption) == "string" and caption ~= "" then
				local text = label(dot, caption, 9)
				text.Position = UDim2.fromOffset(9, -4)
				text.Size = UDim2.fromOffset(120, 15)
				text.ZIndex = 3
				text.TextColor3 = C.Muted
			end
		end
	end
end

-- Redraws incidents and units from a server dispatch snapshot.
function TacticalMap:Update(snapshot: any)
	self.overlay:ClearAllChildren()
	local bounds = self:_bounds()
	if not bounds or type(snapshot) ~= "table" then
		self.counts.Text = "Awaiting dispatch feed."
		return
	end
	local calls = if type(snapshot.Calls) == "table" then snapshot.Calls else {}
	local units = if type(snapshot.Units) == "table" then snapshot.Units else {}
	local plotted = 0

	for _, call in calls do
		local position = MapProjection.deserialise(call.Position)
		if position then
			plotted += 1
			local colour = PRIORITY[call.Priority] or PRIORITY.Routine
			local point = MapProjection.project(position, bounds.CFrame, bounds.Size)
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
		if position then
			located += 1
			local colour = STATUS[unit.Status] or STATUS.Unavailable
			local point = MapProjection.project(position, bounds.CFrame, bounds.Size)
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
		"%d incident%s (%d mapped)\n%d unit%s (%d located)",
		#calls,
		if #calls == 1 then "" else "s",
		plotted,
		#units,
		if #units == 1 then "" else "s",
		located
	)
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
