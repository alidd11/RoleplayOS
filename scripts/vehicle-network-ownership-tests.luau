--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function serviceFixture(): any
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehicleSpawnerService)
		service.networkOwners = {}
		service.networkOwnerVehicles = {}
		return service
	end

	H.test("vehicle network ownership keeps exact forward and reverse records", function()
		local service = serviceFixture()
		local firstPlayer: any = {}
		local secondPlayer: any = {}
		local vehicle: any = {}

		service:_rememberNetworkOwner(vehicle, firstPlayer)
		H.expect(
			service.networkOwners[vehicle] == firstPlayer
				and service.networkOwnerVehicles[firstPlayer] == vehicle,
			"initial physics ownership was not indexed both ways"
		)

		service:_rememberNetworkOwner(vehicle, secondPlayer)
		H.expect(
			service.networkOwners[vehicle] == secondPlayer
				and service.networkOwnerVehicles[firstPlayer] == nil
				and service.networkOwnerVehicles[secondPlayer] == vehicle,
			"driver takeover left a stale reverse ownership record"
		)

		H.expect(
			not service:_forgetNetworkOwner(vehicle, firstPlayer)
				and service.networkOwners[vehicle] == secondPlayer
				and service.networkOwnerVehicles[secondPlayer] == vehicle,
			"stale old-driver release disturbed the newer driver"
		)

		H.expect(
			service:_forgetNetworkOwner(vehicle, secondPlayer)
				and service.networkOwners[vehicle] == nil
				and service.networkOwnerVehicles[secondPlayer] == nil,
			"current driver release did not clear both ownership records"
		)
	end)

	H.test("player network ownership release uses the direct reverse index", function()
		local service = serviceFixture()
		local player: any = {}
		local targetVehicle: any = {}
		local unrelatedPlayer: any = {}
		local unrelatedVehicle: any = {}
		service.networkOwners[unrelatedVehicle] = unrelatedPlayer
		service.networkOwnerVehicles[player] = targetVehicle

		local releasedVehicle, releasedPlayer
		service._releaseVehicleNetworkOwner = function(_self, vehicle, owner)
			releasedVehicle = vehicle
			releasedPlayer = owner
		end

		service:_releasePlayerNetworkOwnership(player)
		H.expect(
			releasedVehicle == targetVehicle and releasedPlayer == player,
			"player release scanned forward ownership instead of using the reverse index"
		)
	end)

	H.test("destroyed vehicle release clears reverse network ownership state", function()
		local service = serviceFixture()
		local player: any = {}
		local vehicle: any = { Parent = nil }
		service.networkOwners[vehicle] = player
		service.networkOwnerVehicles[player] = vehicle

		service:_releaseVehicleNetworkOwner(vehicle, player)
		H.expect(
			service.networkOwners[vehicle] == nil and service.networkOwnerVehicles[player] == nil,
			"destroyed vehicle retained physics ownership state"
		)
	end)

	H.test("vehicle sanitiser strips nested client-callable legacy remotes", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local rigMechanics = runtime.require(root.VehicleSpawnerService.RigMechanics)
		local Instance = runtime.globals.Instance
		local vehicle = Instance.new("Model")
		vehicle.Name = "CorollaTaxi"

		local tune = Instance.new("Folder")
		tune.Name = "A-Chassis Tune"
		tune.Parent = vehicle
		local plugins = Instance.new("Folder")
		plugins.Name = "Plugins"
		plugins.Parent = tune

		local soundPlugin = Instance.new("Folder")
		soundPlugin.Name = "AC6_Stock_Sound"
		soundPlugin.Parent = plugins
		local soundRemote = Instance.new("RemoteEvent")
		soundRemote.Name = "AC6_FE_Sounds"
		soundRemote.Parent = soundPlugin

		local lightPlugin = Instance.new("Folder")
		lightPlugin.Name = "LightAddon"
		lightPlugin.Parent = plugins
		local lightRemote = Instance.new("RemoteEvent")
		lightRemote.Name = "SmeersLightsHandler"
		lightRemote.Parent = lightPlugin

		rigMechanics.sanitiseImportedVehicle(vehicle)

		H.expect(
			soundPlugin.Parent == plugins and lightPlugin.Parent == plugins,
			"sanitiser removed functional plugin containers instead of only legacy remotes"
		)
		H.expect(
			soundPlugin:FindFirstChild("AC6_FE_Sounds") == nil
				and lightPlugin:FindFirstChild("SmeersLightsHandler") == nil,
			"nested client-callable legacy vehicle remote survived sanitisation"
		)
		H.expect(
			vehicle:GetAttribute("RoleplayOSSafelyAdapted") == true,
			"security sanitisation was not recorded on the vehicle"
		)
	end)
end
