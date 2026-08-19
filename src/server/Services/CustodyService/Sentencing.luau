--!strict
local trimToMaximum = require(script.Parent.Utils).trimToMaximum

return function(CustodyService)
	function CustodyService:_sentence(player: Player): any?
		local session = self.context.Services:Get("DataService"):GetSession(player)
		return session and session.Profile.CustodySentence or nil
	end

	function CustodyService:GetSentence(player: Player): any
		local sentence = self:_sentence(player)
		local remaining = if sentence
			then math.max(0, math.floor(tonumber(sentence.RemainingSeconds) or 0))
			else 0
		return {
			Active = remaining > 0,
			-- A display estimate only. RemainingSeconds is the persisted authority so
			-- offline time never serves a sentence.
			ReleaseAt = if remaining > 0 then os.time() + remaining else 0,
			RemainingSeconds = remaining,
			TotalSeconds = if sentence
				then math.max(0, tonumber(sentence.TotalSeconds) or 0)
				else 0,
			Offences = if sentence and type(sentence.Offences) == "table"
				then table.clone(sentence.Offences)
				else {},
			SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
		}
	end

	function CustodyService:HasActiveSentence(player: Player): boolean
		return self:GetSentence(player).Active
	end

	function CustodyService:_policy(): { any }
		local policy = {}
		for code, tariff in self.context.Configuration.Custody.OffenceTariffs do
			if code ~= self.context.Configuration.Custody.DisconnectPenaltyCode then
				table.insert(policy, {
					Code = code,
					Name = tariff.Name,
					-- Optional, because the catch-all and the disconnect penalty are not
					-- offences under anything.
					Statute = tariff.Statute,
					Seconds = tariff.Seconds,
				})
			end
		end
		table.sort(policy, function(a, b)
			return a.Name < b.Name
		end)
		return policy
	end

	function CustodyService:GetPolicy(player: Player?): any
		local mode = self.context.Services:Get("ServerModeService"):Kind()
		local earlyRelease = self.context.Configuration.Custody.PublicEarlyRelease
		local configuredProducts = {}
		for _, product in earlyRelease.Products do
			if type(product.ProductId) == "number" and product.ProductId > 0 then
				table.insert(configuredProducts, table.clone(product))
			end
		end
		local session = player and self.context.Services:Get("DataService"):GetSession(player)
		local credits = if session and session.Profile.Consumables
			then math.max(
				0,
				math.floor(tonumber(session.Profile.Consumables.EarlyReleaseCredits) or 0)
			)
			else 0
		return {
			Offences = self:_policy(),
			MaximumStackedSentenceSeconds = self.context.Configuration.Custody.MaximumStackedSentenceSeconds,
			SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
			ServerKind = mode,
			-- Always true now: sitting a cuffed detainee in a tagged chair, not
			-- standing near a desk, and not limited to Whitelisted servers any more.
			BookingChairRequired = true,
			EarlyReleaseCredits = if mode == "Public" then credits else 0,
			EarlyReleaseProducts = if mode == "Public" then configuredProducts else {},
		}
	end

	function CustodyService:ApplySentence(
		target: Player,
		offenceCodes: { string },
		source: string,
		actorUserId: number?
	): (any?, string?)
		local session = self.context.Services:Get("DataService"):GetSession(target)
		if not session then
			return nil, "PROFILE_UNAVAILABLE"
		end
		local config = self.context.Configuration.Custody
		local sentence = session.Profile.CustodySentence
		local now = os.time()
		local added = 0
		local accepted = {}
		local seen = {}
		for _, code in offenceCodes do
			local tariff = if type(code) == "string" then config.OffenceTariffs[code] else nil
			if tariff and not seen[code] and #accepted < config.MaximumActiveOffences then
				seen[code] = true
				added += tariff.Seconds
				table.insert(accepted, {
					Code = code,
					Name = tariff.Name,
					Seconds = tariff.Seconds,
					AppliedAt = now,
					Source = source,
					ActorUserId = actorUserId,
				})
			end
		end
		if added <= 0 then
			return nil, "NO_VALID_OFFENCES"
		end
		local remaining = math.max(0, tonumber(sentence.RemainingSeconds) or 0)
		local finalDuration = math.min(config.MaximumStackedSentenceSeconds, remaining + added)
		sentence.RemainingSeconds = finalDuration
		sentence.ReleaseAt = 0
		sentence.TotalSeconds = math.max(0, tonumber(sentence.TotalSeconds) or 0) + added
		sentence.UpdatedAt = now
		sentence.Offences = sentence.Offences or {}
		for _, offence in accepted do
			table.insert(sentence.Offences, offence)
		end
		trimToMaximum(sentence.Offences, config.MaximumActiveOffences)
		self.context.Services:Get("DataService"):MarkDirty(target)
		local summary = self:GetSentence(target)
		target:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
		target:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = actorUserId or target.UserId,
			Action = "Custody.SentenceApplied",
			Target = tostring(target.UserId),
			Metadata = { Source = source, AddedSeconds = added, OffenceCount = #accepted },
		})
		return summary, nil
	end

	function CustodyService:AddDisconnectPenalty(player: Player): boolean
		local sentence = self:_sentence(player)
		local remaining = sentence and math.max(0, tonumber(sentence.RemainingSeconds) or 0) or 0
		if remaining <= 0 then
			return false
		end
		local config = self.context.Configuration.Custody
		local added = math.max(0, tonumber(config.DisconnectPenaltySeconds) or 30)
		sentence.RemainingSeconds =
			math.min(config.MaximumStackedSentenceSeconds, remaining + added)
		sentence.ReleaseAt = 0
		sentence.UpdatedAt = os.time()
		self.context.Services:Get("DataService"):MarkDirty(player)
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Custody.DisconnectPenalty",
			Target = tostring(player.UserId),
			Metadata = { AddedSeconds = added },
		})
		return true
	end

	function CustodyService:UseEarlyReleaseCredit(
		player: Player,
		sourceId: string?
	): (boolean, string?)
		if self.context.Services:Get("ServerModeService"):Kind() ~= "Public" then
			return false, "PUBLIC_SERVER_REQUIRED"
		end
		local dataService = self.context.Services:Get("DataService")
		local session = dataService:GetSession(player)
		if not session then
			return false, "NO_SESSION"
		end
		if not self:HasActiveSentence(player) then
			return false, "NO_ACTIVE_CUSTODY_SENTENCE"
		end
		local consumables = session.Profile.Consumables
		local credits = math.max(0, math.floor(tonumber(consumables.EarlyReleaseCredits) or 0))
		if credits <= 0 then
			return false, "NO_EARLY_RELEASE_CREDITS"
		end
		consumables.EarlyReleaseCredits = credits - 1
		local released, reason = self:_completeSentence(player, "EarlyReleaseCredit", sourceId)
		if not released then
			consumables.EarlyReleaseCredits = credits
			dataService:MarkDirty(player)
			return false, reason
		end
		dataService:MarkDirty(player)
		self.event:FireClient(player, { Kind = "EarlyRelease", Credits = credits - 1 })
		return true, nil
	end

	function CustodyService:_completeSentence(
		player: Player,
		source: string,
		receiptId: string?
	): (boolean, string?)
		local civilianSpawnId = nil
		local civilianStationId = nil
		for spawnId, definition in self.context.Configuration.Spawns do
			if definition.TeamName == "Civilian" then
				civilianSpawnId = spawnId
				civilianStationId = definition.StationId
				break
			end
		end
		if not civilianSpawnId or not civilianStationId then
			return false, "CIVILIAN_SPAWN_NOT_CONFIGURED"
		end
		if not player.Parent then
			return false, "PLAYER_LEFT"
		end
		local previousTeam = player.Team
		local previousRespawnLocation = player.RespawnLocation
		local assigned, assignReason =
			self.context.Services:Get("RoleService"):Assign(player, "Civilian")
		if not assigned then
			return false, assignReason or "CIVILIAN_ROLE_ASSIGNMENT_FAILED"
		end
		if not player.Parent then
			player.Team = previousTeam
			return false, "PLAYER_LEFT"
		end
		local spawned, spawnReason = self.context.Services:Get("SpawnService"):Spawn(player, {
			RoleId = "Civilian",
			StationId = civilianStationId,
			SpawnId = civilianSpawnId,
		})
		if not spawned then
			player.Team = previousTeam
			player.RespawnLocation = previousRespawnLocation
			return false, spawnReason or "CIVILIAN_SPAWN_FAILED"
		end
		if not player.Parent then
			return false, "PLAYER_LEFT"
		end
		local sentence = self:_sentence(player)
		if sentence then
			sentence.RemainingSeconds = 0
			sentence.ReleaseAt = 0
			sentence.UpdatedAt = os.time()
		end
		player:SetAttribute("RoleplayOSCustodyReleaseAt", nil)
		player:SetAttribute("RoleplayOSCustodyRemaining", 0)
		player.RespawnLocation = nil
		self.context.Services:Get("DataService"):MarkDirty(player)
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = player.UserId,
			Action = "Custody.SentenceCompleted",
			Target = tostring(player.UserId),
			Metadata = { Source = source, ReceiptId = receiptId },
		})
		return true, nil
	end
end
