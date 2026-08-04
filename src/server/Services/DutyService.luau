--!strict

local Players = game:GetService("Players")
local DutyService = { active = {} }

function DutyService:Init(context: any)
	self.context = context
end

function DutyService:Start()
	self.connections = self.connections or {}
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:End(player)
		end)
	)
	local function watch(player: Player)
		table.insert(
			self.connections,
			player.CharacterAdded:Connect(function()
				task.delay(1, function()
					local duty = self:Get(player)
					if not duty then
						return
					end
					local role = self.context.Configuration.Roles[duty.RoleId]
					if role and role.LoadoutId then
						self.context.Services:Get("LoadoutService"):Apply(player, role.LoadoutId)
					end
					self.context.Services:Get("IdentificationService"):Refresh(player)
				end)
			end)
		)
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
	local profile = session and session.Profile.DutyProfiles[request.DutyProfileId]
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
	if role.UniformId then
		local uniformed, uniformReason =
			self.context.Services:Get("UniformService"):Apply(player, role.UniformId)
		if not uniformed then
			player.Team = previousTeam
			return false, uniformReason
		end
	end
	if role.LoadoutId then
		local equipped, loadoutReason =
			self.context.Services:Get("LoadoutService"):Apply(player, role.LoadoutId)
		if not equipped then
			player.Team = previousTeam
			return false, loadoutReason
		end
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
	-- The rank abbreviation and shoulder number, issued now if this is the first
	-- shift in this service. An explicitly set callsign on the profile still wins,
	-- so a unit given a bespoke one by staff keeps it.
	local shoulder = self.context.Services:Get("ShoulderNumberService"):Callsign(player, profile)
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
	self.context.Services:Get("IdentificationService"):Refresh(player)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Duty.Started",
		Target = request.RoleId,
		Metadata = { StationId = request.StationId, SpawnId = request.SpawnId },
	})
	return true, nil
end

function DutyService:End(player: Player)
	local duty = self.active[player.UserId]
	self.active[player.UserId] = nil
	self.context.Services:Get("UnitService"):Unregister(player)
	self.context.Services:Get("LoadoutService"):ClearIssued(player)
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
	table.clear(self.active)
end

return DutyService
