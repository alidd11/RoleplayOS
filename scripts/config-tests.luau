--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(shared.Config.Config)
		local validator = runtime.require(shared.Shared.ConfigValidator)
		return {
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
		H.expect(bucket:Allow("user") and not bucket:Allow("user"), "fractional refill was unbounded")
	end)

	H.test("network size relationships and malformed sections fail safely", function()
		local f = fixture()
		H.expect(
			not f.Validate("MaximumStringBytes", f.Config.Network.MaximumPayloadBytes + 1, "Network"),
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
