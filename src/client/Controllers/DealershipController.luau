--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TERMINAL_TAG = "RoleplayOSVehicleTerminal"
local CLOSE_ACTION = "RoleplayOSDealershipClose"
local DealershipController = { connections = {}, terminalConnections = {}, selectedTab = "Owned" }

type VehicleView = {
	Id: string,
	DefinitionId: string,
	Name: string,
	Subtitle: string,
	Registration: string?,
	Available: boolean,
	Requirement: string?,
}

local colours = {
	background = Color3.fromRGB(8, 13, 21),
	surface = Color3.fromRGB(15, 23, 34),
	raised = Color3.fromRGB(23, 33, 47),
	accent = Color3.fromRGB(48, 128, 212),
	text = Color3.fromRGB(244, 247, 251),
	muted = Color3.fromRGB(157, 171, 190),
	success = Color3.fromRGB(78, 184, 132),
	locked = Color3.fromRGB(204, 157, 74),
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(parent: Instance, text: string, size: number, bold: boolean): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	value.Text = text
	value.TextColor3 = colours.text
	value.TextSize = size
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local function button(parent: Instance, text: string): TextButton
	local value = Instance.new("TextButton")
	value.AutoButtonColor = false
	value.BackgroundColor3 = colours.raised
	value.BorderSizePixel = 0
	value.Font = Enum.Font.GothamBold
	value.Text = text
	value.TextColor3 = colours.text
	value.TextSize = 12
	value.Parent = parent
	corner(value, 9)
	local pressScale = Instance.new("UIScale")
	pressScale.Parent = value
	value.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(pressScale, TweenInfo.new(0.1), { Scale = 0.97 }):Play()
		end
	end)
	value.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(pressScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end
	end)
	return value
end

local function readString(source: any, keys: { string }, fallback: string): string
	if type(source) ~= "table" then
		return fallback
	end
	for _, key in keys do
		if type(source[key]) == "string" and source[key] ~= "" then
			return source[key]
		end
	end
	return fallback
end

local function normalise(source: any): VehicleView
	local id = readString(source, { "Id", "VehicleId", "DefinitionId" }, "unknown")
	local available = source.Available ~= false
		and source.Locked ~= true
		and source.CanSpawn ~= false
	return {
		Id = id,
		DefinitionId = readString(source, { "DefinitionId" }, id),
		Name = readString(source, { "Name", "DisplayName" }, id),
		Subtitle = readString(source, { "Subtitle", "Class", "Description" }, "Vehicle"),
		Registration = readString(source, { "Registration", "RegistrationNumber" }, ""),
		Available = available,
		Requirement = if available
			then nil
			else readString(
				source,
				{ "Requirement", "LockedReason", "LockReason", "AccessMessage" },
				"This vehicle is not available for your current role."
			),
	}
end

function DealershipController:Init(context: any)
	self.context = context
	self.terminalId = nil
	self.owned = {}
	self.service = {}
	self.dealershipId = nil
	self.plateVehicleId = nil
	self.renderConnections = {}
end

function DealershipController:_connectRendered(signal: RBXScriptSignal, callback: (...any) -> ())
	table.insert(self.renderConnections, signal:Connect(callback))
end

function DealershipController:_clearRenderedConnections()
	for _, connection in self.renderConnections do
		connection:Disconnect()
	end
	table.clear(self.renderConnections)
end

-- Draws the actual inserted vehicle rather than relying on a separately
-- uploaded thumbnail that can drift from the model. The server supplies a
-- script-free visual copy for this player only; the ViewportFrame owns another
-- local clone, so preview-cache eviction cannot blank a card already on screen.
function DealershipController:_vehiclePreview(
	parent: Instance,
	definitionId: string,
	position: UDim2,
	size: UDim2
)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "VehiclePreview"
	viewport.Position = position
	viewport.Size = size
	viewport.BackgroundColor3 = Color3.fromRGB(11, 18, 28)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(150, 160, 178)
	viewport.LightColor = Color3.fromRGB(245, 248, 255)
	viewport.LightDirection = Vector3.new(-1, -0.8, -0.4)
	viewport.Parent = parent
	corner(viewport, 10)

	local placeholder = label(viewport, "VEHICLE", 9, true)
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.TextXAlignment = Enum.TextXAlignment.Center
	placeholder.TextColor3 = colours.muted
	local maximum = self.context.Configuration.VehicleSpawning.MaximumPreviewsPerPlayer or 6
	if (self.previewRequests or 0) >= maximum then
		return
	end
	self.previewRequests = (self.previewRequests or 0) + 1

	task.spawn(function()
		local response = self.context.Controllers.NetworkController:Request(
			"RequestVehiclePreview",
			{ DefinitionId = definitionId }
		)
		if not viewport.Parent or not response.Success then
			return
		end
		local previews = Players.LocalPlayer.PlayerGui:FindFirstChild("RoleplayOSVehiclePreviews")
		local source = previews and previews:WaitForChild(definitionId, 2)
		if not source or not source:IsA("Model") then
			return
		end
		local world = Instance.new("WorldModel")
		world.Parent = viewport
		local model = source:Clone()
		model.Parent = world
		local focus, bounds = model:GetBoundingBox()
		local radius = math.max(bounds.X, bounds.Y, bounds.Z, 1)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		camera.CFrame = CFrame.lookAt(
			focus.Position + Vector3.new(radius * 0.9, radius * 0.42, radius * 1.25),
			focus.Position
		)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		placeholder.Visible = false
	end)
end

function DealershipController:_openPlate(vehicle: VehicleView)
	if not self.dealershipId then
		return
	end
	self.plateVehicleId = vehicle.Id
	self.plateVehicle.Text = string.format("%s  ·  %s", vehicle.Name, vehicle.Registration or "")
	self.plateInput.Text = ""
	self.plateEditor.Visible = true
	self.plateInput:CaptureFocus()
end

function DealershipController:_applyPlate()
	if not self.plateVehicleId or not self.terminalId then
		return
	end
	self.plateApply.Active = false
	self.plateApply.Text = "CHECKING…"
	local response = self.context.Controllers.NetworkController:Request("SetCustomRegistration", {
		TerminalId = self.terminalId,
		VehicleId = self.plateVehicleId,
		Registration = self.plateInput.Text,
	})
	self.context.Controllers.NotificationController:Show(response.Message, "Custom registration")
	self.plateApply.Active = true
	self.plateApply.Text = "MODERATE & APPLY"
	if response.Success then
		self.plateEditor.Visible = false
		self.plateVehicleId = nil
		self:_open(self.terminalId)
	end
end

-- The panel is authored at a fixed size, so it is scaled against the area the
-- device actually leaves usable. Measuring the raw viewport pushed the panel
-- under the top bar and device cutouts on phones and notched displays.
-- Two authored sizes rather than one shrunk to fit.
--
-- A landscape phone is wide and very short, about nine hundred by four hundred
-- once the insets are taken out. Fitting a panel authored at 580 high into that
-- means rendering everything at roughly two thirds, which turns the ten and
-- eleven pixel labels into six and seven pixel ones. Scaling cannot rescue a
-- layout that is simply too tall; the layout has to be shorter, so that the
-- scale stays near one and the text stays the size it was designed to be.
local DESIGN = Vector2.new(760, 580)
local COMPACT_DESIGN = Vector2.new(700, 392)

function DealershipController:_setScale(layout: any)
	if not self.scale or not self.panel then
		return
	end
	local compact = layout.Compact == true
	local design = if compact then COMPACT_DESIGN else DESIGN
	self.panel.Size = UDim2.fromOffset(design.X, design.Y)
	self.scale.Scale = self.context.Controllers.UIOrchestrator:FitScale(layout, design, 20)
	if self.compact ~= compact then
		self.compact = compact
		self:_applyDensity()
		-- Card heights differ between the two, so the list has to be rebuilt
		-- rather than left at whatever density it was drawn with.
		if self.panel.Visible then
			self:_render()
		end
	end
end

-- Moves the header furniture up and the list with it when the panel is short.
-- The eyebrow and the page description are the first things to go: they are
-- context, and context is what a small screen has least room for.
function DealershipController:_applyDensity()
	local compact = self.compact == true
	if self.eyebrow then
		self.eyebrow.Visible = not compact
	end
	if self.title then
		self.title.Position = UDim2.fromOffset(24, if compact then 16 else 39)
		self.title.TextSize = if compact then 19 else 23
	end
	for index, tab in { self.ownedTab, self.serviceTab, self.showroomTab } do
		if tab then
			tab.Position = UDim2.fromOffset(tab.Position.X.Offset, if compact then 52 else 87)
			tab.Size = UDim2.fromOffset(tab.Size.X.Offset, if compact then 36 else 42)
		end
		local _ = index
	end
	if self.close then
		self.close.Position = UDim2.new(1, -62, 0, if compact then 14 else 20)
	end
	if self.heading then
		self.heading.Position = UDim2.fromOffset(24, if compact then 98 else 151)
	end
	if self.list then
		self.list.Position = UDim2.fromOffset(24, if compact then 122 else 181)
		self.list.Size = UDim2.new(1, -48, 1, if compact then -140 else -205)
	end
	if self.empty then
		self.empty.Position = UDim2.fromOffset(24, if compact then 130 else 190)
	end
end

function DealershipController:_setOpen(open: boolean)
	if not self.panel then
		return
	end
	self.panel.Visible = open
	self.backdrop.Visible = open
	if open then
		self.previousSelection = GuiService.SelectedObject
		self.panel.Position = UDim2.new(0.5, 0, 0.5, 12)
		TweenService:Create(
			self.panel,
			TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5) }
		):Play()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.close
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.panel) then
		local previous = self.previousSelection
		GuiService.SelectedObject = if previous and previous.Parent then previous else nil
	end
end

-- One card per vehicle on the forecourt. A locked vehicle stays on the list and
-- says what unlocks it, since hiding what cannot yet be afforded leaves a player
-- with no reason to earn anything.
function DealershipController:_showroomCard(vehicle: any)
	-- Shorter cards on a short screen, so three fit where two would. The list is
	-- the only part of this panel worth the space, and a card that never comes
	-- into view is worse than a slightly tighter one.
	local compact = self.compact == true
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, if compact then 78 else 104)
	card.BackgroundColor3 = colours.surface
	card.BorderSizePixel = 0
	card.Parent = self.list
	corner(card, 12)

	local buyable = not vehicle.Locked and vehicle.Affordable and not vehicle.Owned
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.fromOffset(4, if compact then 46 else 64)
	stripe.Position = UDim2.fromOffset(0, if compact then 16 else 20)
	stripe.BackgroundColor3 = if buyable then colours.success else colours.locked
	stripe.BorderSizePixel = 0
	stripe.Parent = card

	local name = label(card, tostring(vehicle.Name), if compact then 14 else 15, true)
	name.Position = UDim2.fromOffset(20, if compact then 11 else 17)
	name.Size = UDim2.new(1, -252, 0, 22)

	local price = label(card, string.format("£%d", vehicle.Price or 0), 13, true)
	price.Position = UDim2.fromOffset(20, if compact then 33 else 43)
	price.Size = UDim2.new(1, -252, 0, 18)
	price.TextColor3 = if vehicle.Affordable then colours.success else colours.locked

	local state = if vehicle.Owned
		then "ALREADY OWNED"
		elseif vehicle.Locked and vehicle.GamepassId then "UNLOCK WITH A PASS"
		elseif vehicle.Locked then tostring(vehicle.LockedReason or "LOCKED")
		elseif not vehicle.Affordable then "NOT ENOUGH MONEY"
		else "AVAILABLE"
	-- Never below eleven: this line carries the reason a car cannot be bought,
	-- which is the one thing on the card a player has to be able to read.
	local status = label(card, state, if compact then 11 else 10, true)
	status.Position = UDim2.fromOffset(20, if compact then 54 else 68)
	status.Size = UDim2.new(1, -252, 0, 21)
	status.TextColor3 = if buyable then colours.success else colours.locked

	-- Colours cycle on one button rather than opening a second panel. There are
	-- rarely more than a handful and a picker would be a whole screen for a
	-- choice that takes one tap.
	local palette = if type(vehicle.Colours) == "table" and #vehicle.Colours > 0
		then vehicle.Colours
		else { "Default" }
	local chosen = 1
	local colourButton = button(card, tostring(palette[chosen]))
	colourButton.Position = UDim2.new(1, -226, 0, if compact then 19 else 32)
	colourButton.Size = UDim2.fromOffset(98, if compact then 40 else 40)
	colourButton.BackgroundColor3 = colours.raised
	self:_connectRendered(colourButton.Activated, function()
		chosen = chosen % #palette + 1
		colourButton.Text = tostring(palette[chosen])
	end)

	local action = button(
		card,
		if vehicle.Owned
			then "OWNED"
			elseif vehicle.Locked and vehicle.GamepassId then "GET PASS"
			else "BUY"
	)
	action.Position = UDim2.new(1, -122, 0, if compact then 19 else 32)
	action.Size = UDim2.fromOffset(100, 40)
	action.BackgroundColor3 = if buyable or (vehicle.Locked and vehicle.GamepassId)
		then colours.accent
		else colours.raised
	action.Active = vehicle.Owned ~= true
		and (buyable or (vehicle.Locked and vehicle.GamepassId ~= nil))
	self:_connectRendered(action.Activated, function()
		if vehicle.Locked and vehicle.GamepassId then
			self.context.Controllers.GamepassController:Prompt(vehicle.GamepassId)
			return
		end
		self:_purchase(vehicle, tostring(palette[chosen]), action)
	end)
	self:_vehiclePreview(
		card,
		vehicle.DefinitionId,
		UDim2.fromOffset(12, if compact then 8 else 12),
		UDim2.fromOffset(if compact then 92 else 122, if compact then 62 else 80)
	)
	name.Position = UDim2.fromOffset(if compact then 116 else 150, if compact then 11 else 17)
	price.Position = UDim2.fromOffset(if compact then 116 else 150, if compact then 33 else 43)
	status.Position = UDim2.fromOffset(if compact then 116 else 150, if compact then 54 else 68)
end

function DealershipController:_purchase(vehicle: any, colour: string, action: TextButton)
	action.Active = false
	action.Text = "BUYING…"
	local response = self.context.Controllers.NetworkController:Request("PurchaseVehicle", {
		TerminalId = self.terminalId,
		CharacterId = self.characterId,
		DealershipId = self.dealershipId,
		DefinitionId = vehicle.DefinitionId,
		Colour = colour,
	})
	self.context.Controllers.NotificationController:Show(
		if response.Success then "Purchased " .. tostring(vehicle.Name) else response.Message,
		"Dealership"
	)
	if not response.Success then
		action.Active = true
		action.Text = "BUY"
		return
	end
	-- Reopened rather than patched, so the balance, the garage and what is now
	-- affordable all come back from the server together rather than being
	-- guessed at here.
	self:_open(self.terminalId)
end

function DealershipController:_render()
	self:_clearRenderedConnections()
	self.previewRequests = 0
	for _, child in self.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local vehicles = if self.selectedTab == "Owned"
		then self.owned
		elseif self.selectedTab == "Showroom" then self.showroom
		else self.service
	self.ownedTab.BackgroundColor3 = if self.selectedTab == "Owned"
		then colours.accent
		else colours.raised
	self.serviceTab.BackgroundColor3 = if self.selectedTab == "Service"
		then colours.accent
		else colours.raised
	self.showroomTab.BackgroundColor3 = if self.selectedTab == "Showroom"
		then colours.accent
		else colours.raised
	self.heading.Text = if self.selectedTab == "Owned"
		then "YOUR GARAGE"
		elseif self.selectedTab == "Showroom" then string.format(
			"SHOWROOM  ·  £%d AVAILABLE",
			self.balance or 0
		)
		else "SERVICE FLEET"
	self.empty.Visible = #vehicles == 0
	if self.selectedTab == "Showroom" then
		for _, vehicle in vehicles do
			self:_showroomCard(vehicle)
		end
		return
	end
	for _, rawVehicle in vehicles do
		local vehicle = normalise(rawVehicle)
		local card = Instance.new("Frame")
		local compact = self.compact == true
		card.Size = UDim2.new(1, -8, 0, if compact then 78 else 104)
		card.BackgroundColor3 = colours.surface
		card.BorderSizePixel = 0
		card.Parent = self.list
		corner(card, 12)
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromOffset(4, if compact then 46 else 64)
		stripe.Position = UDim2.fromOffset(0, if compact then 16 else 20)
		stripe.BackgroundColor3 = if vehicle.Available then colours.success else colours.locked
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		local name = label(card, vehicle.Name, 15, true)
		name.Position = UDim2.fromOffset(if compact then 116 else 150, if compact then 11 else 17)
		name.Size = UDim2.new(1, -174, 0, 22)
		local details = label(card, vehicle.Subtitle, 11, false)
		details.Position =
			UDim2.fromOffset(if compact then 116 else 150, if compact then 32 else 43)
		details.Size = UDim2.new(1, -174, 0, 18)
		details.TextColor3 = colours.muted
		local access = label(
			card,
			if vehicle.Available
				then (if vehicle.Registration and vehicle.Registration ~= ""
					then vehicle.Registration
					else "READY TO SPAWN")
				else vehicle.Requirement :: string,
			10,
			true
		)
		access.Position = UDim2.fromOffset(if compact then 116 else 150, if compact then 53 else 68)
		access.Size = UDim2.new(1, -174, 0, 21)
		access.TextColor3 = if vehicle.Available then colours.success else colours.locked
		access.TextTruncate = Enum.TextTruncate.AtEnd
		local canCustomise = self.selectedTab == "Owned" and self.dealershipId ~= nil
		local spawn = button(card, if vehicle.Available then "SPAWN" else "LOCKED")
		spawn.Position =
			UDim2.new(1, -138, 0, if compact then 19 else if canCustomise then 11 else 32)
		spawn.Size = UDim2.fromOffset(118, 40)
		spawn.BackgroundColor3 = if vehicle.Available then colours.accent else colours.raised
		spawn.Active = vehicle.Available
		if vehicle.Available then
			self:_connectRendered(spawn.Activated, function()
				spawn.Active = false
				spawn.Text = "SPAWNING…"
				local endpoint = if self.selectedTab == "Owned"
					then "SpawnOwnedVehicle"
					else "SpawnServiceVehicle"
				local payload = { TerminalId = self.terminalId }
				if self.selectedTab == "Owned" then
					payload.VehicleId = vehicle.Id
				else
					payload.DefinitionId = vehicle.Id
				end
				local response =
					self.context.Controllers.NetworkController:Request(endpoint, payload)
				self.context.Controllers.NotificationController:Show(response.Message, "Garage")
				if response.Success then
					self:_setOpen(false)
				else
					spawn.Active = true
					spawn.Text = "SPAWN"
				end
			end)
		end
		if canCustomise and not compact then
			local custom = button(card, "CUSTOM PLATE")
			custom.Position = UDim2.new(1, -138, 0, 56)
			custom.Size = UDim2.fromOffset(118, 36)
			self:_connectRendered(custom.Activated, function()
				self:_openPlate(vehicle)
			end)
		end
		self:_vehiclePreview(
			card,
			vehicle.DefinitionId,
			UDim2.fromOffset(12, if compact then 8 else 12),
			UDim2.fromOffset(if compact then 92 else 122, if compact then 62 else 80)
		)
	end
end

function DealershipController:_open(terminalId: string)
	self.terminalId = terminalId
	self.loading.Visible = true
	self.list.Visible = false
	self:_setOpen(true)
	local response = self.context.Controllers.NetworkController:Request("GetVehicleSpawnMenu", {
		TerminalId = terminalId,
	})
	self.loading.Visible = false
	self.list.Visible = true
	if not response.Success then
		self:_setOpen(false)
		self.context.Controllers.NotificationController:Show(response.Message, "Garage")
		return
	end
	local data = if type(response.Data) == "table" then response.Data else {}
	local terminal = if type(data.Terminal) == "table" then data.Terminal else {}
	self.dealershipId = if type(terminal.DealershipId) == "string"
		then terminal.DealershipId
		else nil
	self.owned = if type(data.OwnedVehicles) == "table" then data.OwnedVehicles else {}
	self.service = if type(data.ServiceVehicles) == "table" then data.ServiceVehicles else {}
	-- The forecourt is a second call because it is priced against the player's
	-- balance and their unlocks, which the spawn menu has no reason to know. A
	-- terminal that only spawns service vehicles has no forecourt, and the tab
	-- is hidden rather than opening on an empty list.
	self.showroom = {}
	self.balance = 0
	self.characterId = nil
	if self.dealershipId then
		local catalogue = self.context.Controllers.NetworkController:Request(
			"GetDealershipCatalogue",
			{ TerminalId = terminalId }
		)
		if catalogue.Success and type(catalogue.Data) == "table" then
			local payload = catalogue.Data
			self.showroom = if type(payload.Vehicles) == "table" then payload.Vehicles else {}
			self.balance = tonumber(payload.Balance) or 0
			self.characterId = payload.CharacterId
		end
	end
	self.showroomTab.Visible = #self.showroom > 0
	if self.selectedTab == "Showroom" and #self.showroom == 0 then
		self.selectedTab = "Owned"
	end
	self:_render()
end

function DealershipController:_bindTerminal(instance: Instance)
	if self.terminalConnections[instance] then
		return
	end
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		local promptParent = if instance:IsA("BasePart")
			then instance
			else instance:FindFirstChildWhichIsA("BasePart", true)
		if not promptParent then
			return
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Browse vehicles"
		prompt.ObjectText = tostring(instance:GetAttribute("DisplayName") or "Dealership")
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0.65
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent
	end
	prompt.ActionText = "Browse vehicles"
	prompt.ObjectText = tostring(instance:GetAttribute("DisplayName") or prompt.ObjectText)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	local connection = prompt.Triggered:Connect(function(player)
		if player ~= Players.LocalPlayer then
			return
		end
		local terminalId = instance:GetAttribute("TerminalId")
		if type(terminalId) ~= "string" or terminalId == "" then
			self.context.Controllers.NotificationController:Show(
				"This vehicle terminal is not configured.",
				"Garage"
			)
			return
		end
		self:_open(terminalId)
	end)
	self.terminalConnections[instance] = connection
end

function DealershipController:_buildUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSDealership"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.32
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.Parent = gui
	self.backdrop = backdrop
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(760, 580)
	panel.BackgroundColor3 = colours.background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)
	self.panel = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(35, 48, 65)
	stroke.Transparency = 0.25
	stroke.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	self.scale = scale
	local eyebrow = label(panel, "VEHICLE SERVICES", 10, true)
	eyebrow.Position = UDim2.fromOffset(24, 19)
	eyebrow.Size = UDim2.fromOffset(300, 18)
	eyebrow.TextColor3 = colours.muted
	self.eyebrow = eyebrow
	local title = label(panel, "Vehicles", 23, true)
	title.Position = UDim2.fromOffset(24, 39)
	title.Size = UDim2.new(1, -100, 0, 32)
	self.title = title
	local close = button(panel, "×")
	close.Position = UDim2.new(1, -62, 0, 20)
	close.Size = UDim2.fromOffset(38, 38)
	close.TextSize = 22
	self.close = close
	local ownedTab = button(panel, "OWNED")
	ownedTab.Position = UDim2.fromOffset(24, 87)
	ownedTab.Size = UDim2.fromOffset(150, 42)
	self.ownedTab = ownedTab
	local serviceTab = button(panel, "SERVICE FLEET")
	serviceTab.Position = UDim2.fromOffset(182, 87)
	serviceTab.Size = UDim2.fromOffset(166, 42)
	self.serviceTab = serviceTab
	-- The forecourt. Without it the dealership could only ever hand back a
	-- vehicle the player already had, so a first car was unobtainable.
	local showroomTab = button(panel, "BUY A VEHICLE")
	showroomTab.Position = UDim2.fromOffset(356, 87)
	showroomTab.Size = UDim2.fromOffset(166, 42)
	self.showroomTab = showroomTab
	local heading = label(panel, "YOUR GARAGE", 11, true)
	heading.Position = UDim2.fromOffset(24, 151)
	heading.Size = UDim2.new(1, -48, 0, 20)
	heading.TextColor3 = colours.muted
	self.heading = heading
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(24, 181)
	list.Size = UDim2.new(1, -48, 1, -205)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = colours.accent
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	self.list = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list
	local loading = label(panel, "Loading available vehicles…", 13, false)
	loading.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.Position = UDim2.fromScale(0.5, 0.55)
	loading.Size = UDim2.fromOffset(300, 24)
	loading.TextXAlignment = Enum.TextXAlignment.Center
	loading.TextColor3 = colours.muted
	loading.Visible = false
	self.loading = loading
	local empty = label(list, "No vehicles are available in this category.", 13, false)
	empty.Size = UDim2.new(1, -8, 0, 70)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextColor3 = colours.muted
	empty.Visible = false
	self.empty = empty
	local plateEditor = Instance.new("Frame")
	plateEditor.Size = UDim2.fromScale(1, 1)
	plateEditor.BackgroundColor3 = colours.background
	plateEditor.BorderSizePixel = 0
	plateEditor.Visible = false
	plateEditor.ZIndex = 40
	plateEditor.Parent = panel
	corner(plateEditor, 16)
	local plateEyebrow = label(plateEditor, "DEALERSHIP SERVICE DESK", 10, true)
	plateEyebrow.Position = UDim2.fromOffset(36, 42)
	plateEyebrow.Size = UDim2.new(1, -72, 0, 22)
	plateEyebrow.TextColor3 = colours.muted
	local plateTitle = label(plateEditor, "Custom registration", 25, true)
	plateTitle.Position = UDim2.fromOffset(36, 68)
	plateTitle.Size = UDim2.new(1, -72, 0, 38)
	local plateCopy = label(
		plateEditor,
		"Choose 2–8 letters, numbers or spaces. Every submission is checked before it is displayed.",
		13,
		false
	)
	plateCopy.Position = UDim2.fromOffset(36, 116)
	plateCopy.Size = UDim2.new(1, -72, 0, 48)
	plateCopy.TextColor3 = colours.muted
	plateCopy.TextWrapped = true
	local plateVehicle = label(plateEditor, "", 13, true)
	plateVehicle.Position = UDim2.fromOffset(36, 190)
	plateVehicle.Size = UDim2.new(1, -72, 0, 28)
	local plateInput = Instance.new("TextBox")
	plateInput.Position = UDim2.fromOffset(36, 232)
	plateInput.Size = UDim2.new(1, -72, 0, 76)
	plateInput.BackgroundColor3 = Color3.fromRGB(243, 201, 45)
	plateInput.BorderSizePixel = 0
	plateInput.ClearTextOnFocus = false
	plateInput.Font = Enum.Font.RobotoMono
	plateInput.PlaceholderText = "AB12 CDE"
	plateInput.Text = ""
	plateInput.TextColor3 = Color3.fromRGB(14, 17, 20)
	plateInput.TextSize = 28
	plateInput.ZIndex = 41
	plateInput.Parent = plateEditor
	corner(plateInput, 10)
	local plateApply = button(plateEditor, "MODERATE & APPLY")
	plateApply.Position = UDim2.fromOffset(36, 338)
	plateApply.Size = UDim2.new(0.64, -6, 0, 52)
	plateApply.BackgroundColor3 = colours.accent
	plateApply.ZIndex = 41
	local plateCancel = button(plateEditor, "CANCEL")
	plateCancel.Position = UDim2.new(0.64, 6, 0, 338)
	plateCancel.Size = UDim2.new(0.36, -42, 0, 52)
	plateCancel.ZIndex = 41
	local plateNotice = label(
		plateEditor,
		"Custom registration gamepass required · roleplay registration only",
		10,
		true
	)
	plateNotice.Position = UDim2.fromOffset(36, 414)
	plateNotice.Size = UDim2.new(1, -72, 0, 24)
	plateNotice.TextColor3 = colours.locked
	for _, descendant in plateEditor:GetDescendants() do
		if descendant:IsA("GuiObject") and descendant.ZIndex < 41 then
			descendant.ZIndex = 41
		end
	end
	self.plateEditor = plateEditor
	self.plateVehicle = plateVehicle
	self.plateInput = plateInput
	self.plateApply = plateApply
	table.insert(
		self.connections,
		backdrop.Activated:Connect(function()
			self:_setOpen(false)
		end)
	)
	table.insert(
		self.connections,
		plateApply.Activated:Connect(function()
			self:_applyPlate()
		end)
	)
	table.insert(
		self.connections,
		plateCancel.Activated:Connect(function()
			plateEditor.Visible = false
			self.plateVehicleId = nil
		end)
	)
	table.insert(
		self.connections,
		close.Activated:Connect(function()
			self:_setOpen(false)
		end)
	)
	table.insert(
		self.connections,
		showroomTab.Activated:Connect(function()
			self.selectedTab = "Showroom"
			self:_render()
		end)
	)
	table.insert(
		self.connections,
		ownedTab.Activated:Connect(function()
			self.selectedTab = "Owned"
			self:_render()
		end)
	)
	table.insert(
		self.connections,
		serviceTab.Activated:Connect(function()
			self.selectedTab = "Service"
			self:_render()
		end)
	)
end

function DealershipController:Start()
	self:_buildUI()
	ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin or not self.panel.Visible then
			return Enum.ContextActionResult.Pass
		end
		self:_setOpen(false)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(CLOSE_ACTION, "Close vehicles")
	ContextActionService:SetDescription(CLOSE_ACTION, "Closes the dealership or service fleet menu")
	for _, instance in CollectionService:GetTagged(TERMINAL_TAG) do
		self:_bindTerminal(instance)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(TERMINAL_TAG):Connect(function(instance)
			self:_bindTerminal(instance)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(TERMINAL_TAG):Connect(function(instance)
			local connection = self.terminalConnections[instance]
			if connection then
				connection:Disconnect()
				self.terminalConnections[instance] = nil
			end
		end)
	)
	-- The orchestrator already tracks camera, top bar and input changes, so the
	-- panel follows one responsive source instead of watching the camera itself.
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Dealership", function(layout)
		self:_setScale(layout)
	end)
	table.insert(
		self.connections,
		self.context.Events.VehicleModeChanged.Event:Connect(function(active)
			if active then
				self:_setOpen(false)
			end
		end)
	)
end

function DealershipController:Destroy()
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if self.unbindLayout then
		self.unbindLayout()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.terminalConnections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.terminalConnections)
	self:_clearRenderedConnections()
	if self.gui then
		self.gui:Destroy()
	end
end

return DealershipController
