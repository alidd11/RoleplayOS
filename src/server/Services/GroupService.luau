--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RobloxGroupService = { cache = {}, connections = {} }

function RobloxGroupService:Init(context: any)
	self.context = context
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
		self.context.Logger:Warning("Roblox group membership check failed", {
			UserId = player.UserId,
			GroupLinkId = key,
			GroupId = groupId,
		})
		local failure = {
			GroupId = groupId,
			MinimumRank = minimumRank or 1,
			Failed = true,
			ExpiresAt = os.clock() + 30,
		}
		playerCache[key] = failure
		return failure
	end
	local roleName = "Guest"
	if rank > 0 then
		local roleOk, resolvedRole = pcall(player.GetRoleInGroup, player, groupId)
		if roleOk and type(resolvedRole) == "string" then
			roleName = resolvedRole
		end
	end
	local membership = {
		GroupId = groupId,
		IsMember = rank > 0,
		HighestRank = rank,
		MinimumRank = minimumRank or 1,
		Roles = if rank > 0 then { { Name = roleName, Rank = rank } } else {},
		ExpiresAt = os.clock() + 300,
	}
	playerCache[key] = membership
	return membership
end

function RobloxGroupService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.cache[player.UserId] = nil
		end)
	)
end

function RobloxGroupService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cache)
end

return RobloxGroupService
