--!strict

local Players = game:GetService("Players")

local RecordIndexService = {
	connections = {},
	queue = {},
	queued = {},
	pendingSync = {},
	cache = {},
	running = false,
}

local function normalise(value: string): string
	return string.lower(value):gsub("[^a-z0-9 ]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

local function compact(value: string): string
	return normalise(value):gsub(" ", "")
end

local function recordKey(kind: string, id: string): string
	return kind .. ":" .. id
end

local function indexKey(kind: string, value: string): string?
	local token = string.match(normalise(value), "[a-z0-9]+") or ""
	if #token < 2 then
		return nil
	end
	return kind .. ":" .. string.sub(token, 1, 2)
end

local function activeWarrants(record: any): { any }
	local active = {}
	local now = os.time()
	for _, warrant in if type(record.Warrants) == "table" then record.Warrants else {} do
		if warrant.Active == true and (warrant.ExpiresAt == nil or warrant.ExpiresAt > now) then
			table.insert(active, warrant)
		end
	end
	return active
end

local function personView(record: any): any
	local warrants = activeWarrants(record)
	return {
		CharacterId = record.CharacterId,
		FullName = record.FullName,
		DateOfBirth = record.DateOfBirth,
		Licences = record.Licences,
		DrivingRecord = record.DrivingRecord,
		CustodyRecord = record.CustodyRecord,
		CriminalRecord = record.CriminalRecord,
		Warrants = warrants,
		Flags = if #warrants > 0 then { "WANTED" } else {},
		UpdatedAt = record.UpdatedAt,
	}
end

function RecordIndexService:Init(context: any)
	self.context = context
	table.clear(self.queue)
	table.clear(self.queued)
	table.clear(self.cache)
	table.clear(self.pendingSync)
end

function RecordIndexService:_cacheSet(key: string, value: any)
	self.cache[key] = {
		Value = value,
		ExpiresAt = os.clock() + self.context.Configuration.MDT.RecordCacheSeconds,
	}
end

function RecordIndexService:_getRecord(key: string): (any?, string?)
	local cached = self.cache[key]
	if cached and cached.ExpiresAt > os.clock() then
		return cached.Value, nil
	end
	self.cache[key] = nil
	local value, reason = self.context.Services:Get("DataService"):GetMdtRecord(key)
	if reason then
		return nil, reason
	end
	if value then
		self:_cacheSet(key, value)
	end
	return value, nil
end

function RecordIndexService:_updateRecord(key: string, transform: (any?) -> any): (any?, string?)
	local updated, reason = self.context.Services:Get("DataService"):UpdateMdtRecord(key, transform)
	if updated then
		self:_cacheSet(key, updated)
	end
	return updated, reason
end

function RecordIndexService:_upsertIndex(key: string, id: string, entry: any): (boolean, string?)
	local maximum = self.context.Configuration.MDT.MaximumIndexBucketEntries
	local updated, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(key, function(stored)
			local bucket = if type(stored) == "table" then stored else { Entries = {} }
			bucket.Entries = if type(bucket.Entries) == "table" then bucket.Entries else {}
			if bucket.Entries[id] == nil then
				local count = 0
				local oldestId
				local oldestAt = math.huge
				for existingId, existing in bucket.Entries do
					count += 1
					local updatedAt = if type(existing) == "table"
						then existing.UpdatedAt or 0
						else 0
					if updatedAt < oldestAt then
						oldestAt = updatedAt
						oldestId = existingId
					end
				end
				if count >= maximum and oldestId then
					bucket.Entries[oldestId] = nil
				end
			end
			bucket.Entries[id] = entry
			bucket.UpdatedAt = os.time()
			return bucket
		end)
	return updated ~= nil, reason
end

function RecordIndexService:IndexCharacter(player: Player, character: any): (boolean, string?)
	local fullName = character.Identity.FirstName .. " " .. character.Identity.LastName
	local personKey = recordKey("Person", character.CharacterId)
	local person, reason = self:_updateRecord(personKey, function(existing)
		return {
			RecordType = "Person",
			CharacterId = character.CharacterId,
			OwnerUserId = player.UserId,
			FullName = fullName,
			DateOfBirth = character.Identity.DateOfBirth,
			Licences = character.Licences or {},
			DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} },
			CustodyRecord = character.CustodyRecord or { Bookings = {} },
			CriminalRecord = character.CriminalRecord or {},
			Warrants = if existing and type(existing.Warrants) == "table"
				then existing.Warrants
				else {},
			UpdatedAt = os.time(),
		}
	end)
	if not person then
		return false, reason
	end
	self.context.Services:Get("WarrantService"):CachePersonRecord(person)
	local entry = {
		CharacterId = character.CharacterId,
		FullName = fullName,
		SearchText = normalise(fullName) .. "|" .. normalise(
			character.Identity.LastName .. " " .. character.Identity.FirstName
		),
		UpdatedAt = os.time(),
	}
	local seen = {}
	for _, token in { character.Identity.FirstName, character.Identity.LastName } do
		local key = indexKey("Person", token)
		if key and not seen[key] then
			seen[key] = true
			local indexed, indexReason = self:_upsertIndex(key, character.CharacterId, entry)
			if not indexed then
				return false, indexReason
			end
		end
	end
	for _, vehicle in character.Vehicles or {} do
		local indexed, vehicleReason = self:IndexVehicle(player, character, vehicle)
		if not indexed then
			return false, vehicleReason
		end
	end
	return true, nil
end

function RecordIndexService:IndexVehicle(
	player: Player,
	character: any,
	vehicle: any
): (boolean, string?)
	local key = recordKey("Vehicle", vehicle.VehicleId)
	local updated, reason = self:_updateRecord(key, function(_existing)
		return {
			RecordType = "Vehicle",
			VehicleId = vehicle.VehicleId,
			Registration = vehicle.Registration,
			DefinitionId = vehicle.DefinitionId,
			OwnerCharacterId = character.CharacterId,
			OwnerUserId = player.UserId,
			OwnerName = character.Identity.FirstName .. " " .. character.Identity.LastName,
			Colour = vehicle.Colour,
			Mileage = vehicle.Mileage or 0,
			Condition = vehicle.Condition or 100,
			Insured = vehicle.Insured == true,
			Taxed = vehicle.Taxed == true,
			UpdatedAt = os.time(),
		}
	end)
	if not updated then
		return false, reason
	end
	local search = compact(vehicle.Registration)
	local bucket = indexKey("Vehicle", search)
	if not bucket then
		return false, "INVALID_REGISTRATION_INDEX"
	end
	return self:_upsertIndex(bucket, vehicle.VehicleId, {
		VehicleId = vehicle.VehicleId,
		Registration = vehicle.Registration,
		SearchText = search,
		UpdatedAt = os.time(),
	})
end

function RecordIndexService:_removeVehicleIndex(registration: string, vehicleId: string)
	local bucket = indexKey("Vehicle", compact(registration))
	if not bucket then
		return
	end
	local _, reason = self.context.Services
		:Get("DataService")
		:UpdateMdtIndex(bucket, function(stored)
			if type(stored) ~= "table" or type(stored.Entries) ~= "table" then
				return stored
			end
			stored.Entries[vehicleId] = nil
			stored.UpdatedAt = os.time()
			return stored
		end)
	if reason then
		self.context.Logger:Warning("Stale vehicle index removal failed", {
			VehicleId = vehicleId,
			Error = reason,
		})
	end
end

function RecordIndexService:ReindexVehicle(
	player: Player,
	character: any,
	vehicle: any,
	previousRegistration: string?
): (boolean, string?)
	local indexed, reason = self:IndexVehicle(player, character, vehicle)
	if
		indexed
		and previousRegistration
		and compact(previousRegistration) ~= compact(vehicle.Registration)
	then
		self:_removeVehicleIndex(previousRegistration, vehicle.VehicleId)
	end
	return indexed, reason
end

function RecordIndexService:ScheduleCharacter(player: Player, character: any)
	local key = "Person:" .. character.CharacterId
	local existing = self.pendingSync[key]
	if existing then
		existing.Resync = true
		return
	end
	local state = { Resync = false }
	self.pendingSync[key] = state
	task.spawn(function()
		local ok, reason
		repeat
			state.Resync = false
			ok, reason = self:IndexCharacter(player, character)
		until not state.Resync
		self.pendingSync[key] = nil
		if not ok then
			self.context.Logger:Warning("Deferred MDT character indexing failed", {
				CharacterId = character.CharacterId,
				Error = reason,
			})
		end
	end)
end

function RecordIndexService:ScheduleVehicle(
	player: Player,
	character: any,
	vehicle: any,
	previousRegistration: string?
)
	local key = "Vehicle:" .. vehicle.VehicleId
	local existing = self.pendingSync[key]
	if existing then
		existing.Resync = true
		if previousRegistration then
			existing.PreviousRegistration = existing.PreviousRegistration or previousRegistration
		end
		return
	end
	local state = { Resync = false, PreviousRegistration = previousRegistration }
	self.pendingSync[key] = state
	task.spawn(function()
		local ok, reason
		repeat
			state.Resync = false
			local previous = state.PreviousRegistration
			state.PreviousRegistration = nil
			ok, reason = self:ReindexVehicle(player, character, vehicle, previous)
		until not state.Resync
		self.pendingSync[key] = nil
		if not ok then
			self.context.Logger:Warning("Deferred MDT vehicle indexing failed", {
				VehicleId = vehicle.VehicleId,
				Error = reason,
			})
		end
	end)
end

function RecordIndexService:GetPerson(characterId: string): (any?, string?)
	return self:_getRecord(recordKey("Person", characterId))
end

function RecordIndexService:UpdatePerson(
	characterId: string,
	transform: (any?) -> any
): (any?, string?)
	return self:_updateRecord(recordKey("Person", characterId), transform)
end

function RecordIndexService:SearchPeople(query: string, page: number): (any?, string?)
	local search = normalise(query)
	local key = indexKey("Person", search)
	if not key then
		return nil, "QUERY_TOO_SHORT"
	end
	local bucket, reason = self.context.Services:Get("DataService"):GetMdtIndex(key)
	if reason then
		return nil, reason
	end
	local matches = {}
	for _, entry in if bucket and type(bucket.Entries) == "table" then bucket.Entries else {} do
		if
			type(entry.SearchText) == "string" and string.find(entry.SearchText, search, 1, true)
		then
			table.insert(matches, entry)
		end
	end
	table.sort(matches, function(a, b)
		return a.FullName < b.FullName
	end)
	local size = self.context.Configuration.MDT.PageSize
	page = math.max(1, math.floor(page))
	local first = (page - 1) * size + 1
	local items = {}
	for index = first, math.min(#matches, first + size - 1) do
		local record, recordReason = self:GetPerson(matches[index].CharacterId)
		if recordReason then
			return nil, recordReason
		end
		if record then
			table.insert(items, personView(record))
		end
	end
	return { Items = items, Page = page, Total = #matches }, nil
end

function RecordIndexService:SearchVehicles(query: string, page: number): (any?, string?)
	local search = compact(query)
	local key = indexKey("Vehicle", search)
	if not key then
		return nil, "QUERY_TOO_SHORT"
	end
	local bucket, reason = self.context.Services:Get("DataService"):GetMdtIndex(key)
	if reason then
		return nil, reason
	end
	local matches = {}
	for _, entry in if bucket and type(bucket.Entries) == "table" then bucket.Entries else {} do
		if
			type(entry.SearchText) == "string" and string.find(entry.SearchText, search, 1, true)
		then
			table.insert(matches, entry)
		end
	end
	table.sort(matches, function(a, b)
		return a.Registration < b.Registration
	end)
	local size = self.context.Configuration.MDT.PageSize
	page = math.max(1, math.floor(page))
	local first = (page - 1) * size + 1
	local items = {}
	for index = first, math.min(#matches, first + size - 1) do
		local record, recordReason = self:_getRecord(recordKey("Vehicle", matches[index].VehicleId))
		if recordReason then
			return nil, recordReason
		end
		if record then
			local owner = select(1, self:GetPerson(record.OwnerCharacterId))
			local wanted = owner and #activeWarrants(owner) > 0
			table.insert(items, {
				VehicleId = record.VehicleId,
				Registration = record.Registration,
				DefinitionId = record.DefinitionId,
				OwnerCharacterId = record.OwnerCharacterId,
				OwnerName = record.OwnerName,
				Colour = record.Colour,
				Mileage = record.Mileage,
				Condition = record.Condition,
				Insured = record.Insured,
				Taxed = record.Taxed,
				Flags = if wanted then { "WANTED" } else {},
				UpdatedAt = record.UpdatedAt,
			})
		end
	end
	return { Items = items, Page = page, Total = #matches }, nil
end

function RecordIndexService:_queuePlayer(player: Player)
	if self.queued[player.UserId] then
		return
	end
	self.queued[player.UserId] = true
	table.insert(self.queue, player)
end

function RecordIndexService:_indexPlayer(player: Player)
	local deadline = os.clock() + 30
	local session
	repeat
		session = self.context.Services:Get("DataService"):GetSession(player)
		if not session then
			task.wait(0.25)
		end
	until session or not player.Parent or os.clock() >= deadline
	if not session then
		return
	end
	for _, character in session.Profile.Characters do
		local ok, reason = self:IndexCharacter(player, character)
		if not ok then
			self.context.Logger:Warning("MDT background indexing failed", {
				CharacterId = character.CharacterId,
				Error = reason,
			})
		end
		task.wait(self.context.Configuration.MDT.IndexWriteSpacingSeconds)
	end
end

function RecordIndexService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			self:_queuePlayer(player)
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_queuePlayer(player)
	end
	task.spawn(function()
		while self.running do
			local player = table.remove(self.queue, 1)
			if player then
				self.queued[player.UserId] = nil
				self:_indexPlayer(player)
			else
				task.wait(0.5)
			end
		end
	end)
end

function RecordIndexService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.queue)
	table.clear(self.queued)
	table.clear(self.cache)
	table.clear(self.pendingSync)
end

return RecordIndexService
