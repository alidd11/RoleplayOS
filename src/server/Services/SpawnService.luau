--!strict

local SpawnService = { points = {} }

function SpawnService:Init(context: any)
	self.context = context
end

function SpawnService:_registerConfiguredPoints()
	table.clear(self.points)
	local found = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			local spawnId = instance:GetAttribute("SpawnId")
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
			point.Name = team.Name
			point.TeamColor = team.TeamColor
			point.Neutral = false
			point.AllowTeamChangeOnTouch = false
		end
	end
end

function SpawnService:Start()
	self:_registerConfiguredPoints()
end

function SpawnService:Resolve(request: any): (SpawnLocation?, string?)
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
	local point, reason = self:Resolve(request)
	if not point then
		return false, reason
	end
	player.RespawnLocation = point
	local loaded, loadError = pcall(function()
		player:LoadCharacterAsync()
	end)
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

function SpawnService:EnterCivilian(
	player: Player,
	characterId: string,
	spawnId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or session.ActiveCharacterId ~= characterId then
		return false, "CHARACTER_NOT_ACTIVE"
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
	session.Profile.AuditMetadata.LastCharacterId = characterId
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end

function SpawnService:Destroy()
	table.clear(self.points)
end

return SpawnService
