--!strict

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local TooltipSystem = require(script.Parent.TooltipSystem)
local AssetPreloader = require(script.Parent.Parent.Systems.AssetPreloader)
local AudioFeedback = require(script.Parent.Parent.Systems.AudioFeedback)
local Widgets = require(script.Parent.DeveloperDashboardWidgets)
local StorePanel = require(script.StorePanel)
local TutorialsPanel = require(script.TutorialsPanel)
local JobsPanel = require(script.JobsPanel)
local CommunityPanel = require(script.CommunityPanel)

local COLOURS = Widgets.colours
local CIVILIAN_JOB_ROLE_IDS = Widgets.civilianJobRoleIds
local ROLE_DISPLAY_ORDER = Widgets.roleDisplayOrder
local roleTileImageUri = Widgets.roleTileImageUri
local rolePresentation = Widgets.rolePresentation
local portraitPreview = Widgets.portraitPreview
local tileGrid = Widgets.tileGrid
local corner = Widgets.corner
local stroke = Widgets.stroke
local text = Widgets.text
local pressable = Widgets.pressable
local button = Widgets.button
local clear = Widgets.clear
local card = Widgets.card
local posterTile = Widgets.posterTile
local input = Widgets.input

-- Roblox's unified top bar is a 36px band on an unscaled desktop client and
-- carries 32px square icon controls inside it, leaving a 2px gutter above and
-- below. The world menu toggle mirrors those proportions so it reads as one of
-- the native controls; the responsive binding rescales them whenever Roblox
-- reports a taller band (touch, high DPI, VR).
local NATIVE_BAND_HEIGHT = 36
local NATIVE_CONTROL_SIZE = 32
-- Gap Roblox leaves between adjacent top-bar clusters.
local NATIVE_CONTROL_GAP = 8
-- Beyond this the page stops growing and centres instead. A line of text
-- stretched the full width of a large monitor is harder to read, not easier.
local MAXIMUM_CONTENT_WIDTH = 1680
-- How many top-bar heights Roblox's own control cluster spans: the logo, then
-- the pill holding the menu, chat and microphone buttons. Used only as a floor
-- when Roblox reports no inset of its own, so our controls are never drawn
-- underneath its own.

local App = {}
local activeAudioFeedback: any = nil
local activeMountGui: ScreenGui? = nil
function App.mount(context: any): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if activeMountGui and activeMountGui.Parent then
		return activeMountGui
	end

	local function removeStaleLayer(name: string)
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	-- A Rojo sync or a client-script restart can rerun mount without resetting
	-- PlayerGui. Remove only the exact RoleplayOS layers so old dashboards cannot
	-- stack on top of the new one while unrelated HUD systems remain untouched.
	removeStaleLayer("RoleplayOS")
	removeStaleLayer("RoleplayOSMenuToggle")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleplayOS"
	gui:SetAttribute("RoleplayOSManagedUI", true)
	gui.ResetOnSpawn = false
	-- The visual canvas deliberately renders behind Roblox's top bar and device
	-- cutouts. Interactive content is positioned inside the safe region by the
	-- responsive binding below, so the experience stays full bleed without
	-- competing with native Roblox controls.
	gui.IgnoreGuiInset = true
	-- Set ScreenInsets after the legacy IgnoreGuiInset compatibility property;
	-- assigning the legacy property may otherwise rewrite the inset mode.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the gameplay HUD (minimap, needs, progression) which would otherwise
	-- draw over the menu, but below the controls overlay at 90.
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	activeMountGui = gui
	gui.Destroying:Connect(function()
		if activeMountGui == gui then
			activeMountGui = nil
		end
	end)
	local configuration = context.Configuration
	if not configuration then
		local roleplayOS = ReplicatedStorage:WaitForChild("RoleplayOS")
		local configFolder = roleplayOS:WaitForChild("Config")
		configuration = require(configFolder:WaitForChild("Config"))
	end
	local preloader = AssetPreloader.new({ Configuration = configuration })
	local ModalSystem = require(script.Parent.ModalSystem)
	local sharedModalSystem = context.Systems and context.Systems.ModalSystem
	local modalSystem = sharedModalSystem or ModalSystem.new(context)
	local ownsModalSystem = sharedModalSystem == nil
	local CharacterCreator = require(script.Parent.CharacterCreator)
	local characterCreator = CharacterCreator.new(context)
	local sharedAudioFeedback = context.Systems and context.Systems.AudioFeedback
	local audioFeedback: any = sharedAudioFeedback
	local ownsAudioFeedback = false
	if not audioFeedback then
		ownsAudioFeedback = true
		local audioOk, audioResult = pcall(AudioFeedback.new, context)
		if audioOk then
			audioFeedback = audioResult
		else
			warn("[RoleplayOS] Optional audio feedback unavailable: " .. tostring(audioResult))
		end
	end
	activeAudioFeedback = audioFeedback
	Widgets.setAudioFeedback(audioFeedback)
	gui.Destroying:Connect(function()
		preloader:Destroy()
		characterCreator:Destroy()
		if ownsModalSystem then
			modalSystem:Destroy()
		end
		if ownsAudioFeedback and audioFeedback then
			audioFeedback:Destroy()
		end
		if activeAudioFeedback == audioFeedback then
			activeAudioFeedback = nil
			Widgets.setAudioFeedback(nil)
		end
	end)

	local menuToggleGui = Instance.new("ScreenGui")
	menuToggleGui.Name = "RoleplayOSMenuToggle"
	menuToggleGui:SetAttribute("RoleplayOSManagedUI", true)
	menuToggleGui.ResetOnSpawn = false
	-- Roblox's TopbarSafeInsets rectangle begins immediately after the native
	-- logo/chat/voice cluster and changes with voice chat, device orientation,
	-- safe areas and CoreGui visibility. Mounting the button in that rectangle
	-- makes its (0, 0) origin the first genuinely available top-bar position;
	-- estimating the cluster width in gameplay coordinates caused the mobile
	-- button to drift down and overlap the radio/header.
	-- This is an interactive control, so keep it inside Roblox's reported
	-- top-bar safe area. The dashboard canvas itself may remain full-bleed, but
	-- a guessed pixel offset is not stable across phones, notches, voice chat,
	-- or hidden CoreGui controls.
	menuToggleGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	menuToggleGui.ClipToDeviceSafeArea = true
	-- Keep the control above the menu canvas as well as the gameplay HUD. It is
	-- both the opener and the always-available close/back action.
	menuToggleGui.DisplayOrder = 60
	menuToggleGui.Parent = gui.Parent
	-- Keep a compact text label, but place it in the same top row as Roblox's
	-- native controls. A wide desktop pill or a second-row mobile button makes
	-- the experience look like it has two competing navigation systems.
	local menuToggle = Instance.new("TextButton")
	menuToggle.Name = "OpenMenu"
	menuToggle.Size = UDim2.fromOffset(64, NATIVE_CONTROL_SIZE)
	menuToggle.BackgroundColor3 = COLOURS.SurfaceRaised
	menuToggle.BackgroundTransparency = 0.06
	menuToggle.BorderSizePixel = 0
	menuToggle.AutoButtonColor = true
	menuToggle.Text = "MENU"
	menuToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	menuToggle.TextSize = 14
	menuToggle.Font = Enum.Font.GothamBold
	menuToggle.Visible = false
	menuToggle.Selectable = true
	menuToggle.Parent = menuToggleGui
	-- Match the final topbar layout from the first frame. Starting at (8, 8)
	-- caused a visible hop before the responsive binding corrected it, so this
	-- mirrors the centred position the binding settles on.
	menuToggle.Position = UDim2.fromOffset(NATIVE_CONTROL_GAP, 11)
	local menuToggleCorner = Instance.new("UICorner")
	menuToggleCorner.CornerRadius = UDim.new(0, NATIVE_CONTROL_SIZE / 2)
	menuToggleCorner.Parent = menuToggle
	local menuToggleStroke = Instance.new("UIStroke")
	menuToggleStroke.Color = Color3.fromRGB(96, 106, 171)
	menuToggleStroke.Transparency = 0.32
	menuToggleStroke.Parent = menuToggle
	-- A dedicated non-interactive backdrop extends above the legacy GUI origin.
	-- This keeps the visual treatment full bleed even on clients which still
	-- apply the historical top-bar offset to an inset-free ScreenGui.
	local bleedBackdrop = Instance.new("Frame")
	bleedBackdrop.Name = "FullBleedBackdrop"
	bleedBackdrop.BackgroundColor3 = COLOURS.Canvas
	bleedBackdrop.BorderSizePixel = 0
	bleedBackdrop.ZIndex = -10
	bleedBackdrop.Parent = gui
	local bleedGradient = Instance.new("UIGradient")
	bleedGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 35, 70)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(28, 25, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 21, 42)),
	})
	bleedGradient.Rotation = 28
	bleedGradient.Parent = bleedBackdrop

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.Name = "Root"
	root.BackgroundColor3 = COLOURS.Canvas
	root.BorderSizePixel = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOURS.AccentSoft),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(35, 32, 78)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 29, 58)),
	})
	gradient.Rotation = 28
	gradient.Parent = root
	-- Keep the canvas alive without turning it into a screensaver. Two oversized,
	-- low-contrast washes drift behind the UI so the empty areas feel intentional
	-- and the blue/purple brand treatment remains visible when artwork is sparse.
	local ambientBlue = Instance.new("Frame")
	ambientBlue.Name = "AmbientBlue"
	ambientBlue.AnchorPoint = Vector2.new(0.5, 0.5)
	ambientBlue.Position = UDim2.fromScale(0.12, 0.2)
	ambientBlue.Size = UDim2.fromScale(0.8, 0.9)
	ambientBlue.BackgroundColor3 = Color3.fromRGB(32, 92, 190)
	ambientBlue.BackgroundTransparency = 0.94
	ambientBlue.BorderSizePixel = 0
	ambientBlue.ZIndex = -1
	ambientBlue.Parent = root
	local ambientBlueGradient = Instance.new("UIGradient")
	ambientBlueGradient.Color = ColorSequence.new(Color3.fromRGB(45, 118, 235))
	ambientBlueGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.6, 0.74),
		NumberSequenceKeypoint.new(1, 1),
	})
	ambientBlueGradient.Rotation = 24
	ambientBlueGradient.Parent = ambientBlue
	local ambientPurple = Instance.new("Frame")
	ambientPurple.Name = "AmbientPurple"
	ambientPurple.AnchorPoint = Vector2.new(0.5, 0.5)
	ambientPurple.Position = UDim2.fromScale(0.9, 0.78)
	ambientPurple.Size = UDim2.fromScale(0.72, 0.82)
	ambientPurple.BackgroundColor3 = Color3.fromRGB(126, 78, 220)
	ambientPurple.BackgroundTransparency = 0.95
	ambientPurple.BorderSizePixel = 0
	ambientPurple.ZIndex = -1
	ambientPurple.Parent = root
	local ambientPurpleGradient = Instance.new("UIGradient")
	ambientPurpleGradient.Color = ColorSequence.new(Color3.fromRGB(151, 94, 238))
	ambientPurpleGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.62, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	ambientPurpleGradient.Rotation = 202
	ambientPurpleGradient.Parent = ambientPurple

	local loadingOverlay = Instance.new("Frame")
	loadingOverlay.Name = "LoadingExperience"
	loadingOverlay.Size = UDim2.fromScale(1, 1)
	loadingOverlay.BackgroundColor3 = COLOURS.Canvas
	loadingOverlay.BorderSizePixel = 0
	loadingOverlay.ZIndex = 100
	loadingOverlay.Parent = gui
	-- A low-contrast edge wash suggests emergency lighting without putting two
	-- obvious pulsing shapes behind the title. The centre remains calm and legible.
	for index, definition in
		{
			{ Colour = Color3.fromRGB(25, 76, 150), Left = true, Delay = 0 },
			{ Colour = Color3.fromRGB(120, 31, 45), Left = false, Delay = 1.1 },
		}
	do
		local glow = Instance.new("Frame")
		glow.Name = if index == 1 then "BlueEdgeWash" else "RedEdgeWash"
		glow.AnchorPoint = Vector2.new(if definition.Left then 0 else 1, 0)
		glow.Position = UDim2.fromScale(if definition.Left then 0 else 1, 0)
		glow.Size = UDim2.fromScale(0.42, 1)
		glow.BackgroundColor3 = definition.Colour
		glow.BackgroundTransparency = 0
		glow.BorderSizePixel = 0
		glow.ZIndex = 100
		glow.Parent = loadingOverlay
		local edgeGradient = Instance.new("UIGradient")
		edgeGradient.Color = ColorSequence.new(definition.Colour)
		edgeGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.84),
			NumberSequenceKeypoint.new(1, 1),
		})
		edgeGradient.Rotation = if definition.Left then 0 else 180
		edgeGradient.Parent = glow
		-- A restrained static wash reads as emergency-service branding without
		-- flashing behind text or spending render time while this overlay is hidden.
	end
	local loadingTitle =
		text(loadingOverlay, "EMERGENCY RESPONSE: PORTSMOUTH", 25, COLOURS.Text, true)
	loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingTitle.Position = UDim2.fromScale(0.5, 0.44)
	loadingTitle.Size = UDim2.new(1, -48, 0, 38)
	loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
	loadingTitle.ZIndex = 101
	local loadingStatus = text(loadingOverlay, "Preparing your profile…", 14, COLOURS.Muted)
	loadingStatus.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingStatus.Position = UDim2.fromScale(0.5, 0.51)
	loadingStatus.Size = UDim2.new(1, -48, 0, 26)
	loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
	loadingStatus.ZIndex = 101
	local loadingBar = Instance.new("Frame")
	loadingBar.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingBar.Position = UDim2.fromScale(0.5, 0.57)
	loadingBar.Size = UDim2.fromOffset(260, 3)
	loadingBar.BackgroundColor3 = COLOURS.Border
	loadingBar.BorderSizePixel = 0
	loadingBar.ZIndex = 101
	loadingBar.Parent = loadingOverlay
	local loadingFill = Instance.new("Frame")
	loadingFill.Name = "ProgressBar"
	loadingFill.Size = UDim2.fromScale(0, 1)
	loadingFill.BackgroundColor3 = COLOURS.Accent
	loadingFill.BorderSizePixel = 0
	loadingFill.ZIndex = 102
	loadingFill.Parent = loadingBar
	local preloaderInteractive = false
	local loadingFinished = false
	local continueLoading: TextButton? = nil
	local preloaderProgressConnection: RBXScriptConnection? = nil
	local preloaderPhaseConnection: RBXScriptConnection? = nil
	local function interfaceMotionEnabled(): boolean
		local settings = context.Controllers.SettingsController:Get()
		return not settings or settings.InterfaceMotion ~= false
	end
	task.spawn(function()
		if not interfaceMotionEnabled() then
			return
		end
		TweenService:Create(
			gradient,
			TweenInfo.new(18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Offset = Vector2.new(0.28, 0.08) }
		):Play()
		TweenService:Create(
			ambientBlue,
			TweenInfo.new(16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.2, 0.28) }
		):Play()
		TweenService:Create(
			ambientPurple,
			TweenInfo.new(20, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.78, 0.68) }
		):Play()
	end)

	local function updateLoadingStatus(progress: number)
		local statusText = if progress < 0.2
			then "Connecting to server…"
			elseif progress < 0.4 then "Loading vehicles…"
			elseif progress < 0.6 then "Loading equipment…"
			elseif progress < 0.8 then "Preparing menu…"
			elseif progress < 1 then "Finalizing…"
			else "Ready"
		loadingStatus.Text = statusText
		loadingFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	local function finishLoading(force: boolean?)
		if loadingFinished then
			return
		end
		if not force and not preloaderInteractive then
			return
		end
		loadingFinished = true
		if preloaderProgressConnection then
			preloaderProgressConnection:Disconnect()
			preloaderProgressConnection = nil
		end
		if preloaderPhaseConnection then
			preloaderPhaseConnection:Disconnect()
			preloaderPhaseConnection = nil
		end
		preloaderInteractive = true
		if continueLoading then
			continueLoading:Destroy()
			continueLoading = nil
		end
		loadingFill.Size = UDim2.fromScale(1, 1)
		loadingStatus.Text = "Ready"
		loadingStatus.TextColor3 = COLOURS.Muted
		loadingOverlay.BackgroundTransparency = 1
		loadingOverlay.Visible = false
		gui.Enabled = true
		root.Visible = true
	end
	preloaderProgressConnection = preloader.onProgress.Event:Connect(updateLoadingStatus)
	preloaderPhaseConnection = preloader.onPhaseChange.Event:Connect(function(phase: string)
		if loadingFinished then
			return
		end
		if phase == "interactive" then
			preloaderInteractive = true
			loadingOverlay.BackgroundTransparency = 0.6
			continueLoading = button(loadingOverlay, "Continue", true)
			continueLoading.AnchorPoint = Vector2.new(0.5, 1)
			continueLoading.Position = UDim2.new(0.5, 0, 1, -30)
			continueLoading.Size = UDim2.fromOffset(190, 44)
			continueLoading.ZIndex = 103
			continueLoading.Activated:Connect(function()
				if continueLoading then
					continueLoading:Destroy()
					continueLoading = nil
				end
				finishLoading(true)
				if audioFeedback then
					audioFeedback:ButtonClick()
				end
			end)
		elseif phase == "complete" then
			finishLoading()
		end
	end)

	-- Retrying is the thing that actually fixes this, and there was no way to do
	-- it short of rejoining the server.
	local retryLoading = button(loadingOverlay, "Retry", true)
	retryLoading.AnchorPoint = Vector2.new(0.5, 1)
	retryLoading.Position = UDim2.new(0.5, 0, 1, -82)
	retryLoading.Size = UDim2.fromOffset(190, 44)
	retryLoading.ZIndex = 103
	retryLoading.Visible = false
	retryLoading.Activated:Connect(function()
		retryLoading.Active = false
		retryLoading.Text = "Retrying…"
		loadingStatus.Text = "Reconnecting to the server…"
		loadingStatus.TextColor3 = COLOURS.Muted
		task.spawn(function()
			local response = context.Controllers.StartMenuController:Refresh()
			retryLoading.Text = "Retry"
			retryLoading.Active = true
			if response.Success then
				finishLoading()
				return
			end
			loadingStatus.Text = "Could not reach the server."
			loadingStatus.TextColor3 = COLOURS.Danger
			if audioFeedback then
				audioFeedback:Error()
			end
			-- Does not force-finish. A failed retry means the server is still
			-- unreachable, so the honest state is the retry screen staying up with
			-- the button re-enabled, not a menu the player can open with no working
			-- session behind it. Silently promoting past a confirmed failure here is
			-- what caused a player to be dropped into gameplay immediately after
			-- being told the connection failed.
		end)
	end)
	preloader:Start()

	-- Safety net only, not a substitute for the preloader actually finishing.
	--
	-- AssetPreloader now catches its own errors and guarantees it reaches
	-- "interactive"/"complete" even when preloading throws, so this should rarely
	-- if ever fire. It exists for the one case that isn't the preloader's fault:
	-- something else in startup hangs before Start() even runs. Fifteen seconds is
	-- long enough that it will not pre-empt a legitimate slow load, and it never
	-- fires while the retry screen is already up and offering the player a real,
	-- honest way forward.
	task.delay(15, function()
		if not loadingOverlay or not loadingOverlay.Parent or not loadingOverlay.Visible then
			return
		end
		if retryLoading.Visible then
			return
		end
		warn(
			"[RoleplayOS] Startup exceeded 15s without the asset preloader reporting "
				.. "interactive. Promoting to interactive without confirmation; this "
				.. "indicates a real startup bug and should be investigated rather than "
				.. "relied on."
		)
		finishLoading(true)
	end)

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 250, 1, 0)
	sidebar.BackgroundColor3 = COLOURS.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = root
	-- Divides the bar from the content beneath it. Authored for a sidebar down the
	-- left, where it was a hairline on the right edge; in the bar layout that put
	-- a one pixel tick in the top corner and left the bar with no edge at all.
	local sidebarStroke = Instance.new("Frame")
	sidebarStroke.AnchorPoint = Vector2.new(0, 1)
	sidebarStroke.Position = UDim2.fromScale(0, 1)
	sidebarStroke.Size = UDim2.new(1, 0, 0, 1)
	sidebarStroke.BackgroundColor3 = COLOURS.Border
	sidebarStroke.BorderSizePixel = 0
	sidebarStroke.Parent = sidebar

	local brand = text(sidebar, game.Name, 21, COLOURS.Text, true)
	-- The Roblox top bar already identifies the experience. Repeating the game
	-- name inside the dashboard consumed the most valuable part of the compact
	-- header and pushed the useful announcement down.
	brand.Visible = false
	brand.Position = UDim2.fromOffset(26, 20)
	brand.Size = UDim2.new(1, -52, 0, 42)
	brand.TextSize = 17
	brand.TextTruncate = Enum.TextTruncate.None
	brand.TextWrapped = true
	local brandTextConstraint = Instance.new("UITextSizeConstraint")
	brandTextConstraint.MinTextSize = 10
	brandTextConstraint.MaxTextSize = 17
	brandTextConstraint.Parent = brand

	local navigation = Instance.new("Frame")
	navigation.BackgroundTransparency = 1
	navigation.Position = UDim2.fromOffset(18, 112)
	navigation.Size = UDim2.new(1, -36, 0, 190)
	navigation.Parent = sidebar
	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 7)
	navLayout.Parent = navigation
	-- The old Portsmouth experience kept the product navigation at the bottom,
	-- where it stayed available while the large role artwork carried the page.
	-- Keep the original navigation instance as the responsive source of truth,
	-- but render the player-facing controls in a dedicated dock below.
	local bottomDock = Instance.new("Frame")
	bottomDock.Name = "BottomNavigation"
	bottomDock.AnchorPoint = Vector2.new(0.5, 1)
	bottomDock.BackgroundColor3 = COLOURS.Surface
	bottomDock.BackgroundTransparency = 0.08
	bottomDock.BorderSizePixel = 0
	bottomDock.ZIndex = 20
	bottomDock.Parent = root
	corner(bottomDock, 16)
	stroke(bottomDock, COLOURS.Border, 0.12)
	local bottomDockPadding = Instance.new("UIPadding")
	bottomDockPadding.PaddingLeft = UDim.new(0, 8)
	bottomDockPadding.PaddingRight = UDim.new(0, 8)
	bottomDockPadding.PaddingTop = UDim.new(0, 8)
	bottomDockPadding.PaddingBottom = UDim.new(0, 8)
	bottomDockPadding.Parent = bottomDock
	local bottomDockLayout = Instance.new("UIListLayout")
	bottomDockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bottomDockLayout.FillDirection = Enum.FillDirection.Horizontal
	bottomDockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomDockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bottomDockLayout.Padding = UDim.new(0, 8)
	bottomDockLayout.Parent = bottomDock

	local announcementMessages = {
		"Please read the rules before entering Portsmouth",
		"Choose a role, then report for duty",
		"Need help? Open Help for controls and guides",
		"Play fair, keep scenes realistic, and respect other players",
	}
	local announcementIndex = 1
	local announcement =
		text(root, announcementMessages[announcementIndex], 12, COLOURS.Muted, true)
	announcement.Name = "Announcement"
	announcement.AnchorPoint = Vector2.new(0.5, 0)
	announcement.BackgroundColor3 = Color3.fromRGB(31, 25, 48)
	announcement.BackgroundTransparency = 0.12
	announcement.BorderSizePixel = 0
	announcement.TextXAlignment = Enum.TextXAlignment.Center
	announcement.Size = UDim2.fromOffset(420, 28)
	announcement.ZIndex = 18
	announcement.Parent = root
	corner(announcement, 14)
	stroke(announcement, Color3.fromRGB(126, 91, 189), 0.5)
	task.spawn(function()
		while announcement.Parent do
			task.wait(10)
			if not announcement.Parent then
				break
			end
			announcementIndex = announcementIndex % #announcementMessages + 1
			announcement.Text = announcementMessages[announcementIndex]
		end
	end)

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(250, 0)
	content.Size = UDim2.new(1, -250, 1, 0)
	content.Parent = root

	-- A thin status strip where a title block used to be.
	--
	-- The block spent 76 pixels restating the tab the player had just pressed -
	-- "Play. Choose who you want to be today." - and on a phone it was already
	-- hidden, so the space was dead on the device with least of it. The one thing
	-- in it worth keeping is whether the server is actually up, which is now the
	-- whole strip. pageTitle and pageDescription stay as instances because every
	-- render function sets them; they are simply never shown.
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(44, 16)
	header.Size = UDim2.new(1, -88, 0, 24)
	header.Parent = content
	local pageTitle = text(header, "Play", 30, COLOURS.Text, true)
	pageTitle.Size = UDim2.new(1, -220, 0, 40)
	pageTitle.Visible = false
	local pageDescription = text(header, "Choose who you want to be today.", 14, COLOURS.Muted)
	pageDescription.Position = UDim2.fromOffset(0, 41)
	pageDescription.Size = UDim2.new(1, -220, 0, 24)
	pageDescription.Visible = false
	local status = text(header, "●  CONNECTING", 11, COLOURS.Warning, true)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.fromScale(1, 0)
	status.Size = UDim2.fromOffset(190, 24)
	status.TextXAlignment = Enum.TextXAlignment.Right

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(44, 48)
	scroll.Size = UDim2.new(1, -88, 1, -76)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = COLOURS.Border
	scroll.Parent = content
	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Padding = UDim.new(0, 14)
	flow.Parent = scroll

	local menuData: any = nil
	-- The player's own gang, refreshed alongside menuData. Only ever consulted
	-- for one thing here: whether a territory it holds should offer an
	-- additional civilian spawn option alongside the ordinary one.
	local gangStatus: any = nil
	local storeState = { selectedStoreCategory = nil :: string? }
	-- Seeded from the character the player last used, which the server already
	-- sends and nothing read. Without it a returning player picks the same
	-- character again on every join before they can do anything else.
	local selectedCharacterId: string? = nil
	-- Civilian is the only team with character creation. Other teams use the
	-- player's existing character and change uniform/loadout through locker-room
	-- clickers, so their team selection should never open the character editor.
	local selectedTeamId: string? = nil
	-- The menu gates only the first entry. Once the server has accepted a
	-- character or duty entry, a refreshed menu snapshot must not trap the player.
	local hasEnteredWorld = false
	local dismissToWorld: () -> ()
	TooltipSystem:Init(context)
	local function updateMenuToggleAppearance(isOpen: boolean)
		menuToggle.Text = "MENU"
		menuToggle.TextTruncate = Enum.TextTruncate.AtEnd
		menuToggle:SetAttribute("AccessibilityLabel", if isOpen then "Close menu" else "Open menu")
	end
	local function setMenuOpen(isOpen: boolean)
		playerGui:SetAttribute("RoleplayOSMenuOpen", isOpen)
		-- Nothing to go back to yet.
		--
		-- On a first join the menu is the whole game, and a toggle floating over
		-- it offered to dismiss the one screen the player has to use before
		-- anything else works.
		--
		-- Or-ing the closed state in is deliberate rather than belt and braces: a
		-- menu that is shut means the player is in the city whatever route took
		-- them there, and gating purely on the flag would hide their only way
		-- back if any path ever entered the world without setting it.
		menuToggle.Visible = hasEnteredWorld or not isOpen
		updateMenuToggleAppearance(isOpen)
		-- PlayerList stays off: PlayerListController owns it now, permanently.
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not isOpen)
		end)
	end
	playerGui:GetAttributeChangedSignal("RoleplayOSMenuOpen"):Connect(function()
		updateMenuToggleAppearance(playerGui:GetAttribute("RoleplayOSMenuOpen") == true)
	end)
	local function openFromWorld()
		setMenuOpen(true)
		gui.Enabled = true
		context.Controllers.StartMenuController:Refresh()
		root.Position = UDim2.fromOffset(0, 0)
		root.BackgroundTransparency = 0
		if interfaceMotionEnabled() then
			root.Position = UDim2.fromOffset(0, 8)
			root.BackgroundTransparency = 1
			TweenService:Create(
				root,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0 }
			):Play()
		end
	end

	menuToggle.Activated:Connect(function()
		if playerGui:GetAttribute("RoleplayOSMenuOpen") == true and gui.Enabled then
			dismissToWorld()
		else
			openFromWorld()
		end
		if audioFeedback then
			audioFeedback:ButtonClick()
		end
	end)

	local function showCharacterCreationModal(previousError: string?)
		local form = Instance.new("Frame")
		form.Name = "CharacterCreationForm"
		form.Size = UDim2.fromScale(1, 0)
		form.AutomaticSize = Enum.AutomaticSize.Y
		form.BackgroundTransparency = 1
		form.BorderSizePixel = 0
		local creationFlow = Instance.new("UIListLayout")
		creationFlow.SortOrder = Enum.SortOrder.LayoutOrder
		creationFlow.Padding = UDim.new(0, 8)
		creationFlow.Parent = form
		local copy = text(
			form,
			"Name your civilian and set a date of birth. You choose how they look next, "
				.. "and that look is set once.",
			13,
			COLOURS.Muted
		)
		copy.LayoutOrder = 1
		copy.Size = UDim2.new(1, 0, 0, 34)
		copy.TextWrapped = true
		local firstName = input(form, "First name")
		firstName.LayoutOrder = 2
		local lastName = input(form, "Last name")
		lastName.LayoutOrder = 3
		local dateOfBirth = input(form, "Date of birth  ·  YYYY-MM-DD")
		dateOfBirth.LayoutOrder = 4
		local errorLabel = text(form, previousError or "", 12, COLOURS.Danger)
		errorLabel.LayoutOrder = 5
		errorLabel.Size = UDim2.new(1, 0, 0, 28)
		errorLabel.TextWrapped = true
		modalSystem:Open({
			Title = "Create Civilian Character",
			Body = form,
			Actions = {
				{ Label = "Cancel", Primary = false, Callback = function() end },
				{
					Label = "Create civilian character",
					Primary = true,
					Callback = function()
						local response = context.Controllers.CharacterController:Create({
							FirstName = firstName.Text,
							LastName = lastName.Text,
							DateOfBirth = dateOfBirth.Text,
						})
						if response.Success then
							if audioFeedback then
								audioFeedback:Success()
							end
							context.Controllers.StartMenuController:Refresh()
							-- Straight into the creator while the character is new
							-- and its appearance is still free to author. Returning
							-- to the menu first would leave the one unpaid edit
							-- behind a button most players would never press.
							local newId = response.Data and response.Data.CharacterId
							if type(newId) == "string" then
								task.defer(function()
									characterCreator:Open(newId, function()
										context.Controllers.StartMenuController:Refresh()
									end)
								end)
							end
						else
							task.defer(function()
								showCharacterCreationModal(response.Message)
							end)
						end
					end,
				},
			},
			Width = 460,
			Dismissable = true,
		})
	end

	local function showDutySelection(role: any, dutyProfile: any)
		local body = Instance.new("Frame")
		body.Name = "DutySpawnOptions"
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = body
		local copy =
			text(body, "Choose exactly where you want to report for duty.", 13, COLOURS.Muted)
		copy.LayoutOrder = 1
		copy.Size = UDim2.new(1, 0, 0, 30)
		copy.TextWrapped = true
		local spawnOptions = if type(role.Spawns) == "table" then role.Spawns else {}
		local validSpawnCount = 0
		for _, spawnOption in spawnOptions do
			if type(spawnOption) ~= "table" then
				continue
			end
			local spawnId = if type(spawnOption.SpawnId) == "string"
				then spawnOption.SpawnId
				else ""
			if spawnId == "" then
				continue
			end
			local stationName = if type(spawnOption.StationName) == "string"
					and spawnOption.StationName ~= ""
				then spawnOption.StationName
				else "Station"
			local displayName = if type(spawnOption.DisplayName) == "string"
					and spawnOption.DisplayName ~= ""
				then spawnOption.DisplayName
				else string.gsub(spawnId, "_", " ")
			local choiceText = stationName .. "  ·  " .. displayName
			local choice = button(body, choiceText, false)
			TooltipSystem:Attach(choice, choiceText)
			validSpawnCount += 1
			choice.LayoutOrder = 10 + validSpawnCount
			choice.Size = UDim2.new(1, 0, 0, 48)
			choice.Activated:Connect(function()
				choice.Text = "Starting duty…"
				local response = context.Controllers.DutyController:Begin({
					DutyProfileId = dutyProfile.ProfileId,
					RoleId = role.Id,
					StationId = spawnOption.StationId,
					SpawnId = spawnId,
				})
				if response.Success then
					if audioFeedback then
						audioFeedback:Success()
					end
					modalSystem:Close()
					dismissToWorld()
				else
					choice.Text = choiceText
				end
			end)
		end
		if validSpawnCount == 0 then
			modalSystem:Open({
				Title = "Duty unavailable",
				Body = "No valid spawn point is configured for this role.",
				Actions = { { Label = "Close", Primary = true, Callback = function() end } },
				Width = 460,
				Dismissable = true,
			})
			return
		end
		if audioFeedback then
			audioFeedback:PanelOpen()
		end
		modalSystem:Open({
			Title = "Start " .. role.Name,
			Body = body,
			Actions = { { Label = "Cancel", Primary = false, Callback = function() end } },
			Width = 480,
			Dismissable = true,
		})
	end

	local renderPlay: () -> ()
	local function activateRole(role: any)
		if role.Locked then
			if role.Action == "PromptGamepass" then
				local gamepassId = tonumber(role.GamepassId)
				if not gamepassId or gamepassId <= 0 then
					context.Controllers.NotificationController:Show(
						"This pass is not available for purchase yet.",
						"Pass unavailable"
					)
					if audioFeedback then
						audioFeedback:Error()
					end
					return
				end
				local prompted, promptError =
					context.Controllers.GamepassController:Prompt(gamepassId)
				if not prompted then
					context.Controllers.NotificationController:Show(
						promptError or "The Roblox purchase prompt could not be opened.",
						"Purchase unavailable"
					)
					if audioFeedback then
						audioFeedback:Error()
					end
				end
				return
			end
			context.Controllers.NotificationController:Show(
				role.LockMessage,
				if role.Action == "OpenApplication"
					then "Application required"
					else "Access required"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
			selectedTeamId = "Civilian"
			renderPlay()
			scroll.CanvasPosition = Vector2.zero
			return
		end
		if not role.DepartmentId then
			context.Controllers.NotificationController:Show(
				"Select Civilian from the Play screen.",
				"Public role"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		local dutyProfile = nil
		for _, profile in menuData and menuData.DutyProfiles or {} do
			if profile.DepartmentId == role.DepartmentId then
				dutyProfile = profile
				break
			end
		end
		if not dutyProfile or not role.Spawns or #role.Spawns == 0 then
			context.Controllers.NotificationController:Show(
				"No valid duty profile or station is available.",
				"Duty unavailable"
			)
			if audioFeedback then
				audioFeedback:Error()
			end
			return
		end
		selectedTeamId = role.DepartmentId or role.Id
		showDutySelection(role, dutyProfile)
	end

	local renderCommunity: () -> ()
	local renderJobs: () -> ()
	local renderStore: () -> ()
	local renderTutorials: () -> ()
	local renderSettings: () -> ()
	local renderControls: () -> ()
	local currentRender: (() -> ())? = nil
	local selectBottomNav: ((string) -> ())? = nil
	local function shortLandscape(): boolean
		-- SafeViewport can retain the simulator's device-safe padding while the
		-- actual viewport has already rotated. Use the live viewport for the
		-- orientation decision so a phone cannot accidentally take the tall
		-- desktop header branch after a landscape switch.
		local camera = workspace.CurrentCamera
		local viewport = if camera
			then camera.ViewportSize
			else context.Controllers.UIOrchestrator:GetLayout().Viewport
		-- Desktop Studio and laptop clients can report a content height below 720
		-- after Roblox's own top bar is excluded. Require the short axis to be
		-- genuinely phone-sized as well, otherwise desktop uses the phone row and
		-- drops MENU into the page header.
		return viewport.X > viewport.Y and viewport.X < 1000 and viewport.Y < 600
	end
	local function portraitCardColumns(): number
		local width = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		if shortLandscape() then
			return if width >= 980 then 2 else 1
		elseif width >= 1600 then
			return 4
		elseif width >= 1280 then
			return 3
		elseif width >= 720 then
			return 2
		end
		return 1
	end
	-- Play and Civilian Jobs are the same grid of the same tile, so they ask one
	-- place how wide a poster should be. Two copies of this is how the two pages
	-- came to look like different products in the first place.
	--
	-- This is a preference rather than the column count: the grid divides it back
	-- over however many tiles the server actually offers, so a row is never left
	-- short.
	local function posterColumns(): number
		local width = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		if shortLandscape() then
			return 5
		elseif width >= 1280 then
			-- 1280 rather than something wider because that is where an ordinary
			-- laptop sits, and a laptop is where most of this is played.
			return 6
		elseif width >= 1100 then
			return 5
		elseif width >= 900 then
			return 4
		end
		return portraitCardColumns()
	end
	local function posterActionHeight(): number
		return if shortLandscape() then 30 else 34
	end
	-- Below this a poster stops being readable, so a page too short to hold the
	-- grid scrolls rather than shrinking its tiles any further.
	local function posterMinimumHeight(): number
		-- Tall enough for the image and its caption, and no taller.
		--
		-- Two hundred and eight put the caption on the page edge, so the label under
		-- the Civilian poster was cut in half by the bottom of the scroll. The tile
		-- is an image with a label beneath it, and the label belongs inside the tile
		-- rather than against wherever the tile happens to end.
		return if shortLandscape() then 176 else 190
	end
	-- Bumped by every render. A page that asks the server for anything yields,
	-- and clearing the container before the yield does not help: two renders both
	-- clear, both wait, and then both append, so the page appears twice. After a
	-- yield a render checks it is still the current one and gives up if not.
	local renderGeneration = 0
	dismissToWorld = function()
		if not hasEnteredWorld then
			local activeCharacter = menuData and menuData.ActiveCharacterId
			local hasCharacter = (type(activeCharacter) == "string" and activeCharacter ~= "")
				or (type(selectedCharacterId) == "string" and selectedCharacterId ~= "")
			local duty = context.Controllers.DutyController.active
			local hasDuty = type(duty) == "table" and type(duty.DepartmentId) == "string"
			if not hasCharacter and not hasDuty then
				context.Controllers.NotificationController:Show(
					"Create or select a character before entering the city.",
					"Character required"
				)
				if audioFeedback then
					audioFeedback:Error()
				end
				setMenuOpen(true)
				return
			end
			hasEnteredWorld = true
		end
		setMenuOpen(false)
		if not interfaceMotionEnabled() then
			gui.Enabled = false
			return
		end
		TweenService:Create(
			root,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 }
		):Play()
		task.delay(0.17, function()
			gui.Enabled = false
		end)
	end

	-- A heading that is the first thing on a page is not rendered at all.
	--
	-- The navigation bar already names the page, and it names it in the one place
	-- the player just pressed, highlighted. Repeating "Departments" under a lit
	-- "Services" tab told nobody anything they did not know two seconds ago, and
	-- the title with its subtitle cost 42 pixels of a landscape phone's roughly
	-- 260 pixels of visible list: a sixth of the page, spent on a label.
	--
	-- Later headings are kept, because those genuinely separate one block from
	-- the next rather than restating where the player is.
	--
	-- Detected from the layout counter, which clear() resets to zero for each
	-- page, so this stays correct as pages are added or reordered rather than
	-- depending on a list of which headings happen to be first today.
	local function sectionHeading(titleValue: string, subtitle: string)
		if (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) == 0 then
			return
		end
		local compact = shortLandscape()
		local wrapper = Instance.new("Frame")
		wrapper.BackgroundTransparency = 1
		wrapper.Size = UDim2.new(1, 0, 0, if compact then 42 else 54)
		wrapper.Parent = scroll
		local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
		wrapper.LayoutOrder = nextOrder
		local titleItem = text(wrapper, titleValue, 17, COLOURS.Text, true)
		titleItem.Size = UDim2.new(1, 0, 0, if compact then 23 else 28)
		titleItem.TextSize = if compact then 16 else 17
		local subtitleItem = text(wrapper, subtitle, 13, COLOURS.Muted)
		subtitleItem.Position = UDim2.fromOffset(0, if compact then 23 else 29)
		subtitleItem.Size = UDim2.new(1, 0, 0, if compact then 17 else 20)
		subtitleItem.TextSize = if compact then 11 else 13
	end

	renderPlay = function()
		renderGeneration += 1
		clear(scroll)
		pageTitle.Text = "Play"
		pageDescription.Text = if selectedTeamId == "Civilian"
			then "Create or choose a civilian character, then enter the city."
			else "Choose a service or step into civilian life."
		-- Do not render the old role/job layout while the server payload is still
		-- arriving. A single explicit loading state prevents the first-frame flash
		-- that made the retired UX appear to be active.
		if not menuData then
			local loading = card(scroll, if shortLandscape() then 86 else 104)
			local loadingCopy = text(loading, "Loading Portsmouth…", 17, COLOURS.Text, true)
			loadingCopy.Position = UDim2.fromOffset(20, 16)
			loadingCopy.Size = UDim2.new(1, -40, 0, 26)
			local loadingDetail = text(loading, "Preparing roles and characters", 13, COLOURS.Muted)
			loadingDetail.Position = UDim2.fromOffset(20, 48)
			loadingDetail.Size = UDim2.new(1, -40, 0, 20)
			return
		end
		if selectedTeamId ~= nil then
			-- The way back out of a department, on the page the player is stuck
			-- on. The Play tab clears the same filter, but a player who has
			-- drilled into a service is looking at this page rather than at the
			-- dock, and a filtered list with no visible way back reads as the
			-- menu having broken rather than as a filter having been applied.
			--
			-- First in the page, so it is above the tiles that are being filtered
			-- rather than below them.
			local back = button(scroll, "←  ALL TEAMS", false)
			back.Size = UDim2.new(
				0,
				if shortLandscape() then 148 else 180,
				0,
				if shortLandscape() then 32 else 38
			)
			-- Regular weight, one step up. This was the bold face at twelve, which
			-- closes the letterforms before the size does and reads as pixelated
			-- rather than small - the same fault the lighting panel legends had.
			back.Font = Enum.Font.GothamMedium
			back.TextSize = 13
			back.TextColor3 = COLOURS.Accent
			local backStroke = back:FindFirstChildOfClass("UIStroke")
			if backStroke then
				backStroke.Color = COLOURS.Accent
			end
			back.Activated:Connect(function()
				selectedTeamId = nil
				renderPlay()
				scroll.CanvasPosition = Vector2.zero
			end)
		end
		local availableRoles = {}
		local civilianRoles = {}
		local serviceRoles = {}
		for _, role in menuData.Roles or {} do
			if
				role.Visible
				and (selectedTeamId == nil or role.Id == selectedTeamId or role.DepartmentId == selectedTeamId)
				-- Driving a bus is a job somebody does, not a service that answers
				-- calls. It sat between Armed Response and the Prison Service on the
				-- strength of having a team and a uniform, which is how it is built
				-- rather than what it is. Jobs offers it instead, and nothing about
				-- joining it changes. Still reachable here if the player has drilled
				-- into Transport directly.
				and not (selectedTeamId == nil and CIVILIAN_JOB_ROLE_IDS[role.Id])
			then
				if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
					table.insert(civilianRoles, role)
				else
					table.insert(serviceRoles, role)
				end
			end
		end
		-- Civilian stays at the front: it is where a player without a character
		-- has to go, and burying it under the services is how somebody ends up
		-- trying to join a team they have no identity for.
		table.sort(serviceRoles, function(a, b)
			local orderA = ROLE_DISPLAY_ORDER[a.Id] or math.huge
			local orderB = ROLE_DISPLAY_ORDER[b.Id] or math.huge
			if orderA == orderB then
				return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
			end
			return orderA < orderB
		end)
		for _, role in civilianRoles do
			table.insert(availableRoles, role)
		end
		for _, role in serviceRoles do
			table.insert(availableRoles, role)
		end
		-- Says which of the two lists is on screen. Filtered down to one service
		-- the page had gone on calling itself "Start playing" over three policing
		-- roles, which is what made the filter look like a fault rather than a
		-- filter.
		sectionHeading(
			if selectedTeamId == "Civilian"
				then "Civilian"
				elseif selectedTeamId ~= nil then "Selected service"
				else "Start playing",
			if selectedTeamId == "Civilian"
				then "Your character and civilian identity."
				elseif selectedTeamId ~= nil then "Use All teams for the full list."
				else "Choose a service or step into civilian life."
		)
		if #availableRoles > 0 then
			-- Portrait tiles with artwork, a dark lower label band and a full
			-- width action beneath, as the old Portsmouth Play screen had.
			local roleActionHeight = posterActionHeight()
			-- Height comes from the page rather than from a table of pixel
			-- heights per breakpoint.
			--
			-- Those heights were chosen against one window and were wrong in
			-- every other one: on a desktop monitor the two rows finished about
			-- three fifths of the way down and left a band of empty canvas
			-- between the last poster and the navigation dock. Dividing up what
			-- the scrolling frame actually measures puts the whole section on one
			-- page at any size, and where the page is too short to hold it - a
			-- phone, mostly - the minimum keeps the posters legible and the
			-- section scrolls instead.
			--
			-- Drilled into a team the grid shares the page with the character
			-- list, so there it takes a poster's worth of height and leaves the
			-- rest to the characters.
			local focusedTeam = selectedTeamId ~= nil
			local roleGrid = tileGrid(scroll, {
				Name = "RoleGrid",
				Count = #availableRoles,
				Columns = posterColumns(),
				Height = if focusedTeam then (if shortLandscape() then 214 else 312) else nil,
				MinHeight = posterMinimumHeight(),
			})
			-- Characters are the first decision on Play. Keep the role posters below
			-- them so a new player never has to scroll past every department to create
			-- their identity.
			roleGrid.LayoutOrder = 50
			for _, role in availableRoles do
				local presentation = rolePresentation(role)
				local isCivilianRole = role.Id == "Civilian" or role.DepartmentId == "Civilian"
				local _, open = posterTile(roleGrid, {
					Id = tostring(role.Id),
					Image = roleTileImageUri(role),
					Monogram = presentation.Icon,
					Title = tostring(role.Name),
					Accent = presentation.Colour,
					ActionLabel = if role.Locked
						then "REQUIREMENTS"
						elseif isCivilianRole then "CHARACTERS"
						else "JOIN",
					ActionMuted = role.Locked,
					ActionHeight = roleActionHeight,
				})
				open.Activated:Connect(function()
					activateRole(role)
				end)
			end
		end
		if selectedTeamId ~= "Civilian" then
			return
		end
		sectionHeading(
			"Civilian characters",
			"Create your civilian identity here. Team uniforms are selected separately in locker rooms."
		)
		local landscape = shortLandscape()
		local compactViewport = context.Controllers.UIOrchestrator:GetLayout().Viewport
		local compactEmptyCard = compactViewport.X < 1000 or compactViewport.Y < 500
		local function enterCivilian(characterId: string)
			local spawnId: string? = nil
			for _, role in menuData and menuData.Roles or {} do
				if role.Id == "Civilian" then
					for _, spawn in role.Spawns or {} do
						if type(spawn.SpawnId) == "string" and spawn.SpawnId ~= "" then
							spawnId = spawn.SpawnId
							break
						end
					end
				end
				if spawnId then
					break
				end
			end
			if not spawnId then
				context.Controllers.NotificationController:Show(
					"No civilian spawn is configured on this server.",
					"Civilian unavailable"
				)
				if audioFeedback then
					audioFeedback:Error()
				end
				return
			end
			-- EnterCivilian requires the server session's ActiveCharacterId to
			-- match the card being used. Selecting here also makes switching
			-- between civilian identities deterministic instead of relying on a
			-- previous session selection.
			local selected = context.Controllers.CharacterController:Select(characterId)
			if not selected.Success then
				return
			end
			local response = context.Controllers.DutyController:EnterCivilian(characterId, spawnId)
			if response.Success then
				if audioFeedback then
					audioFeedback:Success()
				end
				dismissToWorld()
			end
		end
		if not menuData or #menuData.Characters == 0 then
			local empty =
				card(scroll, if compactEmptyCard then 164 else if landscape then 108 else 150)
			local titleItem = text(empty, "Start your first story", 18, COLOURS.Text, true)
			titleItem.Position =
				UDim2.fromOffset(20, if compactEmptyCard then 14 else if landscape then 13 else 18)
			titleItem.Size = UDim2.new(
				1,
				if compactEmptyCard then -40 else if landscape then -218 else -40,
				0,
				if compactEmptyCard then 28 else if landscape then 34 else 28
			)
			titleItem.TextSize = if compactEmptyCard or landscape then 16 else 18
			titleItem.TextWrapped = compactEmptyCard or landscape
			titleItem.TextTruncate = Enum.TextTruncate.None
			local copy =
				text(empty, "Create a civilian identity to enter the city.", 13, COLOURS.Muted)
			copy.Position =
				UDim2.fromOffset(20, if compactEmptyCard then 45 else if landscape then 42 else 50)
			copy.Size = UDim2.new(
				1,
				if compactEmptyCard then -40 else if landscape then -218 else -40,
				0,
				if compactEmptyCard then 42 else if landscape then 44 else 50
			)
			copy.TextWrapped = true
			copy.TextTruncate = Enum.TextTruncate.None
			local create = button(empty, "Create character", true)
			create.AnchorPoint = if compactEmptyCard then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			create.Position = if compactEmptyCard
				then UDim2.new(0, 20, 1, -14)
				else UDim2.new(1, -20, 0.5, 0)
			create.Size = if compactEmptyCard then UDim2.new(1, -40, 0, 40) else create.Size
			create.Activated:Connect(function()
				showCharacterCreationModal()
			end)
		else
			local columns = portraitCardColumns()
			-- Landscape turns the card on its side rather than shrinking it.
			--
			-- Stacking a portrait above its text needs height, and height is the one
			-- thing a phone held sideways has none of: the list is about 174 pixels
			-- tall, so a 258 card was taller than the area it scrolled inside and its
			-- lower half was never on screen. Width is the plentiful axis, so the
			-- portrait moves beside the text instead of above it and the whole card
			-- fits, with the next one showing beneath to say the list continues.
			-- Side by side whenever the card is wide, not only on a phone held
			-- sideways.
			--
			-- shortLandscape asks whether this is a small screen in landscape - it
			-- requires the long axis to be under a thousand pixels - and the card
			-- orientation was being decided by it. So a desktop, which has more
			-- width than anything, took the portrait branch: a full-width portrait
			-- stacked above its text in a 284 pixel card, with the name, date and
			-- button crammed into the left third of a nine hundred pixel row and
			-- most of the height empty.
			--
			-- The question the card actually needs answered is whether it is wide
			-- enough to put the portrait beside the text, which a desktop always is.
			local viewportWidth = if workspace.CurrentCamera
				then workspace.CurrentCamera.ViewportSize.X
				else 1280
			local sideBySide = landscape or viewportWidth >= 900
			local tileHeight = if sideBySide then 168 else 284
			local extraSlotPass = nil
			for _, pass in menuData.Gamepasses or {} do
				if pass.Id == "ExtraCharacterSlot" and pass.PurchaseType == "DeveloperProduct" then
					extraSlotPass = pass
					break
				end
			end
			local canCreate = menuData.EmptySlots > 0
			local canOfferExtraSlot = not canCreate
				and extraSlotPass ~= nil
				and extraSlotPass.Owned ~= true
			local characterGrid = tileGrid(scroll, {
				Name = "CharacterGrid",
				Count = #menuData.Characters + (if canCreate or canOfferExtraSlot then 1 else 0),
				Columns = columns,
				Height = tileHeight,
			})
			for _, character in menuData.Characters do
				local item = card(characterGrid, tileHeight)
				item.ClipsDescendants = true
				local selected = selectedCharacterId == character.CharacterId
				local selectedRail = Instance.new("Frame")
				selectedRail.BackgroundColor3 = if selected then COLOURS.Success else COLOURS.Accent
				selectedRail.BorderSizePixel = 0
				selectedRail.Size = UDim2.new(1, 0, 0, 4)
				selectedRail.Parent = item
				local preview = portraitPreview(
					item,
					COLOURS.Accent,
					character.PreviewAppearance,
					function()
						return item.Parent == characterGrid
					end
				)
				-- Beside the text in landscape, above it in portrait.
				local textLeft = if sideBySide then 132 else 16
				local textInset = if sideBySide then -148 else -32
				preview.Position = UDim2.fromOffset(12, 12)
				preview.Size = if sideBySide
					then UDim2.fromOffset(108, 144)
					else UDim2.new(1, -24, 0, 132)
				local name = text(item, character.FullName, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(textLeft, if sideBySide then 18 else 156)
				name.Size = UDim2.new(1, textInset, 0, 27)
				local dob = text(item, "Born " .. character.DateOfBirth, 12, COLOURS.Muted)
				dob.Position = UDim2.fromOffset(textLeft, if sideBySide then 48 else 182)
				dob.Size = UDim2.new(1, textInset, 0, 22)
				local identity = text(item, "CIVILIAN CHARACTER", 11, COLOURS.Accent, true)
				identity.Position = UDim2.fromOffset(textLeft, if sideBySide then 74 else 205)
				identity.Size = UDim2.new(1, textInset, 0, 18)
				-- A fixed label restating what the card plainly is. It goes first when
				-- the buttons need the room, which in landscape they do.
				-- Room for it once the card is on its side on a real screen; only a
				-- short landscape phone has to drop it for the button.
				identity.Visible = not landscape
				local choose = button(item, if selected then "Enter city" else "Choose", selected)
				choose.AnchorPoint = Vector2.new(0, 1)
				choose.Position = UDim2.new(0, textLeft, 1, -12)
				choose.Size = UDim2.new(1, textInset, 0, if sideBySide then 38 else 42)
				if
					selected
					and Players.LocalPlayer.Team
					and Players.LocalPlayer.Team.Name == "Civilian"
				then
					choose.Position = UDim2.new(0, textLeft, 1, -12)
					choose.Size = UDim2.new(1, textInset, 0, if landscape then 30 else 36)
					local saveOutfit = button(item, "Save outfit", false)
					saveOutfit.AnchorPoint = Vector2.new(0, 1)
					-- Sat at the same height as the date of birth and the identity line
					-- and drew straight over them, slicing "Born" in half. It stacks above
					-- the choose button now, in space the text no longer claims.
					-- Two actions share this row: keep the Roblox outfit, or author one in
					-- the creator. Stacking them would push the row into the date of birth
					-- on a phone held sideways, so they sit side by side instead.
					local actionRow = if landscape then -46 else -56
					local actionHeight = if landscape then 28 else 30
					local actionSize = UDim2.new(0.5, textInset / 2 - 4, 0, actionHeight)
					saveOutfit.Position = UDim2.new(0, textLeft, 1, actionRow)
					saveOutfit.Size = actionSize
					saveOutfit.TextSize = 11
					saveOutfit.Activated:Connect(function()
						saveOutfit.Text = "Saving…"
						local response =
							context.Controllers.CharacterController:SaveCurrentAppearance(
								character.CharacterId
							)
						if response.Success then
							context.Controllers.NotificationController:Show(
								"This civilian now keeps the current Roblox avatar outfit.",
								"Outfit saved"
							)
							context.Controllers.StartMenuController:Refresh()
						else
							saveOutfit.Text = "Save outfit"
							if audioFeedback then
								audioFeedback:Error()
							end
						end
					end)
					local editLook = button(item, "Edit look", false)
					editLook.AnchorPoint = Vector2.new(0, 1)
					editLook.Position = UDim2.new(0.5, textLeft + textInset / 2 + 4, 1, actionRow)
					editLook.Size = actionSize
					editLook.TextSize = 11
					editLook.Activated:Connect(function()
						editLook.Text = "Checking\u{2026}"
						local state = context.Controllers.CharacterController:AppearanceEditState(
							character.CharacterId
						)
						editLook.Text = "Edit look"
						if not state.Success then
							if audioFeedback then
								audioFeedback:Error()
							end
							return
						end
						local editState = state.Data or {}
						if editState.CanEdit then
							characterCreator:Open(character.CharacterId, function()
								context.Controllers.StartMenuController:Refresh()
							end, editState)
							return
						end
						-- Locked with no edit in hand. The product is the only way back in,
						-- so offer it rather than reporting a dead end the player cannot act on.
						local product = nil
						for _, pass in menuData and menuData.Gamepasses or {} do
							if
								pass.Id == "CharacterAppearanceEdit"
								and pass.PurchaseType == "DeveloperProduct"
							then
								product = pass
								break
							end
						end
						if product and product.ProductId then
							MarketplaceService:PromptProductPurchase(
								Players.LocalPlayer,
								product.ProductId
							)
						else
							context.Controllers.NotificationController:Show(
								"Appearance edits are not on sale on this server yet.",
								"Edit unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
						end
					end)
				elseif
					selected
					and gangStatus
					and gangStatus.Gang
					and type(gangStatus.Gang.TerritoryId) == "string"
					and gangStatus.Gang.TerritoryId ~= ""
				then
					-- An additional way in, not a replacement for the ordinary
					-- one above: a gang holding a territory gets a second
					-- button here, the civilian spawn stays exactly as it was.
					choose.Position = UDim2.new(0, textLeft, 1, -12)
					choose.Size = UDim2.new(1, textInset, 0, if landscape then 30 else 36)
					local territoryName = gangStatus.TerritoryName or "your territory"
					local spawnAtTerritory = button(item, "Spawn at " .. territoryName, false)
					spawnAtTerritory.AnchorPoint = Vector2.new(0, 1)
					spawnAtTerritory.Position =
						UDim2.new(0, textLeft, 1, if landscape then -46 else -56)
					spawnAtTerritory.Size = UDim2.new(1, textInset, 0, if landscape then 28 else 30)
					spawnAtTerritory.TextSize = 11
					spawnAtTerritory.Activated:Connect(function()
						local response =
							context.Controllers.DutyController:EnterCivilianAtTerritory(
								character.CharacterId
							)
						if response.Success and audioFeedback then
							audioFeedback:Success()
						end
					end)
				end
				choose.Activated:Connect(function()
					if selected then
						enterCivilian(character.CharacterId)
						return
					end
					local response =
						context.Controllers.CharacterController:Select(character.CharacterId)
					if response.Success then
						selectedCharacterId = character.CharacterId
						if menuData then
							menuData.ActiveCharacterId = character.CharacterId
						end
						context.Controllers.StartMenuController:Refresh()
						context.Controllers.NotificationController:Show(
							"Character selected.",
							"Ready"
						)
						if audioFeedback then
							audioFeedback:Success()
						end
						renderPlay()
					end
				end)
			end
			if canCreate or canOfferExtraSlot then
				local createCard = card(characterGrid, tileHeight)
				createCard.ClipsDescendants = true
				local createPreview = Instance.new("Frame")
				createPreview.BackgroundColor3 = COLOURS.SurfaceRaised
				createPreview.BorderSizePixel = 0
				createPreview.Position = UDim2.fromOffset(12, 14)
				createPreview.Size = if landscape
					then UDim2.fromOffset(112, 112)
					else UDim2.new(1, -24, 0, 132)
				createPreview.Parent = createCard
				corner(createPreview, 12)
				stroke(createPreview, COLOURS.Accent, 0.62)
				local plus =
					text(createPreview, if canCreate then "+" else "★", 42, COLOURS.Accent, true)
				plus.Size = UDim2.fromScale(1, 1)
				plus.TextXAlignment = Enum.TextXAlignment.Center
				local createTitle = text(
					createCard,
					if canCreate then "New character" else "Extra character slot",
					17,
					COLOURS.Text,
					true
				)
				createTitle.Position = if landscape
					then UDim2.fromOffset(136, 16)
					else UDim2.fromOffset(16, 156)
				createTitle.Size = if landscape
					then UDim2.new(1, -152, 0, 27)
					else UDim2.new(1, -32, 0, 27)
				local createCopy = text(
					createCard,
					if canCreate
						then "Create one separate civilian identity."
						else "Unlock one additional identity with a one-time purchase.",
					13,
					COLOURS.Muted
				)
				createCopy.Position = if landscape
					then UDim2.fromOffset(136, 46)
					else UDim2.fromOffset(16, 185)
				createCopy.Size = if landscape
					then UDim2.new(1, -152, 0, 38)
					else UDim2.new(1, -32, 0, 40)
				createCopy.TextWrapped = true
				local create = button(
					createCard,
					if canCreate then "Create character" else "UNLOCK SLOT",
					not canCreate
				)
				create.AnchorPoint = Vector2.new(0, 1)
				create.Position = if landscape
					then UDim2.new(0, 136, 1, -14)
					else UDim2.new(0, 16, 1, -14)
				create.Size = if landscape
					then UDim2.new(1, -152, 0, 34)
					else UDim2.new(1, -32, 0, 42)
				create.Activated:Connect(function()
					if canCreate then
						showCharacterCreationModal()
					elseif extraSlotPass and extraSlotPass.ProductId then
						MarketplaceService:PromptProductPurchase(
							Players.LocalPlayer,
							extraSlotPass.ProductId
						)
					end
				end)
			end
		end
	end

	renderJobs = JobsPanel.create({
		context = context,
		scroll = scroll,
		pageTitle = pageTitle,
		pageDescription = pageDescription,
		sectionHeading = sectionHeading,
		getMenuData = function()
			return menuData
		end,
		getSelectedCharacterId = function()
			return selectedCharacterId
		end,
		civilianJobRoleIds = CIVILIAN_JOB_ROLE_IDS,
		colours = COLOURS,
		clear = clear,
		card = card,
		text = text,
		shortLandscape = shortLandscape,
		posterActionHeight = posterActionHeight,
		posterColumns = posterColumns,
		posterMinimumHeight = posterMinimumHeight,
		tileGrid = tileGrid,
		posterTile = posterTile,
		rolePresentation = rolePresentation,
		roleTileImageUri = roleTileImageUri,
		activateRole = activateRole,
		audioFeedback = audioFeedback,
		dismissToWorld = dismissToWorld,
		nextGeneration = function()
			renderGeneration += 1
		end,
	})

	renderStore = StorePanel.create({
		context = context,
		scroll = scroll,
		pageTitle = pageTitle,
		pageDescription = pageDescription,
		sectionHeading = sectionHeading,
		state = storeState,
		colours = COLOURS,
		nextGeneration = function()
			renderGeneration += 1
		end,
		clear = clear,
		card = card,
		text = text,
		button = button,
		corner = corner,
		stroke = stroke,
		TooltipSystem = TooltipSystem,
		Players = Players,
		MarketplaceService = MarketplaceService,
	})

	local tutorials = {
		{
			Title = "Starting your character",
			Summary = "Create an identity, choose a role and enter Portsmouth.",
			Body = "Create or select a civilian character under Players. Careers then shows every public and whitelisted role available to you. Locked cards explain the exact requirement.",
		},
		{
			Title = "Emergency calls",
			Summary = "Learn how calls reach Control, MDT and responding units.",
			Body = "Use the phone to contact 999. Control creates and grades an incident, assigns available units and updates its status. Relevant emergency teams receive the server-local call through their MDT.",
		},
		{
			Title = "Police and custody",
			Summary = "Understand cautions, arrest, transport and booking.",
			Body = "Police tools are server-authorised. Officers caution and restrain a nearby player, transport them to custody and complete booking. Charges determine the custody duration and persistent record.",
		},
		{
			Title = "Vehicles and dealerships",
			Summary = "Buy, spawn and keep your registered vehicles.",
			Body = "Visit a dealership prompt to browse civilian vehicles. Owned vehicles retain their registration. Service depots show vehicles allowed by your current role, rank and division.",
		},
		{
			Title = "Controls and accessibility",
			Summary = "See the correct inputs for your current device.",
			Body = "Open Controls for keyboard, touch, gamepad, console and VR bindings. Roblox prompts remain the authority for contextual interactions such as dealerships and dispatch seats.",
		},
	}

	renderTutorials = TutorialsPanel.create({
		context = context,
		scroll = scroll,
		pageTitle = pageTitle,
		pageDescription = pageDescription,
		sectionHeading = sectionHeading,
		colours = COLOURS,
		tutorials = tutorials,
		nextGeneration = function()
			renderGeneration += 1
		end,
		clear = clear,
		card = card,
		text = text,
		button = button,
		pressable = pressable,
		corner = corner,
		modalSystem = modalSystem,
		renderControls = function()
			renderControls()
		end,
		renderSettings = function()
			renderSettings()
		end,
	})

	-- Three questions, in the order somebody actually asks them: where am I, where
	-- else can I go, and what about my own community.
	--
	-- The page used to open on a tall block of marketing copy, carried two
	-- headings both called "Your server", and left the servers you could actually
	-- join below the fold. Nothing here is decoration: the status strip answers
	-- the first question in one line so the rest of the page can be the answer to
	-- the second.
	renderCommunity = CommunityPanel.create({
		context = context,
		scroll = scroll,
		pageTitle = pageTitle,
		pageDescription = pageDescription,
		sectionHeading = sectionHeading,
		getMenuData = function()
			return menuData
		end,
		colours = COLOURS,
		clear = clear,
		card = card,
		text = text,
		corner = corner,
		pressable = pressable,
		audioFeedback = audioFeedback,
		nextGeneration = function()
			renderGeneration += 1
			return renderGeneration
		end,
		currentGeneration = function()
			return renderGeneration
		end,
	})

	local activeNav: TextButton? = nil
	-- isAction entries run their callback without taking the selected-page
	-- highlight, so overlays like Controls do not blank the content area.
	local function addNav(labelValue: string, render: () -> (), isAction: boolean?)
		local item = Instance.new("TextButton")
		item.AutoButtonColor = false
		item.BackgroundColor3 = COLOURS.Sidebar
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamMedium
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 14
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Size = UDim2.new(1, 0, 0, 40)
		item.Parent = navigation
		corner(item, 8)
		local itemPadding = Instance.new("UIPadding")
		itemPadding.PaddingLeft = UDim.new(0, 14)
		itemPadding.Parent = item
		pressable(item)
		item.Activated:Connect(function()
			if isAction then
				render()
				return
			end
			if activeNav then
				activeNav.BackgroundColor3 = COLOURS.Sidebar
				activeNav.TextColor3 = COLOURS.Muted
			end
			activeNav = item
			currentRender = render
			item.BackgroundColor3 = COLOURS.AccentSoft
			item.TextColor3 = COLOURS.Text
			render()
		end)
		return item
	end

	local playNav = addNav("Play", renderPlay)
	-- Civilian Jobs sits beside Play because it is somewhere to go and be, not
	-- something to buy. Without it the taxi shift has no entry point anywhere in
	-- the client. It is named for who the work is for: next to five emergency
	-- services, "Jobs" read as the place a player would look for a police job.
	addNav("Civilian Jobs", renderJobs)
	addNav("Store", renderStore)
	addNav("Servers", renderCommunity)
	addNav("Help", renderTutorials)
	navigation.Visible = false
	activeNav = playNav
	currentRender = renderPlay
	playNav.BackgroundColor3 = COLOURS.AccentSoft
	playNav.TextColor3 = COLOURS.Text

	local profile = card(sidebar, 68)
	profile.AnchorPoint = Vector2.new(0, 1)
	profile.Position = UDim2.new(0, 18, 1, -20)
	profile.Size = UDim2.new(1, -36, 0, 68)
	local playerName = text(profile, Players.LocalPlayer.DisplayName, 14, COLOURS.Text, true)
	playerName.Position = UDim2.fromOffset(14, 11)
	playerName.Size = UDim2.new(1, -28, 0, 24)
	local environment = text(profile, "Development environment", 11, COLOURS.Muted)
	environment.Position = UDim2.fromOffset(14, 35)
	environment.Size = UDim2.new(1, -28, 0, 20)

	local bottomNavItems: { [string]: TextButton } = {}
	local bottomNavRenders: { [string]: () -> () } = {}
	-- Run when the tab is pressed, and deliberately not stored as part of the
	-- render: currentRender is replayed on every server refresh and on every
	-- breakpoint change, so anything that resets what the player is looking at
	-- has to hang off the press instead of off the page.
	local bottomNavEnters: { [string]: () -> () } = {}
	local bottomNavOrder = 0
	-- Play is the single role-selection route. The dock only exposes the four
	-- destinations players need during a session; departments are filtered and
	-- joined from the Play screen itself.
	local bottomNavCount = 5
	selectBottomNav = function(key: string)
		local item = bottomNavItems[key]
		local render = bottomNavRenders[key]
		if not item or not render then
			return
		end
		for _, other in bottomNavItems do
			other.BackgroundColor3 = COLOURS.Surface
			other.TextColor3 = COLOURS.Muted
		end
		item.BackgroundColor3 = COLOURS.AccentFill
		item.TextColor3 = COLOURS.Text
		local enter = bottomNavEnters[key]
		if enter then
			enter()
		end
		currentRender = render
		render()
	end
	local function addBottomNav(
		labelValue: string,
		render: () -> (),
		key: string,
		onEnter: (() -> ())?
	)
		bottomNavOrder += 1
		local item = Instance.new("TextButton")
		item.Name = key .. "Tab"
		item.AutoButtonColor = false
		item.BackgroundColor3 = COLOURS.Surface
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamBold
		item.Text = labelValue
		item.TextColor3 = COLOURS.Muted
		item.TextSize = 13
		-- Every tab gets an equal fifth of the dock, and the words are not of
		-- equal length: "Civilian Jobs" wants about ninety pixels and its share on
		-- a phone is nearer sixty. The dock is two lines tall, so the label uses
		-- the second one rather than running out over the tab beside it.
		item.TextWrapped = true
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.LayoutOrder = bottomNavOrder
		item.Size = UDim2.new(1 / bottomNavCount, -10, 1, 0)
		item.Selectable = true
		item.ZIndex = 21
		item.Parent = bottomDock
		corner(item, 10)
		stroke(item, COLOURS.Border, 0.25)
		pressable(item, true)
		bottomNavItems[key] = item
		bottomNavRenders[key] = render
		if onEnter then
			bottomNavEnters[key] = onEnter
		end
		item.Activated:Connect(function()
			if selectBottomNav then
				selectBottomNav(key)
			end
		end)
	end
	-- The same route names and callbacks are used by the compact dock and the
	-- desktop fallback sidebar, so changing page selection never leaves one of
	-- them highlighting a different destination.
	-- Pressing Play always lands on the full team list.
	--
	-- Joining a department leaves the page filtered to that department's own
	-- roles, and nothing was clearing that: a player who pressed JOIN on the
	-- Roads Policing Unit and then cancelled the station picker was left on a
	-- Play page offering the three policing roles and no route back to Civilian
	-- or to any other service. Rejoining the game was the only way out. The tab
	-- is the escape hatch a player reaches for first, so it clears the filter
	-- before rendering; the back control on the page itself is the other half.
	addBottomNav("Play", renderPlay, "Play", function()
		selectedTeamId = nil
	end)
	-- The label changes; the key does not. It is what the dock highlights by and
	-- what the desktop fallback matches on.
	addBottomNav("Civilian Jobs", renderJobs, "Jobs")
	addBottomNav("Store", renderStore, "Store")
	addBottomNav("Servers", renderCommunity, "Servers")
	addBottomNav("Help", renderTutorials, "Help")
	local defaultDockItem = bottomNavItems.Play
	if defaultDockItem then
		defaultDockItem.BackgroundColor3 = COLOURS.AccentFill
		defaultDockItem.TextColor3 = COLOURS.Text
	end

	local function navCount(): number
		local count = 0
		for _, item in navigation:GetChildren() do
			if item:IsA("TextButton") then
				count += 1
			end
		end
		return math.max(1, count)
	end
	local lastResponsiveKey: string? = nil

	context.Controllers.UIOrchestrator:Bind("DeveloperDashboard", function(layout)
		local safeTop = layout.NativeTop
		local navItems = navCount()
		bleedBackdrop.Position = UDim2.fromOffset(0, -safeTop)
		-- Measured live: AbsolutePosition.Y lands at -2*safeTop even though
		-- Position is authored at -safeTop, on whatever produces that extra
		-- shift here (Studio's own Play viewport, observed while testing this).
		-- The backdrop's height only ever grew by the single safeTop, so its
		-- bottom edge fell exactly safeTop short of the true screen bottom --
		-- a real gap, and the speedometer's bottom-anchored HUD sat in it,
		-- read through the open menu as a second, unrelated gauge. Growing the
		-- height by the same amount the position already shifted keeps the
		-- bottom edge flush regardless of where that extra shift comes from.
		bleedBackdrop.Size = UDim2.new(1, 0, 1, safeTop * 2)
		-- Size the toggle from the band Roblox actually reports. Its position is
		-- deliberately relative to TopbarSafeInsets above, never to the gameplay
		-- viewport or a guessed native-cluster width.
		local reportedBand = math.floor(GuiService.TopbarInset.Height + 0.5)
		local nativeBand = if reportedBand > 0 then reportedBand else NATIVE_BAND_HEIGHT
		-- Sized and centred against Roblox's own controls rather than filling the
		-- band.
		--
		-- Measured on a running client: the native band is 58 high, its controls
		-- end at x=208, and a TopbarSafeInsets origin of (0, 0) already resolves
		-- to exactly 208 -- so the horizontal position was never the problem and
		-- adding NativeLeft here would double-count it, which is what the note
		-- about the 248px cluster guess was warning against.
		--
		-- The vertical was wrong. At 0.78 of the band the button came out 45 high
		-- against Roblox's ~36, and a fixed 2px gutter pinned it to the top of the
		-- row, so it read as taller than the native controls and sitting above
		-- them. Matching their proportion and centring it in the band puts the two
		-- on the same line at the same weight, which is what makes it look native
		-- rather than bolted on.
		local controlSize = math.clamp(math.floor(nativeBand * 0.62 + 0.5), 28, 44)
		local menuWidth = math.floor(controlSize * 1.9 + 0.5)
		menuToggle.Size = UDim2.fromOffset(math.clamp(menuWidth, 58, 78), controlSize)
		menuToggleCorner.CornerRadius = UDim.new(0, math.floor(controlSize * 0.34 + 0.5))
		local bandGap = math.max(0, math.floor((nativeBand - controlSize) / 2 + 0.5))
		menuToggle.Position = UDim2.fromOffset(NATIVE_CONTROL_GAP, bandGap)
		-- Compact already accounts for a short landscape phone, so the height is
		-- not tested again here.
		-- One navigation language on every device: a top bar mirrors Roblox's
		-- established menu pattern and avoids presenting desktop players with a
		-- completely different sidebar information architecture.
		local narrow = layout.SafeViewport.X < 720
		-- Landscape phones have a short usable height but a wide viewport. Keep
		-- their header in a dedicated compact row instead of applying desktop
		-- title/navigation offsets that overlap on-screen controls.
		local compactLandscape = layout.SafeViewport.Y < 500
			and layout.SafeViewport.X > layout.SafeViewport.Y
		local safeLeft = layout.SafeLeft
		local safeRight = layout.SafeRight
		-- On a landscape phone Roblox's native controls consume the whole first
		-- row. Give the product identity and tabs their own row below it instead
		-- of placing the title into the native logo/chat/microphone cluster.
		-- Tall enough to actually contain the row, and no taller.
		--
		-- Measured on a running client at 1365x768: the band ended at y=38
		-- while the navigation row ran to y=50, so the tabs sat twelve pixels
		-- over the top of the content beneath them. On a narrow screen it was
		-- worse -- the title occupied 38..68 and the tabs 44..76, overlapping
		-- each other as well as the content, because both were positioned from
		-- the band top with no regard for the other's height.
		--
		-- These are now derived from what the row holds rather than picked, so
		-- the band shrinks and the overlap goes at the same time: the content
		-- below gains the twelve pixels it was losing plus the reduction.
		-- The bar holds one line of status text and nothing else, so it is sized
		-- to that line rather than to a comfortable row. Every pixel taken off
		-- here goes to the posters, which is the only thing on this page a
		-- player is actually looking at.
		local barHeight = safeTop + (if narrow then 56 else if compactLandscape then 36 else 26)
		sidebar.Size = UDim2.new(1, 0, 0, barHeight)
		content.Position = UDim2.fromOffset(0, barHeight)
		content.Size = UDim2.new(1, 0, 1, -barHeight)
		-- In this stacked layout the title shares its row with Roblox's own
		-- controls, which sit at the top left. safeLeft only describes a
		-- device cutout, so clearing that alone left the title underneath
		-- them in portrait, where the control cluster is proportionally much
		-- wider. NativeLeft is where Roblox reports its controls end.
		local headerLeft = if compactLandscape
			then safeLeft + 18
			else math.max(safeLeft, layout.NativeLeft) + 18
		-- Keep the product name directly below Roblox's native control band.
		-- It should read as the experience identity, not compete with Roblox's
		-- own logo, chat and microphone controls.
		brand.Position = UDim2.fromOffset(
			headerLeft,
			if narrow then safeTop + 6 elseif compactLandscape then safeTop + 6 else safeTop + 8
		)
		brand.Size = UDim2.fromOffset(
			if compactLandscape
				then math.max(160, layout.SafeViewport.X - headerLeft - safeRight - 36)
				elseif narrow then math.max(
					80,
					layout.SafeViewport.X - headerLeft - safeRight - 18
				)
				else 270,
			30
		)
		brand.TextSize = 14
		brand.TextWrapped = false
		brand.TextScaled = false
		brand.TextTruncate = Enum.TextTruncate.AtEnd
		local brandBounds = brand:FindFirstChildOfClass("UITextSizeConstraint")
		if not brandBounds then
			brandBounds = Instance.new("UITextSizeConstraint")
			brandBounds.Parent = brand
		end
		brandBounds.MinTextSize = 10
		brandBounds.MaxTextSize = 17
		TooltipSystem:Attach(brand, brand.Text)
		-- Wide enough for the navigation to share the title's row, so it
		-- starts past the title rather than at a fixed offset that could
		-- land on top of it once the title has been pushed right.
		-- The title reserves less of the row on a short screen. It is decorative
		-- and already truncates, while the tabs beside it are the only way to
		-- move around the menu, and they were the thing being squeezed.
		local navLeft = headerLeft + 282
		navigation.Position = if narrow
			then UDim2.fromOffset(safeLeft + 18, safeTop + 32)
			elseif compactLandscape then UDim2.fromOffset(headerLeft, safeTop + 8)
			else UDim2.fromOffset(navLeft, safeTop + 4)
		navigation.Size = if narrow
			then UDim2.new(1, -(36 + safeLeft + safeRight), 0, 28)
			elseif compactLandscape then UDim2.new(1, -(headerLeft + safeRight + 18), 0, 28)
			else UDim2.new(1, -(navLeft + 18 + safeRight), 0, 28)
		navLayout.FillDirection = Enum.FillDirection.Horizontal
		navLayout.Padding = UDim.new(0, 6)
		for _, item in navigation:GetChildren() do
			if item:IsA("TextButton") then
				item.Size = UDim2.new(1 / navItems, -5, 1, 0)
				-- Shrink the label into its slot rather than letting it run out of one.
				--
				-- Every tab gets an equal share of the bar, but the words are not of
				-- equal length. "Civilian jobs" wants about ninety pixels and its share
				-- on a landscape phone is nearer eighty, so it overflowed and ran into
				-- "Services" next to it: the highlight of one ending underneath the text
				-- of the other. It read as a broken menu before the player had pressed
				-- anything.
				--
				-- Scaled to fit rather than truncated, because "Civilian j..." is not a
				-- usable label either. The floor is what stops the fit being achieved by
				-- making the text unreadable: below about nine pixels these stop being
				-- legible on a phone, and they are the only way around the menu.
				item.TextScaled = false
				item.TextTruncate = Enum.TextTruncate.AtEnd
				local bounds = item:FindFirstChildOfClass("UITextSizeConstraint")
				if not bounds then
					bounds = Instance.new("UITextSizeConstraint")
					bounds.Parent = item
				end
				bounds.MinTextSize = 10
				bounds.MaxTextSize = if narrow then 11 else 12
				item.TextXAlignment = Enum.TextXAlignment.Center
				TooltipSystem:Attach(item, item.Text)
				local padding = item:FindFirstChildOfClass("UIPadding")
				if padding then
					padding.PaddingLeft = UDim.new()
				end
			end
		end
		profile.Visible = false
		-- Width taken from the parent rather than computed from SafeViewport.
		--
		-- The list is a child of a frame that already spans the screen, so a
		-- scale width with pixel margins is exactly the usable area by
		-- construction. Deriving an absolute width from SafeViewport instead
		-- meant the answer was only as good as that measurement, and when the
		-- two disagreed the list came up short and left a band of empty screen
		-- down the right of every page while the navigation above it ran the
		-- full width. Nothing here depends on that number any more.
		local marginLeft = safeLeft + 24
		local marginRight = safeRight + 24
		local available = layout.Viewport.X - marginLeft - marginRight
		local dockHeight = if narrow then 62 else 76
		bottomDock.Visible = true
		-- The rotating tip was creating a second header row on desktop. Keep the
		-- menu control in Roblox's top band and let the page content start directly
		-- beneath it; guidance remains available in Help.
		announcement.Visible = false
		bottomDock.Position = UDim2.new(0.5, 0, 1, -(layout.SafeBottom + 14))
		bottomDock.Size = UDim2.new(1, -(marginLeft + marginRight), 0, dockHeight)
		bottomDockPadding.PaddingLeft = UDim.new(0, if narrow then 5 else 8)
		bottomDockPadding.PaddingRight = UDim.new(0, if narrow then 5 else 8)
		bottomDockPadding.PaddingTop = UDim.new(0, if narrow then 5 else 8)
		bottomDockPadding.PaddingBottom = UDim.new(0, if narrow then 5 else 8)
		for _, item in bottomNavItems do
			item.TextSize = if narrow then 12 else 14
		end
		announcement.Position = UDim2.new(0.5, 0, 0, safeTop + 2)
		announcement.Size = UDim2.fromOffset(if narrow then 260 else 420, 28)
		pageTitle.Visible = false
		pageDescription.Visible = false
		-- The strip moves into the bar rather than sitting in a row of its own.
		--
		-- On desktop that bar held nothing: the tabs are in the dock at the
		-- bottom and the toggle is up in Roblox's own band, so the page paid
		-- thirty eight pixels for one line of text with an empty strip above
		-- it. Putting the text in the empty bar buys the grid both back.
		status.Parent = sidebar
		status.AnchorPoint = Vector2.new(1, 0.5)
		status.Position = UDim2.new(1, -(marginRight > 0 and marginRight or 24), 0.5, 0)
		status.Size = UDim2.fromOffset(190, 20)
		header.Visible = false
		if available > MAXIMUM_CONTENT_WIDTH then
			-- On a display wide enough for it, a centred column reads better than
			-- one line of text stretched across a metre of monitor.
			local centred = math.floor((layout.Viewport.X - MAXIMUM_CONTENT_WIDTH) / 2)
			header.Position = UDim2.fromOffset(centred, 6)
			header.Size = UDim2.fromOffset(MAXIMUM_CONTENT_WIDTH, 0)
			scroll.Position = UDim2.fromOffset(centred, 8)
			scroll.Size =
				UDim2.new(0, MAXIMUM_CONTENT_WIDTH, 1, -(16 + layout.SafeBottom + dockHeight + 12))
		else
			header.Position = UDim2.fromOffset(marginLeft, 6)
			header.Size = UDim2.new(1, -(marginLeft + marginRight), 0, 0)
			scroll.Position = UDim2.fromOffset(marginLeft, 8)
			scroll.Size = UDim2.new(
				1,
				-(marginLeft + marginRight),
				1,
				-(16 + layout.SafeBottom + dockHeight + 12)
			)
		end
		-- Cards have genuinely different compositions at these breakpoints, not
		-- merely different widths. Repaint only when a breakpoint changes so a
		-- phone rotation or window resize never leaves desktop cards squeezed into
		-- a mobile column, without doing work on every viewport-size signal.
		local responsiveKey = string.format(
			"%d:%s",
			portraitCardColumns(),
			if shortLandscape() then "short" else "standard"
		)
		if lastResponsiveKey and responsiveKey ~= lastResponsiveKey and currentRender then
			task.defer(currentRender)
		end
		lastResponsiveKey = responsiveKey
	end)

	context.Events.StartMenuChanged.Event:Connect(function(data)
		menuData = data
		storeState.menuData = data
		if not selectedCharacterId and type(data.LastCharacterId) == "string" then
			-- Only when nothing is chosen yet, so a refresh never moves a choice
			-- the player has just made out from under them.
			for _, character in data.Characters or {} do
				if character.CharacterId == data.LastCharacterId then
					selectedCharacterId = data.LastCharacterId
					break
				end
			end
		end
		local gameName = data.Framework.GameName
		brand.Text = gameName
		status.Text = "●  Online  ·  " .. data.Server.Kind
		status.TextColor3 = COLOURS.Success
		finishLoading()
		if currentRender then
			currentRender()
		end
		-- Fetched alongside menuData rather than on every render: a gang's
		-- territory does not change fast enough to need refreshing more often
		-- than the rest of the menu already does.
		task.spawn(function()
			local response = context.Controllers.NetworkController:Request("GetGangStatus", {})
			if response.Success then
				gangStatus = response.Data
				if currentRender then
					currentRender()
				end
			end
		end)
	end)
	context.Events.CharacterChanged.Event:Connect(function(characterId)
		if type(characterId) ~= "string" or characterId == "" then
			return
		end
		selectedCharacterId = characterId
		if menuData then
			menuData.ActiveCharacterId = characterId
		end
	end)
	-- Paint immediately so the menu is on screen while the first request is still
	-- in flight. The StartMenuChanged handler above fills in real data on success.
	setMenuOpen(true)
	renderPlay()
	task.spawn(function()
		local response = context.Controllers.StartMenuController:Refresh()
		if response.Success then
			return
		end
		status.Text = "●  CONNECTION ERROR"
		status.TextColor3 = COLOURS.Danger
		-- The overlay comes down on failure too.
		--
		-- It was hidden in exactly one place, inside the handler that fires only
		-- when the first request succeeds. So a player whose request failed was
		-- left on a full screen cover, at ZIndex 100, with the progress bar still
		-- sliding back and forth for ever, while this very message was written to
		-- a label underneath it. The only way out was a button labelled "Skip
		-- loading", which reads like an impatience shortcut rather than the exit
		-- from a broken state.
		--
		-- This is the first twenty seconds of the game for everybody and the only
		-- screen a new player has seen, so it is the worst place in the interface
		-- to say nothing.
		loadingStatus.Text = "Could not reach the server."
		loadingStatus.TextColor3 = COLOURS.Danger
		retryLoading.Visible = true
		context.Controllers.NotificationController:Show(
			"Could not reach the server. Reopen the menu to retry, or rejoin if it keeps failing.",
			"Error"
		)
		if audioFeedback then
			audioFeedback:Error()
		end
	end)

	if interfaceMotionEnabled() then
		root.Position = UDim2.fromOffset(0, 12)
		root.BackgroundTransparency = 1
		TweenService
			:Create(root, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 0,
			})
			:Play()
	end
	context.Controllers.SettingsController:Apply()
	return gui
end

return table.freeze(App)
