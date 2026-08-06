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
						:Get("CommunityServerService")
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
						"Private communities",
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
	self.context.Network:RegisterFunction("CreatePrivateCommunity", function(payload)
		return type(payload) == "table" and type(payload.GroupId) == "number"
	end, function(player, payload, requestId)
		if game.PrivateServerOwnerId == 0 or player.UserId ~= game.PrivateServerOwnerId then
			return {
				Success = false,
				Code = "PRIVATE_SERVER_OWNER_REQUIRED",
				Message = "Only the private server owner can create this community.",
				RequestId = requestId,
			}
		end
		local community, reason =
			self.context.Services:Get("CommunityService"):Create(player, payload.GroupId)
		if not community then
			return {
				Success = false,
				Code = reason,
				Message = reason == "COMMUNITY_GROUP_OWNER_REQUIRED"
						and "You must own that Roblox group."
					or reason == "COMMUNITY_GROUP_UNAVAILABLE" and "Roblox could not verify that group. Try again shortly."
					or "The community could not be created.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "Community created.",
			Data = self.context.Services:Get("CommunityService"):PublicSummary(player),
			RequestId = requestId,
		}
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
			local includeWarrants =
				self.context.Services:Get("MDTService"):CanUsePermission(player, "WarrantRead")
			data, searchReason = self.context.Services
				:Get("PersonRecordService")
				:Search(query, page, includeWarrants)
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
		return type(payload) == "table" and (payload.Page == nil or type(payload.Page) == "number")
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
		local incidents, reason = self.context.Services:Get("IncidentService"):Recent(player, page)
		return {
			Success = incidents ~= nil,
			Code = if incidents then "OK" else reason,
			Message = if incidents then "" else "Incident records are temporarily unavailable.",
			Data = incidents,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SetCustomRegistration", function(payload)
		return type(payload) == "table"
			and type(payload.TerminalId) == "string"
			and type(payload.VehicleId) == "string"
			and type(payload.Registration) == "string"
	end, function(player, payload, requestId)
		local terminal, terminalReason = self.context.Services
			:Get("VehicleService")
			:AuthoriseDealershipTerminal(player, payload.TerminalId)
		if not terminal then
			return {
				Success = false,
				Code = terminalReason,
				Message = "Custom registrations can only be changed inside a dealership.",
				RequestId = requestId,
			}
		end
		local result, reason = self.context.Services
			:Get("VehicleOwnershipService")
			:SetCustomRegistration(player, payload.VehicleId, payload.Registration)
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result
				then "Registration updated."
				else "That registration could not be used.",
			Data = result,
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
	self.context.Network:RegisterFunction("RequestVehiclePreview", function(payload)
		return type(payload) == "table" and type(payload.DefinitionId) == "string"
	end, function(player, payload, requestId)
		-- The client asks for a picture of a vehicle it can already see listed;
		-- the server still decides whether a model exists and what it looks like.
		local preview, reason =
			self.context.Services:Get("VehiclePreviewService"):Request(player, payload.DefinitionId)
		return {
			Success = preview ~= nil,
			Code = if preview then "OK" else reason,
			Message = if preview then "" else "No preview is available for that vehicle.",
			Data = if preview then { DefinitionId = payload.DefinitionId } else nil,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetVehicleSpawnMenu", function(payload)
		return type(payload) == "table" and type(payload.TerminalId) == "string"
	end, function(player, payload, requestId)
		local menu, reason =
			self.context.Services:Get("VehicleService"):Menu(player, payload.TerminalId)
		return {
			Success = menu ~= nil,
			Code = if menu then "OK" else reason,
			Message = if menu then "" else "This vehicle terminal is unavailable.",
			Data = menu,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SpawnOwnedVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.TerminalId) == "string"
			and type(payload.VehicleId) == "string"
	end, function(player, payload, requestId)
		local spawned, reason = self.context.Services
			:Get("VehicleService")
			:SpawnOwned(player, payload.TerminalId, payload.VehicleId)
		return {
			Success = spawned ~= nil,
			Code = if spawned then "OK" else reason,
			Message = if spawned then "Vehicle ready." else "The vehicle could not be spawned.",
			Data = spawned,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("GetDealershipCatalogue", function(payload)
		return type(payload) == "table" and type(payload.TerminalId) == "string"
	end, function(player, payload, requestId)
		local catalogue, reason =
			self.context.Services:Get("DealershipService"):Catalogue(player, payload.TerminalId)
		if not catalogue then
			return {
				Success = false,
				Code = reason or "DEALERSHIP_UNAVAILABLE",
				Message = "This forecourt is not available.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "",
			Data = catalogue,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("PurchaseVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.TerminalId) == "string"
			and type(payload.CharacterId) == "string"
			and type(payload.DealershipId) == "string"
			and type(payload.DefinitionId) == "string"
			and type(payload.Colour) == "string"
	end, function(player, payload, requestId)
		local vehicle, reason = self.context.Services:Get("DealershipService"):Purchase(
			player,
			payload.TerminalId,
			payload.CharacterId,
			payload.DealershipId,
			payload.DefinitionId,
			payload.Colour
		)
		return {
			Success = vehicle ~= nil,
			Code = if vehicle then "OK" else reason,
			Message = if vehicle
				then "Vehicle purchased."
				elseif
					reason == "TERMINAL_TOO_FAR"
					or reason == "TERMINAL_NOT_FOUND"
					or reason == "DEALERSHIP_TERMINAL_REQUIRED"
					or reason == "DEALERSHIP_TERMINAL_MISMATCH"
				then "Vehicle purchases can only be made inside the selected dealership."
				elseif reason == "PURCHASE_IN_PROGRESS" then
					-- Said plainly, because the player reaching this has just been
					-- told their last attempt timed out and is trying again. Telling
					-- them it is still going is what stops them buying twice.
					"Your last purchase is still going through. Give it a moment."
				else "The purchase could not be completed.",
			Data = vehicle,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("SpawnServiceVehicle", function(payload)
		return type(payload) == "table"
			and type(payload.TerminalId) == "string"
			and type(payload.DefinitionId) == "string"
	end, function(player, payload, requestId)
		local spawned, reason = self.context.Services
			:Get("VehicleService")
			:SpawnService(player, payload.TerminalId, payload.DefinitionId)
		return {
			Success = spawned ~= nil,
			Code = if spawned then "OK" else reason,
			Message = if spawned
				then "Service vehicle ready."
				else "That service vehicle is unavailable.",
			Data = spawned,
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
		local changed, reason = self.context.Services
			:Get("UnitService")
			:SetStatus(tostring(player.UserId), payload.Status)
		if changed then
			self.context.Services
				:Get("DispatchService")
				:Publish("UnitChanged", tostring(player.UserId), 0)
		end
		return {
			Success = changed,
			Code = if changed then "OK" else reason,
			Message = if changed then "Status updated." else "The status could not be updated.",
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
	self.context.Network:RegisterFunction("PurchaseFromVendor", function(payload)
		return type(payload) == "table"
			and type(payload.VendorId) == "string"
			and type(payload.ItemId) == "string"
	end, function(player, payload, requestId)
		local result, reason = self.context.Services:Get("VendorService"):Purchase(player, payload)
		if not result then
			return {
				Success = false,
				Code = reason or "VENDOR_PURCHASE_FAILED",
				Message = "That purchase could not be completed.",
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
				else "Booking requires a nearby custody desk and handcuffed detainee.",
			Data = record,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction(
		"GetCustodyPolicy",
		tablePayload,
		function(_, _, requestId)
			return {
				Success = true,
				Code = "OK",
				Message = "",
				Data = self.context.Services:Get("CustodyService"):GetPolicy(),
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
	self.context.Network:MarkReady()
end
function NetworkService:Destroy() end
return NetworkService
