--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local WarrantService = { warrants = {}, byCharacter = {} }

function WarrantService:Init(context: any)
	self.context = context
end

function WarrantService:Start() end

function WarrantService:CachePersonRecord(record: any)
	local characterId = record.CharacterId
	if type(characterId) ~= "string" then
		return
	end
	local previous = self.byCharacter[characterId]
	if previous then
		for warrantId in previous do
			self.warrants[warrantId] = nil
		end
	end
	local ids = {}
	for _, warrant in if type(record.Warrants) == "table" then record.Warrants else {} do
		if type(warrant.WarrantId) == "string" then
			ids[warrant.WarrantId] = true
			self.warrants[warrant.WarrantId] = warrant
		end
	end
	self.byCharacter[characterId] = ids
end

function WarrantService:HasActiveForCharacter(characterId: string): (boolean, { any })
	local active = {}
	local now = os.time()
	for warrantId in self.byCharacter[characterId] or {} do
		local warrant = self.warrants[warrantId]
		if
			warrant
			and warrant.Active == true
			and (warrant.ExpiresAt == nil or warrant.ExpiresAt > now)
		then
			table.insert(active, warrant)
		end
	end
	return #active > 0, active
end

function WarrantService:_filter(actor: Player, raw: string): (string?, string?)
	local maximum = self.context.Configuration.MDT.MaximumWarrantReasonLength
	local reason = string.sub(string.gsub(raw, "[%c]", ""), 1, maximum)
	reason = string.match(reason, "^%s*(.-)%s*$") or ""
	if #reason < 3 then
		return nil, "INVALID_WARRANT_REASON"
	end
	if RunService:IsStudio() then
		return reason, nil
	end
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(reason, actor.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" or #filtered < 3 then
		return nil, "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

function WarrantService:Create(
	actor: Player,
	characterId: string,
	rawReason: string,
	expiresAt: number?
): (any?, string?)
	if not self.context.Services:Get("MDTService"):CanUsePermission(actor, "WarrantWrite") then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local reason, filterReason = self:_filter(actor, rawReason)
	if not reason then
		return nil, filterReason
	end
	local now = os.time()
	if expiresAt ~= nil then
		expiresAt = math.floor(expiresAt)
		local latest = now + self.context.Configuration.MDT.MaximumWarrantDurationDays * 86400
		if expiresAt <= now or expiresAt > latest then
			return nil, "INVALID_WARRANT_EXPIRY"
		end
	end
	local warrant = {
		WarrantId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Reason = reason,
		IssuedAt = now,
		IssuedByUserId = actor.UserId,
		ExpiresAt = expiresAt,
		Active = true,
	}
	local found = false
	local record, storeReason = self.context.Services
		:Get("RecordIndexService")
		:UpdatePerson(characterId, function(existing)
			if type(existing) ~= "table" then
				return nil
			end
			found = true
			existing.Warrants = if type(existing.Warrants) == "table" then existing.Warrants else {}
			local alreadyWritten = false
			for _, storedWarrant in existing.Warrants do
				if storedWarrant.WarrantId == warrant.WarrantId then
					alreadyWritten = true
					break
				end
			end
			if not alreadyWritten then
				table.insert(existing.Warrants, warrant)
			end
			existing.UpdatedAt = os.time()
			return existing
		end)
	if not found or not record then
		return nil, storeReason or "PERSON_RECORD_NOT_FOUND"
	end
	self:CachePersonRecord(record)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Warrant.Created",
		Target = warrant.WarrantId,
		Metadata = { CharacterId = characterId },
	})
	return warrant, nil
end

function WarrantService:Revoke(
	actor: Player,
	characterId: string,
	warrantId: string
): (any?, string?)
	if not self.context.Services:Get("MDTService"):CanUsePermission(actor, "WarrantWrite") then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local revoked
	local record, storeReason = self.context.Services
		:Get("RecordIndexService")
		:UpdatePerson(characterId, function(existing)
			if type(existing) ~= "table" or type(existing.Warrants) ~= "table" then
				return existing
			end
			for _, warrant in existing.Warrants do
				if warrant.WarrantId == warrantId and warrant.Active == true then
					warrant.Active = false
					warrant.RevokedAt = os.time()
					warrant.RevokedByUserId = actor.UserId
					revoked = warrant
					break
				end
			end
			existing.UpdatedAt = os.time()
			return existing
		end)
	if storeReason then
		return nil, storeReason
	end
	if not revoked or not record then
		return nil, "ACTIVE_WARRANT_NOT_FOUND"
	end
	self:CachePersonRecord(record)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Warrant.Revoked",
		Target = warrantId,
		Metadata = { CharacterId = characterId },
	})
	return revoked, nil
end

function WarrantService:Destroy()
	table.clear(self.warrants)
	table.clear(self.byCharacter)
end

return WarrantService
