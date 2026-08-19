--!strict
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local Tokens = Utils.Tokens
local C, T, S = Utils.Colour, Utils.Text, Utils.Stroke
local corner = Utils.corner
local label = Utils.label
local actionButton = Utils.actionButton
local panelLabel = Utils.panelLabel

local SEARCH_POWERS = {
	{ Code = "PACE_S1", Label = "PACE S1  ·  STOLEN OR PROHIBITED" },
	{ Code = "CJPOA_S60", Label = "CJPOA S60  ·  OFFENSIVE WEAPONS" },
	{ Code = "FIREARMS_S47", Label = "FIREARMS ACT S47  ·  FIREARMS" },
	{ Code = "PACE_S32_POST_ARREST", Label = "PACE S32  ·  POST-ARREST" },
	{ Code = "PACE_S54_CUSTODY", Label = "PACE S54  ·  DETAINEE AT STATION" },
}

return function(PublicSafetyController)
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
end
