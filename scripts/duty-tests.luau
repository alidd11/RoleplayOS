--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local tasks = table.clone(runtime.globals.task)
		tasks.defer = function(callback)
			callback()
		end
		runtime.globals.task = tasks
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local duty = runtime.require(root.DutyService)
		local taxi = runtime.require(root.TaxiService)
		local employment = runtime.require(root.EmploymentService)
		local police, transport = { Name = "Police" }, { Name = "Transport" }
		local player = { UserId = 1, Parent = runtime.services.Players, Team = police }
		runtime.services.Players.GetPlayerByUserId = function()
			return player
		end
		local character = { CharacterId = "active", Employment = {} }
		local session =
			{ ActiveCharacterId = "active", Profile = { Characters = { active = character } } }
		local row = { RoleId = "police", DepartmentId = "Police", TeamName = "Police" }
		local f: any = {
			Duty = duty,
			Taxi = taxi,
			Player = player,
			Row = row,
			Character = character,
			Unregisters = 0,
			AccessResult = { Allowed = true },
			Cleanup = 0,
		}
		local function cleanup()
			f.Cleanup += 1
		end
		local deps = {
			DataService = {
				GetSession = function()
					return session
				end,
				MarkDirty = function() end,
			},
			TeamService = {
				Get = function(_self, name)
					assert(name == "Police" or name == "Transport", "Unexpected team lookup")
					return if name == "Police" then police else transport
				end,
			},
			PhoneService = {},
			EmploymentService = employment,
			AccessService = {
				Evaluate = function()
					task.wait()
					if f.DuringAccess then
						f.DuringAccess()
					end
					return f.AccessResult
				end,
			},
			UnitService = {
				units = { ["1"] = { DepartmentId = "Police" } },
				Unregister = function()
					f.Unregisters += 1
				end,
			},
			DispatchService = { running = false },
			LoadoutService = { ClearIssued = cleanup },
			UniformService = { Restore = cleanup },
			ImportedSystemAdapterService = { ClearEpaulettes = cleanup },
			IdentificationService = { Refresh = cleanup },
			AuditService = { Record = function() end },
		}
		local context = {
			Configuration = {
				Roles = { police = { DepartmentId = "Police", TeamName = "Police", Access = {} } },
				Jobs = { TaxiDriver = { Class = "Public" } },
				Framework = { MaximumEmploymentHistory = 40 },
				Taxi = {},
			},
			Services = {
				Get = function(_self, name)
					return assert(deps[name], "Unexpected duty dependency: " .. name)
				end,
			},
		}
		employment:Init(context)
		taxi:Init(context)
		taxi.running = true
		duty:Init(context)
		duty.running = true
		duty.active[1] = row
		function f:Destroy()
			duty:Destroy()
			taxi:Destroy()
			employment:Destroy()
		end
		return f
	end

	H.test("actual duty lookup rejects team change through a taxi shift during access", function()
		for _, result in
			{ { Allowed = true }, { Allowed = false, ReasonCode = "GROUP_CHECK_FAILED" } }
		do
			local f = fixture()
			f.AccessResult = result
			f.DuringAccess = function()
				H.expect(f.Taxi:StartShift(f.Player) ~= nil, "actual taxi shift failed")
			end
			local returned = f.Duty:Get(f.Player)
			H.expect(
				f.Player.Team.Name == "Transport" and #f.Character.Employment == 1,
				"taxi transition did not run"
			)
			H.expect(
				returned == nil and f.Duty.active[1] == nil,
				"stale Police duty escaped after team change"
			)
			H.expect(
				f.Unregisters == 1 and f.Cleanup == 4,
				"invalid shift did not use normal cleanup"
			)
			f:Destroy()
		end
	end)

	H.test("actual duty lookup preserves valid shifts across uncertain group access", function()
		for _, result in
			{ { Allowed = true }, { Allowed = false, ReasonCode = "GROUP_CHECK_FAILED" } }
		do
			local f = fixture()
			f.AccessResult = result
			H.expect(
				f.Duty:Get(f.Player) == f.Row
					and f.Duty.active[1] == f.Row
					and f.Unregisters == 0
					and f.Cleanup == 0,
				"valid shift was ended"
			)
			f:Destroy()
		end
	end)

	H.test("actual duty lookup retains definitive denial and replacement fences", function()
		local f = fixture()
		f.AccessResult = { Allowed = false, ReasonCode = "GROUP_RANK_REQUIRED" }
		H.expect(
			f.Duty:Get(f.Player) == nil and f.Unregisters == 1,
			"definitive denial retained duty"
		)
		f:Destroy()
		f = fixture()
		local replacement = table.clone(f.Row)
		f.DuringAccess = function()
			f.Duty.active[1] = replacement
		end
		H.expect(
			f.Duty:Get(f.Player) == nil and f.Duty.active[1] == replacement and f.Unregisters == 0,
			"old lookup ended replacement shift"
		)
		f:Destroy()
	end)
	H.test("duty rollback cleanup remains symmetrical with normal end", function()
		local f = fixture()
		local previousTeam = f.Player.Team
		f.Duty.active[1] = nil
		-- Exercise the same cleanup services a failed start must use by ending a
		-- synthetic partially-started shift through the public cleanup path.
		f.Duty.active[1] = f.Row
		f.Duty:End(f.Player)
		H.expect(f.Duty.active[1] == nil, "partial duty record survived cleanup")
		H.expect(f.Unregisters == 1, "partial unit registration survived cleanup")
		H.expect(f.Cleanup == 4, "issued duty presentation state survived cleanup")
		H.expect(f.Player.Team == previousTeam, "cleanup unexpectedly changed the team")
		f:Destroy()
	end)
end
