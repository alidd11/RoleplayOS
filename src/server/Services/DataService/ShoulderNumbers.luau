--!strict
local Utils = require(script.Parent.Utils)
local deepCopy = Utils.deepCopy

return function(DataService)
	-- Claims the next shoulder number for a department and records who holds it.
	--
	-- The counter and the holder record are two keys, and only the counter is
	-- allocated under UpdateAsync, so a server that dies between the two burns a
	-- number without assigning it. That is the safe direction to fail: a gap in the
	-- sequence is invisible, whereas issuing the same number twice would put two
	-- officers on air as the same unit. Numbers are plentiful and never reissued.
	function DataService:AllocateShoulderNumber(
		departmentId: string,
		userId: number,
		start: number
	): (number?, string?)
		local counterKey = self:_scopedKey("counter:" .. departmentId)
		local holderKey = self:_scopedKey(departmentId .. ":" .. tostring(start))
		local issued: number? = nil
		if self.mock then
			local current = self.mockShoulder[counterKey]
			issued = if type(current) == "number" then current + 1 else start
			self.mockShoulder[counterKey] = issued
			holderKey = self:_scopedKey(departmentId .. ":" .. tostring(issued))
			self.mockShoulder[holderKey] = { UserId = userId, AssignedAt = os.time() }
			return issued, nil
		end
		local ok = self:_retry(function()
			return self.shoulderStore:UpdateAsync(counterKey, function(stored)
				issued = if type(stored) == "number" then stored + 1 else start
				return issued
			end)
		end)
		if not ok or not issued then
			return nil, "SHOULDER_NUMBER_STORE_UNAVAILABLE"
		end
		holderKey = self:_scopedKey(departmentId .. ":" .. tostring(issued))
		-- The holder record is what the staff export reads. Losing it costs the
		-- reconciliation view, not the allocation, so a failure here is warned about
		-- rather than surfaced as a refusal to go on duty.
		local recorded = self:_retry(function()
			return self.shoulderStore:SetAsync(
				holderKey,
				{ UserId = userId, AssignedAt = os.time() }
			)
		end)
		if not recorded then
			self.context.Logger:Warning("Shoulder number holder record failed", {
				DepartmentId = departmentId,
				Number = issued,
				UserId = userId,
			})
		end
		return issued, nil
	end

	function DataService:GetShoulderNumberHolder(
		departmentId: string,
		number: number
	): (any?, string?)
		local holderKey = self:_scopedKey(departmentId .. ":" .. tostring(number))
		if self.mock then
			return deepCopy(self.mockShoulder[holderKey]), nil
		end
		local ok, result = self:_retry(function()
			return self.shoulderStore:GetAsync(holderKey)
		end)
		return if ok then result else nil, if ok then nil else "SHOULDER_NUMBER_STORE_UNAVAILABLE"
	end
end
