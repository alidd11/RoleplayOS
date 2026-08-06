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

local CIRCUIT_CONTROLS = {
	{ Id = "Master", Label = "360" },
	{ Id = "FrontBlue", Label = "FRONT\nBLUE" },
	{ Id = "RearBlue", Label = "REAR\nBLUE" },
	{ Id = "FrontScene", Label = "FRONT\nSCENE" },
	{ Id = "RearScene", Label = "REAR\nSCENE" },
	{ Id = "RearReds", Label = "REAR\nREDS" },
	{ Id = "LowPower", Label = "LOW\nPOWER" },
	{ Id = "Grille", Label = "GRILLE\nLIGHTS" },
	{ Id = "RunLock", Label = "RUN\nLOCK" },
	{ Id = "LeftAlley", Label = "LEFT\nALLEY" },
	{ Id = "Spots", Label = "SPOTS" },
	{ Id = "RightAlley", Label = "RIGHT\nALLEY" },
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

function EmergencyLightsController:Init(context: any)
	self.context = context
	self.settings = Config.EmergencyLighting
	-- Weak keyed, so a vehicle that is destroyed or streams out drops out of
	-- here on its own rather than being leaked until the player leaves.
	self.tracked = setmetatable({}, { __mode = "k" })
	self.buttons = {}
	self.state = { Available = false, Stage = 0, Siren = "", Circuits = {} }
end

function EmergencyLightsController:_circuit(part: BasePart): string?
	local explicit = part:GetAttribute("RoleplayOSLightCircuit")
	if type(explicit) == "string" and self.settings.Circuits[explicit] then
		return explicit
	end
	local name = string.lower(part.Name)
	for circuit, patterns in self.settings.Circuits do
		for _, pattern in patterns do
			if string.find(name, pattern, 1, true) then
				return circuit
			end
		end
	end
	return nil
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
							Circuit = self:_circuit(descendant),
							Brightness = if descendant:FindFirstChildWhichIsA("Light")
								then (descendant:FindFirstChildWhichIsA("Light") :: Light).Brightness
								else nil,
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
				if record.Brightness then
					record.Light.Brightness = record.Brightness
				end
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
		local lightsActive = model:GetAttribute(settings.StateAttribute) == true
		if type(stage) ~= "number" then
			stage = 0
		end
		if not lightsActive then
			if entry.Lit then
				self:_restore(entry)
			end
			continue
		end
		entry.Lit = true
		local primary = model:GetAttribute("RoleplayOSLightPrimary")
		local secondary = model:GetAttribute("RoleplayOSLightSecondary")
		local lowPower = model:GetAttribute("RoleplayOSLowPower") == true
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
			local circuitOn = record.Circuit
				and model:GetAttribute(settings.CircuitAttributePrefix .. record.Circuit)
					== true
			local inStage = stage >= settings.Stages
				or (stage == 1 and (record.Circuit == "RearBlue" or record.Circuit == "RearReds"))
				or (stage == 1 and record.Circuit == nil and index % 2 == 0)
				or circuitOn
			local on = inStage and record.Side == phase
			record.Part.Material = if on then Enum.Material.Neon else record.Material
			record.Part.Color = if on
				then (if record.Side == 0 then primary else secondary)
				else record.Colour
			if record.Light then
				record.Light.Enabled = on
				if record.Brightness then
					record.Light.Brightness = if lowPower
						then record.Brightness * 0.45
						else record.Brightness
				end
			end
		end
	end
end

function EmergencyLightsController:_button(
	parent: Instance,
	id: string,
	text: string,
	colour: Color3?
): TextButton
	local item = Instance.new("TextButton")
	item.Name = id
	item.AutoButtonColor = false
	item.BackgroundColor3 = colour or Color3.fromRGB(220, 220, 154)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(15, 17, 18)
	item.TextSize = 12
	item.TextWrapped = true
	item.Parent = parent
	corner(item, 9)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(63, 67, 66)
	stroke.Thickness = 2
	stroke.Parent = item
	local scale = Instance.new("UIScale")
	scale.Parent = item
	table.insert(
		self.connections,
		item.InputBegan:Connect(function(inputObject)
			if
				inputObject.UserInputType == Enum.UserInputType.Touch
				or inputObject.UserInputType == Enum.UserInputType.MouseButton1
			then
				scale.Scale = 0.97
			end
		end)
	)
	table.insert(
		self.connections,
		item.InputEnded:Connect(function()
			scale.Scale = 1
		end)
	)
	self.buttons[id] = item
	return item
end

function EmergencyLightsController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSELS"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 14
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Controller"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Size = UDim2.fromOffset(238, 402)
	panel.BackgroundColor3 = Color3.fromRGB(16, 19, 21)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.SelectionGroup = true
	panel.Parent = gui
	corner(panel, 14)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(57, 62, 65)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel
	self.panel = panel
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	self.panelScale = panelScale

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.Text = "EMERGENCY CONTROLS"
	title.TextColor3 = Color3.fromRGB(205, 211, 213)
	title.TextSize = 10
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(12, 34)
	grid.Size = UDim2.new(1, -24, 0, 244)
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(66, 55)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, control in CIRCUIT_CONTROLS do
		local item = self:_button(grid, control.Id, control.Label)
		item.LayoutOrder = order
		item.Activated:Connect(function()
			self:_activate(control.Id)
		end)
	end

	local sirens = self:_button(panel, "Sirens", "SIRENS", Color3.fromRGB(204, 61, 51))
	sirens.Position = UDim2.fromOffset(12, 288)
	sirens.Size = UDim2.fromOffset(102, 47)
	sirens.Activated:Connect(function()
		self:CycleSiren()
	end)
	local response = self:_button(panel, "Response", "999", Color3.fromRGB(42, 83, 184))
	response.Position = UDim2.fromOffset(124, 288)
	response.Size = UDim2.fromOffset(102, 47)
	response.Activated:Connect(function()
		self:_request({ Stage = self.settings.Stages, Siren = "Wail" })
	end)
	local scene = self:_button(panel, "AtScene", "AT SCENE", Color3.fromRGB(174, 169, 93))
	scene.Position = UDim2.fromOffset(12, 345)
	scene.Size = UDim2.fromOffset(102, 45)
	scene.Activated:Connect(function()
		self:_request({ Stage = 1, Siren = "" })
	end)
	local reset = self:_button(panel, "Reset", "RESET", Color3.fromRGB(77, 139, 91))
	reset.Position = UDim2.fromOffset(124, 345)
	reset.Size = UDim2.fromOffset(102, 45)
	reset.Activated:Connect(function()
		self:_request({ Reset = true, Siren = "" })
	end)
end

function EmergencyLightsController:_paint()
	local state = self.state
	for _, control in CIRCUIT_CONTROLS do
		local active = if control.Id == "Master"
			then state.Stage == self.settings.Stages
			elseif control.Id == "LowPower" then state.LowPower == true
			elseif control.Id == "RunLock" then state.RunLock == true
			else state.Circuits and state.Circuits[control.Id] == true
		local item = self.buttons[control.Id]
		if item then
			item.BackgroundColor3 = if active
				then Color3.fromRGB(255, 220, 78)
				else Color3.fromRGB(220, 220, 154)
		end
	end
	if self.buttons.Sirens then
		self.buttons.Sirens.Text = if state.Siren and state.Siren ~= ""
			then string.upper(state.Siren)
			else "SIRENS"
	end
end

function EmergencyLightsController:_request(payload: any)
	local response =
		self.context.Controllers.NetworkController:Request("SetEmergencyLights", payload)
	if response.Success then
		self.state = response.Data
		self:_paint()
	elseif response.Code ~= "NOT_DRIVING" then
		self.context.Controllers.NotificationController:Show(response.Message, "Emergency lights")
	end
end

function EmergencyLightsController:_activate(id: string)
	if id == "Master" then
		self:_request({
			Stage = if self.state.Stage == self.settings.Stages then 0 else self.settings.Stages,
		})
	elseif id == "LowPower" then
		self:_request({ LowPower = self.state.LowPower ~= true })
	elseif id == "RunLock" then
		self:_request({ RunLock = self.state.RunLock ~= true })
	else
		local active = self.state.Circuits and self.state.Circuits[id] == true
		self:_request({ Circuit = id, Enabled = not active })
	end
end

function EmergencyLightsController:_refreshAvailability(driver: boolean)
	if not driver then
		self.state = { Available = false, Stage = 0, Siren = "", Circuits = {} }
		self.panel.Visible = false
		return
	end
	-- Asked more than once.
	--
	-- This ran only on the transition into driving, and the server does not
	-- necessarily know about the vehicle yet at that moment: the seat replicates
	-- to this client before the spawn has finished being recorded. One question
	-- asked a fraction too early left the panel hidden until the player got out
	-- and back in, which reads as the feature being broken.
	for attempt = 1, 4 do
		if self.driver ~= true then
			return
		end
		local response =
			self.context.Controllers.NetworkController:Request("GetEmergencyLights", {})
		if response.Success and type(response.Data) == "table" then
			self.state = response.Data
			self.panel.Visible = self.state.Available == true
			self:_paint()
			if self.state.Available == true then
				return
			end
			-- Said once, and only to the output, because the usual reasons are
			-- ordinary: most drivers are civilians in their own car. It exists so
			-- that somebody wondering why the panel is missing can find out
			-- instead of guessing at five things at once.
			if attempt == 1 and self.state.Reason then
				print("[RoleplayOS] Lighting panel hidden: " .. tostring(self.state.Reason))
			end
		end
		task.wait(0.75)
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
	self:_request({
		Stage = if self.state.Stage and self.state.Stage > 0 then 0 else self.settings.Stages,
	})
end

function EmergencyLightsController:CycleSiren()
	local tones = { "", "Wail", "Yelp", "Phaser" }
	local current = table.find(tones, self.state.Siren or "") or 1
	local nextIndex = current % #tones + 1
	self:_request({
		Siren = tones[nextIndex],
	})
	if self.state.Siren ~= "" and (self.state.Stage or 0) == 0 then
		self:_request({ Stage = self.settings.Stages })
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
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"EmergencyLights",
		function(layout)
			local scale =
				self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(238, 402), 24)
			if layout.Compact then
				scale = math.min(scale, 0.78)
			end
			self.panelScale.Scale = scale
			self.panel.Position =
				UDim2.new(1, -(layout.SafeRight + 16), 0.5, math.floor(layout.NativeTop * 0.25))
			local driver = layout.State == "Driver"
			if self.driver ~= driver then
				self.driver = driver
				task.spawn(function()
					self:_refreshAvailability(driver)
				end)
			end
		end
	)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			if self.driver then
				task.spawn(function()
					self:_refreshAvailability(true)
				end)
			end
		end)
	)

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
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return EmergencyLightsController
