--!strict

-- Vehicle content. These are merged over the defaults in Config.luau, so this
-- is the file to edit rather than that one.
--
-- WorkspaceModelName must match the model's name in Workspace character for
-- character. It is what the Studio installer looks for when it moves a parked
-- model into the template store, and what the emergency-lighting pass matches on
-- when it adopts a vehicle that was placed by hand rather than spawned.
--
-- The two Surron names below are the one thing here I could not verify: nothing
-- in the repository records what those models are actually called in your
-- baseplate. If they differ, correct the two WorkspaceModelName lines and
-- nothing else needs touching. On the next boot the lighting pass names every
-- parked vehicle it could not place, so the log will tell you the real names.
--
-- A note on the forecourt list further down: the merge walks tables key by key,
-- and an array is a table whose keys are 1, 2, 3. Listing only the new vehicle
-- would not append it, it would overwrite whatever is currently first. The whole
-- forecourt is written out for that reason.
return {
	Vehicles = {
		HondaADV160 = {
			Id = "HondaADV160",
			Name = "Honda ADV 160",
			Price = 7500,
			ModelName = "HondaADV160",
			WorkspaceModelName = "2024 Honda ADV 160",
			AssetPath = { "Vehicles", "Civilian", "Standard", "HondaADV160" },
			Colours = { "Red", "Black", "White" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
		-- Roads Policing. Service vehicles carry no price: they are issued by the
		-- role rather than bought, which is why Price is zero here and on every
		-- other marked vehicle.
		SurronPolice = {
			Id = "SurronPolice",
			Name = "Sur-Ron Roads Policing",
			Price = 0,
			ModelName = "SurronPolice",
			WorkspaceModelName = "Surron Police",
			AssetPath = { "Vehicles", "Services", "Police", "RoadsPolicing", "SurronPolice" },
			Colours = { "Police" },
			Category = "Service",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "RoadsPolicing",
			RoleIds = { "RoadsPolicingOfficer" },
		},
		-- The civilian one, behind the Sur-Ron pass. DisplayWhenLocked keeps it on
		-- the forecourt for players who have not bought it, which is the only way
		-- anybody finds out it exists.
		SurronCivilian = {
			Id = "SurronCivilian",
			Name = "Sur-Ron Light Bee",
			Price = 9500,
			ModelName = "SurronCivilian",
			WorkspaceModelName = "Surron",
			AssetPath = { "Vehicles", "Civilian", "Premium", "SurronCivilian" },
			Colours = { "Black", "Red", "White" },
			Access = {
				AccessType = "Gamepass",
				Id = "SurronBike",
				DisplayWhenLocked = true,
			},
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
				"SurronCivilian",
				"PremiumSaloon",
				"Ferrari488",
				"UrusMansory",
			},
		},
	},
}
