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
		-- Priced against the wage rates in Config.luau rather than against real
		-- money. Police pay is 2600 an hour, and the note beside it sets the
		-- yardstick: a first car at fifteen thousand is about six hours of
		-- shifts, a premium saloon about eighteen. These keep the same order
		-- among themselves that the real cars have, so a Civic sits below an S90
		-- and an X5 above both, and land on that curve rather than on a number
		-- that sounded expensive.
		--
		-- Every one of these is discovered from its model rather than declared,
		-- and discovery refuses a civilian vehicle with no price. All seven were
		-- therefore being dropped on load, which is why none of them reached a
		-- forecourt. Stating the price here is what admits them.
		CivicTypeR = {
			Id = "CivicTypeR",
			Name = "Honda Civic Type R",
			Price = 28000,
			ModelName = "20' Honda Civic Type R",
			WorkspaceModelName = "20' Honda Civic Type R",
			AssetPath = { "Vehicles", "Civilian", "Standard", "20' Honda Civic Type R" },
			Colours = { "Red", "White", "Black" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
		VolvoS90 = {
			Id = "VolvoS90",
			Name = "Volvo S90",
			Price = 42000,
			ModelName = "20' Volvo S90",
			WorkspaceModelName = "20' Volvo S90",
			AssetPath = { "Vehicles", "Civilian", "Standard", "20' Volvo S90" },
			Colours = { "Black", "Silver", "White" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
		VolvoXC90 = {
			Id = "VolvoXC90",
			Name = "Volvo XC90",
			Price = 55000,
			ModelName = "22' Volvo XC90",
			WorkspaceModelName = "22' Volvo XC90",
			AssetPath = { "Vehicles", "Civilian", "Standard", "22' Volvo XC90" },
			Colours = { "Black", "Grey", "White" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
		AudiRS3 = {
			Id = "AudiRS3",
			Name = "Audi RS3",
			Price = 62000,
			ModelName = "22' Audi RS3",
			WorkspaceModelName = "22' Audi RS3",
			AssetPath = { "Vehicles", "Civilian", "Premium", "22' Audi RS3" },
			Colours = { "Grey", "Blue", "Black" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
		BmwX5 = {
			Id = "BmwX5",
			Name = "BMW X5",
			Price = 68000,
			ModelName = "21' BMW X5 GO5",
			WorkspaceModelName = "21' BMW X5 GO5",
			AssetPath = { "Vehicles", "Civilian", "Premium", "21' BMW X5 GO5" },
			Colours = { "Black", "White", "Blue" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
		},
	},
	Dealerships = {
		CityMotors = {
			Id = "CityMotors",
			Name = "City Motors",
			VehicleIds = {
				"HondaADV160",
				"CivicTypeR",
				"VolvoS90",
				"VolvoXC90",
				"AudiRS3",
				"BmwX5",
				"SurronCivilian",
			},
		},
	},
}
