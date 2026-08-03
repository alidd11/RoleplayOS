--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

export type Layout = {
	Breakpoint: string,
	State: string,
	Viewport: Vector2,
	Compact: boolean,
	Vehicle: boolean,
	Dispatch: boolean,
	NativeTop: number,
	NativeLeft: number,
	HotbarBottom: number,
	RightReserve: number,
	InputMode: string,
	VR: boolean,
}

local UIOrchestrator = {
	connections = {},
	bindings = {},
	state = "OnFoot",
	cameraConnection = nil,
}

function UIOrchestrator:Init(context: any)
	self.context = context
end

function UIOrchestrator:_layout(): Layout
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if viewport.X < 100 or viewport.Y < 100 then
		viewport = Vector2.new(1280, 720)
	end
	local vr = VRService.VREnabled
	local lastInput = UserInputService:GetLastInputType()
	local inputMode = if vr
		then "VR"
		elseif string.find(lastInput.Name, "Gamepad") then "Gamepad"
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch"
		else "KeyboardMouse"
	local breakpoint = if vr
		then "VR"
		elseif viewport.X < 700 then "Compact"
		elseif viewport.X < 1050 then "Tablet"
		else "Desktop"
	local vehicle = self.state == "Driver" or self.state == "Passenger"
	local measuredTop = math.max(0, math.floor(GuiService.TopbarInset.Height + 0.5))
	-- TopbarInset describes the region Roblox leaves free for experience content.
	-- Its left edge moves as Roblox changes the native control cluster, so it must
	-- be measured rather than assumed, otherwise our controls render underneath it.
	local measuredLeft = math.max(0, math.floor(GuiService.TopbarInset.Min.X + 0.5))
	return {
		Breakpoint = breakpoint,
		State = self.state,
		Viewport = viewport,
		Compact = breakpoint == "Compact" or vr,
		Vehicle = vehicle,
		Dispatch = self.state == "DispatchSeat",
		NativeTop = math.max(if vr then 72 else 48, measuredTop),
		NativeLeft = measuredLeft,
		HotbarBottom = if vr then 124 else if vehicle then 112 else 76,
		RightReserve = if vr
			then 64
			else if vehicle then (if breakpoint == "Compact" then 150 else 210) else 18,
		InputMode = inputMode,
		VR = vr,
	}
end

function UIOrchestrator:_publish()
	local layout = self:_layout()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("RoleplayOSUIState", layout.State)
		playerGui:SetAttribute("RoleplayOSBreakpoint", layout.Breakpoint)
		playerGui:SetAttribute("RoleplayOSNativeTopPixels", layout.NativeTop)
		playerGui:SetAttribute("RoleplayOSHotbarBottomPixels", layout.HotbarBottom)
		playerGui:SetAttribute("RoleplayOSReservedRightPixels", layout.RightReserve)
		playerGui:SetAttribute("RoleplayOSInputMode", layout.InputMode)
		playerGui:SetAttribute("RoleplayOSVREnabled", layout.VR)
	end
	for _, callback in self.bindings do
		local ok, problem = pcall(callback, layout)
		if not ok then
			warn("RoleplayOS UI layout binding failed: " .. tostring(problem))
		end
	end
end

function UIOrchestrator:Bind(key: string, callback: (Layout) -> ()): () -> ()
	self.bindings[key] = callback
	local ok, problem = pcall(callback, self:_layout())
	if not ok then
		warn("RoleplayOS UI layout binding failed: " .. tostring(problem))
	end
	return function()
		self.bindings[key] = nil
	end
end

function UIOrchestrator:GetLayout(): Layout
	return self:_layout()
end

function UIOrchestrator:Start()
	table.insert(
		self.connections,
		self.context.Events.UIStateChanged.Event:Connect(function(state)
			if type(state) == "string" then
				self.state = state
				self:_publish()
			end
		end)
	)
	local function watchCamera()
		if self.cameraConnection then
			self.cameraConnection:Disconnect()
			self.cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			self.cameraConnection = camera
				:GetPropertyChangedSignal("ViewportSize")
				:Connect(function()
					self:_publish()
				end)
		end
	end
	watchCamera()
	table.insert(
		self.connections,
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	)
	table.insert(
		self.connections,
		GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
			self:_publish()
		end)
	)
	table.insert(
		self.connections,
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
			self:_publish()
		end)
	)
	table.insert(
		self.connections,
		UserInputService.LastInputTypeChanged:Connect(function()
			self:_publish()
		end)
	)
	table.insert(
		self.connections,
		VRService:GetPropertyChangedSignal("VREnabled"):Connect(function()
			self:_publish()
		end)
	)
	self:_publish()
end

function UIOrchestrator:Destroy()
	if self.cameraConnection then
		self.cameraConnection:Disconnect()
		self.cameraConnection = nil
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.bindings)
end

return UIOrchestrator
