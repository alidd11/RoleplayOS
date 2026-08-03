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
	gui.ClipToDeviceSafeArea = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local shell = Instance.new("Frame")
	shell.Name = "Minimap"
	shell.AnchorPoint = Vector2.new(1, 0.5)
	shell.Position = UDim2.new(1, -18, 0.5, 0)
	shell.Size = UDim2.fromOffset(184, 208)
	shell.BackgroundColor3 = C.Surface
	shell.BorderSizePixel = 0
	shell.Parent = gui
	self.shell = shell
	corner(shell, 13)
	local shellStroke = Instance.new("UIStroke")
	shellStroke.Color = Color3.fromRGB(52, 66, 88)
	shellStroke.Transparency = 0.15
	shellStroke.Parent = shell

	local title = makeLabel(shell, "AREA MAP", 10)
	title.Position = UDim2.fromOffset(12, 5)
	title.Size = UDim2.new(1, -24, 0, 20)
	title.TextColor3 = C.Muted

	local viewport = Instance.new("Frame")
	viewport.Name = "VectorMap"
	viewport.Position = UDim2.fromOffset(8, 26)
	viewport.Size = UDim2.new(1, -16, 1, -34)
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

function MinimapController:_drawRoad(part: BasePart, bounds: BasePart)
	local point = self:_project(part.Position, bounds)
	local road = Instance.new("Frame")
	road.Name = "Road"
	road.AnchorPoint = Vector2.new(0.5, 0.5)
	road.Position = UDim2.fromScale(point.X, point.Y)
	local footprint = MapProjection.footprint(part.Size, bounds.Size, 0.003)
	road.Size = UDim2.fromScale(footprint.X, footprint.Y)
	road.Rotation = -part.Orientation.Y + bounds.Orientation.Y
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
end

function MinimapController:_drawPoint(item: Instance, bounds: BasePart)
	local position: Vector3?
	if item:IsA("BasePart") then
		position = item.Position
	elseif item:IsA("Attachment") then
		position = item.WorldPosition
	end
	if not position then
		return
	end
	local point = self:_project(position, bounds)
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
end

function MinimapController:_rebuild()
	local bounds = self:_bounds()
	self.bounds = bounds
	self:_clearGeometry()
	if not bounds then
		self.gui.Enabled = false
		return
	end
	local roadCount = 0
	for _, item in CollectionService:GetTagged(self.settings.RoadTag) do
		if roadCount >= self.settings.MaximumRoads then
			break
		end
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			self:_drawRoad(item, bounds)
			roadCount += 1
		end
	end
	local pointCount = 0
	for _, item in CollectionService:GetTagged(self.settings.PointTag) do
		if pointCount >= self.settings.MaximumPoints then
			break
		end
		if item:IsDescendantOf(workspace) then
			self:_drawPoint(item, bounds)
			pointCount += 1
		end
	end
	self.gui.Enabled = self.settings.Enabled
end

function MinimapController:_updateMarker()
	local bounds = self.bounds
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not bounds or not root or not root:IsA("BasePart") then
		self.marker.Visible = false
		return
	end
	local point = self:_project(root.Position, bounds)
	self.marker.Position = UDim2.fromScale(point.X, point.Y)
	local localLook = bounds.CFrame:VectorToObjectSpace(root.CFrame.LookVector)
	self.marker.Rotation = math.deg(math.atan2(-localLook.X, -localLook.Z))
	self.marker.Visible = true
end

function MinimapController:Start()
	self:_mount()
	if not self.settings.Enabled then
		return
	end
	for _, tag in { self.settings.BoundsTag, self.settings.RoadTag, self.settings.PointTag } do
		table.insert(
			self.connections,
			CollectionService:GetInstanceAddedSignal(tag):Connect(function()
				self:_rebuild()
			end)
		)
		table.insert(
			self.connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(function()
				self:_rebuild()
			end)
		)
	end
	self:_rebuild()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Minimap", function(layout)
		self.shell.Visible = not layout.Vehicle or not layout.Compact
		self.shell.AnchorPoint = if layout.Vehicle then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
		self.shell.Position = if layout.Vehicle
			then UDim2.new(0, 18, 0.52, 0)
			else UDim2.new(1, -layout.RightReserve, 0.5, 0)
		self.shell.Size = if layout.Vehicle
			then UDim2.fromOffset(150, 170)
			else UDim2.fromOffset(
				if layout.Compact then 150 else 184,
				if layout.Compact then 170 else 208
			)
	end)
	self.running = true
	task.spawn(function()
		while self.running do
			self:_updateMarker()
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
