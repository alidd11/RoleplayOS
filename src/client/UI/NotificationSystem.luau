--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local COLOURS = {
	Canvas = Color3.fromRGB(15, 20, 28),
	SurfaceRaised = Color3.fromRGB(31, 40, 55),
	Border = Color3.fromRGB(56, 68, 88),
	Text = Color3.fromRGB(240, 244, 251),
	Muted = Color3.fromRGB(174, 184, 201),
	Success = Color3.fromRGB(84, 211, 142),
	Warning = Color3.fromRGB(245, 188, 78),
	Danger = Color3.fromRGB(244, 104, 112),
	Info = Color3.fromRGB(91, 156, 255),
}

local LEVELS = {
	success = { Colour = COLOURS.Success, Label = "SUCCESS" },
	warning = { Colour = COLOURS.Warning, Label = "NOTICE" },
	danger = { Colour = COLOURS.Danger, Label = "ACTION REQUIRED" },
	error = { Colour = COLOURS.Danger, Label = "ACTION REQUIRED" },
	info = { Colour = COLOURS.Info, Label = "INFORMATION" },
}

local System = { toasts = {}, nextId = 0 }

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function motionEnabled(self): boolean
	local settingsController = self.context.Controllers.SettingsController
	local settings = settingsController and settingsController:Get()
	return not settings or settings.InterfaceMotion ~= false
end

function System:Init(context: any)
	self.context = context
	self.toasts = {}
	self.nextId = 0
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("RoleplayOSNotifications")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSNotifications"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 80
	gui.IgnoreGuiInset = false
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui:SetAttribute("RoleplayOSInterfaceMotion", true)
	gui.Parent = playerGui
	self.gui = gui

	local list = Instance.new("Frame")
	list.Name = "ToastStack"
	list.AnchorPoint = Vector2.new(1, 0)
	list.Position = UDim2.new(1, -18, 0, 18)
	list.Size = UDim2.new(0, 360, 1, -36)
	list.BackgroundTransparency = 1
	list.Parent = gui
	self.list = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = list

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(220, 0)
	constraint.MaxSize = Vector2.new(360, math.huge)
	constraint.Parent = list
end

function System:_remove(toast: Frame)
	if not toast.Parent then
		return
	end
	local animated = motionEnabled(self)
	if animated then
		local tween = TweenService:Create(
			toast,
			TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 20, 0, 0) }
		)
		tween:Play()
		tween.Completed:Wait()
	end
	toast:Destroy()
end

function System:Show(message: string, level: string?)
	if not self.list or not self.list.Parent then
		return
	end
	self.nextId += 1
	local key = string.lower(level or "info")
	local style = LEVELS[key] or LEVELS.info

	local toast = Instance.new("Frame")
	toast.Name = "Toast_" .. self.nextId
	toast.LayoutOrder = self.nextId
	toast.Size = UDim2.new(1, 0, 0, 96)
	toast.BackgroundColor3 = COLOURS.SurfaceRaised
	toast.BackgroundTransparency = 0.08
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true
	toast.Parent = self.list
	corner(toast, 10)

	local outline = Instance.new("UIStroke")
	outline.Color = COLOURS.Border
	outline.Transparency = 0.15
	outline.Thickness = 1
	outline.Parent = toast

	local stripe = Instance.new("Frame")
	stripe.Name = "LevelStripe"
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = style.Colour
	stripe.BorderSizePixel = 0
	stripe.Parent = toast

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 11)
	title.Size = UDim2.new(1, -30, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.Text = "ROLEPLAYOS  ·  " .. style.Label
	title.TextColor3 = COLOURS.Text
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = toast

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(18, 32)
	body.Size = UDim2.new(1, -30, 0, 48)
	body.Font = Enum.Font.Gotham
	body.Text = message
	body.TextColor3 = COLOURS.Muted
	body.TextSize = 12
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = toast
	if (key == "danger" or key == "error") and #message > 120 then
		local expanded = false
		local readMore = Instance.new("TextButton")
		readMore.Name = "ReadMore"
		readMore.BackgroundTransparency = 1
		readMore.AnchorPoint = Vector2.new(1, 1)
		readMore.Position = UDim2.new(1, -12, 1, -8)
		readMore.Size = UDim2.fromOffset(82, 18)
		readMore.Font = Enum.Font.GothamBold
		readMore.Text = "Read more"
		readMore.TextColor3 = style.Colour
		readMore.TextSize = 11
		readMore.TextXAlignment = Enum.TextXAlignment.Right
		readMore.ZIndex = 3
		readMore.Parent = toast
		readMore.Activated:Connect(function()
			expanded = not expanded
			body.TextTruncate = if expanded then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
			body.Size = if expanded then UDim2.new(1, -30, 0, 100) else UDim2.new(1, -30, 0, 48)
			readMore.Text = if expanded then "Show less" else "Read more"
			toast.Size = if expanded then UDim2.new(1, 0, 0, 148) else UDim2.new(1, 0, 0, 96)
		end)
	end

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Position = UDim2.new(0, 0, 1, -3)
	progress.Size = UDim2.new(1, 0, 0, 3)
	progress.BackgroundColor3 = style.Colour
	progress.BorderSizePixel = 0
	progress.Parent = toast

	while #self.list:GetChildren() - 1 > 4 do
		local oldest = self.list:FindFirstChildWhichIsA("Frame")
		if oldest then
			self:_remove(oldest)
		else
			break
		end
	end

	if motionEnabled(self) then
		toast.BackgroundTransparency = 1
		toast.Position = UDim2.fromOffset(30, 0)
		TweenService:Create(
			toast,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.08, Position = UDim2.new(0, 0, 0, 0) }
		):Play()
		TweenService:Create(
			progress,
			TweenInfo.new(5, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromOffset(0, 3) }
		):Play()
	else
		progress.Size = UDim2.new(1, 0, 0, 3)
	end

	task.delay(5, function()
		self:_remove(toast)
	end)
end

function System:Destroy()
	if self.gui then
		self.gui:Destroy()
	end
	self.gui = nil
	self.list = nil
	table.clear(self.toasts)
end

return System
