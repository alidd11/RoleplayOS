--!strict
local NetworkService = {}
local function tablePayload(value: any): (boolean, string?)
	return type(value) == "table", "EXPECTED_TABLE"
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
	self.context.Network:RegisterFunction("BeginDuty", function(payload)
		return type(payload) == "table"
			and type(payload.DutyProfileId) == "string"
			and type(payload.RoleId) == "string"
			and type(payload.StationId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
		local started, reason = self.context.Services:Get("DutyService"):Begin(player, payload)
		if not started then
			return {
				Success = false,
				Code = reason,
				Message = reason == "SPAWN_POINT_UNAVAILABLE"
						and "That station spawn is not available. Choose another station."
					or reason == "SPAWN_ROLE_NOT_ALLOWED" and "That role cannot use the selected spawn point."
					or "Duty could not be started.",
				RequestId = requestId,
			}
		end
		return {
			Success = true,
			Code = "OK",
			Message = "You are now on duty.",
			Data = {
				RoleId = payload.RoleId,
				StationId = payload.StationId,
				SpawnId = payload.SpawnId,
			},
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("EnterCivilian", function(payload)
		return type(payload) == "table"
			and type(payload.CharacterId) == "string"
			and type(payload.SpawnId) == "string"
	end, function(player, payload, requestId)
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
			return {
				Success = false,
				Code = reason,
				Message = reason == "INVALID_NAME" and "Enter a valid first and last name."
					or reason == "AGE_OUT_OF_RANGE" and "This character does not meet the configured age requirement."
					or "The character could not be created.",
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
		local data = payload.Type == "Person"
				and self.context.Services
					:Get("PersonRecordService")
					:Search(query, payload.Page or 1)
			or { Items = self.context.Services:Get("VehicleRecordService"):Search(query), Page = 1 }
		return { Success = true, Code = "OK", Message = "", Data = data, RequestId = requestId }
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
	self.context.Network:RegisterFunction("SetCustomRegistration", function(payload)
		return type(payload) == "table"
			and type(payload.VehicleId) == "string"
			and type(payload.Registration) == "string"
	end, function(player, payload, requestId)
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
		local closed, reason = self.context.Services:Get("CallService"):Close(payload.CallId)
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
			Message = "",
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
	self.context.Network:RegisterFunction("PurchaseFood", function(payload)
		return type(payload) == "table" and type(payload.FoodId) == "string"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("NeedsService"):PurchaseFood(player, payload.FoodId)
		return {
			Success = result ~= nil,
			Code = if result then "OK" else reason,
			Message = if result then "Food consumed." else "The food could not be purchased.",
			Data = result,
			RequestId = requestId,
		}
	end)
	self.context.Network:RegisterFunction("CuffPlayer", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local result, reason =
			self.context.Services:Get("CustodyService"):Toggle(player, payload.TargetUserId)
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
	end, function(player, payload, requestId)
		local record, reason = self.context.Services
			:Get("CustodyService")
			:Book(player, payload.TargetUserId, payload.Reason)
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
	self.context.Network:RegisterFunction("GetPresentedId", function(payload)
		return type(payload) == "table" and type(payload.TargetUserId) == "number"
	end, function(player, payload, requestId)
		local card, reason =
			self.context.Services:Get("IdentificationService"):Present(player, payload.TargetUserId)
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
end
function NetworkService:Destroy() end
return NetworkService
