--!strict
--[[
	ModalSystem.luau
	Unified modal overlay for RoleplayOS.
	Replaces 4+ inline modal implementations in DeveloperDashboard.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
	AccentFill = Color3.fromHex("#1F5FD0"),
}

local ModalSystem = {}
ModalSystem.__index = ModalSystem

function ModalSystem.new(context)
	local self = setmetatable({}, ModalSystem)
	self.context = context
	self.interfaceMotion = true

	if context and context.Controllers and context.Controllers.SettingsController then
		local settings = context.Controllers.SettingsController
		if settings.GetSetting then
			self.interfaceMotion = settings:GetSetting("InterfaceMotion") ~= false
		end
	end

	self.activeModal = nil
	self.backdropConnection = nil
	self.escapeConnection = nil

	self.screenGui = Instance.new("ScreenGui")
	self.screenGui.Name = "RoleplayOSModals"
	self.screenGui.ResetOnSpawn = false
	self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.screenGui:SetAttribute("RoleplayOSManagedUI", true)
	self.screenGui.DisplayOrder = 200
	self.screenGui.Parent = playerGui

	return self
end

function ModalSystem:_createBackdrop()
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.ZIndex = 1

	if self.interfaceMotion then
		TweenService:Create(
			backdrop,
			TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.75 }
		):Play()
	else
		backdrop.BackgroundTransparency = 0.75
	end

	return backdrop
end

function ModalSystem:_createCard(config)
	local width = config.Width or 520
	local height = config.Height

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(width, height or 0)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = COLOURS.Surface
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
	card.ZIndex = 2

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 15)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOURS.Border
	stroke.Transparency = 0.82
	stroke.Thickness = 1
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 24)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = card

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text = config.Title or ""
	title.TextColor3 = COLOURS.Text
	title.Font = Enum.Font.GothamBold
	title.TextSize = 23
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = card

	-- Body (Text or Frame)
	local bodyContainer = Instance.new("Frame")
	bodyContainer.Name = "Body"
	bodyContainer.Size = UDim2.fromScale(1, 0)
	bodyContainer.Position = UDim2.fromOffset(0, 40)
	bodyContainer.BackgroundTransparency = 1
	bodyContainer.BorderSizePixel = 0
	bodyContainer.AutomaticSize = Enum.AutomaticSize.Y
	bodyContainer.Parent = card

	if typeof(config.Body) == "string" then
		local bodyText = Instance.new("TextLabel")
		bodyText.Name = "BodyText"
		bodyText.Size = UDim2.fromScale(1, 0)
		bodyText.BackgroundTransparency = 1
		bodyText.Text = config.Body
		bodyText.TextColor3 = COLOURS.Muted
		bodyText.Font = Enum.Font.Gotham
		bodyText.TextSize = 14
		bodyText.TextXAlignment = Enum.TextXAlignment.Left
		bodyText.TextYAlignment = Enum.TextYAlignment.Top
		bodyText.TextWrapped = true
		bodyText.AutomaticSize = Enum.AutomaticSize.Y
		bodyText.Parent = bodyContainer
	elseif typeof(config.Body) == "Instance" then
		config.Body.Parent = bodyContainer
	end

	-- Actions
	local actionsContainer = Instance.new("Frame")
	actionsContainer.Name = "Actions"
	actionsContainer.Size = UDim2.new(1, 0, 0, 40)
	actionsContainer.Position = UDim2.new(0, 0, 1, 16)
	actionsContainer.AnchorPoint = Vector2.new(0, 0)
	actionsContainer.BackgroundTransparency = 1
	actionsContainer.BorderSizePixel = 0
	actionsContainer.Parent = bodyContainer

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionsLayout.Padding = UDim.new(0, 10)
	actionsLayout.Parent = actionsContainer

	if config.Actions then
		for i, action in ipairs(config.Actions) do
			local btn = Instance.new("TextButton")
			btn.Name = "Action_" .. i
			btn.Size = UDim2.fromOffset(0, 36)
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.BackgroundColor3 = action.Primary and COLOURS.AccentFill or COLOURS.SurfaceRaised
			btn.BackgroundTransparency = 0
			btn.BorderSizePixel = 0
			btn.Text = "  " .. action.Label .. "  "
			btn.TextColor3 = COLOURS.Text
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 13
			btn.AutoButtonColor = false
			btn.Selectable = true
			btn.Parent = actionsContainer

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 8)
			btnCorner.Parent = btn

			local btnPadding = Instance.new("UIPadding")
			btnPadding.PaddingLeft = UDim.new(0, 12)
			btnPadding.PaddingRight = UDim.new(0, 12)
			btnPadding.Parent = btn

			local btnScale = Instance.new("UIScale")
			btnScale.Parent = btn
			local function setPressed(pressed: boolean)
				local scale = if pressed then 0.97 else 1
				if self.interfaceMotion then
					TweenService:Create(
						btnScale,
						TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
						{ Scale = scale }
					):Play()
				else
					btnScale.Scale = scale
				end
			end
			btn.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					setPressed(true)
				end
			end)
			btn.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					setPressed(false)
				end
			end)

			btn.Activated:Connect(function()
				-- Close before invoking the callback. A callback may open a replacement
				-- modal; closing afterward would immediately destroy that new modal.
				self:Close()
				if action.Callback then
					action.Callback()
				end
			end)
		end
	end

	-- Animate in
	if self.interfaceMotion then
		card.Size = UDim2.fromOffset(width, height or 0)
		card.BackgroundTransparency = 0.2

		TweenService:Create(
			card,
			TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }
		):Play()

		if not height then
			local currentSize = card.Size
			TweenService:Create(
				card,
				TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = currentSize }
			):Play()
		end
	end

	return card
end

function ModalSystem:Open(config)
	self:Close()

	local backdrop = self:_createBackdrop()
	backdrop.Parent = self.screenGui

	local card = self:_createCard(config)
	card.Parent = self.screenGui

	self.activeModal = {
		backdrop = backdrop,
		card = card,
		dismissable = config.Dismissable ~= false,
	}

	if config.Dismissable ~= false then
		self.backdropConnection = backdrop.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:Close()
			end
		end)

		self.escapeConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == Enum.KeyCode.Escape then
				self:Close()
			end
		end)
	end

	return self.activeModal
end

function ModalSystem:Close()
	if self.backdropConnection then
		self.backdropConnection:Disconnect()
		self.backdropConnection = nil
	end

	if self.escapeConnection then
		self.escapeConnection:Disconnect()
		self.escapeConnection = nil
	end

	if self.activeModal then
		local modal = self.activeModal
		self.activeModal = nil

		if self.interfaceMotion then
			TweenService:Create(
				modal.card,
				TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(
						modal.card.AbsoluteSize.X * 0.96,
						modal.card.AbsoluteSize.Y
					),
				}
			):Play()

			TweenService:Create(
				modal.backdrop,
				TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }
			):Play()

			task.delay(0.2, function()
				if modal.card then
					modal.card:Destroy()
				end
				if modal.backdrop then
					modal.backdrop:Destroy()
				end
			end)
		else
			if modal.card then
				modal.card:Destroy()
			end
			if modal.backdrop then
				modal.backdrop:Destroy()
			end
		end
	end
end

function ModalSystem:Destroy()
	self:Close()
	if self.screenGui then
		self.screenGui:Destroy()
	end
end

return ModalSystem
