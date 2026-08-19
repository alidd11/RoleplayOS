--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local root = Utils.root
local humanoid = Utils.humanoid

return function(CustodyService)
	function CustodyService:_destroyEscort(state: any, target: Player?)
		for _, item in state.EscortInstances or {} do
			if item and item.Parent then
				item:Destroy()
			end
		end
		state.EscortInstances = nil
		state.EscortedByUserId = nil
		if target then
			local targetHumanoid = humanoid(target)
			if targetHumanoid then
				targetHumanoid.AutoRotate = true
				targetHumanoid.WalkSpeed = self.context.Configuration.Custody.CuffedWalkSpeed
			end
			local targetRoot = root(target)
			if targetRoot then
				pcall(targetRoot.SetNetworkOwner, targetRoot, nil)
			end
			target:SetAttribute("RoleplayOSEscorted", false)
		end
	end

	function CustodyService:_release(target: Player)
		local state = self.cuffed[target.UserId]
		if state then
			self:_destroyEscort(state, target)
		end
		self.cuffed[target.UserId] = nil
		target:SetAttribute("RoleplayOSCuffed", false)
		target:SetAttribute("RoleplayOSCuffPosition", nil)
		local targetHumanoid = humanoid(target)
		if targetHumanoid then
			targetHumanoid.WalkSpeed = self.context.Configuration.Needs.WalkSpeed
			targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			targetHumanoid.AutoRotate = true
		end
	end

	function CustodyService:_summary(targetUserId: number): any
		local state = self.cuffed[targetUserId]
		return {
			TargetUserId = targetUserId,
			Cuffed = state ~= nil,
			CuffPosition = state and state.CuffPosition or nil,
			OfficerUserId = state and state.OfficerUserId or nil,
			Escorted = state and state.EscortedByUserId ~= nil or false,
			EscortedByUserId = state and state.EscortedByUserId or nil,
			Cautioned = state and state.CautionedAt ~= nil or false,
			Searched = state and state.LastSearchAt ~= nil or false,
		}
	end

	function CustodyService:SetCuffed(
		actor: Player,
		targetUserId: number,
		mode: string?
	): (any?, string?)
		if not self:_authorised(actor) or actor.UserId == targetUserId then
			return nil, "NOT_AUTHORISED"
		end
		local equipped = false
		if actor.Character then
			for _, child in actor.Character:GetChildren() do
				if
					child:IsA("Tool")
					and (
						child.Name == "Handcuffs"
						or child:GetAttribute("RoleplayOSToolId") == "Handcuffs"
					)
				then
					equipped = true
					break
				end
			end
		end
		if not equipped then
			return nil, "HANDCUFFS_MUST_BE_EQUIPPED"
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if
			not target
			or not self:_near(
				actor,
				target,
				self.context.Configuration.Custody.MaximumInteractionDistance
			)
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		local targetHumanoid = humanoid(target)
		if not targetHumanoid or targetHumanoid.Health <= 0 then
			return nil, "TARGET_UNAVAILABLE"
		end
		local existing = self.cuffed[targetUserId]
		local requestedMode = mode or "Apply"
		if requestedMode ~= "Apply" and requestedMode ~= "Remove" then
			return nil, "INVALID_CUFF_MODE"
		end
		if requestedMode == "Remove" and existing then
			self:_release(target)
		elseif requestedMode == "Apply" and not existing then
			local newState = {
				OfficerUserId = actor.UserId,
				CuffedAt = os.time(),
				CuffPosition = "Rear",
			}
			self.cuffed[targetUserId] = newState
			target:SetAttribute("RoleplayOSCuffed", true)
			target:SetAttribute("RoleplayOSCuffPosition", "Rear")
			targetHumanoid.WalkSpeed = self.context.Configuration.Custody.CuffedWalkSpeed
			targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			-- Applying rear cuffs immediately establishes the physical escort pose:
			-- detainee in front, officer behind and facing the back of their head.
			-- The escort constraints remain server-owned and are removed by every
			-- existing release/death/reset/disconnect path.
			self:_escort(actor, target, newState)
		end
		local summary = self:_summary(targetUserId)
		self.event:FireClient(target, { Kind = "State", State = summary })
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = actor.UserId,
			Action = if summary.Cuffed then "Custody.Cuffed" else "Custody.Released",
			Target = tostring(targetUserId),
			Metadata = { Position = summary.CuffPosition },
		})
		return summary, nil
	end

	function CustodyService:_escort(actor: Player, target: Player, state: any): (any?, string?)
		if state.EscortedByUserId then
			if state.EscortedByUserId ~= actor.UserId then
				return nil, "ALREADY_ESCORTED"
			end
			self:_destroyEscort(state, target)
			return self:_summary(target.UserId), nil
		end
		for _, otherState in self.cuffed do
			if otherState.EscortedByUserId == actor.UserId then
				return nil, "OFFICER_ALREADY_ESCORTING"
			end
		end
		local actorRoot = root(actor)
		local targetRoot = root(target)
		local targetHumanoid = humanoid(target)
		if not actorRoot or not targetRoot or not targetHumanoid then
			return nil, "TARGET_UNAVAILABLE"
		end
		local officerAttachment = Instance.new("Attachment")
		officerAttachment.Name = "RoleplayOSEscortPoint"
		-- Roblox characters face local -Z. Placing the detainee on that side keeps
		-- the officer behind them, looking toward the back of their head, while both
		-- bodies share the same forward orientation.
		officerAttachment.Position =
			Vector3.new(0, 0, -self.context.Configuration.Custody.EscortDistance)
		officerAttachment.Parent = actorRoot
		local targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = "RoleplayOSEscortTarget"
		targetAttachment.Parent = targetRoot
		local position = Instance.new("AlignPosition")
		position.Name = "RoleplayOSEscortPosition"
		position.Attachment0 = targetAttachment
		position.Attachment1 = officerAttachment
		position.ApplyAtCenterOfMass = true
		position.MaxForce = self.context.Configuration.Custody.EscortMaximumForce
		position.MaxVelocity = self.context.Configuration.Custody.EscortMaximumVelocity
		position.Responsiveness = 18
		position.ReactionForceEnabled = false
		position.Parent = targetRoot
		local orientation = Instance.new("AlignOrientation")
		orientation.Name = "RoleplayOSEscortOrientation"
		orientation.Attachment0 = targetAttachment
		orientation.Attachment1 = officerAttachment
		orientation.MaxTorque = self.context.Configuration.Custody.EscortMaximumForce
		orientation.Responsiveness = 16
		orientation.ReactionTorqueEnabled = false
		orientation.Parent = targetRoot
		state.EscortedByUserId = actor.UserId
		state.EscortInstances = { officerAttachment, targetAttachment, position, orientation }
		targetHumanoid.WalkSpeed = 0
		targetHumanoid.AutoRotate = false
		target:SetAttribute("RoleplayOSEscorted", true)
		pcall(targetRoot.SetNetworkOwner, targetRoot, nil)
		return self:_summary(target.UserId), nil
	end

	function CustodyService:_search(
		actor: Player,
		target: Player,
		state: any,
		data: any
	): (any?, string?)
		local grounds, reason = self:_filter(
			actor,
			data.Grounds,
			self.context.Configuration.Custody.MaximumSearchGroundsLength
		)
		if not grounds then
			return nil, reason
		end
		-- Filtering yields. Revalidate the security boundary before recording a search.
		if
			not self:_authorised(actor)
			or not self.cuffed[target.UserId]
			or not self:_near(
				actor,
				target,
				self.context.Configuration.Custody.MaximumInteractionDistance
			)
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		local power = data.Power
		if
			type(power) ~= "string"
			or not table.find(self.context.Configuration.Custody.SearchPowers, power)
		then
			return nil, "INVALID_SEARCH_POWER"
		end
		local items = {}
		local seen = {}
		for _, container in { target:FindFirstChildOfClass("Backpack"), target.Character } do
			for _, item in if container then container:GetChildren() else {} do
				if item:IsA("Tool") and not seen[item.Name] then
					seen[item.Name] = true
					table.insert(items, item.Name)
					if #items >= self.context.Configuration.Custody.MaximumSearchItems then
						break
					end
				end
			end
		end
		table.sort(items)
		state.LastSearchAt = os.time()
		state.LastSearchByUserId = actor.UserId
		self.event:FireClient(target, {
			Kind = "SearchNotice",
			OfficerUserId = actor.UserId,
			Grounds = grounds,
			Power = power,
		})
		self.context.Services:Get("AuditService"):Record({
			ActorUserId = actor.UserId,
			Action = "Custody.Searched",
			Target = tostring(target.UserId),
			Metadata = { Power = power, ItemCount = #items },
		})
		return {
			State = self:_summary(target.UserId),
			Items = items,
			Grounds = grounds,
			Power = power,
			RecordEntitlement = true,
		},
			nil
	end

	function CustodyService:_vehicle(actor: Player, target: Player, state: any): (any?, string?)
		local targetHumanoid = humanoid(target)
		if not targetHumanoid then
			return nil, "TARGET_UNAVAILABLE"
		end
		if targetHumanoid.SeatPart then
			targetHumanoid.Sit = false
			local actorRoot = root(actor)
			local targetRoot = root(target)
			if actorRoot and targetRoot then
				targetRoot.CFrame = actorRoot.CFrame * CFrame.new(2.5, 0, 0)
			end
			state.VehicleSeat = nil
			return self:_summary(target.UserId), nil
		end
		local actorRoot = root(actor)
		local targetRoot = root(target)
		if not actorRoot or not targetRoot then
			return nil, "TARGET_UNAVAILABLE"
		end
		local nearest: Seat? = nil
		local nearestDistance = math.huge
		for _, candidate in
			CollectionService:GetTagged(self.context.Configuration.Custody.VehicleSeatTag)
		do
			if
				candidate:IsA("Seat")
				and candidate:IsDescendantOf(workspace)
				and not candidate.Occupant
			then
				local officerDistance = (candidate.Position - actorRoot.Position).Magnitude
				local targetDistance = (candidate.Position - targetRoot.Position).Magnitude
				local distance = math.max(officerDistance, targetDistance)
				if
					distance <= self.context.Configuration.Custody.MaximumVehicleDistance
					and distance < nearestDistance
				then
					nearest = candidate
					nearestDistance = distance
				end
			end
		end
		if not nearest then
			return nil, "CUSTODY_SEAT_UNAVAILABLE"
		end
		self:_destroyEscort(state, target)
		nearest:Sit(targetHumanoid)
		state.VehicleSeat = nearest
		return self:_summary(target.UserId), nil
	end

	function CustodyService:Action(
		actor: Player,
		targetUserId: number,
		action: string,
		data: any
	): (any?, string?)
		if not self:_authorised(actor) or actor.UserId == targetUserId then
			return nil, "NOT_AUTHORISED"
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		local state = self.cuffed[targetUserId]
		if not target or not state then
			return nil, "TARGET_NOT_CUFFED"
		end
		if
			not self:_near(
				actor,
				target,
				self.context.Configuration.Custody.MaximumInteractionDistance
			)
		then
			return nil, "TARGET_OUT_OF_RANGE"
		end
		local result, reason
		if action == "Status" then
			result = self:_summary(targetUserId)
		elseif action == "Escort" then
			result, reason = self:_escort(actor, target, state)
		elseif action == "Search" then
			result, reason = self:_search(actor, target, state, data)
		elseif action == "SeizeWeapons" then
			result, reason =
				self.context.Services:Get("MeleeWeaponService"):Seize(actor, targetUserId)
		elseif action == "Vehicle" then
			result, reason = self:_vehicle(actor, target, state)
		elseif action == "Caution" then
			state.CautionedAt = os.time()
			state.CautionedByUserId = actor.UserId
			local caution = self.context.Configuration.Custody.ArrestCaution
			self.event:FireClient(target, {
				Kind = "Caution",
				Text = caution,
				OfficerUserId = actor.UserId,
				SimulationNotice = self.context.Configuration.Custody.SimulationNotice,
			})
			result = { State = self:_summary(targetUserId), Caution = caution }
		elseif action == "CuffPosition" then
			local position = data.Position
			if position ~= "Front" and position ~= "Rear" then
				return nil, "INVALID_CUFF_POSITION"
			end
			state.CuffPosition = position
			target:SetAttribute("RoleplayOSCuffPosition", position)
			result = self:_summary(targetUserId)
		elseif action == "Release" then
			if state.OfficerUserId ~= actor.UserId then
				return nil, "NOT_MANAGING_OFFICER"
			end
			self:_release(target)
			result = self:_summary(targetUserId)
		else
			return nil, "INVALID_CUSTODY_ACTION"
		end
		if not result then
			return nil, reason
		end
		if action ~= "Status" and action ~= "Search" then
			self.context.Services:Get("AuditService"):Record({
				ActorUserId = actor.UserId,
				Action = "Custody." .. action,
				Target = tostring(targetUserId),
				Metadata = {},
			})
		end
		return result, nil
	end
end
