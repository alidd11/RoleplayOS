--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local NeedsService = { states = {}, connections = {} }

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
	if not character then
		return nil
	end
	character.Needs = character.Needs or { Hunger = 100 }
	local state = self.states[player.UserId]
	if not state or state.CharacterId ~= character.CharacterId then
		state = {
			CharacterId = character.CharacterId,
			Stamina = 100,
			Hunger = math.clamp(tonumber(character.Needs.Hunger) or 100, 0, 100),
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
	if not state or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return false, "SPRINT_UNAVAILABLE"
	end
	state.Sprinting = sprinting and state.Stamina > 1 and state.Hunger > 2
	return true, nil
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
	if
		state.Sprinting
		and moving
		and state.Stamina > 0
		and state.Hunger > 2
		and not humanoid.Sit
	then
		state.Stamina = math.max(
			0,
			state.Stamina - self.context.Configuration.Needs.StaminaDrainPerSecond * delta
		)
	else
		state.Stamina = math.min(
			100,
			state.Stamina + self.context.Configuration.Needs.StaminaRecoveryPerSecond * delta
		)
	end
	if state.Stamina <= 0 or state.Hunger <= 2 then
		state.Sprinting = false
	end
	state.Hunger =
		math.max(0, state.Hunger - self.context.Configuration.Needs.HungerDrainPerSecond * delta)
	local staminaRatio = state.Stamina / 100
	local speed = self.context.Configuration.Needs.WalkSpeed
	if state.Sprinting then
		speed = self.context.Configuration.Needs.MinimumSprintSpeed
			+ (
					self.context.Configuration.Needs.MaximumSprintSpeed
					- self.context.Configuration.Needs.MinimumSprintSpeed
				)
				* staminaRatio
	elseif state.Hunger < 10 then
		speed *= 0.82
	end
	if player:GetAttribute("RoleplayOSCuffed") then
		state.Sprinting = false
		speed = 7
		humanoid.JumpPower = 0
	else
		humanoid.JumpPower = 50
	end
	humanoid.WalkSpeed = speed
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
				self:_step(player, delta)
			end
		end
	end)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.states[player.UserId] = nil
		end)
	)
end

function NeedsService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.states)
end

return NeedsService
