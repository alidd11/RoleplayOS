--!strict

local AuditService = { entries = {} }
function AuditService:Init(context: any)
	self.context = context
end
function AuditService:Start() end
function AuditService:Record(entry: any)
	entry.Timestamp = entry.Timestamp or os.time()
	entry.ServerJobId = game.JobId
	table.insert(self.entries, entry)
	if #self.entries > 500 then
		table.remove(self.entries, 1)
	end
	self.context.Logger:Audit(
		entry.Action,
		{ ActorUserId = entry.ActorUserId, Target = entry.Target, RequestId = entry.RequestId }
	)
end
function AuditService:Destroy()
	table.clear(self.entries)
end
return AuditService
