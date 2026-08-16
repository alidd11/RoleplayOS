--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Coalescer = require(ReplicatedStorage.RoleplayOS.Shared.Coalescer)
local TerminalTheme = require(script.Parent.Parent.UI.OperationalTerminalTheme)

local DispatchController = { connections = {}, selectedCallId = nil }

-- GetDispatchSnapshot refills at one per second and the MDT map draws from the
-- same endpoint on the same client, so each panel takes at most half of it.
local BOARD_REFRESH_INTERVAL = 2
local C = TerminalTheme

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = C.Raised
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = value
	item.TextColor3 = C.Text
	item.TextSize = 10
	item.Parent = parent
	corner(item, 8)
	return item
end

local function input(parent: Instance, placeholder: string): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = C.Raised
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = C.Muted
	item.Text = ""
	item.TextColor3 = C.Text
	item.TextSize = 11
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	corner(item, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 11)
	padding.PaddingRight = UDim.new(0, 11)
	padding.Parent = item
	return item
end

function DispatchController:Init(context: any)
	self.context = context
	self.characterConnections = {}
end

function DispatchController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSDispatchConsole"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.Enabled = false
	gui.DisplayOrder = 12
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local playerGui = gui.Parent
	if playerGui then
		playerGui:SetAttribute("RoleplayOSDispatchOpen", false)
	end

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new()
	dim.BackgroundTransparency = 0.28
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local shell = Instance.new("Frame")
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromScale(0.88, 0.86)
	shell.BackgroundColor3 = C.Surface
	shell.BorderSizePixel = 0
	shell.Parent = dim
	corner(shell, 22)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(760, 500)
	constraint.MaxSize = Vector2.new(1180, 720)
	constraint.Parent = shell
	self.constraint = constraint
	local scale = Instance.new("UIScale")
	scale.Parent = shell
	self.scale = scale
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Transparency = 0.1
	stroke.Parent = shell
	local classification = Instance.new("Frame")
	classification.Name = "Classification"
	classification.Size = UDim2.new(1, 0, 0, 4)
	classification.BackgroundColor3 = C.Classification
	classification.BorderSizePixel = 0
	classification.Parent = shell

	local title = label(shell, "JOINT CONTROL  ·  CAD OPERATIONS", 17, true)
	title.Position = UDim2.fromOffset(20, 13)
	title.Size = UDim2.new(1, -40, 0, 24)
	local live =
		label(shell, "●  LIVE  ·  MULTI-AGENCY DISPATCH  ·  CONSOLE AUTHENTICATED", 9, true)
	live.Position = UDim2.fromOffset(20, 38)
	live.Size = UDim2.new(1, -40, 0, 18)
	live.TextColor3 = C.Secure
	local close = button(shell, "CLOSE")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -20, 0, 18)
	close.Size = UDim2.fromOffset(70, 30)
	close.Activated:Connect(function()
		gui.Enabled = false
		if playerGui then
			playerGui:SetAttribute("RoleplayOSDispatchOpen", false)
		end
	end)
	local cctv = button(shell, "VIEW CCTV")
	cctv.AnchorPoint = Vector2.new(1, 0)
	cctv.Position = UDim2.new(1, -100, 0, 18)
	cctv.Size = UDim2.fromOffset(88, 30)
	cctv.BackgroundColor3 = C.Accent
	cctv.Activated:Connect(function()
		self.context.Controllers.CCTVController:Open()
	end)

	local metrics = Instance.new("Frame")
	metrics.Name = "OperationalSummary"
	metrics.BackgroundTransparency = 1
	metrics.Position = UDim2.fromOffset(20, 68)
	metrics.Size = UDim2.new(1, -40, 0, 48)
	metrics.Parent = shell
	local metricLayout = Instance.new("UIListLayout")
	metricLayout.FillDirection = Enum.FillDirection.Horizontal
	metricLayout.Padding = UDim.new(0, 8)
	metricLayout.SortOrder = Enum.SortOrder.LayoutOrder
	metricLayout.Parent = metrics
	self.statLabels = {}
	local metricDefinitions = {
		{ "ACTIVE CALLS", C.Accent },
		{ "IMMEDIATE", C.Immediate },
		{ "ON SCENE", C.Secure },
		{ "UNITS ONLINE", C.Classification },
	}
	for index, definition in metricDefinitions do
		local metric = Instance.new("Frame")
		metric.BackgroundColor3 = C.Raised
		metric.BorderSizePixel = 0
		metric.Size = UDim2.new(0.25, -6, 1, 0)
		metric.LayoutOrder = index
		metric.Parent = metrics
		corner(metric, 9)
		local accent = Instance.new("Frame")
		accent.BackgroundColor3 = definition[2]
		accent.BorderSizePixel = 0
		accent.Size = UDim2.fromOffset(3, 26)
		accent.Position = UDim2.fromOffset(10, 11)
		accent.Parent = metric
		local metricTitle = label(metric, definition[1], 8, true)
		metricTitle.Position = UDim2.fromOffset(20, 7)
		metricTitle.Size = UDim2.new(1, -28, 0, 14)
		metricTitle.TextColor3 = C.Muted
		local metricValue = label(metric, "0", 17, true)
		metricValue.Position = UDim2.fromOffset(20, 20)
		metricValue.Size = UDim2.new(1, -28, 0, 22)
		self.statLabels[index] = metricValue
	end

	local callsTitle = label(shell, "LIVE INCIDENT QUEUE", 10, true)
	callsTitle.Position = UDim2.fromOffset(20, 128)
	callsTitle.Size = UDim2.new(0.58, -30, 0, 18)
	local calls = Instance.new("ScrollingFrame")
	calls.BackgroundTransparency = 1
	calls.BorderSizePixel = 0
	calls.Position = UDim2.fromOffset(20, 152)
	calls.Size = UDim2.new(0.58, -30, 1, -232)
	calls.AutomaticCanvasSize = Enum.AutomaticSize.Y
	calls.CanvasSize = UDim2.new()
	calls.ScrollBarThickness = 6
	calls.Parent = shell
	local callsLayout = Instance.new("UIListLayout")
	callsLayout.Padding = UDim.new(0, 8)
	callsLayout.Parent = calls
	self.calls = calls

	local unitsTitle = label(shell, "MULTI-AGENCY UNIT BOARD", 10, true)
	unitsTitle.Position = UDim2.new(0.58, 0, 0, 128)
	unitsTitle.Size = UDim2.new(0.42, -20, 0, 18)
	local units = Instance.new("ScrollingFrame")
	units.BackgroundTransparency = 1
	units.BorderSizePixel = 0
	units.Position = UDim2.new(0.58, 0, 0, 152)
	units.Size = UDim2.new(0.42, -20, 1, -226)
	units.AutomaticCanvasSize = Enum.AutomaticSize.Y
	units.CanvasSize = UDim2.new()
	units.ScrollBarThickness = 6
	units.Parent = shell
	local unitsLayout = Instance.new("UIListLayout")
	unitsLayout.Padding = UDim.new(0, 8)
	unitsLayout.Parent = units
	self.units = units
	self.callsTitle = callsTitle
	self.unitsTitle = unitsTitle

	local newCall = button(shell, "＋  NEW CONTROL CALL")
	newCall.Position = UDim2.new(0, 20, 1, -64)
	newCall.Size = UDim2.new(0.58, -30, 0, 44)
	newCall.BackgroundColor3 = C.Accent

	local actions = Instance.new("Frame")
	actions.Position = UDim2.new(0.58, 0, 1, -64)
	actions.Size = UDim2.new(0.42, -20, 0, 44)
	actions.BackgroundTransparency = 1
	actions.Parent = shell
	local onScene = button(actions, "MARK ON SCENE")
	onScene.Size = UDim2.new(0.5, -5, 1, 0)
	local resolve = button(actions, "RESOLVE CALL")
	resolve.Position = UDim2.new(0.5, 5, 0, 0)
	resolve.Size = UDim2.new(0.5, -5, 1, 0)
	resolve.BackgroundColor3 = Color3.fromRGB(124, 51, 58)

	local shade = Instance.new("Frame")
	shade.Name = "CallComposerShade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new()
	shade.BackgroundTransparency = 0.18
	shade.BorderSizePixel = 0
	shade.Visible = false
	shade.ZIndex = 20
	shade.Parent = dim
	self.composer = shade
	local composer = Instance.new("Frame")
	composer.Name = "CallComposer"
	composer.AnchorPoint = Vector2.new(0.5, 0.5)
	composer.Position = UDim2.fromScale(0.5, 0.5)
	composer.Size = UDim2.fromOffset(560, 560)
	composer.BackgroundColor3 = C.Surface
	composer.BorderSizePixel = 0
	composer.ZIndex = 21
	composer.Parent = shade
	corner(composer, 16)
	-- The composer hangs off the full-screen shade rather than off the board, so
	-- the board's own UIScale never reached it and it drew at its authored 560 by
	-- 560. On a landscape phone that is taller than the screen: centred, its
	-- CANCEL and CREATE buttons sat about 120 pixels below the bottom edge and
	-- were clipped away entirely, while the shade swallowed every press behind
	-- it. Control could open a call and then neither send it nor escape.
	self.composerScale = Instance.new("UIScale")
	self.composerScale.Parent = composer
	self.composerDesign = Vector2.new(560, 560)
	local composerStroke = Instance.new("UIStroke")
	composerStroke.Color = C.Border
	composerStroke.Parent = composer
	local composerTitle = label(composer, "CREATE CONTROL CALL", 18, true)
	composerTitle.Position = UDim2.fromOffset(22, 18)
	composerTitle.Size = UDim2.new(1, -44, 0, 28)
	composerTitle.ZIndex = 22
	local composerCopy = label(
		composer,
		"Record verified information, alert active units, then deploy resources.",
		10
	)
	composerCopy.Position = UDim2.fromOffset(22, 47)
	composerCopy.Size = UDim2.new(1, -44, 0, 20)
	composerCopy.TextColor3 = C.Muted
	composerCopy.ZIndex = 22
	local summary = input(composer, "Summary · what is happening?")
	summary.Position = UDim2.fromOffset(22, 82)
	summary.Size = UDim2.new(1, -44, 0, 44)
	summary.ZIndex = 22
	local location = input(composer, "Exact location")
	location.Position = UDim2.fromOffset(22, 136)
	location.Size = UDim2.new(1, -44, 0, 44)
	location.ZIndex = 22
	local caller = input(composer, "Caller name (optional)")
	caller.Position = UDim2.fromOffset(22, 190)
	caller.Size = UDim2.new(0.58, -6, 0, 42)
	caller.ZIndex = 22
	local callerNumber = input(composer, "Callback number")
	callerNumber.Position = UDim2.new(0.58, 6, 0, 190)
	callerNumber.Size = UDim2.new(0.42, -28, 0, 42)
	callerNumber.ZIndex = 22
	local incidentType = button(composer, "TYPE  ·  EMERGENCY")
	incidentType.Position = UDim2.fromOffset(22, 244)
	incidentType.Size = UDim2.new(0.62, -6, 0, 38)
	incidentType.ZIndex = 22
	local priority = button(composer, "PRIORITY  ·  PROMPT")
	priority.Position = UDim2.new(0.62, 6, 0, 244)
	priority.Size = UDim2.new(0.38, -28, 0, 38)
	priority.ZIndex = 22
	local recipientTitle = label(composer, "SEND TO DEPARTMENTS", 9, true)
	recipientTitle.Position = UDim2.fromOffset(22, 296)
	recipientTitle.Size = UDim2.new(1, -44, 0, 18)
	recipientTitle.TextColor3 = C.Muted
	recipientTitle.ZIndex = 22
	local departmentIds =
		{ "Police", "Ambulance", "Fire", "Highways", "Prison", "Transport", "Control" }
	local selectedDepartments = { Control = true }
	for index, departmentId in departmentIds do
		local department = button(composer, departmentId:upper())
		department.Position = UDim2.new(
			(index - 1) % 4 * 0.25,
			22 + ((index - 1) % 4) * 2,
			0,
			319 + math.floor((index - 1) / 4) * 37
		)
		department.Size = UDim2.new(0.25, -28, 0, 30)
		department.ZIndex = 22
		local function renderDepartment()
			department.BackgroundColor3 = if selectedDepartments[departmentId]
				then C.Accent
				else C.Raised
		end
		renderDepartment()
		department.Activated:Connect(function()
			selectedDepartments[departmentId] = if selectedDepartments[departmentId]
				then nil
				else true
			renderDepartment()
		end)
	end
	local notes = input(composer, "Control notes (optional)")
	notes.Position = UDim2.fromOffset(22, 397)
	notes.Size = UDim2.new(1, -44, 0, 72)
	notes.MultiLine = true
	notes.TextYAlignment = Enum.TextYAlignment.Top
	notes.ZIndex = 22
	local cancel = button(composer, "CANCEL")
	cancel.Position = UDim2.fromOffset(22, 492)
	cancel.Size = UDim2.new(0.35, -6, 0, 46)
	cancel.ZIndex = 22
	local createButton = button(composer, "CREATE & BROADCAST CALL")
	createButton.Position = UDim2.new(0.35, 6, 0, 492)
	createButton.Size = UDim2.new(0.65, -28, 0, 46)
	createButton.BackgroundColor3 = C.Accent
	createButton.ZIndex = 22
	self.priority = "Prompt"
	self.incidentType = "Emergency"
	local incidentTypes = {
		"Emergency",
		"Crime in progress",
		"Road traffic collision",
		"Medical",
		"Fire",
		"Public assistance",
		"Prison incident",
		"Transport incident",
	}
	incidentType.Activated:Connect(function()
		local index = table.find(incidentTypes, self.incidentType) or 1
		self.incidentType = incidentTypes[index % #incidentTypes + 1]
		incidentType.Text = "TYPE  ·  " .. string.upper(self.incidentType)
	end)
	priority.Activated:Connect(function()
		local order = { "Prompt", "Routine", "Immediate" }
		local index = table.find(order, self.priority) or 1
		self.priority = order[index % #order + 1]
		priority.Text = "PRIORITY  ·  " .. string.upper(self.priority)
		priority.BackgroundColor3 = if self.priority == "Immediate" then C.Immediate else C.Raised
	end)
	newCall.Activated:Connect(function()
		shade.Visible = true
	end)
	cancel.Activated:Connect(function()
		shade.Visible = false
	end)
	createButton.Activated:Connect(function()
		local departments = {}
		for departmentId in selectedDepartments do
			table.insert(departments, departmentId)
		end
		local response = self.context.Controllers.NetworkController:Request("DispatchCreateCall", {
			Summary = summary.Text,
			Location = location.Text,
			CallerName = caller.Text,
			CallerNumber = callerNumber.Text,
			Notes = notes.Text,
			IncidentType = self.incidentType,
			Priority = self.priority,
			DepartmentIds = departments,
		})
		self.context.Controllers.NotificationController:Show(
			response.Message,
			response.Success and "Dispatch" or "Dispatch unavailable"
		)
		if response.Success then
			for _, field in { summary, location, caller, callerNumber, notes } do
				field.Text = ""
			end
			shade.Visible = false
			self:Refresh()
		end
	end)
	onScene.Activated:Connect(function()
		if not self.selectedCallId then
			return
		end
		self.context.Controllers.NetworkController:Request(
			"DispatchUpdateCall",
			{ CallId = self.selectedCallId, Status = "OnScene" }
		)
		self:Refresh()
	end)
	resolve.Activated:Connect(function()
		if not self.selectedCallId then
			return
		end
		local response = self.context.Controllers.NetworkController:Request(
			"DispatchCloseCall",
			{ CallId = self.selectedCallId }
		)
		if response.Success then
			self.selectedCallId = nil
			self:Refresh()
		end
	end)
end

function DispatchController:_clear(container: ScrollingFrame)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

function DispatchController:_renderCalls(calls: { any })
	self:_clear(self.calls)
	self.callsTitle.Text = string.format("ACTIVE CALLS  ·  %d", #calls)
	if #calls == 0 then
		local empty = label(self.calls, "No active incidents in the queue", 11, true)
		empty.Size = UDim2.new(1, -5, 0, 44)
		empty.TextColor3 = C.Muted
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end
	for _, call in calls do
		local row = button(self.calls, "")
		row.Size = UDim2.new(1, -5, 0, 94)
		row.BackgroundColor3 = if call.CallId == self.selectedCallId
			then Color3.fromRGB(29, 53, 82)
			else C.Raised
		local priority = label(row, string.upper(call.Priority), 9, true)
		priority.Position = UDim2.fromOffset(12, 8)
		priority.Size = UDim2.fromOffset(100, 16)
		priority.TextColor3 = if call.Priority == "Immediate" then C.Immediate else C.Accent
		local status = label(row, tostring(call.Status):upper(), 9, true)
		status.AnchorPoint = Vector2.new(1, 0)
		status.Position = UDim2.new(1, -12, 0, 8)
		status.Size = UDim2.fromOffset(100, 16)
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.TextColor3 = C.Muted
		local summary = label(row, tostring(call.Summary), 12, true)
		summary.Position = UDim2.fromOffset(12, 28)
		summary.Size = UDim2.new(1, -24, 0, 18)
		-- Typed by whoever raised the call, so its length is whatever they felt
		-- like. Without this it spilled out of the queue column and over the unit
		-- board beside it, the row having nothing to clip it.
		summary.TextTruncate = Enum.TextTruncate.AtEnd
		local meta = label(
			row,
			string.format("%s  ·  %s", tostring(call.IncidentType), tostring(call.Location)),
			9
		)
		meta.Position = UDim2.fromOffset(12, 50)
		meta.Size = UDim2.new(1, -24, 0, 15)
		meta.TextColor3 = C.Muted
		local recipients = table.concat(call.DepartmentIds or {}, " · ")
		local detail = label(
			row,
			string.format(
				"%s  ·  %d unit%s  ·  Caller: %s",
				recipients,
				#call.UnitIds,
				if #call.UnitIds == 1 then "" else "s",
				tostring(call.CallerName or "Unknown")
			),
			8
		)
		detail.Position = UDim2.fromOffset(12, 70)
		detail.Size = UDim2.new(1, -24, 0, 14)
		detail.TextColor3 = C.Muted
		row.Activated:Connect(function()
			self.selectedCallId = call.CallId
			self:_renderCalls(calls)
		end)
	end
end

function DispatchController:_renderUnits(units: { any })
	self:_clear(self.units)
	self.unitsTitle.Text = string.format("OPERATIONAL UNITS  ·  %d", #units)
	if #units == 0 then
		local empty = label(self.units, "No units currently online", 11, true)
		empty.Size = UDim2.new(1, -5, 0, 44)
		empty.TextColor3 = C.Muted
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end
	for _, unit in units do
		local row = button(self.units, "")
		row.Size = UDim2.new(1, -5, 0, 58)
		local callsign = label(row, unit.Callsign, 12, true)
		callsign.Position = UDim2.fromOffset(12, 8)
		callsign.Size = UDim2.new(1, -24, 0, 18)
		local state = label(row, unit.DepartmentId .. "  ·  " .. unit.Status, 9)
		state.Position = UDim2.fromOffset(12, 30)
		state.Size = UDim2.new(1, -24, 0, 16)
		state.TextColor3 = C.Muted
		row.Activated:Connect(function()
			if not self.selectedCallId then
				self.context.Controllers.NotificationController:Show(
					"Select a call first.",
					"Dispatch"
				)
				return
			end
			local response =
				self.context.Controllers.NetworkController:Request("DispatchAssignUnit", {
					CallId = self.selectedCallId,
					UnitId = unit.UnitId,
				})
			self.context.Controllers.NotificationController:Show(response.Message, "Dispatch")
			if response.Success then
				self:Refresh()
			end
		end)
	end
end

function DispatchController:Refresh()
	local response = self.context.Controllers.NetworkController:Request("GetDispatchSnapshot", {})
	if response.Success then
		local calls = response.Data.Calls or {}
		local units = response.Data.Units or {}
		local immediate = 0
		local onScene = 0
		for _, call in calls do
			if call.Priority == "Immediate" then
				immediate += 1
			end
			if call.Status == "OnScene" then
				onScene += 1
			end
		end
		if self.statLabels then
			self.statLabels[1].Text = tostring(#calls)
			self.statLabels[2].Text = tostring(immediate)
			self.statLabels[3].Text = tostring(onScene)
			self.statLabels[4].Text = tostring(#units)
		end
		self:_renderCalls(calls)
		self:_renderUnits(units)
	end
end

function DispatchController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self:_mount()
	table.insert(
		self.connections,
		playerGui:GetAttributeChangedSignal("RoleplayOSCCTVOpen"):Connect(function()
			if playerGui:GetAttribute("RoleplayOSCCTVOpen") == true then
				self.gui.Enabled = false
			end
		end)
	)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Dispatch", function(layout)
		-- The console has a minimum size, so it is scaled against the usable area
		-- on every device class rather than only when compact; the raw viewport
		-- ignored the top bar and device cutouts and clipped the console edges.
		self.scale.Scale =
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(760, 500), 24)
		-- Fitted separately, because it is not a child of the console.
		if self.composerScale then
			self.composerScale.Scale =
				self.context.Controllers.UIOrchestrator:FitScale(layout, self.composerDesign, 24)
		end
	end)
	local function watchCharacter(character: Model)
		for _, connection in self.characterConnections do
			connection:Disconnect()
		end
		table.clear(self.characterConnections)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		table.insert(
			self.characterConnections,
			humanoid.Seated:Connect(function(active)
				if not active then
					self.gui.Enabled = false
					playerGui:SetAttribute("RoleplayOSDispatchOpen", false)
				end
			end)
		)
		table.insert(
			self.characterConnections,
			humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
				if humanoid.SeatPart == nil then
					self.gui.Enabled = false
					playerGui:SetAttribute("RoleplayOSDispatchOpen", false)
				end
			end)
		)
	end
	if Players.LocalPlayer.Character then
		watchCharacter(Players.LocalPlayer.Character)
	end
	table.insert(self.connections, Players.LocalPlayer.CharacterAdded:Connect(watchCharacter))
	-- Only the automatic refresh is coalesced. Opening the board and being
	-- granted console access still redraw immediately, because those are the
	-- player asking rather than the server telling.
	self.refresh = Coalescer.new(BOARD_REFRESH_INTERVAL, function()
		self:Refresh()
	end)
	local network = self.context.Controllers.NetworkController
	local changed = network:ResolveEvent("DispatchChanged")
	if changed then
		table.insert(
			self.connections,
			changed.OnClientEvent:Connect(function(update)
				self.context.Events.DispatchChanged:Fire(update)
				if self.gui.Enabled then
					self.refresh:Request()
				end
			end)
		)
	end
	local consoleAccess = network:ResolveEvent("DispatchConsoleAccess")
	if consoleAccess then
		table.insert(
			self.connections,
			consoleAccess.OnClientEvent:Connect(function(data)
				self.gui.Enabled = data.Allowed == true
				playerGui:SetAttribute("RoleplayOSDispatchOpen", self.gui.Enabled)
				if self.gui.Enabled then
					self:Refresh()
				end
			end)
		)
	end
end

function DispatchController:Destroy()
	if self.refresh then
		self.refresh:Cancel()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, connection in self.characterConnections do
		connection:Disconnect()
	end
	table.clear(self.characterConnections)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return DispatchController
