--!strict
local HttpService = game:GetService("HttpService")
local IncidentService = { incidents = {} }
function IncidentService:Init(context: any)
	self.context = context
end
function IncidentService:Start() end
function IncidentService:Create(player: Player, data: any): (any?, string?)
	if type(data.Title) ~= "string" or #data.Title < 3 or #data.Title > 120 then
		return nil, "INVALID_INCIDENT"
	end
	local incident = {
		IncidentId = HttpService:GenerateGUID(false),
		Title = data.Title,
		Status = "Open",
		PersonIds = data.PersonIds or {},
		VehicleIds = data.VehicleIds or {},
		Notes = {},
		CreatedAt = os.time(),
	}
	self.incidents[incident.IncidentId] = incident
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Incident.Created",
		Target = incident.IncidentId,
		Metadata = {},
	})
	return incident, nil
end
function IncidentService:Close(player: Player, incidentId: string): (boolean, string?)
	local incident = self.incidents[incidentId]
	if not incident then
		return false, "INCIDENT_NOT_FOUND"
	end
	incident.Status = "Closed"
	incident.ClosedAt = os.time()
	self.context.Services:Get("AuditService"):Record({
		ActorUserId = player.UserId,
		Action = "Incident.Closed",
		Target = incidentId,
		Metadata = {},
	})
	return true, nil
end
function IncidentService:Destroy()
	table.clear(self.incidents)
end
return IncidentService
