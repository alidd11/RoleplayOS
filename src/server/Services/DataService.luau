--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProfileSchema = require(ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)

local DataService = { sessions = {}, running = false, connections = {}, loading = {} }
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
	self.mockCommunities = {}
	self.mockRegistrations = {}
	self.mockMdtRecords = {}
	self.mockMdtIndexes = {}
	self.mockShoulder = {}
	if not self.mock then
		self.store = DataStoreService:GetDataStore(STORE_NAME)
		self.communityStore = DataStoreService:GetDataStore(COMMUNITY_STORE_NAME)
		self.registrationStore = DataStoreService:GetDataStore(REGISTRATION_STORE_NAME)
		self.mdtRecordStore = DataStoreService:GetDataStore(MDT_RECORD_STORE_NAME)
		self.mdtIndexStore = DataStoreService:GetDataStore(MDT_INDEX_STORE_NAME)
		self.shoulderStore = DataStoreService:GetDataStore(SHOULDER_STORE_NAME)
	end
	self.serverId = game.JobId ~= "" and game.JobId or "studio"
end

function DataService:GetMdtRecord(key: string): (any?, string?)
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
	local counterKey = "counter:" .. departmentId
	local issued: number? = nil
	if self.mock then
		local current = self.mockShoulder[counterKey]
		issued = if type(current) == "number" then current + 1 else start
		self.mockShoulder[counterKey] = issued
		self.mockShoulder[departmentId .. ":" .. tostring(issued)] =
			{ UserId = userId, AssignedAt = os.time() }
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
	-- The holder record is what the staff export reads. Losing it costs the
	-- reconciliation view, not the allocation, so a failure here is warned about
	-- rather than surfaced as a refusal to go on duty.
	local recorded = self:_retry(function()
		return self.shoulderStore:SetAsync(
			departmentId .. ":" .. tostring(issued),
			{ UserId = userId, AssignedAt = os.time() }
		)
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
	if self.mock then
		return deepCopy(self.mockShoulder[departmentId .. ":" .. tostring(number)]), nil
	end
	local ok, result = self:_retry(function()
		return self.shoulderStore:GetAsync(departmentId .. ":" .. tostring(number))
	end)
	return if ok then result else nil, if ok then nil else "SHOULDER_NUMBER_STORE_UNAVAILABLE"
end

function DataService:ReserveCustomRegistration(
	registration: string,
	userId: number,
	vehicleId: string
): (boolean, string?)
	if self.mock then
		local existing = self.mockRegistrations[registration]
		if existing and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId) then
			return false, "REGISTRATION_ALREADY_USED"
		end
		self.mockRegistrations[registration] = { UserId = userId, VehicleId = vehicleId }
		return true, nil
	end
	local reserved = false
	local ok = self:_retry(function()
		return self.registrationStore:UpdateAsync(registration, function(existing)
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
	if self.mock then
		local existing = self.mockRegistrations[registration]
		if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
			self.mockRegistrations[registration] = nil
		end
		return
	end
	task.spawn(function()
		self:_retry(function()
			return self.registrationStore:UpdateAsync(registration, function(existing)
				if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
					return nil
				end
				return existing
			end)
		end)
	end)
end

function DataService:GetCommunity(communityId: string): (any?, string?)
	if self.mock then
		return self.mockCommunities[communityId], nil
	end
	local ok, result = self:_retry(function()
		return self.communityStore:GetAsync(communityId)
	end)
	if not ok then
		self.context.Logger:Error("Community load failed", { CommunityId = communityId })
		return nil, "COMMUNITY_LOAD_FAILED"
	end
	return result, nil
end

function DataService:UpdateCommunity(communityId: string, transform: (any?) -> any): (any?, string?)
	if self.mock then
		local updated = transform(self.mockCommunities[communityId])
		self.mockCommunities[communityId] = updated
		return updated, nil
	end
	local updated
	local ok = self:_retry(function()
		return self.communityStore:UpdateAsync(communityId, function(stored)
			updated = transform(stored)
			return updated
		end)
	end)
	if not ok then
		self.context.Logger:Error("Community update failed", { CommunityId = communityId })
		return nil, "COMMUNITY_UPDATE_FAILED"
	end
	return updated, nil
end

-- Retries transient DataStore failures with a backoff. `final` marks an error
-- as settled: retrying it cannot change the answer, so the backoff is skipped
-- and the caller is told at once. Without it a held session lease was retried
-- like a network fault, and since a lease clears on a clock rather than on
-- contention, that spent the full backoff to arrive at the same refusal.
function DataService:_retry(operation: () -> any, final: ((any) -> boolean)?): (boolean, any)
	local lastError
	for attempt = 1, self.context.Configuration.Framework.MaxSaveAttempts do
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
	-- Claimed for the duration of the store call so a second caller waits on this
	-- one rather than opening its own. Cleared on every exit below, including the
	-- failures, or a player who failed once could never be loaded again.
	self.loading[player.UserId] = true
	local ok, problem = self:_retry(function()
		return self.store:UpdateAsync(tostring(player.UserId), function(stored)
			local profile, migrationError = ProfileSchema.migrate(stored, player.UserId)
			if not profile then
				error(migrationError)
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
	self.sessions[player.UserId] =
		{ Profile = loaded, Dirty = false, Saving = false, ActiveCharacterId = nil, Revision = 0 }
	self.loading[player.UserId] = nil
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
	local ok, problem = self:_retry(function()
		self.store:UpdateAsync(tostring(player.UserId), function(stored)
			local lock = stored and stored.AuditMetadata and stored.AuditMetadata.SessionLock
			if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > now then
				error("SESSION_OWNERSHIP_LOST")
			end
			snapshot.AuditMetadata.SessionLock = release and nil
				or {
					ServerId = self.serverId,
					ExpiresAt = now + self.context.Configuration.Framework.SessionLeaseSeconds,
				}
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
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			self:Save(player, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end
	if pending > 0 then
		self.context.Logger:Warning("Shutdown save deadline reached", {
			PendingProfiles = pending,
		})
	end
end

return DataService
