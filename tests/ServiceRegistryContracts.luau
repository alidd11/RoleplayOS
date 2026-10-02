--!strict
local Registry = require(game:GetService("ServerScriptService").RoleplayOS.Systems.ServiceRegistry)

return function(H: any)
	local function context(): any
		local logs = {}
		return {
			Logger = {
				Info = function() end,
				Error = function(_self, message, metadata)
					table.insert(logs, { Message = message, Metadata = metadata })
				end,
			},
			Logs = logs,
		}
	end
	local function service(flags: any?): any
		local result = table.clone(flags or {})
		result.Init = function() end
		result.Start = function() end
		result.Destroy = function() end
		return result
	end
	H.test("service registry refuses duplicate and unknown registrations", function()
		local registry = Registry.new()
		local first = service()
		registry:Register("first", first)
		H.expect(registry:Get("first") == first, "registry changed service identity")
		H.expect(not pcall(function()
			registry:Register("first", service())
		end), "duplicate service accepted")
		H.expect(not pcall(function()
			registry:Get("unknown")
		end), "unknown service accepted")
	end)
	H.test("required service failures abort both startup phases by default", function()
		for _, phase in { "Init", "Start" } do
			for _, flags in { {}, { Critical = false }, { Optional = false } } do
				local registry, ctx = Registry.new(), context()
				local broken, later = service(flags), service()
				local laterRan = false
				broken[phase] = function()
					error("injected required failure")
				end
				later[phase] = function()
					laterRan = true
				end
				registry:Register("Required", broken)
				registry:Register("Later", later)
				if phase == "Start" then
					registry:Initialise(ctx)
				end
				local ok, problem = pcall(function()
					if phase == "Init" then
						registry:Initialise(ctx)
					else
						registry:Start(ctx)
					end
				end)
				H.expect(
					not ok and string.find(tostring(problem), "Required", 1, true),
					"required failure silently degraded"
				)
				H.expect(not laterRan, "startup continued after required failure")
			end
		end
	end)
	H.test("explicit optional initialisation failure never starts that service", function()
		local registry, ctx = Registry.new(), context()
		local optional, later = service({ Optional = true }), service()
		local optionalStarted, laterStarted = false, false
		optional.Init = function()
			error("optional init failure")
		end
		optional.Start = function()
			optionalStarted = true
		end
		later.Start = function()
			laterStarted = true
		end
		registry:Register("Optional", optional)
		registry:Register("Later", later)
		registry:Initialise(ctx)
		registry:Start(ctx)
		H.expect(
			not optionalStarted and laterStarted,
			"optional init failure broke startup sequencing"
		)
		H.expect(
			#ctx.Logs == 1 and ctx.Logs[1].Metadata.Phase == "Init",
			"optional failure not logged"
		)
		H.expect(registry:Get("Optional") == optional, "optional service was removed from registry")
	end)
	H.test("explicit optional startup failures are reported in a detached sorted list", function()
		local registry, ctx = Registry.new(), context()
		for _, name in { "Zulu", "Alpha" } do
			local optional = service({ Optional = true })
			optional.Start = function()
				error("optional start failure")
			end
			registry:Register(name, optional)
		end
		registry:Initialise(ctx)
		registry:Start(ctx)
		local failed = registry:Failed()
		H.expect(
			#failed == 2 and failed[1] == "Alpha" and failed[2] == "Zulu",
			"degraded services not sorted"
		)
		table.clear(failed)
		H.expect(#registry:Failed() == 2 and #ctx.Logs == 2, "caller mutated failure state")
	end)
	H.test("critical service cannot be downgraded by a conflicting optional flag", function()
		for _, phase in { "Init", "Start" } do
			local registry, ctx = Registry.new(), context()
			local critical = service({ Critical = true, Optional = true })
			critical[phase] = function()
				error("critical failure")
			end
			registry:Register("Critical", critical)
			if phase == "Start" then
				registry:Initialise(ctx)
			end
			H.expect(not pcall(function()
				if phase == "Init" then
					registry:Initialise(ctx)
				else
					registry:Start(ctx)
				end
			end), "critical failure degraded")
		end
	end)
	H.test(
		"service lifecycle preserves initialisation order and reverse teardown despite failures",
		function()
			local registry, ctx = Registry.new(), context()
			local trace = {}
			for _, name in { "Data", "Domain", "Network" } do
				local entry = service()
				entry.Init = function()
					table.insert(trace, "Init:" .. name)
				end
				entry.Start = function()
					table.insert(trace, "Start:" .. name)
				end
				entry.Destroy = function()
					table.insert(trace, "Destroy:" .. name)
					if name == "Domain" then
						error("teardown failure")
					end
				end
				registry:Register(name, entry)
			end
			registry:Initialise(ctx)
			registry:Start(ctx)
			registry:Destroy(ctx)
			H.expect(
				table.concat(trace, ",")
					== "Init:Data,Init:Domain,Init:Network,Start:Data,Start:Domain,Start:Network,Destroy:Network,Destroy:Domain,Destroy:Data",
				"lifecycle order or final persistence teardown changed"
			)
			H.expect(
				#ctx.Logs == 1 and ctx.Logs[1].Metadata.Service == "Domain",
				"teardown failure not reported"
			)
		end
	)
end
