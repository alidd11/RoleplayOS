--!strict

local ProgressionVisibility = {}

-- A whitelisted server is still the public tier: entry is gated on a group, but
-- the experience inside it is the open one, so the public heads-up display
-- belongs there too. Only a community's own private server is excluded.
function ProgressionVisibility.isPublicHudAllowed(serverKind: string, teamDefinition: any?): boolean
	return (serverKind == "Public" or serverKind == "Whitelisted")
		and type(teamDefinition) == "table"
		and teamDefinition.AutoAssignable == true
end

return table.freeze(ProgressionVisibility)
