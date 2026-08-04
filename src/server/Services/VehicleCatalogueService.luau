--!strict

-- Builds the vehicle catalogue from the asset folders.
--
-- Every vehicle used to need a hand written configuration entry naming its own
-- asset path, which is workable for ten and hopeless for the hundreds this game
-- expects. A car dropped into the right folder now appears in the right section
-- on its own, and the folder it sits in is what decides where that is.
--
--   Vehicles/Civilian/<Tier>/<Model>
--   Vehicles/Services/<Department>/<Model>
--   Vehicles/Services/<Department>/<Division>/<Model>
--
-- Anything that needs to differ from the defaults is an attribute on the model
-- itself, set in Studio next to the car rather than in a file somewhere else:
--
--   Price        number   what it costs
--   Colours      string   comma separated, first is the default
--   GamepassId   number   locks it behind a pass, still shown in the showroom
--   DisplayName  string   overrides the name derived from the model name
--   RoleIds      string   comma separated, restricts a service vehicle
--   Starter      boolean  granted to a new character
--
-- Discovered entries are merged into the configuration rather than kept beside
-- it, so every existing reader sees them without knowing this service exists. A
-- hand written entry always wins, so the vehicles tuned by hand keep their
-- values and this only fills in what nobody has spoken for.

local ServerStorage = game:GetService("ServerStorage")

local VehicleCatalogueService = { discovered = {} }

local function split(value: any): { string }
	if type(value) ~= "string" or value == "" then
		return {}
	end
	local parts = {}
	for piece in string.gmatch(value, "[^,]+") do
		local trimmed = string.match(piece, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(parts, trimmed)
		end
	end
	return parts
end

-- "PoliceResponse" reads as "Police response" rather than being left to appear
-- in the showroom as a class name.
local function prettify(name: string): string
	local spaced = string.gsub(name, "(%l)(%u)", "%1 %2")
	spaced = string.gsub(spaced, "(%u)(%u%l)", "%1 %2")
	return (string.upper(string.sub(spaced, 1, 1)) .. string.sub(spaced, 2))
end

function VehicleCatalogueService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.VehicleCatalogue
end

function VehicleCatalogueService:_definitionFrom(model: Instance, path: { string }): any?
	-- path is everything below the Vehicles folder, ending with the model name.
	local root = path[1]
	if not root or #path < 2 then
		return nil
	end
	local service = root == "Services"
	local price = tonumber(model:GetAttribute("Price"))
	local colours = split(model:GetAttribute("Colours"))
	local gamepassId = tonumber(model:GetAttribute("GamepassId"))
	local roleIds = split(model:GetAttribute("RoleIds"))

	local definition: any = {
		Id = model.Name,
		Name = model:GetAttribute("DisplayName") or prettify(model.Name),
		ModelName = model.Name,
		AssetPath = table.clone(path),
		Colours = if #colours > 0 then colours else { self.settings.DefaultColour },
		Category = if service then "Service" else "Civilian",
		Price = price or (if service then 0 else self.settings.DefaultPrice),
		Discovered = true,
	}
	table.insert(definition.AssetPath, 1, "Vehicles")

	if service then
		-- Services/<Department>/[<Division>/]<Model>
		definition.DepartmentId = path[2]
		definition.TeamName = path[2]
		if #path >= 4 then
			definition.DivisionId = path[3]
		end
		if #roleIds > 0 then
			definition.RoleIds = roleIds
		end
	else
		definition.Tier = path[2]
		if model:GetAttribute("Starter") == true then
			definition.Starter = true
		end
	end

	if gamepassId then
		definition.Access = {
			AccessType = "Gamepass",
			GamepassId = gamepassId,
			DisplayWhenLocked = true,
		}
	elseif not service then
		definition.Access = { AccessType = "Public" }
	end
	return definition
end

function VehicleCatalogueService:_walk(instance: Instance, path: { string })
	for _, child in instance:GetChildren() do
		local nextPath = table.clone(path)
		table.insert(nextPath, child.Name)
		if child:IsA("Model") then
			local definition = self:_definitionFrom(child, nextPath)
			if definition then
				local existing = self.context.Configuration.Vehicles[definition.Id]
				if existing then
					-- Hand written wins. A configured vehicle has usually been
					-- tuned deliberately, and silently replacing it with folder
					-- defaults would undo that without saying so.
					if existing.Discovered ~= true then
						continue
					end
				end
				self.context.Configuration.Vehicles[definition.Id] = definition
				self.discovered[definition.Id] = definition
			end
		elseif child:IsA("Folder") then
			self:_walk(child, nextPath)
		end
	end
end

function VehicleCatalogueService:All(): { [string]: any }
	return self.context.Configuration.Vehicles
end

function VehicleCatalogueService:Discovered(): { [string]: any }
	return self.discovered
end

-- Whether a vehicle sits under one of the folder paths a dealership sells from.
-- This is what makes a car appear on the right forecourt from where it was put
-- rather than from a list somebody has to remember to update.
function VehicleCatalogueService:MatchesPath(definition: any, prefix: { string }): boolean
	local path = definition and definition.AssetPath
	if type(path) ~= "table" then
		return false
	end
	for index, segment in prefix do
		-- Offset by one: AssetPath starts with the Vehicles folder itself, which
		-- a dealership never names.
		if path[index + 1] ~= segment then
			return false
		end
	end
	return true
end

function VehicleCatalogueService:Start()
	if not self.settings.Enabled then
		return
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local vehicles = if assets then assets:FindFirstChild("Vehicles") else nil
	if not vehicles then
		self.context.Logger:Warning(
			"No vehicle assets folder, so nothing was discovered",
			{ Expected = "ServerStorage.RoleplayOSAssets.Vehicles" }
		)
		return
	end
	self:_walk(vehicles, {})
	local count = 0
	for _ in self.discovered do
		count += 1
	end
	self.context.Logger:Info("Vehicle catalogue built from folders", { Discovered = count })
end

function VehicleCatalogueService:Destroy()
	table.clear(self.discovered)
end

return VehicleCatalogueService
