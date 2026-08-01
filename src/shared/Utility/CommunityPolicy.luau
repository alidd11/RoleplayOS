--!strict

local CommunityPolicy = {}

function CommunityPolicy.hasPermission(template: any, membership: any, permission: string): boolean
	if not membership or membership.Status ~= "Active" then
		return false
	end
	local role = template.Roles[membership.RoleId]
	return role ~= nil
		and (
			table.find(role.Permissions, "*") ~= nil
			or table.find(role.Permissions, permission) ~= nil
		)
end

function CommunityPolicy.canManage(template: any, actor: any, target: any): boolean
	if not CommunityPolicy.hasPermission(template, actor, "Members.Manage") then
		return false
	end
	local actorRole = template.Roles[actor.RoleId]
	local targetRole = target and template.Roles[target.RoleId]
	return targetRole == nil or actorRole.Priority > targetRole.Priority
end

function CommunityPolicy.validatePolicies(policies: any): (boolean, string?)
	if type(policies) ~= "table" then
		return false, "INVALID_POLICIES"
	end
	if not table.find({ "Open", "Approval", "InviteOnly" }, policies.JoinMode) then
		return false, "INVALID_JOIN_MODE"
	end
	if
		type(policies.AllowPublicCivilian) ~= "boolean"
		or type(policies.RequireCommunityMembership) ~= "boolean"
	then
		return false, "INVALID_ACCESS_POLICY"
	end
	return true, nil
end

return table.freeze(CommunityPolicy)
