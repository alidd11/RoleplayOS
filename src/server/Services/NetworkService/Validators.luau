--!strict
local Validators = {}

local MAXIMUM_SAFE_INTEGER = 9007199254740991

function Validators.playerUserId(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value ~= 0
		and value % 1 == 0
		and math.abs(value) <= MAXIMUM_SAFE_INTEGER
end

function Validators.boundedString(value: any, minimum: number, maximum: number): boolean
	return type(value) == "string" and #value >= minimum and #value <= maximum
end

function Validators.tablePayload(value: any): (boolean, string?)
	return type(value) == "table", "EXPECTED_TABLE"
end

function Validators.boundedStringArray(value: any, maximum: number): boolean
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, item in value do
		count += 1
		if count > maximum or type(key) ~= "number" or type(item) ~= "string" then
			return false
		end
	end
	return true
end

return Validators
