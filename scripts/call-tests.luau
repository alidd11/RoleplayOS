--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.CallService)
		local configuration =
			runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		configuration.Dispatch.MaximumActiveCalls = 2
		configuration.Dispatch.MaximumResolvedRecoveryCalls = 1
		configuration.Dispatch.MaximumOperationalNotes = 2
		local publications, projections, audits, endpoints = {}, {}, {}, {}
		local units = {
			units = {
				police = { DepartmentId = "Police", Status = "Available" },
				second = { DepartmentId = "Police", Status = "Available" },
				fire = { DepartmentId = "Fire", Status = "Available" },
			},
			SetStatus = function(self, id, status)
				self.units[id].Status = status
				return true
			end,
		}
		local incident = {
			ScheduleFromCall = function(_self, call, actor)
				call.IncidentLastAttemptAt = os.clock()
				table.insert(projections, { Call = call, Actor = actor })
			end,
			BeginShutdown = function() end,
		}
		local duty = { DepartmentId = "Police", Callsign = "P1" }
		local mdt = {
			GetAuthorisedDuty = function()
				return duty
			end,
		}
		local services = {
			CallService = service,
			UnitService = units,
			IncidentService = incident,
			MDTService = mdt,
			DispatchService = {
				Publish = function(_self, kind, id, revision)
					table.insert(publications, { Kind = kind, Id = id, Revision = revision })
				end,
			},
			AuditService = {
				Record = function(_self, entry)
					table.insert(audits, entry)
				end,
			},
		}
		local context = {
			Configuration = configuration,
			Services = {
				Get = function(_self, name)
					return assert(services[name], "Unconfigured call fixture dependency")
				end,
			},
			Network = {
				RegisterFunction = function(_self, name, schema, handler)
					endpoints[name] = { Schema = schema, Handler = handler }
				end,
			},
		}
		service:Init(context)
		return {
			Runtime = runtime,
			Service = service,
			Context = context,
			Configuration = configuration,
			Units = units.units,
			Mdt = mdt,
			Publications = publications,
			Projections = projections,
			Audits = audits,
			Endpoints = endpoints,
			Create = function()
				return assert(service:Create({
					Summary = "Test emergency",
					Priority = configuration.Dispatch.CallPriorities[1],
					IncidentType = configuration.Dispatch.IncidentTypes[1],
					DepartmentIds = { "Police" },
				}))
			end,
		}
	end

	H.test("call update validates the entire patch before mutating state", function()
		local f = fixture()
		local call = f.Create()
		H.expect(f.Service:Assign(call.CallId, "police"), "fixture assignment failed")
		local revision, serviceRevision, publications =
			call.Revision, f.Service.revision, #f.Publications
		local priority = call.Priority
		local result, reason =
			f.Service:Update(call.CallId, { Status = "OnScene", Priority = "invalid" })
		H.expect(result == nil and reason == "INVALID_CALL_PRIORITY", "invalid patch accepted")
		H.expect(
			call.Status == "Assigned" and call.Priority == priority,
			"refused patch partially changed the call"
		)
		H.expect(
			call.Revision == revision
				and f.Service.revision == serviceRevision
				and #f.Publications == publications,
			"refused patch advanced revisions or published"
		)
		local nextPriority = f.Configuration.Dispatch.CallPriorities[2]
		H.expect(nextPriority ~= nil, "fixture requires two configured priorities")
		H.expect(
			f.Service:Update(call.CallId, { Status = "OnScene", Priority = nextPriority }) == call,
			"valid combined update refused"
		)
		H.expect(
			call.Status == "OnScene"
				and call.Priority == nextPriority
				and call.Revision == revision + 1
				and f.Service.revision == serviceRevision + 1
				and #f.Publications == publications + 1,
			"valid patch did not commit exactly once"
		)
	end)

	H.test("dispatch update schema already blocks invalid client priorities", function()
		local f = fixture()
		local register = f.Runtime.require(
			f.Runtime.services.ServerScriptService.RoleplayOS.Services.NetworkService.DispatchEndpoints
		)
		register({ context = f.Context })
		local schema = f.Endpoints.DispatchUpdateCall.Schema
		H.expect(
			not schema({ CallId = "call", Status = "OnScene", Priority = "invalid" }),
			"invalid client priority passed schema"
		)
		H.expect(
			schema({
				CallId = "call",
				Status = "OnScene",
				Priority = f.Configuration.Dispatch.CallPriorities[1],
			}),
			"valid update failed schema"
		)
	end)

	H.test("call assignments preserve on-scene progress and terminal resolution", function()
		local f = fixture()
		local call = f.Create()
		H.expect(f.Service:Assign(call.CallId, "police"), "assignment refused")
		f.Units.police.Status = "OnScene"
		H.expect(f.Service:NoteUnitOnScene("police"), "on-scene transition refused")
		local revision, publications = call.Revision, #f.Publications
		H.expect(f.Service:Assign(call.CallId, "police"), "retry refused")
		H.expect(
			call.Revision == revision
				and #f.Publications == publications
				and f.Units.police.Status == "OnScene",
			"retry rewrote progress"
		)
		H.expect(f.Service:Assign(call.CallId, "second"), "second responder refused")
		H.expect(call.Status == "OnScene", "additional responder regressed call")
		H.expect(not f.Service:Assign(call.CallId, "fire"), "wrong department attached")
		H.expect(f.Service:Close(call.CallId, 10), "resolution refused")
		H.expect(
			f.Units.police.AssignedCallId == nil
				and f.Units.police.Status == "Available"
				and f.Units.second.AssignedCallId == nil
				and #f.Projections == 1,
			"resolution did not release units and schedule history"
		)
		revision, publications = call.Revision, #f.Publications
		H.expect(not f.Service:Assign(call.CallId, "police"), "resolved call reassigned")
		H.expect(
			f.Service:Update(call.CallId, { Status = "OnScene" }) == nil,
			"resolved call updated"
		)
		H.expect(not f.Service:Close(call.CallId, 10), "resolved call closed twice")
		H.expect(
			call.Status == "Resolved"
				and call.Revision == revision
				and #f.Publications == publications
				and #f.Projections == 1,
			"terminal refusal mutated history"
		)
	end)

	H.test("call release reopens only after the last linked unit leaves", function()
		local f = fixture()
		local call = f.Create()
		f.Service:Assign(call.CallId, "police")
		f.Service:Assign(call.CallId, "second")
		f.Service:NoteUnitOnScene("police")
		-- UnitService owns removal of the actual unit; this fixture models that boundary.
		f.Units.police = nil
		H.expect(f.Service:ReleaseUnit("police") == 1, "first release missed")
		H.expect(call.Status == "OnScene" and #call.UnitIds == 1, "remaining responder lost")
		f.Units.second = nil
		H.expect(f.Service:ReleaseUnit("second") == 1, "last release missed")
		H.expect(call.Status == "Open" and #call.UnitIds == 0, "unattended call not reopened")
		H.expect(f.Service:ReleaseUnit("second") == 0, "repeated release changed call")
	end)

	H.test("call recovery remains bounded without discarding unresolved history", function()
		local f = fixture()
		local first, second = f.Create(), f.Create()
		H.expect(f.Service:Create({
			Summary = "Third emergency",
			Priority = f.Configuration.Dispatch.CallPriorities[1],
		}) == nil, "active capacity exceeded")
		H.expect(f.Service:Close(first.CallId, 10), "first close refused")
		local closed, reason = f.Service:Close(second.CallId, 10)
		H.expect(
			not closed
				and reason == "INCIDENT_RECOVERY_CAPACITY_REACHED"
				and second.Status == "Open",
			"full recovery backlog discarded another call"
		)
		local snapshot = f.Service:Snapshot()
		H.expect(
			#snapshot == 1 and snapshot[1].CallId == second.CallId,
			"recovery call leaked to board"
		)
		H.expect(f.Service.calls[first.CallId] == first, "unpersisted history discarded")
		first.IncidentPersisted = true
		f.Service:Snapshot()
		H.expect(f.Service.calls[first.CallId] == nil, "confirmed projection retained")
		H.expect(f.Service:Close(second.CallId, 10), "freed recovery capacity not reusable")
	end)

	H.test("actual call notes retain their cap and refuse a late resolved target", function()
		local f = fixture()
		local call = f.Create()
		local player = { UserId = 10, DisplayName = "Officer" }
		for _, note in { "First note", "Second note", "Third note" } do
			H.expect(
				f.Service:AddOperationalNote(player, call.CallId, note) == call,
				"note refused"
			)
		end
		H.expect(
			#call.OperationalNotes == 2
				and call.OperationalNotes[1].Text == "Second note"
				and call.OperationalNotes[2].Text == "Third note"
				and #f.Audits == 3,
			"note retention order or audit wrong"
		)
		local lookups = 0
		f.Mdt.GetAuthorisedDuty = function()
			lookups += 1
			if lookups == 2 then
				f.Service:Close(call.CallId, 10)
			end
			return { DepartmentId = "Police", Callsign = "P1" }
		end
		local result, reason = f.Service:AddOperationalNote(player, call.CallId, "Late note")
		H.expect(result == nil and reason == "CALL_NOT_FOUND", "late note appended after closure")
		H.expect(
			#call.OperationalNotes == 2 and #f.Audits == 3,
			"late note changed historical snapshot"
		)
	end)
end
