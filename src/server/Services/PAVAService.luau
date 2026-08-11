--!strict

local Players = game:GetService("Players")

local PAVAService = { effects = {}, cooldowns = {} }

local EFFECT_SECONDS = 30
local MAX_DISTANCE = 18
local MIN_INTERVAL = 0.65
local REDUCED_WALK_SPEED = 10

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function hasPAVA(player: Player): boolean
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		local tool = container and container:FindFirstChild("PAVA")
		if tool and tool:IsA("Tool") and tool:GetAttribute("RoleplayOSToolId") == "PAVA" then
			return true
		end
	end
	return false
end

local function policeDuty(context: any, player: Player): boolean
	local duty = context.Services:Get("DutyService"):Get(player)
	return duty ~= nil and duty.DepartmentId == "Police"
end

function PAVAService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("PAVAEffect")
	self.effects = {}
	self.cooldowns = {}
	self.connections = {}
end

function PAVAService:_restore(target: Player, token: number)
	local record = self.effects[target.UserId]
	if not record or record.Token ~= token then
		return
	end
	local humanoid = humanoidOf(target)
	if humanoid and humanoid:GetAttribute("RoleplayOSPAVAOriginalWalkSpeed") ~= nil then
		local original = humanoid:GetAttribute("RoleplayOSPAVAOriginalWalkSpeed")
		humanoid:SetAttribute("RoleplayOSPAVAOriginalWalkSpeed", nil)
		if type(original) == "number" and humanoid.WalkSpeed == REDUCED_WALK_SPEED then
			humanoid.WalkSpeed = original
		end
	end
	if target.Parent == Players then
		target:SetAttribute("RoleplayOSPAVAffectedUntil", nil)
	end
	self.effects[target.UserId] = nil
	if target.Parent == Players then
		self.event:FireClient(target, { Active = false })
	end
end

function PAVAService:Spray(actor: Player, targetUserId: number): (boolean, string?)
	if not policeDuty(self.context, actor) then
		return false, "POLICE_DUTY_REQUIRED"
	end
	if not hasPAVA(actor) then
		return false, "PAVA_NOT_EQUIPPED"
	end
	local now = os.clock()
	if now - (self.cooldowns[actor.UserId] or 0) < MIN_INTERVAL then
		return false, "PAVA_COOLDOWN"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == actor then
		return false, "PAVA_TARGET_INVALID"
	end
	local actorRoot, targetRoot = rootOf(actor), rootOf(target)
	if
		not actorRoot
		or not targetRoot
		or (actorRoot.Position - targetRoot.Position).Magnitude > MAX_DISTANCE
	then
		return false, "PAVA_TARGET_OUT_OF_RANGE"
	end
	local targetHumanoid = humanoidOf(target)
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false, "PAVA_TARGET_INVALID"
	end
	self.cooldowns[actor.UserId] = now
	local token = now
	local existing = self.effects[target.UserId]
	if existing then
		self:_restore(target, existing.Token)
	end
	local original = targetHumanoid.WalkSpeed
	targetHumanoid:SetAttribute("RoleplayOSPAVAOriginalWalkSpeed", original)
	targetHumanoid.WalkSpeed = math.min(original, REDUCED_WALK_SPEED)
	target:SetAttribute("RoleplayOSPAVAffectedUntil", os.time() + EFFECT_SECONDS)
	self.effects[target.UserId] = { Token = token, ActorUserId = actor.UserId }
	self.event:FireClient(target, { Active = true, Duration = EFFECT_SECONDS })
	task.delay(EFFECT_SECONDS, function()
		self:_restore(target, token)
	end)
	self.context.Logger:Audit("Emergency.PAVAUsed", {
		ActorUserId = actor.UserId,
		Target = tostring(target.UserId),
	})
	return true, nil
end

function PAVAService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.cooldowns[player.UserId] = nil
			local record = self.effects[player.UserId]
			if record then
				self.effects[player.UserId] = nil
			end
		end)
	)
end

function PAVAService:Destroy()
	for _, connection in self.connections or {} do
		connection:Disconnect()
	end
	table.clear(self.connections or {})
	for userId, record in self.effects do
		local target = Players:GetPlayerByUserId(userId)
		if target then
			self:_restore(target, record.Token)
		end
	end
	table.clear(self.effects)
	table.clear(self.cooldowns)
end

return PAVAService
