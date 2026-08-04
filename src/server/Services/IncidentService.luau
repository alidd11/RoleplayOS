--!strict

local HttpService = game:GetService("HttpService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local IncidentService = { cache = {}, pending = {} }

function IncidentService:Init(context: any)
	self.context = context
end

function IncidentService:Start() end

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

function IncidentService:_persist(incident: any): (any?, string?)
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
		return nil, reason
	end
	self.cache[incident.IncidentId] = stored
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
	if not indexed then
		return nil, indexReason
	end
	return stored, nil
end

function IncidentService:Create(player: Player, data: any): (any?, string?)
	if not self.context.Services:Get("MDTService"):CanUsePermission(player, "IncidentWrite") then
		return nil, "MDT_NOT_AUTHORISED"
	end
	if type(data.Title) ~= "string" then
		return nil, "INVALID_INCIDENT"
	end
	local title, titleReason = self:_filterTitle(player, data.Title)
	if not title then
		return nil, titleReason
	end
	local duty = self.context.Services:Get("MDTService"):GetDuty(player)
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
	local incidentId = "CALL:" .. call.CallId
	if self.pending[incidentId] then
		return
	end
	self.pending[incidentId] = true
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
		-- The claim is released whether persisting returns or raises. Releasing it
		-- only on the way out meant a single raise held it forever: that incident
		-- could never be scheduled again, and shutdown then spent its whole
		-- deadline waiting for something that had already died.
		local ok, stored, reason = pcall(function()
			return self:_persist(snapshot)
		end)
		self.pending[incidentId] = nil
		if not ok then
			self.context.Logger:Error("Closed dispatch incident persistence raised", {
				IncidentId = incidentId,
				Error = tostring(stored),
			})
			return
		end
		if not stored then
			self.context.Logger:Error("Closed dispatch incident persistence failed", {
				IncidentId = incidentId,
				Error = reason,
			})
		end
	end)
end

function IncidentService:Close(player: Player, incidentId: string): (any?, string?)
	if not self.context.Services:Get("MDTService"):CanUsePermission(player, "IncidentWrite") then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local updated, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtRecord("Incident:" .. incidentId, function(existing)
			if type(existing) ~= "table" then
				return nil
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
	return self:_persist(updated)
end

function IncidentService:Recent(player: Player, page: number): (any?, string?)
	local duty = self.context.Services:Get("MDTService"):GetDuty(player)
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
	for _, call in self.context.Services:Get("CallService"):Snapshot() do
		if duty.DepartmentId == "Control" or table.find(call.DepartmentIds, duty.DepartmentId) then
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
	for _, entry in if index and type(index.Entries) == "table" then index.Entries else {} do
		local departments = if type(entry.DepartmentIds) == "table" then entry.DepartmentIds else {}
		if duty.DepartmentId == "Control" or table.find(departments, duty.DepartmentId) then
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
	for indexPosition = first, math.min(#entries, first + size - 1) do
		local summary = entries[indexPosition]
		local record = if summary.LiveDispatchCall then summary else self.cache[summary.IncidentId]
		if not record then
			record, reason = self.context.Services
				:Get("DataService")
				:GetMdtRecord("Incident:" .. summary.IncidentId)
			if reason then
				return nil, reason
			end
			if record then
				self.cache[summary.IncidentId] = record
			end
		end
		if record then
			table.insert(items, record)
		end
	end
	return { Items = items, Page = page, Total = #entries }, nil
end

function IncidentService:Destroy()
	local deadline = os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds / 2
	while next(self.pending) ~= nil and os.clock() < deadline do
		task.wait()
	end
	if next(self.pending) ~= nil then
		self.context.Logger:Warning("Incident persistence shutdown deadline reached", {})
	end
	table.clear(self.cache)
	table.clear(self.pending)
end

return IncidentService
