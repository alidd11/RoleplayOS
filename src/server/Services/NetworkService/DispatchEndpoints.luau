--!strict
local Validators = require(script.Parent.Validators)
local boundedString = Validators.boundedString
local boundedStringArray = Validators.boundedStringArray
local tablePayload = Validators.tablePayload

local function listed(value: any, values: any): boolean
	return type(values) == "table" and table.find(values, value) ~= nil
end

local function optionalString(value: any, maximum: number): boolean
	return value == nil or boundedString(value, 0, maximum)
end

local function validDepartmentIds(value: any, departments: any): boolean
	if value == nil then
		return true
	end
	if type(departments) ~= "table" then
		return false
	end
	local maximum = 0
	for _ in departments do
		maximum += 1
	end
	if not boundedStringArray(value, maximum) then
		return false
	end
	for _, departmentId in value do
		if not boundedString(departmentId, 1, 64) or departments[departmentId] == nil then
			return false
		end
	end
	return true
end

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
		local settings = self.context.Configuration.Dispatch
		return type(payload) == "table"
			and boundedString(payload.Summary, 3, 160)
			and listed(payload.Priority, settings.CallPriorities)
			and boundedString(payload.Location, 1, 120)
			and listed(payload.IncidentType, settings.IncidentTypes)
			and optionalString(payload.CallerName, 60)
			and optionalString(payload.CallerNumber, 20)
			and optionalString(payload.Notes, 300)
			and validDepartmentIds(payload.DepartmentIds, self.context.Configuration.Departments)
	end, function(player, payload, requestId)
		local call, reason =
			self.context.Services:Get("DispatchService"):CreateCall(player, payload)
		local messages = {
			DISPATCH_CONSOLE_REQUIRED = "Sit at an authorised dispatch console first.",
			DISPATCH_CALL_IN_PROGRESS = "Your previous dispatch call is still being created.",
			CALL_CAPACITY_REACHED = "The live dispatch queue is full. Resolve an active call first.",
		}
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call
				then "Call created."
				else (reason and messages[reason]) or "The call could not be created.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchUpdateCall", function(payload)
		local settings = self.context.Configuration.Dispatch
		return type(payload) == "table"
			and boundedString(payload.CallId, 1, 64)
			and (payload.Status == nil or payload.Status == "OnScene")
			and (payload.Priority == nil or listed(payload.Priority, settings.CallPriorities))
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
			and boundedString(payload.CallId, 1, 64)
			and boundedString(payload.UnitId, 1, 32)
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
		return type(payload) == "table" and boundedString(payload.CallId, 1, 64)
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
		return type(payload) == "table"
			and listed(payload.Status, self.context.Configuration.Dispatch.UnitStatuses)
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
