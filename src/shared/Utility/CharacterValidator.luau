--!strict

local CharacterValidator = {}

local function validName(value: any): boolean
	return type(value) == "string"
		and #value >= 2
		and #value <= 24
		and string.match(value, "^[A-Za-z][A-Za-z'%- ]*[A-Za-z]$") ~= nil
end

function CharacterValidator.identity(
	identity: any,
	now: DateTime?,
	minimumAge: number?,
	maximumAge: number?
): (boolean, string?)
	if
		type(identity) ~= "table"
		or not validName(identity.FirstName)
		or not validName(identity.LastName)
	then
		return false, "INVALID_NAME"
	end
	if
		type(identity.DateOfBirth) ~= "string"
		or not string.match(identity.DateOfBirth, "^%d%d%d%d%-%d%d%-%d%d$")
	then
		return false, "INVALID_DATE_OF_BIRTH"
	end
	local year, month, day = string.match(identity.DateOfBirth, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	local ok, birth =
		pcall(DateTime.fromUniversalTime, tonumber(year), tonumber(month), tonumber(day))
	if not ok then
		return false, "INVALID_DATE_OF_BIRTH"
	end
	local current = (now or DateTime.now()):ToUniversalTime()
	local age = current.Year - birth:ToUniversalTime().Year
	if
		current.Month < tonumber(month)
		or (current.Month == tonumber(month) and current.Day < tonumber(day))
	then
		age -= 1
	end
	if age < (minimumAge or 16) or age > (maximumAge or 100) then
		return false, "AGE_OUT_OF_RANGE"
	end
	return true, nil
end

return table.freeze(CharacterValidator)
