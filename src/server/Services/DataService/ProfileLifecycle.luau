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
		if self.closing or not self.running then
			return nil, "SERVICE_SHUTTING_DOWN"
		end
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
		if live and live.Player == player and not live.Releasing then
			return live.Profile, nil
		end
		-- A load already in flight is waited on rather than duplicated. The claim
		-- belongs to one exact Player instance so a leave/rejoin cannot clear the
		-- old slot and start a second UpdateAsync while the first one is still
		-- capable of acquiring or publishing the same profile.
		local existingLoad = self.loading[player.UserId]
		if existingLoad then
			local deadline = os.clock()
				+ (self.context.Configuration.Framework.SessionHandoverSeconds or 10)
			while self.loading[player.UserId] == existingLoad and os.clock() < deadline do
				if self.closing or not self.running then
					return nil, "SERVICE_SHUTTING_DOWN"
				end
				if not player:IsDescendantOf(Players) then
					return nil, "PLAYER_LEFT"
				end
				task.wait(0.1)
			end
			if self.loading[player.UserId] then
				return nil, "PROFILE_LOAD_IN_PROGRESS"
			end
			local settled = self.sessions[player.UserId]
			if settled and settled.Player == player and not settled.Releasing then
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
				if self.closing or not self.running then
					return nil, "SERVICE_SHUTTING_DOWN"
				end
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
		if not self:_checkKey(profileKey, "Profiles") then
			return nil, "PROFILE_KEY_INVALID"
		end
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
			if self.closing or not self.running then
				return nil, "SERVICE_SHUTTING_DOWN"
			end
			if not player:IsDescendantOf(Players) then
				return nil, "PLAYER_LEFT"
			end
			self.sessions[player.UserId] = {
				Player = player,
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
		-- one rather than opening its own. The token is tied to the exact Player
		-- instance: PlayerRemoving marks only that token cancelled, and a rejoin
		-- cannot replace it until the old request has fully stopped touching storage.
		local loadToken = { Player = player, Cancelled = false }
		self.loading[player.UserId] = loadToken
		local function finishLoading()
			if self.loading[player.UserId] == loadToken then
				self.loading[player.UserId] = nil
			end
		end
		local ok, problem = self:_retry(function()
			if loadToken.Cancelled or self.closing or not self.running then
				error("PROFILE_LOAD_CANCELLED")
			end
			return self.store:UpdateAsync(profileKey, function(stored)
				if loadToken.Cancelled or self.closing or not self.running then
					error("PROFILE_LOAD_CANCELLED")
				end
				local profile, migrationError = ProfileSchema.migrate(stored, player.UserId)
				if not profile then
					-- Never replace data this server cannot understand. In particular a
					-- rollback can encounter a newer schema containing fields this build
					-- does not know about; resetting that record would turn a deployment
					-- mismatch into permanent player-data loss.
					quarantined = deepCopy(stored)
					quarantineReason = migrationError
					error("PROFILE_QUARANTINE_REQUIRED")
				end
				local lock = profile.AuditMetadata.SessionLock
				if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > os.time() then
					lockedUntil = lock.ExpiresAt
					error("PROFILE_SESSION_LOCKED")
				end
				lockedUntil = nil
				-- Budget waits and retries happen outside this transform, so expiry
				-- must be based on the attempt that actually acquires and can commit the lease.
				profile.AuditMetadata.SessionLock = {
					ServerId = self.serverId,
					ExpiresAt = os.time()
						+ self.context.Configuration.Framework.SessionLeaseSeconds,
				}
				loaded = profile
				return profile
			end)
		end, function(failure)
			local text = tostring(failure)
			return string.find(text, "PROFILE_SESSION_LOCKED", 1, true) ~= nil
				or string.find(text, "PROFILE_LOAD_CANCELLED", 1, true) ~= nil
				or string.find(text, "PROFILE_QUARANTINE_REQUIRED", 1, true) ~= nil
		end)
		if not ok and string.find(tostring(problem), "PROFILE_LOAD_CANCELLED", 1, true) ~= nil then
			finishLoading()
			return nil,
				if self.closing or not self.running then "SERVICE_SHUTTING_DOWN" else "PLAYER_LEFT"
		end
		if
			not ok
			and string.find(tostring(problem), "PROFILE_QUARANTINE_REQUIRED", 1, true) ~= nil
		then
			-- The primary UpdateAsync aborted, so the unreadable profile is still the
			-- authoritative stored value. Keep a bounded recovery copy for operators,
			-- but never make the backup a prerequisite for preserving the original.
			local key = "q:" .. profileKey
			local backedUp = false
			if self:_checkKey(key, "Profiles") then
				backedUp = self:_retry(function()
					return self.store:SetAsync(key, {
						UserId = player.UserId,
						Reason = quarantineReason,
						StoredAt = os.time(),
						Profile = quarantined,
					})
				end, nil, Enum.DataStoreRequestType.SetIncrementAsync)
			end
			self.context.Logger:Error("Profile could not be migrated safely", {
				UserId = player.UserId,
				Reason = quarantineReason,
				QuarantineBackedUp = backedUp,
			})
			finishLoading()
			return nil, if backedUp then "PROFILE_QUARANTINED" else "PROFILE_QUARANTINE_FAILED"
		end
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
				local waitUntil = os.clock() + remaining + 1
				while os.clock() < waitUntil do
					if loadToken.Cancelled or self.closing or not self.running then
						finishLoading()
						return nil,
							if self.closing or not self.running
								then "SERVICE_SHUTTING_DOWN"
								else "PLAYER_LEFT"
					end
					if not player:IsDescendantOf(Players) then
						finishLoading()
						return nil, "PLAYER_LEFT"
					end
					task.wait(0.1)
				end
				finishLoading()
				return self:Load(player, true)
			end
			if remaining > 0 then
				self.context.Logger:Warning("Profile lease held for longer than a join can wait", {
					UserId = player.UserId,
					Seconds = remaining,
				})
				finishLoading()
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
			finishLoading()
			return nil, "PROFILE_LOAD_FAILED: " .. string.sub(tostring(problem), 1, 180)
		end
		if
			loadToken.Cancelled
			or self.closing
			or not self.running
			or not player:IsDescendantOf(Players)
		then
			-- The load may have acquired this server's lease after PlayerRemoving
			-- or after shutdown began.
			-- Keep the loading claim until that writer is completely finished, then
			-- clear only our own lease before allowing a replacement player to load.
			local released = self:_retry(function()
				return self.store:UpdateAsync(profileKey, function(stored)
					if type(stored) == "table" and type(stored.AuditMetadata) == "table" then
						local lock = stored.AuditMetadata.SessionLock
						if lock and lock.ServerId == self.serverId then
							stored.AuditMetadata.SessionLock = nil
						end
					end
					return stored
				end)
			end)
			if not released then
				self.context.Logger:Warning("Abandoned profile load lease could not be released", {
					UserId = player.UserId,
				})
			end
			finishLoading()
			return nil,
				if self.closing or not self.running then "SERVICE_SHUTTING_DOWN" else "PLAYER_LEFT"
		end
		self.sessions[player.UserId] = {
			Player = player,
			Profile = loaded,
			Dirty = false,
			Saving = false,
			ActiveCharacterId = nil,
			Revision = 0,
			DataKey = profileKey,
		}
		finishLoading()
		-- Establish a baseline at join. Dirty saves are measured again below so
		-- long sessions cannot grow past the warning threshold unseen.
		task.spawn(function()
			self:_measure(player, loaded)
		end)
		return loaded, nil
	end

	function DataService:GetSession(player: Player): any?
		local session = self.sessions[player.UserId]
		-- Releasing is the final profile write barrier. Once the final-save owner
		-- has claimed the session, yielding gameplay work must not reacquire the
		-- profile and mutate state after its durable snapshot has begun.
		return if session
				and session.Player == player
				and not session.Releasing
			then session
			else nil
	end

	function DataService:MarkDirty(player: Player)
		local session = self.sessions[player.UserId]
		if session and session.Player == player and not session.Releasing then
			session.Dirty = true
			session.Revision = (session.Revision or 0) + 1
		end
	end

	function DataService:Save(player: Player, release: boolean?): (boolean, string?)
		local session = self.sessions[player.UserId]
		if not session or session.Player ~= player then
			return false, "NO_SESSION"
		end
		if session.Releasing and not release then
			return false, "SESSION_RELEASING"
		end
		-- Close the mutation boundary before the final snapshot is taken. This is
		-- deliberately before the mock branch too, so runtime semantics do not
		-- differ between Studio and production.
		if release then
			session.Releasing = true
		end
		if session.Mock then
			session.Dirty = false
			if release and self.sessions[player.UserId] == session then
				self.sessions[player.UserId] = nil
			end
			return true, nil
		end
		-- A release must become visible before waiting on an existing save.
		--
		-- Otherwise an immediate rejoin can arrive while this final save is blocked
		-- behind an autosave, see a normal live session, and adopt the profile that
		-- this call is about to release. The final save then removes the replacement
		-- player's session underneath them.
		if session.Saving then
			if not release then
				return false, "SAVE_IN_PROGRESS"
			end
			if self.closing then
				local deadline = self.shutdownDeadline
					or (os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds)
				while session.Saving and os.clock() < deadline do
					task.wait(0.05)
				end
				if session.Saving then
					-- Never discard the session while its previous writer still owns a
					-- snapshot. That writer can still commit after this function returns;
					-- removing the session here would allow a replacement load to start
					-- and be overwritten later by the stale in-flight save.
					return false, "SAVE_IN_PROGRESS"
				end
			else
				-- Outside shutdown there is no teardown deadline. The active save is
				-- already bounded by DataService retry policy, so wait for that writer
				-- to finish and then perform the release ourselves instead of orphaning
				-- a permanently Releasing session.
				while session.Saving do
					task.wait(0.05)
				end
			end
			-- Another concurrent release (for example BindToClose racing a leave)
			-- may have completed while this caller waited.
			if self.sessions[player.UserId] ~= session then
				return true, nil
			end
		end
		session.Saving = true
		local revision = session.Revision or 0
		local snapshot = deepCopy(session.Profile)
		-- Measure changed state at the durable boundary, not only at join. A long
		-- session can accumulate enough bounded histories and owned content to cross
		-- the warning threshold before the next reconnect. Skip this extra encode
		-- during BindToClose so observability cannot consume the final-save window.
		if session.Dirty and not self.closing then
			self:_measure(player, snapshot)
		end
		local profileKey = session.DataKey or self:_profileKey(player)
		local ok, problem = self:_retry(function()
			self.store:UpdateAsync(profileKey, function(stored)
				-- Retry/budget waits happen before this transform. Stamp the lease from
				-- the attempt that can actually commit, not from the start of Save.
				local writeNow = os.time()
				local lock = stored and stored.AuditMetadata and stored.AuditMetadata.SessionLock
				if lock and lock.ServerId ~= self.serverId and lock.ExpiresAt > writeNow then
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
						ExpiresAt = writeNow
							+ self.context.Configuration.Framework.SessionLeaseSeconds,
					}
				end
				return snapshot
			end)
		end, function(failure)
			-- A lost lease is a settled ownership result, not a transient DataStore
			-- failure. Retrying cannot recover it while another live server remains
			-- authoritative, and can consume most of the shutdown save budget.
			return string.find(tostring(failure), "SESSION_OWNERSHIP_LOST", 1, true) ~= nil
		end)
		session.Saving = false
		if ok then
			if (session.Revision or 0) == revision then
				session.Dirty = false
			end
			if release and self.sessions[player.UserId] == session then
				self.sessions[player.UserId] = nil
			end
			return true, nil
		end
		local ownershipLost = string.find(tostring(problem), "SESSION_OWNERSHIP_LOST", 1, true)
			~= nil
		local playerStillPresent = player.Parent == Players
			and Players:GetPlayerByUserId(player.UserId) == player
		local retainedSession = false
		local reacquireReason: string? = nil
		if release then
			if
				not self.closing
				and playerStillPresent
				and not ownershipLost
				and self.sessions[player.UserId] == session
			then
				-- A failed UpdateAsync is ambiguous: the release may already have
				-- committed and cleared this server's lease. Before reopening mutation
				-- access for a cancelled teleport, atomically reacquire ownership while
				-- preserving whichever profile snapshot is actually durable.
				local reacquired, reacquireProblem = self:_retry(function()
					return self.store:UpdateAsync(profileKey, function(stored)
						if type(stored) ~= "table" or type(stored.AuditMetadata) ~= "table" then
							error("PROFILE_REACQUIRE_INVALID")
						end
						local reacquireNow = os.time()
						local lock = stored.AuditMetadata.SessionLock
						if
							lock
							and lock.ServerId ~= self.serverId
							and lock.ExpiresAt > reacquireNow
						then
							error("SESSION_OWNERSHIP_LOST")
						end
						stored.AuditMetadata.SessionLock = {
							ServerId = self.serverId,
							ExpiresAt = reacquireNow
								+ self.context.Configuration.Framework.SessionLeaseSeconds,
						}
						return stored
					end)
				end, function(failure)
					local text = tostring(failure)
					return string.find(text, "SESSION_OWNERSHIP_LOST", 1, true) ~= nil
						or string.find(text, "PROFILE_REACQUIRE_INVALID", 1, true) ~= nil
				end)
				if reacquired and self.sessions[player.UserId] == session then
					session.Releasing = false
					retainedSession = true
				else
					reacquireReason = tostring(reacquireProblem)
				end
			elseif self.sessions[player.UserId] == session then
				-- A genuine disconnect/shutdown has no live session to resume. A lost
				-- lease is also fail-closed: another server is authoritative, so this
				-- process must not reopen mutation access even if the Player instance
				-- has not disappeared yet.
				self.sessions[player.UserId] = nil
			end
		end
		self.context.Logger:Error("Profile save failed", {
			UserId = player.UserId,
			Error = tostring(problem),
			Released = release == true,
			SessionRetained = retainedSession,
			ReacquireError = reacquireReason,
		})
		return false, "PROFILE_SAVE_FAILED"
	end
end
