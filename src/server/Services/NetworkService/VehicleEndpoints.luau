--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload

return function(self: any)
	self.context.Network:RegisterFunction("SetVehicleLights", function(payload)
		return type(payload) == "table" and type(payload.Action) == "string"
	end, function(player, payload, requestId)
		local ok, reason = self.context.Services:Get("VehicleLightingService"):Set(player, payload)
		if not ok then
			return {
				Success = false,
				Code = reason,
				Message = if reason == "NOT_DRIVING"
					then "You are not driving a vehicle."
					else "That control does not exist.",
				RequestId = requestId,
			}
		end
		return { Success = true, Code = "OK", Message = "", RequestId = requestId }
	end)

	self.context.Network:RegisterFunction("SetEmergencyLights", function(payload)
		return type(payload) == "table"
			and (payload.Stage == nil or type(payload.Stage) == "number")
			and (payload.Lights == nil or type(payload.Lights) == "boolean")
			and (payload.Siren == nil or type(payload.Siren) == "string")
			and (payload.Circuit == nil or type(payload.Circuit) == "string")
			and (payload.Enabled == nil or type(payload.Enabled) == "boolean")
			and (payload.RunLock == nil or type(payload.RunLock) == "boolean")
			and (payload.LowPower == nil or type(payload.LowPower) == "boolean")
			and (payload.Reset == nil or type(payload.Reset) == "boolean")
			and (payload.Director == nil or type(payload.Director) == "string")
	end, function(player, payload, requestId)
		local ok, reason = self.context.Services:Get("EmergencyLightsService"):Set(player, payload)
		if not ok then
			local messages = {
				NOT_DRIVING = "You are not driving a vehicle.",
				VEHICLE_HAS_NO_LIGHTS = "This vehicle has no warning lights.",
				NOT_ON_DUTY = "You are not on duty.",
				DEPARTMENT_HAS_NO_LIGHTS = "Your department does not run warning lights.",
				ROLE_HAS_NO_LIGHTS = "Your role does not run warning lights.",
				LIGHTS_DISABLED = "Emergency lighting is switched off on this server.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "The lights could not be changed.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = self.context.Services:Get("EmergencyLightsService"):GetState(player),
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetEmergencyLights", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = self.context.Services:Get("EmergencyLightsService"):GetState(player),
			RequestId = requestId,
		}
	end)

	self.context.Network:RegisterFunction(
		"GetOwnedVehicles",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("VehicleOwnershipService"):List(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("GetVehicleSpawnerMenu", function(payload)
		return type(payload) == "table" and type(payload.SpawnerId) == "string"
	end, function(player, payload, requestId)
		local menu, reason =
			self.context.Services:Get("VehicleSpawnerService"):Menu(player, payload.SpawnerId)
		return {
			Success = menu ~= nil,
			Code = if menu then "OK" else reason,
			Message = if menu
				then ""
				else "This vehicle facility is unavailable for your current role.",
			Data = menu,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SpawnVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.SpawnerId) == "string"
			and type(payload.DefinitionId) == "string"
			and (payload.VehicleId == nil or type(payload.VehicleId) == "string")
	end, function(player, payload, requestId)
		local spawned, reason =
			self.context.Services
				:Get("VehicleSpawnerService")
				:Spawn(player, payload.SpawnerId, payload.DefinitionId, payload.VehicleId)
		local messages = {
			ACTIVE_VEHICLE_EXISTS = "You already have a vehicle spawned.",
			ALL_BAYS_OCCUPIED = "Every vehicle bay is currently blocked.",
			NO_SPAWN_POINTS = "This facility has no configured spawn points.",
			SPAWN_COOLDOWN = "Please wait before spawning another vehicle.",
			VEHICLE_TEMPLATE_MISSING = "That vehicle model has not been installed.",
			VEHICLE_NOT_ALLOWED = "Your current role cannot use that vehicle.",
		}
		return {
			Success = spawned ~= nil,
			Code = if spawned then "OK" else reason,
			Message = if spawned
				then "Vehicle ready."
				else messages[reason] or "The vehicle could not be spawned.",
			Data = spawned,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PurchaseVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.DefinitionId) == "string"
			and type(payload.Colour) == "string"
	end, function(player, payload, requestId)
		local vehicle, reason = self.context.Services
			:Get("VehicleOwnershipService")
			:Purchase(player, payload.DefinitionId, payload.Colour)
		if not vehicle then
			local messages = {
				CHARACTER_NOT_ACTIVE = "Select a character before buying a vehicle.",
				VEHICLE_NOT_FOR_SALE = "That vehicle is not for sale here.",
				INVALID_VEHICLE_SELECTION = "That colour is not available for this vehicle.",
				INSUFFICIENT_FUNDS = "You cannot afford this vehicle.",
				GAMEPASS_REQUIRED = "This vehicle needs its game pass.",
				REGISTRATION_UNAVAILABLE = "No registration could be issued. Try again.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "The vehicle could not be bought.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Vehicle purchased.",
			Data = {
				VehicleId = vehicle.VehicleId,
				DefinitionId = vehicle.DefinitionId,
				Registration = vehicle.Registration,
				Colour = vehicle.Colour,
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetCustomVehicleRegistration", function(payload)
		return type(payload) == "table"
			and type(payload.SpawnerId) == "string"
			and #payload.SpawnerId <= 64
			and type(payload.VehicleId) == "string"
			and #payload.VehicleId <= 64
			and type(payload.Registration) == "string"
			and #payload.Registration <= 16
	end, function(player, payload, requestId)
		local authorised, facilityReason = self.context.Services
			:Get("VehicleSpawnerService")
			:AuthoriseCivilianFacility(player, payload.SpawnerId)
		if not authorised then
			return {
				Success = false,
				Code = facilityReason,
				Message = "Custom registrations can only be changed at a civilian vehicle facility.",
				RequestId = requestId,
			}
		end
		local result, reason = self.context.Services
			:Get("VehicleOwnershipService")
			:SetCustomRegistration(player, payload.VehicleId, payload.Registration)
		local messages = {
			GAMEPASS_REQUIRED = "Custom registration access is required.",
			INVALID_REGISTRATION_LENGTH = "Enter a registration of the permitted length.",
			REGISTRATION_NOT_PERMITTED = "That registration is not permitted.",
			REGISTRATION_ALREADY_USED = "That registration is already registered.",
			TEXT_FILTER_UNAVAILABLE = "The registration could not be checked. Try again shortly.",
			VEHICLE_NOT_OWNED = "That vehicle is not in your garage.",
		}
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then "Registration updated."
				else messages[reason] or "The registration could not be updated.",
			Data = result,
			RequestId = requestId,
		}
	end)
end
