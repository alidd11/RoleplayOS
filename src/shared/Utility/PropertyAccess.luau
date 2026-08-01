--!strict

local PropertyAccess = {}

function PropertyAccess.canEnter(holding: any, characterId: string): (boolean, string)
	if holding.CharacterId == characterId then
		return true, "OWNER"
	end
	for _, id in holding.AccessCharacterIds or {} do
		if id == characterId then
			return true, "KEYHOLDER"
		end
	end
	return false, "NO_PROPERTY_ACCESS"
end

return table.freeze(PropertyAccess)
