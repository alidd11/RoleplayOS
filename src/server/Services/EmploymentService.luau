--!strict
local HttpService = game:GetService("HttpService")
local EmploymentService = {}
function EmploymentService:Init(context: any)
	self.context = context
end
function EmploymentService:Start() end
function EmploymentService:Hire(player: Player, characterId: string, jobId: string): (any?, string?)
	local job = self.context.Configuration.Jobs[jobId]
	if not job then
		return nil, "JOB_NOT_FOUND"
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local character = session and session.Profile.Characters[characterId]
	if not character then
		return nil, "CHARACTER_NOT_OWNED"
	end
	if job.Class ~= "Public" then
		return nil, "APPLICATION_REQUIRED"
	end
	local record = {
		EmploymentId = HttpService:GenerateGUID(false),
		JobId = jobId,
		Grade = 1,
		Experience = 0,
		Warnings = {},
		StartedAt = os.time(),
	}
	table.insert(character.Employment, record)
	self.context.Services:Get("DataService"):MarkDirty(player)
	return record, nil
end
function EmploymentService:Destroy() end
return EmploymentService
