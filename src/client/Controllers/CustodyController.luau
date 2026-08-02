--!strict

local Players = game:GetService("Players")
local CustodyController = { connections = {}, targetUserId = nil }
function CustodyController:Init(context: any)
	self.context = context
end
local function button(parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Color3.fromRGB(24, 34, 48)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.Text = text
	b.TextColor3 = Color3.fromRGB(240, 245, 251)
	b.TextSize = 12
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end
function CustodyController:_refresh()
	for _, child in self.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			local row = button(self.list, player.DisplayName .. "  ·  " .. player.Name)
			row.Size = UDim2.new(1, 0, 0, 36)
			table.insert(
				self.connections,
				row.Activated:Connect(function()
					self.targetUserId = player.UserId
					self.selected.Text = "DETAINEE  ·  " .. player.DisplayName
				end)
			)
		end
	end
end
function CustodyController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCustodyBooking"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 22
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local launcher = button(gui, "CUSTODY")
	launcher.Position = UDim2.new(1, -308, 1, -66)
	launcher.Size = UDim2.fromOffset(104, 36)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(500, 420)
	panel.BackgroundColor3 = Color3.fromRGB(8, 14, 22)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -40, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "CUSTODY BOOKING"
	title.TextColor3 = Color3.fromRGB(244, 248, 252)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 58)
	list.Size = UDim2.new(1, -40, 0, 145)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list
	self.list = list
	local selected = Instance.new("TextLabel")
	selected.Position = UDim2.fromOffset(20, 214)
	selected.Size = UDim2.new(1, -40, 0, 24)
	selected.BackgroundTransparency = 1
	selected.Font = Enum.Font.Gotham
	selected.Text = "Select the handcuffed detainee."
	selected.TextColor3 = Color3.fromRGB(152, 167, 187)
	selected.TextSize = 11
	selected.TextXAlignment = Enum.TextXAlignment.Left
	selected.Parent = panel
	self.selected = selected
	local reason = Instance.new("TextBox")
	reason.Position = UDim2.fromOffset(20, 248)
	reason.Size = UDim2.new(1, -40, 0, 80)
	reason.BackgroundColor3 = Color3.fromRGB(20, 29, 41)
	reason.BorderSizePixel = 0
	reason.ClearTextOnFocus = false
	reason.Font = Enum.Font.Gotham
	reason.PlaceholderText = "Necessity and grounds for arrest / detention"
	reason.Text = ""
	reason.TextColor3 = Color3.fromRGB(242, 246, 251)
	reason.TextSize = 13
	reason.TextWrapped = true
	reason.Parent = panel
	Instance.new("UICorner", reason).CornerRadius = UDim.new(0, 8)
	local create = button(panel, "CREATE CUSTODY RECORD")
	create.Position = UDim2.fromOffset(20, 344)
	create.Size = UDim2.new(0.68, -6, 0, 52)
	create.BackgroundColor3 = Color3.fromRGB(43, 112, 184)
	local close = button(panel, "CLOSE")
	close.Position = UDim2.new(0.68, 6, 0, 344)
	close.Size = UDim2.new(0.32, -26, 0, 52)
	table.insert(
		self.connections,
		launcher.Activated:Connect(function()
			panel.Visible = true
			self:_refresh()
		end)
	)
	table.insert(
		self.connections,
		close.Activated:Connect(function()
			panel.Visible = false
		end)
	)
	table.insert(
		self.connections,
		create.Activated:Connect(function()
			if not self.targetUserId then
				return
			end
			local response = self.context.Controllers.NetworkController:Request(
				"BookCustody",
				{ TargetUserId = self.targetUserId, Reason = reason.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Custody")
			if response.Success then
				panel.Visible = false
				reason.Text = ""
				self.targetUserId = nil
			end
		end)
	)
end
function CustodyController:Destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
end
return CustodyController
