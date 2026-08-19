--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local FuelConsumption = require(ReplicatedStorage.RoleplayOS.Shared.FuelConsumption)

local VehicleSpawnerService = {
	-- A broken or absent vehicle facility degrades that feature only. It must
	-- never prevent character, data, access, MDT, phone or custody startup.
	Critical = false,
	active = {},
	cooldowns = {},
	spawning = {},
	connections = {},
	-- Held per player and released when they leave, rather than appended to the
	-- flat list above, so a long server does not accumulate one closure per
	-- person who has ever played on it.
	deathConnections = {},
	spawnConnections = {},
	seatConnections = {},
	-- Per-vehicle odometer and tank state, keyed by owner user id. Held here
	-- rather than only on the model's attributes because the burn loop needs the
	-- previous position to integrate distance, and that is working state rather
	-- than something a client should be able to read.
	telemetry = {},
}

function VehicleSpawnerService:_vehicleDefinitions(): { [string]: any }
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinitions then
		return validator:GetVehicleDefinitions()
	end
	return self.context.Configuration.Vehicles
end

function VehicleSpawnerService:_vehicleDefinition(definitionId: string): any?
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetVehicleDefinition then
		return validator:GetVehicleDefinition(definitionId)
	end
	return self.context.Configuration.Vehicles[definitionId]
end

local function rootPosition(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function modelPosition(instance: Instance): Vector3?
	local interaction = instance:FindFirstChild("InteractionPoint", true)
	if interaction and interaction:IsA("BasePart") then
		return interaction.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

-- Stands anybody up before their seat stops existing.
--
-- A passenger left seated when the model is destroyed keeps the sitting state
-- with no seat beneath them: they float, cannot walk, and have to reset. That
-- applies to every route a vehicle disappears by, not only to the owner dying,
-- so it is done wherever one is destroyed.
local function ejectOccupants(vehicle: Instance)
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			local occupant = descendant.Occupant
			if occupant then
				occupant.Sit = false
				occupant:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end

-- Cuts anything the vehicle tied the rider to when they get off it.
--
-- Bike kits pose their rider by welding limbs to the machine, which is how the
-- riding position survives with no animation playing, and several of them never
-- undo it. The rider then walks away still joined to a bike that is no longer
-- moving with them: accessories hang off the head, limbs trail behind, and the
-- character reads as having come apart. Nothing is wrong with the avatar itself
-- -- it looks correct until the moment it is first mounted -- so the damage is
-- entirely in joints somebody else's script left behind.
--
-- Only joints with one end in the rider and the other in the vehicle are cut.
-- That is exactly the set the vehicle added and nothing else: the rig's own
-- joints have both ends in the character, and a held tool's weld does too, since
-- an equipped tool is parented into the character. Both sides are searched
-- because a kit may parent its welds to either.
local function detachRider(character: Model, vehicle: Instance): number
	local function inside(part: Instance?, root: Instance): boolean
		return part ~= nil and (part == root or part:IsDescendantOf(root))
	end
	local removed = 0
	for _, container in { character, vehicle } do
		for _, descendant in container:GetDescendants() do
			if
				not (
					descendant:IsA("Weld")
					or descendant:IsA("WeldConstraint")
					or descendant:IsA("Motor6D")
				)
			then
				continue
			end
			local joint = descendant :: any
			local first, second = joint.Part0, joint.Part1
			local firstInRider = inside(first, character)
			local secondInRider = inside(second, character)
			if
				(firstInRider and inside(second, vehicle))
				or (secondInRider and inside(first, vehicle))
			then
				descendant:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

-- The joints an R6 rig is built from, and what each one holds.
local R6_JOINTS = {
	{ Holder = "HumanoidRootPart", Joint = "RootJoint", Held = "Torso" },
	{ Holder = "Torso", Joint = "Neck", Held = "Head" },
	{ Holder = "Torso", Joint = "Left Shoulder", Held = "Left Arm" },
	{ Holder = "Torso", Joint = "Right Shoulder", Held = "Right Arm" },
	{ Holder = "Torso", Joint = "Left Hip", Held = "Left Leg" },
	{ Holder = "Torso", Joint = "Right Hip", Held = "Right Leg" },
}

local R6_BODY_PARTS = {
	HumanoidRootPart = true,
	Torso = true,
	Head = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

-- Puts an R6 rig back together after a vehicle took it apart.
--
-- detachRider cannot help with this one, and correctly so. The moped does not
-- weld the rider to itself: it dismantles the rider. On mounting it severs each
-- joint of an R6 character and replaces it with a rigid weld between the same
-- two body parts --
--
--     C.HumanoidRootPart.RootJoint.Part1 = nil
--     MW(C.HumanoidRootPart, C.Torso)
--
-- and does the same to the neck, both shoulders and both hips, keeping the
-- originals in a table to undo when the seat weld goes. Every one of those welds
-- has both ends inside the character, so the rule detachRider works by - one end
-- in the rider, one in the vehicle - cannot see them. That rule is right and
-- must stay: it is what stops it cutting the rig itself or a held tool.
--
-- When the kit's undo does not run, the rider walks away with RootJoint.Part1
-- nil and a weld holding the torso rigid, which is the torso stuck to the bike.
--
-- Only R6 is affected. The kit gates the whole block on the character having a
-- Torso, which an R15 rig does not, so this is a no-op on a modern avatar and
-- exists for players whose avatar is R6 under Player Choice.
local function restoreRig(character: Model): number
	local repaired = 0
	for _, entry in R6_JOINTS do
		local holder = character:FindFirstChild(entry.Holder)
		local held = character:FindFirstChild(entry.Held)
		local joint = holder and holder:FindFirstChild(entry.Joint)
		if joint and joint:IsA("Motor6D") and held and held:IsA("BasePart") then
			if joint.Part1 == nil then
				joint.Part1 = held
				repaired += 1
			end
		end
	end
	if repaired == 0 then
		return 0
	end
	-- The rigid welds the kit put in place of those joints. Both ends have to be
	-- body parts, which is exactly the set it created and nothing else: a tool's
	-- grip weld holds a Handle, and a Handle is not a body part.
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("Weld") then
			continue
		end
		local weld = descendant :: Weld
		local first, second = weld.Part0, weld.Part1
		if
			first
			and second
			and R6_BODY_PARTS[first.Name]
			and R6_BODY_PARTS[second.Name]
			and first.Parent == character
			and second.Parent == character
		then
			weld:Destroy()
		end
	end
	return repaired
end

-- The vehicle a seat belongs to: the outermost model it sits inside.
local function vehicleOf(seat: BasePart): Instance
	local root: Instance = seat
	while root.Parent and root.Parent ~= Workspace do
		root = root.Parent
	end
	return root
end

-- Hangs the rider's accessories on the bike's proxy head, which its own script
-- fails to do on an R15 avatar.
--
-- These kits hide the rider and show a dummy in the riding pose, then move each
-- accessory's weld onto the dummy's head so hats and hair still appear. The
-- dummy head is an invisible two by one by one proxy, one per rig:
--
--     R6   Misc.Anims.R6.Head.Parts.NewHead
--     R15  Misc.Anims.R15.Torso.Head.NewHead
--
-- The kit reaches for Misc.Anims.R15.NewHead, which is two levels short of where
-- that part actually lives. On an R6 rider the path is right and everything
-- works; on an R15 rider - which is every modern avatar - indexing nil throws,
-- and because the throw happens inside the loop over accessories, it takes the
-- whole loop with it on the first one. Nothing is repointed, so every accessory
-- stays welded to a head the kit has just hidden, and the rider's hat vanishes
-- with it.
--
-- Doing it here rather than correcting the script means the model is untouched
-- and needs no re-export, it survives the kit being re-imported, and it covers
-- the other two vehicles carrying the same script.
local function anchorAccessoriesToProxy(character: Model, vehicle: Instance): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local misc = vehicle:FindFirstChild("Misc")
	local anims = misc and misc:FindFirstChild("Anims")
	if not humanoid or not anims then
		return 0
	end
	local rig =
		anims:FindFirstChild(if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6")
	-- Found by name rather than by path, because the two rigs bury it at
	-- different depths and a third kit may bury it somewhere else again.
	local proxy = rig and rig:FindFirstChild("NewHead", true)
	if not proxy or not proxy:IsA("BasePart") then
		return 0
	end
	local head = character:FindFirstChild("Head")
	local moved = 0
	for _, accessory in character:GetChildren() do
		if not accessory:IsA("Accessory") then
			continue
		end
		local handle = accessory:FindFirstChild("Handle")
		local weld = handle and handle:FindFirstChild("AccessoryWeld")
		if not weld or not weld:IsA("Weld") then
			continue
		end
		-- Only the ones still on the rider's real head. Anything the kit already
		-- moved, or that hangs off a limb it does not pose, is left alone.
		--
		-- Checked on both ends, not just Part1: Roblox's own AddAccessory puts
		-- the body part on Part1, but reattachAccessories below rebuilds a weld
		-- the other way round when it restores one from a stray join. An
		-- accessory that went through that rebuild once and then mounted a
		-- second vehicle has Head on Part0, and a Part1-only check would leave
		-- it welded to a head this proxy is about to hide.
		if weld.Part1 == head then
			weld.Part1 = proxy
			moved += 1
		elseif weld.Part0 == head then
			weld.Part0 = proxy
			moved += 1
		end
	end
	return moved
end

-- Brings accessories back onto the rider when a vehicle kept hold of them.
--
-- Written first against the wrong theory. The guess was that kits clear the
-- character's joints and take the accessory welds with them, so this rebuilt any
-- weld that had gone missing. Reading the Sur-Ron's own FEAnims script showed
-- that is not what happens: it never destroys the weld, it repoints it.
--
--     -- mounting
--     Accessory.Part1 = bike.Misc.Anims.R6.Head.Parts.NewHead
--     -- dismounting
--     Accessory.Part1 = C.Head
--
-- The bike hides the rider and shows its own dummy rig, and hangs the rider's
-- hats on the dummy's head so they still appear. The weld survives; only its far
-- end moves. So a hunt for missing welds finds none and does nothing.
--
-- What does go wrong is the return trip. If the restore branch does not run -
-- the character respawning, the bike being removed underneath them, the player
-- leaving the seat by any path the kit did not anticipate - the accessory is
-- still welded to a dummy head on a bike the rider has walked away from, which
-- is the hat left hovering over the machine.
--
-- So this looks for accessories anchored into the vehicle rather than for
-- accessories anchored into nothing, and puts them back on the body part whose
-- attachment matches. Rebuilding a genuinely missing weld is kept as well, since
-- it costs nothing and another kit may yet do what the first theory described.
local function reattachAccessories(character: Model, vehicle: Instance?): number
	local attachments: { [string]: Attachment } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Parent:IsA("BasePart") then
			local part = descendant.Parent :: BasePart
			-- Body parts only. A handle's own attachment is the other half of the
			-- pair and must not be matched against itself.
			if not part:FindFirstAncestorWhichIsA("Accessory") then
				attachments[descendant.Name] = descendant
			end
		end
	end
	local restored = 0
	for _, accessory in character:GetChildren() do
		if not accessory:IsA("Accessory") then
			continue
		end
		local handle = accessory:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then
			continue
		end
		-- Held by the vehicle, or held by nothing. Either needs putting back;
		-- anything still joined to the rider is already correct and left alone.
		local stray: Instance? = nil
		local attached = false
		for _, joint in handle:GetChildren() do
			if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
				attached = true
				local far = (joint :: any).Part0
				if far == handle then
					far = (joint :: any).Part1
				end
				if vehicle ~= nil and far ~= nil and far:IsDescendantOf(vehicle) then
					stray = joint
					attached = false
				end
				break
			end
		end
		if attached then
			continue
		end
		if stray then
			stray:Destroy()
		end
		local handleAttachment: Attachment? = nil
		for _, child in handle:GetChildren() do
			if child:IsA("Attachment") and attachments[child.Name] then
				handleAttachment = child
				break
			end
		end
		local bodyAttachment = handleAttachment and attachments[handleAttachment.Name]
		if not handleAttachment or not bodyAttachment then
			continue
		end
		local weld = Instance.new("Weld")
		weld.Name = "AccessoryWeld"
		weld.Part0 = bodyAttachment.Parent :: BasePart
		weld.Part1 = handle
		weld.C0 = bodyAttachment.CFrame
		weld.C1 = handleAttachment.CFrame
		weld.Parent = handle
		handle.CanCollide = false
		handle.Massless = true
		restored += 1
	end
	return restored
end

-- Is the chassis finished building itself?
--
-- Measured by whether the seat has been unanchored. These templates are authored
-- with every part anchored -- 163 of them on the van -- and releasing them is
-- among the last things Initialize does, after it has created the runtime joints
-- and wired the drive system up. An anchored seat is a vehicle that is still
-- being assembled.
--
-- The obvious signal, the chassis Values folder, is not one: it ships inside the
-- template, so it is present before Initialize has run at all and a check against
-- it returns true immediately. That was the first attempt at this and it changed
-- nothing, because it was never false.
local function chassisReady(seat: VehicleSeat): boolean
	return seat.Parent ~= nil and not seat.Anchored
end

-- Puts the driver in the seat, once there is something to drive.
--
-- This used to sit them on the frame after the vehicle was parented, which is
-- before A-Chassis has finished initialising. The chassis binds its controls when
-- the seat is taken, so taking it too early bound nothing: the car would not
-- drive at all, and its interface never reached the player. Getting out and back
-- in fixed it, because by then initialisation had long finished -- which is
-- exactly the "jump out and back in before it works" this had.
--
-- Waiting on the chassis rather than on a fixed delay, because how long it takes
-- depends on the vehicle. The timeout still seats them on a vehicle that never
-- reports ready, since a car you cannot drive is better than one you cannot get
-- into.
local function seatPlayer(player: Player, seat: VehicleSeat)
	task.spawn(function()
		local deadline = os.clock() + 6
		while os.clock() < deadline and not chassisReady(seat) do
			if not seat.Parent then
				return
			end
			task.wait(0.1)
		end
		for _ = 1, 12 do
			if not seat.Parent or seat.Occupant then
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") then
				root.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
				task.wait()
				if seat.Parent and not seat.Occupant and humanoid.Parent then
					seat:Sit(humanoid)
				end
				if seat.Occupant == humanoid then
					return
				end
			end
			task.wait(0.25)
		end
	end)
end

-- Imported vehicle kits often bundle optional plugins for a different model
-- hierarchy. Running those plugins against a model without their expected
-- Body.Brakes, Body.Kickstand, SirenControl or sound nodes produces a tight
-- error loop and can consume several gigabytes over a session. The chassis,
-- seat, animation and native plate systems are deliberately left untouched.
local function removePath(root: Instance, path: { string }): boolean
	local current = root
	for index, segment in path do
		local child = current:FindFirstChild(segment)
		if not child then
			return false
		end
		if index == #path then
			child:Destroy()
			return true
		end
		current = child
	end
	return false
end

local function sanitiseImportedVehicle(vehicle: Model)
	local removed = 0
	local function remove(path: { string })
		if removePath(vehicle, path) then
			removed += 1
		end
	end

	-- Honda ADV/NCT optional plugins. The README says these are independent
	-- plugins; this particular model does not provide their required nodes.
	for _, path in
		{
			{ "Tuner", "Plugins", "Kickstand" },
			{ "Tuner", "Plugins", "LightAddon" },
			{ "Tuner", "Plugins", "AC6C_Style_Gauges" },
			{ "Tuner", "Plugins", "AC6_Sounds" },
			{ "Tuner", "Plugins", "EPICLIGHTS_V4" },
		}
	do
		remove(path)
	end

	-- Corolla optional legacy controls. Taxi lighting and sound are not sirens,
	-- and the framework owns the vehicle UI and emergency-lighting boundary.
	for _, path in
		{
			{ "DriveSeat", "Pickup" },
			{ "DriveSeat", "SirenControl" },
			{ "SmeersLightsHandler" },
			{ "AC6_FE_Sounds" },
		}
	do
		remove(path)
	end

	-- Audio nobody in this group can fetch.
	--
	-- These uploads belong to the people who built these kits, so the group cannot
	-- be granted access and the engine reports every one on each spawn -- the wind
	-- loop alone is carried by nine vehicles and accounts for most of the noise in
	-- the log.
	--
	-- Most of them are replaced rather than silenced, because the fleet already
	-- contains a working sound for the same job. The kits do not agree on which
	-- ignition or indicator sample to use, so the ones that happen to be locked
	-- can simply borrow the id from the ones that are not: every replacement below
	-- is an id already in use on other vehicles here and proven to load.
	local replacements = {
		-- Ignition crank. Ten vehicles already use this one.
		["370689846"] = "rbxassetid://906447701",
		-- Ignition second stage. Six kits ship this with no id at all, which
		-- arrives as a request for asset zero; three others fill it in with this.
		["0"] = "rbxassetid://6224906632",
		-- Indicator relay clicks, off and on, from the lighting kit four other
		-- vehicles carry.
		["10652911149"] = "rbxassetid://6212969290",
		["10652911247"] = "rbxassetid://6212969851",
		-- The helmet click has no equivalent anywhere, but it is the same kind of
		-- short mechanical tick, so it borrows the indicator's.
		["11503290062"] = "rbxassetid://6212969290",
	}

	-- Nothing in the fleet plays a wind loop or a tyre squeal, so there is nothing
	-- to borrow and these two are silenced instead.
	--
	-- Silenced rather than destroyed, and so is everything above. A kit plugin
	-- reaches its sounds by name and immediately uses them -- the ignition script
	-- does script:WaitForChild("Start1") and then car.DriveSeat.Start1:Play() --
	-- so taking the instance away does not merely error, it hangs that script on
	-- the WaitForChild forever. An empty SoundId asks the network for nothing and
	-- still leaves the plugin something to hold.
	local silenced = {
		["188608071"] = true,
		["201887209"] = true,
	}

	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Sound") then
			local id = string.match(descendant.SoundId, "%d+")
			-- Zero is only ever substituted on the ignition sound it belongs to. It
			-- is a blank field rather than a real id, so anything else carrying it
			-- is a different kit's oversight and gets silence rather than a crank.
			local swap = if id == "0" and descendant.Name ~= "Start2"
				then nil
				else replacements[id or ""]
			if swap then
				descendant.SoundId = swap
				removed += 1
			elseif id and (silenced[id] or id == "0") then
				descendant.SoundId = ""
				descendant.Volume = 0
				removed += 1
			end
		end
	end
	if removed > 0 then
		vehicle:SetAttribute("RoleplayOSSafelyAdapted", true)
	end
end

-- Removes the player's vehicle, whatever the reason.
function VehicleSpawnerService:Remove(userId: number)
	local vehicle = self.active[userId]
	-- Banked before the entry is cleared, and cleared before the destroy.
	--
	-- These two lines were the other way round, and it cost every driver their
	-- last stretch of mileage. The Destroying handler installed at spawn is
	-- guarded on `self.active[userId] == vehicle`, so clearing the entry first
	-- made that test false before the handler ran: the final flush that exists
	-- precisely for this never happened, and self.telemetry kept the destroyed
	-- model and its VehicleId for the life of the server, one entry per person who
	-- had ever driven.
	--
	-- This is the path taken when a player dies and when they leave, so the loss
	-- was up to fifteen seconds of driving every time, which is most of the reason
	-- an odometer would ever look wrong. The replacement path in Spawn already had
	-- the order right.
	self:_persistTelemetry(userId, true)
	self.telemetry[userId] = nil
	self.active[userId] = nil
	if vehicle and vehicle.Parent then
		ejectOccupants(vehicle)
		vehicle:Destroy()
	end
end

function VehicleSpawnerService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.VehicleSpawners
end

function VehicleSpawnerService:_folder(): Instance?
	return Workspace:FindFirstChild(self.settings.FolderName)
end

function VehicleSpawnerService:_spawner(spawnerId: string): Instance?
	local folder = self:_folder()
	if not folder then
		return nil
	end
	for _, instance in folder:GetDescendants() do
		if
			(instance:IsA("Model") or instance:IsA("BasePart"))
			and instance:GetAttribute("SpawnerId") == spawnerId
		then
			return instance
		end
	end
	return nil
end

function VehicleSpawnerService:_authorise(player: Player, spawnerId: string): (Instance?, string?)
	local spawner = self:_spawner(spawnerId)
	if not spawner then
		return nil, "SPAWNER_NOT_FOUND"
	end
	local playerPosition = rootPosition(player)
	local position = modelPosition(spawner)
	if not playerPosition or not position then
		return nil, "CHARACTER_NOT_READY"
	end
	if (playerPosition - position).Magnitude > self.settings.MaximumInteractionDistance then
		return nil, "SPAWNER_TOO_FAR"
	end
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		-- Taxi shifts are civilian employment, not a Transport duty profile.
		-- They still use the Transport depot, so authorise them through the
		-- employment credential before applying department-duty checks.
		if
			departmentId == "Transport"
			and self.context.Services:Get("TaxiService"):IsDriver(player)
		then
			return spawner, nil
		end
		local duty = self.context.Services:Get("DutyService"):Get(player)
		if not duty or duty.DepartmentId ~= departmentId then
			return nil, "WRONG_DEPARTMENT"
		end
		local divisionId = spawner:GetAttribute("DivisionId")
		if type(divisionId) == "string" and divisionId ~= "" and duty.DivisionId ~= divisionId then
			return nil, "WRONG_DIVISION"
		end
		return spawner, nil
	end
	-- A gang's own facility at its territory: the same shape, a different
	-- authority. The check is against who currently holds the territory, not
	-- against a name on the spawner itself, so a facility follows a contested
	-- zone through a flip without anything here needing to change.
	local territoryId = spawner:GetAttribute("TerritoryId")
	if type(territoryId) == "string" and territoryId ~= "" then
		local ownerGangId = self.context.Services:Get("GangTerritoryService"):OwnerOf(territoryId)
		local session = self.context.Services:Get("DataService"):GetSession(player)
		local gangId = session and session.Profile.GangId
		if not ownerGangId or type(gangId) ~= "string" or gangId ~= ownerGangId then
			return nil, "GANG_TERRITORY_NOT_HELD"
		end
	end
	return spawner, nil
end

function VehicleSpawnerService:_definitionAllowed(
	player: Player,
	spawner: Instance,
	definition: any
): boolean
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		-- Taxi is a public employment vehicle, but its operational bay belongs
		-- to Transport. Keep the Corolla civilian-owned/free while allowing an
		-- on-shift taxi driver to use the shared Transport fleet facility.
		if departmentId == "Transport" and definition.JobId == "TaxiDriver" then
			return definition.Fleet == true
				and self.context.Services:Get("TaxiService"):IsDriver(player)
		end
		if definition.Category ~= "Service" or definition.DepartmentId ~= departmentId then
			return false
		end
		-- Which unit's fleet this terminal is showing.
		--
		-- A terminal may name a division, in which case it is that unit's bay and
		-- only that unit's vehicles belong on it. Where it names none it serves
		-- the whole department from one place, and then the division that matters
		-- is the one the officer came on duty as - otherwise a single shared
		-- terminal hands every officer the keys to every unit's fleet.
		--
		-- Vehicles with no division of their own are the department's general
		-- stock and stay available either way.
		local divisionId = spawner:GetAttribute("DivisionId")
		if type(divisionId) ~= "string" or divisionId == "" then
			local duty = self.context.Services:Get("DutyService"):Get(player)
			divisionId = duty and duty.DivisionId
		end
		return type(divisionId) ~= "string"
			or divisionId == ""
			or definition.DivisionId == nil
			or definition.DivisionId == divisionId
	end
	-- Named explicitly rather than left to fall into the generic non-Civilian
	-- branch below: that branch authorises any Fleet vehicle regardless of
	-- category, which is looser than a gang facility should be.
	if definition.Category == "Gang" then
		return definition.Fleet == true
	end
	if definition.Category ~= "Civilian" then
		return definition.Fleet == true
	end
	if definition.Fleet == true and definition.JobId == "TaxiDriver" then
		return self.context.Services:Get("TaxiService"):IsDriver(player)
	end
	for _, vehicle in self.context.Services:Get("VehicleOwnershipService"):List(player) do
		if vehicle.DefinitionId == definition.Id then
			return true
		end
	end
	return false
end

-- A showroom copy of a vehicle, for the forecourt's 3D preview.
--
-- The templates live in ServerStorage and never reach a client, so a viewport
-- there has nothing to render. This publishes a stripped copy: geometry and
-- nothing else, with every script, sound, light, joint and value removed, so
-- what replicates is the shape of the car rather than a second working vehicle.
--
-- Built when somebody first opens a forecourt rather than at startup, so a
-- server whose players never visit a dealership never pays to replicate them.
function VehicleSpawnerService:_ensurePreview(definitionId: string, definition: any): Instance?
	local root = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
	if not root then
		root = Instance.new("Folder")
		root.Name = "RoleplayOSVehiclePreviews"
		root.Parent = ReplicatedStorage
	end
	local existing = root:FindFirstChild(definitionId)
	if existing then
		return existing
	end
	local template = self:_template(definition)
	if not template then
		return nil
	end
	local preview = template:Clone()
	preview.Name = definitionId
	for _, descendant in preview:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Sound")
			or descendant:IsA("Light")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Constraint")
			or descendant:IsA("JointInstance")
			or descendant:IsA("ValueBase")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("LayerCollector")
			or descendant:IsA("Configuration")
		then
			descendant:Destroy()
		end
	end
	for _, descendant in preview:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	preview.Parent = root
	return preview
end

function VehicleSpawnerService:Menu(player: Player, spawnerId: string): (any?, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return nil, reason
	end
	local vehicles = {}
	local departmentId = spawner:GetAttribute("DepartmentId")
	local territoryId = spawner:GetAttribute("TerritoryId")
	local isIssuedFacility = (type(departmentId) == "string" and departmentId ~= "")
		or (type(territoryId) == "string" and territoryId ~= "")
	if isIssuedFacility then
		for id, definition in self:_vehicleDefinitions() do
			local template = self:_template(definition)
			if self:_definitionAllowed(player, spawner, definition) and template then
				self:_ensurePreview(id, definition)
				table.insert(vehicles, {
					Id = id,
					Name = definition.Name,
					Category = definition.Category,
					DivisionId = definition.DivisionId,
					-- Issued, never sold. A department vehicle belongs to the unit
					-- rather than to the officer, so this terminal takes one out and
					-- has nothing to charge for. Saying so here is what stops the
					-- forecourt's buy flow from being offered at a police bay,
					-- where it read as a free car nobody could actually take.
					Spawnable = true,
				})
			end
		end
	else
		-- A forecourt, not a garage list.
		--
		-- This offered only what the player already owned, so the dealership's
		-- catalogue and every price in it were unreachable: there was no screen
		-- anywhere that showed a car for sale. Everything the forecourt sells is
		-- listed now, each entry saying whether this character owns one, and the
		-- owned copies are listed after it so a second Civic is a separate row
		-- with its own registration rather than a duplicate of the catalogue.
		local ownership = self.context.Services:Get("VehicleOwnershipService")
		local owned = ownership:List(player)
		local ownedByDefinition: { [string]: boolean } = {}
		for _, vehicle in owned do
			ownedByDefinition[vehicle.DefinitionId] = true
		end
		-- The forecourt this spawner sells from. Defaults to the only one
		-- configured rather than to the spawner's own name, which is
		-- CityDealership in the map and CityMotors in configuration.
		local dealershipId = spawner:GetAttribute("DealershipId") or "CityMotors"
		local dealership = self.context.Configuration.Dealerships[dealershipId]
		local forecourt = dealership and dealership.VehicleIds
		-- Where a spawner names no dealership, everything civilian is for sale
		-- rather than nothing, so a new forecourt is useful before it is
		-- configured rather than empty until somebody notices.
		if not forecourt then
			forecourt = {}
			for id, definition in self:_vehicleDefinitions() do
				if definition.Category == "Civilian" and definition.Fleet ~= true then
					table.insert(forecourt, id)
				end
			end
		end
		for _, definitionId in forecourt do
			local definition = self:_vehicleDefinition(definitionId)
			local template = definition and self:_template(definition)
			if definition and definition.Category == "Civilian" and template then
				local access =
					self.context.Services:Get("AccessService"):Evaluate(player, definition.Access)
				self:_ensurePreview(definitionId, definition)
				table.insert(vehicles, {
					Id = definitionId,
					Name = definition.Name,
					Category = "Civilian",
					Price = definition.Price,
					Colours = definition.Colours,
					Owned = ownedByDefinition[definitionId] == true,
					Locked = not access.Allowed,
					LockReason = if access.Allowed then nil else access.ReasonCode,
					ForSale = true,
				})
			end
		end
		for _, vehicle in owned do
			local definition = self:_vehicleDefinition(vehicle.DefinitionId)
			local template = definition and self:_template(definition)
			if definition and definition.Category == "Civilian" and template then
				table.insert(vehicles, {
					Id = vehicle.DefinitionId,
					VehicleId = vehicle.VehicleId,
					Name = definition.Name,
					Category = "Civilian",
					Registration = vehicle.Registration,
					Colour = vehicle.Colour,
					Fuel = vehicle.Fuel,
					Condition = vehicle.Condition,
					Mileage = vehicle.Mileage,
					Insured = vehicle.Insured,
					Taxed = vehicle.Taxed,
					Owned = true,
				})
			end
		end
	end
	table.sort(vehicles, function(a, b)
		-- What is for sale first, cheapest first, then the cars this character
		-- already keeps here. Sorting the two together interleaved a showroom
		-- entry with its own owned copies.
		if (a.ForSale == true) ~= (b.ForSale == true) then
			return a.ForSale == true
		end
		if a.ForSale == true and a.Price ~= b.Price then
			return (a.Price or 0) < (b.Price or 0)
		end
		if a.Name == b.Name then
			return tostring(a.Registration or a.VehicleId or "")
				< tostring(b.Registration or b.VehicleId or "")
		end
		return a.Name < b.Name
	end)
	return {
		SpawnerId = spawnerId,
		Name = spawner:GetAttribute("DisplayName") or spawner.Name,
		Vehicles = vehicles,
	},
		nil
end

function VehicleSpawnerService:AuthoriseCivilianFacility(
	player: Player,
	spawnerId: string
): (boolean, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return false, reason
	end
	local departmentId = spawner:GetAttribute("DepartmentId")
	if type(departmentId) == "string" and departmentId ~= "" then
		return false, "CIVILIAN_FACILITY_REQUIRED"
	end
	return true, nil
end

function VehicleSpawnerService:_template(definition: any): Model?
	local current: Instance? = ServerStorage:FindFirstChild("RoleplayOSAssets")
	-- Keep the former root as a development migration fallback only. Production
	-- must resolve from the canonical asset tree that real-baseplate.project.json
	-- owns and the deployment validator checks.
	if not current and self.context.Configuration.Framework.Environment ~= "Production" then
		current = ServerStorage:FindFirstChild("RoleplayOSVehicleTemplates")
	end
	for _, segment in definition.AssetPath or {} do
		current = current and current:FindFirstChild(segment) or nil
	end
	if current and current:IsA("Model") then
		return current
	end
	-- Development places may use parked authoring vehicles directly. This is
	-- deliberately unavailable in Production: a live Workspace chassis may
	-- already have initialised and must never become a reusable server template.
	if self.context.Configuration.Framework.Environment ~= "Production" then
		local source: Instance? = Workspace
		if type(definition.WorkspaceSourcePath) == "table" then
			for _, segment in definition.WorkspaceSourcePath do
				source = source and source:FindFirstChild(segment) or nil
			end
		else
			local sourceName = definition.WorkspaceModelName
			source = if type(sourceName) == "string" and sourceName ~= ""
				then Workspace:FindFirstChild(sourceName)
				else nil
		end
		if source and source:IsA("Model") then
			return source
		end
	end
	return nil
end

function VehicleSpawnerService:_bay(spawner: Instance): (BasePart?, string?)
	local points = spawner:FindFirstChild("SpawnPoints", true)
	if not points then
		return nil, "NO_SPAWN_POINTS"
	end
	for _, point in points:GetChildren() do
		if point:IsA("BasePart") then
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { spawner, point }
			local occupied = false
			for _, part in
				Workspace:GetPartBoundsInBox(point.CFrame, self.settings.SpawnClearance, params)
			do
				local model = part:FindFirstAncestorOfClass("Model")
				if
					model
					and (
						model:FindFirstChildWhichIsA("VehicleSeat", true)
						or model:FindFirstChildWhichIsA("Humanoid", true)
					)
				then
					occupied = true
					break
				end
			end
			if not occupied then
				return point, nil
			end
		end
	end
	return nil, "ALL_BAYS_OCCUPIED"
end

-- Imported vehicles rarely share the same pivot convention. Some use the
-- chassis centre, others the floor, and several have a pivot well outside the
-- visible body. Placing that arbitrary pivot on the bay surface can put the
-- wheels below the map, after which Roblox removes the falling assembly.
-- Position the vehicle by its actual bounding box instead.
function VehicleSpawnerService:_place(vehicle: Model, bay: BasePart)
	local pivot = vehicle:GetPivot()
	local boxCFrame, boxSize = vehicle:GetBoundingBox()
	local pivotToBox = pivot:ToObjectSpace(boxCFrame)
	local targetBox = bay.CFrame * CFrame.new(0, bay.Size.Y / 2 + boxSize.Y / 2 + 0.75, 0)
	vehicle:PivotTo(targetBox * pivotToBox:Inverse())
end

function VehicleSpawnerService:_guardInitialSpawn(vehicle: Model, bay: BasePart)
	local rescued = false
	task.spawn(function()
		local deadline = os.clock() + 10
		while vehicle.Parent and os.clock() < deadline do
			task.wait(0.25)
			local position = vehicle:GetPivot().Position
			-- Recover relative to the bay, before Roblox's FallenPartsDestroyHeight
			-- can delete the assembly. Waiting until the global destroy boundary is
			-- already crossed races the engine and is too late on low maps.
			if position.Y < bay.Position.Y - 18 then
				if rescued then
					self.context.Logger:Error("Spawned vehicle continued falling after recovery", {
						Vehicle = vehicle.Name,
						DefinitionId = vehicle:GetAttribute("RoleplayOSDefinitionId"),
					})
					return
				end
				rescued = true
				self:_place(vehicle, bay)
				self.context.Logger:Warning("Recovered a vehicle that fell through its bay", {
					Vehicle = vehicle.Name,
					DefinitionId = vehicle:GetAttribute("RoleplayOSDefinitionId"),
				})
			end
		end
	end)
end

function VehicleSpawnerService:Spawn(
	player: Player,
	spawnerId: string,
	definitionId: string,
	vehicleId: string?
): (any?, string?)
	local spawner, reason = self:_authorise(player, spawnerId)
	if not spawner then
		return nil, reason
	end
	local definition = self:_vehicleDefinition(definitionId)
	if not definition or not self:_definitionAllowed(player, spawner, definition) then
		return nil, "VEHICLE_NOT_ALLOWED"
	end
	local existing = self.active[player.UserId]
	if os.clock() - (self.cooldowns[player.UserId] or 0) < self.settings.CooldownSeconds then
		return nil, "SPAWN_COOLDOWN"
	end
	if self.spawning[player.UserId] then
		return nil, "SPAWN_IN_PROGRESS"
	end
	local bay, bayReason = self:_bay(spawner)
	if not bay then
		return nil, bayReason
	end
	local template = self:_template(definition)
	if not template then
		return nil, "VEHICLE_TEMPLATE_MISSING"
	end
	local vehicle = template:Clone()
	vehicle.Name = string.format("%s_%d", definition.ModelName or definitionId, player.UserId)
	sanitiseImportedVehicle(vehicle)
	local ownership = self.context.Services:Get("VehicleOwnershipService")
	local registration: string? = nil
	self.spawning[player.UserId] = true
	if definition.Category == "Service" or definition.Fleet == true then
		-- A gang facility has no DepartmentId, so its own fleet plates would
		-- otherwise file under the literal fallback "Service" alongside every
		-- other department-less Fleet vehicle. TerritoryId is what actually
		-- names this facility when DepartmentId does not.
		local teamName = spawner:GetAttribute("DepartmentId")
			or spawner:GetAttribute("TerritoryId")
			or "Service"
		local issuedRegistration, registrationReason =
			ownership:GetOrCreateTeamRegistration(player, tostring(teamName), definitionId)
		if not issuedRegistration then
			self.spawning[player.UserId] = nil
			vehicle:Destroy()
			return nil, registrationReason or "REGISTRATION_UNAVAILABLE"
		end
		registration = issuedRegistration
	else
		for _, owned in ownership:List(player) do
			if owned.DefinitionId == definitionId and owned.VehicleId == vehicleId then
				registration = owned.Registration
				break
			end
		end
		if not registration then
			self.spawning[player.UserId] = nil
			vehicle:Destroy()
			return nil, "VEHICLE_NOT_OWNED"
		end
	end
	if existing and existing.Parent then
		-- The replacement is now fully authorised and has a valid template and
		-- registration. Only at this point is the player's previous car removed,
		-- so a failed spawn can never leave them without their current vehicle.
		ejectOccupants(existing)
		existing:Destroy()
		self.active[player.UserId] = nil
	end
	vehicle:SetAttribute("RoleplayOSDefinitionId", definitionId)
	vehicle:SetAttribute("RoleplayOSOwnerUserId", player.UserId)
	-- Custom registrations are changed by persistent vehicle id, not by the
	-- catalogue definition. Without this attribute VehiclePlateService could not
	-- find the live clone, so the saved plate changed while the car in front of
	-- the player kept its old registration until it was spawned again.
	if type(vehicleId) == "string" and vehicleId ~= "" then
		vehicle:SetAttribute("RoleplayOSVehicleId", vehicleId)
	end
	self.context.Services:Get("VehiclePlateService"):Apply(vehicle, registration or "")
	-- A vehicle leaves the facility with a full tank, and carries its own
	-- odometer reading with it.
	--
	-- Fuel is burnt while driving now, which raises the question the previous
	-- comment here flagged: consumption with no way to refuel strands people. The
	-- map has no filling station, and building one blind -- against objects that
	-- do not exist to test against -- would be shipping something unverifiable.
	--
	-- Collecting the vehicle is the refuel instead. You are taking a car out of a
	-- depot or a garage, and it is fuelled when you do, which makes running dry a
	-- reason to go back for it rather than a dead end. The stored figure is still
	-- written throughout the drive, so the record and the MDT show the tank as it
	-- was last seen; it is simply topped up on the next collection.
	--
	-- Mileage is the opposite: it must survive the garage, because that is the
	-- entire point of an odometer.
	local mileage = 0
	if definition.Category == "Civilian" and type(vehicleId) == "string" then
		for _, owned in ownership:List(player) do
			if owned.VehicleId == vehicleId then
				if type(owned.Mileage) == "number" then
					mileage = owned.Mileage
				end
				break
			end
		end
	end
	if self.context.Configuration.VehicleData.FuelEnabled then
		vehicle:SetAttribute("RoleplayOSFuel", 100)
	end
	vehicle:SetAttribute("RoleplayOSMileage", mileage)
	local vehicleSeat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
	if vehicleSeat then
		vehicleSeat:SetAttribute("RoleplayOSRegistration", registration or "")
		vehicleSeat:SetAttribute("RoleplayOSOwnerUserId", player.UserId)
	end
	self:_place(vehicle, bay)
	vehicle.Parent = Workspace
	if vehicleSeat then
		seatPlayer(player, vehicleSeat)
	end
	-- ELS is deliberately framework-owned, but adoption was never called by the
	-- only service that creates framework vehicles. The server therefore had no
	-- tag/state to expose and every emergency-light controller correctly reported
	-- that the spawned car had no recognised lights.
	if type(definition.DepartmentId) == "string" then
		self.context.Services:Get("EmergencyLightsService"):Adopt(vehicle, definition.DepartmentId)
		-- A no-op on a vehicle with no EasyLS kit. On one that has it, this is
		-- what actually lights the bar EmergencyLightsService just silenced.
		self.context.Services:Get("EmergencyLightPatternService"):Adopt(vehicle)
	end
	-- Road lighting, which every vehicle has whether or not it is a service one.
	self.context.Services:Get("VehicleLightingService"):Adopt(vehicle)
	self:_removeStockGauges(vehicle)
	self.context.Services:Get("WorldBudgetService"):Normalise(vehicle)
	-- A-Chassis templates are intentionally authored anchored. Their Initialize
	-- script creates the runtime joints and unanchors the correct assemblies.
	-- Reapplying the template's anchored state after that initializer ran froze or
	-- tore down the newly-created chassis and was a primary disappearance cause.
	self:_guardInitialSpawn(vehicle, bay)
	self.active[player.UserId] = vehicle
	self:_beginTelemetry(player, vehicle, vehicleId, mileage)
	self.cooldowns[player.UserId] = os.clock()
	self.spawning[player.UserId] = nil
	vehicle.Destroying:Once(function()
		if self.active[player.UserId] == vehicle then
			self.active[player.UserId] = nil
			-- Last chance to bank the drive before the model goes.
			self:_persistTelemetry(player.UserId, true)
			self.telemetry[player.UserId] = nil
		end
	end)
	return {
		DefinitionId = definitionId,
		ModelName = vehicle.Name,
		Registration = registration,
	},
		nil
end

-- Fuel burn and the odometer.
--
-- Both readouts on the driver's cluster were decoration before this. Fuel was
-- written once at spawn and never touched, so the gauge showed one figure for a
-- whole session; mileage was read by the cluster and stored in the profile but
-- written by nothing at all, anywhere.
--
-- Distance is integrated server-side from the vehicle's own position between
-- ticks rather than trusted from the client, because fuel is an economic
-- quantity and mileage ends up on a record the MDT reads.

-- The chassis's own values folder, for the engine cut. Same problem the cluster
-- solves: plugins keep folders called Values too, so a folder is only accepted
-- when it can actually answer for the engine.
local function chassisValues(vehicle: Model, settings: any): Folder?
	local name = settings.ValuesFolderName
	for _, descendant in vehicle:GetDescendants() do
		if descendant.Name == name and descendant:IsA("Folder") then
			if descendant:FindFirstChild(settings.EngineValueName) then
				return descendant
			end
		end
	end
	return nil
end

function VehicleSpawnerService:_beginTelemetry(
	player: Player,
	vehicle: Model,
	vehicleId: string?,
	mileage: number
)
	local pivot = vehicle:GetPivot().Position
	self.telemetry[player.UserId] = {
		Vehicle = vehicle,
		VehicleId = vehicleId,
		Fuel = 100,
		Mileage = mileage,
		LastPosition = pivot,
		-- What was last written to the profile, so a tick that moved nothing does
		-- not mark the session dirty.
		PersistedFuel = nil,
		PersistedMileage = nil,
	}
end

-- Banks the current reading onto the owner's profile.
--
-- Rate limited by the caller except on the final call, which happens as the
-- vehicle is destroyed and must not be skipped.
function VehicleSpawnerService:_persistTelemetry(userId: number, force: boolean): boolean
	local state = self.telemetry[userId]
	if not state or type(state.VehicleId) ~= "string" then
		return false
	end
	if
		not force
		and state.PersistedFuel == state.Fuel
		and state.PersistedMileage == state.Mileage
	then
		return false
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false
	end
	local ownership = self.context.Services:Get("VehicleOwnershipService")
	local fuel = if self.context.Configuration.VehicleData.FuelEnabled then state.Fuel else nil
	local wrote = ownership:RecordTelemetry(player, state.VehicleId, fuel, state.Mileage)
	state.PersistedFuel = state.Fuel
	state.PersistedMileage = state.Mileage
	return wrote
end

-- Stops the engine when the tank is empty, and lets it run again once it is not.
--
-- Config.Chassis.EngineValueName has named this value since the config was
-- written and nothing had ever read it. A-Chassis makes its own torque from that
-- folder and never consults MaxSpeed, so cutting the engine is the only lever
-- that reaches these vehicles at all.
function VehicleSpawnerService:_setEngine(vehicle: Model, running: boolean)
	local settings = self.context.Configuration.Chassis
	local values = chassisValues(vehicle, settings)
	local engine = values and values:FindFirstChild(settings.EngineValueName)
	if engine and engine:IsA("ValueBase") and (engine :: any).Value ~= running then
		(engine :: any).Value = running
	end
end

function VehicleSpawnerService:_consumeTick(dt: number)
	local settings = self.context.Configuration.VehicleData
	for _, state in self.telemetry do
		local vehicle = state.Vehicle
		if not vehicle or not vehicle.Parent then
			continue
		end
		local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
		local position = vehicle:GetPivot().Position
		local previous = state.LastPosition or position
		state.LastPosition = position

		-- Only bills a vehicle somebody is sitting in. A car abandoned in the road
		-- is not burning anything, and this is also what stops the loop charging for
		-- the shove a spawner gives a vehicle as it sets it down.
		if not seat or seat.Occupant == nil then
			continue
		end

		-- Horizontal only. A vehicle dropped by the spawner, or bounced by a kerb,
		-- travels vertically without going anywhere, and neither the odometer nor
		-- the tank should record that as distance.
		local moved = (Vector3.new(position.X, 0, position.Z) - Vector3.new(
			previous.X,
			0,
			previous.Z
		)).Magnitude

		local miles, burnt = FuelConsumption.tick(moved, dt, settings)
		-- The odometer runs whether or not fuel is a system here. Mileage is a
		-- property of the vehicle that the MDT and the vehicle record both read.
		state.Mileage += miles
		vehicle:SetAttribute("RoleplayOSMileage", state.Mileage)

		if settings.FuelEnabled then
			state.Fuel = math.max(state.Fuel - burnt, 0)
			vehicle:SetAttribute("RoleplayOSFuel", state.Fuel)
			self:_setEngine(vehicle, state.Fuel > settings.EmptyFuelPercent)
		end
	end
end

-- Takes the chassis's own gauges out of a vehicle.
--
-- The cluster replaces them, and two separate pieces of code were previously
-- hiding them: VehicleUIController disabling the chassis ScreenGui, and the
-- speedometer hiding the gauge frame within it. Neither stopped the script, which
-- carried on writing a needle rotation and a speed string to an invisible frame
-- on every Velocity change for as long as anybody was driving.
--
-- The whole gauge frame goes rather than just the script, so there is nothing
-- left to be re-enabled by something else later. Done on the live clone only --
-- the template is a Rojo $path and would be overwritten on the next sync.
function VehicleSpawnerService:_removeStockGauges(vehicle: Model): number
	local names = self.context.Configuration.Chassis.StockGaugeScripts or {}
	local removed = 0
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("LocalScript") and table.find(names, descendant.Name) then
			-- The frame is the thing worth removing; the script rides inside it.
			local frame = descendant.Parent
			if frame and frame:IsA("GuiObject") then
				frame:Destroy()
			else
				descendant.Disabled = true
			end
			removed += 1
		end
	end
	return removed
end

-- Watches one player's seat, and cleans up after whatever they were riding.
function VehicleSpawnerService:_watchSeat(player: Player)
	local previous = self.seatConnections[player.UserId]
	if previous then
		previous:Disconnect()
		self.seatConnections[player.UserId] = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local lastVehicle: Instance? = nil
	self.seatConnections[player.UserId] = humanoid
		:GetPropertyChangedSignal("SeatPart")
		:Connect(function()
			local seat = humanoid.SeatPart
			if seat then
				local mounted = vehicleOf(seat)
				lastVehicle = mounted
				-- After the kit has had its go, so this picks up only what its broken
				-- R15 path left behind rather than racing it.
				task.delay(0.4, function()
					local body = player.Character
					if not body or humanoid.SeatPart ~= seat or not mounted.Parent then
						return
					end
					local moved = anchorAccessoriesToProxy(body, mounted)
					if moved > 0 then
						self.context.Logger:Info("Accessories hung on the vehicle's proxy head", {
							UserId = player.UserId,
							Vehicle = mounted.Name,
							AccessoriesMoved = moved,
						})
					end
				end)
				return
			end
			-- Just got off. Deferred by a frame so Roblox has finished removing
			-- its own seat weld before we look at what is left.
			local vehicle = lastVehicle
			lastVehicle = nil
			if not vehicle or not vehicle.Parent then
				return
			end
			task.defer(function()
				local body = player.Character
				if not body or not vehicle.Parent then
					return
				end
				-- Accessories first, then the rest of the joints.
				--
				-- Order matters: detachRider destroys every joint spanning the rider
				-- and the vehicle, and an accessory the kit left welded to its dummy
				-- head is one of those. Cutting first would leave the hat attached to
				-- nothing, which is a different way of losing it.
				local restored = reattachAccessories(body, vehicle)
				local removed = detachRider(body, vehicle)
				-- Last, because it is the only one that puts joints back rather than
				-- taking them away, and it must not have its work cut by the two
				-- above.
				local repaired = restoreRig(body)
				if removed > 0 or restored > 0 or repaired > 0 then
					self.context.Logger:Info("Rider released from a vehicle that kept hold", {
						UserId = player.UserId,
						Vehicle = vehicle.Name,
						JointsRemoved = removed,
						AccessoriesRestored = restored,
						RigJointsRepaired = repaired,
					})
				end
			end)
		end)
end

function VehicleSpawnerService:Start()
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:Remove(player.UserId)
			self.cooldowns[player.UserId] = nil
			self.spawning[player.UserId] = nil
			for _, held in { self.deathConnections, self.spawnConnections, self.seatConnections } do
				local connection = held[player.UserId]
				if connection then
					connection:Disconnect()
					held[player.UserId] = nil
				end
			end
		end)
	)
	-- The car goes when its driver does.
	--
	-- Nothing on this server reacted to a player dying, so a dead player's
	-- vehicle stayed in the world until they left it. Spawning again replaces
	-- it, so it was litter rather than a lock-out, but on a full server that is
	-- an abandoned car with physics and lights running for every death.
	--
	-- Died rather than CharacterRemoving, because a character is also removed
	-- for a team change or a manual respawn, and taking somebody's car for those
	-- is a broader rule than the one asked for. Re-armed on every character,
	-- since each respawn brings a new humanoid and a watch connected once at
	-- join stops firing the moment they first die.
	local function watchDeath(player: Player, character: Model)
		local found = character:FindFirstChildWhichIsA("Humanoid")
			or character:WaitForChild("Humanoid", 10)
		if not found or not found:IsA("Humanoid") or player.Character ~= character then
			return
		end
		local previous = self.deathConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.deathConnections[player.UserId] = found.Died:Connect(function()
			self:Remove(player.UserId)
		end)
	end
	local function watch(player: Player)
		local previous = self.spawnConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.spawnConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			watchDeath(player, character)
			-- Re-armed per character: the humanoid is a new instance after every
			-- respawn, so a watcher bound to the old one is watching nothing.
			self:_watchSeat(player)
		end)
		local character = player.Character
		if character then
			task.defer(function()
				if player.Parent and player.Character == character then
					watchDeath(player, character)
					self:_watchSeat(player)
				end
			end)
		end
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	-- The burn loop. One timer for every occupied vehicle rather than a connection
	-- per car, since the work is proportional to the number of drivers and there
	-- are never many.
	local interval = self.context.Configuration.VehicleData.ConsumptionIntervalSeconds
	self.consuming = true
	task.spawn(function()
		local lastPersist = os.clock()
		while self.consuming do
			task.wait(interval)
			if not self.consuming then
				break
			end
			local ok, err = pcall(function()
				self:_consumeTick(interval)
			end)
			if not ok then
				warn("[RoleplayOS] fuel tick failed: " .. tostring(err))
			end
			-- Written back far less often than it is calculated. The attributes on
			-- the model are what the cluster reads and they update every tick; the
			-- profile only needs the figure often enough to survive a disconnect.
			if os.clock() - lastPersist >= 15 then
				lastPersist = os.clock()
				for userId in self.telemetry do
					pcall(function()
						self:_persistTelemetry(userId, false)
					end)
				end
			end
		end
	end)
end

function VehicleSpawnerService:Destroy()
	self.consuming = false
	-- Bank every drive in progress before the server goes.
	for userId in self.telemetry do
		pcall(function()
			self:_persistTelemetry(userId, true)
		end)
	end
	table.clear(self.telemetry)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, vehicle in self.active do
		if vehicle.Parent then
			ejectOccupants(vehicle)
			vehicle:Destroy()
		end
	end
	for _, held in { self.deathConnections, self.spawnConnections } do
		for _, connection in held do
			connection:Disconnect()
		end
		table.clear(held)
	end
	table.clear(self.active)
	table.clear(self.spawning)
end

return VehicleSpawnerService
