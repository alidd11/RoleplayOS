--!strict
-- Run in a Rojo test place with this folder mapped as a container, or adapt these
-- specs to TestEZ. They deliberately exercise modules that have no server state.
local H = require(script.Parent.TestHarness)
local Shared = game:GetService("ReplicatedStorage").RoleplayOS.Shared
local Access = require(Shared.AccessEvaluator)
local RateLimiter = require(Shared.RateLimiter)
local Economy = require(Shared.EconomyValidator)
local SettlementPolicy = require(Shared.TransferSettlementPolicy)
local TaxiSettlementPolicy = require(Shared.TaxiSettlementPolicy)
local Characters = require(Shared.CharacterValidator)
local ConfigValidator = require(Shared.ConfigValidator)
local Registration = require(Shared.RegistrationGenerator)
local PropertyAccess = require(Shared.PropertyAccess)
local Placement = require(Shared.FurniturePlacementValidator)
local Serialisation = require(Shared.Serialisation)
local ProfileSchema = require(Shared.ProfileSchema)
local Response = require(Shared.Response)
local SpawnPolicy = require(Shared.SpawnPolicy)
local SettingsValidator = require(Shared.SettingsValidator)
local LevelProgression = require(Shared.LevelProgression)
local ProgressionVisibility = require(Shared.ProgressionVisibility)
local DispatchPolicy = require(Shared.DispatchPolicy)
local PhoneValidator = require(Shared.PhoneValidator)
local PayloadInspector = require(Shared.PayloadInspector)
local ResponseInspector = require(Shared.ResponseInspector)
local NetworkRetryPolicy = require(Shared.NetworkRetryPolicy)
local MoneyDropPolicy = require(Shared.MoneyDropPolicy)
local Coalescer = require(Shared.Coalescer)
local Fuel = require(Shared.FuelConsumption)
local Gangs = require(Shared.GangRules)
local EmergencyPatterns = require(Shared.EmergencyPatterns)
local OfficialServerPolicy = require(Shared.OfficialServerPolicy)
local Config = require(game:GetService("ReplicatedStorage").RoleplayOS.Config.Config)
local OfficialServerService =
	require(game:GetService("ServerScriptService").RoleplayOS.Services.OfficialServerService)
local IncidentService =
	require(game:GetService("ServerScriptService").RoleplayOS.Services.IncidentService)
local RecordIndexService =
	require(game:GetService("ServerScriptService").RoleplayOS.Services.RecordIndexService)
local WarrantService =
	require(game:GetService("ServerScriptService").RoleplayOS.Services.WarrantService)
local TaxiService = require(game:GetService("ServerScriptService").RoleplayOS.Services.TaxiService)

H.test("cash drops require bounded whole pound amounts", function()
	H.expect(MoneyDropPolicy.validateAmount(1, 1, 1000), "minimum cash drop refused")
	H.expect(MoneyDropPolicy.validateAmount(1000, 1, 1000), "maximum cash drop refused")
	local fractional, fractionalReason = MoneyDropPolicy.validateAmount(1.5, 1, 1000)
	H.expect(
		not fractional and fractionalReason == "WHOLE_AMOUNT_REQUIRED",
		"fractional drop accepted"
	)
	local excessive, excessiveReason = MoneyDropPolicy.validateAmount(1001, 1, 1000)
	H.expect(not excessive and excessiveReason == "DROP_TOO_LARGE", "oversized drop accepted")
	local nonFinite = MoneyDropPolicy.validateAmount(0 / 0, 1, 1000)
	H.expect(not nonFinite, "non-finite drop accepted")
end)
H.test("ambiguous taxi fare failures remain pending but definitive no-funds may cancel", function()
	H.expect(
		TaxiSettlementPolicy.shouldKeepFarePending(false, "TRANSFER_SETTLEMENT_PENDING"),
		"committed pending fare was treated as cancelled"
	)
	H.expect(
		TaxiSettlementPolicy.shouldKeepFarePending(false, "SHARED_RECORD_UPDATE_FAILED"),
		"ambiguous persistence failure was treated as cancelled"
	)
	H.expect(
		not TaxiSettlementPolicy.shouldKeepFarePending(false, "INSUFFICIENT_FUNDS"),
		"definitively unaffordable fare remained pending"
	)
	H.expect(
		not TaxiSettlementPolicy.shouldKeepFarePending(true, nil),
		"successful fare remained pending"
	)
end)
H.test("unresolved taxi fare cannot be cancelled", function()
	local request: any = {
		RequestId = "taxi-test",
		PassengerUserId = 10,
		DriverUserId = 20,
		State = "Accepted",
		SettlementPending = true,
	}
	local service: any = setmetatable({
		requests = { [request.RequestId] = request },
		completing = {},
		byPassenger = {},
		byDriver = {},
	}, { __index = TaxiService })
	local testPlayer: any = { UserId = 10 }
	local cancelled, reason = TaxiService.Cancel(service, testPlayer, request.RequestId)
	H.expect(not cancelled, "unresolved taxi fare was cancelled")
	H.expect(reason == "TAXI_SETTLEMENT_PENDING", "wrong unresolved fare refusal")
	H.expect(request.State == "Accepted", "unresolved journey became cancelled")
end)
H.test("old taxi settlement-pending bookings release bounded runtime claims", function()
	local request: any = {
		RequestId = "taxi-expired",
		PassengerUserId = 10,
		DriverUserId = 20,
		State = "Accepted",
		SettlementPending = true,
		SettlementPendingAt = 1,
	}
	local service: any = setmetatable({
		requests = { [request.RequestId] = request },
		byPassenger = { [10] = request.RequestId },
		byDriver = { [20] = request.RequestId },
		declined = {},
		settings = { MaximumRetainedTerminalRequests = 0 },
	}, { __index = TaxiService })
	TaxiService._trimTerminalRequests(service)
	H.expect(service.requests[request.RequestId] == nil, "pending taxi booking exceeded its bound")
	H.expect(service.byPassenger[10] == nil, "expired pending booking retained passenger claim")
	H.expect(service.byDriver[20] == nil, "expired pending booking retained driver claim")
end)
H.test("transfer settlement replay IDs and acknowledgement transitions are stable", function()
	H.expect(
		SettlementPolicy.transactionId("transfer-1", "debit")
			== SettlementPolicy.transactionId("transfer-1", "debit"),
		"retry changed the sender settlement transaction ID"
	)
	local status, senderSaved, recipientSaved =
		SettlementPolicy.acknowledge("Committed", false, false, "Sender")
	H.expect(
		status == "Committed" and senderSaved == true and recipientSaved ~= true,
		"first leg settled early"
	)
	status, senderSaved, recipientSaved = SettlementPolicy.acknowledge(
		status :: string,
		senderSaved :: boolean,
		recipientSaved :: boolean,
		"Sender"
	)
	H.expect(
		status == "Committed" and senderSaved == true,
		"replayed sender ack changed settlement"
	)
	status, senderSaved, recipientSaved = SettlementPolicy.acknowledge(
		status :: string,
		senderSaved :: boolean,
		recipientSaved :: boolean,
		"Recipient"
	)
	H.expect(
		status == "Settled" and senderSaved == true and recipientSaved == true,
		"second durable leg did not settle"
	)
	local invalidStatus = SettlementPolicy.acknowledge("Preparing", false, false, "Sender")
	H.expect(invalidStatus == nil, "preparing settlement accepted a profile acknowledgement")
	local receipt = {
		TransferId = "transfer-1",
		SenderCharacterId = "sender-char",
		RecipientUserId = 20,
		RecipientCharacterId = "recipient-char",
		Amount = 50,
		Kind = "PlayerTransfer",
	}
	H.expect(
		SettlementPolicy.receiptMatches(
			receipt,
			"transfer-1",
			"sender-char",
			20,
			"recipient-char",
			50,
			"PlayerTransfer"
		),
		"matching operation receipt was not recognised"
	)
	H.expect(
		not SettlementPolicy.receiptMatches(
			receipt,
			"transfer-1",
			"sender-char",
			20,
			"recipient-char",
			51,
			"PlayerTransfer"
		),
		"operation ID was accepted with a conflicting amount"
	)
end)

H.test("cash drops have per-player and server population limits", function()
	H.expect(Config.MoneyDrops.MaximumActivePerPlayer > 0, "per-player drop limit missing")
	H.expect(
		Config.MoneyDrops.MaximumActiveGlobal >= Config.MoneyDrops.MaximumActivePerPlayer,
		"global drop limit is smaller than the per-player limit"
	)
end)

H.test("public access is granted", function()
	H.expect(Access.evaluate({ AccessType = "Public" }, {}).Allowed, "public denied")
end)
H.test("gamepass access returns useful denial", function()
	local result = Access.evaluate(
		{ AccessType = "Gamepass", GamepassId = 12 },
		{ Gamepasses = {} }
	)
	H.expect(not result.Allowed and result.ReasonCode == "GAMEPASS_REQUIRED", "wrong denial")
end)
H.test("public-only access is restricted by server kind", function()
	local rule = { AccessType = "ServerKind", Kind = "Public" }
	H.expect(Access.evaluate(rule, { ServerKind = "Public" }).Allowed, "public denied")
	local private = Access.evaluate(rule, { ServerKind = "Private" })
	H.expect(
		not private.Allowed and private.ReasonCode == "SERVER_KIND_REQUIRED",
		"private server bypassed public-only access"
	)
end)
H.test("official server registry enforces its cap in the shared-record transform", function()
	local first = OfficialServerPolicy.appendInstance(nil, "code-one", 2, "Community", 100)
	local second, secondIndex =
		OfficialServerPolicy.appendInstance(first, "code-two", 2, "Community", 101)
	H.expect(secondIndex == 2, "second reserved instance was not appended")
	local capped, cappedIndex, cappedReason =
		OfficialServerPolicy.appendInstance(second, "code-three", 2, "Community", 102)
	H.expect(
		cappedIndex == nil and cappedReason == "OFFICIAL_SERVER_FULL",
		"instance cap was exceeded"
	)
	H.expect(#capped.Instances == 2, "capped transform changed the registry")
end)
H.test("official server registry append is idempotent and preserves legacy access codes", function()
	local legacy = { AccessCode = "legacy-code" }
	local migrated, legacyIndex =
		OfficialServerPolicy.appendInstance(legacy, "new-code", 3, "Community", 100)
	H.expect(legacyIndex == 2 and migrated.Instances[1] == "legacy-code", "legacy code was lost")
	local retried, retryIndex =
		OfficialServerPolicy.appendInstance(migrated, "new-code", 3, "Community", 101)
	H.expect(retryIndex == 2 and #retried.Instances == 2, "retry duplicated a reserved instance")
end)

H.test(
	"official server list reports a shared-record read failure instead of a new-server row",
	function()
		local service: any = setmetatable({
			settings = {
				Enabled = true,
				Entries = {
					Harbour = {
						Id = "Harbour",
						Name = "Harbour",
						Reserved = true,
					},
				},
			},
			_storedInstanceCodes = function()
				return {}, "OFFICIAL_SERVER_UNAVAILABLE"
			end,
			_isHere = function()
				return false
			end,
		}, { __index = OfficialServerService })

		local rows, reason = OfficialServerService.List(service)
		H.expect(rows == nil, "failed shared-record read returned an empty-server placeholder")
		H.expect(
			reason == "OFFICIAL_SERVER_UNAVAILABLE",
			"shared-record failure was not propagated"
		)
	end
)
H.test("official directory reports cold read failures and reuses its last good snapshot", function()
	local cached = { Servers = {}, PublicServers = {} }
	local service: any = setmetatable({
		settings = { DirectoryCacheSeconds = 1 },
		context = { Configuration = { Network = { HandlerTimeoutSeconds = 8 } } },
		directoryCache = nil,
		directoryCacheExpiresAt = 0,
		directoryRefresh = nil,
		ListPublicInstances = function()
			return {}, nil
		end,
		List = function()
			return nil, "OFFICIAL_SERVER_UNAVAILABLE"
		end,
	}, { __index = OfficialServerService })

	local snapshot, reason = OfficialServerService.Directory(service)
	H.expect(snapshot == nil, "cold directory refresh cached an incomplete snapshot")
	H.expect(reason == "OFFICIAL_SERVER_UNAVAILABLE", "cold directory failure was hidden")

	service.directoryCache = cached
	service.directoryCacheExpiresAt = 0
	snapshot, reason = OfficialServerService.Directory(service)
	H.expect(snapshot == cached, "failed refresh did not reuse the last good snapshot")
	H.expect(reason == nil, "last good snapshot returned with an error")
end)
H.test("server-tier access preserves the actionable public gamepass denial", function()
	local result = Access.evaluate({
		AccessType = "Combined",
		Match = "Any",
		Rules = {
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kind = "Public" },
					{ AccessType = "Gamepass", GamepassId = 12 },
				},
			},
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kinds = { "Whitelisted", "Private" } },
					{ AccessType = "Group", GroupLinkId = "Police" },
				},
			},
		},
	}, {
		ServerKind = "Public",
		Gamepasses = {},
		Groups = {},
	})
	H.expect(
		not result.Allowed
			and result.ReasonCode == "GAMEPASS_REQUIRED"
			and result.Metadata.GamepassId == 12,
		"public gamepass denial was hidden by another server tier"
	)
end)
H.test("server-tier access preserves the actionable whitelisted group denial", function()
	local result = Access.evaluate({
		AccessType = "Combined",
		Match = "Any",
		Rules = {
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kind = "Public" },
					{ AccessType = "Gamepass", GamepassId = 12 },
				},
			},
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kinds = { "Whitelisted", "Private" } },
					{ AccessType = "Group", GroupLinkId = "Police" },
				},
			},
		},
	}, {
		ServerKind = "Whitelisted",
		Gamepasses = {},
		Groups = {},
	})
	H.expect(
		not result.Allowed and result.ReasonCode == "GROUP_CHECK_FAILED",
		"whitelisted group denial was hidden by another server tier"
	)
end)
H.test("a Combined rule with nothing to combine fails closed", function()
	-- An All rule reached the unconditional allow at the end of the Combined
	-- branch simply because the loop never ran, so a config typo opened the gate.
	for _, rule in
		{
			{ AccessType = "Combined", Match = "All", Rules = {} },
			{ AccessType = "Combined", Match = "All" },
			{ AccessType = "Combined", Match = "Alll", Rules = {} },
			{ AccessType = "Combined", Rules = {} },
		}
	do
		local result =
			Access.evaluate(rule, { ServerKind = "Public", Gamepasses = {}, Groups = {} })
		H.expect(not result.Allowed, "an empty Combined rule granted access")
	end
	-- A populated All rule still has to work.
	local satisfied = Access.evaluate({
		AccessType = "Combined",
		Match = "All",
		Rules = { { AccessType = "Public" }, { AccessType = "ServerKind", Kind = "Public" } },
	}, { ServerKind = "Public" })
	H.expect(satisfied.Allowed, "a satisfied All rule was denied")
end)
H.test("Roblox group access enforces membership and rank", function()
	local rule = { AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 10 }
	local denied = Access.evaluate(rule, {
		Groups = { Police = { GroupId = 123, IsMember = true, HighestRank = 5 } },
	})
	H.expect(
		not denied.Allowed and denied.ReasonCode == "GROUP_RANK_REQUIRED",
		"low group rank allowed"
	)
	local allowed = Access.evaluate(rule, {
		Groups = { Police = { GroupId = 123, IsMember = true, HighestRank = 10 } },
	})
	H.expect(allowed.Allowed, "qualifying group rank denied")
end)
H.test("unconfigured Roblox group fails closed", function()
	local result = Access.evaluate({ AccessType = "Group", GroupLinkId = "Police" }, {
		Groups = { Police = { GroupId = 0, NotConfigured = true } },
	})
	H.expect(
		not result.Allowed and result.ReasonCode == "GROUP_NOT_CONFIGURED",
		"unconfigured group allowed"
	)
end)
H.test("suspension overrides public access", function()
	H.expect(
		Access.evaluate({ AccessType = "Public" }, { Suspended = true }).ReasonCode == "SUSPENDED",
		"suspension bypassed"
	)
end)
H.test("token bucket limits and refills", function()
	local now = 0
	local limiter = RateLimiter.new(2, 1, function()
		return now
	end)
	H.expect(limiter:Allow("a") and limiter:Allow("a") and not limiter:Allow("a"), "capacity wrong")
	now = 1
	H.expect(limiter:Allow("a"), "did not refill")

	local reconnectNow = 0
	local reconnectLimiter = RateLimiter.new(1, 0, function()
		return reconnectNow
	end, 10)
	H.expect(reconnectLimiter:Allow("user"), "initial request was rate limited")
	H.expect(not reconnectLimiter:Allow("user"), "same user unexpectedly received a new bucket")
	reconnectNow = 31
	H.expect(reconnectLimiter:Allow("user"), "expired reconnect bucket was not pruned")
end)
H.test("remote payload inspector rejects abusive structures", function()
	H.expect(PayloadInspector.validate({ Message = "safe", Count = 2 }), "safe payload rejected")
	H.expect(not PayloadInspector.validate({ Value = math.huge }), "infinite number accepted")
	H.expect(
		not PayloadInspector.validate({ Value = string.rep("x", 20) }, { MaximumStringBytes = 10 }),
		"oversized string accepted"
	)
	local cyclic = {}
	cyclic.Self = cyclic
	H.expect(not PayloadInspector.validate(cyclic), "cyclic table accepted")
end)
H.test("remote response inspector bounds data while preserving waypoints", function()
	H.expect(
		ResponseInspector.validate({ PickupPosition = Vector3.new(1, 2, 3), Name = "Taxi" }),
		"safe Vector3 response rejected"
	)
	H.expect(not ResponseInspector.validate({ Value = math.huge }), "infinite response accepted")
	H.expect(
		not ResponseInspector.validate(
			{ Value = string.rep("x", 20) },
			{ MaximumResponseStringBytes = 10 }
		),
		"oversized response string accepted"
	)
	local cyclic = {}
	cyclic.Self = cyclic
	H.expect(not ResponseInspector.validate(cyclic), "cyclic response accepted")
	local instance = Instance.new("Folder")
	H.expect(not ResponseInspector.validate({ Value = instance }), "Instance response accepted")
	instance:Destroy()
end)
H.test("bank transfer retries retain their key after ambiguous network failures", function()
	for _, code in
		{
			"SERVER_TIMEOUT",
			"SERVER_ERROR",
			"SERVER_BUSY",
			"REQUEST_TIMEOUT",
			"NETWORK_ERROR",
			"TRANSFER_IN_PROGRESS",
			"TRANSFER_SETTLEMENT_PENDING",
			"TRANSFER_RECOVERY_PENDING",
			"UNRECOGNISED_FAILURE",
		}
	do
		H.expect(
			NetworkRetryPolicy.shouldRetainBankTransferId(false, code),
			"ambiguous failure discarded its bank transfer id: " .. code
		)
	end
	H.expect(
		not NetworkRetryPolicy.shouldRetainBankTransferId(false, "INSUFFICIENT_FUNDS"),
		"definitive bank transfer failure retained its key"
	)
	H.expect(
		not NetworkRetryPolicy.shouldRetainBankTransferId(true, "OK"),
		"successful bank transfer retained its key"
	)
end)
H.test("ambiguous bank transfer retries cannot change transaction details", function()
	H.expect(
		NetworkRetryPolicy.canReusePendingBankTransfer(nil, "alice:50"),
		"a new bank transfer was blocked"
	)
	H.expect(
		NetworkRetryPolicy.canReusePendingBankTransfer("alice:50", "alice:50"),
		"retrying the original bank transfer was blocked"
	)
	H.expect(
		not NetworkRetryPolicy.canReusePendingBankTransfer("alice:50", "bob:50"),
		"ambiguous transfer allowed a changed recipient"
	)
	H.expect(
		not NetworkRetryPolicy.canReusePendingBankTransfer("alice:50", "alice:75"),
		"ambiguous transfer allowed a changed amount"
	)
end)
H.test("economy rejects unsafe amounts", function()
	H.expect(
		not Economy.amount(0) and not Economy.amount(0 / 0) and not Economy.amount(math.huge),
		"unsafe amount accepted"
	)
end)
H.test("economy prevents duplicates and overdrafts", function()
	local tx = { TransactionId = "tx", Amount = 101, Direction = "Debit" }
	H.expect(
		select(2, Economy.transaction(tx, {}, 100)) == "INSUFFICIENT_FUNDS",
		"overdraft accepted"
	)
	H.expect(
		select(2, Economy.transaction(tx, { tx = true }, 200)) == "DUPLICATE_TRANSACTION",
		"duplicate accepted"
	)
end)
H.test("economy defaults to bank and accepts only named accounts", function()
	H.expect(
		select(1, Economy.account(nil)) == "Bank",
		"legacy transaction did not default to bank"
	)
	H.expect(select(1, Economy.account("Bank")) == "Bank", "bank account rejected")
	H.expect(select(1, Economy.account("Cash")) == "Cash", "cash account rejected")
	H.expect(select(2, Economy.account("Wallet")) == "INVALID_ACCOUNT", "unknown account accepted")
	local valid, reason = Economy.transaction({
		TransactionId = "cash-tx",
		Amount = 1,
		Direction = "Credit",
		Account = "Cash",
	}, {}, 0)
	H.expect(valid and reason == nil, "cash transaction rejected")
end)
H.test("profile migration reconciles carried cash", function()
	local profile = ProfileSchema.migrate({
		SchemaVersion = 9,
		Characters = { old = { Economy = { Balance = 10, Transactions = {} } } },
	}, 10)
	H.expect(profile.SchemaVersion == 11, "profile schema did not advance")
	H.expect(profile.Characters.old.Economy.Cash == 0, "missing carried cash was not reconciled")
end)
H.test("profile migration fails closed on corrupt persisted collections", function()
	local characters, charactersReason = ProfileSchema.migrate({
		SchemaVersion = ProfileSchema.CURRENT_VERSION,
		Characters = "corrupt",
	}, 10)
	H.expect(
		characters == nil and charactersReason == "PROFILE_CHARACTERS_NOT_TABLE",
		"corrupt characters were replaced instead of quarantined"
	)

	local applications, applicationsReason = ProfileSchema.migrate({
		SchemaVersion = ProfileSchema.CURRENT_VERSION,
		Applications = 42,
	}, 10)
	H.expect(
		applications == nil and applicationsReason == "PROFILE_APPLICATIONS_NOT_TABLE",
		"corrupt applications were replaced instead of quarantined"
	)
end)
H.test("profile migration fails closed on corrupt economy containers", function()
	local economy, economyReason = ProfileSchema.migrate({
		SchemaVersion = 9,
		Characters = { one = { Economy = "corrupt" } },
	}, 10)
	H.expect(
		economy == nil and economyReason == "PROFILE_ECONOMY_NOT_TABLE",
		"corrupt economy was replaced"
	)

	local transactions, transactionsReason = ProfileSchema.migrate({
		SchemaVersion = 9,
		Characters = { one = { Economy = { Balance = 10, Cash = 5, Transactions = "corrupt" } } },
	}, 10)
	H.expect(
		transactions == nil and transactionsReason == "PROFILE_ECONOMY_TRANSACTIONS_NOT_TABLE",
		"corrupt transaction history was replaced"
	)

	local refunds, refundsReason = ProfileSchema.migrate({
		SchemaVersion = 13,
		Characters = {
			one = {
				Economy = {
					Balance = 10,
					Cash = 5,
					Transactions = {},
					PendingCashDropRefunds = "corrupt",
				},
			},
		},
	}, 10)
	H.expect(
		refunds == nil and refundsReason == "PROFILE_PENDING_CASH_REFUNDS_NOT_TABLE",
		"corrupt pending refund queue was replaced"
	)
end)
H.test("character identity validates age and names", function()
	local valid = Characters.identity(
		{ FirstName = "Alice", LastName = "Jones", DateOfBirth = "1990-02-10" },
		DateTime.fromUniversalTime(2026, 1, 1),
		16,
		100
	)
	H.expect(valid, "valid identity rejected")
end)
H.test("configuration is coherent", function()
	local valid, errors = ConfigValidator.validate(Config)
	H.expect(valid, table.concat(errors, "; "))
end)
H.test("dispatch operational-note limits are finite and bounded", function()
	for _, value in { -1, 1.5, 201, 0 / 0, math.huge } do
		local candidate = table.clone(Config)
		candidate.Dispatch = table.clone(Config.Dispatch)
		candidate.Dispatch.MaximumOperationalNotes = value
		local valid = ConfigValidator.validate(candidate)
		H.expect(not valid, "accepted invalid operational-note limit " .. tostring(value))
	end
	H.expect(DispatchPolicy.operationalNoteLimit(-1) == 0, "negative note limit was not clamped")
	H.expect(
		DispatchPolicy.operationalNoteLimit(math.huge) == 200,
		"infinite note limit was unbounded"
	)
	H.expect(
		DispatchPolicy.operationalNoteLimit("invalid") == 50,
		"invalid note limit lost fallback"
	)
end)
H.test("economy transaction and transfer receipt histories are bounded", function()
	local candidate = table.clone(Config)
	candidate.Economy = table.clone(Config.Economy)
	candidate.Economy.MaximumTransferReceipts = 0
	local valid = ConfigValidator.validate(candidate)
	H.expect(not valid, "accepted an unbounded transfer receipt configuration")
	candidate.Economy.MaximumTransferReceipts = 10.5
	valid = ConfigValidator.validate(candidate)
	H.expect(not valid, "accepted a fractional transfer receipt bound")
end)
H.test("configuration rejects unsafe persistence timings", function()
	local function withFrameworkPatch(patch: any): any
		local candidate = table.clone(Config)
		candidate.Framework = table.clone(Config.Framework)
		for key, value in patch do
			candidate.Framework[key] = value
		end
		return candidate
	end

	local malformed = table.clone(Config)
	malformed.Framework = "invalid"
	local malformedValid = ConfigValidator.validate(malformed)
	H.expect(not malformedValid, "malformed Framework section raised or passed validation")

	for _, case in
		{
			{ { AutosaveSeconds = 0 }, "zero autosave interval" },
			{ { ShutdownSaveSeconds = 0 }, "zero shutdown save window" },
			{ { MaxSaveAttempts = 0 }, "zero save attempts" },
			{ { JoinLoadAttempts = 0 }, "zero load attempts" },
			{
				{ SessionLeaseSeconds = Config.Framework.AutosaveSeconds * 2 - 1 },
				"short session lease",
			},
			{
				{ MaximumLeaseWaitSeconds = Config.Framework.SessionLeaseSeconds },
				"lease wait as long as the lease",
			},
			{ { SessionHandoverSeconds = 0 }, "zero handover wait" },
			{ { SessionHandoverSeconds = "invalid" }, "non-numeric handover wait" },
			{ { ProfileSizeWarningBytes = 4 * 1024 * 1024 }, "late profile-size warning" },
		}
	do
		local valid = ConfigValidator.validate(withFrameworkPatch(case[1]))
		H.expect(not valid, "accepted " .. case[2])
	end
end)
H.test("bank robbery economy is bounded and mode agnostic", function()
	local robbery = Config.BankRobbery
	H.expect(type(robbery.Tag) == "string" and robbery.Tag ~= "", "bank robbery tag missing")
	H.expect(robbery.MinimumReward > 0, "bank robbery minimum reward invalid")
	H.expect(robbery.MaximumReward >= robbery.MinimumReward, "bank robbery reward range invalid")
	H.expect(robbery.RobberyDurationSeconds > 0, "bank robbery duration invalid")
	H.expect(robbery.ServerKinds == nil, "bank robbery was restricted to one server mode")
end)
H.test("civilian dealerships cannot expose service vehicles", function()
	for dealershipId, dealership in Config.Dealerships do
		local seen = {}
		for _, vehicleId in dealership.VehicleIds do
			local vehicle = Config.Vehicles[vehicleId]
			H.expect(vehicle ~= nil, "unknown dealership vehicle " .. vehicleId)
			H.expect(
				vehicle.Category == "Civilian",
				"service vehicle leaked into dealership " .. dealershipId
			)
			H.expect(not seen[vehicleId], "duplicate dealership vehicle " .. vehicleId)
			seen[vehicleId] = true
		end
	end
end)
H.test("service vehicles have coherent department and division routing", function()
	for vehicleId, vehicle in Config.Vehicles do
		if vehicle.Category == "Service" then
			H.expect(
				Config.Departments[vehicle.DepartmentId] ~= nil,
				"service vehicle has no department " .. vehicleId
			)
			if vehicle.DivisionId then
				local division = Config.Divisions[vehicle.DivisionId]
				H.expect(
					division and division.DepartmentId == vehicle.DepartmentId,
					"vehicle division routes to another department " .. vehicleId
				)
			end
		end
	end
end)
H.test("Universal Projects production group links are configured", function()
	H.expect(
		Config.ExperienceAccess.RequiredGroupLinkId == "UniversalProjects",
		"entry group missing"
	)
	H.expect(Config.GroupLinks.UniversalProjects.GroupId == 33809042, "wrong main group")
	H.expect(Config.GroupLinks.Police.GroupId == 34720334, "wrong police group")
	H.expect(Config.GroupLinks.ArmedResponse.GroupId == 16985274, "wrong armed response group")
	H.expect(Config.GroupLinks.RoadsPolicing.GroupId == 33815770, "wrong roads policing group")
	H.expect(Config.GroupLinks.Ambulance.GroupId == 33840360, "wrong ambulance group")
	H.expect(Config.GroupLinks.Fire.GroupId == 14293067, "wrong fire group")
	H.expect(Config.GroupLinks.Transport.GroupId == 33360488, "wrong transport group")
	H.expect(Config.GroupLinks.Highways.GroupId == 34022475, "wrong highways group")
	H.expect(Config.GroupLinks.Prison.GroupId == 16361786, "wrong prison group")
end)
H.test("registration has stable display shape", function()
	H.expect(
		string.match(Registration.generate(Random.new(42)), "^%u%u%d%d %u%u%u$") ~= nil,
		"bad registration"
	)
end)
H.test("property owner and keyholder access", function()
	local holding = { CharacterId = "owner", AccessCharacterIds = { "guest" } }
	H.expect(
		PropertyAccess.canEnter(holding, "owner")
			and PropertyAccess.canEnter(holding, "guest")
			and not PropertyAccess.canEnter(holding, "stranger"),
		"property rules wrong"
	)
end)
H.test("furniture bounds reject escaped placement", function()
	H.expect(
		Placement.validate(
			{ Position = { 5, 1, 5 }, Rotation = { 0, 0, 0 } },
			Vector3.zero,
			Vector3.new(10, 10, 10),
			Vector3.new(2, 2, 2)
		),
		"valid placement rejected"
	)
	H.expect(
		not Placement.validate(
			{ Position = { 10, 1, 5 }, Rotation = { 0, 0, 0 } },
			Vector3.zero,
			Vector3.new(10, 10, 10),
			Vector3.new(2, 2, 2)
		),
		"escaped placement accepted"
	)
end)
H.test("serialisation round trips CFrame", function()
	local original = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0)
	local restored = Serialisation.toCFrame(Serialisation.cframe(original))
	H.expect(
		restored ~= nil and (restored.Position - original.Position).Magnitude < 0.001,
		"round trip failed"
	)
end)
H.test("migration reconciles missing fields", function()
	local profile = ProfileSchema.migrate({ SchemaVersion = 0 }, 42)
	H.expect(
		profile.SchemaVersion == ProfileSchema.CURRENT_VERSION
			and profile.UserId == 42
			and type(profile.Characters) == "table"
			and type(profile.Communities) == "table",
		"migration failed"
	)
end)

H.test("profile migration fails closed on unreadable authoritative state", function()
	local invalidVersion, invalidVersionReason = ProfileSchema.migrate({
		SchemaVersion = "corrupt",
	}, 42)
	H.expect(
		invalidVersion == nil and invalidVersionReason == "PROFILE_VERSION_INVALID",
		"invalid schema version was treated as a legacy profile"
	)

	local custody, custodyReason = ProfileSchema.migrate({
		SchemaVersion = 8,
		CustodySentence = "corrupt",
	}, 42)
	H.expect(
		custody == nil and custodyReason == "PROFILE_CUSTODY_SENTENCE_NOT_TABLE",
		"corrupt custody state was replaced"
	)

	local invites, invitesReason = ProfileSchema.migrate({
		SchemaVersion = 12,
		GangInvites = "corrupt",
	}, 42)
	H.expect(
		invites == nil and invitesReason == "PROFILE_GANG_INVITES_NOT_TABLE",
		"corrupt gang invites were replaced"
	)
end)
H.test("profile migration preserves unreadable authoritative scalar state", function()
	local cases = {
		{
			{
				SchemaVersion = 8,
				CustodySentence = { ReleaseAt = "corrupt" },
			},
			"PROFILE_CUSTODY_RELEASE_AT_INVALID",
		},
		{
			{
				SchemaVersion = 8,
				CustodySentence = { ReleaseAt = 0, RemainingSeconds = "corrupt" },
			},
			"PROFILE_CUSTODY_REMAINING_SECONDS_INVALID",
		},
		{
			{
				SchemaVersion = 9,
				Characters = { character = { Economy = { Balance = "corrupt", Cash = 0 } } },
			},
			"PROFILE_ECONOMY_BALANCE_INVALID",
		},
		{
			{
				SchemaVersion = 9,
				Characters = { character = { Economy = { Balance = 0, Cash = "corrupt" } } },
			},
			"PROFILE_ECONOMY_CASH_INVALID",
		},
		{
			{
				SchemaVersion = 10,
				Consumables = { EarlyReleaseCredits = "corrupt" },
			},
			"PROFILE_EARLY_RELEASE_CREDITS_INVALID",
		},
		{
			{
				SchemaVersion = 11,
				Consumables = { AppearanceEdits = "corrupt" },
			},
			"PROFILE_APPEARANCE_EDITS_INVALID",
		},
	}

	for _, case in cases do
		local migrated, reason = ProfileSchema.migrate(case[1], 42)
		H.expect(migrated == nil and reason == case[2], case[2] .. " was silently normalised")
	end
end)
H.test("profile migration still backfills missing authoritative scalar state", function()
	local custody = ProfileSchema.migrate({
		SchemaVersion = 8,
		CustodySentence = {},
	}, 42)
	H.expect(
		custody.CustodySentence.RemainingSeconds == 0,
		"missing legacy custody state was not backfilled"
	)

	local economy = ProfileSchema.migrate({
		SchemaVersion = 9,
		Characters = { character = { Economy = {} } },
	}, 42)
	H.expect(
		economy.Characters.character.Economy.Balance == 0
			and economy.Characters.character.Economy.Cash == 0,
		"missing legacy economy state was not backfilled"
	)

	local consumables = ProfileSchema.migrate({
		SchemaVersion = 10,
		Consumables = {},
	}, 42)
	H.expect(
		consumables.Consumables.EarlyReleaseCredits == 0
			and consumables.Consumables.AppearanceEdits == 0,
		"missing legacy consumable state was not backfilled"
	)
end)
H.test("profile migration preserves developer receipt replay protection", function()
	local consumables, consumablesReason = ProfileSchema.migrate({
		SchemaVersion = 10,
		Consumables = "corrupt",
	}, 42)
	H.expect(
		consumables == nil and consumablesReason == "PROFILE_CONSUMABLES_NOT_TABLE",
		"corrupt consumables were replaced"
	)

	local receipts, receiptsReason = ProfileSchema.migrate({
		SchemaVersion = 10,
		Consumables = { ProcessedDeveloperReceipts = "corrupt" },
	}, 42)
	H.expect(
		receipts == nil and receiptsReason == "PROFILE_DEVELOPER_RECEIPTS_NOT_TABLE",
		"corrupt developer receipt history was replaced"
	)
end)
H.test("migration adds bounded cash-drop recovery state", function()
	local profile = ProfileSchema.migrate({
		SchemaVersion = 13,
		Characters = {
			character = {
				Economy = {
					Balance = 100,
					Cash = 50,
					Transactions = {},
				},
			},
		},
	}, 42)
	H.expect(
		profile.SchemaVersion == ProfileSchema.CURRENT_VERSION,
		"profile version did not advance"
	)
	H.expect(
		type(profile.Characters.character.Economy.PendingCashDropRefunds) == "table",
		"cash-drop recovery container missing"
	)
end)
H.test("migration preserves pending registration swap recovery", function()
	local profile = ProfileSchema.migrate({
		SchemaVersion = ProfileSchema.CURRENT_VERSION,
		Characters = {
			character = {
				Vehicles = {
					{
						VehicleId = "vehicle-1",
						Registration = "AB12 CDE",
						PendingRegistrationSwap = {
							OperationId = "swap-1",
							FromRegistration = "AB12 CDE",
							ToRegistration = "XY34 ZZZ",
							State = "Prepared",
							PreparedAt = 123,
						},
					},
				},
			},
		},
	}, 42)
	local pending = profile.Characters.character.Vehicles[1].PendingRegistrationSwap
	H.expect(
		type(pending) == "table"
			and pending.OperationId == "swap-1"
			and pending.FromRegistration == "AB12 CDE"
			and pending.ToRegistration == "XY34 ZZZ"
			and pending.State == "Prepared",
		"registration swap recovery marker was dropped during migration"
	)
end)
H.test("settings reject unknown and invalid values", function()
	H.expect(
		SettingsValidator.validatePatch({ InterfaceScale = "Large" }) ~= nil,
		"valid scale rejected"
	)
	H.expect(
		SettingsValidator.validatePatch({ InterfaceScale = "Huge" }) == nil,
		"invalid scale accepted"
	)
	H.expect(SettingsValidator.validatePatch({ Exploit = true }) == nil, "unknown setting accepted")
end)
H.test("level progression handles boundaries and maximum level", function()
	local levelTwo = LevelProgression.xpForLevel(2, 100, 1.18)
	H.expect(levelTwo == 100, "level two threshold is wrong")
	local summary = LevelProgression.fromXp(levelTwo, 100, 1.18, 100)
	H.expect(summary.Level == 2 and summary.CurrentLevelXP == 0, "threshold did not level up")
	local maximumXp = LevelProgression.xpForLevel(100, 100, 1.18)
	local maximum = LevelProgression.fromXp(maximumXp, 100, 1.18, 100)
	H.expect(maximum.Level == 100 and maximum.AtMaximumLevel, "maximum level was not capped")
end)
H.test("progression HUD is restricted to public non-whitelisted teams", function()
	H.expect(
		ProgressionVisibility.isPublicHudAllowed("Public", { AutoAssignable = true }),
		"public civilian team was hidden"
	)
	H.expect(
		not ProgressionVisibility.isPublicHudAllowed("Public", { AutoAssignable = false }),
		"whitelisted team received the public HUD"
	)
	H.expect(
		ProgressionVisibility.isPublicHudAllowed("Whitelisted", { AutoAssignable = true }),
		"whitelisted server did not apply the expected public-team rule"
	)
	H.expect(
		not ProgressionVisibility.isPublicHudAllowed("Whitelisted", { AutoAssignable = false }),
		"whitelisted team received the public HUD on a group whitelisted server"
	)
end)
H.test("spawn policy binds role to exact station point", function()
	local allowed = SpawnPolicy.validate(
		Config.Stations,
		Config.Spawns,
		"CityCentre",
		"PoliceLockerRoom",
		"PoliceFrontline",
		"Police"
	)
	H.expect(allowed, "valid frontline spawn rejected")
	local invalid, reason = SpawnPolicy.validate(
		Config.Stations,
		Config.Spawns,
		"CityCentre",
		"FireLockerRoom",
		"PoliceFrontline",
		"Police"
	)
	H.expect(not invalid and reason == "SPAWN_ROLE_NOT_ALLOWED", "cross-service spawn allowed")
end)
H.test("response envelope contains contract fields", function()
	local response = Response.ok({ value = 1 }, "req")
	H.expect(
		response.Success and response.Code == "OK" and response.RequestId == "req",
		"bad response"
	)
end)
H.test("dispatch policy requires authorised duty and a dispatch seat", function()
	local duty = { DepartmentId = "Control" }
	H.expect(
		DispatchPolicy.canUseMdt(duty, { "Police", "Control" }),
		"authorised duty was denied MDT access"
	)
	H.expect(
		DispatchPolicy.canDispatch(duty, { "Control" }, true),
		"controller in a dispatch seat was denied"
	)
	H.expect(
		not DispatchPolicy.canDispatch(duty, { "Control" }, false),
		"dispatch was available away from a console"
	)
end)
H.test("phone validation normalises UK mobile numbers and bounds messages", function()
	H.expect(PhoneValidator.number("07123 456 789") == "07123456789", "phone was not normalised")
	H.expect(PhoneValidator.number("999") == nil, "emergency number was accepted as a mobile")
	H.expect(PhoneValidator.message(" hello ", 20) == "hello", "message was not trimmed")
	H.expect(PhoneValidator.message(string.rep("a", 21), 20) == nil, "long message accepted")
	H.expect(
		#PhoneValidator.numberFromCharacterId("abcdef12-3456") == 11,
		"generated number invalid"
	)
end)
H.test("a burst of refresh requests collapses into one trailing run", function()
	local runs = 0
	local coalescer = Coalescer.new(0.1, function()
		runs += 1
	end)
	-- The first is answered at once, so a panel never sits stale waiting out an
	-- interval before it draws anything.
	coalescer:Request()
	H.expect(runs == 1, "the first request did not run immediately")
	-- A burst during the interval is the case this exists for: four dispatch
	-- changes inside a second must cost one refresh, not four.
	coalescer:Request()
	coalescer:Request()
	coalescer:Request()
	H.expect(runs == 1, "a request inside the interval ran immediately")
	task.wait(0.25)
	H.expect(runs == 2, string.format("expected one trailing run, saw %d in total", runs))
	-- The last change of a burst must not be dropped. Leading-edge-only throttling
	-- would leave the panel showing state that is no longer true.
	coalescer:Request()
	H.expect(runs == 3, "a request after the interval had elapsed did not run")

	-- Cancelled means cancelled: a trailing run must not fire against interface
	-- that has already been torn down.
	coalescer:Request()
	coalescer:Cancel()
	task.wait(0.25)
	H.expect(runs == 3, "a cancelled coalescer still fired its trailing run")
end)

H.test("a mile is derived from the speed conversion, not invented", function()
	local K = Config.VehicleData.StudsPerSecondToMph
	-- A vehicle at K mph covers one stud a second, so an hour covers 3600 studs.
	H.expect(
		math.abs(Fuel.studsPerMile(K) - 3600 / K) < 1e-9,
		"studs per mile does not follow from K"
	)
	H.expect(
		math.abs(Fuel.miles(Fuel.studsPerMile(K), K) - 1) < 1e-9,
		"one mile of studs is not one mile"
	)
	H.expect(Fuel.miles(0, K) == 0, "standing still covered distance")
	H.expect(Fuel.miles(-500, K) == 0, "negative displacement covered distance")
end)

H.test("the teleport guard allows a vehicle driven at the top of the dial", function()
	local settings = Config.VehicleData
	local K = settings.StudsPerSecondToMph
	local dt = settings.ConsumptionIntervalSeconds
	-- The distance a vehicle actually covers in one tick at the dial's top speed.
	local atTopSpeed = (settings.TopSpeedMphCeiling / K) * dt
	local limit = Fuel.implausibleStuds(dt, settings.TopSpeedMphCeiling, K)
	H.expect(limit > atTopSpeed, "a vehicle at top speed is treated as a teleport")
	-- This is the regression: the guard was a flat 400 studs and top speed for one
	-- two-second tick is about 448, so fast driving was silently billed nothing.
	H.expect(
		atTopSpeed > 400,
		"the old flat guard would not have been exceeded, so this test proves nothing"
	)
	local miles = Fuel.tick(atTopSpeed, dt, settings)
	H.expect(miles > 0, "distance driven at top speed was discarded")
end)

H.test("a teleport is billed as nothing rather than as a long drive", function()
	local settings = Config.VehicleData
	local dt = settings.ConsumptionIntervalSeconds
	local limit =
		Fuel.implausibleStuds(dt, settings.TopSpeedMphCeiling, settings.StudsPerSecondToMph)
	local miles, burnt = Fuel.tick(limit * 10, dt, settings)
	H.expect(miles == 0, "a teleport added mileage")
	-- Idle burn still applies: the engine was running through the tick either way.
	local idleOnly = (dt / 60) * settings.FuelPercentPerIdleMinute
	H.expect(math.abs(burnt - idleOnly) < 1e-9, "a teleport was charged for distance")
end)

H.test("fuel burn has a distance term and an idle term", function()
	local settings = Config.VehicleData
	-- Distance alone.
	local moving = Fuel.burn(1, 0, settings.FuelPercentPerMile, settings.FuelPercentPerIdleMinute)
	H.expect(
		math.abs(moving - settings.FuelPercentPerMile) < 1e-9,
		"a mile did not cost its configured share"
	)
	-- Idle alone. A vehicle running for a minute burns the idle rate.
	local idling = Fuel.burn(0, 60, settings.FuelPercentPerMile, settings.FuelPercentPerIdleMinute)
	H.expect(math.abs(idling - settings.FuelPercentPerIdleMinute) < 1e-9, "idling was free")
	H.expect(idling > 0, "a parked engine is a free generator")
end)

H.test("a tank lasts a sensible distance rather than a session or a lifetime", function()
	local settings = Config.VehicleData
	local range = 100 / settings.FuelPercentPerMile
	-- A real car does about 400 miles to a tank, which nobody would notice inside
	-- one session; a range of a few miles would be unplayable.
	H.expect(range > 20, "a full tank does not last twenty miles")
	H.expect(range < 200, "a full tank lasts so long the gauge never moves")
end)

H.test("the empty threshold stops the engine before the tank reads zero", function()
	local settings = Config.VehicleData
	H.expect(settings.EmptyFuelPercent > 0, "the engine only cuts at exactly zero")
	H.expect(settings.EmptyFuelPercent < 5, "the engine cuts while the gauge still shows fuel")
end)

H.test("gang names are shaped before they reach a filter or a datastore", function()
	local ok = Gangs.validateName("Bridge 42")
	H.expect(ok == "Bridge 42", "a plain name was refused")
	H.expect(
		select(1, Gangs.validateName("  Bridge 42  ")) == "Bridge 42",
		"the cleaned name is not returned"
	)
	H.expect(
		select(2, Gangs.validateName("ab")) == "NAME_LENGTH",
		"a two character name was allowed"
	)
	H.expect(
		select(2, Gangs.validateName(string.rep("a", 25))) == "NAME_LENGTH",
		"an overlong name was allowed"
	)
	H.expect(select(2, Gangs.validateName("  ")) == "NAME_REQUIRED", "whitespace passed as a name")
	H.expect(select(2, Gangs.validateName(42)) == "NAME_REQUIRED", "a number passed as a name")
	-- The shapes people actually use to game a list.
	H.expect(
		select(2, Gangs.validateName("-Bridge")) == "NAME_CHARACTERS",
		"a leading hyphen was allowed"
	)
	H.expect(
		select(2, Gangs.validateName("Bridge  42")) == "NAME_CHARACTERS",
		"a double space was allowed"
	)
	H.expect(
		select(2, Gangs.validateName("<<Bridge>>")) == "NAME_CHARACTERS",
		"punctuation drawing was allowed"
	)
end)

H.test("two gangs cannot be visibly identical", function()
	H.expect(
		Gangs.nameKey("Bridge 42") == Gangs.nameKey("bridge42"),
		"case and spacing distinguish two names"
	)
	H.expect(Gangs.nameKey("Bridge 42") ~= Gangs.nameKey("Bridge 43"), "different names collided")
end)

H.test("invites respect the leader, the cap and existing membership", function()
	local gang = {
		Id = "g",
		Name = "Bridge 42",
		LeaderUserId = 1,
		MemberUserIds = { 2, 3 },
		TerritoryId = nil,
	}
	H.expect(Gangs.canInvite(gang, 1, 9), "the leader could not invite")
	H.expect(select(2, Gangs.canInvite(gang, 2, 9)) == "NOT_THE_LEADER", "a member could invite")
	H.expect(
		select(2, Gangs.canInvite(gang, 1, 2)) == "ALREADY_A_MEMBER",
		"an existing member was re-invited"
	)
	H.expect(
		select(2, Gangs.canInvite(gang, 1, 1)) == "ALREADY_A_MEMBER",
		"the leader invited themselves"
	)
	-- The leader occupies a place, so the cap is reached one member early.
	local full = { Id = "g", Name = "n", LeaderUserId = 1, MemberUserIds = {}, TerritoryId = nil }
	for i = 2, Gangs.MaximumMembers do
		table.insert(full.MemberUserIds, i)
	end
	H.expect(select(2, Gangs.canInvite(full, 1, 99)) == "GANG_FULL", "a gang went over its cap")
end)

H.test("a territory does not change hands on a tie, and police suppress a contest", function()
	-- A strict majority only: an equal showing leaves the holder alone.
	local holder, why = Gangs.contestOutcome("a", { a = 3, b = 3 }, 0)
	H.expect(holder == "a" and why == "NO_CHANGE", "a tie flipped the zone")
	holder, why = Gangs.contestOutcome("a", { a = 2, b = 4 }, 0)
	H.expect(holder == "b" and why == "CONTESTED", "a majority did not take the zone")
	holder, why = Gangs.contestOutcome("a", { a = 4, b = 2 }, 0)
	H.expect(holder == "a" and why == "HELD", "the holder lost while winning")
	-- An officer stops the contest without taking the ground.
	holder, why = Gangs.contestOutcome("a", { b = 9 }, 1)
	H.expect(holder == "a" and why == "SUPPRESSED_BY_POLICE", "police did not suppress a contest")
	-- An empty zone belongs to whoever held it.
	holder, why = Gangs.contestOutcome("a", {}, 0)
	H.expect(holder == "a" and why == "NO_CHANGE", "an empty zone changed hands")
	H.expect(
		select(1, Gangs.contestOutcome(nil, {}, 0)) == nil,
		"an unheld empty zone gained an owner"
	)
end)

H.test("contest timings leave room for a fight and for it to settle", function()
	H.expect(Gangs.ContestSeconds > 30, "a zone flips faster than anybody can respond")
	H.expect(Gangs.PoliceClearSeconds < Gangs.ContestSeconds, "clearing takes longer than taking")
	H.expect(
		Gangs.ClaimCooldownSeconds > Gangs.ContestSeconds,
		"a zone can be traded back immediately"
	)
	H.expect(
		Gangs.MaximumMembers > 1 and Gangs.MaximumMembers <= 30,
		"the member cap is not a sane size"
	)
end)

H.test("a lamp module's data becomes a pattern, or nil when it is not one", function()
	local lamp =
		EmergencyPatterns.lampFromData({ lightName = "F1", patternData = { "Blue", false } })
	H.expect(lamp ~= nil and lamp.Name == "F1", "a valid lamp was not read")
	H.expect(#lamp.Steps == 2, "the steps were not carried across")

	local fallback = EmergencyPatterns.lampFromData({ patternData = { "Red" } }, "F2")
	H.expect(fallback ~= nil and fallback.Name == "F2", "a missing lightName did not fall back")

	H.expect(
		EmergencyPatterns.lampFromData({ lightID = 9, spacer = true }) == nil,
		"a spacer with no patternData was read as a lamp"
	)
	H.expect(
		EmergencyPatterns.lampFromData({ lightName = "F1", patternData = {} }) == nil,
		"an empty pattern was read as a lamp"
	)
	H.expect(EmergencyPatterns.lampFromData("not a table") == nil, "a non-table was read as a lamp")
	H.expect(EmergencyPatterns.lampFromData(nil) == nil, "nil was read as a lamp")
end)

H.test("tempo falls back to the default and floors at one millisecond", function()
	H.expect(
		EmergencyPatterns.tempoSeconds(nil) == EmergencyPatterns.DefaultTempo / 1000,
		"a missing tempo did not fall back to the default"
	)
	H.expect(EmergencyPatterns.tempoSeconds(900) == 0.9, "900ms did not convert to 0.9s")
	H.expect(EmergencyPatterns.tempoSeconds(0) == 0.001, "a zero tempo produced a zero-length step")
	H.expect(EmergencyPatterns.tempoSeconds(-50) == 0.001, "a negative tempo was not floored")
end)

H.test("colourAt steps a lamp at the stage's tempo and wraps short strips", function()
	local lamp: EmergencyPatterns.LampPattern = { Name = "F1", Steps = { "Red", false } }
	local stage: EmergencyPatterns.Stage =
		{ Name = "Stage1", TempoSeconds = 1, Lamps = { lamp }, Length = 4 }
	H.expect(EmergencyPatterns.colourAt(lamp, stage, 0) == "Red", "step 0 was not the first entry")
	H.expect(EmergencyPatterns.colourAt(lamp, stage, 1) == nil, "step 1 was not dark")
	-- The lamp only has two steps but the stage runs four long, so it repeats
	-- rather than running out and going dark for the back half of the cycle.
	H.expect(EmergencyPatterns.colourAt(lamp, stage, 2) == "Red", "the short strip did not wrap")
	H.expect(
		EmergencyPatterns.colourAt(lamp, stage, 3) == nil,
		"the short strip's wrap was misaligned"
	)
	-- The stage itself wraps at its own Length, back to step 0.
	H.expect(
		EmergencyPatterns.colourAt(lamp, stage, 4) == "Red",
		"the stage did not wrap at its length"
	)

	local halfTempo: EmergencyPatterns.Stage =
		{ Name = "Stage1", TempoSeconds = 0.5, Lamps = { lamp }, Length = 4 }
	H.expect(
		EmergencyPatterns.colourAt(lamp, halfTempo, 0.5) == nil,
		"a faster tempo did not advance the step"
	)
end)

H.test("a kit is only adopted whole", function()
	local lamp: EmergencyPatterns.LampPattern = { Name = "F1", Steps = { "Red" } }
	local stage: EmergencyPatterns.Stage =
		{ Name = "Stage1", TempoSeconds = 1, Lamps = { lamp }, Length = 1 }
	local part = Instance.new("Part")
	H.expect(not EmergencyPatterns.canAdopt({
		Remote = workspace,
		LightsParent = nil,
		Stages = { Stage1 = stage },
		Colours = EmergencyPatterns.DefaultColours,
		Lamps = {},
		OnTransparency = EmergencyPatterns.DefaultOnTransparency,
	}), "a kit with no lights parent was adopted")
	H.expect(not EmergencyPatterns.canAdopt({
		Remote = workspace,
		LightsParent = workspace,
		Stages = { Stage1 = stage },
		Colours = EmergencyPatterns.DefaultColours,
		Lamps = {},
		OnTransparency = EmergencyPatterns.DefaultOnTransparency,
	}), "a kit whose lamp names matched nothing was adopted")
	H.expect(
		EmergencyPatterns.canAdopt({
			Remote = workspace,
			LightsParent = workspace,
			Stages = { Stage1 = stage },
			Colours = EmergencyPatterns.DefaultColours,
			Lamps = { F1 = part },
			OnTransparency = EmergencyPatterns.DefaultOnTransparency,
		}),
		"a complete kit was refused"
	)
	part:Destroy()
end)

H.test(
	"incident index projection removes malformed rows and restores its configured cap",
	function()
		local index = {
			Entries = {
				corrupt = "invalid row",
				badTimestamp = {
					IncidentId = "badTimestamp",
					Title = "Bad timestamp",
					Status = "Closed",
					CreatedAt = "yesterday",
					DepartmentIds = { "Police" },
					UpdatedAt = 1,
				},
				oldest = {
					IncidentId = "oldest",
					Title = "Oldest incident",
					Status = "Closed",
					CreatedAt = 1,
					DepartmentIds = { "Police" },
					UpdatedAt = 1,
				},
				middle = {
					IncidentId = "middle",
					Title = "Middle incident",
					Status = "Closed",
					CreatedAt = 2,
					DepartmentIds = { "Police" },
					UpdatedAt = 2,
				},
				newer = {
					IncidentId = "newer",
					Title = "Newer incident",
					Status = "Closed",
					CreatedAt = 3,
					DepartmentIds = { "Police" },
					UpdatedAt = 3,
				},
			},
		}
		local dataService = {
			UpdateMdtIndex = function(_self, _key, transform)
				index = transform(index)
				return index, nil
			end,
		}
		local context = {
			Configuration = { MDT = { MaximumIncidentIndexEntries = 2 } },
			Services = {
				Get = function(_self, name)
					H.expect(name == "DataService", "unexpected incident index dependency")
					return dataService
				end,
			},
		}
		local service = setmetatable(
			{ context = context, running = true },
			{ __index = IncidentService }
		)
		local projected, reason = service:_indexIncident({
			IncidentId = "latest",
			Title = "Latest incident",
			Status = "Closed",
			CreatedAt = 4,
			DepartmentIds = { "Police" },
		})
		H.expect(projected and reason == nil, "malformed existing rows blocked incident projection")
		H.expect(index.Entries.corrupt == nil, "malformed scalar row remained indexed")
		H.expect(index.Entries.badTimestamp == nil, "malformed timestamp row remained indexed")
		H.expect(index.Entries.oldest == nil, "projection failed to trim multiple old rows")
		H.expect(index.Entries.middle == nil, "projection did not enforce the lowered cap")
		H.expect(
			index.Entries.newer ~= nil and index.Entries.latest ~= nil,
			"newest rows were not retained"
		)
		local count = 0
		for _ in index.Entries do
			count += 1
		end
		H.expect(count == 2, "incident index exceeded its configured hard cap")
	end
)

H.test("incident index rejects delayed projections after closure", function()
	local index = { Entries = {} }
	local retryTransform
	local dataService = {
		UpdateMdtIndex = function(_self, _key, transform)
			retryTransform = transform
			index = transform(index)
			return index, nil
		end,
	}
	local service = setmetatable({
		context = {
			Configuration = { MDT = { MaximumIncidentIndexEntries = 10 } },
			Services = {
				Get = function()
					return dataService
				end,
			},
		},
	}, { __index = IncidentService })
	local open = {
		IncidentId = "race",
		Title = "Original incident",
		Status = "Open",
		CreatedAt = 1,
		DepartmentIds = { "Police" },
		Revision = 1,
	}
	service:_indexIncident(open)
	local delayedTransform = retryTransform
	local closed = table.clone(open)
	closed.Status = "Closed"
	closed.ClosedAt = 2
	closed.Revision = 2
	service:_indexIncident(closed)
	-- Replay the old transform against the newer committed row, as UpdateAsync
	-- does after a conflict or an ambiguous-write retry.
	index = delayedTransform(index)
	H.expect(index.Entries.race.Status == "Closed", "delayed projection reopened closed history")
	H.expect(index.Entries.race.Revision == 2, "delayed projection lost the newer revision")
	H.expect(index.Entries.race.ClosedAt == 2, "delayed projection lost the closure timestamp")
	index.Entries.race.Revision = nil
	service:_indexIncident(open)
	H.expect(index.Entries.race.Status == "Closed", "legacy closed row was reopened")
	local newer = table.clone(closed)
	newer.Revision = 3
	newer.Title = "Newer durable revision"
	service:_indexIncident(newer)
	service:_indexIncident(closed)
	H.expect(
		index.Entries.race.Title == newer.Title,
		"older closed projection replaced newer revision"
	)
	H.expect(index.Entries.race.Revision == 3, "older closed projection rolled revision backwards")
end)

H.test("ignored incident projections still clean and cap the recent index", function()
	for _, case in
		{
			{ Status = "Open", Revision = 2, IncomingStatus = "Open", IncomingRevision = 1 },
			{ Status = "Closed", Revision = 2, IncomingStatus = "Closed", IncomingRevision = 1 },
			{ Status = "Closed", Revision = 2, IncomingStatus = "Open", IncomingRevision = 3 },
			{ Status = "Closed", IncomingStatus = "Open", IncomingRevision = 3 },
		}
	do
		local protected = {
			IncidentId = "race",
			Title = "Committed incident",
			Status = case.Status,
			Revision = case.Revision,
			ClosedAt = if case.Status == "Closed" then 2 else nil,
			CreatedAt = 1,
			DepartmentIds = { "Police" },
			UpdatedAt = 7,
		}
		local older = table.clone(protected)
		older.IncidentId = "other"
		-- Equal timestamps exercise the existing deterministic ID tie-break.
		local index = { Entries = { race = protected, other = older, corrupt = "invalid" } }
		local service = setmetatable({
			context = {
				Configuration = { MDT = { MaximumIncidentIndexEntries = 1 } },
				Services = {
					Get = function()
						return {
							UpdateMdtIndex = function(_self, _key, transform)
								index = transform(index)
								return index, nil
							end,
						}
					end,
				},
			},
		}, { __index = IncidentService })
		local incoming = table.clone(protected)
		incoming.Title = "Delayed projection"
		incoming.Status = case.IncomingStatus
		incoming.Revision = case.IncomingRevision
		local indexed, reason = service:_indexIncident(incoming)
		H.expect(indexed and reason == nil, "ignored projection failed maintenance")
		H.expect(index.Entries.corrupt == nil, "ignored projection retained a malformed row")
		H.expect(index.Entries.other == nil, "ignored projection bypassed the cap or ID tie-break")
		H.expect(index.Entries.race == protected, "ignored projection replaced the committed row")
		H.expect(protected.Title == "Committed incident", "ignored projection changed title")
		H.expect(protected.Status == case.Status, "ignored projection changed status")
		H.expect(protected.Revision == case.Revision, "ignored projection changed revision")
		H.expect(protected.UpdatedAt == 7, "ignored projection refreshed the row's timestamp")
		H.expect(
			protected.ClosedAt == (if case.Status == "Closed" then 2 else nil),
			"ignored projection lost closure metadata"
		)
		-- Protection does not grant special retention: a genuinely newer incident
		-- still displaces this row, even when the attempted write is ignored.
		older.CreatedAt = 2
		index.Entries.other = older
		service:_indexIncident(incoming)
		H.expect(index.Entries.race == nil, "protected row bypassed chronological retention")
		H.expect(index.Entries.other == older, "maintenance evicted the newer incident")
	end
end)

H.test("incident history refills stale rows within one extra candidate page", function()
	for _, staleCount in { 2, 5 } do
		local index = { Entries = {} }
		local records = {}
		for position = 1, 6 do
			local id = tostring(position)
			local row = {
				IncidentId = id,
				Title = "Incident " .. id,
				Status = "Closed",
				CreatedAt = 7 - position,
				UpdatedAt = 1,
				DepartmentIds = { "Police" },
			}
			index.Entries[id] = row
			if position > staleCount then
				records["Incident:" .. id] = row
			end
		end
		local reads, writes = 0, 0
		local duty = { DepartmentId = "Police" }
		local dataService = {
			GetMdtIndex = function()
				return index, nil
			end,
			GetMdtRecord = function(_self, key)
				reads += 1
				return records[key], nil
			end,
			UpdateMdtIndex = function(_self, _key, transform)
				writes += 1
				index = transform(index)
				return index, nil
			end,
		}
		local service = setmetatable({
			running = true,
			_getReadDuty = function()
				return duty
			end,
			_cacheGet = function()
				return nil
			end,
			_cacheSet = function() end,
			context = {
				Configuration = { MDT = { PageSize = 2 } },
				Services = {
					Get = function()
						return dataService
					end,
				},
				Logger = { Warning = function() end },
			},
		}, { __index = IncidentService })
		local result, reason = service:Recent({}, 1, true)
		H.expect(result ~= nil and reason == nil, "incident refill failed")
		if staleCount == 2 then
			H.expect(#result.Items == 2, "incident refill did not fill the available page")
			H.expect(
				result.Items[1].IncidentId == "3" and result.Items[2].IncidentId == "4",
				"incident refill skipped or reordered valid records"
			)
			H.expect(result.Total == 4 and reads == 6 and writes == 4, "unexpected refill work")
		else
			H.expect(#result.Items == 0, "history scanned beyond the bounded stale prefix")
			H.expect(result.Total == 2, "unvisited rows were removed from the total")
			H.expect(reads == 8 and writes == 8, "history exceeded one extra candidate page")
			H.expect(index.Entries["5"] ~= nil, "history cleaned an unvisited candidate")
		end
		local beforeReads, beforeWrites = reads, writes
		local empty = service:Recent({}, 99, true)
		H.expect(empty ~= nil and #empty.Items == 0, "out-of-range page was not empty")
		H.expect(reads == beforeReads and writes == beforeWrites, "empty page spent store work")
	end
end)

H.test("MDT searches refill pages after suppressing stale rows", function()
	for _, kind in { "Person", "Vehicle" } do
		local bucket = { Entries = {} }
		local records = {}
		for index = 1, 4 do
			local id = tostring(index)
			local text = "ab" .. id
			bucket.Entries[id] = if kind == "Person"
				then { CharacterId = id, FullName = text, SearchText = text, UpdatedAt = 1 }
				else { VehicleId = id, Registration = text, SearchText = text, UpdatedAt = 1 }
			if index > 2 then
				records[id] = if kind == "Person"
					then { CharacterId = id, FullName = text }
					else { VehicleId = id, Registration = text }
			end
		end
		local reads = 0
		local service = setmetatable({
			context = {
				Configuration = { MDT = { PageSize = 2 } },
				Services = {
					Get = function()
						return {
							GetMdtIndex = function()
								return bucket, nil
							end,
						}
					end,
				},
				Logger = { Warning = function() end },
			},
			GetPerson = function(_self, id)
				reads += 1
				return records[id], nil
			end,
			_getRecord = function(_self, key)
				reads += 1
				return records[string.match(key, ":(.+)$")], nil
			end,
			_removeStalePersonIndex = function()
				return true, nil, true
			end,
			_repairStaleVehicleIndex = function()
				return true, nil, true
			end,
		}, { __index = RecordIndexService })
		local result, reason
		if kind == "Person" then
			result, reason = service:SearchPeople("ab", 1, "Emergency", false)
		else
			result, reason = service:SearchVehicles("ab", 1, false)
		end
		H.expect(result ~= nil and reason == nil, "search failed during stale-row refill")
		H.expect(
			#result.Items == 2,
			kind .. " search left a page empty despite later valid matches"
		)
		H.expect(result.Total == 2, "stale rows still inflated the search total")
		H.expect(
			result.Items[1][if kind == "Person" then "CharacterId" else "VehicleId"] == "3"
				and result.Items[2][if kind == "Person" then "CharacterId" else "VehicleId"]
					== "4",
			"refill skipped or reordered valid matches"
		)
		H.expect(reads == 4, "refill read candidates more than once")
		-- A long stale prefix must not turn one search into an entire bucket scan.
		table.clear(records)
		bucket.Entries["5"] = if kind == "Person"
			then { CharacterId = "5", FullName = "ab5", SearchText = "ab5", UpdatedAt = 1 }
			else { VehicleId = "5", Registration = "ab5", SearchText = "ab5", UpdatedAt = 1 }
		reads = 0
		local bounded = if kind == "Person"
			then service:SearchPeople("ab", 1, "Emergency", false)
			else service:SearchVehicles("ab", 1, false)
		H.expect(bounded ~= nil and #bounded.Items == 0, "stale-only search returned a record")
		H.expect(reads == 4, "refill exceeded one extra page of candidate reads")
	end
end)

H.test(
	"record index upsert removes malformed rows and restores its configured bucket cap",
	function()
		local bucket = {
			Entries = {
				corrupt = "invalid row",
				badTimestamp = {
					VehicleId = "badTimestamp",
					Registration = "BAD123",
					SearchText = "bad123",
					UpdatedAt = "yesterday",
				},
				oldest = {
					VehicleId = "oldest",
					Registration = "OLD123",
					SearchText = "old123",
					UpdatedAt = 1,
				},
				middle = {
					VehicleId = "middle",
					Registration = "MID123",
					SearchText = "mid123",
					UpdatedAt = 2,
				},
				newer = {
					VehicleId = "newer",
					Registration = "NEW123",
					SearchText = "new123",
					UpdatedAt = 3,
				},
			},
		}
		local dataService = {
			UpdateMdtIndex = function(_self, _key, transform)
				bucket = transform(bucket)
				return bucket, nil
			end,
		}
		local context = {
			Configuration = { MDT = { MaximumIndexBucketEntries = 2 } },
			Services = {
				Get = function(_self, name)
					H.expect(name == "DataService", "unexpected record index dependency")
					return dataService
				end,
			},
		}
		local service = setmetatable({ context = context }, { __index = RecordIndexService })
		local indexed, reason = service:_upsertIndex("Vehicle:AB", "latest", {
			VehicleId = "latest",
			Registration = "LAT123",
			SearchText = "lat123",
			UpdatedAt = 4,
		})
		H.expect(indexed and reason == nil, "malformed existing rows blocked record indexing")
		H.expect(bucket.Entries.corrupt == nil, "malformed scalar row remained indexed")
		H.expect(bucket.Entries.badTimestamp == nil, "malformed timestamp row remained indexed")
		H.expect(bucket.Entries.oldest == nil, "upsert failed to trim multiple old rows")
		H.expect(bucket.Entries.middle == nil, "upsert did not enforce the lowered cap")
		H.expect(
			bucket.Entries.newer ~= nil and bucket.Entries.latest ~= nil,
			"newest rows were not retained"
		)
		local count = 0
		for _ in bucket.Entries do
			count += 1
		end
		H.expect(count == 2, "record index bucket exceeded its configured hard cap")
	end
)

H.test("vehicle registration cleanup preserves the current search bucket", function()
	local buckets = {}
	local writes = 0
	local service = setmetatable({
		context = {
			Configuration = { MDT = { MaximumIndexBucketEntries = 10 } },
			Services = {
				Get = function()
					return {
						UpdateMdtIndex = function(_self, key, transform)
							writes += 1
							buckets[key] = transform(buckets[key])
							return buckets[key], nil
						end,
					}
				end,
			},
		},
	}, { __index = RecordIndexService })
	local function entry(registration)
		return {
			VehicleId = "vehicle",
			Registration = registration,
			SearchText = string.lower(registration),
			UpdatedAt = 1,
		}
	end
	service:_upsertIndex("Vehicle:ab", "vehicle", entry("AB123"))
	local current = entry("AB999")
	service:_upsertIndex("Vehicle:ab", "vehicle", current)
	local beforeCleanup = writes
	local removed, reason = service:_removeVehicleIndex("AB123", "vehicle", "AB999")
	H.expect(removed and reason == nil, "same-bucket cleanup failed")
	H.expect(buckets["Vehicle:ab"].Entries.vehicle == current, "cleanup deleted the new plate")
	H.expect(writes == beforeCleanup, "same-bucket cleanup spent an unnecessary store write")
	service:_removeVehicleIndex("ab 123", "vehicle", "AB-999")
	H.expect(writes == beforeCleanup, "normalised same-bucket cleanup wrote to the store")
	local nextEntry = entry("CD999")
	service:_upsertIndex("Vehicle:cd", "vehicle", nextEntry)
	service:_removeVehicleIndex("AB999", "vehicle", "CD999")
	H.expect(buckets["Vehicle:ab"].Entries.vehicle == nil, "old bucket was not cleaned")
	H.expect(buckets["Vehicle:cd"].Entries.vehicle == nextEntry, "new bucket was altered")
	service:_removeVehicleIndex("AB999", "vehicle", "CD999")
	H.expect(buckets["Vehicle:cd"].Entries.vehicle == nextEntry, "cleanup retry lost the new row")
end)

H.test("warrant cache ignores malformed persisted warrant entries and expiries", function()
	local context = {
		Configuration = {
			MDT = {
				RecordCacheSeconds = 60,
				MaximumWarrantCacheCharacters = 2,
			},
		},
	}
	local service = setmetatable({
		warrants = {},
		byCharacter = {},
		cacheMeta = {},
		cacheCount = 0,
		cacheSweepCounter = 0,
		refreshing = {},
		refreshCount = 0,
	}, { __index = WarrantService })
	service:Init(context)
	service:Start()
	service:CachePersonRecord({
		CharacterId = "malformed-only",
		Warrants = {
			42,
			{
				WarrantId = "bad-expiry",
				Active = true,
				ExpiresAt = "indefinite",
			},
		},
	})
	local hasMalformed, malformedActive, malformedReason =
		service:HasActiveForCharacter("malformed-only")
	H.expect(not hasMalformed, "a malformed expiry was treated as an active warrant")
	H.expect(
		#malformedActive == 0 and malformedReason == nil,
		"malformed entries corrupted the cache"
	)
	service:CachePersonRecord({
		CharacterId = "with-active",
		Warrants = {
			false,
			{ WarrantId = "active", Active = true },
		},
	})
	local hasActive, active, activeReason = service:HasActiveForCharacter("with-active")
	H.expect(
		hasActive and #active == 1 and active[1].WarrantId == "active",
		"valid active warrant was lost"
	)
	H.expect(activeReason == nil, "valid warrant lookup returned an error")
	local person = { CharacterId = "target", Warrants = { 42 } }
	local dependencies = {
		MDTService = {
			CanUsePermission = function()
				return true
			end,
		},
		RecordIndexService = {
			UpdatePerson = function(_self, _characterId, transform)
				person = transform(person)
				return person, nil
			end,
		},
		AuditService = { Record = function() end },
	}
	context.Configuration.MDT.MaximumActiveWarrantsPerPerson = 4
	context.Configuration.MDT.MaximumWarrantHistoryEntries = 10
	context.Configuration.MDT.MaximumWarrantDurationDays = 365
	context.Services = {
		Get = function(_self, name)
			return dependencies[name]
		end,
	}
	service._filter = function()
		return "valid reason", nil
	end
	local issued, issueReason = service:Create({ UserId = 10 }, "target", "reason", nil)
	H.expect(issued ~= nil and issueReason == nil, "warrant creation failed on a malformed old row")
	service:Destroy()
end)

H.finish()
return true
