--!strict

local HttpService = game:GetService("HttpService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local WarrantService = {
	warrants = {},
	byCharacter = {},
	cacheMeta = {},
	cacheCount = 0,
	cacheSweepCounter = 0,
	running = false,
	acceptingCache = false,
}

function WarrantService:Init(context: any)
	self.context = context
	table.clear(self.warrants)
	table.clear(self.byCharacter)
	table.clear(self.cacheMeta)
	self.cacheCount = 0
	self.cacheSweepCounter = 0
	self.running = false
	-- RecordIndexService starts earlier and may hydrate person records before this
	-- service's Start runs. Cache hydration is valid after Init, but never after
	-- Destroy, when background indexing is still unwinding in reverse order.
	self.acceptingCache = true
end

function WarrantService:Start()
	self.running = true
end

function WarrantService:_dropCachedCharacter(characterId: string)
	local ids = self.byCharacter[characterId]
	if ids then
		for warrantId in ids do
			self.warrants[warrantId] = nil
		end
		self.byCharacter[characterId] = nil
	end
	if self.cacheMeta[characterId] then
		self.cacheMeta[characterId] = nil
		self.cacheCount = math.max(0, self.cacheCount - 1)
	end
end

function WarrantService:_sweepCache()
	self.cacheSweepCounter += 1
	local now = os.clock()
	if self.cacheSweepCounter >= 32 then
		self.cacheSweepCounter = 0
		for characterId, meta in self.cacheMeta do
			if type(meta) ~= "table" or (meta.ExpiresAt or 0) <= now then
				self:_dropCachedCharacter(characterId)
			end
		end
	end

	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumWarrantCacheCharacters) or 512)
	)
	while self.cacheCount > maximum do
		local oldestCharacterId
		local oldestAccess = math.huge
		for characterId, meta in self.cacheMeta do
			local accessedAt = if type(meta) == "table" then meta.AccessedAt or 0 else 0
			if accessedAt < oldestAccess then
				oldestAccess = accessedAt
				oldestCharacterId = characterId
			end
		end
		if not oldestCharacterId then
			break
		end
		self:_dropCachedCharacter(oldestCharacterId)
	end
end

function WarrantService:CachePersonRecord(record: any)
	if not self.acceptingCache then
		return
	end
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
	if not self.cacheMeta[characterId] then
		self.cacheCount += 1
	end
	local now = os.clock()
	self.cacheMeta[characterId] = {
		ExpiresAt = now + self.context.Configuration.MDT.RecordCacheSeconds,
		AccessedAt = now,
	}
	self:_sweepCache()
end

function WarrantService:HasActiveForCharacter(characterId: string): (boolean, { any }, string?)
	if not self.running or not self.acceptingCache then
		return false, {}, "WARRANT_CACHE_UNAVAILABLE"
	end
	local meta = self.cacheMeta[characterId]
	local clock = os.clock()
	if not meta or (meta.ExpiresAt or 0) <= clock then
		if meta then
			self:_dropCachedCharacter(characterId)
		end
		local record, reason =
			self.context.Services:Get("RecordIndexService"):GetPerson(characterId)
		if reason then
			return false, {}, reason
		end
		if not record then
			return false, {}, nil
		end
		if not self.acceptingCache then
			return false, {}, "WARRANT_CACHE_UNAVAILABLE"
		end
		self:CachePersonRecord(record)
		meta = self.cacheMeta[characterId]
	end
	if meta then
		meta.AccessedAt = os.clock()
	end

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
	return #active > 0, active, nil
end

function WarrantService:_filter(actor: Player, raw: string): (string?, string?)
	local maximum = self.context.Configuration.MDT.MaximumWarrantReasonLength
	local reason = string.sub(string.gsub(raw, "[%c]", ""), 1, maximum)
	reason = string.match(reason, "^%s*(.-)%s*$") or ""
	if #reason < 3 then
		return nil, "INVALID_WARRANT_REASON"
	end
	local filtered, filterReason = TextFilter.forBroadcast(reason, actor.UserId)
	if not filtered or #filtered < 3 then
		return nil, filterReason or "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

function WarrantService:Create(
	actor: Player,
	characterId: string,
	rawReason: string,
	expiresAt: number?
): (any?, string?)
	if not self.running then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local mdt = self.context.Services:Get("MDTService")
	local authorised = mdt:CanUsePermission(actor, "WarrantWrite")
	if not self.running or not authorised then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local reason, filterReason = self:_filter(actor, rawReason)
	if not reason then
		return nil, filterReason
	end
	-- Text filtering yields. The officer may leave duty, change role or disconnect
	-- while Roblox is moderating the reason. Re-authorise immediately before the
	-- durable person-record write so an old request cannot issue a warrant with
	-- stale WarrantWrite authority.
	authorised = mdt:CanUsePermission(actor, "WarrantWrite")
	if not self.running or not authorised then
		return nil, "MDT_NOT_AUTHORISED"
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
	if not self.running then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local authorised =
		self.context.Services:Get("MDTService"):CanUsePermission(actor, "WarrantWrite")
	if not self.running or not authorised then
		return nil, "MDT_NOT_AUTHORISED"
	end
	local revocationOperationId = HttpService:GenerateGUID(false)
	local revoked
	local record, storeReason = self.context.Services
		:Get("RecordIndexService")
		:UpdatePerson(characterId, function(existing)
			-- UpdateAsync may invoke this transform more than once after a conflict,
			-- and DataService may retry the whole call after an ambiguous failure.
			-- Reset per invocation so a discarded transform cannot later claim that
			-- this actor revoked a warrant another server actually changed.
			revoked = nil
			if type(existing) ~= "table" or type(existing.Warrants) ~= "table" then
				return existing
			end
			for _, warrant in existing.Warrants do
				if warrant.WarrantId == warrantId then
					if warrant.Active == true then
						warrant.Active = false
						warrant.RevokedAt = os.time()
						warrant.RevokedByUserId = actor.UserId
						warrant.RevocationOperationId = revocationOperationId
						revoked = warrant
						existing.UpdatedAt = os.time()
						return existing
					end
					if warrant.RevocationOperationId == revocationOperationId then
						-- A previous retry may have committed successfully even if Roblox
						-- reported an ambiguous failure. Recognise only this operation's
						-- marker; never inherit another server's revocation attribution.
						revoked = warrant
						return existing
					end
					return existing
				end
			end
			return existing
		end)
	if storeReason then
		return nil, storeReason
	end
	if record then
		-- Even if another server won the revocation race, use the durable result
		-- we just observed to retire any stale active-warrant cache on this server.
		self:CachePersonRecord(record)
	end
	if not revoked or not record then
		return nil, "ACTIVE_WARRANT_NOT_FOUND"
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Warrant.Revoked",
		Target = warrantId,
		Metadata = { CharacterId = characterId },
	})
	return revoked, nil
end

function WarrantService:Destroy()
	self.running = false
	self.acceptingCache = false
	table.clear(self.warrants)
	table.clear(self.byCharacter)
	table.clear(self.cacheMeta)
	self.cacheCount = 0
	self.cacheSweepCounter = 0
end

return WarrantService
