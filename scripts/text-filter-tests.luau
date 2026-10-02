--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")

local function await(predicate: () -> boolean, seconds: number)
	local deadline = os.clock() + seconds
	while not predicate() and os.clock() < deadline do
		task.wait(0.005)
	end
	assert(predicate(), "Text-filter fixture missed its bounded checkpoint")
end

return function(H: any)
	local function fixture(studio: boolean?): any
		local runtime = Runtime.new()
		local scheduler = table.clone(task)
		runtime.globals.task = scheduler
		runtime.services.RunService.IsStudio = function()
			return studio == true
		end
		local f: any = { Calls = {}, Scheduler = scheduler }
		f.Filter = function()
			return {
				GetNonChatStringForBroadcastAsync = function()
					return "approved broadcast"
				end,
				GetNonChatStringForUserAsync = function(_self, recipient)
					return "approved for " .. tostring(recipient)
				end,
			}
		end
		runtime.services.TextService.FilterStringAsync = function(_self, text, userId, context)
			table.insert(f.Calls, { Text = text, UserId = userId, Context = context })
			return f.Filter()
		end
		f.Service =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Systems.TextFilter)
		return f
	end

	H.test("text filtering keeps the Studio bypass separate from the live path", function()
		local f = fixture(true)
		H.expect(f.Service.forBroadcast("raw input", 10) == "raw input", "Studio bypass changed")
		H.expect(#f.Calls == 0, "Studio bypass contacted the RPC fixture")
		local value, reason = f.Service.forBroadcast("", 10)
		H.expect(value == nil and reason == "TEXT_FILTER_INVALID_INPUT", "empty input accepted")
	end)

	H.test("live filtering selects broadcast and recipient-specific extraction", function()
		local f = fixture()
		H.expect(
			f.Service.forBroadcast("raw input", 10) == "approved broadcast",
			"raw broadcast leaked"
		)
		H.expect(
			f.Service.forUser("private input", 10, 20) == "approved for 20",
			"wrong recipient extraction"
		)
		H.expect(#f.Calls == 2 and f.Calls[2].UserId == 10, "wrong filter author")
	end)

	H.test("filter and extraction failures refuse raw text and release capacity", function()
		local f = fixture()
		local healthy = f.Filter
		for _, failure in
			{
				function()
					error("injected RPC failure")
				end,
				function()
					return {
						GetNonChatStringForBroadcastAsync = function()
							error("injected extraction failure")
						end,
					}
				end,
				function()
					return {
						GetNonChatStringForBroadcastAsync = function()
							return ""
						end,
					}
				end,
			}
		do
			f.Filter = failure
			for _ = 1, 20 do
				local value, reason = f.Service.forBroadcast("must not leak", 10)
				H.expect(
					value == nil and reason == "TEXT_FILTER_UNAVAILABLE",
					"failure exposed raw text or leaked a slot"
				)
			end
		end
		f.Filter = healthy
		H.expect(f.Service.forBroadcast("recovery", 10) == "approved broadcast", "recovery refused")
	end)

	H.test(
		"broadcast batches wait for all fields and discard partial successes on failure",
		function()
			local f = fixture()
			local healthy = f.Filter
			f.Filter = function()
				task.wait(0.01)
				return healthy()
			end
			local result = f.Service.manyForBroadcast({ first = "first", second = "second" }, 10)
			H.expect(
				result
					and result.first == "approved broadcast"
					and result.second == "approved broadcast",
				"batch lost a field"
			)
			local count = 0
			f.Filter = function()
				count += 1
				if count == 1 then
					error("injected batch failure")
				end
				return healthy()
			end
			local partial, reason =
				f.Service.manyForBroadcast({ first = "first", second = "second" }, 10)
			H.expect(
				partial == nil and reason == "TEXT_FILTER_UNAVAILABLE",
				"partial batch escaped"
			)
		end
	)

	local function timeoutBatch(f: any): any
		local results = {}
		local completed = 0
		for index = 1, 16 do
			task.spawn(function()
				local value, reason = f.Service.forBroadcast("delayed input", index)
				results[index] = { Value = value, Reason = reason }
				completed += 1
			end)
		end
		await(function()
			return completed == 16
		end, 6)
		return results
	end

	H.test("successfully cancelled filter workers free their admission slots", function()
		local f = fixture()
		local healthy = f.Filter
		local workers = {}
		f.Filter = function()
			table.insert(workers, coroutine.running())
			task.wait(5)
			return healthy()
		end
		local results = timeoutBatch(f)
		for index, result in results do
			H.expect(
				result.Value == nil and result.Reason == "TEXT_FILTER_TIMEOUT",
				"timeout exposed text"
			)
			H.expect(coroutine.status(workers[index]) == "dead", "worker was not cancelled")
		end
		f.Filter = healthy
		H.expect(
			f.Service.forBroadcast("recovery", 10) == "approved broadcast",
			"cancelled workers retained capacity"
		)
	end)

	H.test("uncancellable filter workers remain counted until they actually finish", function()
		local f = fixture()
		local healthy = f.Filter
		local release = false
		local completed = 0
		f.Scheduler.cancel = function()
			error("injected cancellation refusal")
		end
		f.Filter = function()
			local deadline = os.clock() + 6
			while not release and os.clock() < deadline do
				task.wait(0.005)
			end
			completed += 1
			return healthy()
		end
		local results = timeoutBatch(f)
		-- The extra RPC would finish immediately, making premature admission visible.
		f.Filter = healthy
		local value, reason = f.Service.forBroadcast("replacement", 20)
		local callsBeforeRelease = #f.Calls
		release = true
		await(function()
			return completed == 16
		end, 2)
		H.expect(
			value == nil and reason == "TEXT_FILTER_BUSY",
			"replacement admitted while 16 workers still ran"
		)
		H.expect(callsBeforeRelease == 16, "admission exceeded the worker cap")
		for _, result in results do
			H.expect(
				result.Value == nil and result.Reason == "TEXT_FILTER_TIMEOUT",
				"late completion changed a timed-out result"
			)
		end
		H.expect(
			f.Service.forBroadcast("recovery", 20) == "approved broadcast",
			"completed workers retained capacity"
		)
		H.expect(#f.Calls == 17, "recovery did not reuse exactly one released slot")
	end)
end
