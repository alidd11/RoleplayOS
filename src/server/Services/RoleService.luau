--!strict

local Players = game:GetService("Players")

local RoleService = { running = false }

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function RoleService:Init(context: any)
	self.context = context
	self.running = false
end

function RoleService:Start()
	self.running = true
end
function RoleService:Assign(player: Player, roleId: string): (boolean, string?)
	if not self.running or not playerIsCurrent(player) then
		return false, "ROLE_UNAVAILABLE"
	end
	local role = self.context.Configuration.Roles[roleId]
	if not role then
		return false, "ROLE_NOT_FOUND"
	end
	local dataService = self.context.Services:Get("DataService")
	local session = dataService:GetSession(player)
	if not session then
		return false, "PROFILE_UNAVAILABLE"
	end
	local result = self.context.Services:Get("AccessService"):Evaluate(player, role.Access)
	-- Access evaluation can yield on Roblox group membership. A stale request
	-- must not assign a team after teardown, Player replacement or profile reload.
	if
		not self.running
		or not playerIsCurrent(player)
		or dataService:GetSession(player) ~= session
	then
		return false, "ROLE_UNAVAILABLE"
	end
	if not result.Allowed then
		return false, result.ReasonCode
	end
	local team = self.context.Services:Get("TeamService"):Get(role.TeamName)
	if not team then
		return false, "TEAM_NOT_CONFIGURED"
	end
	if not self.running or not playerIsCurrent(player) then
		return false, "ROLE_UNAVAILABLE"
	end
	player.Team = team
	player.Neutral = false
	return true, nil
end

function RoleService:Destroy()
	self.running = false
end
return RoleService
