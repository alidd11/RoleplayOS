--!strict
local InventoryService = {
	definitions = {
		Radio = { StackLimit = 1, Weight = 1 },
		Parcel = { StackLimit = 10, Weight = 2 },
	},
}
function InventoryService:Init(context: any)
	self.context = context
end
function InventoryService:Start() end
function InventoryService:Add(
	player: Player,
	characterId: string,
	definitionId: string,
	quantity: number
): (boolean, string?)
	local definition = self.definitions[definitionId]
	if not definition or quantity <= 0 or quantity % 1 ~= 0 then
		return false, "INVALID_ITEM"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return false, "CHARACTER_NOT_OWNED"
	end
	local found
	for _, item in character.Inventory do
		if item.DefinitionId == definitionId then
			found = item
		end
	end
	if found then
		if found.Quantity + quantity > definition.StackLimit then
			return false, "STACK_LIMIT"
		end
		found.Quantity += quantity
	else
		table.insert(character.Inventory, {
			ItemId = definitionId .. "-" .. tostring(os.clock()),
			DefinitionId = definitionId,
			Quantity = quantity,
			Metadata = {},
		})
	end
	self.context.Services:Get("DataService"):MarkDirty(player)
	return true, nil
end
function InventoryService:Destroy() end
return InventoryService
