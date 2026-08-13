--!strict

local AccessEvaluator = {}

local messages = {
	GAMEPASS_REQUIRED = "A gamepass is required.",
	APPLICATION_REQUIRED = "An approved application is required.",
	GROUP_REQUIRED = "Membership of the linked Roblox group is required.",
	GROUP_RANK_REQUIRED = "A higher rank in the linked Roblox group is required.",
	GROUP_CHECK_FAILED = "Roblox group membership could not be verified. Please try again.",
	GROUP_NOT_CONFIGURED = "This department's Roblox group has not been configured.",
	RANK_REQUIRED = "A higher rank is required.",
	QUALIFICATION_REQUIRED = "A qualification is required.",
	DEPARTMENT_REQUIRED = "Department membership is required.",
	WHITELIST_REQUIRED = "Whitelist access is required.",
	STAFF_REQUIRED = "Staff permission is required.",
	SUSPENDED = "Access is suspended.",
	BLACKLISTED = "Access is denied because this account is blacklisted.",
	ACCESS_DENIED = "Access requirements are not met.",
	SERVER_KIND_REQUIRED = "This entitlement is not available in this server type.",
}

local function denied(code: string, message: string?, metadata: any?): any
	return {
		Allowed = false,
		ReasonCode = code,
		Message = message or messages[code] or messages.ACCESS_DENIED,
		Metadata = metadata or {},
	}
end

function AccessEvaluator.evaluate(rule: any, subject: any, now: number?): any
	if subject.Blacklisted then
		return denied("BLACKLISTED", subject.BlacklistReason)
	end
	if subject.Suspended then
		return denied("SUSPENDED", subject.SuspensionReason)
	end
	local current = now or os.time()
	local kind = rule.AccessType
	if kind == "Public" then
		return { Allowed = true, ReasonCode = "OK", Metadata = {} }
	end
	if kind == "ServerKind" then
		-- Kind names one, Kinds names several. Several is how "anywhere except the
		-- public place" is written, since there is no negation here and listing
		-- the alternatives is clearer than inventing one.
		if rule.Kinds ~= nil then
			for _, allowed in rule.Kinds do
				if subject.ServerKind == allowed then
					return { Allowed = true, ReasonCode = "OK", Metadata = {} }
				end
			end
			return denied("SERVER_KIND_REQUIRED", rule.Message, { RequiredKinds = rule.Kinds })
		end
		if subject.ServerKind == rule.Kind then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("SERVER_KIND_REQUIRED", rule.Message, { RequiredKind = rule.Kind })
	end
	if kind == "Gamepass" then
		if subject.Gamepasses and subject.Gamepasses[tostring(rule.GamepassId or rule.Id)] then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("GAMEPASS_REQUIRED", rule.Message, { GamepassId = rule.GamepassId })
	end
	if kind == "Application" then
		if subject.Applications and subject.Applications[rule.DepartmentId] == "Accepted" then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("APPLICATION_REQUIRED", rule.Message, {
			DepartmentId = rule.DepartmentId,
			Status = subject.Applications and subject.Applications[rule.DepartmentId],
		})
	end
	if kind == "Group" then
		local membership = subject.Groups and subject.Groups[rule.GroupLinkId]
		if not membership then
			return denied("GROUP_CHECK_FAILED")
		end
		if membership.NotConfigured then
			return denied("GROUP_NOT_CONFIGURED", nil, { GroupLinkId = rule.GroupLinkId })
		end
		if membership.Failed then
			return denied("GROUP_CHECK_FAILED")
		end
		if not membership.IsMember then
			return denied("GROUP_REQUIRED", nil, { GroupId = membership.GroupId })
		end
		local minimumRank = rule.MinimumGroupRank or membership.MinimumRank or 1
		if membership.HighestRank < minimumRank then
			return denied("GROUP_RANK_REQUIRED", nil, {
				GroupId = membership.GroupId,
				MinimumRank = minimumRank,
				CurrentRank = membership.HighestRank,
			})
		end
		return { Allowed = true, ReasonCode = "OK", Message = "", Metadata = {} }
	end
	if kind == "Rank" then
		if
			(subject.Ranks and subject.Ranks[rule.DepartmentId] or -1) >= (rule.MinimumRank or 0)
		then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("RANK_REQUIRED", rule.Message, { MinimumRank = rule.MinimumRank })
	end
	if kind == "Qualification" then
		if subject.Qualifications and subject.Qualifications[rule.QualificationId] then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied(
			"QUALIFICATION_REQUIRED",
			rule.Message,
			{ QualificationId = rule.QualificationId }
		)
	end
	if kind == "Department" then
		if subject.Departments and subject.Departments[rule.DepartmentId] then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("DEPARTMENT_REQUIRED")
	end
	if kind == "Whitelist" then
		if subject.Whitelists and subject.Whitelists[rule.Id] then
			return { Allowed = true, ReasonCode = "OK", Metadata = {} }
		end
		return denied("WHITELIST_REQUIRED")
	end
	if kind == "Staff" then
		if subject.Permissions and subject.Permissions[rule.Id] then
			return { Allowed = true, ReasonCode = "OK", Message = "", Metadata = {} }
		end
		return denied("STAFF_REQUIRED")
	end
	if kind == "Combined" then
		local matchAny = rule.Match == "Any"
		local last = denied("ACCESS_DENIED")
		local actionable = nil
		for _, child in rule.Rules or {} do
			local result = AccessEvaluator.evaluate(child, subject, current)
			if result.Allowed == matchAny then
				return result
			end
			last = result
			-- An Any rule commonly describes access in different server tiers. A
			-- branch for another tier fails with SERVER_KIND_REQUIRED, but that is
			-- not the useful reason to show in the current tier. Preserve the first
			-- denial from a branch which did apply (for example a missing pass in a
			-- public server, or group membership in a whitelisted server).
			if result.ReasonCode ~= "SERVER_KIND_REQUIRED" and actionable == nil then
				actionable = result
			end
		end
		if matchAny then
			return actionable or last
		end
		return { Allowed = true, ReasonCode = "OK", Metadata = {} }
	end
	return denied("ACCESS_DENIED")
end

return table.freeze(AccessEvaluator)
