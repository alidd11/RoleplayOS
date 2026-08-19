--!strict
-- One flat 1,700-line file of RegisterFunction calls made every endpoint hard
-- to find and risked a hidden shared upvalue between unrelated features. Each
-- domain's endpoints are self-contained (they only ever touch `self` and their
-- own locals - verified before this split), so they moved out verbatim into
-- sibling modules that each register their own slice onto `self`.
local NetworkService = { Critical = true }

local registerCoreEndpoints = require(script.CoreEndpoints)
local registerVehicleEndpoints = require(script.VehicleEndpoints)
local registerDutyEndpoints = require(script.DutyEndpoints)
local registerCharacterEndpoints = require(script.CharacterEndpoints)
local registerGangEndpoints = require(script.GangEndpoints)
local registerMDTEndpoints = require(script.MDTEndpoints)
local registerDispatchEndpoints = require(script.DispatchEndpoints)
local registerPhoneEndpoints = require(script.PhoneEndpoints)
local registerTaxiEndpoints = require(script.TaxiEndpoints)
local registerCustodyEndpoints = require(script.CustodyEndpoints)
local registerRadioEndpoints = require(script.RadioEndpoints)

function NetworkService:Init(context: any)
	self.context = context
end

function NetworkService:Start()
	local access = self.context.Services:Get("ExperienceAccessService")
	self.context.Network:SetAuthorizer(function(player)
		return access:IsVerified(player)
	end)

	registerCoreEndpoints(self)
	registerVehicleEndpoints(self)
	registerDutyEndpoints(self)
	registerCharacterEndpoints(self)
	registerGangEndpoints(self)
	registerMDTEndpoints(self)
	registerDispatchEndpoints(self)
	registerPhoneEndpoints(self)
	registerTaxiEndpoints(self)
	registerCustodyEndpoints(self)
	registerRadioEndpoints(self)

	self.context.Network:MarkReady()
end

function NetworkService:Destroy() end

return NetworkService
