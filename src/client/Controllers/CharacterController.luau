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
		self.context.Events.CharacterChanged:Fire(characterId)
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end
-- Asks whether this character's look may still be authored, and at what cost.
--
-- The answer is the server's to give: a character is free to author until it has
-- been authored once, and paid afterwards. The menu uses this to decide between
-- opening the creator and offering the product, so it must never be inferred
-- from anything the client already holds.
function CharacterController:AppearanceEditState(characterId: string): any
	local response = self.context.Controllers.NetworkController:Request("GetAppearanceEditState", {
		CharacterId = characterId,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Error")
	end
	return response
end
function CharacterController:SaveCurrentAppearance(characterId: string): any
	local response = self.context.Controllers.NetworkController:Request("SaveCivilianAppearance", {
		CharacterId = characterId,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Outfit unavailable")
	end
	return response
end
function CharacterController:Destroy() end
return CharacterController
