--!strict
local HttpService = game:GetService("HttpService")
local CallService = { calls = {} }
function CallService:Init(context: any)
	self.context = context
end
function CallService:Start() end
function CallService:Create(data: any): (any?, string?)
	if
		type(data.Summary) ~= "string"
		or #data.Summary < 3
		or #data.Summary > 160
		or not table.find(self.context.Configuration.Dispatch.CallPriorities, data.Priority)
	then
		return nil, "INVALID_CALL"
	end
	local call = {
		CallId = HttpService:GenerateGUID(false),
		Priority = data.Priority,
		Summary = data.Summary,
		Location = tostring(data.Location or "Unknown"),
		UnitIds = {},
		Status = "Open",
		CreatedAt = os.time(),
	}
	self.calls[call.CallId] = call
	return call, nil
end
function CallService:Assign(callId: string, unitId: string): (boolean, string?)
	local call = self.calls[callId]
	local unit = self.context.Services:Get("UnitService").units[unitId]
	if not call or not unit then
		return false, "CALL_OR_UNIT_NOT_FOUND"
	end
	if not table.find(call.UnitIds, unitId) then
		table.insert(call.UnitIds, unitId)
	end
	unit.Status = "Assigned"
	return true, nil
end
function CallService:Close(callId: string): (boolean, string?)
	local call = self.calls[callId]
	if not call then
		return false, "CALL_NOT_FOUND"
	end
	call.Status = "Closed"
	for _, unitId in call.UnitIds do
		self.context.Services:Get("UnitService"):SetStatus(unitId, "Available")
	end
	return true, nil
end
function CallService:Destroy()
	table.clear(self.calls)
end
return CallService
