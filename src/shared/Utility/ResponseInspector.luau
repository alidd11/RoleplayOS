--!strict

local ResponseInspector = {}

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function ResponseInspector.validate(value: any, limits: any?): (boolean, string?)
	local options = limits or {}
	local maximumDepth = options.MaximumResponseDepth or 12
	local maximumNodes = options.MaximumResponseNodes or 8192
	local maximumStringBytes = options.MaximumResponseStringBytes or 4096
	local maximumTotalStringBytes = options.MaximumResponseTotalStringBytes or 131072
	local nodes = 0
	local stringBytes = 0
	local visiting = {}

	local function countNode(): (boolean, string?)
		nodes += 1
		if nodes > maximumNodes then
			return false, "TOO_MANY_VALUES"
		end
		return true, nil
	end

	local function inspectString(item: string): (boolean, string?)
		if #item > maximumStringBytes then
			return false, "STRING_TOO_LARGE"
		end
		stringBytes += #item
		if stringBytes > maximumTotalStringBytes then
			return false, "TOTAL_STRING_BYTES_TOO_LARGE"
		end
		return true, nil
	end

	local inspect: (any, number) -> (boolean, string?)

	local function inspectKey(key: any, depth: number): (boolean, string?)
		local nodeOk, nodeReason = countNode()
		if not nodeOk then
			return false, nodeReason
		end
		if depth > maximumDepth then
			return false, "TOO_DEEP"
		end
		local kind = typeof(key)
		if kind == "string" then
			return inspectString(key)
		elseif kind == "number" then
			return finite(key), "INVALID_NUMBER"
		end
		return false, "UNSUPPORTED_KEY_TYPE:" .. kind
	end

	inspect = function(item: any, depth: number): (boolean, string?)
		local nodeOk, nodeReason = countNode()
		if not nodeOk then
			return false, nodeReason
		end
		if depth > maximumDepth then
			return false, "TOO_DEEP"
		end
		local kind = typeof(item)
		if kind == "string" then
			return inspectString(item)
		elseif kind == "number" then
			return finite(item), "INVALID_NUMBER"
		elseif kind == "boolean" or kind == "nil" then
			return true, nil
		elseif kind == "Vector3" then
			return finite(item.X) and finite(item.Y) and finite(item.Z), "INVALID_VECTOR3"
		elseif kind ~= "table" then
			return false, "UNSUPPORTED_ROBLOX_TYPE:" .. kind
		end
		if visiting[item] then
			return false, "CYCLIC_TABLE"
		end
		visiting[item] = true
		for key, child in item do
			local keyOk, keyReason = inspectKey(key, depth + 1)
			if not keyOk then
				visiting[item] = nil
				return false, keyReason
			end
			local childOk, childReason = inspect(child, depth + 1)
			if not childOk then
				visiting[item] = nil
				return false, childReason
			end
		end
		visiting[item] = nil
		return true, nil
	end

	return inspect(value, 0)
end

return table.freeze(ResponseInspector)
