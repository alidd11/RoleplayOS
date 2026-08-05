--!strict

local Players = game:GetService("Players")

local ExperienceAccessService = { Critical = true, connections = {} }

function ExperienceAccessService:Init(context: any)
	self.context = context
end

-- Entry to this server, which is not the same as entry to the experience.
--
-- The published place is open to everyone: that is the public tier, where
-- emergency roles are bought rather than applied for. A server asks for a group
-- only when it is one of the whitelisted ones, and it asks for that server's
-- group rather than a single experience wide one.
function ExperienceAccessService:_check(player: Player)
	local config = self.context.Configuration.ExperienceAccess
	if not player:IsDescendantOf(Players) then
		return
	end
	local linkId = self.context.Services:Get("CommunityServerService"):RequiredGroupLinkId()
	if not linkId then
		return
	end
	local groupService = self.context.Services:Get("GroupService")
	local membership = groupService:GetMembership(player, linkId)
	-- A failed check is usually Roblox throttling this server rather than an
	-- answer about this player, and a throttle clears on a clock. The waits
	-- therefore double, so the retries outlast a rate limit instead of arriving
	-- inside it and turning every throttled join into a kick.
	for attempt = 2, config.VerifyAttempts or 4 do
		if membership.Failed ~= true or not player:IsDescendantOf(Players) then
			break
		end
		task.wait((config.VerifyBackoffSeconds or 3) * 2 ^ (attempt - 2))
		if not player:IsDescendantOf(Players) then
			return
		end
		groupService:Invalidate(player, linkId)
		membership = groupService:GetMembership(player, linkId)
	end
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
	player:Kick(
		if membership.Failed == true
			then "Roblox could not verify your Universal Projects membership. Please rejoin shortly."
			else config.KickMessage
	)
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
