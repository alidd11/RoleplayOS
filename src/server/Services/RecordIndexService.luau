--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local RecordIndexService = {
	connections = {},
	queued = {},
	waiting = {},
	pendingSync = {},
	personIndexRepairs = {},
	personIndexRepairCount = 0,
	vehicleIndexRepairs = {},
	vehicleIndexRepairCount = 0,
	cache = {},
	cacheCount = 0,
	cacheSweepCounter = 0,
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function normalise(value: string): string
	return string.lower(value):gsub("[^a-z0-9 ]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

local function compact(value: string): string
	return normalise(value):gsub(" ", "")
end

local function recordKey(kind: string, id: string): string
	return kind .. ":" .. id
end

local function indexKey(kind: string, value: string): string?
	local token = string.match(normalise(value), "[a-z0-9]+") or ""
	if #token < 2 then
		return nil
	end
	return kind .. ":" .. string.sub(token, 1, 2)
end

local function personView(record: any, accessProfile: string, warrants: { any }?): any
	local police = accessProfile == "Police"
	local highways = police or accessProfile == "Highways"
	local visibleWarrants = warrants or {}
	return {
		CharacterId = record.CharacterId,
		FullName = record.FullName,
		DateOfBirth = record.DateOfBirth,
		Licences = if highways then record.Licences else nil,
		DrivingRecord = if highways then record.DrivingRecord else nil,
		CustodyRecord = if police then record.CustodyRecord else nil,
		CriminalRecord = if police then record.CriminalRecord else nil,
		Warrants = if warrants ~= nil then visibleWarrants else nil,
		Flags = if #visibleWarrants > 0 then { "WANTED" } else {},
		AccessProfile = accessProfile,
		UpdatedAt = record.UpdatedAt,
	}
end

function RecordIndexService:Init(context: any)
	self.context = context
	table.clear(self.queued)
	table.clear(self.waiting)
	table.clear(self.cache)
	table.clear(self.pendingSync)
	table.clear(self.personIndexRepairs)
	self.personIndexRepairCount = 0
	table.clear(self.vehicleIndexRepairs)
	self.vehicleIndexRepairCount = 0
	self.cacheCount = 0
	self.cacheSweepCounter = 0
end

function RecordIndexService:_cacheDrop(key: string)
	if self.cache[key] ~= nil then
		self.cache[key] = nil
		self.cacheCount = math.max(0, self.cacheCount - 1)
	end
end

function RecordIndexService:_cacheSet(key: string, value: any)
	if not self.running then
		return
	end
	local replacing = self.cache[key] ~= nil
	self.cache[key] = {
		Value = value,
		ExpiresAt = os.clock() + self.context.Configuration.MDT.RecordCacheSeconds,
	}
	if not replacing then
		self.cacheCount += 1
	end
	self:_sweepCache()
end

-- Drops entries whose time is up and enforces a hard entry cap.
--
-- TTL alone bounds how long an entry can live, not how many unique records a
-- busy server can touch inside that window. The count cap prevents a burst of
-- searches from growing the record cache with every returned person/vehicle.
function RecordIndexService:_sweepCache()
	self.cacheSweepCounter += 1
	local now = os.clock()
	if self.cacheSweepCounter >= 32 then
		self.cacheSweepCounter = 0
		for key, entry in self.cache do
			if type(entry) ~= "table" or (entry.ExpiresAt or 0) <= now then
				self:_cacheDrop(key)
			end
		end
	end

	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumRecordCacheEntries) or 2048)
	)
	while self.cacheCount > maximum do
		local oldestKey
		local oldestExpiry = math.huge
		for key, entry in self.cache do
			local expiresAt = if type(entry) == "table" then entry.ExpiresAt or 0 else 0
			if expiresAt < oldestExpiry then
				oldestExpiry = expiresAt
				oldestKey = key
			end
		end
		if not oldestKey then
			break
		end
		self:_cacheDrop(oldestKey)
	end
end

function RecordIndexService:_getRecordFresh(key: string): (any?, string?)
	if not self.running then
		return nil, "INDEX_CANCELLED"
	end
	local value, reason = self.context.Services:Get("DataService"):GetMdtRecord(key)
	if reason then
		return nil, reason
	end
	if not self.running then
		return nil, "INDEX_CANCELLED"
	end
	self:_cacheDrop(key)
	if value then
		self:_cacheSet(key, value)
	end
	return value, nil
end

function RecordIndexService:_getRecord(key: string): (any?, string?)
	local cached = self.cache[key]
	if cached and cached.ExpiresAt > os.clock() then
		return cached.Value, nil
	end
	self:_cacheDrop(key)
	return self:_getRecordFresh(key)
end

function RecordIndexService:_updateRecord(key: string, transform: (any?) -> any): (any?, string?)
	local updated, reason = self.context.Services:Get("DataService"):UpdateMdtRecord(key, transform)
	if updated then
		self:_cacheSet(key, updated)
	end
	return updated, reason
end

function RecordIndexService:_upsertIndex(key: string, id: string, entry: any): (boolean, string?)
	local maximum = self.context.Configuration.MDT.MaximumIndexBucketEntries
	local updated, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(key, function(stored)
			local bucket = if type(stored) == "table" then stored else { Entries = {} }
			bucket.Entries = if type(bucket.Entries) == "table" then bucket.Entries else {}
			if bucket.Entries[id] == nil then
				local count = 0
				local oldestId
				local oldestAt = math.huge
				for existingId, existing in bucket.Entries do
					count += 1
					local updatedAt = if type(existing) == "table"
						then existing.UpdatedAt or 0
						else 0
					if updatedAt < oldestAt then
						oldestAt = updatedAt
						oldestId = existingId
					end
				end
				if count >= maximum and oldestId then
					bucket.Entries[oldestId] = nil
				end
			end
			bucket.Entries[id] = entry
			bucket.UpdatedAt = os.time()
			return bucket
		end)
	return updated ~= nil, reason
end

function RecordIndexService:_dropPersonIndexRepair(characterId: string, state: any)
	if self.personIndexRepairs[characterId] == state then
		self.personIndexRepairs[characterId] = nil
		self.personIndexRepairCount = math.max(0, self.personIndexRepairCount - 1)
	end
end

function RecordIndexService:_schedulePersonIndexRepair(
	player: Player,
	characterId: string,
	entry: any,
	keys: { string }
): boolean
	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.MDT.MaximumPendingPersonIndexRepairs) or 128)
	)
	while self.running and playerIsCurrent(player) do
		local existing = self.personIndexRepairs[characterId]
		if existing then
			existing.Player = player
			existing.Entry = entry
			for _, key in keys do
				if not table.find(existing.Keys, key) then
					table.insert(existing.Keys, key)
				end
			end
			return true
		end

		if self.personIndexRepairCount < maximum then
			local state = {
				Player = player,
				Entry = entry,
				Keys = table.clone(keys),
			}
			self.personIndexRepairs[characterId] = state
			self.personIndexRepairCount += 1
			task.spawn(function()
				local retrySeconds = math.max(
					5,
					tonumber(self.context.Configuration.MDT.PersonIndexRepairRetrySeconds) or 60
				)
				while
					self.running
					and self.personIndexRepairs[characterId] == state
					and playerIsCurrent(state.Player)
					and #state.Keys > 0
				do
					-- The first write already exhausted DataService's bounded retry budget.
					-- Back off before trying the missing bucket again so a store outage does
					-- not turn eventual consistency into a tight retry storm.
					task.wait(retrySeconds)
					if
						not self.running
						or self.personIndexRepairs[characterId] ~= state
						or not playerIsCurrent(state.Player)
					then
						break
					end
					local key = state.Keys[1]
					local indexed, reason = self:_upsertIndex(key, characterId, state.Entry)
					if indexed then
						table.remove(state.Keys, 1)
					else
						self.context.Logger:Warning("Person search index repair will retry", {
							CharacterId = characterId,
							Bucket = key,
							Error = reason,
						})
					end
				end
				self:_dropPersonIndexRepair(characterId, state)
			end)
			return true
		end

		-- The repair set is deliberately hard-capped. Do not discard this already
		-- committed projection merely because every recovery slot is occupied.
		-- The caller is an existing background projection worker, so apply
		-- backpressure without issuing another DataStore request until a slot frees.
		task.wait(1)
	end
	return false
end

function RecordIndexService:_dropVehicleIndexRepair(vehicleId: string, state: any)
	if self.vehicleIndexRepairs[vehicleId] == state then
		self.vehicleIndexRepairs[vehicleId] = nil
		self.vehicleIndexRepairCount = math.max(0, self.vehicleIndexRepairCount - 1)
	end
end

function RecordIndexService:_scheduleVehicleIndexRepair(
	player: Player,
	vehicleId: string,
	bucket: string,
	entry: any
): boolean
	local maximum = math.max(
		1,
		math.floor(
			tonumber(self.context.Configuration.MDT.MaximumPendingVehicleIndexRepairs) or 128
		)
	)
	while self.running and playerIsCurrent(player) do
		local existing = self.vehicleIndexRepairs[vehicleId]
		if existing then
			existing.Player = player
			existing.Bucket = bucket
			existing.Entry = entry
			existing.Generation += 1
			return true
		end

		if self.vehicleIndexRepairCount < maximum then
			local state = {
				Player = player,
				Bucket = bucket,
				Entry = entry,
				Generation = 1,
			}
			self.vehicleIndexRepairs[vehicleId] = state
			self.vehicleIndexRepairCount += 1
			task.spawn(function()
				local retrySeconds = math.max(
					5,
					tonumber(self.context.Configuration.MDT.VehicleIndexRepairRetrySeconds) or 60
				)
				while
					self.running
					and self.vehicleIndexRepairs[vehicleId] == state
					and playerIsCurrent(state.Player)
				do
					-- The durable vehicle record is already committed. Retry only the
					-- missing registration bucket after a backoff, never the record write.
					task.wait(retrySeconds)
					if
						not self.running
						or self.vehicleIndexRepairs[vehicleId] ~= state
						or not playerIsCurrent(state.Player)
					then
						break
					end
					local generation = state.Generation
					local attemptedBucket = state.Bucket
					local attemptedEntry = state.Entry
					local indexed, reason =
						self:_upsertIndex(attemptedBucket, vehicleId, attemptedEntry)
					if self.vehicleIndexRepairs[vehicleId] ~= state then
						break
					end
					if indexed and state.Generation == generation then
						self:_dropVehicleIndexRepair(vehicleId, state)
						return
					end
					if not indexed and state.Generation == generation then
						self.context.Logger:Warning("Vehicle search index repair will retry", {
							VehicleId = vehicleId,
							Bucket = attemptedBucket,
							Error = reason,
						})
					end
				end
				self:_dropVehicleIndexRepair(vehicleId, state)
			end)
			return true
		end

		-- Keep the repair map hard-capped without abandoning a durable vehicle
		-- whose search projection is missing. This caller is already a background
		-- projection worker, so waiting for capacity adds no extra DataStore load.
		task.wait(1)
	end
	return false
end

-- The person record and the name index, and nothing else.
function RecordIndexService:IndexPerson(player: Player, character: any): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "INDEX_CANCELLED"
	end
	local fullName = character.Identity.FirstName .. " " .. character.Identity.LastName
	local personKey = recordKey("Person", character.CharacterId)
	local person, reason = self:_updateRecord(personKey, function(existing)
		return {
			RecordType = "Person",
			CharacterId = character.CharacterId,
			OwnerUserId = player.UserId,
			FullName = fullName,
			DateOfBirth = character.Identity.DateOfBirth,
			Licences = character.Licences or {},
			DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} },
			CustodyRecord = character.CustodyRecord or { Bookings = {} },
			CriminalRecord = character.CriminalRecord or {},
			Warrants = if existing and type(existing.Warrants) == "table"
				then existing.Warrants
				else {},
			UpdatedAt = os.time(),
		}
	end)
	if not person then
		return false, reason
	end
	if not self.running or not playerIsCurrent(player) then
		return false, "INDEX_CANCELLED"
	end
	self.context.Services:Get("WarrantService"):CachePersonRecord(person)
	local entry = {
		CharacterId = character.CharacterId,
		FullName = fullName,
		SearchText = normalise(fullName) .. "|" .. normalise(
			character.Identity.LastName .. " " .. character.Identity.FirstName
		),
		UpdatedAt = os.time(),
	}
	local seen = {}
	local keys = {}
	for _, token in { character.Identity.FirstName, character.Identity.LastName } do
		local key = indexKey("Person", token)
		if key and not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	for position, key in keys do
		if not self.running or not playerIsCurrent(player) then
			return false, "INDEX_CANCELLED"
		end
		local indexed, indexReason = self:_upsertIndex(key, character.CharacterId, entry)
		if not indexed then
			local remaining = {}
			for remainingPosition = position, #keys do
				table.insert(remaining, keys[remainingPosition])
			end
			local scheduled =
				self:_schedulePersonIndexRepair(player, character.CharacterId, entry, remaining)
			if not scheduled then
				return false, "INDEX_CANCELLED"
			end
			self.context.Logger:Warning("Person search index write deferred for repair", {
				CharacterId = character.CharacterId,
				Bucket = key,
				Error = indexReason,
			})
			-- The durable person record is already committed. Keep vehicle projection
			-- moving while a dedicated bounded worker repairs only the missing name
			-- buckets; rewriting the person record would spend budget without helping.
			return true, nil
		end
	end
	local pending = self.personIndexRepairs[character.CharacterId]
	if pending then
		self:_dropPersonIndexRepair(character.CharacterId, pending)
	end
	return true, nil
end

-- The person record and everything they own.
--
-- Kept separate from IndexPerson above because the two change for completely
-- different reasons and cost completely different amounts. A speeding fine
-- touches the driving record and nothing else, and this used to rewrite the
-- whole fleet with it: a driver with four cars cost eleven DataStore writes for
-- one camera flash, against a budget of about six a second for the entire
-- server. Thirty drivers being fined would have spent the whole server's
-- allowance on records that had not changed.
function RecordIndexService:IndexCharacter(player: Player, character: any): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "INDEX_CANCELLED"
	end
	local ok, reason = self:IndexPerson(player, character)
	if not ok then
		return false, reason
	end
	for _, vehicle in character.Vehicles or {} do
		if not self.running or not playerIsCurrent(player) then
			return false, "INDEX_CANCELLED"
		end
		local indexed, vehicleReason = self:IndexVehicle(player, character, vehicle)
		if not indexed then
			return false, vehicleReason
		end
	end
	return true, nil
end

function RecordIndexService:IndexVehicle(
	player: Player,
	character: any,
	vehicle: any
): (boolean, string?, boolean)
	if not self.running or not playerIsCurrent(player) then
		return false, "INDEX_CANCELLED", false
	end
	local key = recordKey("Vehicle", vehicle.VehicleId)
	local updated, reason = self:_updateRecord(key, function(_existing)
		return {
			RecordType = "Vehicle",
			VehicleId = vehicle.VehicleId,
			Registration = vehicle.Registration,
			DefinitionId = vehicle.DefinitionId,
			OwnerCharacterId = character.CharacterId,
			OwnerUserId = player.UserId,
			OwnerName = character.Identity.FirstName .. " " .. character.Identity.LastName,
			Colour = vehicle.Colour,
			Mileage = vehicle.Mileage or 0,
			Condition = vehicle.Condition or 100,
			Insured = vehicle.Insured == true,
			Taxed = vehicle.Taxed == true,
			UpdatedAt = os.time(),
		}
	end)
	if not updated then
		return false, reason, false
	end
	if not self.running or not playerIsCurrent(player) then
		return false, "INDEX_CANCELLED", false
	end
	local search = compact(vehicle.Registration)
	local bucket = indexKey("Vehicle", search)
	if not bucket then
		return false, "INVALID_REGISTRATION_INDEX", false
	end
	local entry = {
		VehicleId = vehicle.VehicleId,
		Registration = vehicle.Registration,
		SearchText = search,
		UpdatedAt = os.time(),
	}
	local indexed, indexReason = self:_upsertIndex(bucket, vehicle.VehicleId, entry)
	if not indexed then
		local scheduled = self:_scheduleVehicleIndexRepair(player, vehicle.VehicleId, bucket, entry)
		if not scheduled then
			return false, "INDEX_CANCELLED", false
		end
		self.context.Logger:Warning("Vehicle search index write deferred for repair", {
			VehicleId = vehicle.VehicleId,
			Bucket = bucket,
			Error = indexReason,
		})
		-- The durable record is already committed. Treat the projection as accepted
		-- so join/full-character indexing can continue with later vehicles while the
		-- bounded repair worker restores discoverability.
		return true, nil, true
	end

	local pending = self.vehicleIndexRepairs[vehicle.VehicleId]
	if pending then
		self:_dropVehicleIndexRepair(vehicle.VehicleId, pending)
	end
	return true, nil, false
end

function RecordIndexService:_removeVehicleIndex(
	registration: string,
	vehicleId: string
): (boolean, string?)
	local bucket = indexKey("Vehicle", compact(registration))
	if not bucket then
		return true, nil
	end
	local _, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			stored.Entries[vehicleId] = nil
			stored.UpdatedAt = os.time()
			return stored
		end)
	if reason then
		self.context.Logger:Warning("Stale vehicle index removal failed", {
			VehicleId = vehicleId,
			Registration = registration,
			Error = reason,
		})
		return false, reason
	end
	return true, nil
end

function RecordIndexService:_repairStaleVehicleIndex(
	bucket: string,
	expected: any
): (boolean, string?, boolean)
	local vehicleId = expected.VehicleId
	if type(vehicleId) ~= "string" then
		return true, nil, false
	end

	-- A search may fresh-confirm that an old registration row is stale and then
	-- yield before deleting it. Another server can re-register the vehicle back
	-- into this bucket during that gap. Claim only the exact row this search read,
	-- then re-read the durable vehicle record before changing the shared index.
	local cleanupToken = HttpService:GenerateGUID(false)
	local claimed = false
	local _, claimReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			claimed = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[vehicleId]
			if
				type(current) == "table"
				and current.VehicleId == expected.VehicleId
				and current.Registration == expected.Registration
				and current.SearchText == expected.SearchText
				and current.UpdatedAt == expected.UpdatedAt
			then
				current.CleanupToken = cleanupToken
				stored.UpdatedAt = os.time()
				claimed = true
			end
			return stored
		end)
	if claimReason then
		return false, claimReason, false
	end
	if not claimed then
		-- A newer projection already owns this row.
		return true, nil, false
	end

	local record, recordReason = self:_getRecordFresh(recordKey("Vehicle", vehicleId))
	if recordReason then
		return false, recordReason, false
	end
	local currentSearch = if record and type(record.Registration) == "string"
		then compact(record.Registration)
		else ""
	local currentBucket = indexKey("Vehicle", currentSearch)

	local deleted = false
	local _, finalReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			deleted = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[vehicleId]
			if type(current) == "table" and current.CleanupToken == cleanupToken then
				if record and currentBucket == bucket then
					-- The vehicle still belongs in this bucket but the observed row was
					-- stale. Repair it from the fresh durable record instead of deleting
					-- the only searchable projection for the current registration.
					current.VehicleId = record.VehicleId
					current.Registration = record.Registration
					current.SearchText = currentSearch
					current.UpdatedAt = record.UpdatedAt or os.time()
					current.CleanupToken = nil
				else
					stored.Entries[vehicleId] = nil
					deleted = true
				end
				stored.UpdatedAt = os.time()
			end
			return stored
		end)
	if finalReason then
		return false, finalReason, false
	end
	return true, nil, deleted
end

function RecordIndexService:_removeStalePersonIndex(
	bucket: string,
	expected: any
): (boolean, string?, boolean)
	local characterId = expected.CharacterId
	if type(characterId) ~= "string" then
		return true, nil, false
	end

	-- The person record and search bucket live in separate DataStores, so a
	-- confirmed missing record cannot by itself authorise a destructive index
	-- write. Another server may re-index this character between the record read
	-- and cleanup. Claim the exact row first, then re-read the durable record.
	local cleanupToken = HttpService:GenerateGUID(false)
	local claimed = false
	local _, claimReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			claimed = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[characterId]
			if
				type(current) == "table"
				and current.CharacterId == expected.CharacterId
				and current.FullName == expected.FullName
				and current.SearchText == expected.SearchText
				and current.UpdatedAt == expected.UpdatedAt
			then
				current.CleanupToken = cleanupToken
				stored.UpdatedAt = os.time()
				claimed = true
			end
			return stored
		end)
	if claimReason then
		return false, claimReason, false
	end
	if not claimed then
		-- The row changed after this search read it. A newer projection owns it.
		return true, nil, false
	end

	local record, recordReason = self:_getRecordFresh(recordKey("Person", characterId))
	if recordReason then
		return false, recordReason, false
	end

	local deleted = false
	local _, finalReason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			deleted = false
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			local current = stored.Entries[characterId]
			if type(current) == "table" and current.CleanupToken == cleanupToken then
				if record then
					-- A concurrent re-index wrote the durable record before our claim.
					-- Keep the row and remove only our private cleanup marker.
					current.CleanupToken = nil
				else
					stored.Entries[characterId] = nil
					deleted = true
				end
				stored.UpdatedAt = os.time()
			end
			return stored
		end)
	if finalReason then
		return false, finalReason, false
	end
	return true, nil, deleted
end

function RecordIndexService:ReindexVehicle(
	player: Player,
	character: any,
	vehicle: any,
	previousRegistration: string?
): (boolean, string?)
	local indexed, reason, indexDeferred = self:IndexVehicle(player, character, vehicle)
	if
		indexed
		and not indexDeferred
		and self.running
		and playerIsCurrent(player)
		and previousRegistration
		and compact(previousRegistration) ~= compact(vehicle.Registration)
	then
		local removed, removalReason =
			self:_removeVehicleIndex(previousRegistration, vehicle.VehicleId)
		if not removed then
			return false, removalReason
		end
	end
	return indexed, reason
end

-- `scope` says what changed. "Person" writes the person record and the name
-- index; anything else also rewrites every vehicle they own. It defaults to the
-- whole lot, so a caller that has not thought about it is no worse off than
-- before, and the callers that only touch a record say so.
function RecordIndexService:ScheduleCharacter(player: Player, character: any, scope: string?)
	if not self.running or not playerIsCurrent(player) then
		return
	end
	local key = "Person:" .. character.CharacterId
	local existing = self.pendingSync[key]
	if existing then
		-- A fast rejoin may schedule the same character while the old Player
		-- instance is still inside a yielding DataStore write. Keep one job, but
		-- make its next pass use the newest live session references.
		existing.Player = player
		existing.Character = character
		existing.Full = existing.Full or scope ~= "Person"
		existing.Resync = true
		return
	end
	local state = {
		Resync = false,
		Player = player,
		Character = character,
		Full = scope ~= "Person",
	}
	self.pendingSync[key] = state
	task.spawn(function()
		-- Released whether indexing returns or raises. Held on a raise, every
		-- later change to this character was silently refused for the life of the
		-- server: bookings appeared to succeed and never reached the index.
		local ok, reason
		local safe, raised = pcall(function()
			repeat
				state.Resync = false
				local currentPlayer = state.Player
				local currentCharacter = state.Character
				local full = state.Full
				state.Full = false
				if not self.running or not playerIsCurrent(currentPlayer) then
					ok, reason = false, "INDEX_CANCELLED"
				elseif full then
					ok, reason = self:IndexCharacter(currentPlayer, currentCharacter)
				else
					ok, reason = self:IndexPerson(currentPlayer, currentCharacter)
				end
			until not self.running or not state.Resync
		end)
		if self.pendingSync[key] == state then
			self.pendingSync[key] = nil
		end
		if not safe then
			self.context.Logger:Error("Deferred MDT character indexing raised", {
				CharacterId = character.CharacterId,
				Error = tostring(raised),
			})
			return
		end
		if not ok and reason ~= "INDEX_CANCELLED" then
			self.context.Logger:Warning("Deferred MDT character indexing failed", {
				CharacterId = character.CharacterId,
				Error = reason,
			})
		end
	end)
end

function RecordIndexService:ScheduleVehicle(
	player: Player,
	character: any,
	vehicle: any,
	previousRegistration: string?
)
	if not self.running or not playerIsCurrent(player) then
		return
	end
	local key = "Vehicle:" .. vehicle.VehicleId
	local existing = self.pendingSync[key]
	if existing then
		existing.Player = player
		existing.Character = character
		existing.Vehicle = vehicle
		existing.Resync = true
		if previousRegistration then
			existing.PreviousRegistration = existing.PreviousRegistration or previousRegistration
		end
		return
	end
	local state = {
		Resync = false,
		Player = player,
		Character = character,
		Vehicle = vehicle,
		PreviousRegistration = previousRegistration,
	}
	self.pendingSync[key] = state
	task.spawn(function()
		-- Match the character worker: a raised DataStore/indexing error must not
		-- strand the per-vehicle claim forever and silently suppress every later
		-- resync for this vehicle.
		local ok, reason
		local safe, raised = pcall(function()
			repeat
				state.Resync = false
				local currentPlayer = state.Player
				local currentCharacter = state.Character
				local currentVehicle = state.Vehicle
				local previous = state.PreviousRegistration
				state.PreviousRegistration = nil
				if not self.running or not playerIsCurrent(currentPlayer) then
					ok, reason = false, "INDEX_CANCELLED"
				else
					ok, reason = self:ReindexVehicle(
						currentPlayer,
						currentCharacter,
						currentVehicle,
						previous
					)
				end
			until not self.running or not state.Resync
		end)
		if self.pendingSync[key] == state then
			self.pendingSync[key] = nil
		end
		if not safe then
			self.context.Logger:Error("Deferred MDT vehicle indexing raised", {
				VehicleId = vehicle.VehicleId,
				Error = tostring(raised),
			})
			return
		end
		if not ok and reason ~= "INDEX_CANCELLED" then
			self.context.Logger:Warning("Deferred MDT vehicle indexing failed", {
				VehicleId = vehicle.VehicleId,
				Error = reason,
			})
		end
	end)
end

function RecordIndexService:GetPerson(characterId: string): (any?, string?)
	return self:_getRecord(recordKey("Person", characterId))
end

function RecordIndexService:GetPersonFresh(characterId: string): (any?, string?)
	return self:_getRecordFresh(recordKey("Person", characterId))
end

function RecordIndexService:UpdatePerson(
	characterId: string,
	transform: (any?) -> any
): (any?, string?)
	return self:_updateRecord(recordKey("Person", characterId), transform)
end

function RecordIndexService:SearchPeople(
	query: string,
	page: number,
	accessProfile: string,
	includeWarrants: boolean?
): (any?, string?)
	local search = normalise(query)
	local key = indexKey("Person", search)
	if not key then
		return nil, "QUERY_TOO_SHORT"
	end
	local bucket, reason = self.context.Services:Get("DataService"):GetMdtIndex(key)
	if reason then
		return nil, reason
	end
	local matches = {}
	for _, entry in if bucket and type(bucket.Entries) == "table" then bucket.Entries else {} do
		if
			type(entry.SearchText) == "string" and string.find(entry.SearchText, search, 1, true)
		then
			table.insert(matches, entry)
		end
	end
	table.sort(matches, function(a, b)
		return a.FullName < b.FullName
	end)
	local size = self.context.Configuration.MDT.PageSize
	page = math.max(1, math.floor(page))
	local first = (page - 1) * size + 1
	local items = {}
	local total = #matches
	for index = first, math.min(#matches, first + size - 1) do
		local characterId = matches[index].CharacterId
		local warrants
		if includeWarrants == true then
			local _, active, warrantReason =
				self.context.Services:Get("WarrantService"):HasActiveForCharacter(characterId)
			if warrantReason then
				return nil, warrantReason
			end
			warrants = active
		end
		-- On a warrant-cache miss, HasActiveForCharacter refreshed the durable
		-- person record through GetPersonFresh, so this read reuses that cache
		-- entry rather than spending a second DataStore read.
		local record, recordReason = self:GetPerson(characterId)
		if recordReason then
			return nil, recordReason
		end
		if record then
			table.insert(items, personView(record, accessProfile, warrants))
		else
			-- Person projection always writes the durable record before either
			-- name bucket. A successful durable miss therefore proves this row is
			-- dead projection state, not valid retained history. Remove only the
			-- queried bucket row; a store error above never reaches this cleanup.
			local repaired, removalReason, deleted =
				self:_removeStalePersonIndex(key, matches[index])
			if not repaired then
				self.context.Logger:Warning("Person search could not repair stale index", {
					CharacterId = characterId,
					Bucket = key,
					Error = removalReason,
				})
			elseif deleted then
				total = math.max(0, total - 1)
			end
		end
	end
	return { Items = items, Page = page, Total = total }, nil
end

function RecordIndexService:SearchVehicles(
	query: string,
	page: number,
	includeWarrants: boolean?
): (any?, string?)
	local search = compact(query)
	local key = indexKey("Vehicle", search)
	if not key then
		return nil, "QUERY_TOO_SHORT"
	end
	local bucket, reason = self.context.Services:Get("DataService"):GetMdtIndex(key)
	if reason then
		return nil, reason
	end
	local matches = {}
	for _, entry in if bucket and type(bucket.Entries) == "table" then bucket.Entries else {} do
		if
			type(entry.SearchText) == "string" and string.find(entry.SearchText, search, 1, true)
		then
			table.insert(matches, entry)
		end
	end
	table.sort(matches, function(a, b)
		return a.Registration < b.Registration
	end)
	local size = self.context.Configuration.MDT.PageSize
	page = math.max(1, math.floor(page))
	local first = (page - 1) * size + 1
	local items = {}
	local total = #matches
	for index = first, math.min(#matches, first + size - 1) do
		local match = matches[index]
		local keyForRecord = recordKey("Vehicle", match.VehicleId)
		local record, recordReason = self:_getRecord(keyForRecord)
		if recordReason then
			return nil, recordReason
		end
		local currentSearch = if record and type(record.Registration) == "string"
			then compact(record.Registration)
			else ""
		local currentBucket = indexKey("Vehicle", currentSearch)
		local currentMatches = currentBucket == key
			and string.find(currentSearch, search, 1, true) ~= nil
		if record and not currentMatches then
			-- A different server may have changed this registration after our local
			-- record cache was filled. Never delete a global index entry from a cached
			-- mismatch: confirm against the durable record first.
			record, recordReason = self:_getRecordFresh(keyForRecord)
			if recordReason then
				return nil, recordReason
			end
			currentSearch = if record and type(record.Registration) == "string"
				then compact(record.Registration)
				else ""
			currentBucket = indexKey("Vehicle", currentSearch)
			currentMatches = currentBucket == key
				and string.find(currentSearch, search, 1, true) ~= nil
		end
		if not record or not currentMatches then
			-- A registration change writes the new vehicle projection before removing
			-- the old bucket. If that cleanup exhausts its retries, suppress the stale
			-- result and repair only the exact row this search observed. The repair
			-- claims the row and fresh-reads the durable record again before changing
			-- shared index state, closing the confirmation-to-delete race.
			total = math.max(0, total - 1)
			local repaired, removalReason = self:_repairStaleVehicleIndex(key, match)
			if not repaired then
				self.context.Logger:Warning("Vehicle search could not repair stale index", {
					VehicleId = match.VehicleId,
					Error = removalReason,
				})
			end
		elseif record then
			-- Warrant visibility is a separate permission from vehicle search.
			-- Use the dedicated warrant cache/freshness contract rather than deriving
			-- WANTED from the general person-record cache, which may have been filled
			-- before another server created or revoked a warrant.
			local wanted = false
			if includeWarrants == true then
				local hasWarrant, _, warrantReason = self.context.Services
					:Get("WarrantService")
					:HasActiveForCharacter(record.OwnerCharacterId)
				if warrantReason then
					return nil, warrantReason
				end
				wanted = hasWarrant
			end
			table.insert(items, {
				VehicleId = record.VehicleId,
				Registration = record.Registration,
				DefinitionId = record.DefinitionId,
				OwnerCharacterId = record.OwnerCharacterId,
				OwnerName = record.OwnerName,
				Colour = record.Colour,
				Mileage = record.Mileage,
				Condition = record.Condition,
				Insured = record.Insured,
				Taxed = record.Taxed,
				Flags = if wanted then { "WANTED" } else {},
				UpdatedAt = record.UpdatedAt,
			})
		end
	end
	return { Items = items, Page = page, Total = total }, nil
end

function RecordIndexService:_queueReadyPlayer(player: Player)
	-- queued is both the deduplication map and the work set. Keeping no
	-- separate array means departed players leave no stale user IDs behind, and
	-- backlog stays bounded by players that are actually still queued.
	self.queued[player.UserId] = player
end

function RecordIndexService:_waitForSession(player: Player)
	local userId = player.UserId
	self.waiting[userId] = player
	task.spawn(function()
		while self.running and self.waiting[userId] == player and playerIsCurrent(player) do
			local session = self.context.Services:Get("DataService"):GetSession(player)
			if session then
				self.waiting[userId] = nil
				self:_queueReadyPlayer(player)
				return
			end
			-- DataService owns the join-load retry/deadline policy and kicks a player
			-- whose profile cannot be loaded. Do not race it with a shorter local
			-- timeout: a legitimate load can exceed thirty seconds after budget waits
			-- and retry backoff, which previously left that player's records unindexed
			-- for the rest of an otherwise successful server session.
			task.wait(0.25)
		end
	end)
end

function RecordIndexService:_indexPlayer(player: Player)
	if not self.running or not playerIsCurrent(player) then
		return
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return
	end
	for _, character in session.Profile.Characters do
		if not self.running or not playerIsCurrent(player) then
			return
		end
		local ok, reason = self:IndexCharacter(player, character)
		if not ok and reason ~= "INDEX_CANCELLED" then
			self.context.Logger:Warning("MDT background indexing failed", {
				CharacterId = character.CharacterId,
				Error = reason,
			})
		end
		task.wait(self.context.Configuration.MDT.IndexWriteSpacingSeconds)
	end
end

function RecordIndexService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			self:_waitForSession(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local userId = player.UserId
			if self.waiting[userId] == player then
				self.waiting[userId] = nil
			end
			if self.queued[userId] == player then
				self.queued[userId] = nil
			end
			local repairs = {}
			for characterId, repair in self.personIndexRepairs do
				if repair.Player == player then
					table.insert(repairs, { CharacterId = characterId, State = repair })
				end
			end
			for _, repair in repairs do
				self:_dropPersonIndexRepair(repair.CharacterId, repair.State)
			end
			local vehicleRepairs = {}
			for vehicleId, repair in self.vehicleIndexRepairs do
				if repair.Player == player then
					table.insert(vehicleRepairs, { VehicleId = vehicleId, State = repair })
				end
			end
			for _, repair in vehicleRepairs do
				self:_dropVehicleIndexRepair(repair.VehicleId, repair.State)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_waitForSession(player)
	end
	task.spawn(function()
		while self.running do
			local userId, player = next(self.queued)
			if userId then
				self.queued[userId] = nil
				if player and self.running and playerIsCurrent(player) then
					self:_indexPlayer(player)
				end
			else
				task.wait(0.5)
			end
		end
	end)
end

function RecordIndexService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.queued)
	table.clear(self.waiting)
	table.clear(self.cache)
	table.clear(self.pendingSync)
	table.clear(self.personIndexRepairs)
	self.personIndexRepairCount = 0
	table.clear(self.vehicleIndexRepairs)
	self.vehicleIndexRepairCount = 0
	self.cacheCount = 0
	self.cacheSweepCounter = 0
end

return RecordIndexService
