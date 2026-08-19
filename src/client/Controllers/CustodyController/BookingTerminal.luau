--!strict
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local Tokens = Utils.Tokens
local C, T = Utils.Colour, Utils.Text
local formatTime = Utils.formatTime
local text = Utils.text
local button = Utils.button
local outline = Utils.outline
local distanceTo = Utils.distanceTo

return function(CustodyController)
	-- Every player the local client can see wearing handcuffs, nearest first.
	--
	-- The picker used to list the whole server, which meant the officer chose from
	-- a column of names of which at most one could legally be booked and nothing
	-- said which. Cuffed state is a replicated attribute, so the client can show
	-- only the people this screen is actually about.
	function CustodyController:_detainees(): { Player }
		local found = {}
		for _, player in Players:GetPlayers() do
			if
				player ~= Players.LocalPlayer
				and player:GetAttribute("RoleplayOSCuffed") == true
			then
				table.insert(found, player)
			end
		end
		table.sort(found, function(a, b)
			local first, second = distanceTo(a), distanceTo(b)
			if first and second and first ~= second then
				return first < second
			end
			if first and not second then
				return true
			end
			if second and not first then
				return false
			end
			return a.UserId < b.UserId
		end)
		return found
	end

	function CustodyController:_paintChips()
		for userId, chip in self.chips do
			local selected = userId == self.targetUserId
			chip.BackgroundColor3 = if selected then C.accentFill else C.raised
			chip.TextColor3 = if selected then C.text else C.muted
		end
	end

	function CustodyController:_refreshDetainees()
		local detainees = self:_detainees()
		local present = {}
		for order, player in detainees do
			present[player.UserId] = true
			local chip = self.chips[player.UserId]
			if not chip then
				chip = button(self.detaineeRow, "", C.raised)
				chip.Name = tostring(player.UserId)
				chip.AutomaticSize = Enum.AutomaticSize.X
				chip.Size = UDim2.fromOffset(0, 38)
				local padding = Instance.new("UIPadding")
				padding.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
				padding.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
				padding.Parent = chip
				outline(chip)
				self.chips[player.UserId] = chip
				-- Not tracked in self.connections. Chips come and go every time somebody
				-- is cuffed or let go, and Destroy disconnects them, so keeping a handle
				-- would only grow a list of dead entries for the life of the session.
				chip.Activated:Connect(function()
					self.targetUserId = player.UserId
					self:_paintChips()
					self:_refreshSummary()
				end)
			end
			chip.LayoutOrder = order
			local metres = distanceTo(player)
			chip.Text = if metres
				then string.format("%s  ·  %dM", string.upper(player.DisplayName), metres)
				else string.upper(player.DisplayName)
		end
		for userId, chip in self.chips do
			if not present[userId] then
				chip:Destroy()
				self.chips[userId] = nil
			end
		end
		if self.targetUserId and not present[self.targetUserId] then
			self.targetUserId = nil
		end
		if not self.targetUserId and detainees[1] then
			self.targetUserId = detainees[1].UserId
		end
		self.detaineeEmpty.Visible = #detainees == 0
		self:_paintChips()
		return #detainees
	end

	function CustodyController:_refreshPolicy()
		for _, child in self.offenceList:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for order, offence in self.policy do
			local row = button(self.offenceList, "", C.raised)
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 40)
			row.Text = ""
			local marker = Instance.new("Frame")
			marker.Size = UDim2.new(0, 3, 1, 0)
			marker.BackgroundColor3 = C.accent
			marker.BorderSizePixel = 0
			marker.Parent = row
			local name = text(row, tostring(offence.Name), T.body, C.text, true)
			name.Position = UDim2.fromOffset(Tokens.Spacing.inset + 3, 0)
			name.Size = UDim2.new(1, -110, 1, 0)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local tariff = text(row, formatTime(offence.Seconds), T.body, C.muted, true)
			tariff.AnchorPoint = Vector2.new(1, 0)
			tariff.Position = UDim2.new(1, -Tokens.Spacing.inset, 0, 0)
			tariff.Size = UDim2.fromOffset(80, 40)
			tariff.TextXAlignment = Enum.TextXAlignment.Right
			local edge = outline(row)
			local function paint()
				local selected = self.selectedCodes[offence.Code] == true
				row.BackgroundColor3 = if selected then C.accentFill else C.raised
				marker.Visible = selected
				tariff.TextColor3 = if selected then C.text else C.muted
				edge.Color = if selected then C.accent else C.border
			end
			paint()
			-- Rebuilt whenever the offence list is redrawn, so the connection dies with
			-- the row rather than accumulating in self.connections.
			row.Activated:Connect(function()
				self.selectedCodes[offence.Code] = not self.selectedCodes[offence.Code]
				paint()
				self:_refreshSummary()
			end)
		end
	end

	-- The running total, the selected detainee and the one thing still stopping the
	-- booking from going through, all recomputed together.
	--
	-- This screen used to state a tariff per offence and then never add them up, so
	-- the officer chose a sentence length without being shown one, and the reason
	-- field's five character minimum existed only as a refusal after the fact.
	function CustodyController:_refreshSummary()
		local target = if self.targetUserId
			then Players:GetPlayerByUserId(self.targetUserId)
			else nil
		if target then
			local metres = distanceTo(target)
			self.selectedLine.Text = string.format(
				"%s  ·  @%s%s",
				target.DisplayName,
				target.Name,
				if metres then string.format("  ·  %d M AWAY", metres) else ""
			)
			self.selectedLine.TextColor3 = C.text
		else
			self.selectedLine.Text = "Nobody selected."
			self.selectedLine.TextColor3 = C.muted
		end

		local seconds = self:_selectedSeconds()
		local cap = math.max(0, tonumber(self.policyMetadata.MaximumStackedSentenceSeconds) or 0)
		local capped = cap > 0 and seconds > cap
		self.totalLine.Text = if seconds > 0
			then string.format(
				"TIME TO SERVE  ·  %s%s",
				formatTime(math.min(seconds, if cap > 0 then cap else seconds)),
				if capped then string.format("   (capped from %s)", formatTime(seconds)) else ""
			)
			else "TIME TO SERVE  ·  --:--"
		self.totalLine.TextColor3 = if seconds > 0 then C.accent else C.muted

		local grounds = #(string.match(self.reason.Text, "^%s*(.-)%s*$") or "")
		if not target then
			self.hint.Text = "Choose the detainee you have in handcuffs."
			self.hint.TextColor3 = C.warning
		elseif grounds < 5 then
			self.hint.Text = "Write why they are being detained. Five characters minimum."
			self.hint.TextColor3 = C.warning
		elseif seconds <= 0 then
			self.hint.Text =
				"No offence selected. Booking now records this as Other recorded offence."
			self.hint.TextColor3 = C.muted
		elseif self.policyMetadata.BookingChairRequired then
			self.hint.Text = "Ready. Sit the detainee in a custody chair before booking."
			self.hint.TextColor3 = C.muted
		else
			self.hint.Text = "Ready. Stay next to the detainee while this goes through."
			self.hint.TextColor3 = C.muted
		end
	end

	-- Opens the booking screen, on the detainee the officer already has selected.
	--
	-- The panel had exactly one way in: a HUD launcher that was set invisible when
	-- it was built and set invisible again on every access refresh, so it could
	-- never be pressed. Everything behind it was reachable only from that button,
	-- which meant an officer could cuff, search and escort somebody and then had no
	-- way to book them. Booking now opens from the restraint actions in
	-- PublicSafetyController, so the launcher is gone rather than hidden.
	function CustodyController:Open(targetUserId: number?): boolean
		if not self.bookingGui then
			return false
		end
		local duty = self.context.Controllers.DutyController.active
		if duty == nil or duty.DepartmentId ~= "Police" then
			self:_notify(
				"Only an officer on duty can book somebody into custody.",
				"Custody",
				"Danger"
			)
			return false
		end
		if targetUserId then
			self.targetUserId = targetUserId
		end
		if self:_refreshDetainees() == 0 then
			self:_notify("Nobody here is in handcuffs.", "Custody")
			return false
		end
		self.bookingGui.Enabled = true
		self:_refreshSummary()
		self:_startBookingRefresh()
		return true
	end

	function CustodyController:_closeBooking()
		if self.bookingGui then
			self.bookingGui.Enabled = false
		end
		self.bookingGeneration += 1
	end

	-- Distances change every step and cuffs come off without this screen being told,
	-- so the picker is re-read on a slow timer rather than left as it was when the
	-- screen opened. The generation counter stops a stale loop from outliving the
	-- panel it was started for.
	function CustodyController:_startBookingRefresh()
		self.bookingGeneration += 1
		local generation = self.bookingGeneration
		task.spawn(function()
			while
				self.bookingGeneration == generation
				and self.bookingGui
				and self.bookingGui.Enabled
			do
				task.wait(0.5)
				if self.bookingGeneration ~= generation then
					return
				end
				if self:_refreshDetainees() == 0 then
					self:_closeBooking()
					self:_notify("The detainee is no longer in handcuffs.", "Custody")
					return
				end
				self:_refreshSummary()
			end
		end)
	end

	function CustodyController:_submitBooking()
		if not self.targetUserId then
			self:_notify("Choose the detainee you have in handcuffs.", "Custody")
			return
		end
		local grounds = string.match(self.reason.Text, "^%s*(.-)%s*$") or ""
		if #grounds < 5 then
			self:_notify(
				"Write why they are being detained before booking. Five characters minimum.",
				"Custody"
			)
			self.reason:CaptureFocus()
			return
		end
		self.book.Active = false
		self.book.Text = "BOOKING…"
		local response = self.context.Controllers.NetworkController:Request("BookCustody", {
			TargetUserId = self.targetUserId,
			Reason = grounds,
			OffenceCodes = self:_selectedCodeList(),
		})
		self.book.Active = true
		self.book.Text = "BOOK INTO CUSTODY"
		if not response.Success then
			self:_notify(
				self:Explain(response, "The custody booking could not be completed."),
				"Booking refused"
			)
			return
		end
		local target = Players:GetPlayerByUserId(self.targetUserId)
		-- The server's own figure rather than the total this screen added up. Time
		-- already being served stacks onto the new offences and the result is capped,
		-- so the selection is an estimate and the booking record is the truth.
		local releaseAt = tonumber(response.Data and response.Data.ReleaseAt) or 0
		local serving = math.max(0, releaseAt - os.time())
		self:_notify(
			string.format(
				"%s has been booked in and moved to a cell.%s",
				if target then target.DisplayName else "The detainee",
				if serving > 0 then " Serving " .. formatTime(serving) .. "." else ""
			),
			"Booked into custody"
		)
		self:_closeBooking()
		self.reason.Text = ""
		self.targetUserId = nil
		table.clear(self.selectedCodes)
		self:_refreshPolicy()
	end

	function CustodyController:_refreshAccess(duty: any?)
		local activeDuty = duty or self.context.Controllers.DutyController.active
		local authorised = activeDuty ~= nil and activeDuty.DepartmentId == "Police"
		if not authorised then
			self:_closeBooking()
			self.targetUserId = nil
		end
	end

	function CustodyController:_mountBooking()
		local gui = Instance.new("ScreenGui")
		gui.Name = "RoleplayOSCustodyBooking"
		gui:SetAttribute("RoleplayOSManagedUI", true)
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.ClipToDeviceSafeArea = true
		-- Above the HUD, below the start menu. Booking fills the screen, and at 22 it
		-- sat under the radio at 38 and the phone at 40, either of which would draw a
		-- panel straight down the middle of the form the officer was filling in.
		gui.DisplayOrder = 45
		gui.Enabled = false
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		self.bookingGui = gui

		local panel = Instance.new("Frame")
		panel.Size = UDim2.fromScale(1, 1)
		panel.BackgroundColor3 = C.canvas
		panel.BorderSizePixel = 0
		panel.Parent = gui

		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 96)
		header.BackgroundColor3 = C.surface
		header.BorderSizePixel = 0
		header.Parent = panel
		local rule = Instance.new("Frame")
		rule.Position = UDim2.new(0, 0, 1, -2)
		rule.Size = UDim2.new(1, 0, 0, 2)
		rule.BackgroundColor3 = C.accent
		rule.BorderSizePixel = 0
		rule.Parent = header

		local title = text(header, "CUSTODY BOOKING", T.title, C.text, true)
		title.Position = UDim2.fromOffset(28, 18)
		title.Size = UDim2.new(1, -120, 0, 32)
		local subtitle = text(
			header,
			"Charge the detainee you have in handcuffs and send them to the cells",
			T.body,
			C.muted
		)
		subtitle.Position = UDim2.fromOffset(28, 50)
		subtitle.Size = UDim2.new(1, -120, 0, 22)
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd

		local close = button(header, "×", C.raised)
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -24, 0, 24)
		close.Size = UDim2.fromOffset(40, 40)
		close.TextSize = T.title
		table.insert(
			self.connections,
			close.Activated:Connect(function()
				self:_closeBooking()
			end)
		)

		local scroll = Instance.new("ScrollingFrame")
		scroll.Position = UDim2.fromOffset(0, 96)
		scroll.Size = UDim2.new(1, 0, 1, -96)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ScrollBarThickness = Tokens.Scroll.barThickness
		scroll.Parent = panel
		local centre = Instance.new("UIListLayout")
		centre.HorizontalAlignment = Enum.HorizontalAlignment.Center
		centre.Parent = scroll

		-- One column rather than two panes. Everything here is a single decision made
		-- top to bottom -- who, what for, why, submit -- and a column reflows onto a
		-- phone without the offence list having to become a third scrolling region.
		local column = Instance.new("Frame")
		column.AutomaticSize = Enum.AutomaticSize.Y
		column.Size = UDim2.new(1, -56, 0, 0)
		column.BackgroundTransparency = 1
		column.Parent = scroll
		local width = Instance.new("UISizeConstraint")
		width.MaxSize = Vector2.new(900, 100000)
		width.Parent = column
		local stack = Instance.new("UIListLayout")
		stack.Padding = UDim.new(0, Tokens.Spacing.gap)
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Parent = column
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, Tokens.Spacing.section)
		pad.PaddingBottom = UDim.new(0, Tokens.Spacing.section)
		pad.Parent = column

		local detaineeLabel = text(column, "IN HANDCUFFS", T.section, C.muted, true)
		detaineeLabel.LayoutOrder = 1
		detaineeLabel.Size = UDim2.new(1, 0, 0, 16)

		local detaineeRow = Instance.new("ScrollingFrame")
		detaineeRow.LayoutOrder = 2
		detaineeRow.Size = UDim2.new(1, 0, 0, 44)
		detaineeRow.BackgroundTransparency = 1
		detaineeRow.BorderSizePixel = 0
		detaineeRow.AutomaticCanvasSize = Enum.AutomaticSize.X
		detaineeRow.CanvasSize = UDim2.new()
		detaineeRow.ScrollingDirection = Enum.ScrollingDirection.X
		detaineeRow.ScrollBarThickness = Tokens.Scroll.barThickness
		detaineeRow.Parent = column
		local chipLayout = Instance.new("UIListLayout")
		chipLayout.FillDirection = Enum.FillDirection.Horizontal
		chipLayout.Padding = UDim.new(0, Tokens.Spacing.gap)
		chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
		chipLayout.Parent = detaineeRow
		self.detaineeRow = detaineeRow

		local detaineeEmpty = text(detaineeRow, "Nobody here is in handcuffs.", T.body, C.muted)
		detaineeEmpty.LayoutOrder = 0
		detaineeEmpty.Size = UDim2.fromOffset(320, 38)
		self.detaineeEmpty = detaineeEmpty

		local selectedLine = text(column, "Nobody selected.", T.body, C.muted)
		selectedLine.LayoutOrder = 3
		selectedLine.Size = UDim2.new(1, 0, 0, 20)
		selectedLine.TextTruncate = Enum.TextTruncate.AtEnd
		self.selectedLine = selectedLine

		local offenceLabel =
			text(column, "OFFENCES  ·  SELECT ALL THAT APPLY", T.section, C.muted, true)
		offenceLabel.LayoutOrder = 4
		offenceLabel.Size = UDim2.new(1, 0, 0, 30)
		offenceLabel.TextYAlignment = Enum.TextYAlignment.Bottom

		local offenceList = Instance.new("Frame")
		offenceList.LayoutOrder = 5
		offenceList.AutomaticSize = Enum.AutomaticSize.Y
		offenceList.Size = UDim2.fromScale(1, 0)
		offenceList.BackgroundTransparency = 1
		offenceList.Parent = column
		local offenceLayout = Instance.new("UIListLayout")
		offenceLayout.Padding = UDim.new(0, Tokens.Spacing.tight + 2)
		offenceLayout.SortOrder = Enum.SortOrder.LayoutOrder
		offenceLayout.Parent = offenceList
		self.offenceList = offenceList

		local totalLine = text(column, "TIME TO SERVE  ·  --:--", T.subtitle, C.muted, true)
		totalLine.LayoutOrder = 6
		totalLine.Size = UDim2.new(1, 0, 0, 30)
		self.totalLine = totalLine

		local reasonLabel = text(column, "GROUNDS AND CIRCUMSTANCES", T.section, C.muted, true)
		reasonLabel.LayoutOrder = 7
		reasonLabel.Size = UDim2.new(1, 0, 0, 26)
		reasonLabel.TextYAlignment = Enum.TextYAlignment.Bottom

		local reason = Instance.new("TextBox")
		reason.LayoutOrder = 8
		reason.Size = UDim2.new(1, 0, 0, 78)
		reason.BackgroundColor3 = C.raised
		reason.BorderSizePixel = 0
		reason.ClearTextOnFocus = false
		reason.Font = Tokens.Font.regular
		reason.MultiLine = true
		reason.PlaceholderText = "Why they were arrested and why custody is necessary"
		reason.PlaceholderColor3 = C.muted
		reason.Text = ""
		reason.TextColor3 = C.text
		reason.TextSize = T.body
		reason.TextWrapped = true
		reason.TextXAlignment = Enum.TextXAlignment.Left
		reason.TextYAlignment = Enum.TextYAlignment.Top
		reason.Parent = column
		local reasonPad = Instance.new("UIPadding")
		reasonPad.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
		reasonPad.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
		reasonPad.PaddingTop = UDim.new(0, Tokens.Spacing.gap)
		reasonPad.Parent = reason
		outline(reason)
		self.reason = reason

		local hint = text(column, "", T.dense, C.muted)
		hint.LayoutOrder = 9
		hint.Size = UDim2.new(1, 0, 0, 32)
		hint.TextWrapped = true
		self.hint = hint

		local book = button(column, "BOOK INTO CUSTODY", C.accentFill)
		book.LayoutOrder = 10
		book.Size = UDim2.new(1, 0, 0, 52)
		self.book = book
		table.insert(
			self.connections,
			book.Activated:Connect(function()
				if book.Active then
					self:_submitBooking()
				end
			end)
		)

		local notice = text(
			column,
			"Compressed simulation times. Roleplay only — not legal advice or professional training.",
			T.dense,
			C.muted
		)
		notice.LayoutOrder = 11
		notice.Size = UDim2.new(1, 0, 0, 32)
		notice.TextWrapped = true

		-- Connected last, because the summary it recomputes reads every control on
		-- the column and half of them do not exist until this point.
		table.insert(
			self.connections,
			reason:GetPropertyChangedSignal("Text"):Connect(function()
				self:_refreshSummary()
			end)
		)
	end
end
