--!strict

-- What a person on duty is allowed to do.
--
-- Department membership is not a rank or a complete authorisation decision.
-- Roles may narrow a department's default permissions explicitly; roles that do
-- not declare a permission list continue to inherit the department defaults.
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
