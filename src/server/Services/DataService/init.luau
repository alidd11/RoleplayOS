--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {
	Critical = true,
	sessions = {},
	running = false,
	connections = {},
	loading = {},
	budgetWarnings = {},
	finalReleases = {},
	shutdownDeadline = nil,
}
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
local MAXIMUM_KEY_LENGTH = 48
local MAXIMUM_SCOPE_LENGTH = 50
local MAXIMUM_VALUE_BYTES = 4 * 1024 * 1024

local ProfileLifecycle = require(script.ProfileLifecycle)
local MDTRecords = require(script.MDTRecords)
local ShoulderNumbers = require(script.ShoulderNumbers)
local CustomRegistrations = require(script.CustomRegistrations)
local SharedRecords = require(script.SharedRecords)

-- Each of these attaches a group of methods onto DataService directly (they
-- only need `self`, not a lexical upvalue), the same split NetworkService
-- used for its endpoint domains. Order does not matter: nothing here runs
-- until a caller invokes a method, well after every group is attached.
ProfileLifecycle(DataService)
MDTRecords(DataService)
ShoulderNumbers(DataService)
CustomRegistrations(DataService)
SharedRecords(DataService)

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

-- Shared records are global by default because routing/configuration records
-- genuinely belong to the whole experience. Progression callers may opt into an
-- official-server scope instead. The scope is separate from the key, preserving
-- historical public keys and keeping gang:<GUID> below Roblox's key limit.
function DataService:_validateSharedRecordScope(scopeId: string?): boolean
	if scopeId == nil then
		return true
	end
	local entries = self.context.Configuration.OfficialServers
		and self.context.Configuration.OfficialServers.Entries
	local entry = type(entries) == "table" and entries[scopeId] or nil
	if type(entry) ~= "table" or entry.Id ~= scopeId then
		self.context.Logger:Error("Refused unknown shared-record persistence scope", {
			ScopeId = scopeId,
		})
		return false
	end
	local scopeName = "wl:" .. scopeId
	if #scopeName > MAXIMUM_SCOPE_LENGTH then
		self.context.Logger:Error("Data store scope exceeds the fifty character limit", {
			ScopeId = scopeId,
			Length = #scopeName,
		})
		return false
	end
	return true
end

function DataService:_sharedRecordStoreForScope(scopeId: string?): any?
	if scopeId == nil then
		return self.sharedRecordStore
	end
	if not self:_validateSharedRecordScope(scopeId) then
		return nil
	end
	local cached = self.scopedSharedRecordStores[scopeId]
	if cached then
		return cached
	end
	local scopeName = "wl:" .. scopeId
	local ok, store =
		pcall(DataStoreService.GetDataStore, DataStoreService, COMMUNITY_STORE_NAME, scopeName)
	if not ok then
		self.context.Logger:Error("Could not open scoped shared-record store", {
			ScopeId = scopeId,
			Error = tostring(store),
		})
		return nil
	end
	self.scopedSharedRecordStores[scopeId] = store
	return store
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

function DataService:Init(context: any)
	self.context = context
	self.budgetWarnings = {}
	self.finalReleases = {}
	self.shutdownDeadline = nil
	self.mock = RunService:IsStudio() and context.Configuration.Framework.UseMockDataInStudio
	self.mockSharedRecords = {}
	self.scopedSharedRecordStores = {}
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
	if self.shutdownDeadline then
		deadline = math.min(deadline, self.shutdownDeadline)
	end
	local waited = false
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		if os.clock() >= deadline then
			local warningKey = requestType.Name .. ":deadline"
			if os.clock() - (self.budgetWarnings[warningKey] or 0) >= 30 then
				self.budgetWarnings[warningKey] = os.clock()
				self.context.Logger:Warning("DataStore budget did not recover; writing anyway", {
					RequestType = requestType.Name,
				})
			end
			return
		end
		waited = true
		task.wait(0.5)
	end
	if waited then
		-- Logged, because throttling that nobody sees is throttling nobody fixes,
		-- and the fix is usually saving less often rather than saving harder.
		local warningKey = requestType.Name .. ":wait"
		if os.clock() - (self.budgetWarnings[warningKey] or 0) >= 30 then
			self.budgetWarnings[warningKey] = os.clock()
			self.context.Logger:Warning("Waited for DataStore budget", {
				RequestType = requestType.Name,
			})
		end
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
		if self.shutdownDeadline and os.clock() >= self.shutdownDeadline then
			return false, lastError or "SHUTDOWN_SAVE_DEADLINE"
		end
		self:_awaitBudget(budgetType)
		if self.shutdownDeadline and os.clock() >= self.shutdownDeadline then
			return false, lastError or "SHUTDOWN_SAVE_DEADLINE"
		end
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		if final and final(result) then
			return false, result
		end
		-- Backoff only separates one attempt from the next. Sleeping after the
		-- final failed attempt cannot enable another write and, during shutdown,
		-- needlessly consumes the bounded final-save window before the caller can
		-- account for the failure.
		if attempt < self.context.Configuration.Framework.MaxSaveAttempts then
			local backoff = math.min(2 ^ (attempt - 1), 8) + math.random() * 0.25
			if self.shutdownDeadline then
				backoff = math.min(backoff, math.max(0, self.shutdownDeadline - os.clock()))
			end
			if backoff > 0 then
				task.wait(backoff)
			end
		end
	end
	return false, lastError
end

function DataService:_beginFinalRelease(player: Player): any
	local existing = self.finalReleases[player]
	if existing then
		return existing
	end
	local session = self.sessions[player.UserId]
	if not session or session.Player ~= player then
		return nil
	end
	local state: any = {
		Done = false,
		Success = false,
		Reason = nil,
	}
	self.finalReleases[player] = state
	-- Deferred so every synchronous PlayerRemoving handler gets one last chance
	-- to commit disconnect consequences before the profile snapshot is frozen.
	task.defer(function()
		local ok, saved, reason = pcall(function()
			return self:Save(player, true)
		end)
		state.Done = true
		state.Success = ok and saved == true
		state.Reason = if not ok then tostring(saved) else reason
		if not state.Success then
			self.context.Logger:Warning("Final profile release failed", {
				UserId = player.UserId,
				Reason = tostring(state.Reason),
			})
		end
		-- During ordinary player churn the completed state has no further value.
		-- During shutdown it stays until Destroy has accounted for the outcome.
		if not self.closing then
			self.finalReleases[player] = nil
		end
	end)
	return state
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
					or reason == "SERVICE_SHUTTING_DOWN"
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
			if profile or reason == "SERVICE_SHUTTING_DOWN" then
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
			-- Do not erase an in-flight load claim here. The DataStore request may
			-- still be running, and clearing the slot lets an immediate rejoin start
			-- a second UpdateAsync for the same UserId. Mark the exact load as
			-- cancelled instead; its owner will release any lease it acquired before
			-- handing the slot to the replacement player.
			local loading = self.loading[player.UserId]
			if loading and loading.Player == player then
				loading.Cancelled = true
			end
			-- Track the deferred release so BindToClose can wait for it even after
			-- this Player is no longer returned by Players:GetPlayers().
			self:_beginFinalRelease(player)
		end)
	)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Load(player)
		end)
	end
	task.spawn(function()
		local function cadenceSeconds(): number
			return math.min(
				self.context.Configuration.Framework.AutosaveSeconds,
				math.max(
					30,
					math.floor(self.context.Configuration.Framework.SessionLeaseSeconds / 3)
				)
			)
		end

		local nextAutosaveAt = os.clock() + cadenceSeconds()
		while self.running do
			local delay = nextAutosaveAt - os.clock()
			if delay > 0 then
				task.wait(delay)
			end
			if not self.running then
				return
			end

			local autosaveSeconds = cadenceSeconds()
			-- Anchor the next cycle before spreading this one. Waiting a full cadence
			-- after the spread doubled the effective per-profile renewal interval:
			-- with a 60-second cadence and a full-width spread, the same player could
			-- go almost 120 seconds between lease renewals, equal to the configured
			-- 120-second lease and therefore leaving no latency/retry margin.
			nextAutosaveAt = os.clock() + autosaveSeconds
			local players = Players:GetPlayers()
			-- Keep the anti-burst behaviour, but consume only half of the cadence.
			-- Even if player ordering shifts between cycles, a renewal remains well
			-- inside the minimum two-cadence lease rather than landing at its expiry.
			local spreadSeconds = autosaveSeconds / 2
			local spacing = math.max(0.25, spreadSeconds / math.max(#players, 1))
			for index, player in players do
				if not self.running then
					return
				end
				task.spawn(function()
					self:Save(player, false)
				end)
				if index < #players then
					task.wait(spacing)
				end
			end
		end
	end)
end

function DataService:Destroy()
	self.running = false
	-- Mark closing before disconnecting signals so any already-deferred final
	-- release that finishes during teardown keeps its result for this method to
	-- account for.
	self.closing = true
	-- One absolute deadline governs every shutdown wait. Final releases must not
	-- start a second full shutdown window after waiting behind an in-flight save.
	self.shutdownDeadline = os.clock() + self.context.Configuration.Framework.ShutdownSaveSeconds
	-- Loads have no published session yet, so the final-release set cannot see
	-- them. Cancel every exact load token and keep BindToClose open until each
	-- owner has stopped touching profile storage (or the shared deadline expires).
	for _, loadToken in self.loading do
		loadToken.Cancelled = true
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	-- Shortens the budget wait for the rest of this shutdown.
	--
	-- Roblox allows about thirty seconds to close. Waiting twelve of them for
	-- budget, per profile, spends the window that the writes themselves need.

	-- Sessions, not Players:GetPlayers(), are the authoritative set to drain.
	-- A PlayerRemoving callback can already have fired and removed the Player
	-- from Players while its final DataStore write is still in flight.
	for _, session in self.sessions do
		local player = session.Player
		if player then
			self:_beginFinalRelease(player)
		end
	end

	local deadline = self.shutdownDeadline
	local function unfinishedReleases(): number
		local pending = 0
		for _, state in self.finalReleases do
			if not state.Done then
				pending += 1
			end
		end
		return pending
	end
	local function unfinishedLoads(): number
		local pending = 0
		for _ in self.loading do
			pending += 1
		end
		return pending
	end
	while (unfinishedReleases() > 0 or unfinishedLoads() > 0) and os.clock() < deadline do
		task.wait()
	end

	local pending = 0
	local unsaved: { string } = {}
	for player, state in self.finalReleases do
		if not state.Done then
			pending += 1
		elseif not state.Success then
			table.insert(
				unsaved,
				string.format(
					"%s (%d): %s",
					player.Name,
					player.UserId,
					tostring(state.Reason or "PROFILE_SAVE_FAILED")
				)
			)
		end
	end
	local activeLoads: { number } = {}
	for userId in self.loading do
		table.insert(activeLoads, userId)
	end
	table.sort(activeLoads)
	if pending > 0 or #unsaved > 0 or #activeLoads > 0 then
		-- Named, not counted.
		--
		-- Somebody whose profile did not save has lost whatever they earned since
		-- their last autosave, and they will say so. A count cannot be checked
		-- against that claim; a list can, and it is the difference between
		-- answering them and guessing.
		self.context.Logger:Error("Profiles may not have saved at shutdown", {
			StillWriting = pending,
			Failed = unsaved,
			ProfileLoadsStillWriting = activeLoads,
		})
	end
	table.clear(self.finalReleases)
	table.clear(self.scopedSharedRecordStores)
end

return DataService
