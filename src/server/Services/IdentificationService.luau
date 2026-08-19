--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ToolFactory = require(script.Parent.Parent.Systems.ToolFactory)

local IdentificationService = { connections = {}, playerConnections = {} }

local FORBIDDEN_ASSET_CLASSES: { [string]: boolean } = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
}

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

local function setSurfaceText(root: Instance, partName: string, value: string)
	local part = root:FindFirstChild(partName, true)
	local field = part and part:FindFirstChildWhichIsA("TextBox", true)
	if field and field:IsA("TextBox") then
		field.Text = value
		-- Preserve the purchased card's authored typography and sizing. Forcing
		-- TextScaled/TextWrapped here made several independent fields expand into
		-- each other and produced the jumbled presentation seen in Studio.
		field.TextEditable = false
		field.Active = false
		field.Selectable = false
	end
end

local function prepareWarrantCardPresentation(tool: Tool)
	-- The purchased card was authored as a close-up display prop. At Roblox's
	-- normal third-person camera distance its original grip fills most of the
	-- screen, while its SurfaceGuis become unreadable under night lighting.
	-- Preserve the model, welds and authored field layout, but issue a smaller,
	-- presentation-ready copy with self-lit surfaces.
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		local scaleContainer = Instance.new("Model")
		handle.Parent = scaleContainer
		scaleContainer:ScaleTo(0.78)
		handle.Parent = tool
		scaleContainer:Destroy()
	end

	local rotation = tool.Grip - tool.Grip.Position
	tool.Grip = CFrame.new(0.18, -0.24, -0.58) * rotation

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("SurfaceGui") then
			descendant.AlwaysOnTop = true
			descendant.LightInfluence = 0
			descendant.Brightness = 2
		elseif descendant:IsA("TextBox") then
			descendant.TextEditable = false
			descendant.Active = false
			descendant.Selectable = false
		end
	end
end

local function warrantCardTemplate(): Tool?
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local tools = assets and assets:FindFirstChild("Tools")
	local services = tools and tools:FindFirstChild("Services")
	local police = services and services:FindFirstChild("Police")
	local shared = police and police:FindFirstChild("Shared")
	-- The purchased model's authored root is `WarrantCard`, while the player-
	-- facing tool is deliberately `Warrant Card`. Requiring the display name in
	-- ServerStorage made the installed asset invisible to this resolver.
	local template = shared
		and (
			shared:FindFirstChild("Warrant Card")
			or shared:FindFirstChild("WarrantCard")
			or shared:FindFirstChild("PoliceWarrantCard")
		)
	return if template and template:IsA("Tool") then template else nil
end

local function makeWarrantCard(data: any): Tool?
	local template = warrantCardTemplate()
	if not template then
		warn("[RoleplayOS] Police warrant-card template is missing")
		return nil
	end
	local tool = template:Clone()
	tool.Name = "Warrant Card"
	tool.CanBeDropped = false
	prepareWarrantCardPresentation(tool)
	for _, descendant in tool:GetDescendants() do
		local reviewedWarrantClient = descendant:IsA("LocalScript")
			and descendant.Name == "RoleplayOSWarrantCardClient"
		if FORBIDDEN_ASSET_CLASSES[descendant.ClassName] and not reviewedWarrantClient then
			descendant:Destroy()
		elseif descendant:IsA("TextBox") then
			descendant.TextEditable = false
			descendant.Active = false
			descendant.Selectable = false
			if descendant.Text == "METROPOLITAN" then
				descendant.Text = data.ForceName
			end
		end
	end
	setSurfaceText(tool, "Username", data.FullName)
	setSurfaceText(tool, "UserNameID", data.WarrantNumber)
	setSurfaceText(tool, "Rank", data.Rank)
	local picture = tool:FindFirstChild("Picture", true)
	local portrait = picture and picture:FindFirstChildWhichIsA("ImageLabel", true)
	if portrait and portrait:IsA("ImageLabel") then
		portrait.Image = data.AvatarImage
	end
	return tool
end

function IdentificationService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("CredentialPresented")
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
		return false, "BACKPACK_UNAVAILABLE"
	end
	local character = self:_character(player)
	if not character or not player.Team then
		return false, "CHARACTER_OR_TEAM_UNAVAILABLE"
	end
	if player.Team.Name == "Civilian" then
		removeCredential(backpack)
		removeCredential(player.Character)
		removeCredential(player:FindFirstChild("StarterGear"))
		local licence = ToolFactory.drivingLicence(self:_identityData(player, character))
		licence.Parent = backpack
		return true, nil
	end
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if not duty or duty.DepartmentId ~= "Police" then
		-- Refusing to issue a card is also the moment to take back the last one.
		--
		-- Ending a shift destroys duty-issued tools in the backpack, but not the
		-- recovery copy in StarterGear, and this early return used to leave that
		-- copy behind. Roblox hands StarterGear back on the next respawn, so an
		-- officer who came off duty was carrying a valid warrant card again a
		-- moment later, off duty and out of uniform.
		removeCredential(backpack)
		removeCredential(player.Character)
		removeCredential(player:FindFirstChild("StarterGear"))
		return false, "POLICE_DUTY_REQUIRED"
	end
	local role = self.context.Configuration.Roles[duty.RoleId]
	local identity = self:_identityData(player, character)
	local warrantCard = makeWarrantCard({
		FullName = identity.FullName,
		Rank = if role then role.Name else "Police Officer",
		ForceName = self.context.Configuration.Identification.PoliceForceName,
		WarrantNumber = string.format("UP-%06d", player.UserId % 1000000),
		AvatarImage = identity.AvatarImage,
	})
	if warrantCard then
		-- Build and validate the replacement before deleting the current credential.
		-- CharacterAdded and Team signals can run while DutyService is rebuilding a
		-- shift; deleting first made a harmless ordering race permanently remove the
		-- officer's card from Backpack and StarterGear.
		removeCredential(backpack)
		removeCredential(player.Character)
		removeCredential(player:FindFirstChild("StarterGear"))
		warrantCard:SetAttribute("RoleplayOSCredential", "Police")
		warrantCard:SetAttribute("RoleplayOSDutyIssued", true)
		warrantCard.Parent = backpack
		-- StarterGear is a recovery copy only. Roblox restores it after a reset,
		-- while Refresh removes stale copies on team/duty changes.
		local starterGear = player:FindFirstChild("StarterGear")
		if starterGear then
			warrantCard:Clone().Parent = starterGear
		end
		return true, nil
	end
	return false, "WARRANT_CARD_TEMPLATE_UNAVAILABLE"
end

-- Reasons that mean "not yet" rather than "no".
--
-- A player joins with a default Roblox character and no team, and picks their
-- character from the menu in their own time -- which might be ten seconds or two
-- minutes. The retry below gives up after about three, so the first attempt of
-- every session failed and logged a warning naming a player who then got their
-- credential perfectly well the moment they chose a team.
--
-- Nothing is lost by staying quiet: Start watches CharacterAdded and the Team
-- property, so the attempt that matters is the one those fire, not this one.
local NOT_READY_YET = {
	CHARACTER_OR_TEAM_UNAVAILABLE = true,
	BACKPACK_UNAVAILABLE = true,
}

function IdentificationService:RefreshWithRetry(player: Player)
	for attempt = 1, 4 do
		if not player.Parent then
			return
		end
		local issued, reason = self:Refresh(player)
		if issued then
			return
		end
		if attempt < 4 then
			task.wait(0.5 * attempt)
		elseif not NOT_READY_YET[reason] then
			-- A real failure, such as a missing warrant card template, which no
			-- amount of waiting fixes and somebody does need to see.
			self.context.Logger:Warning("Credential could not be issued", {
				UserId = player.UserId,
				Reason = reason,
			})
		end
	end
end

function IdentificationService:Start()
	self.playerConnections = {}
	local function watch(player: Player)
		local existing = self.playerConnections[player.UserId]
		if existing then
			for _, connection in existing do
				connection:Disconnect()
			end
		end
		local connections = {}
		self.playerConnections[player.UserId] = connections
		table.insert(
			connections,
			player.CharacterAdded:Connect(function()
				task.delay(1, function()
					if player.Parent then
						self:RefreshWithRetry(player)
					end
				end)
			end)
		)
		table.insert(
			connections,
			player:GetPropertyChangedSignal("Team"):Connect(function()
				task.defer(function()
					if player.Parent then
						self:RefreshWithRetry(player)
					end
				end)
			end)
		)
		if player.Character then
			self:RefreshWithRetry(player)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local connections = self.playerConnections[player.UserId]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				self.playerConnections[player.UserId] = nil
			end
		end)
	)
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
	self.event:FireClient(target, result)
	return {
		Presented = true,
		PresentedToUserId = target.UserId,
		CredentialType = credentialType,
	},
		nil
end

function IdentificationService:Destroy()
	for _, connections in self.playerConnections do
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	table.clear(self.playerConnections)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return IdentificationService
