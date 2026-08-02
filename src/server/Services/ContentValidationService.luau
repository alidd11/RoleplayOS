--!strict

local ServerStorage = game:GetService("ServerStorage")

local ContentValidationService = {
	report = { Ready = {}, Missing = {}, Invalid = {}, Discovered = {} },
}

local forbiddenClasses = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	UnreliableRemoteEvent = true,
	BindableEvent = true,
	BindableFunction = true,
	ProximityPrompt = true,
	ClickDetector = true,
}

local function resolve(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, segment in path do
		current = current and current:FindFirstChild(segment) or nil
	end
	return current
end

local function unsafeDescendant(root: Instance): Instance?
	for _, descendant in root:GetDescendants() do
		if forbiddenClasses[descendant.ClassName] or descendant:IsA("LuaSourceContainer") then
			return descendant
		end
	end
	return nil
end

function ContentValidationService:Init(context: any)
	self.context = context
	self.report = { Ready = {}, Missing = {}, Invalid = {}, Discovered = {} }
end

local function pathFor(instance: Instance, root: Instance): { string }
	local reversed = {}
	local current: Instance? = instance
	while current and current ~= root do
		table.insert(reversed, current.Name)
		current = current.Parent
	end
	local path = {}
	for index = #reversed, 1, -1 do
		table.insert(path, reversed[index])
	end
	return path
end

local function roleIdsFor(configuration: any, departmentId: string, divisionId: string?): { string }
	local result = {}
	local explicit = {
		Frontline = { "PoliceOfficer", "PoliceFrontline" },
		ArmedResponse = { "ArmedResponseOfficer" },
		RoadsPolicing = { "RoadsPolicingOfficer" },
	}
	if divisionId and explicit[divisionId] then
		return table.clone(explicit[divisionId])
	end
	for roleId, role in configuration.Roles do
		if role.DepartmentId == departmentId then
			table.insert(result, roleId)
		end
	end
	return result
end

local function appendUnique(list: { string }, value: string)
	if not table.find(list, value) then
		table.insert(list, value)
	end
end

function ContentValidationService:_discoverVehicle(assets: Instance, model: Model)
	local path = pathFor(model, assets)
	if #path < 4 or path[1] ~= "Vehicles" then
		return
	end
	local id = model:GetAttribute("RoleplayOSAssetId") or model.Name
	if type(id) ~= "string" or id == "" then
		table.insert(self.report.Invalid, "Vehicle:" .. model:GetFullName() .. ":INVALID_ID")
		return
	end
	local existing = self.context.Configuration.Vehicles[id]
	if existing then
		if table.concat(existing.AssetPath or {}, "/") ~= table.concat(path, "/") then
			table.insert(self.report.Invalid, "Vehicle:" .. id .. ":DUPLICATE_OR_WRONG_FOLDER")
		end
		return
	end
	local definition: any = {
		Id = id,
		Name = model:GetAttribute("DisplayName") or model.Name,
		ModelName = model.Name,
		AssetPath = path,
		Price = model:GetAttribute("Price") or 0,
		Colours = { model:GetAttribute("DefaultColour") or "Default" },
	}
	if path[2] == "Civilian" then
		definition.Category = "Civilian"
		definition.Starter = path[3] == "Starter"
		local gamepassId = model:GetAttribute("GamepassId")
		definition.Access = if type(gamepassId) == "number" and gamepassId > 0
			then { AccessType = "Gamepass", GamepassId = gamepassId, DisplayWhenLocked = true }
			else { AccessType = "Public" }
		local price = model:GetAttribute("Price")
		if path[3] ~= "Starter" and (type(price) ~= "number" or price < 0) then
			table.insert(self.report.Invalid, "Vehicle:" .. id .. ":PRICE_ATTRIBUTE_REQUIRED")
			return
		end
		local dealershipId = model:GetAttribute("DealershipId") or "CityMotors"
		local dealership = self.context.Configuration.Dealerships[dealershipId]
		if not dealership then
			table.insert(self.report.Invalid, "Vehicle:" .. id .. ":UNKNOWN_DEALERSHIP")
			return
		end
		appendUnique(dealership.VehicleIds, id)
	elseif path[2] == "Services" then
		local departmentId = path[3]
		if not self.context.Configuration.Departments[departmentId] then
			table.insert(self.report.Invalid, "Vehicle:" .. id .. ":UNKNOWN_DEPARTMENT")
			return
		end
		local divisionId = if departmentId == "Police" and path[4] ~= "Shared" then path[4] else nil
		definition.Category = "Service"
		definition.TeamName = departmentId
		definition.DepartmentId = departmentId
		definition.DivisionId = divisionId
		definition.RoleIds = roleIdsFor(self.context.Configuration, departmentId, divisionId)
		definition.Access = { AccessType = "Public", DisplayWhenLocked = false }
	else
		return
	end
	self.context.Configuration.Vehicles[id] = definition
	table.insert(self.report.Discovered, "Vehicle:" .. id)
end

function ContentValidationService:_discoverTool(assets: Instance, tool: Tool)
	local path = pathFor(tool, assets)
	if #path < 3 or path[1] ~= "Tools" then
		return
	end
	local id = tool:GetAttribute("RoleplayOSAssetId") or tool.Name
	if type(id) ~= "string" or id == "" then
		table.insert(self.report.Invalid, "Tool:" .. tool:GetFullName() .. ":INVALID_ID")
		return
	end
	local existing = self.context.Configuration.Tools[id]
	if existing then
		if table.concat(existing.AssetPath or {}, "/") ~= table.concat(path, "/") then
			table.insert(self.report.Invalid, "Tool:" .. id .. ":DUPLICATE_OR_WRONG_FOLDER")
		end
		return
	end
	local definition: any = { Id = id, AssetPath = path }
	local targetLoadouts = {}
	if path[2] == "Shared" then
		for loadoutId in self.context.Configuration.Loadouts do
			table.insert(targetLoadouts, loadoutId)
		end
	elseif path[2] == "Services" then
		local departmentId = path[3]
		definition.DepartmentId = departmentId
		local divisionId = if departmentId == "Police" and path[4] ~= "Shared" then path[4] else nil
		for _, roleId in roleIdsFor(self.context.Configuration, departmentId, divisionId) do
			local role = self.context.Configuration.Roles[roleId]
			if role and role.LoadoutId then
				appendUnique(targetLoadouts, role.LoadoutId)
			end
		end
	elseif path[2] ~= "Civilian" then
		return
	end
	self.context.Configuration.Tools[id] = definition
	if tool:GetAttribute("AutoEquip") ~= false then
		for _, loadoutId in targetLoadouts do
			local loadout = self.context.Configuration.Loadouts[loadoutId]
			if loadout then
				loadout.ToolIds = loadout.ToolIds or {}
				appendUnique(loadout.ToolIds, id)
			end
		end
	end
	table.insert(self.report.Discovered, "Tool:" .. id)
end

function ContentValidationService:_discover(assets: Instance)
	local vehicles = assets:FindFirstChild("Vehicles")
	if vehicles then
		for _, descendant in vehicles:GetDescendants() do
			if
				descendant:IsA("Model")
				and descendant.Parent
				and descendant.Parent:IsA("Folder")
			then
				self:_discoverVehicle(assets, descendant)
			end
		end
	end
	local tools = assets:FindFirstChild("Tools")
	if tools then
		for _, descendant in tools:GetDescendants() do
			if descendant:IsA("Tool") then
				self:_discoverTool(assets, descendant)
			end
		end
	end
end

function ContentValidationService:_check(
	assets: Instance,
	kind: string,
	id: string,
	definition: any,
	expectedClass: string
)
	local path = definition.AssetPath
	if type(path) ~= "table" then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":ASSET_PATH_REQUIRED")
		return
	end
	local template = resolve(assets, path)
	if not template then
		table.insert(self.report.Missing, kind .. ":" .. id .. ":" .. table.concat(path, "/"))
		return
	end
	if not template:IsA(expectedClass) then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":WRONG_CLASS")
		return
	end
	local unsafe = unsafeDescendant(template)
	if unsafe then
		table.insert(
			self.report.Invalid,
			kind .. ":" .. id .. ":UNSAFE_" .. string.upper(unsafe.ClassName)
		)
		return
	end
	if expectedClass == "Model" and not template:FindFirstChildWhichIsA("VehicleSeat", true) then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":DRIVER_SEAT_REQUIRED")
		return
	end
	if
		expectedClass == "Tool"
		and template.RequiresHandle
		and not template:FindFirstChild("Handle")
	then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":HANDLE_REQUIRED")
		return
	end
	table.insert(self.report.Ready, kind .. ":" .. id)
end

function ContentValidationService:Start()
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	if not assets then
		self.context.Logger:Warning("RoleplayOS content root is missing", {})
		return
	end
	self:_discover(assets)
	for id, definition in self.context.Configuration.Vehicles do
		self:_check(assets, "Vehicle", id, definition, "Model")
	end
	for id, definition in self.context.Configuration.Tools do
		self:_check(assets, "Tool", id, definition, "Tool")
	end
	self.context.Logger:Info("RoleplayOS content audit complete", {
		Ready = #self.report.Ready,
		Missing = #self.report.Missing,
		Invalid = #self.report.Invalid,
		Discovered = #self.report.Discovered,
	})
	for _, issue in self.report.Invalid do
		self.context.Logger:Error("Invalid RoleplayOS content", { Issue = issue })
	end
	for _, issue in self.report.Missing do
		self.context.Logger:Warning("Missing RoleplayOS content", { Issue = issue })
	end
	if #self.report.Invalid > 0 then
		error("RoleplayOS content audit rejected unsafe or invalid required content")
	end
end

function ContentValidationService:GetReport(): any
	return {
		Ready = table.clone(self.report.Ready),
		Missing = table.clone(self.report.Missing),
		Invalid = table.clone(self.report.Invalid),
		Discovered = table.clone(self.report.Discovered),
	}
end

function ContentValidationService:Destroy()
	table.clear(self.report.Ready)
	table.clear(self.report.Missing)
	table.clear(self.report.Invalid)
	table.clear(self.report.Discovered)
end

return ContentValidationService
