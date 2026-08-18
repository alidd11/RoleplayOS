--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Tokens = require(script.Parent.Parent.UI.DesignTokens)
local C, T, S = Tokens.Colour, Tokens.Text, Tokens.Stroke

local CustodyController = {
	connections = {},
	targetUserId = nil,
	selectedCodes = {},
	policy = {},
	policyMetadata = {},
	chips = {},
}

-- What a refused custody request means, in words the player can act on.
--
-- Every refusal below used to reach the player as "Custody action was refused"
-- or "The custody booking could not be completed", which names the outcome and
-- withholds the only part that matters: whether to walk closer, write more, or
-- stop trying. The server already sends the reason as a Code beside the
-- message, so nothing new has to be asked for to say which it is.
local REFUSALS = {
	NOT_AUTHORISED = "Your role cannot process custody.",
	BOOKING_DESK_REQUIRED = "Stand at a custody desk with the detainee to book them.",
	TARGET_NOT_CUFFED = "The detainee has to be in handcuffs first.",
	TARGET_OUT_OF_RANGE = "Get closer to the detainee, with nothing between you.",
	TARGET_UNAVAILABLE = "That player cannot be dealt with right now.",
	GROUNDS_REQUIRED = "Write the grounds first — a few words is enough.",
	INVALID_GROUNDS = "Those grounds could not be read. Type them again.",
	TEXT_FILTER_UNAVAILABLE = "Roblox could not check that text. Try again in a moment.",
	CUSTODY_CELL_UNAVAILABLE = "This server has no custody cell, so nobody can be booked here.",
	CHARACTER_UNAVAILABLE = "The detainee has no character loaded to book.",
	PROFILE_UNAVAILABLE = "The detainee's save has not loaded yet.",
	NO_VALID_OFFENCES = "None of those offences were recognised.",
	HANDCUFFS_MUST_BE_EQUIPPED = "Hold your handcuffs before using them.",
	NOT_MANAGING_OFFICER = "Only the officer who put these cuffs on can take them off.",
	OFFICER_ALREADY_ESCORTING = "You already have hold of someone. Let go of them first.",
	ALREADY_ESCORTED = "Another officer already has hold of this detainee.",
	CUSTODY_SEAT_UNAVAILABLE = "No custody seat nearby. Bring a marked vehicle closer.",
	INVALID_SEARCH_POWER = "Choose a search power before recording the search.",
	INVALID_CUFF_MODE = "Those handcuffs were used in a way the server does not recognise.",
	INVALID_CUFF_POSITION = "The cuffs cannot go there.",
	INVALID_CUSTODY_ACTION = "That custody action no longer exists.",
	NO_ACTIVE_CUSTODY_SENTENCE = "You are not serving custody time.",
	NO_EARLY_RELEASE_CREDITS = "You have no early release credits left.",
	PUBLIC_SERVER_REQUIRED = "Early release is only offered on public servers.",
	NO_SESSION = "Your save has not loaded yet.",
	CIVILIAN_SPAWN_NOT_CONFIGURED = "This server has nowhere to release people to.",
	CIVILIAN_ROLE_ASSIGNMENT_FAILED = "You could not be put back on the street. Tell a moderator.",
	CIVILIAN_SPAWN_FAILED = "You could not be put back on the street. Tell a moderator.",
	CHARACTER_SPAWN_FAILED = "Your character could not be moved. Tell a moderator.",
}

-- Readable names for the search powers the server accepts. The detainee was
-- being told they had been searched under "PACE_S23_MDA", which is the wire
-- value and not a sentence anybody reads.
local SEARCH_POWERS = {
	PACE_S1 = "stop and search",
	PACE_S23_MDA = "drugs search powers",
	PACE_S32_POST_ARREST = "post-arrest search powers",
}

local function formatTime(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

local function text(
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

local function button(parent: Instance, value: string, fill: Color3): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = fill
	item.BorderSizePixel = 0
	item.Font = Tokens.Font.bold
	item.Text = value
	item.TextColor3 = C.text
	item.TextSize = T.button
	item.Parent = parent
	return item
end

local function outline(parent: Instance, colour: Color3?): UIStroke
	local item = Instance.new("UIStroke")
	item.Color = colour or C.border
	item.Thickness = S.thickness
	item.Transparency = S.transparency
	item.Parent = parent
	return item
end

-- Distance in whole metres between the local character and another player's, or
-- nil when either of them has no character loaded. Roblox studs are close enough
-- to metres for a number an officer only uses to decide whether to walk forward.
local function distanceTo(player: Player): number?
	local localCharacter = Players.LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root or not localRoot:IsA("BasePart") or not root:IsA("BasePart") then
		return nil
	end
	return math.floor((localRoot.Position - root.Position).Magnitude + 0.5)
end

function CustodyController:Init(context: any)
	self.context = context
end

-- The one place that turns a refused custody response into something to do
-- about it. PublicSafetyController runs the restraint actions and this file runs
-- the booking, and the two must not be able to describe the same refusal
-- differently, so the table lives here and that controller asks for it.
function CustodyController:Explain(response: any, fallback: string): string
	if type(response) ~= "table" then
		return fallback
	end
	local explained = REFUSALS[tostring(response.Code)]
	if explained then
		return explained
	end
	return if type(response.Message) == "string" and response.Message ~= ""
		then response.Message
		else fallback
end

function CustodyController:_notify(message: string, title: string, level: string?)
	self.context.Controllers.NotificationController:Show(message, title, level)
end

function CustodyController:_selectedCodeList(): { string }
	local result = {}
	for code, selected in self.selectedCodes do
		if selected then
			table.insert(result, code)
		end
	end
	table.sort(result)
	return result
end

function CustodyController:_selectedSeconds(): number
	local total = 0
	for _, offence in self.policy do
		if self.selectedCodes[offence.Code] then
			total += math.max(0, tonumber(offence.Seconds) or 0)
		end
	end
	return total
end

-- Every player the local client can see wearing handcuffs, nearest first.
--
-- The picker used to list the whole server, which meant the officer chose from
-- a column of names of which at most one could legally be booked and nothing
-- said which. Cuffed state is a replicated attribute, so the client can show
-- only the people this screen is actually about.
function CustodyController:_detainees(): { Player }
	local found = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player:GetAttribute("RoleplayOSCuffed") == true then
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
	local target = if self.targetUserId then Players:GetPlayerByUserId(self.targetUserId) else nil
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
		self.hint.Text = "No offence selected. Booking now records this as Other recorded offence."
		self.hint.TextColor3 = C.muted
	elseif self.policyMetadata.BookingDeskRequired then
		self.hint.Text = "Ready. You and the detainee both have to be standing at a custody desk."
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
		self:_notify("Only an officer on duty can book somebody into custody.", "Custody", "Danger")
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

-- What is happening to the player it is happening to.
--
-- A detainee previously got nothing at all: the cuff event the server sends them
-- was never handled here, so the whole experience of being arrested was a
-- character that stopped answering the controls, with no statement anywhere on
-- screen of who had done it, whether it would end, or what they could do. That
-- is the single most likely moment for somebody to close the game, so it is the
-- one screen in this file that is never optional.
function CustodyController:_mountStatus()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCustodyStatus"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 22
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.statusGui = gui

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.fromOffset(468, 104)
	banner.BackgroundColor3 = C.surface
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	outline(banner)
	self.statusBanner = banner
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	self.statusScale = bannerScale

	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.BackgroundColor3 = C.accent
	rule.BorderSizePixel = 0
	rule.Parent = banner
	self.statusRule = rule

	local kind = text(banner, "IN HANDCUFFS", T.section, C.accent, true)
	kind.Position = UDim2.fromOffset(Tokens.Spacing.pad, 12)
	kind.Size = UDim2.new(1, -180, 0, 14)
	self.statusKind = kind

	local headline = text(banner, "", T.subtitle, C.text, true)
	headline.Position = UDim2.fromOffset(Tokens.Spacing.pad, 30)
	headline.Size = UDim2.new(1, -180, 0, 20)
	headline.TextTruncate = Enum.TextTruncate.AtEnd
	self.statusHeadline = headline

	local detail = text(banner, "", T.dense, C.muted)
	detail.Position = UDim2.fromOffset(Tokens.Spacing.pad, 52)
	detail.Size = UDim2.new(1, -180, 0, 40)
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	self.statusDetail = detail

	local clock = text(banner, "00:00", 26, C.accent, true)
	clock.AnchorPoint = Vector2.new(1, 0)
	clock.Position = UDim2.new(1, -Tokens.Spacing.pad, 0, 14)
	clock.Size = UDim2.fromOffset(148, 32)
	clock.TextXAlignment = Enum.TextXAlignment.Right
	self.statusClock = clock

	local earlyRelease = button(banner, "EARLY RELEASE", C.accentFill)
	earlyRelease.AnchorPoint = Vector2.new(1, 0)
	earlyRelease.Position = UDim2.new(1, -Tokens.Spacing.pad, 0, 52)
	earlyRelease.Size = UDim2.fromOffset(148, 32)
	earlyRelease.TextSize = T.dense
	earlyRelease.Visible = false
	self.earlyRelease = earlyRelease

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, 3)
	track.BackgroundColor3 = C.raised
	track.BorderSizePixel = 0
	track.Visible = false
	track.Parent = banner
	self.statusTrack = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	self.statusFill = fill

	table.insert(
		self.connections,
		earlyRelease.Activated:Connect(function()
			self:_useEarlyRelease()
		end)
	)
end

function CustodyController:_useEarlyRelease()
	local credits = math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
	if credits > 0 then
		local response =
			self.context.Controllers.NetworkController:Request("UseEarlyReleaseCredit", {})
		if response.Data then
			self.policyMetadata = response.Data
		end
		if response.Success then
			self:_announceRelease(
				"Released early. Your criminal record still shows the booking.",
				"Released"
			)
		else
			self:_notify(
				self:Explain(response, "The release credit could not be used."),
				"Custody",
				"Danger"
			)
		end
		self:_updateStatus()
		return
	end
	local product = (self.policyMetadata.EarlyReleaseProducts or {})[1]
	local productId = tonumber(product and product.ProductId) or 0
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	else
		self:_notify("Early release is not on sale on this server.", "Custody")
	end
end

function CustodyController:_refreshPolicyMetadata()
	local response = self.context.Controllers.NetworkController:Request("GetCustodyPolicy", {})
	if response.Success and response.Data then
		self.policy = response.Data.Offences or {}
		self.policyMetadata = response.Data
	end
end

-- Both halves of a release can reach the client, in either order: the sentence
-- attribute drops to zero and, for a credit, a CustodyChanged event explains
-- why. Whichever arrives first speaks and the other stays quiet, so a player is
-- told once and told the more specific of the two things.
function CustodyController:_announceRelease(message: string, title: string)
	local now = os.clock()
	if self.releaseAnnouncedAt and now - self.releaseAnnouncedAt < 3 then
		return
	end
	self.releaseAnnouncedAt = now
	self:_notify(message, title, "Success")
end

function CustodyController:_updateStatus()
	local player = Players.LocalPlayer
	local remaining =
		math.max(0, math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0))
	local serving = remaining > 0
	local cuffed = player:GetAttribute("RoleplayOSCuffed") == true
	local escorted = player:GetAttribute("RoleplayOSEscorted") == true
	self.statusBanner.Visible = serving or cuffed
	if not self.statusBanner.Visible then
		self.peakRemaining = 0
		return
	end

	if serving then
		self.peakRemaining = math.max(self.peakRemaining or 0, remaining)
		self.statusKind.Text = "IN CUSTODY"
		self.statusKind.TextColor3 = C.accent
		self.statusRule.BackgroundColor3 = C.accent
		self.statusHeadline.Text = "You are in the cells"
		self.statusDetail.Text = "You are let out automatically when this reaches zero. "
			.. "Leaving the server does not shorten it."
		self.statusClock.Visible = true
		self.statusClock.Text = formatTime(remaining)
		self.statusTrack.Visible = true
		local peak = math.max(self.peakRemaining or remaining, 1)
		self.statusFill.Size = UDim2.fromScale(math.clamp(1 - remaining / peak, 0, 1), 1)
	else
		self.peakRemaining = 0
		self.statusKind.Text = "IN HANDCUFFS"
		self.statusKind.TextColor3 = C.warning
		self.statusRule.BackgroundColor3 = C.warning
		self.statusHeadline.Text = if self.detainedByName
			then "Detained by " .. self.detainedByName
			else "You have been detained"
		self.statusDetail.Text = if escorted
			then "An officer is walking you. You cannot move or get out of a vehicle "
				.. "until they let go, take the cuffs off, or book you in."
			else "You cannot run or jump. An officer has to take the cuffs off or book "
				.. "you into custody before you can move freely again."
		self.statusClock.Visible = false
		self.statusTrack.Visible = false
	end

	local credits = math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
	local single = (self.policyMetadata.EarlyReleaseProducts or {})[1]
	self.earlyRelease.Visible = serving and self.policyMetadata.ServerKind == "Public"
	self.earlyRelease.Text = if credits > 0
		then string.format("USE CREDIT  ·  %d", credits)
		else string.format(
			"BUY RELEASE  ·  %d R$",
			tonumber(single and single.PriceRobux) or 19
		)

	local wide = if serving then -180 else -Tokens.Spacing.pad * 2
	self.statusKind.Size = UDim2.new(1, wide, 0, 14)
	self.statusHeadline.Size = UDim2.new(1, wide, 0, 20)
	self.statusDetail.Size = UDim2.new(1, wide, 0, 40)
end

-- Announces the transitions rather than only the state, because a banner
-- appearing at the top of the screen is easy to miss at the exact moment the
-- player is trying to work out why their character has stopped moving.
function CustodyController:_watchDetention()
	local player = Players.LocalPlayer
	local function react()
		local remaining = math.max(
			0,
			math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0)
		)
		local cuffed = player:GetAttribute("RoleplayOSCuffed") == true
		local previousRemaining = self.lastRemaining
		local previousCuffed = self.lastCuffed
		self.lastRemaining = remaining
		self.lastCuffed = cuffed
		if cuffed then
			self.lastCuffedAt = os.clock()
		end
		-- A sentence that starts moments after this character was in handcuffs is
		-- a booking that just happened; one that starts without that is this
		-- character rejoining partway through time it was already serving. The
		-- two need opposite wording, and the cuffs coming off and the sentence
		-- appearing can replicate in either order, so the timestamp decides
		-- rather than the current value of the cuffed attribute.
		local justBooked = cuffed
			or (self.lastCuffedAt ~= nil and os.clock() - self.lastCuffedAt < 5)

		if cuffed and previousCuffed == false then
			self:_notify(
				if self.detainedByName
					then self.detainedByName
						.. " has put you in handcuffs. You cannot move away until an officer "
						.. "takes them off or books you into custody."
					else "You have been put in handcuffs. You cannot move away until an officer "
						.. "takes them off or books you into custody.",
				"Detained",
				"Danger"
			)
		elseif previousCuffed == true and not cuffed then
			-- Deferred by a frame: booking takes the cuffs off and starts a sentence
			-- in the same server call, and telling somebody they are free to go
			-- immediately before locking them in a cell is worse than saying nothing.
			task.defer(function()
				local serving = math.max(
					0,
					math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0)
				) > 0
				if not serving then
					self.detainedByName = nil
					self:_notify(
						"The handcuffs are off. You are free to go.",
						"Released",
						"Success"
					)
				end
			end)
		end

		if remaining > 0 and (previousRemaining == nil or previousRemaining == 0) then
			self.detainedByName = nil
			self:_notify(
				if justBooked
					then string.format(
						"You have been booked into custody and moved to a cell. %s to serve.",
						formatTime(remaining)
					)
					else string.format(
						"You are still serving custody time from earlier. %s left.",
						formatTime(remaining)
					),
				"In custody",
				"Danger"
			)
		elseif previousRemaining ~= nil and previousRemaining > 0 and remaining == 0 then
			-- Slightly behind the attribute, so a credit release gets to explain
			-- itself first. The two arrive on different channels and their order is
			-- not guaranteed.
			task.delay(0.35, function()
				self:_announceRelease(
					"You have served your time and been let out of the cells.",
					"Released"
				)
			end)
		end
		self:_updateStatus()
	end
	for _, attribute in { "RoleplayOSCustodyRemaining", "RoleplayOSCuffed", "RoleplayOSEscorted" } do
		table.insert(self.connections, player:GetAttributeChangedSignal(attribute):Connect(react))
	end
	react()
end

function CustodyController:Start()
	self.bookingGeneration = 0
	self.peakRemaining = 0
	self:_mountStatus()
	self:_mountBooking()
	-- Deferred: the serial client Start sequence must not block on an endpoint
	-- the server may not have registered yet.
	task.spawn(function()
		self:_refreshPolicyMetadata()
		self:_refreshPolicy()
		self:_updateStatus()
		self:_refreshSummary()
	end)

	self:_watchDetention()
	self:_refreshAccess(nil)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function(duty)
			self:_refreshAccess(duty)
		end)
	)
	-- Booking describes a person standing in front of this character. Losing the
	-- character ends that, and leaving the screen up over a respawn left an
	-- officer looking at a form whose every button the server would refuse.
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			self:_closeBooking()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			self:_closeBooking()
		end)
	)
	-- Credits bought from the banner arrive through Roblox rather than through
	-- our own reply, so the button relabels itself from a fresh policy read
	-- instead of staying on the price of something already paid for.
	table.insert(
		self.connections,
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
			if purchased and userId == Players.LocalPlayer.UserId then
				task.spawn(function()
					self:_refreshPolicyMetadata()
					self:_updateStatus()
				end)
			end
		end)
	)

	local remote = self.context.Controllers.NetworkController:ResolveEvent("CustodyChanged")
	if remote then
		table.insert(
			self.connections,
			remote.OnClientEvent:Connect(function(payload)
				if type(payload) ~= "table" then
					return
				end
				if payload.Kind == "State" then
					-- The only message that names the officer. It arrives with the cuffs,
					-- and going unhandled was why the arrest had no author.
					local officer = if payload.State
						then Players:GetPlayerByUserId(tonumber(payload.State.OfficerUserId) or 0)
						else nil
					self.detainedByName = if officer then officer.DisplayName else nil
					self:_updateStatus()
				elseif payload.Kind == "Caution" then
					self.context.Controllers.NotificationController:Show(
						payload.Text .. "\n\n" .. payload.SimulationNotice,
						"Arrest caution"
					)
				elseif payload.Kind == "SearchNotice" then
					local power = SEARCH_POWERS[tostring(payload.Power)]
					self.context.Controllers.NotificationController:Show(
						if power
							then "An officer has searched you under " .. power .. "."
							else "An officer has recorded a search of you.",
						"Searched"
					)
				elseif payload.Kind == "EarlyRelease" then
					self.policyMetadata.EarlyReleaseCredits = payload.Credits or 0
					self:_announceRelease(
						"Released early. Your criminal record still shows the booking.",
						"Released"
					)
					self:_updateStatus()
				end
			end)
		)
	end

	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Custody", function(layout)
		self.statusScale.Scale = math.min(
			layout.HudScale,
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(468, 104), 20)
		)
		-- This interface is mounted with CoreUISafeInsets, so its own origin is
		-- already below the native top bar. Adding NativeTop again pushed the
		-- banner a whole top bar further down the screen.
		self.statusBanner.Position = UDim2.new(0.5, 0, 0, 10)
	end)
end

function CustodyController:Destroy()
	self.bookingGeneration = (self.bookingGeneration or 0) + 1
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.chips)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.bookingGui then
		self.bookingGui:Destroy()
		self.bookingGui = nil
	end
	if self.statusGui then
		self.statusGui:Destroy()
		self.statusGui = nil
	end
end

return CustodyController
