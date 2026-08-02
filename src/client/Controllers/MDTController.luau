--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MDTController = { connections = {} }
local C = {
	Surface = Color3.fromRGB(12, 18, 28),
	Raised = Color3.fromRGB(22, 30, 43),
	Border = Color3.fromRGB(52, 66, 88),
	Text = Color3.fromRGB(244, 247, 252),
	Muted = Color3.fromRGB(151, 163, 184),
	Accent = Color3.fromRGB(91, 156, 255),
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function text(parent: Instance, value: string, size: number, bold: boolean?): TextLabel
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
	item.TextSize = 11
	item.Parent = parent
	corner(item, 8)
	return item
end

function MDTController:Init(context: any)
	self.context = context
	self.recordType = "Person"
	self.allowed = false
	self.canWriteWarrants = false
	self.selectedRecord = nil
end

function MDTController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSMDT"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local launcher = button(gui, "MDT  ·  M")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(0, 0.5)
	launcher.Position = UDim2.new(0, 18, 0.62, 0)
	launcher.Size = UDim2.fromOffset(96, 38)
	launcher.Visible = false
	self.launcher = launcher

	local shell = Instance.new("Frame")
	shell.Name = "Terminal"
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromScale(0.86, 0.82)
	shell.BackgroundColor3 = C.Surface
	shell.BorderSizePixel = 0
	shell.Visible = false
	shell.Parent = gui
	corner(shell, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(720, 470)
	constraint.MaxSize = Vector2.new(1120, 720)
	constraint.Parent = shell
	self.constraint = constraint
	local scale = Instance.new("UIScale")
	scale.Parent = shell
	self.scale = scale
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Border
	stroke.Transparency = 0.15
	stroke.Parent = shell
	self.shell = shell

	local title = text(shell, "ROLEPLAYOS  ·  MOBILE DATA TERMINAL", 16, true)
	title.Position = UDim2.fromOffset(22, 15)
	title.Size = UDim2.new(1, -110, 0, 24)
	local subtitle = text(shell, "Secure operational records", 10)
	subtitle.Position = UDim2.fromOffset(22, 39)
	subtitle.Size = UDim2.new(1, -110, 0, 18)
	subtitle.TextColor3 = C.Muted
	local secure = text(shell, "●  SECURE SESSION", 9, true)
	secure.AnchorPoint = Vector2.new(1, 0)
	secure.Position = UDim2.new(1, -104, 0, 42)
	secure.Size = UDim2.fromOffset(150, 16)
	secure.TextXAlignment = Enum.TextXAlignment.Right
	secure.TextColor3 = Color3.fromRGB(89, 215, 144)
	self.secureLabel = secure
	local close = button(shell, "CLOSE")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 15)
	close.Size = UDim2.fromOffset(72, 30)

	local person = button(shell, "PEOPLE")
	person.Position = UDim2.fromOffset(22, 73)
	person.Size = UDim2.fromOffset(92, 34)
	local vehicle = button(shell, "VEHICLES")
	vehicle.Position = UDim2.fromOffset(122, 73)
	vehicle.Size = UDim2.fromOffset(92, 34)
	self.personTab = person
	self.vehicleTab = vehicle

	local input = Instance.new("TextBox")
	input.BackgroundColor3 = C.Raised
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Search name or registration"
	input.PlaceholderColor3 = C.Muted
	input.Text = ""
	input.TextColor3 = C.Text
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Position = UDim2.fromOffset(22, 119)
	input.Size = UDim2.new(0.62, -34, 0, 42)
	input.Parent = shell
	corner(input, 9)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.Parent = input
	self.input = input
	local search = button(shell, "SEARCH")
	search.AnchorPoint = Vector2.new(1, 0)
	search.Position = UDim2.new(0.62, -22, 0, 119)
	search.Size = UDim2.fromOffset(86, 42)
	search.BackgroundColor3 = C.Accent

	local status = text(shell, "Enter at least two characters.", 11)
	status.Position = UDim2.fromOffset(22, 170)
	status.Size = UDim2.new(0.62, -44, 0, 20)
	status.TextColor3 = C.Muted
	self.status = status
	local results = Instance.new("ScrollingFrame")
	results.BackgroundTransparency = 1
	results.BorderSizePixel = 0
	results.Position = UDim2.fromOffset(22, 200)
	results.Size = UDim2.new(0.62, -34, 1, -222)
	results.AutomaticCanvasSize = Enum.AutomaticSize.Y
	results.CanvasSize = UDim2.new()
	results.ScrollBarThickness = 3
	results.Parent = shell
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = results
	self.results = results

	local detail = Instance.new("Frame")
	detail.Position = UDim2.new(0.62, 0, 0, 73)
	detail.Size = UDim2.new(0.38, -22, 1, -95)
	detail.BackgroundColor3 = C.Raised
	detail.BorderSizePixel = 0
	detail.Parent = shell
	corner(detail, 11)
	local detailTitle = text(detail, "RECORD PREVIEW", 11, true)
	detailTitle.Position = UDim2.fromOffset(16, 14)
	detailTitle.Size = UDim2.new(1, -32, 0, 20)
	detailTitle.TextColor3 = C.Accent
	local detailName = text(detail, "Select a search result", 18, true)
	detailName.Position = UDim2.fromOffset(16, 45)
	detailName.Size = UDim2.new(1, -32, 0, 48)
	detailName.TextWrapped = true
	local detailMeta = text(detail, "Verified operational information will appear here.", 11)
	detailMeta.Position = UDim2.fromOffset(16, 104)
	detailMeta.Size = UDim2.new(1, -32, 1, -174)
	detailMeta.TextWrapped = true
	detailMeta.TextYAlignment = Enum.TextYAlignment.Top
	detailMeta.TextColor3 = C.Muted
	self.detailTitle = detailTitle
	self.detailName = detailName
	self.detailMeta = detailMeta
	local warrantAction = button(detail, "ISSUE WARRANT")
	warrantAction.AnchorPoint = Vector2.new(0, 1)
	warrantAction.Position = UDim2.new(0, 16, 1, -16)
	warrantAction.Size = UDim2.new(0.5, -20, 0, 40)
	warrantAction.BackgroundColor3 = C.Accent
	warrantAction.Visible = false
	self.warrantAction = warrantAction
	local revokeAction = button(detail, "REVOKE WARRANT")
	revokeAction.AnchorPoint = Vector2.new(1, 1)
	revokeAction.Position = UDim2.new(1, -16, 1, -16)
	revokeAction.Size = UDim2.new(0.5, -20, 0, 40)
	revokeAction.BackgroundColor3 = Color3.fromRGB(148, 55, 65)
	revokeAction.Visible = false
	self.revokeAction = revokeAction

	local warrantModal = Instance.new("Frame")
	warrantModal.Name = "WarrantModal"
	warrantModal.AnchorPoint = Vector2.new(0.5, 0.5)
	warrantModal.Position = UDim2.fromScale(0.5, 0.5)
	warrantModal.Size = UDim2.fromOffset(440, 286)
	warrantModal.BackgroundColor3 = C.Surface
	warrantModal.BorderSizePixel = 0
	warrantModal.Visible = false
	warrantModal.ZIndex = 20
	warrantModal.Parent = shell
	corner(warrantModal, 12)
	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = C.Border
	modalStroke.Parent = warrantModal
	local modalTitle = text(warrantModal, "ISSUE WARRANT", 15, true)
	modalTitle.Position = UDim2.fromOffset(20, 17)
	modalTitle.Size = UDim2.new(1, -40, 0, 24)
	modalTitle.ZIndex = 21
	local modalCopy =
		text(warrantModal, "The reason is filtered and the action is written to the audit log.", 10)
	modalCopy.Position = UDim2.fromOffset(20, 43)
	modalCopy.Size = UDim2.new(1, -40, 0, 30)
	modalCopy.TextWrapped = true
	modalCopy.TextColor3 = C.Muted
	modalCopy.ZIndex = 21
	local reasonInput = Instance.new("TextBox")
	reasonInput.Position = UDim2.fromOffset(20, 82)
	reasonInput.Size = UDim2.new(1, -40, 0, 76)
	reasonInput.BackgroundColor3 = C.Raised
	reasonInput.BorderSizePixel = 0
	reasonInput.ClearTextOnFocus = false
	reasonInput.Font = Enum.Font.Gotham
	reasonInput.MultiLine = true
	reasonInput.PlaceholderText = "Operational reason"
	reasonInput.PlaceholderColor3 = C.Muted
	reasonInput.Text = ""
	reasonInput.TextColor3 = C.Text
	reasonInput.TextSize = 12
	reasonInput.TextWrapped = true
	reasonInput.TextXAlignment = Enum.TextXAlignment.Left
	reasonInput.TextYAlignment = Enum.TextYAlignment.Top
	reasonInput.ZIndex = 21
	reasonInput.Parent = warrantModal
	corner(reasonInput, 8)
	local reasonPadding = Instance.new("UIPadding")
	reasonPadding.PaddingTop = UDim.new(0, 10)
	reasonPadding.PaddingLeft = UDim.new(0, 10)
	reasonPadding.PaddingRight = UDim.new(0, 10)
	reasonPadding.Parent = reasonInput
	local expiryInput = Instance.new("TextBox")
	expiryInput.Position = UDim2.fromOffset(20, 168)
	expiryInput.Size = UDim2.new(1, -40, 0, 38)
	expiryInput.BackgroundColor3 = C.Raised
	expiryInput.BorderSizePixel = 0
	expiryInput.ClearTextOnFocus = false
	expiryInput.Font = Enum.Font.Gotham
	expiryInput.PlaceholderText = "Expiry in days (blank for no expiry)"
	expiryInput.PlaceholderColor3 = C.Muted
	expiryInput.Text = ""
	expiryInput.TextColor3 = C.Text
	expiryInput.TextSize = 11
	expiryInput.ZIndex = 21
	expiryInput.Parent = warrantModal
	corner(expiryInput, 8)
	local cancelWarrant = button(warrantModal, "CANCEL")
	cancelWarrant.Position = UDim2.fromOffset(20, 224)
	cancelWarrant.Size = UDim2.fromOffset(110, 42)
	cancelWarrant.ZIndex = 21
	local confirmWarrant = button(warrantModal, "ISSUE WARRANT")
	confirmWarrant.AnchorPoint = Vector2.new(1, 0)
	confirmWarrant.Position = UDim2.new(1, -20, 0, 224)
	confirmWarrant.Size = UDim2.fromOffset(150, 42)
	confirmWarrant.BackgroundColor3 = C.Accent
	confirmWarrant.ZIndex = 21
	self.warrantModal = warrantModal
	self.warrantReason = reasonInput
	self.warrantExpiry = expiryInput

	local function setOpen(open: boolean)
		if self.allowed then
			shell.Visible = open
		end
	end
	launcher.Activated:Connect(function()
		setOpen(not shell.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	warrantAction.Activated:Connect(function()
		if self.canWriteWarrants and self.selectedRecord then
			warrantModal.Visible = true
			reasonInput:CaptureFocus()
		end
	end)
	revokeAction.Activated:Connect(function()
		self:_revokeWarrant()
	end)
	cancelWarrant.Activated:Connect(function()
		warrantModal.Visible = false
	end)
	confirmWarrant.Activated:Connect(function()
		self:_issueWarrant()
	end)
	person.Activated:Connect(function()
		self.recordType = "Person"
		self:_renderTabs()
	end)
	vehicle.Activated:Connect(function()
		self.recordType = "Vehicle"
		self:_renderTabs()
	end)
	search.Activated:Connect(function()
		self:_performSearch()
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_performSearch()
		end
	end)
	self:_renderTabs()
end

function MDTController:_renderTabs()
	self.personTab.BackgroundColor3 = if self.recordType == "Person" then C.Accent else C.Raised
	self.vehicleTab.BackgroundColor3 = if self.recordType == "Vehicle" then C.Accent else C.Raised
end

function MDTController:_renderResults(items: { any })
	self.selectedRecord = nil
	self.warrantAction.Visible = false
	self.revokeAction.Visible = false
	for _, child in self.results:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if #items == 0 then
		self.detailName.Text = "No matching records"
		self.detailMeta.Text =
			"Check the spelling or try a broader search. Searches require at least two characters."
	end
	for _, record in items do
		local row = button(self.results, "")
		row.BackgroundColor3 = C.Raised
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -5, 0, 62)
		row.Parent = self.results
		corner(row, 9)
		local primary =
			text(row, record.FullName or record.Registration or "Unknown record", 13, true)
		primary.Position = UDim2.fromOffset(14, 10)
		primary.Size = UDim2.new(1, -28, 0, 20)
		local secondary = text(
			row,
			record.DateOfBirth and ("Date of birth  ·  " .. record.DateOfBirth)
				or ("Vehicle  ·  " .. tostring(record.DefinitionId or "Unknown")),
			10
		)
		secondary.Position = UDim2.fromOffset(14, 33)
		secondary.Size = UDim2.new(1, -28, 0, 18)
		secondary.TextColor3 = C.Muted
		local open = text(row, "VIEW  ›", 9, true)
		open.AnchorPoint = Vector2.new(1, 0.5)
		open.Position = UDim2.new(1, -14, 0.5, 0)
		open.Size = UDim2.fromOffset(60, 18)
		open.TextXAlignment = Enum.TextXAlignment.Right
		open.TextColor3 = C.Accent
		row.Activated:Connect(function()
			self.selectedRecord = record
			self.warrantAction.Visible = record.FullName ~= nil and self.canWriteWarrants
			self.revokeAction.Visible = record.FullName ~= nil
				and self.canWriteWarrants
				and #(record.Warrants or {}) > 0
			self.revokeAction.Text = "REVOKE WARRANT"
			self.revokeConfirmationId = nil
			self.detailTitle.Text = if record.FullName then "PERSON RECORD" else "VEHICLE RECORD"
			self.detailName.Text = record.FullName or record.Registration or "Unknown record"
			if record.FullName then
				local licences = {}
				for licenceId, value in record.Licences or {} do
					if value then
						table.insert(licences, tostring(licenceId))
					end
				end
				local bookings = record.CustodyRecord and record.CustodyRecord.Bookings or {}
				local warrants = {}
				for _, warrant in record.Warrants or {} do
					table.insert(warrants, tostring(warrant.Reason or "Active warrant"))
				end
				self.detailMeta.Text = string.format(
					"DATE OF BIRTH\n%s\n\nLICENCES\n%s\n\nDRIVING POINTS · %d   CUSTODY BOOKINGS · %d\n\nFLAGS\n%s\n\nACTIVE WARRANTS\n%s",
					tostring(record.DateOfBirth or "Not recorded"),
					if #licences > 0 then table.concat(licences, ", ") else "None recorded",
					record.DrivingRecord and record.DrivingRecord.Points or 0,
					#bookings,
					if #(record.Flags or {}) > 0
						then table.concat(record.Flags, ", ")
						else "No active flags",
					if #warrants > 0 then table.concat(warrants, "\n") else "None"
				)
			else
				self.detailMeta.Text = string.format(
					"REGISTRATION\n%s\n\nVEHICLE TYPE\n%s\n\nOWNER RECORD\n%s\n\nFLAGS\n%s",
					tostring(record.Registration or "Unknown"),
					tostring(record.DefinitionId or "Unknown"),
					tostring(record.OwnerCharacterId or "Unavailable"),
					if #(record.Flags or {}) > 0
						then table.concat(record.Flags, ", ")
						else "No active flags"
				)
			end
		end)
	end
end

function MDTController:_issueWarrant()
	local record = self.selectedRecord
	if not record or not self.canWriteWarrants then
		return
	end
	local days = tonumber(self.warrantExpiry.Text)
	if self.warrantExpiry.Text ~= "" and (not days or days < 1 or days > 365) then
		self.status.Text = "Expiry must be between 1 and 365 days."
		return
	end
	local response = self.context.Controllers.NetworkController:Request("MDTCreateWarrant", {
		CharacterId = record.CharacterId,
		Reason = self.warrantReason.Text,
		ExpiresAt = days and (os.time() + math.floor(days) * 86400) or nil,
	})
	self.status.Text = response.Message
	if response.Success then
		self.warrantModal.Visible = false
		self.warrantReason.Text = ""
		self.warrantExpiry.Text = ""
		self:_performSearch()
	end
end

function MDTController:_revokeWarrant()
	local record = self.selectedRecord
	local warrant = record and (record.Warrants or {})[1]
	if not record or not warrant or not self.canWriteWarrants then
		return
	end
	if self.revokeConfirmationId ~= warrant.WarrantId then
		self.revokeConfirmationId = warrant.WarrantId
		self.revokeAction.Text = "CONFIRM REVOKE"
		task.delay(5, function()
			if self.revokeConfirmationId == warrant.WarrantId then
				self.revokeConfirmationId = nil
				self.revokeAction.Text = "REVOKE WARRANT"
			end
		end)
		return
	end
	self.revokeConfirmationId = nil
	local response = self.context.Controllers.NetworkController:Request("MDTRevokeWarrant", {
		CharacterId = record.CharacterId,
		WarrantId = warrant.WarrantId,
	})
	self.status.Text = response.Message
	if response.Success then
		self:_performSearch()
	end
end

function MDTController:_performSearch()
	self.status.Text = "Searching secure records…"
	local response = self:Search(self.recordType, self.input.Text, 1)
	if response.Success then
		local items = response.Data.Items or {}
		self.status.Text = string.format("%d result%s", #items, if #items == 1 then "" else "s")
		self:_renderResults(items)
	else
		self.status.Text = response.Message
	end
end

function MDTController:RefreshAccess()
	local response = self.context.Controllers.NetworkController:Request("GetMDTAccess", {})
	self.allowed = response.Success and response.Data.Allowed == true
	self.canWriteWarrants = self.allowed
		and table.find(response.Data.Permissions or {}, "WarrantWrite") ~= nil
	if self.allowed then
		self.secureLabel.Text = "●  "
			.. tostring(response.Data.DepartmentId or "AUTHORISED"):upper()
	end
	self.gui.Enabled = self.allowed
	self.launcher.Visible = self.allowed
	if not self.allowed then
		self.shell.Visible = false
	end
	if self.warrantAction then
		self.warrantAction.Visible = self.selectedRecord ~= nil and self.canWriteWarrants
	end
	if self.revokeAction then
		self.revokeAction.Visible = self.selectedRecord ~= nil
			and self.canWriteWarrants
			and #((self.selectedRecord and self.selectedRecord.Warrants) or {}) > 0
	end
end

function MDTController:Start()
	self:_mount()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.M and self.allowed then
				self.shell.Visible = not self.shell.Visible
			end
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			self:RefreshAccess()
		end)
	)
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("MDT", function(layout)
		self.launcher.AnchorPoint = if layout.Vehicle
			then Vector2.new(0, 1)
			else Vector2.new(0, 0.5)
		self.launcher.Position = if layout.Vehicle
			then UDim2.new(0, 18, 1, -(layout.HotbarBottom + 8))
			else UDim2.new(0, 18, 0.62, 0)
		if layout.Compact then
			self.constraint.MinSize = Vector2.new(720, 470)
			self.scale.Scale = math.clamp(
				math.min((layout.Viewport.X - 20) / 720, (layout.Viewport.Y - 28) / 470),
				0.44,
				1
			)
		else
			self.constraint.MinSize = Vector2.new(720, 470)
			self.scale.Scale = 1
		end
		if layout.Vehicle then
			self.shell.Visible = false
		end
	end)
	self:RefreshAccess()
end

function MDTController:Search(recordType: string, query: string, page: number?): any
	return self.context.Controllers.NetworkController:Request(
		"MDTSearch",
		{ Type = recordType, Query = query, Page = page or 1 }
	)
end

function MDTController:Destroy()
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

return MDTController
