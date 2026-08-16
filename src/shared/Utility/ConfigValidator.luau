--!strict

local ConfigValidator = {}

function ConfigValidator.validate(config: any): (boolean, { string })
	local errors = {}
	for _, section in
		{
			"Framework",
			"ContentQuality",
			"Performance",
			"EmergencyLighting",
			"Health",
			"ExperienceAccess",
			"Characters",
			"Economy",
			"Progression",
			"Departments",
			"Roles",
			"Jobs",
			"Vehicles",
			"Tools",
			"Uniforms",
			"UniformChangingRooms",
			"Divisions",
			"Properties",
			"Furniture",
			"Network",
			"Spawns",
			"Teams",
			"GroupLinks",
		}
	do
		if type(config[section]) ~= "table" then
			table.insert(errors, "Missing configuration section: " .. section)
		end
	end
	local quality = config.ContentQuality or {}
	if
		type(quality.RequireCertification) ~= "boolean"
		or type(quality.CertificationVersion) ~= "number"
		or quality.CertificationVersion < 1
		or type(quality.WorldAssetTag) ~= "string"
		or quality.WorldAssetTag == ""
		or type(quality.WorldAssetRootName) ~= "string"
		or quality.WorldAssetRootName == ""
		or type(quality.QuarantineRootName) ~= "string"
		or quality.QuarantineRootName == ""
	then
		table.insert(errors, "Invalid content certification configuration")
	end
	if quality.CertifiedAssets ~= nil then
		if type(quality.CertifiedAssets) ~= "table" then
			table.insert(errors, "ContentQuality.CertifiedAssets must be a table")
		else
			for assetId, certification in quality.CertifiedAssets do
				if
					type(assetId) ~= "string"
					or assetId == ""
					or type(certification) ~= "table"
					or certification.Certified ~= true
					or certification.ReviewVersion ~= quality.CertificationVersion
					or type(certification.Source) ~= "string"
					or #certification.Source < 3
					or type(certification.RealWorldReference) ~= "string"
					or #certification.RealWorldReference < 3
					or type(certification.ReviewedBy) ~= "string"
					or #certification.ReviewedBy < 3
				then
					table.insert(
						errors,
						"Invalid content certification manifest entry: " .. tostring(assetId)
					)
				end
			end
		end
	end
	local requiredKinds = {}
	if
		type(quality.RequiredWorldAssetKinds) ~= "table"
		or #quality.RequiredWorldAssetKinds == 0
	then
		table.insert(errors, "World asset kinds are required")
	else
		for _, kind in quality.RequiredWorldAssetKinds do
			if type(kind) ~= "string" or kind == "" or requiredKinds[kind] then
				table.insert(errors, "Invalid or duplicate world asset kind")
			else
				requiredKinds[kind] = true
			end
		end
	end
	for _, field in
		{
			"MaximumVehicleParts",
			"MaximumToolParts",
			"MaximumWorldAssetParts",
			"MaximumVehicleDescendants",
			"MaximumToolDescendants",
			"MaximumWorldAssetDescendants",
			"MinimumVehicleExtentStuds",
			"MaximumVehicleExtentStuds",
			"MinimumWorldAssetExtentStuds",
			"MaximumWorldAssetExtentStuds",
		}
	do
		if type(quality[field]) ~= "number" or quality[field] <= 0 then
			table.insert(errors, "Invalid content quality field: " .. field)
		end
	end
	if
		type(quality.MinimumVehicleExtentStuds) == "number"
		and type(quality.MaximumVehicleExtentStuds) == "number"
		and quality.MinimumVehicleExtentStuds >= quality.MaximumVehicleExtentStuds
	then
		table.insert(errors, "Invalid vehicle content extent range")
	end
	if
		type(quality.MinimumWorldAssetExtentStuds) == "number"
		and type(quality.MaximumWorldAssetExtentStuds) == "number"
		and quality.MinimumWorldAssetExtentStuds >= quality.MaximumWorldAssetExtentStuds
	then
		table.insert(errors, "Invalid world asset extent range")
	end
	for sectionName, section in config do
		if
			type(section) == "table"
			and sectionName ~= "Framework"
			and sectionName ~= "Characters"
			and sectionName ~= "Economy"
			and sectionName ~= "Network"
			and sectionName ~= "Dispatch"
			and sectionName ~= "MDT"
		then
			local ids = {}
			for key, definition in section do
				if type(definition) == "table" and definition.Id then
					if ids[definition.Id] then
						table.insert(
							errors,
							string.format("Duplicate ID %s in %s", definition.Id, sectionName)
						)
					end
					ids[definition.Id] = true
					if definition.Id ~= key then
						table.insert(
							errors,
							string.format(
								"Key %s does not match ID %s in %s",
								key,
								definition.Id,
								sectionName
							)
						)
					end
				end
			end
		end
	end
	for id, vehicle in config.Vehicles or {} do
		if type(vehicle.Price) ~= "number" or vehicle.Price < 0 then
			table.insert(errors, "Invalid vehicle price: " .. id)
		end
		if type(vehicle.Name) ~= "string" or vehicle.Name == "" then
			table.insert(errors, "Invalid vehicle name: " .. id)
		end
		if
			type(vehicle.AssetPath) ~= "table"
			or #vehicle.AssetPath < 2
			or table.find(vehicle.AssetPath, "") ~= nil
		then
			table.insert(errors, "Invalid vehicle asset path: " .. id)
		end
		if type(vehicle.Colours) ~= "table" or #vehicle.Colours == 0 then
			table.insert(errors, "Vehicle has no colours: " .. id)
		end
		if vehicle.Category ~= "Civilian" and vehicle.Category ~= "Service" then
			table.insert(errors, "Invalid vehicle category: " .. id)
		elseif vehicle.Category == "Civilian" then
			if vehicle.DepartmentId ~= nil or vehicle.DivisionId ~= nil then
				table.insert(errors, "Civilian vehicle has a service assignment: " .. id)
			end
		elseif type(vehicle.DepartmentId) ~= "string" or vehicle.DepartmentId == "" then
			table.insert(errors, "Service vehicle has no department: " .. id)
		end
		if vehicle.DepartmentId and not config.Departments[vehicle.DepartmentId] then
			table.insert(errors, "Unknown vehicle department: " .. id)
		end
		if vehicle.DivisionId and not config.Divisions[vehicle.DivisionId] then
			table.insert(errors, "Unknown vehicle division: " .. id)
		elseif
			vehicle.DivisionId
			and config.Divisions[vehicle.DivisionId].DepartmentId ~= vehicle.DepartmentId
		then
			table.insert(errors, "Vehicle division does not belong to its department: " .. id)
		end
	end
	local vehicleSpawners = config.VehicleSpawners or {}
	if
		type(vehicleSpawners.FolderName) ~= "string"
		or vehicleSpawners.FolderName == ""
		or type(vehicleSpawners.MaximumInteractionDistance) ~= "number"
		or vehicleSpawners.MaximumInteractionDistance < 4
		or type(vehicleSpawners.CooldownSeconds) ~= "number"
		or vehicleSpawners.CooldownSeconds < 0
		or typeof(vehicleSpawners.SpawnClearance) ~= "Vector3"
		or vehicleSpawners.SpawnClearance.X <= 0
		or vehicleSpawners.SpawnClearance.Y <= 0
		or vehicleSpawners.SpawnClearance.Z <= 0
	then
		table.insert(errors, "Invalid vehicle spawner configuration")
	end
	for dealershipId, dealership in config.Dealerships or {} do
		local seen = {}
		for _, vehicleId in dealership.VehicleIds or {} do
			local vehicle = config.Vehicles[vehicleId]
			if seen[vehicleId] or not vehicle or vehicle.Category ~= "Civilian" then
				table.insert(
					errors,
					"Invalid or duplicate civilian vehicle "
						.. tostring(vehicleId)
						.. " in dealership "
						.. tostring(dealershipId)
				)
			else
				seen[vehicleId] = true
			end
		end
	end
	-- Application forms, checked against what ApplicationService actually reads.
	--
	-- Each of these is a crash rather than a misconfiguration at runtime: a form
	-- with no Questions iterates nil, a missing CooldownSeconds is subtracted
	-- from a timestamp once a previous application exists, and a Choice question
	-- with no Options is handed to table.find as nil. Duplicate question ids do
	-- not throw, but the later answer silently replaces the earlier one.
	for formId, form in config.Applications or {} do
		local label = " in application " .. tostring(formId)
		if type(form.CooldownSeconds) ~= "number" or form.CooldownSeconds < 0 then
			table.insert(errors, "Missing or negative CooldownSeconds" .. label)
		end
		if type(form.Questions) ~= "table" or #form.Questions == 0 then
			table.insert(errors, "No questions defined" .. label)
		else
			local seenQuestions = {}
			for _, question in form.Questions do
				local questionId = question.Id
				if type(questionId) ~= "string" or questionId == "" then
					table.insert(errors, "Question with no id" .. label)
				elseif seenQuestions[questionId] then
					table.insert(errors, "Duplicate question " .. questionId .. label)
				else
					seenQuestions[questionId] = true
				end
				if question.Type ~= "Text" and question.Type ~= "Choice" then
					table.insert(
						errors,
						"Question " .. tostring(questionId) .. " has an unknown type" .. label
					)
				end
				if
					question.Type == "Choice"
					and (type(question.Options) ~= "table" or #question.Options < 2)
				then
					table.insert(
						errors,
						"Choice question " .. tostring(questionId) .. " needs two options" .. label
					)
				end
				if
					question.MaximumLength ~= nil
					and (type(question.MaximumLength) ~= "number" or question.MaximumLength < 1)
				then
					table.insert(
						errors,
						"Question " .. tostring(questionId) .. " has a bad length limit" .. label
					)
				end
			end
		end
	end
	local network = config.Network or {}
	if
		type(network.MaximumPayloadBytes) ~= "number"
		or network.MaximumPayloadBytes < 256
		or type(network.MaximumDepth) ~= "number"
		or network.MaximumDepth < 1
		or type(network.MaximumNodes) ~= "number"
		or network.MaximumNodes < 1
		or type(network.MaximumStringBytes) ~= "number"
		or network.MaximumStringBytes < 1
		or network.MaximumStringBytes > network.MaximumPayloadBytes
		or type(network.MaximumConcurrentRequests) ~= "number"
		or network.MaximumConcurrentRequests < 1
		or type(network.GlobalCapacity) ~= "number"
		or network.GlobalCapacity < 1
		or type(network.GlobalRefillPerSecond) ~= "number"
		or network.GlobalRefillPerSecond <= 0
	then
		table.insert(errors, "Invalid global network safety configuration")
	end
	if type(network.Endpoints) ~= "table" then
		table.insert(errors, "Network endpoint rate limits are required")
	else
		for name, limits in network.Endpoints do
			if
				type(name) ~= "string"
				or type(limits) ~= "table"
				or type(limits.Capacity) ~= "number"
				or limits.Capacity < 1
				or type(limits.RefillPerSecond) ~= "number"
				or limits.RefillPerSecond <= 0
			then
				table.insert(errors, "Invalid endpoint rate limit: " .. tostring(name))
			end
		end
	end
	if
		type(config.MDT) ~= "table"
		or type(config.MDT.MaximumIndexBucketEntries) ~= "number"
		or config.MDT.MaximumIndexBucketEntries < config.MDT.PageSize
		or type(config.MDT.RecordCacheSeconds) ~= "number"
		or config.MDT.RecordCacheSeconds < 0
		or type(config.MDT.IndexWriteSpacingSeconds) ~= "number"
		or config.MDT.IndexWriteSpacingSeconds < 0.05
		or type(config.MDT.MaximumWarrantReasonLength) ~= "number"
		or config.MDT.MaximumWarrantReasonLength < 20
		or type(config.MDT.MaximumWarrantDurationDays) ~= "number"
		or config.MDT.MaximumWarrantDurationDays < 1
		or type(config.MDT.MaximumIncidentIndexEntries) ~= "number"
		or config.MDT.MaximumIncidentIndexEntries < config.MDT.PageSize
	then
		table.insert(errors, "Invalid MDT index configuration")
	end
	for loadoutId, loadout in config.Loadouts or {} do
		for _, toolId in loadout.ToolIds or {} do
			if not config.Tools[toolId] then
				table.insert(errors, "Unknown tool " .. toolId .. " in loadout " .. loadoutId)
			end
		end
	end
	local changingRooms = config.UniformChangingRooms or {}
	if
		type(changingRooms.FolderName) ~= "string"
		or changingRooms.FolderName == ""
		or type(changingRooms.PromptHoldDuration) ~= "number"
		or changingRooms.PromptHoldDuration < 0
		or type(changingRooms.MaximumInteractionDistance) ~= "number"
		or changingRooms.MaximumInteractionDistance < 4
		or type(changingRooms.Defaults) ~= "table"
	then
		table.insert(errors, "Invalid uniform changing-room configuration")
	else
		local roomIds = {}
		for _, room in changingRooms.Defaults do
			if
				type(room.ChangingRoomId) ~= "string"
				or room.ChangingRoomId == ""
				or roomIds[room.ChangingRoomId]
				or not config.Spawns[room.SpawnId]
				or not config.Departments[room.DepartmentId]
				or not config.Uniforms[room.UniformId]
			then
				table.insert(errors, "Invalid or duplicate uniform changing room")
			else
				roomIds[room.ChangingRoomId] = true
			end
		end
	end
	local progression = config.Progression or {}
	if
		type(progression.BaseXP) ~= "number"
		or progression.BaseXP < 1
		or type(progression.GrowthFactor) ~= "number"
		or progression.GrowthFactor < 1
		or type(progression.MaximumLevel) ~= "number"
		or progression.MaximumLevel < 1
		or progression.MaximumLevel > 1000
		or type(progression.MaximumGrant) ~= "number"
		or progression.MaximumGrant < 1
	then
		table.insert(errors, "Invalid progression configuration")
	end
	for spawnId, spawn in config.Spawns or {} do
		local station = config.Stations[spawn.StationId]
		if spawn.Id ~= spawnId or not station or not table.find(station.SpawnIds, spawnId) then
			table.insert(errors, "Invalid spawn definition: " .. spawnId)
		end
		for _, roleId in spawn.RoleIds or {} do
			local role = config.Roles[roleId]
			if not role then
				table.insert(errors, "Unknown role " .. roleId .. " in spawn " .. spawnId)
			elseif role.TeamName ~= spawn.TeamName then
				table.insert(errors, "Role team mismatch in spawn " .. spawnId)
			end
		end
		if not config.Teams[spawn.TeamName] then
			table.insert(errors, "Unknown team in spawn " .. spawnId)
		end
	end
	for linkId, link in config.GroupLinks or {} do
		if link.Id ~= linkId or type(link.GroupId) ~= "number" or link.GroupId < 0 then
			table.insert(errors, "Invalid Roblox group link: " .. linkId)
		end
		if type(link.MinimumRank) ~= "number" or link.MinimumRank < 1 or link.MinimumRank > 255 then
			table.insert(errors, "Invalid minimum Roblox group rank: " .. linkId)
		end
	end
	local experienceAccess = config.ExperienceAccess
	if
		type(experienceAccess) ~= "table"
		or type(experienceAccess.Enabled) ~= "boolean"
		or not config.GroupLinks[experienceAccess.RequiredGroupLinkId]
		or type(experienceAccess.KickMessage) ~= "string"
		or #experienceAccess.KickMessage < 10
	then
		table.insert(errors, "Invalid experience access configuration")
	end
	local function validateAccessRule(rule: any, ownerId: string)
		if rule.AccessType == "Group" and not config.GroupLinks[rule.GroupLinkId] then
			table.insert(errors, "Unknown Roblox group link in " .. ownerId)
		end
		for _, child in rule.Rules or {} do
			validateAccessRule(child, ownerId)
		end
	end
	for roleId, role in config.Roles or {} do
		validateAccessRule(role.Access, "role " .. roleId)
		if not config.Teams[role.TeamName] then
			table.insert(errors, "Unknown team in role " .. roleId)
		end
		if role.DepartmentId and not config.Departments[role.DepartmentId] then
			table.insert(errors, "Unknown department in role " .. roleId)
		end
		if role.DivisionId then
			local division = config.Divisions[role.DivisionId]
			if not division or division.DepartmentId ~= role.DepartmentId then
				table.insert(errors, "Invalid division in role " .. roleId)
			end
		end
		if role.LoadoutId and not config.Loadouts[role.LoadoutId] then
			table.insert(errors, "Unknown loadout in role " .. roleId)
		end
		if role.UniformId and not config.Uniforms[role.UniformId] then
			table.insert(errors, "Unknown uniform in role " .. roleId)
		end
	end
	for departmentId, department in config.Departments or {} do
		for _, roleId in department.RoleIds or {} do
			local role = config.Roles[roleId]
			if not role or role.DepartmentId ~= departmentId then
				table.insert(errors, "Invalid role " .. roleId .. " in department " .. departmentId)
			end
		end
	end
	for _, listName in { "CallPriorities", "IncidentTypes", "CallStatuses" } do
		local seen = {}
		local values = config.Dispatch and config.Dispatch[listName]
		if type(values) ~= "table" or #values == 0 then
			table.insert(errors, "Invalid dispatch list: " .. listName)
		else
			for _, value in values do
				if type(value) ~= "string" or value == "" or seen[value] then
					table.insert(errors, "Invalid or duplicate dispatch value in " .. listName)
				end
				seen[value] = true
			end
		end
	end
	local robbery = config.BankRobbery
	if
		type(robbery) ~= "table"
		or type(robbery.Tag) ~= "string"
		or robbery.Tag == ""
		or type(robbery.ActivationDistance) ~= "number"
		or robbery.ActivationDistance < 4
		or type(robbery.CompletionDistance) ~= "number"
		or robbery.CompletionDistance < robbery.ActivationDistance
		or type(robbery.RobberyDurationSeconds) ~= "number"
		or robbery.RobberyDurationSeconds < 10
		or type(robbery.CooldownSeconds) ~= "number"
		or robbery.CooldownSeconds < robbery.RobberyDurationSeconds
		or type(robbery.FailedCooldownSeconds) ~= "number"
		or robbery.FailedCooldownSeconds < 5
		or type(robbery.MinimumReward) ~= "number"
		or robbery.MinimumReward < 1
		or type(robbery.MaximumReward) ~= "number"
		or robbery.MaximumReward < robbery.MinimumReward
	then
		table.insert(errors, "Invalid bank robbery configuration")
	end
	local drops = config.MoneyDrops
	if
		type(drops) ~= "table"
		or type(drops.Enabled) ~= "boolean"
		or type(drops.MinimumAmount) ~= "number"
		or drops.MinimumAmount < 1
		or drops.MinimumAmount % 1 ~= 0
		or type(drops.MaximumAmount) ~= "number"
		or drops.MaximumAmount < drops.MinimumAmount
		or drops.MaximumAmount % 1 ~= 0
		or type(drops.MaximumActivePerPlayer) ~= "number"
		or drops.MaximumActivePerPlayer < 1
		or type(drops.MaximumActiveGlobal) ~= "number"
		or drops.MaximumActiveGlobal < drops.MaximumActivePerPlayer
		or type(drops.DropAheadStuds) ~= "number"
		or drops.DropAheadStuds < 0
		or type(drops.PickupDistance) ~= "number"
		or drops.PickupDistance < 4
		or type(drops.PickupHoldSeconds) ~= "number"
		or drops.PickupHoldSeconds < 0
		or type(drops.LifetimeSeconds) ~= "number"
		or drops.LifetimeSeconds < 10
	then
		table.insert(errors, "Invalid money drop configuration")
	end
	for templateId, template in config.Communities and config.Communities.Templates or {} do
		if template.Id ~= templateId or not template.Roles[template.DefaultMemberRoleId] then
			table.insert(errors, "Invalid community template: " .. templateId)
		end
		local priorities = {}
		for roleId, role in template.Roles do
			if role.Id ~= roleId or priorities[role.Priority] then
				table.insert(errors, "Invalid or duplicate community role priority: " .. roleId)
			end
			priorities[role.Priority] = true
		end
	end
	for roleId, rank in config.Communities and config.Communities.GroupRoleRanks or {} do
		if
			not config.Communities.Templates[config.Communities.DefaultTemplateId].Roles[roleId]
			or type(rank) ~= "number"
			or rank < 1
			or rank > 255
		then
			table.insert(errors, "Invalid community group role rank: " .. roleId)
		end
	end
	return #errors == 0, errors
end

return table.freeze(ConfigValidator)
