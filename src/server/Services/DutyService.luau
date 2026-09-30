--!strict

local Players = game:GetService("Players")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)

local function normaliseCallsign(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end
	local callsign = string.upper(string.sub(string.gsub(raw, "[^%w%- ]", ""), 1, 16))
	callsign = string.gsub(callsign, "^%s+", "")
	callsign = string.gsub(callsign, "%s+$", "")
	return if #callsign >= 2 then callsign else nil
end

local function filterCallsign(player: Player, raw: any): (string?, string?)
	local callsign = normaliseCallsign(raw)
	if not callsign then
		return nil, "INVALID_CALLSIGN"
	end
	local filtered, reason =
		TextFilter.forBroadcast(callsign, player.UserId, Enum.TextFilterContext.PublicChat)
	if not filtered or #filtered < 2 or #filtered > 16 then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	return filtered, nil
end

-- Whether a player is still in the game.
--
-- Parent is the reliable test: a Player instance that has left is removed from
-- the Players service but the reference held by an in-flight request stays
-- perfectly valid, so checking the reference alone proves nothing.
local function playerIsPresent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local DutyService = { active = {}, beginning = {}, running = false }

function DutyService:Init(context: any)
	self.context = context
	table.clear(self.beginning)
end

function DutyService:_publishUnitChanged(userId: number, departmentId: string?)
	-- Dispatch recipient checks can yield on duty/group access. Keep those reads
	-- out of duty mutation latency, but never publish into a service that has
	-- already stopped during teardown. Pass the authoritative department even
	-- after unit removal so the refresh hint cannot leak the unit id cross-service.
	task.defer(function()
		local dispatch = self.context.Services:Get("DispatchService")
		if dispatch.running then
			dispatch:PublishUnitChanged(tostring(userId), departmentId, 0)
		end
	end)
end

function DutyService:Start()
	self.running = true
	self.connections = self.connections or {}
	-- Per-player handlers are held against the player rather than pushed onto the
	-- service-wide list, which is only emptied when the server shuts down. Every
	-- join added an entry there that nothing ever removed, so a busy server spent
	-- an evening accumulating one dead closure per join and walked the lot at
	-- shutdown. Disconnecting on the way out also means a player who rejoins the
	-- same server cannot end up with two handlers running for one spawn.
	self.playerConnections = {}
	local function forget(player: Player)
		local connection = self.playerConnections[player.UserId]
		if connection then
			connection:Disconnect()
			self.playerConnections[player.UserId] = nil
		end
	end
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			forget(player)
			self:End(player)
		end)
	)
	local function watch(player: Player)
		forget(player)
		self.playerConnections[player.UserId] = player.CharacterAdded:Connect(function()
			task.delay(1, function()
				if not self.running or not playerIsPresent(player) then
					return
				end
				-- Gamepass weapons used to be dropped into the backpack here on
				-- every spawn, silently, for whoever owned the pass. Everyone else
				-- has to walk up to a dealer and press a button; owning a pass
				-- should shorten that to "for nothing" at the same stall, not skip
				-- it. VendorService's own gamepass branch already does exactly
				-- that free-collection check when the player interacts with the
				-- dealer, so this is the one path to any of these tools now.
				local duty = self:Get(player)
				if not duty then
					return
				end
				local role = self.context.Configuration.Roles[duty.RoleId]
				if role and role.LoadoutId then
					self.context.Services:Get("LoadoutService"):Apply(player, role.LoadoutId)
				end
				if role and role.AutoEquipUniform == true and role.UniformId then
					local applied, reason =
						self.context.Services:Get("UniformService"):Apply(player, role.UniformId)
					if not applied then
						self.context.Logger:Warning("Automatic duty uniform could not be applied", {
							UserId = player.UserId,
							RoleId = duty.RoleId,
							UniformId = role.UniformId,
							Reason = reason,
						})
					end
				end
				if duty.DepartmentId == "Police" then
					local session = self.context.Services:Get("DataService"):GetSession(player)
					local profile = session and session.Profile.DutyProfiles[duty.DutyProfileId]
					self.context.Services
						:Get("ImportedSystemAdapterService")
						:ApplyEpaulettes(player, profile)
				end
				self.context.Services:Get("IdentificationService"):Refresh(player)
			end)
		end)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function DutyService:Get(player: Player): any?
	if not self.running or not playerIsPresent(player) then
		return nil
	end
	local duty = self.active[player.UserId]
	if not duty then
		return nil
	end
	local role = self.context.Configuration.Roles[duty.RoleId]
	local expectedTeam = role and self.context.Services:Get("TeamService"):Get(role.TeamName)
	if
		not role
		or role.DepartmentId ~= duty.DepartmentId
		or role.TeamName ~= duty.TeamName
		or role.DivisionId ~= duty.DivisionId
		or not expectedTeam
		or player.Team ~= expectedTeam
	then
		self:End(player)
		return nil
	end
	local access = self.context.Services:Get("AccessService"):Evaluate(player, role.Access)
	-- Access evaluation may yield on a Roblox group lookup. Revalidate the exact
	-- live duty record afterwards so an ended shift cannot be returned stale.
	if not self.running or not playerIsPresent(player) or self.active[player.UserId] ~= duty then
		return nil
	end
	if not access.Allowed then
		-- A check that could not be made is not a refusal.
		--
		-- Roblox answers a burst of group lookups with a 429, and GroupService
		-- caches that failure through a backoff of up to two minutes. Every one
		-- of those reads as GROUP_CHECK_FAILED, which is indistinguishable here
		-- from "this person is not in the group" unless the reason is checked.
		--
		-- Ending a shift on it is not a small mistake. This is not a getter: it
		-- unregisters the unit from every dispatcher's board, destroys the
		-- radio, notebook and handcuffs, and leaves an officer on the police team
		-- in uniform with no duty and no equipment, while the audit line says the
		-- shift ended normally. Runtime authorisation checks this for anyone
		-- driving, and ending duty there throws them out of a moving car.
		--
		-- It also lands hardest where it matters least deservedly: on the public
		-- place a gamepass satisfies the rule and the group branch is irrelevant,
		-- so this only ever fires on the whitelisted and private servers, where
		-- group rank is the whole basis of access.
		--
		-- The shift is kept and the next evaluation decides. A player genuinely
		-- removed from the group is still ended the moment a check succeeds, so
		-- this tolerates not knowing rather than tolerating not being allowed.
		if access.ReasonCode == "GROUP_CHECK_FAILED" then
			return duty
		end
		self:End(player)
		return nil
	end
	return duty
end

function DutyService:_begin(player: Player, request: any): (boolean, string?)
	if not self.running or not playerIsPresent(player) then
		return false, "DUTY_UNAVAILABLE"
	end
	if self.active[player.UserId] then
		return false, "ALREADY_ON_DUTY"
	end
	if self.context.Services:Get("CustodyService"):HasActiveSentence(player) then
		return false, "ACTIVE_CUSTODY_SENTENCE"
	end
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return false, "PROFILE_UNAVAILABLE"
	end
	-- A shift belongs to a character, not to an account.
	--
	-- Nothing used to require one, so a player could take a police role straight
	-- from the menu without ever making a character. That mostly looked like it
	-- worked: they got the team, the spawn and the loadout. What they did not get
	-- was a warrant card, because the card prints a name and there was no name to
	-- print, and the attempt to issue it treated the missing character as "not
	-- ready yet" and gave up without a word. Selecting a character afterwards
	-- cannot repair it either, since that deliberately ends the shift.
	--
	-- Refusing here is the only point where the player can still be told.
	if
		not session.ActiveCharacterId or not session.Profile.Characters[session.ActiveCharacterId]
	then
		return false, "NO_ACTIVE_CHARACTER"
	end
	-- StartMenuService normally provisions one profile for every department the
	-- player can access. Duty must remain safe when a client submits a valid role
	-- request before that menu refresh finishes, or when an older profile has no
	-- DutyProfiles table after migration.
	session.Profile.DutyProfiles = session.Profile.DutyProfiles or {}
	local profile = session.Profile.DutyProfiles[request.DutyProfileId]
	if not profile then
		local startMenu = self.context.Services:Get("StartMenuService")
		if startMenu and type(startMenu.Build) == "function" then
			startMenu:Build(player)
		end
		if not self.running or not playerIsPresent(player) then
			return false, "DUTY_UNAVAILABLE"
		end
		profile = session.Profile.DutyProfiles[request.DutyProfileId]
	end
	if not profile then
		return false, "DUTY_PROFILE_NOT_FOUND"
	end
	local role = self.context.Configuration.Roles[request.RoleId]
	if not role or role.DepartmentId ~= profile.DepartmentId then
		return false, "INVALID_DUTY_COMBINATION"
	end
	local point, spawnReason = self.context.Services:Get("SpawnService"):Resolve(request)
	if not point then
		return false, spawnReason
	end
	local previousTeam = player.Team
	local assigned, roleReason =
		self.context.Services:Get("RoleService"):Assign(player, request.RoleId)
	if not assigned then
		return false, roleReason
	end
	if not self.running or not playerIsPresent(player) then
		return false, "DUTY_UNAVAILABLE"
	end
	local spawned, finalSpawnReason =
		self.context.Services:Get("SpawnService"):Spawn(player, request)
	if not spawned then
		player.Team = previousTeam
		return false, finalSpawnReason
	end
	if not self.running or not playerIsPresent(player) then
		return false, "DUTY_UNAVAILABLE"
	end
	-- Players arrive in their Roblox clothing and choose an authorised uniform
	-- from the changing room. This keeps clothing selection visible and avoids
	-- silently dressing somebody before the changing-room assets have loaded.
	if role.LoadoutId then
		local equipped, loadoutReason =
			self.context.Services:Get("LoadoutService"):Apply(player, role.LoadoutId)
		if not equipped then
			-- Missing authored tools must not make the underlying team, spawn and
			-- dispatch flows impossible to test. Tool actions remain unavailable
			-- until their trusted assets exist; no substitute permission is granted.
			self.context.Logger:Warning("Duty started with incomplete loadout", {
				UserId = player.UserId,
				RoleId = request.RoleId,
				Reason = loadoutReason,
			})
		end
	end
	-- Nothing is recorded for a player who has already left.
	--
	-- Begin yields repeatedly before reaching this line: a group-rank web call
	-- inside the access check, LoadCharacterAsync inside the spawn, the loadout,
	-- and a DataStore write for the shoulder number. The request handler is not
	-- tied to the connection, so a player who disconnects part-way through leaves
	-- PlayerRemoving to run its cleanup first and finds nothing to clean, and then
	-- this line writes a duty record for a UserId that is no longer in the game.
	--
	-- Nothing ever clears it afterwards, and the first check in Begin refuses
	-- anybody already in self.active, so that player could never go on duty again
	-- for the remaining life of the server -- with no error explaining why.
	if not self.running or not playerIsPresent(player) then
		return false, if playerIsPresent(player) then "DUTY_UNAVAILABLE" else "PLAYER_LEFT"
	end
	local dutyRecord = {
		DutyProfileId = request.DutyProfileId,
		RoleId = request.RoleId,
		StationId = request.StationId,
		SpawnId = request.SpawnId,
		StartedAt = os.time(),
		DepartmentId = role.DepartmentId,
		DivisionId = role.DivisionId,
		TeamName = role.TeamName,
	}
	self.active[player.UserId] = dutyRecord
	if role.AutoEquipUniform == true and role.UniformId then
		local applied, uniformReason =
			self.context.Services:Get("UniformService"):Apply(player, role.UniformId)
		if not applied then
			self.context.Logger:Warning("Duty started without its automatic uniform", {
				UserId = player.UserId,
				RoleId = request.RoleId,
				UniformId = role.UniformId,
				Reason = uniformReason,
			})
		end
	end
	if role.DepartmentId == "Police" then
		local applied, epauletteReason = self.context.Services
			:Get("ImportedSystemAdapterService")
			:ApplyEpaulettes(player, profile)
		if not applied then
			self.context.Logger:Warning("Police epaulettes could not be applied", {
				UserId = player.UserId,
				RoleId = request.RoleId,
				Reason = epauletteReason,
			})
		end
	end
	-- The rank abbreviation and shoulder number is always safe to display because
	-- it is server-authored. A stored custom callsign is user-authored text and
	-- therefore cannot be shown until Roblox has filtered it. Issuing a first
	-- shoulder number can yield through DataStore retries. The player can end
	-- duty or enter the city during that wait, so this duty record must still be
	-- the current one before its unit is registered.
	local shoulder = self.context.Services:Get("ShoulderNumberService"):Callsign(player, profile)
	local playerIsCurrent = playerIsPresent(player)
	if not self.running or not playerIsCurrent or self.active[player.UserId] ~= dutyRecord then
		return false, if playerIsCurrent then "DUTY_UNAVAILABLE" else "PLAYER_LEFT"
	end
	local callsign = if type(shoulder) == "string" and #shoulder >= 2
		then shoulder
		else string.format("%s-%d", role.DepartmentId, player.UserId % 100)
	local unit, unitReason = self.context.Services:Get("UnitService"):Register(player, {
		Callsign = callsign,
		DepartmentId = role.DepartmentId,
		DivisionId = role.DivisionId,
		StationId = request.StationId,
	})
	if not unit then
		self.active[player.UserId] = nil
		player.Team = previousTeam
		return false, unitReason
	end
	if not playerIsPresent(player) then
		self.context.Services:Get("UnitService"):Unregister(player)
		self.active[player.UserId] = nil
		return false, "PLAYER_LEFT"
	end
	dutyRecord.Callsign = callsign
	self:_publishUnitChanged(player.UserId, role.DepartmentId)

	-- Existing profiles may contain a custom callsign saved before callsigns were
	-- filtered. Do not expose that legacy value while moderation is pending: the
	-- server-generated callsign above remains visible, and a successful filter may
	-- replace it only if this exact duty/profile is still current.
	local storedCallsign = if type(profile.Callsign) == "string" then profile.Callsign else nil
	if storedCallsign then
		task.spawn(function()
			if
				not self.running
				or not playerIsPresent(player)
				or self.active[player.UserId] ~= dutyRecord
			then
				return
			end
			local filtered = filterCallsign(player, storedCallsign)
			if not filtered then
				return
			end
			-- Filtering yields. Re-run the full duty/access check before publishing
			-- legacy user text to a unit or another player.
			local currentDuty = self:Get(player)
			if currentDuty ~= dutyRecord then
				return
			end
			local currentSession = dataService:GetSession(player)
			local currentProfile = currentSession
				and currentSession.Profile.DutyProfiles[dutyRecord.DutyProfileId]
			if
				currentSession ~= session
				or currentProfile ~= profile
				or profile.Callsign ~= storedCallsign
			then
				return
			end
			local updated = self.context.Services
				:Get("UnitService")
				:SetCallsign(tostring(player.UserId), filtered)
			if not updated then
				return
			end
			dutyRecord.Callsign = filtered
			profile.Callsign = filtered
			dataService:MarkDirty(player)
			self:_publishUnitChanged(player.UserId, dutyRecord.DepartmentId)
		end)
	end

	task.spawn(function()
		if not self.running or not playerIsPresent(player) then
			return
		end
		local identification = self.context.Services:Get("IdentificationService")
		identification:RefreshWithRetry(player)
		if not self.running or not playerIsPresent(player) then
			return
		end
		-- Team assignment, character spawning and StarterGear replication can settle
		-- in different frames. A second refresh closes that race without issuing a
		-- a duplicate: IdentificationService removes stale credentials first.
		task.delay(1, function()
			if self.running and playerIsPresent(player) and self:Get(player) then
				identification:RefreshWithRetry(player)
			end
		end)
	end)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Duty.Started",
		Target = request.RoleId,
		Metadata = { StationId = request.StationId, SpawnId = request.SpawnId },
	})
	return true, nil
end

function DutyService:Begin(player: Player, request: any): (boolean, string?)
	-- A duty start crosses group access, character spawn, loadout and shoulder
	-- number work before the live duty record exists. Claim the exact Player
	-- instance first so duplicate/retried remotes cannot run those side effects
	-- concurrently and race to overwrite the final duty state.
	if self.beginning[player] then
		return false, "DUTY_START_IN_PROGRESS"
	end
	self.beginning[player] = true
	local ok, started, reason = pcall(self._begin, self, player, request)
	self.beginning[player] = nil
	if not ok then
		error(started)
	end
	return started, reason
end

function DutyService:SetCallsign(player: Player, raw: string): (string?, string?)
	-- Reject obvious off-duty abuse before spending a Roblox moderation request.
	-- This is only a cheap pre-check; the authoritative duty check happens after
	-- filtering because moderation yields.
	if not self.running or not playerIsPresent(player) or not self.active[player.UserId] then
		return nil, "NOT_ON_DUTY"
	end
	local callsign, filterReason = filterCallsign(player, raw)
	if not callsign then
		return nil, filterReason
	end

	-- Filtering yields. Resolve duty, access and the exact profile only after it
	-- completes so stale pre-filter authority cannot be used to update a unit.
	local duty = self:Get(player)
	if not duty then
		return nil, "NOT_ON_DUTY"
	end
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	local profile = session and session.Profile.DutyProfiles[duty.DutyProfileId]
	if not profile then
		return nil, "DUTY_PROFILE_NOT_FOUND"
	end
	local updated, reason =
		self.context.Services:Get("UnitService"):SetCallsign(tostring(player.UserId), callsign)
	if not updated then
		return nil, reason
	end
	profile.Callsign = callsign
	duty.Callsign = callsign
	dataService:MarkDirty(player)
	self:_publishUnitChanged(player.UserId, duty.DepartmentId)
	return callsign, nil
end

function DutyService:End(player: Player)
	local duty = self.active[player.UserId]
	self.active[player.UserId] = nil
	if not self.running then
		return
	end
	local unitId = tostring(player.UserId)
	local unitService = self.context.Services:Get("UnitService")
	local unit = unitService.units[unitId]
	local departmentId = if duty then duty.DepartmentId else if unit then unit.DepartmentId else nil
	unitService:Unregister(player)
	self:_publishUnitChanged(player.UserId, departmentId)
	self.context.Services:Get("LoadoutService"):ClearIssued(player)
	self.context.Services:Get("UniformService"):Restore(player)
	self.context.Services:Get("ImportedSystemAdapterService"):ClearEpaulettes(player)
	self.context.Services:Get("IdentificationService"):Refresh(player)
	if duty then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Duty.Ended",
			Target = duty.RoleId,
			Metadata = { StationId = duty.StationId },
		})
	end
end

function DutyService:Destroy()
	self.running = false
	for _, connection in self.connections or {} do
		connection:Disconnect()
	end
	table.clear(self.connections or {})
	for _, connection in self.playerConnections or {} do
		connection:Disconnect()
	end
	table.clear(self.playerConnections or {})
	table.clear(self.beginning)
	table.clear(self.active)
end

return DutyService
