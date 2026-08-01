--!strict
local HttpService = game:GetService("HttpService")
local ShiftService = { active = {}, taskNonces = {} }
function ShiftService:Init(context: any)
	self.context = context
end
function ShiftService:Start() end
function ShiftService:ClockIn(player: Player, employmentId: string): (any?, string?)
	if self.active[player.UserId] then
		return nil, "SHIFT_ALREADY_ACTIVE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session or not session.ActiveCharacterId then
		return nil, "CHARACTER_NOT_ACTIVE"
	end
	local character = session.Profile.Characters[session.ActiveCharacterId]
	local employment
	for _, item in character.Employment do
		if item.EmploymentId == employmentId and not item.EndedAt then
			employment = item
		end
	end
	if not employment then
		return nil, "EMPLOYMENT_NOT_FOUND"
	end
	local shift = {
		ShiftId = HttpService:GenerateGUID(false),
		EmploymentId = employmentId,
		CharacterId = character.CharacterId,
		StartedAt = os.time(),
		TaskIds = {},
		Earnings = 0,
		LastActivityAt = os.time(),
	}
	self.active[player.UserId] = shift
	return shift, nil
end
function ShiftService:CompleteTask(
	player: Player,
	taskId: string,
	serverProof: string
): (boolean, string?)
	local shift = self.active[player.UserId]
	if not shift then
		return false, "NO_ACTIVE_SHIFT"
	end
	local expected = self.taskNonces[player.UserId] and self.taskNonces[player.UserId][taskId]
	if not expected or expected ~= serverProof then
		return false, "TASK_NOT_AUTHORISED"
	end
	if os.time() - shift.LastActivityAt < 5 then
		return false, "TASK_TOO_FAST"
	end
	self.taskNonces[player.UserId][taskId] = nil
	table.insert(shift.TaskIds, taskId)
	shift.LastActivityAt = os.time()
	return true, nil
end
function ShiftService:ClockOut(player: Player): (any?, string?)
	local shift = self.active[player.UserId]
	if not shift then
		return nil, "NO_ACTIVE_SHIFT"
	end
	shift.EndedAt = os.time()
	self.active[player.UserId] = nil
	return shift, nil
end
function ShiftService:Destroy()
	table.clear(self.active)
end
return ShiftService
