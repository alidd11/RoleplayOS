--!strict

local CommunityServerService = {}

function CommunityServerService:Init(context: any)
	self.context = context
	self.kind = if game.PrivateServerId == ""
		then "Public"
		elseif game.PrivateServerOwnerId == 0 then "Reserved"
		else "Private"
end

function CommunityServerService:GetServerContext(player: Player): any
	return {
		Kind = self.kind,
		PrivateServerOwnerId = if self.kind == "Private" then game.PrivateServerOwnerId else nil,
		Community = self.context.Services:Get("CommunityService"):PublicSummary(player),
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
