--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)

local MinimapController = { connections = {}, running = false }
local C = {
	Surface = Color3.fromRGB(14, 20, 30),
	Map = Color3.fromRGB(22, 30, 42),
	Road = Color3.fromRGB(80, 91, 108),
	RoadEdge = Color3.fromRGB(112, 124, 143),
	Text = Color3.fromRGB(244, 247, 252),
	Muted = Color3.fromRGB(151, 163, 184),
	Accent = Color3.fromRGB(91, 156, 255),
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function makeLabel(parent: Instance, text: string, size: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.Text = text
	item.TextColor3 = C.Text
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

function MinimapController:Init(context: any)
	self.context = context
	self.settings = Config.Minimap
end

function MinimapController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSMinimap"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local shell = Instance.new("Frame")
	shell.Name = "Minimap"
	shell.AnchorPoint = Vector2.new(1, 0.5)
	shell.Position = UDim2.new(1, -18, 0.5, 0)
	shell.Size = UDim2.fromOffset(Config.Minimap.PanelSize.X, Config.Minimap.PanelSize.Y)
	shell.BackgroundColor3 = C.Surface
	shell.BorderSizePixel = 0
	shell.Parent = gui
	self.shell = shell
	-- Scaling the shell keeps every offset inside it in proportion, rather than
	-- each one having to be adjusted for device size individually.
	local shellScale = Instance.new("UIScale")
	shellScale.Parent = shell
	self.shellScale = shellScale
	corner(shell, 13)
	local shellStroke = Instance.new("UIStroke")
	shellStroke.Color = Color3.fromRGB(52, 66, 88)
	shellStroke.Transparency = 0.15
	shellStroke.Parent = shell

	-- No title. It read "AREA MAP" above a picture of the area, which is a label
	-- for a thing that does not need one, and it cost twenty six pixels of height
	-- plus the padding around it on a panel people want smaller.
	local viewport = Instance.new("Frame")
	viewport.Name = "VectorMap"
	viewport.Position = UDim2.fromOffset(5, 5)
	viewport.Size = UDim2.new(1, -10, 1, -10)
	viewport.BackgroundColor3 = C.Map
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.Parent = shell
	corner(viewport, 9)
	self.viewport = viewport

	local marker = Instance.new("TextLabel")
	marker.Name = "PlayerMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(18, 18)
	marker.BackgroundTransparency = 1
	marker.Font = Enum.Font.GothamBold
	marker.Text = "▲"
	marker.TextColor3 = C.Accent
	marker.TextSize = 17
	marker.ZIndex = 10
	marker.Parent = viewport
	self.marker = marker
end

function MinimapController:_bounds(): BasePart?
	for _, item in CollectionService:GetTagged(self.settings.BoundsTag) do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			return item
		end
	end
	return nil
end

function MinimapController:_project(position: Vector3, bounds: BasePart): Vector2
	local point = MapProjection.project(position, bounds.CFrame, bounds.Size)
	return Vector2.new(point.X, point.Y)
end

function MinimapController:_clearGeometry()
	for _, child in self.viewport:GetChildren() do
		if child ~= self.marker then
			child:Destroy()
		end
	end
end

function MinimapController:_drawRoad(part: BasePart, centre: Vector3, radius: number): boolean
	local point = MapProjection.window(part.Position, centre, radius)
	if not point then
		return false
	end
	local road = Instance.new("Frame")
	road.Name = "Road"
	road.AnchorPoint = Vector2.new(0.5, 0.5)
	road.Position = UDim2.fromScale(point.X, point.Y)
	local footprint = MapProjection.windowFootprint(part.Size, radius, 0.006)
	road.Size = UDim2.fromScale(footprint.X, footprint.Y)
	road.Rotation = -part.Orientation.Y
	road.BackgroundColor3 = C.Road
	road.BorderSizePixel = 0
	road.ZIndex = 2
	road.Parent = self.viewport
	corner(road, 2)
	local edge = Instance.new("UIStroke")
	edge.Color = C.RoadEdge
	edge.Transparency = 0.5
	edge.Thickness = 1
	edge.Parent = road
	return true
end

function MinimapController:_drawPoint(item: Instance, centre: Vector3, radius: number): boolean
	local position: Vector3? = nil
	if item:IsA("BasePart") then
		position = item.Position
	elseif item:IsA("Attachment") then
		position = item.WorldPosition
	end
	if not position then
		return false
	end
	local point = MapProjection.window(position, centre, radius)
	if not point then
		return false
	end
	local dot = Instance.new("Frame")
	dot.Name = "PointOfInterest"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(point.X, point.Y)
	dot.Size = UDim2.fromOffset(7, 7)
	local colour = item:GetAttribute("MinimapColour")
	dot.BackgroundColor3 = if typeof(colour) == "Color3" then colour else C.Accent
	dot.BorderSizePixel = 0
	dot.ZIndex = 4
	dot.Parent = self.viewport
	corner(dot, 4)

	local text = item:GetAttribute("MinimapLabel")
	if typeof(text) == "string" and text ~= "" then
		local caption = makeLabel(dot, text, 9)
		caption.Position = UDim2.fromOffset(8, -4)
		caption.Size = UDim2.fromOffset(100, 16)
		caption.ZIndex = 4
	end
	return true
end

-- Collects the tagged geometry once. This is the only pass that is proportional
-- to the size of the map, so it is deliberately separated from drawing and run
-- rarely: on a region-sized world it walks tens of thousands of parts.
function MinimapController:_collect()
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
	self.collectedAt = os.clock()
end

-- Draws the window around the player. Cost is bounded by what is near, not by
-- how large the world is, and the caps now trim a set that was already sorted
-- by distance rather than taking an arbitrary slice of the whole map.
function MinimapController:_redraw(centre: Vector3)
	self:_clearGeometry()
	local radius = self.settings.WindowRadius or 900
	local maximumRoads = if self.compact
		then self.settings.CompactMaximumRoads or self.settings.MaximumRoads
		else self.settings.MaximumRoads
	local maximumPoints = if self.compact
		then self.settings.CompactMaximumPoints or self.settings.MaximumPoints
		else self.settings.MaximumPoints
	local drawn = 0
	for _, part in self.roads do
		if drawn >= maximumRoads then
			break
		end
		-- Streaming can remove a part after it was collected, so presence is
		-- rechecked here rather than trusted from collection time.
		if part.Parent and self:_drawRoad(part, centre, radius) then
			drawn += 1
		end
	end
	local points = 0
	for _, item in self.points do
		if points >= maximumPoints then
			break
		end
		if item.Parent and self:_drawPoint(item, centre, radius) then
			points += 1
		end
	end
	self.drawnAt = centre
end

function MinimapController:_rebuild()
	local bounds = self:_bounds()
	self.bounds = bounds
	self:_collect()
	self.drawnAt = nil
	self.gui.Enabled = self.settings.Enabled
end

function MinimapController:_updateMarker()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		self.marker.Visible = false
		return
	end
	-- The window follows the player, so the marker is always centred and only
	-- its heading changes. Geometry is redrawn once the player has left the
	-- centre far enough for the offset to show, rather than every frame.
	self.marker.Position = UDim2.fromScale(0.5, 0.5)
	self.marker.Rotation =
		math.deg(math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z))
	self.marker.Visible = true
	local threshold = self.settings.RedrawDistance or 60
	local previous = self.drawnAt
	if not previous or (root.Position - previous).Magnitude >= threshold then
		self:_redraw(root.Position)
	end
end

function MinimapController:Start()
	self:_mount()
	if not self.settings.Enabled then
		return
	end
	-- The handset and the terminal occupy the same corner as the minimap, so it
	-- steps aside while either is open instead of showing through the device.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function followDeviceState()
		self.shell.Visible = playerGui:GetAttribute("RoleplayOSDeviceOpen") ~= true
	end
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSDeviceOpen"):Connect(followDeviceState)
	)
	followDeviceState()
	-- Streaming a region-sized world adds and removes tagged parts continuously,
	-- and each collect walks every tagged instance. Rebuilding per signal meant
	-- dozens of full passes a second while driving, so changes are coalesced
	-- into at most one pass per interval.
	local pending = false
	local function requestRebuild()
		if pending then
			return
		end
		pending = true
		task.delay(self.settings.RecollectSeconds or 3, function()
			pending = false
			if self.running then
				self:_rebuild()
			end
		end)
	end
	for _, tag in { self.settings.BoundsTag, self.settings.RoadTag, self.settings.PointTag } do
		table.insert(
			self.connections,
			CollectionService:GetInstanceAddedSignal(tag):Connect(requestRebuild)
		)
		table.insert(
			self.connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(requestRebuild)
		)
	end
	self.running = true
	self:_rebuild()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Minimap", function(layout)
		self.shellScale.Scale = layout.HudScale
		-- Detail follows the panel size, so a change of breakpoint has to force a
		-- redraw: without it the map keeps whatever density it was built with
		-- until the player next moves far enough to trigger one.
		if self.compact ~= layout.Compact then
			self.compact = layout.Compact
			self.drawnAt = nil
		end
		-- Visible while driving, including on a phone, where it used to be hidden
		-- outright. A map you cannot see while driving is the one moment it exists
		-- for, and a mobile officer was sent to an address they saw once with no
		-- way to find it.
		self.shell.Visible = true
		self.shell.AnchorPoint = if layout.Vehicle then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
		-- Sits above centre on touch, where a sprint pad shares the right edge and
		-- a centred minimap would land on top of it.
		self.shell.Position = if layout.Vehicle
			then UDim2.new(0, 18, self.settings.VehicleAnchorY, 0)
			elseif layout.InputMode == "Touch" then UDim2.new(1, -layout.RightReserve, 0.36, 0)
			else UDim2.new(1, -layout.RightReserve, 0.5, 0)
		local panel = if layout.Vehicle or layout.Compact
			then self.settings.CompactPanelSize
			else self.settings.PanelSize
		self.shell.Size = UDim2.fromOffset(panel.X, panel.Y)
	end)
	self.running = true
	task.spawn(function()
		local complained = false
		while self.running do
			-- Guarded, because this is the only thing that moves the marker and a
			-- throw would leave the map frozen with the player's dot where it was
			-- when it happened. Said once: at eight ticks a second a repeating
			-- fault would fill the console on its own.
			local ok, problem = pcall(self._updateMarker, self)
			if not ok and not complained then
				complained = true
				warn("RoleplayOS minimap update failed: " .. tostring(problem))
			end
			task.wait(1 / self.settings.UpdateHz)
		end
	end)
end

function MinimapController:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return MinimapController
