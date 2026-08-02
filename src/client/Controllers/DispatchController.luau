--!strict

local Players = game:GetService("Players")

local DispatchController = { connections = {}, selectedCallId = nil }
local C = {
	Surface = Color3.fromRGB(10, 15, 24),
	Raised = Color3.fromRGB(20, 28, 41),
	Border = Color3.fromRGB(49, 64, 86),
	Text = Color3.fromRGB(244, 247, 252),
	Muted = Color3.fromRGB(148, 162, 183),
	Accent = Color3.fromRGB(64, 145, 255),
	Immediate = Color3.fromRGB(244, 82, 92),
}

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
	corner(shell, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(760, 500)
	constraint.MaxSize = Vector2.new(1180, 720)
	constraint.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Transparency = 0.1
	stroke.Parent = shell

	local title = label(shell, "EMERGENCY CONTROL", 17, true)
	title.Position = UDim2.fromOffset(20, 13)
	title.Size = UDim2.new(1, -40, 0, 24)
	local live = label(shell, "●  LIVE DISPATCH  ·  CONSOLE AUTHENTICATED", 9, true)
	live.Position = UDim2.fromOffset(20, 38)
	live.Size = UDim2.new(1, -40, 0, 18)
	live.TextColor3 = Color3.fromRGB(92, 216, 145)
	local close = button(shell, "CLOSE")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -20, 0, 18)
	close.Size = UDim2.fromOffset(70, 30)
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	local callsTitle = label(shell, "ACTIVE CALLS", 10, true)
	callsTitle.Position = UDim2.fromOffset(20, 72)
	callsTitle.Size = UDim2.new(0.58, -30, 0, 18)
	local calls = Instance.new("ScrollingFrame")
	calls.BackgroundTransparency = 1
	calls.BorderSizePixel = 0
	calls.Position = UDim2.fromOffset(20, 96)
	calls.Size = UDim2.new(0.58, -30, 1, -204)
	calls.AutomaticCanvasSize = Enum.AutomaticSize.Y
	calls.CanvasSize = UDim2.new()
	calls.ScrollBarThickness = 3
	calls.Parent = shell
	local callsLayout = Instance.new("UIListLayout")
	callsLayout.Padding = UDim.new(0, 8)
	callsLayout.Parent = calls
	self.calls = calls

	local unitsTitle = label(shell, "AVAILABLE UNITS", 10, true)
	unitsTitle.Position = UDim2.new(0.58, 0, 0, 72)
	unitsTitle.Size = UDim2.new(0.42, -20, 0, 18)
	local units = Instance.new("ScrollingFrame")
	units.BackgroundTransparency = 1
	units.BorderSizePixel = 0
	units.Position = UDim2.new(0.58, 0, 0, 96)
	units.Size = UDim2.new(0.42, -20, 1, -116)
	units.AutomaticCanvasSize = Enum.AutomaticSize.Y
	units.CanvasSize = UDim2.new()
	units.ScrollBarThickness = 3
	units.Parent = shell
	local unitsLayout = Instance.new("UIListLayout")
	unitsLayout.Padding = UDim.new(0, 8)
	unitsLayout.Parent = units
	self.units = units

	local create = Instance.new("Frame")
	create.Position = UDim2.new(0, 20, 1, -96)
	create.Size = UDim2.new(0.58, -30, 0, 76)
	create.BackgroundColor3 = C.Raised
	create.BorderSizePixel = 0
	create.Parent = shell
	corner(create, 10)
	local summary = input(create, "Call summary")
	summary.Position = UDim2.fromOffset(10, 9)
	summary.Size = UDim2.new(0.5, -14, 0, 29)
	local location = input(create, "Location")
	location.Position = UDim2.new(0.5, 4, 0, 9)
	location.Size = UDim2.new(0.32, -8, 0, 29)
	local createButton = button(create, "CREATE")
	createButton.Position = UDim2.new(0.82, 4, 0, 9)
	createButton.Size = UDim2.new(0.18, -14, 0, 29)
	createButton.BackgroundColor3 = C.Accent
	local priority = button(create, "PROMPT")
	priority.Position = UDim2.fromOffset(10, 43)
	priority.Size = UDim2.fromOffset(92, 24)
	local hint = label(create, "Select a call, then select a unit to attach it.", 9)
	hint.Position = UDim2.fromOffset(112, 44)
	hint.Size = UDim2.new(1, -122, 0, 20)
	hint.TextColor3 = C.Muted
	self.summaryInput = summary
	self.locationInput = location
	self.priorityButton = priority
	self.priority = "Prompt"

	priority.Activated:Connect(function()
		local order = { "Prompt", "Routine", "Immediate" }
		local index = table.find(order, self.priority) or 1
		self.priority = order[index % #order + 1]
		priority.Text = string.upper(self.priority)
		priority.BackgroundColor3 = if self.priority == "Immediate" then C.Immediate else C.Raised
	end)
	createButton.Activated:Connect(function()
		local response = self.context.Controllers.NetworkController:Request("DispatchCreateCall", {
			Summary = summary.Text,
			Location = location.Text,
			Priority = self.priority,
		})
		self.context.Controllers.NotificationController:Show(
			response.Message,
			response.Success and "Dispatch" or "Dispatch unavailable"
		)
		if response.Success then
			summary.Text = ""
			location.Text = ""
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
	for _, call in calls do
		local row = button(self.calls, "")
		row.Size = UDim2.new(1, -5, 0, 72)
		row.BackgroundColor3 = if call.CallId == self.selectedCallId
			then Color3.fromRGB(29, 53, 82)
			else C.Raised
		local priority = label(row, string.upper(call.Priority), 9, true)
		priority.Position = UDim2.fromOffset(12, 8)
		priority.Size = UDim2.fromOffset(90, 16)
		priority.TextColor3 = if call.Priority == "Immediate" then C.Immediate else C.Accent
		local summary = label(row, call.Summary, 12, true)
		summary.Position = UDim2.fromOffset(12, 27)
		summary.Size = UDim2.new(1, -24, 0, 18)
		local meta = label(
			row,
			string.format(
				"%s  ·  %d unit%s",
				call.Location,
				#call.UnitIds,
				if #call.UnitIds == 1 then "" else "s"
			),
			9
		)
		meta.Position = UDim2.fromOffset(12, 48)
		meta.Size = UDim2.new(1, -24, 0, 16)
		meta.TextColor3 = C.Muted
		row.Activated:Connect(function()
			self.selectedCallId = call.CallId
			self:_renderCalls(calls)
		end)
	end
end

function DispatchController:_renderUnits(units: { any })
	self:_clear(self.units)
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
		self:_renderCalls(response.Data.Calls)
		self:_renderUnits(response.Data.Units)
	end
end

function DispatchController:Start()
	self:_mount()
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
				end
			end)
		)
		table.insert(
			self.characterConnections,
			humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
				if humanoid.SeatPart == nil then
					self.gui.Enabled = false
				end
			end)
		)
	end
	if Players.LocalPlayer.Character then
		watchCharacter(Players.LocalPlayer.Character)
	end
	table.insert(self.connections, Players.LocalPlayer.CharacterAdded:Connect(watchCharacter))
	local remotes = self.context.Controllers.NetworkController.remotes
	table.insert(
		self.connections,
		remotes:WaitForChild("DispatchChanged").OnClientEvent:Connect(function(update)
			self.context.Events.DispatchChanged:Fire(update)
			if self.gui.Enabled then
				self:Refresh()
			end
		end)
	)
	table.insert(
		self.connections,
		remotes:WaitForChild("DispatchConsoleAccess").OnClientEvent:Connect(function(data)
			self.gui.Enabled = data.Allowed == true
			if self.gui.Enabled then
				self:Refresh()
			end
		end)
	)
end

function DispatchController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, connection in self.characterConnections do
		connection:Disconnect()
	end
	table.clear(self.characterConnections)
	if self.gui then
		self.gui:Destroy()
	end
end

return DispatchController
