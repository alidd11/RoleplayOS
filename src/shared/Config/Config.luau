--!strict

local Config = {
	Framework = {
		Environment = "Development",
		SchemaVersion = 1,
		AutosaveSeconds = 120,
		ShutdownSaveSeconds = 25,
		MaxSaveAttempts = 4,
		SessionLeaseSeconds = 300,
	},
	Characters = {
		FreeSlots = 2,
		MaximumSlots = 6,
		MinimumAge = 16,
		MaximumAge = 100,
		DeletionConfirmationSeconds = 10,
	},
	Economy = {
		StartingBankBalance = 2500,
		StartingCashBalance = 100,
		MaximumTransactionHistory = 200,
		TransferMaximum = 100000,
	},
	Gamepasses = {
		PremiumVehicles = {
			Id = "PremiumVehicles",
			GamepassId = 0,
			Name = "Premium Vehicles",
			Description = "Unlocks the premium vehicle catalogue.",
		},
		ExtraCharacterSlot = {
			Id = "ExtraCharacterSlot",
			GamepassId = 0,
			Name = "Extra Character Slot",
			Description = "Adds one civilian character slot.",
		},
	},
	Departments = {
		Police = {
			Id = "Police",
			Name = "Police",
			Ranks = { "Constable", "Sergeant", "Inspector" },
			RoleIds = { "PoliceOfficer" },
		},
		Ambulance = {
			Id = "Ambulance",
			Name = "Ambulance",
			Ranks = { "Clinician", "Team Leader" },
			RoleIds = { "Paramedic" },
		},
		Fire = {
			Id = "Fire",
			Name = "Fire and Rescue",
			Ranks = { "Firefighter", "Crew Manager" },
			RoleIds = { "Firefighter" },
		},
		Control = {
			Id = "Control",
			Name = "Dispatch and Control",
			Ranks = { "Controller", "Supervisor" },
			RoleIds = { "Controller" },
		},
	},
	Roles = {
		Civilian = {
			Id = "Civilian",
			Name = "Civilian",
			TeamName = "Civilian",
			Access = { AccessType = "Public", DisplayWhenLocked = true },
		},
		PoliceOfficer = {
			Id = "PoliceOfficer",
			Name = "Police Officer",
			TeamName = "Police",
			DepartmentId = "Police",
			Access = {
				AccessType = "Application",
				DepartmentId = "Police",
				DisplayWhenLocked = true,
			},
			LoadoutId = "PoliceResponse",
			UniformId = "PoliceStandard",
		},
		Paramedic = {
			Id = "Paramedic",
			Name = "Paramedic",
			TeamName = "Ambulance",
			DepartmentId = "Ambulance",
			Access = {
				AccessType = "Application",
				DepartmentId = "Ambulance",
				DisplayWhenLocked = true,
			},
			LoadoutId = "AmbulanceStandard",
			UniformId = "AmbulanceStandard",
		},
		Firefighter = {
			Id = "Firefighter",
			Name = "Firefighter",
			TeamName = "Fire",
			DepartmentId = "Fire",
			Access = { AccessType = "Application", DepartmentId = "Fire", DisplayWhenLocked = true },
			LoadoutId = "FireStandard",
			UniformId = "FireStandard",
		},
	},
	Stations = {
		CityCentre = {
			Id = "CityCentre",
			Name = "City Centre",
			DepartmentIds = { "Police", "Ambulance", "Fire", "Control" },
			SpawnNames = { "FrontDesk", "VehicleBay" },
		},
	},
	Uniforms = {
		PoliceStandard = { Id = "PoliceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		AmbulanceStandard = { Id = "AmbulanceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		FireStandard = { Id = "FireStandard", ShirtTemplate = "", TrousersTemplate = "" },
	},
	Loadouts = {
		PoliceResponse = { Id = "PoliceResponse", ToolNames = { "Radio" } },
		AmbulanceStandard = { Id = "AmbulanceStandard", ToolNames = { "Radio", "MedicalBag" } },
		FireStandard = { Id = "FireStandard", ToolNames = { "Radio" } },
	},
	Jobs = {
		DeliveryDriver = {
			Id = "DeliveryDriver",
			Name = "Delivery driver",
			Class = "Public",
			BaseWage = 12,
			TaskReward = 20,
		},
		TaxiDriver = {
			Id = "TaxiDriver",
			Name = "Taxi driver",
			Class = "Public",
			BaseWage = 12,
			TaskReward = 18,
		},
		BusDriver = {
			Id = "BusDriver",
			Name = "Bus driver",
			Class = "Public",
			BaseWage = 13,
			TaskReward = 20,
		},
		SupermarketWorker = {
			Id = "SupermarketWorker",
			Name = "Supermarket worker",
			Class = "Public",
			BaseWage = 11,
			TaskReward = 10,
		},
		WarehouseWorker = {
			Id = "WarehouseWorker",
			Name = "Warehouse worker",
			Class = "Public",
			BaseWage = 12,
			TaskReward = 12,
		},
		Cleaner = {
			Id = "Cleaner",
			Name = "Cleaner",
			Class = "Public",
			BaseWage = 11,
			TaskReward = 10,
		},
		RefuseCollector = {
			Id = "RefuseCollector",
			Name = "Refuse collector",
			Class = "Public",
			BaseWage = 13,
			TaskReward = 16,
		},
		PostalWorker = {
			Id = "PostalWorker",
			Name = "Postal worker",
			Class = "Public",
			BaseWage = 12,
			TaskReward = 14,
		},
		Mechanic = {
			Id = "Mechanic",
			Name = "Mechanic",
			Class = "Application",
			BaseWage = 16,
			TaskReward = 25,
		},
		EstateAgent = {
			Id = "EstateAgent",
			Name = "Estate agent",
			Class = "Application",
			BaseWage = 15,
			TaskReward = 20,
		},
		CarSalesperson = {
			Id = "CarSalesperson",
			Name = "Car salesperson",
			Class = "Application",
			BaseWage = 14,
			TaskReward = 18,
		},
		SecurityOfficer = {
			Id = "SecurityOfficer",
			Name = "Security officer",
			Class = "Application",
			BaseWage = 15,
			TaskReward = 18,
		},
		RecoveryDriver = {
			Id = "RecoveryDriver",
			Name = "Recovery driver",
			Class = "Application",
			BaseWage = 16,
			TaskReward = 25,
		},
		CouncilWorker = {
			Id = "CouncilWorker",
			Name = "Council worker",
			Class = "Application",
			BaseWage = 14,
			TaskReward = 16,
		},
	},
	Applications = {
		Employment = {
			Id = "Employment",
			Name = "Employment application",
			CooldownSeconds = 604800,
			Questions = {
				{
					Id = "motivation",
					Type = "Text",
					Prompt = "Why would you suit this role?",
					MaximumLength = 1000,
				},
				{
					Id = "conduct",
					Type = "Choice",
					Prompt = "Will you follow the role rules?",
					Options = { "Yes", "No" },
				},
			},
		},
	},
	Vehicles = {
		Compact = {
			Id = "Compact",
			Name = "Compact",
			Price = 15000,
			ModelName = "Compact",
			Colours = { "Black", "Blue", "White" },
			Access = { AccessType = "Public" },
		},
		PremiumSaloon = {
			Id = "PremiumSaloon",
			Name = "Premium saloon",
			Price = 45000,
			ModelName = "PremiumSaloon",
			Colours = { "Black", "Silver" },
			Access = {
				AccessType = "Gamepass",
				Id = "PremiumVehicles",
				GamepassId = 0,
				DisplayWhenLocked = true,
			},
		},
	},
	Dealerships = {
		CityMotors = {
			Id = "CityMotors",
			Name = "City Motors",
			VehicleIds = { "Compact", "PremiumSaloon" },
		},
	},
	Properties = {
		StarterFlat = {
			Id = "StarterFlat",
			Name = "Starter flat",
			PurchasePrice = 80000,
			RentPrice = 800,
			InteriorTemplate = "StarterFlat",
			FurnitureCapacity = 50,
			GarageCapacity = 0,
		},
	},
	EstateAgents = {
		CityEstates = { Id = "CityEstates", Name = "City Estates", PropertyIds = { "StarterFlat" } },
	},
	Furniture = {
		BasicChair = {
			Id = "BasicChair",
			Name = "Basic chair",
			Category = "Seating",
			Price = 120,
			Bounds = { 2, 3, 2 },
			Access = { AccessType = "Public" },
		},
	},
	FurnitureStores = {
		HomeStore = { Id = "HomeStore", Name = "Home Store", FurnitureIds = { "BasicChair" } },
	},
	Businesses = {
		Workshop = {
			Id = "Workshop",
			Name = "Workshop",
			MaximumEmployees = 12,
			WageBands = { 12, 16, 20 },
		},
	},
	MDT = {
		PageSize = 25,
		MaximumQueryLength = 64,
		PermissionByDepartment = {
			Police = { "PersonSearch", "VehicleSearch", "IncidentWrite", "WarrantRead" },
			Control = { "PersonSearch", "VehicleSearch", "IncidentRead" },
		},
	},
	Dispatch = {
		UnitStatuses = { "Available", "Assigned", "OnScene", "Unavailable" },
		CallPriorities = { "Immediate", "Prompt", "Routine" },
		ActiveStateTtlSeconds = 300,
	},
	Network = {
		MaximumPayloadBytes = 8192,
		Endpoints = {
			GetStartMenu = { Capacity = 4, RefillPerSecond = 1 },
			SelectCharacter = { Capacity = 3, RefillPerSecond = 0.5 },
			SubmitApplication = { Capacity = 1, RefillPerSecond = 0.02 },
			EconomyTransfer = { Capacity = 3, RefillPerSecond = 0.2 },
			MDTSearch = { Capacity = 5, RefillPerSecond = 0.5 },
			DispatchUpdate = { Capacity = 10, RefillPerSecond = 2 },
		},
	},
}

return table.freeze(Config)
