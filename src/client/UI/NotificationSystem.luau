--!strict
--[[
	NotificationSystem.luau
	Custom toast notification overlay for RoleplayOS.
	Replaces StarterGui:SetCore("SendNotification") with civic-operations styled toasts.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COLOURS = {
	Canvas = Color3.fromHex("#0F141C"),
	Surface = Color3.fromHex("#181F2B"),
	SurfaceRaised = Color3.fromHex("#1F2837"),
	Text = Color3.fromHex("#F0F4FB"),
	Muted = Color3.fromHex("#AEB8C9"),
	Border = Color3.fromHex("#38455C"),
	Accent = Color3.fromHex("#5B9CFF"),
	Success = Color3.fromHex("#54D38E"),
	Warning = Color3.fromHex("#F5BC4E"),
	Danger = Color3.fromHex("#F46870"),
	Info = Color3.fromHex("#5B9CFF"),
	AccentFill = Color3.fromHex("#1F5FD0"),
}

local LEVELS = {
	Success = { Stripe = COLOURS.Success, Icon = "✓" },
	Warning = { Stripe = COLOURS.Warning, Icon = "!" },
	Danger = { Stripe = COLOURS.Danger, Icon = "✕" },
	Info = { Stripe = COLOURS.Info, Icon = "i" },
}

local NotificationSystem = {}
NotificationSystem.__index = NotificationSystem

function NotificationSystem.new(context)
	local self = setmetatable({}, NotificationSystem)
	self.context = context
	self.interfaceMotion = true

	if context and context.Controllers and context.Controllers.SettingsController then
		local settings = context.Controllers.SettingsController
		local values = settings:Get()
		if values then
			self.interfaceMotion = values.InterfaceMotion ~= false
		end
	end

	self.activeToasts = {}
	self.maxToasts = 4
	self.toastHeight = 56
	self.toastGap = 8
	self.dismissSeconds = 5

	self.screenGui = Instance.new("ScreenGui")
	self.screenGui.Name = "RoleplayOSNotifications"
	self.screenGui.ResetOnSpawn = false
	self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.screenGui:SetAttribute("RoleplayOSManagedUI", true)
	self.screenGui.DisplayOrder = 100
	self.screenGui.Parent = playerGui

	self.container = Instance.new("Frame")
	self.container.Name = "Container"
	self.container.Size = UDim2.fromOffset(360, 0)
	self.container.Position = UDim2.new(1, -376, 0, 16)
	self.container.BackgroundTransparency = 1
	self.container.BorderSizePixel = 0
	self.container.AutomaticSize = Enum.AutomaticSize.Y
	self.container.Parent = self.screenGui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, self.toastGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = self.container

	return self
end

function NotificationSystem:_createToast(title: string, message: string, level: string)
	level = LEVELS[level] and level or "Info"
	local config = LEVELS[level]

	local toast = Instance.new("Frame")
	toast.Name = "Toast_" .. level
	toast.Size = UDim2.fromOffset(360, self.toastHeight)
	toast.BackgroundColor3 = COLOURS.SurfaceRaised
	toast.BackgroundTransparency = 0
	toast.BorderSizePixel = 0
	toast.Active = true
	toast.LayoutOrder = #self.activeToasts + 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOURS.Border
	stroke.Transparency = 0.85
	stroke.Thickness = 1
	stroke.Parent = toast

	local accentStripe = Instance.new("Frame")
	accentStripe.Name = "AccentStripe"
	accentStripe.Size = UDim2.new(0, 4, 1, 0)
	accentStripe.Position = UDim2.fromOffset(0, 0)
	accentStripe.BackgroundColor3 = config.Stripe
	accentStripe.BorderSizePixel = 0
	accentStripe.Parent = toast

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 10)
	stripeCorner.Parent = accentStripe

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.fromOffset(20, 20)
	iconLabel.Position = UDim2.fromOffset(12, 12)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = config.Icon
	iconLabel.TextColor3 = config.Stripe
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 14
	iconLabel.Parent = toast

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -44, 0, 16)
	titleLabel.Position = UDim2.fromOffset(36, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = COLOURS.Text
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Parent = toast

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.Size = UDim2.new(1, -44, 0, 16)
	bodyLabel.Position = UDim2.fromOffset(36, 28)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Text = message
	bodyLabel.TextColor3 = COLOURS.Muted
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.TextSize = 12
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	bodyLabel.Parent = toast

	local progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressBar"
	progressBar.Size = UDim2.new(1, -8, 0, 2)
	progressBar.Position = UDim2.new(0, 4, 1, -4)
	progressBar.AnchorPoint = Vector2.new(0, 1)
	progressBar.BackgroundColor3 = config.Stripe
	progressBar.BackgroundTransparency = 0.3
	progressBar.BorderSizePixel = 0
	progressBar.Parent = toast

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progressBar

	return toast, progressBar
end

function NotificationSystem:_animateIn(toast: Frame)
	if not self.interfaceMotion then
		toast.Position = UDim2.fromOffset(0, 0)
		toast.BackgroundTransparency = 0
		return
	end

	toast.Position = UDim2.fromOffset(30, 0)
	toast.BackgroundTransparency = 0.2

	TweenService:Create(
		toast,
		TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0 }
	):Play()
end

function NotificationSystem:_animateOut(toast: Frame, callback: () -> ())
	if not self.interfaceMotion then
		if callback then
			callback()
		end
		return
	end

	local fade = TweenService:Create(
		toast,
		TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(340, self.toastHeight),
		}
	)

	fade.Completed:Connect(function()
		if callback then
			callback()
		end
	end)

	fade:Play()
end

function NotificationSystem:_dismissToast(toast: Frame)
	local toastData
	for i, t in ipairs(self.activeToasts) do
		if t.frame == toast then
			toastData = table.remove(self.activeToasts, i)
			break
		end
	end
	if not toastData then
		return
	end
	if toastData.connection then
		toastData.connection:Disconnect()
		toastData.connection = nil
	end

	self:_animateOut(toast, function()
		if toast.Parent then
			toast:Destroy()
		end
		self:_repositionToasts()
	end)
end

function NotificationSystem:_destroyToastData(toastData)
	if toastData.connection then
		toastData.connection:Disconnect()
		toastData.connection = nil
	end
	if toastData.frame and toastData.frame.Parent then
		toastData.frame:Destroy()
	end
end

function NotificationSystem:_repositionToasts()
	for i, toastData in ipairs(self.activeToasts) do
		toastData.frame.LayoutOrder = i
	end

	while #self.activeToasts > self.maxToasts do
		local oldest = table.remove(self.activeToasts, 1)
		if oldest then
			self:_destroyToastData(oldest)
		end
	end
end

function NotificationSystem:Show(message: string, title: string?, level: string?)
	title = title or "Notification"
	level = level or "Info"

	if #self.activeToasts >= self.maxToasts then
		local oldest = table.remove(self.activeToasts, 1)
		if oldest then
			self:_destroyToastData(oldest)
		end
	end

	local toast, progressBar = self:_createToast(title, message, level)
	toast.Parent = self.container

	local toastData = {
		frame = toast,
		startTime = tick(),
		duration = self.dismissSeconds,
		connection = nil,
	}

	table.insert(self.activeToasts, toastData)
	self:_animateIn(toast)

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not toast or not toast.Parent then
			connection:Disconnect()
			toastData.connection = nil
			return
		end

		local elapsed = tick() - toastData.startTime
		local remaining = math.max(0, toastData.duration - elapsed)
		local progress = remaining / toastData.duration

		progressBar.Size = UDim2.new(progress, -8 * progress, 0, 2)

		if elapsed >= toastData.duration then
			connection:Disconnect()
			toastData.connection = nil
			self:_dismissToast(toast)
		end
	end)
	toastData.connection = connection

	toast.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			connection:Disconnect()
			toastData.connection = nil
			self:_dismissToast(toast)
		end
	end)
end

function NotificationSystem:ShowSuccess(message: string, title: string?)
	self:Show(message, title or "Success", "Success")
end

function NotificationSystem:ShowWarning(message: string, title: string?)
	self:Show(message, title or "Warning", "Warning")
end

function NotificationSystem:ShowDanger(message: string, title: string?)
	self:Show(message, title or "Error", "Danger")
end

function NotificationSystem:ShowInfo(message: string, title: string?)
	self:Show(message, title or "Info", "Info")
end

function NotificationSystem:Destroy()
	for _, toastData in ipairs(self.activeToasts) do
		self:_destroyToastData(toastData)
	end
	if self.screenGui then
		self.screenGui:Destroy()
	end
	self.activeToasts = {}
end

return NotificationSystem
