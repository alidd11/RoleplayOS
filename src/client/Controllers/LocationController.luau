--!strict

-- Names the place the player is standing in, along the top of the screen.
--
-- Streets and districts are authored as invisible parts in the map, tagged and
-- carrying their name as an attribute, so naming the world is a mapping job
-- rather than a code change. Membership is resolved through the engine's
-- spatial index rather than by testing every zone, so the cost of the check
-- does not grow with the number of streets in the world.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local LocationController = { connections = {}, running = false }

function LocationController:Init(context: any)
	self.context = context
	self.settings = Config.Locations
	self.street = ""
	self.district = ""
end

function LocationController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSLocation"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	-- Ambient, like the rest of the heads-up display, so an opened device
	-- covers it rather than the other way round.
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local holder = Instance.new("Frame")
	holder.Name = "Location"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(420, 44)
	holder.Visible = false
	holder.Parent = gui
	self.holder = holder
	local holderScale = Instance.new("UIScale")
	holderScale.Parent = holder
	self.holderScale = holderScale

	local street = Instance.new("TextLabel")
	street.Name = "Street"
	street.BackgroundTransparency = 1
	street.Font = Enum.Font.GothamBold
	street.Text = ""
	street.TextColor3 = Color3.fromRGB(245, 248, 253)
	street.TextSize = 19
	street.TextStrokeTransparency = 0.65
	street.TextTruncate = Enum.TextTruncate.AtEnd
	street.Size = UDim2.new(1, 0, 0, 24)
	street.Parent = holder
	self.streetLabel = street

	local district = Instance.new("TextLabel")
	district.Name = "District"
	district.BackgroundTransparency = 1
	district.Font = Enum.Font.GothamMedium
	district.Text = ""
	district.TextColor3 = Color3.fromRGB(168, 182, 202)
	district.TextSize = 12
	district.TextStrokeTransparency = 0.8
	district.TextTruncate = Enum.TextTruncate.AtEnd
	district.Position = UDim2.fromOffset(0, 24)
	district.Size = UDim2.new(1, 0, 0, 16)
	district.Parent = holder
	self.districtLabel = district
end

-- Rebuilds the query filter. Collecting is the only pass proportional to the
-- number of zones, so it is separated from the per-check work and coalesced.
function LocationController:_collect()
	local zones = {}
	for _, item in CollectionService:GetTagged(self.settings.ZoneTag) do
		if item:IsA("BasePart") then
			table.insert(zones, item)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = zones
	params.MaxParts = self.settings.MaximumOverlaps
	self.params = params
	self.zoneCount = #zones
end

-- The zone the player stands in. Where zones overlap, the one with the highest
-- Priority attribute wins, so a district can enclose its streets without the
-- larger area masking the smaller.
function LocationController:_resolve(position: Vector3): (string, string)
	if not self.params or self.zoneCount == 0 then
		return "", ""
	end
	local hits =
		workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(1, 1, 1), self.params)
	local bestPriority = -math.huge
	local street, district = "", ""
	for _, zone in hits do
		local priority = zone:GetAttribute("Priority")
		priority = if type(priority) == "number" then priority else 0
		if priority >= bestPriority then
			local name = zone:GetAttribute("StreetName")
			local area = zone:GetAttribute("DistrictName")
			if type(name) == "string" and name ~= "" then
				bestPriority = priority
				street = name
				district = if type(area) == "string" then area else ""
			end
		end
	end
	return street, district
end

function LocationController:_show(street: string, district: string)
	if street == self.street and district == self.district then
		return
	end
	self.street = street
	self.district = district
	self.streetLabel.Text = street
	self.districtLabel.Text = string.upper(district)
	self.districtLabel.Visible = district ~= ""
	self.holder.Visible = street ~= ""
	if street == "" then
		return
	end
	-- A short fade marks the change without drawing attention to itself. Players
	-- who have asked for reduced motion get the name without the movement.
	local settings = self.context.Controllers.SettingsController:Get()
	if settings and settings.InterfaceMotion == false then
		self.holder.Position = UDim2.new(0.5, 0, 0, self.top)
		self.streetLabel.TextTransparency = 0
		return
	end
	self.streetLabel.TextTransparency = 1
	self.holder.Position = UDim2.new(0.5, 0, 0, self.top + 8)
	TweenService:Create(self.streetLabel, TweenInfo.new(0.28, Enum.EasingStyle.Quart), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(self.holder, TweenInfo.new(0.28, Enum.EasingStyle.Quart), {
		Position = UDim2.new(0.5, 0, 0, self.top),
	}):Play()
end

function LocationController:Start()
	self:_mount()
	if not self.settings.Enabled then
		return
	end
	self.top = 0
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Location", function(layout)
		-- Sits under Roblox's own top bar, centred, and steps down further while
		-- driving so it does not sit on the vehicle readouts.
		self.holderScale.Scale = layout.HudScale
		self.top = layout.NativeTop + (if layout.Vehicle then 12 else 6)
		self.holder.Position = UDim2.new(0.5, 0, 0, self.top)
		self.holder.Size = UDim2.fromOffset(
			math.min(420, layout.SafeViewport.X - 40),
			if layout.Compact then 38 else 44
		)
		self.streetLabel.TextSize = if layout.Compact then 16 else 19
	end)

	local pending = false
	local function requestCollect()
		if pending then
			return
		end
		pending = true
		task.delay(self.settings.RecollectSeconds, function()
			pending = false
			if self.running then
				self:_collect()
			end
		end)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.settings.ZoneTag):Connect(requestCollect)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(self.settings.ZoneTag):Connect(requestCollect)
	)

	self.running = true
	self:_collect()
	task.spawn(function()
		while self.running do
			task.wait(self.settings.UpdateSeconds)
			-- Guarded for the same reason as the minimap: resolving a location
			-- reads world geometry that can be mid-stream, and a throw would stop
			-- the street name updating for the rest of the session.
			local ok, problem = pcall(function()
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					self:_show(self:_resolve(root.Position))
				else
					self:_show("", "")
				end
			end)
			if not ok and not self.complained then
				self.complained = true
				warn("RoleplayOS location update failed: " .. tostring(problem))
			end
		end
	end)
end

function LocationController:Destroy()
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

return LocationController
