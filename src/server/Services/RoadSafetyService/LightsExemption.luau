--!strict
local RolePermissions =
	require(game:GetService("ReplicatedStorage").RoleplayOS.Shared.RolePermissions)

return function(RoadSafetyService)
	-- Whether a value read from an attribute or a value object means "lights on".
	--
	-- Lighting systems express this differently: a boolean, a number of the active
	-- stage, or the name of a mode. Anything present and not explicitly off counts,
	-- because a missing signal is far more likely than a system that reports being
	-- on by saying nothing.
	function RoadSafetyService:_readsAsOn(value: any): boolean
		if value == nil then
			return false
		end
		if type(value) == "boolean" then
			return value
		end
		if type(value) == "number" then
			return value > 0
		end
		if type(value) ~= "string" then
			return false
		end
		local lowered = string.lower(value)
		for _, off in self.context.Configuration.EmergencyLights.OffValues do
			if lowered == off then
				return false
			end
		end
		return lowered ~= ""
	end

	-- Whether this vehicle's blue lights are on.
	--
	-- Every configured name is tried as an attribute on the model and on the seat,
	-- then as a value object inside each configured folder. Nothing here assumes a
	-- particular lighting system, because there is no reason to expect one.
	-- Whether a name looks like it belongs to the blue lights.
	--
	-- Exclusions are checked first, so a headlight, a brake light or an interior
	-- lamp is never mistaken for a response. Without that, a marked car simply
	-- driving at night would be exempt from every camera in the map.
	function RoadSafetyService:_nameLooksLikeLights(name: string): boolean
		local settings = self.context.Configuration.EmergencyLights
		local lowered = string.lower(name)
		for _, excluded in settings.ExcludedPatterns do
			if string.find(lowered, excluded, 1, true) then
				return false
			end
		end
		for _, pattern in settings.NamePatterns do
			if string.find(lowered, pattern, 1, true) then
				return true
			end
		end
		return false
	end

	-- Reports the first thing that read as on, once per name.
	--
	-- The exact attribute a lighting system sets cannot be known from here, so this
	-- says what it actually matched. That turns "the exemption is not firing" from
	-- guesswork into a line in the log naming the thing to put in AttributeNames.
	function RoadSafetyService:_noteMatch(where: string, name: string)
		self.noted = self.noted or {}
		if self.noted[name] then
			return
		end
		self.noted[name] = true
		self.context.Logger:Info("Emergency lights read from", { Source = where, Name = name })
	end

	function RoadSafetyService:AreLightsOn(vehicle: Instance?): boolean
		if not vehicle then
			return false
		end
		-- The authoritative answer first.
		--
		-- Where this framework owns the lighting it set this attribute itself, so
		-- there is nothing to infer and no fork to be wrong about. Everything below
		-- is the fallback for a vehicle still running a third party kit, and it is
		-- guesswork: it exists because two different kits in this place disagree
		-- about where the state lives, and guessing wrong costs an emergency driver
		-- a fine.
		local owned = self.context.Configuration.EmergencyLighting
		if owned and owned.Enabled then
			local state = vehicle:GetAttribute(owned.StateAttribute)
			if type(state) == "boolean" then
				-- A response, not merely something lit.
				--
				-- The state attribute became true for any of twelve circuits once the
				-- full panel arrived, so an officer parked at a scene with the rear
				-- floods on, no 360 and no siren, was exempt from every camera in the
				-- city until they pressed reset. The exemption is for a vehicle
				-- responding to an incident, which is what a stage above zero means;
				-- scene lighting is the opposite of a response.
				local stage = vehicle:GetAttribute(owned.StageAttribute)
				return state and type(stage) == "number" and stage > 0
			end
		end

		local settings = self.context.Configuration.EmergencyLights
		local roots: { Instance } = { vehicle }
		local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			table.insert(roots, seat)
		end

		for _, root in roots do
			for _, name in settings.AttributeNames do
				if self:_readsAsOn(root:GetAttribute(name)) then
					self:_noteMatch("attribute", name)
					return true
				end
			end
			-- Then anything whose name looks like it belongs to the blue lights, so a
			-- system nobody here has seen still works without being configured first.
			for name, value in root:GetAttributes() do
				if self:_nameLooksLikeLights(name) and self:_readsAsOn(value) then
					self:_noteMatch("attribute", name)
					return true
				end
			end
		end

		for _, folderName in settings.ValueFolderNames do
			local folder = vehicle:FindFirstChild(folderName, true)
			if folder then
				for _, name in settings.AttributeNames do
					if self:_readsAsOn(folder:GetAttribute(name)) then
						return true
					end
					local item = folder:FindFirstChild(name)
					if item and item:IsA("ValueBase") and self:_readsAsOn((item :: any).Value) then
						self:_noteMatch("value", name)
						return true
					end
				end
				for _, item in folder:GetChildren() do
					if
						item:IsA("ValueBase")
						and self:_nameLooksLikeLights(item.Name)
						and self:_readsAsOn((item :: any).Value)
					then
						self:_noteMatch("value", item.Name)
						return true
					end
				end
			end
		end

		-- Last, any value anywhere in the vehicle whose name looks right. Lighting
		-- systems put these wherever they like, and a vehicle is small enough that
		-- looking through it costs nothing next to being wrong.
		for _, item in vehicle:GetDescendants() do
			if
				item:IsA("ValueBase")
				and self:_nameLooksLikeLights(item.Name)
				and self:_readsAsOn((item :: any).Value)
			then
				self:_noteMatch("descendant", item.Name)
				return true
			end
		end
		return false
	end

	-- Whether this driver, in this vehicle, right now, should be let off.
	function RoadSafetyService:IsExempt(player: Player, vehicle: Instance?): boolean
		local settings = self.context.Configuration.RoadSafety
		if settings.ExemptOnEmergencyLights ~= true then
			return false
		end
		if not self:AreLightsOn(vehicle) then
			return false
		end
		if settings.ExemptRequiresDuty ~= true then
			return true
		end
		-- Mirror EmergencyLightsService's authorisation exactly. A duty record alone
		-- is not enough: civilian jobs, support roles, and roles such as PCSO may be
		-- on duty while still not being authorised to run an emergency response.
		local duty = self.context.Services:Get("DutyService"):Get(player)
		local lighting = self.context.Configuration.EmergencyLighting
		return duty ~= nil
			and type(duty.DepartmentId) == "string"
			and lighting.Departments[duty.DepartmentId] ~= nil
			and RolePermissions.has(self.context.Configuration, duty, "EmergencyLights")
	end
end
