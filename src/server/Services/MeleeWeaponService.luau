--!strict

local Players = game:GetService("Players")

local MeleeWeaponService =
	{ connections = {}, playerConnections = {}, lastStrike = {}, running = false }

local function root(player: Player): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function humanoid(player: Player): Humanoid?
	return if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
end

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function weaponId(tool: Instance): string?
	local id = tool:GetAttribute("RoleplayOSWeaponId") or tool:GetAttribute("RoleplayOSToolId")
	return if type(id) == "string" then id else nil
end

function MeleeWeaponService:Init(context: any)
	self.context = context
	self.lastStrike = {}
	self.running = false
end

function MeleeWeaponService:_definition(tool: Instance): any?
	local id = weaponId(tool)
	local definition = id and self.context.Configuration.Tools[id]
	return if definition and type(definition.Weapon) == "table" then definition else nil
end

function MeleeWeaponService:IsWeapon(tool: Instance?): boolean
	return tool ~= nil and tool:IsA("Tool") and self:_definition(tool) ~= nil
end

-- Everything bought from a stall goes on death, not only what carries a Weapon
-- block in Config.Tools.
--
-- IsWeapon asks for that block, and the firearms do not have one - they exist as
-- passes and vendor rows only - so a gun used to survive a death that took a
-- knife away. Weapons are bought at a dealer and lost when you die, and that has
-- to mean all of them, including any added later that nobody remembers to
-- define here.
local function isDealerIssued(tool: Instance): boolean
	return tool:GetAttribute("RoleplayOSToolSource") == "Vendor"
		or tool:GetAttribute("RoleplayOSWeaponPurchase") == true
end

function MeleeWeaponService:_clear(player: Player)
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and (self:IsWeapon(child) or isDealerIssued(child)) then
					child:Destroy()
				end
			end
		end
	end
end

function MeleeWeaponService:Seize(actor: Player, targetUserId: number): (any?, string?)
	if not self.running or not playerIsCurrent(actor) then
		return nil, "MELEE_UNAVAILABLE"
	end
	local custody = self.context.Services:Get("CustodyService")
	local authorised = custody:IsAuthorisedForSeizure(actor)
	-- The custody check can yield while DutyService resolves Roblox group access.
	-- Revalidate the exact Player and this service before using that authority.
	if not self.running or not playerIsCurrent(actor) then
		return nil, "MELEE_UNAVAILABLE"
	end
	if not authorised then
		return nil, "NOT_AUTHORISED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local actorRoot, targetRoot = root(actor), target and root(target)
	if not target or not actorRoot or not targetRoot then
		return nil, "TARGET_UNAVAILABLE"
	end
	if
		(actorRoot.Position - targetRoot.Position).Magnitude
		> self.context.Configuration.Custody.MaximumInteractionDistance
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local seized = {}
	for _, container in { target.Character, target:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if self:IsWeapon(child) then
					table.insert(seized, weaponId(child) or child.Name)
					child:Destroy()
				end
			end
		end
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = actor.UserId,
		Action = "Custody.WeaponsSeized",
		Target = tostring(targetUserId),
		Metadata = { Weapons = seized },
	})
	return { TargetUserId = targetUserId, Weapons = seized }, nil
end

function MeleeWeaponService:Strike(player: Player, targetUserId: number): (any?, string?)
	if not self.running or not playerIsCurrent(player) then
		return nil, "MELEE_UNAVAILABLE"
	end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local definition = tool and self:_definition(tool)
	if not tool or not definition then
		return nil, "WEAPON_NOT_EQUIPPED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return nil, "INVALID_TARGET"
	end
	local attackerRoot, targetRoot = root(player), root(target)
	local targetHumanoid = humanoid(target)
	if not attackerRoot or not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		return nil, "TARGET_UNAVAILABLE"
	end
	local weapon = definition.Weapon
	local range = math.clamp(tonumber(weapon.Range) or 8, 4, 12)
	if (attackerRoot.Position - targetRoot.Position).Magnitude > range then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local now = os.clock()
	local cooldown = math.clamp(tonumber(weapon.Cooldown) or 0.7, 0.25, 3)
	if now - (self.lastStrike[player.UserId] or 0) < cooldown then
		return nil, "WEAPON_COOLDOWN"
	end
	self.lastStrike[player.UserId] = now
	local direction = targetRoot.Position - attackerRoot.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, target.Character }
	if workspace:Raycast(attackerRoot.Position, direction, params) then
		return nil, "TARGET_BLOCKED"
	end
	targetHumanoid:TakeDamage(math.clamp(tonumber(weapon.Damage) or 18, 1, 40))
	return { TargetUserId = targetUserId, WeaponId = weaponId(tool) }, nil
end

function MeleeWeaponService:Start()
	self.running = true
	self.playerConnections = {}

	local function disconnectPlayer(userId: number)
		local connections = self.playerConnections[userId]
		if not connections then
			return
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		self.playerConnections[userId] = nil
	end

	local function watchCharacter(player: Player, character: Model)
		local connections = self.playerConnections[player.UserId]
		if not connections then
			return
		end
		self.lastStrike[player.UserId] = nil
		if connections.Death then
			connections.Death:Disconnect()
			connections.Death = nil
		end
		local death = character:FindFirstChildOfClass("Humanoid")
		if death then
			connections.Death = death.Died:Connect(function()
				self:_clear(player)
			end)
		end
	end

	local function watch(player: Player)
		disconnectPlayer(player.UserId)
		local connections: any = {}
		self.playerConnections[player.UserId] = connections
		connections.CharacterAdded = player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		connections.CharacterRemoving = player.CharacterRemoving:Connect(function()
			self.lastStrike[player.UserId] = nil
			if connections.Death then
				connections.Death:Disconnect()
				connections.Death = nil
			end
		end)
		local character = player.Character
		if character then
			watchCharacter(player, character)
		end
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.lastStrike[player.UserId] = nil
			disconnectPlayer(player.UserId)
		end)
	)
end

function MeleeWeaponService:Destroy()
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
	table.clear(self.lastStrike)
	self.running = false
end

return MeleeWeaponService
