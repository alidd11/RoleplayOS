--!strict

-- What a person on duty is allowed to do.
--
-- Every police power in this framework used to key on the department, and a
-- department is not a rank. PCSO is deliberately free on the public tier and
-- its department is Police, so that one fact handed every player the powers the
-- police pass is sold for: the full person record including custody and
-- criminal history, warrant creation and revocation, search, escort, and
-- booking somebody into a half hour sentence.
--
-- The configuration said the opposite in two places, both reasoning that a PCSO
-- carries no handcuffs and that the custody workflow is gated on carrying them.
-- That was true of one path out of six.
--
-- Permissions therefore resolve from the role first and fall back to the
-- department. A role that says nothing inherits its department, which keeps
-- every existing role behaving exactly as before; a role that needs to differ
-- from its department says so in one place.
local RolePermissions = {}

function RolePermissions.forDuty(configuration: any, duty: any): { string }
	if type(duty) ~= "table" or type(duty.DepartmentId) ~= "string" then
		return {}
	end
	local role = duty.RoleId and configuration.Roles[duty.RoleId]
	if role and type(role.Permissions) == "table" then
		return role.Permissions
	end
	local byDepartment = configuration.MDT and configuration.MDT.PermissionByDepartment
	return (byDepartment and byDepartment[duty.DepartmentId]) or {}
end

function RolePermissions.has(configuration: any, duty: any, permission: string): boolean
	return table.find(RolePermissions.forDuty(configuration, duty), permission) ~= nil
end

return table.freeze(RolePermissions)
