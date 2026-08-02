--!strict

local ToolFactory = {}

local METAL = Color3.fromRGB(174, 180, 187)
local DARK_METAL = Color3.fromRGB(69, 75, 82)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	colour: Color3,
	material: Enum.Material
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = colour
	item.Material = material
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = true
	item.Massless = true
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function attach(handle: BasePart, item: BasePart, localCFrame: CFrame)
	item.CFrame = handle.CFrame * localCFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = item
	weld.Parent = item
end

local function rounded(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function textLabel(
	parent: Instance,
	text: string,
	position: UDim2,
	size: UDim2,
	textSize: number,
	colour: Color3,
	bold: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = colour
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = position
	label.Size = size
	label.Parent = parent
	return label
end

local function surface(handle: BasePart): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CredentialFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(856, 540)
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = handle
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BorderSizePixel = 0
	canvas.Parent = gui
	return canvas
end

function ToolFactory.handcuffs(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Handcuffs"
	tool.ToolTip = "Rigid handcuffs · select a nearby player"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -0.05, -0.75) * CFrame.Angles(math.rad(82), math.rad(4), math.rad(90))
	local handle =
		part(tool, "Handle", Vector3.new(0.78, 0.3, 0.2), DARK_METAL, Enum.Material.Metal)
	local spine =
		part(tool, "RigidSpine", Vector3.new(1.45, 0.16, 0.16), DARK_METAL, Enum.Material.Metal)
	attach(handle, spine, CFrame.identity)
	for _, side in { -1, 1 } do
		local centreX = side * 1.03
		for index = 0, 11 do
			local angle = index / 12 * math.pi * 2
			local x = centreX + math.cos(angle) * 0.46
			local y = math.sin(angle) * 0.55
			local segment =
				part(tool, "CuffRing", Vector3.new(0.12, 0.31, 0.12), METAL, Enum.Material.Metal)
			attach(handle, segment, CFrame.new(x, y, 0) * CFrame.Angles(0, 0, angle))
		end
		local hinge = part(
			tool,
			"LockHousing",
			Vector3.new(0.34, 0.32, 0.21),
			DARK_METAL,
			Enum.Material.Metal
		)
		attach(handle, hinge, CFrame.new(side * 0.68, 0, 0))
	end
	tool:SetAttribute("RoleplayOSBuiltInFallback", true)
	tool:SetAttribute("RoleplayOSAssetSource", "RoleplayOS functional staging fallback")
	tool:SetAttribute("RoleplayOSRealWorldReference", "UK rigid handcuff form")
	return tool
end

local function credentialBase(name: string, tooltip: string, width: number): (Tool, Part, Frame)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tooltip
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("RoleplayOSAssetSource", "RoleplayOS generated credential")
	tool:SetAttribute("RoleplayOSRealWorldReference", "Fictional UK-style roleplay credential")
	tool.Grip = CFrame.new(0, -0.15, -0.82) * CFrame.Angles(math.rad(88), 0, math.rad(-7))
	local handle = part(
		tool,
		"Handle",
		Vector3.new(width, 1.08, 0.055),
		Color3.fromRGB(229, 225, 208),
		Enum.Material.SmoothPlastic
	)
	return tool, handle, surface(handle)
end

function ToolFactory.drivingLicence(data: any): Tool
	local tool, _, canvas =
		credentialBase("ID Card", "Present fictional driving identification", 1.71)
	canvas.BackgroundColor3 = Color3.fromRGB(225, 214, 190)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(218, 229, 211)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 225, 199)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(209, 218, 196)),
	})
	gradient.Rotation = 16
	gradient.Parent = canvas
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 82)
	header.BackgroundColor3 = Color3.fromRGB(32, 59, 77)
	header.BorderSizePixel = 0
	header.Parent = canvas
	textLabel(
		header,
		"ROLEPLAY DRIVING LICENCE",
		UDim2.fromOffset(28, 9),
		UDim2.new(1, -56, 0, 38),
		29,
		Color3.new(1, 1, 1),
		true
	)
	textLabel(
		header,
		"UNITED KINGDOM · FICTIONAL DOCUMENT",
		UDim2.fromOffset(29, 46),
		UDim2.new(1, -58, 0, 24),
		17,
		Color3.fromRGB(196, 214, 226),
		false
	)
	local portrait = Instance.new("ImageLabel")
	portrait.Position = UDim2.fromOffset(30, 112)
	portrait.Size = UDim2.fromOffset(210, 260)
	portrait.BackgroundColor3 = Color3.fromRGB(184, 193, 178)
	portrait.BorderSizePixel = 0
	portrait.Image = data.AvatarImage
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.Parent = canvas
	rounded(portrait, 10)
	local dark = Color3.fromRGB(32, 42, 48)
	textLabel(
		canvas,
		"1  SURNAME",
		UDim2.fromOffset(274, 106),
		UDim2.fromOffset(520, 27),
		17,
		dark,
		true
	)
	textLabel(
		canvas,
		string.upper(data.LastName),
		UDim2.fromOffset(274, 132),
		UDim2.fromOffset(520, 39),
		28,
		dark,
		true
	)
	textLabel(
		canvas,
		"2  FIRST NAMES",
		UDim2.fromOffset(274, 180),
		UDim2.fromOffset(520, 27),
		17,
		dark,
		true
	)
	textLabel(
		canvas,
		string.upper(data.FirstName),
		UDim2.fromOffset(274, 206),
		UDim2.fromOffset(520, 39),
		27,
		dark,
		true
	)
	textLabel(
		canvas,
		"3  DATE OF BIRTH",
		UDim2.fromOffset(274, 254),
		UDim2.fromOffset(520, 27),
		17,
		dark,
		true
	)
	textLabel(
		canvas,
		data.DateOfBirth,
		UDim2.fromOffset(274, 281),
		UDim2.fromOffset(520, 34),
		23,
		dark,
		true
	)
	textLabel(
		canvas,
		"4a  ISSUED",
		UDim2.fromOffset(274, 324),
		UDim2.fromOffset(220, 25),
		16,
		dark,
		true
	)
	textLabel(
		canvas,
		data.Issued,
		UDim2.fromOffset(274, 348),
		UDim2.fromOffset(220, 31),
		21,
		dark,
		true
	)
	textLabel(
		canvas,
		"4b  VALID TO",
		UDim2.fromOffset(505, 324),
		UDim2.fromOffset(220, 25),
		16,
		dark,
		true
	)
	textLabel(
		canvas,
		data.ValidTo,
		UDim2.fromOffset(505, 348),
		UDim2.fromOffset(220, 31),
		21,
		dark,
		true
	)
	textLabel(
		canvas,
		"5  DRIVER NUMBER",
		UDim2.fromOffset(30, 402),
		UDim2.fromOffset(250, 24),
		16,
		dark,
		true
	)
	textLabel(
		canvas,
		data.DocumentNumber,
		UDim2.fromOffset(30, 429),
		UDim2.fromOffset(570, 42),
		27,
		dark,
		true
	)
	local invalid = textLabel(
		canvas,
		"ROLEPLAY ONLY · NOT VALID IDENTIFICATION",
		UDim2.fromOffset(30, 486),
		UDim2.new(1, -60, 0, 34),
		18,
		Color3.fromRGB(135, 34, 38),
		true
	)
	invalid.TextXAlignment = Enum.TextXAlignment.Center
	return tool
end

function ToolFactory.warrantCard(data: any): Tool
	local tool, handle, canvas = credentialBase("Warrant Card", "Present police warrant card", 2.24)
	handle.Color = Color3.fromRGB(32, 24, 23)
	canvas.BackgroundColor3 = Color3.fromRGB(35, 27, 26)
	local left = Instance.new("Frame")
	left.Position = UDim2.fromOffset(18, 18)
	left.Size = UDim2.fromOffset(330, 504)
	left.BackgroundColor3 = Color3.fromRGB(48, 36, 34)
	left.BorderSizePixel = 0
	left.Parent = canvas
	rounded(left, 18)
	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.fromScale(0.5, 0.12)
	badge.Size = UDim2.fromOffset(190, 235)
	badge.BackgroundColor3 = Color3.fromRGB(190, 157, 71)
	badge.BorderSizePixel = 0
	badge.Parent = left
	rounded(badge, 35)
	local badgeText = textLabel(
		badge,
		"POLICE\nWARRANT\nCARD",
		UDim2.fromOffset(20, 35),
		UDim2.new(1, -40, 1, -70),
		24,
		Color3.fromRGB(29, 36, 47),
		true
	)
	badgeText.TextWrapped = true
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	local fiction = textLabel(
		left,
		"FICTIONAL ROLEPLAY CREDENTIAL",
		UDim2.fromOffset(18, 430),
		UDim2.new(1, -36, 0, 38),
		16,
		Color3.fromRGB(218, 195, 144),
		true
	)
	fiction.TextXAlignment = Enum.TextXAlignment.Center
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(366, 18)
	card.Size = UDim2.fromOffset(472, 504)
	card.BackgroundColor3 = Color3.fromRGB(232, 235, 239)
	card.BorderSizePixel = 0
	card.Parent = canvas
	rounded(card, 14)
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 91)
	band.BackgroundColor3 = Color3.fromRGB(20, 45, 70)
	band.BorderSizePixel = 0
	band.Parent = card
	textLabel(
		band,
		data.ForceName,
		UDim2.fromOffset(20, 10),
		UDim2.new(1, -40, 0, 37),
		22,
		Color3.new(1, 1, 1),
		true
	)
	textLabel(
		band,
		"POLICE WARRANT CARD",
		UDim2.fromOffset(20, 48),
		UDim2.new(1, -40, 0, 27),
		17,
		Color3.fromRGB(184, 211, 235),
		true
	)
	local portrait = Instance.new("ImageLabel")
	portrait.Position = UDim2.fromOffset(22, 116)
	portrait.Size = UDim2.fromOffset(155, 190)
	portrait.BackgroundColor3 = Color3.fromRGB(195, 202, 211)
	portrait.BorderSizePixel = 0
	portrait.Image = data.AvatarImage
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.Parent = card
	rounded(portrait, 8)
	local ink = Color3.fromRGB(26, 35, 44)
	textLabel(card, "OFFICER", UDim2.fromOffset(198, 116), UDim2.fromOffset(250, 25), 15, ink, true)
	textLabel(
		card,
		data.FullName,
		UDim2.fromOffset(198, 141),
		UDim2.fromOffset(250, 56),
		23,
		ink,
		true
	).TextWrapped =
		true
	textLabel(card, "RANK", UDim2.fromOffset(198, 212), UDim2.fromOffset(250, 25), 15, ink, true)
	textLabel(card, data.Rank, UDim2.fromOffset(198, 237), UDim2.fromOffset(250, 38), 21, ink, true)
	textLabel(
		card,
		"COLLAR / WARRANT NUMBER",
		UDim2.fromOffset(22, 331),
		UDim2.fromOffset(420, 26),
		15,
		ink,
		true
	)
	textLabel(
		card,
		data.WarrantNumber,
		UDim2.fromOffset(22, 359),
		UDim2.fromOffset(420, 42),
		25,
		ink,
		true
	)
	textLabel(
		card,
		"ROLEPLAY ONLY · NOT AN OFFICIAL POLICE DOCUMENT",
		UDim2.fromOffset(22, 448),
		UDim2.new(1, -44, 0, 34),
		13,
		Color3.fromRGB(145, 35, 40),
		true
	).TextXAlignment =
		Enum.TextXAlignment.Center
	return tool
end

return table.freeze(ToolFactory)
