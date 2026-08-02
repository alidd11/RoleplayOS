--!strict

local ConfigValidator = {}

function ConfigValidator.validate(config: any): (boolean, { string })
	local errors = {}
	for _, section in
		{
			"Framework",
			"Characters",
			"Economy",
			"Progression",
			"Departments",
			"Roles",
			"Jobs",
			"Vehicles",
			"Properties",
			"Furniture",
			"Network",
			"Communities",
			"Spawns",
			"Teams",
			"GroupLinks",
		}
	do
		if type(config[section]) ~= "table" then
			table.insert(errors, "Missing configuration section: " .. section)
		end
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
