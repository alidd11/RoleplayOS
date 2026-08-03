--!strict

local ANPRAlertController = {}

function ANPRAlertController:Init(context: any)
	self.context = context
end

function ANPRAlertController:Start()
	local event = self.context.Controllers.NetworkController:ResolveEvent("ANPRAlert")
	if not event then
		return
	end
	self.connection = event.OnClientEvent:Connect(function(alert)
		self.context.Controllers.NotificationController:Show(
			string.format("WANTED VEHICLE %s · %s", alert.Registration, alert.Location),
			"ROADS POLICING ANPR"
		)
	end)
end

function ANPRAlertController:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end
end

return ANPRAlertController
