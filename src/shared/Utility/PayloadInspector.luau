--!strict

local PayloadInspector = {}

function PayloadInspector.validate(value: any, limits: any?): (boolean, string?)
	local options = limits or {}
	local maximumDepth = options.MaximumDepth or 8
	local maximumNodes = options.MaximumNodes or 256
	local maximumStringBytes = options.MaximumStringBytes or 2048
	local nodes = 0
	local visiting = {}

	local function inspect(item: any, depth: number): (boolean, string?)
		nodes += 1
		if nodes > maximumNodes then
			return false, "TOO_MANY_VALUES"
		end
		if depth > maximumDepth then
			return false, "TOO_DEEP"
		end
		local kind = typeof(item)
		if kind == "string" then
			return #item <= maximumStringBytes, "STRING_TOO_LARGE"
		elseif kind == "number" then
			return item == item and item ~= math.huge and item ~= -math.huge, "INVALID_NUMBER"
		elseif kind == "boolean" or kind == "nil" then
			return true, nil
		elseif kind ~= "table" then
			return false, "UNSUPPORTED_ROBLOX_TYPE:" .. kind
		end
		if visiting[item] then
			return false, "CYCLIC_TABLE"
		end
		visiting[item] = true
		for key, child in item do
			local keyOk, keyReason = inspect(key, depth + 1)
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

return table.freeze(PayloadInspector)
