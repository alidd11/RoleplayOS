--!strict

local Players = game:GetService("Players")
local ToolFactory = require(script.Parent.Parent.Systems.ToolFactory)

local IdentificationService = { connections = {} }

local function documentNumber(characterId: string): string
	return string.upper(string.sub(string.gsub(characterId, "%-", ""), 1, 12))
end

local function dateAt(timestamp: number): string
	return os.date("!%d.%m.%Y", timestamp)
end

local function removeCredential(container: Instance?)
	if not container then
		return
	end
	for _, name in { "ID Card", "Warrant Card" } do
		local existing = container:FindFirstChild(name)
		if existing and existing:IsA("Tool") then
			existing:Destroy()
		end
	end
end

function IdentificationService:Init(context: any)
	self.context = context
end

function IdentificationService:_character(player: Player): any?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
end

function IdentificationService:_identityData(player: Player, character: any): any
	return {
		FirstName = character.Identity.FirstName,
		LastName = character.Identity.LastName,
		FullName = character.Identity.FirstName .. " " .. character.Identity.LastName,
		DateOfBirth = character.Identity.DateOfBirth,
		DocumentNumber = documentNumber(character.CharacterId),
		Issued = dateAt(character.CreatedAt or os.time()),
		ValidTo = dateAt((character.CreatedAt or os.time()) + 10 * 365 * 86400),
		AvatarImage = string.format(
			"rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420",
			player.UserId
		),
	}
end

function IdentificationService:Refresh(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	removeCredential(backpack)
	removeCredential(player.Character)
	local character = self:_character(player)
	if not character or not player.Team then
		return
	end
	if player.Team.Name == "Civilian" then
		ToolFactory.drivingLicence(self:_identityData(player, character)).Parent = backpack
		return
	end
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if not duty or duty.DepartmentId ~= "Police" then
		return
	end
	local role = self.context.Configuration.Roles[duty.RoleId]
	local identity = self:_identityData(player, character)
	ToolFactory.warrantCard({
		FullName = identity.FullName,
		Rank = if role then role.Name else "Police Officer",
		ForceName = self.context.Configuration.Identification.PoliceForceName,
		WarrantNumber = string.format("UP-%06d", player.UserId % 1000000),
		AvatarImage = identity.AvatarImage,
	}).Parent =
		backpack
end

function IdentificationService:Start()
	local function watch(player: Player)
		table.insert(
			self.connections,
			player.CharacterAdded:Connect(function()
				task.delay(1, function()
					if player.Parent then
						self:Refresh(player)
					end
				end)
			end)
		)
		table.insert(
			self.connections,
			player:GetPropertyChangedSignal("Team"):Connect(function()
				task.defer(function()
					if player.Parent then
						self:Refresh(player)
					end
				end)
			end)
		)
		if player.Character then
			self:Refresh(player)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function IdentificationService:Present(
	actor: Player,
	targetUserId: number,
	credentialType: string
): (any?, string?)
	local toolName = if credentialType == "Police" then "Warrant Card" else "ID Card"
	local equipped = actor.Character and actor.Character:FindFirstChild(toolName)
	if not equipped or not equipped:IsA("Tool") then
		return nil, "CREDENTIAL_MUST_BE_EQUIPPED"
	end
	local duty = self.context.Services:Get("DutyService"):Get(actor)
	if credentialType == "Police" then
		if not duty or duty.DepartmentId ~= "Police" then
			return nil, "POLICE_DUTY_REQUIRED"
		end
	elseif not actor.Team or actor.Team.Name ~= "Civilian" then
		return nil, "CIVILIAN_REQUIRED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local actorRoot = actor.Character and actor.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target
		and target.Character
		and target.Character:FindFirstChild("HumanoidRootPart")
	if
		not actorRoot
		or not targetRoot
		or (actorRoot.Position - targetRoot.Position).Magnitude
			> self.context.Configuration.Identification.MaximumPresentationDistance
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local character = self:_character(actor)
	if not character then
		return nil, "CHARACTER_UNAVAILABLE"
	end
	local result = self:_identityData(actor, character)
	result.CredentialType = credentialType
	result.PresentedByUserId = actor.UserId
	if credentialType == "Police" then
		local role = self.context.Configuration.Roles[duty.RoleId]
		result.Rank = if role then role.Name else "Police Officer"
		result.ForceName = self.context.Configuration.Identification.PoliceForceName
		result.WarrantNumber = string.format("UP-%06d", actor.UserId % 1000000)
	end
	return result, nil
end

function IdentificationService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return IdentificationService
