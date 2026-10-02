--!strict
-- Direct callback contracts, not Roblox RemoteFunction transport emulation.
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Runtime = require("./test-runtime")

local callbacks = {}
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(instance)
	return callbacks[instance:GetDebugId()]
end, function(instance, value)
	callbacks[instance:GetDebugId()] = value
end)

local function success(data: any?): any
	return { Success = true, Code = "OK", Message = "Complete", Data = data }
end

local function await(predicate: () -> boolean)
	local deadline = os.clock() + 1
	while not predicate() and os.clock() < deadline do
		task.wait(0.001)
	end
	assert(predicate(), "Fixture task did not reach its bounded checkpoint")
end

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local replicated = runtime.services.ReplicatedStorage.RoleplayOS
		local config = table.clone(runtime.require(replicated.Config.Config).Network)
		config.GlobalCapacity, config.GlobalRefillPerSecond = 100, 0
		config.Endpoints = { Test = { Capacity = 100, RefillPerSecond = 0 } }
		config.HandlerTimeoutSeconds, config.RequestAbandonSeconds = 0.03, 0.15
		-- Explicit JSON adapter; this does not certify Roblox's encoder semantics.
		runtime.services.HttpService.JSONEncode = function(_self, payload)
			return serde.encode("json", payload)
		end
		local logs = {}
		local logger = {}
		for _, level in { "Security", "Error", "Warning" } do
			logger[level] = function(_self, message, fields)
				table.insert(logs, { Level = level, Message = message, Fields = fields })
			end
		end
		local serverRoot = runtime.services.ServerScriptService.RoleplayOS
		local gateway = runtime.require(serverRoot.Systems.NetworkServer).new(config, logger)
		local f = { Gateway = gateway, Config = config, Runtime = runtime, Logs = logs }
		function f:Register(handler: any?, schema: any?)
			gateway:RegisterFunction("Test", schema or function()
				return true
			end, handler or function()
				return success()
			end)
		end
		function f:Invoke(userId: number?, payload: any?): any
			return callbacks[gateway.endpoints.Test:GetDebugId()](
				{ UserId = userId or 10 },
				payload or {}
			)
		end
		function f:Destroy()
			gateway:Destroy()
			for _, remote in gateway.folder:GetChildren() do
				callbacks[remote:GetDebugId()] = nil
			end
			gateway.folder:Destroy()
		end
		return f
	end

	H.test("actual gateway owns fresh endpoints and readiness", function()
		local f = fixture()
		H.expect(f.Gateway.folder:GetAttribute("Ready") == false, "premature readiness")
		f:Register()
		H.expect(not pcall(function()
			f:Register()
		end), "duplicate endpoint accepted")
		f.Gateway:MarkReady()
		H.expect(f.Gateway.folder:GetAttribute("Ready") == true, "readiness missing")
		f.Gateway:BeginShutdown()
		H.expect(f:Invoke().Code == "SERVER_SHUTTING_DOWN", "closed gateway accepted work")
		H.expect(f.Gateway.folder:GetAttribute("Ready") == false, "shutdown remained ready")
		f:Destroy()
	end)

	H.test("actual gateway fails closed on pending or failed authorisation", function()
		local f = fixture()
		local calls = 0
		f:Register(function()
			calls += 1
			return success()
		end)
		for _, authorizer in
			{
				function()
					return false
				end,
				function()
					error("private authorisation error")
				end,
				function()
					return "truthy"
				end,
			}
		do
			f.Gateway:SetAuthorizer(authorizer)
			H.expect(f:Invoke().Code == "ACCESS_PENDING", "authorisation escaped gate")
		end
		H.expect(calls == 0 and f.Gateway.activeTotal == 0, "denial ran handler")
		f.Gateway:SetAuthorizer(function()
			return true
		end)
		H.expect(f:Invoke().Success and calls == 1, "authorised request refused")
		f:Destroy()
	end)

	H.test(
		"actual gateway rejects structural, encoding and schema failures before handler",
		function()
			local f = fixture()
			local calls = 0
			local schema = function(_payload)
				return true
			end
			f:Register(function()
				calls += 1
				return success()
			end, function(payload)
				return schema(payload)
			end)
			local cycle = {}
			cycle.Self = cycle
			for _, payload in
				{ cycle, { Value = math.huge }, { Value = roblox.Instance.new("Folder") } }
			do
				H.expect(
					f:Invoke(10, payload).Code == "PAYLOAD_REJECTED",
					"unsafe payload accepted"
				)
			end
			f.Config.MaximumPayloadBytes = 2
			H.expect(
				f:Invoke(10, { Text = "larger" }).Code == "PAYLOAD_REJECTED",
				"byte cap bypassed"
			)
			f.Config.MaximumPayloadBytes = 8192
			f.Runtime.services.HttpService.JSONEncode = function()
				error("encoder failure")
			end
			H.expect(f:Invoke().Code == "PAYLOAD_REJECTED", "encoder error escaped")
			f.Runtime.services.HttpService.JSONEncode = function(_self, payload)
				return serde.encode("json", payload)
			end
			for _, validator in
				{
					function(_payload)
						return false, "invalid"
					end,
					function(_payload)
						error("private schema error")
					end,
				}
			do
				schema = validator
				H.expect(f:Invoke().Code == "INVALID_REQUEST", "schema failure escaped")
			end
			H.expect(calls == 0 and f.Gateway.activeTotal == 0, "invalid request ran handler")
			f:Destroy()
		end
	)

	H.test("actual gateway applies endpoint and global rate limits and drains counts", function()
		for _, level in { "endpoint", "global" } do
			local f = fixture()
			if level == "endpoint" then
				f.Config.Endpoints.Test.Capacity = 1
			else
				f.Gateway.globalLimiter.capacity = 1
			end
			f:Register()
			H.expect(f:Invoke().Success, "first request refused")
			H.expect(f:Invoke().Code == "RATE_LIMITED", "bucket exceeded")
			H.expect(f:Invoke(20).Success, "one user's rate limit affected another")
			H.expect(f.Gateway:DrainCounts().RATE_LIMITED == 1, "outcome count lost")
			H.expect(next(f.Gateway:DrainCounts()) == nil, "drained counts retained")
			f:Destroy()
		end
	end)

	H.test("actual gateway sanitises handler errors and reconstructs response envelopes", function()
		local f = fixture()
		local answer: any = success({ Position = roblox.Vector3.new(1, 2, 3) })
		answer.InternalSecret, answer.RequestId = "private", "forged"
		f:Register(function()
			if answer == "throw" then
				error("private handler error")
			end
			return answer
		end)
		local result = f:Invoke()
		H.expect(result.Success and result.Data.Position.X == 1, "valid Vector3 response rejected")
		H.expect(
			result.InternalSecret == nil and result.RequestId ~= "forged",
			"internal fields escaped"
		)
		for _, invalid in
			{
				"throw",
				true,
				{ Success = true, Code = "bad code", Message = "private" },
				success({ Value = math.huge }),
				success({ Value = roblox.Instance.new("Folder") }),
			}
		do
			answer = invalid
			result = f:Invoke()
			H.expect(
				result.Code == "SERVER_ERROR"
					and result.Message == "The request could not be completed.",
				"unsafe handler response escaped"
			)
			H.expect(
				f.Gateway.activeTotal == 0 and next(f.Gateway.active) == nil,
				"completed handler retained slot"
			)
		end
		f:Destroy()
	end)

	H.test("actual gateway rechecks shutdown after yielding authorisation", function()
		local f = fixture()
		local calls = 0
		f:Register(function()
			calls += 1
			return success()
		end)
		f.Gateway:SetAuthorizer(function()
			task.wait(0.001)
			f.Gateway:BeginShutdown()
			return true
		end)
		H.expect(f:Invoke().Code == "SERVER_SHUTTING_DOWN", "shutdown race started handler")
		H.expect(calls == 0 and f.Gateway.activeTotal == 0, "shutdown acquired slot")
		f:Destroy()
	end)

	H.test(
		"actual gateway keeps timed-out work counted until abandonment and releases once",
		function()
			local f = fixture()
			f.Config.MaximumConcurrentRequests = 1
			local done = false
			f:Register(function()
				task.wait(0.22)
				done = true
				return success()
			end)
			H.expect(f:Invoke().Code == "SERVER_TIMEOUT", "handler deadline not enforced")
			H.expect(f.Gateway.activeTotal == 1, "timeout released running work too early")
			H.expect(f:Invoke().Code == "SERVER_BUSY", "timed-out work bypassed user cap")
			local drained, count = f.Gateway:DrainActive(0)
			H.expect(not drained and count == 1, "drain hid running work")
			await(function()
				return f.Gateway.activeTotal == 0
			end)
			H.expect(
				next(f.Gateway.active) == nil and next(f.Gateway.activeSlots) == nil,
				"abandonment retained slot"
			)
			await(function()
				return done
			end)
			H.expect(f.Gateway.activeTotal == 0 and #f.Logs == 2, "late completion released twice")
			f:Destroy()
		end
	)

	H.test("server-busy refusals do not retain empty per-user tracking", function()
		local f = fixture()
		f.Config.MaximumConcurrentRequestsPerServer = 1
		f.Config.HandlerTimeoutSeconds = 0.3
		f.Config.RequestAbandonSeconds = 0.5
		local release, completed = false, false
		f:Register(function()
			local deadline = os.clock() + 0.4
			while not release and os.clock() < deadline do
				task.wait(0.001)
			end
			return success()
		end)
		task.spawn(function()
			f:Invoke()
			completed = true
		end)
		await(function()
			return f.Gateway.activeTotal == 1
		end)
		local clean = true
		for userId = 20, 29 do
			H.expect(f:Invoke(userId).Code == "SERVER_BUSY", "server concurrency cap bypassed")
			clean = clean and f.Gateway.active[userId] == nil
		end
		release = true
		await(function()
			return completed
		end)
		clean = clean and f.Gateway.activeTotal == 0 and next(f.Gateway.active) == nil
		f:Destroy()
		H.expect(clean, "server-busy refusals retained empty per-user tracking")
	end)

	H.test(
		"gateway teardown prevents late callbacks changing counts or logging abandonment",
		function()
			local f = fixture()
			local finished = false
			f:Register(function()
				task.wait(0.2)
				finished = true
				return success()
			end)
			H.expect(f:Invoke().Code == "SERVER_TIMEOUT", "fixture did not time out")
			f:Destroy()
			await(function()
				return finished
			end)
			H.expect(
				f.Gateway.activeTotal == 0
					and next(f.Gateway.activeSlots) == nil
					and next(f.Gateway.active) == nil,
				"teardown counters resurrected"
			)
			H.expect(#f.Logs == 1, "late abandonment warned after teardown")
		end
	)
end
