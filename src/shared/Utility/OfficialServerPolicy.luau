--!strict

local OfficialServerPolicy = {}

-- Pure shared-record transform used by UpdateAsync. Keeping the cap check in
-- this transform makes concurrent reservations contend on the same atomic
-- record instead of relying on an earlier, stale read.
function OfficialServerPolicy.appendInstance(
	existing: any,
	accessCode: string,
	maximumInstances: number,
	serverId: string,
	updatedAt: number
): (any, number?, string?)
	local record = if type(existing) == "table" then table.clone(existing) else {}
	local storedInstances = if type(record.Instances) == "table"
		then record.Instances
		elseif type(record.AccessCode) == "string" then { record.AccessCode }
		else {}
	local instances = table.clone(storedInstances)

	for index, code in instances do
		if code == accessCode then
			return record, index, nil
		end
	end

	if #instances >= maximumInstances then
		return record, nil, "OFFICIAL_SERVER_FULL"
	end

	table.insert(instances, accessCode)
	record.ServerId = serverId
	record.Instances = instances
	record.AccessCode = instances[1]
	record.UpdatedAt = updatedAt
	return record, #instances, nil
end

return table.freeze(OfficialServerPolicy)
