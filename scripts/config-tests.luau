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
			Validate = function(field: string, value: any): boolean
				local candidate = table.clone(config)
				candidate.Framework = table.clone(config.Framework)
				candidate.Framework[field] = value
				return validator.validate(candidate)
			end,
			ValidateConfig = validator.validate,
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
end
