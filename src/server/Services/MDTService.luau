--!strict
local MDTService = {}
function MDTService:Init(context: any)
	self.context = context
end
function MDTService:Start() end
function MDTService:HasPermission(departmentId: string, permission: string): boolean
	local permissions = self.context.Configuration.MDT.PermissionByDepartment[departmentId] or {}
	return table.find(permissions, permission) ~= nil
end
function MDTService:SanitiseQuery(query: any): (string?, string?)
	if type(query) ~= "string" then
		return nil, "INVALID_QUERY"
	end
	query = string.gsub(query, "[%c%p]", "")
	query = string.sub(query, 1, self.context.Configuration.MDT.MaximumQueryLength)
	if #query < 2 then
		return nil, "QUERY_TOO_SHORT"
	end
	return string.lower(query), nil
end
function MDTService:AuditSearch(player: Player, queryType: string, requestId: string)
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "MDT.Search",
		Target = queryType,
		RequestId = requestId,
		Metadata = {},
	})
end
function MDTService:Destroy() end
return MDTService
