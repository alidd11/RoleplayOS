--!strict
local BusinessService = { businesses = {} }
function BusinessService:Init(context: any)
	self.context = context
end
function BusinessService:Start()
	for id, definition in self.context.Configuration.Businesses do
		self.businesses[id] = {
			BusinessId = id,
			DefinitionId = id,
			OwnerCharacterId = "",
			ManagerCharacterIds = {},
			EmployeeCharacterIds = {},
			Vacancies = definition.MaximumEmployees,
			WageBands = table.clone(definition.WageBands),
			Revenue = 0,
			Expenses = 0,
		}
	end
end
function BusinessService:CanHire(businessId: string, actorCharacterId: string): boolean
	local business = self.businesses[businessId]
	return business ~= nil
		and (business.OwnerCharacterId == actorCharacterId or table.find(
			business.ManagerCharacterIds,
			actorCharacterId
		) ~= nil)
		and #business.EmployeeCharacterIds < business.Vacancies
end
function BusinessService:Destroy()
	table.clear(self.businesses)
end
return BusinessService
