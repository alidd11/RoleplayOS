--!strict
return function(self: any)
	self.context.Network:RegisterFunction("BeginDuty", function(payload)
		return type(payload) == "table"
			and type(payload.DutyProfileId) == "string"
			and type(payload.RoleId) == "string"
			and type(payload.StationId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
		local started, reason = self.context.Services:Get("DutyService"):Begin(player, payload)
		if not started then
			local messages = {
				SPAWN_POINT_UNAVAILABLE = "That team's spawn pad is missing or not configured.",
				SPAWN_ROLE_NOT_ALLOWED = "That role cannot use the selected spawn point.",
				SPAWN_TEAM_MISMATCH = "The spawn pad does not match the selected team.",
				DUTY_PROFILE_NOT_FOUND = "Your duty profile is not ready. Reopen the menu and try again.",
				TEAM_NOT_CONFIGURED = "That Roblox Team is not configured.",
				ACTIVE_CUSTODY_SENTENCE = "You cannot report for duty during an active custody sentence.",
				NO_ACTIVE_CHARACTER = "Create and select a character before reporting for duty.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "Duty could not be started.",
				RequestId = requestId,
			}
		end
		-- Read from the role rather than from the duty record, which would mean
		-- asking DutyService and that yields on a group check.
		local role = self.context.Configuration.Roles[payload.RoleId]
		return {
			Success = true,
			Code = "OK",
			Message = "You are now on duty.",
			-- The department travels with the response. The custody panel gates on
			-- it, and without it that gate was never satisfied, so the whole
			-- booking workflow had no way to be opened by anybody.
			Data = {
				RoleId = payload.RoleId,
				StationId = payload.StationId,
				SpawnId = payload.SpawnId,
				DepartmentId = role and role.DepartmentId,
				DivisionId = role and role.DivisionId,
				TeamName = role and role.TeamName,
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioSetCallsign", function(payload)
		return type(payload) == "table" and type(payload.Callsign) == "string"
	end, function(player, payload, requestId)
		local callsign, reason =
			self.context.Services:Get("DutyService"):SetCallsign(player, payload.Callsign)
		return {
			Success = callsign ~= nil,
			Code = if callsign then "OK" else reason,
			Message = if callsign then "Callsign updated." else "Enter a valid callsign.",
			Data = if callsign then { Callsign = callsign } else nil,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PAVASpray", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local sprayed, reason =
			self.context.Services:Get("PAVAService"):Spray(player, payload.TargetUserId)
		local messages = {
			POLICE_DUTY_REQUIRED = "PAVA is restricted to police officers on duty.",
			PAVA_NOT_EQUIPPED = "Equip your issued PAVA before using it.",
			PAVA_COOLDOWN = "PAVA is cooling down.",
			PAVA_TARGET_INVALID = "That target cannot be sprayed.",
			PAVA_TARGET_OUT_OF_RANGE = "The target is out of range.",
		}
		return {
			Success = sprayed,
			Code = if sprayed then "OK" else reason,
			Message = if sprayed
				then "PAVA deployed."
				else (messages[reason] or "PAVA could not be deployed."),
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("EnterCivilian", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
		self.context.Services:Get("DutyService"):End(player)
		local entered, reason = self.context.Services
			:Get("SpawnService")
			:EnterCivilian(player, payload.CharacterId, payload.SpawnId)
		if not entered then
			return {
				Success = false,
				Code = reason,
				Message = "The civilian spawn could not be completed.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Welcome to the city.",
			Data = { SpawnId = payload.SpawnId },
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("EnterCivilianAtGangTerritory", function(payload)
		return type(payload) == "table" and type(payload.CharacterId) == "string"
	end, function(player, payload, requestId)
		self.context.Services:Get("DutyService"):End(player)
		local entered, reason = self.context.Services
			:Get("SpawnService")
			:EnterCivilianAtTerritory(player, payload.CharacterId)
		if not entered then
			local messages = {
				NOT_IN_A_GANG = "You are not in a gang.",
				GANG_HAS_NO_TERRITORY = "Your gang does not hold a territory.",
				TERRITORY_UNAVAILABLE = "That territory is not available right now.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason])
					or "Could not spawn at your gang's territory.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Welcome to your turf.",
			RequestId = requestId,
		}
	end)
end
