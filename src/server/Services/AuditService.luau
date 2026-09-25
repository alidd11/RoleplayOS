--!strict

-- Critical, because EconomyService records here after it has already moved the
-- money and marked the profile dirty. Stepped over, every transaction in the
-- game would raise once the balance had changed: the player is told the request
-- failed, the money has gone anyway, and the only record of it going is the
-- thing that just failed.
local MAX_ENTRIES = 500
local AuditService = {
	Critical = true,
	entries = {},
	head = 1,
	count = 0,
	pending = {},
	pendingHead = 1,
	pendingCount = 0,
	droppedPending = 0,
	flushBusy = false,
	flushScheduled = false,
	running = false,
}

function AuditService:Init(context: any)
	self.context = context
	table.clear(self.entries)
	table.clear(self.pending)
	self.head = 1
	self.count = 0
	self.pendingHead = 1
	self.pendingCount = 0
	self.droppedPending = 0
	self.flushBusy = false
	self.flushScheduled = false
	self.running = false
end

function AuditService:_maximumPending(): number
	return math.max(
		25,
		math.floor(
			tonumber(self.context.Configuration.Framework.AuditMaximumPendingEntries) or 1000
		)
	)
end

function AuditService:_flushThreshold(): number
	return math.min(
		self:_maximumPending(),
		math.max(
			1,
			math.floor(tonumber(self.context.Configuration.Framework.AuditFlushThreshold) or 25)
		)
	)
end

function AuditService:_queuePending(entry: any)
	local maximum = self:_maximumPending()
	local index = ((self.pendingHead + self.pendingCount - 1) % maximum) + 1
	self.pending[index] = entry
	if self.pendingCount < maximum then
		self.pendingCount += 1
		return
	end

	self.pendingHead = (self.pendingHead % maximum) + 1
	self.droppedPending += 1
	if self.droppedPending == 1 or self.droppedPending % 100 == 0 then
		self.context.Logger:Error("Audit pending buffer full; oldest entries dropped", {
			DroppedEntries = self.droppedPending,
			MaximumPendingEntries = maximum,
		})
	end
end

function AuditService:_takePending(): { any }
	local count = self.pendingCount
	if count == 0 then
		return {}
	end

	local maximum = self:_maximumPending()
	local batch = table.create(count)
	for offset = 0, count - 1 do
		local index = ((self.pendingHead + offset - 1) % maximum) + 1
		local entry = self.pending[index]
		if entry ~= nil then
			table.insert(batch, entry)
		end
	end
	table.clear(self.pending)
	self.pendingHead = 1
	self.pendingCount = 0
	return batch
end

function AuditService:_restorePending(batch: { any })
	local newer = self:_takePending()
	for _, entry in batch do
		self:_queuePending(entry)
	end
	for _, entry in newer do
		self:_queuePending(entry)
	end
end

function AuditService:_scheduleFlush()
	if self.flushScheduled or self.flushBusy or not self.running then
		return
	end
	self.flushScheduled = true
	task.defer(function()
		self.flushScheduled = false
		if self.running then
			self:Flush()
		end
	end)
end

function AuditService:Start()
	self.running = true
	task.spawn(function()
		local interval = math.max(
			1,
			tonumber(self.context.Configuration.Framework.AuditFlushIntervalSeconds) or 5
		)
		while self.running do
			task.wait(interval)
			if self.running then
				self:Flush()
			end
		end
	end)
end

local function auditKey(): string
	local job = game.JobId ~= "" and game.JobId or "studio"
	return "audit:" .. string.sub(job, 1, 32) .. ":" .. math.floor(os.time() / 3600)
end

function AuditService:Flush(): boolean
	if self.flushBusy then
		return false
	end
	if self.pendingCount == 0 then
		return true
	end

	self.flushBusy = true
	local batch = self:_takePending()
	local data = self.context.Services:Get("DataService")
	local ok, updated, reason = pcall(function()
		return data:UpdateSharedRecord(auditKey(), function(existing)
			local retained = if type(existing) == "table" then existing else {}
			for _, entry in batch do
				table.insert(retained, entry)
			end
			while #retained > MAX_ENTRIES do
				table.remove(retained, 1)
			end
			return retained
		end)
	end)

	if not ok or updated == nil then
		self:_restorePending(batch)
		self.context.Logger:Error("Audit batch persistence failed", {
			Error = if ok then reason or "AUDIT_STORE_UNAVAILABLE" else tostring(updated),
			PendingEntries = self.pendingCount,
		})
		self.flushBusy = false
		return false
	end

	self.flushBusy = false
	if self.pendingCount >= self:_flushThreshold() then
		self:_scheduleFlush()
	end
	return true
end

function AuditService:Record(entry: any)
	entry.Timestamp = entry.Timestamp or os.time()
	entry.ServerJobId = game.JobId
	-- Keep a bounded ring instead of removing index 1, which shifts every
	-- retained entry on each overflow. Auditing must remain cheap during bursts
	-- such as a large incident or vehicle-spawn event.
	local index = ((self.head + self.count - 1) % MAX_ENTRIES) + 1
	self.entries[index] = entry
	self:_queuePending(entry)
	if self.count < MAX_ENTRIES then
		self.count += 1
	else
		self.head = (self.head % MAX_ENTRIES) + 1
	end
	self.context.Logger:Audit(
		entry.Action,
		{ ActorUserId = entry.ActorUserId, Target = entry.Target, RequestId = entry.RequestId }
	)
	if self.pendingCount >= self:_flushThreshold() then
		self:_scheduleFlush()
	end
end

function AuditService:Destroy()
	self.running = false
	local deadline = os.clock()
		+ math.max(
			1,
			tonumber(self.context.Configuration.Framework.AuditShutdownFlushSeconds) or 5
		)
	while self.flushBusy and os.clock() < deadline do
		task.wait(0.05)
	end
	while self.pendingCount > 0 and os.clock() < deadline do
		local flushed = self:Flush()
		if not flushed and self.pendingCount > 0 then
			task.wait(0.25)
		end
	end
	if self.pendingCount > 0 then
		self.context.Logger:Warning("Audit shutdown deadline reached", {
			PendingEntries = self.pendingCount,
			DroppedEntries = self.droppedPending,
		})
	end
	table.clear(self.entries)
	table.clear(self.pending)
	self.head = 1
	self.count = 0
	self.pendingHead = 1
	self.pendingCount = 0
	self.droppedPending = 0
	self.flushScheduled = false
	self.flushBusy = false
end

return AuditService
