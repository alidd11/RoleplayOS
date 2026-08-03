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
function DealershipController:_setScale(layout: any)
	if not self.scale then
		return
	end
	self.scale.Scale =
		self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(760, 580), 28)
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

function DealershipController:_render()
	for _, child in self.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local vehicles = if self.selectedTab == "Owned" then self.owned else self.service
	self.ownedTab.BackgroundColor3 = if self.selectedTab == "Owned"
		then colours.accent
		else colours.raised
	self.serviceTab.BackgroundColor3 = if self.selectedTab == "Service"
		then colours.accent
		else colours.raised
	self.heading.Text = if self.selectedTab == "Owned" then "YOUR GARAGE" else "SERVICE FLEET"
	self.empty.Visible = #vehicles == 0
	for _, rawVehicle in vehicles do
		local vehicle = normalise(rawVehicle)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 104)
		card.BackgroundColor3 = colours.surface
		card.BorderSizePixel = 0
		card.Parent = self.list
		corner(card, 12)
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromOffset(4, 64)
		stripe.Position = UDim2.fromOffset(0, 20)
		stripe.BackgroundColor3 = if vehicle.Available then colours.success else colours.locked
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		local name = label(card, vehicle.Name, 15, true)
		name.Position = UDim2.fromOffset(20, 17)
		name.Size = UDim2.new(1, -174, 0, 22)
		local details = label(card, vehicle.Subtitle, 11, false)
		details.Position = UDim2.fromOffset(20, 43)
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
		access.Position = UDim2.fromOffset(20, 68)
		access.Size = UDim2.new(1, -174, 0, 21)
		access.TextColor3 = if vehicle.Available then colours.success else colours.locked
		access.TextTruncate = Enum.TextTruncate.AtEnd
		local canCustomise = self.selectedTab == "Owned" and self.dealershipId ~= nil
		local spawn = button(card, if vehicle.Available then "SPAWN" else "LOCKED")
		spawn.Position = UDim2.new(1, -138, 0, if canCustomise then 11 else 32)
		spawn.Size = UDim2.fromOffset(118, 40)
		spawn.BackgroundColor3 = if vehicle.Available then colours.accent else colours.raised
		spawn.Active = vehicle.Available
		if vehicle.Available then
			table.insert(
				self.connections,
				spawn.Activated:Connect(function()
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
			)
		end
		if canCustomise then
			local custom = button(card, "CUSTOM PLATE")
			custom.Position = UDim2.new(1, -138, 0, 56)
			custom.Size = UDim2.fromOffset(118, 36)
			table.insert(
				self.connections,
				custom.Activated:Connect(function()
					self:_openPlate(vehicle)
				end)
			)
		end
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
	local eyebrow = label(panel, "ROLEPLAYOS  /  VEHICLES", 10, true)
	eyebrow.Position = UDim2.fromOffset(24, 19)
	eyebrow.Size = UDim2.fromOffset(300, 18)
	eyebrow.TextColor3 = colours.muted
	local title = label(panel, "Dealership & Garage", 23, true)
	title.Position = UDim2.fromOffset(24, 39)
	title.Size = UDim2.new(1, -100, 0, 32)
	local close = button(panel, "×")
	close.Position = UDim2.new(1, -62, 0, 20)
	close.Size = UDim2.fromOffset(38, 38)
	close.TextSize = 22
	self.close = close
	local ownedTab = button(panel, "OWNED VEHICLES")
	ownedTab.Position = UDim2.fromOffset(24, 87)
	ownedTab.Size = UDim2.fromOffset(174, 42)
	self.ownedTab = ownedTab
	local serviceTab = button(panel, "SERVICE VEHICLES")
	serviceTab.Position = UDim2.fromOffset(208, 87)
	serviceTab.Size = UDim2.fromOffset(184, 42)
	self.serviceTab = serviceTab
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
	if self.gui then
		self.gui:Destroy()
	end
end

return DealershipController
