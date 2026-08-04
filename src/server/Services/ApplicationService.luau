--!strict
local HttpService = game:GetService("HttpService")
local ApplicationService = {}
local allowed = {
	Draft = true,
	Submitted = true,
	UnderReview = true,
	Interview = true,
	Accepted = true,
	Rejected = true,
	Withdrawn = true,
}
function ApplicationService:Init(context: any)
	self.context = context
end
function ApplicationService:Start() end
function ApplicationService:Submit(player: Player, formId: string, answers: any): (any?, string?)
	local form = self.context.Configuration.Applications[formId]
	if not form then
		return nil, "FORM_NOT_FOUND"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	for _, existing in session.Profile.Applications do
		if
			existing.FormId == formId
			and existing.Status ~= "Rejected"
			and existing.Status ~= "Withdrawn"
		then
			return nil, "APPLICATION_ALREADY_EXISTS"
		elseif
			existing.FormId == formId
			and existing.Status == "Rejected"
			and os.time() - existing.UpdatedAt < form.CooldownSeconds
		then
			return nil, "APPLICATION_COOLDOWN"
		end
	end
	local clean = {}
	for _, question in form.Questions do
		local answer = answers[question.Id]
		if
			type(answer) ~= "string"
			or #answer == 0
			or #answer > (question.MaximumLength or 100)
		then
			return nil, "INVALID_ANSWER"
		end
		if question.Type == "Choice" and not table.find(question.Options, answer) then
			return nil, "INVALID_CHOICE"
		end
		clean[question.Id] = answer
	end
	local record = {
		ApplicationId = HttpService:GenerateGUID(false),
		FormId = formId,
		Status = "Submitted",
		Answers = clean,
		SubmittedAt = os.time(),
		UpdatedAt = os.time(),
	}
	table.insert(session.Profile.Applications, record)
	-- Applications accumulate for the life of an account and nothing ever removed
	-- one, so a player who applies repeatedly grew their profile without limit
	-- until it could no longer be saved at all. The oldest go first; what matters
	-- is the current standing, not every attempt ever made.
	local maximum = self.context.Configuration.Framework.MaximumApplicationHistory or 60
	while #session.Profile.Applications > maximum do
		table.remove(session.Profile.Applications, 1)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return {
		ApplicationId = record.ApplicationId,
		FormId = formId,
		Status = record.Status,
		SubmittedAt = record.SubmittedAt,
	},
		nil
end
function ApplicationService:SetStatus(
	reviewer: Player,
	target: Player,
	applicationId: string,
	status: string,
	applicantMessage: string?
): (boolean, string?)
	if not allowed[status] then
		return false, "INVALID_STATUS"
	end
	local targetSession = self.context.Services:Get("DataService"):GetSession(target)
	if not targetSession then
		return false, "PROFILE_UNAVAILABLE"
	end
	for _, record in targetSession.Profile.Applications do
		if record.ApplicationId == applicationId then
			record.Status = status
			record.UpdatedAt = os.time()
			record.ApplicantMessage = applicantMessage
			self.context.Services:Get("DataService"):MarkDirty(target)
			self.context.Services:Get("AuditService"):Record({
				ActorUserId = reviewer.UserId,
				Action = "Application.StatusChanged",
				Target = applicationId,
				Metadata = { Status = status },
			})
			return true, nil
		end
	end
	return false, "APPLICATION_NOT_FOUND"
end
function ApplicationService:Destroy() end
return ApplicationService
