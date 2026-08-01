--!strict
local Players = game:GetService("Players")
local PersonRecordService = {}
function PersonRecordService:Init(context: any)
	self.context = context
end
function PersonRecordService:Start() end
function PersonRecordService:Search(query: string, page: number): any
	local results = {}
	for _, player in Players:GetPlayers() do
		local session = self.context.Services:Get("DataService"):GetSession(player)
		if session then
			for _, character in session.Profile.Characters do
				local name =
					string.lower(character.Identity.FirstName .. " " .. character.Identity.LastName)
				if string.find(name, query, 1, true) then
					table.insert(results, {
						CharacterId = character.CharacterId,
						FullName = character.Identity.FirstName
							.. " "
							.. character.Identity.LastName,
						DateOfBirth = character.Identity.DateOfBirth,
						Licences = character.Licences,
						Flags = {},
					})
				end
			end
		end
	end
	local size = self.context.Configuration.MDT.PageSize
	local startIndex = (math.max(page, 1) - 1) * size + 1
	return {
		Items = table.move(results, startIndex, math.min(#results, startIndex + size - 1), 1, {}),
		Page = page,
		Total = #results,
	}
end
function PersonRecordService:Destroy() end
return PersonRecordService
