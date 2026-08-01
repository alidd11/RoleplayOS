--!strict
local EstateAgentService = {}
function EstateAgentService:Init(context: any)
	self.context = context
end
function EstateAgentService:Start() end
function EstateAgentService:Catalogue(agentId: string): ({ any }?, string?)
	local agent = self.context.Configuration.EstateAgents[agentId]
	if not agent then
		return nil, "ESTATE_AGENT_NOT_FOUND"
	end
	local result = {}
	for _, id in agent.PropertyIds do
		local definition = self.context.Configuration.Properties[id]
		table.insert(result, {
			Id = id,
			Name = definition.Name,
			PurchasePrice = definition.PurchasePrice,
			RentPrice = definition.RentPrice,
			Available = self.context.Services:Get("PropertyService").holdingsByProperty[id] == nil,
		})
	end
	return result, nil
end
function EstateAgentService:Destroy() end
return EstateAgentService
