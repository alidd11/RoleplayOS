--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BoundsValidator = require(ReplicatedStorage.RoleplayOS.Shared.FurniturePlacementValidator)
local PropertyAccess = require(ReplicatedStorage.RoleplayOS.Shared.PropertyAccess)
local FurniturePlacementService = { collisionValidator = nil }
function FurniturePlacementService:Init(context: any)
	self.context = context
end
function FurniturePlacementService:Start() end
function FurniturePlacementService:SetCollisionValidator(
	callback: (string, any, Vector3) -> boolean
)
	self.collisionValidator = callback
end
function FurniturePlacementService:Place(
	player: Player,
	characterId: string,
	propertyId: string,
	itemId: string,
	transform: any,
	roomMinimum: Vector3,
	roomMaximum: Vector3
): (any?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	local holding
	for _, value in character.Properties do
		if value.PropertyId == propertyId then
			holding = value
		end
	end
	local access = holding and PropertyAccess.canEnter(holding, characterId)
	if not access then
		return nil, "NO_PROPERTY_ACCESS"
	end
	local item
	for _, value in character.FurnitureInventory do
		if value.ItemId == itemId then
			item = value
		end
	end
	local definition = item and self.context.Configuration.Furniture[item.DefinitionId]
	if not definition then
		return nil, "ITEM_NOT_OWNED"
	end
	local valid, reason = BoundsValidator.validate(
		transform,
		roomMinimum,
		roomMaximum,
		Vector3.new(table.unpack(definition.Bounds))
	)
	if not valid then
		return nil, reason
	end
	if
		self.collisionValidator
		and not self.collisionValidator(
			propertyId,
			transform,
			Vector3.new(table.unpack(definition.Bounds))
		)
	then
		return nil, "PLACEMENT_COLLIDES"
	end
	if
		#(character.FurniturePlacements or {})
		>= self.context.Configuration.Properties[propertyId].FurnitureCapacity
	then
		return nil, "FURNITURE_LIMIT_REACHED"
	end
	character.FurniturePlacements = character.FurniturePlacements or {}
	local placement = {
		PlacementId = HttpService:GenerateGUID(false),
		ItemId = itemId,
		PropertyId = propertyId,
		Transform = transform,
	}
	table.insert(character.FurniturePlacements, placement)
	self.context.Services:Get("DataService"):MarkDirty(player)
	return placement, nil
end
function FurniturePlacementService:Destroy() end
return FurniturePlacementService
