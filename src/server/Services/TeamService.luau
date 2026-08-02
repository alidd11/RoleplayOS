--!strict

local Teams = game:GetService("Teams")
local TeamService = { teams = {} }

function TeamService:Init(context: any)
	self.context = context
end

function TeamService:Start()
	for teamId, definition in self.context.Configuration.Teams do
		local team = Teams:FindFirstChild(definition.Name)
		if team and not team:IsA("Team") then
			error("Configured team name is occupied by a non-Team instance: " .. definition.Name)
		end
		if not team then
			team = Instance.new("Team")
			team.Name = definition.Name
			team.Parent = Teams
		end
		team.TeamColor = BrickColor.new(definition.BrickColor)
		team.AutoAssignable = definition.AutoAssignable
		self.teams[teamId] = team
	end
end

function TeamService:Get(teamId: string): Team?
	return self.teams[teamId]
end

function TeamService:Destroy()
	table.clear(self.teams)
end

return TeamService
