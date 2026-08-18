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
local FULL_PANEL = Vector2.new(244, 406)
local COMPACT_PANEL = Vector2.new(448, 206)

-- The control head's materials. A siren box is a dark moulding with a slightly
-- lighter faceplate, screened legends and indicator lamps: three greys and two
-- lamp colours is the whole palette, and keeping it that short is what stops it
-- drifting back towards looking like a phone app.
local CHASSIS = Color3.fromRGB(13, 15, 17)
local FACEPLATE = Color3.fromRGB(26, 30, 34)
local BEZEL = Color3.fromRGB(48, 55, 60)
local KEY_CAP = Color3.fromRGB(34, 39, 44)
local KEY_SEAM = Color3.fromRGB(10, 12, 14)
local LEGEND = Color3.fromRGB(200, 207, 212)
local ENGRAVED = Color3.fromRGB(118, 128, 136)
local LAMP_DARK = Color3.fromRGB(38, 44, 50)
local LAMP_AMBER = Color3.fromRGB(255, 176, 46)
local LAMP_BLUE = Color3.fromRGB(74, 150, 255)
local LAMP_RED = Color3.fromRGB(232, 74, 66)
local LAMP_GREEN = Color3.fromRGB(96, 214, 140)

-- The siren keys, in the order a control head carries them: the continuous
-- tones together, then the horn, which is held rather than selected.
local TONE_CONTROLS = {
	{ Id = "Wail", Label = "WAIL" },
	{ Id = "Yelp", Label = "YELP" },
	{ Id = "Priority", Label = "PRIO" },
}

-- The three states an officer actually works in, which is what the old 999 / AT
-- SCENE / RESET row was reaching for without saying so.
local STAGE_CONTROLS = {
	{ Id = "StageOff", Label = "OFF", Lamp = LAMP_GREEN },
	{ Id = "StageScene", Label = "SCENE", Lamp = LAMP_AMBER },
	{ Id = "StageResponse", Label = "999", Lamp = LAMP_BLUE },
}

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
	self.lamps = {}
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
	-- The vehicle lights itself.
	--
	-- Every emergency vehicle in this fleet ships EasyLS, which runs its own
	-- patterns over its own lamps from its own script. Painting them from here
	-- as well is two owners of one lightbar, and whichever wrote last wins: the
	-- kit's pattern and this one cancel into a bar that flashes wrong, or does
	-- not flash at all. Recorded as tracked so the tag is not reconsidered every
	-- step, and then left entirely alone.
	if VehicleLights.ownKit(model) then
		self.pending[model] = nil
		self.tracked[model] = { Parts = {}, Lit = false, Kit = true }
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

-- The siren sounds belonging to the vehicle being driven.
--
-- There used to be a _syncSiren here that stopped every tone in the vehicle and
-- played the one the server's attribute named, at this framework's volume, on a
-- loop. The vehicles already have a script that does exactly that from the
-- driver's keyboard, over the same four Sound objects, with its own volumes and
-- its own idea of which tone is on. Two owners of one Sound is a siren that
-- stops whenever the other one spoke last, which is precisely what a panel
-- button that appears to do nothing looks like.
--
-- The panel drives the vehicle's own sounds directly now, the same way the
-- vehicle's own keys do, and reads what is playing rather than what the server
-- last recorded. One owner, one truth, and the kit's keys keep working
-- untouched.
function EmergencyLightsController:_drivenVehicle(): Model?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return if seat then seat:FindFirstAncestorOfClass("Model") else nil
end

function EmergencyLightsController:_sirenRack(): Instance?
	local vehicle = self:_drivenVehicle()
	return if vehicle then VehicleLights.sirenRack(vehicle) else nil
end

function EmergencyLightsController:_toneSound(rack: Instance, tone: string): Sound?
	for _, name in VehicleLights.SirenAliases[tone] or {} do
		for _, child in rack:GetChildren() do
			-- Kits vary in casing, AirHorn against Airhorn among them.
			if child:IsA("Sound") and string.lower(child.Name) == string.lower(name) then
				return child
			end
		end
	end
	return nil
end

-- Keeps the framework's record in step with the vehicle's own lights key.
--
-- Pressing J goes straight to the kit, which lights the bar and tells nobody:
-- its stage lives in a local variable and its remote answers only GetBinds. The
-- panel would sit at OFF with the bar flashing above the bonnet, and worse, the
-- blue light exemption and what dispatch sees both hang off this framework's
-- stage attribute, so an officer who used the vehicle's own key was running a
-- blue light response the speed cameras still ticketed.
--
-- What the kit does expose is the flashing itself. A running pattern rewrites
-- lamp transparency several times a second and a stopped one rewrites nothing,
-- so a sample of a few lamps two polls apart answers the question the remote
-- will not. The grace window covers the gap between two steps of a slow pattern.
local KIT_FLASH_GRACE = 1.5

function EmergencyLightsController:_followKit()
	local watch = self.kitWatch
	if not watch then
		return
	end
	local signature = 0
	for index, lamp in watch.Lamps do
		if lamp.Parent then
			signature += lamp.Transparency * index
		end
	end
	local now = os.clock()
	if signature ~= watch.Signature then
		watch.Signature = signature
		watch.LastChange = now
	end
	local lit = now - watch.LastChange < KIT_FLASH_GRACE
	local recorded = (self.state.Stage or 0) > 0
	if lit == recorded then
		return
	end
	-- Recorded, never driven. This never asks the kit to change anything; it only
	-- writes down what the kit already did.
	self:_request({ Stage = if lit then self.settings.Stages else 0 })
end

-- Which continuous tone the vehicle is actually sounding, by asking it.
function EmergencyLightsController:_playingTone(): string
	local rack = self:_sirenRack()
	if not rack then
		return ""
	end
	for _, tone in VehicleLights.SirenCycle do
		local sound = self:_toneSound(rack, tone)
		if sound and sound.IsPlaying then
			return tone
		end
	end
	return ""
end

-- Selects one continuous tone, or silence, exactly as the vehicle's own keys do:
-- the tones are mutually exclusive and looped, and the volume the kit was
-- authored with is left alone.
function EmergencyLightsController:_setTone(tone: string)
	local rack = self:_sirenRack()
	if not rack then
		return
	end
	for _, other in VehicleLights.SirenCycle do
		local sound = self:_toneSound(rack, other)
		if sound then
			sound.Looped = true
			sound.RollOffMaxDistance = self.settings.SirenRangeStuds
			if other == tone then
				if not sound.IsPlaying then
					sound:Play()
				end
			elseif sound.IsPlaying then
				sound:Stop()
			end
		end
	end
	-- Recorded, not obeyed. Dispatch and the speed cameras need to know a unit is
	-- running a siren; the sound itself is the vehicle's business.
	self:_request({ Siren = tone, Stage = if tone ~= "" then self.settings.Stages else nil })
end

-- The airhorn, which is held rather than selected.
function EmergencyLightsController:_setHorn(down: boolean)
	local rack = self:_sirenRack()
	if not rack then
		return
	end
	local horn = self:_toneSound(rack, VehicleLights.MomentaryTone)
	if not horn then
		return
	end
	horn.Looped = false
	if down then
		horn:Play()
	else
		horn:Stop()
	end
end

function EmergencyLightsController:_restore(entry: any)
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
end

function EmergencyLightsController:_step()
	local settings = self.settings
	local phase = math.floor(os.clock() * settings.FlashesPerSecond * 2) % 2

	-- The head follows the vehicle's own keys.
	--
	-- The driver can change tone with R, T or G and light the bar with J without
	-- this panel being touched, and a lit key for a tone that stopped ten seconds
	-- ago is worse than no key at all. Compared rather than repainted, so the
	-- usual answer costs one string comparison on a loop that is already running.
	if self.panel and self.panel.Visible then
		self:_followKit()
		local tone = self:_playingTone()
		if tone ~= self.paintedTone then
			self.paintedTone = tone
			self:_paint()
		end
	end

	-- Vehicles whose lamps had not arrived when the tag did.
	for model in self.pending do
		if model.Parent then
			self:_adopt(model)
		else
			self.pending[model] = nil
		end
	end

	for model, entry in self.tracked do
		if not model.Parent or entry.Kit then
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

-- One key on the control head.
--
-- These were rounded pastel tiles with black text, which is what an app looks
-- like. A siren controller is a moulded box of dark caps with the legend
-- screened onto them and an indicator lamp above each: the cap does not change
-- colour when the function is on, the lamp beside it lights. That distinction is
-- most of why the panel now reads as equipment bolted to a dashboard rather than
-- as a page of buttons floating over the windscreen.
function EmergencyLightsController:_key(
	parent: Instance,
	id: string,
	text: string,
	lamp: Color3?
): TextButton
	local item = Instance.new("TextButton")
	item.Name = id
	item.AutoButtonColor = false
	item.BackgroundColor3 = KEY_CAP
	item.BorderSizePixel = 0
	item.Font = Enum.Font.RobotoMono
	item.Text = text
	item.TextColor3 = LEGEND
	item.TextSize = 10
	item.TextWrapped = true
	item.Parent = parent
	corner(item, 4)
	-- Two strokes would be truer to a moulded cap, but one dark seam against the
	-- lighter faceplate is enough to separate them and costs one instance.
	local stroke = Instance.new("UIStroke")
	stroke.Color = KEY_SEAM
	stroke.Thickness = 1
	stroke.Parent = item
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 9)
	padding.Parent = item

	local led = Instance.new("Frame")
	led.Name = "Lamp"
	led.AnchorPoint = Vector2.new(0.5, 0)
	led.Position = UDim2.new(0.5, 0, 0, 4)
	led.Size = UDim2.new(1, -16, 0, 3)
	led.BackgroundColor3 = LAMP_DARK
	led.BorderSizePixel = 0
	led.Parent = item
	corner(led, 2)
	local glow = Instance.new("UIStroke")
	glow.Color = lamp or LAMP_AMBER
	glow.Thickness = 3
	glow.Transparency = 1
	glow.Parent = led

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
	self.lamps[id] = { Led = led, Glow = glow, Colour = lamp or LAMP_AMBER }
	return item
end

-- Lights or darkens a key's indicator.
function EmergencyLightsController:_lamp(id: string, on: boolean)
	local record = self.lamps[id]
	if not record then
		return
	end
	record.Led.BackgroundColor3 = if on then record.Colour else LAMP_DARK
	-- The halo is what sells it as a lamp rather than a coloured strip, and it is
	-- only paid for while something is actually lit.
	record.Glow.Transparency = if on then 0.55 else 1
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

	-- The moulding, and the faceplate recessed inside it. Two frames rather than
	-- one is what gives the box an edge to catch light on, which is the whole
	-- difference between a panel and a rectangle.
	local panel = Instance.new("Frame")
	panel.Name = "Controller"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Size = UDim2.fromOffset(FULL_PANEL.X, FULL_PANEL.Y)
	panel.BackgroundColor3 = CHASSIS
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.SelectionGroup = true
	panel.Parent = gui
	corner(panel, 10)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = BEZEL
	panelStroke.Thickness = 2
	panelStroke.Parent = panel
	self.panel = panel
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	self.panelScale = panelScale

	local face = Instance.new("Frame")
	face.Name = "Faceplate"
	face.Position = UDim2.fromOffset(6, 6)
	face.Size = UDim2.new(1, -12, 1, -12)
	face.BackgroundColor3 = FACEPLATE
	face.BorderSizePixel = 0
	face.Parent = panel
	corner(face, 7)
	self.face = face

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 7)
	title.Size = UDim2.new(1, -20, 0, 12)
	title.Font = Enum.Font.RobotoMono
	title.Text = "SIREN / LIGHT CONTROL"
	title.TextColor3 = ENGRAVED
	title.TextSize = 9
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = face

	-- Reads out what the vehicle is doing, which on a real head is a small backlit
	-- window rather than a label that changes colour.
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, -10, 0, 5)
	readout.Size = UDim2.fromOffset(74, 15)
	readout.BackgroundColor3 = CHASSIS
	readout.BorderSizePixel = 0
	readout.Font = Enum.Font.RobotoMono
	readout.Text = "STANDBY"
	readout.TextColor3 = LAMP_GREEN
	readout.TextSize = 9
	readout.Parent = face
	corner(readout, 3)
	self.readout = readout

	-- Rows are positioned by _reshape, which is the only place that knows how
	-- wide the head currently is.
	local function row(name: string): Frame
		local item = Instance.new("Frame")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Parent = face
		return item
	end
	self.toneRow = row("Tones")
	self.hornRow = row("Horn")
	self.stageRow = row("Stages")

	for _, control in TONE_CONTROLS do
		local item = self:_key(self.toneRow, control.Id, control.Label, LAMP_RED)
		item.Activated:Connect(function()
			-- Pressing the tone that is already running silences it, the way the
			-- vehicle's own keys do.
			self:_setTone(if self:_playingTone() == control.Id then "" else control.Id)
			self:_paint()
		end)
	end

	-- Held, not selected. Down on press and up on release, including when the
	-- pointer leaves the key still held, which otherwise leaves the horn stuck on.
	local horn = self:_key(self.hornRow, "Airhorn", "AIR HORN", LAMP_RED)
	horn.BackgroundColor3 = Color3.fromRGB(58, 32, 30)
	table.insert(
		self.connections,
		horn.MouseButton1Down:Connect(function()
			self:_setHorn(true)
			self:_lamp("Airhorn", true)
		end)
	)
	local function hornUp()
		self:_setHorn(false)
		self:_lamp("Airhorn", false)
	end
	table.insert(self.connections, horn.MouseButton1Up:Connect(hornUp))
	table.insert(self.connections, horn.MouseLeave:Connect(hornUp))

	for _, control in STAGE_CONTROLS do
		local item = self:_key(self.stageRow, control.Id, control.Label, control.Lamp)
		item.Activated:Connect(function()
			self:_activate(control.Id)
		end)
	end

	local grid = Instance.new("Frame")
	grid.Name = "Circuits"
	grid.BackgroundTransparency = 1
	grid.Parent = face
	self.grid = grid
	local layout = Instance.new("UIGridLayout")
	self.gridLayout = layout
	layout.CellSize = UDim2.fromOffset(68, 38)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, control in CIRCUIT_CONTROLS do
		local item = self:_key(grid, control.Id, control.Label, LAMP_BLUE)
		item.LayoutOrder = order
		item.Activated:Connect(function()
			self:_activate(control.Id)
		end)
	end
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
	self.panel.Size = UDim2.fromOffset(size.X, size.Y)

	local inset = 10
	local gap = 6
	local width = size.X - 12 - inset * 2
	local top = 24

	-- Keys are laid out by count rather than by fraction, so a row of three and a
	-- row of one still produce caps of the same width. A control head whose keys
	-- are different sizes for no reason is the first thing that gives it away.
	local function spread(frame: Frame, height: number, cell: number)
		local index = 0
		for _, child in frame:GetChildren() do
			if child:IsA("TextButton") then
				child.Position = UDim2.fromOffset(index * (cell + gap), 0)
				child.Size = UDim2.fromOffset(cell, height)
				index += 1
			end
		end
	end

	local keys = #TONE_CONTROLS + 1 + #STAGE_CONTROLS
	if compact then
		-- One bank across the top on a landscape phone.
		--
		-- Stacked, the three rows left twenty eight pixels for the circuit grid,
		-- which is under one row of a grid that can need three: the lighting half
		-- of the head simply had nowhere to draw. The screen's width is the
		-- dimension there is any of, so the siren keys spend it in a single row and
		-- give their height back to the circuits.
		local cell = math.floor((width - (keys - 1) * gap) / keys)
		local height = 32
		local left = inset
		local function bank(frame: Frame, count: number)
			frame.Position = UDim2.fromOffset(left, top)
			frame.Size = UDim2.fromOffset(count * cell + (count - 1) * gap, height)
			spread(frame, height, cell)
			left += count * (cell + gap)
		end
		bank(self.toneRow, #TONE_CONTROLS)
		bank(self.hornRow, 1)
		bank(self.stageRow, #STAGE_CONTROLS)
		top += height + gap
	else
		local function place(frame: Frame, count: number, height: number)
			local cell = math.floor((width - (count - 1) * gap) / count)
			frame.Position = UDim2.fromOffset(inset, top)
			frame.Size = UDim2.fromOffset(width, height)
			spread(frame, height, cell)
			top += height + gap
		end
		place(self.toneRow, #TONE_CONTROLS, 40)
		place(self.hornRow, 1, 34)
		place(self.stageRow, #STAGE_CONTROLS, 40)
	end

	-- A moulded seam between the siren half of the head and the lighting half,
	-- which is how these boxes are actually divided.
	if not self.divider then
		local divider = Instance.new("Frame")
		divider.Name = "Seam"
		divider.BackgroundColor3 = KEY_SEAM
		divider.BorderSizePixel = 0
		divider.Parent = self.face
		self.divider = divider
	end
	self.divider.Position = UDim2.fromOffset(inset, top + 1)
	self.divider.Size = UDim2.fromOffset(width, 1)
	top += gap + 2

	local columns = if compact then 6 else 3
	local cellWidth = math.floor((width - (columns - 1) * gap) / columns)
	local cellHeight = if compact then 32 else 38
	self.gridLayout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	self.grid.Position = UDim2.fromOffset(inset, top)
	self.grid.Size = UDim2.new(0, width, 1, -top - inset)
	self.gridColumns = columns
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
	-- A tone key for a sound the vehicle does not carry is a key that cannot
	-- work, so it comes off the head rather than sitting there dark.
	local rack = self:_sirenRack()
	for _, control in TONE_CONTROLS do
		local item = self.buttons[control.Id]
		if item then
			item.Visible = rack ~= nil and self:_toneSound(rack, control.Id) ~= nil
		end
	end
	if self.buttons.Airhorn then
		local horn = rack and self:_toneSound(rack, VehicleLights.MomentaryTone)
		self.hornRow.Visible = horn ~= nil
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
		self:_lamp(control.Id, active)
	end

	-- Asked of the vehicle, not of the server. The driver can change the tone
	-- with the vehicle's own keys at any moment, and a head that reports the
	-- framework's last recorded value instead is a head that lies.
	local tone = self:_playingTone()
	for _, control in TONE_CONTROLS do
		self:_lamp(control.Id, tone == control.Id)
	end

	local stage = state.Stage or 0
	self:_lamp("StageOff", stage == 0)
	self:_lamp("StageScene", stage == 1)
	self:_lamp("StageResponse", stage >= self.settings.Stages)

	if self.readout then
		local text = if stage == 0 then "STANDBY" elseif stage == 1 then "AT SCENE" else "RESPONSE"
		if tone ~= "" then
			text = string.upper(tone)
		end
		self.readout.Text = text
		self.readout.TextColor3 = if tone ~= ""
			then LAMP_RED
			elseif stage > 0 then LAMP_BLUE
			else LAMP_GREEN
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
	local vehicle = self:_drivenVehicle()
	return if vehicle then VehicleLights.ownKit(vehicle) else nil
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
	if id == "StageOff" then
		-- Everything down: the kit's pattern, the tone, and this framework's
		-- record of both.
		if self.state.Stage and self.state.Stage > 0 then
			self:_cycleKit("MainELS")
		end
		self:_setTone("")
		self:_request({ Reset = true, Siren = "" })
	elseif id == "StageScene" then
		self:_setTone("")
		self:_request({ Stage = 1, Siren = "" })
	elseif id == "StageResponse" then
		if not self.state.Stage or self.state.Stage < self.settings.Stages then
			self:_cycleKit("MainELS")
		end
		self:_request({ Stage = self.settings.Stages })
		self:_setTone("Wail")
		self:_paint()
	elseif id == "Director" then
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
		self.kitControls = false
		self.kitWatch = nil
		self.panel.Visible = false
		self:_bindControls(false)
		return
	end
	-- Whether this vehicle came with its own keyboard controls, which decides
	-- whether this framework binds any of its own. Read from the vehicle rather
	-- than from the server's reply, because it is a fact about the model.
	self.kitControls = self:_sirenRack() ~= nil
	local vehicle = self:_drivenVehicle()
	local lamps = if vehicle then VehicleLights.kitLamps(vehicle, 8) else {}
	self.kitWatch = if #lamps > 0 then { Lamps = lamps, Signature = -1, LastChange = 0 } else nil
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

-- Bound only while there is a panel to control, on a vehicle that has not
-- brought its own keys.
--
-- These used to be bound for everybody, all the time. A civilian pressing F sent
-- a request that failed NOT_DRIVING and was deliberately swallowed, so the key
-- did nothing and said nothing. Worse, the gamepad binding was ButtonY, which
-- the phone also binds, and this handler passed the input on: one press of Y
-- toggled the lightbar and opened the phone.
--
-- Then the d-pad and F and G turned out to be the kit's keys too. Every
-- emergency vehicle in this fleet carries a siren box that binds R, T, G and F
-- through UserInputService, and sinking an input in ContextActionService does
-- not stop UserInputService from seeing it: both handlers ran. Pressing F
-- toggled this framework's lights and sounded the vehicle's airhorn; pressing G
-- cycled this panel's tone and switched the vehicle to priority underneath it.
--
-- A vehicle that brought its own controls keeps them, and this binds nothing.
-- The panel is the only thing this framework adds, and it does not need a key.
function EmergencyLightsController:_bindControls(available: boolean)
	local wanted = available and not self.kitControls
	if wanted == self.bound then
		return
	end
	self.bound = wanted
	if not wanted then
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
	local rack = self:_sirenRack()
	if not rack then
		return
	end
	local tones = { "" }
	for _, tone in VehicleLights.SirenCycle do
		if self:_toneSound(rack, tone) then
			table.insert(tones, tone)
		end
	end
	if #tones == 1 then
		return
	end
	-- Stepped from what the vehicle is sounding, not from what the server last
	-- recorded. The two can differ the moment the driver uses the vehicle's own
	-- keys, and stepping from the stale one skips a tone or repeats one.
	local current = table.find(tones, self:_playingTone()) or 1
	self:_setTone(tones[current % #tones + 1])
	self:_paint()
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
