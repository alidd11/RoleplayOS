--!strict
-- This script is mapped only by acceptance.project.json. Never map the tests folder
-- into the production place.

local ok, problem = pcall(function()
	require(script.Parent.run)
end)

if not ok then
	warn("[RoleplayOS Acceptance] Pure contract suite failed: " .. tostring(problem))
	error(problem, 0)
end

print("[RoleplayOS Acceptance] Pure contract suite completed")
