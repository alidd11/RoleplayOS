-- Run from the Roblox Studio Command Bar while not play-testing.
--
-- Prints a ready-to-paste ContentQuality.CertifiedAssets entry for an imported
-- asset, listing every executable descendant it currently contains.
--
-- Why this exists
-- ---------------
-- Practically everything in this game is imported, and imported content is full
-- of scripts: a single vehicle carries thirty to forty between its chassis, its
-- lighting kit and its sound system, and it cannot drive without them. A rule
-- that forbids scripts outright is therefore a rule that would be bypassed on
-- every asset, which protects nothing and blocks everything.
--
-- What the manifest actually buys is change detection. It pins the exact set of
-- executables an asset contained at the moment it was accepted, so anything that
-- appears later -- a backdoor added to a model, a script slipped into an update
-- of a marketplace asset, an edit nobody meant to publish -- fails validation
-- and names itself, instead of running unnoticed on the live server.
--
-- It is deliberately not a claim that anybody has read those scripts. Record
-- honestly in `Source` where the asset came from, and use `ReviewedBy` to say
-- what was actually done, so the manifest never overstates its own assurance.
--
-- Usage
-- -----
--   1. Set TARGET_PATH below to the asset, from ServerStorage.
--   2. Run in the Command Bar.
--   3. Paste the printed block into ContentQuality.CertifiedAssets in
--      src/shared/Config/Config.luau, then edit Source/ReviewedBy to the truth.
--   4. Re-run the place and confirm the asset no longer reports UNSAFE_*.

-- Example: the taxi. Change this to whichever asset you are registering.
local TARGET_PATH = { "RoleplayOSAssets", "Vehicles", "Services", "Transport", "CorollaTaxi" }
local ASSET_ID = "CorollaTaxi"

-- Mirrors ContentValidationService's own forbidden set. Anything matching here
-- has to appear in the manifest or the asset is rejected.
local FORBIDDEN_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	UnreliableRemoteEvent = true,
	BindableEvent = true,
	BindableFunction = true,
	ProximityPrompt = true,
	ClickDetector = true,
}

local function resolve(path)
	local current = game
	for _, segment in ipairs(path) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

local function relativePath(root, descendant)
	local parts = {}
	local current = descendant
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return parts
end

local function quote(value)
	return '"' .. value .. '"'
end

local root = resolve(TARGET_PATH)
if not root then
	warn("Asset not found at " .. table.concat(TARGET_PATH, "."))
	return
end

-- Grouped by name because the config table is keyed that way. A name carrying
-- more than one entry is emitted as a list, which the validator accepts.
local byName = {}
local order = {}
local total = 0
for _, descendant in ipairs(root:GetDescendants()) do
	if FORBIDDEN_CLASSES[descendant.ClassName] or descendant:IsA("LuaSourceContainer") then
		local name = descendant.Name
		if not byName[name] then
			byName[name] = {}
			table.insert(order, name)
		end
		table.insert(byName[name], {
			ClassName = descendant.ClassName,
			Path = relativePath(root, descendant),
		})
		total += 1
	end
end

table.sort(order)

local lines = {}
table.insert(lines, "\t\t\t" .. ASSET_ID .. " = {")
table.insert(lines, "\t\t\t\tCertified = true,")
table.insert(lines, "\t\t\t\tReviewVersion = 1,")
table.insert(lines, '\t\t\t\tSource = "TODO: where this asset came from",')
table.insert(lines, '\t\t\t\tRealWorldReference = "TODO",')
table.insert(
	lines,
	'\t\t\t\tReviewedBy = "Imported asset inventory pinned by '
		.. 'generate-asset-certification.studio.luau; not a line-by-line source review",'
)
table.insert(lines, "\t\t\t\tAllowedUnsafeDescendants = {")

for _, name in ipairs(order) do
	local entries = byName[name]
	-- A name needing brackets is not a valid Lua identifier, so emit it keyed.
	local key = if string.match(name, "^[%a_][%w_]*$") then name else "[" .. quote(name) .. "]"
	if #entries == 1 then
		local entry = entries[1]
		local segments = {}
		for _, segment in ipairs(entry.Path) do
			table.insert(segments, quote(segment))
		end
		table.insert(
			lines,
			"\t\t\t\t\t"
				.. key
				.. " = { ClassName = "
				.. quote(entry.ClassName)
				.. ", Path = { "
				.. table.concat(segments, ", ")
				.. " } },"
		)
	else
		table.insert(lines, "\t\t\t\t\t" .. key .. " = {")
		for _, entry in ipairs(entries) do
			local segments = {}
			for _, segment in ipairs(entry.Path) do
				table.insert(segments, quote(segment))
			end
			table.insert(
				lines,
				"\t\t\t\t\t\t{ ClassName = "
					.. quote(entry.ClassName)
					.. ", Path = { "
					.. table.concat(segments, ", ")
					.. " } },"
			)
		end
		table.insert(lines, "\t\t\t\t\t},")
	end
end

table.insert(lines, "\t\t\t\t},")
table.insert(lines, "\t\t\t},")

print(
	string.format(
		"-- %s: %d executable descendants across %d distinct names",
		ASSET_ID,
		total,
		#order
	)
)
print(table.concat(lines, "\n"))
