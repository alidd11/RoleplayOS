-- Run once from the Studio Command Bar while NOT play-testing.
--
-- Sets up the world-asset side of the baseplate so the only work left is
-- dragging things to where they belong on the real map.
--
-- There are two parallel systems in this framework and only one of them was
-- ever set up here, which is why the content audit reports six kinds missing
-- while the features themselves half work.
--
-- Services find their content by a functional tag: RoadSafetyService looks for
-- RoleplayOSSpeedCamera, the CCTV system for RoleplayOSCCTV, custody for its
-- desk tag, and so on. That is what makes a camera actually catch somebody.
--
-- The content audit wants the same models certified: carrying the
-- RoleplayOSWorldAsset tag, an RoleplayOSAssetKind and a stable
-- RoleplayOSAssetId, and living at
-- Workspace/RoleplayOSWorldAssets/<Kind>/<Model>. That is what makes the place
-- publishable. Your five speed cameras satisfy the first and none of the
-- second, so they work and do not count.
--
-- This adopts whatever already exists into the certified structure rather than
-- creating duplicates of it, and puts a clearly labelled marker in the folders
-- that have nothing yet so the structure is complete and visible. Markers are
-- meant to be moved into position and then have real content built onto or
-- swapped into them.
--
-- Safe to run more than once. Nothing is deleted and anything already certified
-- is left alone.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(not RunService:IsRunning(), "Stop the play test before setting up the baseplate")

local config = require(game.ReplicatedStorage.RoleplayOS.Config.Config)
local quality = config.ContentQuality
local ROOT_NAME = quality.WorldAssetRootName
local WORLD_TAG = quality.WorldAssetTag

-- Which functional tag already marks content of each kind. A kind with no tag
-- has no discovery mechanism of its own yet, so it only ever gets a marker.
local SOURCE_TAG = {
	SpeedCamera = config.RoadSafety.SpeedCameraTag,
	CCTVCamera = config.CCTV.CameraTag,
	ANPRCamera = config.CCTV.SensorTag,
	CustodyFurniture = config.Custody.BookingDeskTag,
	DispatchFurniture = config.Dispatch.SeatTag,
	DealershipNPC = nil,
}

local root = Workspace:FindFirstChild(ROOT_NAME)
if not root then
	root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = Workspace
	print("[RoleplayOS] Created Workspace." .. ROOT_NAME)
end

-- A stable ID that will not collide with a second run or a second model.
local used: { [string]: boolean } = {}
for _, descendant in root:GetDescendants() do
	local existing = descendant:GetAttribute("RoleplayOSAssetId")
	if type(existing) == "string" and existing ~= "" then
		used[existing] = true
	end
end

local function uniqueId(kind: string): string
	local index = 1
	while used[string.format("%s%02d", kind, index)] do
		index += 1
	end
	local id = string.format("%s%02d", kind, index)
	used[id] = true
	return id
end

-- The visible model a tagged part belongs to. A tag is often on a part inside
-- the model rather than on the model itself.
local function modelOf(instance: Instance): Instance?
	if instance:IsA("Model") then
		return instance
	end
	local current = instance.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function certify(model: Instance, kind: string, folder: Folder)
	if not CollectionService:HasTag(model, WORLD_TAG) then
		CollectionService:AddTag(model, WORLD_TAG)
	end
	model:SetAttribute("RoleplayOSAssetKind", kind)
	local id = model:GetAttribute("RoleplayOSAssetId")
	if type(id) ~= "string" or id == "" then
		model:SetAttribute("RoleplayOSAssetId", uniqueId(kind))
	end
	-- The audit requires the model to be a direct child of its kind folder, and
	-- that folder a direct child of the root. Reparenting keeps the model's world
	-- position, so nothing moves on screen.
	if model.Parent ~= folder then
		model.Parent = folder
	end
end

-- A marker for a kind with nothing to adopt. Deliberately obvious: a bright
-- floating block with a label, so it is easy to find in a large map and
-- impossible to mistake for finished content.
local function marker(kind: string, folder: Folder, offset: number): Model
	local model = Instance.new("Model")
	model.Name = kind .. "Placeholder"
	local part = Instance.new("Part")
	part.Name = "Marker"
	part.Size = Vector3.new(4, 4, 4)
	part.Position = Vector3.new(offset * 8, 8, -40)
	part.Anchored = true
	part.CanCollide = false
	part.Color = Color3.fromRGB(241, 176, 47)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.25
	part.Parent = model
	model.PrimaryPart = part
	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(220, 46)
	label.StudsOffset = Vector3.new(0, 3, 0)
	label.AlwaysOnTop = true
	label.Parent = part
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 13
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.Text = kind .. "\nplaceholder - move and replace"
	text.Parent = label
	model.Parent = folder
	return model
end

local adopted, created = {}, {}
for index, kind in quality.RequiredWorldAssetKinds do
	local folder = root:FindFirstChild(kind)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = kind
		folder.Parent = root
	end

	-- Adopt anything already carrying this kind's functional tag.
	local found = 0
	local sourceTag = SOURCE_TAG[kind]
	if type(sourceTag) == "string" and sourceTag ~= "" then
		local seen: { [Instance]: boolean } = {}
		for _, tagged in CollectionService:GetTagged(sourceTag) do
			if tagged:IsDescendantOf(Workspace) then
				local model = modelOf(tagged)
				if model and model ~= root and not seen[model] then
					seen[model] = true
					certify(model, kind, folder :: Folder)
					found += 1
				end
			end
		end
	end

	-- Count anything already sitting in the folder, adopted just now or not.
	local certified = 0
	for _, child in (folder :: Folder):GetChildren() do
		if child:IsA("Model") then
			certified += 1
		end
	end
	if certified == 0 then
		marker(kind, folder :: Folder, index)
		table.insert(created, kind)
	elseif found > 0 then
		table.insert(adopted, string.format("%s (%d)", kind, found))
	end
end

print("\n[RoleplayOS] Baseplate world assets")
print("  root: Workspace." .. ROOT_NAME)
if #adopted > 0 then
	print("  adopted existing content: " .. table.concat(adopted, ", "))
end
if #created > 0 then
	print("  placeholders created for: " .. table.concat(created, ", "))
	print("  those are the kinds with no real content yet -- move them into")
	print("  position on the map, then build or swap the real thing onto them.")
end
print("  run the game once and the content audit will confirm what is certified.")
