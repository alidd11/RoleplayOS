--!strict

-- GroupId is the number in roblox.com/communities/<number>/...
-- MinimumRank uses Roblox's 0-255 group-rank value, not the role-set ID.
return {
	GroupLinks = {
		UniversalProjects = { GroupId = 33809042, MinimumRank = 1 },
		Police = { GroupId = 34720334, MinimumRank = 1 },
		ArmedResponse = { GroupId = 16985274, MinimumRank = 1 },
		RoadsPolicing = { GroupId = 33815770, MinimumRank = 1 },
		Ambulance = { GroupId = 33840360, MinimumRank = 1 },
		Fire = { GroupId = 14293067, MinimumRank = 1 },
		-- Control is intentionally governed by the main Universal Projects group.
		Control = { GroupId = 33809042, MinimumRank = 1 },
		Transport = { GroupId = 33360488, MinimumRank = 1 },
		Highways = { GroupId = 34022475, MinimumRank = 1 },
		Prison = { GroupId = 16361786, MinimumRank = 1 },
	},
}
