--!strict

local DutyController = {}

function DutyController:Init(context: any)
	self.context = context
	self.active = nil
end

function DutyController:Start() end

function DutyController:Begin(request: any): any
	local response = self.context.Controllers.NetworkController:Request("BeginDuty", request)
	if response.Success then
		self.active = response.Data
		self.context.Events.DutyChanged:Fire(self.active)
		self.context.Controllers.NotificationController:Show(response.Message, "On duty")
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Duty unavailable")
	end
	return response
end

function DutyController:EnterCivilian(characterId: string, spawnId: string): any
	local response = self.context.Controllers.NetworkController:Request("EnterCivilian", {
		CharacterId = characterId,
		SpawnId = spawnId,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Spawn unavailable")
	end
	return response
end

function DutyController:Destroy() end

return DutyController
