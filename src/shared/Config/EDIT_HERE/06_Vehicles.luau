--!strict

-- Vehicle content. These are merged over the defaults in Config.luau, so this
-- is the file to edit rather than that one.
--
-- WorkspaceModelName must match the model's name in Workspace character for
-- character. It is what the Studio installer looks for when it moves a parked
-- model into the template store, and what the emergency-lighting pass matches on
-- when it adopts a vehicle that was placed by hand rather than spawned.
--
-- The Surron source names below match the three variants in the imported source
-- package: marked, unmarked and civilian. If the source package is replaced,
-- update the corresponding WorkspaceSourcePath and nothing else needs touching.
--
-- A note on the forecourt list further down: the merge walks tables key by key,
-- and an array is a table whose keys are 1, 2, 3. Listing only the new vehicle
-- would not append it, it would overwrite whatever is currently first. The whole
-- forecourt is written out for that reason.
return {
	Vehicles = {
		CorollaTaxi = {
			Id = "CorollaTaxi",
			Name = "Toyota Corolla Taxi",
			Price = 0,
			ModelName = "CorollaTaxi",
			WorkspaceModelName = "CorollaTaxi",
			-- Taxi is a public job, but its fleet is issued from the shared
			-- Transport depot. Keeping the template in the Transport branch makes
			-- the asset location agree with the live spawner and the authoring guide.
			AssetPath = { "Vehicles", "Services", "Transport", "CorollaTaxi" },
			Colours = { "White", "Black", "Yellow" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
			JobId = "TaxiDriver",
			Fleet = true,
		},
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
			WorkspaceModelName = "23' Plate Surron Ultra Bee | Marked",
			WorkspaceSourcePath = { "Surron Ultra Bee", "23' Plate Surron Ultra Bee | Marked" },
			AssetPath = { "Vehicles", "Services", "Police", "RoadsPolicing", "SurronPolice" },
			Colours = { "Police" },
			Category = "Service",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "RoadsPolicing",
			RoleIds = { "RoadsPolicingOfficer" },
		},
		SurronPoliceUnmarked = {
			Id = "SurronPoliceUnmarked",
			Name = "Sur-Ron Roads Policing (Unmarked)",
			Price = 0,
			ModelName = "SurronPoliceUnmarked",
			WorkspaceModelName = "23' Plate Surron Ultra Bee | UnMarked",
			WorkspaceSourcePath = { "Surron Ultra Bee", "23' Plate Surron Ultra Bee | UnMarked" },
			AssetPath = {
				"Vehicles",
				"Services",
				"Police",
				"RoadsPolicing",
				"SurronPoliceUnmarked",
			},
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
			WorkspaceModelName = "23' Plate Surron Ultra Bee | Civilian",
			WorkspaceSourcePath = { "Surron Ultra Bee", "23' Plate Surron Ultra Bee | Civilian" },
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
				"HondaADV160",
				"SurronCivilian",
			},
		},
	},
}
