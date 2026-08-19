--!strict

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local SettingsController = { settings = nil, effectStates = {}, connections = {} }
local SCALE = { Small = 0.9, Standard = 1, Large = 1.1 }
local NATIVE_TEXT_SCALE = {
	[Enum.PreferredTextSize.Medium] = 1,
	[Enum.PreferredTextSize.Large] = 1.05,
	[Enum.PreferredTextSize.Larger] = 1.1,
	[Enum.PreferredTextSize.Largest] = 1.15,
}

function SettingsController:Init(context: any)
	self.context = context
	self.effectStates = setmetatable({}, { __mode = "k" })
end

-- SCALE and NATIVE_TEXT_SCALE together already bound the multiplier to
-- 0.9-1.265, so an absolute per-element floor/ceiling on top of that only
-- overrides sizes the multiplier was never going to threaten: an 8px
-- PhoneController label at Small got bumped to a 10px floor - a 25%
-- *increase* when the player asked for smaller - and the dashboard's 42px
-- monogram was shrunk to a 36px ceiling at every setting, authored size or
-- not. Scaling the authored size directly needs no rescue clamp.
function SettingsController:_scaleValue(): number
	return (SCALE[self.settings.InterfaceScale] or 1)
		* (NATIVE_TEXT_SCALE[GuiService.PreferredTextSize] or 1)
end

function SettingsController:_applyScaleToItem(item: Instance)
	if not self.settings then
		return
	end
	if not (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")) then
		return
	end
	local screenGui = item:FindFirstAncestorWhichIsA("ScreenGui")
	if not screenGui or not screenGui:GetAttribute("RoleplayOSManagedUI") then
		return
	end
	local textItem = item :: TextLabel | TextButton | TextBox
	local baseSize = textItem:GetAttribute("RoleplayOSBaseTextSize")
	if type(baseSize) ~= "number" then
		baseSize = textItem.TextSize
		textItem:SetAttribute("RoleplayOSBaseTextSize", baseSize)
	end
	textItem.TextSize = math.floor(baseSize * self:_scaleValue() + 0.5)
end

function SettingsController:_applyInterfaceScale()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui or not self.settings then
		return
	end
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui:GetAttribute("RoleplayOSManagedUI") then
			gui:SetAttribute("RoleplayOSInterfaceMotion", self.settings.InterfaceMotion)
			for _, item in gui:GetDescendants() do
				self:_applyScaleToItem(item)
			end
		end
	end
end

function SettingsController:_applyContrast()
	local effect = Lighting:FindFirstChild("RoleplayOSHighContrast")
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "RoleplayOSHighContrast"
		effect.Parent = Lighting
	end
	-- Bound to a local rather than casting three times in a row.
	--
	-- A statement beginning with an open bracket can be read as a call on the
	-- previous line, so the formatter guards it with a semicolon. Which formatter
	-- version decides that has changed: the one pinned for the build adds the
	-- semicolons and the newer one does not, so the file could not satisfy both
	-- and the build failed on formatting alone. With no leading bracket there is
	-- nothing to disambiguate and every version agrees.
	local correction = effect :: ColorCorrectionEffect
	correction.Contrast = self.settings.HighContrast and 0.2 or 0
	correction.Saturation = self.settings.HighContrast and -0.05 or 0
	correction.Enabled = self.settings.HighContrast
end

local function isDecorative(item: Instance): boolean
	return item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam")
end

-- Only ever walks the world when the setting is switched on, and only watches
-- for new effects while it stays on. Walking every descendant on each apply,
-- and running a callback for every instance that streams in, both scale with
-- the size of the world rather than with the number of effects in it, which a
-- region-sized map makes very expensive.
function SettingsController:_applyReducedEffects()
	local reduced = self.settings.ReducedEffects == true
	if reduced == self.reducedApplied then
		return
	end
	self.reducedApplied = reduced
	if reduced then
		for _, item in workspace:GetDescendants() do
			if isDecorative(item) then
				if self.effectStates[item] == nil then
					self.effectStates[item] = item.Enabled
				end
				item.Enabled = false
			end
		end
		self.effectWatcher = workspace.DescendantAdded:Connect(function(item)
			if isDecorative(item) then
				self.effectStates[item] = item.Enabled
				item.Enabled = false
			end
		end)
		return
	end
	if self.effectWatcher then
		self.effectWatcher:Disconnect()
		self.effectWatcher = nil
	end
	-- Restore from what was recorded rather than walking the world again. The
	-- record is weak keyed, so effects already collected simply drop out.
	for item, enabled in self.effectStates do
		if item.Parent then
			item.Enabled = enabled
		end
	end
	table.clear(self.effectStates)
end

function SettingsController:Apply()
	if not self.settings then
		return
	end
	self:_applyInterfaceScale()
	self:_applyContrast()
	self:_applyReducedEffects()
	self.context.Events.SettingsChanged:Fire(table.clone(self.settings))
end

function SettingsController:Start()
	table.insert(
		self.connections,
		GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
			self:_applyInterfaceScale()
		end)
	)
	-- _applyInterfaceScale only ever walked what already existed, so anything
	-- built lazily after that walk - toasts, modal cards, tooltips, minimap
	-- captions, MDT rows, phone pages, dispatch rows - kept its authored size
	-- regardless of the setting. Applying the current scale to each new text
	-- item as it is added catches those without re-walking the whole tree.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(
		self.connections,
		playerGui.DescendantAdded:Connect(function(item)
			self:_applyScaleToItem(item)
		end)
	)
	-- Deferred so a not-yet-registered endpoint cannot stall the serial client
	-- Start sequence; Apply re-runs against the interface once settings arrive.
	task.spawn(function()
		local response = self.context.Controllers.NetworkController:Request("GetSettings", {})
		if response.Success then
			self.settings = response.Data
			self:Apply()
		end
	end)
end

function SettingsController:Get(): any
	return self.settings
end

function SettingsController:Update(key: string, value: any): any
	local response = self.context.Controllers.NetworkController:Request("UpdateSettings", {
		[key] = value,
	})
	if response.Success then
		self.settings = response.Data
		self:Apply()
	else
		self.context.Controllers.NotificationController:Show(response.Message, "Settings")
	end
	return response
end

function SettingsController:Destroy()
	if self.effectWatcher then
		self.effectWatcher:Disconnect()
		self.effectWatcher = nil
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.effectStates)
end

return SettingsController
