--!strict
return function(self: any)
	self.context.Network:RegisterFunction("GetGangStatus", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local status = self.context.Services:Get("GangService"):GetStatus(player)
		if not status then
			return {
				Success = false,
				Code = "PROFILE_UNAVAILABLE",
				Message = "Your profile is still loading. Try again in a moment.",
				RequestId = requestId,
			}
		end
		-- The territory's display name travels alongside the gang record so the
		-- client can label a spawn option without a second round trip.
		local territoryId = status.Gang and status.Gang.TerritoryId
		local territoryName = if type(territoryId) == "string"
			then self.context.Services:Get("GangTerritoryService"):NameOf(territoryId)
			else nil
		local data = table.clone(status)
		data.TerritoryName = territoryName
		return { Success = true, Code = "OK", Message = "", Data = data, RequestId = requestId }
	end)
	local gangMessages = {
		PROFILE_UNAVAILABLE = "Your profile is still loading. Try again in a moment.",
		ALREADY_IN_A_GANG = "You are already in a gang.",
		NOT_IN_A_GANG = "You are not in a gang.",
		NOT_THE_LEADER = "Only the leader can do that.",
		GANG_PASS_REQUIRED = "Gang System Access is required to do that.",
		NAME_REQUIRED = "Enter a name for the gang.",
		NAME_LENGTH = "Gang names are 3-24 characters.",
		NAME_CHARACTERS = "Use letters, numbers, spaces, apostrophes and hyphens only.",
		NAME_TAKEN = "That name is already taken.",
		INVALID_TARGET = "Choose a player to invite.",
		PLAYER_NOT_ONLINE = "That player is not on this server.",
		ALREADY_INVITED = "That player already has a pending invite.",
		TOO_MANY_PENDING_INVITES = "That player has too many pending invites.",
		GANG_FULL = "The gang is full.",
		INVALID_RESPONSE = "That invite response was not understood.",
		INVITE_NOT_FOUND = "That invite is no longer available.",
		GANG_NOT_FOUND = "That gang no longer exists.",
		GANG_JOIN_FAILED = "The gang could not be joined.",
		GANG_LEAVE_FAILED = "The gang could not be left. Try again.",
	}
	self.context.Network:RegisterFunction("CreateGang", function(payload)
		return type(payload) == "table" and type(payload.Name) == "string"
	end, function(player, payload, requestId)
		local gang, reason = self.context.Services:Get("GangService"):Create(player, payload.Name)
		return {
			Success = gang ~= nil,
			Code = if gang then "OK" else reason,
			Message = if gang
				then ""
				else (reason and gangMessages[reason]) or "The gang could not be created.",
			Data = gang,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("InviteToGang", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local invited, reason =
			self.context.Services:Get("GangService"):Invite(player, payload.TargetUserId)
		return {
			Success = invited,
			Code = if invited then "OK" else reason,
			Message = if invited
				then "Invite sent."
				else (reason and gangMessages[reason]) or "The invite could not be sent.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RespondToGangInvite", function(payload)
		return type(payload) == "table"
			and type(payload.GangId) == "string"
			and type(payload.Accept) == "boolean"
	end, function(player, payload, requestId)
		local responded, reason = self.context.Services
			:Get("GangService")
			:RespondToInvite(player, payload.GangId, payload.Accept)
		return {
			Success = responded,
			Code = if responded then "OK" else reason,
			Message = if responded
				then ""
				else (reason and gangMessages[reason]) or "The invite could not be answered.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("LeaveGang", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local left, reason = self.context.Services:Get("GangService"):Leave(player)
		return {
			Success = left,
			Code = if left then "OK" else reason,
			Message = if left
				then "You have left the gang."
				else (reason and gangMessages[reason]) or "The gang could not be left.",
			RequestId = requestId,
		}
	end)
end
