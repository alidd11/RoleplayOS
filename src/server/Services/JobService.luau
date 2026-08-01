--!strict
local JobService = {}
function JobService:Init(context: any)
	self.context = context
end
function JobService:Start() end
function JobService:GetCatalogue(): { any }
	local result = {}
	for _, job in self.context.Configuration.Jobs do
		table.insert(
			result,
			{ Id = job.Id, Name = job.Name, Class = job.Class, BaseWage = job.BaseWage }
		)
	end
	return result
end
function JobService:GetServerReward(jobId: string, completedTasks: number): (number?, string?)
	local job = self.context.Configuration.Jobs[jobId]
	if not job or completedTasks < 0 or completedTasks % 1 ~= 0 then
		return nil, "INVALID_JOB_REWARD"
	end
	return job.BaseWage + job.TaskReward * completedTasks, nil
end
function JobService:Destroy() end
return JobService
