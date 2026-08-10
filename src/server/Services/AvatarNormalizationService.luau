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

local function normalize(character: Model)
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
