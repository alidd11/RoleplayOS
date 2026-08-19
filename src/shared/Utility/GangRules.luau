--!strict

-- The rules a gang is bound by: what it may be called, who may be in it, and how
-- a territory changes hands.
--
-- First piece of the gang system described in docs/GANG_SYSTEM_SPEC.md. It is
-- pure -- no instances, no services, no state -- so it can be exercised directly
-- and is the same shape the acceptance suite already tests the other validators
-- in. Nothing calls it yet; the service that will is not written.
--
-- The point of it existing first is that every one of these decisions is a rule
-- somebody will try to break. A gang name reaches other players' screens, a
-- member list is written to a profile, and a territory pays money -- so each of
-- those needs a single place that says what is allowed, rather than the check
-- being reimplemented at each call site and disagreeing with itself.

local GangRules = {}

-- Names are filtered by Roblox before they are shown, but the shape is checked
-- here first so an obviously bad one never reaches the filter or the datastore.
-- Deliberately the same rule the character validator applies to a person's name,
-- with digits allowed: gangs are named things like "Bridge 42" and people are
-- not.
GangRules.MinimumNameLength = 3
GangRules.MaximumNameLength = 24

-- A cap exists so a gang cannot hold every territory by weight of numbers alone,
-- which is the griefing surface the spec flags as the main risk in making
-- territory contested.
GangRules.MaximumMembers = 12

-- Contesting, in seconds of continuous presence.
--
-- Long enough that a claim cannot be flipped by running through, short enough
-- that a genuine push is worth making. A police officer standing in the zone
-- halts the contest; holding it for the clear duration resets the territory to
-- unowned, which is the settling move the spec asks for so a large gang cannot
-- simply sit on everything.
GangRules.ContestSeconds = 90
GangRules.PoliceClearSeconds = 45

-- How long after a territory changes hands before it can change again. Without
-- this, two gangs of similar size trade a zone indefinitely and the income and
-- the dispatch calls both become noise.
GangRules.ClaimCooldownSeconds = 300

local function trimmed(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.match(value, "^%s*(.-)%s*$")
	return if text == "" then nil else text
end

-- Is this an acceptable gang name?
--
-- Returns the cleaned name on success so the caller stores exactly what was
-- validated, rather than validating one string and writing another.
function GangRules.validateName(value: any): (string?, string?)
	local text = trimmed(value)
	if not text then
		return nil, "NAME_REQUIRED"
	end
	if #text < GangRules.MinimumNameLength or #text > GangRules.MaximumNameLength then
		return nil, "NAME_LENGTH"
	end
	-- Letters, digits, spaces, apostrophes and hyphens, starting and ending on a
	-- letter or digit. Keeps out the punctuation people use to draw shapes in a
	-- name, and the leading spaces used to sort to the top of a list.
	if not string.match(text, "^[%w][%w'%- ]*[%w]$") then
		return nil, "NAME_CHARACTERS"
	end
	-- No runs of whitespace, which read as a single space and let two visibly
	-- identical gangs exist.
	if string.match(text, "%s%s") then
		return nil, "NAME_CHARACTERS"
	end
	return text, nil
end

-- Two names collide if they differ only by case or spacing. Compared on a folded
-- form rather than the raw string, so "Bridge 42" and "bridge42" cannot both
-- exist and be told apart on a screen.
function GangRules.nameKey(value: string): string
	return string.lower((string.gsub(value, "%s+", "")))
end

export type Gang = {
	Id: string,
	Name: string,
	LeaderUserId: number,
	MemberUserIds: { number },
	TerritoryId: string?,
}

function GangRules.isMember(gang: Gang, userId: number): boolean
	if gang.LeaderUserId == userId then
		return true
	end
	return table.find(gang.MemberUserIds, userId) ~= nil
end

-- May this player be invited?
--
-- The leader's entitlement is not checked here, deliberately. Whether somebody
-- owns the pass is a server question answered from the gamepass cache, and a
-- pure module that claimed to answer it would invite a caller to trust a client's
-- word for it.
function GangRules.canInvite(
	gang: Gang,
	inviterUserId: number,
	targetUserId: number
): (boolean, string?)
	if gang.LeaderUserId ~= inviterUserId then
		return false, "NOT_THE_LEADER"
	end
	if targetUserId == inviterUserId then
		return false, "ALREADY_A_MEMBER"
	end
	if GangRules.isMember(gang, targetUserId) then
		return false, "ALREADY_A_MEMBER"
	end
	-- The leader counts toward the cap, because they occupy a place in the gang
	-- the same as anybody else.
	if #gang.MemberUserIds + 1 >= GangRules.MaximumMembers then
		return false, "GANG_FULL"
	end
	return true, nil
end

-- Who currently controls a contested zone, given who is standing in it.
--
-- Presence only, and a strict majority: an equal showing changes nothing, so a
-- zone cannot flip on the arrival of one person. Police presence is not a
-- contender for control -- an officer suppresses the contest rather than winning
-- it, which is what keeps the clear a separate act from a claim.
function GangRules.contestOutcome(
	holderGangId: string?,
	presentByGang: { [string]: number },
	policePresent: number
): (string?, string?)
	if policePresent > 0 then
		return holderGangId, "SUPPRESSED_BY_POLICE"
	end
	local leaderId: string? = nil
	local leaderCount = 0
	local tied = false
	for gangId, count in presentByGang do
		if count > leaderCount then
			leaderId, leaderCount, tied = gangId, count, false
		elseif count == leaderCount and count > 0 then
			tied = true
		end
	end
	if leaderCount == 0 or tied then
		return holderGangId, "NO_CHANGE"
	end
	if leaderId == holderGangId then
		return holderGangId, "HELD"
	end
	return leaderId, "CONTESTED"
end

return GangRules
