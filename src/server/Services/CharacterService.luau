--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Validator = require(ReplicatedStorage.RoleplayOS.Shared.CharacterValidator)
local PhoneValidator = require(ReplicatedStorage.RoleplayOS.Shared.PhoneValidator)
local CharacterService = {}
function CharacterService:Init(context: any)
	self.context = context
end
function CharacterService:Start() end
local function filterIdentity(player: Player, identity: any): (any?, string?)
	local filtered = table.clone(identity)
	for _, field in { "FirstName", "LastName" } do
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(identity[field], player.UserId)
				:GetNonChatStringForBroadcastAsync()
		end)
		if not ok or type(result) ~= "string" or #result < 1 then
			return nil, "TEXT_FILTER_UNAVAILABLE"
		end
		filtered[field] = result
	end
	return filtered, nil
end
function CharacterService:Create(player: Player, identity: any): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	if not session then
		return nil, "PROFILE_UNAVAILABLE"
	end
	local valid, reason = Validator.identity(
		identity,
		nil,
		self.context.Configuration.Characters.MinimumAge,
		self.context.Configuration.Characters.MaximumAge
	)
	if not valid then
		return nil, reason
	end
	local filteredIdentity, filterReason = filterIdentity(player, identity)
	if not filteredIdentity then
		return nil, filterReason
	end
	local count = 0
	for _ in session.Profile.Characters do
		count += 1
	end
	local slots = self.context.Configuration.Characters.FreeSlots
	if
		session.Profile.GamepassCache[tostring(
			self.context.Configuration.Gamepasses.ExtraCharacterSlot.GamepassId
		)]
	then
		slots += 1
	end
	if count >= math.min(slots, self.context.Configuration.Characters.MaximumSlots) then
		return nil, "NO_CHARACTER_SLOT"
	end
	local id = HttpService:GenerateGUID(false)
	local now = os.time()
	local character = {
		CharacterId = id,
		Identity = filteredIdentity,
		Appearance = {},
		Economy = {
			Balance = self.context.Configuration.Economy.StartingBankBalance,
			Cash = self.context.Configuration.Economy.StartingCashBalance,
			Transactions = {},
		},
		Employment = {},
		Vehicles = {},
		Properties = {},
		FurnitureInventory = {},
		FurniturePlacements = {},
		Inventory = {},
		Licences = {},
		CriminalRecord = {},
		MedicalRecord = {},
		DrivingRecord = { Points = 0, Fines = {} },
		CustodyRecord = { Bookings = {} },
		Progression = {},
		Phone = {
			Number = PhoneValidator.numberFromCharacterId(id),
			Messages = {},
		},
		CreatedAt = now,
		LastPlayedAt = now,
	}
	session.Profile.Characters[id] = character
	table.insert(session.Profile.CharacterSlots, id)
	local starter, starterReason =
		self.context.Services:Get("VehicleOwnershipService"):GrantStarter(player, id)
	if not starter then
		session.Profile.Characters[id] = nil
		table.remove(session.Profile.CharacterSlots, #session.Profile.CharacterSlots)
		return nil, starterReason or "STARTER_VEHICLE_UNAVAILABLE"
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return self:Summary(character), nil
end
function CharacterService:Summary(character: any): any
	return {
		CharacterId = character.CharacterId,
		FullName = character.Identity.FirstName .. " " .. character.Identity.LastName,
		DateOfBirth = character.Identity.DateOfBirth,
		LastPlayedAt = character.LastPlayedAt,
	}
end
function CharacterService:List(player: Player): { any }
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local result = {}
	if not session then
		return result
	end
	for _, character in session.Profile.Characters do
		table.insert(result, self:Summary(character))
	end
	table.sort(result, function(a, b)
		return a.LastPlayedAt > b.LastPlayedAt
	end)
	return result
end
function CharacterService:Select(player: Player, characterId: string): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	session.ActiveCharacterId = characterId
	character.LastPlayedAt = os.time()
	self.context.Services:Get("DataService"):MarkDirty(player)
	return character, nil
end
function CharacterService:Delete(
	player: Player,
	characterId: string,
	confirmationId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character or confirmationId ~= characterId then
		return false, "DELETION_NOT_CONFIRMED"
	end
	if session.ActiveCharacterId == characterId then
		return false, "CHARACTER_ACTIVE"
	end
	if #character.Vehicles > 0 or #character.Properties > 0 or #character.Employment > 0 then
		return false, "CHARACTER_HAS_PROTECTED_RECORDS"
	end
	session.Profile.Characters[characterId] = nil
	local index = table.find(session.Profile.CharacterSlots, characterId)
	if index then
		table.remove(session.Profile.CharacterSlots, index)
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end
function CharacterService:Destroy() end
return CharacterService
