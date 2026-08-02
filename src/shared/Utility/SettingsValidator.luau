--!strict

local SettingsValidator = {}

local DEFAULTS = table.freeze({
	InterfaceScale = "Standard",
	InterfaceMotion = true,
	HighContrast = false,
	ReducedEffects = false,
	CameraShake = true,
	ShowHints = true,
})

local SCALE_VALUES = table.freeze({ Small = true, Standard = true, Large = true })

function SettingsValidator.defaults(): any
	return table.clone(DEFAULTS)
end

function SettingsValidator.validatePatch(patch: any): (any?, string?)
	if type(patch) ~= "table" then
		return nil, "SETTINGS_PATCH_NOT_TABLE"
	end
	local clean = {}
	local count = 0
	for key, value in patch do
		count += 1
		if count > 6 or DEFAULTS[key] == nil then
			return nil, "UNKNOWN_SETTING"
		end
		if key == "InterfaceScale" then
			if type(value) ~= "string" or not SCALE_VALUES[value] then
				return nil, "INVALID_INTERFACE_SCALE"
			end
		elseif type(value) ~= "boolean" then
			return nil, "INVALID_SETTING_VALUE"
		end
		clean[key] = value
	end
	return clean, nil
end

function SettingsValidator.reconcile(settings: any): any
	local result = SettingsValidator.defaults()
	if type(settings) ~= "table" then
		return result
	end
	local clean = SettingsValidator.validatePatch(settings)
	if clean then
		for key, value in clean do
			result[key] = value
		end
	end
	return result
end

return table.freeze(SettingsValidator)
