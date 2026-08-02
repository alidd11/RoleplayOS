--!strict

local Players = game:GetService("Players")
local CustomRegistrationController = { selectedVehicleId = nil, connections = {} }

function CustomRegistrationController:Init(context: any)
	self.context = context
end

function CustomRegistrationController:_button(parent: Instance, text: string): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = Color3.fromRGB(23, 32, 46)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(241, 245, 251)
	item.TextSize = 12
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = item
	return item
end

function CustomRegistrationController:_refresh()
	for _, child in self.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local response = self.context.Controllers.NetworkController:Request("GetOwnedVehicles", {})
	for _, vehicle in if response.Success then response.Data else {} do
		local row = self:_button(
			self.list,
			string.format("%s   ·   %s", vehicle.Name, vehicle.Registration)
		)
		row.Size = UDim2.new(1, 0, 0, 38)
		table.insert(
			self.connections,
			row.Activated:Connect(function()
				self.selectedVehicleId = vehicle.VehicleId
				self.selection.Text = "SELECTED  ·  "
					.. vehicle.Name
					.. "  ·  "
					.. vehicle.Registration
			end)
		)
	end
end

function CustomRegistrationController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCustomRegistration"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 16
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local launcher = self:_button(gui, "CUSTOM PLATE")
	launcher.AnchorPoint = Vector2.new(1, 0.5)
	launcher.Position = UDim2.new(1, -18, 0.58, 0)
	launcher.Size = UDim2.fromOffset(116, 38)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 430)
	panel.BackgroundColor3 = Color3.fromRGB(10, 16, 25)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(22, 18)
	title.Size = UDim2.new(1, -44, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "CUSTOM REGISTRATION"
	title.TextColor3 = Color3.fromRGB(244, 247, 252)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(22, 62)
	list.Size = UDim2.new(1, -44, 0, 180)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.Parent = list
	self.list = list
	local selection = Instance.new("TextLabel")
	selection.Position = UDim2.fromOffset(22, 254)
	selection.Size = UDim2.new(1, -44, 0, 24)
	selection.BackgroundTransparency = 1
	selection.Font = Enum.Font.Gotham
	selection.Text = "Select one of your vehicles above."
	selection.TextColor3 = Color3.fromRGB(155, 168, 187)
	selection.TextSize = 11
	selection.TextXAlignment = Enum.TextXAlignment.Left
	selection.Parent = panel
	self.selection = selection
	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(22, 286)
	input.Size = UDim2.new(1, -44, 0, 48)
	input.BackgroundColor3 = Color3.fromRGB(23, 32, 46)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.RobotoMono
	input.PlaceholderText = "2–8 letters, numbers or spaces"
	input.Text = ""
	input.TextColor3 = Color3.fromRGB(244, 247, 252)
	input.TextSize = 16
	input.Parent = panel
	local apply = self:_button(panel, "MODERATE & APPLY")
	apply.Position = UDim2.fromOffset(22, 350)
	apply.Size = UDim2.new(0.65, -6, 0, 52)
	apply.BackgroundColor3 = Color3.fromRGB(64, 145, 255)
	local close = self:_button(panel, "CLOSE")
	close.Position = UDim2.new(0.65, 6, 0, 350)
	close.Size = UDim2.new(0.35, -28, 0, 52)
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
		apply.Activated:Connect(function()
			if not self.selectedVehicleId then
				return
			end
			local response = self.context.Controllers.NetworkController:Request(
				"SetCustomRegistration",
				{ VehicleId = self.selectedVehicleId, Registration = input.Text }
			)
			self.context.Controllers.NotificationController:Show(response.Message, "Custom plate")
			if response.Success then
				input.Text = ""
				self:_refresh()
			end
		end)
	)
end

function CustomRegistrationController:Start()
	self:_mount()
end

function CustomRegistrationController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return CustomRegistrationController
