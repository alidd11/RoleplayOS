--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EmergencyAlertController = {}

function EmergencyAlertController:Init(context: any)
	self.context = context
end

function EmergencyAlertController:Start()
	local remote = ReplicatedStorage.RoleplayOS.Network.Remotes:WaitForChild("EmergencyAlert")
	self.connection = remote.OnClientEvent:Connect(function(payload)
		local call = type(payload) == "table" and payload.Call or nil
		if type(call) == "table" then
			self.context.Controllers.NotificationController:Show(
				string.format("%s\n%s", tostring(call.Summary), tostring(call.Location)),
				string.format("%s INCIDENT", tostring(call.Priority):upper())
			)
		end
	end)
end

function EmergencyAlertController:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end
end

return EmergencyAlertController
