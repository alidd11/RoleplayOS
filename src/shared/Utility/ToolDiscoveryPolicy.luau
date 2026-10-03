--!strict

local ToolDiscoveryPolicy = {}

function ToolDiscoveryPolicy.shouldAutoEquip(value: any): boolean
	return value == true
end

return table.freeze(ToolDiscoveryPolicy)
