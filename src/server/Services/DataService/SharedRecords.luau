--!strict
local Utils = require(script.Parent.Utils)
local deepCopy = Utils.deepCopy

local DELETED_FIELD = "__RoleplayOSDeleted"

local function isDeleted(value: any): boolean
	return type(value) == "table" and value[DELETED_FIELD] == true
end

local function mockRecordKey(recordId: string, scopeId: string?): string
	return if scopeId == nil then recordId else scopeId .. "\0" .. recordId
end

return function(DataService)
	function DataService:GetSharedRecord(recordId: string, scopeId: string?): (any?, string?)
		if not self:_validateSharedRecordScope(scopeId) then
			return nil, "SHARED_RECORD_LOAD_FAILED"
		end
		local storageKey = mockRecordKey(recordId, scopeId)
		if self.mock then
			-- Match DataStore semantics: callers receive a detached value. Returning
			-- the stored table itself let a later local mutation silently change the
			-- mock record without UpdateSharedRecord, hiding missing durable writes
			-- during Studio testing.
			return deepCopy(self.mockSharedRecords[storageKey]), nil
		end
		local store = self:_sharedRecordStoreForScope(scopeId)
		if not store then
			return nil, "SHARED_RECORD_LOAD_FAILED"
		end
		local ok, result = self:_retry(function()
			return store:GetAsync(recordId)
		end, nil, Enum.DataStoreRequestType.GetAsync)
		if not ok then
			self.context.Logger:Error("Shared record load failed", {
				RecordId = recordId,
				ScopeId = scopeId,
			})
			return nil, "SHARED_RECORD_LOAD_FAILED"
		end
		if isDeleted(result) then
			return nil, nil
		end
		return result, nil
	end

	function DataService:UpdateSharedRecord(
		recordId: string,
		transform: (any?) -> any,
		scopeId: string?
	): (any?, string?)
		if not self:_validateSharedRecordScope(scopeId) then
			return nil, "SHARED_RECORD_UPDATE_FAILED"
		end
		local storageKey = mockRecordKey(recordId, scopeId)
		if self.mock then
			-- UpdateAsync gives its transform an isolated deserialised value and the
			-- returned result is persisted independently of the caller's table.
			-- Preserve those boundaries in Studio so mock behaviour cannot make an
			-- accidental reference mutation look like a successful durable update.
			local updated = transform(deepCopy(self.mockSharedRecords[storageKey]))
			self.mockSharedRecords[storageKey] = deepCopy(updated)
			return deepCopy(updated), nil
		end
		local store = self:_sharedRecordStoreForScope(scopeId)
		if not store then
			return nil, "SHARED_RECORD_UPDATE_FAILED"
		end
		local updated
		local ok = self:_retry(function()
			return store:UpdateAsync(recordId, function(stored)
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
			self.context.Logger:Error("Shared record update failed", {
				RecordId = recordId,
				ScopeId = scopeId,
			})
			return nil, "SHARED_RECORD_UPDATE_FAILED"
		end
		return updated, nil
	end

	-- Progression services use these wrappers when the same logical record name
	-- must remain separate between the public domain and an official server.
	-- A nil scope deliberately preserves the historical public/global store.
	function DataService:GetScopedSharedRecord(
		scopeId: string?,
		recordId: string
	): (any?, string?)
		return self:GetSharedRecord(recordId, scopeId)
	end

	function DataService:UpdateScopedSharedRecord(
		scopeId: string?,
		recordId: string,
		transform: (any?) -> any
	): (any?, string?)
		return self:UpdateSharedRecord(recordId, transform, scopeId)
	end
end
