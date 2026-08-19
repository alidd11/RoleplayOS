--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GangRules = require(ReplicatedStorage.RoleplayOS.Shared.GangRules)
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)

-- Territory zones, and claiming and contesting them: the second and third
-- pieces of docs/GANG_SYSTEM_SPEC.md, on top of the membership GangService
-- already persists.
--
-- Tagged parts in the map, discovered through CollectionService the same way
-- RoleplayOSZone already works for LocationController -- an id and a name on
-- an invisible part, found rather than hand-listed, so placing one in Studio
-- is what defines a territory. A different tag from RoleplayOSZone,
-- deliberately: that one means a street or district for the location banner,
-- not a gang's ground.
--
-- Ownership is server authoritative and lives in a shared record, "gang-
-- territory-owners", the same DataService mechanism GangService already uses
-- for a gang itself -- there are only ever as many territories as the map was
-- authored with, so one small record is the whole of it rather than one per
-- zone. Each territory part carries two attributes mirroring that record,
-- OwnerGangId and OwnerChangedAt, and the contest loop below reads only
-- those, never the record itself: a tick runs every few seconds per
-- territory, and a DataStore GetAsync on that cadence is exactly the kind of
-- read volume that gets a server throttled. The record is touched at boot,
-- to seed the mirror, and on an actual change, never in between.
--
-- Contesting is presence based, per the spec: a gang with a strict majority
-- in the zone becomes its challenger, and holding that lead continuously for
-- GangRules.ContestSeconds is what commits the flip -- a momentary majority
-- that breaks before then has to start over. GangRules.contestOutcome
-- already decides who is leading a given instant, including that police
-- presence suppresses any resolution outright; this is what tracks whether
-- that lead has held long enough, and what enforces the cooldown after a
-- change so two gangs of similar size cannot trade a zone indefinitely.
--
-- Police clearing is the same shape as a contest, aimed the other way: a
-- contest is a continuous lead building toward a flip, a clear is continuous
-- police suppression building toward a reset to unowned. Both live in memory
-- for the same reason -- a server restart losing progress on either is
-- correct, since nobody has held anything long enough yet for it to mean
-- something.
--
-- A dispatch call is raised the moment a contest starts, once per attempt,
-- the same way ANPRService raises one on a wanted-plate hit: an automated
-- caller, not a player at a console.
--
-- Income runs on its own loop, on Payroll's own interval rather than a new
-- one, per the spec. It pays a flat total per owned territory, split across
-- whichever of the gang's members are online with an active character right
-- now -- not accrued, not queued. A period with nobody online simply pays
-- nothing: the alternative, banking a debt to be settled later, is exactly
-- the repeatable-by-rejoining shape the spec warns against.
local GangTerritoryService = {
	connections = {},
	running = false,
	-- TerritoryId -> { Id, Name, Part }. Ownership is not cached here: the
	-- part's own attributes are the live mirror, so this table cannot go
	-- stale by holding a second copy of it.
	territories = {},
	-- TerritoryId -> { ChallengerGangId, StartedAt }. In memory only.
	contests = {},
	-- TerritoryId -> { StartedAt }. In memory only. Separate from contests
	-- because a clear can run while nobody is contesting at all -- police
	-- suppress and hold an already-quiet, already-owned zone just the same.
	policeClears = {},
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
			self.contests[id] = nil
			self.policeClears[id] = nil
		end
	end)
	self:_seedMirror(id)
end

-- Writes the persisted owner onto the part's attributes. Called once, when a
-- territory is first adopted, to bring a fresh mirror in line with whatever
-- the record already says -- a server that has just started has not changed
-- anything yet, so this is the only time adoption itself touches the record.
function GangTerritoryService:_seedMirror(territoryId: string)
	local territory = self.territories[territoryId]
	if not territory then
		return
	end
	local owners = self.context.Services:Get("DataService"):GetSharedRecord(TERRITORY_OWNERS_RECORD)
	local record = type(owners) == "table" and owners[territoryId]
	local gangId = type(record) == "table" and record.GangId
	local changedAt = type(record) == "table" and record.ChangedAt
	territory.Part:SetAttribute("OwnerGangId", if type(gangId) == "string" then gangId else "")
	territory.Part:SetAttribute(
		"OwnerChangedAt",
		if type(changedAt) == "number" then changedAt else 0
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
	self.running = true
	task.spawn(function()
		while self.running do
			task.wait(self.context.Configuration.Gangs.ContestCheckSeconds)
			-- Guarded per territory, the same reason CustodyService's sentence
			-- tick guards per prisoner: one bad read must not stop every other
			-- territory's contest from being checked for the rest of the tick.
			for territoryId in self.territories do
				local ok, problem = pcall(function()
					self:_tick(territoryId)
				end)
				if not ok then
					self.context.Logger:Error("Gang territory contest tick failed", {
						TerritoryId = territoryId,
						Error = tostring(problem),
					})
				end
			end
		end
	end)
	task.spawn(function()
		while self.running do
			task.wait(self.context.Configuration.Payroll.IntervalSeconds)
			local ok, problem = pcall(function()
				self:_payIncome()
			end)
			if not ok then
				self.context.Logger:Error(
					"Gang territory income failed",
					{ Error = tostring(problem) }
				)
			end
		end
	end)
end

-- Whether a world position sits inside a part's own bounds, in the part's
-- local space. Not a physics query: territory parts are not expected to be
-- collidable or queryable, since they exist to be tagged and sized, not
-- touched, and a physics-based spatial query would silently see nothing if
-- either was ever turned off.
local function pointInPart(position: Vector3, part: BasePart): boolean
	local relative = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Y) <= half.Y
		and math.abs(relative.Z) <= half.Z
end

-- Who is standing in a territory right now, by gang, and how many on-duty
-- police are among them. One pass over the server's players per territory
-- per tick -- there are only ever a handful of territories and a server's
-- players are never many thousands, so this stays cheap without an index.
function GangTerritoryService:_presence(part: BasePart): ({ [string]: number }, number)
	local presentByGang: { [string]: number } = {}
	local policePresent = 0
	local dataService = self.context.Services:Get("DataService")
	local dutyService = self.context.Services:Get("DutyService")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and pointInPart((root :: BasePart).Position, part) then
			local session = dataService:GetSession(player)
			local gangId = session and session.Profile.GangId
			if type(gangId) == "string" then
				presentByGang[gangId] = (presentByGang[gangId] or 0) + 1
			end
			local duty = dutyService:Get(player)
			if duty and duty.DepartmentId == "Police" then
				policePresent += 1
			end
		end
	end
	return presentByGang, policePresent
end

-- Raises a dispatch call for a contest that has just started, the same
-- automated-caller shape ANPRService uses for a wanted-plate hit: no player
-- at a console, a real CallService record so it shows up on the same board.
function GangTerritoryService:_raiseContestCall(territory: any)
	self.context.Services:Get("CallService"):Create({
		Summary = "Gang activity reported at " .. territory.Name,
		Location = territory.Name,
		Position = MapProjection.serialise(territory.Part.Position),
		Priority = "Prompt",
		IncidentType = "Crime in progress",
		DepartmentIds = { "Police", "Control" },
		Source = "GangTerritory",
		CallerName = "Automatic gang activity report",
	})
end

function GangTerritoryService:_tick(territoryId: string)
	local territory = self.territories[territoryId]
	if not territory then
		return
	end
	local part = territory.Part
	local holderGangId = part:GetAttribute("OwnerGangId")
	holderGangId = if type(holderGangId) == "string" and holderGangId ~= ""
		then holderGangId
		else nil
	local changedAt = part:GetAttribute("OwnerChangedAt")
	changedAt = if type(changedAt) == "number" then changedAt else 0
	if os.time() - changedAt < GangRules.ClaimCooldownSeconds then
		-- In cooldown: no contest and no clear can progress here at all. Any
		-- lead being built is dropped rather than left to complete the instant
		-- the cooldown ends on a presence count that may no longer be current.
		self.contests[territoryId] = nil
		self.policeClears[territoryId] = nil
		return
	end
	local presentByGang, policePresent = self:_presence(part)
	local leaderId, reason = GangRules.contestOutcome(holderGangId, presentByGang, policePresent)
	if reason == "SUPPRESSED_BY_POLICE" then
		self.contests[territoryId] = nil
		if not holderGangId then
			-- Nothing to clear: an unowned zone is already the outcome a clear
			-- would produce.
			self.policeClears[territoryId] = nil
			return
		end
		local clear = self.policeClears[territoryId]
		if not clear then
			self.policeClears[territoryId] = { StartedAt = os.time() }
			return
		end
		if os.time() - clear.StartedAt < GangRules.PoliceClearSeconds then
			return
		end
		self.policeClears[territoryId] = nil
		self:SetOwner(territoryId, nil)
		return
	end
	-- Any outcome other than sustained police suppression breaks a clear in
	-- progress, the same as a broken lead breaks a contest in progress: the
	-- continuous hold is the whole requirement.
	self.policeClears[territoryId] = nil
	if reason ~= "CONTESTED" or not leaderId then
		-- HELD or NO_CHANGE: nothing is currently building toward a flip.
		self.contests[territoryId] = nil
		return
	end
	local challenge = self.contests[territoryId]
	if not challenge or challenge.ChallengerGangId ~= leaderId then
		self.contests[territoryId] = { ChallengerGangId = leaderId, StartedAt = os.time() }
		self.context.Logger:Info("Gang territory contest started", {
			TerritoryId = territoryId,
			ChallengerGangId = leaderId,
			HolderGangId = holderGangId,
		})
		self:_raiseContestCall(territory)
		return
	end
	if os.time() - challenge.StartedAt < GangRules.ContestSeconds then
		return
	end
	self.contests[territoryId] = nil
	self:SetOwner(territoryId, leaderId)
end

-- Every territory this server knows about, for a status panel or a map.
function GangTerritoryService:List(): { any }
	local result = {}
	for id, territory in self.territories do
		local ownerGangId = territory.Part:GetAttribute("OwnerGangId")
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
	local territory = self.territories[territoryId]
	if not territory then
		return nil
	end
	local ownerGangId = territory.Part:GetAttribute("OwnerGangId")
	return if type(ownerGangId) == "string" and ownerGangId ~= "" then ownerGangId else nil
end

-- The part a territory's ground actually is, for anything that needs to
-- position something there -- a member spawning in rather than at the
-- civilian spawn, most immediately.
function GangTerritoryService:PartOf(territoryId: string): BasePart?
	local territory = self.territories[territoryId]
	return territory and territory.Part
end

function GangTerritoryService:NameOf(territoryId: string): string?
	local territory = self.territories[territoryId]
	return territory and territory.Name
end

-- Moves a territory to a new owner, or to nobody. The one mutation primitive:
-- what decides to call it with what is the contest and police-clear tick
-- above.
--
-- Keeps four things in step: the territory-owners record, which is the
-- persisted source of truth; the part's own mirrored attributes, which is
-- what the contest loop and every client actually read; the gang losing the
-- territory, whose TerritoryId is cleared if this was the one it pointed at;
-- and the gang gaining it, whose TerritoryId is set to match. A gang record
-- exists independently of any territory, so a missing losing or gaining gang
-- is not refused -- there is nothing left on that side to keep in step with.
function GangTerritoryService:SetOwner(territoryId: string, newGangId: string?): (boolean, string?)
	local territory = self.territories[territoryId]
	if not territory then
		return false, "TERRITORY_NOT_FOUND"
	end
	local dataService = self.context.Services:Get("DataService")
	local changedAt = os.time()
	local previousGangId: string? = nil
	local _, ownersReason = dataService:UpdateSharedRecord(TERRITORY_OWNERS_RECORD, function(owners)
		owners = if type(owners) == "table" then owners else {}
		local existing = owners[territoryId]
		previousGangId = if type(existing) == "table"
				and type(existing.GangId) == "string"
				and existing.GangId ~= ""
			then existing.GangId
			else nil
		if newGangId then
			owners[territoryId] = { GangId = newGangId, ChangedAt = changedAt }
		else
			owners[territoryId] = nil
		end
		return owners
	end)
	if ownersReason then
		return false, "TERRITORY_UPDATE_FAILED"
	end
	territory.Part:SetAttribute("OwnerGangId", newGangId or "")
	territory.Part:SetAttribute("OwnerChangedAt", changedAt)
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

-- Pays every owned territory's income for one period. Reads the owning gang's
-- record once per owned territory -- at Payroll's interval rather than the
-- contest tick's, this is nowhere near the read volume that DataStore
-- throttling would care about.
function GangTerritoryService:_payIncome()
	local income = self.context.Configuration.Gangs.TerritoryIncomePerInterval
	if not income or income <= 0 then
		return
	end
	local dataService = self.context.Services:Get("DataService")
	for territoryId, territory in self.territories do
		local ownerGangId = territory.Part:GetAttribute("OwnerGangId")
		if type(ownerGangId) == "string" and ownerGangId ~= "" then
			local gang = dataService:GetSharedRecord(gangKey(ownerGangId))
			if type(gang) == "table" then
				self:_payGangShare(gang, income, territoryId)
			end
		end
	end
end

-- Splits one territory's income across whichever of the gang's members are
-- online right now with an active character. Flat total, not per member: a
-- twelve-member gang and a two-member gang holding the same ground earn the
-- same total, split thinner or thicker.
function GangTerritoryService:_payGangShare(gang: any, income: number, territoryId: string)
	local roster = {}
	if type(gang.LeaderUserId) == "number" then
		table.insert(roster, gang.LeaderUserId)
	end
	if type(gang.MemberUserIds) == "table" then
		for _, userId in gang.MemberUserIds do
			if userId ~= gang.LeaderUserId then
				table.insert(roster, userId)
			end
		end
	end
	local dataService = self.context.Services:Get("DataService")
	local recipients = {}
	for _, userId in roster do
		local player = Players:GetPlayerByUserId(userId)
		local session = player and dataService:GetSession(player)
		local characterId = session and session.ActiveCharacterId
		if player and characterId then
			table.insert(recipients, { Player = player, CharacterId = characterId })
		end
	end
	if #recipients == 0 then
		return
	end
	local share = math.floor(income / #recipients)
	if share <= 0 then
		return
	end
	local economyService = self.context.Services:Get("EconomyService")
	for _, recipient in recipients do
		economyService:Apply(recipient.Player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = recipient.CharacterId,
			Direction = "Credit",
			Amount = share,
			ReasonCode = "GangTerritoryIncome",
			Metadata = { TerritoryId = territoryId, GangId = gang.Id },
		})
	end
end

function GangTerritoryService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.territories)
	table.clear(self.contests)
	table.clear(self.policeClears)
end

return GangTerritoryService
