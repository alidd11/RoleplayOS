--!strict

local Players = game:GetService("Players")
local PublicSafetyController = { connections = {}, watched = {} }
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
	self.card.Visible = true
	self.cardName.Text = card.FullName
	self.cardDob.Text = "DATE OF BIRTH  ·  " .. card.DateOfBirth
	self.cardNumber.Text = "DOCUMENT  ·  " .. card.DocumentNumber
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
	if tool.Name ~= "Handcuffs" and tool.Name ~= "ID Card" then
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
			local endpoint = if tool.Name == "Handcuffs" then "CuffPlayer" else "GetPresentedId"
			local response = self.context.Controllers.NetworkController:Request(
				endpoint,
				{ TargetUserId = target }
			)
			self.context.Controllers.NotificationController:Show(response.Message, tool.Name)
			if response.Success and tool.Name == "ID Card" then
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
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 25
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.45)
	card.Size = UDim2.fromOffset(430, 245)
	card.BackgroundColor3 = Color3.fromRGB(235, 231, 214)
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 55)
	band.BackgroundColor3 = Color3.fromRGB(22, 49, 75)
	band.BorderSizePixel = 0
	band.Parent = card
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -40, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "UNITED KINGDOM  ·  IDENTITY CARD"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = band
	local function label(y, size, color)
		local l = Instance.new("TextLabel")
		l.Position = UDim2.fromOffset(24, y)
		l.Size = UDim2.new(1, -48, 0, 30)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = color
		l.TextSize = size
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = card
		return l
	end
	self.cardName = label(82, 24, Color3.fromRGB(22, 31, 39))
	self.cardDob = label(130, 12, Color3.fromRGB(58, 68, 76))
	self.cardNumber = label(168, 12, Color3.fromRGB(58, 68, 76))
	self.card = card
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
	for _, c in self.connections do
		c:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
end
return PublicSafetyController
