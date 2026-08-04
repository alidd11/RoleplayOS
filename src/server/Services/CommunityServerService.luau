--!strict

local CommunityServerService = {}

function CommunityServerService:Init(context: any)
	self.context = context
end

-- Which of the three products this server is.
--
-- Resolved on demand rather than at startup. A reserved server learns which
-- official entry it is from the first arrival's teleport data, so a value fixed
-- in Init would always have been computed before there was anything to read.
--
--   Public       the published place, open to everyone, roles bought
--   Whitelisted  an official server gated on a group, roles applied for
--   Private      somebody's own private server, their own rules
--   Reserved     a reserved server that is not a configured official entry
function CommunityServerService:Kind(): string
	if game.PrivateServerId == "" then
		return if self:RequiredGroupLinkId() then "Whitelisted" else "Public"
	end
	if game.PrivateServerOwnerId ~= 0 then
		return "Private"
	end
	return if self:RequiredGroupLinkId() then "Whitelisted" else "Reserved"
end

-- The group this particular server gates entry on, if any.
--
-- An official entry names its own, which is what makes the whitelisted community
-- whitelisted without closing the public place. The experience wide setting is
-- still honoured when it is switched on, for a deployment that wants every
-- server gated.
function CommunityServerService:RequiredGroupLinkId(): string?
	local fromServer = self.context.Services:Get("OfficialServerService"):RequiredGroupLinkId()
	if fromServer then
		return fromServer
	end
	local access = self.context.Configuration.ExperienceAccess
	if access.Enabled == true and type(access.RequiredGroupLinkId) == "string" then
		return access.RequiredGroupLinkId
	end
	return nil
end

-- The group entry to this server is gated on, when it is gated at all.
function CommunityServerService:AccessGroup(): any?
	local linkId = self:RequiredGroupLinkId()
	if not linkId then
		return nil
	end
	return self.context.Configuration.GroupLinks[linkId]
end

function CommunityServerService:GetServerContext(player: Player): any
	local group = self:AccessGroup()
	local kind = self:Kind()
	return {
		Kind = kind,
		PrivateServerOwnerId = if kind == "Private" then game.PrivateServerOwnerId else nil,
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
