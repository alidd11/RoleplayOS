--!strict

local PhoneValidator = {}

function PhoneValidator.number(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local normalised = string.gsub(value, "[%s%-()]", "")
	if string.match(normalised, "^07%d%d%d%d%d%d%d%d%d$") == nil then
		return nil
	end
	return normalised
end

function PhoneValidator.message(value: any, maximumLength: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$") or ""
	if #trimmed < 1 or #trimmed > maximumLength then
		return nil
	end
	return trimmed
end

function PhoneValidator.numberFromCharacterId(characterId: string): string
	local hex = string.gsub(characterId, "[^%x]", "")
	local tail = string.sub(hex .. "00000000", 1, 8)
	local value = tonumber(tail, 16) or 0
	return "07" .. string.format("%09d", value % 1000000000)
end

return table.freeze(PhoneValidator)
