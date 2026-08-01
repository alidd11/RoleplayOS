--!strict

local Generator = {}
local alphabet = "ABCDEFGHJKLMNPRSTUVWXYZ"

function Generator.generate(random: Random?): string
	local rng = random or Random.new()
	local function letter(): string
		local index = rng:NextInteger(1, #alphabet)
		return string.sub(alphabet, index, index)
	end
	return string.format(
		"%s%s%02d %s%s%s",
		letter(),
		letter(),
		rng:NextInteger(0, 99),
		letter(),
		letter(),
		letter()
	)
end

return table.freeze(Generator)
