--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(maximum: number?): any
		local runtime = Runtime.new()
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(root.Config.Config)
		config.Framework.AuditMaximumPendingEntries = maximum
		local service =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Services.AuditService)
		local f: any = { Service = service, Stored = {}, FailWrite = false, Writes = 0 }
		local data = {
			UpdateSharedRecord = function(_self, _key, transform)
				f.Writes += 1
				if f.FailWrite then
					return nil, "INJECTED_WRITE_FAILURE"
				end
				f.Stored = transform(table.clone(f.Stored))
				return table.clone(f.Stored), nil
			end,
		}
		service:Init({
			Configuration = config,
			Logger = { Error = function() end, Warning = function() end, Audit = function() end },
			Services = {
				Get = function(_self, name)
					assert(name == "DataService", "Unexpected audit fixture dependency")
					return data
				end,
			},
		})
		f.Record = function(_self, id)
			service:Record({ AuditId = id, Action = "CONTRACT_TEST", Timestamp = 1 })
		end
		return f
	end

	-- Temporary, bounded reproduction: removed once the startup guard is fixed.
	H.test("audit diagnostic confirms an infinite pending bound retains 600 rows", function()
		local f = fixture(math.huge)
		for index = 1, 600 do
			f:Record(tostring(index))
		end
		H.expect(
			f.Service.pendingCount == 600 and f.Service.droppedPending == 0,
			"unsafe configuration did not reproduce the missing cap"
		)
	end)

	H.test("actual audit rings retain newest entries under explicit and fallback caps", function()
		for _, maximum in { 25, 500 } do
			local f = fixture(if maximum == 500 then nil else maximum)
			for index = 1, 600 do
				f:Record(tostring(index))
			end
			H.expect(f.Service.count == 500, "recent audit ring grew beyond its cap")
			H.expect(
				f.Service.pendingCount == maximum and f.Service.droppedPending == 600 - maximum,
				"pending ring did not bound and report loss"
			)
			local batch = f.Service:_takePending()
			H.expect(
				#batch == maximum
					and batch[1].AuditId == tostring(601 - maximum)
					and batch[maximum].AuditId == "600",
				"pending chronology changed"
			)
			H.expect(
				f.Service.pendingCount == 0 and next(f.Service.pending) == nil,
				"taking the pending batch retained entries"
			)
		end
	end)

	H.test("actual audit failed flush restores bounded order and deduplicates retry IDs", function()
		local f = fixture(25)
		f:Record("first")
		f:Record("second")
		f.FailWrite = true
		H.expect(
			not f.Service:Flush() and f.Service.pendingCount == 2 and not f.Service.flushBusy,
			"failed flush discarded the batch or retained its claim"
		)
		f.FailWrite = false
		f:Record("third")
		H.expect(
			f.Service:Flush() and f.Service.pendingCount == 0 and #f.Stored == 3,
			"recovery did not persist the retained batch"
		)
		H.expect(
			f.Stored[1].AuditId == "first" and f.Stored[3].AuditId == "third",
			"failed-write recovery changed chronology"
		)
		f:Record("second")
		H.expect(
			f.Service:Flush() and #f.Stored == 3 and f.Writes == 3,
			"repeated audit ID duplicated its durable row"
		)
	end)
end
