--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProfileSchema = require(ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)

local DataService = { sessions = {}, running = false }
local STORE_NAME = "RoleplayOS_PlayerProfiles_v1"
local COMMUNITY_STORE_NAME = "RoleplayOS_Communities_v1"

function DataService:Init(context: any)
	self.context = context
	self.store = DataStoreService:GetDataStore(STORE_NAME)
	self.communityStore = DataStoreService:GetDataStore(COMMUNITY_STORE_NAME)
	self.serverId = game.JobId ~= "" and game.JobId or "studio"
end

function DataService:GetCommunity(communityId: string): (any?, string?)
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
	if RunService:IsStudio() and self.context.Configuration.Framework.UseMockDataInStudio then
		local profile = ProfileSchema.default(player.UserId)
		self.sessions[player.UserId] = {
			Profile = profile,
			Dirty = false,
			Saving = false,
			ActiveCharacterId = nil,
			Mock = true,
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
		{ Profile = loaded, Dirty = false, Saving = false, ActiveCharacterId = nil }
	return loaded, nil
end

function DataService:GetSession(player: Player): any?
	return self.sessions[player.UserId]
end

function DataService:MarkDirty(player: Player)
	local session = self.sessions[player.UserId]
	if session then
		session.Dirty = true
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
		return false, "SAVE_IN_PROGRESS"
	end
	if not session.Dirty and not release then
		return true, nil
	end
	session.Saving = true
	local snapshot = session.Profile
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
		session.Dirty = false
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
	Players.PlayerAdded:Connect(function(player)
		local profile = self:Load(player)
		if not profile then
			player:Kick("Your profile could not be loaded safely. Please rejoin shortly.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Save(player, true)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Load(player)
		end)
	end
	task.spawn(function()
		while self.running do
			task.wait(self.context.Configuration.Framework.AutosaveSeconds)
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
	for _, player in Players:GetPlayers() do
		self:Save(player, true)
	end
end

return DataService
