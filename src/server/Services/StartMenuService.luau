--!strict
local StartMenuService = {}
function StartMenuService:Init(context: any)
	self.context = context
end
function StartMenuService:Start() end

function StartMenuService:_ensureDutyProfile(player: Player, session: any, departmentId: string)
	if type(departmentId) ~= "string" or departmentId == "" then
		return
	end
	for _, profile in session.Profile.DutyProfiles do
		if profile.DepartmentId == departmentId then
			return
		end
	end
	local profileId = "Auto_" .. departmentId
	session.Profile.DutyProfiles[profileId] = {
		ProfileId = profileId,
		DepartmentId = departmentId,
		Rank = 1,
		QualificationIds = {},
		-- Left unset here. The shoulder number is issued on first going on duty,
		-- by the service that owns the counter, so that it is unique across every
		-- server rather than derived from the user id. Deriving it collided:
		-- UserId % 100 gave a hundred numbers per department and two officers on
		-- the same number the moment a department passed that many members.
		Callsign = nil,
	}
	self.context.Services:Get("DataService"):MarkDirty(player)
end

function StartMenuService:Build(player: Player): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local roles = {}
	for _, role in self.context.Configuration.Roles do
		-- PoliceOfficer is retained in configuration as a compatibility alias for
		-- older duty records. Frontline Policing is the single player-facing base
		-- police role, so sending both would render a duplicate choice.
		if role.Id == "PoliceOfficer" then
			continue
		end
		local access = self.context.Services:Get("AccessService"):Evaluate(player, role.Access)
		if access.Allowed then
			self:_ensureDutyProfile(player, session, role.DepartmentId)
		end
		table.insert(roles, {
			Id = role.Id,
			Name = role.Name,
			DepartmentId = role.DepartmentId,
			UniformId = role.UniformId,
			Visible = role.Access.DisplayWhenLocked ~= false or access.Allowed,
			Locked = not access.Allowed,
			LockType = role.Access.AccessType,
			LockMessage = access.Message,
			-- Only send the entitlement identifier required by the client purchase
			-- prompt. The server remains authoritative and re-evaluates ownership;
			-- exposing this ID never grants the role by itself.
			GamepassId = access.Metadata and access.Metadata.GamepassId,
			Action = access.ReasonCode == "GAMEPASS_REQUIRED" and "PromptGamepass"
				or access.ReasonCode == "APPLICATION_REQUIRED" and "OpenApplication"
				or "SelectRole",
			Spawns = self.context.Services
				:Get("StationService")
				:GetAvailableSpawns(role.Id, role.DepartmentId),
			PreviewUniform = if role.UniformId
				then (function()
					local uniform = self.context.Configuration.Uniforms[role.UniformId]
					if not uniform then
						return nil
					end
					return {
						ShirtTemplate = uniform.ShirtTemplate,
						TrousersTemplate = uniform.TrousersTemplate,
					}
				end)()
				else nil,
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
	local slotCount = self.context.Services:Get("CharacterService"):SlotAllowance(session)
	local server = self.context.Services:Get("ServerModeService"):GetServerContext(player)
	local gamepasses = {}
	for definitionId, definition in self.context.Configuration.Gamepasses do
		local gamepassId = definition.GamepassId
		local configured = type(gamepassId) == "number" and gamepassId > 0
		local publicTeam = string.sub(definitionId, 1, 6) == "Public"
		table.insert(gamepasses, {
			Id = definitionId,
			GamepassId = if configured then gamepassId else nil,
			Name = definition.Name,
			Description = definition.Description,
			-- Artwork is presentation data only. The entitlement still uses the
			-- server-owned GamepassId and is rechecked before access is granted.
			ImageAssetId = definition.ImageAssetId or definition.IconAssetId,
			PriceInRobux = definition.PriceInRobux,
			Configured = configured,
			Owned = configured and session.Profile.GamepassCache[tostring(gamepassId)] == true,
			AvailableInServer = not publicTeam or server.Kind == "Public",
			Category = if publicTeam
				then "Public teams"
				elseif string.find(definitionId, "Civilian", 1, true) then "Civilian equipment"
				else "Upgrades",
		})
	end
	if server.Kind == "Public" then
		for _, definition in self.context.Configuration.Custody.PublicEarlyRelease.Products do
			local configured = type(definition.ProductId) == "number" and definition.ProductId > 0
			table.insert(gamepasses, {
				Id = "EarlyRelease_" .. definition.Id,
				ProductId = if configured then definition.ProductId else nil,
				PurchaseType = "DeveloperProduct",
				Name = definition.Name,
				Description = definition.Description,
				PriceInRobux = definition.PriceRobux,
				Configured = configured,
				Owned = false,
				AvailableInServer = true,
				Category = "Custody credits",
			})
		end
	end
	table.sort(gamepasses, function(a, b)
		if a.Category == b.Category then
			return a.Name < b.Name
		end
		return a.Category < b.Category
	end)
	return {
		Framework = {
			Version = "0.1-dev",
			Environment = self.context.Configuration.Framework.Environment,
			GameName = self.context.Configuration.Framework.Branding.GameName ~= ""
					and self.context.Configuration.Framework.Branding.GameName
				or game.Name,
			ShowRoleplayOSMark = self.context.Configuration.Framework.Branding.ShowRoleplayOSMark,
		},
		Server = server,
		Characters = self.context.Services:Get("CharacterService"):List(player),
		DutyProfiles = dutyProfiles,
		EmptySlots = math.max(0, slotCount - #session.Profile.CharacterSlots),
		Roles = roles,
		Gamepasses = gamepasses,
		Stations = self.context.Configuration.Stations,
		Jobs = self.context.Configuration.Jobs,
		LastCharacterId = session.Profile.AuditMetadata.LastCharacterId,
	},
		nil
end
function StartMenuService:Destroy() end
return StartMenuService
