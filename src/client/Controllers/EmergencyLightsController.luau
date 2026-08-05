--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

-- Runs the flash pattern for every emergency vehicle this client can see.
--
-- The server owns whether the lights are on and never sends a single flash. The
-- pattern is derived here from the vehicle's attribute and the clock, so a
-- lightbar strobing twice a second costs nothing on the network, twenty of them
-- cost nothing, and a vehicle that has not streamed in costs nothing at all
-- because this client does not have it.
--
-- Vehicles are found through CollectionService rather than by scanning the
-- world, so one streaming in is picked up the moment it arrives.
local EmergencyLightsController = { connections = {}, tracked = {} }

local ACTION_LIGHTS = "RoleplayOSEmergencyLights"
local ACTION_SIREN = "RoleplayOSEmergencySiren"

function EmergencyLightsController:Init(context: any)
	self.context = context
	self.settings = Config.EmergencyLighting
	-- Weak keyed, so a vehicle that is destroyed or streams out drops out of
	-- here on its own rather than being leaked until the player leaves.
	self.tracked = setmetatable({}, { __mode = "k" })
end

-- Records what a light part looked like before it was ever flashed, so it can
-- be put back exactly. Restoring to a guessed default would leave every
-- lightbar in the city the same grey after its first run.
function EmergencyLightsController:_adopt(model: Instance)
	if self.tracked[model] then
		return
	end
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("RoleplayOSLight") ~= false then
			local name = string.lower(descendant.Name)
			local excluded = false
			for _, pattern in self.settings.ExcludedNamePatterns do
				if string.find(name, pattern, 1, true) then
					excluded = true
					break
				end
			end
			if not excluded then
				for _, pattern in self.settings.LightNamePatterns do
					if string.find(name, pattern, 1, true) then
						table.insert(parts, {
							Part = descendant,
							Colour = descendant.Color,
							Material = descendant.Material,
							Light = descendant:FindFirstChildWhichIsA("Light"),
							-- Alternates the two sides of the bar, which is what
							-- makes it read as a lightbar rather than as a lamp
							-- switching on and off.
							Side = #parts % 2,
						})
						break
					end
				end
			end
		end
		if #parts >= self.settings.MaximumLightParts then
			break
		end
	end
	if #parts == 0 then
		return
	end
	self.tracked[model] = { Parts = parts, Lit = false }
end

function EmergencyLightsController:_restore(entry: any)
	for _, record in entry.Parts do
		if record.Part.Parent then
			record.Part.Color = record.Colour
			record.Part.Material = record.Material
			if record.Light then
				record.Light.Enabled = false
			end
		end
	end
	entry.Lit = false
end

function EmergencyLightsController:_step()
	local settings = self.settings
	local phase = math.floor(os.clock() * settings.FlashesPerSecond * 2) % 2

	for model, entry in self.tracked do
		if not model.Parent then
			continue
		end
		local stage = model:GetAttribute(settings.StageAttribute)
		if type(stage) ~= "number" or stage <= 0 then
			if entry.Lit then
				self:_restore(entry)
			end
			continue
		end
		entry.Lit = true
		local primary = model:GetAttribute("RoleplayOSLightPrimary")
		local secondary = model:GetAttribute("RoleplayOSLightSecondary")
		if typeof(primary) ~= "Color3" then
			primary = Color3.fromRGB(0, 68, 255)
		end
		if typeof(secondary) ~= "Color3" then
			secondary = primary
		end
		for index, record in entry.Parts do
			if not record.Part.Parent then
				continue
			end
			-- Stage one is the rear cluster only, for a vehicle stopped at a
			-- scene: visible to the traffic it is warning without lighting up
			-- the whole street.
			local inStage = stage >= settings.Stages or index % 2 == 0
			local on = inStage and record.Side == phase
			record.Part.Material = if on then Enum.Material.Neon else record.Material
			record.Part.Color = if on
				then (if record.Side == 0 then primary else secondary)
				else record.Colour
			if record.Light then
				record.Light.Enabled = on
			end
		end
	end
end

function EmergencyLightsController:_bindControls()
	-- F is the lights, G steps the siren. Bound through ContextActionService so
	-- Roblox's own priority handling applies and a gamepad and a touch button
	-- come free rather than being rebuilt here.
	ContextActionService:BindAction(ACTION_LIGHTS, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

	ContextActionService:BindAction(ACTION_SIREN, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:CycleSiren()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
end

function EmergencyLightsController:Toggle()
	local response = self.context.Controllers.NetworkController:Request("SetEmergencyLights", {
		Stage = if self.stage and self.stage > 0 then 0 else self.settings.Stages,
	})
	if response.Success then
		self.stage = if self.stage and self.stage > 0 then 0 else self.settings.Stages
	elseif response.Code ~= "NOT_DRIVING" then
		-- Silent when the player simply is not in a car, because that is not a
		-- failure. Anything else is worth saying, since a dead button on a
		-- response is worse than a message.
		self.context.Controllers.NotificationController:Push(response.Message)
	end
end

function EmergencyLightsController:CycleSiren()
	local tones = { "", "Wail", "Yelp", "Phaser" }
	local index = ((self.siren or 0) + 1) % #tones
	local response = self.context.Controllers.NetworkController:Request("SetEmergencyLights", {
		Siren = tones[index + 1],
	})
	if response.Success then
		self.siren = index
	end
end

function EmergencyLightsController:Start()
	if not self.settings.Enabled or not RunService:IsRunning() then
		return
	end
	local player = Players.LocalPlayer
	if not player then
		return
	end

	for _, model in CollectionService:GetTagged(self.settings.Tag) do
		self:_adopt(model)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(self.settings.Tag):Connect(function(model)
			self:_adopt(model)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(self.settings.Tag):Connect(function(model)
			local entry = self.tracked[model]
			if entry then
				self:_restore(entry)
				self.tracked[model] = nil
			end
		end)
	)

	-- Stepped on a timer rather than every frame. The pattern changes a couple
	-- of times a second, so running it at the display's refresh rate would be
	-- sixty times the work for the same picture.
	local accumulator = 0
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(delta)
			accumulator += delta
			if accumulator < 1 / (self.settings.FlashesPerSecond * 4) then
				return
			end
			accumulator = 0
			self:_step()
		end)
	)

	self:_bindControls()
end

function EmergencyLightsController:Destroy()
	ContextActionService:UnbindAction(ACTION_LIGHTS)
	ContextActionService:UnbindAction(ACTION_SIREN)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return EmergencyLightsController
