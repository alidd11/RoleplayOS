--!strict

-- Shoulder numbers for the emergency services.
--
-- Every officer, clinician and firefighter carries one number per service for
-- as long as the game exists. It is issued once, on first going on duty in that
-- service, and never reissued to anyone else, because members put these numbers
-- in their Discord display names and a number that moved between people would
-- make every one of those names wrong.
--
-- The number is held per department rather than per person. Someone who serves
-- in both Police and Fire holds a number in each, which is how the real services
-- work and costs no more than a single number would: allocation happens once per
-- person per service, ever, so the store sees a handful of writes a day at most.
--
-- Numbers are kept through promotion even past the ranks that display them, so
-- an inspector demoted back to sergeant wears the number they always had.

local ShoulderNumberService = {}

function ShoulderNumberService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.ShoulderNumbers
end

-- The departments this player may read a roster for.
--
-- The management line is not configured separately: it is the rank at which a
-- service stops wearing shoulder numbers, which is what that boundary means in
-- the real services and is already declared on the ladder. Anyone at or above it
-- sees their own service's roster, and nobody sees another service's.
function ShoulderNumberService:_readableDepartments(player: Player): { [string]: boolean }
	local allowed = {}
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local profiles = session and session.Profile and session.Profile.DutyProfiles
	if type(profiles) ~= "table" then
		return allowed
	end
	for _, profile in profiles do
		local departmentId = profile.DepartmentId
		if
			type(departmentId) == "string"
			and not self:IsNumberedRank(departmentId, tonumber(profile.Rank) or 1)
		then
			allowed[departmentId] = true
		end
	end
	return allowed
end

function ShoulderNumberService:Start() end

-- The roster a given player may see: their own services only, and only where
-- they hold a management rank. Read-only. Nothing here assigns, reassigns or
-- frees a number, because a number moving between people is the one thing the
-- whole design exists to prevent.
function ShoulderNumberService:RosterFor(player: Player): (any?, string?)
	local allowed = self:_readableDepartments(player)
	if not next(allowed) then
		return nil, "ROSTER_NOT_AUTHORISED"
	end
	local rows = {}
	for _, row in self:Roster() do
		if allowed[row.DepartmentId] then
			table.insert(rows, row)
		end
	end
	return { Rows = rows, Departments = allowed, GeneratedAt = os.time() }, nil
end

function ShoulderNumberService:_department(departmentId: string): any?
	return self.context.Configuration.Departments[departmentId]
end

-- The rank entry a profile's stored index points at, or nil when the index has
-- fallen outside the ladder because ranks were removed from the configuration.
function ShoulderNumberService:GetRank(departmentId: string, rank: number): any?
	local department = self:_department(departmentId)
	local ranks = department and department.Ranks
	if type(ranks) ~= "table" then
		return nil
	end
	return ranks[math.clamp(math.floor(rank), 1, #ranks)]
end

function ShoulderNumberService:IsNumberedRank(departmentId: string, rank: number): boolean
	local entry = self:GetRank(departmentId, rank)
	return entry ~= nil and entry.Numbered == true
end

function ShoulderNumberService:Format(number: number): string
	return string.format(self.settings.Format or "%04d", number)
end

-- The number this profile holds, issuing one if it has none and the service is
-- enabled. Returns nil when the store is unavailable, and the caller must treat
-- that as "no number to show" rather than as a reason to refuse duty: being
-- unable to reach a DataStore is not a reason to stop someone working a shift.
function ShoulderNumberService:Resolve(player: Player, profile: any): number?
	if not self.settings.Enabled or type(profile) ~= "table" then
		return nil
	end
	local existing = tonumber(profile.ShoulderNumber)
	if existing then
		return existing
	end
	local departmentId = profile.DepartmentId
	if type(departmentId) ~= "string" then
		return nil
	end
	local start = (self.settings.Start and self.settings.Start[departmentId])
		or self.settings.DefaultStart
		or 100
	local issued, problem = self.context.Services
		:Get("DataService")
		:AllocateShoulderNumber(departmentId, player.UserId, start)
	if not issued then
		self.context.Logger:Warning("Shoulder number allocation failed", {
			UserId = player.UserId,
			DepartmentId = departmentId,
			Error = problem,
		})
		return nil
	end
	profile.ShoulderNumber = issued
	profile.ShoulderNumberAssignedAt = os.time()
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "ShoulderNumber.Issued",
		Target = departmentId .. ":" .. tostring(issued),
		Metadata = { DepartmentId = departmentId, Number = issued },
	})
	return issued
end

-- How the officer is addressed on air and shown on the unit list: the rank's
-- abbreviation, followed by the number where the rank carries one. A rank above
-- the numbered ranks is named alone, since insignia replaces the number there.
function ShoulderNumberService:Callsign(player: Player, profile: any): string?
	local departmentId = profile and profile.DepartmentId
	if type(departmentId) ~= "string" then
		return nil
	end
	local rank = tonumber(profile.Rank) or 1
	local entry = self:GetRank(departmentId, rank)
	local abbreviation = if entry and type(entry.Abbreviation) == "string"
		then entry.Abbreviation
		else string.upper(string.sub(departmentId, 1, 3))
	-- Resolved even when the rank does not display it, so the number is issued
	-- on first duty and waiting if the officer is ever demoted into a rank that
	-- shows one.
	local number = self:Resolve(player, profile)
	if not number or not self:IsNumberedRank(departmentId, rank) then
		return abbreviation
	end
	return abbreviation .. " " .. self:Format(number)
end

-- The roster staff reconcile Discord display names against. Read-only, built
-- from the profiles of players currently in this server, since the framework
-- holds no index of every profile that has ever existed.
function ShoulderNumberService:Roster(): { any }
	local rows = {}
	local data = self.context.Services:Get("DataService")
	for _, player in game:GetService("Players"):GetPlayers() do
		local session = data:GetSession(player)
		local profiles = session and session.Profile and session.Profile.DutyProfiles
		if type(profiles) == "table" then
			for _, profile in profiles do
				local number = tonumber(profile.ShoulderNumber)
				if number then
					table.insert(rows, {
						UserId = player.UserId,
						Username = player.Name,
						DisplayName = player.DisplayName,
						DepartmentId = profile.DepartmentId,
						Rank = tonumber(profile.Rank) or 1,
						RankName = (
							self:GetRank(profile.DepartmentId, tonumber(profile.Rank) or 1) or {}
						).Name,
						Number = number,
						Formatted = self:Format(number),
						Callsign = self:Callsign(player, profile),
						AssignedAt = profile.ShoulderNumberAssignedAt,
					})
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.DepartmentId == b.DepartmentId then
			return a.Number < b.Number
		end
		return tostring(a.DepartmentId) < tostring(b.DepartmentId)
	end)
	return rows
end

-- Who holds a given number, for staff checking a Discord name against the game.
function ShoulderNumberService:Lookup(departmentId: string, number: number): (any?, string?)
	return self.context.Services:Get("DataService"):GetShoulderNumberHolder(departmentId, number)
end

function ShoulderNumberService:Destroy() end

return ShoulderNumberService
