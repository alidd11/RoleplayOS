--!strict
local Validators = require(script.Parent.Validators)
local tablePayload = Validators.tablePayload
local boundedStringArray = Validators.boundedStringArray

return function(self: any)
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
end
