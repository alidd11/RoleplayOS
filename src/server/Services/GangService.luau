--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GangRules = require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.GangRules)

-- Gang membership: the first piece of docs/GANG_SYSTEM_SPEC.md, on top of the
-- rules GangRules already validates.
--
-- A gang is shared between everyone in it, so it cannot live on any one
-- member's profile the way an application or a duty profile does -- it lives
-- in DataService's shared records, under "gang:" .. GangId, the same
-- mechanism EconomyService uses for a pending transfer. Each account's
-- profile carries only a GangId pointer to it, plus its own pending invites,
-- which is the one piece of gang state that genuinely belongs to a single
-- profile: nobody else needs to see what has been sent to a player who has
-- not answered it yet.
--
-- Invites require the target to be online. A player who cannot be reached has
-- no live profile to write the invite into, and there is nothing here that
-- needs to reach an offline player: the alternative -- a second shared record
-- acting as a cross-server mailbox -- is real complexity for a feature this
-- spec does not ask for.
local GangService = { running = false, creating = {} }

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function gangKey(gangId: string): string
	return "gang:" .. gangId
end

function GangService:Init(context: any)
	self.context = context
	table.clear(self.creating)
end

function GangService:Start()
	self.running = true
end

function GangService:_sessionIsCurrent(player: Player, session: any): boolean
	return self.running
		and playerIsCurrent(player)
		and self.context.Services:Get("DataService"):GetSession(player) == session
end

function GangService:_gang(gangId: string): (GangRules.Gang?, string?)
	local record, reason =
		self.context.Services:Get("DataService"):GetSharedRecord(gangKey(gangId))
	if reason then
		return nil, reason
	end
	if type(record) ~= "table" then
		return nil, nil
	end
	return record :: GangRules.Gang, nil
end

function GangService:_releaseNameReservation(nameKey: string, gangId: string)
	local dataService = self.context.Services:Get("DataService")
	local _, reason = dataService:UpdateSharedRecord("gang-names", function(index)
		if type(index) == "table" and index[nameKey] == gangId then
			index[nameKey] = nil
		end
		return index
	end)
	if reason then
		self.context.Logger:Error("Gang name reservation cleanup failed", {
			GangId = gangId,
			NameKey = nameKey,
			Reason = reason,
		})
	end
end

-- The gang a profile's pointer actually resolves to, or nil -- clearing the
-- pointer itself if it no longer resolves.
--
-- A gang can stop existing for a member who is not there to see it happen:
-- disbanding only touches the leader's own profile and the shared record, so
-- an offline member's GangId is stale the moment that happens and stays stale
-- until something checks. Every public method below checks first.
function GangService:_reconcile(player: Player, session: any): (GangRules.Gang?, string?)
	if not self:_sessionIsCurrent(player, session) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local gangId = session.Profile.GangId
	if type(gangId) ~= "string" then
		return nil, nil
	end
	local gang, gangReason = self:_gang(gangId)
	-- A failed shared read is uncertainty, not evidence that the gang vanished.
	-- Clearing the profile pointer on a transient DataStore error permanently
	-- removes a valid membership while the shared gang still lists the player.
	if gangReason then
		return nil, gangReason
	end
	if not self:_sessionIsCurrent(player, session) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	if not gang or not GangRules.isMember(gang, player.UserId) then
		session.Profile.GangId = nil
		self.context.Services:Get("DataService"):MarkDirty(player)
		return nil, nil
	end
	return gang, nil
end

function GangService:_ownsPass(session: any): boolean
	local gamepassId = self.context.Configuration.Gamepasses.GangSystemAccess.GamepassId
	return session.Profile.GamepassCache[tostring(gamepassId)] == true
end

-- What a client needs to show its own gang panel: the gang, if any, and every
-- invite waiting on an answer.
function GangService:GetStatus(player: Player): any
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil
	end
	local gang, reconcileReason = self:_reconcile(player, session)
	if reconcileReason or not self:_sessionIsCurrent(player, session) then
		return nil
	end
	local invites = {}
	for _, invite in session.Profile.GangInvites do
		table.insert(invites, invite)
	end
	return { Gang = gang, Invites = invites }
end

function GangService:Create(player: Player, name: any): (GangRules.Gang?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	if self.creating[player] then
		return nil, "GANG_CREATE_IN_PROGRESS"
	end
	self.creating[player] = true

	local ok, result, resultReason = pcall(function(): (GangRules.Gang?, string?)
		local dataService = self.context.Services:Get("DataService")
		local session = dataService:GetSession(player)
		if not session then
			return nil, "PROFILE_UNAVAILABLE"
		end
		local currentGang, reconcileReason = self:_reconcile(player, session)
		if reconcileReason then
			return nil, reconcileReason
		end
		if currentGang then
			return nil, "ALREADY_IN_A_GANG"
		end
		if not self:_sessionIsCurrent(player, session) then
			return nil, "PROFILE_UNAVAILABLE"
		end
		if not self:_ownsPass(session) then
			return nil, "GANG_PASS_REQUIRED"
		end
		local cleanName, nameReason = GangRules.validateName(name)
		if not cleanName then
			return nil, nameReason
		end

		local gangId = HttpService:GenerateGUID(false)
		local nameKey = GangRules.nameKey(cleanName)
		-- The reservation value identifies its owner. UpdateAsync may invoke its
		-- transform more than once, so a sticky external success boolean is not a
		-- reliable result: an early invocation can win and a retry can then discover
		-- that another server actually committed the name.
		local nameIndex, indexReason = dataService:UpdateSharedRecord("gang-names", function(index)
			index = if type(index) == "table" then index else {}
			if index[nameKey] == nil then
				index[nameKey] = gangId
			end
			return index
		end)
		if indexReason then
			return nil, "GANG_CREATE_FAILED"
		end
		if type(nameIndex) ~= "table" or nameIndex[nameKey] ~= gangId then
			return nil, "NAME_TAKEN"
		end

		-- The name reservation yielded. Do not create a gang for an old Player
		-- instance or a profile session that has since been released/replaced.
		if not self:_sessionIsCurrent(player, session) then
			self:_releaseNameReservation(nameKey, gangId)
			return nil, "PROFILE_UNAVAILABLE"
		end

		local gang: GangRules.Gang = {
			Id = gangId,
			Name = cleanName,
			LeaderUserId = player.UserId,
			MemberUserIds = {},
			TerritoryId = nil,
		}

		-- Stage the local pointer before the shared write. If the player leaves
		-- while that write yields, DataService's deferred final save already has
		-- the intended membership in the profile instead of creating an orphaned
		-- shared gang after PlayerRemoving finished.
		session.Profile.GangId = gangId
		dataService:MarkDirty(player)

		local storedGang, gangReason = dataService:UpdateSharedRecord(gangKey(gangId), function(existing)
			if existing == nil then
				return gang
			end
			return existing
		end)
		if gangReason or type(storedGang) ~= "table" or storedGang.Id ~= gangId then
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			self:_releaseNameReservation(nameKey, gangId)
			return nil, "GANG_CREATE_FAILED"
		end

		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Gang.Created",
			Target = gangId,
			Metadata = { Name = cleanName },
		})
		return gang, nil
	end)

	self.creating[player] = nil
	if not ok then
		error(result)
	end
	return result, resultReason
end
function GangService:Invite(leader: Player, targetUserId: any): (boolean, string?)
	if type(targetUserId) ~= "number" then
		return false, "INVALID_TARGET"
	end
	local dataService = self.context.Services:Get("DataService")
	local leaderSession = dataService:GetSession(leader)
	if not leaderSession then
		return false, "PROFILE_UNAVAILABLE"
	end
	local gang, gangReason = self:_reconcile(leader, leaderSession)
	if gangReason then
		return false, gangReason
	end
	if not gang then
		return false, "NOT_IN_A_GANG"
	end
	-- Trusted from the gamepass cache, not from the client, on every invite --
	-- not only at creation -- because a pass can be refunded after the gang
	-- that sold it exists.
	if not self:_ownsPass(leaderSession) then
		return false, "GANG_PASS_REQUIRED"
	end
	local allowed, reason = GangRules.canInvite(gang, leader.UserId, targetUserId)
	if not allowed then
		return false, reason
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "PLAYER_NOT_ONLINE"
	end
	local targetSession = dataService:GetSession(target)
	if not targetSession then
		return false, "PROFILE_UNAVAILABLE"
	end
	local targetGang, targetReason = self:_reconcile(target, targetSession)
	if targetReason then
		return false, targetReason
	end
	if targetGang then
		return false, "ALREADY_IN_A_GANG"
	end
	-- Target reconciliation yields on its shared record. The inviter must still
	-- be the same live profile before their authority is used to mutate the
	-- target's inbox.
	if not self:_sessionIsCurrent(leader, leaderSession) then
		return false, "PROFILE_UNAVAILABLE"
	end
	for _, invite in targetSession.Profile.GangInvites do
		if invite.GangId == gang.Id then
			return false, "ALREADY_INVITED"
		end
	end
	local maximumPending = self.context.Configuration.Gangs.MaximumPendingInvites
	if #targetSession.Profile.GangInvites >= maximumPending then
		return false, "TOO_MANY_PENDING_INVITES"
	end
	table.insert(targetSession.Profile.GangInvites, {
		GangId = gang.Id,
		GangName = gang.Name,
		InvitedByUserId = leader.UserId,
		InvitedAt = os.time(),
	})
	dataService:MarkDirty(target)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = leader.UserId,
		Action = "Gang.Invited",
		Target = tostring(targetUserId),
		Metadata = { GangId = gang.Id },
	})
	return true, nil
end

function GangService:RespondToInvite(player: Player, gangId: any, accept: any): (boolean, string?)
	if type(gangId) ~= "string" or type(accept) ~= "boolean" then
		return false, "INVALID_RESPONSE"
	end
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return false, "PROFILE_UNAVAILABLE"
	end
	local index = nil
	for i, invite in session.Profile.GangInvites do
		if invite.GangId == gangId then
			index = i
			break
		end
	end
	if not index then
		return false, "INVITE_NOT_FOUND"
	end
	table.remove(session.Profile.GangInvites, index)
	dataService:MarkDirty(player)
	if not accept then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Gang.InviteDeclined",
			Target = gangId,
		})
		return true, nil
	end
	local currentGang, reconcileReason = self:_reconcile(player, session)
	if reconcileReason then
		return false, reconcileReason
	end
	if currentGang then
		return false, "ALREADY_IN_A_GANG"
	end
	-- Re-validated inside the transform, not just before it. The invite was
	-- checked against the cap when it was sent, but accepting can happen long
	-- afterwards, and two invitees accepting in the same instant must not both
	-- win a seat the cap only had room for one of.
	local joined = false
	local joinReason: string? = nil
	dataService:UpdateSharedRecord(gangKey(gangId), function(stored)
		if type(stored) ~= "table" then
			joinReason = "GANG_NOT_FOUND"
			return stored
		end
		local allowed, reason = GangRules.canInvite(stored, stored.LeaderUserId, player.UserId)
		if not allowed then
			joinReason = reason
			return stored
		end
		table.insert(stored.MemberUserIds, player.UserId)
		joined = true
		return stored
	end)
	if not joined then
		return false, joinReason or "GANG_JOIN_FAILED"
	end
	session.Profile.GangId = gangId
	dataService:MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Gang.Joined",
		Target = gangId,
	})
	return true, nil
end

function GangService:Leave(player: Player): (boolean, string?)
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return false, "PROFILE_UNAVAILABLE"
	end
	local gang, reconcileReason = self:_reconcile(player, session)
	if reconcileReason then
		return false, reconcileReason
	end
	if not gang then
		return false, "NOT_IN_A_GANG"
	end
	-- The shared record is mutated before the local pointer is cleared, not
	-- after. Clearing it first and disbanding second was the same mistake
	-- CustodyService's early-release path made: if the shared write then
	-- failed, the player would already show as not in a gang while the shared
	-- record still listed them as its leader, and nothing would ever retry it.
	if gang.LeaderUserId == player.UserId then
		-- Leadership transfer is not built. The leader leaving disbands the
		-- gang outright rather than orphaning it with nobody able to invite, no
		-- vehicle spawner to authorise and, once territory exists, nobody to
		-- clear a contest or collect its income.
		local _, disbandReason = dataService:UpdateSharedRecord(gangKey(gang.Id), function()
			return nil
		end)
		-- The transform legitimately returns nil on success -- that is what
		-- disbanding means -- so only the reason string distinguishes a failed
		-- write from a successful one, never the returned value.
		if disbandReason then
			return false, "GANG_LEAVE_FAILED"
		end
		dataService:UpdateSharedRecord("gang-names", function(index)
			if type(index) == "table" then
				index[GangRules.nameKey(gang.Name)] = nil
			end
			return index
		end)
		-- A disbanded gang that held a territory would otherwise leave it
		-- pointing at an id nothing can ever match again -- not a security
		-- hole, since no profile keeps that id once the disband above runs,
		-- but a spawner and a future contest both left addressing a dead gang
		-- rather than the unowned ground this should actually be.
		if type(gang.TerritoryId) == "string" and gang.TerritoryId ~= "" then
			self.context.Services:Get("GangTerritoryService"):SetOwner(gang.TerritoryId, nil)
		end
		session.Profile.GangId = nil
		dataService:MarkDirty(player)
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Gang.Disbanded",
			Target = gang.Id,
			Metadata = { Name = gang.Name },
		})
		return true, nil
	end
	local _, leaveReason = dataService:UpdateSharedRecord(gangKey(gang.Id), function(stored)
		if type(stored) ~= "table" then
			return stored
		end
		local memberIndex = table.find(stored.MemberUserIds, player.UserId)
		if memberIndex then
			table.remove(stored.MemberUserIds, memberIndex)
		end
		return stored
	end)
	if leaveReason then
		return false, "GANG_LEAVE_FAILED"
	end
	session.Profile.GangId = nil
	dataService:MarkDirty(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Gang.Left",
		Target = gang.Id,
	})
	return true, nil
end

function GangService:Destroy()
	self.running = false
	table.clear(self.creating)
end

return GangService
