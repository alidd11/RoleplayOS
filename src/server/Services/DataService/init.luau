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
			local autosaveSeconds = math.min(
				self.context.Configuration.Framework.AutosaveSeconds,
				math.max(
					30,
					math.floor(self.context.Configuration.Framework.SessionLeaseSeconds / 3)
				)
			)
			task.wait(autosaveSeconds)
			local players = Players:GetPlayers()
			-- Spread requests across the cadence. The previous loop launched every
			-- save in one frame, creating a DataStore burst with a full server.
			local spacing = math.max(0.25, autosaveSeconds / math.max(#players, 1))
			for index, player in players do
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
