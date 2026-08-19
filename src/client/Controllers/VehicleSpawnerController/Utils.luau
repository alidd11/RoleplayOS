--!strict

local Tokens = require(script.Parent.Parent.Parent.UI.DesignTokens)
local C, R, T, S = Tokens.Colour, Tokens.Radius, Tokens.Text, Tokens.Stroke

local function formatMoney(amount: number): string
	local grouped = tostring(math.floor(math.max(amount, 0)))
	while true do
		local replaced
		grouped, replaced = string.gsub(grouped, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return grouped
end

local function frameVehicle(stage: ViewportFrame, model: Instance, closeness: number)
	local shown = model:Clone()
	shown.Parent = stage
	local camera = Instance.new("Camera")
	camera.Parent = stage
	stage.CurrentCamera = camera
	local centre, size = shown:GetBoundingBox()
	local distance = math.sqrt(size.X * size.X + size.Z * size.Z) * closeness
	-- These models are imported and do not agree on which way is forwards, so a
	-- fixed corner showed some nose on and the rest reversing towards the camera.
	-- The drive seat faces the way the car does, and survives the stripping
	-- because it is a part rather than a script.
	local seat = shown:FindFirstChildWhichIsA("VehicleSeat", true)
	local forward = if seat then seat.CFrame.LookVector else Vector3.new(0, 0, -1)
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.05 then
		forward = Vector3.new(0, 0, -1)
	end
	forward = forward.Unit
	local side = Vector3.new(-forward.Z, 0, forward.X)
	camera.CFrame = CFrame.lookAt(
		centre.Position
			+ forward * distance
			+ side * (distance * 0.72)
			+ Vector3.new(0, distance * 0.34, 0),
		centre.Position - Vector3.new(0, size.Y * 0.08, 0)
	)
	return shown
end

-- The vehicle itself, opened by clicking its card.
--
-- Colour moved here from the grid. On a card it was three squares under a price
-- competing with the buy button; here it is the decision the screen is about,
-- which matters because the choice is permanent - the record keeps it and
-- nothing in the game resprays - and because buying the same car again in
-- another colour is a normal thing to want.

return {
	Tokens = Tokens,
	C = C,
	R = R,
	T = T,
	S = S,
	formatMoney = formatMoney,
	frameVehicle = frameVehicle,
}
