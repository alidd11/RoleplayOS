--!strict

local HttpService = game:GetService("HttpService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CommunityGroupPolicy = require(ReplicatedStorage.RoleplayOS.Shared.CommunityGroupPolicy)
local CommunityPolicy = require(ReplicatedStorage.RoleplayOS.Shared.CommunityPolicy)

local CommunityService = { cache = {}, activeCommunityId = nil }

function CommunityService:Init(context: any)
	self.context = context
end

function CommunityService:_template(templateId: string): any?
	return self.context.Configuration.Communities.Templates[templateId]
end

function CommunityService:_privateServerCommunityId(): string?
	if
		game.PrivateServerId == ""
		or not self.context.Configuration.Communities.AllowPrivateServerCommunities
	then
		return nil
	end
	return "private:" .. game.PrivateServerId
end

function CommunityService:Create(
	owner: Player,
	groupId: number,
	templateId: string?
): (any?, string?)
	if not self.context.Configuration.Communities.Enabled then
		return nil, "COMMUNITIES_DISABLED"
	end
	if not self:_privateServerCommunityId() or game.PrivateServerOwnerId ~= owner.UserId then
		return nil, "PRIVATE_SERVER_OWNER_REQUIRED"
	end
	if groupId <= 0 or groupId % 1 ~= 0 then
		return nil, "INVALID_COMMUNITY_GROUP"
	end
	local groupOk, groupInfo = pcall(GroupService.GetGroupInfoAsync, GroupService, groupId)
	if
		not groupOk
		or type(groupInfo) ~= "table"
		or groupInfo.Id ~= groupId
		or type(groupInfo.Name) ~= "string"
	then
		return nil, "COMMUNITY_GROUP_UNAVAILABLE"
	end
	local groupOwner = groupInfo.Owner
	if type(groupOwner) ~= "table" or groupOwner.Id ~= owner.UserId then
		return nil, "COMMUNITY_GROUP_OWNER_REQUIRED"
	end
	local selectedTemplateId = templateId
		or self.context.Configuration.Communities.DefaultTemplateId
	local template = self:_template(selectedTemplateId)
	if not template then
		return nil, "COMMUNITY_TEMPLATE_NOT_FOUND"
	end
	local communityId = self:_privateServerCommunityId() or HttpService:GenerateGUID(false)
	local now = os.time()
	local record, problem = self.context.Services
		:Get("DataService")
		:UpdateCommunity(communityId, function(existing)
			if existing then
				error("COMMUNITY_ALREADY_EXISTS")
			end
			return {
				CommunityId = communityId,
				Name = groupInfo.Name,
				OwnerUserId = owner.UserId,
				RobloxGroup = {
					GroupId = groupId,
					Name = groupInfo.Name,
					EmblemUrl = groupInfo.EmblemUrl,
					OwnerUserId = owner.UserId,
				},
				TemplateId = selectedTemplateId,
				CreatedAt = now,
				UpdatedAt = now,
				Policies = table.clone(template.DefaultPolicies),
				Branding = {},
				Members = {
					[tostring(owner.UserId)] = {
						CommunityId = communityId,
						RoleId = "Owner",
						Status = "Active",
						JoinedAt = now,
						UpdatedAt = now,
					},
				},
				Version = 1,
			}
		end)
	if not record then
		return nil, problem
	end
	self.cache[communityId] = record
	self.activeCommunityId = communityId
	local session = self.context.Services:Get("DataService"):GetSession(owner)
	if session then
		session.Profile.Communities[communityId] = record.Members[tostring(owner.UserId)]
		self.context.Services:Get("DataService"):MarkDirty(owner)
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = owner.UserId,
		Action = "Community.Created",
		Target = communityId,
		Metadata = { TemplateId = selectedTemplateId, GroupId = groupId },
	})
	return record, nil
end

function CommunityService:Get(communityId: string): (any?, string?)
	if self.cache[communityId] then
		return self.cache[communityId], nil
	end
	local record, problem = self.context.Services:Get("DataService"):GetCommunity(communityId)
	if record then
		self.cache[communityId] = record
	end
	return record, problem
end

function CommunityService:GetMembership(player: Player, communityId: string): any?
	local community = self.cache[communityId]
	if community and community.RobloxGroup then
		local membership = self.context.Services
			:Get("GroupService")
			:GetMembershipByGroupId(player, community.RobloxGroup.GroupId)
		if membership.Failed or membership.NotConfigured or not membership.IsMember then
			return nil
		end
		local selectedRoleId = CommunityGroupPolicy.resolveRole(
			membership.HighestRank,
			self.context.Configuration.Communities.GroupRoleRanks
		)
		if not selectedRoleId then
			return nil
		end
		return {
			CommunityId = communityId,
			RoleId = selectedRoleId,
			Status = "Active",
			GroupRank = membership.HighestRank,
		}
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session and session.Profile.Communities[communityId]
end

function CommunityService:HasPermission(
	player: Player,
	permission: string,
	communityId: string?
): boolean
	local id = communityId or self.activeCommunityId
	if not id then
		return false
	end
	local community = self.cache[id]
	local template = community and self:_template(community.TemplateId)
	return template ~= nil
		and CommunityPolicy.hasPermission(template, self:GetMembership(player, id), permission)
end

function CommunityService:PublicSummary(player: Player): any?
	local id = self.activeCommunityId
	local community = id and self.cache[id]
	if not community then
		return nil
	end
	local membership = self:GetMembership(player, id)
	return {
		CommunityId = community.CommunityId,
		Name = community.Name,
		TemplateId = community.TemplateId,
		RobloxGroup = community.RobloxGroup and {
			GroupId = community.RobloxGroup.GroupId,
			Name = community.RobloxGroup.Name,
			EmblemUrl = community.RobloxGroup.EmblemUrl,
		} or nil,
		Policies = community.Policies,
		Membership = membership and { RoleId = membership.RoleId, Status = membership.Status }
			or nil,
		CanManage = self:HasPermission(player, "Community.Manage", id),
	}
end

function CommunityService:Invite(
	actor: Player,
	targetUserId: number,
	roleId: string?
): (boolean, string?)
	local communityId = self.activeCommunityId
	local community = communityId and self.cache[communityId]
	if not community or not self:HasPermission(actor, "Members.Manage", communityId) then
		return false, "COMMUNITY_PERMISSION_DENIED"
	end
	if community.RobloxGroup then
		return false, "COMMUNITY_MEMBERSHIP_MANAGED_BY_ROBLOX_GROUP"
	end
	local template = self:_template(community.TemplateId)
	local selectedRoleId = roleId or template.DefaultMemberRoleId
	local selectedRole = template.Roles[selectedRoleId]
	local actorMembership = self:GetMembership(actor, communityId)
	if
		not selectedRole
		or selectedRole.Priority >= template.Roles[actorMembership.RoleId].Priority
	then
		return false, "COMMUNITY_ROLE_NOT_ASSIGNABLE"
	end
	local memberCount = 0
	for _ in community.Members do
		memberCount += 1
	end
	if memberCount >= template.MaximumMembers then
		return false, "COMMUNITY_MEMBER_LIMIT"
	end
	local now = os.time()
	local updated, problem = self.context.Services
		:Get("DataService")
		:UpdateCommunity(communityId, function(stored)
			stored.Members[tostring(targetUserId)] = {
				CommunityId = communityId,
				RoleId = selectedRoleId,
				Status = "Invited",
				UpdatedAt = now,
			}
			stored.UpdatedAt = now
			stored.Version += 1
			return stored
		end)
	if not updated then
		return false, problem
	end
	self.cache[communityId] = updated
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Community.MemberInvited",
		Target = tostring(targetUserId),
		Metadata = { CommunityId = communityId, RoleId = selectedRoleId },
	})
	return true, nil
end

function CommunityService:RespondToInvite(
	player: Player,
	communityId: string,
	accept: boolean
): (boolean, string?)
	local community = self:Get(communityId)
	if community and community.RobloxGroup then
		return false, "COMMUNITY_MEMBERSHIP_MANAGED_BY_ROBLOX_GROUP"
	end
	local invitation = community and community.Members[tostring(player.UserId)]
	if not invitation or invitation.Status ~= "Invited" then
		return false, "COMMUNITY_INVITE_NOT_FOUND"
	end
	local newStatus = if accept then "Active" else "Declined"
	local now = os.time()
	local updated, problem = self.context.Services
		:Get("DataService")
		:UpdateCommunity(communityId, function(stored)
			if
				not stored.Members[tostring(player.UserId)]
				or stored.Members[tostring(player.UserId)].Status ~= "Invited"
			then
				error("COMMUNITY_INVITE_CHANGED")
			end
			if accept then
				stored.Members[tostring(player.UserId)].Status = "Active"
				stored.Members[tostring(player.UserId)].JoinedAt = now
				stored.Members[tostring(player.UserId)].UpdatedAt = now
			else
				stored.Members[tostring(player.UserId)] = nil
			end
			stored.UpdatedAt = now
			stored.Version += 1
			return stored
		end)
	if not updated then
		return false, problem
	end
	self.cache[communityId] = updated
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if session then
		if accept then
			session.Profile.Communities[communityId] = updated.Members[tostring(player.UserId)]
		else
			session.Profile.Communities[communityId] = nil
		end
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Community.Invite" .. newStatus,
		Target = communityId,
		Metadata = {},
	})
	return true, nil
end

function CommunityService:Start()
	local privateId = self:_privateServerCommunityId()
	if privateId then
		local community = self:Get(privateId)
		if community then
			self.activeCommunityId = privateId
		elseif game.PrivateServerOwnerId > 0 then
			self.context.Logger:Info("Private server is ready to create a community", {
				OwnerUserId = game.PrivateServerOwnerId,
			})
		end
	end
end

function CommunityService:Destroy()
	table.clear(self.cache)
end

return CommunityService
