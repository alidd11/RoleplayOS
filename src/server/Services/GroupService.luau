--!strict

local GroupService = game:GetService("GroupService")
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
	if cached and (not cached.RetryAfter or os.clock() < cached.RetryAfter) then
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
	local ok, result =
		pcall(GroupService.GetRolesInGroupAsync, GroupService, player.UserId, groupId)
	if not ok or type(result) ~= "table" then
		self.context.Logger:Warning("Roblox group membership check failed", {
			UserId = player.UserId,
			GroupLinkId = key,
			GroupId = groupId,
		})
		local failure = {
			GroupId = groupId,
			MinimumRank = minimumRank or 1,
			Failed = true,
			RetryAfter = os.clock() + 30,
		}
		playerCache[key] = failure
		return failure
	end
	local highestRank = 0
	local roles = if type(result.Roles) == "table" then result.Roles else {}
	for _, role in roles do
		if type(role.Rank) == "number" then
			highestRank = math.max(highestRank, role.Rank)
		end
	end
	local membership = {
		GroupId = groupId,
		IsMember = result.IsMember == true,
		HighestRank = highestRank,
		MinimumRank = minimumRank or 1,
		Roles = roles,
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
