--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Tokens = require(script.Parent.Parent.UI.DesignTokens)
local C, T, S = Tokens.Colour, Tokens.Text, Tokens.Stroke

-- Weak keyed. A tool destroyed on respawn should be collectable, and holding it
-- strongly kept every tool the player had ever carried alive for the session.
local PublicSafetyController = {
	connections = {},
	watched = setmetatable({}, { __mode = "k" }),
	scanConnections = {},
	actionState = {},
}
local CLOSE_ACTION = "RoleplayOSCustodyActionsClose"

-- The distance the server enforces on every restraint action. Shown rather than
-- enforced here: the officer is told how far away the detainee is and where the
-- line is, so a refusal reads as "walk forward" instead of as a broken button.
local INTERACTION_RANGE = 12

local SEARCH_POWERS = {
	{ Code = "PACE_S1", Label = "PACE S1  ·  STOLEN OR PROHIBITED" },
	{ Code = "CJPOA_S60", Label = "CJPOA S60  ·  OFFENSIVE WEAPONS" },
	{ Code = "FIREARMS_S47", Label = "FIREARMS ACT S47  ·  FIREARMS" },
	{ Code = "PACE_S32_POST_ARREST", Label = "PACE S32  ·  POST-ARREST" },
	{ Code = "PACE_S54_CUSTODY", Label = "PACE S54  ·  DETAINEE AT STATION" },
}

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
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Parent = parent
	return item
end

-- Square and on the terminal palette, like every other operational surface. This
-- panel was the last one still drawing its own rounded navy, which made the one
-- screen an officer uses while holding somebody look like a different product
-- from the vehicle forecourt and the MDT.
local function actionButton(parent: Instance, value: string, fill: Color3?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.Size = UDim2.new(0.5, -5, 0, 38)
	item.BackgroundColor3 = fill or C.raised
	item.BorderSizePixel = 0
	item.Font = Tokens.Font.bold
	item.Text = value
	item.TextColor3 = C.text
	item.TextSize = T.button
	item.Parent = parent
	return item
end

local function panelLabel(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3,
	bold: boolean?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Tokens.Font.bold else Tokens.Font.regular
	item.Text = value
	item.TextColor3 = colour
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

local function distanceToTarget(userId: number?): number?
	local target = if userId then Players:GetPlayerByUserId(userId) else nil
	local localCharacter = Players.LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root or not localRoot:IsA("BasePart") or not root:IsA("BasePart") then
		return nil
	end
	return math.floor((localRoot.Position - root.Position).Magnitude + 0.5)
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
	self.actionGeneration = (self.actionGeneration or 0) + 1
	if open then
		self.previousSelection = GuiService.SelectedObject
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.actionClose
		end
		self:_startActionRefresh()
		return
	end
	self.actionTargetUserId = nil
	table.clear(self.actionState)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.actionPanel) then
		local previous = self.previousSelection
		GuiService.SelectedObject = if previous and previous.Parent then previous else nil
	end
end

function PublicSafetyController:_showActions(targetUserId: number, state: any?)
	self.actionTargetUserId = targetUserId
	table.clear(self.actionState)
	if type(state) == "table" then
		for key, value in state do
			self.actionState[key] = value
		end
	end
	self.searchResult.Text = ""
	self:_setActionsOpen(true)
	self:_refreshActions()
end

-- Everything the officer needs to know before pressing anything: who they are
-- holding, what has already been done to them, and how far away they are.
--
-- The panel used to state only the name. Whether the caution had been read,
-- whether a search had been recorded and whether the officer still had hold of
-- them were all facts the server tracked and the officer had no way to see, so
-- the workflow was carried out from memory and the buttons gave no clue which
-- of them had already been used.
function PublicSafetyController:_refreshActions()
	local userId = self.actionTargetUserId
	local target = if userId then Players:GetPlayerByUserId(userId) else nil
	if not target then
		self.actionTarget.Text = "DETAINEE  ·  NO LONGER HERE"
		self.actionStatus.Text = ""
		self.actionRange.Text = ""
		return
	end
	self.actionTarget.Text = string.format("%s  ·  @%s", target.DisplayName, target.Name)

	-- The reply to CuffPlayer beats the detainee's replicated attribute to this
	-- client, so for the first moments after an arrest the panel is trusting the
	-- answer it already has rather than reporting the person it just cuffed as
	-- not cuffed.
	local cuffed = target:GetAttribute("RoleplayOSCuffed") == true
		or (not self.actionCuffedSeen and self.actionState.Cuffed == true)
	local escorted = target:GetAttribute("RoleplayOSEscorted") == true
	local position = tostring(target:GetAttribute("RoleplayOSCuffPosition") or "Rear")
	local held = escorted and self.actionState.EscortedByUserId == Players.LocalPlayer.UserId
	local parts = {}
	table.insert(parts, if cuffed then "CUFFED " .. string.upper(position) else "NOT CUFFED")
	if escorted then
		table.insert(parts, if held then "YOU HAVE HOLD" else "HELD BY ANOTHER OFFICER")
	end
	if self.actionState.Cautioned then
		table.insert(parts, "CAUTIONED")
	end
	if self.actionState.Searched then
		table.insert(parts, "SEARCHED")
	end
	self.actionStatus.Text = table.concat(parts, "   ·   ")
	self.actionStatus.TextColor3 = if cuffed then C.accent else C.warning

	local metres = distanceToTarget(userId)
	if not metres then
		self.actionRange.Text = "OUT OF SIGHT"
		self.actionRange.TextColor3 = C.warning
	elseif metres > INTERACTION_RANGE then
		self.actionRange.Text = string.format("%d M AWAY  ·  TOO FAR, WALK CLOSER", metres)
		self.actionRange.TextColor3 = C.warning
	else
		self.actionRange.Text = string.format("%d M AWAY  ·  IN REACH", metres)
		self.actionRange.TextColor3 = C.muted
	end

	self.escort.Text = if held then "LET GO" elseif escorted then "HELD BY OTHER" else "TAKE HOLD"
end

-- Distance changes with every step and the cuffs can come off from the other
-- officer's panel, so the readout is re-derived on a timer from replicated
-- attributes. No request is made: everything on it is already on the client.
function PublicSafetyController:_startActionRefresh()
	local generation = self.actionGeneration
	self.actionCuffedSeen = false
	task.spawn(function()
		local opened = os.clock()
		while self.actionGeneration == generation and self.actionPanel.Visible do
			local userId = self.actionTargetUserId
			local target = if userId then Players:GetPlayerByUserId(userId) else nil
			if target and target:GetAttribute("RoleplayOSCuffed") == true then
				self.actionCuffedSeen = true
			end
			self:_refreshActions()
			-- The panel describes a person in handcuffs in front of the officer, and
			-- closes when that stops being true rather than staying up over a
			-- workflow that has already ended somewhere else. It waits to have seen
			-- the cuffs replicate before it will act on their absence, because
			-- otherwise the arrest that opened it would close it a frame later.
			local uncuffed = self.actionCuffedSeen
				and (not target or target:GetAttribute("RoleplayOSCuffed") ~= true)
			local neverArrived = not self.actionCuffedSeen and os.clock() - opened > 5
			if not target or uncuffed or neverArrived then
				self:_setActionsOpen(false)
				return
			end
			task.wait(0.4)
		end
	end)
end

-- What actually happened, rather than "Custody action completed" for every
-- button on the panel and "Custody action was refused" for every possible reason.
function PublicSafetyController:_describe(action: string, data: any): string
	local state = if type(data) == "table" and type(data.State) == "table" then data.State else data
	if action == "Caution" then
		return "Caution read out."
	elseif action == "Search" then
		local items = if type(data) == "table" and type(data.Items) == "table"
			then data.Items
			else {}
		return if #items > 0
			then "Search recorded. Found: " .. table.concat(items, ", ") .. "."
			else "Search recorded. They were carrying nothing."
	elseif action == "SeizeWeapons" then
		local weapons = if type(data) == "table" and type(data.Weapons) == "table"
			then data.Weapons
			else {}
		return if #weapons > 0
			then "Seized: " .. table.concat(weapons, ", ") .. "."
			else "Nothing to seize. They were carrying no weapons."
	elseif action == "Escort" then
		local held = type(state) == "table" and state.EscortedByUserId == Players.LocalPlayer.UserId
		return if held then "You have hold of them." else "You have let go of them."
	elseif action == "Vehicle" then
		return "Moved into or out of the nearest custody seat."
	elseif action == "CuffPosition" then
		local position = if type(state) == "table" then tostring(state.CuffPosition) else "Rear"
		return "Cuffs moved to the " .. string.lower(position) .. "."
	elseif action == "Release" then
		return "Handcuffs removed. They are free to go."
	end
	return "Done."
end

function PublicSafetyController:_custodyAction(action: string, data: any?)
	if not self.actionTargetUserId then
		self.context.Controllers.NotificationController:Show(
			"Nobody is selected. Use your handcuffs on somebody first.",
			"Custody"
		)
		return
	end
	local response = self.context.Controllers.NetworkController:Request("CustodyAction", {
		TargetUserId = self.actionTargetUserId,
		Action = action,
		Data = data or {},
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(
			self.context.Controllers.CustodyController:Explain(
				response,
				"That custody action was refused."
			),
			"Custody",
			"Danger"
		)
		return
	end
	local state = if type(response.Data) == "table"
			and type(response.Data.State) == "table"
		then response.Data.State
		else response.Data
	if type(state) == "table" and state.Cuffed ~= nil then
		for key, value in state do
			self.actionState[key] = value
		end
	end
	if action == "Search" then
		local items = if type(response.Data.Items) == "table" then response.Data.Items else {}
		self.searchResult.Text = if #items > 0
			then "FOUND  ·  " .. table.concat(items, ", ")
			else "FOUND  ·  NOTHING"
		self.searchResult.TextColor3 = if #items > 0 then C.warning else C.muted
	end
	self.context.Controllers.NotificationController:Show(
		self:_describe(action, response.Data),
		"Custody",
		"Success"
	)
	if action == "Release" then
		self:_setActionsOpen(false)
		return
	end
	self:_refreshActions()
end

function PublicSafetyController:_showCard(card: any)
	local police = card.CredentialType == "Police"
	if police then
		-- The warrant-card Tool has its own fitted SurfaceGui and is visible in
		-- the officer's hand. The generic licence overlay does not share its
		-- proportions, so displaying both caused text to overflow the asset.
		self.card.Visible = false
		return
	end
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
	local roleplayToolId = tostring(tool:GetAttribute("RoleplayOSToolId") or tool.Name)
	if
		roleplayToolId ~= "Handcuffs"
		and roleplayToolId ~= "ID Card"
		and roleplayToolId ~= "Warrant Card"
	then
		return
	end
	self.watched[tool] = true
	table.insert(
		self.connections,
		tool.Activated:Connect(function()
			local target = self:_targetUserId()
			if not target then
				self.context.Controllers.NotificationController:Show(
					"Point at a player standing near you and use it again.",
					tool.Name
				)
				return
			end
			local isCuffs = roleplayToolId == "Handcuffs"
			local response = self.context.Controllers.NetworkController:Request(
				if isCuffs then "CuffPlayer" else "GetPresentedId",
				if isCuffs
					then { TargetUserId = target, Mode = "Apply" }
					else {
						TargetUserId = target,
						CredentialType = if roleplayToolId == "Warrant Card"
							then "Police"
							else "Civilian",
					}
			)
			if not response.Success then
				-- The server sends one message for every refusal the handcuffs can
				-- meet -- wrong role, too far, target dead, cuffs not in hand -- and
				-- the officer was shown the same sentence for all of them.
				self.context.Controllers.NotificationController:Show(
					self.context.Controllers.CustodyController:Explain(
						response,
						"The handcuffs could not be used."
					),
					roleplayToolId,
					"Danger"
				)
				return
			end
			if not isCuffs then
				self.context.Controllers.NotificationController:Show(
					response.Message,
					roleplayToolId
				)
				return
			end
			if response.Data and response.Data.Cuffed then
				-- Also the way back in. Using the cuffs on somebody already wearing
				-- them reopens their custody actions, which is the only route back
				-- to the panel after the officer has closed it.
				self:_showActions(target, response.Data)
			end
		end)
	)
end

function PublicSafetyController:_scan(container: Instance, slot: string)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			self:_watchTool(child)
		end
	end
	-- Backpack and Character must be watched simultaneously. Replacing the
	-- global listener here used to make credentials issued after duty started
	-- visible but inert because scanning Character disconnected Backpack.
	local existing = self.scanConnections[slot]
	if existing then
		existing:Disconnect()
	end
	self.scanConnections[slot] = container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			self:_watchTool(child)
		end
	end)
end

function PublicSafetyController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSPublicSafety"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
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
	actionPanel.Size = UDim2.fromOffset(420, 570)
	actionPanel.BackgroundColor3 = C.surface
	actionPanel.BorderSizePixel = 0
	actionPanel.Visible = false
	actionPanel.Parent = gui
	local actionStroke = Instance.new("UIStroke")
	actionStroke.Color = C.border
	actionStroke.Thickness = S.thickness
	actionStroke.Transparency = S.transparency
	actionStroke.Parent = actionPanel
	local actionScale = Instance.new("UIScale")
	actionScale.Parent = actionPanel
	local actionRule = Instance.new("Frame")
	actionRule.Size = UDim2.new(1, 0, 0, 2)
	actionRule.BackgroundColor3 = C.accent
	actionRule.BorderSizePixel = 0
	actionRule.Parent = actionPanel

	local actionTitle = panelLabel(actionPanel, "PERSON IN CUSTODY", T.subtitle, C.text, true)
	actionTitle.Position = UDim2.fromOffset(18, 16)
	actionTitle.Size = UDim2.new(1, -76, 0, 22)
	local actionClose = actionButton(actionPanel, "×")
	actionClose.Position = UDim2.new(1, -52, 0, 12)
	actionClose.Size = UDim2.fromOffset(38, 34)
	actionClose.TextSize = T.title

	local actionTarget = panelLabel(actionPanel, "NOBODY SELECTED", T.body, C.text, true)
	actionTarget.Position = UDim2.fromOffset(18, 44)
	actionTarget.Size = UDim2.new(1, -36, 0, 20)
	actionTarget.TextTruncate = Enum.TextTruncate.AtEnd
	local actionStatus = panelLabel(actionPanel, "", T.dense, C.accent, true)
	actionStatus.Position = UDim2.fromOffset(18, 66)
	actionStatus.Size = UDim2.new(1, -36, 0, 18)
	actionStatus.TextTruncate = Enum.TextTruncate.AtEnd
	local actionRange = panelLabel(actionPanel, "", T.dense, C.muted)
	actionRange.Position = UDim2.fromOffset(18, 86)
	actionRange.Size = UDim2.new(1, -36, 0, 18)

	local searchLabel = panelLabel(actionPanel, "SEARCH", T.section, C.muted, true)
	searchLabel.Position = UDim2.fromOffset(18, 114)
	searchLabel.Size = UDim2.new(1, -36, 0, 14)

	local powerIndex = 1
	local power = actionButton(actionPanel, SEARCH_POWERS[powerIndex].Label)
	power.Position = UDim2.fromOffset(18, 132)
	power.Size = UDim2.new(1, -36, 0, 34)
	power.TextColor3 = C.accent

	local grounds = Instance.new("TextBox")
	grounds.Position = UDim2.fromOffset(18, 172)
	grounds.Size = UDim2.new(1, -36, 0, 64)
	grounds.BackgroundColor3 = C.raised
	grounds.BorderSizePixel = 0
	grounds.ClearTextOnFocus = false
	grounds.Font = Tokens.Font.regular
	grounds.MultiLine = true
	grounds.PlaceholderText = "Why you are searching them, and what you expect to find"
	grounds.PlaceholderColor3 = C.muted
	grounds.Text = ""
	grounds.TextColor3 = C.text
	grounds.TextSize = T.body
	grounds.TextWrapped = true
	grounds.TextXAlignment = Enum.TextXAlignment.Left
	grounds.TextYAlignment = Enum.TextYAlignment.Top
	grounds.Parent = actionPanel
	local groundsPad = Instance.new("UIPadding")
	groundsPad.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
	groundsPad.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
	groundsPad.PaddingTop = UDim.new(0, Tokens.Spacing.gap)
	groundsPad.Parent = grounds
	local groundsStroke = Instance.new("UIStroke")
	groundsStroke.Color = C.border
	groundsStroke.Thickness = S.thickness
	groundsStroke.Transparency = S.transparency
	groundsStroke.Parent = grounds

	-- What the search turned up, on the panel rather than nowhere. The server has
	-- always replied with the detainee's inventory and this client discarded it,
	-- so an officer recorded a search and was never told the result of it.
	local searchResult = panelLabel(actionPanel, "", T.dense, C.muted, true)
	searchResult.Position = UDim2.fromOffset(18, 240)
	searchResult.Size = UDim2.new(1, -36, 0, 18)
	searchResult.TextTruncate = Enum.TextTruncate.AtEnd
	self.searchResult = searchResult

	local actionsLabel = panelLabel(actionPanel, "ACTIONS", T.section, C.muted, true)
	actionsLabel.Position = UDim2.fromOffset(18, 264)
	actionsLabel.Size = UDim2.new(1, -36, 0, 14)

	-- Four rows of two, and the box is the height of four rows.
	--
	-- It held eight buttons in a box sized for four, and a ninth was added later,
	-- so the last pair overflowed the frame and drew on top of the disclaimer at
	-- the bottom of the panel. Booking moved out to a full width button of its
	-- own below, which both fixes the arithmetic and stops the one action that
	-- ends the arrest from sitting in the grid looking like a cuff position.
	local actions = Instance.new("Frame")
	actions.Position = UDim2.fromOffset(18, 282)
	actions.Size = UDim2.new(1, -36, 0, 160)
	actions.BackgroundTransparency = 1
	actions.Parent = actionPanel
	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellPadding = UDim2.fromOffset(8, 8)
	actionLayout.CellSize = UDim2.new(0.5, -4, 0, 34)
	actionLayout.FillDirectionMaxCells = 2
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actions
	local caution = actionButton(actions, "READ CAUTION")
	caution.LayoutOrder = 1
	local search = actionButton(actions, "RECORD SEARCH")
	search.LayoutOrder = 2
	local escort = actionButton(actions, "TAKE HOLD")
	escort.LayoutOrder = 3
	self.escort = escort
	local vehicle = actionButton(actions, "VEHICLE IN / OUT")
	vehicle.LayoutOrder = 4
	local front = actionButton(actions, "CUFFS TO FRONT")
	front.LayoutOrder = 5
	local rear = actionButton(actions, "CUFFS TO REAR")
	rear.LayoutOrder = 6
	local seize = actionButton(actions, "SEIZE WEAPONS")
	seize.LayoutOrder = 7
	local release = actionButton(actions, "REMOVE CUFFS")
	release.LayoutOrder = 8
	release.TextColor3 = C.danger

	-- The end of the arrest, and until recently it had no button anywhere.
	--
	-- The booking screen lives in CustodyController and its only opener was a HUD
	-- launcher that is forced invisible, so an officer could caution, search,
	-- cuff and escort somebody and then simply had nothing to press. It is the
	-- primary action of this panel, so it is the full width button under the
	-- grid rather than one cell among eight.
	local book = actionButton(actionPanel, "BOOK INTO CUSTODY", C.accentFill)
	book.Position = UDim2.fromOffset(18, 454)
	book.Size = UDim2.new(1, -36, 0, 48)

	local notice = panelLabel(
		actionPanel,
		"Simplified UK roleplay workflow · server validated · not professional training",
		T.dense,
		C.muted
	)
	notice.Position = UDim2.fromOffset(18, 510)
	notice.Size = UDim2.new(1, -36, 0, 36)
	notice.TextWrapped = true
	notice.TextYAlignment = Enum.TextYAlignment.Top

	table.insert(
		self.connections,
		actionClose.Activated:Connect(function()
			self:_setActionsOpen(false)
		end)
	)
	table.insert(
		self.connections,
		power.Activated:Connect(function()
			powerIndex = (powerIndex % #SEARCH_POWERS) + 1
			power.Text = SEARCH_POWERS[powerIndex].Label
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
		book.Activated:Connect(function()
			-- Carried across so the booking screen opens on the person the officer
			-- already has selected, rather than asking them to pick again. The
			-- actions panel only stands down once the booking screen is up, so a
			-- refused open does not leave the officer looking at nothing.
			local target = self.actionTargetUserId
			if self.context.Controllers.CustodyController:Open(target) then
				self:_setActionsOpen(false)
			end
		end)
	)
	table.insert(
		self.connections,
		search.Activated:Connect(function()
			-- Checked here as well as on the server, because the server's refusal
			-- arrives as a notification over a form the officer can no longer see
			-- the state of, and the fix is always "type in the box above".
			local written = string.match(grounds.Text, "^%s*(.-)%s*$") or ""
			if #written < 5 then
				self.context.Controllers.NotificationController:Show(
					"Write your grounds for the search in the box first.",
					"Search"
				)
				grounds:CaptureFocus()
				return
			end
			self:_custodyAction(
				"Search",
				{ Grounds = written, Power = SEARCH_POWERS[powerIndex].Code }
			)
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
		seize.Activated:Connect(function()
			self:_custodyAction("SeizeWeapons")
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
			local orchestrator = self.context.Controllers.UIOrchestrator
			scale.Scale = orchestrator:FitScale(layout, Vector2.new(480, 303), 40)
			actionScale.Scale = orchestrator:FitScale(layout, Vector2.new(420, 570), 40)
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
	self.actionStatus = actionStatus
	self.actionRange = actionRange
	self.gui = gui
end

function PublicSafetyController:Start()
	self:_mount()
	local credentialEvent =
		self.context.Controllers.NetworkController:ResolveEvent("CredentialPresented")
	if credentialEvent then
		table.insert(
			self.connections,
			credentialEvent.OnClientEvent:Connect(function(card)
				if type(card) == "table" then
					self:_showCard(card)
				end
			end)
		)
	end
	-- CustodyService owns the chair's ProximityPrompt server-side and validates
	-- the trigger itself, so this is a read-only reply naming who is in the
	-- chair (or why there is nobody to process) rather than a request this
	-- client makes - the same shape VendorOpened already uses.
	--
	-- Goes straight to the booking terminal, not the roadside actions panel.
	-- Caution, search and the rest happen at the point of arrest and are still
	-- reached by using the cuffs again on a detainee stood in front of an
	-- officer; sitting someone down in a custody chair is specifically the
	-- booking-desk moment, and putting the same roadside panel behind it would
	-- have made the chair nothing but a second way to open the first screen.
	local chairEvent =
		self.context.Controllers.NetworkController:ResolveEvent("CustodyChairProcessed")
	if chairEvent then
		table.insert(
			self.connections,
			chairEvent.OnClientEvent:Connect(function(result)
				if type(result) ~= "table" then
					return
				end
				if result.Success and type(result.Data) == "table" then
					self.context.Controllers.CustodyController:Open(result.Data.TargetUserId)
					return
				end
				self.context.Controllers.NotificationController:Show(
					self.context.Controllers.CustodyController:Explain(
						{ Code = result.Reason },
						"That chair could not be used."
					),
					"Custody Chair",
					"Danger"
				)
			end)
		)
	end
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
	-- Stand the panel down when the thing it belongs to ends.
	--
	-- It closed on its own buttons, on Escape, and on nothing else, so going off
	-- duty, changing team or being killed mid-arrest left a full custody
	-- workflow on screen for a detainee the officer no longer had, every button
	-- of which the server would refuse.
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
		end)
	)
	local player = Players.LocalPlayer
	table.insert(
		self.connections,
		player.CharacterRemoving:Connect(function()
			if self.actionPanel.Visible then
				self:_setActionsOpen(false)
			end
			self.card.Visible = false
		end)
	)
	self:_scan(player:WaitForChild("Backpack"), "Backpack")
	if player.Character then
		self:_scan(player.Character, "Character")
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_scan(character, "Character")
		end)
	)
end

function PublicSafetyController:Destroy()
	ContextActionService:UnbindAction(CLOSE_ACTION)
	-- Retires the status refresh loop as well: it is a spawned thread rather than
	-- a connection, so nothing else would stop it.
	self.actionGeneration = (self.actionGeneration or 0) + 1
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, connection in self.scanConnections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.scanConnections)
	table.clear(self.actionState)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return PublicSafetyController
