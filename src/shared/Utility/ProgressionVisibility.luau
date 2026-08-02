--!strict

local ProgressionVisibility = {}

function ProgressionVisibility.isPublicHudAllowed(serverKind: string, teamDefinition: any?): boolean
	return serverKind == "Public"
		and type(teamDefinition) == "table"
		and teamDefinition.AutoAssignable == true
end

return table.freeze(ProgressionVisibility)
