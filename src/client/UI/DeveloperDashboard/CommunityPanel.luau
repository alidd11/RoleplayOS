--!strict

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local CommunityPanel = {}

-- "2h 14m", "8m", or "Just started" for anything under a minute. Minutes only
-- below an hour and hours-and-minutes above it, since a server's uptime is
-- read at a glance rather than measured - nobody needs to know it has been up
-- for 8,340 seconds.
local function formatUptime(startedAt: number): string
	local elapsed = math.max(0, os.time() - startedAt)
	if elapsed < 60 then
		return "Just started"
	end
	local hours = math.floor(elapsed / 3600)
	local minutes = math.floor((elapsed % 3600) / 60)
	if hours > 0 then
		return string.format("Up %dh %dm", hours, minutes)
	end
	return string.format("Up %dm", minutes)
end

function CommunityPanel.create(deps: any): () -> ()
	local context = deps.context
	local scroll = deps.scroll
	local pageTitle = deps.pageTitle
	local pageDescription = deps.pageDescription
	local sectionHeading = deps.sectionHeading
	local getMenuData = deps.getMenuData
	local COLOURS = deps.colours
	local clear = deps.clear
	local card = deps.card
	local text = deps.text
	local corner = deps.corner
	local pressable = deps.pressable
	local audioFeedback = deps.audioFeedback

	local KIND_LABEL = {
		Public = "PUBLIC SERVER",
		Whitelisted = "WHITELISTED SERVER",
		Private = "PRIVATE SERVER",
		Reserved = "RESERVED SERVER",
	}
	local KIND_BLURB = {
		Public = "Open to everyone. Teams and passes are available here.",
		Whitelisted = "Entry is restricted, and services are held by group rank.",
		Private = "Run by its owner, to their own standards.",
		Reserved = "A dedicated instance of this experience.",
	}

	-- One card layout for an official instance and a public one - the two only
	-- differ in what identifies the row and how a join request is shaped, not
	-- in what the row says or how it looks. Keeping one renderer is what stops
	-- the two lists reading as two different features sharing a page.
	local function renderInstanceRow(entry: any)
		local row = card(scroll, 132)
		local here = entry.Current == true
		local marker = Instance.new("Frame")
		marker.BackgroundColor3 = if here then COLOURS.Success else COLOURS.Accent
		marker.BorderSizePixel = 0
		marker.Position = UDim2.fromOffset(0, 16)
		marker.Size = UDim2.fromOffset(5, 100)
		marker.Parent = row
		local tierLabel = if here
			then "CURRENT SESSION"
			elseif entry.Kind == "Public" then "PUBLIC SERVER"
			else "OFFICIAL SERVER"
		local tier =
			text(row, tierLabel, 11, if here then COLOURS.Success else COLOURS.Accent, true)
		tier.Position = UDim2.fromOffset(22, 14)
		tier.Size = UDim2.new(1, -190, 0, 16)
		local hasInstance = type(entry.InstanceIndex) == "number"
		local name = text(
			row,
			tostring(entry.Name) .. (if hasInstance then " #" .. entry.InstanceIndex else ""),
			20,
			COLOURS.Text,
			true
		)
		name.Position = UDim2.fromOffset(22, 32)
		name.Size = UDim2.new(1, -190, 0, 26)
		local blurb = text(row, tostring(entry.Description or ""), 12, COLOURS.Muted)
		blurb.Position = UDim2.fromOffset(22, 60)
		blurb.Size = UDim2.new(1, -210, 0, 26)
		blurb.TextWrapped = true
		-- Live headcount and uptime, or a note that nobody has opened this
		-- server yet - the two states an instance can be in from a player's
		-- side, both worth saying plainly rather than showing blank space.
		local statsColour = if type(entry.PlayerCount) == "number"
				and type(entry.MaximumPlayers) == "number"
				and entry.PlayerCount >= entry.MaximumPlayers
			then COLOURS.Warning
			else COLOURS.Accent
		local statsText = if type(entry.PlayerCount) == "number"
				and type(entry.MaximumPlayers) == "number"
			then string.format("%d / %d online", entry.PlayerCount, entry.MaximumPlayers) .. (if type(
					entry.StartedAt
				) == "number"
				then "  ·  " .. formatUptime(entry.StartedAt)
				else "")
			else "Not yet open — the first to join starts it"
		local stats = text(row, statsText, 12, statsColour, true)
		stats.Position = UDim2.fromOffset(22, 92)
		stats.Size = UDim2.new(1, -210, 0, 18)
		local join = Instance.new("TextButton")
		join.AutoButtonColor = false
		join.AnchorPoint = Vector2.new(1, 0.5)
		join.Position = UDim2.new(1, -20, 0.5, 0)
		join.Size = UDim2.fromOffset(140, 48)
		join.BackgroundColor3 = if here then COLOURS.SurfaceRaised else COLOURS.AccentFill
		join.BorderSizePixel = 0
		join.Font = Enum.Font.GothamBold
		join.Text = if here then "YOU ARE HERE" else "JOIN"
		join.TextColor3 = if here then COLOURS.Muted else COLOURS.Text
		join.TextSize = 13
		join.Active = not here
		join.Parent = row
		corner(join, 10)
		if not here then
			pressable(join)
		end
		join.Activated:Connect(function()
			if here then
				return
			end
			join.Active = false
			join.Text = "CONNECTING…"
			local response = if entry.Kind == "Public"
				then context.Controllers.NetworkController:Request(
					"JoinPublicServer",
					{ JobId = entry.JobId }
				)
				else context.Controllers.NetworkController:Request(
					"JoinOfficialServer",
					{ ServerId = entry.Id, InstanceIndex = entry.InstanceIndex }
				)
			-- A teleport that works never comes back here, so anything
			-- arriving at this point is a refusal worth showing.
			join.Active = true
			join.Text = "JOIN"
			context.Controllers.NotificationController:Show(response.Message, "Servers")
			if not response.Success and audioFeedback then
				audioFeedback:Error()
			end
		end)
	end

	local render: () -> ()
	render = function()
		local generation = deps.nextGeneration()
		local menuData = getMenuData()
		clear(scroll)
		pageTitle.Text = "Servers"
		pageDescription.Text = "Move between official sessions without losing your place."
		local server = menuData and menuData.Server
		local kind = server and server.Kind or "Public"
		local community = server and server.Community

		-- Where you are now, first: it is what almost everybody opens this page
		-- to confirm, and it is where inviting a friend belongs, since an
		-- invite is about the server the inviter is already standing in rather
		-- than about browsing to a different one.
		sectionHeading("This server", "What you have joined, and what that allows.")
		local whereCard = card(scroll, 132)
		local accent = Instance.new("Frame")
		accent.BackgroundColor3 = if kind == "Public" then COLOURS.Accent else COLOURS.Success
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(0, 18)
		accent.Size = UDim2.fromOffset(4, 96)
		accent.Parent = whereCard
		local kindLabel = text(whereCard, KIND_LABEL[kind] or "SERVER", 11, COLOURS.Accent, true)
		kindLabel.Position = UDim2.fromOffset(20, 18)
		kindLabel.Size = UDim2.new(1, -190, 0, 18)
		local whereName = text(
			whereCard,
			(community and community.Name)
				or (server and server.AccessGroupName)
				or "Emergency Response: Portsmouth",
			19,
			COLOURS.Text,
			true
		)
		whereName.Position = UDim2.fromOffset(20, 38)
		whereName.Size = UDim2.new(1, -190, 0, 26)
		local whereBlurb = text(whereCard, KIND_BLURB[kind] or "", 12, COLOURS.Muted)
		whereBlurb.Position = UDim2.fromOffset(20, 64)
		whereBlurb.Size = UDim2.new(1, -210, 0, 38)
		whereBlurb.TextWrapped = true
		local invite = Instance.new("TextButton")
		invite.AutoButtonColor = false
		invite.AnchorPoint = Vector2.new(1, 0.5)
		invite.Position = UDim2.new(1, -20, 0.5, 0)
		invite.Size = UDim2.fromOffset(140, 48)
		invite.BackgroundColor3 = COLOURS.AccentFill
		invite.BorderSizePixel = 0
		invite.Font = Enum.Font.GothamBold
		invite.Text = "INVITE"
		invite.TextColor3 = COLOURS.Text
		invite.TextSize = 13
		invite.Parent = whereCard
		corner(invite, 10)
		pressable(invite)
		invite.Activated:Connect(function()
			local localPlayer = Players.LocalPlayer
			local canOk, canInvite =
				pcall(SocialService.CanSendGameInviteAsync, SocialService, localPlayer)
			if not canOk or not canInvite then
				context.Controllers.NotificationController:Show(
					"Invites are not available on this device right now.",
					"Invite friends"
				)
				if audioFeedback then
					audioFeedback:Error()
				end
				return
			end
			local promptOk, promptError =
				pcall(SocialService.PromptGameInvite, SocialService, localPlayer)
			if not promptOk then
				context.Controllers.NotificationController:Show(
					"The invite screen could not be opened.",
					"Invite friends"
				)
				warn("[RoleplayOS] PromptGameInvite failed: " .. tostring(promptError))
			end
		end)

		-- The servers the team runs, then whatever public instances are
		-- currently reporting in - one request for both, since a player
		-- comparing "should I go official or stay public" wants both answers
		-- on screen together rather than fetched one at a time.
		local officialResponse =
			context.Controllers.NetworkController:Request("GetOfficialServers", {})
		-- Another page was opened while that was in flight, so this one is stale
		-- and its container now belongs to whatever replaced it.
		if generation ~= deps.currentGeneration() then
			return
		end
		local data = if officialResponse.Success and type(officialResponse.Data) == "table"
			then officialResponse.Data
			else nil
		local officialRows = if data and type(data.Servers) == "table" then data.Servers else nil
		local publicRows = if data and type(data.PublicServers) == "table"
			then data.PublicServers
			else nil

		if type(officialRows) == "table" and #officialRows > 0 then
			sectionHeading(
				"Official servers",
				"Choose the environment that matches how you want to play."
			)
			for _, entry in officialRows do
				renderInstanceRow(entry)
			end
		end

		if type(publicRows) == "table" and #publicRows > 0 then
			sectionHeading(
				"Public servers",
				"Other public sessions currently running, busiest first."
			)
			for _, entry in publicRows do
				renderInstanceRow({
					Kind = "Public",
					JobId = entry.JobId,
					Name = "Emergency Response: Portsmouth",
					Description = KIND_BLURB.Public,
					Current = entry.Current,
					PlayerCount = entry.PlayerCount,
					MaximumPlayers = entry.MaximumPlayers,
					StartedAt = entry.StartedAt,
				})
			end
		end
	end
	return render
end

return CommunityPanel
