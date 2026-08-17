--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local VehicleLights = require(ReplicatedStorage.RoleplayOS.Shared.VehicleLights)

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

-- The two shapes the panel takes. Tall on a desktop, wide on a phone, because a
-- landscape phone has height to spare in neither direction but width in one.
local FULL_PANEL = Vector2.new(238, 402)
local COMPACT_PANEL = Vector2.new(420, 188)

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
	-- The kit's second pattern. Shown only on a vehicle that has one, like every
	-- other control here.
	{ Id = "Director", Label = "DIRECTOR" },
}

-- Controls that are always worth showing, whatever lamps the vehicle turns out
-- to have. Master is the vehicle's main lights and the rest are framework state
-- rather than circuits, so none of them depends on a particular bulb existing.
local ALWAYS_AVAILABLE = {
	Master = true,
	LowPower = true,
	RunLock = true,
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
	-- Vehicles that were tagged before their geometry arrived. Weak for the same
	-- reason as tracked: a model that streams out or is destroyed leaves on its
	-- own.
	self.pending = setmetatable({}, { __mode = "k" })
	self.buttons = {}
	self.secondary = {}
	self.state = { Available = false, Stage = 0, Siren = "", Circuits = {} }
end

function EmergencyLightsController:_circuit(part: BasePart, root: Instance): string?
	return VehicleLights.circuitFor(self.settings, part, root)
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
			if VehicleLights.isLightPart(self.settings, descendant, model) then
				local light = descendant:FindFirstChildWhichIsA("Light")
				local circuit = self:_circuit(descendant, model)
				table.insert(parts, {
					Part = descendant,
					Colour = descendant.Color,
					Material = descendant.Material,
					Light = light,
					Circuit = circuit,
					-- Built once. This was concatenated inside the flash loop, so
					-- ten vehicles in view generated several thousand throwaway
					-- strings a second for a name that never changes.
					CircuitAttribute = if circuit
						then self.settings.CircuitAttributePrefix .. circuit
						else nil,
					Brightness = if light then light.Brightness else nil,
					-- Lightbar lenses are authored almost invisible, and the flash
					-- only ever set colour and material. Every lamp on the Peugeot
					-- is more than half transparent, so the bar was painted the
					-- right blue and stayed dark: correct in the properties and
					-- absent from the screen.
					Transparency = descendant.Transparency,
					-- Alternates the two sides of the bar, which is what makes it
					-- read as a lightbar rather than as a lamp switching on and off.
					Side = #parts % 2,
				})
			end
		end
		if #parts >= self.settings.MaximumLightParts then
			break
		end
	end
	if #parts == 0 then
		-- Not "this vehicle has no lights" - "not yet".
		--
		-- The tag is added by the server the moment the vehicle is created, and
		-- with streaming on it reaches this client before the body does. Adoption
		-- ran against a model that was still only a few parts, found nothing that
		-- looked like a lamp, and gave up permanently. The vehicle then sat there
		-- fully loaded, correctly tagged, at stage two, with thirty seven lamps
		-- the painter had already decided did not exist - which is every blue
		-- light in the game silently never coming on.
		--
		-- Kept as pending and retried by the step loop instead, which is already
		-- running and already knows how to do nothing cheaply.
		self.pending[model] = true
		return
	end
	self.pending[model] = nil
	self.tracked[model] = { Parts = parts, Lit = false, Siren = "", MissingSiren = {} }
end

function EmergencyLightsController:_syncSiren(model: Instance, entry: any, tone: string)
	if entry.Siren == tone then
		return
	end
	entry.Siren = tone
	local sounds = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Sound") then
			-- Imported ELS kits vary in casing (for example AirHorn/Airhorn).
			-- Resolve the vehicle's native sounds case-insensitively so a visible
			-- siren button cannot silently produce no audio.
			sounds[string.lower(descendant.Name)] = descendant
		end
	end
	for _, aliases in VehicleLights.SirenAliases do
		for _, name in aliases do
			local sound = sounds[string.lower(name)]
			if sound then
				sound.Looped = true
				sound:Stop()
			end
		end
	end
	if tone == "" then
		return
	end
	local selected: Sound? = nil
	for _, name in VehicleLights.SirenAliases[tone] or {} do
		selected = sounds[string.lower(name)]
		if selected then
			break
		end
	end
	if not selected then
		if not entry.MissingSiren[tone] then
			entry.MissingSiren[tone] = true
			warn(
				"[RoleplayOS] Vehicle has no native siren sound for "
					.. tone
					.. ": "
					.. model:GetFullName()
			)
		end
		return
	end
	selected.Looped = true
	selected.Volume = self.settings.SirenVolume
	selected.RollOffMaxDistance = self.settings.SirenRangeStuds
	selected.RollOffMode = Enum.RollOffMode.InverseTapered
	selected:Play()
end

function EmergencyLightsController:_restore(entry: any, model: Instance?)
	for _, record in entry.Parts do
		if record.Part.Parent then
			record.Part.Color = record.Colour
			record.Part.Material = record.Material
			record.Part.Transparency = record.Transparency
			if record.Light then
				record.Light.Enabled = false
				if record.Brightness then
					record.Light.Brightness = record.Brightness
				end
			end
		end
		-- Forgotten, not just written. The step above skips a write when it
		-- matches what it last wrote, so leaving these set would have it compare
		-- against values that are no longer on the part and skip the write that
		-- lights it again.
		record.LastMaterial = nil
		record.LastColour = nil
		record.LastTransparency = nil
		record.LastOn = nil
		record.LastBrightness = nil
	end
	entry.Lit = false
	if model then
		self:_syncSiren(model, entry, "")
	end
end

function EmergencyLightsController:_step()
	local settings = self.settings
	local phase = math.floor(os.clock() * settings.FlashesPerSecond * 2) % 2

	-- Vehicles whose lamps had not arrived when the tag did.
	for model in self.pending do
		if model.Parent then
			self:_adopt(model)
		else
			self.pending[model] = nil
		end
	end

	for model, entry in self.tracked do
		if not model.Parent then
			continue
		end
		local siren = model:GetAttribute(settings.SirenAttribute)
		self:_syncSiren(model, entry, if type(siren) == "string" then siren else "")
		local stage = model:GetAttribute(settings.StageAttribute)
		local lightsActive = model:GetAttribute(settings.StateAttribute) == true
		if type(stage) ~= "number" then
			stage = 0
		end
		if not lightsActive then
			if entry.Lit then
				self:_restore(entry, model)
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
			local circuitOn = record.CircuitAttribute ~= nil
				and model:GetAttribute(record.CircuitAttribute) == true
			local inStage = stage >= settings.Stages
				or (stage == 1 and (record.Circuit == "RearBlue" or record.Circuit == "RearReds"))
				or (stage == 1 and record.Circuit == nil and index % 2 == 0)
				or circuitOn
			local on = inStage and record.Side == phase
			-- Written only when it changes.
			--
			-- This loop runs nearly nine times a second while the pattern itself
			-- only changes four times, so half of every write was already
			-- redundant, and a part that is off was being reassigned its own
			-- unchanged off values for as long as the lights were running. Ten
			-- emergency vehicles in view came to roughly eleven thousand property
			-- writes a second on every client, almost none of which changed
			-- anything. On a full server that is the whole cost of this feature
			-- and none of its effect.
			local material = if on then Enum.Material.Neon else record.Material
			local colour = if on
				then (if record.Side == 0 then primary else secondary)
				else record.Colour
			if record.LastMaterial ~= material then
				record.LastMaterial = material
				record.Part.Material = material
			end
			if record.LastColour ~= colour then
				record.LastColour = colour
				record.Part.Color = colour
			end
			-- A lit lens has to be visible as well as the right colour. Restored
			-- to whatever it was authored as when the lamp goes out, so a bar that
			-- is meant to be near invisible at rest still is.
			local transparency = if on then 0 else record.Transparency
			if record.LastTransparency ~= transparency then
				record.LastTransparency = transparency
				record.Part.Transparency = transparency
			end
			if record.Light then
				if record.LastOn ~= on then
					record.LastOn = on
					record.Light.Enabled = on
				end
				local brightness = if record.Brightness
					then (if lowPower then record.Brightness * 0.45 else record.Brightness)
					else nil
				if brightness ~= nil and record.LastBrightness ~= brightness then
					record.LastBrightness = brightness
					record.Light.Brightness = brightness
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
	-- Below the driving pedals, which sit at twelve. They share the bottom right
	-- of a phone screen and the pedals are the ones you cannot do without: if the
	-- two ever overlap again, the throttle should be what receives the touch.
	gui.DisplayOrder = 11
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Controller"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Size = UDim2.fromOffset(FULL_PANEL.X, FULL_PANEL.Y)
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
	self.grid = grid
	local layout = Instance.new("UIGridLayout")
	self.gridLayout = layout
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
	self.secondary[#self.secondary + 1] = sirens
	sirens.Activated:Connect(function()
		self:CycleSiren()
	end)
	local response = self:_button(panel, "Response", "999", Color3.fromRGB(42, 83, 184))
	response.Position = UDim2.fromOffset(124, 288)
	response.Size = UDim2.fromOffset(102, 47)
	self.secondary[#self.secondary + 1] = response
	response.Activated:Connect(function()
		self:_request({ Stage = self.settings.Stages, Siren = "Wail" })
	end)
	local scene = self:_button(panel, "AtScene", "AT SCENE", Color3.fromRGB(174, 169, 93))
	scene.Position = UDim2.fromOffset(12, 345)
	scene.Size = UDim2.fromOffset(102, 45)
	self.secondary[#self.secondary + 1] = scene
	scene.Activated:Connect(function()
		self:_request({ Stage = 1, Siren = "" })
	end)
	local reset = self:_button(panel, "Reset", "RESET", Color3.fromRGB(77, 139, 91))
	reset.Position = UDim2.fromOffset(124, 345)
	reset.Size = UDim2.fromOffset(102, 45)
	self.secondary[#self.secondary + 1] = reset
	reset.Activated:Connect(function()
		self:_request({ Reset = true, Siren = "" })
	end)
end

-- Switches the panel between its tall shape and its wide one.
--
-- Both hold the same sixteen controls; only the number of columns and the row
-- of secondary buttons differ, so nothing has to be rebuilt and no state is
-- lost when a phone is rotated.
function EmergencyLightsController:_reshape(compact: boolean)
	if self.compactShape == compact then
		return
	end
	self.compactShape = compact
	local size = if compact then COMPACT_PANEL else FULL_PANEL
	local columns = if compact then 6 else 3
	local cell = if compact then Vector2.new(60, 48) else Vector2.new(66, 55)
	self.panel.Size = UDim2.fromOffset(size.X, size.Y)
	self.gridLayout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	local rows = math.ceil(#CIRCUIT_CONTROLS / columns)
	self.grid.Size = UDim2.new(1, -24, 0, rows * cell.Y + (rows - 1) * 8)
	local top = 34 + rows * cell.Y + (rows - 1) * 8 + 10
	local across = if compact then 4 else 2
	local width = math.floor((size.X - 24 - (across - 1) * 8) / across)
	for index, item in self.secondary do
		local column = (index - 1) % across
		local row = math.floor((index - 1) / across)
		item.Position = UDim2.fromOffset(12 + column * (width + 8), top + row * 53)
		item.Size = UDim2.fromOffset(width, 46)
	end
end

-- Hides the controls this vehicle cannot carry out.
--
-- A button that records a state against a lamp the vehicle does not have is
-- indistinguishable, to the person pressing it, from a broken button. The
-- server reports which circuits resolved to real lamps and whether the vehicle
-- brought its own kit, and everything else is taken off the panel rather than
-- shown greyed out: there is nothing the player can do to earn it.
function EmergencyLightsController:_applyAvailability()
	local state = self.state
	local available = state.AvailableCircuits or {}
	local hasKit = state.Kit ~= nil
	local shown = 0
	for _, control in CIRCUIT_CONTROLS do
		local item = self.buttons[control.Id]
		if item then
			local visible = if control.Id == "Director"
				then hasKit
				elseif ALWAYS_AVAILABLE[control.Id] then true
				else available[control.Id] == true
			item.Visible = visible
			if visible then
				shown += 1
				item.LayoutOrder = shown
			end
		end
	end
end

function EmergencyLightsController:_paint()
	local state = self.state
	self:_applyAvailability()
	for _, control in CIRCUIT_CONTROLS do
		local active = if control.Id == "Director"
			then false
			elseif control.Id == "Master" then state.Stage == self.settings.Stages
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

-- The lighting kit inside the vehicle currently being driven.
--
-- These vehicles light themselves. EasyLS runs its own server script over its
-- own lamps and answers to one RemoteFunction, and the framework's circuit
-- attributes reach none of it. Asking the kit is what actually makes a light
-- come on; the framework request beside it is what keeps the server's idea of
-- the vehicle - the blue light exemption, what dispatch sees - in step.
function EmergencyLightsController:_kitRemote(): RemoteFunction?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local vehicle = seat and seat:FindFirstAncestorOfClass("Model")
	if not vehicle then
		return nil
	end
	local remote = vehicle:FindFirstChild("EasyLS_Remote", true)
	return if remote and remote:IsA("RemoteFunction") then remote else nil
end

function EmergencyLightsController:_cycleKit(action: string)
	local remote = self:_kitRemote()
	if not remote then
		return
	end
	-- The kit refuses anybody who is not in its drive seat, and a failure here
	-- must not take the panel down with it.
	pcall(function()
		remote:InvokeServer(action)
	end)
end

function EmergencyLightsController:_activate(id: string)
	if id == "Director" then
		self:_cycleKit("DirectorELS")
	elseif id == "Master" then
		-- Cycles the kit's pattern and tells the server the lights are on, so the
		-- two agree about a vehicle that is now visibly lit.
		self:_cycleKit("MainELS")
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
		self:_bindControls(false)
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
			self:_bindControls(self.state.Available == true)
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

-- Bound only while there is a panel to control, and unbound the moment there is
-- not.
--
-- These used to be bound for everybody, all the time. A civilian pressing F sent
-- a request that failed NOT_DRIVING and was deliberately swallowed, so the key
-- did nothing and said nothing. Worse, the gamepad binding was ButtonY, which
-- the phone also binds, and this handler passed the input on: one press of Y
-- toggled the lightbar and opened the phone.
--
-- The gamepad now uses the d-pad, which nothing else claims, and the handler
-- sinks rather than passes, which is safe precisely because it is only bound
-- while the player is driving a vehicle that has lights.
function EmergencyLightsController:_bindControls(available: boolean)
	if available == self.bound then
		return
	end
	self.bound = available
	if not available then
		ContextActionService:UnbindAction(ACTION_LIGHTS)
		ContextActionService:UnbindAction(ACTION_SIREN)
		return
	end
	ContextActionService:BindAction(ACTION_LIGHTS, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.DPadUp)

	ContextActionService:BindAction(ACTION_SIREN, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:CycleSiren()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.G, Enum.KeyCode.DPadRight)
end

function EmergencyLightsController:Toggle()
	self:_request({
		Stage = if self.state.Stage and self.state.Stage > 0 then 0 else self.settings.Stages,
	})
end

function EmergencyLightsController:CycleSiren()
	local tones = { "" }
	if self.state.Tones then
		for _, tone in { "Wail", "Yelp", "Phaser", "Horn" } do
			if self.state.Tones[tone] and self.state.Tones[tone] ~= "" then
				table.insert(tones, tone)
			end
		end
	end
	if #tones == 1 then
		return
	end
	local current = table.find(tones, self.state.Siren or "") or 1
	local nextIndex = current % #tones + 1
	-- One request. The follow-up that used to be here read self.state, which the
	-- reply above had already replaced, so it tested the answer rather than the
	-- question and never fired. The server raises the stage itself now.
	self:_request({ Siren = tones[nextIndex] })
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
			local scale = self.context.Controllers.UIOrchestrator:FitScale(layout, FULL_PANEL, 24)
			if layout.Compact then
				-- Stood on the pedals, above them in the display order, so an
				-- officer on a phone could not reach the accelerator.
				--
				-- Four hundred and two tall at the compact scale is over three
				-- hundred pixels, centred on a landscape phone screen of about
				-- three hundred and fifty: it covered the bottom right corner
				-- where the throttle and brake live. Anchoring the panel's bottom
				-- above whatever the pedals reserve keeps the two apart on any
				-- screen, rather than by picking a number that happens to work on
				-- one.
				local reserve = if layout.InputMode == "Touch"
					then layout.HotbarBottom + Config.DrivingControls.PedalSize + 34
					else layout.HotbarBottom + 16
				-- Laid out wide rather than tall on a phone.
				--
				-- Two hundred and thirty eight by four hundred and two is a
				-- portrait panel, and a landscape phone has about three hundred
				-- and fifty pixels of height and eight hundred of width. Fitting
				-- the tall version into what is left above the pedals meant a
				-- scale near a third, which is twenty pixel buttons: present, and
				-- unusable. Six columns instead of three spends the width the
				-- screen actually has.
				self:_reshape(true)
				local usable = math.max(layout.SafeViewport.Y - reserve - 20, 140)
				scale = math.min(
					self.context.Controllers.UIOrchestrator:FitScale(layout, COMPACT_PANEL, 24),
					usable / COMPACT_PANEL.Y
				)
				self.panel.AnchorPoint = Vector2.new(1, 1)
				self.panel.Position = UDim2.new(1, -(layout.SafeRight + 16), 1, -reserve)
			else
				self:_reshape(false)
				self.panel.AnchorPoint = Vector2.new(1, 0.5)
				self.panel.Position =
					UDim2.new(1, -(layout.SafeRight + 16), 0.5, math.floor(layout.NativeTop * 0.25))
			end
			self.panelScale.Scale = scale
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
				self:_restore(entry, model)
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
