--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction("TaxiRequest", function(payload)
		return type(payload) == "table"
			and type(payload.Pickup) == "string"
			and type(payload.Dropoff) == "string"
			and type(payload.Band) == "string"
	end, function(player, payload, requestId)
		local taxi, reason = self.context.Services
			:Get("TaxiService")
			:Request(player, payload.Pickup, payload.Dropoff, payload.Band)
		local messages = {
			CIVILIAN_REQUIRED = "Taxi bookings are available to civilian characters.",
			INSUFFICIENT_FUNDS = "You do not have enough money in your bank account for that fare.",
			TAXI_REQUEST_ALREADY_ACTIVE = "You already have an active taxi booking.",
		}
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Taxi requested. Drivers have been notified."
				else messages[reason] or "The taxi request could not be sent.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiAccept", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local taxi, reason =
			self.context.Services:Get("TaxiService"):Accept(player, payload.RequestId)
		local acceptMessages = {
			TAXI_OWN_REQUEST = "You booked this ride. Another driver has to take it.",
			TAXI_DRIVER_REQUIRED = "Start a taxi shift before accepting bookings.",
			TAXI_REQUEST_ALREADY_ACTIVE = "Finish your current booking first.",
			TAXI_VEHICLE_REQUIRED = "Spawn your taxi before accepting a booking.",
		}
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Taxi booking accepted."
				else (reason and acceptMessages[reason])
					or "That taxi booking is no longer available.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiDecline", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local passed, reason =
			self.context.Services:Get("TaxiService"):Decline(player, payload.RequestId)
		return {
			Success = passed,
			Code = if passed then "OK" else reason,
			Message = if passed
				then "Booking passed on. It stays open for other drivers."
				elseif
					reason == "TAXI_DRIVER_REQUIRED"
				then "Start a taxi shift before reviewing bookings."
				else "That taxi booking is no longer available.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiComplete", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local taxi, reason =
			self.context.Services:Get("TaxiService"):Complete(player, payload.RequestId)
		local messages =
			{ INSUFFICIENT_FUNDS = "The passenger no longer has enough money for this fare." }
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Fare paid and driver credited."
				else messages[reason] or "The taxi could not be completed.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiCancel", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local cancelled, reason =
			self.context.Services:Get("TaxiService"):Cancel(player, payload.RequestId)
		return {
			Success = cancelled,
			Code = if cancelled then "OK" else reason,
			Message = if cancelled
				then "Taxi booking cancelled."
				else "The taxi booking could not be cancelled.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"TaxiStartShift",
		tablePayload,
		function(player, _, requestId)
			local shift, reason = self.context.Services:Get("TaxiService"):StartShift(player)
			return {
				Success = shift ~= nil,
				Code = if shift then "OK" else reason,
				Message = if shift
					then "You are now available for taxi bookings."
					elseif
						reason == "TAXI_REQUEST_ALREADY_ACTIVE"
					then "Finish the taxi you booked before starting a shift."
					else "The taxi shift could not be started.",
				Data = shift,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"TaxiEndShift",
		tablePayload,
		function(player, _, requestId)
			local ended, reason = self.context.Services:Get("TaxiService"):EndShift(player)
			return {
				Success = ended,
				Code = if ended then "OK" else reason,
				Message = if ended
					then "You are no longer available for taxi bookings."
					else "Finish or cancel your active taxi ride first.",
				RequestId = requestId,
			}
		end
	)
end
