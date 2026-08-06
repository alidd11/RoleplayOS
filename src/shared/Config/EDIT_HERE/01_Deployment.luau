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
	Integrations = {
		Discord = {
			SpeedingFines = {
				-- Create a webhook inside the configured Discord channel, save its
				-- complete URL as the RoleplayOSSpeedingFinesWebhook Creator Hub
				-- secret, enable HTTP requests, then change this to true.
				Enabled = false,
			},
		},
	},
}
