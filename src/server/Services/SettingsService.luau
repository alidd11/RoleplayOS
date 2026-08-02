--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SettingsValidator = require(ReplicatedStorage.RoleplayOS.Shared.SettingsValidator)

local SettingsService = {}

function SettingsService:Init(context: any)
	self.context = context
end

function SettingsService:Start() end

function SettingsService:Get(player: Player): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	return SettingsValidator.reconcile(session.Profile.Settings), nil
end

function SettingsService:Update(player: Player, patch: any): (any?, string?)
	local clean, reason = SettingsValidator.validatePatch(patch)
	if not clean then
		return nil, reason
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local settings = SettingsValidator.reconcile(session.Profile.Settings)
	for key, value in clean do
		settings[key] = value
	end
	session.Profile.Settings = settings
	self.context.Services:Get("DataService"):MarkDirty(player)
	return table.clone(settings), nil
end

function SettingsService:Destroy() end

return SettingsService
