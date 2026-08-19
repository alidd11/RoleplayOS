--!strict
return function(DataService)
	function DataService:GetSharedRecord(recordId: string): (any?, string?)
		if self.mock then
			return self.mockSharedRecords[recordId], nil
		end
		local ok, result = self:_retry(function()
			return self.sharedRecordStore:GetAsync(recordId)
		end)
		if not ok then
			self.context.Logger:Error("Shared record load failed", { RecordId = recordId })
			return nil, "SHARED_RECORD_LOAD_FAILED"
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
				updated = transform(stored)
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
