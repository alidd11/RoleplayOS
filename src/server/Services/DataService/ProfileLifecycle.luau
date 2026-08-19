--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileSchema = require(ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)
local Utils = require(script.Parent.Utils)
local deepCopy = Utils.deepCopy

return function(DataService)
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
		task.spawn(function()
			self:_measure(player, loaded)
		end)
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
				-- Give the session up rather than abandoning it half-released.
				--
				-- This returned without dropping it, which left the player's profile
				-- in self.sessions for the rest of the server's life: they had already
				-- gone, so the autosave loop would never revisit them, and every later
				-- load on this server found the session still present and refused.
				-- Rejoining was impossible until the server itself died.
				--
				-- It is reachable in ordinary conditions. A retry under DataStore
				-- throttling can wait several seconds per attempt, and four attempts
				-- can outlast ShutdownSaveSeconds, which is exactly when a busy server
				-- is saving hardest.
				--
				-- Dropping is the same choice the failed-save path below makes, for
				-- the same reason: holding the profile in memory saves nothing once
				-- the player has left, and the stored lease expires on its own clock.
				-- The in-flight save keeps its own reference and still completes.
				if release then
					self.sessions[player.UserId] = nil
					self.context.Logger:Warning("Released a session whose save was still running", {
						UserId = player.UserId,
					})
				end
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
end
