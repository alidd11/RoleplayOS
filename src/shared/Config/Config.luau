--!strict

local function publicPassOr(existingRule: any, gamepassId: number): any
	return {
		AccessType = "Combined",
		Match = "Any",
		DisplayWhenLocked = true,
		Rules = {
			existingRule,
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kind = "Public" },
					{ AccessType = "Gamepass", GamepassId = gamepassId },
				},
			},
		},
	}
end

local function publicOr(existingRule: any): any
	return {
		AccessType = "Combined",
		Match = "Any",
		DisplayWhenLocked = true,
		Rules = {
			existingRule,
			{ AccessType = "ServerKind", Kind = "Public" },
		},
	}
end

local Config = {
	Framework = {
		Environment = "Development",
		SchemaVersion = 7,
		Branding = {
			GameName = "Emergency Response: Portsmouth",
			ShowRoleplayOSMark = true,
		},
		UseMockDataInStudio = true,
		GrantMockEmergencyAccessInStudio = true,
		-- Saving also renews the session lease, so this is what keeps a live
		-- server's claim on a profile alive.
		AutosaveSeconds = 60,
		-- Roblox allows about thirty seconds for BindToClose. Two services block on
		-- shutdown and their budgets add up rather than sharing: incidents take
		-- half of this and profiles take all of it, so twenty five meant a worst
		-- case of thirty seven and a half and the process was killed mid save.
		-- Sixteen keeps the pair under twenty five with room for the rest.
		ShutdownSaveSeconds = 16,
		MaxSaveAttempts = 4,
		-- How long a profile stays claimed by a server, and how long a player is
		-- locked out after a server dies without releasing it.
		--
		-- This must stay comfortably above AutosaveSeconds, not equal to it. The
		-- lease is renewed by the save, so equal values expire it at the exact
		-- moment its renewal falls due, and any save latency lets a server lose
		-- the lease on a player who is still sitting in front of it. At double
		-- the cadence a save has to miss twice running before that can happen.
		--
		-- Lowering it shortens the lockout after a crash but shortens the grace
		-- for a live server too; it should not go below twice AutosaveSeconds.
		SessionLeaseSeconds = 120,
		-- The longest a join will sit waiting for someone else's lease to lapse.
		--
		-- Waiting happens inside the PlayerAdded handler, where the player has no
		-- profile and no character yet. Roblox abandons a join that takes too
		-- long, and the player sees a connection error rather than anything this
		-- framework chose to tell them, so a wait must stay far shorter than the
		-- lease it is waiting on. Beyond this the player is told plainly to come
		-- back in a moment, which is a worse outcome than loading but a much
		-- better one than a silent disconnection.
		MaximumLeaseWaitSeconds = 12,
		-- How long a join waits for the same player's previous session on this
		-- server to finish saving and let go. Roblox often puts a returning
		-- player back on the server they just left, so this covers the ordinary
		-- case of leaving and rejoining straight away rather than an unusual one.
		-- It must comfortably exceed a save that has to retry.
		SessionHandoverSeconds = 10,
		-- How many times a join will try to load a profile before giving up.
		-- Each attempt already retries the store call itself; this is the outer
		-- loop, so a failure that clears within a few seconds never reaches the
		-- player at all.
		JoinLoadAttempts = 3,
		-- A profile larger than this is reported while there is still room to act.
		-- Roblox refuses a value over four megabytes, and a profile that reaches
		-- that stops saving silently: every write fails from then on and the
		-- player loses everything after their last good save.
		ProfileSizeWarningBytes = 1400000,
		-- Caps on the parts of a profile that are history rather than possessions.
		-- History is trimmed oldest first, since losing the record of a job held
		-- two years ago costs nothing, whereas an unbounded list eventually costs
		-- the entire profile.
		MaximumApplicationHistory = 60,
		MaximumEmploymentHistory = 40,
		-- Speed and red light cameras write these without anybody asking, so this
		-- is the history most able to grow on its own.
		MaximumDrivingFines = 80,
	},
	ContentQuality = {
		RequireCertification = true,
		CertificationVersion = 1,
		WorldAssetTag = "RoleplayOSWorldAsset",
		WorldAssetRootName = "RoleplayOSWorldAssets",
		QuarantineRootName = "RoleplayOSAssetQuarantine",
		RequiredWorldAssetKinds = {
			"ANPRCamera",
			"CCTVCamera",
			"CustodyFurniture",
			"DealershipNPC",
			"DispatchFurniture",
			"SpeedCamera",
		},
		MaximumVehicleParts = 350,
		MaximumToolParts = 80,
		MaximumWorldAssetParts = 250,
		MaximumVehicleDescendants = 900,
		MaximumToolDescendants = 180,
		MaximumWorldAssetDescendants = 650,
		MinimumVehicleExtentStuds = 2,
		MaximumVehicleExtentStuds = 55,
		MinimumWorldAssetExtentStuds = 0.1,
		MaximumWorldAssetExtentStuds = 80,
	},
	-- Roblox throttles group membership lookups per server, and answers a burst
	-- with a 429 that is indistinguishable from any other failure. Every number
	-- here exists to keep this framework under that ceiling, because a throttled
	-- check is read as an unverified member and an unverified member is kicked.
	Groups = {
		-- Gap between prefetching one group link and the next, jittered. Ten links
		-- warmed back to back per joining player is what made a filling server
		-- throttle itself.
		WarmSpacingSeconds = 0.6,
		-- A verified answer is good for this long. Raising it cuts request volume
		-- but leaves a promotion or removal unseen for longer.
		CacheSeconds = 300,
		-- Ceiling on the wait after consecutive failures, which doubles each time.
		MaximumFailureBackoffSeconds = 120,
	},
	-- The official servers listed in the Communities section.
	--
	-- Each is a reserved server: reserved once, its access code kept, and every
	-- later join sent to that same code so the community is not scattered across
	-- instances Roblox happened to spin up. A reserved server does not appear in
	-- the Roblox server list, which is the point, since these are reached from
	-- the menu rather than found from outside.
	OfficialServers = {
		Enabled = true,
		-- An official server is a set of instances rather than one. When the first
		-- fills, the next join opens another, so nobody is turned away at peak.
		--
		-- Occupancy is published to a memory store by each instance and read by
		-- whoever is about to send somebody, because a server cannot see how full
		-- another one is any other way.
		MaximumPlayersPerInstance = 30,
		-- A ceiling on how far the community can be split. Past this, joins are
		-- refused rather than scattering everybody across instances too thin to
		-- roleplay in.
		MaximumInstances = 6,
		-- How often an instance republishes its occupancy, and how long that
		-- reading is trusted. The lifetime is deliberately several times the
		-- interval so one missed beat does not read as an empty server.
		OccupancyHeartbeatSeconds = 12,
		OccupancyLifetimeSeconds = 45,
		Entries = {
			-- The whitelisted community. Emergency roles here are held by group
			-- membership and application, not bought, which is the whole reason
			-- for it existing separately from the public place.
			UniversalProjects = {
				Id = "UniversalProjects",
				Name = "Universal Projects",
				Description = "Whitelisted roleplay. Emergency services by application.",
				Order = 1,
				Whitelisted = true,
				RequiredGroupLinkId = "UniversalProjects",
				-- The place this world lives in. Zero means the same place as the
				-- public one, which is the state until a separate place exists.
				--
				-- Put the whitelisted world in its own place in THIS universe and
				-- name its id here. Any place in the same universe teleports
				-- natively and shares the same data stores, so a player's profile,
				-- money and vehicles follow them across. A place in a different
				-- universe would not share those and they would arrive with
				-- nothing, so do not use one.
				PlaceId = 0,
				-- Reserved instances gather everybody into one world and open
				-- another only when it fills. Set false to hand the player to that
				-- place's ordinary matchmaking instead.
				Reserved = true,
			},
			Training = {
				Id = "Training",
				Name = "Training",
				Description = "Assessments and inductions. Quiet by design.",
				Order = 2,
				Whitelisted = true,
				RequiredGroupLinkId = "UniversalProjects",
				PlaceId = 0,
				Reserved = true,
			},
		},
	},
	-- Entry to the experience itself.
	--
	-- Off, deliberately. Gating the whole place on the Universal Projects group
	-- meant nobody outside it could join at all, so the public tier could not
	-- exist: every server reported as Whitelisted, and the roles written as
	-- "in the group or on a public server" never saw a public server to match.
	-- One flag was defeating the three tiers the rest of the configuration
	-- already describes.
	--
	-- Whitelisting now belongs to the servers that want it. An official server
	-- entry naming a RequiredGroupLinkId gates itself, and the public place stays
	-- open to everybody.
	ExperienceAccess = {
		Enabled = false,
		RequiredGroupLinkId = "UniversalProjects",
		KickMessage = "This experience is restricted to members of the Universal Projects Roblox community.",
		-- Attempts to get a definitive answer before giving up, with the wait
		-- doubling each time. A throttle clears on a clock, so the retries have to
		-- outlast it rather than hammer through it; the previous two-and-three
		-- second retries expired long before a rate limit did and turned every
		-- throttled join into a kick.
		VerifyAttempts = 4,
		VerifyBackoffSeconds = 3,
	},
	Characters = {
		FreeSlots = 2,
		MaximumSlots = 6,
		MinimumAge = 16,
		MaximumAge = 100,
		DeletionConfirmationSeconds = 10,
	},
	Communities = {
		Enabled = true,
		-- The group a player must be in before they can join any private
		-- community. Private servers are run to their owner's standards and
		-- whitelisted ones are staffed by people who applied; both sit downstream
		-- of membership here. Set to nil to let anybody into a private server.
		RequiredGroupLinkId = "UniversalProjects",
		AllowPrivateServerCommunities = true,
		MaximumMembershipsPerPlayer = 20,
		DefaultTemplateId = "RoleplayCommunity",
		GroupRoleRanks = {
			Owner = 255,
			Administrator = 200,
			Moderator = 100,
			Member = 1,
		},
		Templates = {
			RoleplayCommunity = {
				Id = "RoleplayCommunity",
				Name = "Roleplay Community",
				MaximumMembers = 250,
				DefaultMemberRoleId = "Member",
				Roles = {
					Owner = { Id = "Owner", Priority = 100, Permissions = { "*" } },
					Administrator = {
						Id = "Administrator",
						Priority = 80,
						Permissions = {
							"Community.Manage",
							"Members.Manage",
							"Sessions.Manage",
							"Moderation.Manage",
							"Content.Manage",
						},
					},
					Moderator = {
						Id = "Moderator",
						Priority = 60,
						Permissions = { "Members.View", "Sessions.Manage", "Moderation.Manage" },
					},
					Member = {
						Id = "Member",
						Priority = 10,
						Permissions = { "Community.Join", "Sessions.Join" },
					},
				},
				DefaultPolicies = {
					JoinMode = "Approval",
					AllowPublicCivilian = true,
					RequireCommunityMembership = false,
					EconomyPreset = "Standard",
					RoleplayRules = "Standard",
				},
			},
		},
	},
	Economy = {
		StartingBankBalance = 2500,
		StartingCashBalance = 100,
		MaximumTransactionHistory = 200,
		TransferMaximum = 100000,
	},
	-- Wages. Without an income the economy only ever drains, so prices carry no
	-- meaning: these rates are what every price in the game is measured against.
	--
	-- They are set from what things cost rather than from what sounds plausible.
	-- Against the starter vehicle at fifteen thousand, an emergency shift buys a
	-- first car in roughly six hours of play, the premium saloon in about
	-- eighteen and the starter flat in about thirty, which leaves the first
	-- purchase reachable in a session or two and property a long-term goal.
	-- Change these together with prices, never one alone.
	Payroll = {
		Enabled = true,
		-- Pay is settled this often while working, rather than in a lump on
		-- clocking off, so a crash or a disconnect costs at most one period.
		IntervalSeconds = 120,
		-- Studs a character must have covered since the last payment to be paid
		-- for it. A character left standing must not earn the same as one
		-- answering calls, or every price stops meaning anything.
		MinimumMovementStuds = 24,
		DepartmentHourlyRates = {
			Police = 2600,
			Ambulance = 2600,
			Fire = 2500,
			Control = 2300,
			Prison = 2200,
			Highways = 2000,
			Transport = 1900,
		},
		DefaultDepartmentHourlyRate = 2000,
		-- Added per rank above the first, so seniority is worth holding.
		RankHourlyBonus = 180,
		-- Civilian employment pays less than an emergency service shift, so the
		-- services remain the career path. A job may set its own HourlyRate to
		-- override this; BaseWage is a per-task figure and is not an hourly rate.
		CivilianHourlyRate = 1400,
	},
	Progression = {
		BaseXP = 100,
		GrowthFactor = 1.18,
		MaximumLevel = 100,
		MaximumGrant = 1000,
		MaximumHistory = 100,
		MaximumRewardIds = 500,
		DefaultTaskXP = 25,
	},
	Minimap = {
		Enabled = true,
		BoundsTag = "RoleplayOSMinimapBounds",
		RoadTag = "RoleplayOSMinimapRoad",
		PointTag = "RoleplayOSMinimapPOI",
		UpdateHz = 8,
		-- Caps apply to the window around the player, not the whole world, so
		-- they bound what is drawn rather than arbitrarily truncating a
		-- region-sized map to whichever parts happened to be enumerated first.
		MaximumRoads = 300,
		MaximumPoints = 80,
		-- A phone draws into a panel roughly half the size and has the least
		-- capable renderer, so it draws proportionally less into it. Detail that
		-- lands below a pixel on that panel costs a frame to build and cannot be
		-- seen once it is there.
		CompactMaximumRoads = 140,
		CompactMaximumPoints = 36,
		-- Studs either side of the player shown on the minimap. Projecting a
		-- region-sized world whole leaves every road a few thousandths of the
		-- surface wide, which reads as a smear.
		WindowRadius = 900,
		-- How far the player moves before the window is redrawn.
		RedrawDistance = 60,
		-- Minimum gap between full passes over the tagged geometry. Only this
		-- pass scales with the size of the map.
		RecollectSeconds = 3,
		-- Panel footprint before the interface scale is applied. Anything that
		-- has to sit clear of the minimap reads this rather than repeating the
		-- numbers, so the two cannot drift apart when the panel is resized.
		PanelSize = Vector2.new(184, 208),
		CompactPanelSize = Vector2.new(150, 170),
		-- Fraction of the screen height the panel is centred on while driving,
		-- where it moves to the left edge.
		VehicleAnchorY = 0.52,
	},
	Locations = {
		Enabled = true,
		-- Streets and districts are invisible parts in the map carrying this tag.
		-- Each holds a StreetName attribute, optionally a DistrictName, and
		-- optionally a numeric Priority so an enclosing district does not mask
		-- the street inside it: the highest priority overlapping the player wins.
		ZoneTag = "RoleplayOSZone",
		-- How often the player's zone is resolved. This is a spatial query, not a
		-- pass over every zone, so it stays cheap as the map grows.
		UpdateSeconds = 0.4,
		-- Minimum gap between rebuilds of the query filter, which is the only
		-- work proportional to the number of zones.
		RecollectSeconds = 5,
		-- Overlapping zones considered at one point. Beyond a handful the map has
		-- been authored with zones stacked on each other rather than beside.
		MaximumOverlaps = 12,
	},
	Gamepasses = {
		PremiumVehicles = {
			Id = "PremiumVehicles",
			GamepassId = 1935128985,
			Name = "Premium Vehicles",
			Description = "Unlocks the premium vehicle catalogue.",
		},
		ExtraCharacterSlot = {
			Id = "ExtraCharacterSlot",
			GamepassId = 1935374962,
			Name = "Extra Character Slot",
			Description = "Adds one civilian character slot.",
		},
		CustomRegistration = {
			Id = "CustomRegistration",
			GamepassId = 1932237647,
			Name = "Custom Registration Plate",
			Description = "Lets civilians choose a moderated registration for an owned vehicle.",
		},
		CivilianKnife = {
			Id = "CivilianKnife",
			GamepassId = 1932205625,
			Name = "Civilian Knife Access",
			Description = "Unlocks approved civilian knife items.",
		},
		CivilianHandgun = {
			Id = "CivilianHandgun",
			GamepassId = 1935362991,
			Name = "Civilian Handgun Access",
			Description = "Unlocks approved civilian handgun items.",
		},
		CivilianShotgun = {
			Id = "CivilianShotgun",
			GamepassId = 1934043075,
			Name = "Civilian Shotgun Access",
			Description = "Unlocks approved civilian shotgun items.",
		},
		CivilianRifle = {
			Id = "CivilianRifle",
			GamepassId = 1933239337,
			Name = "Civilian Rifle Access",
			Description = "Unlocks approved civilian rifle items.",
		},
		PublicArmedResponse = {
			Id = "PublicArmedResponse",
			GamepassId = 1933635353,
			Name = "Public Armed Response Division",
			Description = "Unlocks Armed Response in public servers.",
		},
		PublicRoadsPolicing = {
			Id = "PublicRoadsPolicing",
			GamepassId = 1933455264,
			Name = "Public Roads Policing Division",
			Description = "Unlocks Roads Policing in public servers.",
		},
		PublicAmbulanceTeam = {
			Id = "PublicAmbulanceTeam",
			GamepassId = 1934391076,
			Name = "Public Ambulance Team",
			Description = "Unlocks the Ambulance team in public servers.",
		},
		PublicFireTeam = {
			Id = "PublicFireTeam",
			GamepassId = 1934942991,
			Name = "Public Fire & Rescue Team",
			Description = "Unlocks Fire and Rescue in public servers.",
		},
		PublicControlTeam = {
			Id = "PublicControlTeam",
			GamepassId = 1931427656,
			Name = "Public Control Room Team",
			Description = "Unlocks Emergency Control in public servers.",
		},
		PublicTransportTeam = {
			Id = "PublicTransportTeam",
			GamepassId = 1935021036,
			Name = "Public Bus Service Team",
			Description = "Unlocks the Bus Service in public servers.",
		},
		PublicHighwaysTeam = {
			Id = "PublicHighwaysTeam",
			GamepassId = 1933137299,
			Name = "Public Highways Team",
			Description = "Unlocks Highways in public servers.",
		},
		PublicPrisonTeam = {
			Id = "PublicPrisonTeam",
			GamepassId = 1935158990,
			Name = "Public Prison Service Team",
			Description = "Unlocks the Prison Service in public servers.",
		},
	},
	EquipmentPasses = {
		Knife = { GamepassId = 1932205625, TeamName = "Civilian", ToolNames = { "Knife" } },
		Handgun = { GamepassId = 1935362991, TeamName = "Civilian", ToolNames = { "Handgun" } },
		Shotgun = { GamepassId = 1934043075, TeamName = "Civilian", ToolNames = { "Shotgun" } },
		Rifle = { GamepassId = 1933239337, TeamName = "Civilian", ToolNames = { "Rifle" } },
	},
	-- People standing around the map who sell things.
	--
	-- Tag a model with the tag below and give it a RoleplayOSVendorId attribute
	-- naming one of the definitions here. Anything with a PrimaryPart or a
	-- HumanoidRootPart works, so a posed avatar, a shopkeeper rig or a market
	-- stall are all the same thing as far as this is concerned.
	--
	-- Interaction is a ProximityPrompt, which Roblox renders and drives itself on
	-- touch, gamepad and keyboard alike. That matters more than it sounds: a
	-- bespoke click region would have needed separate handling per device and is
	-- exactly the sort of thing that ends up unreachable on a phone.
	Vendors = {
		Tag = "RoleplayOSVendor",
		-- Held to open the stall. Long enough that walking past does not trigger it.
		HoldSeconds = 0.35,
		ActivationDistance = 10,
		-- Re-checked on the server when something is bought, since the client can
		-- claim any distance it likes.
		MaximumPurchaseDistance = 16,
		Definitions = {
			CornerShop = {
				Name = "Corner Shop",
				Subtitle = "Food and drink",
				Items = {
					{ Id = "Water", Kind = "Food", FoodId = "Water" },
					{ Id = "Apple", Kind = "Food", FoodId = "Apple" },
					{ Id = "Meal", Kind = "Food", FoodId = "Meal" },
				},
			},
			-- Cash weapons. Priced against the wage rates, so a handgun is a few
			-- hours of work rather than an afternoon's pocket change.
			StreetDealer = {
				Name = "Dealer",
				Subtitle = "No questions asked",
				Items = {
					{ Id = "Knife", Kind = "Tool", ToolId = "Knife", Name = "Knife", Price = 900 },
					{
						Id = "Handgun",
						Kind = "Tool",
						ToolId = "Handgun",
						Name = "Handgun",
						Price = 7500,
					},
				},
			},
			-- Items carrying both a pass and a price. Owning the pass hands it over
			-- for nothing; everybody else can still buy it with cash. Cash prices
			-- are set high enough that the pass remains worth having.
			LicensedDealer = {
				Name = "Licensed Firearms",
				Subtitle = "Permit holders only",
				Items = {
					{
						Id = "PassShotgun",
						Kind = "Tool",
						ToolId = "Shotgun",
						Name = "Shotgun",
						GamepassId = 1934043075,
						Price = 26000,
					},
					{
						Id = "PassRifle",
						Kind = "Tool",
						ToolId = "Rifle",
						Name = "Rifle",
						GamepassId = 1933239337,
						Price = 42000,
					},
				},
			},
		},
	},
	VehicleIdentity = {
		MinimumRegistrationLength = 2,
		MaximumRegistrationLength = 8,
		PlatePartNames = { "RegistrationPlate", "NumberPlate", "LicencePlate", "LicensePlate" },
	},
	CCTV = {
		CameraTag = "RoleplayOSCCTV",
		MaximumCameras = 64,
		ViewerDepartments = { "Control" },
	},
	ANPR = {
		SensorTag = "RoleplayOSANPR",
		CooldownSeconds = 15,
		MaximumSensors = 128,
		RoadsRoleId = "RoadsPolicingOfficer",
	},
	RoadSafety = {
		SpeedCameraTag = "RoleplayOSSpeedCamera",
		AverageEntryTag = "RoleplayOSAverageSpeedEntry",
		AverageExitTag = "RoleplayOSAverageSpeedExit",
		StudsPerSecondToMph = 0.626,
		ToleranceMph = 2,
		FineBase = 100,
		FinePerMph = 10,
		MaximumFine = 1000,
		PointsByExcess = { { 10, 3 }, { 20, 4 }, { 30, 6 }, { 999, 6 } },
		SensorCooldownSeconds = 8,
		AverageJourneyExpirySeconds = 1800,
		StateCleanupSeconds = 60,
	},
	Custody = {
		BookingDeskTag = "RoleplayOSCustodyDesk",
		CellSpawnTag = "RoleplayOSCustodyCellSpawn",
		VehicleSeatTag = "RoleplayOSCustodySeat",
		MaximumInteractionDistance = 12,
		MaximumBookingDistance = 18,
		MaximumVehicleDistance = 16,
		MaximumReasonLength = 160,
		MaximumSearchGroundsLength = 220,
		MaximumSearchItems = 30,
		MaximumBookingHistory = 40,
		MaximumCriminalRecordHistory = 100,
		MaximumActiveOffences = 16,
		MaximumStackedSentenceSeconds = 1800,
		CuffedWalkSpeed = 8,
		EscortDistance = 3.25,
		EscortMaximumForce = 18000,
		EscortMaximumVelocity = 16,
		SearchPowers = { "PACE_S1", "PACE_S23_MDA", "PACE_S32_POST_ARREST" },
		DisconnectPenaltyCode = "LEAVE_WHILE_RESTRAINED",
		SimulationNotice = "Simplified roleplay simulation — not legal advice or professional training.",
		ArrestCaution = "You do not have to say anything. But it may harm your defence if you do not mention when questioned something which you later rely on in court. Anything you do say may be given in evidence.",
		-- Compressed gameplay tariffs, not real-world sentences. The server adds these values;
		-- clients can only submit an allowlisted Code.
		OffenceTariffs = {
			OTHER = { Name = "Other recorded offence", Seconds = 120 },
			THEFT = { Name = "Theft", Seconds = 180 },
			ASSAULT = { Name = "Assault", Seconds = 240 },
			DANGEROUS_DRIVING = { Name = "Dangerous driving", Seconds = 300 },
			ROBBERY = { Name = "Robbery", Seconds = 420 },
			FIREARMS = { Name = "Firearms offence", Seconds = 480 },
			LEAVE_WHILE_RESTRAINED = {
				Name = "Left the server while restrained",
				Seconds = 180,
			},
		},
	},
	Identification = {
		MaximumPresentationDistance = 12,
		PoliceForceName = "UP Hampshire & Isle of Wight Constabulary",
	},
	UKTime = { Enabled = true, UpdateSeconds = 15 },
	-- Rank ladders. A profile stores its rank as an index into this list, so
	-- ranks may be appended freely but never reordered or removed from the
	-- middle: doing so silently repromotes or demotes everyone above the change.
	--
	-- `Numbered` decides whether the rank wears a shoulder number. In the British
	-- services these are worn by the junior ranks and dropped at the point rank
	-- insignia takes over, which is why an inspector has no collar number. The
	-- number is still kept on the profile when someone is promoted past that
	-- point, so it comes back on demotion rather than being reissued.
	Departments = {
		Police = {
			Id = "Police",
			Name = "Police",
			Ranks = {
				{ Name = "Constable", Abbreviation = "PC", Numbered = true },
				{ Name = "Sergeant", Abbreviation = "PS", Numbered = true },
				{ Name = "Inspector", Abbreviation = "Insp", Numbered = false },
				{ Name = "Chief Inspector", Abbreviation = "Ch Insp", Numbered = false },
				{ Name = "Superintendent", Abbreviation = "Supt", Numbered = false },
				{ Name = "Chief Superintendent", Abbreviation = "Ch Supt", Numbered = false },
				{ Name = "Assistant Chief Constable", Abbreviation = "ACC", Numbered = false },
				{ Name = "Deputy Chief Constable", Abbreviation = "DCC", Numbered = false },
				{ Name = "Chief Constable", Abbreviation = "CC", Numbered = false },
			},
			RoleIds = {
				"PoliceOfficer",
				"PoliceFrontline",
				"ArmedResponseOfficer",
				"RoadsPolicingOfficer",
			},
		},
		Ambulance = {
			Id = "Ambulance",
			Name = "Ambulance",
			Ranks = {
				{ Name = "Emergency Care Assistant", Abbreviation = "ECA", Numbered = true },
				{
					Name = "Associate Ambulance Practitioner",
					Abbreviation = "AAP",
					Numbered = true,
				},
				{ Name = "Technician", Abbreviation = "Tech", Numbered = true },
				{ Name = "Paramedic", Abbreviation = "Para", Numbered = true },
				{ Name = "Senior Paramedic", Abbreviation = "Sen Para", Numbered = true },
				{ Name = "Clinical Team Leader", Abbreviation = "CTL", Numbered = true },
				{ Name = "Operations Manager", Abbreviation = "Ops Mgr", Numbered = false },
				{ Name = "Head of Operations", Abbreviation = "Head of Ops", Numbered = false },
			},
			RoleIds = { "Paramedic" },
		},
		Fire = {
			Id = "Fire",
			Name = "Fire and Rescue",
			Ranks = {
				{ Name = "Firefighter", Abbreviation = "FF", Numbered = true },
				{ Name = "Crew Manager", Abbreviation = "CM", Numbered = true },
				{ Name = "Watch Manager", Abbreviation = "WM", Numbered = true },
				{ Name = "Station Manager", Abbreviation = "SM", Numbered = false },
				{ Name = "Group Manager", Abbreviation = "GM", Numbered = false },
				{ Name = "Area Manager", Abbreviation = "AM", Numbered = false },
				{ Name = "Deputy Chief Fire Officer", Abbreviation = "DCFO", Numbered = false },
				{ Name = "Chief Fire Officer", Abbreviation = "CFO", Numbered = false },
			},
			RoleIds = { "Firefighter" },
		},
		Control = {
			Id = "Control",
			Name = "Dispatch and Control",
			Ranks = {
				{ Name = "Call Handler", Abbreviation = "CH", Numbered = true },
				{ Name = "Dispatcher", Abbreviation = "Disp", Numbered = true },
				{ Name = "Senior Dispatcher", Abbreviation = "Sen Disp", Numbered = true },
				{ Name = "Control Room Supervisor", Abbreviation = "Sup", Numbered = false },
				{ Name = "Control Room Manager", Abbreviation = "Mgr", Numbered = false },
			},
			RoleIds = { "Controller" },
		},
		Transport = {
			Id = "Transport",
			Name = "Transport",
			Ranks = {
				{ Name = "Driver", Abbreviation = "Drv", Numbered = true },
				{ Name = "Senior Driver", Abbreviation = "Sen Drv", Numbered = true },
				{ Name = "Supervisor", Abbreviation = "Sup", Numbered = false },
				{ Name = "Operations Manager", Abbreviation = "Ops Mgr", Numbered = false },
			},
			RoleIds = { "TransportOperator" },
		},
		Highways = {
			Id = "Highways",
			Name = "Highway Patrol",
			Ranks = {
				{ Name = "Traffic Officer", Abbreviation = "TO", Numbered = true },
				{ Name = "Senior Traffic Officer", Abbreviation = "STO", Numbered = true },
				{ Name = "Team Manager", Abbreviation = "TM", Numbered = false },
				{ Name = "Operations Manager", Abbreviation = "Ops Mgr", Numbered = false },
			},
			RoleIds = { "HighwayPatrolOfficer" },
		},
		Prison = {
			Id = "Prison",
			Name = "Prison Service",
			Ranks = {
				{ Name = "Prison Officer", Abbreviation = "PO", Numbered = true },
				{ Name = "Senior Officer", Abbreviation = "SO", Numbered = true },
				{ Name = "Principal Officer", Abbreviation = "PrO", Numbered = true },
				{ Name = "Custodial Manager", Abbreviation = "CM", Numbered = false },
				{ Name = "Governor", Abbreviation = "Gov", Numbered = false },
			},
			RoleIds = { "PrisonOfficer" },
		},
	},
	-- Shoulder numbers are issued from a counter held per department, so two
	-- servers claiming at the same moment cannot land on the same number and no
	-- scan of existing holders is needed to find the next free one. Numbers are
	-- never reissued: a counter that only moves forward means a number identifies
	-- one person for the lifetime of the game, which is the whole point of
	-- putting it in a Discord name.
	ShoulderNumbers = {
		Enabled = true,
		Format = "%04d",
		-- Each service starts its own block, so the number alone reads as
		-- belonging to that service.
		Start = {
			Police = 1000,
			Ambulance = 3000,
			Fire = 5000,
			Control = 7000,
			Transport = 7500,
			Highways = 8000,
			Prison = 9000,
		},
		DefaultStart = 100,
	},
	Teams = {
		Civilian = {
			Id = "Civilian",
			Name = "Civilian",
			BrickColor = "Medium stone grey",
			AutoAssignable = true,
		},
		Police = {
			Id = "Police",
			Name = "Police",
			BrickColor = "Navy blue",
			AutoAssignable = false,
		},
		Ambulance = {
			Id = "Ambulance",
			Name = "Ambulance",
			BrickColor = "Earth green",
			AutoAssignable = false,
		},
		Fire = { Id = "Fire", Name = "Fire", BrickColor = "Bright red", AutoAssignable = false },
		Control = {
			Id = "Control",
			Name = "Control",
			BrickColor = "Really black",
			AutoAssignable = false,
		},
		Transport = {
			Id = "Transport",
			Name = "Transport",
			BrickColor = "New Yeller",
			AutoAssignable = false,
		},
		Highways = {
			Id = "Highways",
			Name = "Highway Patrol",
			BrickColor = "Dark green",
			AutoAssignable = false,
		},
		Prison = {
			Id = "Prison",
			Name = "Prison Service",
			BrickColor = "Dark orange",
			AutoAssignable = false,
		},
	},
	GroupLinks = {
		UniversalProjects = {
			Id = "UniversalProjects",
			GroupId = 33809042,
			MinimumRank = 1,
			DisplayName = "Universal Projects",
		},
		Police = {
			Id = "Police",
			GroupId = 34720334,
			MinimumRank = 1,
			DisplayName = "UP Hampshire & Isle of Wight Constabulary",
		},
		ArmedResponse = {
			Id = "ArmedResponse",
			GroupId = 16985274,
			MinimumRank = 1,
			DisplayName = "UP Armed Response Unit",
		},
		RoadsPolicing = {
			Id = "RoadsPolicing",
			GroupId = 33815770,
			MinimumRank = 1,
			DisplayName = "UP Constabulary Divisional Hub",
		},
		Ambulance = {
			Id = "Ambulance",
			GroupId = 33840360,
			MinimumRank = 1,
			DisplayName = "UP East of England Ambulance",
		},
		Fire = {
			Id = "Fire",
			GroupId = 14293067,
			MinimumRank = 1,
			DisplayName = "UP Norfolk Fire and Rescue Service",
		},
		Control = {
			Id = "Control",
			GroupId = 33809042,
			MinimumRank = 1,
			DisplayName = "Universal Projects (temporary Control link)",
		},
		Transport = {
			Id = "Transport",
			GroupId = 33360488,
			MinimumRank = 1,
			DisplayName = "UK RP Linc Transit",
		},
		Highways = {
			Id = "Highways",
			GroupId = 34022475,
			MinimumRank = 1,
			DisplayName = "MPS Training Grounds (Highway Patrol)",
		},
		Prison = {
			Id = "Prison",
			GroupId = 16361786,
			MinimumRank = 1,
			DisplayName = "Ministry of Justice HMCTS",
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
			Access = publicOr({
				AccessType = "Group",
				GroupLinkId = "Police",
				MinimumGroupRank = 1,
			}),
			LoadoutId = "PoliceResponse",
			UniformId = "PoliceStandard",
		},
		PoliceFrontline = {
			Id = "PoliceFrontline",
			Name = "Frontline Policing",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "Frontline",
			Access = publicOr({
				AccessType = "Group",
				GroupLinkId = "Police",
				MinimumGroupRank = 1,
			}),
			LoadoutId = "PoliceFrontline",
			UniformId = "PoliceStandard",
		},
		ArmedResponseOfficer = {
			Id = "ArmedResponseOfficer",
			Name = "Armed Response Unit",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "ArmedResponse",
			Access = publicPassOr({
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
					{ AccessType = "Group", GroupLinkId = "ArmedResponse", MinimumGroupRank = 1 },
				},
			}, 1933635353),
			LoadoutId = "ArmedResponse",
			UniformId = "PoliceStandard",
		},
		RoadsPolicingOfficer = {
			Id = "RoadsPolicingOfficer",
			Name = "Roads Policing Unit",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "RoadsPolicing",
			Access = publicPassOr({
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
					{ AccessType = "Group", GroupLinkId = "RoadsPolicing", MinimumGroupRank = 1 },
				},
			}, 1933455264),
			LoadoutId = "RoadsPolicing",
			UniformId = "PoliceStandard",
		},
		Paramedic = {
			Id = "Paramedic",
			Name = "Paramedic",
			TeamName = "Ambulance",
			DepartmentId = "Ambulance",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Ambulance", MinimumGroupRank = 1 },
				1934391076
			),
			LoadoutId = "AmbulanceStandard",
			UniformId = "AmbulanceStandard",
		},
		Firefighter = {
			Id = "Firefighter",
			Name = "Firefighter",
			TeamName = "Fire",
			DepartmentId = "Fire",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Fire", MinimumGroupRank = 1 },
				1934942991
			),
			LoadoutId = "FireStandard",
			UniformId = "FireStandard",
		},
		Controller = {
			Id = "Controller",
			Name = "Emergency Control",
			TeamName = "Control",
			DepartmentId = "Control",
			Access = publicPassOr({
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "Application", DepartmentId = "Control" },
					{ AccessType = "Group", GroupLinkId = "Control", MinimumGroupRank = 1 },
				},
			}, 1931427656),
			LoadoutId = "ControlStandard",
		},
		TransportOperator = {
			Id = "TransportOperator",
			Name = "Bus Service",
			TeamName = "Transport",
			DepartmentId = "Transport",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Transport", MinimumGroupRank = 1 },
				1935021036
			),
			LoadoutId = "TransportStandard",
			UniformId = "TransportStandard",
		},
		HighwayPatrolOfficer = {
			Id = "HighwayPatrolOfficer",
			Name = "Highway Patrol",
			TeamName = "Highways",
			DepartmentId = "Highways",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Highways", MinimumGroupRank = 1 },
				1933137299
			),
			LoadoutId = "HighwaysStandard",
			UniformId = "HighwaysStandard",
		},
		PrisonOfficer = {
			Id = "PrisonOfficer",
			Name = "Prison Service",
			TeamName = "Prison",
			DepartmentId = "Prison",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Prison", MinimumGroupRank = 1 },
				1935158990
			),
			LoadoutId = "PrisonStandard",
			UniformId = "PrisonStandard",
		},
	},
	Stations = {
		CityCentre = {
			Id = "CityCentre",
			Name = "City Centre",
			DepartmentIds = {
				"Police",
				"Ambulance",
				"Fire",
				"Control",
				"Transport",
				"Highways",
				"Prison",
			},
			SpawnIds = {
				"CityCivilian",
				"PoliceLockerRoom",
				"PoliceVehicleBay",
				"AmbulanceLockerRoom",
				"FireLockerRoom",
				"ControlRoom",
				"TransportDepot",
				"HighwaysDepot",
				"PrisonStaff",
			},
		},
	},
	Spawns = {
		CityCivilian = {
			Id = "CityCivilian",
			StationId = "CityCentre",
			TeamName = "Civilian",
			RoleIds = { "Civilian" },
			DepartmentIds = {},
		},
		PoliceLockerRoom = {
			Id = "PoliceLockerRoom",
			StationId = "CityCentre",
			TeamName = "Police",
			RoleIds = {
				"PoliceOfficer",
				"PoliceFrontline",
				"ArmedResponseOfficer",
				"RoadsPolicingOfficer",
			},
			DepartmentIds = { "Police" },
		},
		PoliceVehicleBay = {
			Id = "PoliceVehicleBay",
			StationId = "CityCentre",
			TeamName = "Police",
			RoleIds = { "PoliceFrontline", "ArmedResponseOfficer", "RoadsPolicingOfficer" },
			DepartmentIds = { "Police" },
		},
		AmbulanceLockerRoom = {
			Id = "AmbulanceLockerRoom",
			StationId = "CityCentre",
			TeamName = "Ambulance",
			RoleIds = { "Paramedic" },
			DepartmentIds = { "Ambulance" },
		},
		FireLockerRoom = {
			Id = "FireLockerRoom",
			StationId = "CityCentre",
			TeamName = "Fire",
			RoleIds = { "Firefighter" },
			DepartmentIds = { "Fire" },
		},
		ControlRoom = {
			Id = "ControlRoom",
			StationId = "CityCentre",
			TeamName = "Control",
			RoleIds = { "Controller" },
			DepartmentIds = { "Control" },
		},
		TransportDepot = {
			Id = "TransportDepot",
			StationId = "CityCentre",
			TeamName = "Transport",
			RoleIds = { "TransportOperator" },
			DepartmentIds = { "Transport" },
		},
		HighwaysDepot = {
			Id = "HighwaysDepot",
			StationId = "CityCentre",
			TeamName = "Highways",
			RoleIds = { "HighwayPatrolOfficer" },
			DepartmentIds = { "Highways" },
		},
		PrisonStaff = {
			Id = "PrisonStaff",
			StationId = "CityCentre",
			TeamName = "Prison",
			RoleIds = { "PrisonOfficer" },
			DepartmentIds = { "Prison" },
		},
	},
	Uniforms = {
		PoliceStandard = { Id = "PoliceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		AmbulanceStandard = { Id = "AmbulanceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		FireStandard = { Id = "FireStandard", ShirtTemplate = "", TrousersTemplate = "" },
		TransportStandard = { Id = "TransportStandard", ShirtTemplate = "", TrousersTemplate = "" },
		HighwaysStandard = { Id = "HighwaysStandard", ShirtTemplate = "", TrousersTemplate = "" },
		PrisonStandard = { Id = "PrisonStandard", ShirtTemplate = "", TrousersTemplate = "" },
	},
	Divisions = {
		Frontline = { Id = "Frontline", DepartmentId = "Police", Name = "Frontline Policing" },
		ArmedResponse = { Id = "ArmedResponse", DepartmentId = "Police", Name = "Armed Response" },
		RoadsPolicing = { Id = "RoadsPolicing", DepartmentId = "Police", Name = "Roads Policing" },
	},
	Tools = {
		Radio = { Id = "Radio", AssetPath = { "Tools", "Shared", "Radio" } },
		Notebook = { Id = "Notebook", AssetPath = { "Tools", "Shared", "Notebook" } },
		Handcuffs = {
			Id = "Handcuffs",
			AssetPath = { "Tools", "Services", "Police", "Shared", "Handcuffs" },
			DepartmentId = "Police",
		},
		MedicalBag = {
			Id = "MedicalBag",
			AssetPath = { "Tools", "Services", "Ambulance", "MedicalBag" },
			DepartmentId = "Ambulance",
		},
	},
	Loadouts = {
		PoliceResponse = { Id = "PoliceResponse", ToolIds = { "Radio", "Handcuffs" } },
		PoliceFrontline = {
			Id = "PoliceFrontline",
			ToolIds = { "Radio", "Notebook", "Handcuffs" },
		},
		ArmedResponse = { Id = "ArmedResponse", ToolIds = { "Radio", "Notebook", "Handcuffs" } },
		RoadsPolicing = { Id = "RoadsPolicing", ToolIds = { "Radio", "Notebook", "Handcuffs" } },
		AmbulanceStandard = { Id = "AmbulanceStandard", ToolIds = { "Radio", "MedicalBag" } },
		FireStandard = { Id = "FireStandard", ToolIds = { "Radio" } },
		ControlStandard = { Id = "ControlStandard", ToolIds = { "Radio" } },
		TransportStandard = { Id = "TransportStandard", ToolIds = { "Radio" } },
		HighwaysStandard = { Id = "HighwaysStandard", ToolIds = { "Radio", "Notebook" } },
		PrisonStandard = { Id = "PrisonStandard", ToolIds = { "Radio", "Notebook" } },
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
			AssetPath = { "Vehicles", "Civilian", "Starter", "Compact" },
			Colours = { "Black", "Blue", "White" },
			Access = { AccessType = "Public" },
			Category = "Civilian",
			Starter = true,
		},
		PremiumSaloon = {
			Id = "PremiumSaloon",
			Name = "Premium saloon",
			Price = 45000,
			ModelName = "PremiumSaloon",
			AssetPath = { "Vehicles", "Civilian", "Premium", "PremiumSaloon" },
			Colours = { "Black", "Silver" },
			Access = {
				AccessType = "Gamepass",
				Id = "PremiumVehicles",
				GamepassId = 1935128985,
				DisplayWhenLocked = true,
			},
			Category = "Civilian",
		},
		PoliceResponse = {
			Id = "PoliceResponse",
			Name = "Marked response car",
			Price = 0,
			ModelName = "PoliceResponse",
			AssetPath = { "Vehicles", "Services", "Police", "Frontline", "PoliceResponse" },
			Colours = { "Police" },
			Category = "Service",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "Frontline",
			RoleIds = {
				"PoliceOfficer",
				"PoliceFrontline",
				"ArmedResponseOfficer",
				"RoadsPolicingOfficer",
			},
			Access = publicOr({
				AccessType = "Group",
				GroupLinkId = "Police",
				MinimumGroupRank = 1,
			}),
		},
		ArmedResponseSUV = {
			Id = "ArmedResponseSUV",
			Name = "Armed response SUV",
			Price = 0,
			ModelName = "ArmedResponseSUV",
			AssetPath = { "Vehicles", "Services", "Police", "ArmedResponse", "ArmedResponseSUV" },
			DivisionId = "ArmedResponse",
			Colours = { "Police" },
			Category = "Service",
			TeamName = "Police",
			DepartmentId = "Police",
			RoleIds = { "ArmedResponseOfficer" },
			Access = publicPassOr({
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
					{
						AccessType = "Group",
						GroupLinkId = "ArmedResponse",
						MinimumGroupRank = 1,
					},
				},
			}, 1933635353),
		},
		RoadsPolicingEstate = {
			Id = "RoadsPolicingEstate",
			Name = "Roads policing estate",
			Price = 0,
			ModelName = "RoadsPolicingEstate",
			AssetPath = { "Vehicles", "Services", "Police", "RoadsPolicing", "RoadsPolicingEstate" },
			DivisionId = "RoadsPolicing",
			Colours = { "Police" },
			Category = "Service",
			TeamName = "Police",
			DepartmentId = "Police",
			RoleIds = { "RoadsPolicingOfficer" },
			Access = publicPassOr({
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
					{
						AccessType = "Group",
						GroupLinkId = "RoadsPolicing",
						MinimumGroupRank = 1,
					},
				},
			}, 1933455264),
		},
		AmbulanceResponse = {
			Id = "AmbulanceResponse",
			Name = "Ambulance response car",
			Price = 0,
			ModelName = "AmbulanceResponse",
			AssetPath = { "Vehicles", "Services", "Ambulance", "AmbulanceResponse" },
			Colours = { "Ambulance" },
			Category = "Service",
			TeamName = "Ambulance",
			DepartmentId = "Ambulance",
			RoleIds = { "Paramedic" },
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Ambulance", MinimumGroupRank = 1 },
				1934391076
			),
		},
		FireEngine = {
			Id = "FireEngine",
			Name = "Fire engine",
			Price = 0,
			ModelName = "FireEngine",
			AssetPath = { "Vehicles", "Services", "Fire", "FireEngine" },
			Colours = { "Fire" },
			Category = "Service",
			TeamName = "Fire",
			DepartmentId = "Fire",
			RoleIds = { "Firefighter" },
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Fire", MinimumGroupRank = 1 },
				1934942991
			),
		},
		ServiceBus = {
			Id = "ServiceBus",
			Name = "Service bus",
			Price = 0,
			ModelName = "ServiceBus",
			AssetPath = { "Vehicles", "Services", "Transport", "ServiceBus" },
			Colours = { "Operator" },
			Category = "Service",
			TeamName = "Transport",
			DepartmentId = "Transport",
			RoleIds = { "TransportOperator" },
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Transport", MinimumGroupRank = 1 },
				1935021036
			),
		},
		HighwaysPatrol = {
			Id = "HighwaysPatrol",
			Name = "Highways patrol vehicle",
			Price = 0,
			ModelName = "HighwaysPatrol",
			AssetPath = { "Vehicles", "Services", "Highways", "HighwaysPatrol" },
			Colours = { "Highways" },
			Category = "Service",
			TeamName = "Highways",
			DepartmentId = "Highways",
			RoleIds = { "HighwayPatrolOfficer" },
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Highways", MinimumGroupRank = 1 },
				1933137299
			),
		},
		PrisonTransport = {
			Id = "PrisonTransport",
			Name = "Prison transport van",
			Price = 0,
			ModelName = "PrisonTransport",
			AssetPath = { "Vehicles", "Services", "Prison", "PrisonTransport" },
			Colours = { "Prison" },
			Category = "Service",
			TeamName = "Prison",
			DepartmentId = "Prison",
			RoleIds = { "PrisonOfficer" },
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Prison", MinimumGroupRank = 1 },
				1935158990
			),
		},
	},
	Spawning = {
		-- Tag applied to the SpawnLocation pads the framework manages. Tagging
		-- lets startup ask for the pads directly; without it every descendant of
		-- the workspace is walked, which blocks startup on a large map.
		PadTag = "RoleplayOSSpawnPad",
	},
	-- Vehicles are driven by a third-party chassis. RoleplayOS presents the
	-- readouts itself so they match the rest of the interface, scale with the
	-- device and respect the safe area, which a chassis's own interface does not.
	DrivingControls = {
		Enabled = true,
		-- Accelerator size in pixels before the interface scale is applied. The
		-- brake is drawn shorter above it, as a pedal pair rather than two equal
		-- buttons.
		PedalSize = 92,
		-- A pedal held this long with the vehicle still stationary means the
		-- chassis reads its input somewhere the pedals do not reach.
		NoResponseSeconds = 2.5,
	},
	Chassis = {
		-- Interfaces cloned into PlayerGui by the chassis, disabled on sight so
		-- two sets of gauges are never on screen at once. Names differ between
		-- A-Chassis forks, so check what actually appears in PlayerGui while
		-- seated and add it here rather than assuming this list is complete.
		SuppressGuiNames = {
			"A-Chassis Interface",
			"AC6_Interface",
			"ACGUI",
			"Gauges",
			"GaugesGUI",
		},
		-- Where the chassis publishes its live values, searched under the seat
		-- and then the vehicle model. Fuel is deliberately not read from here:
		-- RoleplayOS owns fuel on the server, and a client value could not be
		-- trusted anyway.
		ValuesFolderName = "Values",
		GearValueName = "Gear",
		-- Written as well as the seat's own throttle, so a chassis that keeps its
		-- input in this folder is driven without needing to know which fork it is.
		ThrottleValueName = "Throttle",
		-- Engine speed the sweep treats as full. Used only for the display.
		Redline = 8000,
		-- Road speed the sweep treats as full where no engine speed is reported.
		TopSpeedMph = 150,
		-- Segments in the cluster sweep. Roblox has no arc primitive, so the
		-- sweep is a bar of discrete segments.
		SweepSegments = 22,
		RpmValueName = "RPM",
	},
	VehicleSpawning = {
		TerminalTag = "RoleplayOSVehicleTerminal",
		SpawnPointTag = "RoleplayOSVehicleSpawn",
		MaximumInteractionDistance = 14,
		MaximumSpawnDistance = 160,
		SpawnClearance = { 14, 8, 24 },
		SpawnCooldownSeconds = 8,
		PromptHoldDuration = 0.35,
		TrackingIntervalSeconds = 1,
		-- Preview models held for one player while browsing a depot. Each is a
		-- copy of a real vehicle, so this bounds what a player accumulates
		-- scrolling a large fleet.
		MaximumPreviewsPerPlayer = 6,
		StudsToMiles = 0.000173984,
		MaximumTrackedSpeedStudsPerSecond = 350,
		FuelPercentPerMile = 0.2,
		IdleFuelPercentPerMinute = 0.04,
		PersistenceIntervalSeconds = 30,
		StopVehicleWhenFuelEmpty = true,
		StarterDefinitionId = "Compact",
		StarterColour = "Blue",
		StarterGarageId = "CityGarage",
	},
	Dealerships = {
		CityMotors = {
			Id = "CityMotors",
			Name = "City Motors",
			-- Named here, and appended to automatically for any civilian model
			-- whose DealershipId attribute points at this forecourt.
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
		MaximumIndexBucketEntries = 5000,
		RecordCacheSeconds = 60,
		IndexWriteSpacingSeconds = 0.25,
		MaximumWarrantReasonLength = 160,
		MaximumWarrantDurationDays = 365,
		MaximumIncidentIndexEntries = 2000,
		AllowedDepartments = { "Police", "Ambulance", "Fire", "Control", "Highways", "Prison" },
		PermissionByDepartment = {
			Police = {
				"PersonSearch",
				"VehicleSearch",
				"IncidentWrite",
				"WarrantRead",
				"WarrantWrite",
			},
			Ambulance = { "PersonSearch", "IncidentRead" },
			Fire = { "PersonSearch", "IncidentRead" },
			Control = { "PersonSearch", "VehicleSearch", "IncidentRead", "Dispatch" },
			Highways = { "PersonSearch", "VehicleSearch", "IncidentWrite" },
			Prison = { "PersonSearch", "WarrantRead" },
		},
	},
	Dispatch = {
		SeatTag = "RoleplayOSDispatchSeat",
		DispatcherDepartments = { "Control" },
		UnitStatuses = { "Available", "Assigned", "OnScene", "Unavailable" },
		CallPriorities = { "Immediate", "Prompt", "Routine" },
		IncidentTypes = {
			"Emergency",
			"Crime in progress",
			"Road traffic collision",
			"Medical",
			"Fire",
			"Public assistance",
			"Prison incident",
			"Transport incident",
		},
		DefaultDepartmentsByIncidentType = {
			Emergency = { "Police", "Ambulance", "Fire", "Control" },
			["Crime in progress"] = { "Police", "Control" },
			["Road traffic collision"] = { "Police", "Ambulance", "Highways", "Control" },
			Medical = { "Ambulance", "Control" },
			Fire = { "Fire", "Ambulance", "Control" },
			["Public assistance"] = { "Police", "Control" },
			["Prison incident"] = { "Prison", "Police", "Control" },
			["Transport incident"] = { "Transport", "Police", "Control" },
		},
		CallStatuses = { "Open", "Assigned", "OnScene" },
		ActiveStateTtlSeconds = 300,
	},
	EmergencyTriggers = {
		Tag = "RoleplayOSEmergencyTrigger",
		MaximumActivationDistance = 18,
		PlayerCooldownSeconds = 3,
		Incidents = {
			BankRobbery = {
				Summary = "Bank robbery alarm",
				Priority = "Immediate",
				Departments = { "Police", "Control" },
				CooldownSeconds = 180,
			},
			ATMRobbery = {
				Summary = "ATM tamper alarm",
				Priority = "Prompt",
				Departments = { "Police", "Control" },
				CooldownSeconds = 90,
			},
			FireAlarm = {
				Summary = "Automatic fire alarm",
				Priority = "Immediate",
				Departments = { "Fire", "Control", "Ambulance" },
				CooldownSeconds = 120,
			},
			MedicalPanic = {
				Summary = "Emergency medical panic alarm",
				Priority = "Immediate",
				Departments = { "Ambulance", "Control" },
				CooldownSeconds = 60,
			},
		},
	},
	Phone = {
		Enabled = true,
		MaximumMessageLength = 240,
		MaximumMessages = 200,
		EmergencyNumber = "999",
	},
	Needs = {
		WalkSpeed = 16,
		MinimumSprintSpeed = 18,
		MaximumSprintSpeed = 24,
		StaminaDrainPerSecond = 14,
		StaminaRecoveryPerSecond = 10,
		HungerDrainPerSecond = 0.04,
		Foods = {
			Water = { Name = "Water", Price = 4, Hunger = 4 },
			Apple = { Name = "Apple", Price = 6, Hunger = 12 },
			Meal = { Name = "Hot meal", Price = 18, Hunger = 40 },
		},
	},
	Network = {
		MaximumPayloadBytes = 8192,
		MaximumDepth = 8,
		MaximumNodes = 256,
		MaximumStringBytes = 2048,
		MaximumConcurrentRequests = 4,
		-- A request still running after this long is presumed lost and stops
		-- occupying a concurrency slot, so one stuck handler cannot refuse every
		-- later request from that player for the rest of the session.
		RequestAbandonSeconds = 30,
		GlobalCapacity = 30,
		GlobalRefillPerSecond = 10,
		Endpoints = {
			GetFrameworkStatus = { Capacity = 4, RefillPerSecond = 1 },
			-- Reads every loaded profile in the server, so it is deliberately
			-- slower to refill than a lookup a player would repeat.
			GetShoulderNumberRoster = { Capacity = 3, RefillPerSecond = 0.2 },
			CreatePrivateCommunity = { Capacity = 1, RefillPerSecond = 0.02 },
			GetStartMenu = { Capacity = 4, RefillPerSecond = 1 },
			GetSettings = { Capacity = 4, RefillPerSecond = 1 },
			GetProgression = { Capacity = 4, RefillPerSecond = 1 },
			GetPublicProgressionHud = { Capacity = 4, RefillPerSecond = 1 },
			UpdateSettings = { Capacity = 6, RefillPerSecond = 1 },
			CreateCharacter = { Capacity = 2, RefillPerSecond = 0.1 },
			SelectCharacter = { Capacity = 3, RefillPerSecond = 0.5 },
			SubmitApplication = { Capacity = 1, RefillPerSecond = 0.02 },
			MDTSearch = { Capacity = 5, RefillPerSecond = 0.5 },
			MDTCreateWarrant = { Capacity = 2, RefillPerSecond = 0.05 },
			MDTRevokeWarrant = { Capacity = 2, RefillPerSecond = 0.05 },
			MDTGetIncidents = { Capacity = 4, RefillPerSecond = 0.25 },
			GetMDTAccess = { Capacity = 4, RefillPerSecond = 1 },
			GetDispatchSnapshot = { Capacity = 6, RefillPerSecond = 1 },
			DispatchCreateCall = { Capacity = 4, RefillPerSecond = 0.5 },
			DispatchUpdateCall = { Capacity = 6, RefillPerSecond = 1 },
			DispatchAssignUnit = { Capacity = 8, RefillPerSecond = 1 },
			DispatchCloseCall = { Capacity = 4, RefillPerSecond = 0.5 },
			DispatchSetUnitStatus = { Capacity = 6, RefillPerSecond = 1 },
			SetCustomRegistration = { Capacity = 2, RefillPerSecond = 0.05 },
			GetCCTVCameras = { Capacity = 4, RefillPerSecond = 0.5 },
			GetOwnedVehicles = { Capacity = 4, RefillPerSecond = 0.5 },
			GetVehicleSpawnMenu = { Capacity = 4, RefillPerSecond = 0.75 },
			-- Browsing a large depot legitimately requests many previews in
			-- succession, so this is more generous than a purchase endpoint.
			RequestVehiclePreview = { Capacity = 12, RefillPerSecond = 4 },
			SpawnOwnedVehicle = { Capacity = 2, RefillPerSecond = 0.15 },
			PurchaseVehicle = { Capacity = 2, RefillPerSecond = 0.08 },
			SpawnServiceVehicle = { Capacity = 2, RefillPerSecond = 0.15 },
			CuffPlayer = { Capacity = 3, RefillPerSecond = 0.3 },
			CustodyAction = { Capacity = 5, RefillPerSecond = 0.75 },
			GetCustodyPolicy = { Capacity = 3, RefillPerSecond = 0.2 },
			BookCustody = { Capacity = 2, RefillPerSecond = 0.1 },
			GetPresentedId = { Capacity = 4, RefillPerSecond = 0.5 },
			GetPhone = { Capacity = 5, RefillPerSecond = 1 },
			PhoneSendText = { Capacity = 5, RefillPerSecond = 0.5 },
			PhonePlaceCall = { Capacity = 3, RefillPerSecond = 0.25 },
			PhoneAnswerCall = { Capacity = 3, RefillPerSecond = 0.5 },
			PhoneEndCall = { Capacity = 4, RefillPerSecond = 1 },
			PhoneEmergency = { Capacity = 2, RefillPerSecond = 0.1 },
			PhoneToggleFlashlight = { Capacity = 4, RefillPerSecond = 2 },
			-- Every sprint is two calls, one on press and one on release, and
			-- players tap this far more often than any other control.
			SetSprintState = { Capacity = 20, RefillPerSecond = 8 },
			PurchaseFood = { Capacity = 2, RefillPerSecond = 0.25 },
			PurchaseFromVendor = { Capacity = 3, RefillPerSecond = 0.3 },
			GetDealershipCatalogue = { Capacity = 4, RefillPerSecond = 0.5 },
			GetOfficialServers = { Capacity = 4, RefillPerSecond = 0.5 },
			-- A teleport is one action a player takes deliberately, never repeatedly.
			JoinOfficialServer = { Capacity = 2, RefillPerSecond = 0.1 },
			BeginDuty = { Capacity = 2, RefillPerSecond = 0.2 },
			EnterCivilian = { Capacity = 2, RefillPerSecond = 0.2 },
		},
	},
}

return table.freeze(Config)
