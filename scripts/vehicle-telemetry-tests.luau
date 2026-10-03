--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	H.test("vehicle telemetry caches the resolved driver seat", function()
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleSpawnerService)

		local scans = 0
		local cachedSeat: any = { Parent = true, Occupant = nil }
		local replacementSeat: any = { Parent = true, Occupant = nil }
		local vehicle: any = {
			Parent = true,
			GetPivot = function()
				return { Position = {} }
			end,
			FindFirstChildWhichIsA = function(_self, className, recursive)
				H.expect(
					className == "VehicleSeat" and recursive == true,
					"telemetry resolved an unexpected descendant class"
				)
				scans += 1
				return replacementSeat
			end,
		}
		service.context = { Configuration = { VehicleData = {} } }
		service.telemetry = {
			[10] = {
				Vehicle = vehicle,
				Seat = cachedSeat,
			},
		}

		service:_consumeTick(1)
		H.expect(scans == 0, "telemetry rescanned a vehicle with a valid cached seat")

		cachedSeat.Parent = nil
		service:_consumeTick(1)
		H.expect(
			scans == 1 and service.telemetry[10].Seat == replacementSeat,
			"telemetry did not refresh a destroyed cached seat exactly once"
		)

		service:_consumeTick(1)
		H.expect(scans == 1, "telemetry rescanned the replacement seat on the next tick")
	end)
end
