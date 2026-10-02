--!strict
-- Actual EconomyService with explicit detached persistence/player fixtures.
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local EconomyService = runtime.require(root.EconomyService)
		local copy = runtime.require(root.DataService.Utils).deepCopy
		local players, sessions, durable, shared = {}, {}, {}, {}
		for _, entry in { { 10, "sender", 100 }, { 20, "recipient", 50 } } do
			local player = { UserId = entry[1], Parent = runtime.services.Players }
			players[entry[1]] = player
			local profile = {
				Characters = {
					[entry[2]] = {
						Identity = { FirstName = entry[2], LastName = "Player" },
						Economy = {
							Balance = entry[3],
							Cash = 5,
							Transactions = {},
							PendingCashDropRefunds = {},
						},
					},
				},
			}
			sessions[entry[1]] =
				{ Player = player, ActiveCharacterId = entry[2], Profile = profile }
			durable[entry[1]] = copy(profile)
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return players[id]
		end
		local data: any = { Writes = 0, Saves = 0, Dirty = 0 }
		function data:GetSession(player)
			local session = sessions[player.UserId]
			return if session and session.Player == player then session else nil
		end
		function data:GetCurrentProfileSharedRecordScope()
			return nil
		end
		function data:MarkDirty()
			self.Dirty += 1
		end
		function data:GetSharedRecord(key)
			if self.BeforeRead then
				local reason = self.BeforeRead(key)
				if reason then
					return nil, reason
				end
			end
			return copy(shared[key]), nil
		end
		function data:UpdateSharedRecord(key, transform)
			self.Writes += 1
			if self.BeforeWrite then
				local reason = self.BeforeWrite(key)
				if reason then
					return nil, reason
				end
			end
			local updated
			for _ = 1, 2 do
				updated = transform(copy(shared[key]))
			end
			-- DataService's logical contract includes deletion, backed by its tombstone.
			shared[key] = copy(updated)
			if self.AfterWrite then
				local reason = self.AfterWrite(key)
				if reason then
					return nil, reason
				end
			end
			return copy(updated), nil
		end
		function data:Save(player)
			self.Saves += 1
			if self.BeforeSave then
				local reason = self.BeforeSave(player)
				if reason then
					return false, reason
				end
			end
			durable[player.UserId] = copy(sessions[player.UserId].Profile)
			if self.AfterSave then
				local reason = self.AfterSave(player)
				if reason then
					return false, reason
				end
			end
			return true, nil
		end
		local audit = { Count = 0 }
		function audit:Record()
			self.Count += 1
		end
		local context = {
			Configuration = {
				Economy = {
					MaximumTransactionHistory = 4,
					MaximumTransferReceipts = 2,
					TransferMaximum = 1000,
				},
				MoneyDrops = { MaximumActivePerPlayer = 2 },
			},
			Logger = { Error = function() end, Warning = function() end },
			Services = {
				Get = function(_self, name)
					assert(
						name == "DataService" or name == "AuditService",
						"unexpected economy dependency"
					)
					return if name == "DataService" then data else audit
				end,
			},
		}
		local function economy(): any
			local value = setmetatable({
				seen = {},
				order = {},
				transferring = {},
				connections = {},
				reconciling = {},
				recoveryPending = {},
				recoveryPersistenceFailed = {},
			}, { __index = EconomyService })
			value:Init(context)
			-- Start's real player signals are deliberately outside these fixtures.
			value.running = true
			return value
		end
		local f: any = {
			Economy = economy(),
			Data = data,
			Players = players,
			Sessions = sessions,
			Durable = durable,
			Shared = shared,
			Audit = audit,
		}
		function f:Character(id)
			local session = sessions[id]
			return session.Profile.Characters[session.ActiveCharacterId]
		end
		function f:Restart()
			self.Economy:Destroy()
			for id, profile in durable do
				sessions[id].Profile = copy(profile)
			end
			self.Economy = economy()
		end
		function f:Recover()
			-- Sender may report settlement-pending until the recipient leg completes.
			self.Economy:ReconcilePendingTransfers(players[10], "sender")
			local recovered, reason =
				self.Economy:ReconcilePendingTransfers(players[20], "recipient")
			H.expect(recovered and reason == nil, "recipient recovery failed")
			recovered, reason = self.Economy:ReconcilePendingTransfers(players[10], "sender")
			H.expect(recovered and reason == nil, "sender recovery did not drain")
		end
		function f:AssertSettled()
			H.expect(
				self:Character(10).Economy.Balance == 90
					and self:Character(20).Economy.Balance == 60,
				"settlement lost or duplicated money"
			)
			H.expect(
				shared["pts:10"].Pending == nil
					and shared["pts:20"] == nil
					and shared["ts:phone-operation"] == nil,
				"settlement journal did not drain"
			)
			H.expect(
				next(self.Economy.transferring) == nil and next(self.Economy.recoveryPending) == nil,
				"settlement leaked runtime locks"
			)
		end
		return f
	end
	local function transaction(id: string, amount: number, account: string?): any
		return {
			TransactionId = id,
			CharacterId = "sender",
			Amount = amount,
			Account = account,
			Direction = "Debit",
			ReasonCode = "Contract.Test",
		}
	end

	H.test(
		"actual economy applies only the selected account and refuses duplicate transactions",
		function()
			local f = fixture()
			H.expect(f.Economy:Apply(f.Players[10], transaction("bank", 10)), "bank debit refused")
			H.expect(
				f.Economy:Apply(f.Players[10], transaction("cash", 2, "Cash")),
				"cash debit refused"
			)
			local applied, reason = f.Economy:Apply(f.Players[10], transaction("bank", 10))
			H.expect(
				not applied and reason == "DUPLICATE_TRANSACTION",
				"transaction replay applied"
			)
			H.expect(
				f:Character(10).Economy.Balance == 90 and f:Character(10).Economy.Cash == 3,
				"account isolation failed"
			)
			H.expect(
				f.Data.Dirty == 2 and f.Audit.Count == 2,
				"duplicate dirtied or audited as applied"
			)
		end
	)
	H.test("actual economy refuses inactive characters and pending transfer mutations", function()
		local f = fixture()
		local tx = transaction("inactive", 10)
		tx.CharacterId = "recipient"
		local applied, reason = f.Economy:Apply(f.Players[10], tx)
		H.expect(
			not applied and reason == "CHARACTER_NOT_ACTIVE",
			"foreign/inactive character charged"
		)
		f.Economy.recoveryPending["10:sender"] = true
		applied, reason = f.Economy:Apply(f.Players[10], transaction("pending", 10))
		H.expect(
			not applied and reason == "TRANSFER_RECOVERY_PENDING" and f.Data.Dirty == 0,
			"pending recovery allowed spending"
		)
	end)
	H.test("actual economy rebuilds replay guards from persisted transaction history", function()
		local f = fixture()
		H.expect(f.Economy:Apply(f.Players[10], transaction("durable", 10)), "debit refused")
		f.Data:Save(f.Players[10])
		f:Restart()
		local applied, reason = f.Economy:Apply(f.Players[10], transaction("durable", 10))
		H.expect(
			not applied
				and reason == "DUPLICATE_TRANSACTION"
				and f:Character(10).Economy.Balance == 90,
			"restart forgot durable replay guard"
		)
	end)
	H.test("actual economy bounds both transaction history and runtime replay state", function()
		local f = fixture()
		for i = 1, 6 do
			H.expect(
				f.Economy:Apply(f.Players[10], transaction("tx-" .. i, 1)),
				"bounded debit refused"
			)
		end
		local history = f:Character(10).Economy.Transactions
		H.expect(
			#history == 4
				and history[1].TransactionId == "tx-3"
				and history[4].TransactionId == "tx-6",
			"history retained wrong entries"
		)
		local count = 0
		for _ in f.Economy.seen["10:sender"] do
			count += 1
		end
		H.expect(
			count == 4 and #f.Economy.order["10:sender"] == 4,
			"runtime replay state grew past cap"
		)
	end)
	H.test(
		"actual two-profile transfer settles once and rejects changed operation details",
		function()
			local f = fixture()
			local result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(result ~= nil and reason == nil, "transfer failed")
			f:AssertSettled()
			local saves = f.Data.Saves
			result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(
				result ~= nil and reason == nil and f.Data.Saves == saves,
				"receipt replay repeated profile writes"
			)
			result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 11, "operation")
			H.expect(
				result == nil and reason == "TRANSFER_ID_CONFLICT",
				"changed operation details reused receipt"
			)
			f:AssertSettled()
		end
	)
	H.test(
		"ambiguous settlement-record creation remains discoverable before money changes",
		function()
			local f = fixture()
			f.Data.AfterWrite = function(key)
				return if key == "ts:phone-operation" then "SHARED_RECORD_UPDATE_FAILED" else nil
			end
			local result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(
				result == nil and reason == "TRANSFER_RECOVERY_PENDING",
				"ambiguous record reported success"
			)
			H.expect(
				f:Character(10).Economy.Balance == 100 and f:Character(20).Economy.Balance == 50,
				"money changed before confirmed journal"
			)
			H.expect(
				f.Shared["pts:10"].Pending ~= nil and f.Shared["pts:20"].Pending ~= nil,
				"ambiguous journal orphaned participant pointers"
			)
			f.Data.AfterWrite = nil
			f:Restart()
			f:Recover()
			f:AssertSettled()
		end
	)
	H.test(
		"failed debit save keeps settlement pending and recovers from the last durable profile",
		function()
			local f = fixture()
			f.Data.BeforeSave = function(player)
				return if player.UserId == 10 then "PROFILE_SAVE_FAILED" else nil
			end
			local result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(
				result == nil and reason == "TRANSFER_SETTLEMENT_PENDING",
				"failed save retired settlement"
			)
			H.expect(
				f:Character(20).Economy.Balance == 50
					and f.Durable[10].Characters.sender.Economy.Balance == 100,
				"failed save credited recipient or altered durable sender"
			)
			H.expect(
				not f.Economy:Apply(f.Players[10], transaction("spend", 1)),
				"half-settled sender could spend"
			)
			f.Data.BeforeSave = nil
			f:Restart()
			f:Recover()
			f:AssertSettled()
		end
	)
	H.test(
		"ambiguous profile save cannot debit twice when recovery rebuilds the durable history",
		function()
			local f = fixture()
			f.Data.AfterSave = function(player)
				return if player.UserId == 10 then "PROFILE_SAVE_FAILED" else nil
			end
			local result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(
				result == nil
					and reason == "TRANSFER_SETTLEMENT_PENDING"
					and f.Durable[10].Characters.sender.Economy.Balance == 90,
				"ambiguous profile fixture did not commit"
			)
			f.Data.AfterSave = nil
			f:Restart()
			f:Recover()
			f:AssertSettled()
		end
	)
	H.test(
		"ambiguous settlement acknowledgement is idempotent after a simulated restart",
		function()
			local f = fixture()
			local journalWrites = 0
			f.Data.AfterWrite = function(key)
				if key == "ts:phone-operation" then
					journalWrites += 1
				end
				return if key == "ts:phone-operation" and journalWrites == 2
					then "SHARED_RECORD_UPDATE_FAILED"
					else nil
			end
			local result, reason = f.Economy:Transfer(f.Players[10], f.Players[20], 10, "operation")
			H.expect(
				result == nil
					and reason == "TRANSFER_SETTLEMENT_PENDING"
					and f.Shared["ts:phone-operation"].SenderSaved,
				"ambiguous acknowledgement fixture did not commit"
			)
			f.Data.AfterWrite = nil
			f:Restart()
			f:Recover()
			f:AssertSettled()
		end
	)
	H.test(
		"departure during participant reservation creates no money and missing-journal recovery clears pointers",
		function()
			local f = fixture()
			local recipient = f.Players[20]
			f.Data.AfterWrite = function(key)
				if key == "pts:20" then
					recipient.Parent = nil
					f.Players[20] = nil
				end
				return nil
			end
			local result, reason = f.Economy:Transfer(f.Players[10], recipient, 10, "operation")
			H.expect(
				result == nil
					and reason == "TRANSFER_RECOVERY_PENDING"
					and f.Shared["ts:phone-operation"] == nil,
				"departure committed a journal"
			)
			H.expect(
				f:Character(10).Economy.Balance == 100 and f:Character(20).Economy.Balance == 50,
				"departure moved money"
			)
			H.expect(next(f.Economy.transferring) == nil, "departure leaked transfer locks")
			f.Data.AfterWrite = nil
			local recovered = f.Economy:ReconcilePendingTransfers(f.Players[10], "sender")
			H.expect(
				recovered and f.Shared["pts:10"] == nil and f.Shared["pts:20"] == nil,
				"orphaned pointers did not drain"
			)
		end
	)
	H.test(
		"actual economy keeps settlement receipts bounded while preserving the newest replay",
		function()
			local f = fixture()
			for _, operation in { "aaa", "bbb", "ccc" } do
				local result, reason =
					f.Economy:Transfer(f.Players[10], f.Players[20], 1, operation)
				H.expect(result ~= nil and reason == nil, "bounded-receipt transfer failed")
			end
			local recent = f.Shared["pts:10"].Recent
			local count = 0
			for _ in recent do
				count += 1
			end
			H.expect(
				count == 2 and recent["phone-aaa"] == nil and recent["phone-ccc"] ~= nil,
				"receipt retention exceeded cap or lost current receipt"
			)
		end
	)
end
