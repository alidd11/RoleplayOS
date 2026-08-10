--!strict

-- RoleplayOS currently supports exactly two deployments: Public and
-- Whitelisted. Roblox private/reserved instances inherit the mode of their
-- configured place; they are not user-operated communities.
local ServerModeService = { Critical = true }

function ServerModeService:Init(context: any)
	self.context = context
end

function ServerModeService:RequiredGroupLinkId(): string?
	-- OfficialServerService learns the identity of reserved same-place worlds
	-- from trusted teleport data. Looking only at game.PlaceId made those worlds
	-- load whitelisted profiles while every gameplay service treated them as
	-- Public. Use the single authoritative resolver whenever it is available.
	local officialService = self.context.Services:Get("OfficialServerService")
	local officialLinkId = officialService:RequiredGroupLinkId()
	if type(officialLinkId) == "string" and officialLinkId ~= "" then
		return officialLinkId
	end
	local entries = self.context.Configuration.OfficialServers.Entries
	for _, entry in entries do
		if
			entry.Whitelisted == true
			and tonumber(entry.PlaceId) == game.PlaceId
			and type(entry.RequiredGroupLinkId) == "string"
		then
			return entry.RequiredGroupLinkId
		end
	end
	local access = self.context.Configuration.ExperienceAccess
	if access.Enabled == true and type(access.RequiredGroupLinkId) == "string" then
		return access.RequiredGroupLinkId
	end
	return nil
end

function ServerModeService:Kind(): string
	return if self:RequiredGroupLinkId() then "Whitelisted" else "Public"
end

function ServerModeService:AccessGroup(): any?
	local linkId = self:RequiredGroupLinkId()
	return if linkId then self.context.Configuration.GroupLinks[linkId] else nil
end

function ServerModeService:GetServerContext(_player: Player): any
	local group = self:AccessGroup()
	return {
		Kind = self:Kind(),
		AccessGroupName = group and group.DisplayName or nil,
	}
end

function ServerModeService:CanJoin(_player: Player): (boolean, string?)
	return true, nil
end

function ServerModeService:Start() end
function ServerModeService:Destroy() end

return ServerModeService
