--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigMechanics = require(script.RigMechanics)

local VehicleSpawnerService = {
	running = false,
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
	-- Explicit physics ownership for managed vehicles, keyed by the live model.
	-- Entries exist only while a driver owns at least one unanchored assembly.
	networkOwners = {},
	-- Per-vehicle odometer and tank state, keyed by owner user id. Held here
	-- rather than only on the model's attributes because the burn loop needs the
	-- previous position to integrate distance, and that is working state rather
	-- than something a client should be able to read.
	telemetry = {},
	-- Showroom previews are stripped geometry kept in ReplicatedStorage so the
	-- client can build its ViewportFrames. They are an idle cache, not gameplay
	-- state, and are expired by Authorisation after a long quiet period.
	previewLastUsed = {},
}
require(script.Authorisation)(VehicleSpawnerService)
require(script.Spawning)(VehicleSpawnerService)
require(script.Telemetry)(VehicleSpawnerService)
require(script.SeatLifecycle)(VehicleSpawnerService)

function VehicleSpawnerService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.VehicleSpawners
	self.running = false
	self.previewCleaning = true
	self.networkOwners = {}
end

-- Returns the one live framework-owned vehicle for this player when it is the
-- exact persistent vehicle requested. This keeps callers on the spawner's
-- authoritative active map instead of rediscovering a clone through Workspace.
function VehicleSpawnerService:GetActiveOwnedVehicle(ownerUserId: number, vehicleId: string): Model?
	local vehicle = self.active[ownerUserId]
	if
		not vehicle
		or not vehicle.Parent
		or vehicle:GetAttribute("RoleplayOSOwnerUserId") ~= ownerUserId
		or vehicle:GetAttribute("RoleplayOSVehicleId") ~= vehicleId
	then
		return nil
	end
	return vehicle
end

function VehicleSpawnerService:Start()
	self.running = true
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:_releasePlayerNetworkOwnership(player)
			self:Remove(player.UserId)
			self.cooldowns[player.UserId] = nil
			-- Spawn claims are keyed by the exact Player instance. A rejoin may
			-- reuse the same UserId while an old yielding handler is still unwinding;
			-- clearing only this Player cannot release the new session's claim.
			self.spawning[player] = nil
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
		if not self.running then
			return
		end
		local found = character:FindFirstChildWhichIsA("Humanoid")
			or character:WaitForChild("Humanoid", 10)
		if
			not self.running
			or player.Parent ~= Players
			or Players:GetPlayerByUserId(player.UserId) ~= player
			or not found
			or not found:IsA("Humanoid")
			or player.Character ~= character
		then
			return
		end
		local previous = self.deathConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.deathConnections[player.UserId] = found.Died:Connect(function()
			if self.running then
				self:Remove(player.UserId)
			end
		end)
	end
	local function watch(player: Player)
		if not self.running then
			return
		end
		local previous = self.spawnConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		self.spawnConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			watchDeath(player, character)
			-- Re-armed per character: the humanoid is a new instance after every
			-- respawn, so a watcher bound to the old one is watching nothing.
			if self.running and player.Character == character then
				self:_watchSeat(player)
			end
		end)
		local character = player.Character
		if character then
			task.defer(function()
				if
					self.running
					and player.Parent == Players
					and Players:GetPlayerByUserId(player.UserId) == player
					and player.Character == character
				then
					watchDeath(player, character)
					if self.running and player.Character == character then
						self:_watchSeat(player)
					end
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
	-- Preview models are useful while a catalogue is being browsed, but retaining
	-- every vehicle's stripped geometry for the whole server lifetime needlessly
	-- raises the server and replication footprint on quiet long-running servers.
	-- The expiry is deliberately long: ordinary dealership use never notices it,
	-- while an abandoned catalogue eventually releases its cache.
	task.spawn(function()
		while self.previewCleaning do
			task.wait(300)
			if self.previewCleaning then
				self:_prunePreviews()
			end
		end
	end)
end

function VehicleSpawnerService:Destroy()
	self.running = false
	self.consuming = false
	self.previewCleaning = false
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
	table.clear(self.connections)
	-- Destroying a vehicle clears its own active entry through the spawn-time
	-- Destroying watcher. Snapshot first so mutating self.active from that callback
	-- cannot make this teardown iterator skip another framework-owned vehicle.
	local activeVehicles = {}
	for _, vehicle in self.active do
		table.insert(activeVehicles, vehicle)
	end
	for _, vehicle in activeVehicles do
		if vehicle.Parent then
			RigMechanics.ejectOccupants(vehicle)
			vehicle:Destroy()
		end
	end
	for _, held in { self.deathConnections, self.spawnConnections, self.seatConnections } do
		for _, connection in held do
			connection:Disconnect()
		end
		table.clear(held)
	end
	table.clear(self.active)
	table.clear(self.networkOwners)
	table.clear(self.cooldowns)
	table.clear(self.spawning)
	local previewRoot = ReplicatedStorage:FindFirstChild("RoleplayOSVehiclePreviews")
	if previewRoot then
		previewRoot:Destroy()
	end
	table.clear(self.previewLastUsed)
end

return VehicleSpawnerService
