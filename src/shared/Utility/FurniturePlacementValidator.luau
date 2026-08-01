--!strict

local Validator = {}

function Validator.validate(
	transform: any,
	roomMinimum: Vector3,
	roomMaximum: Vector3,
	itemSize: Vector3
): (boolean, string?)
	if
		type(transform) ~= "table"
		or type(transform.Position) ~= "table"
		or type(transform.Rotation) ~= "table"
	then
		return false, "INVALID_TRANSFORM"
	end
	local p = transform.Position
	local r = transform.Rotation
	if #p ~= 3 or #r ~= 3 then
		return false, "INVALID_TRANSFORM"
	end
	for _, value in { p[1], p[2], p[3], r[1], r[2], r[3] } do
		if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
			return false, "INVALID_NUMBER"
		end
	end
	if math.abs(r[1]) > 0.001 or math.abs(r[3]) > 0.001 or math.abs(r[2]) > math.pi * 2 then
		return false, "INVALID_ROTATION"
	end
	local half = itemSize / 2
	local position = Vector3.new(p[1], p[2], p[3])
	if
		position.X - half.X < roomMinimum.X
		or position.Y - half.Y < roomMinimum.Y
		or position.Z - half.Z < roomMinimum.Z
		or position.X + half.X > roomMaximum.X
		or position.Y + half.Y > roomMaximum.Y
		or position.Z + half.Z > roomMaximum.Z
	then
		return false, "OUT_OF_BOUNDS"
	end
	return true, nil
end

return table.freeze(Validator)
