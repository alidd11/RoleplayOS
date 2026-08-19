--!strict

local CollectionService = game:GetService("CollectionService")

-- Territory zones: the second piece of docs/GANG_SYSTEM_SPEC.md, on top of the
-- membership GangService already persists.
--
-- Tagged parts in the map, discovered through CollectionService the same way
-- RoleplayOSZone already works for LocationController -- an id and a name on
-- an invisible part, found rather than hand-listed, so placing one in Studio
-- is what defines a territory. A different tag from RoleplayOSZone, not a
-- shared one: that tag means "a street or district for the location banner to
-- read", and a territory is an unrelated concept that happens to also be a
-- tagged part in the map.
--
-- Ownership is server authoritative and lives in a shared record, "gang-
-- territory-owners", the same DataService mechanism GangService already uses
-- for a gang itself -- there are only ever as many territories as the map was
-- authored with, so one small record is the whole of it rather than one per
-- zone. The part's own OwnerGangId attribute is a replicated mirror of that
-- record, not a second copy of the truth: clients read it for free, nothing
-- server-side ever reads it back.
--
-- What claims a territory is not built here. That is claiming and contesting,
-- the next piece -- this is the data a contest changes, in the same way
-- GangRules validated invites before GangService existed to call it.
local GangTerritoryService = {
	connections = {},
	-- TerritoryId -> { Id, Name, Part }. Ownership is not cached here: it is
	-- read from the shared record whenever it is asked for, so this table
	-- cannot itself go stale.
	territories = {},
}

local TERRITORY_OWNERS_RECORD = "gang-territory-owners"

local function gangKey(gangId: string): string
	return "gang:" .. gangId
end

function GangTerritoryService:Init(context: any)
	self.context = context
end

-- Reads a territory's id and display name off the part that defines it.
--
-- Refused rather than partially adopted: a territory with no id cannot be
-- addressed by anything that claims or pays out to it, and one with no name
-- has nothing to show a player standing in it.
function GangTerritoryService:_describe(part: Instance): (string?, string?)
	local id = part:GetAttribute("TerritoryId")
	local name = part:GetAttribute("DisplayName")
	if type(id) ~= "string" or id == "" then
		return nil, "TERRITORY_ID_MISSING"
	end
	if type(name) ~= "string" or name == "" then
		return nil, "DISPLAY_NAME_MISSING"
	end
	return id, name
end

function GangTerritoryService:_adopt(part: Instance)
	local id, nameOrReason = self:_describe(part)
	if not id then
		self.context.Logger:Warning("Territory part is missing an attribute", {
			Part = part:GetFullName(),
			Reason = nameOrReason,
		})
		return
	end
	local existing = self.territories[id]
	if existing and existing.Part ~= part then
		-- Two parts claiming the same id would make every later lookup
		-- ambiguous about which one a claim, a payout or a spawn actually
		-- means. The first one placed keeps the id; the second is refused and
		-- named in the log so it can be fixed in Studio.
		self.context.Logger:Warning("Duplicate territory id, second part refused", {
			TerritoryId = id,
			KeptPart = existing.Part:GetFullName(),
			RefusedPart = part:GetFullName(),
		})
		return
	end
	self.territories[id] = { Id = id, Name = nameOrReason, Part = part }
	part.Destroying:Once(function()
		if self.territories[id] and self.territories[id].Part == part then
			self.territories[id] = nil
		end
	end)
	self:_mirror(id)
end

-- Writes the current owner onto the part as an attribute, for clients to read
-- without a round trip. "" means unclaimed -- attributes cannot hold nil, and
-- an empty gang id is not a value anything else in the framework produces.
function GangTerritoryService:_mirror(territoryId: string)
	local territory = self.territories[territoryId]
	if not territory then
		return
	end
	local owners = self.context.Services:Get("DataService"):GetSharedRecord(TERRITORY_OWNERS_RECORD)
	local ownerGangId = type(owners) == "table" and owners[territoryId]
	territory.Part:SetAttribute(
		"OwnerGangId",
		if type(ownerGangId) == "string" then ownerGangId else ""
	)
end

function GangTerritoryService:Start()
	local tag = self.context.Configuration.Gangs.TerritoryTag
	for _, part in CollectionService:GetTagged(tag) do
		self:_adopt(part)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
			self:_adopt(part)
		end)
	)
	local count = 0
	for _ in self.territories do
		count += 1
	end
	self.context.Logger:Info("Gang territories discovered", { Count = count })
end

-- Every territory this server knows about, for a status panel or a map.
function GangTerritoryService:List(): { any }
	local owners = self.context.Services:Get("DataService"):GetSharedRecord(TERRITORY_OWNERS_RECORD)
	local result = {}
	for id, territory in self.territories do
		local ownerGangId = type(owners) == "table" and owners[id]
		table.insert(result, {
			Id = id,
			Name = territory.Name,
			OwnerGangId = if type(ownerGangId) == "string" and ownerGangId ~= ""
				then ownerGangId
				else nil,
		})
	end
	return result
end

function GangTerritoryService:OwnerOf(territoryId: string): string?
	local owners = self.context.Services:Get("DataService"):GetSharedRecord(TERRITORY_OWNERS_RECORD)
	local ownerGangId = type(owners) == "table" and owners[territoryId]
	return if type(ownerGangId) == "string" and ownerGangId ~= "" then ownerGangId else nil
end

-- Moves a territory to a new owner, or to nobody. The only mutation primitive
-- here -- what decides to call it with what is the contest loop this piece
-- does not build.
--
-- Keeps three records in step: the territory-owners record, which is the
-- source of truth; the gang losing the territory, whose TerritoryId is
-- cleared if this was the one it pointed at; and the gang gaining it, whose
-- TerritoryId is set to match. A gang record exists independently of any
-- territory, so a missing losing or gaining gang is not refused -- there is
-- nothing left on that side to keep in step with.
function GangTerritoryService:SetOwner(territoryId: string, newGangId: string?): (boolean, string?)
	if not self.territories[territoryId] then
		return false, "TERRITORY_NOT_FOUND"
	end
	local dataService = self.context.Services:Get("DataService")
	local previousGangId: string? = nil
	local _, ownersReason = dataService:UpdateSharedRecord(TERRITORY_OWNERS_RECORD, function(owners)
		owners = if type(owners) == "table" then owners else {}
		previousGangId = if type(owners[territoryId]) == "string"
				and owners[territoryId] ~= ""
			then owners[territoryId]
			else nil
		if newGangId then
			owners[territoryId] = newGangId
		else
			owners[territoryId] = nil
		end
		return owners
	end)
	if ownersReason then
		return false, "TERRITORY_UPDATE_FAILED"
	end
	self:_mirror(territoryId)
	if previousGangId and previousGangId ~= newGangId then
		dataService:UpdateSharedRecord(gangKey(previousGangId), function(gang)
			if type(gang) == "table" and gang.TerritoryId == territoryId then
				gang.TerritoryId = nil
			end
			return gang
		end)
	end
	if newGangId and newGangId ~= previousGangId then
		dataService:UpdateSharedRecord(gangKey(newGangId), function(gang)
			if type(gang) == "table" then
				gang.TerritoryId = territoryId
			end
			return gang
		end)
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "GangTerritory.OwnerChanged",
		Target = territoryId,
		Metadata = { From = previousGangId, To = newGangId },
	})
	return true, nil
end

function GangTerritoryService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.territories)
end

return GangTerritoryService
