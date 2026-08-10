--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapProjection = require(ReplicatedStorage.RoleplayOS.Shared.MapProjection)

local EmergencyTriggerService = {
	connections = {},
	cooldowns = {},
	playerCooldowns = {},
	panicCooldowns = {},
}

function EmergencyTriggerService:Init(context: any)
	self.context = context
	self.event = context.Network:RegisterEvent("EmergencyAlert")
end

function EmergencyTriggerService:_departments(instance: Instance, incident: any): { string }
	local configured = instance:GetAttribute("Departments")
	if type(configured) ~= "string" or configured == "" then
		return table.clone(incident.Departments)
	end
	local result = {}
	for value in string.gmatch(configured, "[^,%s]+") do
		if self.context.Configuration.Departments[value] and not table.find(result, value) then
			table.insert(result, value)
		end
	end
	return if #result > 0 then result else table.clone(incident.Departments)
end

function EmergencyTriggerService:_near(player: Player, instance: Instance, maximum: number): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local position = if instance:IsA("BasePart")
		then instance.Position
		elseif instance:IsA("Model") then instance:GetPivot().Position
		else nil
	return root ~= nil and position ~= nil and (root.Position - position).Magnitude <= maximum
end

function EmergencyTriggerService:Trigger(instance: Instance, player: Player?): (any?, string?)
	local config = self.context.Configuration.EmergencyTriggers
	if
		not CollectionService:HasTag(instance, config.Tag) or not instance:IsDescendantOf(workspace)
	then
		return nil, "UNAUTHORISED_TRIGGER"
	end
	local incidentId = instance:GetAttribute("IncidentType")
	local incident = type(incidentId) == "string" and config.Incidents[incidentId] or nil
	if not incident then
		return nil, "UNKNOWN_INCIDENT"
	end
	local now = os.clock()
	local cooldown = math.clamp(
		tonumber(instance:GetAttribute("CooldownSeconds")) or incident.CooldownSeconds,
		5,
		900
	)
	if (self.cooldowns[instance] or 0) > now then
		return nil, "TRIGGER_COOLDOWN"
	end
	if player then
		if not self:_near(player, instance, config.MaximumActivationDistance) then
			return nil, "TRIGGER_TOO_FAR"
		end
		if (self.playerCooldowns[player.UserId] or 0) > now then
			return nil, "PLAYER_TRIGGER_COOLDOWN"
		end
		self.playerCooldowns[player.UserId] = now + config.PlayerCooldownSeconds
	end
	self.cooldowns[instance] = now + cooldown
	local departments = self:_departments(instance, incident)
	local call, reason = self.context.Services:Get("CallService"):Create({
		Priority = incident.Priority,
		Summary = tostring(instance:GetAttribute("Summary") or incident.Summary),
		Location = tostring(instance:GetAttribute("Location") or instance.Name),
		-- The trigger itself is the incident location, so alarms and panic
		-- points plot exactly where they were activated.
		Position = if instance:IsA("BasePart")
			then MapProjection.serialise(instance.Position)
			else nil,
		DepartmentIds = departments,
		Source = "AutomaticTrigger",
	})
	if not call then
		return nil, reason
	end
	for _, target in Players:GetPlayers() do
		local duty = self.context.Services:Get("DutyService"):Get(target)
		if duty and table.find(departments, duty.DepartmentId) then
			self.event:FireClient(target, { Call = call, ServerId = game.JobId })
		end
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = if player then player.UserId else 0,
		Action = "Emergency.Trigger",
		Target = tostring(incidentId),
		Metadata = { CallId = call.CallId, Departments = departments, ServerId = game.JobId },
	})
	return call, nil
end

function EmergencyTriggerService:Panic(player: Player): (any?, string?)
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if not duty then
		return nil, "NOT_ON_DUTY"
	end
	local now = os.clock()
	if (self.panicCooldowns[player.UserId] or 0) > now then
		return nil, "PANIC_COOLDOWN"
	end
	self.panicCooldowns[player.UserId] = now + 30
	local callsign = duty.Callsign or string.format("UNIT-%d", player.UserId % 1000)
	local departments = { duty.DepartmentId }
	if duty.DepartmentId ~= "Control" then
		table.insert(departments, "Control")
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local call, reason = self.context.Services:Get("CallService"):Create({
		Priority = "Immediate",
		Summary = callsign .. " PANIC BUTTON",
		Location = "UNIT PANIC / " .. callsign,
		Position = if root and root:IsA("BasePart")
			then MapProjection.serialise(root.Position)
			else nil,
		DepartmentIds = departments,
		Source = "RadioPanic",
	})
	if not call then
		return nil, reason
	end
	for _, target in Players:GetPlayers() do
		local targetDuty = self.context.Services:Get("DutyService"):Get(target)
		if targetDuty then
			self.event:FireClient(target, { Call = call, ServerId = game.JobId })
		end
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Emergency.RadioPanic",
		Target = call.CallId,
		Metadata = { Callsign = callsign, Departments = departments, ServerId = game.JobId },
	})
	return call, nil
end

function EmergencyTriggerService:_watch(instance: Instance)
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	table.insert(
		self.connections,
		prompt.Triggered:Connect(function(player)
			self:Trigger(instance, player)
		end)
	)
end

function EmergencyTriggerService:Start()
	for _, instance in CollectionService:GetTagged(self.context.Configuration.EmergencyTriggers.Tag) do
		self:_watch(instance)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.context.Configuration.EmergencyTriggers.Tag)
			:Connect(function(instance)
				self:_watch(instance)
			end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self.playerCooldowns[player.UserId] = nil
		end)
	)
end

function EmergencyTriggerService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cooldowns)
	table.clear(self.playerCooldowns)
	table.clear(self.panicCooldowns)
end

return EmergencyTriggerService
