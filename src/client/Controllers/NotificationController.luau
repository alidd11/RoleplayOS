--!strict
local NotificationSystem = require(script.Parent.Parent.UI.NotificationSystem)
local NotificationController = {}
function NotificationController:Init(context: any)
	NotificationSystem:Init(context)
end
function NotificationController:Start() end
function NotificationController:Show(message: string, level: string?)
	NotificationSystem:Show(message, level)
end
function NotificationController:Destroy()
	NotificationSystem:Destroy()
end
return NotificationController
