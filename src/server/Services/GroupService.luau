--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RobloxGroupService = { Critical = true, cache = {}, connections = {}, failures = {} }

function RobloxGroupService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.Groups
end

function RobloxGroupService:GetMembership(player: Player, linkId: string): any
	local definition = self.context.Configuration.GroupLinks[linkId]
	if not definition then
		return { Failed = true, Reason = "GROUP_LINK_NOT_FOUND" }
	end
	return self:GetMembershipByGroupId(player, definition.GroupId, linkId, definition.MinimumRank)
end

function RobloxGroupService:Invalidate(player: Player, linkId: string?)
	local playerCache = self.cache[player.UserId]
	if not playerCache then
		return
	end
	if linkId then
		playerCache[linkId] = nil
	else
		self.cache[player.UserId] = nil
	end
end

function RobloxGroupService:GetMembershipByGroupId(
	player: Player,
	groupId: number,
	cacheKey: string?,
	minimumRank: number?
): any
	local key = cacheKey or "group:" .. tostring(groupId)
	local playerCache = self.cache[player.UserId]
	if not playerCache then
		playerCache = {}
		self.cache[player.UserId] = playerCache
	end
	local cached = playerCache[key]
	if cached and (not cached.ExpiresAt or os.clock() < cached.ExpiresAt) then
		return cached
	end
	playerCache[key] = nil
	if
		RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio
	then
		local mock = {
			GroupId = groupId,
			IsMember = true,
			HighestRank = 255,
			MinimumRank = minimumRank or 1,
			Roles = { { Id = 0, Name = "Studio Owner", Rank = 255 } },
			Mock = true,
		}
		playerCache[key] = mock
		return mock
	end
	if groupId <= 0 then
		local unconfigured = {
			GroupId = groupId,
			MinimumRank = minimumRank or 1,
			NotConfigured = true,
		}
		playerCache[key] = unconfigured
		return unconfigured
	end
	local ok, rank = pcall(player.GetRankInGroup, player, groupId)
	if not ok or type(rank) ~= "number" then
		-- Roblox throttles this call, and a failure is very often a 429 rather
		-- than a real answer about the player. Retrying a throttle on a fixed
		-- short interval deepens it, so each consecutive failure waits longer
		-- before the next attempt is allowed.
		local failures = (self.failures[key] or 0) + 1
		self.failures[key] = failures
		local backoff =
			math.min(15 * 2 ^ (failures - 1), self.settings.MaximumFailureBackoffSeconds)
		self.context.Logger:Warning("Roblox group membership check failed", {
			UserId = player.UserId,
			GroupLinkId = key,
			GroupId = groupId,
			ConsecutiveFailures = failures,
			RetryAfterSeconds = backoff,
		})
		local failure = {
			GroupId = groupId,
			MinimumRank = minimumRank or 1,
			Failed = true,
			ExpiresAt = os.clock() + backoff,
		}
		playerCache[key] = failure
		return failure
	end
	self.failures[key] = nil
	-- The role name costs a second web call per group and is only ever shown,
	-- never used to decide anything, so it is not fetched here. Doubling the
	-- request count on every join to label a rank is what pushes a busy server
	-- into the throttle that then reads as a failed membership check.
	local membership = {
		GroupId = groupId,
		IsMember = rank > 0,
		HighestRank = rank,
		MinimumRank = minimumRank or 1,
		Roles = if rank > 0 then { { Name = "Member", Rank = rank } } else {},
		ExpiresAt = os.clock() + self.settings.CacheSeconds,
	}
	playerCache[key] = membership
	return membership
end

-- Populates the membership cache for every configured link. Without this the
-- first StartMenu build performs one live GetRankInGroup per link inside the
-- request, because AccessService evaluates each role in turn.
-- Prefetches every configured link so the first StartMenu build does not perform
-- a live lookup per link inside the request.
--
-- Spaced out rather than fired as a burst. There are ten links, so warming them
-- back to back meant ten calls per joining player at once, and a server filling
-- up after a restart made hundreds within seconds. Roblox answers that with a
-- 429, which this framework then read as "membership could not be verified" and
-- turned into a kick, so the burst locked out the very players it was checking.
--
-- The link that gates entry is warmed first and without delay, because a player
-- is waiting on it. Everything else is a prefetch and can take its time.
function RobloxGroupService:Warm(player: Player)
	local gate = self.context.Configuration.ExperienceAccess.RequiredGroupLinkId
	if gate and self.context.Configuration.GroupLinks[gate] then
		self:GetMembership(player, gate)
	end
	for linkId in self.context.Configuration.GroupLinks do
		if not player:IsDescendantOf(Players) then
			return
		end
		if linkId ~= gate then
			-- Jittered so that several players joining together do not line their
			-- lookups up with each other and rebuild the burst.
			task.wait(self.settings.WarmSpacingSeconds * (0.5 + math.random()))
			if not player:IsDescendantOf(Players) then
				return
			end
			self:GetMembership(player, linkId)
		end
	end
end

function RobloxGroupService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.cache[player.UserId] = nil
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				self:Warm(player)
			end)
		end)
	)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Warm(player)
		end)
	end
end

function RobloxGroupService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cache)
end

return RobloxGroupService
