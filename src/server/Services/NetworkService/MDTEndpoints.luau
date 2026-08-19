--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction("MDTSearch", function(payload)
		return type(payload) == "table"
			and type(payload.Query) == "string"
			and (payload.Type == "Person" or payload.Type == "Vehicle"),
			"INVALID_SEARCH"
	end, function(player, payload, requestId)
		local permission = if payload.Type == "Person" then "PersonSearch" else "VehicleSearch"
		if not self.context.Services:Get("MDTService"):CanUsePermission(player, permission) then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "You must be on an authorised duty to use this search.",
				RequestId = requestId,
			}
		end
		local query, reason = self.context.Services:Get("MDTService"):SanitiseQuery(payload.Query)
		if not query then
			return {
				Success = false,
				Code = reason,
				Message = "The search query was invalid.",
				RequestId = requestId,
			}
		end
		self.context.Services:Get("MDTService"):AuditSearch(player, payload.Type, requestId)
		local page = if type(payload.Page) == "number"
			then math.clamp(math.floor(payload.Page), 1, 1000)
			else 1
		local data, searchReason
		if payload.Type == "Person" then
			local duty = self.context.Services:Get("MDTService"):GetDuty(player)
			local accessProfile = "Emergency"
			if
				duty
				and duty.DepartmentId == "Police"
				and self.context.Services:Get("MDTService"):CanUsePermission(player, "WarrantRead")
			then
				accessProfile = "Police"
			elseif duty and duty.DepartmentId == "Highways" then
				accessProfile = "Highways"
			end
			data, searchReason =
				self.context.Services:Get("PersonRecordService"):Search(query, page, accessProfile)
		else
			data, searchReason = self.context.Services:Get("VehicleRecordService"):Search(
				query,
				page,
				self.context.Services:Get("MDTService"):CanUsePermission(player, "WarrantRead")
			)
		end
		return {
			Success = data ~= nil,
			Code = if data then "OK" else searchReason or "MDT_SEARCH_UNAVAILABLE",
			Message = if data then "" else "Persistent records are temporarily unavailable.",
			Data = data,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetMDTAccess",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("MDTService"):AccessSummary(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("MDTCreateWarrant", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.Reason) == "string"
			and (payload.ExpiresAt == nil or type(payload.ExpiresAt) == "number")
	end, function(player, payload, requestId)
		local warrant, reason =
			self.context.Services
				:Get("WarrantService")
				:Create(player, payload.CharacterId, payload.Reason, payload.ExpiresAt)
		return {
			Success = warrant ~= nil,
			Code = if warrant then "OK" else reason,
			Message = if warrant then "Warrant issued." else "The warrant could not be issued.",
			Data = warrant,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTRevokeWarrant", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.WarrantId) == "string"
	end, function(player, payload, requestId)
		local warrant, reason = self.context.Services
			:Get("WarrantService")
			:Revoke(player, payload.CharacterId, payload.WarrantId)
		return {
			Success = warrant ~= nil,
			Code = if warrant then "OK" else reason,
			Message = if warrant then "Warrant revoked." else "The warrant could not be revoked.",
			Data = warrant,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTGetIncidents", function(payload)
		return type(payload) == "table"
			and (payload.Page == nil or type(payload.Page) == "number")
			and (payload.ResolvedOnly == nil or type(payload.ResolvedOnly) == "boolean")
	end, function(player, payload, requestId)
		local mdt = self.context.Services:Get("MDTService")
		if
			not mdt:CanUsePermission(player, "IncidentRead")
			and not mdt:CanUsePermission(player, "IncidentWrite")
		then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "This duty cannot view incident records.",
				RequestId = requestId,
			}
		end
		local page = if type(payload.Page) == "number"
			then math.clamp(math.floor(payload.Page), 1, 1000)
			else 1
		local incidents, reason = self.context.Services
			:Get("IncidentService")
			:Recent(player, page, payload.ResolvedOnly == true)
		return {
			Success = incidents ~= nil,
			Code = if incidents then "OK" else reason,
			Message = if incidents then "" else "Incident records are temporarily unavailable.",
			Data = incidents,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTAddIncidentNote", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and type(payload.Note) == "string"
	end, function(player, payload, requestId)
		local call, reason = self.context.Services
			:Get("CallService")
			:AddOperationalNote(player, payload.CallId, payload.Note)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Operational note added." else "The note could not be added.",
			Data = call,
			RequestId = requestId,
		}
	end)
end
