--!strict

local DELETED_FIELD = "__RoleplayOSDeleted"

local function isDeleted(value: any): boolean
	return type(value) == "table" and value[DELETED_FIELD] == true
end

return function(DataService)
	function DataService:GetSharedRecord(recordId: string): (any?, string?)
		if self.mock then
			return self.mockSharedRecords[recordId], nil
		end
		local ok, result = self:_retry(function()
			return self.sharedRecordStore:GetAsync(recordId)
		end, nil, Enum.DataStoreRequestType.GetAsync)
		if not ok then
			self.context.Logger:Error("Shared record load failed", { RecordId = recordId })
			return nil, "SHARED_RECORD_LOAD_FAILED"
		end
		if isDeleted(result) then
			return nil, nil
		end
		return result, nil
	end

	function DataService:UpdateSharedRecord(
		recordId: string,
		transform: (any?) -> any
	): (any?, string?)
		if self.mock then
			local updated = transform(self.mockSharedRecords[recordId])
			self.mockSharedRecords[recordId] = updated
			return updated, nil
		end
		local updated
		local ok = self:_retry(function()
			return self.sharedRecordStore:UpdateAsync(recordId, function(stored)
				-- UpdateAsync treats nil as "cancel this write", while the in-memory
				-- implementation naturally treats nil as deletion. Preserve one
				-- persistence contract by representing a deleted shared record with an
				-- internal tombstone and hiding that marker from every caller.
				local logicalStored = if isDeleted(stored) then nil else stored
				updated = transform(logicalStored)
				if updated == nil then
					return {
						[DELETED_FIELD] = true,
						DeletedAt = os.time(),
					}
				end
				return updated
			end)
		end)
		if not ok then
			self.context.Logger:Error("Shared record update failed", { RecordId = recordId })
			return nil, "SHARED_RECORD_UPDATE_FAILED"
		end
		return updated, nil
	end
end
