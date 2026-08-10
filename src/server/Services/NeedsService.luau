--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local NeedsService = { states = {}, connections = {}, failureLog = {} }

function NeedsService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("NeedsChanged")
end

function NeedsService:_character(player: Player): any?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
end

function NeedsService:_state(player: Player): any?
	local character = self:_character(player)
	-- Moment-to-moment movement must still work while a profile is loading or
	-- before an RP character is selected. Hunger becomes persistent as soon as a
	-- character exists; until then this is a safe session-only state.
	local characterId = if character then character.CharacterId else "player:" .. player.UserId
	if character then
		character.Needs = character.Needs or { Hunger = 100 }
	end
	local state = self.states[player.UserId]
	if not state or state.CharacterId ~= characterId then
		state = {
			CharacterId = characterId,
			Stamina = 100,
			Hunger = math.clamp(
				if character then tonumber(character.Needs.Hunger) or 100 else 100,
				0,
				100
			),
			Sprinting = false,
			LastSent = 0,
			LastPersist = os.clock(),
		}
		self.states[player.UserId] = state
	end
	return state
end

function NeedsService:Snapshot(player: Player): (any?, string?)
	local state = self:_state(player)
	return if state
		then { Stamina = state.Stamina, Hunger = state.Hunger, Sprinting = state.Sprinting }
		else nil,
		if state then nil else "ACTIVE_CHARACTER_REQUIRED"
end

function NeedsService:SetSprinting(player: Player, sprinting: any): (boolean, string?)
	if type(sprinting) ~= "boolean" then
		return false, "INVALID_SPRINT_STATE"
	end
	local state = self:_state(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not state or not humanoid or humanoid.Health <= 0 then
		return false, "SPRINT_UNAVAILABLE"
	end
	-- Sitting is its own answer, not a failure. Everything used to collapse into
	-- one code, so pressing shift in a car told the driver they could not run
	-- right now, which is true, useless, and indistinguishable from being too
	-- tired.
	if humanoid.Sit then
		return false, "SPRINT_WHILE_SEATED"
	end
	-- Being out of breath or hungry now reports as a refusal.
	--
	-- This assigned `sprinting and stamina > 1 and hunger > 2` and then returned
	-- success unconditionally, so the one case a player most needs explaining —
	-- holding shift and simply not running — was reported as having worked. The
	-- key looked broken because the server said yes and did nothing.
	if sprinting then
		if state.Stamina <= 1 then
			return false, "SPRINT_EXHAUSTED"
		end
		if state.Hunger <= 2 then
			return false, "SPRINT_TOO_HUNGRY"
		end
	end
	state.Sprinting = sprinting
	-- Apply the speed now rather than waiting for the next tick. The step loop
	-- runs twice a second, so deferring left up to half a second of dead input
	-- after the key went down, which reads as the sprint key not working.
	self:_applySpeed(player, state, humanoid)
	return true, nil
end

-- How much fitness the character has earned, as fractions to scale drain and
-- recovery by.
--
-- Read from the level they already have rather than from a second counter, so
-- there is one notion of how far along somebody is and playing the game is what
-- moves it. A character with no progression yet is simply at the bottom of the
-- curve, which is the same place everybody starts.
function NeedsService:_fitness(
	player: Player,
	state: any
): { DrainReduction: number, RecoveryBonus: number }
	local settings = self.context.Configuration.Needs.Fitness
	local none = { DrainReduction = 0, RecoveryBonus = 0 }
	if type(settings) ~= "table" then
		return none
	end
	-- Cached, because this runs twice a second for every player and resolving a
	-- level walks the whole experience curve and rebuilds every track summary
	-- underneath it. At a full server that is sixty of those a second to answer a
	-- question whose answer changes a few times an hour.
	local now = os.clock()
	if state.Fitness and now - (state.FitnessAt or 0) < 15 then
		return state.Fitness
	end
	state.FitnessAt = now
	local ok, summary = pcall(function()
		return self.context.Services:Get("ProgressionService"):Get(player)
	end)
	local level = if ok and type(summary) == "table" then tonumber(summary.Level) else nil
	if not level then
		state.Fitness = none
		return none
	end
	local progress = math.clamp((level - 1) / math.max(settings.FullBonusLevel - 1, 1), 0, 1)
	state.Fitness = {
		DrainReduction = settings.MaximumDrainReduction * progress,
		RecoveryBonus = settings.MaximumRecoveryBonus * progress,
	}
	return state.Fitness
end

-- Resolves the walk speed implied by the current needs state. Shared by the
-- step loop and by immediate state changes so the two cannot disagree.
function NeedsService:_applySpeed(player: Player, state: any, humanoid: Humanoid)
	local needs = self.context.Configuration.Needs
	local speed = needs.WalkSpeed
	if state.Sprinting then
		speed = needs.MinimumSprintSpeed
			+ (needs.MaximumSprintSpeed - needs.MinimumSprintSpeed) * (state.Stamina / 100)
	elseif state.Hunger < 10 then
		speed *= 0.82
	end
	if player:GetAttribute("RoleplayOSCuffed") then
		state.Sprinting = false
		speed = 7
		-- Jumping is disabled by state rather than by JumpPower. JumpPower only
		-- applies when Humanoid.UseJumpPower is true, and that defaults to false
		-- in modern experiences, so writing zero to it did nothing at all and a
		-- cuffed suspect could simply jump away.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	humanoid.WalkSpeed = speed
end

-- The starter meal, as a held item.
--
-- Built here rather than loaded from ServerStorage because the content audit
-- reports twenty one assets missing and every tool that depends on one is
-- currently unavailable. A first item that does not appear is worse than no
-- first item, so this one has no asset to be missing.
function NeedsService:_makeFoodTool(name: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = "Eat it. There is only the one."
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.9, 0.28, 0.72)
	handle.Color = Color3.fromRGB(214, 176, 116)
	handle.Material = Enum.Material.Sand
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local filling = Instance.new("Part")
	filling.Name = "Filling"
	filling.Size = Vector3.new(0.82, 0.1, 0.66)
	filling.Color = Color3.fromRGB(124, 168, 92)
	filling.Material = Enum.Material.SmoothPlastic
	filling.CanCollide = false
	filling.Massless = true
	filling.CFrame = handle.CFrame
	filling.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = filling
	weld.Parent = filling
	-- Translation before rotation, matching the phone and the credentials, so
	-- the offset is applied before the frame turns rather than inside it.
	tool.Grip = CFrame.new(0, -0.1, -0.45) * CFrame.Angles(math.rad(90), 0, 0)
	return tool
end

-- Eats it: restores hunger, takes it out of the inventory, and destroys itself.
--
-- Activated fires on the server, so nothing about this trusts the client. The
-- attribute is the guard against a player activating twice before the tool is
-- destroyed, which would otherwise feed them twice from one sandwich.
function NeedsService:_eat(player: Player, tool: Tool, foodId: string)
	if tool:GetAttribute("RoleplayOSEaten") then
		return
	end
	tool:SetAttribute("RoleplayOSEaten", true)
	local food = self.context.Configuration.Needs.Foods[foodId]
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local state = self:_state(player)
	local character = self:_character(player)
	if not food or not session or not session.ActiveCharacterId or not state or not character then
		tool:SetAttribute("RoleplayOSEaten", nil)
		return
	end
	local removed = self.context.Services
		:Get("InventoryService")
		:Remove(player, session.ActiveCharacterId, foodId, 1)
	if not removed then
		-- Not carrying it any more, so this is a stale tool from a life that
		-- already ate. Destroy it rather than feed them from nothing.
		tool:Destroy()
		return
	end
	state.Hunger = math.clamp(state.Hunger + food.Hunger, 0, 100)
	character.Needs = { Hunger = state.Hunger }
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.event:FireClient(
		player,
		{ Stamina = state.Stamina, Hunger = state.Hunger, Sprinting = state.Sprinting }
	)
	tool:Destroy()
end

-- Grants the starter meal, and hands back the one already owned after a respawn.
--
-- Idempotent, because respawning empties the backpack but not the inventory. A
-- character who has been granted it and eaten it gets nothing; one who has been
-- granted it and still carries it gets the tool back.
function NeedsService:EnsureStarterFood(player: Player)
	local settings = self.context.Configuration.Needs.StarterFood
	if not settings or settings.Enabled ~= true then
		return
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = self:_character(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not backpack or not session or not session.ActiveCharacterId then
		return
	end
	local foodId = settings.FoodId
	local food = self.context.Configuration.Needs.Foods[foodId]
	if not food then
		return
	end
	local inventory = self.context.Services:Get("InventoryService")
	if not character.StarterFoodGranted then
		local added = inventory:Add(player, session.ActiveCharacterId, foodId, 1)
		if not added then
			return
		end
		-- Recorded outside Needs on purpose: Needs is replaced wholesale whenever
		-- hunger is written, so a flag kept in there would be erased by the next
		-- mouthful.
		character.StarterFoodGranted = true
		self.context.Services:Get("DataService"):MarkDirty(player)
	elseif not inventory:Has(character, foodId) then
		return
	end
	if
		backpack:FindFirstChild(food.Name)
		or (player.Character and player.Character:FindFirstChild(food.Name))
	then
		return
	end
	local tool = self:_makeFoodTool(food.Name)
	tool.Activated:Connect(function()
		self:_eat(player, tool, foodId)
	end)
	tool.Parent = backpack
end

function NeedsService:PurchaseFood(player: Player, foodId: any): (any?, string?)
	if type(foodId) ~= "string" then
		return nil, "INVALID_FOOD"
	end
	local food = self.context.Configuration.Needs.Foods[foodId]
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local state = self:_state(player)
	if not food or not session or not session.ActiveCharacterId or not state then
		return nil, "INVALID_FOOD"
	end
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = session.ActiveCharacterId,
		Amount = food.Price,
		Direction = "Debit",
		ReasonCode = "Food.Purchase",
		RelatedEntityId = foodId,
	})
	if not paid then
		return nil, reason
	end
	state.Hunger = math.clamp(state.Hunger + food.Hunger, 0, 100)
	local character = self:_character(player)
	if character then
		character.Needs = { Hunger = state.Hunger }
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	self.event:FireClient(
		player,
		{ Stamina = state.Stamina, Hunger = state.Hunger, Sprinting = state.Sprinting }
	)
	return { FoodId = foodId, Hunger = state.Hunger }, nil
end

function NeedsService:_step(player: Player, delta: number)
	local state = self:_state(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not state or not humanoid then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.05
	local needs = self.context.Configuration.Needs
	local fitness = self:_fitness(player, state)
	if
		state.Sprinting
		and moving
		and state.Stamina > 0
		and state.Hunger > 2
		and not humanoid.Sit
	then
		state.Stamina = math.max(
			0,
			state.Stamina - needs.StaminaDrainPerSecond * (1 - fitness.DrainReduction) * delta
		)
	else
		state.Stamina = math.min(
			100,
			state.Stamina + needs.StaminaRecoveryPerSecond * (1 + fitness.RecoveryBonus) * delta
		)
	end
	if state.Stamina <= 0 or state.Hunger <= 2 then
		state.Sprinting = false
	end
	state.Hunger =
		math.max(0, state.Hunger - self.context.Configuration.Needs.HungerDrainPerSecond * delta)
	self:_applySpeed(player, state, humanoid)
	local now = os.clock()
	local lastPayload = state.LastPayload
	local materiallyChanged = not lastPayload
		or lastPayload.Sprinting ~= state.Sprinting
		or math.abs(lastPayload.Stamina - state.Stamina) >= 1
		or math.abs(lastPayload.Hunger - state.Hunger) >= 1
	if materiallyChanged and now - state.LastSent >= 0.5 then
		state.LastSent = now
		state.LastPayload =
			{ Stamina = state.Stamina, Hunger = state.Hunger, Sprinting = state.Sprinting }
		self.event:FireClient(
			player,
			{ Stamina = state.Stamina, Hunger = state.Hunger, Sprinting = state.Sprinting }
		)
	end
	local character = self:_character(player)
	if character then
		character.Needs = { Hunger = state.Hunger }
	end
	if now - state.LastPersist >= 60 then
		state.LastPersist = now
		self.context.Services:Get("DataService"):MarkDirty(player)
	end
end

-- Reports a failure without flooding the log. This runs twice a second for every
-- player, so a fault that repeats would write thousands of identical lines and
-- bury whatever else went wrong.
function NeedsService:_noteFailure(userId: number, problem: any)
	local at = os.clock()
	local previous = self.failureLog[userId]
	if previous and at - previous < 60 then
		return
	end
	self.failureLog[userId] = at
	self.context.Logger:Error("Needs step failed", {
		UserId = userId,
		Error = tostring(problem),
	})
end

function NeedsService:Start()
	self.running = true
	task.spawn(function()
		local last = os.clock()
		while self.running do
			task.wait(0.5)
			local now = os.clock()
			local delta = math.min(now - last, 1)
			last = now
			for _, player in Players:GetPlayers() do
				-- Guarded per player. A throw here used to end the loop outright,
				-- and this loop is the whole of stamina, hunger and sprinting: one
				-- player in an odd state would have frozen all three for everybody
				-- in the server, silently, until it restarted.
				local ok, problem = pcall(self._step, self, player, delta)
				if not ok then
					self:_noteFailure(player.UserId, problem)
				end
			end
		end
	end)
	-- Per-player handlers are held against the player rather than pushed onto the
	-- service-wide list, which is only emptied when the server shuts down. Every
	-- join added an entry there that nothing ever removed, so a busy server spent
	-- an evening accumulating one dead closure per join and walked the lot at
	-- shutdown. Disconnecting on the way out also means a player who rejoins the
	-- same server cannot end up with two handlers running for one spawn.
	self.playerConnections = {}
	local function forget(player: Player)
		local connection = self.playerConnections[player.UserId]
		if connection then
			connection:Disconnect()
			self.playerConnections[player.UserId] = nil
		end
	end
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			forget(player)
			self.states[player.UserId] = nil
			self.failureLog[player.UserId] = nil
		end)
	)
	-- Handed out on every spawn rather than only on the first, because a respawn
	-- empties the backpack and the check above decides whether anything is
	-- actually owed.
	local function watch(player: Player)
		forget(player)
		self.playerConnections[player.UserId] = player.CharacterAdded:Connect(function()
			task.defer(function()
				-- Guarded, because a deferred throw goes nowhere. This is how
				-- the starter meal failed silently for a character whose
				-- inventory container predated the field: no item, no error,
				-- and nothing to suggest the feature existed at all.
				local ok, problem = pcall(self.EnsureStarterFood, self, player)
				if not ok then
					self.context.Logger:Warning("Starter food could not be granted", {
						UserId = player.UserId,
						Error = tostring(problem),
					})
				end
			end)
		end)
		if player.Character then
			task.defer(function()
				local ok, problem = pcall(self.EnsureStarterFood, self, player)
				if not ok then
					self.context.Logger:Warning("Starter food could not be granted", {
						UserId = player.UserId,
						Error = tostring(problem),
					})
				end
			end)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function NeedsService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, connection in self.playerConnections or {} do
		connection:Disconnect()
	end
	table.clear(self.playerConnections or {})
	table.clear(self.states)
end

return NeedsService
