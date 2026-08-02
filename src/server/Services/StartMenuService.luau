--!strict
local StartMenuService = {}
function StartMenuService:Init(context: any)
	self.context = context
end
function StartMenuService:Start() end
function StartMenuService:Build(player: Player): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local roles = {}
	for _, role in self.context.Configuration.Roles do
		local access = self.context.Services:Get("AccessService"):Evaluate(player, role.Access)
		table.insert(roles, {
			Id = role.Id,
			Name = role.Name,
			DepartmentId = role.DepartmentId,
			Visible = role.Access.DisplayWhenLocked ~= false or access.Allowed,
			Locked = not access.Allowed,
			LockType = role.Access.AccessType,
			LockMessage = access.Message,
			Action = access.ReasonCode == "GAMEPASS_REQUIRED" and "PromptGamepass"
				or access.ReasonCode == "APPLICATION_REQUIRED" and "OpenApplication"
				or "SelectRole",
			Spawns = self.context.Services
				:Get("StationService")
				:GetAvailableSpawns(role.Id, role.DepartmentId),
		})
	end
	local dutyProfiles = {}
	for _, profile in session.Profile.DutyProfiles do
		table.insert(dutyProfiles, {
			ProfileId = profile.ProfileId,
			DepartmentId = profile.DepartmentId,
			Rank = profile.Rank,
			Callsign = profile.Callsign,
		})
	end
	local slotCount = self.context.Configuration.Characters.FreeSlots
	return {
		Framework = {
			Version = "0.1-dev",
			Environment = self.context.Configuration.Framework.Environment,
		},
		Server = self.context.Services:Get("CommunityServerService"):GetServerContext(player),
		Characters = self.context.Services:Get("CharacterService"):List(player),
		DutyProfiles = dutyProfiles,
		EmptySlots = math.max(0, slotCount - #session.Profile.CharacterSlots),
		Roles = roles,
		Stations = self.context.Configuration.Stations,
		Jobs = self.context.Configuration.Jobs,
		LastCharacterId = session.Profile.AuditMetadata.LastCharacterId,
	},
		nil
end
function StartMenuService:Destroy() end
return StartMenuService
