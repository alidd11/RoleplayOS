--!strict
local InventoryService = {
	definitions = {
		Radio = { StackLimit = 1, Weight = 1 },
		Parcel = { StackLimit = 10, Weight = 2 },
		Sandwich = { StackLimit = 1, Weight = 1 },
	},
}

local function validQuantity(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function validInventory(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local length = #value
	local count = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > length then
			return false
		end
		count += 1
	end
	-- Readable rows may still form a dictionary or sparse list. Refuse those
	-- before table.remove can fail after a quantity has already been consumed.
	return count == length
end

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
	if not definition or not validQuantity(quantity) then
		return false, "INVALID_ITEM"
	end
	if quantity > definition.StackLimit then
		return false, "STACK_LIMIT"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if type(character) ~= "table" then
		return false, "CHARACTER_NOT_OWNED"
	end
	-- Missing legacy containers may be backfilled, but present unreadable data
	-- must remain available for recovery rather than be overwritten and saved.
	if character.Inventory == nil then
		character.Inventory = {}
	elseif not validInventory(character.Inventory) then
		return false, "INVALID_INVENTORY"
	end
	local found
	for _, item in character.Inventory do
		if type(item) == "table" and item.DefinitionId == definitionId then
			if not validQuantity(item.Quantity) then
				return false, "INVALID_ITEM_STATE"
			end
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
-- Takes a quantity back out, and drops the entry when nothing is left.
--
-- There was no way to remove anything: things could be added to a character's
-- inventory and never left it, so nothing in it could be spent, used or lost.
function InventoryService:Remove(
	player: Player,
	characterId: string,
	definitionId: string,
	quantity: number
): (boolean, string?)
	if not validQuantity(quantity) then
		return false, "INVALID_ITEM"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if type(character) ~= "table" then
		return false, "CHARACTER_NOT_OWNED"
	end
	if character.Inventory == nil then
		return false, "NOT_HELD"
	elseif not validInventory(character.Inventory) then
		return false, "INVALID_INVENTORY"
	end
	for index, item in character.Inventory do
		if type(item) == "table" and item.DefinitionId == definitionId then
			if not validQuantity(item.Quantity) then
				return false, "INVALID_ITEM_STATE"
			end
			if item.Quantity < quantity then
				return false, "NOT_ENOUGH"
			end
			item.Quantity -= quantity
			if item.Quantity <= 0 then
				table.remove(character.Inventory, index)
			end
			self.context.Services:Get("DataService"):MarkDirty(player)
			return true, nil
		end
	end
	return false, "NOT_HELD"
end

-- Whether the character is carrying at least one of something.
function InventoryService:Has(character: any, definitionId: string): boolean
	if type(character) ~= "table" or not validInventory(character.Inventory) then
		return false
	end
	for _, item in character.Inventory do
		if
			type(item) == "table"
			and item.DefinitionId == definitionId
			and validQuantity(item.Quantity)
		then
			return true
		end
	end
	return false
end

function InventoryService:Destroy() end
return InventoryService
