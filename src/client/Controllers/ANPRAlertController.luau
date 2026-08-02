--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ANPRAlertController = {}

function ANPRAlertController:Init(context: any)
	self.context = context
end

function ANPRAlertController:Start()
	local remotes =
		ReplicatedStorage:WaitForChild("RoleplayOS"):WaitForChild("Network"):WaitForChild("Remotes")
	local event = remotes:WaitForChild("ANPRAlert") :: RemoteEvent
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
