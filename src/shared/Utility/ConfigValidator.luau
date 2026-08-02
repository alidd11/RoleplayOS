--!strict

local ConfigValidator = {}

function ConfigValidator.validate(config: any): (boolean, { string })
	local errors = {}
	for _, section in
		{
			"Framework",
			"Characters",
			"Economy",
			"Departments",
			"Roles",
			"Jobs",
			"Vehicles",
			"Properties",
			"Furniture",
			"Network",
			"Communities",
			"Spawns",
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
	for spawnId, spawn in config.Spawns or {} do
		local station = config.Stations[spawn.StationId]
		if spawn.Id ~= spawnId or not station or not table.find(station.SpawnIds, spawnId) then
			table.insert(errors, "Invalid spawn definition: " .. spawnId)
		end
		for _, roleId in spawn.RoleIds or {} do
			if not config.Roles[roleId] then
				table.insert(errors, "Unknown role " .. roleId .. " in spawn " .. spawnId)
			end
		end
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
	return #errors == 0, errors
end

return table.freeze(ConfigValidator)
