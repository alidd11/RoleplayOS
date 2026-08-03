--!strict

local CommunityServerService = {}

function CommunityServerService:Init(context: any)
	self.context = context
	-- A public server that gates entry on a Roblox group is not the same product
	-- as an open one: it is the whitelisted tier, where emergency services are
	-- group locked. Reporting it as merely Public left the interface unable to
	-- tell a player which of the three they had joined.
	local restricted = self.context.Configuration.ExperienceAccess.Enabled == true
		and self.context.Configuration.ExperienceAccess.RequiredGroupLinkId ~= nil
	self.kind = if game.PrivateServerId == ""
		then (if restricted then "Whitelisted" else "Public")
		elseif game.PrivateServerOwnerId == 0 then "Reserved"
		else "Private"
end

-- The group entry to this experience is gated on, when it is gated at all.
function CommunityServerService:AccessGroup(): any?
	local access = self.context.Configuration.ExperienceAccess
	if access.Enabled ~= true or type(access.RequiredGroupLinkId) ~= "string" then
		return nil
	end
	return self.context.Configuration.GroupLinks[access.RequiredGroupLinkId]
end

function CommunityServerService:GetServerContext(player: Player): any
	local group = self:AccessGroup()
	return {
		Kind = self.kind,
		PrivateServerOwnerId = if self.kind == "Private" then game.PrivateServerOwnerId else nil,
		Community = self.context.Services:Get("CommunityService"):PublicSummary(player),
		-- Named so the interface can say which community the whitelist belongs
		-- to rather than stating that one exists.
		AccessGroupName = group and group.DisplayName or nil,
	}
end

function CommunityServerService:CanJoin(player: Player): (boolean, string?)
	local service = self.context.Services:Get("CommunityService")
	local communityId = service.activeCommunityId
	if not communityId then
		return true, nil
	end
	local community = service.cache[communityId]
	local membership = service:GetMembership(player, communityId)
	if membership and membership.Status == "Banned" then
		return false, "COMMUNITY_BANNED"
	end
	if membership and membership.Status == "Suspended" then
		return false, "COMMUNITY_SUSPENDED"
	end
	if
		community.Policies.RequireCommunityMembership
		and (not membership or membership.Status ~= "Active")
	then
		return false, "COMMUNITY_MEMBERSHIP_REQUIRED"
	end
	return true, nil
end

function CommunityServerService:Start() end
function CommunityServerService:Destroy() end

return CommunityServerService
