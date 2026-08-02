--!strict
local CharacterController = {}
function CharacterController:Init(context: any)
	self.context = context
	self.activeCharacterId = nil
end
function CharacterController:Start() end
function CharacterController:Create(identity: any): any
	local response = self.context.Controllers.NetworkController:Request("CreateCharacter", {
		Identity = identity,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end
function CharacterController:Select(characterId: string): any
	local response = self.context.Controllers.NetworkController:Request(
		"SelectCharacter",
		{ CharacterId = characterId }
	)
	if response.Success then
		self.activeCharacterId = characterId
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end
function CharacterController:Destroy() end
return CharacterController
