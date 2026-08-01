--!strict
local MessagingService = game:GetService("MessagingService")
local DispatchService = { Optional = true }
function DispatchService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("DispatchChanged")
end
function DispatchService:Publish(kind: string, id: string, revision: number)
	local payload = { Kind = kind, Id = id, Revision = revision, ServerId = game.JobId }
	self.event:FireAllClients(payload)
	local ok, problem =
		pcall(MessagingService.PublishAsync, MessagingService, "RoleplayOS.Dispatch.v1", payload)
	if not ok then
		self.context.Logger:Warning(
			"Cross-server dispatch publish failed",
			{ Error = tostring(problem) }
		)
	end
end
function DispatchService:Start()
	local ok, connection = pcall(
		MessagingService.SubscribeAsync,
		MessagingService,
		"RoleplayOS.Dispatch.v1",
		function(message)
			if message.Data.ServerId ~= game.JobId then
				self.event:FireAllClients(message.Data)
			end
		end
	)
	if ok then
		self.subscription = connection
	else
		self.context.Logger:Warning("Cross-server dispatch unavailable")
	end
end
function DispatchService:Destroy()
	if self.subscription then
		self.subscription:Disconnect()
	end
end
return DispatchService
