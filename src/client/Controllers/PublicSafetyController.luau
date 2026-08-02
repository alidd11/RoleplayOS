--!strict

local Players = game:GetService("Players")

local PublicSafetyController = { connections = {}, watched = {} }

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

function PublicSafetyController:Init(context: any)
	self.context = context
end

function PublicSafetyController:_targetUserId(): number?
	local mouse = Players.LocalPlayer:GetMouse()
	local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	return player and player.UserId or nil
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
			if response.Success and not isCuffs then
				self:_showCard(response.Data)
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
	self.context.Controllers.UIOrchestrator:Bind("PublicSafetyCredential", function(layout)
		scale.Scale =
			math.clamp(math.min(layout.Viewport.X / 540, layout.Viewport.Y / 355), 0.67, 1)
	end)
	self.card = card
	self.band = band
	self.cardTitle = title
	self.cardSubtitle = subtitle
	self.avatar = avatar
	self.cardName = name
	self.cardDob = dob
	self.cardNumber = number
	self.validity = validity
	self.gui = gui
end

function PublicSafetyController:Start()
	self:_mount()
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
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return PublicSafetyController
