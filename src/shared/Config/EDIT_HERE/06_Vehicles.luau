--!strict

-- Vehicle content. These are merged over the defaults in Config.luau, so this
-- is the file to edit rather than that one.
--
-- A note on the forecourt list below: the merge walks tables key by key, and an
-- array is a table whose keys are 1, 2, 3. Listing only the new vehicle would
-- therefore not append it, it would overwrite whatever is currently first. The
-- whole forecourt is written out for that reason.
return {
	Vehicles = {
		HondaADV160 = {
			Id = "HondaADV160",
			Name = "Honda ADV 160",
			Price = 7500,
			ModelName = "HondaADV160",
			-- Must match the model's name in Workspace exactly, including the
			-- year, because that is what the Studio installer looks for when it
			-- moves the model into the template store.
			WorkspaceModelName = "2024 Honda ADV 160",
			AssetPath = { "Vehicles", "Civilian", "Standard", "HondaADV160" },
			Colours = { "Red", "Black", "White" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
	},
	Dealerships = {
		CityMotors = {
			Id = "CityMotors",
			Name = "City Motors",
			VehicleIds = {
				"Compact",
				"M3Touring",
				"FordRanger",
				"HondaADV160",
				"PremiumSaloon",
				"Ferrari488",
				"UrusMansory",
			},
		},
	},
}
