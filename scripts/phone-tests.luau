--!strict
local fs = require("@lune/fs")
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local timers = {}
		runtime.globals.task = {
			delay = function(seconds, callback)
				local timer = { Seconds = seconds, Callback = callback, Cancelled = false }
				table.insert(timers, timer)
				return timer
			end,
			cancel = function(timer)
				timer.Cancelled = true
			end,
		}
		local function signal()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end
		local players, sessions = {}, {}
		for id = 1, 4 do
			local player =
				{ UserId = id, Parent = runtime.services.Players, CharacterAdded = signal() }
			players[id] = player
			sessions[player] = {
				ActiveCharacterId = "active",
				Profile = {
					Characters = {
						active = { Phone = { Number = "0712345678" .. id, Messages = {} } },
					},
				},
			}
		end
		runtime.services.Players.GetPlayers = function()
			return players
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return players[id]
		end
		runtime.services.Players.PlayerAdded = signal()
		runtime.services.Players.PlayerRemoving = signal()
		local f: any = { Players = players, Timers = timers, Events = {}, Disconnects = {} }
		local dependencies = {
			DataService = {
				GetSession = function(_self, player)
					return sessions[player]
				end,
			},
			PhoneVoiceService = {
				ConnectCall = function()
					return false, "VOICE_NOT_AVAILABLE"
				end,
				DisconnectCall = function(_self, id)
					table.insert(f.Disconnects, id)
				end,
			},
		}
		local service =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Services.PhoneService)
		service:Init({
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "Unexpected phone dependency: " .. name)
				end,
			},
			Network = {
				RegisterEvent = function()
					return {
						FireClient = function(_self, player, payload)
							table.insert(f.Events, {
								Player = player,
								CallId = payload.Call.CallId,
								State = payload.Call.State,
							})
						end,
					}
				end,
			},
		})
		service:Start()
		f.Service = service
		function f:Call(from, to)
			return assert(
				service:PlaceCall(
					players[from],
					sessions[players[to]].Profile.Characters.active.Phone.Number
				)
			)
		end
		return f
	end

	H.test("actual phone hang-up replay preserves newer calls and original retention", function()
		local f = fixture()
		local old = f:Call(1, 2)
		H.expect(f.Service:EndCall(f.Players[1], old.CallId), "initial hang-up failed")
		local timer = f.Service.callTimers[old.CallId]
		local endedAt = old.EndedAt
		local first, second = f:Call(1, 3), f:Call(2, 4)
		local events, disconnects = #f.Events, #f.Disconnects
		for _, participant in { 1, 2 } do
			H.expect(f.Service:EndCall(f.Players[participant], old.CallId), "hang-up retry failed")
		end
		H.expect(
			f.Service.userCalls[1] == first.CallId
				and f.Service.userCalls[3] == first.CallId
				and f.Service.userCalls[2] == second.CallId
				and f.Service.userCalls[4] == second.CallId,
			"old hang-up cleared newer busy mappings"
		)
		H.expect(
			#f.Events == events and #f.Disconnects == disconnects,
			"retry repeated end notifications or voice teardown"
		)
		H.expect(
			f.Service.callTimers[old.CallId] == timer
				and not timer.Cancelled
				and old.EndedAt == endedAt,
			"retry restarted terminal retention"
		)
		local unavailable, reason = f.Service:PlaceCall(f.Players[1], "07123456782")
		H.expect(
			unavailable == nil and reason == "CALL_UNAVAILABLE",
			"retry allowed overlapping calls"
		)
		timer.Callback()
		H.expect(
			f.Service.calls[old.CallId] == nil
				and f.Service.calls[first.CallId] == first
				and f.Service.calls[second.CallId] == second,
			"old cleanup removed a newer call"
		)
		f.Service:Destroy()
	end)

	H.test("actual phone normal call lifecycle retains participant authorisation", function()
		local f = fixture()
		local call = f:Call(1, 2)
		local ringingTimer = f.Service.callTimers[call.CallId]
		local ended, reason = f.Service:EndCall(f.Players[3], call.CallId)
		H.expect(
			not ended and reason == "CALL_NOT_FOUND" and call.State == "Ringing",
			"stranger ended call"
		)
		H.expect(f.Service:AnswerCall(f.Players[1], call.CallId) == nil, "caller answered own call")
		H.expect(
			f.Service:AnswerCall(f.Players[2], call.CallId) == call
				and call.State == "Connected"
				and ringingTimer.Cancelled,
			"recipient answer failed"
		)
		H.expect(
			f.Service:EndCall(f.Players[2], call.CallId)
				and call.State == "Ended"
				and f.Service.userCalls[1] == nil
				and f.Service.userCalls[2] == nil,
			"normal hang-up failed"
		)
		ended, reason = f.Service:EndCall(f.Players[3], call.CallId)
		H.expect(not ended and reason == "CALL_NOT_FOUND", "stranger retry accepted")
		f.Service.callTimers[call.CallId].Callback()
		H.expect(f.Service.calls[call.CallId] == nil, "terminal cleanup failed")
		f.Service:Destroy()
	end)
	H.test("phone tool listeners are released with destroyed tools", function()
		local source = fs.readFile("src/client/Controllers/PhoneController/init.luau")
		H.expect(
			string.find(source, "self.toolConnections = setmetatable", 1, true) ~= nil,
			"phone tool connections are still retained in the controller-wide list"
		)
		H.expect(
			string.find(source, "tool.Destroying:Connect", 1, true) ~= nil,
			"destroyed phone tools do not release their listeners"
		)
		H.expect(
			string.find(source, "self.toolConnections[tool] = nil", 1, true) ~= nil,
			"destroyed phone tool listener state is retained"
		)
	end)
end
