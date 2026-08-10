--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local UniformService = { connections = {}, promptConnections = {}, originals = {} }

local ISSUED_FOLDER_NAME = "RoleplayOSIssuedUniform"

local function resolve(root: Instance, path: { any }): Instance?
	local current: Instance? = root
	for _, segment in path do
		if not current or type(segment) ~= "string" then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function isPersonalAppearance(instance: Instance): boolean
	return instance:IsA("Shirt")
		or instance:IsA("Pants")
		or instance:IsA("ShirtGraphic")
		or instance:IsA("Accessory")
end

local function removePersonalAppearance(character: Model, removeAccessories: boolean)
	for _, child in character:GetChildren() do
		if
			child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or (removeAccessories and child:IsA("Accessory"))
		then
			child:Destroy()
		end
	end
end

local function removeIssuedKit(character: Model)
	local issued = character:FindFirstChild(ISSUED_FOLDER_NAME)
	if issued then
		issued:Destroy()
	end
end

local function targetPartName(partName: string): string
	if partName == "Peaked Cap" or partName == "Cap Badge" then
		return "Head"
	end
	if partName == "Belt" or partName == "BeltBuckle" or partName == "Pouch" then
		return "LowerTorso"
	end
	return "UpperTorso"
end

local function targetBodyPart(character: Model, bodyPartName: string): (BasePart?, CFrame, boolean)
	local exact = character:FindFirstChild(bodyPartName)
	if exact and exact:IsA("BasePart") then
		return exact, CFrame.identity, false
	end
	-- The supplied kit is authored against R15. Classic/block avatars expose a
	-- single Torso, so map both torso sections onto it instead of silently
	-- dropping every wearable piece.
	if bodyPartName == "UpperTorso" or bodyPartName == "LowerTorso" then
		local torso = character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			local verticalOffset = if bodyPartName == "LowerTorso" then -0.55 else 0.2
			return torso, CFrame.new(0, verticalOffset, 0), true
		end
	end
	return nil, CFrame.identity, false
end

local function sanitizePart(part: BasePart)
	for _, descendant in part:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("RemoteEvent")
			or descendant:IsA("RemoteFunction")
			or descendant:IsA("Weld")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("Motor6D")
		then
			descendant:Destroy()
		end
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function template(value: any): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	if string.match(value, "^rbxassetid://%d+$") then
		return value
	end
	return nil
end

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function rootPosition(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function offset(value: any): Vector3
	if type(value) ~= "table" then
		return Vector3.zero
	end
	return Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0)
end

function UniformService:Init(context: any)
	self.context = context
	table.clear(self.connections)
	table.clear(self.promptConnections)
	table.clear(self.originals)
end

function UniformService:_captureOriginal(player: Player, character: Model)
	local existing = self.originals[player.UserId]
	if existing and existing.Character == character then
		return
	end
	local appearance = {}
	for _, child in character:GetChildren() do
		if isPersonalAppearance(child) then
			table.insert(appearance, child:Clone())
		end
	end
	self.originals[player.UserId] = {
		Character = character,
		Appearance = appearance,
	}
end

function UniformService:_applyKit(character: Model, definition: any): (boolean, string?)
	if type(definition.KitAssetPath) ~= "table" then
		return true, nil
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local kit = assets and resolve(assets, definition.KitAssetPath)
	if not kit then
		return false, "UNIFORM_KIT_MISSING"
	end
	local referenceCharacter = kit:FindFirstChild("Character")
	local wearable = kit:FindFirstChild("Vest") or kit:FindFirstChild("Wearables")
	if not referenceCharacter or not wearable then
		return false, "UNIFORM_KIT_INVALID"
	end

	local issued = Instance.new("Folder")
	issued.Name = ISSUED_FOLDER_NAME
	issued.Parent = character
	local fitted = 0
	for _, source in wearable:GetDescendants() do
		if not source:IsA("BasePart") then
			continue
		end
		local bodyPartName = targetPartName(source.Name)
		local referencePart = referenceCharacter:FindFirstChild(bodyPartName)
		local targetPart, rigOffset, classicTorso = targetBodyPart(character, bodyPartName)
		if not referencePart or not referencePart:IsA("BasePart") or not targetPart then
			continue
		end
		local clone = source:Clone()
		sanitizePart(clone)
		clone.CFrame = targetPart.CFrame
			* rigOffset
			* referencePart.CFrame:ToObjectSpace(source.CFrame)
		if source.Name == "Stab" then
			-- Preserve the purchased mesh and texture, but fit its rigid R15
			-- mannequin dimensions around the player's standardised torso.
			clone.Transparency = 0
			clone.CastShadow = true
			if clone:IsA("MeshPart") then
				clone.DoubleSided = true
			end
			if classicTorso then
				clone.Size = Vector3.new(
					targetPart.Size.X * 1.08,
					targetPart.Size.Y * 0.88,
					targetPart.Size.Z * 1.16
				)
			else
				clone.Size =
					Vector3.new(clone.Size.X * 1.05, clone.Size.Y * 1.05, clone.Size.Z * 1.14)
			end
			clone.CFrame *= CFrame.new(0, 0, -0.09)
		end
		clone.Parent = issued
		local weld = Instance.new("WeldConstraint")
		weld.Name = "UniformWeld"
		weld.Part0 = targetPart
		weld.Part1 = clone
		weld.Parent = clone
		fitted += 1
	end
	if fitted == 0 then
		issued:Destroy()
		return false, "UNIFORM_KIT_EMPTY"
	end
	return true, nil
end

function UniformService:Apply(player: Player, uniformId: string): (boolean, string?)
	local definition = self.context.Configuration.Uniforms[uniformId]
	local character = player.Character
	local shirtTemplate = definition and template(definition.ShirtTemplate)
	local trousersTemplate = definition and template(definition.TrousersTemplate)
	if not definition or not character or not shirtTemplate or not trousersTemplate then
		return false, "UNIFORM_UNAVAILABLE"
	end
	self.context.Services:Get("AvatarNormalizationService"):Normalize(character)
	self:_captureOriginal(player, character)
	removeIssuedKit(character)
	removePersonalAppearance(character, definition.RemovePersonalAccessories == true)
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = shirtTemplate
	shirt.Parent = character
	local trousers = Instance.new("Pants")
	trousers.PantsTemplate = trousersTemplate
	trousers.Parent = character
	local kitCallSucceeded, kitApplied, kitReason = pcall(function()
		return self:_applyKit(character, definition)
	end)
	if not kitCallSucceeded or not kitApplied then
		self.context.Logger:Warning("Uniform kit could not be applied", {
			UserId = player.UserId,
			UniformId = uniformId,
			Reason = if kitCallSucceeded then kitReason else tostring(kitApplied),
		})
	end
	return true, nil
end

function UniformService:Restore(player: Player)
	local original = self.originals[player.UserId]
	self.originals[player.UserId] = nil
	local character = player.Character
	if not original or original.Character ~= character or not character then
		return
	end
	removeIssuedKit(character)
	removePersonalAppearance(character, true)
	for _, appearance in original.Appearance or {} do
		appearance.Parent = character
	end
end

function UniformService:_equipFromRoom(player: Player, room: Instance)
	local settings = self.context.Configuration.UniformChangingRooms
	local playerPosition = rootPosition(player)
	local roomPosition = positionOf(room)
	if
		not playerPosition
		or not roomPosition
		or (playerPosition - roomPosition).Magnitude > settings.MaximumInteractionDistance + 2
	then
		return
	end
	local duty = self.context.Services:Get("DutyService"):Get(player)
	local uniformId = room:GetAttribute("UniformId")
	local departmentId = room:GetAttribute("DepartmentId")
	local role = duty and self.context.Configuration.Roles[duty.RoleId]
	if not duty or not role or role.DepartmentId ~= departmentId or role.UniformId ~= uniformId then
		return
	end
	local applied, reason = self:Apply(player, uniformId)
	if not applied then
		self.context.Logger:Warning("Changing-room uniform could not be applied", {
			UserId = player.UserId,
			UniformId = uniformId,
			Reason = reason,
		})
		return
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Uniform.Equipped",
		Target = uniformId,
		Metadata = { ChangingRoomId = room:GetAttribute("ChangingRoomId") },
	})
end

function UniformService:_configure(room: Instance)
	if self.promptConnections[room] or room.Parent == nil then
		return
	end
	local settings = self.context.Configuration.UniformChangingRooms
	local parent = if room:IsA("BasePart")
		then room
		else room:FindFirstChild("UpperTorso", true) or room:FindFirstChild(
			"HumanoidRootPart",
			true
		) or room:FindFirstChildWhichIsA("BasePart", true)
	if not parent then
		return
	end
	local prompt = room:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RoleplayOSUniformPrompt"
		prompt.Parent = parent
	end
	prompt.ActionText = "Wear uniform"
	prompt.ObjectText = tostring(room:GetAttribute("DisplayName") or "Changing room")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = settings.PromptHoldDuration
	prompt.MaxActivationDistance = settings.MaximumInteractionDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	self.promptConnections[room] = prompt.Triggered:Connect(function(player)
		self:_equipFromRoom(player, room)
	end)
end

function UniformService:_spawnAnchors(): { [string]: SpawnLocation }
	local anchors = {}
	local padTag = self.context.Configuration.Spawning.PadTag
	local candidates = if type(padTag) == "string" then CollectionService:GetTagged(padTag) else {}
	if #candidates == 0 then
		candidates = workspace:GetDescendants()
	end
	for _, descendant in candidates do
		if descendant:IsA("SpawnLocation") then
			local spawnId = descendant:GetAttribute("SpawnId")
			if type(spawnId) == "string" and spawnId ~= "" then
				anchors[spawnId] = descendant
			end
			anchors[descendant.Name] = anchors[descendant.Name] or descendant
		end
	end
	return anchors
end

function UniformService:_createDefaults(folder: Instance)
	local settings = self.context.Configuration.UniformChangingRooms
	local anchors = self:_spawnAnchors()
	for _, specification in settings.Defaults do
		local existing
		for _, room in folder:GetChildren() do
			if room:GetAttribute("ChangingRoomId") == specification.ChangingRoomId then
				existing = room
				break
			end
		end
		if not existing then
			local anchor = anchors[specification.SpawnId]
			if not anchor then
				self.context.Logger:Warning("Changing room has no matching team spawn", {
					ChangingRoomId = specification.ChangingRoomId,
					SpawnId = specification.SpawnId,
				})
				continue
			end
			local room = Instance.new("Part")
			room.Name = specification.ChangingRoomId
			room.Size = Vector3.new(3, 5, 1)
			room.Material = Enum.Material.SmoothPlastic
			room.Color = Color3.fromRGB(27, 43, 64)
			room.Anchored = true
			room.CanCollide = true
			room:SetAttribute("ChangingRoomId", specification.ChangingRoomId)
			room:SetAttribute("DisplayName", specification.DisplayName)
			room:SetAttribute("DepartmentId", specification.DepartmentId)
			room:SetAttribute("UniformId", specification.UniformId)
			room.CFrame = anchor.CFrame * CFrame.new(offset(specification.Offset))
			room.Parent = folder
		end
	end
end

function UniformService:Start()
	local settings = self.context.Configuration.UniformChangingRooms
	local folder = workspace:FindFirstChild(settings.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = settings.FolderName
		folder.Parent = workspace
	end
	self:_createDefaults(folder)
	for _, room in folder:GetChildren() do
		self:_configure(room)
	end
	table.insert(
		self.connections,
		folder.ChildAdded:Connect(function(room)
			task.defer(function()
				self:_configure(room)
			end)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.originals[player.UserId] = nil
		end)
	)
end

function UniformService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.promptConnections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.promptConnections)
	table.clear(self.originals)
end

return UniformService
