--!strict
local VehicleRecordService = {}
function VehicleRecordService:Init(context: any)
	self.context = context
end
function VehicleRecordService:Start() end
function VehicleRecordService:Search(
	query: string,
	page: number,
	includeWarrants: boolean?
): (any?, string?)
	return self.context.Services
		:Get("RecordIndexService")
		:SearchVehicles(query, page, includeWarrants)
end
function VehicleRecordService:Destroy() end
return VehicleRecordService
