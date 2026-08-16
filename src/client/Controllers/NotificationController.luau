--!strict

local NotificationController = {}

function NotificationController:Init(context: any)
	self.context = context
	self.notificationSystem = context.Systems and context.Systems.NotificationSystem or nil
	self.ownsNotificationSystem = false
end

function NotificationController:Start() end

function NotificationController:Show(message: string, title: string?, _duration: number?)
	if not self.notificationSystem then
		local NotificationSystem = require(script.Parent.Parent.UI.NotificationSystem)
		self.notificationSystem = NotificationSystem.new(self.context)
		self.ownsNotificationSystem = true
	end
	self.notificationSystem:ShowInfo(message, title or "RoleplayOS")
end

function NotificationController:ShowError(message: string)
	if not self.notificationSystem then
		local NotificationSystem = require(script.Parent.Parent.UI.NotificationSystem)
		self.notificationSystem = NotificationSystem.new(self.context)
		self.ownsNotificationSystem = true
	end
	self.notificationSystem:ShowDanger(message, "Error")
end

function NotificationController:Destroy()
	if self.ownsNotificationSystem and self.notificationSystem then
		self.notificationSystem:Destroy()
	end
	self.notificationSystem = nil
	self.ownsNotificationSystem = false
end

return NotificationController
