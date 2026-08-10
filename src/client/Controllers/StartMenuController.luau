--!strict
local StartMenuController = {}
function StartMenuController:Init(context: any)
	self.context = context
	self.viewModel = nil
	self.refreshing = false
	self.refreshFinished = Instance.new("BindableEvent")
	self.lastResponse = nil
end
-- The dashboard performs the initial refresh after it has mounted the loading
-- state. Starting a second request here raced the same expensive access build,
-- duplicated group/gamepass work and left one request timing out even when the
-- other had already rendered the menu.
function StartMenuController:Start() end
function StartMenuController:Refresh(): any
	-- Opening the menu, retrying the loading screen and a purchase completion can
	-- all request a refresh at the same time. They need one server access build,
	-- not three competing requests. Late callers share the completed response.
	if self.refreshing then
		self.refreshFinished.Event:Wait()
		return self.lastResponse
	end
	self.refreshing = true
	local ok, response = pcall(function()
		return self.context.Controllers.NetworkController:Request("GetStartMenu", {})
	end)
	if not ok then
		response = {
			Success = false,
			Message = "The menu could not reach the server. Please try again.",
		}
	end
	self.lastResponse = response
	if response.Success then
		self.viewModel = response.Data
		self.context.Events.StartMenuChanged:Fire(response.Data)
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	self.refreshing = false
	self.refreshFinished:Fire()
	return response
end
function StartMenuController:Destroy()
	self.refreshFinished:Destroy()
end
return StartMenuController
