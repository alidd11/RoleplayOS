-- Run once from the Studio Command Bar while NOT play-testing.
-- Finds uniquely named knife Tools already present in the place and copies them
-- into the ServerStorage asset tree managed by Rojo.

assert(
	not game:GetService("RunService"):IsRunning(),
	"Stop the play test before installing civilian knife assets"
)

local ServerStorage = game:GetService("ServerStorage")

local targetRoot = ServerStorage:FindFirstChild("RoleplayOSAssets") or Instance.new("Folder")
targetRoot.Name = "RoleplayOSAssets"
targetRoot.Parent = ServerStorage

local toolsRoot = targetRoot:FindFirstChild("Tools") or Instance.new("Folder")
toolsRoot.Name = "Tools"
toolsRoot.Parent = targetRoot

local civilianRoot = toolsRoot:FindFirstChild("Civilian") or Instance.new("Folder")
civilianRoot.Name = "Civilian"
civilianRoot.Parent = toolsRoot

local function isInside(instance: Instance, ancestor: Instance): boolean
	return instance == ancestor or instance:IsDescendantOf(ancestor)
end

local function findCandidates(toolName: string): { Tool }
	local candidates = {}
	for _, descendant in game:GetDescendants() do
		if
			descendant:IsA("Tool")
			and descendant.Name == toolName
			and not isInside(descendant, targetRoot)
		then
			table.insert(candidates, descendant)
		end
	end
	return candidates
end

local installed = 0
for _, toolName in { "Knife", "Machete", "RamboKnife", "ZKnife" } do
	local candidates = findCandidates(toolName)
	if #candidates == 0 then
		warn("No Studio Tool found for " .. toolName)
		continue
	end
	if #candidates > 1 then
		local locations = {}
		for _, candidate in candidates do
			table.insert(locations, candidate:GetFullName())
		end
		warn(
			"Skipping ambiguous "
				.. toolName
				.. "; choose one source Tool. Found: "
				.. table.concat(locations, ", ")
		)
		continue
	end

	local destination = civilianRoot:FindFirstChild(toolName)
	if destination then
		destination:Destroy()
	end

	local clone = candidates[1]:Clone()
	clone.Name = toolName
	clone.Parent = civilianRoot
	installed += 1
	print("Installed " .. toolName .. " from " .. candidates[1]:GetFullName())
end

print(
	string.format(
		"Installed %d civilian knife asset(s). Rojo source path: server-assets/Tools/Civilian",
		installed
	)
)
