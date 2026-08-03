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
	SafeTop: number,
	SafeBottom: number,
	SafeLeft: number,
	SafeRight: number,
	SafeViewport: Vector2,
	HotbarBottom: number,
	RightReserve: number,
	InputMode: string,
	VR: boolean,
}

-- A reserve larger than this share of the screen would hide the interface
-- rather than protect it, so such a report is treated as a measurement fault.
local MAXIMUM_RESERVE_SHARE = 0.4

local function insetArea(mode: Enum.ScreenInsets): Rect?
	-- GetInsetArea only exists on recent clients. A missing method must degrade
	-- to the top bar measurements instead of failing the whole layout pass.
	local ok, area = pcall(function()
		return GuiService:GetInsetArea(mode)
	end)
	return if ok and typeof(area) == "Rect" then area else nil
end

local function reserve(value: number, extent: number): number
	return math.clamp(math.floor(value + 0.5), 0, math.floor(extent * MAXIMUM_RESERVE_SHARE))
end

-- Returns the top, bottom, left and right reserves of the region Roblox leaves
-- free for experience content. The difference between the uninset and
-- CoreUI-safe rectangles already accounts for the top bar, notches, Dynamic
-- Islands, rounded corners and home indicators, so no device-specific constant
-- is needed anywhere in the interface.
local function safeReserves(viewport: Vector2): (number, number, number, number)
	local full = insetArea(Enum.ScreenInsets.None)
	local safe = insetArea(Enum.ScreenInsets.CoreUISafeInsets)
	if full and safe then
		return reserve(safe.Min.Y - full.Min.Y, viewport.Y),
			reserve(full.Max.Y - safe.Max.Y, viewport.Y),
			reserve(safe.Min.X - full.Min.X, viewport.X),
			reserve(full.Max.X - safe.Max.X, viewport.X)
	end
	-- Older clients describe only the top bar band. Assume no bottom reserve
	-- rather than guessing a cutout the engine has not reported.
	local topbar = GuiService.TopbarInset
	local right = if topbar.Max.X > 0 then viewport.X - topbar.Max.X else 0
	return reserve(topbar.Height, viewport.Y),
		0,
		reserve(topbar.Min.X, viewport.X),
		reserve(right, viewport.X)
end

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
	local safeTop, safeBottom, safeLeft, safeRight = safeReserves(viewport)
	return {
		Breakpoint = breakpoint,
		State = self.state,
		Viewport = viewport,
		Compact = breakpoint == "Compact" or vr,
		Vehicle = vehicle,
		Dispatch = self.state == "DispatchSeat",
		NativeTop = math.max(if vr then 72 else 48, measuredTop),
		NativeLeft = measuredLeft,
		SafeTop = safeTop,
		SafeBottom = safeBottom,
		SafeLeft = safeLeft,
		SafeRight = safeRight,
		-- Usable area for interfaces mounted with CoreUISafeInsets. Panels must
		-- size and scale against this rather than the raw viewport, otherwise
		-- they spill under the reserved regions and are clipped.
		SafeViewport = Vector2.new(
			math.max(1, viewport.X - safeLeft - safeRight),
			math.max(1, viewport.Y - safeTop - safeBottom)
		),
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

-- Panels are authored at a fixed pixel size. This returns the UIScale factor
-- that keeps such a panel, plus the requested margin, inside the usable area on
-- the current device. The lower bound only guards against a degenerate viewport
-- report; real devices never reach it.
function UIOrchestrator:FitScale(layout: Layout, design: Vector2, margin: number): number
	local usable = layout.SafeViewport
	return math.clamp(
		math.min(
			(usable.X - margin) / math.max(design.X, 1),
			(usable.Y - margin) / math.max(design.Y, 1)
		),
		0.35,
		1
	)
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
