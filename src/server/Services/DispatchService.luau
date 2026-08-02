--!strict
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local DispatchService = { Optional = true }
function DispatchService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("DispatchChanged")
end
function DispatchService:Publish(kind: string, id: string, revision: number)
	local payload = { Kind = kind, Id = id, Revision = revision, ServerId = game.JobId }
	self.event:FireAllClients(payload)
	if not RunService:IsStudio() then
		task.spawn(function()
			local ok, problem = pcall(
				MessagingService.PublishAsync,
				MessagingService,
				"RoleplayOS.Dispatch.v1",
				payload
			)
			if not ok then
				self.context.Logger:Warning(
					"Cross-server dispatch publish failed",
					{ Error = tostring(problem) }
				)
			end
		end)
	end
end
function DispatchService:Start()
	self.running = true
	if RunService:IsStudio() then
		return
	end
	task.spawn(function()
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
		if ok and self.running then
			self.subscription = connection
		elseif ok then
			connection:Disconnect()
		else
			self.context.Logger:Warning("Cross-server dispatch unavailable")
		end
	end)
end
function DispatchService:Destroy()
	self.running = false
	if self.subscription then
		self.subscription:Disconnect()
	end
end
return DispatchService
