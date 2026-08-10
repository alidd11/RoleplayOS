--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FineNotificationController = { sequence = 0 }

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

function FineNotificationController:Init(context: any)
	self.context = context
end

function FineNotificationController:_mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSFineNotification"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ClipToDeviceSafeArea = true
	gui.DisplayOrder = 32
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -16)
	banner.Size = UDim2.fromOffset(430, 78)
	banner.BackgroundColor3 = Color3.fromRGB(19, 24, 31)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	corner(banner, 13)
	self.banner = banner

	local accent = Instance.new("Frame")
	accent.Size = UDim2.fromOffset(5, 78)
	accent.BackgroundColor3 = Color3.fromRGB(230, 170, 39)
	accent.BackgroundTransparency = 1
	accent.BorderSizePixel = 0
	accent.Parent = banner
	corner(accent, 3)
	self.accent = accent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.new(1, -34, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = "SPEEDING PENALTY"
	title.TextColor3 = Color3.fromRGB(241, 244, 248)
	title.TextSize = 13
	title.TextTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = banner
	self.title = title

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromOffset(20, 34)
	detail.Size = UDim2.new(1, -34, 0, 34)
	detail.Font = Enum.Font.Gotham
	detail.TextColor3 = Color3.fromRGB(185, 195, 208)
	detail.TextSize = 11
	detail.TextTransparency = 1
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.Parent = banner
	self.detail = detail

	local scale = Instance.new("UIScale")
	scale.Parent = banner
	self.scale = scale
end

function FineNotificationController:_show(payload: any)
	if type(payload) ~= "table" then
		return
	end
	self.sequence += 1
	local sequence = self.sequence
	local points = math.max(0, math.floor(tonumber(payload.Points) or 0))
	local fine = math.max(0, math.floor(tonumber(payload.Fine) or 0))
	self.title.Text = string.format(
		"YOU HAVE BEEN FINED %d %s AND £%d",
		points,
		if points == 1 then "POINT" else "POINTS",
		fine
	)
	local payment = if payload.Status == "Paid"
		then "Deducted from your bank account."
		else "Payment is outstanding."
	self.detail.Text = string.format(
		"Recorded at %d mph in a %d mph limit · %s",
		math.floor(tonumber(payload.RecordedMph) or 0),
		math.floor(tonumber(payload.LimitMph) or 0),
		payment
	)
	self.banner.Visible = true
	self.banner.Position = UDim2.new(0.5, 0, 0, -16)
	self.banner.BackgroundTransparency = 1
	self.accent.BackgroundTransparency = 1
	self.title.TextTransparency = 1
	self.detail.TextTransparency = 1
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(self.banner, info, {
		Position = UDim2.new(0.5, 0, 0, 12),
		BackgroundTransparency = 0.06,
	}):Play()
	TweenService:Create(self.accent, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(self.title, info, { TextTransparency = 0 }):Play()
	TweenService:Create(self.detail, info, { TextTransparency = 0 }):Play()
	task.delay(6, function()
		if self.sequence ~= sequence or not self.banner.Parent then
			return
		end
		local exitInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local tween = TweenService:Create(self.banner, exitInfo, {
			Position = UDim2.new(0.5, 0, 0, -12),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if self.sequence == sequence then
				self.banner.Visible = false
			end
		end)
		TweenService:Create(self.accent, exitInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.title, exitInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(self.detail, exitInfo, { TextTransparency = 1 }):Play()
	end)
end

function FineNotificationController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind(
		"FineNotification",
		function(layout)
			self.scale.Scale = math.min(
				layout.HudScale,
				self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(430, 78), 20)
			)
		end
	)
	local event = self.context.Controllers.NetworkController:ResolveEvent("RoadSafetyFine")
	if event then
		self.connection = event.OnClientEvent:Connect(function(payload)
			self:_show(payload)
		end)
	end
end

function FineNotificationController:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return FineNotificationController
