--!strict

-- Asynchronous Discord delivery for road-safety records. A failed webhook must
-- never delay, cancel or roll back an in-game fine.

local HttpService = game:GetService("HttpService")

local DiscordFineService = { queue = {}, running = false, warned = false }

function DiscordFineService:Init(context: any)
	self.context = context
	-- Walked rather than indexed straight through. Integrations is not in the
	-- validator's required list, so a deployment override that drops or misspells
	-- it would throw here, and a service that throws in Init is stepped over
	-- silently. Reporting would then be off with nothing saying so, which is the
	-- one outcome worse than reporting being off.
	local integrations = context.Configuration.Integrations
	local discord = integrations and integrations.Discord
	self.settings = discord and discord.SpeedingFines
	if type(self.settings) ~= "table" then
		self.settings = { Enabled = false }
		context.Logger:Warning(
			"Discord speeding-fine settings are missing; reporting is off",
			{ Section = "Integrations.Discord.SpeedingFines" }
		)
	end
end

function DiscordFineService:_isWhitelistedPoliceOfficer(officer: any): boolean
	if self.context.Services:Get("ServerModeService"):Kind() ~= "Whitelisted" then
		return false
	end
	if typeof(officer) ~= "Instance" or not officer:IsA("Player") then
		return false
	end
	local duty = self.context.Services:Get("DutyService"):Get(officer)
	if not duty or duty.DepartmentId ~= "Police" then
		return false
	end
	local membership = self.context.Services:Get("GroupService"):GetMembership(officer, "Police")
	local rank = tonumber(membership.HighestRank) or 0
	local minimum = tonumber(membership.MinimumRank) or 1
	return membership.IsMember == true and rank >= minimum
end

function DiscordFineService:Enqueue(record: any, officer: any): (boolean, string?)
	if self.settings.Enabled ~= true then
		return false, "DISCORD_FINE_LOG_DISABLED"
	end
	if not self:_isWhitelistedPoliceOfficer(officer) then
		return false, "DISCORD_FINE_LOG_NOT_WHITELISTED_POLICE"
	end
	if #self.queue >= self.settings.MaximumQueue then
		table.remove(self.queue, 1)
		self.context.Logger:Warning("Discord fine queue dropped its oldest report", {
			MaximumQueue = self.settings.MaximumQueue,
		})
	end
	table.insert(self.queue, table.clone(record))
	return true, nil
end

function DiscordFineService:_payload(record: any): string
	local officer = record.IssuingOfficer or "Automated camera"
	local rank = record.IssuingOfficerRank or "Automated camera"
	-- Coerced rather than trusted. Each of these reaches string.format with a
	-- numeric specifier, and a record missing one would raise rather than produce
	-- a report with a zero in it.
	local recordedMph = tonumber(record.RecordedMph) or 0
	local limitMph = tonumber(record.LimitMph) or 0
	local fine = tonumber(record.Fine) or 0
	local points = tonumber(record.Points) or 0
	return HttpService:JSONEncode({
		username = "RoleplayOS Road Safety",
		allowed_mentions = { parse = {} },
		embeds = {
			{
				title = "Speeding fine issued",
				color = 3447003,
				description = self.settings.DepartmentName,
				fields = {
					{ name = "Driver", value = tostring(record.Driver), inline = true },
					{ name = "Registration", value = tostring(record.Registration), inline = true },
					{ name = "Location", value = tostring(record.Location), inline = false },
					{
						name = "Recorded speed",
						value = string.format("%d mph", recordedMph),
						inline = true,
					},
					{
						name = "Road limit",
						value = string.format("%d mph", limitMph),
						inline = true,
					},
					{
						name = "Penalty",
						value = string.format("£%d · %d points", fine, points),
						inline = true,
					},
					{ name = "Officer", value = tostring(officer), inline = true },
					{ name = "Officer rank", value = tostring(rank), inline = true },
					{ name = "Source", value = tostring(record.Type), inline = true },
				},
				footer = { text = "Fine ID · " .. tostring(record.FineId) },
				timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", record.IssuedAt),
			},
		},
	})
end

function DiscordFineService:_send(record: any)
	local secretOk, webhook = pcall(HttpService.GetSecret, HttpService, self.settings.SecretName)
	if not secretOk then
		if not self.warned then
			self.warned = true
			self.context.Logger:Warning("Discord speeding-fine webhook secret is unavailable", {
				SecretName = self.settings.SecretName,
				ChannelId = self.settings.ChannelId,
			})
		end
		return
	end
	local requestOk, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = webhook,
		Method = "POST",
		Headers = { ["content-type"] = "application/json" },
		Body = self:_payload(record),
		Timeout = 8,
	})
	if not requestOk or not response.Success then
		self.context.Logger:Warning("Discord speeding-fine report failed", {
			FineId = record.FineId,
			StatusCode = if requestOk then response.StatusCode else 0,
			Error = if requestOk then response.StatusMessage else tostring(response),
		})
	end
end

function DiscordFineService:Start()
	if self.settings.Enabled ~= true then
		return
	end
	self.running = true
	task.spawn(function()
		while self.running do
			local record = table.remove(self.queue, 1)
			if record then
				-- Guarded, because _payload formats numbers straight out of the
				-- record and string.format raises on a nil. Unguarded, one
				-- malformed fine would kill this thread, and every later report
				-- would queue behind a loop that had already stopped with nothing
				-- logged to say so.
				local ok, problem = pcall(function()
					self:_send(record)
				end)
				if not ok then
					self.context.Logger:Warning("Discord speeding-fine report was dropped", {
						FineId = record.FineId,
						Error = tostring(problem),
					})
				end
			end
			task.wait(if record then self.settings.MinimumIntervalSeconds else 1)
		end
	end)
end

function DiscordFineService:Destroy()
	self.running = false
	table.clear(self.queue)
end

return DiscordFineService
