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

function SettingsController:_applyInterfaceScale()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui or not self.settings then
		return
	end
	local scaleValue = (SCALE[self.settings.InterfaceScale] or 1)
		* (NATIVE_TEXT_SCALE[GuiService.PreferredTextSize] or 1)
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui:GetAttribute("RoleplayOSManagedUI") then
			gui:SetAttribute("RoleplayOSInterfaceMotion", self.settings.InterfaceMotion)
			for _, item in gui:GetDescendants() do
				if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
					local baseSize = item:GetAttribute("RoleplayOSBaseTextSize")
					if type(baseSize) ~= "number" then
						baseSize = item.TextSize
						item:SetAttribute("RoleplayOSBaseTextSize", baseSize)
					end
					item.TextSize = math.clamp(math.floor(baseSize * scaleValue + 0.5), 10, 36)
				end
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
	(effect :: ColorCorrectionEffect).Contrast = self.settings.HighContrast and 0.2 or 0
	(effect :: ColorCorrectionEffect).Saturation = self.settings.HighContrast and -0.05 or 0
	(effect :: ColorCorrectionEffect).Enabled = self.settings.HighContrast
end

function SettingsController:_applyReducedEffects()
	local reduced = self.settings.ReducedEffects
	for _, item in workspace:GetDescendants() do
		if item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
			if self.effectStates[item] == nil then
				self.effectStates[item] = item.Enabled
			end
			item.Enabled = if reduced then false else self.effectStates[item]
		end
	end
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
	table.insert(
		self.connections,
		workspace.DescendantAdded:Connect(function(item)
			if
				self.settings
				and self.settings.ReducedEffects
				and (item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam"))
			then
				self.effectStates[item] = item.Enabled
				item.Enabled = false
			end
		end)
	)
	local response = self.context.Controllers.NetworkController:Request("GetSettings", {})
	if response.Success then
		self.settings = response.Data
		self:Apply()
	end
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
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.effectStates)
end

return SettingsController
