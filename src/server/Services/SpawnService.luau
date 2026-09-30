--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local SpawnService = {
	points = {},
	pointStates = {},
	civilianEntering = {},
	running = false,
}

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function SpawnService:Init(context: any)
	self.context = context
	table.clear(self.points)
	table.clear(self.pointStates)
	table.clear(self.civilianEntering)
	self.running = false
end

-- Spawn pads to consider. Walking every descendant of the workspace is fine on
-- a baseplate and slow on a region-sized map, where it blocks the rest of
-- startup, so a tagged set is preferred when the map provides one and the walk
-- remains as the fallback for maps that have not been tagged yet.
function SpawnService:_candidatePads(): { Instance }
	local tag = self.context.Configuration.Spawning and self.context.Configuration.Spawning.PadTag
	local tagged = if type(tag) == "string" then CollectionService:GetTagged(tag) else {}
	if #tagged > 0 then
		return tagged
	end
	self.context.Logger:Warning("Spawn pads are untagged; scanning the workspace instead", {
		Tag = tag,
	})
	return workspace:GetDescendants()
end

function SpawnService:_registerConfiguredPoints()
	table.clear(self.points)
	local found = {}
	for _, instance in self:_candidatePads() do
		if instance:IsA("SpawnLocation") and instance:IsDescendantOf(workspace) then
			local spawnId = instance:GetAttribute("SpawnId")
			if type(spawnId) ~= "string" or spawnId == "" then
				spawnId = self.context.Configuration.Spawning.TeamNameFallbacks[instance.Name]
			end
			if type(spawnId) == "string" and self.context.Configuration.Spawns[spawnId] then
				if found[spawnId] then
					self.context.Logger:Error(
						"SpawnId is assigned to multiple pads",
						{ SpawnId = spawnId }
					)
					self.points[spawnId] = nil
				else
					found[spawnId] = true
					self.points[spawnId] = instance
				end
			end
		end
	end
	for spawnId, definition in self.context.Configuration.Spawns do
		local point = self.points[spawnId]
		local team = self.context.Services:Get("TeamService"):Get(definition.TeamName)
		if not point then
			self.context.Logger:Warning(
				"Configured native spawn pad is missing",
				{ SpawnId = spawnId }
			)
		elseif not team then
			self.context.Logger:Error("Spawn team is unavailable", { SpawnId = spawnId })
			self.points[spawnId] = nil
		else
			if not self.pointStates[point] then
				self.pointStates[point] = {
					OriginalName = point.Name,
					OriginalTeamColor = point.TeamColor,
					OriginalNeutral = point.Neutral,
					OriginalAllowTeamChangeOnTouch = point.AllowTeamChangeOnTouch,
					ManagedName = team.Name,
					ManagedTeamColor = team.TeamColor,
				}
			end
			point.Name = team.Name
			point.TeamColor = team.TeamColor
			point.Neutral = false
			point.AllowTeamChangeOnTouch = false
		end
	end
end

function SpawnService:_restorePointState()
	for point, state in self.pointStates do
		if point.Parent then
			-- Restore only properties that still carry the values this service
			-- applied. A later map/runtime owner must not be overwritten on teardown.
			if point.Name == state.ManagedName then
				point.Name = state.OriginalName
			end
			if point.TeamColor == state.ManagedTeamColor then
				point.TeamColor = state.OriginalTeamColor
			end
			if point.Neutral == false then
				point.Neutral = state.OriginalNeutral
			end
			if point.AllowTeamChangeOnTouch == false then
				point.AllowTeamChangeOnTouch = state.OriginalAllowTeamChangeOnTouch
			end
		end
	end
	table.clear(self.pointStates)
end

function SpawnService:Start()
	local ok, problem = pcall(function()
		self:_registerConfiguredPoints()
	end)
	if not ok then
		self:_restorePointState()
		table.clear(self.points)
		error(problem, 0)
	end
	self.running = true
end

function SpawnService:Resolve(request: any): (SpawnLocation?, string?)
	if not self.running then
		return nil, "SPAWN_UNAVAILABLE"
	end
	local role = self.context.Configuration.Roles[request.RoleId]
	if not role then
		return nil, "ROLE_NOT_FOUND"
	end
	local valid, reason =
		self.context.Services
			:Get("StationService")
			:ValidateSpawn(request.StationId, request.SpawnId, request.RoleId, role.DepartmentId)
	if not valid then
		return nil, reason
	end
	local point = self.points[request.SpawnId]
	if not point or not point:IsDescendantOf(workspace) then
		return nil, "SPAWN_POINT_UNAVAILABLE"
	end
	local team = self.context.Services:Get("TeamService"):Get(role.TeamName)
	if not team or point.TeamColor ~= team.TeamColor or point.Neutral then
		return nil, "SPAWN_TEAM_MISMATCH"
	end
	return point, nil
end

function SpawnService:Spawn(player: Player, request: any): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "SPAWN_UNAVAILABLE"
	end
	local point, reason = self:Resolve(request)
	if not point then
		return false, reason
	end
	if not self.running or not playerIsCurrent(player) then
		return false, "SPAWN_UNAVAILABLE"
	end
	player.RespawnLocation = point
	local loaded, loadError = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not self.running or not playerIsCurrent(player) then
		return false, "SPAWN_UNAVAILABLE"
	end
	if not loaded or not player.Character then
		self.context.Logger:Error("Character spawn failed", {
			UserId = player.UserId,
			SpawnId = request.SpawnId,
			Error = tostring(loadError),
		})
		return false, "CHARACTER_SPAWN_FAILED"
	end
	self.context.Logger:Info("Player spawned through native team pad", {
		UserId = player.UserId,
		SpawnId = request.SpawnId,
		StationId = request.StationId,
		Team = point.Name,
	})
	return true, nil
end

function SpawnService:_enterCivilian(
	player: Player,
	characterId: string,
	spawnId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or session.ActiveCharacterId ~= characterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local custodyService = self.context.Services:Get("CustodyService")
	if custodyService:HasActiveSentence(player) then
		local spawned, custodyReason = custodyService:SpawnInCell(player)
		if not spawned then
			return false, custodyReason
		end
		session.Profile.AuditMetadata.LastCharacterId = characterId
		self.context.Services:Get("DataService"):MarkDirty(player)
		return true, nil
	end
	local definition = self.context.Configuration.Spawns[spawnId]
	if not definition or definition.TeamName ~= "Civilian" then
		return false, "INVALID_CIVILIAN_SPAWN"
	end
	local request = {
		RoleId = "Civilian",
		StationId = definition.StationId,
		SpawnId = spawnId,
	}
	local previousTeam = player.Team
	local assigned, roleReason = self.context.Services:Get("RoleService"):Assign(player, "Civilian")
	if not assigned then
		return false, roleReason
	end
	local spawned, spawnReason = self:Spawn(player, request)
	if not spawned then
		player.Team = previousTeam
		return false, spawnReason
	end
	local applied, appearanceReason =
		self.context.Services:Get("CharacterService"):ApplyCivilianAppearance(player, characterId)
	if not applied then
		self.context.Logger:Warning("Civilian appearance could not be applied", {
			UserId = player.UserId,
			CharacterId = characterId,
			Reason = appearanceReason,
		})
	end
	session.Profile.AuditMetadata.LastCharacterId = characterId
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end

-- The first configured civilian spawn, the same one EnterCivilian itself
-- resolves to today since there is only ever the one. Used as a safe loading
-- point for a territory spawn: a territory part carries no Team of its own,
-- so it cannot be handed to RespawnLocation the way a real pad can.
function SpawnService:_civilianSpawnId(): string?
	for spawnId, definition in self.context.Configuration.Spawns do
		if definition.TeamName == "Civilian" then
			return spawnId
		end
	end
	return nil
end

-- An additional way into the city, alongside the ordinary civilian spawn: a
-- gang's own ground, for a member of the gang that currently holds it.
--
-- Loads the character at the ordinary civilian pad first -- the same safe,
-- Team-matched starting point every civilian gets -- and only then moves it.
-- SpawnService.Spawn hands a real SpawnLocation to RespawnLocation and lets
-- Roblox place the character; a territory part is just a tagged Part with no
-- Team of its own, so the same trick does not apply and a teleport after
-- loading is what actually gets a character there.
function SpawnService:_enterCivilianAtTerritory(
	player: Player,
	characterId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or session.ActiveCharacterId ~= characterId then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	local custodyService = self.context.Services:Get("CustodyService")
	if custodyService:HasActiveSentence(player) then
		local spawned, custodyReason = custodyService:SpawnInCell(player)
		if not spawned then
			return false, custodyReason
		end
		session.Profile.AuditMetadata.LastCharacterId = characterId
		self.context.Services:Get("DataService"):MarkDirty(player)
		return true, nil
	end
	local gangId = session.Profile.GangId
	if type(gangId) ~= "string" then
		return false, "NOT_IN_A_GANG"
	end
	local dataService = self.context.Services:Get("DataService")
	local officialEntry = self.context.Services:Get("OfficialServerService"):CurrentEntry()
	local sharedScope = if type(officialEntry) == "table"
			and type(officialEntry.Id) == "string"
		then officialEntry.Id
		else nil
	local gang, gangReason = dataService:GetScopedSharedRecord(sharedScope, "gang:" .. gangId)
	if gangReason then
		return false, gangReason
	end
	local territoryId = type(gang) == "table" and gang.TerritoryId
	if type(territoryId) ~= "string" or territoryId == "" then
		return false, "GANG_HAS_NO_TERRITORY"
	end
	local territoryPart = self.context.Services:Get("GangTerritoryService"):PartOf(territoryId)
	if not territoryPart then
		return false, "TERRITORY_UNAVAILABLE"
	end
	local civilianSpawnId = self:_civilianSpawnId()
	local civilianPoint = civilianSpawnId and self.points[civilianSpawnId]
	if not civilianPoint then
		return false, "SPAWN_POINT_UNAVAILABLE"
	end
	local previousTeam = player.Team
	local assigned, roleReason = self.context.Services:Get("RoleService"):Assign(player, "Civilian")
	if not assigned then
		return false, roleReason
	end
	if not self.running or not playerIsCurrent(player) then
		player.Team = previousTeam
		return false, "SPAWN_UNAVAILABLE"
	end
	player.RespawnLocation = civilianPoint
	local loaded, loadError = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not self.running or not playerIsCurrent(player) then
		return false, "SPAWN_UNAVAILABLE"
	end
	local loadedCharacter = player.Character
	if not loaded or not loadedCharacter then
		self.context.Logger:Error("Character spawn failed", {
			UserId = player.UserId,
			TerritoryId = territoryId,
			Error = tostring(loadError),
		})
		player.Team = previousTeam
		return false, "CHARACTER_SPAWN_FAILED"
	end
	local root = loadedCharacter:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame =
			CFrame.new(territoryPart.Position + Vector3.new(0, territoryPart.Size.Y / 2 + 3, 0))
	end
	local applied, appearanceReason =
		self.context.Services:Get("CharacterService"):ApplyCivilianAppearance(player, characterId)
	if not applied then
		self.context.Logger:Warning("Civilian appearance could not be applied", {
			UserId = player.UserId,
			CharacterId = characterId,
			Reason = appearanceReason,
		})
	end
	self.context.Logger:Info("Player spawned at gang territory", {
		UserId = player.UserId,
		TerritoryId = territoryId,
	})
	session.Profile.AuditMetadata.LastCharacterId = characterId
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end

function SpawnService:_withCivilianEntryClaim(
	player: Player,
	callback: () -> (boolean, string?)
): (boolean, string?)
	if self.civilianEntering[player] then
		return false, "CIVILIAN_ENTRY_IN_PROGRESS"
	end

	-- Character loading yields. Hold one local claim across both ordinary and
	-- gang-territory entry, then join the shared role-transition claim before
	-- ending duty. This prevents BeginDuty or character selection from overtaking
	-- the team/character load while the civilian entry is still in flight.
	local claim = {}
	self.civilianEntering[player] = claim
	local dutyService = self.context.Services:Get("DutyService")
	local transitionClaim, transitionReason = dutyService:ClaimRoleTransition(player)
	if not transitionClaim then
		if self.civilianEntering[player] == claim then
			self.civilianEntering[player] = nil
		end
		return false,
			if transitionReason == "ROLE_TRANSITION_IN_PROGRESS"
				then "CIVILIAN_ENTRY_IN_PROGRESS"
				else transitionReason
	end

	local ok, entered, reason = pcall(function(): (boolean, string?)
		dutyService:End(player)
		return callback()
	end)
	dutyService:ReleaseRoleTransition(player, transitionClaim)
	if self.civilianEntering[player] == claim then
		self.civilianEntering[player] = nil
	end
	if not ok then
		error(entered)
	end
	return entered, reason
end

function SpawnService:EnterCivilian(
	player: Player,
	characterId: string,
	spawnId: string
): (boolean, string?)
	return self:_withCivilianEntryClaim(player, function()
		return self:_enterCivilian(player, characterId, spawnId)
	end)
end

function SpawnService:EnterCivilianAtTerritory(
	player: Player,
	characterId: string
): (boolean, string?)
	return self:_withCivilianEntryClaim(player, function()
		return self:_enterCivilianAtTerritory(player, characterId)
	end)
end

function SpawnService:Destroy()
	self.running = false
	table.clear(self.civilianEntering)
	self:_restorePointState()
	table.clear(self.points)
end

return SpawnService
