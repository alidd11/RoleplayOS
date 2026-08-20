--!strict

local JobsPanel = {}

function JobsPanel.create(deps: any): () -> ()
	local context = deps.context
	local scroll = deps.scroll
	local pageTitle = deps.pageTitle
	local pageDescription = deps.pageDescription
	local sectionHeading = deps.sectionHeading
	local getMenuData = deps.getMenuData
	local getSelectedCharacterId = deps.getSelectedCharacterId
	local CIVILIAN_JOB_ROLE_IDS = deps.civilianJobRoleIds
	local COLOURS = deps.colours
	local clear = deps.clear
	local card = deps.card
	local text = deps.text
	local shortLandscape = deps.shortLandscape
	local posterActionHeight = deps.posterActionHeight
	local posterColumns = deps.posterColumns
	local posterMinimumHeight = deps.posterMinimumHeight
	local tileGrid = deps.tileGrid
	local posterTile = deps.posterTile
	local rolePresentation = deps.rolePresentation
	local roleTileImageUri = deps.roleTileImageUri
	local activateRole = deps.activateRole
	local audioFeedback = deps.audioFeedback
	local dismissToWorld = deps.dismissToWorld
	local render: () -> ()
	render = function()
		deps.nextGeneration()
		local menuData = getMenuData()
		local selectedCharacterId = getSelectedCharacterId()
		clear(scroll)
		pageTitle.Text = "Civilian jobs"
		pageDescription.Text = "Pick up work that is available in the city today."
		sectionHeading("Civilian jobs", "Only fully connected civilian jobs appear here.")
		-- Civilian work that is built as a role rather than as a Job entry.
		--
		-- These join through the same duty flow as any service, so they are drawn
		-- from menuData.Roles and handed to activateRole exactly as the Play page
		-- would have. Listing them here is a statement about what they are, not a
		-- second way of joining them.
		local jobRoles = {}
		for _, role in menuData and menuData.Roles or {} do
			if role.Visible and CIVILIAN_JOB_ROLE_IDS[role.Id] then
				table.insert(jobRoles, role)
			end
		end
		local jobs = {}
		for _, job in pairs(menuData and menuData.Jobs or {}) do
			-- A catalogue entry is a promise: it must have a working join path.
			-- Do not show future/application placeholders as if they were playable.
			if tostring(job.Id) == "TaxiDriver" then
				table.insert(jobs, job)
			end
		end
		-- One grid of one tile, whichever of the two payloads the work arrived in.
		--
		-- A player weighing up driving a bus against driving a taxi is choosing
		-- between two jobs. That one is configured as a role with a team and the
		-- other as a catalogue entry is a fact about the configuration, and
		-- letting it show had turned this page into a card followed by a list of
		-- rows, sharing nothing with each other or with the Play grid the same
		-- player had just come from.
		local entryCount = #jobRoles + #jobs
		if entryCount == 0 then
			local empty = card(scroll, if shortLandscape() then 110 else 132)
			local title = text(empty, "No work is available yet", 17, COLOURS.Text, true)
			title.Position = UDim2.fromOffset(20, 18)
			title.Size = UDim2.new(1, -40, 0, 26)
			local copy = text(
				empty,
				"New civilian systems will appear here when they are ready to play.",
				13,
				COLOURS.Muted
			)
			copy.Position = UDim2.fromOffset(20, 50)
			copy.Size = UDim2.new(1, -40, 0, 42)
			copy.TextWrapped = true
			return
		end
		local actionHeight = posterActionHeight()
		local jobGrid = tileGrid(scroll, {
			Name = "CivilianJobGrid",
			Count = entryCount,
			Columns = posterColumns(),
			MinHeight = posterMinimumHeight(),
		})
		for _, role in jobRoles do
			local presentation = rolePresentation(role)
			local _, join = posterTile(jobGrid, {
				Id = tostring(role.Id),
				Image = roleTileImageUri(role),
				Monogram = presentation.Icon,
				Title = tostring(role.Name),
				Detail = if role.Locked
					then tostring(role.LockMessage or "Requirements not met")
					else presentation.Label,
				Accent = presentation.Colour,
				ActionLabel = if role.Locked then "REQUIREMENTS" else "JOIN",
				ActionMuted = role.Locked,
				ActionHeight = actionHeight,
			})
			join.Activated:Connect(function()
				activateRole(role)
			end)
		end
		for _, job in jobs do
			local isTaxi = tostring(job.Id) == "TaxiDriver"
			local access = if tostring(job.Class) == "Public"
				then "PUBLIC EMPLOYMENT"
				else "APPLICATION ROLE"
			local hasActiveCharacter = type(menuData and menuData.ActiveCharacterId) == "string"
				and menuData.ActiveCharacterId ~= ""
			-- What the button says when it is not mid-flight. Every path that
			-- gives up puts this back, so a refused shift never leaves the tile
			-- offering a different action from the one it opened with.
			local idleActionText = if hasActiveCharacter then "START SHIFT" else "ENTER CITY"
			local _, action = posterTile(jobGrid, {
				Id = tostring(job.Id),
				Image = roleTileImageUri(job),
				-- Catalogue work has no uploaded artwork, so the tile carries the
				-- opening of the job's own name where a department mark would sit.
				Monogram = string.upper(string.sub(tostring(job.Name), 1, 4)),
				Title = tostring(job.Name),
				Detail = access .. "  ·  £" .. tostring(job.BaseWage or 0) .. " base wage",
				Accent = COLOURS.Success,
				ActionLabel = idleActionText,
				ActionMuted = not isTaxi,
				ActionHeight = actionHeight,
			})
			action.Selectable = isTaxi
			if isTaxi then
				action.Activated:Connect(function()
					action.Active = false
					action.Text = if hasActiveCharacter then "STARTING…" else "ENTERING CITY…"
					if not hasActiveCharacter then
						local characterId = selectedCharacterId
							or (menuData and menuData.LastCharacterId)
						if
							not characterId
							and menuData
							and menuData.Characters
							and #menuData.Characters == 1
						then
							characterId = menuData.Characters[1].CharacterId
						end
						if not characterId then
							context.Controllers.NotificationController:Show(
								"Create a civilian character before starting work.",
								"Taxi unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
							action.Active = true
							action.Text = idleActionText
							return
						end
						local selected = context.Controllers.CharacterController:Select(characterId)
						local entered = if selected.Success
							then (function()
								local civilianSpawnId: string? = nil
								for _, role in menuData and menuData.Roles or {} do
									if role.Id == "Civilian" or role.DepartmentId == "Civilian" then
										for _, spawn in role.Spawns or {} do
											if
												type(spawn.SpawnId) == "string"
												and spawn.SpawnId ~= ""
											then
												civilianSpawnId = spawn.SpawnId
												break
											end
										end
									end
									if civilianSpawnId then
										break
									end
								end
								if not civilianSpawnId then
									return { Success = false }
								end
								return context.Controllers.DutyController:EnterCivilian(
									characterId,
									civilianSpawnId
								)
							end)()
							else selected
						if not entered.Success then
							context.Controllers.NotificationController:Show(
								"Select a civilian character before starting work.",
								"Taxi unavailable"
							)
							if audioFeedback then
								audioFeedback:Error()
							end
							action.Active = true
							action.Text = idleActionText
							return
						end
					end
					local response =
						context.Controllers.NetworkController:Request("TaxiStartShift", {})
					context.Controllers.NotificationController:Show(response.Message, "Taxi")
					if response.Success then
						dismissToWorld()
					else
						action.Active = true
						action.Text = idleActionText
						if audioFeedback then
							audioFeedback:Error()
						end
					end
				end)
			end
		end
	end
	return render
end

return JobsPanel
