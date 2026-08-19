--!strict

local Players = game:GetService("Players")

local CustomPlate = require(script.CustomPlate)
local DetailsPanel = require(script.DetailsPanel)
local CatalogueGrid = require(script.CatalogueGrid)

local VehicleSpawnerController = { connections = {}, promptConnections = {} }

local function spawnerFor(prompt: ProximityPrompt): Instance?
	local current = prompt.Parent
	while current and current ~= workspace do
		if type(current:GetAttribute("SpawnerId")) == "string" then
			return current
		end
		current = current.Parent
	end
	return nil
end

CustomPlate(VehicleSpawnerController)
DetailsPanel(VehicleSpawnerController)
CatalogueGrid(VehicleSpawnerController)

function VehicleSpawnerController:Init(context: any)
	self.context = context
end

function VehicleSpawnerController:_close()
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

function VehicleSpawnerController:_bind(prompt: ProximityPrompt)
	if self.promptConnections[prompt] then
		return
	end
	local spawner = spawnerFor(prompt)
	if not spawner then
		return
	end
	local spawnerId = spawner:GetAttribute("SpawnerId")
	if type(spawnerId) ~= "string" or spawnerId == "" then
		return
	end
	self.promptConnections[prompt] = prompt.Triggered:Connect(function()
		-- On a client, this signal represents the local player's completed
		-- interaction. Do not depend on the optional player argument: its shape
		-- differs between client and server prompt signals, which previously made
		-- a visible E prompt complete without ever opening the interface.
		self:_open(spawnerId)
	end)
end

function VehicleSpawnerController:Start()
	-- Shut when the thing it belongs to goes away.
	--
	-- The forecourt closed on its own buttons and on nothing else, so going
	-- civilian while it was open left it on screen over a world it no longer
	-- described, with a fleet the player could not use and no way back to the
	-- game but the close button they had already walked away from.
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function()
			self:_close()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			self:_close()
		end)
	)
	local player = Players.LocalPlayer
	table.insert(
		self.connections,
		player.CharacterRemoving:Connect(function()
			self:_close()
		end)
	)
	local folder = workspace:WaitForChild("RoleplayOSVehicleFacilities", 20)
	if not folder then
		return
	end
	for _, instance in folder:GetDescendants() do
		if instance:IsA("ProximityPrompt") then
			self:_bind(instance)
		end
	end
	table.insert(
		self.connections,
		folder.DescendantAdded:Connect(function(instance)
			if instance:IsA("ProximityPrompt") then
				task.defer(function()
					self:_bind(instance)
				end)
			end
		end)
	)
end

function VehicleSpawnerController:Destroy()
	self:_close()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for prompt, connection in self.promptConnections do
		connection:Disconnect()
		self.promptConnections[prompt] = nil
	end
	table.clear(self.connections)
	table.clear(self.promptConnections)
end

return VehicleSpawnerController
