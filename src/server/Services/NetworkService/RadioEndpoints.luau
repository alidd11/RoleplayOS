--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction(
		"GetRadioSnapshot",
		tablePayload,
		function(player, _, requestId)
			local data, reason = self.context.Services:Get("RadioService"):Snapshot(player)
			return {
				Success = data ~= nil,
				Code = if data then "OK" else reason,
				Message = if data then "" else "You must be on duty to use the radio.",
				Data = data,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("RadioSetChannel", function(payload)
		return type(payload) == "table" and type(payload.ChannelId) == "string"
	end, function(player, payload, requestId)
		local data, reason =
			self.context.Services:Get("RadioService"):SetChannel(player, payload.ChannelId)
		return {
			Success = data ~= nil,
			Code = if data then "OK" else reason,
			Message = if data then "Channel changed." else "That channel is not available.",
			Data = data,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioTransmit", function(payload)
		return type(payload) == "table"
			and type(payload.Message) == "string"
			and #payload.Message <= 180
	end, function(player, payload, requestId)
		local sent, reason =
			self.context.Services:Get("RadioService"):Transmit(player, payload.Message)
		return {
			Success = sent == true,
			Code = if sent then "OK" else reason,
			Message = if sent then "Transmitted." else "The message could not be transmitted.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioPanic", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local call, reason = self.context.Services:Get("EmergencyTriggerService"):Panic(player)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call
				then "PANIC ALERT SENT TO ALL ON-DUTY UNITS."
				elseif reason == "PANIC_COOLDOWN" then "PANIC COOLDOWN ACTIVE."
				else "The panic alert could not be sent.",
			Data = call,
			RequestId = requestId,
		}
	end)
end
