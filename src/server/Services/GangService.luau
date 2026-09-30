--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GangRules = require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.GangRules)
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

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
local GangService = {
	running = false,
	creating = {},
	membershipWrites = {},
	pendingMemberships = {},
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local NAME_CLEANUP_RECORD = "gang-name-cleanups"

local function gangKey(gangId: string): string
	return "gang:" .. gangId
end

function GangService:Init(context: any)
	self.context = context
	table.clear(self.creating)
	table.clear(self.membershipWrites)
	table.clear(self.pendingMemberships)
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
	local record, reason = self.context.Services:Get("DataService"):GetSharedRecord(gangKey(gangId))
	if reason then
		return nil, reason
	end
	if type(record) ~= "table" then
		return nil, nil
	end
	return record :: GangRules.Gang, nil
end

function GangService:_releaseNameReservation(nameKey: string, gangId: string): (boolean, string?)
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
		return false, reason
	end
	return true, nil
end

function GangService:_queueNameCleanup(nameKey: string, gangId: string): (boolean, string?)
	local dataService = self.context.Services:Get("DataService")
	local maximum = math.max(
		1,
		math.floor(tonumber(self.context.Configuration.Gangs.MaximumPendingNameCleanups) or 64)
	)
	local queuedAt = os.time()
	local pending, reason = dataService:UpdateSharedRecord(NAME_CLEANUP_RECORD, function(existing)
		existing = if type(existing) == "table" then existing else {}
		local current = existing[nameKey]
		if type(current) == "table" and current.GangId == gangId then
			return existing
		end
		if current ~= nil then
			return existing
		end
		local count = 0
		for _ in existing do
			count += 1
		end
		if count >= maximum then
			return existing
		end
		existing[nameKey] = {
			GangId = gangId,
			QueuedAt = queuedAt,
		}
		return existing
	end)
	if reason then
		return false, reason
	end
	local marker = type(pending) == "table" and pending[nameKey]
	if type(marker) ~= "table" or marker.GangId ~= gangId then
		self.context.Logger:Error("Gang name cleanup backlog is full or conflicting", {
			GangId = gangId,
			NameKey = nameKey,
			MaximumPendingNameCleanups = maximum,
		})
		return false, "GANG_NAME_CLEANUP_BACKLOG_FULL"
	end
	return true, nil
end

function GangService:_clearNameCleanup(nameKey: string, gangId: string): boolean
	local _, reason = self.context.Services
		:Get("DataService")
		:UpdateSharedRecord(NAME_CLEANUP_RECORD, function(existing)
			if
				type(existing) == "table"
				and type(existing[nameKey]) == "table"
				and existing[nameKey].GangId == gangId
			then
				existing[nameKey] = nil
			end
			return existing
		end)
	if reason then
		self.context.Logger:Warning("Gang name cleanup marker could not be cleared", {
			GangId = gangId,
			NameKey = nameKey,
			Reason = reason,
		})
		return false
	end
	return true
end

function GangService:_repairNameCleanup(nameKey: string): (boolean, string?)
	local dataService = self.context.Services:Get("DataService")
	local pending, pendingReason = dataService:GetSharedRecord(NAME_CLEANUP_RECORD)
	if pendingReason then
		return false, pendingReason
	end
	local marker = type(pending) == "table" and pending[nameKey]
	if marker == nil then
		return true, nil
	end
	if type(marker) ~= "table" or type(marker.GangId) ~= "string" or marker.GangId == "" then
		self.context.Logger:Error("Gang name cleanup marker is invalid", { NameKey = nameKey })
		return false, "GANG_NAME_CLEANUP_INVALID"
	end
	local gangId = marker.GangId
	local gang, gangReason = self:_gang(gangId)
	if gangReason then
		return false, gangReason
	end
	if gang then
		-- The delete did not commit. The gang is still authoritative, so the name
		-- reservation must stay and only the cancelled recovery marker is removed.
		self:_clearNameCleanup(nameKey, gangId)
		return true, nil
	end
	local released, releaseReason = self:_releaseNameReservation(nameKey, gangId)
	if not released then
		return false, releaseReason
	end
	if not self:_clearNameCleanup(nameKey, gangId) then
		-- Do not allow a new gang to adopt the name while the old recovery marker
		-- is still durable. The marker is exact-owner guarded, but retaining one
		-- recovery identity per name keeps the backlog bounded and unambiguous.
		return false, "GANG_NAME_CLEANUP_PENDING"
	end
	return true, nil
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
	if self.pendingMemberships[player.UserId] == gangId then
		return nil, "GANG_MEMBERSHIP_UPDATE_IN_PROGRESS"
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
	local removedInvite = false
	for index = #session.Profile.GangInvites, 1, -1 do
		if session.Profile.GangInvites[index].GangId == gangId then
			table.remove(session.Profile.GangInvites, index)
			removedInvite = true
		end
	end
	if removedInvite then
		self.context.Services:Get("DataService"):MarkDirty(player)
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
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return nil
	end
	local gang, reconcileReason = self:_reconcile(player, session)
	if reconcileReason or not self:_sessionIsCurrent(player, session) then
		return nil
	end

	-- Gang names created before moderation was enforced cannot be safely shown:
	-- the original author may be offline, and Roblox filtering must be attributed
	-- to the author. Quarantine those legacy values from client responses rather
	-- than guessing at a filtering identity.
	local clientGang = gang
	if gang and gang.NameModerated ~= true then
		clientGang = table.clone(gang)
		clientGang.Name = "Gang"
	end

	local invites = {}
	local invitesSanitised = false
	for _, invite in session.Profile.GangInvites do
		-- Old invite rows copied the unmoderated gang name into the invitee's
		-- profile. Replace it with server-authored text so the unsafe value does
		-- not remain client-visible or keep being persisted on later saves.
		if invite.GangNameModerated ~= true then
			invite.GangName = "Gang invitation"
			invite.GangNameModerated = true
			invitesSanitised = true
		end
		table.insert(invites, table.clone(invite))
	end
	if invitesSanitised then
		dataService:MarkDirty(player)
	end
	return { Gang = clientGang, Invites = invites }
end

function GangService:Create(player: Player, name: any): (GangRules.Gang?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "PROFILE_UNAVAILABLE"
	end
	if self.creating[player] then
		return nil, "GANG_CREATE_IN_PROGRESS"
	end
	if self.membershipWrites[player.UserId] then
		return nil, "GANG_MEMBERSHIP_UPDATE_IN_PROGRESS"
	end
	self.creating[player] = true
	self.membershipWrites[player.UserId] = player
	local pendingGangId: string? = nil

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
		local filteredName, filterReason =
			TextFilter.forBroadcast(cleanName, player.UserId, Enum.TextFilterContext.PublicChat)
		if not filteredName then
			return nil, filterReason or "TEXT_FILTER_UNAVAILABLE"
		end
		-- Gang names are identifiers, not chat messages. A censored or rewritten
		-- name is refused rather than persisted under a value different from the
		-- unique-name reservation the player asked for.
		if filteredName ~= cleanName or string.find(filteredName, "#", 1, true) then
			return nil, "NAME_NOT_PERMITTED"
		end
		-- Filtering yields. Revalidate the exact profile session and entitlement
		-- before reserving a shared name or mutating membership state.
		if not self:_sessionIsCurrent(player, session) then
			return nil, "PROFILE_UNAVAILABLE"
		end
		if not self:_ownsPass(session) then
			return nil, "GANG_PASS_REQUIRED"
		end

		local gangId = HttpService:GenerateGUID(false)
		local nameKey = GangRules.nameKey(cleanName)
		local repaired, repairReason = self:_repairNameCleanup(nameKey)
		if not repaired then
			self.context.Logger:Warning("Gang name recovery could not complete", {
				NameKey = nameKey,
				Reason = repairReason,
			})
			return nil, "GANG_CREATE_FAILED"
		end
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
			NameModerated = true,
			LeaderUserId = player.UserId,
			MemberUserIds = {},
			TerritoryId = nil,
		}

		-- Stage the local pointer before the shared write. The pending marker stops
		-- another request from reconciling that provisional pointer away while the
		-- shared write is in flight.
		pendingGangId = gangId
		self.pendingMemberships[player.UserId] = gangId
		session.Profile.GangId = gangId
		dataService:MarkDirty(player)

		local storedGang, gangReason = dataService:UpdateSharedRecord(
			gangKey(gangId),
			function(existing)
				if existing == nil then
					return gang
				end
				return existing
			end
		)
		if gangReason or type(storedGang) ~= "table" or storedGang.Id ~= gangId then
			if self.pendingMemberships[player.UserId] == gangId then
				self.pendingMemberships[player.UserId] = nil
			end
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			self:_releaseNameReservation(nameKey, gangId)
			return nil, "GANG_CREATE_FAILED"
		end
		if self.pendingMemberships[player.UserId] == gangId then
			self.pendingMemberships[player.UserId] = nil
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
	if pendingGangId and self.pendingMemberships[player.UserId] == pendingGangId then
		self.pendingMemberships[player.UserId] = nil
	end
	if self.membershipWrites[player.UserId] == player then
		self.membershipWrites[player.UserId] = nil
	end
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
	-- Target reconciliation yields on its shared record. Both sides of the
	-- invitation must still be the exact live profile sessions before the target
	-- inbox is mutated: PlayerRemoving may have completed the target's release
	-- while this worker was waiting on shared storage.
	if
		not self:_sessionIsCurrent(leader, leaderSession)
		or not self:_sessionIsCurrent(target, targetSession)
	then
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
	local inviteName = if gang.NameModerated == true then gang.Name else "Gang invitation"
	table.insert(targetSession.Profile.GangInvites, {
		GangId = gang.Id,
		GangName = inviteName,
		GangNameModerated = true,
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
	if not self.running or not playerIsCurrent(player) then
		return false, "PROFILE_UNAVAILABLE"
	end
	if self.membershipWrites[player.UserId] then
		return false, "GANG_MEMBERSHIP_UPDATE_IN_PROGRESS"
	end
	self.membershipWrites[player.UserId] = player
	local pendingGangId: string? = nil

	local ok, result, resultReason = pcall(function(): (boolean, string?)
		local dataService = self.context.Services:Get("DataService")
		local session = dataService:GetSession(player)
		if not session then
			return false, "PROFILE_UNAVAILABLE"
		end

		local function inviteIndex(): number?
			for index, invite in session.Profile.GangInvites do
				if invite.GangId == gangId then
					return index
				end
			end
			return nil
		end

		local index = inviteIndex()
		if not index then
			return false, "INVITE_NOT_FOUND"
		end

		if not accept then
			table.remove(session.Profile.GangInvites, index)
			dataService:MarkDirty(player)
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
		if not self:_sessionIsCurrent(player, session) then
			return false, "PROFILE_UNAVAILABLE"
		end

		-- Persist the intended pointer before adding this user to the shared gang.
		-- If the server dies after the shared write, the next server therefore has
		-- enough durable state to find the membership instead of leaving a member
		-- in the shared roster with no profile pointer back to it.
		pendingGangId = gangId
		self.pendingMemberships[player.UserId] = gangId
		session.Profile.GangId = gangId
		dataService:MarkDirty(player)
		local saved, saveReason = dataService:Save(player)
		if not saved then
			if self.pendingMemberships[player.UserId] == gangId then
				self.pendingMemberships[player.UserId] = nil
			end
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			self.context.Logger:Warning("Gang join intent could not be saved", {
				UserId = player.UserId,
				GangId = gangId,
				Reason = saveReason,
			})
			return false, "GANG_JOIN_FAILED"
		end
		if not self:_sessionIsCurrent(player, session) then
			if self.pendingMemberships[player.UserId] == gangId then
				self.pendingMemberships[player.UserId] = nil
			end
			return false, "PROFILE_UNAVAILABLE"
		end

		-- The transform is idempotent and carries no external success flag:
		-- UpdateAsync may invoke it more than once. A retry that observes this user
		-- already present simply returns the committed record.
		local storedGang, updateReason = dataService:UpdateSharedRecord(
			gangKey(gangId),
			function(stored)
				if type(stored) ~= "table" then
					return stored
				end
				if GangRules.isMember(stored, player.UserId) then
					return stored
				end
				local allowed = GangRules.canInvite(stored, stored.LeaderUserId, player.UserId)
				if not allowed then
					return stored
				end
				table.insert(stored.MemberUserIds, player.UserId)
				return stored
			end
		)
		if self.pendingMemberships[player.UserId] == gangId then
			self.pendingMemberships[player.UserId] = nil
		end

		if updateReason then
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			return false, "GANG_JOIN_FAILED"
		end
		if type(storedGang) ~= "table" then
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			local staleIndex = inviteIndex()
			if staleIndex and self:_sessionIsCurrent(player, session) then
				table.remove(session.Profile.GangInvites, staleIndex)
				dataService:MarkDirty(player)
			end
			return false, "GANG_NOT_FOUND"
		end
		if not GangRules.isMember(storedGang, player.UserId) then
			if session.Profile.GangId == gangId then
				session.Profile.GangId = nil
				if self:_sessionIsCurrent(player, session) then
					dataService:MarkDirty(player)
				end
			end
			local allowed, reason =
				GangRules.canInvite(storedGang, storedGang.LeaderUserId, player.UserId)
			return false, if allowed then "GANG_JOIN_FAILED" else reason
		end

		-- The pointer was saved before the shared membership. If the Player left
		-- during that shared write, consistency is already durable; the stale invite
		-- is harmless and _reconcile removes it on the next live session.
		if self:_sessionIsCurrent(player, session) then
			local acceptedIndex = inviteIndex()
			if acceptedIndex then
				table.remove(session.Profile.GangInvites, acceptedIndex)
			end
			dataService:MarkDirty(player)
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Gang.Joined",
			Target = gangId,
		})
		return true, nil
	end)

	if pendingGangId and self.pendingMemberships[player.UserId] == pendingGangId then
		self.pendingMemberships[player.UserId] = nil
	end
	if self.membershipWrites[player.UserId] == player then
		self.membershipWrites[player.UserId] = nil
	end
	if not ok then
		error(result)
	end
	return result, resultReason
end

function GangService:Leave(player: Player): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "PROFILE_UNAVAILABLE"
	end
	if self.membershipWrites[player.UserId] then
		return false, "GANG_MEMBERSHIP_UPDATE_IN_PROGRESS"
	end
	self.membershipWrites[player.UserId] = player

	local ok, result, resultReason = pcall(function(): (boolean, string?)
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
			local nameKey = GangRules.nameKey(gang.Name)
			local cleanupQueued, cleanupReason = self:_queueNameCleanup(nameKey, gang.Id)
			if not cleanupQueued then
				self.context.Logger:Warning("Gang disband refused without durable name recovery", {
					GangId = gang.Id,
					NameKey = nameKey,
					Reason = cleanupReason,
				})
				return false, "GANG_LEAVE_FAILED"
			end
			local _, disbandReason = dataService:UpdateSharedRecord(gangKey(gang.Id), function()
				return nil
			end)
			-- The transform legitimately returns nil on success -- that is what
			-- disbanding means -- so only the reason string distinguishes a failed
			-- write from a successful one, never the returned value. Keep the
			-- recovery marker even on failure: an ambiguous DataStore response may
			-- mean the deletion actually committed, and the repair path checks the
			-- gang record before it ever releases the name.
			if disbandReason then
				return false, "GANG_LEAVE_FAILED"
			end
			local nameReleased = self:_releaseNameReservation(nameKey, gang.Id)
			if nameReleased then
				self:_clearNameCleanup(nameKey, gang.Id)
			end
			-- A disbanded gang that held a territory would otherwise leave it
			-- pointing at an id nothing can ever match again -- not a security
			-- hole, since no profile keeps that id once the disband above runs,
			-- but a spawner and a future contest both left addressing a dead gang
			-- rather than the unowned ground this should actually be.
			if type(gang.TerritoryId) == "string" and gang.TerritoryId ~= "" then
				self.context.Services:Get("GangTerritoryService"):SetOwner(gang.TerritoryId, nil)
			end
			if self:_sessionIsCurrent(player, session) and session.Profile.GangId == gang.Id then
				session.Profile.GangId = nil
				dataService:MarkDirty(player)
			end
			self.context.Services:Get("AuditService"):Record({
				ActorUserId = player.UserId,
				Action = "Gang.Disbanded",
				Target = gang.Id,
				Metadata = {
					Name = if gang.NameModerated == true then gang.Name else "Legacy gang",
				},
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
		if self:_sessionIsCurrent(player, session) and session.Profile.GangId == gang.Id then
			session.Profile.GangId = nil
			dataService:MarkDirty(player)
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Gang.Left",
			Target = gang.Id,
		})
		return true, nil
	end)

	if self.membershipWrites[player.UserId] == player then
		self.membershipWrites[player.UserId] = nil
	end
	if not ok then
		error(result)
	end
	return result, resultReason
end

function GangService:Destroy()
	self.running = false
	table.clear(self.creating)
	table.clear(self.membershipWrites)
	table.clear(self.pendingMemberships)
end

return GangService
