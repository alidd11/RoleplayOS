--!strict
local CollectionService = game:GetService("CollectionService")

return function(CustodyService)
	function CustodyService:_cellSpawn(): BasePart?
		for _, instance in
			CollectionService:GetTagged(self.context.Configuration.Custody.CellSpawnTag)
		do
			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				return instance
			end
			if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
				local part = instance.PrimaryPart
					or instance:FindFirstChildWhichIsA("BasePart", true)
				if part then
					return part
				end
			end
		end
		return nil
	end

	function CustodyService:_placeInCell(player: Player): (boolean, string?)
		local cell = self:_cellSpawn()
		if not cell or not player.Character then
			return false, "CUSTODY_CELL_UNAVAILABLE"
		end
		player.Character:PivotTo(cell.CFrame * CFrame.new(0, 3, 0))
		return true, nil
	end

	function CustodyService:SpawnInCell(player: Player): (boolean, string?)
		if not self:HasActiveSentence(player) then
			return false, "NO_ACTIVE_CUSTODY_SENTENCE"
		end
		local cell = self:_cellSpawn()
		if not cell then
			return false, "CUSTODY_CELL_UNAVAILABLE"
		end
		local assigned, reason = self.context.Services:Get("RoleService"):Assign(player, "Civilian")
		if not assigned then
			return false, reason
		end
		player.RespawnLocation = if cell:IsA("SpawnLocation") then cell else nil
		local loaded, problem = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not loaded or not player.Character then
			self.context.Logger:Error("Custody cell spawn failed", {
				UserId = player.UserId,
				Error = tostring(problem),
			})
			return false, "CHARACTER_SPAWN_FAILED"
		end
		local placed, placeReason = self:_placeInCell(player)
		if not placed then
			return false, placeReason
		end
		local summary = self:GetSentence(player)
		player:SetAttribute("RoleplayOSCustodyReleaseAt", summary.ReleaseAt)
		player:SetAttribute("RoleplayOSCustodyRemaining", summary.RemainingSeconds)
		return true, nil
	end
end
