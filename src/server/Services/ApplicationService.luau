--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)
local ApplicationService = {}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function submissionAvailable(
	profile: any,
	formId: string,
	cooldownSeconds: number
): (boolean, string?)
	for _, existing in profile.Applications do
		if
			existing.FormId == formId
			and existing.Status ~= "Rejected"
			and existing.Status ~= "Withdrawn"
		then
			return false, "APPLICATION_ALREADY_EXISTS"
		elseif
			existing.FormId == formId
			and existing.Status == "Rejected"
			and os.time() - existing.UpdatedAt < cooldownSeconds
		then
			return false, "APPLICATION_COOLDOWN"
		end
	end
	return true, nil
end
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
	if not playerIsCurrent(player) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local form = self.context.Configuration.Applications[formId]
	if not form then
		return nil, "FORM_NOT_FOUND"
	end
	local data = self.context.Services:Get("DataService")
	local session = data:GetSession(player)
	if not session or session.Releasing then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local available, availabilityReason =
		submissionAvailable(session.Profile, formId, form.CooldownSeconds)
	if not available then
		return nil, availabilityReason
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
		if question.Type == "Choice" then
			clean[question.Id] = answer
		else
			-- Free text written by one player and read by another. Every other
			-- player authored string in the framework is filtered before it is
			-- stored; these were not, and they are read by reviewing staff.
			local filtered, filterReason = TextFilter.forBroadcast(answer, player.UserId)
			if not filtered then
				return nil, filterReason or "TEXT_FILTER_UNAVAILABLE"
			end
			clean[question.Id] = filtered
		end
	end
	-- Filtering yields. PlayerRemoving defers the final save, so the outgoing
	-- session can still be present here while its save snapshot is already in
	-- flight. Matching only by UserId/session reference is therefore not enough:
	-- a stale submit must not dirty a profile after its release snapshot.
	if not playerIsCurrent(player) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local current = data:GetSession(player)
	if not current or current ~= session or current.Releasing then
		return nil, "PROFILE_UNAVAILABLE"
	end
	-- Another request can finish filtering first, or an application can be
	-- rejected while this request is yielding. Re-run the complete policy rather
	-- than only the active-application half so cooldowns cannot be bypassed.
	available, availabilityReason =
		submissionAvailable(current.Profile, formId, form.CooldownSeconds)
	if not available then
		return nil, availabilityReason
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
	data:MarkDirty(player)
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
