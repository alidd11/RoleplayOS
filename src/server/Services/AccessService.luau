--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AccessEvaluator = require(ReplicatedStorage.RoleplayOS.Shared.AccessEvaluator)
local AccessService = {}

local function collectGroupLinks(rule: any, result: { [string]: boolean })
	if rule.AccessType == "Group" and type(rule.GroupLinkId) == "string" then
		result[rule.GroupLinkId] = true
	end
	for _, child in rule.Rules or {} do
		collectGroupLinks(child, result)
	end
end
function AccessService:Init(context: any)
	self.context = context
end
function AccessService:Start() end
function AccessService:Evaluate(player: Player, rule: any, extra: any?): any
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return {
			Allowed = false,
			ReasonCode = "PROFILE_UNAVAILABLE",
			Message = "Your profile is not available.",
			Metadata = {},
		}
	end
	local profile = session.Profile
	local subject = {
		Gamepasses = profile.GamepassCache,
		Applications = {},
		Qualifications = profile.Qualifications,
		Whitelists = profile.Whitelists,
		Departments = extra and extra.Departments,
		Ranks = extra and extra.Ranks,
		Permissions = extra and extra.Permissions,
		TemporaryAccess = profile.AuditMetadata.TemporaryAccess,
		Suspended = profile.AuditMetadata.Suspended,
		SuspensionReason = profile.AuditMetadata.SuspensionReason,
		Blacklisted = profile.AuditMetadata.Blacklisted,
		BlacklistReason = profile.AuditMetadata.BlacklistReason,
		Groups = {},
		ServerKind = self.context.Services:Get("CommunityServerService"):Kind(),
	}
	local requiredGroups = {}
	collectGroupLinks(rule, requiredGroups)
	for linkId in requiredGroups do
		subject.Groups[linkId] =
			self.context.Services:Get("GroupService"):GetMembership(player, linkId)
	end
	for _, application in profile.Applications do
		subject.Applications[application.FormId] = application.Status
	end
	return AccessEvaluator.evaluate(rule, subject)
end
function AccessService:Destroy() end
return AccessService
