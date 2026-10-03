--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	H.test("vehicle telemetry caches the chassis engine control", function()
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleSpawnerService)

		local scans = 0
		local vehicle: any = {}
		local values: any = {}
		local currentEngine: any = nil
		local firstEngine: any = {
			Parent = values,
			Value = false,
			IsDescendantOf = function(_self, candidate)
				return candidate == vehicle
			end,
			IsA = function(_self, className)
				return className == "ValueBase"
			end,
		}
		local replacementEngine: any = {
			Parent = values,
			Value = false,
			IsDescendantOf = function(_self, candidate)
				return candidate == vehicle
			end,
			IsA = function(_self, className)
				return className == "ValueBase"
			end,
		}
		currentEngine = firstEngine
		values.Name = "Values"
		values.IsA = function(_self, className)
			return className == "Folder"
		end
		values.FindFirstChild = function(_self, name)
			return if name == "Engine" then currentEngine else nil
		end
		vehicle.GetDescendants = function()
			scans += 1
			return { values }
		end

		service.context = {
			Configuration = {
				Chassis = {
					ValuesFolderName = "Values",
					EngineValueName = "Engine",
				},
			},
		}
		local state: any = {}

		service:_setEngine(vehicle, true, state)
		H.expect(
			scans == 1 and state.Engine == firstEngine and firstEngine.Value == true,
			"initial engine control was not resolved and cached"
		)

		service:_setEngine(vehicle, false, state)
		H.expect(
			scans == 1 and firstEngine.Value == false,
			"cached engine control triggered another descendant scan"
		)

		firstEngine.Parent = nil
		currentEngine = replacementEngine
		service:_setEngine(vehicle, true, state)
		H.expect(
			scans == 2 and state.Engine == replacementEngine and replacementEngine.Value == true,
			"destroyed engine control was not refreshed exactly once"
		)

		service:_setEngine(vehicle, false, state)
		H.expect(scans == 2, "replacement engine control was rescanned on the next update")
	end)

	H.test("vehicle telemetry caches the resolved driver seat", function()
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleSpawnerService)

		local scans = 0
		local cachedSeat: any = { Parent = true, Occupant = nil, InVehicle = true }
		cachedSeat.IsDescendantOf = function(self, candidate)
			return self.InVehicle and candidate == vehicle
		end
		local replacementSeat: any = { Parent = true, Occupant = nil, InVehicle = true }
		replacementSeat.IsDescendantOf = function(self, candidate)
			return self.InVehicle and candidate == vehicle
		end
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

		cachedSeat.InVehicle = false
		service:_consumeTick(1)
		H.expect(
			scans == 1 and service.telemetry[10].Seat == replacementSeat,
			"telemetry did not refresh a reparented cached seat exactly once"
		)

		service:_consumeTick(1)
		H.expect(scans == 1, "telemetry rescanned the replacement seat on the next tick")
	end)
end
