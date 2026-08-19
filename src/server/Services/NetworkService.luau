--!strict
local NetworkService = { Critical = true }
local function tablePayload(value: any): (boolean, string?)
	return type(value) == "table", "EXPECTED_TABLE"
end
local function boundedStringArray(value: any, maximum: number): boolean
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, item in value do
		count += 1
		if count > maximum or type(key) ~= "number" or type(item) ~= "string" then
			return false
		end
	end
	return true
end
function NetworkService:Init(context: any)
	self.context = context
end
function NetworkService:Start()
	local access = self.context.Services:Get("ExperienceAccessService")
	self.context.Network:SetAuthorizer(function(player)
		return access:IsVerified(player)
	end)
	self.context.Network:RegisterFunction("DropCash", function(payload)
		return type(payload) == "table" and type(payload.Amount) == "number"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("MoneyDropService"):Drop(player, payload.Amount)
		local messages = {
			INVALID_AMOUNT = "Enter a valid cash amount.",
			WHOLE_AMOUNT_REQUIRED = "Cash can only be dropped in whole pounds.",
			DROP_TOO_SMALL = "That amount is too small to drop.",
			DROP_TOO_LARGE = "That amount is above the cash drop limit.",
			INSUFFICIENT_FUNDS = "You do not have enough cash.",
			TOO_MANY_ACTIVE_DROPS = "Pick up an existing cash drop before making another.",
			SERVER_DROP_LIMIT = "There are too many cash drops in the area. Try again shortly.",
			CHARACTER_UNAVAILABLE = "Your character cannot drop cash right now.",
			CIVILIAN_REQUIRED = "Finish your service duty before dropping cash.",
		}
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then "Cash dropped."
				else (reason and messages[reason]) or "Cash could not be dropped.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetFrameworkStatus",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = {
					Framework = "RoleplayOS",
					Version = "0.1-dev",
					SchemaVersion = self.context.Configuration.Framework.SchemaVersion,
					Server = self.context.Services
						:Get("ServerModeService")
						:GetServerContext(player),
					Capabilities = {
						"Characters",
						"Access control",
						"Economy",
						"Jobs and applications",
						"Vehicles",
						"Properties and furniture",
						"Emergency services",
						"MDT and dispatch",
						"Mobile phone",
					},
				},
				RequestId = requestId,
			}
		end
	)
	-- Read-only roster for staff reconciling Discord display names against the
	-- game. Registered here with every other endpoint so it is covered by the
	-- rate-limit check, which only inspects this file.
	self.context.Network:RegisterFunction("GetShoulderNumberRoster", function(payload)
		return payload == nil or type(payload) == "table"
	end, function(player, _, requestId)
		local roster, reason = self.context.Services:Get("ShoulderNumberService"):RosterFor(player)
		if not roster then
			return {
				Success = false,
				Code = reason or "ROSTER_NOT_AUTHORISED",
				Message = "A management rank is required to read a roster.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = roster,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetOfficialServers", function(payload)
		return payload == nil or type(payload) == "table"
	end, function(_, _, requestId)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = {
				Servers = self.context.Services:Get("OfficialServerService"):List(),
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("JoinOfficialServer", function(payload)
		return type(payload) == "table" and type(payload.ServerId) == "string"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("OfficialServerService"):Join(player, payload.ServerId)
		if not result then
			return {
				Success = false,
				Code = reason or "OFFICIAL_SERVER_UNAVAILABLE",
				Message = if reason == "ALREADY_ON_THIS_SERVER"
					then "You are already on this server."
					elseif
						reason == "PROFILE_BUSY"
					then "Your progress is still saving. Try again in a moment."
					elseif
						reason == "OFFICIAL_SERVER_FULL"
					then "Every instance of that server is full. Try again shortly."
					else "That server could not be joined right now.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Connecting…",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetVehicleLights", function(payload)
		return type(payload) == "table" and type(payload.Action) == "string"
	end, function(player, payload, requestId)
		local ok, reason = self.context.Services:Get("VehicleLightingService"):Set(player, payload)
		if not ok then
			return {
				Success = false,
				Code = reason,
				Message = if reason == "NOT_DRIVING"
					then "You are not driving a vehicle."
					else "That control does not exist.",
				RequestId = requestId,
			}
		end
		return { Success = true, Code = "OK", Message = "", RequestId = requestId }
	end)

	self.context.Network:RegisterFunction("SetEmergencyLights", function(payload)
		return type(payload) == "table"
			and (payload.Stage == nil or type(payload.Stage) == "number")
			and (payload.Lights == nil or type(payload.Lights) == "boolean")
			and (payload.Siren == nil or type(payload.Siren) == "string")
			and (payload.Circuit == nil or type(payload.Circuit) == "string")
			and (payload.Enabled == nil or type(payload.Enabled) == "boolean")
			and (payload.RunLock == nil or type(payload.RunLock) == "boolean")
			and (payload.LowPower == nil or type(payload.LowPower) == "boolean")
			and (payload.Reset == nil or type(payload.Reset) == "boolean")
			and (payload.Director == nil or type(payload.Director) == "string")
	end, function(player, payload, requestId)
		local ok, reason = self.context.Services:Get("EmergencyLightsService"):Set(player, payload)
		if not ok then
			local messages = {
				NOT_DRIVING = "You are not driving a vehicle.",
				VEHICLE_HAS_NO_LIGHTS = "This vehicle has no warning lights.",
				NOT_ON_DUTY = "You are not on duty.",
				DEPARTMENT_HAS_NO_LIGHTS = "Your department does not run warning lights.",
				ROLE_HAS_NO_LIGHTS = "Your role does not run warning lights.",
				LIGHTS_DISABLED = "Emergency lighting is switched off on this server.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "The lights could not be changed.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = self.context.Services:Get("EmergencyLightsService"):GetState(player),
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetEmergencyLights", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = self.context.Services:Get("EmergencyLightsService"):GetState(player),
			RequestId = requestId,
		}
	end)

	self.context.Network:RegisterFunction("BeginDuty", function(payload)
		return type(payload) == "table"
			and type(payload.DutyProfileId) == "string"
			and type(payload.RoleId) == "string"
			and type(payload.StationId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
		local started, reason = self.context.Services:Get("DutyService"):Begin(player, payload)
		if not started then
			local messages = {
				SPAWN_POINT_UNAVAILABLE = "That team's spawn pad is missing or not configured.",
				SPAWN_ROLE_NOT_ALLOWED = "That role cannot use the selected spawn point.",
				SPAWN_TEAM_MISMATCH = "The spawn pad does not match the selected team.",
				DUTY_PROFILE_NOT_FOUND = "Your duty profile is not ready. Reopen the menu and try again.",
				TEAM_NOT_CONFIGURED = "That Roblox Team is not configured.",
				ACTIVE_CUSTODY_SENTENCE = "You cannot report for duty during an active custody sentence.",
				NO_ACTIVE_CHARACTER = "Create and select a character before reporting for duty.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "Duty could not be started.",
				RequestId = requestId,
			}
		end
		-- Read from the role rather than from the duty record, which would mean
		-- asking DutyService and that yields on a group check.
		local role = self.context.Configuration.Roles[payload.RoleId]
		return {
			Success = true,
			Code = "OK",
			Message = "You are now on duty.",
			-- The department travels with the response. The custody panel gates on
			-- it, and without it that gate was never satisfied, so the whole
			-- booking workflow had no way to be opened by anybody.
			Data = {
				RoleId = payload.RoleId,
				StationId = payload.StationId,
				SpawnId = payload.SpawnId,
				DepartmentId = role and role.DepartmentId,
				DivisionId = role and role.DivisionId,
				TeamName = role and role.TeamName,
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioSetCallsign", function(payload)
		return type(payload) == "table" and type(payload.Callsign) == "string"
	end, function(player, payload, requestId)
		local callsign, reason =
			self.context.Services:Get("DutyService"):SetCallsign(player, payload.Callsign)
		return {
			Success = callsign ~= nil,
			Code = if callsign then "OK" else reason,
			Message = if callsign then "Callsign updated." else "Enter a valid callsign.",
			Data = if callsign then { Callsign = callsign } else nil,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PAVASpray", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local sprayed, reason =
			self.context.Services:Get("PAVAService"):Spray(player, payload.TargetUserId)
		local messages = {
			POLICE_DUTY_REQUIRED = "PAVA is restricted to police officers on duty.",
			PAVA_NOT_EQUIPPED = "Equip your issued PAVA before using it.",
			PAVA_COOLDOWN = "PAVA is cooling down.",
			PAVA_TARGET_INVALID = "That target cannot be sprayed.",
			PAVA_TARGET_OUT_OF_RANGE = "The target is out of range.",
		}
		return {
			Success = sprayed,
			Code = if sprayed then "OK" else reason,
			Message = if sprayed
				then "PAVA deployed."
				else (messages[reason] or "PAVA could not be deployed."),
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("EnterCivilian", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
		self.context.Services:Get("DutyService"):End(player)
		local entered, reason = self.context.Services
			:Get("SpawnService")
			:EnterCivilian(player, payload.CharacterId, payload.SpawnId)
		if not entered then
			return {
				Success = false,
				Code = reason,
				Message = "The civilian spawn could not be completed.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Welcome to the city.",
			Data = { SpawnId = payload.SpawnId },
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("EnterCivilianAtGangTerritory", function(payload)
		return type(payload) == "table" and type(payload.CharacterId) == "string"
	end, function(player, payload, requestId)
		self.context.Services:Get("DutyService"):End(player)
		local entered, reason = self.context.Services
			:Get("SpawnService")
			:EnterCivilianAtTerritory(player, payload.CharacterId)
		if not entered then
			local messages = {
				NOT_IN_A_GANG = "You are not in a gang.",
				GANG_HAS_NO_TERRITORY = "Your gang does not hold a territory.",
				TERRITORY_UNAVAILABLE = "That territory is not available right now.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason])
					or "Could not spawn at your gang's territory.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Welcome to your turf.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetSettings",
		tablePayload,
		function(player, _, requestId)
			local settings, reason = self.context.Services:Get("SettingsService"):Get(player)
			if not settings then
				return {
					Success = false,
					Code = reason,
					Message = "Settings are unavailable.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = settings,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetProgression",
		tablePayload,
		function(player, payload, requestId)
			local characterId = if type(payload.CharacterId) == "string"
				then payload.CharacterId
				else nil
			local summary, reason =
				self.context.Services:Get("ProgressionService"):Get(player, characterId)
			if not summary then
				return {
					Success = false,
					Code = reason,
					Message = "Progression is unavailable.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = summary,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetPublicProgressionHud",
		tablePayload,
		function(player, _, requestId)
			local hud, reason = self.context.Services:Get("ProgressionService"):GetPublicHud(player)
			if not hud then
				return {
					Success = false,
					Code = reason,
					Message = "Public progression is not available here.",
					RequestId = requestId,
				}
			end
			return { Success = true, Code = "OK", Message = "", Data = hud, RequestId = requestId }
		end
	)
	self.context.Network:RegisterFunction(
		"UpdateSettings",
		tablePayload,
		function(player, payload, requestId)
			local settings, reason =
				self.context.Services:Get("SettingsService"):Update(player, payload)
			if not settings then
				return {
					Success = false,
					Code = reason,
					Message = "That setting could not be saved.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "Settings saved.",
				Data = settings,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetStartMenu",
		tablePayload,
		function(player, _, requestId)
			local data, reason = self.context.Services:Get("StartMenuService"):Build(player)
			if not data then
				return {
					Success = false,
					Code = reason,
					Message = "The start menu is unavailable.",
					RequestId = requestId,
				}
			end
			return { Success = true, Code = "OK", Message = "", Data = data, RequestId = requestId }
		end
	)
	self.context.Network:RegisterFunction("CreateCharacter", function(payload)
		return type(payload) == "table" and type(payload.Identity) == "table"
	end, function(player, payload, requestId)
		local summary, reason =
			self.context.Services:Get("CharacterService"):Create(player, payload.Identity)
		if not summary then
			local messages = {
				INVALID_NAME = "Use 2-24 letters for both names.",
				INVALID_DATE_OF_BIRTH = "Enter the date of birth as YYYY-MM-DD.",
				AGE_OUT_OF_RANGE = "This character does not meet the configured age requirement.",
				NO_CHARACTER_SLOT = "All available character slots are already in use.",
				PROFILE_UNAVAILABLE = "Your profile is still loading. Try again in a moment.",
				TEXT_FILTER_TIMEOUT = "Roblox moderation did not respond. Please try again.",
				TEXT_FILTER_UNAVAILABLE = "Roblox could not approve that name. Try another name.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "The character could not be created.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Character created.",
			Data = summary,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SelectCharacter", function(payload)
		return type(payload) == "table" and type(payload.CharacterId) == "string",
			"INVALID_CHARACTER_ID"
	end, function(player, payload, requestId)
		local character, reason =
			self.context.Services:Get("CharacterService"):Select(player, payload.CharacterId)
		if not character then
			return {
				Success = false,
				Code = reason,
				Message = "The character could not be selected.",
				RequestId = requestId,
			}
		end
		self.context.Services:Get("DutyService"):End(player)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = { CharacterId = character.CharacterId },
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SaveCivilianAppearance", function(payload)
		return type(payload) == "table" and type(payload.CharacterId) == "string"
	end, function(player, payload, requestId)
		local saved, reason = self.context.Services
			:Get("CharacterService")
			:SaveCurrentAppearance(player, payload.CharacterId)
		local messages = {
			CHARACTER_NOT_ACTIVE = "Select this character before saving its outfit.",
			CIVILIAN_REQUIRED = "Save civilian outfits only while playing as a civilian.",
			CHARACTER_UNAVAILABLE = "Your character is not ready yet.",
			APPEARANCE_UNAVAILABLE = "Your current avatar outfit is not ready yet.",
		}
		return {
			Success = saved,
			Code = if saved then "OK" else reason,
			Message = if saved
				then "Civilian outfit saved."
				else (reason and messages[reason]) or "The civilian outfit could not be saved.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetAvatarCatalogCategories", function(payload)
		return type(payload) == "table"
	end, function(_player, _payload, requestId)
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = { Categories = self.context.Services:Get("AvatarCatalogService"):Categories() },
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SearchAvatarCatalog", function(payload)
		return type(payload) == "table" and type(payload.CategoryId) == "string"
	end, function(_player, payload, requestId)
		local results, reason = self.context.Services
			:Get("AvatarCatalogService")
			:Search(payload.CategoryId, payload.Keyword)
		local messages = {
			UNKNOWN_CATEGORY = "That category is not available.",
			CATALOGUE_UNAVAILABLE = "The catalogue is unavailable right now. Try again shortly.",
		}
		return {
			Success = results ~= nil,
			Code = if results then "OK" else reason,
			Message = if results then "" else (reason and messages[reason]) or "Search failed.",
			Data = results,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetAppearanceEditState", function(payload)
		return type(payload) == "table" and type(payload.CharacterId) == "string"
	end, function(player, payload, requestId)
		local state, reason = self.context.Services
			:Get("CharacterService")
			:AppearanceEditState(player, payload.CharacterId)
		return {
			Success = state ~= nil,
			Code = if state then "OK" else reason,
			Message = if state then "" else "That character could not be found.",
			Data = state,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetAuthoredAppearance", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.Appearance) == "table"
	end, function(player, payload, requestId)
		local saved, reason =
			self.context.Services
				:Get("CharacterService")
				:SetAuthoredAppearance(player, payload.CharacterId, payload.Appearance)
		local messages = {
			CHARACTER_NOT_OWNED = "That character could not be found.",
			CHARACTER_NOT_ACTIVE = "Select this character before changing how it looks.",
			CIVILIAN_REQUIRED = "Change a character's appearance while off duty as a civilian.",
			CHARACTER_UNAVAILABLE = "Your character is not ready yet.",
			APPEARANCE_EDIT_REQUIRED = "This character's look is already set. "
				.. "Buy a Change Character Appearance to edit it again.",
			INVALID_APPEARANCE = "That appearance could not be read.",
			INVALID_APPEARANCE_ASSET = "One of those items could not be used.",
			INVALID_APPEARANCE_SCALE = "That body size is outside what is allowed.",
			INVALID_APPEARANCE_COLOUR = "That skin colour could not be read.",
		}
		return {
			Success = saved,
			Code = if saved then "OK" else reason,
			Message = if saved
				then "Appearance saved."
				else (reason and messages[reason]) or "The appearance could not be saved.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SubmitApplication", function(payload)
		return type(payload) == "table" and type(payload.FormId) == "string" and type(
			payload.Answers
		) == "table",
			"INVALID_APPLICATION"
	end, function(player, payload, requestId)
		local record, reason = self.context.Services
			:Get("ApplicationService")
			:Submit(player, payload.FormId, payload.Answers)
		if not record then
			return {
				Success = false,
				Code = reason,
				Message = "The application could not be submitted.",
				RequestId = requestId,
			}
		end
		return { Success = true, Code = "OK", Message = "", Data = record, RequestId = requestId }
	end)
	self.context.Network:RegisterFunction("GetGangStatus", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local status = self.context.Services:Get("GangService"):GetStatus(player)
		if not status then
			return {
				Success = false,
				Code = "PROFILE_UNAVAILABLE",
				Message = "Your profile is still loading. Try again in a moment.",
				RequestId = requestId,
			}
		end
		-- The territory's display name travels alongside the gang record so the
		-- client can label a spawn option without a second round trip.
		local territoryId = status.Gang and status.Gang.TerritoryId
		local territoryName = if type(territoryId) == "string"
			then self.context.Services:Get("GangTerritoryService"):NameOf(territoryId)
			else nil
		local data = table.clone(status)
		data.TerritoryName = territoryName
		return { Success = true, Code = "OK", Message = "", Data = data, RequestId = requestId }
	end)
	local gangMessages = {
		PROFILE_UNAVAILABLE = "Your profile is still loading. Try again in a moment.",
		ALREADY_IN_A_GANG = "You are already in a gang.",
		NOT_IN_A_GANG = "You are not in a gang.",
		NOT_THE_LEADER = "Only the leader can do that.",
		GANG_PASS_REQUIRED = "Gang System Access is required to do that.",
		NAME_REQUIRED = "Enter a name for the gang.",
		NAME_LENGTH = "Gang names are 3-24 characters.",
		NAME_CHARACTERS = "Use letters, numbers, spaces, apostrophes and hyphens only.",
		NAME_TAKEN = "That name is already taken.",
		INVALID_TARGET = "Choose a player to invite.",
		PLAYER_NOT_ONLINE = "That player is not on this server.",
		ALREADY_INVITED = "That player already has a pending invite.",
		TOO_MANY_PENDING_INVITES = "That player has too many pending invites.",
		GANG_FULL = "The gang is full.",
		INVALID_RESPONSE = "That invite response was not understood.",
		INVITE_NOT_FOUND = "That invite is no longer available.",
		GANG_NOT_FOUND = "That gang no longer exists.",
		GANG_JOIN_FAILED = "The gang could not be joined.",
		GANG_LEAVE_FAILED = "The gang could not be left. Try again.",
	}
	self.context.Network:RegisterFunction("CreateGang", function(payload)
		return type(payload) == "table" and type(payload.Name) == "string"
	end, function(player, payload, requestId)
		local gang, reason = self.context.Services:Get("GangService"):Create(player, payload.Name)
		return {
			Success = gang ~= nil,
			Code = if gang then "OK" else reason,
			Message = if gang
				then ""
				else (reason and gangMessages[reason]) or "The gang could not be created.",
			Data = gang,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("InviteToGang", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local invited, reason =
			self.context.Services:Get("GangService"):Invite(player, payload.TargetUserId)
		return {
			Success = invited,
			Code = if invited then "OK" else reason,
			Message = if invited
				then "Invite sent."
				else (reason and gangMessages[reason]) or "The invite could not be sent.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RespondToGangInvite", function(payload)
		return type(payload) == "table"
			and type(payload.GangId) == "string"
			and type(payload.Accept) == "boolean"
	end, function(player, payload, requestId)
		local responded, reason = self.context.Services
			:Get("GangService")
			:RespondToInvite(player, payload.GangId, payload.Accept)
		return {
			Success = responded,
			Code = if responded then "OK" else reason,
			Message = if responded
				then ""
				else (reason and gangMessages[reason]) or "The invite could not be answered.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("LeaveGang", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local left, reason = self.context.Services:Get("GangService"):Leave(player)
		return {
			Success = left,
			Code = if left then "OK" else reason,
			Message = if left
				then "You have left the gang."
				else (reason and gangMessages[reason]) or "The gang could not be left.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTSearch", function(payload)
		return type(payload) == "table"
			and type(payload.Query) == "string"
			and (payload.Type == "Person" or payload.Type == "Vehicle"),
			"INVALID_SEARCH"
	end, function(player, payload, requestId)
		local permission = if payload.Type == "Person" then "PersonSearch" else "VehicleSearch"
		if not self.context.Services:Get("MDTService"):CanUsePermission(player, permission) then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "You must be on an authorised duty to use this search.",
				RequestId = requestId,
			}
		end
		local query, reason = self.context.Services:Get("MDTService"):SanitiseQuery(payload.Query)
		if not query then
			return {
				Success = false,
				Code = reason,
				Message = "The search query was invalid.",
				RequestId = requestId,
			}
		end
		self.context.Services:Get("MDTService"):AuditSearch(player, payload.Type, requestId)
		local page = if type(payload.Page) == "number"
			then math.clamp(math.floor(payload.Page), 1, 1000)
			else 1
		local data, searchReason
		if payload.Type == "Person" then
			local duty = self.context.Services:Get("MDTService"):GetDuty(player)
			local accessProfile = "Emergency"
			if
				duty
				and duty.DepartmentId == "Police"
				and self.context.Services:Get("MDTService"):CanUsePermission(player, "WarrantRead")
			then
				accessProfile = "Police"
			elseif duty and duty.DepartmentId == "Highways" then
				accessProfile = "Highways"
			end
			data, searchReason =
				self.context.Services:Get("PersonRecordService"):Search(query, page, accessProfile)
		else
			data, searchReason = self.context.Services:Get("VehicleRecordService"):Search(
				query,
				page,
				self.context.Services:Get("MDTService"):CanUsePermission(player, "WarrantRead")
			)
		end
		return {
			Success = data ~= nil,
			Code = if data then "OK" else searchReason or "MDT_SEARCH_UNAVAILABLE",
			Message = if data then "" else "Persistent records are temporarily unavailable.",
			Data = data,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetMDTAccess",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("MDTService"):AccessSummary(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("MDTCreateWarrant", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.Reason) == "string"
			and (payload.ExpiresAt == nil or type(payload.ExpiresAt) == "number")
	end, function(player, payload, requestId)
		local warrant, reason =
			self.context.Services
				:Get("WarrantService")
				:Create(player, payload.CharacterId, payload.Reason, payload.ExpiresAt)
		return {
			Success = warrant ~= nil,
			Code = if warrant then "OK" else reason,
			Message = if warrant then "Warrant issued." else "The warrant could not be issued.",
			Data = warrant,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTRevokeWarrant", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.WarrantId) == "string"
	end, function(player, payload, requestId)
		local warrant, reason = self.context.Services
			:Get("WarrantService")
			:Revoke(player, payload.CharacterId, payload.WarrantId)
		return {
			Success = warrant ~= nil,
			Code = if warrant then "OK" else reason,
			Message = if warrant then "Warrant revoked." else "The warrant could not be revoked.",
			Data = warrant,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTGetIncidents", function(payload)
		return type(payload) == "table"
			and (payload.Page == nil or type(payload.Page) == "number")
			and (payload.ResolvedOnly == nil or type(payload.ResolvedOnly) == "boolean")
	end, function(player, payload, requestId)
		local mdt = self.context.Services:Get("MDTService")
		if
			not mdt:CanUsePermission(player, "IncidentRead")
			and not mdt:CanUsePermission(player, "IncidentWrite")
		then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "This duty cannot view incident records.",
				RequestId = requestId,
			}
		end
		local page = if type(payload.Page) == "number"
			then math.clamp(math.floor(payload.Page), 1, 1000)
			else 1
		local incidents, reason = self.context.Services
			:Get("IncidentService")
			:Recent(player, page, payload.ResolvedOnly == true)
		return {
			Success = incidents ~= nil,
			Code = if incidents then "OK" else reason,
			Message = if incidents then "" else "Incident records are temporarily unavailable.",
			Data = incidents,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MDTAddIncidentNote", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and type(payload.Note) == "string"
	end, function(player, payload, requestId)
		local call, reason = self.context.Services
			:Get("CallService")
			:AddOperationalNote(player, payload.CallId, payload.Note)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Operational note added." else "The note could not be added.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetOwnedVehicles",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("VehicleOwnershipService"):List(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("GetVehicleSpawnerMenu", function(payload)
		return type(payload) == "table" and type(payload.SpawnerId) == "string"
	end, function(player, payload, requestId)
		local menu, reason =
			self.context.Services:Get("VehicleSpawnerService"):Menu(player, payload.SpawnerId)
		return {
			Success = menu ~= nil,
			Code = if menu then "OK" else reason,
			Message = if menu
				then ""
				else "This vehicle facility is unavailable for your current role.",
			Data = menu,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SpawnVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.SpawnerId) == "string"
			and type(payload.DefinitionId) == "string"
			and (payload.VehicleId == nil or type(payload.VehicleId) == "string")
	end, function(player, payload, requestId)
		local spawned, reason =
			self.context.Services
				:Get("VehicleSpawnerService")
				:Spawn(player, payload.SpawnerId, payload.DefinitionId, payload.VehicleId)
		local messages = {
			ACTIVE_VEHICLE_EXISTS = "You already have a vehicle spawned.",
			ALL_BAYS_OCCUPIED = "Every vehicle bay is currently blocked.",
			NO_SPAWN_POINTS = "This facility has no configured spawn points.",
			SPAWN_COOLDOWN = "Please wait before spawning another vehicle.",
			VEHICLE_TEMPLATE_MISSING = "That vehicle model has not been installed.",
			VEHICLE_NOT_ALLOWED = "Your current role cannot use that vehicle.",
		}
		return {
			Success = spawned ~= nil,
			Code = if spawned then "OK" else reason,
			Message = if spawned
				then "Vehicle ready."
				else messages[reason] or "The vehicle could not be spawned.",
			Data = spawned,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PurchaseVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.DefinitionId) == "string"
			and type(payload.Colour) == "string"
	end, function(player, payload, requestId)
		local vehicle, reason = self.context.Services
			:Get("VehicleOwnershipService")
			:Purchase(player, payload.DefinitionId, payload.Colour)
		if not vehicle then
			local messages = {
				CHARACTER_NOT_ACTIVE = "Select a character before buying a vehicle.",
				VEHICLE_NOT_FOR_SALE = "That vehicle is not for sale here.",
				INVALID_VEHICLE_SELECTION = "That colour is not available for this vehicle.",
				INSUFFICIENT_FUNDS = "You cannot afford this vehicle.",
				GAMEPASS_REQUIRED = "This vehicle needs its game pass.",
				REGISTRATION_UNAVAILABLE = "No registration could be issued. Try again.",
			}
			return {
				Success = false,
				Code = reason,
				Message = (reason and messages[reason]) or "The vehicle could not be bought.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Vehicle purchased.",
			Data = {
				VehicleId = vehicle.VehicleId,
				DefinitionId = vehicle.DefinitionId,
				Registration = vehicle.Registration,
				Colour = vehicle.Colour,
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetCustomVehicleRegistration", function(payload)
		return type(payload) == "table"
			and type(payload.SpawnerId) == "string"
			and #payload.SpawnerId <= 64
			and type(payload.VehicleId) == "string"
			and #payload.VehicleId <= 64
			and type(payload.Registration) == "string"
			and #payload.Registration <= 16
	end, function(player, payload, requestId)
		local authorised, facilityReason = self.context.Services
			:Get("VehicleSpawnerService")
			:AuthoriseCivilianFacility(player, payload.SpawnerId)
		if not authorised then
			return {
				Success = false,
				Code = facilityReason,
				Message = "Custom registrations can only be changed at a civilian vehicle facility.",
				RequestId = requestId,
			}
		end
		local result, reason = self.context.Services
			:Get("VehicleOwnershipService")
			:SetCustomRegistration(player, payload.VehicleId, payload.Registration)
		local messages = {
			GAMEPASS_REQUIRED = "Custom registration access is required.",
			INVALID_REGISTRATION_LENGTH = "Enter a registration of the permitted length.",
			REGISTRATION_NOT_PERMITTED = "That registration is not permitted.",
			REGISTRATION_ALREADY_USED = "That registration is already registered.",
			TEXT_FILTER_UNAVAILABLE = "The registration could not be checked. Try again shortly.",
			VEHICLE_NOT_OWNED = "That vehicle is not in your garage.",
		}
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then "Registration updated."
				else messages[reason] or "The registration could not be updated.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetCCTVCameras",
		tablePayload,
		function(player, _, requestId)
			local cameras, reason = self.context.Services:Get("CCTVService"):Snapshot(player)
			return {
				Success = cameras ~= nil,
				Code = if cameras then "OK" else reason,
				Message = if cameras then "" else "CCTV is unavailable for this duty.",
				Data = cameras,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"GetDispatchSnapshot",
		tablePayload,
		function(player, _, requestId)
			local snapshot, reason = self.context.Services:Get("DispatchService"):Snapshot(player)
			if not snapshot then
				return {
					Success = false,
					Code = reason,
					Message = "Dispatch is unavailable for this duty.",
					RequestId = requestId,
				}
			end
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = snapshot,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("DispatchCreateCall", function(payload)
		return type(payload) == "table"
			and type(payload.Summary) == "string"
			and type(payload.Priority) == "string"
			and type(payload.Location) == "string"
			and type(payload.IncidentType) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local prepared, prepareReason =
			self.context.Services:Get("DispatchService"):PrepareCall(player, payload)
		if not prepared then
			return {
				Success = false,
				Code = prepareReason,
				Message = "The call details could not be accepted.",
				RequestId = requestId,
			}
		end
		local call, reason = self.context.Services:Get("CallService"):Create(prepared)
		if not call then
			return {
				Success = false,
				Code = reason,
				Message = "The call could not be created.",
				RequestId = requestId,
			}
		end
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Dispatch.CallCreated",
			Target = call.CallId,
			Metadata = { Priority = call.Priority, IncidentType = call.IncidentType },
		})
		return {
			Success = true,
			Code = "OK",
			Message = "Call created.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchUpdateCall", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and (payload.Status == nil or type(payload.Status) == "string")
			and (payload.Priority == nil or type(payload.Priority) == "string")
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local call, reason = self.context.Services:Get("CallService"):Update(
			payload.CallId,
			{ Status = payload.Status, Priority = payload.Priority }
		)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Call updated." else "The call could not be updated.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchAssignUnit", function(payload)
		return type(payload) == "table"
			and type(payload.CallId) == "string"
			and type(payload.UnitId) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local assigned, reason =
			self.context.Services:Get("CallService"):Assign(payload.CallId, payload.UnitId)
		return {
			Success = assigned,
			Code = if assigned then "OK" else reason,
			Message = if assigned then "Unit attached." else "The unit could not be attached.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchCloseCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("DispatchService"):IsAtConsole(player) then
			return {
				Success = false,
				Code = "DISPATCH_CONSOLE_REQUIRED",
				Message = "Sit at an authorised dispatch console first.",
				RequestId = requestId,
			}
		end
		local closed, reason =
			self.context.Services:Get("CallService"):Close(payload.CallId, player.UserId)
		return {
			Success = closed,
			Code = if closed then "OK" else reason,
			Message = if closed then "Call closed." else "The call could not be closed.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("DispatchSetUnitStatus", function(payload)
		return type(payload) == "table" and type(payload.Status) == "string"
	end, function(player, payload, requestId)
		if not self.context.Services:Get("MDTService"):CanUse(player) then
			return {
				Success = false,
				Code = "MDT_NOT_AUTHORISED",
				Message = "You are not on an authorised duty.",
				RequestId = requestId,
			}
		end
		local unitId = tostring(player.UserId)
		-- Assigned is dispatch's to give. A unit that could set it on itself could
		-- show as attending a call nobody sent it to.
		if payload.Status == "Assigned" then
			return {
				Success = false,
				Code = "STATUS_SET_BY_DISPATCH",
				Message = "Only dispatch can attach a unit to a call.",
				RequestId = requestId,
			}
		end
		local changed, reason =
			self.context.Services:Get("UnitService"):SetStatus(unitId, payload.Status)
		if changed then
			if payload.Status == "OnScene" then
				self.context.Services:Get("CallService"):NoteUnitOnScene(unitId)
			end
			self.context.Services:Get("DispatchService"):Publish("UnitChanged", unitId, 0)
		end
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			Message = if changed then "Status updated." else "The status could not be updated.",
			-- Echoed so the terminal shows what the server recorded rather than
			-- what the officer pressed.
			Data = if changed then { Status = payload.Status } else nil,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetPhone", tablePayload, function(player, _, requestId)
		local snapshot, reason = self.context.Services:Get("PhoneService"):Snapshot(player)
		if not snapshot then
			return {
				Success = false,
				Code = reason,
				Message = "Select a character before using the phone.",
				RequestId = requestId,
			}
		end
		return { Success = true, Code = "OK", Message = "", Data = snapshot, RequestId = requestId }
	end)
	self.context.Network:RegisterFunction("PhoneSendText", function(payload)
		return type(payload) == "table"
			and type(payload.Number) == "string"
			and type(payload.Message) == "string"
	end, function(player, payload, requestId)
		local message, reason = self.context.Services
			:Get("PhoneService")
			:SendText(player, payload.Number, payload.Message)
		return {
			Success = message ~= nil,
			Code = if message then "OK" else reason,
			Message = if message then "Message sent." else "The message could not be sent.",
			Data = message,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneTransferFunds", function(payload)
		return type(payload) == "table"
			and type(payload.Recipient) == "string"
			and type(payload.Amount) == "number"
	end, function(player, payload, requestId)
		local transfer, reason = self.context.Services
			:Get("PhoneService")
			:TransferFunds(player, payload.Recipient, payload.Amount)
		local messages = {
			INSUFFICIENT_FUNDS = "You do not have enough money in your bank account.",
			SELF_TRANSFER = "You cannot send money to yourself.",
			TRANSFER_LIMIT = "That transfer exceeds the per-transfer limit.",
			TRANSFER_IN_PROGRESS = "Your previous transfer is still being processed.",
			INVALID_RECIPIENT_NAME = "Enter the username of the person you are paying.",
			RECIPIENT_NAME_AMBIGUOUS = "More than one player is using that display name. Use their username.",
			PHONE_RECIPIENT_UNAVAILABLE = "That player is not in this server.",
		}
		return {
			Success = transfer ~= nil,
			Code = if transfer then "OK" else reason,
			Message = if transfer
				then string.format("£%d sent to %s.", transfer.Amount, transfer.Recipient)
				else messages[reason] or "The transfer could not be completed.",
			Data = transfer,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhonePlaceCall", function(payload)
		return type(payload) == "table" and type(payload.Number) == "string"
	end, function(player, payload, requestId)
		local call, reason =
			self.context.Services:Get("PhoneService"):PlaceCall(player, payload.Number)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Calling…" else "The call could not be placed.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneAnswerCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		local call, reason =
			self.context.Services:Get("PhoneService"):AnswerCall(player, payload.CallId)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call then "Call connected." else "The call could not be answered.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneEndCall", function(payload)
		return type(payload) == "table" and type(payload.CallId) == "string"
	end, function(player, payload, requestId)
		local ended, reason =
			self.context.Services:Get("PhoneService"):EndCall(player, payload.CallId)
		return {
			Success = ended,
			Code = if ended then "OK" else reason,
			Message = if ended then "Call ended." else "The call could not be ended.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneEmergency", function(payload)
		return type(payload) == "table"
			and type(payload.Summary) == "string"
			and type(payload.Location) == "string"
	end, function(player, payload, requestId)
		local call, reason = self.context.Services
			:Get("PhoneService")
			:Emergency(player, payload.Summary, payload.Location)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call
				then "Your 999 call has been sent to control."
				else "The emergency call failed. Try again.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetSprintState", function(payload)
		return type(payload) == "table" and type(payload.Sprinting) == "boolean"
	end, function(player, payload, requestId)
		local changed, reason =
			self.context.Services:Get("NeedsService"):SetSprinting(player, payload.Sprinting)
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			-- Said out loud. A refused sprint returned an empty message and the
			-- client discarded the reply, so a player out of breath or too hungry
			-- to run pressed shift and got nothing, with no way to tell that from
			-- the key being broken.
			Message = if changed
				then ""
				elseif reason == "SPRINT_EXHAUSTED" then "You need to catch your breath."
				elseif reason == "SPRINT_TOO_HUNGRY" then "You are too hungry to run."
				elseif reason == "SPRINT_WHILE_SEATED" then ""
				else "You cannot run right now.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PhoneToggleFlashlight", function(payload)
		return type(payload) == "table" and type(payload.Enabled) == "boolean"
	end, function(player, payload, requestId)
		local changed, reason =
			self.context.Services:Get("PhoneService"):ToggleFlashlight(player, payload.Enabled)
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			Message = if changed then "Flashlight updated." else "Equip the phone first.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiRequest", function(payload)
		return type(payload) == "table"
			and type(payload.Pickup) == "string"
			and type(payload.Dropoff) == "string"
			and type(payload.Band) == "string"
	end, function(player, payload, requestId)
		local taxi, reason = self.context.Services
			:Get("TaxiService")
			:Request(player, payload.Pickup, payload.Dropoff, payload.Band)
		local messages = {
			CIVILIAN_REQUIRED = "Taxi bookings are available to civilian characters.",
			INSUFFICIENT_FUNDS = "You do not have enough money in your bank account for that fare.",
			TAXI_REQUEST_ALREADY_ACTIVE = "You already have an active taxi booking.",
		}
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Taxi requested. Drivers have been notified."
				else messages[reason] or "The taxi request could not be sent.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiAccept", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local taxi, reason =
			self.context.Services:Get("TaxiService"):Accept(player, payload.RequestId)
		local acceptMessages = {
			TAXI_OWN_REQUEST = "You booked this ride. Another driver has to take it.",
			TAXI_DRIVER_REQUIRED = "Start a taxi shift before accepting bookings.",
			TAXI_REQUEST_ALREADY_ACTIVE = "Finish your current booking first.",
			TAXI_VEHICLE_REQUIRED = "Spawn your taxi before accepting a booking.",
		}
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Taxi booking accepted."
				else (reason and acceptMessages[reason])
					or "That taxi booking is no longer available.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiDecline", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local passed, reason =
			self.context.Services:Get("TaxiService"):Decline(player, payload.RequestId)
		return {
			Success = passed,
			Code = if passed then "OK" else reason,
			Message = if passed
				then "Booking passed on. It stays open for other drivers."
				elseif
					reason == "TAXI_DRIVER_REQUIRED"
				then "Start a taxi shift before reviewing bookings."
				else "That taxi booking is no longer available.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiComplete", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local taxi, reason =
			self.context.Services:Get("TaxiService"):Complete(player, payload.RequestId)
		local messages =
			{ INSUFFICIENT_FUNDS = "The passenger no longer has enough money for this fare." }
		return {
			Success = taxi ~= nil,
			Code = if taxi then "OK" else reason,
			Message = if taxi
				then "Fare paid and driver credited."
				else messages[reason] or "The taxi could not be completed.",
			Data = taxi,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("TaxiCancel", function(payload)
		return type(payload) == "table" and type(payload.RequestId) == "string"
	end, function(player, payload, requestId)
		local cancelled, reason =
			self.context.Services:Get("TaxiService"):Cancel(player, payload.RequestId)
		return {
			Success = cancelled,
			Code = if cancelled then "OK" else reason,
			Message = if cancelled
				then "Taxi booking cancelled."
				else "The taxi booking could not be cancelled.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"TaxiStartShift",
		tablePayload,
		function(player, _, requestId)
			local shift, reason = self.context.Services:Get("TaxiService"):StartShift(player)
			return {
				Success = shift ~= nil,
				Code = if shift then "OK" else reason,
				Message = if shift
					then "You are now available for taxi bookings."
					elseif
						reason == "TAXI_REQUEST_ALREADY_ACTIVE"
					then "Finish the taxi you booked before starting a shift."
					else "The taxi shift could not be started.",
				Data = shift,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"TaxiEndShift",
		tablePayload,
		function(player, _, requestId)
			local ended, reason = self.context.Services:Get("TaxiService"):EndShift(player)
			return {
				Success = ended,
				Code = if ended then "OK" else reason,
				Message = if ended
					then "You are no longer available for taxi bookings."
					else "Finish or cancel your active taxi ride first.",
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("PurchaseFromVendor", function(payload)
		return type(payload) == "table"
			and type(payload.VendorId) == "string"
			and type(payload.ItemId) == "string"
	end, function(player, payload, requestId)
		local result, reason = self.context.Services:Get("VendorService"):Purchase(player, payload)
		if not result then
			-- Every failure used to collapse into "That purchase could not be
			-- completed", so walking too far from the stall, being broke, and
			-- already owning the item all read identically to the player. The
			-- reason code was always there; nothing surfaced it.
			local messages = {
				VENDOR_NOT_FOUND = "That stall could not be found.",
				VENDOR_OUT_OF_RANGE = "Move closer to the stall to buy from it.",
				ITEM_NOT_FOUND = "That item is no longer on offer.",
				EMERGENCY_SERVICE_RESTRICTED = "Not sold to on-duty emergency services.",
				ALREADY_HELD = "You already have one of these.",
				INSUFFICIENT_FUNDS = "You cannot afford that right now.",
				CHARACTER_NOT_ACTIVE = "Select a character before buying.",
				INVALID_FOOD = "That is not something this stall sells.",
				BACKPACK_UNAVAILABLE = "Your backpack is not ready. Try again in a moment.",
				TOOL_UNAVAILABLE = "That item is not currently available.",
			}
			return {
				Success = false,
				Code = reason or "VENDOR_PURCHASE_FAILED",
				Message = (reason and messages[reason]) or "That purchase could not be completed.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = result,
			RequestId = requestId,
		}
	end)
	-- Food is bought from a vendor, and PurchaseFromVendor re-checks that the
	-- player is standing at one. This endpoint reached the same purchase with no
	-- proximity rule at all, so a player could eat mid-pursuit, from a rooftop or
	-- inside a custody cell. It is kept only so an existing client build does not
	-- break, and refuses.
	self.context.Network:RegisterFunction("PurchaseFood", function(payload)
		return type(payload) == "table" and type(payload.FoodId) == "string"
	end, function(_, _, requestId)
		return {
			Success = false,
			Code = "VENDOR_REQUIRED",
			Message = "Food is bought from a shop. Find one on the map.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("CuffPlayer", function(payload)
		return type(payload) == "table"
			and type(payload.TargetUserId) == "number"
			and (payload.Mode == nil or payload.Mode == "Apply" or payload.Mode == "Remove")
	end, function(player, payload, requestId)
		local result, reason = self.context.Services
			:Get("CustodyService")
			:SetCuffed(player, payload.TargetUserId, payload.Mode)
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then (result.Cuffed and "Player handcuffed." or "Handcuffs removed.")
				else "The handcuffs could not be used.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("BookCustody", function(payload)
		return type(payload) == "table"
			and type(payload.TargetUserId) == "number"
			and type(payload.Reason) == "string"
			and boundedStringArray(
				payload.OffenceCodes,
				self.context.Configuration.Custody.MaximumActiveOffences
			)
	end, function(player, payload, requestId)
		local record, reason =
			self.context.Services
				:Get("CustodyService")
				:Book(player, payload.TargetUserId, payload.Reason, payload.OffenceCodes)
		return {
			Success = record ~= nil,
			Code = if record then "OK" else reason,
			Message = if record
				then "Custody booking created."
				elseif
					reason == "TARGET_NOT_SEATED"
				then "Sit the detainee in a custody chair before booking them."
				elseif
					reason == "TARGET_NOT_CUFFED"
				then "The detainee must be handcuffed before processing."
				else "The custody booking could not be completed.",
			Data = record,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("MeleeStrike", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("MeleeWeaponService"):Strike(player, payload.TargetUserId)
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result then "" else "That item could not be used.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetCustodyPolicy",
		tablePayload,
		function(player, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("CustodyService"):GetPolicy(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction(
		"UseEarlyReleaseCredit",
		tablePayload,
		function(player, _, requestId)
			local used, reason =
				self.context.Services:Get("CustodyService"):UseEarlyReleaseCredit(player)
			return {
				Success = used,
				Code = if used then "OK" else reason,
				Message = if used
					then "Early release approved."
					else "The release credit could not be used.",
				Data = self.context.Services:Get("CustodyService"):GetPolicy(player),
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("CustodyAction", function(payload)
		return type(payload) == "table"
			and type(payload.TargetUserId) == "number"
			and type(payload.Action) == "string"
			and (payload.Data == nil or type(payload.Data) == "table")
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services
				:Get("CustodyService")
				:Action(player, payload.TargetUserId, payload.Action, payload.Data or {})
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result then "Custody action completed." else "Custody action was refused.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetPresentedId", function(payload)
		return type(payload) == "table"
			and type(payload.TargetUserId) == "number"
			and (payload.CredentialType == "Civilian" or payload.CredentialType == "Police")
	end, function(player, payload, requestId)
		local card, reason = self.context.Services
			:Get("IdentificationService")
			:Present(player, payload.TargetUserId, payload.CredentialType)
		return {
			Success = card ~= nil,
			Code = if card then "OK" else reason,
			Message = if card
				then "Identification presented."
				else "Identification could not be presented.",
			Data = card,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetRadioSnapshot",
		tablePayload,
		function(player, _, requestId)
			local data, reason = self.context.Services:Get("RadioService"):Snapshot(player)
			return {
				Success = data ~= nil,
				Code = if data then "OK" else reason,
				Message = if data then "" else "You must be on duty to use the radio.",
				Data = data,
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("RadioSetChannel", function(payload)
		return type(payload) == "table" and type(payload.ChannelId) == "string"
	end, function(player, payload, requestId)
		local data, reason =
			self.context.Services:Get("RadioService"):SetChannel(player, payload.ChannelId)
		return {
			Success = data ~= nil,
			Code = if data then "OK" else reason,
			Message = if data then "Channel changed." else "That channel is not available.",
			Data = data,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioTransmit", function(payload)
		return type(payload) == "table"
			and type(payload.Message) == "string"
			and #payload.Message <= 180
	end, function(player, payload, requestId)
		local sent, reason =
			self.context.Services:Get("RadioService"):Transmit(player, payload.Message)
		return {
			Success = sent == true,
			Code = if sent then "OK" else reason,
			Message = if sent then "Transmitted." else "The message could not be transmitted.",
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("RadioPanic", function(payload)
		return type(payload) == "table"
	end, function(player, _, requestId)
		local call, reason = self.context.Services:Get("EmergencyTriggerService"):Panic(player)
		return {
			Success = call ~= nil,
			Code = if call then "OK" else reason,
			Message = if call
				then "PANIC ALERT SENT TO ALL ON-DUTY UNITS."
				elseif reason == "PANIC_COOLDOWN" then "PANIC COOLDOWN ACTIVE."
				else "The panic alert could not be sent.",
			Data = call,
			RequestId = requestId,
		}
	end)
	self.context.Network:MarkReady()
end
function NetworkService:Destroy() end
return NetworkService
