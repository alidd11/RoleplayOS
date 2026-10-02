--!strict
local Runtime = require("./test-runtime")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

return function(H: any)
	local function fixture(employment: any?): any
		local runtime = Runtime.new()
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(root.Config.Config)
		local schema = runtime.require(root.Shared.ProfileSchema)
		local profile = schema.default(10)
		local character =
			{ CharacterId = "owned", Employment = employment or { { JobId = "TaxiDriver" } } }
		profile.Characters.owned = character
		local migrated, reason = schema.migrate(profile, 10)
		assert(migrated == profile and reason == nil, "Payroll fixture failed current migration")
		local model = roblox.Instance.new("Model")
		local part = roblox.Instance.new("Part")
		part.Name, part.Parent = "HumanoidRootPart", model
		-- Lune does not supply this engine default; give the fixture an explicit position.
		part.Position = roblox.Vector3.new(0, 0, 0)
		local player = { UserId = 10, Parent = runtime.services.Players, Character = model }
		runtime.services.Players.GetPlayerByUserId = function(_self, userId)
			return if userId == player.UserId and player.Parent == runtime.services.Players
				then player
				else nil
		end
		local f: any = {
			Player = player,
			Character = character,
			Root = part,
			Model = model,
			Config = config,
			Session = { Profile = profile, ActiveCharacterId = "owned" },
			Payments = {},
		}
		local dependencies = {
			DutyService = {
				Get = function()
					if f.DutyQuery then
						f.DutyQuery()
					end
					return f.Duty
				end,
			},
			DataService = {
				GetSession = function(_self, candidate)
					return if candidate == player then f.Session else nil
				end,
			},
			EconomyService = {
				Apply = function(_self, candidate, transaction)
					assert(candidate == player, "Payroll paid the wrong player")
					table.insert(f.Payments, transaction)
					return transaction, nil
				end,
			},
		}
		local service =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Services.PayrollService)
		service:Init({
			Configuration = config,
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "Unexpected payroll fixture dependency")
				end,
			},
		})
		service.running = true
		f.Service = service
		f.Destroy = function()
			service:Destroy()
			model:Destroy()
		end
		return f
	end

	H.test(
		"actual payroll preserves malformed employment rows while paying a readable job",
		function()
			local employment = { { JobId = "TaxiDriver" }, 4, false, {}, { JobId = {} } }
			local f = fixture(employment)
			local completed, problem = pcall(function()
				f.Service:_pay(f.Player)
			end)
			H.expect(completed, "malformed persisted employment raised: " .. tostring(problem))
			H.expect(
				#f.Payments == 1 and f.Payments[1].Metadata.Source == "TaxiDriver",
				"readable employment was not used"
			)
			H.expect(
				f.Character.Employment == employment and employment[2] == 4 and #employment == 5,
				"payroll repaired or deleted the persisted history"
			)
			f.Destroy()
		end
	)

	H.test(
		"actual payroll refuses an unreadable-only employment history without throwing",
		function()
			local f = fixture({ 4, {}, { JobId = "not-configured" } })
			f.Service.marks[10] = f.Root.Position
			local completed = pcall(function()
				f.Service:_pay(f.Player)
			end)
			H.expect(
				completed and #f.Payments == 0 and f.Service.marks[10] == nil,
				"unreadable employment raised, paid or retained a work mark"
			)
			f.Destroy()
		end
	)

	H.test("actual civilian payroll pays the first period then requires movement", function()
		local f = fixture()
		f.Service:_pay(f.Player)
		local expected = math.floor(
			f.Config.Payroll.CivilianHourlyRate * f.Config.Payroll.IntervalSeconds / 3600 + 0.5
		)
		H.expect(
			#f.Payments == 1 and f.Payments[1].Amount == expected,
			"civilian wage used the per-task BaseWage or wrong period"
		)
		local first = f.Payments[1]
		H.expect(
			first.CharacterId == "owned"
				and first.Direction == "Credit"
				and first.ReasonCode == "Wages",
			"wage authority contract changed"
		)
		f.Service:_pay(f.Player)
		H.expect(#f.Payments == 1, "idle character was paid again")
		f.Root.Position += roblox.Vector3.new(f.Config.Payroll.MinimumMovementStuds, 0, 0)
		f.Service:_pay(f.Player)
		H.expect(
			#f.Payments == 2 and f.Payments[2].TransactionId ~= first.TransactionId,
			"worked period did not use a fresh payment ID"
		)
		f.Destroy()
	end)

	H.test("actual duty payroll reads rank from the current duty profile", function()
		local f = fixture({})
		f.Duty = { DepartmentId = "Police", DutyProfileId = "duty" }
		f.Session.Profile.DutyProfiles.duty = { Rank = 3 }
		f.Service:_pay(f.Player)
		local rate = f.Config.Payroll.DepartmentHourlyRates.Police
			+ 2 * f.Config.Payroll.RankHourlyBonus
		local expected = math.floor(rate * f.Config.Payroll.IntervalSeconds / 3600 + 0.5)
		H.expect(
			#f.Payments == 1
				and f.Payments[1].Amount == expected
				and f.Payments[1].Metadata.Source == "Police",
			"department/rank wage changed"
		)
		f.Destroy()
	end)

	H.test("actual payroll fences departure and teardown during duty lookup", function()
		for _, teardown in { false, true } do
			local f = fixture()
			f.DutyQuery = function()
				task.wait(0.001)
				if teardown then
					f.Service:Destroy()
				else
					f.Player.Parent = nil
				end
			end
			f.Service:_pay(f.Player)
			H.expect(
				#f.Payments == 0 and f.Service.marks[10] == nil,
				"late duty result changed payroll state after departure/teardown"
			)
			f.Destroy()
		end
	end)

	H.test("actual payroll requires the current selected character and a physical root", function()
		for _, missingSession in { false, true } do
			local f = fixture()
			if missingSession then
				f.Session = nil
			else
				f.Root:Destroy()
			end
			f.Service:_pay(f.Player)
			H.expect(#f.Payments == 0, "unavailable character received wages")
			f.Destroy()
		end
	end)
end
