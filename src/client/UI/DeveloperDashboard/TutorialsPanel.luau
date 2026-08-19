--!strict

local TutorialsPanel = {}

function TutorialsPanel.create(deps: any): () -> ()
	local context = deps.context
	local scroll = deps.scroll
	local pageTitle = deps.pageTitle
	local pageDescription = deps.pageDescription
	local sectionHeading = deps.sectionHeading
	local COLOURS = deps.colours
	local tutorials = deps.tutorials
	local clear = deps.clear
	local card = deps.card
	local text = deps.text
	local button = deps.button
	local pressable = deps.pressable
	local corner = deps.corner
	local modalSystem = deps.modalSystem
	local nextGeneration = deps.nextGeneration
	local renderControls = deps.renderControls
	local renderSettings = deps.renderSettings
	local render: () -> ()
	render = function()
		nextGeneration()
		clear(scroll)
		pageTitle.Text = "Tutorials"
		pageDescription.Text = "Learn each system before starting your roleplay."
		sectionHeading("Game guides", "Short, practical explanations of the live systems.")
		local utilities = card(scroll, 78)
		local controls = button(utilities, "Controls", false)
		controls.Position = UDim2.fromOffset(18, 17)
		controls.Size = UDim2.new(0.5, -27, 0, 44)
		controls.Activated:Connect(renderControls)
		local settings = button(utilities, "Settings", false)
		settings.Position = UDim2.new(0.5, 9, 0, 17)
		settings.Size = UDim2.new(0.5, -27, 0, 44)
		settings.Activated:Connect(renderSettings)
		local compactTutorials = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X < 650
		for index, tutorial in tutorials do
			local item = card(scroll, if compactTutorials then 166 else 124)
			local number = text(item, string.format("%02d", index), 13, COLOURS.Accent, true)
			number.Position = UDim2.fromOffset(20, 18)
			number.Size = UDim2.fromOffset(34, 24)
			local titleItem = text(item, tutorial.Title, 18, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(58, 16)
			titleItem.Size = UDim2.new(1, if compactTutorials then -76 else -230, 0, 28)
			local summary = text(item, tutorial.Summary, 13, COLOURS.Muted)
			summary.Position = UDim2.fromOffset(58, 44)
			summary.Size = UDim2.new(1, if compactTutorials then -76 else -250, 0, 54)
			summary.TextWrapped = true
			local open = button(item, "Open guide", false)
			open.AnchorPoint = if compactTutorials then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			open.Position = if compactTutorials
				then UDim2.new(0, 18, 1, -14)
				else UDim2.new(1, -18, 0.5, 0)
			open.Size = if compactTutorials
				then UDim2.new(1, -36, 0, 40)
				else UDim2.fromOffset(150, 42)
			open.Activated:Connect(function()
				local guideViewport = context.Controllers.UIOrchestrator:GetLayout().SafeViewport
				modalSystem:Open({
					Title = tutorial.Title,
					Body = tutorial.Body,
					Actions = { { Label = "Close", Primary = true, Callback = function() end } },
					Width = math.min(520, guideViewport.X - 32),
					Height = math.min(300, guideViewport.Y - 32),
					Dismissable = true,
				})
			end)
		end
	end

	renderSettings = function()
		deps.nextGeneration()
		clear(scroll)
		pageTitle.Text = "Advanced settings"
		pageDescription.Text = "Accessible, responsive controls for this experience."
		sectionHeading(
			"Interface and accessibility",
			"Roblox-native volume, graphics and controls remain in the Roblox menu."
		)
		local settings = context.Controllers.SettingsController:Get()
		if not settings then
			local unavailable = card(scroll, 80)
			local message = text(unavailable, "Settings are still loading.", 14, COLOURS.Muted)
			message.Position = UDim2.fromOffset(18, 18)
			message.Size = UDim2.new(1, -36, 0, 40)
			return
		end
		local function settingRow(
			titleValue: string,
			description: string,
			buttonText: string,
			onActivate: () -> ()
		)
			local row = card(scroll, 88)
			local titleItem = text(row, titleValue, 15, COLOURS.Text, true)
			titleItem.Position = UDim2.fromOffset(18, 12)
			titleItem.Size = UDim2.new(1, -210, 0, 25)
			local detail = text(row, description, 12, COLOURS.Muted)
			detail.Position = UDim2.fromOffset(18, 39)
			detail.Size = UDim2.new(1, -210, 0, 32)
			detail.TextWrapped = true
			local action = button(row, buttonText, false)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -16, 0.5, 0)
			action.Size = UDim2.fromOffset(160, 40)
			action.Activated:Connect(onActivate)
		end
		settingRow(
			"Interface scale",
			"Combines with your Roblox preferred text size.",
			settings.InterfaceScale,
			function()
				local nextValue = if settings.InterfaceScale == "Small"
					then "Standard"
					elseif settings.InterfaceScale == "Standard" then "Large"
					else "Small"
				context.Controllers.SettingsController:Update("InterfaceScale", nextValue)
				renderSettings()
			end
		)
		for _, definition in
			{
				{
					"Interface motion",
					"Interface transitions and button motion.",
					"InterfaceMotion",
				},
				{
					"High contrast",
					"Increases scene contrast and reduces colour wash.",
					"HighContrast",
				},
				{
					"Reduced effects",
					"Disables decorative particles, trails and beams locally.",
					"ReducedEffects",
				},
				{
					"Camera shake",
					"Allows game camera shake effects when implemented.",
					"CameraShake",
				},
				{ "Gameplay hints", "Shows contextual help and onboarding prompts.", "ShowHints" },
			}
		do
			local key = definition[3]
			settingRow(
				definition[1],
				definition[2],
				settings[key] and "Enabled" or "Disabled",
				function()
					context.Controllers.SettingsController:Update(key, not settings[key])
					renderSettings()
				end
			)
		end
	end

	-- Controls as an ordinary page rather than an overlay. It was the one item in
	-- the sidebar that opened something else entirely, which made it read as a
	-- different product from the four either side of it.
	renderControls = function()
		deps.nextGeneration()
		clear(scroll)
		pageTitle.Text = "Controls"
		pageDescription.Text = "Every action, and what it is bound to on your device."
		local controller = context.Controllers.ControlsController
		local data = controller:List()
		local order = data.ModeOrder
		local labels = data.ModeLabels
		local selected = controller:DetectedMode()

		local rowsHolder: Frame
		local modeButtons: { [string]: TextButton } = {}

		local function paint()
			for mode, item in modeButtons do
				local active = mode == selected
				item.BackgroundColor3 = if active then COLOURS.Accent else COLOURS.Canvas
				item.TextColor3 = if active then COLOURS.Text else COLOURS.Muted
			end
			for _, child in rowsHolder:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			for index, control in data.Controls do
				local row = Instance.new("Frame")
				row.LayoutOrder = index
				row.Size = UDim2.new(1, 0, 0, 42)
				-- Banded rather than bordered. A list this long reads faster when
				-- the eye can follow a stripe across to the binding.
				row.BackgroundColor3 = if index % 2 == 0 then COLOURS.Canvas else COLOURS.Surface
				row.BorderSizePixel = 0
				row.Parent = rowsHolder
				corner(row, 8)
				local action = text(row, tostring(control.Action), 14, COLOURS.Text)
				action.Position = UDim2.fromOffset(16, 0)
				action.Size = UDim2.new(0.5, -16, 1, 0)
				local binding =
					text(row, tostring(control[selected] or "—"), 14, COLOURS.Accent, true)
				binding.Position = UDim2.new(0.5, 4, 0, 0)
				binding.Size = UDim2.new(0.5, -20, 1, 0)
			end
		end

		sectionHeading("Your device", "Bindings change with what you are playing on.")
		local switcher = card(scroll, 62)
		local switcherLayout = Instance.new("UIListLayout")
		switcherLayout.FillDirection = Enum.FillDirection.Horizontal
		switcherLayout.Padding = UDim.new(0, 8)
		switcherLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		switcherLayout.Parent = switcher
		local switcherPadding = Instance.new("UIPadding")
		switcherPadding.PaddingLeft = UDim.new(0, 12)
		switcherPadding.PaddingRight = UDim.new(0, 12)
		switcherPadding.Parent = switcher
		for index, mode in order do
			local item = Instance.new("TextButton")
			item.AutoButtonColor = false
			item.BackgroundColor3 = COLOURS.Canvas
			item.BorderSizePixel = 0
			item.Font = Enum.Font.GothamBold
			item.LayoutOrder = index
			item.Text = tostring(labels[mode] or mode)
			item.TextColor3 = COLOURS.Muted
			item.TextSize = 11
			item.Size = UDim2.new(1 / #order, -6, 0, 38)
			item.Parent = switcher
			corner(item, 9)
			pressable(item)
			modeButtons[mode] = item
			item.Activated:Connect(function()
				selected = mode
				paint()
			end)
		end

		sectionHeading("Controls", "Held actions are marked where they differ.")
		local listCard = card(scroll, 0)
		listCard.AutomaticSize = Enum.AutomaticSize.Y
		local listPadding = Instance.new("UIPadding")
		listPadding.PaddingTop = UDim.new(0, 10)
		listPadding.PaddingBottom = UDim.new(0, 10)
		listPadding.PaddingLeft = UDim.new(0, 10)
		listPadding.PaddingRight = UDim.new(0, 10)
		listPadding.Parent = listCard
		rowsHolder = Instance.new("Frame")
		rowsHolder.BackgroundTransparency = 1
		rowsHolder.Size = UDim2.fromScale(1, 0)
		rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
		rowsHolder.Parent = listCard
		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.Padding = UDim.new(0, 4)
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Parent = rowsHolder

		paint()
	end
	return render
end

return TutorialsPanel
