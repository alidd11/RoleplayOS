--!strict

local HttpService = game:GetService("HttpService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local IncidentService = {
	cache = {},
	pending = {},
	cacheCount = 0,
	cacheSweepCounter = 0,
	shuttingDown = false,
	shutdownDeadline = nil,
	running = false,
}

function IncidentService:Init(context: any)
	self.context = context
	table.clear(self.cache)
	table.clear(self.pending)
	self.cacheCount = 0
	self.cacheSweepCounter = 0
	self.shuttingDown = false
	self.shutdownDeadline = nil
	self.running = false
end

function IncidentService:_sweepCache()
	self.cacheSweepCounter += 1
	if self.cacheSweepCounter < 32 then
		return
	end
	self.cacheSweepCounter = 0

	local now = os.clock()
	for incidentId, entry in self.cache do
		if type(entry) ~= "table" or (entry.ExpiresAt or 0) <= now then
			self.cache[incidentId] = nil
			self.cacheCount = math.max(0, self.cacheCount - 1)
		end
	end
end

function IncidentService:_cacheSet(incidentId: string, value: any)
	if not self.running then
		return
	end
	local replacing = self.cache[incidentId] ~= nil
	self.cache[incidentId] = {
		Value = value,
		ExpiresAt = os.clock() + self.context.Configuration.MDT.RecordCacheSeconds,
	}
	if not replacing then
		self.cacheCount += 1
	end

	self:_sweepCache()

	local maximum = math.max(1, self.context.Configuration.MDT.MaximumIncidentIndexEntries or 2000)
	if self.cacheCount <= maximum then
		return
	end

	local oldestId
	local oldestExpiry = math.huge
	for cachedId, entry in self.cache do
		local expiresAt = if type(entry) == "table" then entry.ExpiresAt or 0 else 0
		if expiresAt < oldestExpiry then
			oldestExpiry = expiresAt
			oldestId = cachedId
		end
	end
	if oldestId then
		self.cache[oldestId] = nil
		self.cacheCount = math.max(0, self.cacheCount - 1)
	end
end

function IncidentService:_cacheGet(incidentId: string): any?
	local entry = self.cache[incidentId]
	if not entry then
		return nil
	end
	if type(entry) ~= "table" or (entry.ExpiresAt or 0) <= os.clock() then
		self.cache[incidentId] = nil
		self.cacheCount = math.max(0, self.cacheCount - 1)
		return nil
	end
	return entry.Value
end

function IncidentService:Start()
	self.running = true
end

function IncidentService:BeginShutdown()
	if self.shuttingDown then
		return
	end
	self.shuttingDown = true
	self.shutdownDeadline = os.clock()
		+ self.context.Configuration.Framework.ShutdownSaveSeconds / 2
end

function IncidentService:_getReadDuty(player: Player): any?
	local mdt = self.context.Services:Get("MDTService")
	local duty = mdt:GetAuthorisedDuty(player, nil)
	if not duty then
		return nil
	end
	if
		not mdt:HasPermission(duty, "IncidentRead") and not mdt:HasPermission(duty, "IncidentWrite")
	then
		return nil
	end
	return duty
end

function IncidentService:_filterTitle(actor: Player, raw: string): (string?, string?)
	local title = string.sub(string.gsub(raw, "[%c]", ""), 1, 120)
	title = string.match(title, "^%s*(.-)%s*$") or ""
	if #title < 3 then
		return nil, "INVALID_INCIDENT"
	end
	local filtered, reason = TextFilter.forBroadcast(title, actor.UserId)
	if not filtered or #filtered < 3 then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

function IncidentService:_indexIncident(incident: any): (boolean, string?)
	local maximum = self.context.Configuration.MDT.MaximumIncidentIndexEntries
	local indexed, indexReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex("Incident:Recent", function(existing)
			local index = if type(existing) == "table" then existing else { Entries = {} }
			index.Entries = if type(index.Entries) == "table" then index.Entries else {}
			index.Entries[incident.IncidentId] = {
				IncidentId = incident.IncidentId,
				Title = incident.Title,
				Status = incident.Status,
				CreatedAt = incident.CreatedAt,
				ClosedAt = incident.ClosedAt,
				DepartmentIds = table.clone(incident.DepartmentIds or {}),
				UpdatedAt = os.time(),
			}
			local count = 0
			local oldestId
			local oldestAt = math.huge
			for id, entry in index.Entries do
				count += 1
				if (entry.CreatedAt or 0) < oldestAt then
					oldestAt = entry.CreatedAt or 0
					oldestId = id
				end
			end
			if count > maximum and oldestId then
				index.Entries[oldestId] = nil
			end
			index.UpdatedAt = os.time()
			return index
		end)
	return indexed ~= nil, indexReason
end

function IncidentService:_removeStaleRecentIndex(expected: any): (boolean, string?, boolean)
	local incidentId = expected.IncidentId
	if type(incidentId) ~= "string" then
		return true, nil, false
	end

	-- The recent index and incident record are separate durable writes. Claim only
	-- the exact row this search observed, then re-read the durable record before
	-- deleting anything so a concurrent projection cannot be mistaken for stale
	-- history merely because this server read an older index snapshot.
	local cleanupToken = HttpService:GenerateGUID(false)
	local claimed = false
	local _, claimReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex("Incident:Recent", function(stored)
			claimed = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[incidentId]
			if
				type(current) == "table"
				and current.IncidentId == expected.IncidentId
				and current.Title == expected.Title
				and current.Status == expected.Status
				and current.CreatedAt == expected.CreatedAt
				and current.UpdatedAt == expected.UpdatedAt
			then
				current.CleanupToken = cleanupToken
				stored.UpdatedAt = os.time()
				claimed = true
			end
			return stored
		end)
	if claimReason then
		return false, claimReason, false
	end
	if not claimed then
		return true, nil, false
	end

	local record, recordReason =
		self.context.Services:Get("DataService"):GetMdtRecord("Incident:" .. incidentId)
	if recordReason then
		return false, recordReason, false
	end

	local deleted = false
	local _, finalReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex("Incident:Recent", function(stored)
			deleted = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[incidentId]
			if type(current) == "table" and current.CleanupToken == cleanupToken then
				if record then
					current.CleanupToken = nil
				else
					stored.Entries[incidentId] = nil
					deleted = true
				end
				stored.UpdatedAt = os.time()
			end
			return stored
		end)
	if finalReason then
		return false, finalReason, false
	end
	return true, nil, deleted
end

function IncidentService:_persist(incident: any): (any?, string?, boolean, any?)
	local key = "Incident:" .. incident.IncidentId
	local stored, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtRecord(key, function(existing)
			if
				type(existing) == "table"
				and (existing.Revision or 0) > (incident.Revision or 0)
			then
				return existing
			end
			return incident
		end)
	if not stored then
		return nil, reason, false, nil
	end
	self:_cacheSet(incident.IncidentId, stored)
	local indexed, indexReason = self:_indexIncident(stored)
	if not indexed then
		-- The primary record is already durable. Expose that stage to the caller so
		-- a retry can repair only the recent index instead of spending another
		-- record-store write and another full DataStore retry budget.
		return nil, indexReason, true, stored
	end
	return stored, nil, true, stored
end
function IncidentService:Create(player: Player, data: any): (any?, string?)
	if not self.running then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local mdt = self.context.Services:Get("MDTService")
	local duty = mdt:GetAuthorisedDuty(player, "IncidentWrite")
	if not duty then
		return nil, "MDT_NOT_AUTHORISED"
	end
	if type(data) ~= "table" or type(data.Title) ~= "string" then
		return nil, "INVALID_INCIDENT"
	end
	local title, titleReason = self:_filterTitle(player, data.Title)
	if not title then
		return nil, titleReason
	end
	-- Text filtering yields. Re-authorise after moderation and use that exact duty
	-- snapshot for the incident department so a stale request cannot persist after
	-- the player leaves duty, changes role or disconnects.
	duty = mdt:GetAuthorisedDuty(player, "IncidentWrite")
	if not self.running or not duty then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local incident = {
		IncidentId = HttpService:GenerateGUID(false),
		Title = title,
		Status = "Open",
		PersonIds = if type(data.PersonIds) == "table" then data.PersonIds else {},
		VehicleIds = if type(data.VehicleIds) == "table" then data.VehicleIds else {},
		Notes = {},
		DepartmentIds = { duty.DepartmentId },
		CreatedAt = os.time(),
		CreatedByUserId = player.UserId,
		Revision = 1,
	}
	local stored, reason = self:_persist(incident)
	if not stored then
		return nil, reason
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Incident.Created",
		Target = incident.IncidentId,
		Metadata = {},
	})
	return stored, nil
end

function IncidentService:ScheduleFromCall(call: any, closedByUserId: number)
	if not self.running or call.IncidentPersisted == true then
		return
	end
	local incidentId = "CALL:" .. call.CallId
	if self.pending[incidentId] then
		return
	end
	self.pending[incidentId] = true
	call.IncidentLastAttemptAt = os.clock()
	local snapshot = {
		IncidentId = incidentId,
		SourceCallId = call.CallId,
		Title = call.Summary,
		IncidentType = call.IncidentType,
		Status = "Closed",
		Location = call.Location,
		Priority = call.Priority,
		CallerName = call.CallerName,
		CallerNumber = call.CallerNumber,
		Notes = call.Notes,
		OperationalNotes = table.clone(call.OperationalNotes or {}),
		DepartmentIds = table.clone(call.DepartmentIds),
		UnitIds = table.clone(call.UnitIds),
		PersonIds = {},
		VehicleIds = {},
		CreatedAt = call.CreatedAt,
		ClosedAt = call.ClosedAt or os.time(),
		ClosedByUserId = closedByUserId,
		Revision = call.Revision or 1,
	}
	task.spawn(function()
		-- Keep one claim across shutdown retries. CallService releases its in-memory
		-- call table before IncidentService is destroyed, so this worker's call
		-- reference is the recovery source during the existing incident shutdown
		-- budget. Ordinary runtime failures still return to the minute sweep.
		while true do
			local ok, stored, reason, recordWritten, durableRecord = pcall(function()
				if call.IncidentRecordPersisted == true then
					local record = call.IncidentRecordSnapshot or snapshot
					local indexed, indexReason = self:_indexIncident(record)
					return if indexed then record else nil, indexReason, true, record
				end
				return self:_persist(snapshot)
			end)
			if not ok then
				self.context.Logger:Error("Closed dispatch incident persistence raised", {
					IncidentId = incidentId,
					Error = tostring(stored),
				})
				break
			end
			if recordWritten then
				call.IncidentRecordPersisted = true
				if not stored and durableRecord then
					-- Keep the exact record UpdateAsync committed only while its index is
					-- missing. This handles a newer revision returned by the record store
					-- without making the repair perform another read.
					call.IncidentRecordSnapshot = durableRecord
				end
			end
			if stored then
				call.IncidentPersisted = true
				call.IncidentRecordSnapshot = nil
				break
			end

			local deadline = tonumber(self.shutdownDeadline) or -math.huge
			if not self.shuttingDown or os.clock() >= deadline then
				self.context.Logger:Warning("Closed dispatch incident persistence will retry", {
					IncidentId = incidentId,
					Error = reason,
					RecordPersisted = call.IncidentRecordPersisted == true,
				})
				break
			end

			-- DataService already exhausted its bounded retry policy for this stage.
			-- During orderly shutdown, immediately spend the remaining incident
			-- budget on the unresolved projection instead of discarding its source.
			self.context.Logger:Warning(
				"Closed dispatch incident persistence retrying at shutdown",
				{
					IncidentId = incidentId,
					Error = reason,
					RecordPersisted = call.IncidentRecordPersisted == true,
				}
			)
			task.wait()
		end
		self.pending[incidentId] = nil
	end)
end
function IncidentService:Close(player: Player, incidentId: string): (any?, string?)
	if not self.running then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local authorised =
		self.context.Services:Get("MDTService"):CanUsePermission(player, "IncidentWrite")
	if not self.running or not authorised then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local updated, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtRecord("Incident:" .. incidentId, function(existing)
			if type(existing) ~= "table" then
				return nil
			end
			-- Closing is idempotent. A retry after the primary record committed but
			-- its recent-index projection failed must preserve the original closure
			-- actor, timestamp and revision while repairing only that projection.
			if existing.Status == "Closed" then
				return existing
			end
			existing.Status = "Closed"
			existing.ClosedAt = os.time()
			existing.ClosedByUserId = player.UserId
			existing.Revision = (existing.Revision or 0) + 1
			return existing
		end)
	if not updated then
		return nil, reason or "INCIDENT_NOT_FOUND"
	end
	-- UpdateMdtRecord above is the authoritative durable mutation. Do not send
	-- the same record through _persist(), which would spend another UpdateAsync
	-- retry budget and rewrite a record that is already committed.
	self:_cacheSet(updated.IncidentId, updated)
	local indexed, indexReason = self:_indexIncident(updated)
	if not indexed then
		return nil, indexReason
	end
	return updated, nil
end

function IncidentService:Recent(
	player: Player,
	page: number,
	resolvedOnly: boolean?
): (any?, string?)
	if not self.running then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local duty = self:_getReadDuty(player)
	if not duty then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local index, reason = self.context.Services:Get("DataService"):GetMdtIndex("Incident:Recent")
	if reason then
		return nil, reason
	end
	local entries = {}
	-- Open dispatch calls are operational MDT records immediately. They remain
	-- server-local and are replaced by the persisted incident created when the
	-- dispatcher resolves the call.
	if not resolvedOnly then
		for _, call in self.context.Services:Get("CallService"):Snapshot() do
			if
				duty.DepartmentId == "Control" or table.find(call.DepartmentIds, duty.DepartmentId)
			then
				table.insert(entries, {
					IncidentId = "CALL-" .. call.CallId,
					CallId = call.CallId,
					Title = call.Summary,
					Status = "Live call · " .. call.Status,
					IncidentType = call.IncidentType,
					Location = call.Location,
					Priority = call.Priority,
					DepartmentIds = table.clone(call.DepartmentIds),
					CreatedAt = call.CreatedAt,
					Revision = call.Revision,
					LiveDispatchCall = true,
				})
			end
		end
	end
	for _, entry in if index and type(index.Entries) == "table" then index.Entries else {} do
		local departments = if type(entry.DepartmentIds) == "table" then entry.DepartmentIds else {}
		local isResolved = entry.Status == "Closed"
		if
			isResolved == (resolvedOnly == true)
			and (duty.DepartmentId == "Control" or table.find(departments, duty.DepartmentId))
		then
			table.insert(entries, entry)
		end
	end
	table.sort(entries, function(a, b)
		return (a.CreatedAt or 0) > (b.CreatedAt or 0)
	end)
	local size = self.context.Configuration.MDT.PageSize
	page = math.max(1, math.floor(page))
	local first = (page - 1) * size + 1
	local items = {}
	local total = #entries
	for indexPosition = first, math.min(#entries, first + size - 1) do
		local summary = entries[indexPosition]
		local record = if summary.LiveDispatchCall
			then summary
			else self:_cacheGet(summary.IncidentId)
		if not record then
			record, reason = self.context.Services
				:Get("DataService")
				:GetMdtRecord("Incident:" .. summary.IncidentId)
			if reason then
				return nil, reason
			end
			if record then
				self:_cacheSet(summary.IncidentId, record)
			end
		end
		if record then
			table.insert(items, record)
		elseif not summary.LiveDispatchCall then
			local repaired, removalReason, deleted = self:_removeStaleRecentIndex(summary)
			if not repaired then
				self.context.Logger:Warning("Incident search could not repair stale index", {
					IncidentId = summary.IncidentId,
					Error = removalReason,
				})
			elseif deleted then
				total = math.max(0, total - 1)
			end
		end
	end
	-- Index and record reads can yield on DataStore budget, retries and network
	-- latency. Revalidate the exact duty snapshot before returning any records so
	-- a player who left duty, changed role or disconnected while those reads were
	-- in flight cannot receive a response authorised by an older duty.
	local currentDuty = self:_getReadDuty(player)
	if not self.running or currentDuty ~= duty then
		return nil, "MDT_NOT_AUTHORISED"
	end
	return { Items = items, Page = page, Total = total }, nil
end

function IncidentService:Destroy()
	self:BeginShutdown()
	local deadline = tonumber(self.shutdownDeadline) or os.clock()
	while next(self.pending) ~= nil and os.clock() < deadline do
		task.wait()
	end
	if next(self.pending) ~= nil then
		self.context.Logger:Warning("Incident persistence shutdown deadline reached", {})
	end
	self.running = false
	table.clear(self.cache)
	table.clear(self.pending)
	self.cacheCount = 0
	self.cacheSweepCounter = 0
	self.shuttingDown = false
	self.shutdownDeadline = nil
end

return IncidentService
