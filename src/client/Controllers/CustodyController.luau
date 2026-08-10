--!strict

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local CustodyController = {
	connections = {},
	targetUserId = nil,
	selectedCodes = {},
	policy = {},
	policyMetadata = {},
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function button(parent: Instance, text: string): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = Color3.fromRGB(24, 34, 48)
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(240, 245, 251)
	item.TextSize = 12
	item.Parent = parent
	corner(item, 8)
	return item
end

local function formatTime(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

function CustodyController:Init(context: any)
	self.context = context
end

function CustodyController:_refreshPlayers()
	for _, child in self.playerList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			local row = button(self.playerList, player.DisplayName .. "  ·  " .. player.Name)
			row.Size = UDim2.new(1, 0, 0, 34)
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

function CustodyController:_refreshPolicy()
	for _, child in self.offenceList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, offence in self.policy do
		local row = button(
			self.offenceList,
			string.format("%s  ·  %s", offence.Name, formatTime(offence.Seconds))
		)
		row.Size = UDim2.new(1, 0, 0, 32)
		local function paint()
			row.BackgroundColor3 = if self.selectedCodes[offence.Code]
				then Color3.fromRGB(31, 105, 160)
				else Color3.fromRGB(24, 34, 48)
		end
		paint()
		table.insert(
			self.connections,
			row.Activated:Connect(function()
				self.selectedCodes[offence.Code] = not self.selectedCodes[offence.Code]
				paint()
			end)
		)
	end
end

function CustodyController:_updateSentenceHud()
	local remaining = Players.LocalPlayer:GetAttribute("RoleplayOSCustodyRemaining")
	local active = type(remaining) == "number" and remaining > 0
	self.sentenceHud.Visible = active
	if active then
		self.sentenceTime.Text = formatTime(remaining)
	end
	local credits = math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
	local products = self.policyMetadata.EarlyReleaseProducts or {}
	local single = products[1]
	self.earlyRelease.Visible = active and self.policyMetadata.ServerKind == "Public"
	self.earlyRelease.Text = if credits > 0
		then string.format("USE CREDIT · %d", credits)
		else string.format(
			"EARLY RELEASE · %d R$",
			tonumber(single and single.PriceRobux) or 19
		)
end

function CustodyController:_refreshAccess(duty: any?)
	local activeDuty = duty or self.context.Controllers.DutyController.active
	local authorised = activeDuty ~= nil and activeDuty.DepartmentId == "Police"
	-- Booking is deliberately contextual. The permanent HUD launcher competed
	-- with vehicle and mobile controls; restraint actions are opened from the
	-- selected detainee flow in PublicSafetyController instead.
	self.launcher.Visible = false
	if not authorised then
		self.panel.Visible = false
		self.targetUserId = nil
	end
end

function CustodyController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSCustodyBooking"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Anchored to a screen edge, so it must stay clear of notches, rounded
	-- corners and home indicators rather than being clipped by them.
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 22
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local launcher = button(gui, "CUSTODY")
	launcher.Size = UDim2.fromOffset(104, 36)
	launcher.Visible = false
	self.launcher = launcher

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(540, 550)
	panel.BackgroundColor3 = Color3.fromRGB(8, 14, 22)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	self.panel = panel

	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	self.panelScale = panelScale

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

	local playerList = Instance.new("ScrollingFrame")
	playerList.Position = UDim2.fromOffset(20, 58)
	playerList.Size = UDim2.new(1, -40, 0, 104)
	playerList.BackgroundTransparency = 1
	playerList.BorderSizePixel = 0
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.CanvasSize = UDim2.new()
	playerList.ScrollBarThickness = 3
	playerList.Parent = panel
	local playerLayout = Instance.new("UIListLayout")
	playerLayout.Padding = UDim.new(0, 5)
	playerLayout.Parent = playerList
	self.playerList = playerList

	local selected = Instance.new("TextLabel")
	selected.Position = UDim2.fromOffset(20, 170)
	selected.Size = UDim2.new(1, -40, 0, 22)
	selected.BackgroundTransparency = 1
	selected.Font = Enum.Font.Gotham
	selected.Text = "Select the handcuffed detainee."
	selected.TextColor3 = Color3.fromRGB(152, 167, 187)
	selected.TextSize = 11
	selected.TextXAlignment = Enum.TextXAlignment.Left
	selected.Parent = panel
	self.selected = selected

	local offenceTitle = selected:Clone()
	offenceTitle.Position = UDim2.fromOffset(20, 200)
	offenceTitle.Text = "GAMEPLAY OFFENCES  ·  SELECT ALL THAT APPLY"
	offenceTitle.Font = Enum.Font.GothamBold
	offenceTitle.Parent = panel

	local offenceList = Instance.new("ScrollingFrame")
	offenceList.Position = UDim2.fromOffset(20, 226)
	offenceList.Size = UDim2.new(1, -40, 0, 104)
	offenceList.BackgroundTransparency = 1
	offenceList.BorderSizePixel = 0
	offenceList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	offenceList.CanvasSize = UDim2.new()
	offenceList.ScrollBarThickness = 3
	offenceList.Parent = panel
	local offenceLayout = Instance.new("UIListLayout")
	offenceLayout.Padding = UDim.new(0, 5)
	offenceLayout.Parent = offenceList
	self.offenceList = offenceList

	local reason = Instance.new("TextBox")
	reason.Position = UDim2.fromOffset(20, 342)
	reason.Size = UDim2.new(1, -40, 0, 78)
	reason.BackgroundColor3 = Color3.fromRGB(20, 29, 41)
	reason.BorderSizePixel = 0
	reason.ClearTextOnFocus = false
	reason.Font = Enum.Font.Gotham
	reason.PlaceholderText = "Grounds, circumstances and custody necessity"
	reason.Text = ""
	reason.TextColor3 = Color3.fromRGB(242, 246, 251)
	reason.TextSize = 13
	reason.TextWrapped = true
	reason.Parent = panel
	corner(reason, 8)
	self.reason = reason

	local create = button(panel, "BOOK INTO CUSTODY")
	create.Position = UDim2.fromOffset(20, 434)
	create.Size = UDim2.new(0.68, -6, 0, 50)
	create.BackgroundColor3 = Color3.fromRGB(43, 112, 184)
	local close = button(panel, "CLOSE")
	close.Position = UDim2.new(0.68, 6, 0, 434)
	close.Size = UDim2.new(0.32, -26, 0, 50)

	local notice = selected:Clone()
	notice.Position = UDim2.fromOffset(20, 494)
	notice.Size = UDim2.new(1, -40, 0, 38)
	notice.Text =
		"Compressed simulation times. Roleplay only — not legal advice or professional training."
	notice.TextWrapped = true
	notice.TextColor3 = Color3.fromRGB(120, 142, 164)
	notice.Parent = panel

	local sentenceHud = Instance.new("Frame")
	sentenceHud.AnchorPoint = Vector2.new(0.5, 0)
	sentenceHud.Size = UDim2.fromOffset(340, 48)
	sentenceHud.BackgroundColor3 = Color3.fromRGB(11, 19, 30)
	sentenceHud.BackgroundTransparency = 0.08
	sentenceHud.BorderSizePixel = 0
	sentenceHud.Visible = false
	sentenceHud.Parent = gui
	corner(sentenceHud, 12)
	local sentenceLabel = Instance.new("TextLabel")
	sentenceLabel.Position = UDim2.fromOffset(14, 7)
	sentenceLabel.Size = UDim2.fromOffset(140, 14)
	sentenceLabel.BackgroundTransparency = 1
	sentenceLabel.Font = Enum.Font.GothamBold
	sentenceLabel.Text = "IN CUSTODY"
	sentenceLabel.TextColor3 = Color3.fromRGB(144, 170, 196)
	sentenceLabel.TextSize = 9
	sentenceLabel.TextXAlignment = Enum.TextXAlignment.Left
	sentenceLabel.Parent = sentenceHud
	local sentenceSub = sentenceLabel:Clone()
	sentenceSub.Position = UDim2.fromOffset(14, 23)
	sentenceSub.Size = UDim2.fromOffset(140, 16)
	sentenceSub.Font = Enum.Font.Gotham
	sentenceSub.Text = "REMAINING SIMULATION TIME"
	sentenceSub.TextColor3 = Color3.fromRGB(224, 232, 241)
	sentenceSub.TextSize = 9
	sentenceSub.Parent = sentenceHud
	local sentenceTime = sentenceLabel:Clone()
	sentenceTime.Position = UDim2.fromOffset(154, 0)
	sentenceTime.Size = UDim2.fromOffset(60, 48)
	sentenceTime.Text = "00:00"
	sentenceTime.TextColor3 = Color3.fromRGB(99, 190, 255)
	sentenceTime.TextSize = 15
	sentenceTime.TextXAlignment = Enum.TextXAlignment.Right
	sentenceTime.Parent = sentenceHud
	self.sentenceHud = sentenceHud
	self.sentenceTime = sentenceTime
	local earlyRelease = button(sentenceHud, "EARLY RELEASE · 19 R$")
	earlyRelease.Position = UDim2.new(1, -104, 0, 6)
	earlyRelease.Size = UDim2.fromOffset(96, 36)
	earlyRelease.BackgroundColor3 = Color3.fromRGB(35, 101, 181)
	earlyRelease.TextSize = 9
	earlyRelease.Visible = false
	self.earlyRelease = earlyRelease
	table.insert(
		self.connections,
		earlyRelease.Activated:Connect(function()
			local credits =
				math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
			if credits > 0 then
				local response =
					self.context.Controllers.NetworkController:Request("UseEarlyReleaseCredit", {})
				if response.Data then
					self.policyMetadata = response.Data
				end
				self.context.Controllers.NotificationController:Show(response.Message, "Custody")
				self:_updateSentenceHud()
				return
			end
			local product = (self.policyMetadata.EarlyReleaseProducts or {})[1]
			local productId = tonumber(product and product.ProductId) or 0
			if productId > 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
			else
				self.context.Controllers.NotificationController:Show(
					"Early release purchases are not configured yet.",
					"Custody"
				)
			end
		end)
	)

	table.insert(
		self.connections,
		launcher.Activated:Connect(function()
			panel.Visible = true
			self:_refreshPlayers()
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
				self.context.Controllers.NotificationController:Show(
					"Select a handcuffed detainee.",
					"Custody"
				)
				return
			end
			local response = self.context.Controllers.NetworkController:Request("BookCustody", {
				TargetUserId = self.targetUserId,
				Reason = reason.Text,
				OffenceCodes = self:_selectedCodeList(),
			})
			self.context.Controllers.NotificationController:Show(response.Message, "Custody")
			if response.Success then
				panel.Visible = false
				reason.Text = ""
				self.targetUserId = nil
				table.clear(self.selectedCodes)
				self:_refreshPolicy()
			end
		end)
	)
end

function CustodyController:Start()
	self:_mount()
	-- Deferred: the serial client Start sequence must not block on an endpoint
	-- the server may not have registered yet.
	task.spawn(function()
		local policyResponse =
			self.context.Controllers.NetworkController:Request("GetCustodyPolicy", {})
		if policyResponse.Success and policyResponse.Data then
			self.policy = policyResponse.Data.Offences or {}
			self.policyMetadata = policyResponse.Data
		end
		self:_refreshPolicy()
		self:_updateSentenceHud()
	end)

	local player = Players.LocalPlayer
	table.insert(
		self.connections,
		player:GetAttributeChangedSignal("RoleplayOSCustodyRemaining"):Connect(function()
			self:_updateSentenceHud()
		end)
	)
	self:_updateSentenceHud()
	self:_refreshAccess(nil)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function(duty)
			self:_refreshAccess(duty)
		end)
	)

	local remote = self.context.Controllers.NetworkController:ResolveEvent("CustodyChanged")
	if remote then
		table.insert(
			self.connections,
			remote.OnClientEvent:Connect(function(payload)
				if payload.Kind == "Caution" then
					self.context.Controllers.NotificationController:Show(
						payload.Text .. "\n\n" .. payload.SimulationNotice,
						"Arrest caution"
					)
				elseif payload.Kind == "SearchNotice" then
					self.context.Controllers.NotificationController:Show(
						"An officer has recorded a search under " .. tostring(payload.Power) .. ".",
						"Search"
					)
				elseif payload.Kind == "EarlyRelease" then
					self.policyMetadata.EarlyReleaseCredits = payload.Credits or 0
					self.context.Controllers.NotificationController:Show(
						"You have been released. Your criminal record remains unchanged.",
						"Custody"
					)
					self:_updateSentenceHud()
				end
			end)
		)
	end

	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Custody", function(layout)
		self.launcher.AnchorPoint = Vector2.new(1, 1)
		self.launcher.Position = UDim2.new(1, -layout.RightReserve, 1, -layout.HotbarBottom)
		self.panelScale.Scale =
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(540, 550), 32)
		-- This interface is mounted with CoreUISafeInsets, so its own origin is
		-- already below the native top bar. Adding NativeTop again pushed the
		-- sentence banner a whole top bar further down the screen.
		self.sentenceHud.Position = UDim2.new(0.5, 0, 0, 10)
	end)
end

function CustodyController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return CustodyController
