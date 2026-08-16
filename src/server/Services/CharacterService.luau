--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextFilter = require(script.Parent.Parent.Systems.TextFilter)
local Validator = require(ReplicatedStorage.RoleplayOS.Shared.CharacterValidator)
local PhoneValidator = require(ReplicatedStorage.RoleplayOS.Shared.PhoneValidator)
local CharacterService = { Critical = true }

-- Only values read from a server-owned HumanoidDescription are persisted. The
-- client never submits catalogue IDs, which keeps civilian outfit changes
-- editable without turning the endpoint into an asset injection surface.
local APPEARANCE_PROPERTIES = {
	"BackAccessory",
	"BodyTypeScale",
	"DepthScale",
	"Face",
	"FaceAccessory",
	"FrontAccessory",
	"HairAccessory",
	"HatAccessory",
	"Head",
	"HeadScale",
	"HeightScale",
	"LeftArm",
	"LeftLeg",
	"NeckAccessory",
	"Pants",
	"ProportionScale",
	"RightArm",
	"RightLeg",
	"Shirt",
	"ShoulderAccessory",
	"Torso",
	"WaistAccessory",
	"WidthScale",
	"GraphicTShirt",
}

-- Skin tone, kept apart from the list above because it is not a string or a
-- number.
--
-- Every colour on a HumanoidDescription is a Color3, so none of them survived
-- the string/number filter in captureAppearance and none were listed to be
-- captured in the first place. applyAppearance then built a brand new
-- HumanoidDescription, whose colours are unset and therefore black, and called
-- ApplyDescriptionReset with it. The result was that selecting a saved civilian
-- character painted the player's whole body pure black every single time --
-- deterministically, not as a race -- and it applied to every extra character
-- slot a player bought, because each one re-applies its appearance on selection.
--
-- Stored as a hex string so it stays a flat, DataStore-safe value alongside the
-- asset ids rather than becoming a nested table.
local APPEARANCE_COLOUR_PROPERTIES = {
	"HeadColor",
	"LeftArmColor",
	"LeftLegColor",
	"RightArmColor",
	"RightLegColor",
	"TorsoColor",
}

local COLOUR_PROPERTY_LOOKUP: { [string]: boolean } = {}
for _, propertyName in APPEARANCE_COLOUR_PROPERTIES do
	COLOUR_PROPERTY_LOOKUP[propertyName] = true
end

-- The colour a limb is actually wearing, for characters saved before skin tone
-- was captured. Without this their stored appearance still has no colours and
-- would still reset them to black on every load.
local COLOUR_FALLBACK_SOURCES: { [string]: string } = {
	HeadColor = "HeadColor3",
	LeftArmColor = "LeftArmColor3",
	LeftLegColor = "LeftLegColor3",
	RightArmColor = "RightArmColor3",
	RightLegColor = "RightLegColor3",
	TorsoColor = "TorsoColor3",
}

local function captureAppearance(character: Model): ({ [string]: any }?, string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, "CHARACTER_UNAVAILABLE"
	end
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return nil, "APPEARANCE_UNAVAILABLE"
	end
	local appearance: { [string]: any } = {}
	for _, propertyName in APPEARANCE_PROPERTIES do
		local propertyOk, value = pcall(function()
			return (description :: any)[propertyName]
		end)
		if propertyOk and (type(value) == "string" or type(value) == "number") then
			appearance[propertyName] = value
		end
	end
	-- Skin tone, read from the body rather than the description.
	--
	-- BodyColors carries what the character is visibly wearing, while the
	-- description can still be reporting unset black if the avatar's appearance
	-- has not finished loading. Capturing from the description would therefore
	-- save black as though the player had chosen it, making the reset below
	-- permanent rather than transient.
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	for _, propertyName in APPEARANCE_COLOUR_PROPERTIES do
		local colour: Color3? = nil
		if bodyColors then
			local sourceOk, sourceValue = pcall(function()
				return (bodyColors :: any)[COLOUR_FALLBACK_SOURCES[propertyName]]
			end)
			if sourceOk and typeof(sourceValue) == "Color3" then
				colour = sourceValue
			end
		end
		if not colour then
			local propertyOk, value = pcall(function()
				return (description :: any)[propertyName]
			end)
			if propertyOk and typeof(value) == "Color3" then
				colour = value
			end
		end
		if colour and not (colour.R == 0 and colour.G == 0 and colour.B == 0) then
			local hexOk, hex = pcall(function()
				return colour:ToHex()
			end)
			if hexOk and type(hex) == "string" then
				appearance[propertyName] = hex
			end
		end
	end
	return appearance, nil
end

local function applyAppearance(character: Model, appearance: { [string]: any }): (boolean, string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local description = Instance.new("HumanoidDescription")
	for propertyName, value in appearance do
		if COLOUR_PROPERTY_LOOKUP[propertyName] then
			if type(value) == "string" then
				pcall(function()
					(description :: any)[propertyName] = Color3.fromHex(value)
				end)
			end
		else
			pcall(function()
				(description :: any)[propertyName] = value
			end)
		end
	end
	-- Anything the saved appearance did not carry is taken from the body as it
	-- stands, so a character saved before skin tone was captured keeps the colour
	-- it is already wearing instead of being reset to black.
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		for _, propertyName in APPEARANCE_COLOUR_PROPERTIES do
			if appearance[propertyName] == nil then
				pcall(function()
					(description :: any)[propertyName] = (bodyColors :: any)[COLOUR_FALLBACK_SOURCES[propertyName]]
				end)
			end
		end
	end
	local ok, reason = pcall(function()
		humanoid:ApplyDescriptionReset(description)
	end)
	description:Destroy()
	if not ok then
		return false, tostring(reason)
	end
	return true, nil
end
function CharacterService:Init(context: any)
	self.context = context
end
function CharacterService:Start() end
local function filterIdentity(player: Player, identity: any): (any?, string?)
	-- Both names at once. Filtered one after the other they cost the sum of two
	-- web calls, which is longer than a request should ever take and is why
	-- creating a character timed out rather than being refused.
	local cleaned, reason = TextFilter.manyForBroadcast({
		FirstName = identity.FirstName,
		LastName = identity.LastName,
	}, player.UserId)
	if not cleaned then
		return nil, reason or "TEXT_FILTER_UNAVAILABLE"
	end
	local filtered = table.clone(identity)
	filtered.FirstName = cleaned.FirstName
	filtered.LastName = cleaned.LastName
	return filtered, nil
end
-- Single authority for how many character slots a profile may occupy. The start
-- menu and creation path must agree, otherwise a purchased slot is unreachable.
function CharacterService:SlotAllowance(session: any): number
	local slots = self.context.Configuration.Characters.FreeSlots
	slots += math.max(0, math.floor(tonumber(session.Profile.Consumables.ExtraCharacterSlots) or 0))
	return math.min(slots, self.context.Configuration.Characters.MaximumSlots)
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
	if count >= self:SlotAllowance(session) then
		return nil, "NO_CHARACTER_SLOT"
	end
	local id = HttpService:GenerateGUID(false)
	local now = os.time()
	local startingAppearance = {}
	if player.Character then
		local captured = captureAppearance(player.Character)
		if captured then
			startingAppearance = captured
		end
	end
	local character = {
		CharacterId = id,
		Identity = filteredIdentity,
		-- Capture the player's current Roblox avatar at creation time so the new
		-- identity starts personalised instead of falling back to a blank outfit.
		Appearance = startingAppearance,
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
		-- Vehicle registration uses a separate persistent reservation. A transient
		-- failure there must not erase an otherwise valid character; retry lazily
		-- when the character is selected instead.
		character.StarterVehiclePending = true
		self.context.Logger:Warning("Starter vehicle deferred after character creation", {
			UserId = player.UserId,
			CharacterId = id,
			Reason = starterReason or "STARTER_VEHICLE_UNAVAILABLE",
		})
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.context.Services:Get("RecordIndexService"):ScheduleCharacter(player, character)
	return self:Summary(character), nil
end
function CharacterService:Summary(character: any): any
	local appearance = character.Appearance or {}
	return {
		CharacterId = character.CharacterId,
		FullName = character.Identity.FirstName .. " " .. character.Identity.LastName,
		DateOfBirth = character.Identity.DateOfBirth,
		LastPlayedAt = character.LastPlayedAt,
		-- Only the clothing asset identifiers needed by the local ViewportFrame are
		-- exposed. The remainder of the persistent character record stays server-side.
		-- Empty values deliberately fall back to the player's current Roblox avatar.
		PreviewAppearance = {
			ShirtTemplate = appearance.ShirtTemplate or appearance.Shirt,
			TrousersTemplate = appearance.TrousersTemplate or appearance.Pants,
		},
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

function CharacterService:ApplyCivilianAppearance(
	player: Player,
	characterId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not session or session.ActiveCharacterId ~= characterId or not character then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	if self.context.Services:Get("DutyService"):Get(player) then
		return false, "CIVILIAN_REQUIRED"
	end
	local runtimeCharacter = player.Character
	if not runtimeCharacter then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local appearance = character.Appearance
	if type(appearance) ~= "table" or next(appearance) == nil then
		local captured, captureReason = captureAppearance(runtimeCharacter)
		if not captured then
			return false, captureReason
		end
		appearance = captured
		character.Appearance = appearance
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
	runtimeCharacter:SetAttribute("RoleplayOSCivilianAppearance", true)
	return applyAppearance(runtimeCharacter, appearance)
end

function CharacterService:SaveCurrentAppearance(
	player: Player,
	characterId: string
): (boolean, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not session or session.ActiveCharacterId ~= characterId or not character then
		return false, "CHARACTER_NOT_ACTIVE"
	end
	if
		self.context.Services:Get("DutyService"):Get(player)
		or not player.Team
		or player.Team.Name ~= "Civilian"
	then
		return false, "CIVILIAN_REQUIRED"
	end
	local runtimeCharacter = player.Character
	if not runtimeCharacter then
		return false, "CHARACTER_UNAVAILABLE"
	end
	local appearance, reason = captureAppearance(runtimeCharacter)
	if not appearance then
		return false, reason
	end
	character.Appearance = appearance
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end
function CharacterService:Select(player: Player, characterId: string): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	session.ActiveCharacterId = characterId
	character.LastPlayedAt = os.time()
	if character.StarterVehiclePending == true then
		local starter =
			self.context.Services:Get("VehicleOwnershipService"):GrantStarter(player, characterId)
		if starter then
			character.StarterVehiclePending = nil
		end
	end
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
