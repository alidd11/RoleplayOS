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
	local maximumActiveCalls = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.Dispatch.MaximumActiveCalls) or 100)
	)
	local activeCalls = 0
	for _, existing in self.calls do
		if existing.Status ~= "Resolved" then
			activeCalls += 1
			if activeCalls >= maximumActiveCalls then
				return nil, "CALL_CAPACITY_REACHED"
			end
		end
	end

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
	if not call or call.Status == "Resolved" then
		return nil, "CALL_NOT_FOUND"
	end

	local mdt = self.context.Services:Get("MDTService")
	local duty = mdt:GetAuthorisedDuty(player, "IncidentRead")
	if not duty then
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

	-- Filtering yields. The call may have resolved and been projected to durable
	-- history, or the officer may have left/changed duty, while Roblox moderated
	-- the note. Revalidate both before mutating the live call so a late note can
	-- never land after the historical snapshot was taken.
	if self.calls[callId] ~= call or call.Status == "Resolved" then
		return nil, "CALL_NOT_FOUND"
	end
	duty = mdt:GetAuthorisedDuty(player, "IncidentRead")
	if not duty then
		return nil, "MDT_NOT_AUTHORISED"
	end
	-- The duty lookup above can itself yield on group access. Check the target one
	-- final time; no further yield occurs before the note is committed.
	if self.calls[callId] ~= call or call.Status == "Resolved" then
		return nil, "CALL_NOT_FOUND"
	end
	if duty.DepartmentId ~= "Control" and not table.find(call.DepartmentIds, duty.DepartmentId) then
		return nil, "CALL_NOT_RELEVANT"
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
	-- Resolved calls remain in memory briefly as the bounded recovery source for
	-- their durable incident projection. They are historical at that point and
	-- must not be reopened by attaching a unit through a stale/malicious request.
	if not call or call.Status == "Resolved" or not unit then
		return false, "CALL_OR_UNIT_NOT_FOUND"
	end
	if unit.AssignedCallId == callId and table.find(call.UnitIds, unitId) then
		-- Assignment requests can be retried by the client/network layer. Treat an
		-- already-linked unit as success without rewriting its status: an officer
		-- that already reached OnScene must not be pushed backwards to Assigned.
		return true, nil
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
	-- Adding another unit to a call already on scene must not move the whole
	-- incident backwards to Assigned. The call advances to Assigned only from
	-- Open; OnScene remains OnScene while additional responders are attached.
	if call.Status == "Open" then
		call.Status = "Assigned"
	end
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
		-- Open and Assigned are consequences of server-owned unit membership:
		-- ReleaseUnit owns the return to Open, and Assign owns Assigned. The only
		-- dispatcher-driven status transition is advancing an assigned call to
		-- OnScene. Accepting Open/Assigned here lets a modified client split the
		-- call status from UnitIds and each unit's AssignedCallId.
		if data.Status ~= "OnScene" then
			return nil, "INVALID_CALL_STATUS"
		end
		if (call.Status ~= "Assigned" and call.Status ~= "OnScene") or #call.UnitIds == 0 then
			return nil, "INVALID_CALL_STATUS"
		end
		call.Status = "OnScene"
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
	call.ClosedByUserId = closedByUserId or 0
	for _, unitId in call.UnitIds do
		local unit = self.context.Services:Get("UnitService").units[unitId]
		if unit then
			unit.AssignedCallId = nil
			self.context.Services:Get("UnitService"):SetStatus(unitId, "Available")
		end
	end
	call.Revision += 1
	self.context.Services:Get("IncidentService"):ScheduleFromCall(call, call.ClosedByUserId)
	self.revision += 1
	self.context.Services:Get("DispatchService"):Publish("CallClosed", callId, self.revision)
	return true, nil
end
function CallService:Snapshot(): { any }
	local result = {}
	-- Resolved calls remain the bounded recovery source for their durable incident
	-- projection. The first persistence attempt happens at Close; this sweep runs
	-- every minute even with no MDT readers, and retries only when the configured
	-- interval has elapsed. A successful projection can then expire normally.
	local now = os.time()
	local clock = os.clock()
	local dispatch = self.context.Configuration.Dispatch
	local ttl = (dispatch and tonumber(dispatch.ActiveStateTtlSeconds)) or 300
	local retrySeconds =
		math.max(5, (dispatch and tonumber(dispatch.IncidentPersistenceRetrySeconds)) or 60)
	local incidentService = self.context.Services:Get("IncidentService")
	for callId, call in self.calls do
		if call.Status ~= "Resolved" then
			table.insert(result, table.clone(call))
			continue
		end
		local closedAt = tonumber(call.ClosedAt) or now
		local age = now - closedAt
		if call.IncidentPersisted ~= true then
			local lastAttempt = tonumber(call.IncidentLastAttemptAt) or -math.huge
			if clock - lastAttempt >= retrySeconds then
				incidentService:ScheduleFromCall(call, tonumber(call.ClosedByUserId) or 0)
			end
			if age > ttl then
				-- Do not retain failed history indefinitely. By this point the
				-- projection has had its immediate attempt plus the periodic retries
				-- inside the same hard TTL that already bounds resolved call state.
				self.context.Logger:Error(
					"Resolved call incident projection exhausted recovery window",
					{
						CallId = call.CallId,
						RecordPersisted = call.IncidentRecordPersisted == true,
					}
				)
				self.calls[callId] = nil
			end
		elseif age > ttl then
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
	-- One final orderly-shutdown attempt before the source calls are released.
	-- IncidentService is destroyed later (reverse service order) and waits for its
	-- tracked persistence workers, while DataService remains alive until last.
	local incidentService = self.context.Services:Get("IncidentService")
	for _, call in self.calls do
		if call.Status == "Resolved" and call.IncidentPersisted ~= true then
			incidentService:ScheduleFromCall(call, tonumber(call.ClosedByUserId) or 0)
		end
	end
	table.clear(self.calls)
	self.revision = 0
end
return CallService
