--!strict
-- Fault-injected contracts against actual DataService, never real DataStores.
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local DataService = runtime.require(root.DataService)
		local copy = runtime.require(root.DataService.Utils).deepCopy
		local profileSchema =
			runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Shared.ProfileSchema)
		local store: any = { Values = {}, Updates = 0, Sets = 0, Gets = 0, Replays = 2 }
		function store:UpdateAsync(key, transform)
			self.Updates += 1
			if self.BeforeUpdate then
				self.BeforeUpdate(key)
			end
			local updated
			-- Replay the callback against fresh copies of the same stored version.
			for _ = 1, self.Replays do
				updated = transform(copy(self.Values[key]))
			end
			if updated ~= nil then
				self.Values[key] = copy(updated)
			end
			if self.AfterUpdate then
				self.AfterUpdate(key)
			end
			return copy(self.Values[key])
		end
		function store:SetAsync(key, value)
			self.Sets += 1
			if self.BeforeSet then
				self.BeforeSet(key)
			end
			self.Values[key] = copy(value)
			if self.AfterSet then
				self.AfterSet(key)
			end
		end
		function store:GetAsync(key)
			self.Gets += 1
			if self.BeforeGet then
				self.BeforeGet(key)
			end
			return copy(self.Values[key])
		end
		local player: any = {
			UserId = 42,
			Name = "ContractPlayer",
			Parent = runtime.services.Players,
			Present = true,
		}
		function player:IsDescendantOf(parent)
			return self.Present and parent == runtime.services.Players
		end
		function player:GetJoinData()
			return {}
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, userId)
			return if player.Present and userId == player.UserId then player else nil
		end
		local logs = {}
		local logger = {}
		for _, level in { "Info", "Warning", "Error" } do
			logger[level] = function(_self, message, metadata)
				table.insert(logs, { Level = level, Message = message, Metadata = metadata })
			end
		end
		local service: any = setmetatable({
			context = {
				Configuration = {
					Framework = {
						MaxSaveAttempts = 1,
						SessionLeaseSeconds = 120,
						ShutdownSaveSeconds = 0.1,
					},
					OfficialServers = {
						Entries = { Police = { Id = "Police", Whitelisted = true } },
					},
				},
				Logger = logger,
			},
			sessions = {},
			loading = {},
			connections = {},
			finalReleases = {},
			scopedSharedRecordStores = {},
			serverId = "test-owner",
			running = true,
			mock = false,
			store = store,
			sharedRecordStore = store,
			registrationStore = store,
			shoulderStore = store,
			mdtRecordStore = store,
			mdtIndexStore = store,
			mockSharedRecords = {},
			mockMdtRecords = {},
			mockMdtIndexes = {},
			mockRegistrations = {},
			mockShoulder = {},
			_awaitBudget = function() end,
			_measure = function() end,
		}, { __index = DataService })
		local profile = profileSchema.default(player.UserId)
		profile.AuditMetadata.SessionLock =
			{ ServerId = service.serverId, ExpiresAt = os.time() + 120 }
		store.Values["42"] = copy(profile)
		local function session(): any
			local value = {
				Player = player,
				Profile = copy(profile),
				Dirty = true,
				Revision = 1,
				DataKey = "42",
			}
			service.sessions[player.UserId] = value
			return value
		end
		return {
			Service = service,
			Store = store,
			Player = player,
			Session = session,
			Copy = copy,
			Logs = logs,
		}
	end

	H.test("profile loads are idempotent and acquire only one lease", function()
		local f = fixture()
		local profile, reason = f.Service:Load(f.Player)
		H.expect(profile ~= nil and reason == nil, "profile did not load")
		H.expect(f.Service:Load(f.Player) == profile, "repeat load replaced the live session")
		H.expect(f.Store.Updates == 1 and f.Service.loading[42] == nil, "load claim did not settle")
		H.expect(
			f.Store.Values["42"].AuditMetadata.SessionLock.ServerId == "test-owner",
			"wrong lease owner"
		)
	end)
	H.test("profile load attempts are staggered across a join wave", function()
		local f = fixture()
		f.Service.context.Configuration.Framework.ProfileLoadStartIntervalSeconds = 0.03
		f.Service.nextProfileLoadAt = 0
		local second: any = {
			UserId = 43,
			Name = "SecondContractPlayer",
			Parent = f.Player.Parent,
			Present = true,
		}
		function second:IsDescendantOf(parent)
			return self.Present and parent == self.Parent
		end
		function second:GetJoinData()
			return {}
		end
		f.Store.Values["43"] = f.Copy(f.Store.Values["42"])
		f.Store.Values["43"].AuditMetadata.SessionLock = nil
		local starts = {}
		f.Store.BeforeUpdate = function(key)
			if key == "42" or key == "43" then
				table.insert(starts, os.clock())
			end
		end
		H.expect(f.Service:Load(f.Player) ~= nil, "first profile load failed")
		H.expect(f.Service:Load(second) ~= nil, "second profile load failed")
		H.expect(#starts == 2, "profile load pacing changed UpdateAsync count")
		H.expect(
			starts[2] - starts[1] >= 0.02,
			"profile UpdateAsync starts were not staggered"
		)
	end)

	H.test("profile load refuses another live server's lease without modifying it", function()
		local f = fixture()
		f.Store.Values["42"].AuditMetadata.SessionLock.ServerId = "other-owner"
		local profile, reason = f.Service:Load(f.Player, true)
		H.expect(
			profile == nil and string.find(reason, "PROFILE_SESSION_LOCKED", 1, true),
			"foreign lease accepted"
		)
		H.expect(
			f.Store.Values["42"].AuditMetadata.SessionLock.ServerId == "other-owner",
			"foreign lease changed"
		)
		H.expect(
			f.Store.Updates == 1 and f.Service.sessions[42] == nil and f.Service.loading[42] == nil,
			"failed load leaked state"
		)
	end)
	H.test("unreadable profiles preserve primary data even when quarantine backup fails", function()
		for _, backupFails in { false, true } do
			local f = fixture()
			f.Store.Values["42"].Characters = "corrupt-authoritative-state"
			if backupFails then
				f.Store.BeforeSet = function()
					error("backup outage")
				end
			end
			local profile, reason = f.Service:Load(f.Player)
			H.expect(
				profile == nil
					and reason
						== (if backupFails
							then "PROFILE_QUARANTINE_FAILED"
							else "PROFILE_QUARANTINED"),
				"wrong quarantine result"
			)
			H.expect(
				f.Store.Values["42"].Characters == "corrupt-authoritative-state",
				"primary corruption was overwritten"
			)
			if not backupFails then
				H.expect(
					f.Store.Values["q:42"].Profile.Characters == "corrupt-authoritative-state",
					"backup lost original state"
				)
			end
			H.expect(
				f.Service.loading[42] == nil and f.Service.sessions[42] == nil,
				"quarantine published a session"
			)
		end
	end)
	H.test(
		"invalid migration numbers are quarantined without rewriting the primary profile",
		function()
			for _, case in { "fractional-version", "overflowed-balance" } do
				local f = fixture()
				local stored = f.Store.Values["42"]
				if case == "fractional-version" then
					stored.SchemaVersion = 0.5
				else
					stored.SchemaVersion = 9
					stored.Characters.legacy = { Economy = { Balance = "1e309" } }
				end
				local profile, reason = f.Service:Load(f.Player)
				H.expect(
					profile == nil and reason == "PROFILE_QUARANTINED",
					"invalid numeric state was published"
				)
				H.expect(
					f.Store.Values["42"].SchemaVersion == stored.SchemaVersion,
					"primary schema changed on rejection"
				)
				local backup = f.Store.Values["q:42"]
				if case == "fractional-version" then
					H.expect(
						backup.Reason == "PROFILE_VERSION_INVALID"
							and backup.Profile.SchemaVersion == 0.5,
						"version backup lost original state"
					)
				else
					H.expect(
						f.Store.Values["42"].Characters.legacy.Economy.Balance == "1e309",
						"primary balance was coerced on rejection"
					)
					H.expect(
						backup.Reason == "PROFILE_ECONOMY_BALANCE_INVALID"
							and backup.Profile.Characters.legacy.Economy.Balance == "1e309",
						"balance backup lost original state"
					)
				end
			end
		end
	)
	H.test(
		"a departed player's late load releases its lease without publishing a session",
		function()
			local f = fixture()
			f.Store.AfterUpdate = function()
				f.Player.Present = false
			end
			local profile, reason = f.Service:Load(f.Player)
			H.expect(
				profile == nil and reason == "PLAYER_LEFT",
				"late load published after departure"
			)
			H.expect(
				f.Store.Updates == 2 and f.Store.Values["42"].AuditMetadata.SessionLock == nil,
				"late lease not released"
			)
			H.expect(
				f.Service.sessions[42] == nil and f.Service.loading[42] == nil,
				"late load leaked runtime claims"
			)
		end
	)
	H.test("saving an earlier snapshot does not clear a newer dirty revision", function()
		local f = fixture()
		local session = f.Session()
		session.Profile.TestValue = "snapshot"
		f.Store.BeforeUpdate = function()
			session.Profile.TestValue = "newer mutation"
			f.Service:MarkDirty(f.Player)
		end
		H.expect(f.Service:Save(f.Player), "save failed")
		H.expect(f.Store.Values["42"].TestValue == "snapshot", "snapshot aliased mutable session")
		H.expect(
			session.Dirty and session.Revision == 2 and not session.Saving,
			"newer mutation marked saved"
		)
		f.Store.BeforeUpdate = nil
		H.expect(f.Service:Save(f.Player), "follow-up save failed")
		H.expect(
			not session.Dirty and f.Store.Values["42"].TestValue == "newer mutation",
			"follow-up save lost mutation"
		)
	end)
	H.test("final save closes mutation access before taking its durable snapshot", function()
		local f = fixture()
		local session = f.Session()
		f.Store.BeforeUpdate = function()
			H.expect(f.Service:GetSession(f.Player) == nil, "release exposed mutable session")
			f.Service:MarkDirty(f.Player)
			H.expect(session.Revision == 1, "release accepted dirty mutation")
		end
		H.expect(f.Service:Save(f.Player, true), "release failed")
		H.expect(
			f.Service.sessions[42] == nil and f.Store.Values["42"].AuditMetadata.SessionLock == nil,
			"release retained lease/session"
		)
	end)
	H.test(
		"failed cancelled-teleport release reacquires ownership before reopening mutation",
		function()
			local f = fixture()
			local session = f.Session()
			f.Store.AfterUpdate = function()
				if f.Store.Updates == 1 then
					error("committed but response lost")
				end
			end
			local saved, reason = f.Service:Save(f.Player, true)
			H.expect(
				not saved and reason == "PROFILE_SAVE_FAILED",
				"ambiguous release reported success"
			)
			H.expect(
				f.Store.Updates == 2
					and f.Store.Values["42"].AuditMetadata.SessionLock.ServerId == "test-owner",
				"lease not reacquired"
			)
			H.expect(
				f.Service:GetSession(f.Player) == session
					and not session.Releasing
					and session.Dirty,
				"live player could not safely resume"
			)
		end
	)
	H.test("failed reacquisition keeps a cancelled-teleport session fenced", function()
		local f = fixture()
		local session = f.Session()
		f.Store.AfterUpdate = function()
			error("committed but response lost")
		end
		H.expect(not f.Service:Save(f.Player, true), "ambiguous release reported success")
		H.expect(
			f.Service:GetSession(f.Player) == nil and session.Releasing,
			"uncertain ownership reopened mutation"
		)
	end)
	H.test("a lost profile lease is final and never overwrites another server", function()
		local f = fixture()
		f.Session()
		f.Service.context.Configuration.Framework.MaxSaveAttempts = 3
		f.Store.Values["42"].AuditMetadata.SessionLock.ServerId = "other-owner"
		H.expect(not f.Service:Save(f.Player, true), "foreign owner was overwritten")
		H.expect(
			f.Store.Updates == 1
				and f.Store.Values["42"].AuditMetadata.SessionLock.ServerId == "other-owner",
			"ownership loss retried or changed data"
		)
		H.expect(f.Service:GetSession(f.Player) == nil, "ownership loss reopened a session")
	end)
	H.test("shutdown deadline does not discard a session with an in-flight writer", function()
		local f = fixture()
		local session = f.Session()
		session.Saving = true
		f.Service.closing, f.Service.shutdownDeadline = true, os.clock() - 1
		local saved, reason = f.Service:Save(f.Player, true)
		H.expect(not saved and reason == "SAVE_IN_PROGRESS", "shutdown ignored active writer")
		H.expect(
			f.Service.sessions[42] == session and session.Releasing and f.Store.Updates == 0,
			"shutdown discarded or raced the writer"
		)
		local calls = 0
		local ok, problem = f.Service:_retry(function()
			calls += 1
		end)
		H.expect(
			not ok and problem == "SHUTDOWN_SAVE_DEADLINE" and calls == 0,
			"expired deadline still spent a write"
		)
	end)
	H.test(
		"DataService retries transient failures but stops at its configured attempt cap",
		function()
			local f = fixture()
			f.Service.context.Configuration.Framework.MaxSaveAttempts = 2
			local attempts = 0
			local ok, result = f.Service:_retry(function()
				attempts += 1
				if attempts == 1 then
					error("transient")
				end
				return "recovered"
			end)
			H.expect(
				ok and result == "recovered" and attempts == 2,
				"transient failure did not recover"
			)
			attempts = 0
			ok = f.Service:_retry(function()
				attempts += 1
				error("persistent")
			end)
			H.expect(not ok and attempts == 2, "retry exceeded its cap")
		end
	)
	H.test(
		"shared record tombstones hide deletion and allow recreation under callback replay",
		function()
			local f = fixture()
			f.Service:UpdateSharedRecord("record", function()
				return { Value = 1 }
			end)
			local deleted, reason = f.Service:UpdateSharedRecord("record", function()
				return nil
			end)
			H.expect(
				deleted == nil
					and reason == nil
					and f.Store.Values.record.__RoleplayOSDeleted == true,
				"delete cancelled rather than committed"
			)
			H.expect(
				f.Service:GetSharedRecord("record") == nil,
				"tombstone escaped the persistence boundary"
			)
			f.Service:UpdateSharedRecord("record", function(stored)
				H.expect(stored == nil, "recreation received internal tombstone")
				return { Value = 2 }
			end)
			H.expect(f.Service:GetSharedRecord("record").Value == 2, "record did not recreate")
		end
	)
	H.test("mock shared and MDT records do not alias caller-owned tables", function()
		local f = fixture()
		f.Service.mock = true
		for _, methods in
			{
				{ "UpdateSharedRecord", "GetSharedRecord" },
				{ "UpdateMdtRecord", "GetMdtRecord" },
				{ "UpdateMdtIndex", "GetMdtIndex" },
			}
		do
			local input = { Nested = { Value = 1 } }
			local result = f.Service[methods[1]](f.Service, "record", function()
				return input
			end)
			input.Nested.Value, result.Nested.Value = 2, 3
			local read = f.Service[methods[2]](f.Service, "record")
			H.expect(read.Nested.Value == 1, "write aliased caller value")
			read.Nested.Value = 4
			H.expect(
				f.Service[methods[2]](f.Service, "record").Nested.Value == 1,
				"read aliased stored value"
			)
		end
	end)
	H.test("registration swaps reject competing operations and ignore stale rollback", function()
		for _, mock in { false, true } do
			local f = fixture()
			f.Service.mock = mock
			H.expect(
				f.Service:ReserveCustomRegistrationSwap("ab123", 42, "vehicle", "first"),
				"first reservation refused"
			)
			local reserved, reason =
				f.Service:ReserveCustomRegistrationSwap("AB123", 42, "vehicle", "second")
			H.expect(
				not reserved and reason == "REGISTRATION_SWAP_IN_PROGRESS",
				"competing swap stole reservation"
			)
			f.Service:CompleteCustomRegistrationSwap("AB123", 42, "vehicle", "first")
			H.expect(
				f.Service:ReserveCustomRegistrationSwap("AB123", 42, "vehicle", "second"),
				"next operation refused after completion"
			)
			f.Service:ReleaseCustomRegistrationSwap("ab123", 42, "vehicle", "first")
			local records = if mock then f.Service.mockRegistrations else f.Store.Values
			H.expect(
				records.AB123.SwapOperationId == "second",
				"stale rollback freed newer reservation"
			)
			reserved, reason = f.Service:ReserveCustomRegistration("AB123", 99, "other")
			H.expect(
				not reserved and reason == "REGISTRATION_ALREADY_USED",
				"different owner stole plate"
			)
		end
	end)
	H.test("ambiguous shoulder holder writes verify the exact committed owner", function()
		for _, committed in { false, true } do
			local f = fixture()
			if committed then
				f.Store.AfterSet = function()
					error("lost response")
				end
			else
				f.Store.BeforeSet = function()
					error("write never committed")
				end
			end
			local issued, reason = f.Service:AllocateShoulderNumber("Police", 42, 100)
			H.expect(
				(issued == 100) == committed,
				"ambiguous holder result did not match verified ownership"
			)
			H.expect((reason == nil) == committed and f.Store.Gets == 1, "holder was not verified")
			H.expect(
				f.Store.Values["counter:Police"] == 100,
				"failed holder write reissued counter"
			)
		end
	end)
end
