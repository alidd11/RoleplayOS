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

function DispatchPolicy.operationalNoteLimit(value: any): number
	local configured = tonumber(value)
	if type(configured) ~= "number" or configured ~= configured then
		return 50
	end
	return math.clamp(math.floor(configured), 0, 200)
end

return table.freeze(DispatchPolicy)
