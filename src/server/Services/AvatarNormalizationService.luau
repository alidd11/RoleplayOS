--!strict

local Players = game:GetService("Players")

local AvatarNormalizationService = { connections = {} }

local STANDARD_SCALES = {
	BodyHeightScale = 1,
	-- Service kits are authored against Roblox's standard Classic/block R15
	-- mannequin. Keep the default width and depth so uniforms do not have to be
	-- scaled around a narrow, non-standard player silhouette.
	BodyWidthScale = 1,
	BodyDepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0,
	BodyProportionScale = 0,
}

-- A Color3 that was never assigned reads as pure black, which is how an avatar
-- whose appearance has not finished loading is told apart from one that really
-- is wearing black. No Roblox skin tone is fully black, so this cannot reject a
-- legitimate avatar.
local function isUnsetColour(colour: Color3): boolean
	return colour.R == 0 and colour.G == 0 and colour.B == 0
end

local function normalize(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if player and player.Team and player.Team.Name == "Civilian" then
		-- Civilian characters own their appearance. Emergency duty is the only
		-- path that should standardise the rig and replace personal clothing.
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	-- Scale values alone do not standardise an avatar: a player can still arrive
	-- with a package-specific torso, arms and legs whose meshes have completely
	-- different silhouettes. Replace only those body-part package IDs with the
	-- default R15 block body while retaining face, skin colour, clothing, hair and
	-- accessories. This gives rigid uniform kit parts one dependable target.
	if character:GetAttribute("RoleplayOSStandardBodyApplied") ~= true then
		local applied = false
		local ok = pcall(function()
			local description = humanoid:GetAppliedDescription()
			-- Take the skin tone from the body itself, not from the description.
			--
			-- Every colour field on a HumanoidDescription is a Color3, and an
			-- unset Color3 is black rather than nil. GetAppliedDescription
			-- returns exactly those unset defaults while the avatar's appearance
			-- is still loading, so the description this reads can be entirely
			-- black through no fault of the player's avatar.
			--
			-- ApplyDescriptionReset then paints that black onto the body. It is
			-- intermittent because it is a race: the duty flow spawns the
			-- character with LoadCharacterAsync and applies the uniform straight
			-- after, while appearance loading is separate and asynchronous, so
			-- whether the colours have arrived yet depends on timing. When it
			-- loses, the player is left with pure black limbs, and because this
			-- runs once per character behind the attribute below it is never
			-- retried -- the black stays until they respawn.
			--
			-- The BodyColors instance is the authoritative visible colour and is
			-- populated with the real skin tone, so copying from it makes the
			-- result independent of whether the description has caught up.
			local bodyColors = character:FindFirstChildOfClass("BodyColors")
			if bodyColors then
				description.HeadColor = bodyColors.HeadColor3
				description.TorsoColor = bodyColors.TorsoColor3
				description.LeftArmColor = bodyColors.LeftArmColor3
				description.RightArmColor = bodyColors.RightArmColor3
				description.LeftLegColor = bodyColors.LeftLegColor3
				description.RightLegColor = bodyColors.RightLegColor3
			elseif isUnsetColour(description.TorsoColor) then
				-- No body colours to read and a description that has not loaded.
				-- Leave the avatar alone rather than guessing: returning without
				-- setting the attribute means the next call normalises properly.
				return
			end
			description.Head = 0
			description.Torso = 0
			description.LeftArm = 0
			description.RightArm = 0
			description.LeftLeg = 0
			description.RightLeg = 0
			description.HeightScale = STANDARD_SCALES.BodyHeightScale
			description.WidthScale = STANDARD_SCALES.BodyWidthScale
			description.DepthScale = STANDARD_SCALES.BodyDepthScale
			description.HeadScale = STANDARD_SCALES.HeadScale
			description.BodyTypeScale = STANDARD_SCALES.BodyTypeScale
			description.ProportionScale = STANDARD_SCALES.BodyProportionScale
			humanoid:ApplyDescriptionReset(description)
			applied = true
		end)
		if ok and applied then
			character:SetAttribute("RoleplayOSStandardBodyApplied", true)
		end
	end
	humanoid.AutomaticScalingEnabled = true
	for valueName, standardValue in STANDARD_SCALES do
		local scale = humanoid:FindFirstChild(valueName)
		if scale and scale:IsA("NumberValue") then
			scale.Value = standardValue
		end
	end
	character:SetAttribute("RoleplayOSStandardAvatar", true)
end

function AvatarNormalizationService:Init(context: any)
	self.context = context
	table.clear(self.connections)
end

function AvatarNormalizationService:Normalize(character: Model)
	normalize(character)
end

function AvatarNormalizationService:Start()
	local function watch(player: Player)
		table.insert(
			self.connections,
			player.CharacterAppearanceLoaded:Connect(function(character)
				normalize(character)
			end)
		)
		if player.Character then
			task.defer(normalize, player.Character)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function AvatarNormalizationService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return AvatarNormalizationService
