--!strict

local CommunityGroupPolicy = {}

function CommunityGroupPolicy.resolveRole(highestRank: number, roleRanks: any): string?
	local selectedRoleId = nil
	local selectedRank = -1
	for roleId, requiredRank in roleRanks do
		if
			type(requiredRank) == "number"
			and highestRank >= requiredRank
			and requiredRank > selectedRank
		then
			selectedRoleId = roleId
			selectedRank = requiredRank
		end
	end
	return selectedRoleId
end

return table.freeze(CommunityGroupPolicy)
