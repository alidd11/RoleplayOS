--!strict

local Serialisation = {}

function Serialisation.vector3(value: Vector3): { number }
	return { value.X, value.Y, value.Z }
end

function Serialisation.toVector3(value: any): Vector3?
	if type(value) ~= "table" or #value ~= 3 then
		return nil
	end
	for _, component in value do
		if
			type(component) ~= "number"
			or component ~= component
			or math.abs(component) == math.huge
		then
			return nil
		end
	end
	return Vector3.new(value[1], value[2], value[3])
end

function Serialisation.cframe(value: CFrame): { Position: { number }, Rotation: { number } }
	local rx, ry, rz = value:ToOrientation()
	return { Position = Serialisation.vector3(value.Position), Rotation = { rx, ry, rz } }
end

function Serialisation.toCFrame(value: any): CFrame?
	if type(value) ~= "table" then
		return nil
	end
	local position = Serialisation.toVector3(value.Position)
	local rotation = Serialisation.toVector3(value.Rotation)
	if not position or not rotation then
		return nil
	end
	return CFrame.new(position) * CFrame.fromOrientation(rotation.X, rotation.Y, rotation.Z)
end

return table.freeze(Serialisation)
