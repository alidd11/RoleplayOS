--!strict
local StarterGui = game:GetService("StarterGui")
local NotificationController = {}
function NotificationController:Init(_context: any) end
function NotificationController:Start() end
function NotificationController:Show(message: string, level: string?)
	pcall(
		StarterGui.SetCore,
		StarterGui,
		"SendNotification",
		{ Title = "RoleplayOS" .. (level and " · " .. level or ""), Text = message, Duration = 5 }
	)
end
function NotificationController:Destroy() end
return NotificationController
