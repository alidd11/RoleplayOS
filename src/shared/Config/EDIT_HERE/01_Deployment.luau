--!strict

return {
	Framework = {
		-- Change to "Production" only for a release build.
		Environment = "Development",
		Branding = {
			GameName = "Emergency Response: Portsmouth",
			ShowRoleplayOSMark = true,
		},
		-- Both must be false before publishing the production place.
		UseMockDataInStudio = true,
		GrantMockEmergencyAccessInStudio = true,
	},
}
