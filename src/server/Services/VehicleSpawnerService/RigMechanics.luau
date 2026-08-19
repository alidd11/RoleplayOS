--!strict

local Workspace = game:GetService("Workspace")

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

return {
	rootPosition = rootPosition,
	modelPosition = modelPosition,
	ejectOccupants = ejectOccupants,
	detachRider = detachRider,
	restoreRig = restoreRig,
	vehicleOf = vehicleOf,
	anchorAccessoriesToProxy = anchorAccessoriesToProxy,
	reattachAccessories = reattachAccessories,
	chassisReady = chassisReady,
	seatPlayer = seatPlayer,
	removePath = removePath,
	sanitiseImportedVehicle = sanitiseImportedVehicle,
	chassisValues = chassisValues,
}
