-- Run from the Roblox Studio Command Bar while not play-testing.
--
-- Turns a bare mesh Model into a RoleplayOS melee Tool and installs it at the
-- AssetPath its Config entry expects.
--
-- There is deliberately no damage script in the tool
-- --------------------------------------------------
-- Damage is owned by MeleeWeaponService on the server. It already checks that
-- the weapon is equipped, that the target is a different living player, that
-- they are inside the configured range, that the cooldown has elapsed, and that
-- nothing is between the two of them, before applying damage clamped to the
-- value in Config.Tools[id].Weapon. It also strips weapons on death and lets
-- police seize them.
--
-- A damage script living inside the Tool would duplicate every one of those
-- checks and, being replicated to the client, could be driven directly by an
-- exploiter: unlimited rate, unlimited range, through walls, and surviving
-- seizure. The tool therefore carries geometry and nothing else, which is also
-- what lets it pass content validation without a manifest entry.
--
-- Usage
-- -----
--   1. Set SOURCE and TOOL_ID below.
--   2. Run in the Command Bar.
--   3. Check the grip in Studio: the handle is placed from the mesh bounding
--      box, which is a starting point rather than an art direction. Nudge
--      Tool.Grip until it sits correctly in the hand.

local ServerStorage = game:GetService("ServerStorage")

-- The Model of meshes to convert, and the Config.Tools id it becomes.
local SOURCE = workspace:FindFirstChild("ZKnife")
local TOOL_ID = "ZKnife"

-- Where the tool is installed, matching Config.Tools[TOOL_ID].AssetPath.
local ASSET_PATH = { "Tools", "Civilian", TOOL_ID }

-- The grip end of a blade is the smallest dimension of its bounding box; the
-- handle is sized to sit inside the fist rather than to match the blade.
local HANDLE_SIZE = Vector3.new(0.3, 0.3, 0.9)

if not SOURCE then
	warn("[assemble-melee-tool] Source model not found. Set SOURCE.")
	return
end

local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
if not assets then
	warn("[assemble-melee-tool] ServerStorage.RoleplayOSAssets is missing.")
	return
end

-- Walks to the parent folder, creating any missing level, then reports the leaf
-- name the tool must be given.
local function ensureParent(root: Instance, path: { string }): (Instance, string)
	local current = root
	for index = 1, #path - 1 do
		local segment = path[index]
		local child = current:FindFirstChild(segment)
		if not child then
			local folder = Instance.new("Folder")
			folder.Name = segment
			folder.Parent = current
			child = folder
		end
		current = child
	end
	return current, path[#path]
end

local parent, leafName = ensureParent(assets, ASSET_PATH)

-- The existing entry is a placeholder Folder in every case here, but check
-- rather than assume: replacing a real Tool that somebody built would be worse
-- than refusing to run.
local existing = parent:FindFirstChild(leafName)
if existing and existing:IsA("Tool") then
	warn(
		"[assemble-melee-tool] "
			.. existing:GetFullName()
			.. " is already a Tool. Delete it first if you meant to rebuild it."
	)
	return
end

local source = SOURCE:Clone()

local tool = Instance.new("Tool")
tool.Name = leafName
tool.ToolTip = TOOL_ID
tool.CanBeDropped = false
tool.RequiresHandle = true
tool:SetAttribute("RoleplayOSToolId", TOOL_ID)
tool:SetAttribute("RoleplayOSWeaponId", TOOL_ID)

-- Roblox needs a part named Handle to hold the tool by. The imported meshes are
-- blade geometry with no grip among them, so the handle is its own invisible
-- part and the meshes are welded to it at their existing offsets. That keeps the
-- model looking exactly as imported while giving the engine something to grip.
local boxCFrame, boxSize = source:GetBoundingBox()

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = HANDLE_SIZE
handle.Transparency = 1
handle.CanCollide = false
handle.CanQuery = false
handle.Massless = true
handle.CFrame = boxCFrame * CFrame.new(0, 0, boxSize.Z / 2 - HANDLE_SIZE.Z / 2)
handle.Parent = tool

local welded = 0
for _, descendant in source:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.Anchored = false
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = descendant
		weld.Parent = handle
		welded += 1
	end
end

-- Reparent the geometry itself, textures included, and drop the now-empty
-- wrapper Model: a Tool holds parts directly.
for _, child in source:GetChildren() do
	child.Parent = tool
end
source:Destroy()

-- A blade points away from the hand and sits roughly along the forearm. This is
-- a sane default rather than a measured one; confirm it in Studio.
tool.Grip = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, 0)

if existing then
	existing:Destroy()
end
tool.Parent = parent

print(
	string.format(
		"[assemble-melee-tool] Built %s at %s (%d parts welded to Handle). "
			.. "Check Tool.Grip in Studio.",
		TOOL_ID,
		tool:GetFullName(),
		welded
	)
)
