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
			-- Only tables are cloned. table.clone raises on a scalar, and this
			-- runs inside the UpdateAsync transform on every load, so the first
			-- scalar default added to this schema would have failed every load
			-- for every player at once, with the retry machinery reading it as an
			-- outage and the join handler kicking for it. Nothing would have
			-- pointed at the new setting.
			target[key] = if type(value) == "table" then table.clone(value) else value
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
	-- Coerced rather than compared directly. A stored SchemaVersion that is not a
	-- number would otherwise raise "attempt to compare" inside the transform, and
	-- a raise there is indistinguishable from an outage: retried, then a kick,
	-- every join, forever.
	local version = tonumber(data.SchemaVersion) or 0
	if version > ProfileSchema.CURRENT_VERSION then
		return nil, "PROFILE_VERSION_TOO_NEW"
	end
	data.SchemaVersion = version
	-- The migrations below walk these, so a corrupt one has to be replaced here
	-- rather than allowed to throw halfway through.
	if data.Characters ~= nil and type(data.Characters) ~= "table" then
		data.Characters = {}
	end
	if data.Applications ~= nil and type(data.Applications) ~= "table" then
		data.Applications = {}
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
	if data.SchemaVersion == 7 then
		-- Every container a character is created with, backfilled on the ones
		-- that were not.
		--
		-- Nineteen fields are written at birth and only three of them had ever
		-- been migrated, so a character made before any of the other sixteen
		-- existed simply does not have it. That is not a quiet nil either:
		-- InventoryService iterates `character.Inventory` directly, so the first
		-- thing to touch one of these on an older character throws.
		--
		-- Listed rather than copied from the creation table on purpose. Only the
		-- empty containers belong here; Identity, CharacterId and the timestamps
		-- are real data and inventing them would be worse than the nil.
		for _, character in data.Characters or {} do
			if type(character) == "table" then
				character.Appearance = character.Appearance or {}
				character.Employment = character.Employment or {}
				character.Vehicles = character.Vehicles or {}
				character.Properties = character.Properties or {}
				character.FurnitureInventory = character.FurnitureInventory or {}
				character.FurniturePlacements = character.FurniturePlacements or {}
				character.Inventory = character.Inventory or {}
				character.Licences = character.Licences or {}
				character.CriminalRecord = character.CriminalRecord or {}
				character.MedicalRecord = character.MedicalRecord or {}
				character.Progression = character.Progression or {}
			end
		end
		data.SchemaVersion = 8
	end
	data.UserId = userId
	reconcile(data, ProfileSchema.default(userId))
	return data, nil
end

return table.freeze(ProfileSchema)
