--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Utils = require(script.Utils)
local Shell = require(script.Shell)
local Bank = require(script.Bank)
local Taxi = require(script.Taxi)
local Call = require(script.Call)

local PhoneController = { connections = {}, activeCall = nil }
local PHONE_ACTION = "RoleplayOSTogglePhone"
local money = Utils.money

Shell(PhoneController)
Bank(PhoneController)
Taxi(PhoneController)
Call(PhoneController)

function PhoneController:Init(context: any)
	self.context = context
	self.page = "Home"
	self.watchedTools = setmetatable({}, { __mode = "k" })
end

-- Announces that a full device is on screen. The ambient heads-up display
-- occupies the same corner as the handset, so it stands down rather than
-- fighting it for space; layering alone would leave it visibly underneath.

function PhoneController:Refresh()
	self:_updateClock()
	local response = self.context.Controllers.NetworkController:Request("GetPhone", {})
	if response.Success then
		self.phoneData = response.Data
		local navigation = self.context.Controllers.MinimapController
		local taxi = response.Data.Taxi
		local driverRequest = response.Data.TaxiDriverRequest
		if taxi and taxi.IsDriver == true and taxi.PickupPosition then
			navigation:SetWaypoint(taxi.PickupPosition, "PICKUP")
		elseif driverRequest and driverRequest.PickupPosition then
			navigation:SetWaypoint(driverRequest.PickupPosition, "PICKUP")
		else
			navigation:ClearWaypoint()
		end
		self.number.Text = response.Data.Number
		self.activeCall = response.Data.ActiveCall
		if self.activeCall then
			self:_renderCall()
		else
			self:_render()
		end
	else
		self.number.Text = response.Message
		self:_render()
	end
end

function PhoneController:Start()
	self:_mount()
	local function updateShortcutLabel(lastInputType: Enum.UserInputType)
		if tostring(lastInputType):find("Gamepad") then
			local key = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonY)
			local image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonY)
			self.launcher.Text = if image == ""
				then "PHONE  ·  " .. (if key == "" then "Y" else key)
				else "PHONE"
			self.shortcutGlyph.Image = image
			self.shortcutGlyph.Visible = image ~= ""
		else
			self.launcher.Text = "PHONE  ·  P"
			self.shortcutGlyph.Visible = false
		end
	end
	local function togglePhone(
		_actionName: string,
		inputState: Enum.UserInputState,
		inputObject: InputObject
	): Enum.ContextActionResult
		if
			inputState == Enum.UserInputState.Begin
			and inputObject.KeyCode == Enum.KeyCode.ButtonB
		then
			if not self.body.Visible then
				return Enum.ContextActionResult.Pass
			end
			self.body.Visible = false
			self:_announce(false)
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		if
			inputState ~= Enum.UserInputState.Begin
			or self.hasCharacter ~= true
			or self.vehicleMode == true
			or UserInputService:GetFocusedTextBox() ~= nil
		then
			return Enum.ContextActionResult.Pass
		end
		self.body.Visible = not self.body.Visible
		self:_announce(self.body.Visible)
		if self.body.Visible then
			self:Refresh()
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = self.close
			end
		elseif
			GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.body)
		then
			GuiService.SelectedObject = nil
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(
		PHONE_ACTION,
		togglePhone,
		false,
		Enum.KeyCode.P,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(PHONE_ACTION, "PHONE")
	ContextActionService:SetDescription(PHONE_ACTION, "Open or close your phone.")
	updateShortcutLabel(UserInputService:GetLastInputType())
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(updateShortcutLabel)
	)
	local event = self.context.Controllers.NetworkController:ResolveEvent("PhoneChanged")
	local function watchTool(tool: Instance)
		if
			tool:IsA("Tool")
			and (tool.Name == "Phone" or tool:GetAttribute("RoleplayOSToolId") == "Phone")
			and not self.watchedTools[tool]
		then
			self.watchedTools[tool] = true
			local function open()
				self.body.Visible = true
				self:_announce(true)
				self:Refresh()
			end
			-- Selecting the handset in the toolbar is what takes it out, so the
			-- screen comes up on Equipped. Activated alone was not enough: it only
			-- fires when an already equipped tool is clicked in the world, so
			-- picking the slot appeared to do nothing.
			table.insert(self.connections, tool.Equipped:Connect(open))
			table.insert(self.connections, tool.Activated:Connect(open))
			table.insert(
				self.connections,
				tool.Unequipped:Connect(function()
					-- Putting the handset away closes it, so the screen cannot be
					-- left open while the character is holding something else.
					self.body.Visible = false
					self:_announce(false)
				end)
			)
		end
	end
	local backpack = Players.LocalPlayer:WaitForChild("Backpack")
	for _, item in backpack:GetChildren() do
		watchTool(item)
	end
	table.insert(self.connections, backpack.ChildAdded:Connect(watchTool))
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			table.insert(self.connections, character.ChildAdded:Connect(watchTool))
		end)
	)
	if event then
		table.insert(
			self.connections,
			event.OnClientEvent:Connect(function(update)
				if update.Kind == "TaxiRequest" or update.Kind == "TaxiStatus" then
					self.page = "Taxi"
					self.body.Visible = true
					self:_announce(true)
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						if update.Message then update.Message.Body else "Taxi update received.",
						"Taxi"
					)
				elseif update.Kind == "Text" then
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						"New message received.",
						"Messages"
					)
				elseif update.Kind == "BankTransfer" then
					self:Refresh()
					self.context.Controllers.NotificationController:Show(
						string.format("%s received from %s.", money(update.Amount), update.From),
						"Bank"
					)
				elseif update.Kind == "Call" then
					self.activeCall = if update.Call.State == "Ended" then nil else update.Call
					self.body.Visible = true
					self:_announce(true)
					if self.activeCall then
						self:_renderCall()
					else
						self:_render()
					end
				end
			end)
		)
	end
	table.insert(
		self.connections,
		self.context.Events.CharacterChanged.Event:Connect(function()
			self.hasCharacter = true
			self.launcher.Visible = false
			self:Refresh()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.VehicleModeChanged.Event:Connect(function(active)
			self.vehicleMode = active
			self.launcher.Visible = false
			if active then
				self.body.Visible = false
				self:_announce(false)
			end
		end)
	)
end

function PhoneController:Destroy()
	ContextActionService:UnbindAction(PHONE_ACTION)
	if self.unbindLayout then
		self.unbindLayout()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.gui then
		self.gui:Destroy()
	end
end

return PhoneController
