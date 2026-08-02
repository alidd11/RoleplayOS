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
						"Private communities",
					},
				},
				RequestId = requestId,
			}
		end
	)
	self.context.Network:RegisterFunction("CreatePrivateCommunity", function(payload)
		return type(payload) == "table" and type(payload.Name) == "string"
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
			self.context.Services:Get("CommunityService"):Create(player, payload.Name)
		if not community then
			return {
				Success = false,
				Code = reason,
				Message = "The community could not be created.",
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
end
function NetworkService:Destroy() end
return NetworkService
