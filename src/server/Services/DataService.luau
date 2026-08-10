--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProfileSchema = require(ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)

local DataService =
	{ Critical = true, sessions = {}, running = false, connections = {}, loading = {} }
local STORE_NAME = "RoleplayOS_PlayerProfiles_v1"
local COMMUNITY_STORE_NAME = "RoleplayOS_Communities_v1"
local REGISTRATION_STORE_NAME = "RoleplayOS_CustomRegistrations_v1"
local MDT_RECORD_STORE_NAME = "RoleplayOS_MDTRecords_v1"
local MDT_INDEX_STORE_NAME = "RoleplayOS_MDTIndexes_v1"
local SHOULDER_STORE_NAME = "RoleplayOS_ShoulderNumbers_v1"

-- Roblox refuses a key longer than fifty characters and a value larger than four
-- megabytes. Both arrive as an ordinary error from a call this framework already
-- retries, so without an explicit check they look like a transient outage and are
-- retried forever instead of being recognised as a fault that will never clear.
local MAXIMUM_KEY_LENGTH = 50
local MAXIMUM_VALUE_BYTES = 4 * 1024 * 1024

function DataService:_checkKey(key: string, store: string): boolean
	if #key <= MAXIMUM_KEY_LENGTH then
		return true
	end
	self.context.Logger:Error("Data store key exceeds the fifty character limit", {
		Store = store,
		Length = #key,
		Key = string.sub(key, 1, 64),
	})
	return false
end

-- Measures a profile and warns while there is still room to act.
--
-- A profile that passes four megabytes stops saving, and it stops saving
-- silently: every write from then on fails and the player's progress is lost
-- from the last good save onward. That is the worst outcome this service has, so
-- it is reported as a warning long before it becomes one.
function DataService:_measure(player: Player, profile: any)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, profile)
	if not ok or type(encoded) ~= "string" then
		return
	end
	local bytes = #encoded
	local warnAt = self.context.Configuration.Framework.ProfileSizeWarningBytes
		or math.floor(MAXIMUM_VALUE_BYTES * 0.35)
	if bytes < warnAt then
		return
	end
	self.context.Logger:Warning("Profile is approaching the data store size limit", {
		UserId = player.UserId,
		Bytes = bytes,
		LimitBytes = MAXIMUM_VALUE_BYTES,
		PercentOfLimit = math.floor(bytes / MAXIMUM_VALUE_BYTES * 100),
	})
end

local function deepCopy(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return visited[value]
	end
	local copy = {}
	visited[value] = copy
	for key, child in value do
		copy[deepCopy(key, visited)] = deepCopy(child, visited)
	end
	return copy
end

function DataService:Init(context: any)
	self.context = context
	self.mock = RunService:IsStudio() and context.Configuration.Framework.UseMockDataInStudio
	self.mockSharedRecords = {}
	self.mockRegistrations = {}
	self.mockMdtRecords = {}
	self.mockMdtIndexes = {}
	self.mockShoulder = {}
	if not self.mock then
		self.store = DataStoreService:GetDataStore(STORE_NAME)
		self.sharedRecordStore = DataStoreService:GetDataStore(COMMUNITY_STORE_NAME)
		self.registrationStore = DataStoreService:GetDataStore(REGISTRATION_STORE_NAME)
		self.mdtRecordStore = DataStoreService:GetDataStore(MDT_RECORD_STORE_NAME)
		self.mdtIndexStore = DataStoreService:GetDataStore(MDT_INDEX_STORE_NAME)
		self.shoulderStore = DataStoreService:GetDataStore(SHOULDER_STORE_NAME)
	end
	self.serverId = game.JobId ~= "" and game.JobId or "studio"
end

-- Public progression deliberately keeps the original bare UserId key so this
-- release cannot make existing live profiles appear to have been wiped. An
-- official whitelisted world receives its own namespace, even when it is a
-- second place inside the same universe (places in one universe share stores).
-- Teleport data covers reserved same-place servers; PlaceId covers a dedicated
-- whitelisted place entered directly.
function DataService:_profileKey(player: Player): string
	local official = self.context.Configuration.OfficialServers
	local entries = official and official.Entries or {}
	local officialServerId: string? = nil
	local ok, joinData = pcall(player.GetJoinData, player)
	if ok and type(joinData) == "table" and type(joinData.TeleportData) == "table" then
		local supplied = joinData.TeleportData.OfficialServerId
		if type(supplied) == "string" then
			officialServerId = supplied
		end
	end
	if officialServerId then
		local entry = entries[officialServerId]
		if entry and entry.Whitelisted == true then
			return string.format("wl:%s:%d", officialServerId, player.UserId)
		end
	end
	for entryId, entry in entries do
		if
			type(entry) == "table"
			and entry.Whitelisted == true
			and tonumber(entry.PlaceId) == game.PlaceId
		then
			return string.format("wl:%s:%d", tostring(entryId), player.UserId)
		end
	end
	return tostring(player.UserId)
end

-- Secondary player-owned stores (MDT records/indexes, custom registrations and
-- shoulder numbers) must follow the same public/whitelisted boundary as the
-- profile which owns them. Public keeps its historical unprefixed keys; a
-- whitelisted server prefixes every key with the official-server identity.
-- Server-directory data intentionally does not use this scope.
function DataService:_bindDataScope(profileKey: string)
	local scope = string.match(profileKey, "^(wl:[^:]+:)") or ""
	if self.dataScope == nil then
		self.dataScope = scope
	elseif self.dataScope ~= scope then
		self.context.Logger:Error("Mixed persistence scopes detected in one server", {
			ExistingScope = self.dataScope,
			RequestedScope = scope,
		})
	end
end

function DataService:_scopedKey(key: string): string
	return (self.dataScope or "") .. key
end

function DataService:GetMdtRecord(key: string): (any?, string?)
	key = self:_scopedKey(key)
	if not self:_checkKey(key, "MdtRecords") then
		return nil, "MDT_RECORD_STORE_UNAVAILABLE"
	end
	if self.mock then
		return deepCopy(self.mockMdtRecords[key]), nil
	end
	local ok, result = self:_retry(function()
		return self.mdtRecordStore:GetAsync(key)
	end)
	return if ok then result else nil, if ok then nil else "MDT_RECORD_STORE_UNAVAILABLE"
end

function DataService:UpdateMdtRecord(key: string, transform: (any?) -> any): (any?, string?)
	key = self:_scopedKey(key)
	if not self:_checkKey(key, "MdtRecords") then
		return nil, "MDT_RECORD_STORE_UNAVAILABLE"
	end
	if self.mock then
		local updated = transform(deepCopy(self.mockMdtRecords[key]))
		self.mockMdtRecords[key] = deepCopy(updated)
		return deepCopy(updated), nil
	end
	local updated
	local ok = self:_retry(function()
		return self.mdtRecordStore:UpdateAsync(key, function(stored)
			updated = transform(stored)
			return updated
		end)
	end)
	return if ok then updated else nil, if ok then nil else "MDT_RECORD_STORE_UNAVAILABLE"
end

function DataService:GetMdtIndex(key: string): (any?, string?)
	key = self:_scopedKey(key)
	if not self:_checkKey(key, "MdtIndexes") then
		return nil, "MDT_INDEX_STORE_UNAVAILABLE"
	end
	if self.mock then
		return deepCopy(self.mockMdtIndexes[key]), nil
	end
	local ok, result = self:_retry(function()
		return self.mdtIndexStore:GetAsync(key)
	end)
	return if ok then result else nil, if ok then nil else "MDT_INDEX_STORE_UNAVAILABLE"
end

function DataService:UpdateMdtIndex(key: string, transform: (any?) -> any): (any?, string?)
	key = self:_scopedKey(key)
	if not self:_checkKey(key, "MdtIndexes") then
		return nil, "MDT_INDEX_STORE_UNAVAILABLE"
	end
	if self.mock then
		local updated = transform(deepCopy(self.mockMdtIndexes[key]))
		self.mockMdtIndexes[key] = deepCopy(updated)
		return deepCopy(updated), nil
	end
	local updated
	local ok = self:_retry(function()
		return self.mdtIndexStore:UpdateAsync(key, function(stored)
			updated = transform(stored)
			return updated
		end)
	end)
	return if ok then updated else nil, if ok then nil else "MDT_INDEX_STORE_UNAVAILABLE"
end

-- Claims the next shoulder number for a department and records who holds it.
--
-- The counter and the holder record are two keys, and only the counter is
-- allocated under UpdateAsync, so a server that dies between the two burns a
-- number without assigning it. That is the safe direction to fail: a gap in the
-- sequence is invisible, whereas issuing the same number twice would put two
-- officers on air as the same unit. Numbers are plentiful and never reissued.
function DataService:AllocateShoulderNumber(
	departmentId: string,
	userId: number,
	start: number
): (number?, string?)
	local counterKey = self:_scopedKey("counter:" .. departmentId)
	local holderKey = self:_scopedKey(departmentId .. ":" .. tostring(start))
	local issued: number? = nil
	if self.mock then
		local current = self.mockShoulder[counterKey]
		issued = if type(current) == "number" then current + 1 else start
		self.mockShoulder[counterKey] = issued
		holderKey = self:_scopedKey(departmentId .. ":" .. tostring(issued))
		self.mockShoulder[holderKey] = { UserId = userId, AssignedAt = os.time() }
		return issued, nil
	end
	local ok = self:_retry(function()
		return self.shoulderStore:UpdateAsync(counterKey, function(stored)
			issued = if type(stored) == "number" then stored + 1 else start
			return issued
		end)
	end)
	if not ok or not issued then
		return nil, "SHOULDER_NUMBER_STORE_UNAVAILABLE"
	end
	holderKey = self:_scopedKey(departmentId .. ":" .. tostring(issued))
	-- The holder record is what the staff export reads. Losing it costs the
	-- reconciliation view, not the allocation, so a failure here is warned about
	-- rather than surfaced as a refusal to go on duty.
	local recorded = self:_retry(function()
		return self.shoulderStore:SetAsync(holderKey, { UserId = userId, AssignedAt = os.time() })
	end)
	if not recorded then
		self.context.Logger:Warning("Shoulder number holder record failed", {
			DepartmentId = departmentId,
			Number = issued,
			UserId = userId,
		})
	end
	return issued, nil
end

function DataService:GetShoulderNumberHolder(departmentId: string, number: number): (any?, string?)
	local holderKey = self:_scopedKey(departmentId .. ":" .. tostring(number))
	if self.mock then
		return deepCopy(self.mockShoulder[holderKey]), nil
	end
	local ok, result = self:_retry(function()
		return self.shoulderStore:GetAsync(holderKey)
	end)
	return if ok then result else nil, if ok then nil else "SHOULDER_NUMBER_STORE_UNAVAILABLE"
end

function DataService:ReserveCustomRegistration(
	registration: string,
	userId: number,
	vehicleId: string
): (boolean, string?)
	local registrationKey = self:_scopedKey(registration)
	if self.mock then
		local existing = self.mockRegistrations[registrationKey]
		if existing and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId) then
			return false, "REGISTRATION_ALREADY_USED"
		end
		self.mockRegistrations[registrationKey] = { UserId = userId, VehicleId = vehicleId }
		return true, nil
	end
	local reserved = false
	local ok = self:_retry(function()
		return self.registrationStore:UpdateAsync(registrationKey, function(existing)
			if existing and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId) then
				return existing
			end
			reserved = true
			return { UserId = userId, VehicleId = vehicleId, UpdatedAt = os.time() }
		end)
	end)
	if not ok then
		return false, "REGISTRATION_STORE_UNAVAILABLE"
	end
	return reserved, if reserved then nil else "REGISTRATION_ALREADY_USED"
end

function DataService:ReleaseCustomRegistration(
	registration: string,
	userId: number,
	vehicleId: string
)
	local registrationKey = self:_scopedKey(registration)
	if self.mock then
		local existing = self.mockRegistrations[registrationKey]
		if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
			self.mockRegistrations[registrationKey] = nil
		end
		return
	end
	task.spawn(function()
		self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
					return nil
				end
				return existing
			end)
		end)
	end)
end

function DataService:GetSharedRecord(recordId: string): (any?, string?)
	if self.mock then
		return self.mockSharedRecords[recordId], nil
	end
	local ok, result = self:_retry(function()
		return self.sharedRecordStore:GetAsync(recordId)
	end)
	if not ok then
		self.context.Logger:Error("Shared record load failed", { RecordId = recordId })
		return nil, "SHARED_RECORD_LOAD_FAILED"
	end
	return result, nil
end

function DataService:UpdateSharedRecord(recordId: string, transform: (any?) -> any): (any?, string?)
	if self.mock then
		local updated = transform(self.mockSharedRecords[recordId])
		self.mockSharedRecords[recordId] = updated
		return updated, nil
	end
	local updated
	local ok = self:_retry(function()
		return self.sharedRecordStore:UpdateAsync(recordId, function(stored)
			updated = transform(stored)
			return updated
		end)
	end)
	if not ok then
		self.context.Logger:Error("Shared record update failed", { RecordId = recordId })
		return nil, "SHARED_RECORD_UPDATE_FAILED"
	end
	return updated, nil
end

-- Retries transient DataStore failures with a backoff. `final` marks an error
-- as settled: retrying it cannot change the answer, so the backoff is skipped
-- and the caller is told at once. Without it a held session lease was retried
-- like a network fault, and since a lease clears on a clock rather than on
-- contention, that spent the full backoff to arrive at the same refusal.
-- Waits for DataStore request budget before spending an attempt.
--
-- Roblox meters DataStore calls per server, at roughly sixty plus ten per
-- player per minute, and a call made with no budget left is rejected. Without
-- this, a rejection was indistinguishable from a network fault: it consumed one
-- of the few retry attempts, backed off blindly, and could exhaust the attempts
-- while the budget was busy recovering. The write was then reported as failed
-- and the player's progress since their last save was gone.
--
-- The shutdown path is where this bites hardest, because that is every profile
-- in the server writing at once, which is exactly when the budget runs out and
-- exactly when there is no later save to put it right.
--
-- Waiting is bounded. Past the deadline the attempt is made anyway, so a
-- misread budget delays a write rather than dropping it.
function DataService:_awaitBudget(requestType: Enum.DataStoreRequestType)
	-- Twelve seconds normally, two while closing: Roblox allows about thirty
	-- seconds to shut down, and waiting is only worth doing while there is still
	-- time to use the budget once it arrives.
	-- Six, not twelve. The network layer gives a handler eight seconds, so a
	-- twelve second wait guaranteed that any request reaching it was reported to
	-- the player as a timeout while the work carried on behind them.
	local deadline = os.clock() + (if self.closing then 2 else 6)
	local waited = false
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		if os.clock() >= deadline then
			self.context.Logger:Warning("DataStore budget did not recover; writing anyway", {
				RequestType = requestType.Name,
			})
			return
		end
		waited = true
		task.wait(0.5)
	end
	if waited then
		-- Logged, because throttling that nobody sees is throttling nobody fixes,
		-- and the fix is usually saving less often rather than saving harder.
		self.context.Logger:Warning("Waited for DataStore budget", {
			RequestType = requestType.Name,
		})
	end
end

-- Exposes the current budget without allowing monitoring services to cross the
-- persistent-storage boundary. DataService remains the only service that talks
-- to Roblox DataStore APIs directly.
function DataService:GetRequestBudget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

-- `requestType` defaults to UpdateAsync because every write path uses it, and a
-- write is where exhausted budget costs data rather than costing a reload.
function DataService:_retry(
	operation: () -> any,
	final: ((any) -> boolean)?,
	requestType: Enum.DataStoreRequestType?
): (boolean, any)
	local lastError
	local budgetType = requestType or Enum.DataStoreRequestType.UpdateAsync
	for attempt = 1, self.context.Configuration.Framework.MaxSaveAttempts do
		self:_awaitBudget(budgetType)
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		if final and final(result) then
			return false, result
		end
		task.wait(math.min(2 ^ (attempt - 1), 8) + math.random() * 0.25)
	end
	return false, lastError
end

function DataService:Load(player: Player, waited: boolean?): (any?, string?)
	-- Loading is idempotent. Two paths call it for the same player: the join
	-- signal, and the sweep over everyone already present when this service
	-- starts. Whoever joins a server first satisfies both, so both ran, and the
	-- loser found the winner's session already in place. That was reported as a
	-- failure and the join handler kicked for it, which meant the first player
	-- into a fresh server was liable to be kicked by their own successful load.
	--
	-- A session that exists is a profile that loaded. That is the successful
	-- outcome, not a conflict, so it is returned as one.
	local live = self.sessions[player.UserId]
	if live and not live.Releasing then
		return live.Profile, nil
	end
	-- A load already in flight is waited on rather than duplicated, so the two
	-- callers cannot both open an UpdateAsync on one profile.
	if self.loading[player.UserId] then
		local deadline = os.clock()
			+ (self.context.Configuration.Framework.SessionHandoverSeconds or 10)
		while self.loading[player.UserId] and os.clock() < deadline do
			if not player:IsDescendantOf(Players) then
				return nil, "PLAYER_LEFT"
			end
			task.wait(0.1)
		end
		local settled = self.sessions[player.UserId]
		if settled and not settled.Releasing then
			return settled.Profile, nil
		end
	end
	-- A rejoin routinely outruns the departure it follows. Leaving defers a
	-- final save, that save is a DataStore round trip, and the session is only
	-- dropped once it returns. Roblox frequently puts a returning player back on
	-- the same server, so arriving inside that window found the outgoing session
	-- still present and refused the load, which the join handler turned into a
	-- kick. Leaving and immediately rejoining was therefore close to a reliable
	-- way to be kicked.
	--
	-- The outgoing save must still finish first, so this waits for the handover
	-- rather than discarding it: loading over a save in flight would race two
	-- writers on one profile.
	if self.sessions[player.UserId] then
		local deadline = os.clock()
			+ (self.context.Configuration.Framework.SessionHandoverSeconds or 10)
		while self.sessions[player.UserId] and os.clock() < deadline do
			if not player:IsDescendantOf(Players) then
				return nil, "PLAYER_LEFT"
			end
			task.wait(0.1)
		end
		if self.sessions[player.UserId] then
			self.context.Logger:Warning("Previous session did not release in time", {
				UserId = player.UserId,
			})
			return nil, "SESSION_ALREADY_LOADED"
		end
	end
	local profileKey = self:_profileKey(player)
	self:_bindDataScope(profileKey)
	if self.mock then
		local profile = ProfileSchema.default(player.UserId)
		if self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio then
			profile.DutyProfiles.StudioPolice = {
				ProfileId = "StudioPolice",
				DepartmentId = "Police",
				Rank = 1,
				QualificationIds = {},
				Callsign = "STUDIO-1",
			}
			profile.DutyProfiles.StudioControl = {
				ProfileId = "StudioControl",
				DepartmentId = "Control",
				Rank = 1,
				QualificationIds = {},
				Callsign = "CONTROL-1",
			}
			table.insert(profile.Applications, {
				ApplicationId = "StudioPoliceAccess",
				FormId = "Police",
				Status = "Accepted",
				Answers = {},
				SubmittedAt = os.time(),
				UpdatedAt = os.time(),
			})
			table.insert(profile.Applications, {
				ApplicationId = "StudioControlAccess",
				FormId = "Control",
				Status = "Accepted",
				Answers = {},
				SubmittedAt = os.time(),
				UpdatedAt = os.time(),
			})
		end
		self.sessions[player.UserId] = {
			Profile = profile,
			Dirty = false,
			Saving = false,
			ActiveCharacterId = nil,
			Mock = true,
			Revision = 0,
		}
		self.context.Logger:Info("Loaded in-memory Studio profile", { UserId = player.UserId })
		return profile, nil
	end
	local now = os.time()
	local loaded
	-- Recorded so a lease held by a server that has gone away can be waited out
	-- rather than treated as an unrecoverable failure.
	local lockedUntil: number? = nil
	-- Set when the stored profile could not be read at all, so it can be written
	-- aside after the transform. Nothing may yield inside an UpdateAsync
	-- transform, so the backup cannot be written from in there.
	local quarantined: any = nil
	local quarantineReason: string? = nil
	-- Claimed for the duration of the store call so a second caller waits on this
	-- one rather than opening its own. Cleared on every exit below, including the
	-- failures, or a player who failed once could never be loaded again.
	self.loading[player.UserId] = true
	local ok, problem = self:_retry(function()
		return self.store:UpdateAsync(profileKey, function(stored)
			local profile, migrationError = ProfileSchema.migrate(stored, player.UserId)
			if not profile then
				-- A profile that cannot be read is set aside and replaced, not
				-- thrown on. Raising here is indistinguishable from an outage: it
				-- is retried, then kicked, on every join, forever. A schema
				-- rollback would have locked out everybody who played the newer
				-- build with no way back.
				--
				-- The unreadable original is kept, so this loses nothing that can
				-- be recovered by hand later.
				quarantined = stored
				quarantineReason = migrationError
				profile = ProfileSchema.default(player.UserId)
			end
			local lock = profile.AuditMetadata.SessionLock
			if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > os.time() then
				lockedUntil = lock.ExpiresAt
				error("PROFILE_SESSION_LOCKED")
			end
			lockedUntil = nil
			profile.AuditMetadata.SessionLock = {
				ServerId = self.serverId,
				ExpiresAt = now + self.context.Configuration.Framework.SessionLeaseSeconds,
			}
			loaded = profile
			return profile
		end)
	end, function(failure)
		return string.find(tostring(failure), "PROFILE_SESSION_LOCKED", 1, true) ~= nil
	end)
	if not ok and lockedUntil and not waited then
		-- A lease is held by another server. Retrying immediately cannot succeed,
		-- since it expires on a clock rather than on contention, so wait it out
		-- when the remaining time is short. Rejoining straight after leaving is
		-- the common case, and kicking the player for it reads as a fault.
		--
		-- Exactly one wait: a server that is still alive keeps refreshing its
		-- lease, so retrying whenever time remains would never terminate and the
		-- player would hang rather than be told what happened.
		--
		-- The wait is capped well below the lease. It happens inside PlayerAdded,
		-- before the player has a profile or a character, and a join that takes
		-- too long is abandoned by Roblox and shown to the player as a connection
		-- error. Waiting out a full lease therefore replaced a clear message with
		-- a silent disconnection, which is the worse of the two by far.
		local remaining = lockedUntil - os.time()
		local ceiling = self.context.Configuration.Framework.MaximumLeaseWaitSeconds or 12
		if remaining > 0 and remaining <= ceiling then
			self.context.Logger:Warning("Waiting for a held profile lease", {
				UserId = player.UserId,
				Seconds = remaining,
			})
			task.wait(remaining + 1)
			self.loading[player.UserId] = nil
			if not player:IsDescendantOf(Players) then
				return nil, "PLAYER_LEFT"
			end
			return self:Load(player, true)
		end
		if remaining > 0 then
			self.context.Logger:Warning("Profile lease held for longer than a join can wait", {
				UserId = player.UserId,
				Seconds = remaining,
			})
			self.loading[player.UserId] = nil
			return nil, "PROFILE_SESSION_LOCKED:" .. tostring(math.ceil(remaining))
		end
	end
	if not ok then
		self.context.Logger:Error(
			"Profile load failed",
			{ UserId = player.UserId, Error = tostring(problem) }
		)
		-- The underlying reason travels with the code. A kick that says only that
		-- something went wrong forces whoever is looking into it to reach the
		-- server console, which nobody can do from a phone and nobody does at all
		-- once they have simply left.
		self.loading[player.UserId] = nil
		return nil, "PROFILE_LOAD_FAILED: " .. string.sub(tostring(problem), 1, 180)
	end
	self.sessions[player.UserId] = {
		Profile = loaded,
		Dirty = false,
		Saving = false,
		ActiveCharacterId = nil,
		Revision = 0,
		DataKey = profileKey,
	}
	self.loading[player.UserId] = nil
	if quarantined ~= nil then
		self.context.Logger:Error("Profile could not be read and was set aside", {
			UserId = player.UserId,
			Reason = quarantineReason,
		})
		-- Written outside the transform and after the load has succeeded, so a
		-- failure to keep the backup costs the record rather than the session.
		local key = "quarantine:" .. profileKey .. ":" .. tostring(os.time())
		if self:_checkKey(key, "Profiles") then
			self:_retry(function()
				return self.store:SetAsync(key, {
					UserId = player.UserId,
					Reason = quarantineReason,
					StoredAt = os.time(),
					Profile = quarantined,
				})
			end)
		end
	end
	-- Measured once per join rather than on every save, which would encode the
	-- whole profile every forty seconds for a number that barely moves.
	self:_measure(player, loaded)
	return loaded, nil
end

function DataService:GetSession(player: Player): any?
	return self.sessions[player.UserId]
end

function DataService:MarkDirty(player: Player)
	local session = self.sessions[player.UserId]
	if session then
		session.Dirty = true
		session.Revision = (session.Revision or 0) + 1
	end
end

function DataService:Save(player: Player, release: boolean?): (boolean, string?)
	local session = self.sessions[player.UserId]
	if not session then
		return false, "NO_SESSION"
	end
	if session.Mock then
		session.Dirty = false
		if release then
			self.sessions[player.UserId] = nil
		end
		return true, nil
	end
	if session.Saving then
		if not release then
			return false, "SAVE_IN_PROGRESS"
		end
		local deadline = os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds
		while session.Saving and os.clock() < deadline do
			task.wait(0.05)
		end
		if session.Saving then
			return false, "SAVE_IN_PROGRESS"
		end
	end
	session.Saving = true
	-- Marks the session as on its way out, so a load arriving now waits for the
	-- handover instead of adopting a profile that is about to be dropped.
	if release then
		session.Releasing = true
	end
	local revision = session.Revision or 0
	local snapshot = deepCopy(session.Profile)
	local now = os.time()
	local profileKey = session.DataKey or self:_profileKey(player)
	local ok, problem = self:_retry(function()
		self.store:UpdateAsync(profileKey, function(stored)
			local lock = stored and stored.AuditMetadata and stored.AuditMetadata.SessionLock
			if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > now then
				error("SESSION_OWNERSHIP_LOST")
			end
			-- Written as a statement, not as `release and nil or {...}`.
			--
			-- That idiom cannot express "nil when true": `release and nil` is nil,
			-- and `nil or {...}` is the table, so the release branch was
			-- unreachable and every release stamped a fresh lease instead of
			-- clearing it. A player leaving therefore locked their own profile for
			-- the full lease on the way out, and was refused by every other server
			-- until it expired.
			if release then
				snapshot.AuditMetadata.SessionLock = nil
			else
				snapshot.AuditMetadata.SessionLock = {
					ServerId = self.serverId,
					ExpiresAt = now + self.context.Configuration.Framework.SessionLeaseSeconds,
				}
			end
			return snapshot
		end)
	end)
	session.Saving = false
	if ok then
		if (session.Revision or 0) == revision then
			session.Dirty = false
		end
		if release then
			self.sessions[player.UserId] = nil
		end
		return true, nil
	end
	-- A release that failed still drops the session. The player has gone, so
	-- holding their profile in memory saves nothing and blocks their return:
	-- every later load on this server would find the session still present and
	-- refuse, locking them out until the server itself died. The stored lease
	-- expires on its own clock, which is what that mechanism is for.
	if release then
		self.sessions[player.UserId] = nil
	end
	self.context.Logger:Error(
		"Profile save failed",
		{ UserId = player.UserId, Error = tostring(problem), Released = release == true }
	)
	return false, "PROFILE_SAVE_FAILED"
end

function DataService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			-- Tried several times before giving up. A data store failure is very
			-- often transient, and kicking on the first one turns a momentary
			-- Roblox wobble into a player who cannot get in and does not come
			-- back. A held lease is not retried here: that clears on a clock and
			-- is reported with the number of seconds instead.
			local attempts = self.context.Configuration.Framework.JoinLoadAttempts or 3
			local profile, reason
			for attempt = 1, attempts do
				profile, reason = self:Load(player)
				if profile then
					return
				end
				if not player:IsDescendantOf(Players) then
					return
				end
				local settled = reason == nil
					or string.find(tostring(reason), "PROFILE_SESSION_LOCKED", 1, true) ~= nil
					or reason == "PLAYER_LEFT"
				if settled or attempt == attempts then
					break
				end
				self.context.Logger:Warning("Retrying a failed profile load", {
					UserId = player.UserId,
					Attempt = attempt,
					Error = tostring(reason),
				})
				task.wait(2 ^ (attempt - 1))
				if not player:IsDescendantOf(Players) then
					return
				end
			end
			if profile then
				return
			end
			-- A held lease is a wait, not a fault, and saying so with the number of
			-- seconds turns a rejoin from guesswork into something the player can
			-- simply do. Anything else keeps the general message, since the cause
			-- is ours rather than theirs and a number would be invented.
			local seconds =
				tonumber(string.match(tostring(reason), "^PROFILE_SESSION_LOCKED:(%d+)$"))
			if seconds then
				player:Kick(
					string.format(
						"Your previous session is still being saved. Please rejoin in about %d seconds.",
						seconds
					)
				)
				return
			end
			player:Kick("Your profile could not be loaded safely. Please rejoin shortly.")
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			-- A load abandoned by the player leaving must not leave its claim
			-- behind, or their next join waits the full handover on a load that
			-- will never finish.
			self.loading[player.UserId] = nil
			-- Defer the final save so gameplay services can commit disconnect consequences
			-- (for example, leaving while restrained) before the session lease is released.
			task.defer(function()
				local ok = self:Save(player, true)
				if not ok then
					self.context.Logger:Warning(
						"Final profile release failed",
						{ UserId = player.UserId }
					)
				end
			end)
		end)
	)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Load(player)
		end)
	end
	task.spawn(function()
		while self.running do
			task.wait(
				math.min(
					self.context.Configuration.Framework.AutosaveSeconds,
					math.max(
						30,
						math.floor(self.context.Configuration.Framework.SessionLeaseSeconds / 3)
					)
				)
			)
			for _, player in Players:GetPlayers() do
				task.spawn(function()
					self:Save(player, false)
				end)
			end
		end
	end)
end

function DataService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	-- Shortens the budget wait for the rest of this shutdown.
	--
	-- Roblox allows about thirty seconds to close. Waiting twelve of them for
	-- budget, per profile, spends the window that the writes themselves need.
	self.closing = true

	local pending = 0
	local unsaved: { string } = {}
	for _, player in Players:GetPlayers() do
		-- PlayerRemoving can release the session immediately before BindToClose
		-- reaches this loop. That profile is already safely finished; trying to
		-- save it again returns NO_SESSION and previously produced a false data-loss
		-- alarm on every clean Studio shutdown.
		if not self.sessions[player.UserId] then
			continue
		end
		pending += 1
		task.spawn(function()
			-- Wrapped, because a save that throws used to skip the decrement
			-- below and leave `pending` above zero for ever. The loop then waited
			-- out the entire shutdown window for a save that had already failed,
			-- spending the time the remaining profiles needed.
			-- Both outcomes are recorded, because Save reports a failed write by
			-- returning false rather than by raising. Only the raise was being
			-- caught, so the list this builds was always empty and a server could
			-- shut down having saved nobody while logging nothing. The one record
			-- that can answer "I lost my money" did not exist.
			local ok, saved, reason = pcall(function()
				return self:Save(player, true)
			end)
			if not ok then
				table.insert(
					unsaved,
					string.format("%s (%d): raised %s", player.Name, player.UserId, tostring(saved))
				)
			elseif not saved then
				table.insert(
					unsaved,
					string.format("%s (%d): %s", player.Name, player.UserId, tostring(reason))
				)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end
	if pending > 0 or #unsaved > 0 then
		-- Named, not counted.
		--
		-- Somebody whose profile did not save has lost whatever they earned since
		-- their last autosave, and they will say so. A count cannot be checked
		-- against that claim; a list can, and it is the difference between
		-- answering them and guessing.
		self.context.Logger:Error("Profiles may not have saved at shutdown", {
			StillWriting = pending,
			Failed = unsaved,
		})
	end
end

return DataService
