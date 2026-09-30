--!strict

local HttpService = game:GetService("HttpService")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isCurrentWarrant(warrant: any, now: number): boolean
	return type(warrant) == "table"
		and warrant.Active == true
		and (
			warrant.ExpiresAt == nil
			or (finiteNumber(warrant.ExpiresAt) and warrant.ExpiresAt > now)
		)
end

local function trimWarrantHistory(warrants: { any }, now: number, maximum: number)
	if #warrants <= maximum then
		return
	end

	local removable = {}
	for index, warrant in warrants do
		if not isCurrentWarrant(warrant, now) then
			local removedAt = if type(warrant) == "table"
				then tonumber(warrant.RevokedAt) or tonumber(warrant.ExpiresAt) or tonumber(
					warrant.IssuedAt
				)
				else nil
			if not finiteNumber(removedAt) then
				removedAt = 0
			end
			table.insert(removable, {
				Index = index,
				At = removedAt,
			})
		end
	end
	table.sort(removable, function(a, b)
		if a.At == b.At then
			return a.Index < b.Index
		end
		return a.At < b.At
	end)

	local removeCount = math.min(#removable, #warrants - maximum)
	local indexes = {}
	for position = 1, removeCount do
		table.insert(indexes, removable[position].Index)
	end
	table.sort(indexes, function(a, b)
		return a > b
	end)
	for _, index in indexes do
		table.remove(warrants, index)
	end
end

local WarrantService = {
	warrants = {},
	byCharacter = {},
	cacheMeta = {},
	cacheCount = 0,
	cacheSweepCounter = 0,
	refreshing = {},
	refreshCount = 0,
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
	table.clear(self.refreshing)
	self.refreshCount = 0
	self.running = false
	-- RecordIndexService starts earlier and may hydrate person records before this
	-- service's Start runs. Cache hydration is valid after Init, but never after
	-- Destroy, when background indexing is still unwinding in reverse order.
	self.acceptingCache = true
end

function WarrantService:Start()
	self.running = true
end

function WarrantService:_disposeRefreshState(state: any)
	if state.Event and state.Waiters == 0 then
		state.Event:Destroy()
		state.Event = nil
	end
end

function WarrantService:_finishRefresh(characterId: string, state: any, reason: string?)
	if self.refreshing[characterId] ~= state then
		return
	end
	self.refreshing[characterId] = nil
	self.refreshCount = math.max(0, self.refreshCount - 1)
	state.Reason = reason
	state.Done = true
	if state.Event then
		state.Event:Fire()
	end
	self:_disposeRefreshState(state)
end

function WarrantService:_loadFreshPerson(characterId: string): (any?, string?)
	local safe, record, reason = pcall(function()
		return self.context.Services:Get("RecordIndexService"):GetPersonFresh(characterId)
	end)
	if not safe then
		self.context.Logger:Error("Warrant cache refresh raised", {
			CharacterId = characterId,
			Error = tostring(record),
		})
		return nil, "WARRANT_CACHE_UNAVAILABLE"
	end
	return record, reason
end

function WarrantService:_refreshCharacter(characterId: string): (boolean, string?)
	local existing = self.refreshing[characterId]
	if existing then
		existing.Waiters += 1
		existing.Event.Event:Wait()
		existing.Waiters -= 1
		local reason = existing.Reason
		self:_disposeRefreshState(existing)
		if reason then
			return false, reason
		end
		return true, nil
	end

	-- The in-flight table is working state, not a cache. Reuse the warrant cache
	-- character cap as its hard memory bound. Do not bypass that bound with an
	-- untracked durable read: under pathological pressure a temporary unavailable
	-- result is safer than multiplying DataStore load or allowing a late read to
	-- overwrite a newer local warrant mutation.
	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumWarrantCacheCharacters) or 512)
	)
	if self.refreshCount >= maximum then
		return false, "WARRANT_CACHE_UNAVAILABLE"
	end

	local state = {
		Event = Instance.new("BindableEvent"),
		Waiters = 0,
		Done = false,
		Reason = nil,
		LatestRecord = nil,
	}
	self.refreshing[characterId] = state
	self.refreshCount += 1

	local record, reason = self:_loadFreshPerson(characterId)
	if self.refreshing[characterId] ~= state then
		-- Destroy may have released the state while the DataStore read yielded.
		return false, "WARRANT_CACHE_UNAVAILABLE"
	end
	if reason then
		self:_finishRefresh(characterId, state, reason)
		return false, reason
	end
	if not self.running or not self.acceptingCache then
		self:_finishRefresh(characterId, state, "WARRANT_CACHE_UNAVAILABLE")
		return false, "WARRANT_CACHE_UNAVAILABLE"
	end
	-- A warrant create/revoke or person re-index can commit while the durable
	-- refresh above is yielding. CachePersonRecord records that later authoritative
	-- result on this refresh state. Prefer it over the refresh snapshot so a late
	-- read cannot roll wanted state backwards on this server.
	local cacheRecord = state.LatestRecord or record
	if cacheRecord then
		self:CachePersonRecord(cacheRecord)
	end
	self:_finishRefresh(characterId, state, nil)
	return true, nil
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
	local refreshState = self.refreshing[characterId]
	if refreshState then
		-- This cache write completed while a fresh durable read was in flight. Keep
		-- the most recent local durable result attached to that read so its older
		-- snapshot cannot overwrite us when it resumes.
		refreshState.LatestRecord = record
	end
	local previous = self.byCharacter[characterId]
	if previous then
		for warrantId in previous do
			self.warrants[warrantId] = nil
		end
	end
	local ids = {}
	for _, warrant in if type(record.Warrants) == "table" then record.Warrants else {} do
		if type(warrant) == "table" and type(warrant.WarrantId) == "string" then
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
		-- The warrant cache has its own freshness contract. Reading through the
		-- general person-record cache here can extend a stale wanted/not-wanted
		-- result when another server changes a warrant shortly before this entry
		-- expires, so TTL/cap misses go back to the durable record. Coalesce callers
		-- for the same character so person search, vehicle search and ANPR cannot all
		-- spend a separate durable read while one refresh is already in flight.
		local refreshed, reason = self:_refreshCharacter(characterId)
		if not refreshed then
			return false, {}, reason
		end
		meta = self.cacheMeta[characterId]
		if not meta then
			return false, {}, nil
		end
	end
	if meta then
		meta.AccessedAt = os.clock()
	end

	local active = {}
	local now = os.time()
	for warrantId in self.byCharacter[characterId] or {} do
		local warrant = self.warrants[warrantId]
		if isCurrentWarrant(warrant, now) then
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
		if expiresAt ~= expiresAt or expiresAt == math.huge or expiresAt == -math.huge then
			return nil, "INVALID_WARRANT_EXPIRY"
		end
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
	local maximumActive = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumActiveWarrantsPerPerson) or 16)
	)
	local maximumHistory = math.max(
		maximumActive,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumWarrantHistoryEntries) or 100)
	)
	local record, storeReason = self.context.Services
		:Get("RecordIndexService")
		:UpdatePerson(characterId, function(existing)
			if type(existing) ~= "table" then
				return nil
			end
			existing.Warrants = if type(existing.Warrants) == "table" then existing.Warrants else {}
			local activeCount = 0
			for _, storedWarrant in existing.Warrants do
				if type(storedWarrant) == "table" then
					if storedWarrant.WarrantId == warrant.WarrantId then
						return existing
					end
					if isCurrentWarrant(storedWarrant, now) then
						activeCount += 1
					end
				end
			end
			if activeCount >= maximumActive then
				return existing
			end
			table.insert(existing.Warrants, warrant)
			trimWarrantHistory(existing.Warrants, now, maximumHistory)
			existing.UpdatedAt = now
			return existing
		end)
	if not record then
		return nil, storeReason or "PERSON_RECORD_NOT_FOUND"
	end
	self:CachePersonRecord(record)
	local storedWarrant
	for _, candidate in if type(record.Warrants) == "table" then record.Warrants else {} do
		if type(candidate) == "table" and candidate.WarrantId == warrant.WarrantId then
			storedWarrant = candidate
			break
		end
	end
	if not storedWarrant then
		return nil, "ACTIVE_WARRANT_LIMIT_REACHED"
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Warrant.Created",
		Target = warrant.WarrantId,
		Metadata = { CharacterId = characterId },
	})
	return storedWarrant, nil
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
	local revokedAt = os.time()
	local maximumHistory = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumWarrantHistoryEntries) or 100)
	)
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
				if type(warrant) == "table" and warrant.WarrantId == warrantId then
					if warrant.Active == true then
						warrant.Active = false
						warrant.RevokedAt = revokedAt
						warrant.RevokedByUserId = actor.UserId
						warrant.RevocationOperationId = revocationOperationId
						revoked = warrant
						trimWarrantHistory(existing.Warrants, revokedAt, maximumHistory)
						existing.UpdatedAt = revokedAt
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
	local refreshing = {}
	for characterId, state in self.refreshing do
		table.insert(refreshing, { CharacterId = characterId, State = state })
	end
	for _, pending in refreshing do
		self:_finishRefresh(pending.CharacterId, pending.State, "WARRANT_CACHE_UNAVAILABLE")
	end
	table.clear(self.refreshing)
	self.refreshCount = 0
	table.clear(self.warrants)
	table.clear(self.byCharacter)
	table.clear(self.cacheMeta)
	self.cacheCount = 0
	self.cacheSweepCounter = 0
end

return WarrantService
