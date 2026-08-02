--!strict
local HttpService = game:GetService("HttpService")
local CallService = { calls = {}, revision = 0 }
function CallService:Init(context: any)
	self.context = context
end
function CallService:Start() end
function CallService:Create(data: any): (any?, string?)
	local incidentType = if table.find(
			self.context.Configuration.Dispatch.IncidentTypes,
			data.IncidentType
		)
		then data.IncidentType
		else "Emergency"
	if
		type(data.Summary) ~= "string"
		or #data.Summary < 3
		or #data.Summary > 160
		or (data.Location ~= nil and (type(data.Location) ~= "string" or #data.Location > 120))
		or not table.find(self.context.Configuration.Dispatch.CallPriorities, data.Priority)
	then
		return nil, "INVALID_CALL"
	end
	local departments = {}
	if type(data.DepartmentIds) == "table" then
		for _, departmentId in data.DepartmentIds do
			if
				type(departmentId) == "string"
				and self.context.Configuration.Departments[departmentId]
				and not table.find(departments, departmentId)
			then
				table.insert(departments, departmentId)
			end
		end
	end
	local call = {
		CallId = HttpService:GenerateGUID(false),
		Priority = data.Priority,
		Summary = data.Summary,
		Location = tostring(data.Location or "Unknown"),
		IncidentType = incidentType,
		CallerName = tostring(data.CallerName or "Unknown caller"),
		CallerNumber = tostring(data.CallerNumber or ""),
		Notes = tostring(data.Notes or ""),
		CreatedByUserId = tonumber(data.CreatedByUserId) or 0,
		UnitIds = {},
		Status = "Open",
		CreatedAt = os.time(),
		Revision = 1,
		DepartmentIds = departments,
		Source = tostring(data.Source or "Dispatch"),
	}
	self.calls[call.CallId] = call
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallCreated", call.CallId, self.revision)
	return call, nil
end
function CallService:Assign(callId: string, unitId: string): (boolean, string?)
	local call = self.calls[callId]
	local unit = self.context.Services:Get("UnitService").units[unitId]
	if not call or not unit then
		return false, "CALL_OR_UNIT_NOT_FOUND"
	end
	if unit.AssignedCallId and unit.AssignedCallId ~= callId then
		return false, "UNIT_ALREADY_ASSIGNED"
	end
	if #call.DepartmentIds > 0 and not table.find(call.DepartmentIds, unit.DepartmentId) then
		return false, "UNIT_DEPARTMENT_NOT_REQUESTED"
	end
	if not table.find(call.UnitIds, unitId) then
		table.insert(call.UnitIds, unitId)
	end
	unit.Status = "Assigned"
	unit.AssignedCallId = callId
	call.Status = "Assigned"
	call.Revision += 1
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallAssigned", callId, self.revision)
	return true, nil
end
function CallService:Update(callId: string, data: any): (any?, string?)
	local call = self.calls[callId]
	if not call or call.Status == "Closed" then
		return nil, "CALL_NOT_FOUND"
	end
	if data.Status ~= nil then
		if not table.find(self.context.Configuration.Dispatch.CallStatuses, data.Status) then
			return nil, "INVALID_CALL_STATUS"
		end
		call.Status = data.Status
	end
	if data.Priority ~= nil then
		if not table.find(self.context.Configuration.Dispatch.CallPriorities, data.Priority) then
			return nil, "INVALID_CALL_PRIORITY"
		end
		call.Priority = data.Priority
	end
	call.Revision += 1
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallUpdated", callId, self.revision)
	return call, nil
end
function CallService:Close(callId: string, closedByUserId: number?): (boolean, string?)
	local call = self.calls[callId]
	if not call or call.Status == "Resolved" then
		return false, "CALL_NOT_FOUND"
	end
	call.Status = "Resolved"
	call.ClosedAt = os.time()
	for _, unitId in call.UnitIds do
		local unit = self.context.Services:Get("UnitService").units[unitId]
		if unit then
			unit.AssignedCallId = nil
			self.context.Services:Get("UnitService"):SetStatus(unitId, "Available")
		end
	end
	call.Revision += 1
	self.context.Services:Get("IncidentService"):ScheduleFromCall(call, closedByUserId or 0)
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallClosed", callId, self.revision)
	return true, nil
end
function CallService:Snapshot(): { any }
	local result = {}
	for _, call in self.calls do
		if call.Status ~= "Resolved" then
			table.insert(result, table.clone(call))
		end
	end
	table.sort(result, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	return result
end
function CallService:Destroy()
	table.clear(self.calls)
	self.revision = 0
end
return CallService
