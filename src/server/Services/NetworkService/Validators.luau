--!strict
local Validators = {}

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
