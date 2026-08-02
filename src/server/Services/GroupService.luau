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
	local playerCache = self.cache[player.UserId]
	if not playerCache then
		playerCache = {}
		self.cache[player.UserId] = playerCache
	end
	if playerCache[linkId] then
		return playerCache[linkId]
	end
	if
		RunService:IsStudio()
		and self.context.Configuration.Framework.GrantMockEmergencyAccessInStudio
	then
		local mock = {
			GroupId = definition.GroupId,
			IsMember = true,
			HighestRank = 255,
			MinimumRank = definition.MinimumRank,
			Roles = { { Id = 0, Name = "Studio Owner", Rank = 255 } },
			Mock = true,
		}
		playerCache[linkId] = mock
		return mock
	end
	if definition.GroupId <= 0 then
		local unconfigured = {
			GroupId = definition.GroupId,
			MinimumRank = definition.MinimumRank,
			NotConfigured = true,
		}
		playerCache[linkId] = unconfigured
		return unconfigured
	end
	local ok, result =
		pcall(GroupService.GetRolesInGroupAsync, GroupService, player.UserId, definition.GroupId)
	if not ok or type(result) ~= "table" then
		self.context.Logger:Warning("Roblox group membership check failed", {
			UserId = player.UserId,
			GroupLinkId = linkId,
			GroupId = definition.GroupId,
		})
		return {
			GroupId = definition.GroupId,
			MinimumRank = definition.MinimumRank,
			Failed = true,
		}
	end
	local highestRank = 0
	local roles = if type(result.Roles) == "table" then result.Roles else {}
	for _, role in roles do
		if type(role.Rank) == "number" then
			highestRank = math.max(highestRank, role.Rank)
		end
	end
	local membership = {
		GroupId = definition.GroupId,
		IsMember = result.IsMember == true,
		HighestRank = highestRank,
		MinimumRank = definition.MinimumRank,
		Roles = roles,
	}
	playerCache[linkId] = membership
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
