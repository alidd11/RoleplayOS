--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(shared.Config.Config)
		local validator = runtime.require(shared.Shared.ConfigValidator)
		return {
			Runtime = runtime,
			Config = config,
			Validate = function(field: string, value: any, section: string?): boolean
				local name = section or "Framework"
				local candidate = table.clone(config)
				candidate[name] = table.clone(config[name])
				candidate[name][field] = value
				return validator.validate(candidate)
			end,
			ValidateConfig = validator.validate,
			RateLimiter = runtime.require(shared.Shared.RateLimiter),
		}
	end

	H.test("MDT pagination and persisted index caps reject unsafe counts", function()
		local f = fixture()
		for _, field in { "PageSize", "MaximumIndexBucketEntries", "MaximumIncidentIndexEntries" } do
			for _, value in
				{ math.huge, -math.huge, 0 / 0, "25", false, 0, -1, f.Config.MDT[field] + 0.5 }
			do
				H.expect(
					not f.Validate(field, value, "MDT"),
					"invalid MDT count accepted: " .. field
				)
			end
		end
	end)

	H.test("missing MDT pagination and index caps fail validation without raising", function()
		local f = fixture()
		for _, field in { "PageSize", "MaximumIndexBucketEntries", "MaximumIncidentIndexEntries" } do
			local completed, valid = pcall(f.Validate, field, nil, "MDT")
			H.expect(completed and not valid, "missing MDT count raised or passed: " .. field)
		end
	end)

	H.test("MDT finite tuning preserves defaults and page-to-cap relationships", function()
		local f = fixture()
		H.expect(f.ValidateConfig(f.Config), "current MDT defaults refused")
		local candidate = table.clone(f.Config)
		candidate.MDT = table.clone(f.Config.MDT)
		candidate.MDT.PageSize = 1
		candidate.MDT.MaximumIndexBucketEntries = 1
		candidate.MDT.MaximumIncidentIndexEntries = 1
		H.expect(f.ValidateConfig(candidate), "single-row pages and retention refused")
		for _, field in { "MaximumIndexBucketEntries", "MaximumIncidentIndexEntries" } do
			H.expect(f.Validate(field, f.Config.MDT.PageSize, "MDT"), "one-page retention refused")
			H.expect(
				not f.Validate(field, f.Config.MDT.PageSize - 1, "MDT"),
				"cap below page size accepted"
			)
		end
	end)

	H.test("economy retention bounds reject non-finite and non-whole counts", function()
		local f = fixture()
		for _, field in { "MaximumTransactionHistory", "MaximumTransferReceipts" } do
			for _, value in { math.huge, -math.huge, 0 / 0, "200", false, 0, -1, 1.5 } do
				H.expect(
					not f.Validate(field, value, "Economy"),
					"invalid economy retention accepted: " .. field
				)
			end
			H.expect(
				not f.Validate(field, nil, "Economy"),
				"missing economy retention accepted: " .. field
			)
		end
	end)

	H.test("economy retention defaults and smallest supported cap remain valid", function()
		local f = fixture()
		H.expect(f.ValidateConfig(f.Config), "current economy defaults refused")
		for _, field in { "MaximumTransactionHistory", "MaximumTransferReceipts" } do
			H.expect(f.Validate(field, 1, "Economy"), "single-entry retention refused: " .. field)
		end
	end)

	H.test("phone configuration rejects unsafe message bounds", function()
		local f = fixture()
		for _, field in { "MaximumMessages", "MaximumMessageLength" } do
			for _, value in { math.huge, -math.huge, 0 / 0, "200", false, -1, 1.5 } do
				H.expect(
					not f.Validate(field, value, "Phone"),
					"invalid phone bound accepted: " .. field
				)
			end
			H.expect(not f.Validate(field, nil, "Phone"), "missing phone bound accepted: " .. field)
		end
		H.expect(not f.Validate("MaximumMessageLength", 0, "Phone"), "zero message length accepted")
	end)

	H.test("missing and malformed phone sections fail validation safely", function()
		local f = fixture()
		for _, value in { false, 4, "phone" } do
			local candidate = table.clone(f.Config)
			candidate.Phone = value
			local completed, valid = pcall(f.ValidateConfig, candidate)
			H.expect(completed and not valid, "malformed phone section raised or passed")
		end
		local candidate = table.clone(f.Config)
		candidate.Phone = nil
		H.expect(not f.ValidateConfig(candidate), "missing phone section accepted")
	end)

	H.test("valid phone bounds preserve message filtering and inbox retention", function()
		local f = fixture()
		H.expect(f.ValidateConfig(f.Config), "current defaults refused")
		H.expect(f.Validate("MaximumMessageLength", 1, "Phone"), "one-character limit refused")
		local shared = f.Runtime.services.ReplicatedStorage.RoleplayOS
		local validator = f.Runtime.require(shared.Shared.PhoneValidator)
		H.expect(
			validator.message("a", 1) == "a" and validator.message("ab", 1) == nil,
			"valid length limit was not enforced"
		)
		local service = f.Runtime.require(
			f.Runtime.services.ServerScriptService.RoleplayOS.Services.PhoneService
		)
		local player = { UserId = 1, Parent = f.Runtime.services.Players }
		f.Runtime.services.Players.GetPlayerByUserId = function()
			return player
		end
		local character = { Phone = { Messages = {} } }
		local session =
			{ ActiveCharacterId = "active", Profile = { Characters = { active = character } } }
		local dirty = 0
		local data = {
			GetSession = function()
				return session
			end,
			MarkDirty = function()
				dirty += 1
			end,
		}
		local config = table.clone(f.Config)
		config.Phone = table.clone(config.Phone)
		service:Init({
			Configuration = config,
			Services = {
				Get = function(_self, name)
					assert(name == "DataService", "Unexpected append dependency")
					return data
				end,
			},
			Network = {
				RegisterEvent = function()
					return {}
				end,
			},
		})
		service.running = true
		for _, maximum in { 0, 1, f.Config.Phone.MaximumMessages } do
			H.expect(
				f.Validate("MaximumMessages", maximum, "Phone"),
				"valid retention limit refused"
			)
			config.Phone.MaximumMessages = maximum
			character.Phone.Messages = {}
			for i = 1, maximum + 2 do
				H.expect(
					service:_append(player, character, { MessageId = tostring(i) }),
					"append failed"
				)
			end
			H.expect(#character.Phone.Messages == maximum, "inbox count exceeded cap")
			if maximum > 0 then
				H.expect(
					character.Phone.Messages[1].MessageId == "3",
					"retention removed newer messages"
				)
			end
		end
		H.expect(dirty == f.Config.Phone.MaximumMessages + 7, "append dirty marking changed")
		service:Destroy()
	end)

	H.test("persistence configuration rejects non-finite timing bounds", function()
		local f = fixture()
		for _, field in { "AutosaveSeconds", "ShutdownSaveSeconds", "SessionLeaseSeconds" } do
			for _, value in { 0 / 0, math.huge, -math.huge, "60", 0, -1 } do
				H.expect(
					not f.Validate(field, value),
					"invalid persistence duration accepted: " .. field
				)
			end
		end
	end)

	H.test("persistence configuration rejects infinite retry counts", function()
		local f = fixture()
		for _, field in { "MaxSaveAttempts", "JoinLoadAttempts" } do
			for _, value in { math.huge, 0 / 0, -math.huge, "4", 0, -1, 1.5 } do
				H.expect(not f.Validate(field, value), "invalid retry count accepted: " .. field)
			end
		end
	end)

	H.test("optional persistence guards reject present non-finite values", function()
		local f = fixture()
		for _, field in
			{ "MaximumLeaseWaitSeconds", "SessionHandoverSeconds", "ProfileSizeWarningBytes" }
		do
			for _, value in { 0 / 0, math.huge, -math.huge, "10", -1 } do
				H.expect(
					not f.Validate(field, value),
					"invalid optional persistence guard accepted: " .. field
				)
			end
		end
	end)

	H.test("valid persistence defaults and optional fallbacks remain accepted", function()
		local f = fixture()
		H.expect(f.ValidateConfig(f.Config), "current configuration was refused")
		for _, field in
			{ "MaximumLeaseWaitSeconds", "SessionHandoverSeconds", "ProfileSizeWarningBytes" }
		do
			H.expect(f.Validate(field, nil), "optional fallback was refused: " .. field)
		end
		H.expect(f.Validate("MaximumLeaseWaitSeconds", 0), "immediate lease refusal was disabled")
		H.expect(
			f.Validate("MaxSaveAttempts", 1) and f.Validate("JoinLoadAttempts", 1),
			"single-attempt bounds were refused"
		)
		H.expect(
			not f.Validate("SessionLeaseSeconds", f.Config.Framework.AutosaveSeconds),
			"unsafe lease/cadence relation accepted"
		)
		H.expect(
			not f.Validate("MaximumLeaseWaitSeconds", f.Config.Framework.SessionLeaseSeconds),
			"unsafe join wait accepted"
		)
		H.expect(
			not f.Validate("ProfileSizeWarningBytes", 4 * 1024 * 1024),
			"warning threshold reached the storage ceiling"
		)
	end)

	for field, minimum in { AuditMaximumPendingEntries = 25, AuditFlushThreshold = 1 } do
		H.test("audit configuration rejects unsafe " .. field, function()
			local f = fixture()
			for _, value in { math.huge, -math.huge, 0 / 0, "25", 0, -1, 25.5, minimum - 1 } do
				H.expect(not f.Validate(field, value), "invalid audit count accepted: " .. field)
			end
		end)
	end

	for _, field in { "AuditFlushIntervalSeconds", "AuditShutdownFlushSeconds" } do
		H.test("audit configuration rejects unsafe " .. field, function()
			local f = fixture()
			for _, value in { math.huge, -math.huge, 0 / 0, "5", 0, -1 } do
				H.expect(not f.Validate(field, value), "invalid audit duration accepted: " .. field)
			end
		end)
	end

	H.test(
		"audit defaults, optional fallbacks and service clamp boundaries remain valid",
		function()
			local f = fixture()
			for _, field in
				{
					"AuditMaximumPendingEntries",
					"AuditFlushThreshold",
					"AuditFlushIntervalSeconds",
					"AuditShutdownFlushSeconds",
				}
			do
				H.expect(f.Validate(field, nil), "audit fallback refused: " .. field)
			end
			H.expect(f.Validate("AuditMaximumPendingEntries", 25), "small pending buffer refused")
			H.expect(f.Validate("AuditFlushThreshold", 1), "immediate burst threshold refused")
			H.expect(f.Validate("AuditFlushThreshold", 600), "clamped threshold refused")
			H.expect(f.Validate("AuditFlushIntervalSeconds", 0.5), "clamped interval refused")
			H.expect(
				f.Validate("AuditShutdownFlushSeconds", 0.5),
				"clamped shutdown budget refused"
			)
		end
	)

	H.test("network configuration requires finite whole safety bounds", function()
		local f = fixture()
		for _, field in
			{
				"MaximumPayloadBytes",
				"MaximumDepth",
				"MaximumNodes",
				"MaximumStringBytes",
				"MaximumResponseDepth",
				"MaximumResponseNodes",
				"MaximumResponseStringBytes",
				"MaximumResponseTotalStringBytes",
				"MaximumConcurrentRequests",
				"MaximumConcurrentRequestsPerServer",
			}
		do
			for _, value in { math.huge, -math.huge, 0 / 0, "8", 0, -1, 1.5 } do
				H.expect(
					not f.Validate(field, value, "Network"),
					"invalid network bound accepted: " .. field
				)
			end
		end
	end)

	H.test("network configuration requires finite positive bucket settings", function()
		local f = fixture()
		for _, field in
			{
				"GlobalCapacity",
				"GlobalRefillPerSecond",
				"AvatarCatalogSharedCapacity",
				"AvatarCatalogSharedRefillPerSecond",
			}
		do
			for _, value in { math.huge, -math.huge, 0 / 0, "1", 0, -1 } do
				H.expect(
					not f.Validate(field, value, "Network"),
					"invalid bucket setting accepted: " .. field
				)
			end
		end
	end)

	H.test("optional network durations reject invalid deadlines", function()
		local f = fixture()
		for _, field in
			{ "HandlerTimeoutSeconds", "RequestAbandonSeconds", "ShutdownRequestDrainSeconds" }
		do
			for _, value in { math.huge, -math.huge, 0 / 0, "8", -1 } do
				H.expect(
					not f.Validate(field, value, "Network"),
					"invalid request duration accepted: " .. field
				)
			end
			if field ~= "ShutdownRequestDrainSeconds" then
				H.expect(not f.Validate(field, 0, "Network"), "zero request duration accepted")
			end
		end
	end)

	H.test("network endpoint buckets reject non-finite settings", function()
		local f = fixture()
		for _, field in { "Capacity", "RefillPerSecond" } do
			for _, value in { math.huge, -math.huge, 0 / 0, "1", 0, -1 } do
				local candidate = table.clone(f.Config)
				candidate.Network = table.clone(f.Config.Network)
				candidate.Network.Endpoints = table.clone(f.Config.Network.Endpoints)
				local limits = table.clone(f.Config.Network.Endpoints.GetSettings)
				limits[field] = value
				candidate.Network.Endpoints.GetSettings = limits
				H.expect(not f.ValidateConfig(candidate), "invalid endpoint bucket accepted")
			end
		end
	end)

	H.test("network fallbacks and fractional rate tuning preserve bounded admission", function()
		local f = fixture()
		for _, field in
			{
				"MaximumConcurrentRequestsPerServer",
				"HandlerTimeoutSeconds",
				"RequestAbandonSeconds",
				"ShutdownRequestDrainSeconds",
			}
		do
			H.expect(f.Validate(field, nil, "Network"), "network fallback refused: " .. field)
		end
		H.expect(f.Validate("ShutdownRequestDrainSeconds", 0, "Network"), "immediate drain refused")
		H.expect(f.Validate("GlobalCapacity", 1.5, "Network"), "fractional capacity refused")
		H.expect(f.Validate("GlobalRefillPerSecond", 0.5, "Network"), "fractional refill refused")
		local now = 0
		local bucket = f.RateLimiter.new(1.5, 0.5, function()
			return now
		end)
		H.expect(bucket:Allow("user") and not bucket:Allow("user"), "fractional cap was lost")
		now = 1
		H.expect(
			bucket:Allow("user") and not bucket:Allow("user"),
			"fractional refill was unbounded"
		)
	end)

	H.test("network size relationships and malformed sections fail safely", function()
		local f = fixture()
		H.expect(
			not f.Validate(
				"MaximumStringBytes",
				f.Config.Network.MaximumPayloadBytes + 1,
				"Network"
			),
			"request string exceeded its payload bound"
		)
		H.expect(
			not f.Validate(
				"MaximumResponseTotalStringBytes",
				f.Config.Network.MaximumResponseStringBytes - 1,
				"Network"
			),
			"response total was smaller than one allowed string"
		)
		local candidate = table.clone(f.Config)
		candidate.Network = 4
		local completed, valid = pcall(f.ValidateConfig, candidate)
		H.expect(completed and not valid, "malformed Network section raised or passed")
	end)
end
