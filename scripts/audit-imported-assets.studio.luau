-- Run from the Studio Command Bar. Read-only: changes nothing.
--
-- Answers one question about imported content: does this experience have
-- permission to load the assets the kit ships?
--
-- A kit's README saying it includes rider animations is true and still leaves
-- them not playing. An Animation, a Sound and a mesh are all assets owned by an
-- account, and Roblox will only load one inside an experience owned by that same
-- account or its group. Import a bike made by somebody else and the model comes
-- across intact while its animations and sounds stay behind, because those are
-- references to assets on their account rather than copies of anything.
--
-- Sounds say so loudly: "User is not authorized to access Asset" in the console.
-- Animations mostly fail in silence, and the rider simply stands upright over
-- the seat in the default idle pose, which reads as a broken animation rather
-- than as a missing permission.
--
-- This lists every animation and sound the vehicles reference, who owns each
-- one, and whether it will actually load here. Anything reported as
-- INACCESSIBLE has to be re-uploaded to the account or group that owns this
-- experience and the ID swapped, or it will never play however correct the rest
-- of the setup is.

local MarketplaceService = game:GetService("MarketplaceService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Workspace = game:GetService("Workspace")

-- Optional: set to a model name to audit one vehicle instead of everything.
local ONLY: string? = nil

local function assetId(value: any): number?
	local digits = string.match(tostring(value or ""), "%d+")
	return if digits then tonumber(digits) else nil
end

-- Every asset reference we can see without reading script source, which the
-- command bar cannot do for scripts inside a model reliably.
local function collect(root: Instance, into: { [number]: string })
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Animation") then
			local id = assetId(descendant.AnimationId)
			if id and id > 0 then
				into[id] = "Animation"
			end
		elseif descendant:IsA("Sound") then
			local id = assetId(descendant.SoundId)
			if id and id > 0 then
				into[id] = "Sound"
			end
		end
	end
end

local function vehicles(): { Instance }
	local found = {}
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildWhichIsA("VehicleSeat", true) then
			if ONLY == nil or child.Name == ONLY then
				table.insert(found, child)
			end
		end
	end
	return found
end

local models = vehicles()
if #models == 0 then
	warn("[RoleplayOS] No vehicles found in Workspace. Is the model parked in the world?")
	return
end

-- Who owns this place. An asset by anybody else will not load inside it.
local placeOwner: string = "unknown"
local ok, info = pcall(function()
	return MarketplaceService:GetProductInfo(game.PlaceId)
end)
if ok and type(info) == "table" and type(info.Creator) == "table" then
	placeOwner = tostring(info.Creator.Name)
end
print(string.format("[RoleplayOS] Experience owner: %s", placeOwner))

local inaccessible = 0
local checked = 0

for _, model in models do
	local references: { [number]: string } = {}
	collect(model, references)
	local count = 0
	for _ in references do
		count += 1
	end
	print(string.format("\n[RoleplayOS] %s -- %d asset references", model.Name, count))
	if count == 0 then
		-- The interesting case for a bike whose README promises animations: the
		-- model holds no Animation instance at all, so the kit loads its IDs from
		-- inside a script and this audit cannot see them. Search the model's
		-- scripts for "rbxassetid" by hand in that case.
		print("   no Animation or Sound instances found -- IDs are probably held in scripts")
	end
	for id, kind in references do
		checked += 1
		local owner = "unknown"
		local productOk, product = pcall(function()
			return MarketplaceService:GetProductInfo(id)
		end)
		if productOk and type(product) == "table" and type(product.Creator) == "table" then
			owner = tostring(product.Creator.Name)
		end
		-- Ownership tells you what to expect; actually loading it tells you the
		-- truth, so both are reported. An animation is loadable only if its
		-- keyframes can be fetched here.
		local loadable = true
		if kind == "Animation" then
			loadable = pcall(function()
				return KeyframeSequenceProvider:GetKeyframeSequenceAsync("rbxassetid://" .. id)
			end)
		else
			loadable = owner == placeOwner or owner == "Roblox"
		end
		if not loadable then
			inaccessible += 1
		end
		print(
			string.format(
				"   %-9s %-14d owner: %-24s %s",
				kind,
				id,
				owner,
				if loadable then "ok" else "INACCESSIBLE -- re-upload and swap the ID"
			)
		)
	end
end

print(
	string.format(
		"\n[RoleplayOS] %d references checked, %d will not load in this experience.",
		checked,
		inaccessible
	)
)
if inaccessible > 0 then
	warn(
		"[RoleplayOS] Those assets belong to somebody else. The kit's README is not wrong "
			.. "that they exist; they are simply not yours to load. Re-upload each one to "
			.. "the group that owns this experience and replace the ID in the model."
	)
end
