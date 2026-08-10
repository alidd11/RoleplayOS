--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local CLOSE_ACTION = "RoleplayOSCloseStartMenu"

local StartMenuAccessibilityController = {
	connections = {},
	previousSelection = nil :: GuiObject?,
	selectionGeneration = 0,
}

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.find(inputType.Name, "Gamepad", 1, true) == 1
end

local function isUsableButton(item: Instance): boolean
	return item:IsA("GuiButton")
		and item.Visible
		and item.Active
		and item.Selectable
		and item.AbsoluteSize.X >= 1
		and item.AbsoluteSize.Y >= 1
end

local function visualPriority(item: GuiObject): number
	-- Overlays and dialogue actions must receive focus before the page behind
	-- them. Within the same layer, reading order is top-to-bottom, left-to-right.
	return item.ZIndex * 1_000_000 - item.AbsolutePosition.Y * 1_000 - item.AbsolutePosition.X
end

function StartMenuAccessibilityController:Init(context: any)
	self.context = context
	self.playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.menuGui = nil
	self.menuToggle = nil
end

function StartMenuAccessibilityController:_resolveInterface(): boolean
	local menuGui = self.playerGui:FindFirstChild("RoleplayOS")
	local toggleGui = self.playerGui:FindFirstChild("RoleplayOSMenuToggle")
	local toggle = if toggleGui then toggleGui:FindFirstChild("OpenMenu", true) else nil
	if not menuGui or not menuGui:IsA("ScreenGui") or not toggle or not toggle:IsA("GuiButton") then
		return false
	end
	self.menuGui = menuGui
	self.menuToggle = toggle
	return true
end

function StartMenuAccessibilityController:_firstAction(): GuiButton?
	local menuGui = self.menuGui
	if not menuGui or not menuGui.Enabled then
		return nil
	end
	local best: GuiButton? = nil
	local bestPriority = -math.huge
	for _, descendant in menuGui:GetDescendants() do
		if isUsableButton(descendant) then
			local candidate = descendant :: GuiButton
			local priority = visualPriority(candidate)
			if priority > bestPriority then
				best = candidate
				bestPriority = priority
			end
		end
	end
	return best
end

function StartMenuAccessibilityController:_restoreFocusSoon()
	self.selectionGeneration += 1
	local generation = self.selectionGeneration
	task.defer(function()
		if generation ~= self.selectionGeneration then
			return
		end
		local inputType = UserInputService:GetLastInputType()
		if isGamepadInput(inputType) or self.context.Controllers.UIOrchestrator:GetLayout().VR then
			GuiService.SelectedObject = self:_firstAction()
		end
	end)
end

function StartMenuAccessibilityController:_dismissTopLayer(): boolean
	local menuGui = self.menuGui
	if not menuGui then
		return false
	end
	local topLayer: GuiObject? = nil
	for _, child in menuGui:GetDescendants() do
		if child:IsA("GuiObject") and child.Visible and child.ZIndex >= 20 then
			if not topLayer or child.ZIndex > topLayer.ZIndex then
				topLayer = child
			end
		end
	end
	if not topLayer then
		return false
	end
	-- Dialogue children share their backdrop's layer. Destroying the direct
	-- child of Root closes the complete dialogue rather than only one control.
	local root = menuGui:FindFirstChild("Root")
	local layer: Instance = topLayer
	while layer.Parent and layer.Parent ~= root do
		layer = layer.Parent
	end
	if layer.Parent == root then
		layer:Destroy()
		self:_restoreFocusSoon()
		return true
	end
	return false
end

function StartMenuAccessibilityController:_closeMenu()
	if self:_dismissTopLayer() then
		return
	end
	local menuGui = self.menuGui
	local menuToggle = self.menuToggle
	if not menuGui or not menuToggle or not menuGui.Enabled then
		return
	end
	menuGui.Enabled = false
	menuToggle.Visible = true
	self.playerGui:SetAttribute("RoleplayOSMenuOpen", false)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
	end)
	GuiService.SelectedObject = menuToggle
end

function StartMenuAccessibilityController:Start()
	-- The menu mounts after controllers start, so resolve it without assuming a
	-- particular scheduler order.
	while not self:_resolveInterface() do
		self.playerGui.ChildAdded:Wait()
	end

	local menuGui = self.menuGui :: ScreenGui
	table.insert(
		self.connections,
		self.playerGui:GetAttributeChangedSignal("RoleplayOSMenuOpen"):Connect(function()
			if self.playerGui:GetAttribute("RoleplayOSMenuOpen") == true then
				self.previousSelection = GuiService.SelectedObject
				self:_restoreFocusSoon()
			elseif
				GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(menuGui)
			then
				GuiService.SelectedObject = self.previousSelection
			end
		end)
	)
	table.insert(
		self.connections,
		menuGui.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("GuiButton") then
				self:_restoreFocusSoon()
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType)
			if
				isGamepadInput(inputType)
				and self.playerGui:GetAttribute("RoleplayOSMenuOpen") == true
			then
				self:_restoreFocusSoon()
			end
		end)
	)

	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if self.playerGui:GetAttribute("RoleplayOSMenuOpen") ~= true then
			return Enum.ContextActionResult.Pass
		end
		self:_closeMenu()
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	ContextActionService:SetTitle(CLOSE_ACTION, "BACK")
	ContextActionService:SetDescription(CLOSE_ACTION, "Close the current dialogue or menu.")
	self:_restoreFocusSoon()
end

function StartMenuAccessibilityController:Destroy()
	ContextActionService:UnbindAction(CLOSE_ACTION)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.selectionGeneration += 1
	if
		GuiService.SelectedObject
		and self.menuGui
		and GuiService.SelectedObject:IsDescendantOf(self.menuGui)
	then
		GuiService.SelectedObject = self.previousSelection
	end
end

return StartMenuAccessibilityController
