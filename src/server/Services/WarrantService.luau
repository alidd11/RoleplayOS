--!strict
local HttpService = game:GetService("HttpService")
local WarrantService = { warrants = {} }
function WarrantService:Init(context: any)
	self.context = context
end
function WarrantService:Start() end
function WarrantService:Create(
	actor: Player,
	characterId: string,
	reasonCode: string,
	expiresAt: number?
): any
	local warrant = {
		WarrantId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		ReasonCode = reasonCode,
		IssuedAt = os.time(),
		ExpiresAt = expiresAt,
		Active = true,
	}
	self.warrants[warrant.WarrantId] = warrant
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Warrant.Created",
		Target = warrant.WarrantId,
		Metadata = { CharacterId = characterId, ReasonCode = reasonCode },
	})
	return warrant
end
function WarrantService:Destroy()
	table.clear(self.warrants)
end
return WarrantService
