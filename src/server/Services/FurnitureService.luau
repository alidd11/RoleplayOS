--!strict
local HttpService = game:GetService("HttpService")
local FurnitureService = {}
function FurnitureService:Init(context: any)
	self.context = context
end
function FurnitureService:Start() end
function FurnitureService:AddOwned(
	player: Player,
	characterId: string,
	definitionId: string
): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character or not self.context.Configuration.Furniture[definitionId] then
		return nil, "INVALID_FURNITURE"
	end
	local item =
		{ ItemId = HttpService:GenerateGUID(false), DefinitionId = definitionId, Quantity = 1 }
	table.insert(character.FurnitureInventory, item)
	self.context.Services:Get("DataService"):MarkDirty(player)
	return item, nil
end
function FurnitureService:Destroy() end
return FurnitureService
