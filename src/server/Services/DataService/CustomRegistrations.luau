--!strict

local function ownsRegistration(existing: any, userId: number, vehicleId: string): boolean
	return type(existing) == "table"
		and existing.Released ~= true
		and existing.UserId == userId
		and existing.VehicleId == vehicleId
end

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
			if
				existing
				and existing.Released ~= true
				and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId)
			then
				return false, "REGISTRATION_ALREADY_USED"
			end
			self.mockRegistrations[registrationKey] = { UserId = userId, VehicleId = vehicleId }
			return true, nil
		end
		local updatedAt = os.time()
		local ok, persisted = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if
					existing
					and existing.Released ~= true
					and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId)
				then
					return existing
				end
				return {
					UserId = userId,
					VehicleId = vehicleId,
					UpdatedAt = updatedAt,
					Released = false,
				}
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		local reserved = ownsRegistration(persisted, userId, vehicleId)
		return reserved, if reserved then nil else "REGISTRATION_ALREADY_USED"
	end

	-- Reserves the replacement side of a custom-registration swap and tags it
	-- with the operation that owns the reservation. A rollback can then release
	-- only this exact attempt: an old delayed recovery can never free a plate
	-- which the same vehicle acquired again under a later operation.
	function DataService:ReserveCustomRegistrationSwap(
		registration: string,
		userId: number,
		vehicleId: string,
		operationId: string
	): (boolean, string?)
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if
				existing
				and existing.Released ~= true
				and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId)
			then
				return false, "REGISTRATION_ALREADY_USED"
			end
			if
				ownsRegistration(existing, userId, vehicleId)
				and existing.SwapOperationId ~= nil
				and existing.SwapOperationId ~= operationId
			then
				return false, "REGISTRATION_SWAP_IN_PROGRESS"
			end
			self.mockRegistrations[registrationKey] = {
				UserId = userId,
				VehicleId = vehicleId,
				SwapOperationId = operationId,
			}
			return true, nil
		end

		local updatedAt = os.time()
		local ok, persisted = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if
					existing
					and existing.Released ~= true
					and (existing.UserId ~= userId or existing.VehicleId ~= vehicleId)
				then
					return existing
				end
				if
					ownsRegistration(existing, userId, vehicleId)
					and existing.SwapOperationId ~= nil
					and existing.SwapOperationId ~= operationId
				then
					return existing
				end
				return {
					UserId = userId,
					VehicleId = vehicleId,
					UpdatedAt = updatedAt,
					Released = false,
					SwapOperationId = operationId,
				}
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		if not ownsRegistration(persisted, userId, vehicleId) then
			return false, "REGISTRATION_ALREADY_USED"
		end
		if persisted.SwapOperationId ~= operationId then
			return false, "REGISTRATION_SWAP_IN_PROGRESS"
		end
		return true, nil
	end

	function DataService:ReleaseCustomRegistration(
		registration: string,
		userId: number,
		vehicleId: string
	): (boolean, string?)
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
				self.mockRegistrations[registrationKey] = nil
			end
			return true, nil
		end
		-- UpdateAsync cannot delete a key: returning nil cancels the update and
		-- leaves the existing value untouched. Use an explicit free tombstone so
		-- the owner check and release remain one atomic compare-and-swap. A later
		-- reservation may overwrite Released=true, while a delayed release from an
		-- old owner cannot erase that newer claim.
		local releasedAt = os.time()
		local ok = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if existing and existing.UserId == userId and existing.VehicleId == vehicleId then
					return { Released = true, ReleasedAt = releasedAt }
				end
				return existing
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		return true, nil
	end

	-- Rollback is stricter than ordinary release: it may only retire the
	-- replacement reservation created by this exact swap operation.
	function DataService:ReleaseCustomRegistrationSwap(
		registration: string,
		userId: number,
		vehicleId: string,
		operationId: string
	): (boolean, string?)
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if
				ownsRegistration(existing, userId, vehicleId)
				and existing.SwapOperationId == operationId
			then
				self.mockRegistrations[registrationKey] = nil
			end
			return true, nil
		end

		local releasedAt = os.time()
		local ok = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if
					ownsRegistration(existing, userId, vehicleId)
					and existing.SwapOperationId == operationId
				then
					return { Released = true, ReleasedAt = releasedAt }
				end
				return existing
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		return true, nil
	end

	-- Once the profile is durably committed to the replacement plate and the old
	-- reservation has been retired, remove the operation tag from the plate that
	-- remains live. This is ownership- and operation-checked for the same reason
	-- rollback is: stale cleanup must not edit a later reservation.
	function DataService:CompleteCustomRegistrationSwap(
		registration: string,
		userId: number,
		vehicleId: string,
		operationId: string
	): (boolean, string?)
		registration = string.upper(registration)
		local registrationKey = self:_scopedKey(registration)
		if self.mock then
			local existing = self.mockRegistrations[registrationKey]
			if
				ownsRegistration(existing, userId, vehicleId)
				and existing.SwapOperationId == operationId
			then
				existing.SwapOperationId = nil
			end
			return true, nil
		end

		local ok = self:_retry(function()
			return self.registrationStore:UpdateAsync(registrationKey, function(existing)
				if
					ownsRegistration(existing, userId, vehicleId)
					and existing.SwapOperationId == operationId
				then
					existing.SwapOperationId = nil
				end
				return existing
			end)
		end)
		if not ok then
			return false, "REGISTRATION_STORE_UNAVAILABLE"
		end
		return true, nil
	end
end
