--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")

return function(H: any)
	local function fixture(vehicles: any): any
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local original = runtime.require(shared.Config.Config)
		local config = table.clone(original)
		config.Vehicles = table.clone(original.Vehicles)
		config.Vehicles.TestVehicle = {
			Name = "Fixture vehicle",
			Category = "Civilian",
			Price = 40,
			Colours = { "Black" },
			Access = { AccessType = "Public" },
		}
		local schema = runtime.require(shared.Shared.ProfileSchema)
		local profile = schema.default(10)
		local character = {
			CharacterId = "owned",
			Vehicles = vehicles,
			Economy = { Cash = 5, Balance = 100, Transactions = {} },
		}
		profile.Characters.owned = character
		local migrated, problem = schema.migrate(profile, 10)
		assert(migrated == profile and problem == nil, "fixture migration failed")
		local player = { UserId = 10, Parent = runtime.services.Players }
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return if id == 10 and player.Parent == runtime.services.Players then player else nil
		end
		local f: any = {
			Player = player,
			Players = runtime.services.Players,
			Character = character,
			Profile = profile,
			Session = { ActiveCharacterId = "owned", Profile = profile },
			Reserved = {},
			ReserveCalls = 0,
			ReleaseCalls = 0,
			Dirty = 0,
			Indexed = 0,
		}
		local data = {
			GetSession = function(_self, candidate)
				return if candidate == player then f.Session else nil
			end,
			MarkDirty = function()
				f.Dirty += 1
			end,
			ReserveCustomRegistration = function(_self, registration, userId, vehicleId)
				assert(userId == 10, "wrong reservation owner")
				f.ReserveCalls += 1
				if f.ReserveFailure then
					return false, "REGISTRATION_STORE_UNAVAILABLE"
				end
				f.Reserved[registration] = vehicleId
				if f.OnReserve then
					f.OnReserve()
				end
				return true, nil
			end,
			ReleaseCustomRegistration = function(_self, registration, userId, vehicleId)
				assert(
					userId == 10 and f.Reserved[registration] == vehicleId,
					"wrong release owner"
				)
				f.Reserved[registration] = nil
				f.ReleaseCalls += 1
				return true, nil
			end,
		}
		local service = runtime.require(root.VehicleOwnershipService)
		local economy = runtime.require(root.EconomyService)
		local dependencies = {
			DataService = data,
			EconomyService = economy,
			AuditService = { Record = function() end },
			ContentValidationService = {
				GetVehicleDefinition = function(_self, id)
					return config.Vehicles[id]
				end,
			},
			AccessService = {
				Evaluate = function()
					return { Allowed = true }
				end,
			},
			RecordIndexService = {
				ScheduleVehicle = function()
					f.Indexed += 1
				end,
			},
		}
		local context = {
			Configuration = config,
			Logger = { Warning = function() end, Error = function() end },
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "unexpected vehicle dependency")
				end,
			},
		}
		service:Init(context)
		economy:Init(context)
		service.running, economy.running = true, true
		f.Service, f.Economy = service, economy
		function f:Purchase()
			return self.Service:Purchase(self.Player, "TestVehicle", "Black")
		end
		function f:Destroy()
			service:Destroy()
			economy:Destroy()
		end
		return f
	end

	H.test(
		"actual vehicle purchase refuses unreadable persisted ownership before charging",
		function()
			for _, vehicles in { 4, "unreadable", false } do
				local f = fixture(vehicles)
				local completed, vehicle, reason = pcall(function()
					return f:Purchase()
				end)
				H.expect(
					completed and vehicle == nil and reason == "INVALID_VEHICLE_STATE",
					string.format(
						"unreadable ownership threw or was accepted (balance=%d, transactions=%d, reservations=%d, result=%s)",
						f.Character.Economy.Balance,
						#f.Character.Economy.Transactions,
						f.ReserveCalls,
						tostring(vehicle)
					)
				)
				H.expect(
					f.Character.Vehicles == vehicles
						and f.Character.Economy.Balance == 100
						and #f.Character.Economy.Transactions == 0,
					"refusal erased ownership or charged funds"
				)
				H.expect(
					f.ReserveCalls == 0 and next(f.Service.purchasing) == nil,
					"refusal reserved a plate or retained purchase claim"
				)
				f:Destroy()
			end
		end
	)

	H.test(
		"actual vehicle allocation rechecks ownership shape before payment and releases its plate",
		function()
			for _, purchase in { false, true } do
				local f = fixture({})
				f.OnReserve = function()
					task.wait(0.001)
					f.Character.Vehicles = "changed while reserving"
				end
				local completed, vehicle, reason = pcall(function()
					if purchase then
						return f:Purchase()
					end
					return f.Service:Create(f.Player, "owned", "TestVehicle", "Black", "garage")
				end)
				H.expect(
					completed and vehicle == nil and reason == "INVALID_VEHICLE_STATE",
					"late malformed ownership threw or was accepted"
				)
				H.expect(
					f.Character.Economy.Balance == 100
						and #f.Character.Economy.Transactions == 0
						and f.Character.Vehicles == "changed while reserving",
					"late shape refusal changed money or ownership"
				)
				H.expect(
					f.ReleaseCalls == 1
						and next(f.Reserved) == nil
						and next(f.Service.registrations) == nil,
					"late shape refusal leaked its registration"
				)
				f:Destroy()
			end
		end
	)

	H.test("actual vehicle creation refuses unreadable ownership before allocating", function()
		local f = fixture(4)
		local completed, vehicle, reason = pcall(function()
			return f.Service:Create(f.Player, "owned", "TestVehicle", "Black", "garage")
		end)
		H.expect(
			completed
				and vehicle == nil
				and reason == "INVALID_VEHICLE_STATE"
				and f.ReserveCalls == 0
				and f.Character.Vehicles == 4,
			"creation overwrote unreadable ownership or leaked a plate"
		)
		f:Destroy()
	end)

	H.test("actual valid vehicle purchase charges once and preserves existing ownership", function()
		local existing = { VehicleId = "existing", DefinitionId = "TestVehicle" }
		local f = fixture({ existing })
		local vehicle, reason = f:Purchase()
		H.expect(
			vehicle
				and reason == nil
				and f.Character.Vehicles[1] == existing
				and f.Character.Vehicles[2] == vehicle,
			"valid ownership append changed"
		)
		H.expect(
			f.Character.Economy.Balance == 60
				and f.Character.Economy.Cash == 5
				and #f.Character.Economy.Transactions == 1,
			"vehicle payment changed"
		)
		H.expect(
			f.Reserved[vehicle.Registration] == vehicle.VehicleId
				and f.Indexed == 1
				and next(f.Service.purchasing) == nil,
			"valid purchase lost registration/indexing or retained claim"
		)
		f:Destroy()
	end)

	H.test("registration lookup stays indexed after purchase without scanning players", function()
		local f = fixture({})
		local vehicle, reason = f:Purchase()
		H.expect(vehicle ~= nil and reason == nil, "fixture purchase failed")
		f.Players.GetPlayers = function()
			error("registration lookup scanned the full player population")
		end
		local found, owner = f.Service:GetByRegistration(vehicle.Registration)
		H.expect(
			found == vehicle and owner == f.Player,
			"newly purchased vehicle was not available through the registration index"
		)
		f:Destroy()
	end)

	H.test("registration index follows changes, cleanup and pending profile fallback", function()
		local vehicle = {
			VehicleId = "existing",
			OwnerCharacterId = "owned",
			DefinitionId = "TestVehicle",
			Registration = "AB123",
		}
		local f = fixture({ vehicle })
		f.Service:_indexLoadedVehicles(f.Player)
		f.Players.GetPlayers = function()
			error("registration lookup scanned the full player population")
		end

		local found, owner = f.Service:GetByRegistration("ab123")
		H.expect(found == vehicle and owner == f.Player, "loaded vehicle was not indexed")

		vehicle.Registration = "CD456"
		f.Service:_indexVehicle(f.Player, vehicle)
		local old = f.Service:GetByRegistration("AB123")
		local updated, updatedOwner = f.Service:GetByRegistration("cd456")
		H.expect(old == nil, "registration change retained the old index entry")
		H.expect(
			updated == vehicle and updatedOwner == f.Player,
			"registration change did not publish the new index entry"
		)

		f.Service:_clearRegistrationIndex(f.Player)
		H.expect(
			f.Service:GetByRegistration("CD456") == nil,
			"player cleanup retained an indexed registration"
		)

		f.Service.registrationIndexPending[f.Player] = true
		local pending, pendingOwner = f.Service:GetByRegistration("CD456")
		H.expect(
			pending == vehicle and pendingOwner == f.Player,
			"pending profile fallback lost a live vehicle during join recovery"
		)
		f.Service.registrationIndexPending[f.Player] = nil
		f:Destroy()
	end)

	H.test("actual failed vehicle reservation does not charge or insert ownership", function()
		local f = fixture({})
		f.ReserveFailure = true
		local vehicle, reason = f:Purchase()
		H.expect(
			vehicle == nil
				and reason == "REGISTRATION_STORE_UNAVAILABLE"
				and f.Character.Economy.Balance == 100
				and #f.Character.Vehicles == 0
				and next(f.Service.purchasing) == nil,
			"reservation failure charged or retained state"
		)
		f:Destroy()
	end)
end
