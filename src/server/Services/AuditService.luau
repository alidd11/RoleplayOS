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
	flushBusy = false,
}
function AuditService:Init(context: any)
	self.context = context
	self.pending = {}
	self.flushBusy = false
end
function AuditService:Start()
	self.flushBusy = false
end

local function auditKey(): string
	local job = game.JobId ~= "" and game.JobId or "studio"
	return "audit:" .. string.sub(job, 1, 32) .. ":" .. math.floor(os.time() / 3600)
end

function AuditService:Flush()
	if self.flushBusy or #self.pending == 0 then
		return
	end
	self.flushBusy = true
	local batch = self.pending
	self.pending = {}
	local data = self.context.Services:Get("DataService")
	local _, reason = data:UpdateSharedRecord(auditKey(), function(existing)
		local retained = if type(existing) == "table" then existing else {}
		for _, entry in batch do
			table.insert(retained, entry)
		end
		while #retained > 500 do
			table.remove(retained, 1)
		end
		return retained
	end)
	if reason then
		for _, entry in batch do
			table.insert(self.pending, entry)
		end
		self.context.Logger:Error("Audit batch persistence failed", { Error = reason })
	end
	self.flushBusy = false
end
function AuditService:Record(entry: any)
	entry.Timestamp = entry.Timestamp or os.time()
	entry.ServerJobId = game.JobId
	-- Keep a bounded ring instead of removing index 1, which shifts every
	-- retained entry on each overflow. Auditing must remain cheap during bursts
	-- such as a large incident or vehicle-spawn event.
	local index = ((self.head + self.count - 1) % MAX_ENTRIES) + 1
	self.entries[index] = entry
	table.insert(self.pending, entry)
	if self.count < MAX_ENTRIES then
		self.count += 1
	else
		self.head = (self.head % MAX_ENTRIES) + 1
	end
	self.context.Logger:Audit(
		entry.Action,
		{ ActorUserId = entry.ActorUserId, Target = entry.Target, RequestId = entry.RequestId }
	)
	if #self.pending >= 25 then
		task.spawn(function()
			self:Flush()
		end)
	end
end
function AuditService:Destroy()
	local deadline = os.clock() + 5
	while self.flushBusy and os.clock() < deadline do
		task.wait()
	end
	self:Flush()
	table.clear(self.entries)
	table.clear(self.pending)
	self.head = 1
	self.count = 0
end
return AuditService
