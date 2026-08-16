--!strict
-- Run in a Rojo test place with this folder mapped as a container, or adapt these
-- specs to TestEZ. They deliberately exercise modules that have no server state.
local H = require(script.Parent.TestHarness)
local Shared = game:GetService("ReplicatedStorage").RoleplayOS.Shared
local Access = require(Shared.AccessEvaluator)
local RateLimiter = require(Shared.RateLimiter)
local Economy = require(Shared.EconomyValidator)
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
local MoneyDropPolicy = require(Shared.MoneyDropPolicy)
local Coalescer = require(Shared.Coalescer)
local Config = require(game:GetService("ReplicatedStorage").RoleplayOS.Config.Config)

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
		profile.SchemaVersion == Config.Framework.SchemaVersion
			and profile.UserId == 42
			and type(profile.Characters) == "table"
			and type(profile.Communities) == "table",
		"migration failed"
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

H.finish()
return true
