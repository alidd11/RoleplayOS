--!strict

local Players = game:GetService("Players")
-- Whether a player is still in the game.
--
-- Parent is the reliable test: a Player instance that has left is removed from
-- the Players service but the reference held by an in-flight request stays
-- perfectly valid, so checking the reference alone proves nothing.
local function playerIsPresent(player: Player): boolean
	return player.Parent ~= nil
end

local DutyService = { active = {} }

function DutyService:Init(context: any)
	self.context = context
end

function DutyService:Start()
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

function DutyService:Begin(player: Player, request: any): (boolean, string?)
	if self.active[player.UserId] then
		return false, "ALREADY_ON_DUTY"
	end
	if self.context.Services:Get("CustodyService"):HasActiveSentence(player) then
		return false, "ACTIVE_CUSTODY_SENTENCE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
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
	local spawned, finalSpawnReason =
		self.context.Services:Get("SpawnService"):Spawn(player, request)
	if not spawned then
		player.Team = previousTeam
		return false, finalSpawnReason
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
	if not playerIsPresent(player) then
		return false, "PLAYER_LEFT"
	end
	self.active[player.UserId] = {
		DutyProfileId = request.DutyProfileId,
		RoleId = request.RoleId,
		StationId = request.StationId,
		SpawnId = request.SpawnId,
		StartedAt = os.time(),
		DepartmentId = role.DepartmentId,
		DivisionId = role.DivisionId,
		TeamName = role.TeamName,
	}
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
	-- The rank abbreviation and shoulder number, issued now if this is the first
	-- shift in this service. An explicitly set callsign on the profile still wins,
	-- so a unit given a bespoke one by staff keeps it.
	local shoulder = self.context.Services:Get("ShoulderNumberService"):Callsign(player, profile)
	if not playerIsPresent(player) then
		self.active[player.UserId] = nil
		return false, "PLAYER_LEFT"
	end
	local callsign = if type(profile.Callsign) == "string" and #profile.Callsign >= 2
		then profile.Callsign
		elseif type(shoulder) == "string" and #shoulder >= 2 then shoulder
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
	self.active[player.UserId].Callsign = callsign
	task.spawn(function()
		local identification = self.context.Services:Get("IdentificationService")
		identification:RefreshWithRetry(player)
		-- Team assignment, character spawning and StarterGear replication can settle
		-- in different frames. A second refresh closes that race without issuing a
		-- a duplicate: IdentificationService removes stale credentials first.
		task.delay(1, function()
			if player.Parent and self:Get(player) then
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

function DutyService:SetCallsign(player: Player, raw: string): (string?, string?)
	local duty = self:Get(player)
	if not duty then
		return nil, "NOT_ON_DUTY"
	end
	local callsign = string.upper(string.sub(string.gsub(raw, "[^%w%- ]", ""), 1, 16))
	callsign = string.gsub(callsign, "^%s+", "")
	callsign = string.gsub(callsign, "%s+$", "")
	if #callsign < 2 then
		return nil, "INVALID_CALLSIGN"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local profile = session and session.Profile.DutyProfiles[duty.DutyProfileId]
	if not profile then
		return nil, "DUTY_PROFILE_NOT_FOUND"
	end
	profile.Callsign = callsign
	duty.Callsign = callsign
	local updated, reason =
		self.context.Services:Get("UnitService"):SetCallsign(tostring(player.UserId), callsign)
	if not updated then
		return nil, reason
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return callsign, nil
end

function DutyService:End(player: Player)
	local duty = self.active[player.UserId]
	self.active[player.UserId] = nil
	self.context.Services:Get("UnitService"):Unregister(player)
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
	for _, connection in self.connections or {} do
		connection:Disconnect()
	end
	table.clear(self.connections or {})
	for _, connection in self.playerConnections or {} do
		connection:Disconnect()
	end
	table.clear(self.playerConnections or {})
	table.clear(self.active)
end

return DutyService
