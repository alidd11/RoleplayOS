--!strict

local DutyService = { active = {} }

function DutyService:Init(context: any)
	self.context = context
end

function DutyService:Start() end

function DutyService:Begin(player: Player, request: any): (boolean, string?)
	if self.active[player.UserId] then
		return false, "ALREADY_ON_DUTY"
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
	}
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
	table.clear(self.active)
end

return DutyService
