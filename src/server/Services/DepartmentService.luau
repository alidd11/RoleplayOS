--!strict
local DepartmentService = {}
function DepartmentService:Init(context: any)
	self.context = context
end
function DepartmentService:Start() end
-- Ranks carry an abbreviation and whether they wear a shoulder number, so an
-- entry is a table rather than the bare name it used to be.
function DepartmentService:GetRankName(departmentId: string, rank: number): string?
	local department = self.context.Configuration.Departments[departmentId]
	local entry = department and department.Ranks and department.Ranks[rank]
	if type(entry) == "table" then
		return entry.Name
	end
	return if type(entry) == "string" then entry else nil
end
function DepartmentService:Destroy() end
return DepartmentService
