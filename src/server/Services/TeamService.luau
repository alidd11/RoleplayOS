--!strict

local Teams = game:GetService("Teams")
local TeamService = { Critical = true, teams = {}, createdTeams = {} }

function TeamService:Init(context: any)
	self.context = context
	self.teams = {}
	self.createdTeams = {}
end

function TeamService:Start()
	for teamId, definition in self.context.Configuration.Teams do
		local team = Teams:FindFirstChild(definition.Name)
		if team and not team:IsA("Team") then
			error("Configured team name is occupied by a non-Team instance: " .. definition.Name)
		end
		local teamColor = BrickColor.new(definition.BrickColor)
		if not team then
			team = Instance.new("Team")
			team.Name = definition.Name
			team.TeamColor = teamColor
			team.AutoAssignable = definition.AutoAssignable
			team.Parent = Teams
			self.createdTeams[team] = true
		else
			team.TeamColor = teamColor
			team.AutoAssignable = definition.AutoAssignable
		end
		self.teams[teamId] = team
	end
end

function TeamService:Get(teamId: string): Team?
	return self.teams[teamId]
end

function TeamService:Destroy()
	for team in self.createdTeams do
		team:Destroy()
	end
	table.clear(self.createdTeams)
	table.clear(self.teams)
end

return TeamService
