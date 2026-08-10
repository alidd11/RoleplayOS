--!strict

-- VEHICLES AND SPAWNERS
--
-- This is the safe, central file for routine vehicle editing. Category controls
-- which kind of spawner can show the vehicle. Never mark a service vehicle as
-- Civilian: civilian dealerships deliberately reject every Service definition.
--
-- AssetPath is relative to ServerStorage > RoleplayOSAssets. WorkspaceModelName
-- is a temporary exact-name fallback for models already placed in the baseplate.
-- Move production vehicles into RoleplayOSAssets and keep AssetPath authoritative.
--
-- Spawner world positions are not stored here. Move each model beneath
-- Workspace > RoleplayOSVehicleFacilities to its department's real location.

return {
	Vehicles = {
		Compact = {
			Name = "BMW M140i",
			Price = 15000,
			Category = "Civilian",
			WorkspaceModelName = "M140i",
			AssetPath = { "Vehicles", "Civilian", "Starter", "Compact" },
		},
		PremiumSaloon = {
			Name = "BMW M5 Touring",
			Price = 45000,
			Category = "Civilian",
			WorkspaceModelName = "M5 Touring",
			AssetPath = { "Vehicles", "Civilian", "Premium", "PremiumSaloon" },
		},
		M3Touring = {
			Name = "BMW M3 Touring",
			Price = 65000,
			Category = "Civilian",
			WorkspaceModelName = "M3 Touring",
			AssetPath = { "Vehicles", "Civilian", "Standard", "M3Touring" },
		},
		FordRanger = {
			Name = "Ford Ranger",
			Price = 42000,
			Category = "Civilian",
			WorkspaceModelName = "Ford Ranger",
			AssetPath = { "Vehicles", "Civilian", "Standard", "FordRanger" },
		},
		Ferrari488 = {
			Name = "Ferrari 488 GT3",
			Price = 220000,
			Category = "Civilian",
			WorkspaceModelName = "Ferrari 488 GT3 Race Car",
			AssetPath = { "Vehicles", "Civilian", "Premium", "Ferrari488" },
		},
		UrusMansory = {
			Name = "Urus Mansory",
			Price = 180000,
			Category = "Civilian",
			WorkspaceModelName = "Urusmansory",
			AssetPath = { "Vehicles", "Civilian", "Premium", "UrusMansory" },
		},

		PoliceResponse = {
			Name = "Marked response car",
			Category = "Service",
			DepartmentId = "Police",
			DivisionId = "Frontline",
			WorkspaceModelName = "Marked 308",
			AssetPath = { "Vehicles", "Services", "Police", "Frontline", "PoliceResponse" },
		},
		FrontlinePatrolEstate = {
			Name = "Frontline patrol estate",
			Category = "Service",
			DepartmentId = "Police",
			DivisionId = "Frontline",
			WorkspaceModelName = "Toyota Corolla - Police",
			AssetPath = {
				"Vehicles",
				"Services",
				"Police",
				"Frontline",
				"FrontlinePatrolEstate",
			},
		},
		ArmedResponseSUV = {
			Name = "Armed response SUV",
			Category = "Service",
			DepartmentId = "Police",
			DivisionId = "ArmedResponse",
			WorkspaceModelName = "UNMXC90",
			AssetPath = { "Vehicles", "Services", "Police", "ArmedResponse", "ArmedResponseSUV" },
		},
		RoadsPolicingEstate = {
			Name = "Roads policing estate",
			Category = "Service",
			DepartmentId = "Police",
			DivisionId = "RoadsPolicing",
			WorkspaceModelName = "Toyota Corolla - Police",
			AssetPath = { "Vehicles", "Services", "Police", "RoadsPolicing", "RoadsPolicingEstate" },
		},
		PoliceUnmarkedGolf = {
			Name = "Unmarked Volkswagen Golf GTI",
			Category = "Service",
			DepartmentId = "Police",
			WorkspaceModelName = "Volkswagen Golf 8 GTI (Unmarked)",
			AssetPath = { "Vehicles", "Services", "Police", "Shared", "PoliceUnmarkedGolf" },
		},
		PoliceTransportVan = {
			Name = "Police transport van",
			Category = "Service",
			DepartmentId = "Police",
			WorkspaceModelName = "PTV",
			AssetPath = { "Vehicles", "Services", "Police", "Shared", "PoliceTransportVan" },
		},
		AmbulanceResponse = {
			Name = "Ambulance response car",
			Category = "Service",
			DepartmentId = "Ambulance",
			AssetPath = { "Vehicles", "Services", "Ambulance", "AmbulanceResponse" },
		},
		FireEngine = {
			Name = "Fire engine",
			Category = "Service",
			DepartmentId = "Fire",
			AssetPath = { "Vehicles", "Services", "Fire", "FireEngine" },
		},
		ServiceBus = {
			Name = "Service bus",
			Category = "Service",
			DepartmentId = "Transport",
			AssetPath = { "Vehicles", "Services", "Transport", "ServiceBus" },
		},
		HighwaysPatrol = {
			Name = "Highways patrol vehicle",
			Category = "Service",
			DepartmentId = "Highways",
			AssetPath = { "Vehicles", "Services", "Highways", "HighwaysPatrol" },
		},
		PrisonTransport = {
			Name = "Prison transport van",
			Category = "Service",
			DepartmentId = "Prison",
			AssetPath = { "Vehicles", "Services", "Prison", "PrisonTransport" },
		},
	},

	VehicleSpawners = {
		FolderName = "RoleplayOSVehicleFacilities",
		MaximumInteractionDistance = 16,
		CooldownSeconds = 8,
		SpawnClearance = Vector3.new(14, 8, 24),
	},

	Dealerships = {
		CityMotors = {
			Name = "City Motors",
			VehicleIds = {
				"Compact",
				"M3Touring",
				"FordRanger",
				"PremiumSaloon",
				"Ferrari488",
				"UrusMansory",
			},
		},
	},
}
