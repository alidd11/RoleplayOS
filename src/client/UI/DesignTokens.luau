--!strict

-- One vocabulary for every RoleplayOS surface. The HUD panels and menu pages
-- grew separately and each picked its own navy, its own blue and its own corner
-- radius, so the same control reads as a different control depending on which
-- screen a player opened it from.
--
-- The palette is the operational terminal set, which MDT, Radio and Dispatch
-- already share. That is not the ramp most files currently use - the lighter
-- blue in the start menu reaches more of them - and moving to this one is the
-- more expensive direction. It was chosen anyway: this is a police roleplay,
-- the terminals are what the game is about, and a colder, darker chassis reads
-- as equipment rather than as an app. Cost is a reason to sequence the work,
-- not a reason to pick the weaker house style.
--
-- Canvas and accentFill are derived rather than taken: the terminal theme has
-- no ground colour and no filled-button colour, because its three panels never
-- needed either.

local DesignTokens = {}

DesignTokens.Colour = table.freeze({
	-- Ground behind every panel. The darkest step, so a panel always reads as
	-- lifted off the world rather than painted onto it.
	canvas = Color3.fromHex("#040C16"),
	-- Body of a panel or page. One step up from canvas is the whole separation,
	-- which is why nothing between the two steps is allowed.
	surface = Color3.fromHex("#06101C"),
	-- Cards, list rows and anything sitting on top of a panel body.
	raised = Color3.fromHex("#0E2032"),
	-- Primary reading colour. Off-white rather than pure white: full white on
	-- this navy vibrates badly at the 11-12px body sizes below.
	text = Color3.fromHex("#F4F7FC"),
	-- Secondary text: timestamps, units, helper lines. Still passes contrast on
	-- surface, so it is safe for anything that must remain legible.
	muted = Color3.fromHex("#97A3B8"),
	-- Every panel, card and input outline. Paired with Stroke below, never used
	-- at full opacity.
	border = Color3.fromHex("#305B79"),
	-- The single interactive blue: links, selected tabs, focus rings, key values.
	-- The terminals' own accent, kept so the MDT and the menu are recognisably
	-- one system rather than two products sharing a login.
	accent = Color3.fromHex("#1B89BF"),
	-- Filled accent surfaces, such as a primary button background. Darker than
	-- accent so white label text on top still clears contrast.
	accentFill = Color3.fromHex("#125E85"),
	-- Confirmed, on-duty, available.
	success = Color3.fromRGB(89, 215, 144),
	-- Needs attention but is not failing yet: expiring, pending, restricted.
	warning = Color3.fromRGB(241, 176, 47),
	-- Failure and irreversible actions. Reserved so it keeps its urgency.
	danger = Color3.fromRGB(244, 82, 92),
})

DesignTokens.Radius = table.freeze({
	-- Outer shell of a full-screen panel or modal, where the curve is read as
	-- the shape of the window itself.
	shell = 22,
	-- Nested panels and columns inside a shell. Deliberately below shell so the
	-- nesting order stays visible.
	panel = 14,
	-- Cards and list rows.
	card = 10,
	-- Buttons, inputs, chips. One value, because a button next to a field with a
	-- different radius is the drift players actually notice.
	control = 8,
})

DesignTokens.Font = table.freeze({
	-- Body copy, values, anything read in quantity.
	regular = Enum.Font.Gotham,
	-- Titles, section labels and button text. Weight carries the hierarchy here,
	-- so the size steps below can stay small and close together.
	bold = Enum.Font.GothamBold,
})

DesignTokens.Text = table.freeze({
	-- Panel or page title. One per screen.
	title = 18,
	-- Card headings and the header of a group of rows.
	subtitle = 14,
	-- Uppercase section label above a group. Small on purpose: it is a signpost,
	-- not content.
	section = 10,
	-- Default body copy.
	body = 12,
	-- Body copy in dense lists and tables where 12 would force wrapping.
	dense = 11,
	-- Button labels. Sits between body and dense so a button never out-shouts
	-- the content it acts on.
	button = 11,
})

DesignTokens.Spacing = table.freeze({
	-- Between an icon and its label, or a value and its unit. Anything closer
	-- reads as one word.
	tight = 4,
	-- Default gap between stacked rows and between controls in a toolbar.
	gap = 8,
	-- Padding inside a card or row.
	inset = 12,
	-- Padding inside a panel body, against its edge.
	pad = 16,
	-- Between unrelated groups within one panel, where the space itself is the
	-- only divider.
	section = 20,
})

DesignTokens.Stroke = table.freeze({
	-- Every outline. Thicker strokes were being used to fake emphasis, which is
	-- what accent colour is for.
	thickness = 1,
	-- Border colour is opaque enough that a visible hairline needs this much
	-- knocked off it.
	transparency = 0.15,
	-- Dividers between rows in a list, where a full-strength border would count
	-- the rows out loud.
	dividerTransparency = 0.6,
})

DesignTokens.Scroll = table.freeze({
	-- Wide enough to grab on a touchscreen, narrow enough not to eat the gutter.
	barThickness = 6,
	-- The bar is a position indicator, not a control, until it is grabbed.
	barTransparency = 0.4,
})

DesignTokens.Scrim = table.freeze({
	-- Backdrop behind a modal. Black rather than tinted navy, so the panel on
	-- top keeps its own colour relationship with the canvas.
	colour = Color3.new(0, 0, 0),
	-- Enough to push the background out of focus while leaving it recognisable,
	-- which matters when a modal is confirming something about what is behind it.
	transparency = 0.28,
})

return table.freeze(DesignTokens)
