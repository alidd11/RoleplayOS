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
local CommunityPolicy = require(Shared.CommunityPolicy)
local SpawnPolicy = require(Shared.SpawnPolicy)
local Config = require(game:GetService("ReplicatedStorage").RoleplayOS.Config.Config)

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
		profile.SchemaVersion == 2
			and profile.UserId == 42
			and type(profile.Characters) == "table"
			and type(profile.Communities) == "table",
		"migration failed"
	)
end)
H.test("community permissions honour active role", function()
	local template = Config.Communities.Templates.RoleplayCommunity
	H.expect(
		CommunityPolicy.hasPermission(template, { RoleId = "Owner", Status = "Active" }, "Anything"),
		"owner wildcard failed"
	)
	H.expect(
		not CommunityPolicy.hasPermission(
			template,
			{ RoleId = "Member", Status = "Suspended" },
			"Sessions.Join"
		),
		"suspended member permitted"
	)
end)
H.test("community hierarchy prevents peer management", function()
	local template = Config.Communities.Templates.RoleplayCommunity
	H.expect(
		CommunityPolicy.canManage(
			template,
			{ RoleId = "Administrator", Status = "Active" },
			{ RoleId = "Member", Status = "Active" }
		),
		"administrator cannot manage member"
	)
	H.expect(
		not CommunityPolicy.canManage(
			template,
			{ RoleId = "Administrator", Status = "Active" },
			{ RoleId = "Administrator", Status = "Active" }
		),
		"peer management allowed"
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
H.finish()
