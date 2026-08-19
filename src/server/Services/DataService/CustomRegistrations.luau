--!strict
return function(DataService)
	function DataService:ReserveCustomRegistration(
		registration: string,
		userId: number,
		vehicleId: string
	): (boolean, string?)
		-- UK registrations are case-insensitive. Normalise at the datastore boundary
		-- as well as in VehicleOwnershipService so older callers cannot create two
		-- reservations for the same plate using different casing.
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if existing and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId) then
				return false, "REGISTRATION_ALREADY_USED"
			end
			self.mockRegistrations[registrationKey] = { UserId = userId, VehicleId = vehicleId }
			return true, nil
		end
		local reserved = false
		local ok = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if existing and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId) then
					return existing
				end
				reserved = true
				return { UserId = userId, VehicleId = vehicleId, UpdatedAt = os.time() }
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		return reserved, if reserved then nil else "REGISTRATION_ALREADY_USED"
	end

	function DataService:ReleaseCustomRegistration(
		registration: string,
		userId: number,
		vehicleId: string
	)
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
				self.mockRegistrations[registrationKey] = nil
			end
			return
		end
		task.spawn(function()
			self:_retry(function()
				return self.registrationStore:UpdateAsync(registrationKey, function(existing)
					if
						existing
						and existing.UserId == userId
						and existing.VehicleId == vehicleId
					then
						return nil
					end
					return existing
				end)
			end)
		end)
	end
end
