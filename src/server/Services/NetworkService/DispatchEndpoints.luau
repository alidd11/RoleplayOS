--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction(
		"GetCCTVCameras",
		tablePayload,
		function(player, _, requestId)
			local cameras, reason = self.context.Services:Get("CCTVService"):Snapshot(player)
			return {
				Success = cameras ~= nil,
				Code = if cameras then "OK" else reason,
				Message = if cameras then "" else "CCTV is unavailable for this duty.",
				Data = cameras,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetDispatchSnapshot",
		tablePayload,
		function(player, _, requestId)
			local snapshot, reason = self.context.Services:Get("DispatchService"):Snapshot(player)
			if not snapshot then
				return {
					Success = false,
					Code = reason,
					Message = "Dispatch is unavailable for this duty.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = snapshot,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("DispatchCreateCall", function(payload)
		return type(payload) == "table"
			and type(payload.Summary) == "string"
			and type(payload.Priority) == "string"
			and type(payload.Location) == "string"
			and type(payload.IncidentType) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local prepared, prepareReason =
			self.context.Services:Get("DispatchService"):PrepareCall(player, payload)
		if not prepared then
			return {
				Success = false,
				Code = prepareReason,
				Message = "The call details could not be accepted.",
				RequestId = requestId,
			}
		end
		local call, reason = self.context.Services:Get("CallService"):Create(prepared)
		if not call then
			return {
				Success = false,
				Code = reason,
				Message = "The call could not be created.",
				RequestId = requestId,
			}
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Dispatch.CallCreated",
			Target = call.CallId,
			Metadata = { Priority = call.Priority, IncidentType = call.IncidentType },
		})
		return {
			Success = true,
			Code = "OK",
			Message = "Call created.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchUpdateCall", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and (payload.Status == nil or type(payload.Status) == "string")
			and (payload.Priority == nil or type(payload.Priority) == "string")
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local call, reason = self.context.Services:Get("CallService"):Update(
			payload.CallId,
			{ Status = payload.Status, Priority = payload.Priority }
		)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Call updated." else "The call could not be updated.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchAssignUnit", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and type(payload.UnitId) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local assigned, reason =
			self.context.Services:Get("CallService"):Assign(payload.CallId, payload.UnitId)
		return {
			Success = assigned,
			Code = if assigned then "OK" else reason,
			Message = if assigned then "Unit attached." else "The unit could not be attached.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchCloseCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local closed, reason =
			self.context.Services:Get("CallService"):Close(payload.CallId, player.UserId)
		return {
			Success = closed,
			Code = if closed then "OK" else reason,
			Message = if closed then "Call closed." else "The call could not be closed.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchSetUnitStatus", function(payload)
		return type(payload) == "table" and type(payload.Status) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("MDTService"):CanUse(player) then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "You are not on an authorised duty.",
				RequestId = requestId,
			}
		end
		local unitId = tostring(player.UserId)
		-- Assigned is dispatch's to give. A unit that could set it on itself could
		-- show as attending a call nobody sent it to.
		if payload.Status == "Assigned" then
			return {
				Success = false,
				Code = "STATUS_SET_BY_DISPATCH",
				Message = "Only dispatch can attach a unit to a call.",
				RequestId = requestId,
			}
		end
		local changed, reason =
			self.context.Services:Get("UnitService"):SetStatus(unitId, payload.Status)
		if changed then
			if payload.Status == "OnScene" then
				self.context.Services:Get("CallService"):NoteUnitOnScene(unitId)
			end
			self.context.Services:Get("DispatchService"):Publish("UnitChanged", unitId, 0)
		end
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			Message = if changed then "Status updated." else "The status could not be updated.",
			-- Echoed so the terminal shows what the server recorded rather than
			-- what the officer pressed.
			Data = if changed then { Status = payload.Status } else nil,
			RequestId = requestId,
		}
	end)
end
