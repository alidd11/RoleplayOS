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
