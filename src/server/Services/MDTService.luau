--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RolePermissions = require(ReplicatedStorage.RoleplayOS.Shared.RolePermissions)
local DispatchPolicy = require(ReplicatedStorage.RoleplayOS.Shared.DispatchPolicy)
local MDTService = {}
function MDTService:Init(context: any)
	self.context = context
end
function MDTService:Start() end
-- Kept taking a department for any caller that still passes one, but the duty
-- is what actually decides, because a role may hold less than its department.
function MDTService:HasPermission(subject: any, permission: string): boolean
	if type(subject) == "string" then
		local permissions = self.context.Configuration.MDT.PermissionByDepartment[subject] or {}
		return table.find(permissions, permission) ~= nil
	end
	return RolePermissions.has(self.context.Configuration, subject, permission)
end
function MDTService:GetDuty(player: Player): any?
	return self.context.Services:Get("DutyService"):Get(player)
end
function MDTService:CanUse(player: Player): boolean
	return DispatchPolicy.canUseMdt(
		self:GetDuty(player),
		self.context.Configuration.MDT.AllowedDepartments
	)
end
function MDTService:CanUsePermission(player: Player, permission: string): boolean
	local duty = self:GetDuty(player)
	return self:CanUse(player) and self:HasPermission(duty, permission)
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
function MDTService:AccessSummary(player: Player): any
	local duty = self:GetDuty(player)
	if not self:CanUse(player) then
		return { Allowed = false, Permissions = {} }
	end
	local unit = self.context.Services:Get("UnitService").units[tostring(player.UserId)]
	local unitStatuses = {}
	for _, status in self.context.Configuration.Dispatch.UnitStatuses do
		-- Assigned is dispatch's decision, not a state an officer may declare.
		if status ~= "Assigned" then
			table.insert(unitStatuses, status)
		end
	end
	return {
		Allowed = true,
		DepartmentId = duty.DepartmentId,
		RoleId = duty.RoleId,
		-- Through the same resolver the enforcement uses. Read straight from the
		-- department, this told a PCSO's terminal it held warrant, custody and
		-- blue light authority that every individual action then refused. The
		-- checks were right; the summary describing them was not.
		Permissions = RolePermissions.forDuty(self.context.Configuration, duty),
		-- The officer's own unit state, so the terminal can show what dispatch is
		-- looking at rather than only what the officer last pressed. Their own
		-- record only; the full board is a separate, separately gated request.
		UnitStatus = unit and unit.Status or nil,
		-- The statuses an officer may put themselves into. Assigned is absent by
		-- design: being sent to a call is dispatch's decision, not a state a unit
		-- may declare for itself.
		UnitStatuses = unitStatuses,
	}
end
function MDTService:Destroy() end
return MDTService
