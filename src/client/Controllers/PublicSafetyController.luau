--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PublicSafetyController = { connections = {}, watched = {} }
local CLOSE_ACTION = "RoleplayOSCustodyActionsClose"

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(
	parent: Instance,
	y: number,
	height: number,
	textSize: number,
	bold: boolean
): TextLabel
	local item = Instance.new("TextLabel")
	item.Position = UDim2.fromOffset(174, y)
	item.Size = UDim2.new(1, -194, 0, height)
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.TextColor3 = Color3.fromRGB(30, 40, 48)
	item.TextSize = textSize
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function actionButton(parent: Instance, text: string): TextButton
	local item = Instance.new("TextButton")
	item.Size = UDim2.new(0.5, -5, 0, 38)
	item.BackgroundColor3 = Color3.fromRGB(25, 39, 55)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(239, 245, 251)
	item.TextSize = 11
	item.Parent = parent
	corner(item, 8)
	return item
end

function PublicSafetyController:Init(context: any)
	self.context = context
end

function PublicSafetyController:_targetUserId(): number?
	local mouse = Players.LocalPlayer:GetMouse()
	local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if player and player ~= Players.LocalPlayer then
		return player.UserId
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local localCharacter = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if localCharacter then { localCharacter } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 24, params)
	local hitModel = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	local hitPlayer = hitModel and Players:GetPlayerFromCharacter(hitModel)
	return if hitPlayer and hitPlayer ~= Players.LocalPlayer then hitPlayer.UserId else nil
end

function PublicSafetyController:_setActionsOpen(open: boolean)
	self.actionPanel.Visible = open
	if open then
		self.previousSelection = GuiService.SelectedObject
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.actionClose
		end
	elseif
		GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.actionPanel)
	then
		local previous = self.previousSelection
		GuiService.SelectedObject = if previous and previous.Parent then previous else nil
	end
end

function PublicSafetyController:_showActions(targetUserId: number)
	self.actionTargetUserId = targetUserId
	local target = Players:GetPlayerByUserId(targetUserId)
	self.actionTarget.Text = if target
		then string.format("DETAINEE  ·  %s  (@%s)", target.DisplayName, target.Name)
		else "DETAINEE  ·  UNKNOWN"
	self:_setActionsOpen(true)
end

function PublicSafetyController:_custodyAction(action: string, data: any?)
	if not self.actionTargetUserId then
		return
	end
	local response = self.context.Controllers.NetworkController:Request("CustodyAction", {
		TargetUserId = self.actionTargetUserId,
		Action = action,
		Data = data or {},
	})
	self.context.Controllers.NotificationController:Show(response.Message, "Custody")
	if response.Success and action == "Release" then
		self:_setActionsOpen(false)
		self.actionTargetUserId = nil
	end
end

function PublicSafetyController:_showCard(card: any)
	local police = card.CredentialType == "Police"
	self.card.BackgroundColor3 = if police
		then Color3.fromRGB(234, 237, 242)
		else Color3.fromRGB(225, 217, 195)
	self.band.BackgroundColor3 = if police
		then Color3.fromRGB(20, 46, 73)
		else Color3.fromRGB(40, 66, 82)
	self.cardTitle.Text = if police
		then card.ForceName
		else "ROLEPLAY DRIVING LICENCE · UNITED KINGDOM"
	self.cardSubtitle.Text = if police then "POLICE WARRANT CARD" else "FICTIONAL PHOTOCARD"
	self.avatar.Image = card.AvatarImage or ""
	self.cardName.Text = string.upper(card.FullName)
	self.cardDob.Text = if police
		then "RANK  ·  " .. tostring(card.Rank or "POLICE OFFICER")
		else "DATE OF BIRTH  ·  " .. card.DateOfBirth
	self.cardNumber.Text = if police
		then "WARRANT NUMBER  ·  " .. tostring(card.WarrantNumber or "")
		else "DRIVER NUMBER  ·  " .. card.DocumentNumber
	self.validity.Text = if police
		then "PRESENTED BY THE NAMED OFFICER"
		else string.format("ISSUED  %s    ·    VALID TO  %s", card.Issued, card.ValidTo)
	self.card.Visible = true
	task.delay(8, function()
		if self.card then
			self.card.Visible = false
		end
	end)
end

function PublicSafetyController:_watchTool(tool: Tool)
	if self.watched[tool] then
		return
	end
	if tool.Name ~= "Handcuffs" and tool.Name ~= "ID Card" and tool.Name ~= "Warrant Card" then
		return
	end
	self.watched[tool] = true
	table.insert(
		self.connections,
		tool.Activated:Connect(function()
			local target = self:_targetUserId()
			if not target then
				self.context.Controllers.NotificationController:Show(
					"Look at a nearby player and try again.",
					tool.Name
				)
				return
			end
			local isCuffs = tool.Name == "Handcuffs"
			local response = self.context.Controllers.NetworkController:Request(
				if isCuffs then "CuffPlayer" else "GetPresentedId",
				if isCuffs
					then { TargetUserId = target, Mode = "Apply" }
					else {
						TargetUserId = target,
						CredentialType = if tool.Name == "Warrant Card"
							then "Police"
							else "Civilian",
					}
			)
			self.context.Controllers.NotificationController:Show(response.Message, tool.Name)
			if response.Success then
				if isCuffs and response.Data.Cuffed then
					self:_showActions(target)
				elseif not isCuffs then
					self:_showCard(response.Data)
				end
			end
		end)
	)
end

function PublicSafetyController:_scan(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			self:_watchTool(child)
		end
	end
	table.insert(
		self.connections,
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				self:_watchTool(child)
			end
		end)
	)
end

function PublicSafetyController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSPublicSafety"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 25
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.46)
	card.Size = UDim2.fromOffset(480, 303)
	card.BackgroundColor3 = Color3.fromRGB(225, 217, 195)
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	corner(card, 15)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(91, 99, 105)
	stroke.Transparency = 0.35
	stroke.Parent = card
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 68)
	band.BackgroundColor3 = Color3.fromRGB(40, 66, 82)
	band.BorderSizePixel = 0
	band.Parent = card
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 9)
	title.Size = UDim2.new(1, -40, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = band
	local subtitle = title:Clone()
	subtitle.Position = UDim2.fromOffset(20, 38)
	subtitle.Size = UDim2.new(1, -40, 0, 20)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(197, 214, 225)
	subtitle.TextSize = 10
	subtitle.Parent = band
	local avatar = Instance.new("ImageLabel")
	avatar.Position = UDim2.fromOffset(20, 88)
	avatar.Size = UDim2.fromOffset(132, 158)
	avatar.BackgroundColor3 = Color3.fromRGB(184, 190, 183)
	avatar.BorderSizePixel = 0
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = card
	corner(avatar, 9)
	local name = label(card, 88, 48, 21, true)
	name.TextWrapped = true
	local dob = label(card, 145, 28, 11, true)
	local number = label(card, 179, 28, 11, true)
	local validity = label(card, 214, 28, 10, false)
	local disclaimer = Instance.new("TextLabel")
	disclaimer.Position = UDim2.fromOffset(20, 266)
	disclaimer.Size = UDim2.new(1, -40, 0, 24)
	disclaimer.BackgroundTransparency = 1
	disclaimer.Font = Enum.Font.GothamBold
	disclaimer.Text = "ROLEPLAY ONLY · NOT VALID IDENTIFICATION"
	disclaimer.TextColor3 = Color3.fromRGB(139, 34, 39)
	disclaimer.TextSize = 10
	disclaimer.TextXAlignment = Enum.TextXAlignment.Center
	disclaimer.Parent = card

	local actionPanel = Instance.new("Frame")
	actionPanel.AnchorPoint = Vector2.new(1, 0.5)
	actionPanel.Size = UDim2.fromOffset(410, 430)
	actionPanel.BackgroundColor3 = Color3.fromRGB(8, 15, 24)
	actionPanel.BorderSizePixel = 0
	actionPanel.Visible = false
	actionPanel.Parent = gui
	corner(actionPanel, 15)
	local actionStroke = Instance.new("UIStroke")
	actionStroke.Color = Color3.fromRGB(47, 70, 94)
	actionStroke.Transparency = 0.25
	actionStroke.Parent = actionPanel
	local actionScale = Instance.new("UIScale")
	actionScale.Parent = actionPanel
	local actionTitle = Instance.new("TextLabel")
	actionTitle.Position = UDim2.fromOffset(18, 15)
	actionTitle.Size = UDim2.new(1, -76, 0, 24)
	actionTitle.BackgroundTransparency = 1
	actionTitle.Font = Enum.Font.GothamBold
	actionTitle.Text = "RESTRAINT & CUSTODY ACTIONS"
	actionTitle.TextColor3 = Color3.fromRGB(240, 246, 252)
	actionTitle.TextSize = 14
	actionTitle.TextXAlignment = Enum.TextXAlignment.Left
	actionTitle.Parent = actionPanel
	local actionClose = actionButton(actionPanel, "×")
	actionClose.Position = UDim2.new(1, -52, 0, 11)
	actionClose.Size = UDim2.fromOffset(38, 34)
	actionClose.TextSize = 20
	local actionTarget = actionTitle:Clone()
	actionTarget.Position = UDim2.fromOffset(18, 48)
	actionTarget.Size = UDim2.new(1, -36, 0, 22)
	actionTarget.Font = Enum.Font.Gotham
	actionTarget.Text = "DETAINEE  ·  NOT SELECTED"
	actionTarget.TextColor3 = Color3.fromRGB(153, 174, 195)
	actionTarget.TextSize = 10
	actionTarget.Parent = actionPanel
	local grounds = Instance.new("TextBox")
	grounds.Position = UDim2.fromOffset(18, 82)
	grounds.Size = UDim2.new(1, -36, 0, 66)
	grounds.BackgroundColor3 = Color3.fromRGB(17, 28, 41)
	grounds.BorderSizePixel = 0
	grounds.ClearTextOnFocus = false
	grounds.Font = Enum.Font.Gotham
	grounds.PlaceholderText = "Record the grounds and objective of any search"
	grounds.Text = ""
	grounds.TextColor3 = Color3.fromRGB(237, 243, 249)
	grounds.TextSize = 12
	grounds.TextWrapped = true
	grounds.Parent = actionPanel
	corner(grounds, 8)

	local powers = { "PACE_S1", "PACE_S23_MDA", "PACE_S32_POST_ARREST" }
	local powerNames = {
		PACE_S1 = "PACE S1 · STOP & SEARCH",
		PACE_S23_MDA = "S23 MDA · DRUGS",
		PACE_S32_POST_ARREST = "PACE S32 · POST-ARREST",
	}
	local powerIndex = 1
	local power = actionButton(actionPanel, powerNames[powers[powerIndex]])
	power.Position = UDim2.fromOffset(18, 158)
	power.Size = UDim2.new(1, -36, 0, 34)
	power.TextColor3 = Color3.fromRGB(112, 190, 249)

	local actions = Instance.new("Frame")
	actions.Position = UDim2.fromOffset(18, 204)
	actions.Size = UDim2.new(1, -36, 0, 162)
	actions.BackgroundTransparency = 1
	actions.Parent = actionPanel
	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellPadding = UDim2.fromOffset(8, 8)
	actionLayout.CellSize = UDim2.new(0.5, -4, 0, 34)
	actionLayout.FillDirectionMaxCells = 2
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actions
	local caution = actionButton(actions, "READ CAUTION")
	local search = actionButton(actions, "RECORD SEARCH")
	local escort = actionButton(actions, "ESCORT / STOP")
	local vehicle = actionButton(actions, "VEHICLE IN / OUT")
	local front = actionButton(actions, "CUFFS TO FRONT")
	local rear = actionButton(actions, "CUFFS TO REAR")
	local release = actionButton(actions, "REMOVE CUFFS")
	release.BackgroundColor3 = Color3.fromRGB(112, 43, 48)
	local notice = actionTarget:Clone()
	notice.Position = UDim2.fromOffset(18, 378)
	notice.Size = UDim2.new(1, -36, 0, 36)
	notice.Text = "SIMPLIFIED UK ROLEPLAY WORKFLOW · SERVER VALIDATED · NOT PROFESSIONAL TRAINING"
	notice.TextWrapped = true
	notice.TextColor3 = Color3.fromRGB(116, 137, 157)
	notice.Parent = actionPanel

	table.insert(
		self.connections,
		actionClose.Activated:Connect(function()
			self:_setActionsOpen(false)
		end)
	)
	table.insert(
		self.connections,
		power.Activated:Connect(function()
			powerIndex = (powerIndex % #powers) + 1
			power.Text = powerNames[powers[powerIndex]]
		end)
	)
	table.insert(
		self.connections,
		caution.Activated:Connect(function()
			self:_custodyAction("Caution")
		end)
	)
	table.insert(
		self.connections,
		search.Activated:Connect(function()
			self:_custodyAction("Search", { Grounds = grounds.Text, Power = powers[powerIndex] })
		end)
	)
	table.insert(
		self.connections,
		escort.Activated:Connect(function()
			self:_custodyAction("Escort")
		end)
	)
	table.insert(
		self.connections,
		vehicle.Activated:Connect(function()
			self:_custodyAction("Vehicle")
		end)
	)
	table.insert(
		self.connections,
		front.Activated:Connect(function()
			self:_custodyAction("CuffPosition", { Position = "Front" })
		end)
	)
	table.insert(
		self.connections,
		rear.Activated:Connect(function()
			self:_custodyAction("CuffPosition", { Position = "Rear" })
		end)
	)
	table.insert(
		self.connections,
		release.Activated:Connect(function()
			self:_custodyAction("Release")
		end)
	)

	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"PublicSafety",
		function(layout)
			scale.Scale =
				math.clamp(math.min(layout.Viewport.X / 540, layout.Viewport.Y / 355), 0.67, 1)
			actionScale.Scale =
				math.clamp(math.min(layout.Viewport.X / 470, layout.Viewport.Y / 500), 0.62, 1)
			actionPanel.AnchorPoint = if layout.Compact or layout.VR
				then Vector2.new(0.5, 0.5)
				else Vector2.new(1, 0.5)
			actionPanel.Position = if layout.Compact or layout.VR
				then UDim2.fromScale(0.5, 0.5)
				else UDim2.new(1, -layout.RightReserve, 0.5, 0)
		end
	)
	self.card = card
	self.band = band
	self.cardTitle = title
	self.cardSubtitle = subtitle
	self.avatar = avatar
	self.cardName = name
	self.cardDob = dob
	self.cardNumber = number
	self.validity = validity
	self.actionPanel = actionPanel
	self.actionClose = actionClose
	self.actionTarget = actionTarget
	self.gui = gui
end

function PublicSafetyController:Start()
	self:_mount()
	ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin or not self.actionPanel.Visible then
			return Enum.ContextActionResult.Pass
		end
		self:_setActionsOpen(false)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(CLOSE_ACTION, "Close custody actions")
	ContextActionService:SetDescription(
		CLOSE_ACTION,
		"Closes the restraint and custody action panel"
	)
	local player = Players.LocalPlayer
	self:_scan(player:WaitForChild("Backpack"))
	if player.Character then
		self:_scan(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_scan(character)
		end)
	)
end

function PublicSafetyController:Destroy()
	ContextActionService:UnbindAction(CLOSE_ACTION)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return PublicSafetyController
