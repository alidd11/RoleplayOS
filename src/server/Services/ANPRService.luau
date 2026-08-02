--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ANPRService = { connections = {}, cooldowns = {} }

function ANPRService:Init(context: any)
	self.context = context
	self.alertEvent = context.Network:RegisterEvent("ANPRAlert")
end

function ANPRService:_alertPlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		local duty = self.context.Services:Get("DutyService"):Get(player)
		if
			duty
			and (
				duty.RoleId == self.context.Configuration.ANPR.RoadsRoleId
				or duty.DepartmentId == "Control"
			)
		then
			table.insert(result, player)
		end
	end
	return result
end

function ANPRService:_vehicleFromHit(hit: BasePart): Model?
	local current: Instance? = hit
	while current and current ~= workspace do
		if
			current:IsA("Model")
			and type(current:GetAttribute("RoleplayOSRegistration")) == "string"
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

function ANPRService:_scan(sensor: BasePart, hit: BasePart)
	local model = self:_vehicleFromHit(hit)
	if not model then
		return
	end
	local registration = model:GetAttribute("RoleplayOSRegistration")
	if type(registration) ~= "string" then
		return
	end
	local key = sensor:GetDebugId() .. ":" .. registration
	local now = os.clock()
	if (self.cooldowns[key] or 0) > now then
		return
	end
	self.cooldowns[key] = now + self.context.Configuration.ANPR.CooldownSeconds
	local vehicle =
		self.context.Services:Get("VehicleOwnershipService"):GetByRegistration(registration)
	if not vehicle then
		return
	end
	local wanted =
		self.context.Services:Get("WarrantService"):HasActiveForCharacter(vehicle.OwnerCharacterId)
	if not wanted then
		return
	end
	local location = sensor:GetAttribute("Location") or sensor.Name
	local call = self.context.Services:Get("CallService"):Create({
		Summary = "ANPR hit: wanted vehicle " .. registration,
		Location = location,
		Priority = "Immediate",
		IncidentType = "Crime in progress",
		DepartmentIds = { "Police", "Control" },
		Source = "ANPR",
		CallerName = "Automatic Number Plate Recognition",
	})
	local payload = {
		Registration = registration,
		Location = location,
		CameraId = sensor:GetAttribute("CameraId"),
		CallId = if call then call.CallId else nil,
		DetectedAt = os.time(),
	}
	for _, player in self:_alertPlayers() do
		self.alertEvent:FireClient(player, payload)
	end
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = 0,
		Action = "ANPR.WantedVehicleDetected",
		Target = registration,
		Metadata = { Location = location },
	})
end

function ANPRService:_watch(instance: Instance)
	if
		not instance:IsA("BasePart")
		or #self.connections >= self.context.Configuration.ANPR.MaximumSensors
	then
		return
	end
	table.insert(
		self.connections,
		instance.Touched:Connect(function(hit)
			self:_scan(instance, hit)
		end)
	)
end

function ANPRService:Start()
	for _, sensor in CollectionService:GetTagged(self.context.Configuration.ANPR.SensorTag) do
		self:_watch(sensor)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.context.Configuration.ANPR.SensorTag)
			:Connect(function(sensor)
				self:_watch(sensor)
			end)
	)
end

function ANPRService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cooldowns)
end

return ANPRService
