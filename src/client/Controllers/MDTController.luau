--!strict
local MDTController = {}
function MDTController:Init(context: any)
	self.context = context
end
function MDTController:Start() end
function MDTController:Search(recordType: string, query: string, page: number?): any
	return self.context.Controllers.NetworkController:Request(
		"MDTSearch",
		{ Type = recordType, Query = query, Page = page or 1 }
	)
end
function MDTController:Destroy() end
return MDTController
