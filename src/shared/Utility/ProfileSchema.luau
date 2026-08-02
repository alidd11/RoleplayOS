--!strict

local SettingsValidator = require(script.Parent.SettingsValidator)
local PhoneValidator = require(script.Parent.PhoneValidator)

local ProfileSchema = {}
ProfileSchema.CURRENT_VERSION = 7

function ProfileSchema.default(userId: number): any
	return {
		SchemaVersion = 7,
		UserId = userId,
		Settings = SettingsValidator.defaults(),
		CharacterSlots = {},
		Characters = {},
		DutyProfiles = {},
		Whitelists = {},
		Applications = {},
		Qualifications = {},
		GamepassCache = {},
		TeamVehicleRegistrations = {},
		CustodySentence = {
			ReleaseAt = 0,
			TotalSeconds = 0,
			Offences = {},
			UpdatedAt = 0,
		},
		Communities = {},
		AuditMetadata = {},
	}
end

local function reconcile(target: any, defaults: any)
	for key, value in defaults do
		if target[key] == nil then
			target[key] = table.clone(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			reconcile(target[key], value)
		end
	end
end

function ProfileSchema.migrate(data: any, userId: number): (any?, string?)
	if data == nil then
		return ProfileSchema.default(userId), nil
	end
	if type(data) ~= "table" then
		return nil, "PROFILE_NOT_TABLE"
	end
	local version = data.SchemaVersion or 0
	if version > ProfileSchema.CURRENT_VERSION then
		return nil, "PROFILE_VERSION_TOO_NEW"
	end
	if version == 0 then
		data.SchemaVersion = 1
		data.DutyProfiles = data.DutyProfiles or {}
	end
	if data.SchemaVersion == 1 then
		data.Communities = data.Communities or {}
		data.SchemaVersion = 2
	end
	if data.SchemaVersion == 2 then
		data.Settings = SettingsValidator.reconcile(data.Settings)
		data.SchemaVersion = 3
	end
	if data.SchemaVersion == 3 then
		for characterId, character in data.Characters or {} do
			character.Phone = character.Phone
				or {
					Number = PhoneValidator.numberFromCharacterId(characterId),
					Messages = {},
				}
		end
		data.SchemaVersion = 4
	end
	if data.SchemaVersion == 4 then
		data.TeamVehicleRegistrations = data.TeamVehicleRegistrations or {}
		data.SchemaVersion = 5
	end
	if data.SchemaVersion == 5 then
		for _, character in data.Characters or {} do
			character.DrivingRecord = character.DrivingRecord or { Points = 0, Fines = {} }
			character.CustodyRecord = character.CustodyRecord or { Bookings = {} }
		end
		data.SchemaVersion = 6
	end
	if data.SchemaVersion == 6 then
		data.CustodySentence = data.CustodySentence
			or {
				ReleaseAt = 0,
				TotalSeconds = 0,
				Offences = {},
				UpdatedAt = 0,
			}
		data.SchemaVersion = 7
	end
	data.UserId = userId
	reconcile(data, ProfileSchema.default(userId))
	return data, nil
end

return table.freeze(ProfileSchema)
