--!strict

local Players = game:GetService("Players")

local ExperienceAccessService = { connections = {} }

function ExperienceAccessService:Init(context: any)
	self.context = context
end

function ExperienceAccessService:_check(player: Player)
	local config = self.context.Configuration.ExperienceAccess
	if not config.Enabled or not player:IsDescendantOf(Players) then
		return
	end
	local membership =
		self.context.Services:Get("GroupService"):GetMembership(player, config.RequiredGroupLinkId)
	if
		membership.IsMember == true
		and (membership.HighestRank or 0) >= (membership.MinimumRank or 1)
	then
		self.context.Logger:Info("Experience group access granted", {
			UserId = player.UserId,
			GroupId = membership.GroupId,
			Mock = membership.Mock == true,
		})
		return
	end
	self.context.Logger:Security("Experience group access denied", {
		UserId = player.UserId,
		GroupId = membership.GroupId,
		Failed = membership.Failed == true,
	})
	player:Kick(config.KickMessage)
end

function ExperienceAccessService:Start()
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				self:_check(player)
			end)
		end)
	)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_check(player)
		end)
	end
end

function ExperienceAccessService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return ExperienceAccessService
