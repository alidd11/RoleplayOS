--!strict

local CommunityController = {}

function CommunityController:Init(context: any)
	self.context = context
	self.current = nil
end

function CommunityController:Start() end

function CommunityController:CreatePrivate(name: string): any
	local response = self.context.Controllers.NetworkController:Request("CreatePrivateCommunity", {
		Name = name,
	})
	if response.Success then
		self.current = response.Data
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end

function CommunityController:Destroy() end

return CommunityController
