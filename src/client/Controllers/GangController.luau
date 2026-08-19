--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)
local GangRules = require(ReplicatedStorage.RoleplayOS.Shared.GangRules)
local Tokens = require(script.Parent.Parent.UI.DesignTokens)
local C, T, S = Tokens.Colour, Tokens.Text, Tokens.Stroke

-- The one place a player reaches gang membership from. Everything else the
-- gang system spec describes -- territory, income, the vehicle spawner -- is
-- server-side and already live; nothing before this file could see any of it,
-- because there was no client controller calling GetGangStatus, CreateGang,
-- InviteToGang, RespondToGangInvite or LeaveGang anywhere in src/client.
--
-- No role gates this the way CustodyController gates on being on duty as
-- police: a gang is a civilian feature, so the panel opens for anyone and the
-- one real gate -- owning GangSystemAccess -- is enforced server-side and
-- surfaced here as a refusal with a purchase prompt, the same way
-- VendorController turns a refused gamepass item into a prompt rather than a
-- dead end.
local GANG_ACTION = "RoleplayOSToggleGangPanel"

-- How often the panel re-reads GetGangStatus while it is open. There is no
-- push event for an invite arriving or a member joining, so this is the same
-- polling idiom CustodyController's _startBookingRefresh uses for a screen
-- that can go stale while it sits open -- read on a slow timer rather than
-- once at open time.
local REFRESH_INTERVAL_SECONDS = 4

local GangController = {
	connections = {},
	targetUserId = nil :: number?,
	chips = {} :: { [number]: TextButton },
	status = nil :: any,
}

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

-- Distance in whole metres between the local character and another player's,
-- or nil when either has no character loaded. Same measure CustodyController
-- uses to sort its detainee picker.
local function distanceTo(player: Player): number?
	local localCharacter = Players.LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root or not localRoot:IsA("BasePart") or not root:IsA("BasePart") then
		return nil
	end
	return math.floor((localRoot.Position - root.Position).Magnitude + 0.5)
end

function GangController:Init(context: any)
	self.context = context
end

function GangController:_notify(message: string, title: string?, level: string?)
	self.context.Controllers.NotificationController:Show(message, title or "Gang", level)
end

-- Every online player who could still be invited: not the local player, and
-- not already a member of the gang the local player leads. Nearest first, the
-- same ordering CustodyController's detainee picker uses so the likeliest
-- target is the one already selected.
function GangController:_invitablePlayers(): { Player }
	local gang = self.status and self.status.Gang
	local memberIds: { [number]: boolean } = {}
	if gang then
		memberIds[gang.LeaderUserId] = true
		for _, memberId in gang.MemberUserIds do
			memberIds[memberId] = true
		end
	end
	local found = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and not memberIds[player.UserId] then
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

function GangController:_paintChips()
	for userId, chip in self.chips do
		local selected = userId == self.targetUserId
		chip.BackgroundColor3 = if selected then C.accentFill else C.raised
		chip.TextColor3 = if selected then C.text else C.muted
	end
end

function GangController:_refreshTargets()
	local players = self:_invitablePlayers()
	local present: { [number]: boolean } = {}
	for order, player in players do
		present[player.UserId] = true
		local chip = self.chips[player.UserId]
		if not chip then
			chip = button(self.targetRow, "", C.raised)
			chip.Name = tostring(player.UserId)
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.Size = UDim2.fromOffset(0, 38)
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
			padding.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
			padding.Parent = chip
			outline(chip)
			self.chips[player.UserId] = chip
			-- Not tracked in self.connections, same reasoning as CustodyController's
			-- chip row: chips are rebuilt every refresh as players come and go, and
			-- destroying the chip disconnects this.
			chip.Activated:Connect(function()
				self.targetUserId = player.UserId
				self:_paintChips()
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
	self.targetEmpty.Visible = #players == 0
	self:_paintChips()
	return #players
end

function GangController:_clearList(list: Instance)
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- A single row inside the members list: name, and LEADER if that member is
-- the one who founded the gang. Nothing here is interactive -- rank and kick
-- tooling is not part of this pass, the same way leadership transfer is not
-- built server-side yet (GangService:Leave disbands rather than handing over).
function GangController:_memberRow(
	parent: Instance,
	userId: number,
	isLeader: boolean,
	order: number
)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local player = Players:GetPlayerByUserId(userId)
	local name = text(
		row,
		if player then player.DisplayName else string.format("Player %d", userId),
		T.body,
		C.text
	)
	name.Size = UDim2.new(1, -100, 1, 0)
	if isLeader then
		local tag = text(row, "LEADER", T.dense, C.accent, true)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.fromScale(1, 0.5)
		tag.Size = UDim2.fromOffset(80, 18)
		tag.TextXAlignment = Enum.TextXAlignment.Right
	end
end

function GangController:_inviteRow(parent: Instance, invite: any, order: number)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = C.raised
	row.BorderSizePixel = 0
	row.Parent = parent
	outline(row)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
	pad.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
	pad.Parent = row
	local name = text(row, tostring(invite.GangName), T.body, C.text, true)
	name.Position = UDim2.fromOffset(0, 8)
	name.Size = UDim2.new(1, -170, 0, 20)
	local by = Players:GetPlayerByUserId(tonumber(invite.InvitedByUserId) or 0)
	local sub = text(
		row,
		if by then "Invited by " .. by.DisplayName else "Invited by a gang leader",
		T.dense,
		C.muted
	)
	sub.Position = UDim2.fromOffset(0, 30)
	sub.Size = UDim2.new(1, -170, 0, 16)

	local accept = button(row, "ACCEPT", C.accentFill)
	accept.AnchorPoint = Vector2.new(1, 0.5)
	accept.Position = UDim2.fromScale(1, 0.5)
	accept.Size = UDim2.fromOffset(76, 32)
	accept.TextSize = T.dense
	accept.Activated:Connect(function()
		self:_respondInvite(invite.GangId, true)
	end)

	local decline = button(row, "DECLINE", C.raised)
	decline.AnchorPoint = Vector2.new(1, 0.5)
	decline.Position = UDim2.new(1, -84, 0.5, 0)
	decline.Size = UDim2.fromOffset(80, 32)
	decline.TextSize = T.dense
	outline(decline)
	decline.Activated:Connect(function()
		self:_respondInvite(invite.GangId, false)
	end)
end

-- Redraws the whole panel from the last GetGangStatus read. Called after
-- every refresh and after every action, rather than patched incrementally --
-- the panel is small enough that a full rebuild is cheap and cannot drift
-- from what the server actually said.
function GangController:_render()
	local status = self.status
	local gang = status and status.Gang
	local invites = (status and status.Invites) or {}
	local isLeader = gang ~= nil and gang.LeaderUserId == Players.LocalPlayer.UserId

	self.createSection.Visible = gang == nil
	self.gangSection.Visible = gang ~= nil
	self.inviteSection.Visible = isLeader
	self.leaveButton.Visible = gang ~= nil

	if gang then
		self.gangName.Text = string.upper(tostring(gang.Name))
		local leader = Players:GetPlayerByUserId(gang.LeaderUserId)
		local memberCount = #gang.MemberUserIds + 1
		self.gangMeta.Text = string.format(
			"%d / %d MEMBERS  ·  LED BY %s",
			memberCount,
			GangRules.MaximumMembers,
			if leader then string.upper(leader.DisplayName) else "SOMEONE OFFLINE"
		)
		local territoryName = status and status.TerritoryName
		self.gangTerritory.Text = if type(territoryName) == "string"
				and territoryName ~= ""
			then "HOLDING TERRITORY  ·  " .. string.upper(territoryName)
			else "NO TERRITORY HELD"
		self.gangTerritory.TextColor3 = if territoryName then C.accent else C.muted

		self:_clearList(self.membersList)
		self:_memberRow(self.membersList, gang.LeaderUserId, true, 1)
		for order, memberId in gang.MemberUserIds do
			self:_memberRow(self.membersList, memberId, false, order + 1)
		end
	end

	self:_clearList(self.invitesList)
	self.invitesEmpty.Visible = #invites == 0
	for order, invite in invites do
		self:_inviteRow(self.invitesList, invite, order)
	end

	if isLeader then
		self:_refreshTargets()
	end
end

function GangController:_refreshStatus()
	local response = self.context.Controllers.NetworkController:Request("GetGangStatus", {})
	if not response.Success then
		if response.Code ~= "ENDPOINT_UNAVAILABLE" then
			self:_notify(
				response.Message or "Your gang status could not be read.",
				"Gang",
				"Danger"
			)
		end
		return
	end
	self.status = response.Data
	self:_render()
end

function GangController:_startRefreshLoop()
	self.refreshGeneration = (self.refreshGeneration or 0) + 1
	local generation = self.refreshGeneration
	task.spawn(function()
		while self.refreshGeneration == generation and self.gui and self.gui.Enabled do
			self:_refreshStatus()
			task.wait(REFRESH_INTERVAL_SECONDS)
		end
	end)
end

function GangController:_submitCreate()
	local name = string.match(self.nameInput.Text, "^%s*(.-)%s*$") or ""
	if #name < GangRules.MinimumNameLength or #name > GangRules.MaximumNameLength then
		self:_notify(
			string.format(
				"Gang names are %d-%d characters.",
				GangRules.MinimumNameLength,
				GangRules.MaximumNameLength
			),
			"Gang"
		)
		return
	end
	self.createButton.Active = false
	self.createButton.Text = "CREATING…"
	local response = self.context.Controllers.NetworkController:Request("CreateGang", {
		Name = name,
	})
	self.createButton.Active = true
	self.createButton.Text = "CREATE GANG"
	if not response.Success then
		if response.Code == "GANG_PASS_REQUIRED" then
			-- The server refuses this the same way a vendor refuses an unowned
			-- gamepass item: it names the reason rather than a dead end, and the
			-- purchase prompt is the one thing this file can do about it.
			local gamepassId = tonumber(Config.Gamepasses.GangSystemAccess.GamepassId)
			self:_notify(
				(response.Message or "Gang System Access is required to do that.")
					.. " Complete the purchase, then try again.",
				"Gang",
				"Danger"
			)
			if gamepassId and gamepassId > 0 then
				self.context.Controllers.GamepassController:Prompt(gamepassId)
			end
			return
		end
		self:_notify(response.Message or "The gang could not be created.", "Gang", "Danger")
		return
	end
	self.nameInput.Text = ""
	self:_notify(string.format("%s has been founded.", name), "Gang", "Success")
	self:_refreshStatus()
end

function GangController:_submitInvite()
	if not self.targetUserId then
		self:_notify("Choose a player to invite.", "Gang")
		return
	end
	self.inviteButton.Active = false
	self.inviteButton.Text = "INVITING…"
	local response = self.context.Controllers.NetworkController:Request("InviteToGang", {
		TargetUserId = self.targetUserId,
	})
	self.inviteButton.Active = true
	self.inviteButton.Text = "SEND INVITE"
	if not response.Success then
		self:_notify(response.Message or "The invite could not be sent.", "Gang", "Danger")
		return
	end
	local target = Players:GetPlayerByUserId(self.targetUserId)
	self:_notify(
		string.format("Invite sent to %s.", if target then target.DisplayName else "that player"),
		"Gang",
		"Success"
	)
end

function GangController:_respondInvite(gangId: string, accept: boolean)
	local response = self.context.Controllers.NetworkController:Request("RespondToGangInvite", {
		GangId = gangId,
		Accept = accept,
	})
	if not response.Success then
		self:_notify(response.Message or "The invite could not be answered.", "Gang", "Danger")
		return
	end
	self:_notify(
		if accept then "You have joined the gang." else "Invite declined.",
		"Gang",
		if accept then "Success" else nil
	)
	self:_refreshStatus()
end

function GangController:_submitLeave()
	local gang = self.status and self.status.Gang
	if not gang then
		return
	end
	local isLeader = gang.LeaderUserId == Players.LocalPlayer.UserId
	self.leaveButton.Active = false
	local response = self.context.Controllers.NetworkController:Request("LeaveGang", {})
	self.leaveButton.Active = true
	if not response.Success then
		self:_notify(response.Message or "The gang could not be left.", "Gang", "Danger")
		return
	end
	self:_notify(
		if isLeader
			then "The gang has been disbanded."
			else response.Message or "You have left the gang.",
		"Gang"
	)
	self:_refreshStatus()
end

function GangController:_open()
	if not self.gui then
		return
	end
	self.gui.Enabled = true
	self:_refreshStatus()
	self:_startRefreshLoop()
end

function GangController:_close()
	if self.gui then
		self.gui.Enabled = false
	end
	self.refreshGeneration = (self.refreshGeneration or 0) + 1
end

function GangController:_toggle()
	if not self.gui then
		return
	end
	if self.gui.Enabled then
		self:_close()
	else
		self:_open()
	end
end

function GangController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSGangPanel"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	-- Same band as CustodyController's booking screen: above the HUD, below
	-- the start menu, and this panel is never open at the same time as that
	-- one so their sharing DisplayOrder territory does not matter.
	gui.DisplayOrder = 45
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

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

	local title = text(header, "GANG", T.title, C.text, true)
	title.Position = UDim2.fromOffset(28, 18)
	title.Size = UDim2.new(1, -120, 0, 32)
	local subtitle =
		text(header, "Found a gang, invite members and hold territory", T.body, C.muted)
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
			self:_close()
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

	-- CREATE A GANG. Only shown when GetGangStatus reports no gang.
	local createSection = Instance.new("Frame")
	createSection.LayoutOrder = 1
	createSection.AutomaticSize = Enum.AutomaticSize.Y
	createSection.Size = UDim2.fromScale(1, 0)
	createSection.BackgroundTransparency = 1
	createSection.Parent = column
	self.createSection = createSection
	local createStack = Instance.new("UIListLayout")
	createStack.Padding = UDim.new(0, Tokens.Spacing.gap)
	createStack.SortOrder = Enum.SortOrder.LayoutOrder
	createStack.Parent = createSection

	local createLabel = text(createSection, "FOUND A GANG", T.section, C.muted, true)
	createLabel.LayoutOrder = 1
	createLabel.Size = UDim2.new(1, 0, 0, 16)

	local nameInput = Instance.new("TextBox")
	nameInput.LayoutOrder = 2
	nameInput.Size = UDim2.new(1, 0, 0, 44)
	nameInput.BackgroundColor3 = C.raised
	nameInput.BorderSizePixel = 0
	nameInput.ClearTextOnFocus = false
	nameInput.Font = Tokens.Font.regular
	nameInput.PlaceholderText = "Gang name"
	nameInput.PlaceholderColor3 = C.muted
	nameInput.Text = ""
	nameInput.TextColor3 = C.text
	nameInput.TextSize = T.body
	nameInput.TextXAlignment = Enum.TextXAlignment.Left
	nameInput.Parent = createSection
	local namePad = Instance.new("UIPadding")
	namePad.PaddingLeft = UDim.new(0, Tokens.Spacing.inset)
	namePad.PaddingRight = UDim.new(0, Tokens.Spacing.inset)
	namePad.Parent = nameInput
	outline(nameInput)
	self.nameInput = nameInput

	local createButton = button(createSection, "CREATE GANG", C.accentFill)
	createButton.LayoutOrder = 3
	createButton.Size = UDim2.new(1, 0, 0, 48)
	self.createButton = createButton
	table.insert(
		self.connections,
		createButton.Activated:Connect(function()
			if createButton.Active then
				self:_submitCreate()
			end
		end)
	)

	local createNotice = text(
		createSection,
		string.format(
			"Requires %s. One purchase covers the whole gang.",
			Config.Gamepasses.GangSystemAccess.Name
		),
		T.dense,
		C.muted
	)
	createNotice.LayoutOrder = 4
	createNotice.Size = UDim2.new(1, 0, 0, 16)

	-- YOUR GANG. Only shown when GetGangStatus reports a gang.
	local gangSection = Instance.new("Frame")
	gangSection.LayoutOrder = 2
	gangSection.AutomaticSize = Enum.AutomaticSize.Y
	gangSection.Size = UDim2.fromScale(1, 0)
	gangSection.BackgroundTransparency = 1
	gangSection.Parent = column
	self.gangSection = gangSection
	local gangStack = Instance.new("UIListLayout")
	gangStack.Padding = UDim.new(0, Tokens.Spacing.tight + 2)
	gangStack.SortOrder = Enum.SortOrder.LayoutOrder
	gangStack.Parent = gangSection

	local gangName = text(gangSection, "", T.subtitle, C.text, true)
	gangName.LayoutOrder = 1
	gangName.Size = UDim2.new(1, 0, 0, 22)
	self.gangName = gangName

	local gangMeta = text(gangSection, "", T.dense, C.muted)
	gangMeta.LayoutOrder = 2
	gangMeta.Size = UDim2.new(1, 0, 0, 16)
	self.gangMeta = gangMeta

	local gangTerritory = text(gangSection, "", T.dense, C.muted, true)
	gangTerritory.LayoutOrder = 3
	gangTerritory.Size = UDim2.new(1, 0, 0, 18)
	self.gangTerritory = gangTerritory

	local membersLabel = text(gangSection, "MEMBERS", T.section, C.muted, true)
	membersLabel.LayoutOrder = 4
	membersLabel.Size = UDim2.new(1, 0, 0, 26)
	membersLabel.TextYAlignment = Enum.TextYAlignment.Bottom

	local membersList = Instance.new("Frame")
	membersList.LayoutOrder = 5
	membersList.AutomaticSize = Enum.AutomaticSize.Y
	membersList.Size = UDim2.fromScale(1, 0)
	membersList.BackgroundTransparency = 1
	membersList.Parent = gangSection
	local membersLayout = Instance.new("UIListLayout")
	membersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	membersLayout.Parent = membersList
	self.membersList = membersList

	-- INVITE A PLAYER. Only shown to the leader -- GangService:Invite refuses
	-- anyone else server-side, and showing the picker to a member who cannot
	-- use it would just be a button that always answers NOT_THE_LEADER.
	local inviteSection = Instance.new("Frame")
	inviteSection.LayoutOrder = 3
	inviteSection.AutomaticSize = Enum.AutomaticSize.Y
	inviteSection.Size = UDim2.fromScale(1, 0)
	inviteSection.BackgroundTransparency = 1
	inviteSection.Parent = column
	self.inviteSection = inviteSection
	local inviteStack = Instance.new("UIListLayout")
	inviteStack.Padding = UDim.new(0, Tokens.Spacing.gap)
	inviteStack.SortOrder = Enum.SortOrder.LayoutOrder
	inviteStack.Parent = inviteSection

	local inviteLabel = text(inviteSection, "INVITE A PLAYER", T.section, C.muted, true)
	inviteLabel.LayoutOrder = 1
	inviteLabel.Size = UDim2.new(1, 0, 0, 16)

	local targetRow = Instance.new("ScrollingFrame")
	targetRow.LayoutOrder = 2
	targetRow.Size = UDim2.new(1, 0, 0, 44)
	targetRow.BackgroundTransparency = 1
	targetRow.BorderSizePixel = 0
	targetRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	targetRow.CanvasSize = UDim2.new()
	targetRow.ScrollingDirection = Enum.ScrollingDirection.X
	targetRow.ScrollBarThickness = Tokens.Scroll.barThickness
	targetRow.Parent = inviteSection
	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.Padding = UDim.new(0, Tokens.Spacing.gap)
	targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
	targetLayout.Parent = targetRow
	self.targetRow = targetRow

	local targetEmpty = text(targetRow, "Nobody else is on this server.", T.body, C.muted)
	targetEmpty.LayoutOrder = 0
	targetEmpty.Size = UDim2.fromOffset(320, 38)
	self.targetEmpty = targetEmpty

	local inviteButton = button(inviteSection, "SEND INVITE", C.accentFill)
	inviteButton.LayoutOrder = 3
	inviteButton.Size = UDim2.new(1, 0, 0, 48)
	self.inviteButton = inviteButton
	table.insert(
		self.connections,
		inviteButton.Activated:Connect(function()
			if inviteButton.Active then
				self:_submitInvite()
			end
		end)
	)

	-- PENDING INVITES. Always in the layout -- a player who is not in a gang
	-- can still be sitting on an invite, which is the one case this screen
	-- must show something even before FOUND A GANG has been used.
	local invitesLabel = text(column, "PENDING INVITES", T.section, C.muted, true)
	invitesLabel.LayoutOrder = 4
	invitesLabel.Size = UDim2.new(1, 0, 0, 26)
	invitesLabel.TextYAlignment = Enum.TextYAlignment.Bottom

	local invitesList = Instance.new("Frame")
	invitesList.LayoutOrder = 5
	invitesList.AutomaticSize = Enum.AutomaticSize.Y
	invitesList.Size = UDim2.fromScale(1, 0)
	invitesList.BackgroundTransparency = 1
	invitesList.Parent = column
	local invitesLayout = Instance.new("UIListLayout")
	invitesLayout.Padding = UDim.new(0, Tokens.Spacing.tight + 2)
	invitesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	invitesLayout.Parent = invitesList
	self.invitesList = invitesList

	local invitesEmpty = text(invitesList, "No invites waiting.", T.body, C.muted)
	invitesEmpty.LayoutOrder = 0
	invitesEmpty.Size = UDim2.new(1, 0, 0, 20)
	self.invitesEmpty = invitesEmpty

	local leaveButton = button(column, "LEAVE GANG", C.danger)
	leaveButton.LayoutOrder = 6
	leaveButton.Size = UDim2.new(1, 0, 0, 48)
	self.leaveButton = leaveButton
	table.insert(
		self.connections,
		leaveButton.Activated:Connect(function()
			if leaveButton.Active then
				self:_submitLeave()
			end
		end)
	)
end

function GangController:Start()
	self.refreshGeneration = 0
	self:_mount()
	self:_render()

	ContextActionService:BindAction(GANG_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		self:_toggle()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.K, Enum.KeyCode.DPadLeft)
	ContextActionService:SetTitle(GANG_ACTION, "Gang")
	ContextActionService:SetDescription(GANG_ACTION, "Open or close the gang panel.")

	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			self:_close()
		end)
	)
end

function GangController:Destroy()
	ContextActionService:UnbindAction(GANG_ACTION)
	self.refreshGeneration = (self.refreshGeneration or 0) + 1
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.chips)
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

return GangController
