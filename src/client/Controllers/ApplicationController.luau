--!strict
local ApplicationController = {}
function ApplicationController:Init(context: any)
	self.context = context
end
function ApplicationController:Start() end
function ApplicationController:Submit(formId: string, answers: { [string]: string }): any
	return self.context.Controllers.NetworkController:Request(
		"SubmitApplication",
		{ FormId = formId, Answers = answers }
	)
end
function ApplicationController:Destroy() end
return ApplicationController
