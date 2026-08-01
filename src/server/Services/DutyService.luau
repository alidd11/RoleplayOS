--!strict
local DutyService = { active = {} }
function DutyService:Init(context: any)
	self.context = context
end
function DutyService:Start() end
function DutyService:Begin(
	player: Player,
	dutyProfileId: string,
	roleId: string,
	stationId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local profile = session and session.Profile.DutyProfiles[dutyProfileId]
	if not profile then
		return false, "DUTY_PROFILE_NOT_FOUND"
	end
	local role = self.context.Configuration.Roles[roleId]
	if
		not role
		or role.DepartmentId ~= profile.DepartmentId
		or not self.context.Configuration.Stations[stationId]
	then
		return false, "INVALID_DUTY_COMBINATION"
	end
	local assigned, reason = self.context.Services:Get("RoleService"):Assign(player, roleId)
	if not assigned then
		return false, reason
	end
	self.active[player.UserId] = {
		DutyProfileId = dutyProfileId,
		RoleId = roleId,
		StationId = stationId,
		StartedAt = os.time(),
	}
	return true, nil
end
function DutyService:End(player: Player)
	self.active[player.UserId] = nil
end
function DutyService:Destroy()
	table.clear(self.active)
end
return DutyService
