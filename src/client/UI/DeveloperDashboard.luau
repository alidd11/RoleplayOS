--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local App = {}
local COLOURS = {
	Canvas = Color3.fromRGB(7, 10, 16),
	Sidebar = Color3.fromRGB(11, 15, 23),
	Surface = Color3.fromRGB(16, 21, 31),
	SurfaceRaised = Color3.fromRGB(21, 28, 41),
	Border = Color3.fromRGB(42, 52, 70),
	Text = Color3.fromRGB(240, 244, 251),
	Muted = Color3.fromRGB(142, 154, 176),
	Accent = Color3.fromRGB(91, 156, 255),
	AccentSoft = Color3.fromRGB(25, 51, 88),
	Success = Color3.fromRGB(84, 211, 142),
	Warning = Color3.fromRGB(245, 188, 78),
	Danger = Color3.fromRGB(244, 104, 112),
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, colour: Color3?, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = colour or COLOURS.Border
	value.Transparency = transparency or 0
	value.Parent = parent
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3?,
	bold: boolean?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = value
	item.TextSize = size
	item.TextColor3 = colour or COLOURS.Text
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function pressable(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 0.97,
			})
			:Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)
end

local function button(parent: Instance, label: string, primary: boolean?): TextButton
	local item = Instance.new("TextButton")
	item.AutoButtonColor = false
	item.BackgroundColor3 = if primary then COLOURS.Accent else COLOURS.SurfaceRaised
	item.Font = Enum.Font.GothamBold
	item.Text = label
	item.TextSize = 14
	item.TextColor3 = COLOURS.Text
	item.Size = UDim2.fromOffset(170, 44)
	item.Parent = parent
	corner(item, 10)
	stroke(item, if primary then COLOURS.Accent else COLOURS.Border, if primary then 0.55 else 0)
	pressable(item)
	return item
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
		then
			child:Destroy()
		end
	end
end

local function card(parent: Instance, height: number): Frame
	local item = Instance.new("Frame")
	item.BackgroundColor3 = COLOURS.Surface
	item.BorderSizePixel = 0
	item.Size = UDim2.new(1, 0, 0, height)
	item.Parent = parent
	corner(item, 12)
	stroke(item)
	return item
end

local function input(parent: Instance, placeholder: string): TextBox
	local item = Instance.new("TextBox")
	item.BackgroundColor3 = COLOURS.Canvas
	item.BorderSizePixel = 0
	item.ClearTextOnFocus = false
	item.Font = Enum.Font.Gotham
	item.PlaceholderText = placeholder
	item.PlaceholderColor3 = COLOURS.Muted
	item.Text = ""
	item.TextColor3 = COLOURS.Text
	item.TextSize = 15
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Size = UDim2.new(1, 0, 0, 46)
	item.Parent = parent
	corner(item, 9)
	stroke(item)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = item
	return item
end

function App.mount(context: any): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOS"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = COLOURS.Canvas
	root.BorderSizePixel = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 12, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 20, 32)),
	})
	gradient.Rotation = 28
	gradient.Parent = root

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 250, 1, 0)
	sidebar.BackgroundColor3 = COLOURS.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = root
	local sidebarStroke = Instance.new("Frame")
	sidebarStroke.AnchorPoint = Vector2.new(1, 0)
	sidebarStroke.Position = UDim2.fromScale(1, 0)
	sidebarStroke.Size = UDim2.new(0, 1, 1, 0)
	sidebarStroke.BackgroundColor3 = COLOURS.Border
	sidebarStroke.BorderSizePixel = 0
	sidebarStroke.Parent = sidebar

	local brand = text(sidebar, "ROLEPLAY", 21, COLOURS.Text, true)
	brand.Position = UDim2.fromOffset(26, 28)
	brand.Size = UDim2.fromOffset(150, 28)
	local osMark = text(sidebar, "OS", 21, COLOURS.Accent, true)
	osMark.Position = UDim2.fromOffset(133, 28)
	osMark.Size = UDim2.fromOffset(40, 28)
	local version = text(sidebar, "FOUNDATION  ·  0.1", 10, COLOURS.Muted, true)
	version.Position = UDim2.fromOffset(27, 57)
	version.Size = UDim2.fromOffset(180, 18)

	local navigation = Instance.new("Frame")
	navigation.BackgroundTransparency = 1
	navigation.Position = UDim2.fromOffset(18, 112)
	navigation.Size = UDim2.new(1, -36, 0, 190)
	navigation.Parent = sidebar
	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 7)
	navLayout.Parent = navigation

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(250, 0)
	content.Size = UDim2.new(1, -250, 1, 0)
	content.Parent = root

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(44, 30)
	header.Size = UDim2.new(1, -88, 0, 76)
	header.Parent = content
	local pageTitle = text(header, "Play", 30, COLOURS.Text, true)
	pageTitle.Size = UDim2.new(1, -220, 0, 40)
	local pageDescription = text(header, "Choose who you want to be today.", 14, COLOURS.Muted)
	pageDescription.Position = UDim2.fromOffset(0, 41)
	pageDescription.Size = UDim2.new(1, -220, 0, 24)
	local status = text(header, "●  CONNECTING", 11, COLOURS.Warning, true)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, 0, 0, 9)
	status.Size = UDim2.fromOffset(190, 28)
	status.TextXAlignment = Enum.TextXAlignment.Right

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(44, 118)
	scroll.Size = UDim2.new(1, -88, 1, -146)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = COLOURS.Border
	scroll.Parent = content
	local flow = Instance.new("UIListLayout")
	flow.Padding = UDim.new(0, 14)
	flow.Parent = scroll

	local menuData: any = nil
	local selectedCharacterId: string? = nil
	local dismissToWorld: () -> ()

	local function showModal()
		local shade = Instance.new("TextButton")
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.25
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 20
		shade.Parent = root
		local modal = Instance.new("Frame")
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.Position = UDim2.fromScale(0.5, 0.5)
		modal.Size = UDim2.fromOffset(460, 465)
		modal.BackgroundColor3 = COLOURS.Surface
		modal.BorderSizePixel = 0
		modal.ZIndex = 21
		modal.Parent = shade
		corner(modal, 15)
		stroke(modal)
		local modalPadding = Instance.new("UIPadding")
		modalPadding.PaddingTop = UDim.new(0, 26)
		modalPadding.PaddingBottom = UDim.new(0, 26)
		modalPadding.PaddingLeft = UDim.new(0, 26)
		modalPadding.PaddingRight = UDim.new(0, 26)
		modalPadding.Parent = modal
		local modalFlow = Instance.new("UIListLayout")
		modalFlow.Padding = UDim.new(0, 12)
		modalFlow.Parent = modal
		local title = text(modal, "Create a character", 24, COLOURS.Text, true)
		title.Size = UDim2.new(1, 0, 0, 36)
		local copy = text(
			modal,
			"Build a civilian identity. You can customise appearance later.",
			13,
			COLOURS.Muted
		)
		copy.Size = UDim2.new(1, 0, 0, 38)
		copy.TextWrapped = true
		local firstName = input(modal, "First name")
		local lastName = input(modal, "Last name")
		local dateOfBirth = input(modal, "Date of birth  ·  YYYY-MM-DD")
		local errorLabel = text(modal, "", 12, COLOURS.Danger)
		errorLabel.Size = UDim2.new(1, 0, 0, 24)
		local actions = Instance.new("Frame")
		actions.BackgroundTransparency = 1
		actions.Size = UDim2.new(1, 0, 0, 46)
		actions.Parent = modal
		local cancel = button(actions, "Cancel", false)
		cancel.Size = UDim2.new(0.5, -6, 1, 0)
		local create = button(actions, "Create character", true)
		create.Position = UDim2.new(0.5, 6, 0, 0)
		create.Size = UDim2.new(0.5, -6, 1, 0)
		cancel.Activated:Connect(function()
			shade:Destroy()
		end)
		create.Activated:Connect(function()
			create.Text = "Creating…"
			local response = context.Controllers.CharacterController:Create({
				FirstName = firstName.Text,
				LastName = lastName.Text,
				DateOfBirth = dateOfBirth.Text,
			})
			if response.Success then
				shade:Destroy()
				context.Controllers.StartMenuController:Refresh()
			else
				errorLabel.Text = response.Message
				create.Text = "Create character"
			end
		end)
		modal.Size = UDim2.fromOffset(438, 442)
		modal.BackgroundTransparency = 1
		TweenService
			:Create(modal, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(460, 465),
				BackgroundTransparency = 0,
			})
			:Play()
	end

	local function showDutySelection(role: any, dutyProfile: any)
		local shade = Instance.new("TextButton")
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.25
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 20
		shade.Parent = root
		local modal = Instance.new("Frame")
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.Position = UDim2.fromScale(0.5, 0.5)
		modal.Size = UDim2.fromOffset(480, 390)
		modal.BackgroundColor3 = COLOURS.Surface
		modal.BorderSizePixel = 0
		modal.ZIndex = 21
		modal.Parent = shade
		corner(modal, 15)
		stroke(modal)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 26)
		padding.PaddingBottom = UDim.new(0, 26)
		padding.PaddingLeft = UDim.new(0, 26)
		padding.PaddingRight = UDim.new(0, 26)
		padding.Parent = modal
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = modal
		local title = text(modal, "Start " .. role.Name, 23, COLOURS.Text, true)
		title.Size = UDim2.new(1, 0, 0, 34)
		local copy =
			text(modal, "Choose exactly where you want to report for duty.", 13, COLOURS.Muted)
		copy.Size = UDim2.new(1, 0, 0, 30)
		for _, spawnOption in role.Spawns or {} do
			local displayName = string.gsub(spawnOption.SpawnId, "(%l)(%u)", "%1 %2")
			local choice = button(modal, spawnOption.StationName .. "  ·  " .. displayName, false)
			choice.Size = UDim2.new(1, 0, 0, 48)
			choice.Activated:Connect(function()
				choice.Text = "Starting duty…"
				local response = context.Controllers.DutyController:Begin({
					DutyProfileId = dutyProfile.ProfileId,
					RoleId = role.Id,
					StationId = spawnOption.StationId,
					SpawnId = spawnOption.SpawnId,
				})
				if response.Success then
					shade:Destroy()
					dismissToWorld()
				else
					choice.Text = spawnOption.StationName .. "  ·  " .. displayName
				end
			end)
		end
		local cancel = button(modal, "Cancel", false)
		cancel.Size = UDim2.new(1, 0, 0, 44)
		cancel.Activated:Connect(function()
			shade:Destroy()
		end)
	end

	local renderPlay: () -> ()
	local renderCommunity: () -> ()
	local renderCareers: () -> ()
	dismissToWorld = function()
		TweenService:Create(
			root,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.17, function()
			gui.Enabled = false
		end)
	end

	local function sectionHeading(titleValue: string, subtitle: string)
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.new(1, 0, 0, 54)
		wrapper.Parent = scroll
		local titleItem = text(wrapper, titleValue, 19, COLOURS.Text, true)
		titleItem.Size = UDim2.new(1, 0, 0, 28)
		local subtitleItem = text(wrapper, subtitle, 13, COLOURS.Muted)
		subtitleItem.Position = UDim2.fromOffset(0, 29)
		subtitleItem.Size = UDim2.new(1, 0, 0, 20)
	end

	renderPlay = function()
		clear(scroll)
		pageTitle.Text = "Play"
		pageDescription.Text = "Choose who you want to be today."
		sectionHeading(
			"Your characters",
			"Civilian lives keep their own money, vehicles and property."
		)
		if not menuData or #menuData.Characters == 0 then
			local empty = card(scroll, 150)
			local titleItem = text(empty, "Start your first story", 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(20, 18)
			titleItem.Size = UDim2.new(1, -210, 0, 28)
			local copy =
				text(empty, "Create a civilian identity to enter the city.", 13, COLOURS.Muted)
			copy.Position = UDim2.fromOffset(20, 50)
			copy.Size = UDim2.new(1, -210, 0, 50)
			copy.TextWrapped = true
			local create = button(empty, "Create character", true)
			create.AnchorPoint = Vector2.new(1, 0.5)
			create.Position = UDim2.new(1, -20, 0.5, 0)
			create.Activated:Connect(showModal)
		else
			for _, character in menuData.Characters do
				local item = card(scroll, 92)
				local avatar = Instance.new("Frame")
				avatar.Position = UDim2.fromOffset(18, 18)
				avatar.Size = UDim2.fromOffset(56, 56)
				avatar.BackgroundColor3 = COLOURS.AccentSoft
				avatar.Parent = item
				corner(avatar, 28)
				local initials =
					text(avatar, string.sub(character.FullName, 1, 1), 22, COLOURS.Accent, true)
				initials.Size = UDim2.fromScale(1, 1)
				initials.TextXAlignment = Enum.TextXAlignment.Center
				local name = text(item, character.FullName, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(90, 20)
				name.Size = UDim2.new(1, -280, 0, 27)
				local dob = text(item, "Born " .. character.DateOfBirth, 12, COLOURS.Muted)
				dob.Position = UDim2.fromOffset(90, 48)
				dob.Size = UDim2.new(1, -280, 0, 22)
				local choose = button(item, "Choose", selectedCharacterId == character.CharacterId)
				choose.AnchorPoint = Vector2.new(1, 0.5)
				choose.Position = UDim2.new(1, -18, 0.5, 0)
				choose.Size = UDim2.fromOffset(132, 42)
				choose.Activated:Connect(function()
					local response =
						context.Controllers.CharacterController:Select(character.CharacterId)
					if response.Success then
						selectedCharacterId = character.CharacterId
						context.Controllers.NotificationController:Show(
							"Character selected.",
							"Ready"
						)
						renderPlay()
					end
				end)
			end
			if menuData.EmptySlots > 0 then
				local create = button(scroll, "+  New character", false)
				create.Size = UDim2.new(1, 0, 0, 48)
				create.Activated:Connect(showModal)
			end
		end
		sectionHeading("Enter the city", "Public civilian play is always available.")
		local enter = card(scroll, 108)
		local titleItem = text(enter, "Civilian", 18, COLOURS.Text, true)
		titleItem.Position = UDim2.fromOffset(20, 18)
		titleItem.Size = UDim2.new(1, -210, 0, 28)
		local copy = text(
			enter,
			"Explore, work, build a career and create your own story.",
			13,
			COLOURS.Muted
		)
		copy.Position = UDim2.fromOffset(20, 49)
		copy.Size = UDim2.new(1, -210, 0, 40)
		local action =
			button(enter, selectedCharacterId and "Enter city" or "Choose a character", true)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -20, 0.5, 0)
		action.Activated:Connect(function()
			if not selectedCharacterId then
				context.Controllers.NotificationController:Show(
					"Choose or create a character first.",
					"Character required"
				)
				return
			end
			local spawnId = "CityCivilian"
			for _, role in menuData.Roles do
				if role.Id == "Civilian" and role.Spawns[1] then
					spawnId = role.Spawns[1].SpawnId
				end
			end
			local response =
				context.Controllers.DutyController:EnterCivilian(selectedCharacterId, spawnId)
			if response.Success then
				dismissToWorld()
			end
		end)
	end

	renderCareers = function()
		clear(scroll)
		pageTitle.Text = "Careers"
		pageDescription.Text = "Every path is visible. Requirements are always clear."
		sectionHeading(
			"Roles and departments",
			"Restricted careers explain exactly how to unlock them."
		)
		for _, role in menuData and menuData.Roles or {} do
			if role.Visible then
				local item = card(scroll, 96)
				local badge = Instance.new("Frame")
				badge.Position = UDim2.fromOffset(18, 19)
				badge.Size = UDim2.fromOffset(58, 58)
				badge.BackgroundColor3 = if role.Locked
					then Color3.fromRGB(45, 38, 27)
					else COLOURS.AccentSoft
				badge.Parent = item
				corner(badge, 12)
				local icon = text(
					badge,
					if role.Locked then "◇" else "✓",
					23,
					if role.Locked then COLOURS.Warning else COLOURS.Accent,
					true
				)
				icon.Size = UDim2.fromScale(1, 1)
				icon.TextXAlignment = Enum.TextXAlignment.Center
				local name = text(item, role.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(91, 18)
				name.Size = UDim2.new(1, -280, 0, 28)
				local detail = text(
					item,
					role.Locked and role.LockMessage or "Available now",
					12,
					role.Locked and COLOURS.Muted or COLOURS.Success
				)
				detail.Position = UDim2.fromOffset(91, 47)
				detail.Size = UDim2.new(1, -280, 0, 28)
				local action = button(
					item,
					role.Locked
							and (role.Action == "OpenApplication" and "View application" or "View access")
						or "Select",
					not role.Locked
				)
				action.AnchorPoint = Vector2.new(1, 0.5)
				action.Position = UDim2.new(1, -18, 0.5, 0)
				action.Size = UDim2.fromOffset(150, 42)
				action.Activated:Connect(function()
					if role.Locked then
						context.Controllers.NotificationController:Show(
							role.LockMessage,
							"Access required"
						)
						return
					end
					if not role.DepartmentId then
						context.Controllers.NotificationController:Show(
							"Select Civilian from the Play screen.",
							"Public role"
						)
						return
					end
					local dutyProfile = nil
					for _, profile in menuData.DutyProfiles or {} do
						if profile.DepartmentId == role.DepartmentId then
							dutyProfile = profile
							break
						end
					end
					if not dutyProfile or not role.Spawns or #role.Spawns == 0 then
						context.Controllers.NotificationController:Show(
							"No valid duty profile or station is available.",
							"Duty unavailable"
						)
						return
					end
					showDutySelection(role, dutyProfile)
				end)
			end
		end
	end

	renderCommunity = function()
		clear(scroll)
		pageTitle.Text = "Community"
		pageDescription.Text = "Run serious roleplay with your own standards and staff team."
		local server = menuData and menuData.Server
		sectionHeading(
			"Your server",
			"Communities share RoleplayOS while retaining their identity."
		)
		local hero = card(scroll, 200)
		local eyebrow = text(
			hero,
			server and string.upper(server.Kind .. " SERVER") or "PUBLIC SERVER",
			11,
			COLOURS.Accent,
			true
		)
		eyebrow.Position = UDim2.fromOffset(22, 20)
		eyebrow.Size = UDim2.new(1, -44, 0, 22)
		local titleValue = server and server.Community and server.Community.Name
			or "Create your community"
		local titleItem = text(hero, titleValue, 23, COLOURS.Text, true)
		titleItem.Position = UDim2.fromOffset(22, 48)
		titleItem.Size = UDim2.new(1, -44, 0, 36)
		local copy = text(
			hero,
			"Membership, staff permissions, sessions and access policies—without compromising server authority.",
			13,
			COLOURS.Muted
		)
		copy.Position = UDim2.fromOffset(22, 89)
		copy.Size = UDim2.new(1, -44, 0, 50)
		copy.TextWrapped = true
		local state = text(
			hero,
			server and server.Community and "●  ACTIVE COMMUNITY" or "●  COMMUNITY READY",
			11,
			COLOURS.Success,
			true
		)
		state.Position = UDim2.fromOffset(22, 151)
		state.Size = UDim2.new(1, -220, 0, 28)
		if server and server.Kind == "Private" and not server.Community then
			local createCommunity = button(hero, "Create community", true)
			createCommunity.AnchorPoint = Vector2.new(1, 1)
			createCommunity.Position = UDim2.new(1, -20, 1, -18)
			createCommunity.Size = UDim2.fromOffset(170, 42)
			createCommunity.Activated:Connect(function()
				local communityName = Players.LocalPlayer.DisplayName .. " Community"
				createCommunity.Text = "Creating…"
				local response =
					context.Controllers.CommunityController:CreatePrivate(communityName)
				if response.Success then
					context.Controllers.StartMenuController:Refresh()
				else
					createCommunity.Text = "Create community"
				end
			end)
		elseif server and server.Kind == "Public" then
			local publicBadge = text(hero, "PRIVATE SERVER REQUIRED", 10, COLOURS.Muted, true)
			publicBadge.AnchorPoint = Vector2.new(1, 1)
			publicBadge.Position = UDim2.new(1, -22, 1, -21)
			publicBadge.Size = UDim2.fromOffset(190, 24)
			publicBadge.TextXAlignment = Enum.TextXAlignment.Right
		end
		sectionHeading(
			"Included controls",
			"A professional foundation for private roleplay operations."
		)
		for _, feature in
			{
				{ "Staff hierarchy", "Owner, administrator, moderator and member roles." },
				{ "Membership policy", "Open, approval-based or invite-only entry." },
				{ "Safety and audit", "Suspensions, bans and sensitive actions are recorded." },
				{
					"Shared gameplay",
					"Characters, careers, economy and services stay authoritative.",
				},
			}
		do
			local item = card(scroll, 78)
			local name = text(item, feature[1], 15, COLOURS.Text, true)
			name.Position = UDim2.fromOffset(18, 12)
			name.Size = UDim2.new(1, -36, 0, 25)
			local detail = text(item, feature[2], 12, COLOURS.Muted)
			detail.Position = UDim2.fromOffset(18, 39)
			detail.Size = UDim2.new(1, -36, 0, 23)
		end
	end

	local activeNav: TextButton? = nil
	local function addNav(labelValue: string, render: () -> ())
		local item = Instance.new("TextButton")
		item.AutoButtonColor = false
		item.BackgroundColor3 = COLOURS.Sidebar
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamMedium
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 14
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Size = UDim2.new(1, 0, 0, 44)
		item.Parent = navigation
		corner(item, 9)
		local itemPadding = Instance.new("UIPadding")
		itemPadding.PaddingLeft = UDim.new(0, 14)
		itemPadding.Parent = item
		pressable(item)
		item.Activated:Connect(function()
			if activeNav then
				activeNav.BackgroundColor3 = COLOURS.Sidebar
				activeNav.TextColor3 = COLOURS.Muted
			end
			activeNav = item
			item.BackgroundColor3 = COLOURS.AccentSoft
			item.TextColor3 = COLOURS.Text
			render()
		end)
		return item
	end

	local playNav = addNav("Play", renderPlay)
	addNav("Careers", renderCareers)
	addNav("Community", renderCommunity)
	activeNav = playNav
	playNav.BackgroundColor3 = COLOURS.AccentSoft
	playNav.TextColor3 = COLOURS.Text

	local profile = card(sidebar, 68)
	profile.AnchorPoint = Vector2.new(0, 1)
	profile.Position = UDim2.new(0, 18, 1, -20)
	profile.Size = UDim2.new(1, -36, 0, 68)
	local playerName = text(profile, Players.LocalPlayer.DisplayName, 14, COLOURS.Text, true)
	playerName.Position = UDim2.fromOffset(14, 11)
	playerName.Size = UDim2.new(1, -28, 0, 24)
	local environment = text(profile, "Development environment", 11, COLOURS.Muted)
	environment.Position = UDim2.fromOffset(14, 35)
	environment.Size = UDim2.new(1, -28, 0, 20)

	context.Events.StartMenuChanged.Event:Connect(function(data)
		menuData = data
		status.Text = "●  ONLINE  ·  " .. string.upper(data.Server.Kind)
		status.TextColor3 = COLOURS.Success
		renderPlay()
	end)
	local response = context.Controllers.StartMenuController:Refresh()
	if response.Success then
		menuData = response.Data
		status.Text = "●  ONLINE  ·  " .. string.upper(response.Data.Server.Kind)
		status.TextColor3 = COLOURS.Success
	else
		status.Text = "●  CONNECTION ERROR"
		status.TextColor3 = COLOURS.Danger
		renderPlay()
	end

	root.Position = UDim2.fromOffset(0, 12)
	root.BackgroundTransparency = 1
	TweenService
		:Create(root, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 0,
		})
		:Play()
	return gui
end

return table.freeze(App)
