--!strict

local Players = game:GetService("Players")

local ExperienceAccessService = { Critical = true, connections = {}, verified = {} }

function ExperienceAccessService:Init(context: any)
	self.context = context
end

-- Entry to this server, which is not the same as entry to the experience.
--
-- The published place is open to everyone: that is the public tier, where
-- emergency roles are bought rather than applied for. A server asks for a group
-- only when it is one of the whitelisted ones, and it asks for that server's
-- group rather than a single experience wide one.
-- Whether this place is configured as a whitelisted world.
--
-- Read straight from the configuration against this server's own place id,
-- deliberately not through the services that decide the gate, because the point
-- is to catch those failing.
function ExperienceAccessService:_shouldBeGated(): boolean
	local official = self.context.Configuration.OfficialServers
	local entries = official and official.Entries
	if type(entries) ~= "table" then
		return false
	end
	for _, entry in entries do
		if
			entry.Whitelisted == true
			and tonumber(entry.PlaceId) == game.PlaceId
			and type(entry.RequiredGroupLinkId) == "string"
		then
			return true
		end
	end
	return false
end

function ExperienceAccessService:_check(player: Player)
	local config = self.context.Configuration.ExperienceAccess
	if not player:IsDescendantOf(Players) then
		return
	end
	local linkId = self.context.Services:Get("ServerModeService"):RequiredGroupLinkId()
	if not linkId then
		-- No gate resolved. On the public place that is the correct answer and
		-- the whole reason it is the public place.
		--
		-- On the whitelisted world it is a configuration failure, and a silent
		-- one: whether a server is whitelisted is decided by whether a group link
		-- resolves, so a link that fails to resolve does not read as a broken
		-- gate, it reads as a server that never had one. The place would report
		-- itself Public and admit anybody, and nothing anywhere would look wrong.
		--
		-- The place id is the one thing this server always knows about itself and
		-- it is not derived from anything above, so it is checked here directly.
		-- Refusing entry to a world that cannot prove it is gated is the only
		-- safe way to be wrong.
		if self:_shouldBeGated() then
			self.context.Logger:Error("Whitelisted place could not resolve its group gate", {
				PlaceId = game.PlaceId,
				UserId = player.UserId,
			})
			player:Kick("This world could not confirm its access settings. Please rejoin shortly.")
		else
			self.verified[player.UserId] = true
		end
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
		self.verified[player.UserId] = true
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

function ExperienceAccessService:IsVerified(player: Player): boolean
	return player:IsDescendantOf(Players) and self.verified[player.UserId] == true
end

function ExperienceAccessService:Start()
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			self.verified[player.UserId] = nil
			task.spawn(function()
				self:_check(player)
			end)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.verified[player.UserId] = nil
		end)
	)
	for _, player in Players:GetPlayers() do
		self.verified[player.UserId] = nil
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
	table.clear(self.verified)
end

return ExperienceAccessService
