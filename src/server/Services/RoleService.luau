--!strict
local Teams = game:GetService("Teams")
local RoleService = {}
function RoleService:Init(context: any)
	self.context = context
end
function RoleService:Start() end
function RoleService:Assign(player: Player, roleId: string): (boolean, string?)
	local role = self.context.Configuration.Roles[roleId]
	if not role then
		return false, "ROLE_NOT_FOUND"
	end
	local result = self.context.Services:Get("AccessService"):Evaluate(player, role.Access)
	if not result.Allowed then
		return false, result.ReasonCode
	end
	local team = Teams:FindFirstChild(role.TeamName)
	if not team or not team:IsA("Team") then
		return false, "TEAM_NOT_CONFIGURED"
	end
	player.Team = team
	return true, nil
end
function RoleService:Destroy() end
return RoleService
