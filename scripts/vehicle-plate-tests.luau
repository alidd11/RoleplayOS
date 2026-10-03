--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	H.test("active owned vehicle lookup validates owner and persistent vehicle id", function()
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local spawner = runtime.require(root.VehicleSpawnerService)
		local vehicle = runtime.globals.Instance.new("Model")
		vehicle:SetAttribute("RoleplayOSOwnerUserId", 10)
		vehicle:SetAttribute("RoleplayOSVehicleId", "owned-vehicle")
		vehicle.Parent = runtime.services.Workspace
		spawner.active = { [10] = vehicle }

		H.expect(
			spawner:GetActiveOwnedVehicle(10, "owned-vehicle") == vehicle,
			"exact active owned vehicle was not resolved"
		)
		H.expect(
			spawner:GetActiveOwnedVehicle(10, "other") == nil
				and spawner:GetActiveOwnedVehicle(20, "owned-vehicle") == nil,
			"active vehicle lookup ignored owner or persistent vehicle identity"
		)

		vehicle:SetAttribute("RoleplayOSOwnerUserId", 11)
		H.expect(
			spawner:GetActiveOwnedVehicle(10, "owned-vehicle") == nil,
			"active vehicle lookup trusted its map without revalidating ownership"
		)
		vehicle:Destroy()
	end)

	H.test("owned plate refresh never scans the world", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local plate = runtime.require(root.VehiclePlateService)
		local vehicle = runtime.globals.Instance.new("Model")
		vehicle.Parent = runtime.services.Workspace
		local lookedUp = 0
		local appliedVehicle: any = nil
		local appliedRegistration: any = nil
		plate.context = {
			Services = {
				Get = function(_self, name)
					H.expect(name == "VehicleSpawnerService", "unexpected plate refresh dependency")
					return {
						GetActiveOwnedVehicle = function(_service, ownerUserId, vehicleId)
							lookedUp += 1
							return if ownerUserId == 10 and vehicleId == "owned-vehicle"
								then vehicle
								else nil
						end,
					}
				end,
			},
		}
		plate.Apply = function(_self, candidate, registration)
			appliedVehicle = candidate
			appliedRegistration = registration
			return 1
		end
		runtime.services.Workspace.GetDescendants = function()
			error("plate refresh scanned the whole workspace")
		end

		H.expect(
			plate:RefreshOwned(10, "owned-vehicle", "AB12 CDE"),
			"live owned vehicle plate refresh failed"
		)
		H.expect(
			lookedUp == 1
				and appliedVehicle == vehicle
				and appliedRegistration == "AB12 CDE",
			"plate refresh did not use the validated active vehicle"
		)
		H.expect(
			not plate:RefreshOwned(10, "missing", "ZZ99 ZZZ") and lookedUp == 2,
			"missing active vehicle was treated as refreshed"
		)
		vehicle:Destroy()
	end)
end
