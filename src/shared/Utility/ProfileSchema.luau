--!strict

local SettingsValidator = require(script.Parent.SettingsValidator)
local PhoneValidator = require(script.Parent.PhoneValidator)

local ProfileSchema = {}
ProfileSchema.CURRENT_VERSION = 13

function ProfileSchema.default(userId: number): any
	return {
		SchemaVersion = 13,
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
		-- GangId is deliberately not defaulted here. It is the gang this account
		-- belongs to, and nil already means "not in a gang" -- storing that
		-- explicitly would be indistinguishable from the key being absent, since
		-- a nil value in a table constructor never becomes a key at all.
		--
		-- It is a pointer rather than the gang record itself: the record is
		-- shared between every member and the leader, so it lives in
		-- DataService's shared records under "gang:" .. GangId, keyed by an id
		-- rather than by any one member's profile.
		--
		-- Invites this account has been sent and has not yet answered. Pending on
		-- the invitee's own profile, not the gang record, so it survives them
		-- logging off between the invite and the accept, and so answering it
		-- never needs the inviter to be online a second time.
		GangInvites = {},
		CustodySentence = {
			ReleaseAt = 0,
			RemainingSeconds = 0,
			TotalSeconds = 0,
			Offences = {},
			UpdatedAt = 0,
		},
		Consumables = {
			EarlyReleaseCredits = 0,
			ExtraCharacterSlots = 0,
			AppearanceEdits = 0,
			ProcessedDeveloperReceipts = {},
		},
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
	if data.SchemaVersion == 8 then
		local sentence = data.CustodySentence
		if type(sentence) ~= "table" then
			sentence = {}
			data.CustodySentence = sentence
		end
		-- Version 8 used an absolute wall-clock deadline, which kept counting
		-- down while a player was offline. Preserve only the unserved portion at
		-- migration time; version 9 thereafter stores playtime remaining.
		sentence.RemainingSeconds = math.max(
			0,
			math.floor(
				tonumber(sentence.RemainingSeconds)
					or ((tonumber(sentence.ReleaseAt) or 0) - os.time())
			)
		)
		sentence.ReleaseAt = 0
		data.SchemaVersion = 9
	end
	if data.SchemaVersion == 9 then
		-- Physical cash became an authoritative EconomyService account in version
		-- 10. Older and partially corrupt profiles must be reconciled before any
		-- cash drop or robbery attempts arithmetic on a missing field.
		for _, character in data.Characters or {} do
			if type(character) == "table" then
				local economy = character.Economy
				if type(economy) ~= "table" then
					economy = {}
					character.Economy = economy
				end
				economy.Balance = math.max(0, math.floor(tonumber(economy.Balance) or 0))
				economy.Cash = math.max(0, math.floor(tonumber(economy.Cash) or 0))
				if type(economy.Transactions) ~= "table" then
					economy.Transactions = {}
				end
			end
		end
		data.SchemaVersion = 10
	end
	if data.SchemaVersion == 10 then
		local consumables = data.Consumables
		if type(consumables) ~= "table" then
			consumables = {}
			data.Consumables = consumables
		end
		consumables.EarlyReleaseCredits =
			math.max(0, math.floor(tonumber(consumables.EarlyReleaseCredits) or 0))
		if type(consumables.ProcessedDeveloperReceipts) ~= "table" then
			consumables.ProcessedDeveloperReceipts = {}
		end
		data.SchemaVersion = 11
	end
	if data.SchemaVersion == 11 then
		-- Appearance is authored once when a character is created and then fixed.
		-- Reopening the editor is a purchase, so the right to do it is counted
		-- here alongside the other consumables.
		local consumables = data.Consumables
		if type(consumables) ~= "table" then
			consumables = {}
			data.Consumables = consumables
		end
		consumables.AppearanceEdits =
			math.max(0, math.floor(tonumber(consumables.AppearanceEdits) or 0))
		-- Characters that already existed were built before the editor did, so
		-- their look was captured from the player's Roblox avatar rather than
		-- authored. Leaving them unlocked lets each set an appearance once
		-- without paying for an edit they were never offered.
		if type(data.Characters) == "table" then
			for _, character in data.Characters do
				if type(character) == "table" and character.AppearanceLocked == nil then
					character.AppearanceLocked = false
				end
			end
		end
		data.SchemaVersion = 12
	end
	if data.SchemaVersion == 12 then
		-- GangId is left alone: an absent key already means "not in a gang", and
		-- there is nothing to migrate an old profile to besides that. Only the
		-- invite list needs a container, since GangService iterates it directly.
		if type(data.GangInvites) ~= "table" then
			data.GangInvites = {}
		end
		data.SchemaVersion = 13
	end
	data.UserId = userId
	reconcile(data, ProfileSchema.default(userId))
	return data, nil
end

return table.freeze(ProfileSchema)
