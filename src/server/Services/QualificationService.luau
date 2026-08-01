--!strict
local QualificationService = {}
function QualificationService:Init(context: any)
	self.context = context
end
function QualificationService:Start() end
function QualificationService:Grant(
	actor: Player,
	target: Player,
	qualificationId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(target)
	if not session then
		return false, "PROFILE_UNAVAILABLE"
	end
	session.Profile.Qualifications[qualificationId] =
		{ QualificationId = qualificationId, AwardedAt = os.time(), AwardedBy = actor.UserId }
	self.context.Services:Get("DataService"):MarkDirty(target)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Qualification.Granted",
		Target = qualificationId,
		Metadata = { TargetUserId = target.UserId },
	})
	return true, nil
end
function QualificationService:Destroy() end
return QualificationService
