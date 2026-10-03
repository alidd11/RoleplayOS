--!strict
local Runtime = require("./test-runtime")

local function contains(values: { number }, wanted: number): boolean
	for _, value in values do
		if value == wanted then
			return true
		end
	end
	return false
end

return function(H: any)
	H.test("active duty candidates are detached from the authoritative duty table", function()
		local runtime = Runtime.new()
		local duty =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Services.DutyService)
		duty.active = { [10] = { DepartmentId = "Police" }, [20] = { DepartmentId = "Fire" } }
		local candidates = duty:ActiveUserIds()
		H.expect(
			#candidates == 2 and contains(candidates, 10) and contains(candidates, 20),
			"active duty candidate snapshot lost a live duty"
		)
		table.clear(candidates)
		H.expect(
			duty.active[10] ~= nil and duty.active[20] ~= nil,
			"caller mutated authoritative duty state through its candidate snapshot"
		)
	end)

	H.test("dispatch fan-out never scans civilians outside active duty", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local players = runtime.services.Players
		local byId: { [number]: any } = {}
		for _, userId in { 10, 20, 30 } do
			byId[userId] = { UserId = userId, Parent = players }
		end
		players.GetPlayerByUserId = function(_self, userId)
			return byId[userId]
		end
		players.GetPlayers = function()
			error("dispatch scanned the full player population")
		end

		local deliveries, lookups = {}, 0
		local duties = {
			[10] = { DepartmentId = "Police" },
			[20] = { DepartmentId = "Fire" },
			[30] = { DepartmentId = "Control" },
		}
		local dependencies = {
			DutyService = {
				ActiveUserIds = function()
					return { 10, 20 }
				end,
			},
			MDTService = {
				GetAuthorisedDuty = function(_self, player)
					lookups += 1
					return duties[player.UserId]
				end,
			},
			CallService = {
				calls = {
					call = { DepartmentIds = { "Police" }, Source = "Phone" },
				},
			},
		}
		local dispatch = runtime.require(root.DispatchService)
		dispatch.context = {
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "unexpected dispatch fan-out dependency")
				end,
			},
		}
		dispatch.changedEvent = {
			FireClient = function(_self, player)
				table.insert(deliveries, player.UserId)
			end,
		}
		dispatch:_fireAuthorised({ Kind = "CallUpdated" }, "call", nil)
		H.expect(
			lookups == 2 and #deliveries == 1 and deliveries[1] == 10,
			"dispatch candidate narrowing changed relevance or revalidation"
		)
	end)

	H.test("emergency alerts fan out only across active duty candidates", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local players = runtime.services.Players
		local byId: { [number]: any } = {}
		for _, userId in { 10, 20, 30 } do
			byId[userId] = { UserId = userId, Parent = players }
		end
		players.GetPlayerByUserId = function(_self, userId)
			return byId[userId]
		end
		players.GetPlayers = function()
			error("emergency alert scanned the full player population")
		end

		local deliveries, lookups = {}, 0
		local duties = {
			[10] = { DepartmentId = "Police" },
			[20] = { DepartmentId = "Fire" },
			[30] = { DepartmentId = "Police" },
		}
		local duty = {
			ActiveUserIds = function()
				return { 10, 20 }
			end,
			Get = function(_self, player)
				lookups += 1
				return duties[player.UserId]
			end,
		}
		local emergency = runtime.require(root.EmergencyTriggerService)
		emergency.context = {
			Services = {
				Get = function(_self, name)
					H.expect(name == "DutyService", "unexpected emergency fan-out dependency")
					return duty
				end,
			},
		}
		emergency.event = {
			FireClient = function(_self, player)
				table.insert(deliveries, player.UserId)
			end,
		}
		emergency.running = true
		emergency:Broadcast({ DepartmentIds = { "Police" } })
		H.expect(
			lookups == 2 and #deliveries == 1 and deliveries[1] == 10,
			"emergency candidate narrowing changed department delivery"
		)
	end)

	H.test("radio transmit fan-out stays inside the selected channel set", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local players = runtime.services.Players
		local config = runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		local byId: { [number]: any } = {}
		for _, userId in { 10, 20, 30 } do
			byId[userId] = { UserId = userId, Parent = players }
		end
		players.GetPlayerByUserId = function(_self, userId)
			return byId[userId]
		end
		players.GetPlayers = function()
			error("radio scanned the full player population")
		end

		local deliveries, lookups = {}, 0
		local duties = {
			[10] = { DepartmentId = "Police", Callsign = "P10" },
			[20] = { DepartmentId = "Police", Callsign = "P20" },
			[30] = { DepartmentId = "Police", Callsign = "P30" },
		}
		local radio = runtime.require(root.RadioService)
		radio.context = {
			Configuration = config,
			Services = {
				Get = function(_self, name)
					H.expect(name == "DutyService", "unexpected radio fan-out dependency")
					return {
						Get = function(_service, player)
							lookups += 1
							return duties[player.UserId]
						end,
					}
				end,
			},
		}
		radio.event = {
			FireClient = function(_self, player)
				table.insert(deliveries, player.UserId)
			end,
		}
		radio.running = true
		radio.current = { [10] = "Police", [20] = "Police", [30] = "Operations" }
		radio.messages = {}
		radio.bursts = {}
		local sent, reason = radio:Transmit(byId[10], "unit test")
		H.expect(sent and reason == nil, "valid radio transmission failed")
		H.expect(
			#deliveries == 2
				and contains(deliveries, 10)
				and contains(deliveries, 20)
				and not contains(deliveries, 30),
			"radio delivered outside the selected channel"
		)
		-- Sender is validated before and after filtering; each recipient is then
		-- revalidated once. The unrelated Operations subscriber is never looked up.
		H.expect(lookups == 4, "radio duty revalidation count changed unexpectedly")
	end)
end
