--!strict

-- Pure projection from world space into normalised map space.
--
-- A single bounds part defines the mapped area. Everything drawn on the
-- minimap and the MDT tactical map goes through here so the two surfaces
-- cannot drift apart, and so the maths stays testable without a DataModel.

local MapProjection = {}

export type Point = { X: number, Y: number }

-- Returns normalised 0..1 coordinates, where X runs along the bounds' local X
-- axis and Y along its local Z axis. Values are clamped, so callers can treat
-- anything outside the mapped area as sitting on the edge rather than
-- disappearing or drawing off-surface.
function MapProjection.project(position: Vector3, boundsCFrame: CFrame, boundsSize: Vector3): Point
	local relative = boundsCFrame:PointToObjectSpace(position)
	return {
		X = math.clamp(relative.X / boundsSize.X + 0.5, 0, 1),
		Y = math.clamp(relative.Z / boundsSize.Z + 0.5, 0, 1),
	}
end

-- Projects into a square window of the given radius centred on a point, rather
-- than into the whole mapped area. A region-sized map projected whole leaves
-- every road a few thousandths of the surface wide, so they collapse into an
-- unreadable smear; a window keeps scale constant however large the world is.
-- Returns nil when the position falls outside the window, so callers can skip
-- it rather than pinning it to an edge.
function MapProjection.window(position: Vector3, centre: Vector3, radius: number): Point?
	if radius <= 0 then
		return nil
	end
	local dx = position.X - centre.X
	local dz = position.Z - centre.Z
	if math.abs(dx) > radius or math.abs(dz) > radius then
		return nil
	end
	return { X = dx / (radius * 2) + 0.5, Y = dz / (radius * 2) + 0.5 }
end

-- Normalised footprint of a part within a window of the given radius.
function MapProjection.windowFootprint(partSize: Vector3, radius: number, minimum: number): Point
	local span = math.max(1, radius * 2)
	return {
		X = math.clamp(partSize.X / span, minimum, 1),
		Y = math.clamp(partSize.Z / span, minimum, 1),
	}
end

-- True when the position lies inside the mapped area. project clamps, so this
-- is the only way to distinguish "on the edge" from "beyond the edge".
function MapProjection.contains(
	position: Vector3,
	boundsCFrame: CFrame,
	boundsSize: Vector3
): boolean
	local relative = boundsCFrame:PointToObjectSpace(position)
	return math.abs(relative.X) <= boundsSize.X / 2 and math.abs(relative.Z) <= boundsSize.Z / 2
end

-- Normalised footprint of a part, used to draw road segments to scale.
function MapProjection.footprint(partSize: Vector3, boundsSize: Vector3, minimum: number): Point
	return {
		X = math.clamp(partSize.X / boundsSize.X, minimum, 1),
		Y = math.clamp(partSize.Z / boundsSize.Z, minimum, 1),
	}
end

-- Serialised world position for transport and storage. Persistent records must
-- hold primitives, never Vector3s, so services publish positions in this shape.
function MapProjection.serialise(position: Vector3): { X: number, Y: number, Z: number }
	return { X = position.X, Y = position.Y, Z = position.Z }
end

function MapProjection.deserialise(value: any): Vector3?
	if
		type(value) ~= "table"
		or type(value.X) ~= "number"
		or type(value.Y) ~= "number"
		or type(value.Z) ~= "number"
	then
		return nil
	end
	return Vector3.new(value.X, value.Y, value.Z)
end

return table.freeze(MapProjection)
