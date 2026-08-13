--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local TooltipSystem = {
	gui = nil,
	active = nil,
}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

function TooltipSystem:Init(_context: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("RoleplayOSTooltips")
	if existing and existing:IsA("ScreenGui") then
		self.gui = existing
		self.active = nil
		return
	end
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOSTooltips"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 250
	gui.IgnoreGuiInset = false
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.Parent = playerGui
	self.gui = gui
	self.active = nil
end

function TooltipSystem:_hide()
	local active = self.active
	self.active = nil
	if active and active.Parent then
		TweenService:Create(active, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
		task.delay(0.1, function()
			if active.Parent then
				active:Destroy()
			end
		end)
	end
end

function TooltipSystem:_show(target: GuiObject, value: string)
	self:_hide()
	if not self.gui or value == "" or not target.Visible then
		return
	end
	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Size = UDim2.fromOffset(260, math.clamp(34 + math.ceil(#value / 36) * 16, 34, 114))
	tooltip.BackgroundColor3 = Color3.fromRGB(31, 40, 55)
	tooltip.BackgroundTransparency = 1
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 10
	tooltip.Parent = self.gui
	corner(tooltip, 8)
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(56, 68, 88)
	outline.Transparency = 0.15
	outline.Parent = tooltip
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 7)
	label.Size = UDim2.new(1, -20, 1, -14)
	label.Font = Enum.Font.Gotham
	label.Text = value
	label.TextColor3 = Color3.fromRGB(240, 244, 251)
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 11
	label.Parent = tooltip
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(800, 600)
	local center = target.AbsolutePosition.X + target.AbsoluteSize.X / 2
	local y = target.AbsolutePosition.Y - 8
	local x = math.clamp(center, 140, viewport.X - 140)
	if y < tooltip.AbsoluteSize.Y + 12 then
		tooltip.AnchorPoint = Vector2.new(0.5, 0)
		y = target.AbsolutePosition.Y + target.AbsoluteSize.Y + 8
	end
	tooltip.Position = UDim2.fromOffset(x, y)
	self.active = tooltip
	TweenService:Create(
		tooltip,
		TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.04 }
	):Play()
end

function TooltipSystem:Attach(target: GuiObject, fullText: string?)
	if not fullText or fullText == "" then
		return
	end
	local token = 0
	target.MouseEnter:Connect(function()
		token += 1
		local current = token
		task.delay(0.4, function()
			if current == token and target:IsDescendantOf(game) then
				self:_show(target, fullText)
			end
		end)
	end)
	target.MouseLeave:Connect(function()
		token += 1
		self:_hide()
	end)
end

function TooltipSystem:Destroy()
	self:_hide()
	if self.gui then
		self.gui:Destroy()
	end
	self.gui = nil
end

return TooltipSystem
