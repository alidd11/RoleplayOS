--!strict
local Utils = require(script.Parent.Utils)
local deepCopy = Utils.deepCopy

return function(DataService)
	function DataService:GetMdtRecord(key: string): (any?, string?)
		key = self:_scopedKey(key)
		if not self:_checkKey(key, "MdtRecords") then
			return nil, "MDT_RECORD_STORE_UNAVAILABLE"
		end
		if self.mock then
			return deepCopy(self.mockMdtRecords[key]), nil
		end
		local ok, result = self:_retry(function()
			return self.mdtRecordStore:GetAsync(key)
		end)
		return if ok then result else nil, if ok then nil else "MDT_RECORD_STORE_UNAVAILABLE"
	end

	function DataService:UpdateMdtRecord(key: string, transform: (any?) -> any): (any?, string?)
		key = self:_scopedKey(key)
		if not self:_checkKey(key, "MdtRecords") then
			return nil, "MDT_RECORD_STORE_UNAVAILABLE"
		end
		if self.mock then
			local updated = transform(deepCopy(self.mockMdtRecords[key]))
			self.mockMdtRecords[key] = deepCopy(updated)
			return deepCopy(updated), nil
		end
		local updated
		local ok = self:_retry(function()
			return self.mdtRecordStore:UpdateAsync(key, function(stored)
				updated = transform(stored)
				return updated
			end)
		end)
		return if ok then updated else nil, if ok then nil else "MDT_RECORD_STORE_UNAVAILABLE"
	end

	function DataService:GetMdtIndex(key: string): (any?, string?)
		key = self:_scopedKey(key)
		if not self:_checkKey(key, "MdtIndexes") then
			return nil, "MDT_INDEX_STORE_UNAVAILABLE"
		end
		if self.mock then
			return deepCopy(self.mockMdtIndexes[key]), nil
		end
		local ok, result = self:_retry(function()
			return self.mdtIndexStore:GetAsync(key)
		end)
		return if ok then result else nil, if ok then nil else "MDT_INDEX_STORE_UNAVAILABLE"
	end

	function DataService:UpdateMdtIndex(key: string, transform: (any?) -> any): (any?, string?)
		key = self:_scopedKey(key)
		if not self:_checkKey(key, "MdtIndexes") then
			return nil, "MDT_INDEX_STORE_UNAVAILABLE"
		end
		if self.mock then
			local updated = transform(deepCopy(self.mockMdtIndexes[key]))
			self.mockMdtIndexes[key] = deepCopy(updated)
			return deepCopy(updated), nil
		end
		local updated
		local ok = self:_retry(function()
			return self.mdtIndexStore:UpdateAsync(key, function(stored)
				updated = transform(stored)
				return updated
			end)
		end)
		return if ok then updated else nil, if ok then nil else "MDT_INDEX_STORE_UNAVAILABLE"
	end
end
