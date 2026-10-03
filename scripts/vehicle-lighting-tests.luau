--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	H.test("road-light controls resolve the adopted driver vehicle from seat ancestry", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleLightingService)
		local players = runtime.services.Players
		local workspace = runtime.services.Workspace

		local player: any = {}
		local character: any = {}
		local humanoid: any = {}
		local vehicle: any = { Parent = workspace }
		local chassis: any = { Parent = vehicle }
		local seat: any = {
			Parent = chassis,
			Occupant = { Parent = character },
			IsA = function(_self, className)
				return className == "VehicleSeat"
			end,
			IsDescendantOf = function(_self, candidate)
				return candidate == vehicle
			end,
		}
		humanoid.SeatPart = seat
		character.FindFirstChildWhichIsA = function(_self, className)
			return if className == "Humanoid" then humanoid else nil
		end
		player.Character = character
		players.GetPlayerFromCharacter = function(_self, candidate)
			return if candidate == character then player else nil
		end

		local unrelated: any = { Parent = workspace }
		unrelated.FindFirstChildWhichIsA = function()
			error("road-light authorisation scanned an unrelated adopted vehicle")
		end
		service.vehicles = {
			[unrelated] = { Seat = nil },
			[vehicle] = { Seat = seat },
		}

		H.expect(
			service:_vehicleFor(player) == vehicle,
			"driver was not resolved from the occupied adopted vehicle"
		)
	end)

	H.test("road-light controls do not authorise a passenger VehicleSeat", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleLightingService)
		local players = runtime.services.Players
		local workspace = runtime.services.Workspace

		local player: any = {}
		local character: any = {}
		local humanoid: any = {}
		local vehicle: any = { Parent = workspace }
		local driverSeat: any = {
			Parent = vehicle,
			Occupant = nil,
			IsDescendantOf = function(_self, candidate)
				return candidate == vehicle
			end,
		}
		local passengerSeat: any = {
			Parent = vehicle,
			Occupant = { Parent = character },
			IsA = function(_self, className)
				return className == "VehicleSeat"
			end,
		}
		humanoid.SeatPart = passengerSeat
		character.FindFirstChildWhichIsA = function(_self, className)
			return if className == "Humanoid" then humanoid else nil
		end
		player.Character = character
		players.GetPlayerFromCharacter = function()
			error("passenger lookup should fail before occupant authority resolution")
		end
		service.vehicles = { [vehicle] = { Seat = driverSeat } }

		H.expect(
			service:_vehicleFor(player) == nil,
			"passenger VehicleSeat gained road-light control"
		)
	end)

	H.test("road-light driver seat cache refreshes after chassis reparenting", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleLightingService)
		local workspace = runtime.services.Workspace

		local scans = 0
		local vehicle: any
		local staleSeat: any = { Parent = true, InVehicle = false }
		staleSeat.IsDescendantOf = function(self, candidate)
			return self.InVehicle and candidate == vehicle
		end
		local replacementSeat: any = { Parent = true, InVehicle = true }
		replacementSeat.IsDescendantOf = function(self, candidate)
			return self.InVehicle and candidate == vehicle
		end
		vehicle = {
			Parent = workspace,
			FindFirstChildWhichIsA = function(_self, className, recursive)
				H.expect(
					className == "VehicleSeat" and recursive == true,
					"driver-seat cache refreshed an unexpected class"
				)
				scans += 1
				return replacementSeat
			end,
		}
		local state: any = { Seat = staleSeat }

		H.expect(
			service:_driverSeat(vehicle, state) == replacementSeat and scans == 1,
			"reparented driver seat was not refreshed exactly once"
		)
		H.expect(
			service:_driverSeat(vehicle, state) == replacementSeat and scans == 1,
			"replacement driver seat was rescanned on the next lookup"
		)
	end)
end
