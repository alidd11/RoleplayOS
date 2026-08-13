--!strict

-- Critical, because EconomyService records here after it has already moved the
-- money and marked the profile dirty. Stepped over, every transaction in the
-- game would raise once the balance had changed: the player is told the request
-- failed, the money has gone anyway, and the only record of it going is the
-- thing that just failed.
local MAX_ENTRIES = 500
local AuditService = { Critical = true, entries = {}, head = 1, count = 0 }
function AuditService:Init(context: any)
	self.context = context
end
function AuditService:Start() end
function AuditService:Record(entry: any)
	entry.Timestamp = entry.Timestamp or os.time()
	entry.ServerJobId = game.JobId
	-- Keep a bounded ring instead of removing index 1, which shifts every
	-- retained entry on each overflow. Auditing must remain cheap during bursts
	-- such as a large incident or vehicle-spawn event.
	local index = ((self.head + self.count - 1) % MAX_ENTRIES) + 1
	self.entries[index] = entry
	if self.count < MAX_ENTRIES then
		self.count += 1
	else
		self.head = (self.head % MAX_ENTRIES) + 1
	end
	self.context.Logger:Audit(
		entry.Action,
		{ ActorUserId = entry.ActorUserId, Target = entry.Target, RequestId = entry.RequestId }
	)
end
function AuditService:Destroy()
	table.clear(self.entries)
	self.head = 1
	self.count = 0
end
return AuditService
