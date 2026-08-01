--!strict

local ProfileSchema = {}
ProfileSchema.CURRENT_VERSION = 2

function ProfileSchema.default(userId: number): any
	return {
		SchemaVersion = 2,
		UserId = userId,
		Settings = {},
		CharacterSlots = {},
		Characters = {},
		DutyProfiles = {},
		Whitelists = {},
		Applications = {},
		Qualifications = {},
		GamepassCache = {},
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
	data.UserId = userId
	reconcile(data, ProfileSchema.default(userId))
	return data, nil
end

return table.freeze(ProfileSchema)
