--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProfileSchema = require(ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)

local DataService = { sessions = {}, running = false, connections = {} }
local STORE_NAME = "RoleplayOS_PlayerProfiles_v1"
local COMMUNITY_STORE_NAME = "RoleplayOS_Communities_v1"
local REGISTRATION_STORE_NAME = "RoleplayOS_CustomRegistrations_v1"
local MDT_RECORD_STORE_NAME = "RoleplayOS_MDTRecords_v1"
local MDT_INDEX_STORE_NAME = "RoleplayOS_MDTIndexes_v1"

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
	if not self.mock then
		self.store = DataStoreService:GetDataStore(STORE_NAME)
		self.communityStore = DataStoreService:GetDataStore(COMMUNITY_STORE_NAME)
		self.registrationStore = DataStoreService:GetDataStore(REGISTRATION_STORE_NAME)
		self.mdtRecordStore = DataStoreService:GetDataStore(MDT_RECORD_STORE_NAME)
		self.mdtIndexStore = DataStoreService:GetDataStore(MDT_INDEX_STORE_NAME)
	end
	self.serverId = game.JobId ~= "" and game.JobId or "studio"
end

function DataService:GetMdtRecord(key: string): (any?, string?)
	if self.mock then
		return deepCopy(self.mockMdtRecords[key]), nil
	end
	local ok, result = self:_retry(function()
		return self.mdtRecordStore:GetAsync(key)
	end)
	return if ok then result else nil, if ok then nil else "MDT_RECORD_STORE_UNAVAILABLE"
end

function DataService:UpdateMdtRecord(key: string, transform: (any?) -> any): (any?, string?)
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
	if self.mock then
		return deepCopy(self.mockMdtIndexes[key]), nil
	end
	local ok, result = self:_retry(function()
		return self.mdtIndexStore:GetAsync(key)
	end)
	return if ok then result else nil, if ok then nil else "MDT_INDEX_STORE_UNAVAILABLE"
end

function DataService:UpdateMdtIndex(key: string, transform: (any?) -> any): (any?, string?)
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

function DataService:_retry(operation: () -> any): (boolean, any)
	local lastError
	for attempt = 1, self.context.Configuration.Framework.MaxSaveAttempts do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(math.min(2 ^ (attempt - 1), 8) + math.random() * 0.25)
	end
	return false, lastError
end

function DataService:Load(player: Player): (any?, string?)
	if self.sessions[player.UserId] then
		return nil, "SESSION_ALREADY_LOADED"
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
	local ok, problem = self:_retry(function()
		return self.store:UpdateAsync(tostring(player.UserId), function(stored)
			local profile, migrationError = ProfileSchema.migrate(stored, player.UserId)
			if not profile then
				error(migrationError)
			end
			local lock = profile.AuditMetadata.SessionLock
			if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > now then
				error("PROFILE_SESSION_LOCKED")
			end
			profile.AuditMetadata.SessionLock = {
				ServerId = self.serverId,
				ExpiresAt = now + self.context.Configuration.Framework.SessionLeaseSeconds,
			}
			loaded = profile
			return profile
		end)
	end)
	if not ok then
		self.context.Logger:Error(
			"Profile load failed",
			{ UserId = player.UserId, Error = tostring(problem) }
		)
		return nil, "PROFILE_LOAD_FAILED"
	end
	self.sessions[player.UserId] =
		{ Profile = loaded, Dirty = false, Saving = false, ActiveCharacterId = nil, Revision = 0 }
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
	self.context.Logger:Error(
		"Profile save failed",
		{ UserId = player.UserId, Error = tostring(problem) }
	)
	return false, "PROFILE_SAVE_FAILED"
end

function DataService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			local profile = self:Load(player)
			if not profile then
				player:Kick("Your profile could not be loaded safely. Please rejoin shortly.")
			end
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local ok = self:Save(player, true)
			if not ok then
				self.context.Logger:Warning(
					"Final profile release failed",
					{ UserId = player.UserId }
				)
			end
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
