--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction("DropCash", function(payload)
		return type(payload) == "table" and type(payload.Amount) == "number"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("MoneyDropService"):Drop(player, payload.Amount)
		local messages = {
			INVALID_AMOUNT = "Enter a valid cash amount.",
			WHOLE_AMOUNT_REQUIRED = "Cash can only be dropped in whole pounds.",
			DROP_TOO_SMALL = "That amount is too small to drop.",
			DROP_TOO_LARGE = "That amount is above the cash drop limit.",
			INSUFFICIENT_FUNDS = "You do not have enough cash.",
			TOO_MANY_ACTIVE_DROPS = "Pick up an existing cash drop before making another.",
			SERVER_DROP_LIMIT = "There are too many cash drops in the area. Try again shortly.",
			CHARACTER_UNAVAILABLE = "Your character cannot drop cash right now.",
			CIVILIAN_REQUIRED = "Finish your service duty before dropping cash.",
		}
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then "Cash dropped."
				else (reason and messages[reason]) or "Cash could not be dropped.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetFrameworkStatus",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = {
					Framework = "RoleplayOS",
					Version = "0.1-dev",
					SchemaVersion = self.context.Configuration.Framework.SchemaVersion,
					Server = self.context.Services
						:Get("ServerModeService")
						:GetServerContext(player),
					Capabilities = {
						"Characters",
						"Access control",
						"Economy",
						"Jobs and applications",
						"Vehicles",
						"Properties and furniture",
						"Emergency services",
						"MDT and dispatch",
						"Mobile phone",
					},
				},
				RequestId = requestId,
			}
		end
	)
	-- Read-only roster for staff reconciling Discord display names against the
	-- game. Registered here with every other endpoint so it is covered by the
	-- rate-limit check, which only inspects this file.
	self.context.Network:RegisterFunction("GetShoulderNumberRoster", function(payload)
		return payload == nil or type(payload) == "table"
	end, function(player, _, requestId)
		local roster, reason = self.context.Services:Get("ShoulderNumberService"):RosterFor(player)
		if not roster then
			return {
				Success = false,
				Code = reason or "ROSTER_NOT_AUTHORISED",
				Message = "A management rank is required to read a roster.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = roster,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetOfficialServers", function(payload)
		return payload == nil or type(payload) == "table"
	end, function(_, _, requestId)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = {
				Servers = self.context.Services:Get("OfficialServerService"):List(),
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("JoinOfficialServer", function(payload)
		return type(payload) == "table"
			and type(payload.ServerId) == "string"
			and (payload.InstanceIndex == nil or type(payload.InstanceIndex) == "number")
	end, function(player, payload, requestId)
		local result, reason = self.context.Services
			:Get("OfficialServerService")
			:Join(player, payload.ServerId, payload.InstanceIndex)
		if not result then
			return {
				Success = false,
				Code = reason or "OFFICIAL_SERVER_UNAVAILABLE",
				Message = if reason == "ALREADY_ON_THIS_SERVER"
					then "You are already on this server."
					elseif
						reason == "PROFILE_BUSY"
					then "Your progress is still saving. Try again in a moment."
					elseif
						reason == "OFFICIAL_SERVER_FULL"
					then "That server is full. Try another instance."
					elseif
						reason == "OFFICIAL_SERVER_INSTANCE_NOT_FOUND"
					then "That instance is no longer open. Refresh the list and try again."
					else "That server could not be joined right now.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Connecting…",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetSprintState", function(payload)
		return type(payload) == "table" and type(payload.Sprinting) == "boolean"
	end, function(player, payload, requestId)
		local changed, reason =
			self.context.Services:Get("NeedsService"):SetSprinting(player, payload.Sprinting)
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			-- Said out loud. A refused sprint returned an empty message and the
			-- client discarded the reply, so a player out of breath or too hungry
			-- to run pressed shift and got nothing, with no way to tell that from
			-- the key being broken.
			Message = if changed
				then ""
				elseif reason == "SPRINT_EXHAUSTED" then "You need to catch your breath."
				elseif reason == "SPRINT_TOO_HUNGRY" then "You are too hungry to run."
				elseif reason == "SPRINT_WHILE_SEATED" then ""
				else "You cannot run right now.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetSettings",
		tablePayload,
		function(player, _, requestId)
			local settings, reason = self.context.Services:Get("SettingsService"):Get(player)
			if not settings then
				return {
					Success = false,
					Code = reason,
					Message = "Settings are unavailable.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = settings,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"UpdateSettings",
		tablePayload,
		function(player, payload, requestId)
			local settings, reason =
				self.context.Services:Get("SettingsService"):Update(player, payload)
			if not settings then
				return {
					Success = false,
					Code = reason,
					Message = "That setting could not be saved.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "Settings saved.",
				Data = settings,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetStartMenu",
		tablePayload,
		function(player, _, requestId)
			local data, reason = self.context.Services:Get("StartMenuService"):Build(player)
			if not data then
				return {
					Success = false,
					Code = reason,
					Message = "The start menu is unavailable.",
					RequestId = requestId,
				}
			end
			return { Success = true, Code = "OK", Message = "", Data = data, RequestId = requestId }
		end
	)
	self.context.Network:RegisterFunction(
		"GetPublicProgressionHud",
		tablePayload,
		function(player, _, requestId)
			local hud, reason = self.context.Services:Get("ProgressionService"):GetPublicHud(player)
			if not hud then
				return {
					Success = false,
					Code = reason,
					Message = "Public progression is not available here.",
					RequestId = requestId,
				}
			end
			return { Success = true, Code = "OK", Message = "", Data = hud, RequestId = requestId }
		end
	)
	self.context.Network:RegisterFunction(
		"GetProgression",
		tablePayload,
		function(player, payload, requestId)
			local characterId = if type(payload.CharacterId) == "string"
				then payload.CharacterId
				else nil
			local summary, reason =
				self.context.Services:Get("ProgressionService"):Get(player, characterId)
			if not summary then
				return {
					Success = false,
					Code = reason,
					Message = "Progression is unavailable.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = summary,
				RequestId = requestId,
			}
		end
	)
end
