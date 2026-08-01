--!strict
local DispatchController = {}
function DispatchController:Init(context: any)
	self.context = context
end
function DispatchController:Start()
	local remote =
		self.context.Controllers.NetworkController.remotes:WaitForChild("DispatchChanged")
	remote.OnClientEvent:Connect(function(update)
		self.context.Events.DispatchChanged:Fire(update)
	end)
end
function DispatchController:Destroy() end
return DispatchController
