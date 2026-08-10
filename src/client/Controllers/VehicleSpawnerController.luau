--!strict

local Players = game:GetService("Players")

local VehicleSpawnerController = { connections = {}, promptConnections = {} }

function VehicleSpawnerController:Init(context: any)
	self.context = context
end

function VehicleSpawnerController:_close()
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

function VehicleSpawnerController:_customPlate(
	spawnerId: string,
	vehicleId: string,
	current: string,
	onSaved: (string) -> ()
)
	if not self.gui then
		return
	end
	local dialog = Instance.new("Frame")
	dialog.Name = "CustomRegistration"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.fromOffset(360, 220)
	dialog.BackgroundColor3 = Color3.fromRGB(13, 23, 36)
	dialog.BorderSizePixel = 0
	dialog.ZIndex = 20
	dialog.Parent = self.gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(290, 210)
	constraint.MaxSize = Vector2.new(360, 220)
	constraint.Parent = dialog
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = dialog
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(67, 94, 128)
	stroke.Transparency = 0.25
	stroke.Parent = dialog
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.Text = "CUSTOM REGISTRATION"
	title.TextColor3 = Color3.fromRGB(245, 248, 252)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 21
	title.Parent = dialog
	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(20, 61)
	input.Size = UDim2.new(1, -40, 0, 54)
	input.BackgroundColor3 = Color3.fromRGB(233, 189, 54)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.RobotoMono
	input.PlaceholderText = "AB12 CDE"
	input.Text = current
	input.TextColor3 = Color3.fromRGB(12, 15, 18)
	input.PlaceholderColor3 = Color3.fromRGB(82, 73, 43)
	input.TextSize = 22
	input.ZIndex = 21
	input.Parent = dialog
	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = input
	local cancel = Instance.new("TextButton")
	cancel.Position = UDim2.new(0, 20, 1, -64)
	cancel.Size = UDim2.new(0.5, -25, 0, 44)
	cancel.BackgroundColor3 = Color3.fromRGB(31, 44, 61)
	cancel.BorderSizePixel = 0
	cancel.Font = Enum.Font.GothamBold
	cancel.Text = "CANCEL"
	cancel.TextColor3 = Color3.fromRGB(220, 228, 238)
	cancel.TextSize = 12
	cancel.ZIndex = 21
	cancel.Parent = dialog
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 9)
	cancelCorner.Parent = cancel
	local save = cancel:Clone()
	save.Position = UDim2.new(0.5, 5, 1, -64)
	save.BackgroundColor3 = Color3.fromRGB(42, 121, 224)
	save.Text = "SAVE"
	save.Parent = dialog
	cancel.Activated:Connect(function()
		dialog:Destroy()
	end)
	save.Activated:Connect(function()
		save.Active = false
		save.Text = "CHECKING…"
		local response = self.context.Controllers.NetworkController:Request(
			"SetCustomVehicleRegistration",
			{ SpawnerId = spawnerId, VehicleId = vehicleId, Registration = input.Text }
		)
		self.context.Controllers.NotificationController:Show(response.Message, "Vehicles")
		if response.Success then
			local registration = tostring(response.Data.Registration)
			onSaved(registration)
			dialog:Destroy()
		else
			save.Active = true
			save.Text = "SAVE"
		end
	end)
	input:CaptureFocus()
end

function VehicleSpawnerController:_open(spawnerId: string)
	local response = self.context.Controllers.NetworkController:Request("GetVehicleSpawnerMenu", {
		SpawnerId = spawnerId,
	})
	if not response.Success then
		self.context.Controllers.NotificationController:Show(response.Message, "Vehicles")
		return
	end
	self:_close()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSVehicleSpawner"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 35
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(2, 7, 13)
	scrim.BackgroundTransparency = 0.28
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Parent = gui
	scrim.Activated:Connect(function()
		self:_close()
	end)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.72, 0.72)
	panel.BackgroundColor3 = Color3.fromRGB(9, 16, 26)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(330, 390)
	sizeConstraint.MaxSize = Vector2.new(920, 650)
	sizeConstraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(58, 81, 112)
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = panel
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 92)
	header.BackgroundColor3 = Color3.fromRGB(14, 26, 41)
	header.BorderSizePixel = 0
	header.Parent = panel
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 18)
	headerCorner.Parent = header
	local accent = Instance.new("Frame")
	accent.Position = UDim2.fromOffset(0, 90)
	accent.Size = UDim2.new(1, 0, 0, 2)
	accent.BackgroundColor3 = Color3.fromRGB(57, 153, 255)
	accent.BorderSizePixel = 0
	accent.Parent = header
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.new(1, -92, 0, 34)
	title.Font = Enum.Font.GothamBold
	title.Text = tostring(response.Data.Name or "Vehicles")
	title.TextColor3 = Color3.fromRGB(245, 248, 252)
	title.TextSize = 23
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(24, 47)
	subtitle.Size = UDim2.new(1, -92, 0, 24)
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Select a vehicle from your available fleet"
	subtitle.TextColor3 = Color3.fromRGB(151, 169, 192)
	subtitle.TextSize = 13
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = header
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -58, 0, 20)
	close.Size = UDim2.fromOffset(38, 38)
	close.BackgroundColor3 = Color3.fromRGB(31, 46, 65)
	close.Text = "×"
	close.TextColor3 = Color3.fromRGB(245, 248, 252)
	close.TextSize = 22
	close.Parent = header
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		self:_close()
	end)
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 112)
	list.Size = UDim2.new(1, -40, 1, -132)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 4
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list
	local vehicles = response.Data.Vehicles or {}
	if #vehicles == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, -6, 0, 180)
		empty.BackgroundColor3 = Color3.fromRGB(14, 24, 37)
		empty.BorderSizePixel = 0
		empty.Parent = list
		local emptyCorner = Instance.new("UICorner")
		emptyCorner.CornerRadius = UDim.new(0, 14)
		emptyCorner.Parent = empty
		local emptyTitle = Instance.new("TextLabel")
		emptyTitle.BackgroundTransparency = 1
		emptyTitle.Position = UDim2.fromOffset(20, 43)
		emptyTitle.Size = UDim2.new(1, -40, 0, 32)
		emptyTitle.Font = Enum.Font.GothamBold
		emptyTitle.Text = "No vehicles available"
		emptyTitle.TextColor3 = Color3.fromRGB(238, 243, 249)
		emptyTitle.TextSize = 18
		emptyTitle.Parent = empty
		local emptyBody = Instance.new("TextLabel")
		emptyBody.BackgroundTransparency = 1
		emptyBody.Position = UDim2.fromOffset(30, 78)
		emptyBody.Size = UDim2.new(1, -60, 0, 54)
		emptyBody.Font = Enum.Font.Gotham
		emptyBody.Text =
			"Your garage is empty or its vehicle models are unavailable. Try again after selecting a character."
		emptyBody.TextWrapped = true
		emptyBody.TextColor3 = Color3.fromRGB(145, 164, 187)
		emptyBody.TextSize = 13
		emptyBody.Parent = empty
	end
	for _, definition in vehicles do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -6, 0, 86)
		card.BackgroundColor3 = Color3.fromRGB(18, 30, 45)
		card.BorderSizePixel = 0
		card.Parent = list
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 13)
		cardCorner.Parent = card
		local marker = Instance.new("Frame")
		marker.Size = UDim2.fromOffset(4, 46)
		marker.Position = UDim2.new(0, 0, 0.5, -23)
		marker.BackgroundColor3 = Color3.fromRGB(57, 153, 255)
		marker.BorderSizePixel = 0
		marker.Parent = card
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(22, 14)
		name.Size = UDim2.new(1, if definition.VehicleId then -218 else -178, 0, 28)
		name.Font = Enum.Font.GothamBold
		name.Text = tostring(definition.Name)
		name.TextColor3 = Color3.fromRGB(240, 245, 251)
		name.TextSize = 16
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = card
		local detail = Instance.new("TextLabel")
		detail.BackgroundTransparency = 1
		detail.Position = UDim2.fromOffset(22, 43)
		detail.Size = UDim2.new(1, if definition.VehicleId then -218 else -178, 0, 24)
		detail.Font = Enum.Font.GothamMedium
		detail.Text = if definition.Registration
			then "REG  •  " .. tostring(definition.Registration)
			else string.upper(
				tostring(definition.DivisionId or definition.Category or "FLEET")
			)
		detail.TextColor3 = Color3.fromRGB(125, 166, 211)
		detail.TextSize = 11
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.Parent = card
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -16, 0.5, 0)
		button.Size = UDim2.fromOffset(if definition.VehicleId then 100 else 126, 44)
		button.BackgroundColor3 = Color3.fromRGB(42, 121, 224)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = "SPAWN"
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextSize = 13
		button.Parent = card
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 10)
		buttonCorner.Parent = button
		button.Activated:Connect(function()
			button.Active = false
			button.Text = "SPAWNING…"
			local spawned = self.context.Controllers.NetworkController:Request("SpawnVehicle", {
				SpawnerId = spawnerId,
				DefinitionId = definition.Id,
				VehicleId = definition.VehicleId,
			})
			self.context.Controllers.NotificationController:Show(spawned.Message, "Vehicles")
			if spawned.Success then
				self:_close()
			else
				button.Active = true
				button.Text = "SPAWN"
			end
		end)
		if type(definition.VehicleId) == "string" then
			local plateButton = button:Clone()
			plateButton.Name = "CustomPlate"
			plateButton.Position = UDim2.new(1, -124, 0.5, 0)
			plateButton.Size = UDim2.fromOffset(72, 44)
			plateButton.BackgroundColor3 = Color3.fromRGB(31, 46, 65)
			plateButton.Text = "PLATE"
			plateButton.Parent = card
			plateButton.Activated:Connect(function()
				self:_customPlate(
					spawnerId,
					definition.VehicleId,
					tostring(definition.Registration or ""),
					function(registration)
						definition.Registration = registration
						detail.Text = "REG  •  " .. registration
					end
				)
			end)
		end
	end
end

local function spawnerFor(prompt: ProximityPrompt): Instance?
	local current = prompt.Parent
	while current and current ~= workspace do
		if type(current:GetAttribute("SpawnerId")) == "string" then
			return current
		end
		current = current.Parent
	end
	return nil
end

function VehicleSpawnerController:_bind(prompt: ProximityPrompt)
	if self.promptConnections[prompt] then
		return
	end
	local spawner = spawnerFor(prompt)
	if not spawner then
		return
	end
	local spawnerId = spawner:GetAttribute("SpawnerId")
	if type(spawnerId) ~= "string" or spawnerId == "" then
		return
	end
	self.promptConnections[prompt] = prompt.Triggered:Connect(function()
		-- On a client, this signal represents the local player's completed
		-- interaction. Do not depend on the optional player argument: its shape
		-- differs between client and server prompt signals, which previously made
		-- a visible E prompt complete without ever opening the interface.
		self:_open(spawnerId)
	end)
end

function VehicleSpawnerController:Start()
	local folder = workspace:WaitForChild("RoleplayOSVehicleFacilities", 20)
	if not folder then
		return
	end
	for _, instance in folder:GetDescendants() do
		if instance:IsA("ProximityPrompt") then
			self:_bind(instance)
		end
	end
	table.insert(
		self.connections,
		folder.DescendantAdded:Connect(function(instance)
			if instance:IsA("ProximityPrompt") then
				task.defer(function()
					self:_bind(instance)
				end)
			end
		end)
	)
end

function VehicleSpawnerController:Destroy()
	self:_close()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for prompt, connection in self.promptConnections do
		connection:Disconnect()
		self.promptConnections[prompt] = nil
	end
	table.clear(self.connections)
	table.clear(self.promptConnections)
end

return VehicleSpawnerController
