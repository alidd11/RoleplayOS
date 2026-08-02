--!strict

local DispatchPolicy = {}

function DispatchPolicy.canUseMdt(duty: any?, allowedDepartments: { string }): boolean
	return type(duty) == "table"
		and type(duty.DepartmentId) == "string"
		and table.find(allowedDepartments, duty.DepartmentId) ~= nil
end

function DispatchPolicy.canDispatch(
	duty: any?,
	allowedDepartments: { string },
	isInDispatchSeat: boolean
): boolean
	return isInDispatchSeat and DispatchPolicy.canUseMdt(duty, allowedDepartments)
end

return table.freeze(DispatchPolicy)
