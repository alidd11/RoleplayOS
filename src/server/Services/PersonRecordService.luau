--!strict
local PersonRecordService = {}
function PersonRecordService:Init(context: any)
	self.context = context
end
function PersonRecordService:Start() end
function PersonRecordService:Search(
	query: string,
	page: number,
	accessProfile: string
): (any?, string?)
	return self.context.Services:Get("RecordIndexService"):SearchPeople(query, page, accessProfile)
end
function PersonRecordService:Destroy() end
return PersonRecordService
