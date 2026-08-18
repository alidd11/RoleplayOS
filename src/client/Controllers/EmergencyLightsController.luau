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
local FULL_PANEL = Vector2.new(252, 402)
local COMPACT_PANEL = Vector2.new(420, 188)

-- The moulding the keys are set into. Three greys, so the caps carry the colour.
local CHASSIS = Color3.fromRGB(13, 15, 17)
local FACEPLATE = Color3.fromRGB(26, 30, 34)
local BEZEL = Color3.fromRGB(48, 55, 60)
local SEAM = Color3.fromRGB(10, 12, 14)
local ENGRAVED = Color3.fromRGB(118, 128, 136)

-- The three tones a control head carries on their own keys, and the three states
-- an officer works in. Discrete keys rather than one that cycles: an officer
-- reaching for yelp should press yelp.
local TONE_CONTROLS = {
	{ Id = "Wail", Label = "WAIL" },
	{ Id = "Yelp", Label = "YELP" },
	{ Id = "Priority", Label = "PRIO" },
}
local MODE_CONTROLS = {
	{ Id = "Reset", Label = "OFF" },
	{ Id = "AtScene", Label = "AT SCENE" },
	{ Id = "Response", Label = "999" },
}

-- The cap your panel already used, kept. Only the indicator above it is new.
local CAP = Color3.fromRGB(220, 220, 154)
local LEGEND = Color3.fromRGB(15, 17, 18)
-- Barely there when off. A dark bar against the pale cap looked like damage to
-- the button rather than like a lamp that is not lit, and nine of them at once
-- made the panel look broken on a vehicle sitting at rest.
local LAMP_DARK = Color3.fromRGB(198, 198, 138)
local LAMP_ON = Color3.fromRGB(255, 214, 64)
local LAMP_BLUE = Color3.fromRGB(64, 148, 255)
local LAMP_RED = Color3.fromRGB(240, 78, 68)
local LAMP_GREEN = Color3.fromRGB(104, 216, 146)

local ACTION_LIGHTS = "RoleplayOSEmergencyLights"
local ACTION_SIREN = "RoleplayOSEmergencySiren"

local CIRCUIT_CONTROLS = {
	{ Id = "Master", Label = "360" },
	{ Id = "FrontBlue", Label = "FRONT\nBLUE" },
	{ Id = "RearBlue", Label = "REAR\nBLUE" },
	{ Id = "FrontScene", Label = "FRONT\nSCENE" },
	{ Id = "RearScene", Label = "REAR\nSCENE" },
	{ Id = "RearReds", Label = "REAR\nREDS" },
	{ Id = "LowPower", Label = "LOW PWR" },
	{ Id = "Grille", Label = "GRILLE" },
	{ Id = "RunLock", Label = "RUN LOCK" },
	{ Id = "LeftAlley", Label = "LEFT\nALLEY" },
	{ Id = "Spots", Label = "SPOTS" },
	{ Id = "RightAlley", Label = "RIGHT\nALLEY" },
	-- The kit's second pattern. Shown only on a vehicle that has one, like every
	-- other control here.
	{ Id = "Director", Label = "DIR" },
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
					-- Taken from where the lamp physically sits, with the adoption
					-- order kept only for a vehicle with no seat to measure against.
					-- Parity of the adoption order alternated whatever GetDescendants
					-- happened to return next, which on a bar modelled as Front, Rear
					-- and Side groups scatters rather than splitting left from right,
					-- so the bar read as flickering instead of lighting up.
					Side = VehicleLights.sideOf(descendant, model) or (#parts % 2),
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
	self.tracked[model] = { Parts = parts, Lit = false }
end

-- The siren sounds belonging to the vehicle being driven.
--
-- There used to be a _syncSiren here that walked the whole model, stopped every
-- tone it found and played the one the server's attribute named, at this
-- framework's volume. The vehicles already have a script that does exactly that
-- from the driver's keyboard, over the same four Sound objects, with its own
-- volumes and its own idea of which tone is on. Two owners of one Sound is a
-- siren that stops whenever the other one spoke last, which is what a panel
-- button that appears to do nothing looks like.
--
-- The panel drives the vehicle's own sounds the way its own keys do, and reads
-- which tone is running from the sounds themselves rather than from the value
-- the server last recorded. One owner, one truth.
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

-- The airhorn, which is held rather than selected. Not looped, and the tone
-- underneath it is left running: sounding the horn over a wail is what the horn
-- is for.
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

	-- The panel follows the vehicle's keys as well as driving them. R, T and G go
	-- straight to the vehicle's own script, so a button lit for a tone that
	-- stopped ten seconds ago is worse than no button at all. Compared rather
	-- than repainted, so the usual answer costs one string comparison.
	if self.panel and self.panel.Visible then
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
			local circuitOn = record.CircuitAttribute ~= nil
				and model:GetAttribute(record.CircuitAttribute) == true
			-- Work lights belong to the scene, not to the response.
			--
			-- Takedowns, alleys and scene lamps are white and steady. The Peugeot
			-- authors them at rgb(159,173,192) against rgb(96,117,207) for every
			-- blue in the same bar, which is the model itself saying these are a
			-- different kind of lamp.
			--
			-- They were on their own button and nothing else, so a full response
			-- left six lamps dark in the middle of the bar. They are not part of a
			-- response - pointing takedowns at oncoming traffic at speed is the one
			-- thing they are never for - but they are exactly what a car stopped at
			-- a scene puts on. So AT SCENE lights them, steady, alongside the rear
			-- warning lamps, and 999 leaves them off.
			local steadyCircuit = settings.SteadyCircuits[record.Circuit] == true
			local inStage = (not steadyCircuit) and stage >= settings.Stages
				or (steadyCircuit and stage == 1)
				or (stage == 1 and (record.Circuit == "RearBlue" or record.Circuit == "RearReds"))
				or (stage == 1 and record.Circuit == nil and index % 2 == 0)
				or circuitOn
			-- Work lights hold; warning lights alternate. A scene lamp that strobes
			-- is not a scene lamp.
			local steady = settings.SteadyCircuits[record.Circuit] == true
			local on = inStage and (steady or record.Side == phase)
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
			-- The fitting decides the colour, and only the blues take the
			-- department's. Reds are red and work lights are white on every marked
			-- car there is, so a force whose palette contains neither still gets
			-- both, which is what the alternation by adoption index could never do.
			local fitted = settings.CircuitColours[record.Circuit]
			local colour = if not on
				then record.Colour
				elseif fitted then fitted
				else (if record.Side == 0 then primary else secondary)
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

-- One key on the panel: your cap, with an indicator above the legend.
--
-- The cap keeps the colour it always had. What is new is the lamp strip along
-- the top of it, which is the only thing that changes when the function comes
-- on. Swapping the whole cap to a brighter shade said "something happened" but
-- not "this is on", and on a panel where nine controls can be on at once that is
-- the difference between reading the panel and counting it.
--
-- The legend is set in medium rather than bold. Bold at twelve pixels, then
-- carried through the panel's UIScale on a phone, is the smearing that made
-- these hard to read: the weight closes the counters before the size does.
-- Medium at thirteen survives the same scale with the letterforms still open.
function EmergencyLightsController:_button(
	parent: Instance,
	id: string,
	text: string,
	colour: Color3?
): TextButton
	local item = Instance.new("TextButton")
	item.Name = id
	item.AutoButtonColor = false
	item.BackgroundColor3 = colour or CAP
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamMedium
	item.Text = text
	item.TextColor3 = LEGEND
	item.TextSize = 13
	item.TextWrapped = true
	item.LineHeight = 1.05
	item.Parent = parent
	corner(item, 9)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(63, 67, 66)
	stroke.Thickness = 2
	stroke.Parent = item
	-- The legend sits below the lamp rather than under it. Without this the
	-- indicator lies across the first line of any two-line label.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 13)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.Parent = item

	local lamp = Instance.new("Frame")
	lamp.Name = "Lamp"
	lamp.AnchorPoint = Vector2.new(0.5, 0)
	lamp.Position = UDim2.new(0.5, 0, 0, 5)
	-- A third of the cap, not all of it. Full width read as a progress bar across
	-- the top of the button rather than as an indicator on it.
	lamp.Size = UDim2.new(0.34, 0, 0, 4)
	lamp.BackgroundColor3 = LAMP_DARK
	lamp.BorderSizePixel = 0
	lamp.ZIndex = 2
	lamp.Parent = item
	corner(lamp, 2)
	local glow = Instance.new("UIStroke")
	glow.Color = LAMP_ON
	glow.Thickness = 3
	glow.Transparency = 1
	glow.Parent = lamp

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
	self.lamps[id] = { Frame = lamp, Glow = glow }
	return item
end

-- Lights or darkens a key's indicator. The halo is what reads as a lamp rather
-- than a coloured strip, and it is only paid for while something is lit.
function EmergencyLightsController:_lamp(id: string, on: boolean, colour: Color3?)
	local record = self.lamps[id]
	if not record then
		return
	end
	local shade = colour or LAMP_ON
	record.Frame.BackgroundColor3 = if on then shade else LAMP_DARK
	record.Glow.Color = shade
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
	-- one is what gives the box an edge to catch light on, which is most of the
	-- difference between a control head and a rectangle.
	local panel = Instance.new("Frame")
	panel.Name = "Controller"
	panel.AnchorPoint = Vector2.new(1, 1)
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
	title.Position = UDim2.fromOffset(11, 7)
	title.Size = UDim2.new(1, -22, 0, 13)
	title.Font = Enum.Font.GothamMedium
	title.Text = "SIREN / LIGHT CONTROL"
	title.TextColor3 = ENGRAVED
	title.TextSize = 10
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = face

	-- What the unit is doing, in a backlit window rather than as a label that
	-- changes colour. A real head tells you the state without you reading the keys.
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, -11, 0, 5)
	readout.Size = UDim2.fromOffset(80, 16)
	readout.BackgroundColor3 = CHASSIS
	readout.BorderSizePixel = 0
	readout.Font = Enum.Font.GothamMedium
	readout.Text = "STANDBY"
	readout.TextColor3 = LAMP_GREEN
	readout.TextSize = 10
	readout.Parent = face
	corner(readout, 3)
	self.readout = readout

	local function row(name: string): Frame
		local item = Instance.new("Frame")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Parent = face
		return item
	end
	self.toneRow = row("Tones")
	self.hornRow = row("Horn")
	self.modeRow = row("Modes")

	-- Discrete tone keys rather than one key that cycles.
	--
	-- A cycling button makes the officer press three times to reach the tone they
	-- want and gives no way to see what the others are. Every control head, and
	-- the EVL panel these vehicles ship with, puts each tone on its own key with
	-- its own indicator. Pressing the tone that is running silences it, which is
	-- what the vehicle's own keys do.
	for _, control in TONE_CONTROLS do
		local item = self:_button(self.toneRow, control.Id, control.Label)
		item.Activated:Connect(function()
			self:_setTone(if self:_playingTone() == control.Id then "" else control.Id)
			self:_paint()
		end)
	end

	-- Held, not selected. Down on press and up on release, and also when the
	-- pointer leaves while still held, which is otherwise how a horn sticks on.
	local horn = self:_button(self.hornRow, "Airhorn", "AIR HORN")
	table.insert(
		self.connections,
		horn.MouseButton1Down:Connect(function()
			self:_setHorn(true)
			self:_lamp("Airhorn", true, LAMP_RED)
		end)
	)
	local function hornUp()
		self:_setHorn(false)
		self:_lamp("Airhorn", false)
	end
	table.insert(self.connections, horn.MouseButton1Up:Connect(hornUp))
	table.insert(self.connections, horn.MouseLeave:Connect(hornUp))

	for _, control in MODE_CONTROLS do
		local item = self:_button(self.modeRow, control.Id, control.Label)
		item.Activated:Connect(function()
			self:_activate(control.Id)
		end)
	end

	-- The moulded seam between the audio half of the head and the lighting half,
	-- which is how these boxes are actually divided.
	local seam = Instance.new("Frame")
	seam.Name = "Seam"
	seam.BackgroundColor3 = SEAM
	seam.BorderSizePixel = 0
	seam.Parent = face
	self.seam = seam

	local grid = Instance.new("Frame")
	grid.Name = "Circuits"
	grid.BackgroundTransparency = 1
	grid.Parent = face
	self.grid = grid
	local layout = Instance.new("UIGridLayout")
	self.gridLayout = layout
	layout.CellSize = UDim2.fromOffset(66, 52)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, control in CIRCUIT_CONTROLS do
		local item = self:_button(grid, control.Id, control.Label)
		item.LayoutOrder = order
		item.Activated:Connect(function()
			self:_activate(control.Id)
		end)
	end
end

function EmergencyLightsController:_reshape(compact: boolean)
	if self.compactShape == compact then
		return
	end
	self.compactShape = compact
	self.laidOut = nil
	self:_layout()
end

-- Positions every row and sizes the moulding to what it is actually holding.
--
-- Rows that are hidden take no space and a vehicle reporting nine circuits gets
-- a shorter box than one reporting thirteen. A control head with gaps in it
-- reads as a broken one.
function EmergencyLightsController:_layout()
	if not self.face then
		return
	end
	local compact = self.compactShape == true
	local size = if compact then COMPACT_PANEL else FULL_PANEL
	local inset, gap = 10, 6
	local width = size.X - 12 - inset * 2
	local top = 25

	local function visibleIn(frame: Frame): { TextButton }
		local list = {}
		for _, child in frame:GetChildren() do
			if child:IsA("TextButton") and child.Visible then
				table.insert(list, child)
			end
		end
		return list
	end

	-- Keys are sized by count, so a row of three and a row of one still produce
	-- caps of the same width. Different-sized keys for no reason is the first
	-- thing that gives a panel away as drawn rather than moulded.
	local keyHeight = if compact then 34 else 40
	local function bandCell(count: number): number
		return math.floor((width - (count - 1) * gap) / math.max(count, 1))
	end

	if compact then
		-- One bank across the top on a landscape phone. Stacked, the three rows
		-- leave the circuit grid almost nothing, and width is the dimension a
		-- landscape screen actually has.
		local tones, horn, modes =
			visibleIn(self.toneRow), visibleIn(self.hornRow), visibleIn(self.modeRow)
		local total = math.max(#tones + #horn + #modes, 1)
		local cell = bandCell(total)
		local left = inset
		local function bank(frame: Frame, keys: { TextButton })
			frame.Visible = #keys > 0
			if #keys == 0 then
				return
			end
			frame.Position = UDim2.fromOffset(left, top)
			frame.Size = UDim2.fromOffset(#keys * cell + (#keys - 1) * gap, keyHeight)
			for i, key in keys do
				key.Position = UDim2.fromOffset((i - 1) * (cell + gap), 0)
				key.Size = UDim2.fromOffset(cell, keyHeight)
			end
			left += #keys * (cell + gap)
		end
		bank(self.toneRow, tones)
		bank(self.hornRow, horn)
		bank(self.modeRow, modes)
		top += keyHeight + gap
	else
		local function place(frame: Frame, height: number)
			local keys = visibleIn(frame)
			frame.Visible = #keys > 0
			if #keys == 0 then
				return
			end
			local cell = bandCell(#keys)
			frame.Position = UDim2.fromOffset(inset, top)
			frame.Size = UDim2.fromOffset(width, height)
			for i, key in keys do
				key.Position = UDim2.fromOffset((i - 1) * (cell + gap), 0)
				key.Size = UDim2.fromOffset(cell, height)
			end
			top += height + gap
		end
		place(self.toneRow, keyHeight)
		place(self.hornRow, if compact then 32 else 38)
		place(self.modeRow, keyHeight)
	end

	self.seam.Position = UDim2.fromOffset(inset, top + 1)
	self.seam.Size = UDim2.fromOffset(width, 1)
	top += gap + 2

	local columns = if compact then 6 else 3
	local cellWidth = math.floor((width - (columns - 1) * gap) / columns)
	local cellHeight = if compact then 40 else 52
	self.gridLayout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	self.grid.Position = UDim2.fromOffset(inset, top)
	local circuits = #visibleIn(self.grid)
	local rows = math.max(math.ceil(circuits / columns), 1)
	local gridHeight = rows * cellHeight + (rows - 1) * gap
	self.grid.Size = UDim2.fromOffset(width, gridHeight)
	self.panel.Size = UDim2.fromOffset(size.X, top + gridHeight + inset + 12)
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
	-- The audio controls come off the panel on a vehicle that cannot sound them,
	-- for the same reason a circuit does: a button that records a state against a
	-- speaker the vehicle does not have is indistinguishable, to the person
	-- pressing it, from a broken button.
	-- A key for a sound the vehicle does not carry comes off the head, for the
	-- same reason a circuit does: a control that records a state against
	-- equipment the vehicle does not have is indistinguishable, to the person
	-- pressing it, from a broken one.
	local rack = self:_sirenRack()
	for _, control in TONE_CONTROLS do
		local key = self.buttons[control.Id]
		if key then
			key.Visible = rack ~= nil and self:_toneSound(rack, control.Id) ~= nil
		end
	end
	if self.buttons.Airhorn then
		self.buttons.Airhorn.Visible = rack ~= nil
			and self:_toneSound(rack, VehicleLights.MomentaryTone) ~= nil
	end
	-- Measured again only when what is on the panel actually changed.
	--
	-- _paint runs on every request, and this used to re-measure the box each
	-- time, so the head resized on every button press - shrinking and growing
	-- under the officer's finger as availability momentarily differed between one
	-- reply and the next. A control head does not change size when you press it.
	-- The signature is the visible set, so a genuine change still re-lays it out.
	if self.grid then
		local signature = {}
		for _, name in { "Tones", "Horn", "Modes", "Circuits" } do
			local frame = self.face and self.face:FindFirstChild(name)
			if frame then
				for _, child in frame:GetChildren() do
					if child:IsA("TextButton") and child.Visible then
						table.insert(signature, child.Name)
					end
				end
			end
		end
		table.sort(signature)
		local joined = table.concat(signature, ",")
		if joined ~= self.laidOut then
			self.laidOut = joined
			self:_layout()
		end
	end
end

function EmergencyLightsController:_paint()
	local state = self.state
	self:_applyAvailability()

	for _, control in CIRCUIT_CONTROLS do
		local active = if control.Id == "Director"
			then (self.directorStep or 0) > 0
			elseif control.Id == "Master" then state.Stage == self.settings.Stages
			elseif control.Id == "LowPower" then state.LowPower == true
			elseif control.Id == "RunLock" then state.RunLock == true
			else state.Circuits and state.Circuits[control.Id] == true
		local fitted = self.settings.CircuitColours[control.Id]
		local shade = if fitted
			then fitted
			elseif control.Id == "LowPower" or control.Id == "RunLock" then LAMP_ON
			else LAMP_BLUE
		self:_lamp(control.Id, active, shade)
	end

	-- Asked of the vehicle, not of the record. The driver can change tone with
	-- the vehicle's own keys at any moment, and a head reporting the framework's
	-- last recorded value instead is a head that lies.
	local tone = self:_playingTone()
	for _, control in TONE_CONTROLS do
		self:_lamp(control.Id, tone == control.Id, LAMP_RED)
	end

	local stage = state.Stage or 0
	self:_lamp("Reset", stage == 0, LAMP_GREEN)
	self:_lamp("AtScene", stage == 1, LAMP_ON)
	self:_lamp("Response", stage >= self.settings.Stages, LAMP_BLUE)

	if self.readout then
		-- Circuits count, not just the stage.
		--
		-- A vehicle with FRONT BLUE and REAR BLUE switched on has a bar flashing
		-- above the bonnet at stage zero, and the readout said STANDBY, because it
		-- only ever looked at the stage. A head that reports standby while the
		-- lights are running is worse than one that reports nothing.
		local anyCircuit = false
		if state.Circuits then
			for _, on in state.Circuits do
				if on == true then
					anyCircuit = true
					break
				end
			end
		end
		local text = if stage >= self.settings.Stages
			then "RESPONSE"
			elseif stage == 1 then "AT SCENE"
			elseif anyCircuit then "LIGHTS ON"
			else "STANDBY"
		if tone ~= "" then
			text = string.upper(tone)
		end
		self.readout.Text = text
		self.readout.TextColor3 = if tone ~= ""
			then LAMP_RED
			elseif stage > 0 or anyCircuit then LAMP_BLUE
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
	-- The three modes, handled before anything else.
	--
	-- These used to be wired with their own inline handlers on the buttons. The
	-- rebuild routed every key through here instead and did not bring them with
	-- it, so all three fell through to the branch at the bottom and asked the
	-- server to toggle a circuit named "Reset", "AtScene" or "Response". No such
	-- circuit exists, so the request did nothing at all: pressing OFF left the
	-- lights running.
	--
	-- Each one drives the tone as well as the stage, because nothing watches the
	-- siren attribute any more - the panel plays the vehicle's own sounds.
	if id == "Reset" then
		if (self.state.Stage or 0) > 0 then
			self:_cycleKit("MainELS")
		end
		self:_setTone("")
		self:_request({ Reset = true })
		self:_paint()
		return
	elseif id == "AtScene" then
		self:_setTone("")
		self:_request({ Stage = 1 })
		self:_paint()
		return
	elseif id == "Response" then
		if (self.state.Stage or 0) < self.settings.Stages then
			self:_cycleKit("MainELS")
		end
		self:_request({ Stage = self.settings.Stages })
		self:_setTone("Wail")
		self:_paint()
		return
	end
	if id == "Director" then
		-- Counted here because the kit will not say.
		--
		-- EasyLS keeps its director stage in a local and its remote answers only
		-- GetBinds, so there is nothing to read. The button lit nothing at all as a
		-- result, which on a control that cycles rather than toggles leaves no way
		-- to know whether it is running. Every press is one step through the kit's
		-- director patterns and back to off, so counting presses against the number
		-- of patterns tracks it exactly as long as this is the only thing pressing
		-- it - and it is, because the kit's own key for it is not bound anywhere in
		-- this fleet. Reset whenever the vehicle changes, so a stale count cannot
		-- follow the officer into the next car.
		self.directorStep = ((self.directorStep or 0) + 1) % (self.settings.DirectorStages + 1)
		self:_cycleKit("DirectorELS")
		self:_paint()
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
		self.vehicleOwnsKeys = false
		self.directorStep = 0
		self.panel.Visible = false
		self:_bindControls(false)
		return
	end
	-- Whether this vehicle came with its own keyboard controls. A fact about the
	-- model, so it is read from the model rather than from the server's reply.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local vehicle = seat and seat:FindFirstAncestorOfClass("Model")
	self.vehicleOwnsKeys = vehicle ~= nil and vehicle:FindFirstChild("SirenControl", true) ~= nil
	if vehicle ~= self.lastVehicle then
		self.lastVehicle = vehicle
		self.directorStep = 0
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
	-- Not on a vehicle that brought its own keys.
	--
	-- Every emergency vehicle in this fleet carries a siren box, cloned into the
	-- driver's PlayerGui, that binds R, T, G and F through UserInputService. This
	-- bound F for lights and G for sirens, and sinking an input in
	-- ContextActionService does not stop UserInputService seeing it: both handlers
	-- ran on one press. F toggled the framework's lights and sounded the vehicle's
	-- airhorn; G cycled this panel's tone and switched the car to priority
	-- underneath it. The vehicle's keys win, and the panel needs no key of its own.
	local wanted = available and not self.vehicleOwnsKeys
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
	-- recorded. The two differ the moment the driver uses the vehicle's own keys,
	-- and stepping from the stale one skips a tone or repeats one.
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
				-- Sat on the bottom right rather than floating at half height.
				--
				-- Centred vertically, the panel had nothing to line up with: it hung
				-- in the middle of the right-hand side with a gap above and below it,
				-- and because its height changed with the vehicle, that gap moved
				-- from car to car. Every other element of the driving HUD is anchored
				-- to an edge, and this is a dashboard control, so the bottom right is
				-- both where the rest of the furniture is and where a control head
				-- actually lives.
				--
				-- The same reserve as the compact shape, so it clears the pedals on a
				-- touchscreen and the speedometer everywhere else.
				self:_reshape(false)
				local reserve = if layout.InputMode == "Touch"
					then layout.HotbarBottom + Config.DrivingControls.PedalSize + 34
					else layout.HotbarBottom + 16
				self.panel.AnchorPoint = Vector2.new(1, 1)
				self.panel.Position = UDim2.new(1, -(layout.SafeRight + 16), 1, -reserve)
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
