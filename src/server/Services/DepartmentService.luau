--!strict
local DepartmentService = {}
function DepartmentService:Init(context: any)
	self.context = context
end
function DepartmentService:Start() end
function DepartmentService:GetRankName(departmentId: string, rank: number): string?
	local department = self.context.Configuration.Departments[departmentId]
	return department and department.Ranks[rank]
end
function DepartmentService:Destroy() end
return DepartmentService
