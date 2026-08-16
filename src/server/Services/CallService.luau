--!strict
local HttpService = game:GetService("HttpService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)
local CallService = { calls = {}, revision = 0 }
function CallService:Init(context: any)
	self.context = context
end
function CallService:Start()
	self.running = true
	task.spawn(function()
		while self.running do
			task.wait(60)
			if self.running then
				self:Snapshot()
			end
		end
	end)
end
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
		-- Serialised primitives, never a Vector3: closing a call can promote it
		-- to a persisted incident, and persistent records hold primitives only.
		Position = if type(data.Position) == "table"
				and type(data.Position.X) == "number"
				and type(data.Position.Y) == "number"
				and type(data.Position.Z) == "number"
			then { X = data.Position.X, Y = data.Position.Y, Z = data.Position.Z }
			else nil,
		IncidentType = incidentType,
		CallerName = tostring(data.CallerName or "Unknown caller"),
		CallerNumber = tostring(data.CallerNumber or ""),
		Notes = tostring(data.Notes or ""),
		OperationalNotes = {},
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

function CallService:AddOperationalNote(
	player: Player,
	callId: string,
	rawNote: string
): (any?, string?)
	local call = self.calls[callId]
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if not call or call.Status == "Resolved" then
		return nil, "CALL_NOT_FOUND"
	end
	if
		not duty
		or not self.context.Services:Get("MDTService"):CanUsePermission(player, "IncidentRead")
	then
		return nil, "MDT_NOT_AUTHORISED"
	end
	if duty.DepartmentId ~= "Control" and not table.find(call.DepartmentIds, duty.DepartmentId) then
		return nil, "CALL_NOT_RELEVANT"
	end
	local note = string.sub(string.match(rawNote, "^%s*(.-)%s*$") or "", 1, 300)
	if #note < 3 then
		return nil, "INVALID_NOTE"
	end
	local filtered, reason = TextFilter.forBroadcast(note, player.UserId)
	if not filtered then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	call.OperationalNotes = if type(call.OperationalNotes) == "table"
		then call.OperationalNotes
		else {}
	table.insert(call.OperationalNotes, {
		Text = filtered,
		Author = duty.Callsign or player.DisplayName,
		DepartmentId = duty.DepartmentId,
		CreatedAt = os.time(),
	})
	local maximumNotes = self.context.Configuration.Dispatch.MaximumOperationalNotes or 50
	while #call.OperationalNotes > maximumNotes do
		table.remove(call.OperationalNotes, 1)
	end
	call.Revision += 1
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallNoteAdded", callId, self.revision)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Dispatch.CallNoteAdded",
		Target = callId,
		Metadata = { DepartmentId = duty.DepartmentId },
	})
	return call, nil
end
-- Moves the call a unit is assigned to on scene when that unit arrives.
--
-- Open, Assigned and OnScene are the three stages a call has, and until now
-- nothing could set the third: dispatch assigned a unit and the call stayed
-- Assigned until it was closed, however long the unit had been standing at the
-- scene. Control could not tell a car still driving to a call from one already
-- working it, which is the distinction the stage exists to make.
--
-- Driven by the unit rather than set by hand, because the officer arriving is
-- the thing that happened and dispatch should not have to be told twice.
function CallService:NoteUnitOnScene(unitId: string): boolean
	local unit = self.context.Services:Get("UnitService").units[unitId]
	local callId = unit and unit.AssignedCallId
	local call = callId and self.calls[callId]
	if not call or call.Status ~= "Assigned" then
		return false
	end
	call.Status = "OnScene"
	call.Revision += 1
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallOnScene", callId, self.revision)
	return true
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
	-- Resolved, not Closed. Nothing in the framework ever writes "Closed", so
	-- this guard never fired and a resolved call could be reopened, put back on
	-- every dispatcher's board and closed a second time, overwriting the
	-- incident that was already persisted from it.
	if not call or call.Status == "Resolved" then
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
-- Takes a unit off every call it was working, without resolving anything.
--
-- Assign is the only thing that ever added a unit to a call, and Close was the
-- only thing that ever removed one. So a unit that simply stopped existing --
-- went off duty, or disconnected -- left its callsign sitting in call.UnitIds
-- and the call sitting at Assigned or OnScene forever. On the dispatch board it
-- read as attended, by a unit no longer in the units list, and it stayed in the
-- queue until a controller noticed and closed it by hand.
--
-- A call that still has other units keeps its status: those officers are still
-- working it. Only the last unit leaving sends it back to Open, which is the
-- honest state -- the job still needs doing and nobody is on it.
function CallService:ReleaseUnit(unitId: string): number
	local released = 0
	for _, call in self.calls do
		if call.Status == "Resolved" then
			continue
		end
		local index = table.find(call.UnitIds, unitId)
		if index then
			table.remove(call.UnitIds, index)
			if #call.UnitIds == 0 and (call.Status == "Assigned" or call.Status == "OnScene") then
				call.Status = "Open"
			end
			call.Revision += 1
			self.revision += 1
			self.context.Services
				:Get("DispatchService")
				:Publish("CallUpdated", call.CallId, self.revision)
			released += 1
		end
	end
	return released
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
	-- Resolved calls are dropped once they are old enough, here rather than on a
	-- timer.
	--
	-- Closing a call marked it Resolved and left it in the table for the life of
	-- the server, and this loop skipped over every one of them on every request.
	-- A busy Control server accumulates hundreds in an evening, and with fifteen
	-- terminals refreshing about once a second that is thousands of wasted
	-- iterations a second by the third hour, growing all the while.
	--
	-- The delay before dropping one exists because a client that asked just
	-- before it closed should still see it disappear rather than have it vanish
	-- from under them. Dispatch.ActiveStateTtlSeconds has been in the
	-- configuration all along with nothing reading it; this is what it was for.
	--
	-- Nothing is lost by dropping it: IncidentService has already persisted the
	-- call at the moment it closed.
	--
	-- Pruned in the reader rather than on its own loop, because if nobody is
	-- asking then nothing is walking the table and there is nothing to save.
	local now = os.time()
	local dispatch = self.context.Configuration.Dispatch
	local ttl = (dispatch and tonumber(dispatch.ActiveStateTtlSeconds)) or 300
	for callId, call in self.calls do
		if call.Status ~= "Resolved" then
			table.insert(result, table.clone(call))
		elseif now - (tonumber(call.ClosedAt) or now) > ttl then
			self.calls[callId] = nil
		end
	end
	table.sort(result, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	return result
end
function CallService:Destroy()
	self.running = false
	table.clear(self.calls)
	self.revision = 0
end
return CallService
