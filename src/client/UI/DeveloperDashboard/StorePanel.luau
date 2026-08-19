--!strict

local StorePanel = {}

function StorePanel.create(deps: any): () -> ()
	local context = deps.context
	local scroll = deps.scroll
	local pageTitle = deps.pageTitle
	local pageDescription = deps.pageDescription
	local sectionHeading = deps.sectionHeading
	local storeState = deps.state
	local COLOURS = deps.colours
	local clear = deps.clear
	local card = deps.card
	local text = deps.text
	local button = deps.button
	local corner = deps.corner
	local stroke = deps.stroke
	local TooltipSystem = deps.TooltipSystem
	local Players = deps.Players
	local MarketplaceService = deps.MarketplaceService
	local render: () -> ()
	render = function()
		deps.nextGeneration()
		clear(scroll)
		pageTitle.Text = "Store"
		pageDescription.Text = "Optional access and upgrades for this experience."
		sectionHeading(
			"RoleplayOS passes",
			"Purchases are handled by Roblox. Your access refreshes automatically."
		)
		if not storeState.menuData or not storeState.menuData.Gamepasses then
			local loading = card(scroll, 90)
			local loadingCopy = text(loading, "Loading available passes…", 14, COLOURS.Muted)
			loadingCopy.Position = UDim2.fromOffset(20, 0)
			loadingCopy.Size = UDim2.new(1, -40, 1, 0)
			return
		end

		local safeWidth = context.Controllers.UIOrchestrator:GetLayout().SafeViewport.X
		local columns = if safeWidth >= 1180
			then 4
			else if safeWidth >= 840 then 3 else if safeWidth >= 560 then 2 else 1
		local categories = {}
		local categoryOrder = {}
		for _, pass in storeState.menuData.Gamepasses do
			if not categories[pass.Category] then
				categories[pass.Category] = {}
				table.insert(categoryOrder, pass.Category)
			end
			table.insert(categories[pass.Category], pass)
		end
		if
			storeState.selectedStoreCategory and not categories[storeState.selectedStoreCategory]
		then
			storeState.selectedStoreCategory = nil
		end
		local categoryBar = Instance.new("ScrollingFrame")
		categoryBar.Name = "ProductCategories"
		categoryBar.BackgroundColor3 = COLOURS.Surface
		categoryBar.BorderSizePixel = 0
		categoryBar.Size = UDim2.new(1, 0, 0, 58)
		categoryBar.AutomaticCanvasSize = Enum.AutomaticSize.X
		categoryBar.CanvasSize = UDim2.new()
		-- The row does scroll, and with no scrollbar there was nothing to say so.
		-- The last category simply appeared sliced off at the panel edge, which
		-- reads as a broken layout rather than as more to reach.
		categoryBar.ScrollBarThickness = 6
		categoryBar.ScrollBarImageTransparency = 0.4
		categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
		categoryBar.Parent = scroll
		local categoryOrderIndex = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
		scroll:SetAttribute("RoleplayOSNextLayoutOrder", categoryOrderIndex)
		categoryBar.LayoutOrder = categoryOrderIndex
		corner(categoryBar, 12)
		stroke(categoryBar)
		local categoryPadding = Instance.new("UIPadding")
		categoryPadding.PaddingLeft = UDim.new(0, 8)
		categoryPadding.PaddingRight = UDim.new(0, 8)
		categoryPadding.PaddingTop = UDim.new(0, 7)
		categoryPadding.PaddingBottom = UDim.new(0, 7)
		categoryPadding.Parent = categoryBar
		local categoryLayout = Instance.new("UIListLayout")
		categoryLayout.FillDirection = Enum.FillDirection.Horizontal
		categoryLayout.Padding = UDim.new(0, 8)
		categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
		categoryLayout.Parent = categoryBar
		local tabs = { "All" }
		for _, category in categoryOrder do
			table.insert(tabs, tostring(category))
		end
		for _, category in tabs do
			local selected = (category == "All" and storeState.selectedStoreCategory == nil)
				or storeState.selectedStoreCategory == category
			local tab = button(categoryBar, category, selected)
			tab.Size = UDim2.fromOffset(math.max(116, 32 + #category * 8), 44)
			tab.Activated:Connect(function()
				storeState.selectedStoreCategory = if category == "All" then nil else category
				render()
			end)
		end
		for _, category in categoryOrder do
			if
				storeState.selectedStoreCategory
				and tostring(category) ~= storeState.selectedStoreCategory
			then
				continue
			end
			local passes = categories[category]
			local section = Instance.new("Frame")
			section.Name = "StoreSection_" .. tostring(category)
			section.BackgroundTransparency = 1
			section.Size = UDim2.new(1, 0, 0, 54)
			section.Parent = scroll
			local nextOrder = (scroll:GetAttribute("RoleplayOSNextLayoutOrder") or 0) + 1
			scroll:SetAttribute("RoleplayOSNextLayoutOrder", nextOrder)
			section.LayoutOrder = nextOrder
			local categoryTitle = text(section, tostring(category), 18, COLOURS.Text, true)
			categoryTitle.Position = UDim2.fromOffset(2, 0)
			categoryTitle.Size = UDim2.new(1, -4, 0, 26)
			local categoryCopy = text(
				section,
				string.format("%d %s", #passes, if #passes == 1 then "option" else "options"),
				11,
				COLOURS.Muted
			)
			categoryCopy.Position = UDim2.fromOffset(2, 25)
			categoryCopy.Size = UDim2.new(1, -4, 0, 18)
			local passGrid = Instance.new("Frame")
			passGrid.Name = "Products"
			passGrid.BackgroundTransparency = 1
			passGrid.Position = UDim2.fromOffset(0, 52)
			passGrid.Size = UDim2.fromScale(1, 0)
			passGrid.Parent = section
			local passLayout = Instance.new("UIGridLayout")
			passLayout.SortOrder = Enum.SortOrder.LayoutOrder
			passLayout.CellPadding = UDim2.fromOffset(14, 14)
			passLayout.CellSize = UDim2.new(1 / columns, -14 * (columns - 1) / columns, 0, 250)
			passLayout.Parent = passGrid
			local function updateSectionHeight()
				local contentHeight = passLayout.AbsoluteContentSize.Y
				passGrid.Size = UDim2.new(1, 0, 0, contentHeight)
				section.Size = UDim2.new(1, 0, 0, 52 + contentHeight)
			end
			passLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSectionHeight)
			for _, pass in passes do
				local item = card(passGrid, 250)
				item.ClipsDescendants = true
				local artwork = Instance.new("Frame")
				artwork.Position = UDim2.fromOffset(12, 12)
				artwork.Size = UDim2.new(1, -24, 0, 78)
				-- Owned reads green, unowned reads as an ordinary raised surface.
				artwork.BackgroundColor3 = if pass.Owned
					then COLOURS.Success:Lerp(COLOURS.Surface, 0.72)
					else COLOURS.SurfaceRaised
				artwork.BorderSizePixel = 0
				artwork.Parent = item
				corner(artwork, 10)
				local artworkGradient = Instance.new("UIGradient")
				artworkGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, artwork.BackgroundColor3),
					ColorSequenceKeypoint.new(1, COLOURS.SurfaceRaised),
				})
				artworkGradient.Rotation = 18
				artworkGradient.Parent = artwork
				local imageId = tonumber(
					pass.ImageAssetId or pass.IconAssetId or pass.ImageId or pass.IconImageId
				)
				if imageId and imageId > 0 then
					local image = Instance.new("ImageLabel")
					image.BackgroundTransparency = 1
					image.Size = UDim2.fromScale(1, 1)
					image.Image = "rbxassetid://" .. tostring(imageId)
					image.ScaleType = Enum.ScaleType.Crop
					image.Parent = artwork
					corner(image, 10)
				else
					local shape = Instance.new("Frame")
					shape.AnchorPoint = Vector2.new(0.5, 0.5)
					shape.Position = UDim2.fromScale(0.5, 0.5)
					shape.Size = UDim2.fromOffset(42, 42)
					shape.Rotation = -12
					shape.BackgroundColor3 = if pass.Owned then COLOURS.Success else COLOURS.Accent
					shape.BackgroundTransparency = 0.28
					shape.BorderSizePixel = 0
					shape.Parent = artwork
					corner(shape, 12)
					local detail = Instance.new("Frame")
					detail.AnchorPoint = Vector2.new(0.5, 0.5)
					detail.Position = UDim2.fromScale(0.5, 0.5)
					detail.Size = UDim2.fromOffset(68, 2)
					detail.Rotation = 35
					detail.BackgroundColor3 = COLOURS.Text
					detail.BackgroundTransparency = 0.7
					detail.BorderSizePixel = 0
					detail.Parent = artwork
				end
				local name = text(item, pass.Name, 17, COLOURS.Text, true)
				name.Position = UDim2.fromOffset(16, 98)
				name.Size = UDim2.new(1, -32, 0, 25)
				name.TextWrapped = true
				name.TextWrapped = false
				name.TextTruncate = Enum.TextTruncate.AtEnd
				TooltipSystem:Attach(name, pass.Name)
				local description = text(item, pass.Description, 12, COLOURS.Muted)
				description.Position = UDim2.fromOffset(16, 126)
				description.Size = UDim2.new(1, -32, 0, 40)
				description.TextWrapped = true
				description.TextYAlignment = Enum.TextYAlignment.Top
				description.TextTruncate = Enum.TextTruncate.AtEnd
				TooltipSystem:Attach(description, pass.Description)
				local price = tonumber(pass.PriceInRobux or pass.Price)
				local stateCopy = if pass.Owned
					then "OWNED"
					elseif price and price > 0 then string.format("R$ %d", price)
					elseif pass.Configured then "VIEW PRICE"
					else "NOT CONFIGURED"
				local state = text(
					item,
					stateCopy,
					10,
					if pass.Owned then COLOURS.Success else COLOURS.Accent,
					true
				)
				state.Position = UDim2.fromOffset(16, 170)
				state.Size = UDim2.new(1, -32, 0, 18)
				local actionLabel = if pass.Owned
					then "Owned"
					elseif not pass.Configured then "Unavailable"
					elseif not pass.AvailableInServer then "Public servers only"
					else "View pass"
				local purchase =
					button(item, actionLabel, not pass.Owned and pass.AvailableInServer)
				purchase.AnchorPoint = Vector2.new(0, 1)
				purchase.Position = UDim2.new(0, 16, 1, -14)
				purchase.Size = UDim2.new(1, -32, 0, 40)
				purchase.Selectable = pass.Configured and pass.AvailableInServer and not pass.Owned
				purchase.Active = purchase.Selectable
				if purchase.Active then
					purchase.Activated:Connect(function()
						if pass.PurchaseType == "DeveloperProduct" then
							MarketplaceService:PromptProductPurchase(
								Players.LocalPlayer,
								pass.ProductId
							)
						else
							context.Controllers.GamepassController:Prompt(pass.GamepassId)
						end
					end)
				else
					purchase.BackgroundColor3 = COLOURS.SurfaceRaised
					purchase.TextColor3 = if pass.Owned then COLOURS.Success else COLOURS.Muted
				end
			end
			updateSectionHeight()
		end
	end
	return render
end

return StorePanel
