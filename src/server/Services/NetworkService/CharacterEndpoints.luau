--!strict
return function(self: any)
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
end
