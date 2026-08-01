--!strict
local SpawnService = {}
function SpawnService:Init(context: any)
	self.context = context
end
function SpawnService:Start() end
function SpawnService:Spawn(player: Player, request: any): (boolean, string?)
	local role = self.context.Configuration.Roles[request.RoleId]
	if not role then
		return false, "ROLE_NOT_FOUND"
	end
	if
		role.DepartmentId
		and not self.context.Services
			:Get("StationService")
			:IsValid(request.StationId, role.DepartmentId, request.SpawnName)
	then
		return false, "INVALID_SPAWN"
	end
	local spawn = workspace:FindFirstChild(request.SpawnName, true)
	if not spawn or not spawn:IsA("SpawnLocation") then
		return false, "SPAWN_UNAVAILABLE"
	end
	player.RespawnLocation = spawn
	player:LoadCharacter()
	return true, nil
end
function SpawnService:Destroy() end
return SpawnService
