--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction("GetPhone", tablePayload, function(player, _, requestId)
		local snapshot, reason = self.context.Services:Get("PhoneService"):Snapshot(player)
		if not snapshot then
			return {
				Success = false,
				Code = reason,
				Message = "Select a character before using the phone.",
				RequestId = requestId,
			}
		end
		return { Success = true, Code = "OK", Message = "", Data = snapshot, RequestId = requestId }
	end)
	self.context.Network:RegisterFunction("PhoneSendText", function(payload)
		return type(payload) == "table"
			and type(payload.Number) == "string"
			and type(payload.Message) == "string"
	end, function(player, payload, requestId)
		local message, reason = self.context.Services
			:Get("PhoneService")
			:SendText(player, payload.Number, payload.Message)
		return {
			Success = message ~= nil,
			Code = if message then "OK" else reason,
			Message = if message then "Message sent." else "The message could not be sent.",
			Data = message,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneTransferFunds", function(payload)
		return type(payload) == "table"
			and type(payload.Recipient) == "string"
			and type(payload.Amount) == "number"
	end, function(player, payload, requestId)
		local transfer, reason = self.context.Services
			:Get("PhoneService")
			:TransferFunds(player, payload.Recipient, payload.Amount)
		local messages = {
			INSUFFICIENT_FUNDS = "You do not have enough money in your bank account.",
			SELF_TRANSFER = "You cannot send money to yourself.",
			TRANSFER_LIMIT = "That transfer exceeds the per-transfer limit.",
			TRANSFER_IN_PROGRESS = "Your previous transfer is still being processed.",
			INVALID_RECIPIENT_NAME = "Enter the username of the person you are paying.",
			RECIPIENT_NAME_AMBIGUOUS = "More than one player is using that display name. Use their username.",
			PHONE_RECIPIENT_UNAVAILABLE = "That player is not in this server.",
		}
		return {
			Success = transfer ~= nil,
			Code = if transfer then "OK" else reason,
			Message = if transfer
				then string.format("£%d sent to %s.", transfer.Amount, transfer.Recipient)
				else messages[reason] or "The transfer could not be completed.",
			Data = transfer,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhonePlaceCall", function(payload)
		return type(payload) == "table" and type(payload.Number) == "string"
	end, function(player, payload, requestId)
		local call, reason =
			self.context.Services:Get("PhoneService"):PlaceCall(player, payload.Number)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Calling…" else "The call could not be placed.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneAnswerCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		local call, reason =
			self.context.Services:Get("PhoneService"):AnswerCall(player, payload.CallId)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Call connected." else "The call could not be answered.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneEndCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		local ended, reason =
			self.context.Services:Get("PhoneService"):EndCall(player, payload.CallId)
		return {
			Success = ended,
			Code = if ended then "OK" else reason,
			Message = if ended then "Call ended." else "The call could not be ended.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneEmergency", function(payload)
		return type(payload) == "table"
			and type(payload.Summary) == "string"
			and type(payload.Location) == "string"
	end, function(player, payload, requestId)
		local call, reason = self.context.Services
			:Get("PhoneService")
			:Emergency(player, payload.Summary, payload.Location)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call
				then "Your 999 call has been sent to control."
				else "The emergency call failed. Try again.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneToggleFlashlight", function(payload)
		return type(payload) == "table" and type(payload.Enabled) == "boolean"
	end, function(player, payload, requestId)
		local changed, reason =
			self.context.Services:Get("PhoneService"):ToggleFlashlight(player, payload.Enabled)
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			Message = if changed then "Flashlight updated." else "Equip the phone first.",
			RequestId = requestId,
		}
	end)
end
