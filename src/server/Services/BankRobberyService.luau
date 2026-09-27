--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local BankRobberyService = {
	connections = {},
	promptConnections = {},
	states = {},
	activePlayers = {},
	running = false,
}

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function playerIsCurrent(player: Player): boolean
	return player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function BankRobberyService:Init(context: any)
	self.context = context
	table.clear(self.connections)
	table.clear(self.promptConnections)
	table.clear(self.states)
	table.clear(self.activePlayers)
end

function BankRobberyService:_near(player: Player, target: Instance, maximum: number): boolean
	local root = rootOf(player)
	local position = positionOf(target)
	return root ~= nil and position ~= nil and (root.Position - position).Magnitude <= maximum
end

function BankRobberyService:_activeCharacter(player: Player): (string?, any?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	local character = characterId and session.Profile.Characters[characterId]
	return characterId, character
end

function BankRobberyService:_startClaimIsCurrent(
	target: Instance,
	state: any,
	player: Player,
	robberyId: string
): boolean
	return self.running
		and playerIsCurrent(player)
		and target:IsDescendantOf(workspace)
		and self.states[target] == state
		and state.Starting == true
		and state.Active ~= true
		and state.RobberyId == robberyId
		and state.PlayerUserId == player.UserId
		and self.activePlayers[player.UserId] == robberyId
end

function BankRobberyService:_releaseStartClaim(
	target: Instance,
	state: any,
	player: Player,
	robberyId: string
)
	if self.states[target] == state and state.Starting == true and state.RobberyId == robberyId then
		state.Starting = false
		state.RobberyId = nil
		state.PlayerUserId = nil
		local prompt = state.Prompt
		if self.running and target.Parent and prompt and prompt.Parent then
			prompt.Enabled = true
		end
	end
	if self.activePlayers[player.UserId] == robberyId then
		self.activePlayers[player.UserId] = nil
	end
end

function BankRobberyService:_alarm(target: Instance, player: Player): (boolean, BasePart?)
	local position = positionOf(target)
	if not position then
		return false, nil
	end
	local alarm = Instance.new("Part")
	alarm.Name = "Bank robbery alarm"
	alarm.Size = Vector3.one
	alarm.CFrame = CFrame.new(position)
	alarm.Anchored = true
	alarm.CanCollide = false
	alarm.CanQuery = false
	alarm.CanTouch = false
	alarm.Transparency = 1
	alarm:SetAttribute("IncidentType", "BankRobbery")
	alarm:SetAttribute("Location", tostring(target:GetAttribute("Location") or target.Name))
	local sound = Instance.new("Sound")
	sound.Name = "RoleplayOSBankAlarm"
	sound.SoundId = self.context.Configuration.BankRobbery.AlarmSoundId
	sound.Volume = self.context.Configuration.BankRobbery.AlarmVolume
	sound.Looped = true
	sound.RollOffMaxDistance = self.context.Configuration.BankRobbery.AlarmMaxDistance
	sound.Parent = alarm
	alarm.Parent = workspace
	CollectionService:AddTag(alarm, self.context.Configuration.EmergencyTriggers.Tag)
	local triggered, call, reason = pcall(function()
		return self.context.Services:Get("EmergencyTriggerService"):Trigger(alarm, nil)
	end)
	if not triggered then
		self.context.Logger:Error("Bank robbery alarm handler failed", {
			UserId = player.UserId,
			Error = tostring(call),
		})
		alarm:Destroy()
		return false, nil
	end
	if not call then
		self.context.Logger:Warning("Bank robbery alarm could not be raised", {
			UserId = player.UserId,
			Reason = reason,
		})
		alarm:Destroy()
		return false, nil
	end
	-- Trigger broadcasts to on-duty users and can therefore yield through their
	-- access checks. Do not leave a late alarm behind after the service, target or
	-- initiating player has gone away.
	if not self.running or not target:IsDescendantOf(workspace) or not playerIsCurrent(player) then
		alarm:Destroy()
		return false, nil
	end
	sound:Play()
	return true, alarm
end

function BankRobberyService:_clearAlarm(state: any)
	local alarm = state and state.Alarm
	if alarm and alarm.Parent then
		alarm:Destroy()
	end
	if state then
		state.Alarm = nil
	end
end

function BankRobberyService:_finish(target: Instance, player: Player, robberyId: string)
	local config = self.context.Configuration.BankRobbery
	local state = self.states[target]
	if not self.running or not state or state.RobberyId ~= robberyId then
		return
	end
	local prompt = state.Prompt
	local characterId, character = self:_activeCharacter(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if
		player.Parent ~= Players
		or not characterId
		or not character
		or not humanoid
		or humanoid.Health <= 0
		or not self:_near(player, target, config.CompletionDistance)
	then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "BankRobbery.Failed",
			Target = robberyId,
			Metadata = { Location = target.Name },
		})
		state.Active = false
		self:_clearAlarm(state)
		self.activePlayers[player.UserId] = nil
		state.CooldownUntil = os.clock() + config.FailedCooldownSeconds
		task.delay(config.FailedCooldownSeconds, function()
			if
				self.running
				and target.Parent
				and self.states[target] == state
				and prompt.Parent
			then
				prompt.Enabled = true
			end
		end)
		return
	end
	local minimum = math.floor(config.MinimumReward)
	local maximum = math.floor(config.MaximumReward)
	local amount = math.random(minimum, maximum)
	local paid, reason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Account = "Cash",
		Amount = amount,
		Direction = "Credit",
		ReasonCode = "BANK_ROBBERY",
		Description = "Cash taken during a bank robbery",
		RelatedEntityId = robberyId,
		Metadata = { Location = target.Name },
	})
	if paid then
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			CharacterId = characterId,
			Action = "BankRobbery.Completed",
			Target = robberyId,
			Metadata = { Amount = amount, Account = "Cash", Location = target.Name },
		})
	else
		self.context.Logger:Error("Bank robbery reward failed", {
			UserId = player.UserId,
			RobberyId = robberyId,
			Reason = reason,
		})
	end
	state.Active = false
	self:_clearAlarm(state)
	self.activePlayers[player.UserId] = nil
	state.CooldownUntil = os.clock() + config.CooldownSeconds
	task.delay(config.CooldownSeconds, function()
		if self.running and target.Parent and self.states[target] == state and prompt.Parent then
			prompt.Enabled = true
		end
	end)
end

function BankRobberyService:Begin(target: Instance, player: Player): (boolean, string?)
	local config = self.context.Configuration.BankRobbery
	local state = self.states[target]
	if not self.running or not playerIsCurrent(player) then
		return false, "ROBBERY_UNAVAILABLE"
	end
	if not CollectionService:HasTag(target, config.Tag) or not target:IsDescendantOf(workspace) then
		return false, "UNAUTHORISED_TARGET"
	end
	if not state or state.Active or state.Starting or (state.CooldownUntil or 0) > os.clock() then
		return false, "ROBBERY_UNAVAILABLE"
	end
	if self.activePlayers[player.UserId] then
		return false, "ROBBERY_ALREADY_ACTIVE"
	end
	local characterId = self:_activeCharacter(player)
	if not characterId then
		return false, "ACTIVE_CHARACTER_REQUIRED"
	end
	if not self:_near(player, target, config.ActivationDistance) then
		return false, "TOO_FAR"
	end

	-- Claim both resources before DutyService:Get. That getter can yield while
	-- Roblox answers a group lookup; without this claim, two prompt callbacks can
	-- both observe the same free bank (or the same free player) and both continue
	-- into alarm creation.
	local robberyId = HttpService:GenerateGUID(false)
	state.Starting = true
	state.RobberyId = robberyId
	state.PlayerUserId = player.UserId
	self.activePlayers[player.UserId] = robberyId
	state.Prompt.Enabled = false

	local dutyChecked, duty = pcall(function()
		return self.context.Services:Get("DutyService"):Get(player)
	end)
	if not dutyChecked then
		self:_releaseStartClaim(target, state, player, robberyId)
		self.context.Logger:Warning("Bank robbery duty check failed", {
			UserId = player.UserId,
			Error = tostring(duty),
		})
		return false, "ROBBERY_UNAVAILABLE"
	end
	if not self:_startClaimIsCurrent(target, state, player, robberyId) then
		self:_releaseStartClaim(target, state, player, robberyId)
		return false, if playerIsCurrent(player) then "ROBBERY_UNAVAILABLE" else "PLAYER_LEFT"
	end
	if duty then
		self:_releaseStartClaim(target, state, player, robberyId)
		return false, "CIVILIAN_REQUIRED"
	end

	local alarmRaised, alarm = self:_alarm(target, player)
	if not alarmRaised then
		self:_releaseStartClaim(target, state, player, robberyId)
		return false, "ROBBERY_ALARM_FAILED"
	end
	if not self:_startClaimIsCurrent(target, state, player, robberyId) then
		if alarm then
			alarm:Destroy()
		end
		self:_releaseStartClaim(target, state, player, robberyId)
		return false, if playerIsCurrent(player) then "ROBBERY_UNAVAILABLE" else "PLAYER_LEFT"
	end

	state.Starting = false
	state.Active = true
	state.Alarm = alarm
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		CharacterId = characterId,
		Action = "BankRobbery.Started",
		Target = robberyId,
		Metadata = { Location = target.Name },
	})
	task.delay(config.RobberyDurationSeconds, function()
		self:_finish(target, player, robberyId)
	end)
	return true, nil
end

function BankRobberyService:_watch(target: Instance)
	if self.states[target] then
		return
	end
	local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		self.context.Logger:Warning(
			"Bank robbery target has no ProximityPrompt",
			{ Target = target.Name }
		)
		return
	end
	prompt.MaxActivationDistance = math.min(
		prompt.MaxActivationDistance,
		self.context.Configuration.BankRobbery.ActivationDistance
	)
	self.states[target] = { Active = false, Starting = false, CooldownUntil = 0, Prompt = prompt }
	self.promptConnections[target] = prompt.Triggered:Connect(function(player)
		self:Begin(target, player)
	end)
end

function BankRobberyService:Start()
	self.running = true
	local tag = self.context.Configuration.BankRobbery.Tag
	for _, target in CollectionService:GetTagged(tag) do
		self:_watch(target)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(target)
			self:_watch(target)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(target)
			local state = self.states[target]
			if state and state.PlayerUserId then
				self.activePlayers[state.PlayerUserId] = nil
			end
			self:_clearAlarm(state)
			local connection = self.promptConnections[target]
			if connection then
				connection:Disconnect()
			end
			self.promptConnections[target] = nil
			self.states[target] = nil
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			local robberyId = self.activePlayers[player.UserId]
			self.activePlayers[player.UserId] = nil
			if not robberyId then
				return
			end
			-- An in-progress robbery keeps its normal completion/failure path. A
			-- start that is still yielding has not begun gameplay yet, so release
			-- that provisional target claim immediately instead of leaving the bank
			-- disabled until the lookup returns.
			for target, state in self.states do
				if
					state.Starting == true
					and state.PlayerUserId == player.UserId
					and state.RobberyId == robberyId
				then
					state.Starting = false
					state.RobberyId = nil
					state.PlayerUserId = nil
					local prompt = state.Prompt
					if self.running and target.Parent and prompt and prompt.Parent then
						prompt.Enabled = true
					end
					break
				end
			end
		end)
	)
end

function BankRobberyService:Destroy()
	self.running = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.promptConnections do
		connection:Disconnect()
	end
	for _, state in self.states do
		self:_clearAlarm(state)
	end
	table.clear(self.connections)
	table.clear(self.promptConnections)
	table.clear(self.states)
	table.clear(self.activePlayers)
end

return BankRobberyService
