--!strict

-- Everywhere that is not the published place. Written out rather than negated,
-- because the evaluator has no negation and the list is short and explicit.
local ELSEWHERE = { "Whitelisted", "Private", "Reserved" }

-- An emergency role, gated differently in each tier.
--
-- On the public place the gamepass is the only way in. Being in the service's
-- Roblox group grants nothing there: the group is how the whitelisted community
-- is staffed, and letting it through on the public place gave every member of
-- it the paid teams for nothing.
--
-- Everywhere else the group is the only way in, and the gamepass grants
-- nothing. Those are worlds people applied to be part of, and a purchase is not
-- an application.
local function publicPassOr(existingRule: any, gamepassId: number): any
	return {
		AccessType = "Combined",
		Match = "Any",
		DisplayWhenLocked = true,
		Rules = {
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kind = "Public" },
					{ AccessType = "Gamepass", GamepassId = gamepassId },
				},
			},
			{
				AccessType = "Combined",
				Match = "All",
				Rules = {
					{ AccessType = "ServerKind", Kinds = ELSEWHERE },
					existingRule,
				},
			},
		},
	}
end

local Config = {
	Framework = {
		Environment = "Development",
		SchemaVersion = 9,
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
		-- Cameras issue fines unattended, so this is the history most able to grow
		-- without anybody choosing to add to it.
		MaximumDrivingFines = 80,
		MaximumEmploymentHistory = 40,
	},
	AssetPreload = {
		Critical = {},
		-- The start screen is the first interaction, so its role artwork should
		-- be ready before the cards are displayed instead of arriving as blank
		-- panels while Roblox fetches each image.
		Background = {
			"rbxthumb://type=Asset&id=124510305332365&w=768&h=768", -- Police
			"rbxthumb://type=Asset&id=115689835891137&w=768&h=768", -- Ambulance
			"rbxthumb://type=Asset&id=95977486831570&w=768&h=768", -- Firefighter
			"rbxthumb://type=Asset&id=113064266300926&w=768&h=768", -- Civilian
			"rbxthumb://type=Asset&id=133420507327997&w=768&h=768", -- Highways / council worker
			"rbxthumb://type=Asset&id=102874702573163&w=768&h=768", -- Transport
			"rbxthumb://type=Asset&id=88863810610980&w=768&h=768", -- Royalty Mail
			"rbxthumb://type=Asset&id=127971383421481&w=768&h=768",
			"rbxthumb://type=Asset&id=101846745500511&w=768&h=768",
		},
	},
	ContentQuality = {
		RequireCertification = true,
		CertificationVersion = 1,
		-- Provenance for reviewed binary assets whose attributes cannot be
		-- retained reliably through Rojo. Runtime class and script checks still
		-- apply; entries here certify only the exact configured asset ID.
		CertifiedAssets = {
			Handcuffs = {
				Certified = true,
				ReviewVersion = 1,
				Source = "User-supplied HandcuffSystem package",
				RealWorldReference = "UK police rigid handcuffs",
				ReviewedBy = "RoleplayOS engineering security review",
			},
			Taser = {
				Certified = true,
				ReviewVersion = 1,
				Source = "User-supplied ACS taser package with RoleplayOS replacement logic",
				RealWorldReference = "UK police conducted-energy device",
				ReviewedBy = "RoleplayOS engineering security review",
				-- Executable descendants remain forbidden unless both their name and
				-- class match this reviewed manifest. This keeps arbitrary scripts in
				-- imported tools fatal while allowing the audited replacement logic.
				AllowedUnsafeDescendants = {
					RoleplayOSTaserServer = {
						ClassName = "Script",
						Path = { "RoleplayOSTaserServer" },
					},
					RoleplayOSTaserClient = {
						ClassName = "LocalScript",
						Path = { "RoleplayOSTaserClient" },
					},
					UpdateAmmo = { ClassName = "RemoteEvent", Path = { "UpdateAmmo" } },
					Reload = { ClassName = "RemoteEvent", Path = { "Reload" } },
					Laser = { ClassName = "RemoteEvent", Path = { "Laser" } },
					Flashlight = { ClassName = "RemoteEvent", Path = { "Flashlight" } },
					FireTaser = { ClassName = "RemoteEvent", Path = { "FireTaser" } },
				},
			},
			PAVA = {
				Certified = true,
				ReviewVersion = 1,
				Source = "User-supplied PAVA spray package with RoleplayOS server-authoritative logic",
				RealWorldReference = "UK police incapacitant spray training prop",
				ReviewedBy = "RoleplayOS engineering security review",
			},
			["Warrant Card"] = {
				Certified = true,
				ReviewVersion = 1,
				Source = "User-supplied Police Officer Warrant Card package",
				RealWorldReference = "UK police warrant card",
				ReviewedBy = "RoleplayOS engineering security review",
				AllowedUnsafeDescendants = {
					RoleplayOSWarrantCardClient = {
						ClassName = "LocalScript",
						Path = { "RoleplayOSWarrantCardClient" },
					},
				},
			},
			PoliceWarrantCard = {
				Certified = true,
				ReviewVersion = 1,
				Source = "User-supplied Police Officer Warrant Card package",
				RealWorldReference = "UK police warrant card",
				ReviewedBy = "RoleplayOS engineering security review",
				AllowedUnsafeDescendants = {
					RoleplayOSWarrantCardClient = {
						ClassName = "LocalScript",
						Path = { "RoleplayOSWarrantCardClient" },
					},
				},
			},
		},
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
	-- What the world is allowed to cost to draw.
	--
	-- Streaming decides how far away the world stops existing. This decides how
	-- much it costs while it is here. Imported content answers that question with
	-- the defaults of the tool it was exported from, which are always the most
	-- expensive option, so it is answered here instead.
	Performance = {
		Enabled = true,
		-- Instances touched before the startup pass yields the frame. Lower is
		-- gentler on the first few seconds of a server and slower to finish.
		InstancesPerStep = 500,
		-- Precise meshes redrawn at full detail however far away they are, which
		-- is how modelling tools export and never what a map wants.
		MeshLevelOfDetail = true,
		-- Distant models drawn as one cheap mesh rather than as all their parts.
		ModelLevelOfDetail = true,
		-- A shadow casting light costs far more than a light, and a lightbar is a
		-- dozen of them strobing at once.
		DisableLightShadows = true,
		-- Studs. Zero leaves light ranges alone.
		MaximumLightRangeStuds = 60,
		-- Studs. Zero leaves sound falloff alone. Keeps a siren mixed for the
		-- players near it rather than for everybody in the server.
		MaximumSoundDistanceStuds = 400,
		-- Volume in cubic studs below which a part stops casting a shadow.
		--
		-- Measured this place at 1201 of 1203 parts casting, 1073 of them smaller
		-- than two studs cubed. A shadow from a door handle, a wing mirror or a
		-- bolt is a few pixels nobody has ever noticed, and every one of them is
		-- still drawn into the shadow map every frame.
		--
		-- This is the reason the setting is a volume rather than a count: it takes
		-- away shadows that were never visible and leaves every shadow that reads,
		-- so it costs no quality at all. Anything with real silhouette -- a car
		-- body, a wall, a lamp post -- is far above the threshold and untouched.
		--
		-- Zero disables the pass.
		ShadowlessPartVolume = 8,
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
		-- The one live place is PUBLISHABLE VERSION OF PORTSMOUTH:
		-- experience 5710996304, place 16596652266. Public matchmaking and the
		-- official whitelist both use this place; the official entry below is
		-- distinguished by trusted teleport data into a reserved server.
		--
		-- Public and official progression still use separate namespaces, so a
		-- player's civilian identity cannot silently become their whitelisted
		-- service identity. Roblox gamepasses remain account-owned as normal.
		-- An official server is a set of reserved instances. When the first fills,
		-- the next join opens another, so nobody is turned away at peak.
		--
		-- Occupancy is published to a memory store by each instance and read by
		-- whoever is about to send somebody, because a server cannot see how full
		-- another one is any other way.
		-- Keep the official reserved-server target below the place's Roblox
		-- MaxPlayers setting. The current development place is configured for 60;
		-- 50 leaves headroom for teleport arrival races and gives one instance
		-- enough population for a healthy public roleplay session.
		MaximumPlayersPerInstance = 50,
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
				Name = "Whitelist Access",
				Description = "Official Portsmouth sessions for Universal Projects members.",
				Order = 1,
				Whitelisted = true,
				RequiredGroupLinkId = "UniversalProjects",
				-- Zero means this same place. The official server route supplies the
				-- identity through teleport data and reserves the destination instance.
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
	Economy = {
		StartingBankBalance = 2500,
		StartingCashBalance = 100,
		MaximumTransactionHistory = 200,
		TransferMaximum = 100000,
	},
	MoneyDrops = {
		Enabled = true,
		MinimumAmount = 1,
		MaximumAmount = 1000,
		MaximumActivePerPlayer = 3,
		MaximumActiveGlobal = 100,
		DropAheadStuds = 3,
		PickupDistance = 10,
		PickupHoldSeconds = 0.35,
		LifetimeSeconds = 300,
	},
	Integrations = {
		Discord = {
			SpeedingFines = {
				-- Store the target channel's complete webhook URL in this Creator
				-- Hub secret. A normal Discord channel link cannot receive posts.
				Enabled = false,
				SecretName = "RoleplayOSSpeedingFinesWebhook",
				GuildId = "1532864611706077194",
				ChannelId = "1534723525275811891",
				DepartmentName = "UP Hampshire Isle of Wight Constabulary",
				-- Enqueue also requires a group-authorised police officer and an
				-- actual Whitelisted server. Public gamepasses never qualify.
				MinimumIntervalSeconds = 1,
				MaximumQueue = 100,
			},
		},
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
		-- Studs either side of the player shown on the minimap.
		--
		-- Nine hundred put nearly two thousand studs of city across a panel a few
		-- inches wide, which is not a map, it is a texture. The point of a corner
		-- minimap is the next junction and the street you are on, so the window is
		-- tight enough that a road is a road.
		WindowRadius = 420,
		-- How far the player moves before the window is redrawn.
		RedrawDistance = 60,
		-- Minimum gap between full passes over the tagged geometry. Only this
		-- pass scales with the size of the map.
		RecollectSeconds = 3,
		-- Panel footprint before the interface scale is applied. Anything that
		-- has to sit clear of the minimap reads this rather than repeating the
		-- numbers, so the two cannot drift apart when the panel is resized.
		-- Wider than tall, and considerably smaller than it was.
		--
		-- This was 184 by 208, portrait, with a titled panel around it, and it ate
		-- a serious piece of the screen for something you glance at. A minimap in
		-- a driving game is landscape because the road ahead is the part that
		-- matters, and it carries no chrome because every pixel of frame is a
		-- pixel not showing the city. Roughly half the area it used to be.
		PanelSize = Vector2.new(178, 114),
		CompactPanelSize = Vector2.new(142, 92),
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
			GamepassId = 1936590544,
			Name = "Premium Vehicles",
			Description = "Access a curated collection of premium civilian vehicles at supported dealerships.",
		},
		CustomRegistration = {
			Id = "CustomRegistration",
			GamepassId = 1937140343,
			Name = "Custom Registration Plate",
			Description = "Choose a Roblox-filtered custom registration for an eligible owned vehicle at a dealership.",
		},
		CivilianKnife = {
			Id = "CivilianKnife",
			GamepassId = 1937446295,
			Name = "Civilian Knife Access",
			Description = "Access approved civilian knife equipment where server rules permit it.",
		},
		ZKnife = {
			Id = "ZKnife",
			GamepassId = 0,
			Name = "Z Knife Access",
			Description = "Access the approved Z knife equipment.",
		},
		CivilianHandgun = {
			Id = "CivilianHandgun",
			GamepassId = 1937822271,
			Name = "Civilian Handgun Access",
			Description = "Access approved civilian handgun equipment where server rules permit it.",
		},
		CivilianShotgun = {
			Id = "CivilianShotgun",
			GamepassId = 1934518052,
			Name = "Civilian Shotgun Access",
			Description = "Access approved civilian shotgun equipment where server rules permit it.",
		},
		CivilianRifle = {
			Id = "CivilianRifle",
			GamepassId = 1934955986,
			Name = "Civilian Rifle Access",
			Description = "Access approved civilian rifle equipment where server rules permit it.",
		},
		-- Base Police Officer and Frontline Policing access on the public place.
		-- PCSO remains the free public policing route.
		PublicPoliceTeam = {
			Id = "PublicPoliceTeam",
			GamepassId = 1937222319,
			Name = "Public Police Team",
			Description = "Report for duty with Frontline Policing in public servers, including its authorised equipment and fleet.",
		},
		PublicArmedResponse = {
			Id = "PublicArmedResponse",
			GamepassId = 1933270297,
			Name = "Public Armed Response Division",
			Description = "Join the Armed Response Unit in public servers with division-specific duty access.",
		},
		PublicRoadsPolicing = {
			Id = "PublicRoadsPolicing",
			GamepassId = 1933156365,
			Name = "Public Roads Policing Division",
			Description = "Join Roads Policing in public servers with traffic-enforcement and division fleet access.",
		},
		PublicAmbulanceTeam = {
			Id = "PublicAmbulanceTeam",
			GamepassId = 1936100607,
			Name = "Public Ambulance Team",
			Description = "Serve with the Ambulance team in public servers and access its authorised vehicles and equipment.",
		},
		PublicFireTeam = {
			Id = "PublicFireTeam",
			GamepassId = 1936292594,
			Name = "Public Fire & Rescue Team",
			Description = "Serve with Fire and Rescue in public servers and access its authorised vehicles and equipment.",
		},
		PublicControlTeam = {
			Id = "PublicControlTeam",
			GamepassId = 1935724637,
			Name = "Public Control Room Team",
			Description = "Operate Emergency Control in public servers using dispatch and incident-management tools.",
		},
		PublicTransportTeam = {
			Id = "PublicTransportTeam",
			GamepassId = 1934302085,
			Name = "Public Bus Service Team",
			Description = "Join the public transport service and operate authorised bus routes and vehicles.",
		},
		PublicHighwaysTeam = {
			Id = "PublicHighwaysTeam",
			GamepassId = 1934122097,
			Name = "Public Highways Team",
			Description = "Join the Highways team in public servers with authorised road-response vehicles and tools.",
		},
		PublicPrisonTeam = {
			Id = "PublicPrisonTeam",
			GamepassId = 1937368306,
			Name = "Public Prison Service Team",
			Description = "Join the Prison Service in public servers with authorised custody-site access and equipment.",
		},
		GangSystemAccess = {
			Id = "GangSystemAccess",
			GamepassId = 1941013627,
			Name = "Gang System Access",
			Description = "Unlock gang creation, membership management, leadership tools, communications, and associated criminal-roleplay features.",
		},
	},
	EquipmentPasses = {
		-- What a pass actually hands over. A pass missing from here, or carrying a
		-- zero, is skipped by ApplyEquipmentPasses - so it sells for Robux and
		-- gives nothing. The ZKnife pass had been created and its id never
		-- brought across, and the machete pass had no entry at all, so both took
		-- 149 Robux for an empty backpack.
		Knife = { GamepassId = 1937446295, TeamName = "Civilian", ToolNames = { "Knife" } },
		ZKnife = { GamepassId = 1949486956, TeamName = "Civilian", ToolNames = { "ZKnife" } },
		Machete = { GamepassId = 1949228959, TeamName = "Civilian", ToolNames = { "Machete" } },
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
					-- Cash or the pass. Owning CivilianKnife hands it over for
					-- nothing; everybody else pays, which is what the price is for.
					{
						Id = "Knife",
						Kind = "Tool",
						ToolId = "Knife",
						Name = "Knife",
						Price = 900,
						GamepassId = 1937446295,
						EmergencyRestricted = true,
					},
					-- Pass only. No Price, so the stall offers the purchase rather
					-- than refusing, which is what VendorService does with a passed
					-- item nobody owns yet.
					{
						Id = "Machete",
						Kind = "Tool",
						ToolId = "Machete",
						Name = "Machete",
						GamepassId = 1949228959,
						EmergencyRestricted = true,
					},
					{
						Id = "ZKnife",
						Kind = "Tool",
						ToolId = "ZKnife",
						Name = "Z Knife",
						GamepassId = 1949486956,
						EmergencyRestricted = true,
					},
				},
			},
		},
	},
	-- Six avatar-based StreetDealer vendors can be placed in the map once and
	-- rotated between six tagged points by the server. The models remain ordinary
	-- vendor models, so the existing purchase validation and ProximityPrompt UI
	-- work on keyboard, controller and touch without a second interaction system.
	DealerRotation = {
		Enabled = true,
		AutoCreate = true,
		-- This is the owner avatar id visible in the existing Studio test logs.
		-- Change it here if the publishable place should use another Roblox avatar.
		AvatarUserId = 4261672558,
		GeneratedFolderName = "RoleplayOSDealers",
		DealerTag = "RoleplayOSDealerAvatar",
		PointTag = "RoleplayOSDealerPoint",
		VendorTag = "RoleplayOSVendor",
		VendorId = "StreetDealer",
		RotationPeriodSeconds = 4 * 60 * 60,
		ExpectedDealerCount = 6,
		ExpectedPointCount = 6,
		FallbackPointOffsets = {
			Vector3.new(0, 0, -36),
			Vector3.new(36, 0, -36),
			Vector3.new(72, 0, -12),
			Vector3.new(72, 0, 36),
			Vector3.new(36, 0, 60),
			Vector3.new(-24, 0, 36),
		},
	},
	VehicleIdentity = {
		MinimumRegistrationLength = 2,
		MaximumRegistrationLength = 8,
		-- What a plate is called inside an imported vehicle.
		--
		-- None of these matched anything the fleet actually uses. Every vehicle in
		-- this game keeps its plate in a model called Plate holding a TextBox
		-- called Identifier, so the registration the server allocated was never
		-- written to a car and the plate on screen was whatever the vehicle's own
		-- script had randomised. Front and rear are separate models with the same
		-- shape, so naming them here covers both.
		PlatePartNames = {
			"RegistrationPlate",
			"NumberPlate",
			"LicencePlate",
			"LicensePlate",
			"Plate",
		},
		PlateTextNames = {
			"PlateText",
			"RegistrationText",
			"Registration",
			"NumberPlateText",
			"Identifier",
		},
		-- Scripts inside a plate that issue their own registration. They run when
		-- the vehicle reaches Workspace, which is after the framework has written
		-- its own, so they always won and then deleted themselves - leaving a car
		-- whose plate matched nothing in the MDT, on ANPR, or on the owner's
		-- record. Removed on spawn so the vehicle keeps its plate and the server
		-- keeps the number.
		PlateGeneratorNames = { "LicensePlateGenerator", "LicencePlateGenerator", "PlateGenerator" },
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
	DeveloperProducts = {
		ExtraCharacterSlot = {
			Id = "ExtraCharacterSlot",
			-- Live product on the Portsmouth universe (5710996304). Its name and
			-- price on Roblox already matched this entry exactly; only the id was
			-- missing, so purchases could never be granted.
			ProductId = 3708269661,
			GrantType = "ExtraCharacterSlot",
			Amount = 1,
			Name = "Extra Character Slot",
			Description = "Permanently unlock one additional civilian identity.",
			PriceRobux = 199,
		},
		-- A character's appearance is authored once, when it is created, and then
		-- fixed. This buys the right to reopen the editor for one character and
		-- change it again, which is why it is a consumable rather than a pass:
		-- each purchase is one edit.
		CharacterAppearanceEdit = {
			Id = "CharacterAppearanceEdit",
			-- Live product on the Portsmouth universe (5710996304).
			ProductId = 3708388537,
			GrantType = "CharacterAppearanceEdit",
			Amount = 1,
			Name = "Change Character Appearance",
			Description = "Reopen the appearance editor for one existing character.",
			PriceRobux = 79,
		},
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
		DisconnectPenaltySeconds = 30,
		PublicEarlyRelease = {
			-- Consumable Developer Products. IDs are set after creating them in the
			-- development experience; credits only exist in Public profile data.
			Products = {
				{
					Id = "Single",
					ProductId = 0,
					Credits = 1,
					PriceRobux = 19,
					Name = "Early Release · 1 Credit",
					Description = "One public-server early custody release credit. Your criminal record remains.",
				},
				{
					Id = "Triple",
					ProductId = 0,
					Credits = 3,
					PriceRobux = 49,
					Name = "Early Release · 3 Credits",
					Description = "Three persistent public-server early release credits. Your criminal record remains.",
				},
				{
					Id = "TenPack",
					ProductId = 0,
					Credits = 10,
					PriceRobux = 129,
					Name = "Early Release · 10 Credits",
					Description = "Ten persistent public-server early release credits. Your criminal record remains.",
				},
			},
		},
		CuffedWalkSpeed = 8,
		EscortDistance = 3.25,
		EscortMaximumForce = 18000,
		EscortMaximumVelocity = 16,
		-- Ordered the way an incident runs: on the street, then at the point of
		-- arrest, then at the station.
		--
		-- Every one of these is a real search power an officer would cite, chosen
		-- so the reason an officer gives matches what is actually happening in the
		-- game. Section 60 and section 47 cover weapons and firearms, which the
		-- game has; section 54 is the search on booking, which the game already
		-- performs automatically. A drugs power was offered here and was removed:
		-- Roblox does not permit references to controlled substances, and a search
		-- reason naming them is exactly that whichever way it is worded, so it went
		-- rather than being renamed. A euphemism for the same thing is the same
		-- thing. The server validates against this list, so a client that sends
		-- anything absent from it gets INVALID_SEARCH_POWER and records no search.
		SearchPowers = {
			"PACE_S1",
			"CJPOA_S60",
			"FIREARMS_S47",
			"PACE_S32_POST_ARREST",
			"PACE_S54_CUSTODY",
		},
		DisconnectPenaltyCode = "LEAVE_WHILE_RESTRAINED",
		SimulationNotice = "Simplified roleplay simulation — not legal advice or professional training.",
		ArrestCaution = "You do not have to say anything. But it may harm your defence if you do not mention when questioned something which you later rely on in court. Anything you do say may be given in evidence.",
		-- Compressed gameplay tariffs, not real-world sentences. The server adds these values;
		-- clients can only submit an allowlisted Code.
		-- Named, cited and priced.
		--
		-- Six offences covered a game with speed cameras, a roads policing unit and
		-- a traffic division, so almost everything an officer actually stopped
		-- somebody for had to be booked as "Other recorded offence". Statutes are
		-- carried alongside the name because citing one is most of what makes a
		-- charge read as a charge rather than as a label, and the booking screen
		-- has room for it.
		--
		-- Seconds are compressed gameplay tariffs and deliberately not real
		-- sentences. They are ordered by how much harm the offence does rather than
		-- by what the statute carries: a firearms offence is the longest here and
		-- would not be the longest in law.
		--
		-- Nothing involving controlled substances or alcohol appears, and nothing
		-- will: Roblox does not permit either, and a charge naming them is the same
		-- problem as a search reason naming them.
		OffenceTariffs = {
			OTHER = { Name = "Other recorded offence", Seconds = 120 },

			-- Road traffic.
			SPEEDING = {
				Name = "Exceeding a speed limit",
				Statute = "Road Traffic Regulation Act 1984 s89",
				Seconds = 90,
			},
			NO_INSURANCE = {
				Name = "Using a vehicle without insurance",
				Statute = "Road Traffic Act 1988 s143",
				Seconds = 120,
			},
			NO_LICENCE = {
				Name = "Driving otherwise than in accordance with a licence",
				Statute = "Road Traffic Act 1988 s87",
				Seconds = 120,
			},
			CARELESS_DRIVING = {
				Name = "Driving without due care and attention",
				Statute = "Road Traffic Act 1988 s3",
				Seconds = 150,
			},
			FAIL_TO_STOP_POLICE = {
				Name = "Failing to stop for a constable",
				Statute = "Road Traffic Act 1988 s163",
				Seconds = 180,
			},
			FAIL_TO_STOP_COLLISION = {
				Name = "Failing to stop after a collision",
				Statute = "Road Traffic Act 1988 s170",
				Seconds = 240,
			},
			VEHICLE_TAKEN_WITHOUT_CONSENT = {
				Name = "Taking a vehicle without consent",
				Statute = "Theft Act 1968 s12",
				Seconds = 240,
			},
			DANGEROUS_DRIVING = {
				Name = "Dangerous driving",
				Statute = "Road Traffic Act 1988 s2",
				Seconds = 300,
			},

			-- Against property.
			THEFT = { Name = "Theft", Statute = "Theft Act 1968 s1", Seconds = 180 },
			CRIMINAL_DAMAGE = {
				Name = "Criminal damage",
				Statute = "Criminal Damage Act 1971 s1",
				Seconds = 180,
			},
			BURGLARY = { Name = "Burglary", Statute = "Theft Act 1968 s9", Seconds = 360 },
			ROBBERY = { Name = "Robbery", Statute = "Theft Act 1968 s8", Seconds = 420 },

			-- Against the person, and against officers doing the job.
			PUBLIC_ORDER = {
				Name = "Threatening or abusive behaviour",
				Statute = "Public Order Act 1986 s4",
				Seconds = 180,
			},
			OBSTRUCT_POLICE = {
				Name = "Obstructing a constable in the execution of their duty",
				Statute = "Police Act 1996 s89",
				Seconds = 150,
			},
			ASSAULT = { Name = "Assault", Statute = "Criminal Justice Act 1988 s39", Seconds = 240 },
			ASSAULT_EMERGENCY_WORKER = {
				Name = "Assaulting an emergency worker",
				Statute = "Assaults on Emergency Workers Act 2018 s1",
				Seconds = 360,
			},

			-- Weapons. All three name things the game actually issues.
			BLADED_ARTICLE = {
				Name = "Possession of a bladed article",
				Statute = "Criminal Justice Act 1988 s139",
				Seconds = 300,
			},
			OFFENSIVE_WEAPON = {
				Name = "Possession of an offensive weapon",
				Statute = "Prevention of Crime Act 1953 s1",
				Seconds = 300,
			},
			FIREARMS = {
				Name = "Firearms offence",
				Statute = "Firearms Act 1968 s1",
				Seconds = 480,
			},

			-- Not an offence. The penalty for walking out of custody by quitting.
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
	-- Periodic record of what the server is doing.
	--
	-- Everything wrong with this game so far arrived as a feeling: it is looping,
	-- it is laggy, people are being kicked. Each had a specific cause and each
	-- took far longer to find than it should have, because there was no record of
	-- what the server looked like at the time.
	Health = {
		Enabled = true,
		IntervalSeconds = 120,
		-- Offset from startup, so the first sample is of a running server rather
		-- than of one still starting, which is always its worst minute.
		FirstSampleSeconds = 45,
	},
	-- Our own emergency lighting, rather than whichever kit a vehicle arrived
	-- with.
	--
	-- The place currently runs at least two different kits, EasyLS and EpicLights,
	-- both of them erroring, and the speed cameras had to guess at a dozen
	-- attribute names to work out whether a vehicle was on a blue light run.
	-- Owning this replaces the guess with one attribute that is true because this
	-- framework set it.
	--
	-- The server owns the state and every client runs the flash pattern itself, so
	-- a strobing lightbar costs nothing on the network however many are running.
	EmergencyLighting = {
		Enabled = true,
		-- The attribute everything else reads. The cameras check this first.
		StateAttribute = "RoleplayOSEmergencyLights",
		StageAttribute = "RoleplayOSLightStage",
		SirenAttribute = "RoleplayOSSiren",
		CircuitAttributePrefix = "RoleplayOSCircuit",
		RunLockAttribute = "RoleplayOSRunLock",
		LowPowerAttribute = "RoleplayOSLowPower",
		-- Tagged on vehicles that have lights, so clients find them through
		-- CollectionService as they stream in rather than by scanning the world.
		Tag = "RoleplayOSEmergencyVehicle",
		-- Who may run lights, and in what colour. Traffic officers run amber in
		-- the UK, not blue, and a department missing from here has no lights at
		-- all rather than defaulting to blue.
		-- Primary and Secondary are the two halves of a bar, alternating. They are
		-- not "the colour and a highlight": whatever is here is half of what the
		-- street sees, so a near-white secondary is a bar that flashes white down
		-- one side. A marked British police car is blue throughout, with the white
		-- kept to the takedowns and scene lamps, which have their own colours in
		-- CircuitColours below.
		Departments = {
			Police = {
				Primary = Color3.fromRGB(0, 68, 255),
				Secondary = Color3.fromRGB(60, 130, 255),
			},
			Ambulance = {
				Primary = Color3.fromRGB(0, 92, 255),
				Secondary = Color3.fromRGB(255, 235, 90),
			},
			Fire = {
				Primary = Color3.fromRGB(0, 68, 255),
				Secondary = Color3.fromRGB(255, 60, 40),
			},
			Highways = {
				Primary = Color3.fromRGB(255, 148, 0),
				Secondary = Color3.fromRGB(255, 196, 60),
			},
		},
		-- Stage one is the rear cluster for a stationary scene, stage two is
		-- everything. A vehicle parked at an incident should be visible without
		-- dazzling the traffic it is warning.
		Stages = 2,
		-- How many director patterns a kit cycles through before returning to off.
		-- Used only to keep the DIRECTOR button's indicator honest: EasyLS keeps its
		-- director stage in a local and offers no way to read it, so presses are
		-- counted against this instead. Two is what the kits in this fleet ship.
		DirectorStages = 2,
		FlashesPerSecond = 2.2,
		-- What each circuit is, rather than what colour the department flashes.
		--
		-- Colour used to come from the lamp's position in the adoption order:
		-- every other lamp took the department's primary and the rest took its
		-- secondary, whatever the lamp actually was. On a police vehicle that is
		-- blue and near-white, so a bar half flashed blue and half flashed white
		-- with no relation to which side of the car the lamp was on - and the rear
		-- reds, correctly identified as reds, came out blue or white like
		-- everything else, because red is not in the police palette at all.
		--
		-- These are facts about the fitting, not about the force: rear reds are
		-- red on every marked car in the country, and scene, alley and takedown
		-- lamps are white work lights. Only the blues take the department colours.
		CircuitColours = {
			RearReds = Color3.fromRGB(255, 32, 24),
			FrontScene = Color3.fromRGB(255, 250, 235),
			RearScene = Color3.fromRGB(255, 250, 235),
			LeftAlley = Color3.fromRGB(255, 250, 235),
			RightAlley = Color3.fromRGB(255, 250, 235),
			Spots = Color3.fromRGB(255, 250, 235),
		},
		-- Work lights, which are lit rather than flashed. A scene lamp strobing is
		-- the tell that a lightbar is being driven by something that does not know
		-- what its lamps are for.
		SteadyCircuits = {
			FrontScene = true,
			RearScene = true,
			LeftAlley = true,
			RightAlley = true,
			Spots = true,
		},
		-- A model can identify a lamp explicitly with a RoleplayOSLightCircuit
		-- attribute, or use one of these case-insensitive name fragments. Models
		-- without circuit names still work through 360 and at-scene modes.
		Circuits = {
			FrontBlue = { "frontblue", "front blue", "front_blue" },
			RearBlue = { "rearblue", "rear blue", "rear_blue" },
			-- "reds" on its own is here for the fittings that are named for what
			-- they are rather than where they are: the Mondeo's rear reds sit in a
			-- model called Reds, with the parts inside numbered and nothing else to
			-- go on. Deliberately plural, so it cannot claim a single red bulb in a
			-- brake cluster.
			RearReds = { "rearred", "rear red", "rear_red", "reds" },
			-- Takedowns are the forward-facing work lights, which is what a front
			-- scene light is. Kits name them that far more often than they write
			-- "front scene", and a vehicle whose fitting is called Takedowns had
			-- nothing to match before.
			FrontScene = { "frontscene", "front scene", "front_scene", "takedown" },
			RearScene = { "rearscene", "rear scene", "rear_scene" },
			Grille = { "grille", "grill" },
			LeftAlley = { "leftalley", "left alley", "left_alley" },
			RightAlley = { "rightalley", "right alley", "right_alley" },
			Spots = { "spotlight", "spot light", "spots", "floodlight", "worklight" },
		},
		-- How a light part is recognised inside a vehicle. Excluded names are
		-- checked first, so an ordinary lamp is never taken for a blue light.
		-- Distinctive substrings only. "grille" and "led" were both here and both
		-- matched bodywork: every imported car has a part called Grille, and
		-- "led" is inside Welded, Panelled and Ledge. Either one passed on its own
		-- name, which also skips the check that it looks like a lamp, so the
		-- radiator grille turned neon on the grille button. A grille light inside
		-- a lightbar is still found through the model it sits in, and anything
		-- else can say so with the RoleplayOSLight attribute.
		LightNamePatterns = {
			"els",
			"lightbar",
			"beacon",
			"strobe",
			"blues",
			"lightz",
		},
		ExcludedNamePatterns = {
			"head",
			"interior",
			"brake",
			"reverse",
			"fog",
			"indicator",
			"hazard",
			"dash",
			"plate",
			"cabin",
			"map",
			"tail",
			"number",
			-- Roadwheels. A wheel called FR or RL sits at the front or the rear
			-- and has no name of its own to go on, so the positional fallback
			-- that resolves an unnamed bulb was claiming all four of them and
			-- the vehicle strobed its tyres.
			"wheel",
			"tyre",
			"tire",
		},
		-- A cap rather than a target. A lightbar modelled as two hundred separate
		-- parts would otherwise be two hundred parts changing colour twice a
		-- second on every client that can see it.
		MaximumLightParts = 64,
		-- Deliberately empty.
		--
		-- Most of the sound errors in this place are free model audio that Roblox
		-- stopped allowing, and putting a guessed asset id here would fail the same
		-- way while looking configured. Upload the tones under the group and put
		-- their ids in EDIT_HERE.
		-- The tones a vehicle may be recorded as sounding. Names, not ids.
		--
		-- These were asset ids under a comment claiming they were owned by the
		-- group and verified in its inventory. Neither is in the group's audio
		-- inventory, and nothing has ever played them: every emergency vehicle in
		-- the fleet ships its own siren sounds and its own script to play them.
		-- The framework's part is to record which tone is running so dispatch and
		-- the speed cameras agree with the street, and that needs a name.
		Sirens = {
			Wail = true,
			Yelp = true,
			Priority = true,
			Airhorn = true,
		},
		-- No SirenVolume. The vehicles author their own, and the panel plays the
		-- vehicle's own sounds rather than a copy, so overriding it here would only
		-- fight the level the kit was balanced at.
		SirenRangeStuds = 320,
	},
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
				"PCSO",
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
		-- Emergency marks a team whose members are on the public payroll and in
		-- uniform. Nothing about the roster says that on its own, and it decides
		-- who the street dealer will serve, so it is stated here rather than
		-- inferred from a name.
		Police = {
			Id = "Police",
			Name = "Police",
			BrickColor = "Navy blue",
			AutoAssignable = false,
			Emergency = true,
		},
		Ambulance = {
			Id = "Ambulance",
			Name = "Ambulance",
			BrickColor = "Earth green",
			AutoAssignable = false,
			Emergency = true,
		},
		Fire = {
			Id = "Fire",
			Name = "Fire",
			BrickColor = "Bright red",
			AutoAssignable = false,
			Emergency = true,
		},
		Control = {
			Id = "Control",
			Name = "Control",
			BrickColor = "Really black",
			AutoAssignable = false,
			Emergency = true,
		},
		Transport = {
			Id = "Transport",
			Name = "Transport",
			BrickColor = "New Yeller",
			AutoAssignable = false,
		},
		Taxi = {
			Id = "Taxi",
			Name = "Taxi",
			BrickColor = "Bright yellow",
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
			Emergency = true,
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
			DisplayName = "Universal Projects Control",
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
		-- Free on the public place, and the only policing role that is. A PCSO
		-- carries a radio and a notebook and no handcuffs, which is both the real
		-- distinction and a reason to buy the police pass.
		PCSO = {
			Id = "PCSO",
			Name = "Police Community Support Officer",
			TeamName = "Police",
			DepartmentId = "Police",
			-- PCSO is the free public policing route. It must not appear or be
			-- assignable in the whitelisted deployment, even to police-group members.
			Access = {
				AccessType = "ServerKind",
				Kind = "Public",
				-- The menu explicitly hides this role outside Public servers. Keeping
				-- the card visible here prevents a stale/undetected server-kind value
				-- from making the free public route disappear entirely.
				DisplayWhenLocked = true,
			},
			LoadoutId = "PCSO",
			UniformId = "PoliceCommunitySupportOfficer",
			AutoEquipUniform = true,
			-- Stated rather than inherited.
			--
			-- This role is free on the public tier and its department is Police,
			-- so inheriting the department handed every player in the game warrant
			-- creation, custody booking, search, escort and the blue light
			-- exemption. A PCSO has no power of arrest, which is the whole reason
			-- the role exists separately, and that has to be written down
			-- somewhere the code reads rather than only in a comment.
			Permissions = { "PersonSearch", "VehicleSearch", "IncidentWrite" },
		},
		PoliceOfficer = {
			Id = "PoliceOfficer",
			Name = "Police Officer",
			TeamName = "Police",
			DepartmentId = "Police",
			Access = publicPassOr({
				AccessType = "Group",
				GroupLinkId = "Police",
				MinimumGroupRank = 1,
			}, 1937222319),
			LoadoutId = "PoliceResponse",
			UniformId = "PoliceStandard",
		},
		PoliceFrontline = {
			Id = "PoliceFrontline",
			Name = "Frontline Policing",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "Frontline",
			Access = publicPassOr({
				AccessType = "Group",
				GroupLinkId = "Police",
				MinimumGroupRank = 1,
			}, 1937222319),
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
			}, 1933270297),
			LoadoutId = "ArmedResponse",
			UniformId = "PoliceStandard",
		},
		-- Whitelisted deployments only.
		--
		-- Written as a plain rule rather than through publicPassOr, because that
		-- helper's whole purpose is to offer a Robux route on the public place and
		-- this role deliberately has none. DisplayWhenLocked is false for the same
		-- reason: a card advertising something nobody on that server can ever have
		-- is worse than no card.
		--
		-- No divisional group of its own yet, so membership of the force is the
		-- bar. Add a DogSupport entry to GroupLinks and a second Group rule here
		-- when the sub-group exists.
		DogSupportOfficer = {
			Id = "DogSupportOfficer",
			Name = "Dog Support Unit",
			TeamName = "Police",
			DepartmentId = "Police",
			DivisionId = "DogSupport",
			Access = {
				AccessType = "Combined",
				Match = "All",
				DisplayWhenLocked = false,
				Rules = {
					{ AccessType = "ServerKind", Kind = "Whitelisted" },
					{ AccessType = "Group", GroupLinkId = "Police", MinimumGroupRank = 1 },
				},
			},
			LoadoutId = "DogSupport",
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
			}, 1933156365),
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
				1936100607
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
				1936292594
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
				AccessType = "Group",
				GroupLinkId = "Control",
				MinimumGroupRank = 1,
			}, 1935724637),
			LoadoutId = "ControlStandard",
		},
		TransportOperator = {
			Id = "TransportOperator",
			Name = "Bus Service",
			TeamName = "Transport",
			DepartmentId = "Transport",
			Access = publicPassOr(
				{ AccessType = "Group", GroupLinkId = "Transport", MinimumGroupRank = 1 },
				1934302085
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
				1934122097
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
				1937368306
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
				"Civilian",
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
			-- Civilian is a role department for spawn validation even though it
			-- has no restricted emergency-service department membership.
			DepartmentIds = { "Civilian" },
		},
		-- One spawn point per service, as Fire and Ambulance already had.
		--
		-- Police used to offer a second at the vehicle bay, which existed only
		-- because there were cars parked there. That put "where I come on duty"
		-- and "where I collect a car" in the same list and gave police roles a
		-- choice no other service had. The bays are still separate, one per
		-- division, so nothing spawns on top of anything else; they are simply
		-- not places to arrive.
		PoliceLockerRoom = {
			Id = "PoliceLockerRoom",
			StationId = "CityCentre",
			TeamName = "Police",
			RoleIds = {
				"PCSO",
				"PoliceOfficer",
				"PoliceFrontline",
				"ArmedResponseOfficer",
				"RoadsPolicingOfficer",
				"DogSupportOfficer",
			},
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
		PoliceCommunitySupportOfficer = {
			Id = "PoliceCommunitySupportOfficer",
			ShirtTemplate = "2301512590",
			TrousersTemplate = "700637070",
			KitAssetPath = { "Uniforms", "Police", "PoliceCommunitySupportOfficer" },
			RemovePersonalAccessories = true,
		},
		PoliceStandard = { Id = "PoliceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		AmbulanceStandard = { Id = "AmbulanceStandard", ShirtTemplate = "", TrousersTemplate = "" },
		FireStandard = { Id = "FireStandard", ShirtTemplate = "", TrousersTemplate = "" },
		TransportStandard = { Id = "TransportStandard", ShirtTemplate = "", TrousersTemplate = "" },
		HighwaysStandard = { Id = "HighwaysStandard", ShirtTemplate = "", TrousersTemplate = "" },
		PrisonStandard = { Id = "PrisonStandard", ShirtTemplate = "", TrousersTemplate = "" },
	},
	UniformChangingRooms = {
		FolderName = "RoleplayOSChangingRooms",
		PromptHoldDuration = 0.35,
		MaximumInteractionDistance = 12,
		Defaults = {
			{
				ChangingRoomId = "PoliceChangingRoom",
				DisplayName = "Police uniform",
				SpawnId = "PoliceLockerRoom",
				DepartmentId = "Police",
				UniformId = "PoliceStandard",
				Offset = { -10, 2, 0 },
			},
			{
				ChangingRoomId = "AmbulanceChangingRoom",
				DisplayName = "Ambulance uniform",
				SpawnId = "AmbulanceLockerRoom",
				DepartmentId = "Ambulance",
				UniformId = "AmbulanceStandard",
				Offset = { -10, 2, 0 },
			},
			{
				ChangingRoomId = "FireChangingRoom",
				DisplayName = "Fire uniform",
				SpawnId = "FireLockerRoom",
				DepartmentId = "Fire",
				UniformId = "FireStandard",
				Offset = { -10, 2, 0 },
			},
			{
				ChangingRoomId = "TransportChangingRoom",
				DisplayName = "Transport uniform",
				SpawnId = "TransportDepot",
				DepartmentId = "Transport",
				UniformId = "TransportStandard",
				Offset = { -10, 2, 0 },
			},
			{
				ChangingRoomId = "HighwaysChangingRoom",
				DisplayName = "Highways uniform",
				SpawnId = "HighwaysDepot",
				DepartmentId = "Highways",
				UniformId = "HighwaysStandard",
				Offset = { -10, 2, 0 },
			},
			{
				ChangingRoomId = "PrisonChangingRoom",
				DisplayName = "Prison uniform",
				SpawnId = "PrisonStaff",
				DepartmentId = "Prison",
				UniformId = "PrisonStandard",
				Offset = { -10, 2, 0 },
			},
		},
	},
	Divisions = {
		Frontline = { Id = "Frontline", DepartmentId = "Police", Name = "Frontline Policing" },
		ArmedResponse = { Id = "ArmedResponse", DepartmentId = "Police", Name = "Armed Response" },
		RoadsPolicing = { Id = "RoadsPolicing", DepartmentId = "Police", Name = "Roads Policing" },
		DogSupport = { Id = "DogSupport", DepartmentId = "Police", Name = "Dog Support" },
	},
	Tools = {
		-- Grip is set here rather than baked into the model.
		--
		-- The assembler gives every blade the same rotation, and these do not all
		-- run along the same axis of their handle: the knives lie along Z and the
		-- machete along Y. One rotation therefore cannot be right for all three,
		-- and it was right for none of them - both knives stood straight up out of
		-- the fist like a needle, and the machete was held by its blade with the
		-- lanyard swinging free. Correcting it here means a re-export is not needed
		-- to change how something is carried.
		Knife = {
			Id = "Knife",
			AssetPath = { "Tools", "Civilian", "Knife" },
			DepartmentId = "Civilian",
			BuiltInFallback = "Weapon",
			Grip = CFrame.new(),
			Weapon = { Damage = 18, Cooldown = 0.65, Range = 8 },
		},
		Machete = {
			Id = "Machete",
			AssetPath = { "Tools", "Civilian", "Machete" },
			DepartmentId = "Civilian",
			BuiltInFallback = "Weapon",
			-- The blade runs along the model's +Y and the wrapped grip along -Y, so
			-- the half-turn that -90 degrees produced put the fist on the blade and
			-- left the lanyard swinging below. Verified against an R15 rig posed
			-- with Roblox's own equip weld.
			Grip = CFrame.Angles(math.rad(90), 0, 0),
			-- Hand-authored, published under the group in May 2025, and until now
			-- never referenced by anything: the swing was a sine curve applied to
			-- the shoulder joint because no tool carried an AnimationId. The client
			-- looks for an Animation named Swing inside the tool and prefers it over
			-- the procedural fallback the moment it finds one, so issuing the tool
			-- with these attached is the whole wiring. Named by role rather than by
			-- asset so a re-cut animation is a change to one line here.
			Animations = { Swing = 121274779518215 },
			Weapon = { Damage = 24, Cooldown = 0.8, Range = 8 },
		},
		ZKnife = {
			Id = "ZKnife",
			AssetPath = { "Tools", "Civilian", "ZKnife" },
			DepartmentId = "Civilian",
			BuiltInFallback = "Weapon",
			Grip = CFrame.new(),
			Weapon = { Damage = 20, Cooldown = 0.7, Range = 8 },
		},
		Handcuffs = {
			Id = "Handcuffs",
			AssetPath = { "Tools", "Services", "Police", "Shared", "Handcuffs" },
			DepartmentId = "Police",
			-- Both numbers were settled in a running game with the tool equipped,
			-- not against a posed rig. A rig stands with its arms down; the game
			-- holds a tool with the forearm raised, so a grip tuned to hang from a
			-- resting hand comes out level, and the cuffs were carried across the
			-- chest like a bar.
			--
			-- Scaled because the authored model is two studs long against a five
			-- stud character. Hung from the hand rather than laid across the palm,
			-- since at a believable size the palm is not big enough to lay them on.
			Scale = 0.42,
			Grip = CFrame.new(-0.01, -0.3, 0.15)
				* CFrame.fromEulerAnglesYXZ(math.rad(-1), math.rad(177), math.rad(179)),
		},
		Taser = {
			Id = "Taser",
			AssetPath = { "Tools", "Services", "Police", "Shared", "Taser" },
			DepartmentId = "Police",
			-- The group's own taser hold, published May 2025 and unused until now.
			-- TaserPoseController prefers it and keeps its hand-built R15 pose as
			-- the fallback, which is still what carries any tool without one.
			Animations = { Idle = 116507173136573 },
		},
		MedicalBag = {
			Id = "MedicalBag",
			AssetPath = { "Tools", "Services", "Ambulance", "MedicalBag" },
			DepartmentId = "Ambulance",
			BuiltInFallback = "MedicalBag",
		},
		PoliceWarrantCard = {
			Id = "PoliceWarrantCard",
			AssetPath = { "Tools", "Services", "Police", "Shared", "Warrant Card" },
			DepartmentId = "Police",
		},
		PAVA = {
			Id = "PAVA",
			AssetPath = { "Tools", "Services", "Police", "Shared", "PAVA" },
			DepartmentId = "Police",
		},
	},
	Loadouts = {
		PoliceResponse = {
			Id = "PoliceResponse",
			ToolIds = { "Handcuffs", "Taser", "PAVA" },
		},
		-- No handcuffs. A PCSO has no power of arrest, and the custody workflow is
		-- gated on carrying them, so the distinction enforces itself.
		PCSO = { Id = "PCSO", ToolIds = {} },
		PoliceFrontline = {
			Id = "PoliceFrontline",
			ToolIds = { "Handcuffs", "Taser", "PAVA" },
		},
		ArmedResponse = { Id = "ArmedResponse", ToolIds = { "Handcuffs", "Taser", "PAVA" } },
		RoadsPolicing = { Id = "RoadsPolicing", ToolIds = { "Handcuffs", "Taser", "PAVA" } },
		DogSupport = { Id = "DogSupport", ToolIds = { "Handcuffs", "Taser", "PAVA" } },
		AmbulanceStandard = { Id = "AmbulanceStandard", ToolIds = { "MedicalBag" } },
		FireStandard = { Id = "FireStandard", ToolIds = {} },
		ControlStandard = { Id = "ControlStandard", ToolIds = {} },
		TransportStandard = { Id = "TransportStandard", ToolIds = {} },
		HighwaysStandard = { Id = "HighwaysStandard", ToolIds = {} },
		PrisonStandard = { Id = "PrisonStandard", ToolIds = {} },
	},
	Jobs = {
		TaxiDriver = {
			Id = "TaxiDriver",
			Name = "Taxi driver",
			Class = "Public",
			BaseWage = 12,
			TaskReward = 18,
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
	Spawning = {
		-- Tag applied to the SpawnLocation pads the framework manages. Tagging
		-- lets startup ask for the pads directly; without it every descendant of
		-- the workspace is walked, which blocks startup on a large map.
		PadTag = "RoleplayOSSpawnPad",
		-- A map author may use the simple convention requested for production:
		-- create one SpawnLocation and name it exactly after its Team. SpawnId
		-- attributes still win where a station has multiple distinct pads.
		TeamNameFallbacks = {
			Civilian = "CityCivilian",
			Police = "PoliceLockerRoom",
			Ambulance = "AmbulanceLockerRoom",
			Fire = "FireLockerRoom",
			Control = "ControlRoom",
			Transport = "TransportDepot",
			-- Taxi shifts use the Transport character pad; there is no duplicate
			-- taxi-only pad to maintain or accidentally leave on the map.
			Taxi = "TransportDepot",
			Highways = "HighwaysDepot",
			Prison = "PrisonStaff",
		},
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
		-- Touch-only actions are still driven by the imported vehicle's native
		-- sounds/values. They are hidden when the vehicle does not expose the
		-- corresponding native capability.
		ActionSize = 58,
	},
	-- Speeding, and who is exempt from it.
	--
	-- Detection belongs to the camera system in the world. This is the rule it
	-- asks about and the record it writes into, so an officer searching a driver
	-- in the MDT sees their points and their fines.
	RoadSafety = {
		SpeedCameraTag = "RoleplayOSSpeedCamera",
		AverageEntryTag = "RoleplayOSAverageSpeedEntry",
		AverageExitTag = "RoleplayOSAverageSpeedExit",
		AverageJourneyExpirySeconds = 1800,
		StateCleanupSeconds = 60,
		-- Cameras are found by shape rather than by tag, so a camera model
		-- dropped into the world works with nothing else done to it. A model
		-- counts as a camera when it holds a part named Sensor and a
		-- Configuration with a SpeedLimit, which is what the camera kit builds.
		SensorName = "Sensor",
		ConfigurationName = "Configuration",
		SpeedLimitValueName = "SpeedLimit",
		-- Optional, and only used for the flash.
		CameraPartName = "Camera",
		LightPartName = "Light",
		-- One reading per vehicle per camera. Touched fires continuously while
		-- anything rests against the sensor, so without this a car stopped on one
		-- is fined until its owner has nothing left.
		SensorCooldownSeconds = 8,
		ToleranceMph = 2,
		-- Uses EconomyService rather than a leaderstats value. When the account
		-- cannot cover the charge, the offence remains as an unpaid fine.
		AutomaticallyDebitFines = true,
		-- Penalties follow the shape of UK sentencing rather than a formula.
		--
		-- This was a hundred pounds plus ten for every mile an hour over, which
		-- is not how anybody is fined here and produced numbers nobody could
		-- predict: twenty five over came to three hundred and fifty.
		--
		-- A minor excess is a fixed penalty notice, handed out at the roadside
		-- for a hundred pounds and three points. Past that it stops being a
		-- ticket and becomes a band, which is what a magistrate works from, and
		-- the bands step rather than slide. A driver can therefore tell what an
		-- offence will cost before committing it, which is the entire deterrent.
		--
		-- Real bands are a proportion of weekly income, which does not exist
		-- here, so each carries a flat amount of roughly the right weight
		-- against the wages in the Payroll section.
		--
		-- Ordered by excess. The first band the excess falls inside wins, and the
		-- last one has no ceiling so there is always an answer.
		PenaltyBands = {
			{ Name = "Fixed penalty", MaximumExcessMph = 10, Fine = 100, Points = 3 },
			{ Name = "Band B", MaximumExcessMph = 20, Fine = 400, Points = 4 },
			{ Name = "Band C", MaximumExcessMph = 30, Fine = 700, Points = 6 },
			-- Disqualification territory in reality. There is no licence to take
			-- away yet, so it is the ceiling instead.
			{ Name = "Band C", MaximumExcessMph = 999, Fine = 1000, Points = 6 },
		},
		-- An emergency driver on a blue light run is exempt. The same driver with
		-- the lights off is not, which is the whole point of the rule: the
		-- exemption belongs to the response, not to the person or the car.
		ExemptOnEmergencyLights = true,
		-- Being on duty is required as well as the lights. Without it, anybody who
		-- got hold of a marked car and found the light switch would be exempt.
		ExemptRequiresDuty = true,
	},
	-- How to tell whether a vehicle's blue lights are on.
	--
	-- Lighting systems differ as much as chassis forks do, so this is a list of
	-- places to look rather than one assumption. Every name is tried as an
	-- attribute on the vehicle model and on the driver's seat, and as a value
	-- object inside the named folders. The first one that reads as on wins.
	--
	-- If the exemption is not working, the surest way to find the right name is to
	-- turn the lights on in Studio and watch which attribute or value changes.
	EmergencyLights = {
		-- Matched by pattern as well as by name, because lighting systems name
		-- this differently and guessing wrong silently costs an emergency driver
		-- a fine. Anything whose name contains one of these counts.
		NamePatterns = {
			"els",
			"lightbar",
			"siren",
			"beacon",
			"emergency",
			"strobe",
			"blues",
			"code3",
			"lightson",
			"lightstate",
		},
		-- Checked first and never matched, so an ordinary lamp cannot be mistaken
		-- for a blue light run. Without these a marked car simply driving with its
		-- headlights on would be exempt from every camera.
		ExcludedPatterns = {
			"head",
			"interior",
			"brake",
			"reverse",
			"fog",
			"indicator",
			"hazard",
			"dash",
			"plate",
			"cabin",
			"map",
		},
		AttributeNames = {
			"RoleplayOSEmergencyLights",
			"ELSActive",
			"Lights",
			"LightsOn",
			"Emergency",
			"Code3",
		},
		ValueFolderNames = { "ELS", "Values", "Configuration", "Settings" },
		-- Values that count as off even when the attribute exists.
		OffValues = { "off", "false", "none", "0" },
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
		-- The chassis's own engine switch, where it has one.
		--
		-- Running out of fuel used to set the seat's MaxSpeed to zero, which stops
		-- a plain Roblox vehicle seat and does nothing whatsoever to A-Chassis:
		-- it makes its own torque from this folder and never reads MaxSpeed. An
		-- empty tank therefore had no effect at all on the cars this game
		-- actually uses. Cutting the engine is the one lever that reaches them.
		EngineValueName = "IsOn",
		-- Engine speed the tachometer arc treats as full.
		--
		-- This briefly scaled the speed needle, which was wrong: it pointed the
		-- needle at "80" on a dial printed in mph while the van did thirty. It now
		-- scales the tacho ring outside the speed ticks, which is the only place a
		-- redline means anything.
		Redline = 8000,
		-- Fraction of Redline the tacho arc shades red. 0.85 of 8000 is 6800, which
		-- is where a petrol engine's limiter usually sits.
		RedlineBand = 0.85,
		-- Where the speed dial starts warning.
		--
		-- The ticks used to warm at 0.68 and 0.86 of top speed, which put amber at
		-- 95mph and red at 120. That is a rev counter's logic on a speedometer: a
		-- redline is a mechanical limit, and a speedometer has no mechanical limit
		-- to mark. Nothing on the dial meant anything to a driver.
		--
		-- These are limits instead. 70 is the national speed limit and the highest
		-- number lawful anywhere in the UK, so above it the driver is speeding
		-- wherever they are; 100 is where a traffic stop stops being a ticket.
		--
		-- Per-road limits would be better still, and RoadSafetyService does know
		-- them -- but only per speed camera sensor, as an attribute on the sensor
		-- rather than as an ambient property of the road. A live "current limit"
		-- needs a zone system that does not exist yet, and inventing one blind would
		-- be worse than a fixed national limit that is at least always true.
		WarnAboveMph = 70,
		DangerAboveMph = 100,
		-- Road speed the sweep treats as full, and the number printed against the
		-- last major tick on the dial face.
		--
		-- 140 rather than 150 so the eight majors land on 0, 20, 40 ... 140. The
		-- numerals are derived from this and the segment count, so any other pair
		-- prints a dial reading 21.4, 42.9, 64.3, which is not a speedometer face.
		TopSpeedMph = 140,
		-- Segments in the cluster sweep, every third one a labelled major. Roblox
		-- has no arc primitive, so the dial's arc is built from discrete ticks.
		SweepSegments = 22,
		RpmValueName = "RPM",
		-- A-Chassis publishes a Vector3 velocity in Values. Prefer it over the
		-- seat assembly velocity, which can include vertical bounce or a detached
		-- wheel assembly and made the displayed speed disagree with the chassis.
		VelocityValueNames = { "Velocity", "LinearVelocity" },
		FuelValueNames = { "Fuel", "FuelLevel", "FuelPercent" },
		HandbrakeValueNames = { "Handbrake", "HandBrake", "ParkingBrake", "PBrake", "ParkBrake" },
		-- Driver aids. Two names each, because a chassis says separately whether a
		-- system is fitted and whether it is intervening this instant, and the
		-- cluster shows a different state for each. A vehicle publishing neither
		-- leaves both lamps dark, which is the honest reading for a car that has
		-- no ABS rather than one whose ABS is idle.
		-- Where the lighting addon keeps its state.
		--
		-- These vehicles already have working indicators, headlights, main beam and
		-- hazards: the A-Chassis lighting plugin binds Z and C to the indicators, X
		-- to the hazards and L to the light stages, and its server handler flips a
		-- BoolValue for each. None of it was on the cluster, so a driver had no way
		-- to tell a left indicator was still running.
		--
		-- Read rather than rebuilt, for the same reason the ELS panel drives the
		-- vehicle's own siren instead of playing its own: a second indicator system
		-- would fight the one already in the model, and the lamps belong to the kit.
		-- Each entry is a path from the vehicle model down to a BoolValue.
		-- A list of candidate paths per lamp, first one found wins. The kit is not
		-- consistent with itself: its handler writes hazards to Body.Lights.Hazards,
		-- but the models carry the value at Plugins.hazards instead, so a single
		-- path finds it on some vehicles and nothing on others.
		LightStatePaths = {
			IndicatorLeft = { { "Body", "Lights", "Left", "on" } },
			IndicatorRight = { { "Body", "Lights", "Right", "on" } },
			-- Three, because the value moves. The handler writes to Body.Lights.
			-- Hazards; the models author it at Plugins.hazards; and A-Chassis
			-- reparents its whole Plugins folder into the interface on initialise,
			-- so at runtime it is under A-Chassis Interface instead. Only the last
			-- of those is true on a spawned vehicle, and the first two are kept for
			-- vehicles authored differently.
			Hazards = {
				{ "A-Chassis Tune", "A-Chassis Interface", "hazards" },
				{ "Body", "Lights", "Hazards" },
				{ "A-Chassis Tune", "Plugins", "hazards" },
			},
			Headlight = { { "Body", "Lights", "Headlight", "on" } },
			MainBeam = { { "Body", "Lights", "Highlight", "on" } },
		},
		AbsValueNames = { "ABS", "Abs", "AntiLock" },
		AbsActiveValueNames = { "ABSActive", "AbsActive" },
		TcsValueNames = { "TCS", "Tcs", "TractionControl" },
		TcsActiveValueNames = { "TCSActive", "TcsActive" },
	},
	VehicleData = {
		-- Retained for speed enforcement and the replacement spawner integration;
		-- RoleplayOS no longer contains a vehicle spawning implementation.
		StudsPerSecondToMph = 0.626,
		-- Is fuel a system in this game at all?
		--
		-- Off. Consumption, the engine cut and the cluster's fuel gauge all go with
		-- it, because a gauge that reads the same number forever is the decoration
		-- this work set out to remove -- showing a permanent 100% would be worse
		-- than showing nothing.
		--
		-- The burn itself is kept rather than deleted, and is covered by the tests
		-- in tests/run.luau either way, so turning this back on is one line. The
		-- odometer is deliberately not gated behind it: mileage is a property of the
		-- vehicle that the MDT and the vehicle record both read, and it has nothing
		-- to do with whether anybody is buying petrol.
		FuelEnabled = false,
		-- Fuel burn, and the odometer that shares its measurement.
		--
		-- RoleplayOSFuel was written once at spawn and never touched again, so the
		-- cluster's fuel gauge showed the same figure for an entire session -- a
		-- readout that cannot change is decoration, not an instrument. Mileage was
		-- worse: the cluster read the attribute, the persisted profile carried the
		-- field, and nothing anywhere wrote either of them.
		--
		-- Both are now driven from distance travelled, measured server-side.
		--
		-- A mile is a real distance here, derived from StudsPerSecondToMph rather
		-- than invented: at K mph per stud/second, a mile is 3600/K studs, about
		-- 5750. A real car managing 400 miles to a tank would burn 0.25% per mile,
		-- which no player would ever notice inside one session, so this is
		-- compressed to roughly a 55 mile range.
		FuelPercentPerMile = 1.8,
		-- Burn while sitting still with the engine running. Real cars do this, and
		-- without it an idling car is a free generator.
		FuelPercentPerIdleMinute = 0.35,
		-- How often the burn loop runs. Distance is integrated between ticks from
		-- the vehicle's own velocity, so a slower tick costs accuracy rather than
		-- correctness, and this is a server loop over every occupied vehicle.
		ConsumptionIntervalSeconds = 2,
		-- Below this the engine will not run. Not zero, because a tank that reaches
		-- exactly zero and stops is harsher than one that splutters near empty.
		EmptyFuelPercent = 0.5,
		-- The fastest a vehicle is believed to go, used only to tell driving apart
		-- from teleporting in the burn loop. Matches the speedometer's dial range;
		-- kept separate from Chassis.TopSpeedMph because that one also decides what
		-- is printed on the dial face, and a guard should not move when a numeral
		-- does.
		TopSpeedMphCeiling = 140,
		-- Was "Compact", a car that is no longer in the project. Left empty
		-- rather than pointed at a bike: this is meant to be a free first car
		-- and nothing in the catalogue is that today. Name a definition here
		-- when the replacement fleet arrives.
		StarterDefinitionId = nil,
		StarterColour = "Blue",
		StarterGarageId = "CityGarage",
	},
	VehicleSpawners = {
		FolderName = "RoleplayOSVehicleFacilities",
		Tag = "RoleplayOSVehicleSpawner",
		MaximumInteractionDistance = 16,
		CooldownSeconds = 8,
		SpawnClearance = Vector3.new(14, 8, 24),
	},
	Dealerships = {
		CityMotors = {
			Id = "CityMotors",
			Name = "City Motors",
			-- Named here, and appended to automatically for any civilian model
			-- whose DealershipId attribute points at this forecourt.
			-- Every car named here was removed from the project deliberately, so
			-- the forecourt was advertising a fleet that no longer exists. The
			-- live list is in EDIT_HERE/06_Vehicles.luau, which merges over this.
			VehicleIds = {},
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
			-- Custody and EmergencyLights are named here rather than implied by
			-- the department, because both used to be. Anybody whose duty said
			-- Police could search, escort and book a detainee, and anybody in a
			-- department with a colour could run blue lights.
			Police = {
				"PersonSearch",
				"VehicleSearch",
				"IncidentWrite",
				"WarrantRead",
				"WarrantWrite",
				"Custody",
				"EmergencyLights",
			},
			Ambulance = { "PersonSearch", "IncidentRead", "EmergencyLights" },
			Fire = { "PersonSearch", "IncidentRead", "EmergencyLights" },
			Control = { "PersonSearch", "VehicleSearch", "IncidentRead", "Dispatch" },
			Highways = {
				"PersonSearch",
				"VehicleSearch",
				"IncidentWrite",
				"EmergencyLights",
			},
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
		MaximumOperationalNotes = 50,
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
	BankRobbery = {
		Tag = "RoleplayOSBankRobberyTarget",
		ActivationDistance = 12,
		CompletionDistance = 20,
		-- Free Creator Store emergency alarm; replace with a Universal Projects
		-- audio asset later if the group wants a branded bank tone.
		AlarmSoundId = "rbxassetid://7594301531",
		AlarmVolume = 0.45,
		AlarmMaxDistance = 150,
		-- Matches the purchased bank package's own robbery/reset timer so the
		-- RoleplayOS payout, alarm lifecycle and physical vault reset stay aligned.
		RobberyDurationSeconds = 200,
		CooldownSeconds = 400,
		FailedCooldownSeconds = 30,
		MinimumReward = 1800,
		MaximumReward = 4500,
	},
	Phone = {
		Enabled = true,
		MaximumMessageLength = 240,
		MaximumMessages = 200,
		EmergencyNumber = "999",
	},
	Taxi = {
		RequestRetentionSeconds = 900,
		MinimumJourneyStuds = 60,
		Bands = {
			Local = { Id = "Local", Name = "Local trip", Fare = 8 },
			City = { Id = "City", Name = "City trip", Fare = 14 },
			Long = { Id = "Long", Name = "Long trip", Fare = 22 },
		},
	},
	Needs = {
		WalkSpeed = 16,
		-- The sprint used to run from eighteen to twenty four, and it was the
		-- wrong way round: fastest at the instant you pressed it and slowest by
		-- the time you noticed, ending at eighteen against a walk of sixteen. The
		-- last seconds of every sprint were a twelve per cent difference nobody
		-- can see, which is why holding shift read as doing nothing.
		--
		-- The floor is raised so a tiring run is still visibly a run. Stamina
		-- decides how long you can run for; it should not decide whether running
		-- looks like walking.
		MinimumSprintSpeed = 22,
		MaximumSprintSpeed = 28,
		-- Fourteen a second emptied a full bar in seven seconds, and ten a second
		-- took ten to refill it: seven seconds of running bought with ten of
		-- walking. A sprint that short is over before it is useful.
		StaminaDrainPerSecond = 9,
		StaminaRecoveryPerSecond = 12,
		-- Fitness, earned rather than bought.
		--
		-- A character who has played gets more out of the same bar: it empties
		-- more slowly and fills faster. Drain and recovery are used rather than a
		-- larger maximum because the bar stays a plain nought to a hundred, so it
		-- reads the same on day one and day fifty and only behaves better.
		--
		-- Bounded deliberately. At the top of the curve a sprint lasts about
		-- eighteen seconds against eleven, which is a real difference to play
		-- with and not one that makes a veteran a different species.
		Fitness = {
			FullBonusLevel = 40,
			MaximumDrainReduction = 0.4,
			MaximumRecoveryBonus = 0.5,
		},
		HungerDrainPerSecond = 0.04,
		Foods = {
			Water = { Name = "Water", Price = 4, Hunger = 4 },
			Apple = { Name = "Apple", Price = 6, Hunger = 12 },
			Meal = { Name = "Hot meal", Price = 18, Hunger = 40 },
			Sandwich = { Name = "Sandwich", Price = 9, Hunger = 22 },
		},
		-- One item every character starts with, carried rather than bought.
		--
		-- Hunger drains from the moment somebody spawns and the only way to answer
		-- it was to already have money and already know where a vendor is. This is
		-- the one meal that is simply in the bag, so a new player finds out what
		-- hunger is by solving it once rather than by starving while they look.
		--
		-- Granted once per character, not once per life. A fresh one on every
		-- respawn would make it unlimited food for anybody willing to die for it.
		StarterFood = {
			Enabled = true,
			FoodId = "Sandwich",
		},
	},
	Network = {
		MaximumPayloadBytes = 8192,
		MaximumDepth = 8,
		MaximumNodes = 256,
		MaximumStringBytes = 2048,
		MaximumConcurrentRequests = 4,
		MaximumConcurrentRequestsPerServer = 64,
		-- How long a handler is given before the server answers without it.
		--
		-- Every endpoint here should reply in well under a second; anything
		-- approaching this is doing something it should not be doing inside a
		-- request. Set below the client's own patience so the server is what
		-- answers, rather than the client giving up on a server still thinking.
		HandlerTimeoutSeconds = 8,
		-- A request still running after this long is presumed lost and stops
		-- occupying a concurrency slot, so one stuck handler cannot refuse every
		-- later request from that player for the rest of the session.
		RequestAbandonSeconds = 30,
		GlobalCapacity = 30,
		GlobalRefillPerSecond = 10,
		Endpoints = {
			DropCash = { Capacity = 3, RefillPerSecond = 0.2 },
			GetRadioSnapshot = { Capacity = 5, RefillPerSecond = 1 },
			RadioSetChannel = { Capacity = 8, RefillPerSecond = 2 },
			RadioTransmit = { Capacity = 6, RefillPerSecond = 1 },
			RadioSetCallsign = { Capacity = 3, RefillPerSecond = 0.2 },
			RadioPanic = { Capacity = 2, RefillPerSecond = 0.05 },
			PAVASpray = { Capacity = 8, RefillPerSecond = 2 },
			GetFrameworkStatus = { Capacity = 4, RefillPerSecond = 1 },
			-- Flicked often on a response, so generous, but still bounded so a held
			-- key cannot become a packet flood.
			SetEmergencyLights = { Capacity = 8, RefillPerSecond = 3 },
			-- Indicators and headlights. A driver signalling at a junction taps
			-- these in quick succession, so the bucket is a little deeper than the
			-- ELS one, but a held key still cannot flood the server.
			SetVehicleLights = { Capacity = 10, RefillPerSecond = 4 },
			GetEmergencyLights = { Capacity = 5, RefillPerSecond = 1 },
			-- Reads every loaded profile in the server, so it is deliberately
			-- slower to refill than a lookup a player would repeat.
			GetShoulderNumberRoster = { Capacity = 3, RefillPerSecond = 0.2 },
			GetStartMenu = { Capacity = 4, RefillPerSecond = 1 },
			GetSettings = { Capacity = 4, RefillPerSecond = 1 },
			GetProgression = { Capacity = 4, RefillPerSecond = 1 },
			GetPublicProgressionHud = { Capacity = 4, RefillPerSecond = 1 },
			UpdateSettings = { Capacity = 6, RefillPerSecond = 1 },
			CreateCharacter = { Capacity = 2, RefillPerSecond = 0.1 },
			SelectCharacter = { Capacity = 3, RefillPerSecond = 0.5 },
			SaveCivilianAppearance = { Capacity = 2, RefillPerSecond = 0.1 },
			-- Read only and cheap, so the menu can ask whenever it repaints.
			GetAppearanceEditState = { Capacity = 6, RefillPerSecond = 1 },
			-- Answered from a table on the server, so effectively free.
			GetAvatarCatalogCategories = { Capacity = 4, RefillPerSecond = 0.5 },
			-- Reaches Roblox's catalogue when the answer is not already cached, and
			-- that quota is shared by everyone on the server. Generous enough to
			-- browse and type comfortably, tight enough that one client cannot
			-- spend the whole server's allowance.
			SearchAvatarCatalog = { Capacity = 8, RefillPerSecond = 1 },
			-- Writing an appearance ends the edit and may spend a purchase, so it
			-- is deliberately slow: a player has no legitimate reason to submit
			-- more than a couple in a row.
			SetAuthoredAppearance = { Capacity = 2, RefillPerSecond = 0.1 },
			SubmitApplication = { Capacity = 1, RefillPerSecond = 0.02 },
			MDTSearch = { Capacity = 5, RefillPerSecond = 0.5 },
			MDTCreateWarrant = { Capacity = 2, RefillPerSecond = 0.05 },
			MDTRevokeWarrant = { Capacity = 2, RefillPerSecond = 0.05 },
			MDTGetIncidents = { Capacity = 4, RefillPerSecond = 0.25 },
			MDTAddIncidentNote = { Capacity = 8, RefillPerSecond = 1 },
			GetMDTAccess = { Capacity = 4, RefillPerSecond = 1 },
			GetDispatchSnapshot = { Capacity = 6, RefillPerSecond = 1 },
			DispatchCreateCall = { Capacity = 4, RefillPerSecond = 0.5 },
			DispatchUpdateCall = { Capacity = 6, RefillPerSecond = 1 },
			DispatchAssignUnit = { Capacity = 8, RefillPerSecond = 1 },
			DispatchCloseCall = { Capacity = 4, RefillPerSecond = 0.5 },
			DispatchSetUnitStatus = { Capacity = 6, RefillPerSecond = 1 },
			GetCCTVCameras = { Capacity = 4, RefillPerSecond = 0.5 },
			GetOwnedVehicles = { Capacity = 4, RefillPerSecond = 0.5 },
			GetVehicleSpawnerMenu = { Capacity = 4, RefillPerSecond = 0.75 },
			SpawnVehicle = { Capacity = 2, RefillPerSecond = 0.15 },
			-- Deliberately tight. A purchase moves money and writes a permanent
			-- record, so it is the one vehicle call that must not be spammable.
			PurchaseVehicle = { Capacity = 3, RefillPerSecond = 0.2 },
			SetCustomVehicleRegistration = { Capacity = 2, RefillPerSecond = 0.08 },
			CuffPlayer = { Capacity = 3, RefillPerSecond = 0.3 },
			CustodyAction = { Capacity = 5, RefillPerSecond = 0.75 },
			GetCustodyPolicy = { Capacity = 3, RefillPerSecond = 0.2 },
			UseEarlyReleaseCredit = { Capacity = 2, RefillPerSecond = 0.1 },
			BookCustody = { Capacity = 2, RefillPerSecond = 0.1 },
			MeleeStrike = { Capacity = 8, RefillPerSecond = 4 },
			GetPresentedId = { Capacity = 4, RefillPerSecond = 0.5 },
			GetPhone = { Capacity = 5, RefillPerSecond = 1 },
			PhoneSendText = { Capacity = 5, RefillPerSecond = 0.5 },
			-- Money movement is intentionally slower than messaging. Every accepted
			-- request performs two persistent economy transactions.
			PhoneTransferFunds = { Capacity = 3, RefillPerSecond = 0.2 },
			PhonePlaceCall = { Capacity = 3, RefillPerSecond = 0.25 },
			PhoneAnswerCall = { Capacity = 3, RefillPerSecond = 0.5 },
			PhoneEndCall = { Capacity = 4, RefillPerSecond = 1 },
			PhoneEmergency = { Capacity = 2, RefillPerSecond = 0.1 },
			PhoneToggleFlashlight = { Capacity = 4, RefillPerSecond = 2 },
			TaxiRequest = { Capacity = 2, RefillPerSecond = 0.1 },
			TaxiAccept = { Capacity = 4, RefillPerSecond = 0.5 },
			TaxiDecline = { Capacity = 6, RefillPerSecond = 0.5 },
			TaxiComplete = { Capacity = 3, RefillPerSecond = 0.2 },
			TaxiCancel = { Capacity = 3, RefillPerSecond = 0.2 },
			TaxiStartShift = { Capacity = 2, RefillPerSecond = 0.1 },
			TaxiEndShift = { Capacity = 2, RefillPerSecond = 0.1 },
			-- Every sprint is two calls, one on press and one on release, and
			-- players tap this far more often than any other control.
			SetSprintState = { Capacity = 20, RefillPerSecond = 8 },
			PurchaseFood = { Capacity = 2, RefillPerSecond = 0.25 },
			PurchaseFromVendor = { Capacity = 3, RefillPerSecond = 0.3 },
			GetOfficialServers = { Capacity = 4, RefillPerSecond = 0.5 },
			-- A teleport is one action a player takes deliberately, never repeatedly.
			JoinOfficialServer = { Capacity = 2, RefillPerSecond = 0.1 },
			BeginDuty = { Capacity = 2, RefillPerSecond = 0.2 },
			EnterCivilian = { Capacity = 2, RefillPerSecond = 0.2 },
		},
	},
}

-- Ordinary game data lives in EDIT_HERE so a future maintainer does not need
-- to modify this framework-sized module. Overrides are recursive: a pass ID can
-- be replaced without copying its name, description or access rules.
-- EDIT_HERE sits beside this module, not inside it. The folder on disk holding
-- both becomes the Folder these are children of, so this module and EDIT_HERE
-- are siblings; reading it as a child found nothing, and the raise took the
-- whole configuration with it. Every controller requires this, so a client
-- whose configuration will not load has no interface at all: the start menu
-- simply never appeared, and the reason was three levels down a stack trace.
local editableFolder = script.Parent and script.Parent:FindFirstChild("EDIT_HERE")
	or script:FindFirstChild("EDIT_HERE")

-- The vehicle catalogue is intentionally empty until reviewed assets are
-- supplied. Keeping deleted vehicles in the base defaults makes the release
-- validator report templates that no longer exist and leaves stale dealership
-- entries available to runtime code.
Config.Vehicles = {}
Config.Dealerships = {}

local function editable(name: string): any
	local module = editableFolder and editableFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		-- Named plainly rather than left as an index error. A missing override
		-- file should say which one, not fail as "attempt to index nil".
		error("RoleplayOS configuration is missing EDIT_HERE/" .. name, 0)
	end
	return require(module)
end

local editableData = {
	editable("01_Deployment"),
	editable("02_Groups"),
	editable("03_Gamepasses"),
	editable("04_Uniforms"),
	editable("05_Balancing"),
	editable("06_Vehicles"),
}

local originalGamepassIds = {}
for id, definition in Config.Gamepasses do
	originalGamepassIds[id] = definition.GamepassId
end

local function applyOverride(target: any, override: any)
	for key, value in override do
		if type(value) == "table" and type(target[key]) == "table" then
			applyOverride(target[key], value)
		else
			target[key] = value
		end
	end
end

for _, override in editableData do
	applyOverride(Config, override)
end

-- Pass IDs also occur inside role and vehicle access rules. Rewrite those
-- references from the old ID to the edited ID so one change in 03_Gamepasses
-- cannot leave half of an entitlement on the previous experience.
local replacementGamepassIds = {}
for id, oldGamepassId in originalGamepassIds do
	local newGamepassId = Config.Gamepasses[id].GamepassId
	if newGamepassId ~= oldGamepassId then
		replacementGamepassIds[oldGamepassId] = newGamepassId
	end
end

local function updateGamepassReferences(value: any)
	if type(value) ~= "table" then
		return
	end
	for key, child in value do
		if key == "GamepassId" and type(child) == "number" then
			value[key] = replacementGamepassIds[child] or child
		elseif type(child) == "table" then
			updateGamepassReferences(child)
		end
	end
end

updateGamepassReferences(Config)

-- Imported-asset inventories are merged in rather than written out above.
--
-- Practically every system in this game is imported, and each import carries
-- dozens of executables that must be individually accounted for. Held inline,
-- the vehicles alone would add several hundred lines of generated path tables
-- to the middle of this file and bury the settings people actually edit. They
-- live in AssetManifests.luau instead, which is regenerated by tooling rather
-- than hand-edited.
--
-- An entry here always wins, so a hand-written certification in this file is
-- never silently replaced by a regenerated manifest.
for id, manifest in require(script.Parent.AssetManifests) do
	if Config.ContentQuality.CertifiedAssets[id] == nil then
		Config.ContentQuality.CertifiedAssets[id] = manifest
	end
end

return table.freeze(Config)
