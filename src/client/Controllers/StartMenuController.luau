--!strict
local StartMenuController = {}
function StartMenuController:Init(context: any)
	self.context = context
	self.viewModel = nil
end
function StartMenuController:Start()
	self:Refresh()
end
function StartMenuController:Refresh(): any
	local response = self.context.Controllers.NetworkController:Request("GetStartMenu", {})
	if response.Success then
		self.viewModel = response.Data
		self.context.Events.StartMenuChanged:Fire(response.Data)
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end
function StartMenuController:Destroy() end
return StartMenuController
