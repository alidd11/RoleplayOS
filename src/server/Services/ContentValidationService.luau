--!strict

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local ContentValidationService = {
	-- Unsafe imported content is a server-wide trust failure, not an optional
	-- feature failure. Missing templates remain warnings in development, while
	-- an executable or malformed required asset prevents the server starting.
	Critical = true,
	report = { Ready = {}, Missing = {}, Invalid = {}, Discovered = {}, WorldReady = {} },
	assetIdentities = {},
	replacements = {},
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

local function unsafeDescendant(root: Instance, allowed: any?): Instance?
	for _, descendant in root:GetDescendants() do
		if forbiddenClasses[descendant.ClassName] or descendant:IsA("LuaSourceContainer") then
			-- A certified repository asset may carry narrowly reviewed framework
			-- logic. Both identity and class must match; similarly named arbitrary
			-- scripts or remotes remain unsafe and reject production startup.
			if type(allowed) ~= "table" or allowed[descendant.Name] ~= descendant.ClassName then
				return descendant
			end
		end
	end
	return nil
end

local function validCertificationText(value: any): boolean
	return type(value) == "string" and #value >= 3 and #value <= 240
end

local function qualityIssue(
	root: Instance,
	expectedClass: string,
	configuration: any,
	configuredAssetId: string?
): string?
	local quality = configuration.ContentQuality
	if not quality then
		return "CONTENT_QUALITY_CONFIG_REQUIRED"
	end
	if quality.RequireCertification then
		local manifest = if configuredAssetId and quality.CertifiedAssets
			then quality.CertifiedAssets[configuredAssetId]
			else nil
		local certified = root:GetAttribute("RoleplayOSAssetCertified")
		local reviewVersion = root:GetAttribute("RoleplayOSReviewVersion")
		local source = root:GetAttribute("RoleplayOSAssetSource")
		local realWorldReference = root:GetAttribute("RoleplayOSRealWorldReference")
		local reviewedBy = root:GetAttribute("RoleplayOSReviewedBy")
		if manifest then
			certified = manifest.Certified
			reviewVersion = manifest.ReviewVersion
			source = manifest.Source
			realWorldReference = manifest.RealWorldReference
			reviewedBy = manifest.ReviewedBy
		end
		if certified ~= true then
			return "CERTIFICATION_REQUIRED"
		end
		if reviewVersion ~= quality.CertificationVersion then
			return "CERTIFICATION_VERSION_INVALID"
		end
		if not validCertificationText(source) then
			return "ASSET_SOURCE_REQUIRED"
		end
		if not validCertificationText(realWorldReference) then
			return "REAL_WORLD_REFERENCE_REQUIRED"
		end
		if not validCertificationText(reviewedBy) then
			return "REVIEWER_REQUIRED"
		end
	end
	local parts = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	local maximumParts = if expectedClass == "Model"
		then quality.MaximumVehicleParts
		elseif expectedClass == "WorldAsset" then quality.MaximumWorldAssetParts
		else quality.MaximumToolParts
	local maximumDescendants = if expectedClass == "Model"
		then quality.MaximumVehicleDescendants
		elseif expectedClass == "WorldAsset" then quality.MaximumWorldAssetDescendants
		else quality.MaximumToolDescendants
	if parts == 0 then
		return "BASEPART_REQUIRED"
	end
	if parts > maximumParts then
		return "PART_BUDGET_EXCEEDED"
	end
	if #root:GetDescendants() > maximumDescendants then
		return "DESCENDANT_BUDGET_EXCEEDED"
	end
	if expectedClass == "Model" and root:IsA("Model") then
		local extent = root:GetExtentsSize()
		local minimum = quality.MinimumVehicleExtentStuds
		local maximum = quality.MaximumVehicleExtentStuds
		if extent.X < minimum or extent.Y < minimum or extent.Z < minimum then
			return "VEHICLE_SCALE_TOO_SMALL"
		end
		if extent.X > maximum or extent.Y > maximum or extent.Z > maximum then
			return "VEHICLE_SCALE_TOO_LARGE"
		end
	end
	return nil
end

function ContentValidationService:Init(context: any)
	self.context = context
	self.report = { Ready = {}, Missing = {}, Invalid = {}, Discovered = {}, WorldReady = {} }
	self.assetIdentities = {}
	self.replacements = {}
end

function ContentValidationService:_registerIdentity(root: Instance, fallbackId: string): boolean
	local rawId = root:GetAttribute("RoleplayOSAssetId")
	local assetId = if type(rawId) == "string" and rawId ~= "" then rawId else fallbackId
	if type(assetId) ~= "string" or assetId == "" or #assetId > 80 then
		table.insert(self.report.Invalid, "Asset:" .. root:GetFullName() .. ":INVALID_ASSET_ID")
		return false
	end
	local existing = self.assetIdentities[assetId]
	if existing and existing ~= root then
		table.insert(
			self.report.Invalid,
			"Asset:"
				.. assetId
				.. ":DUPLICATE_ID:"
				.. existing:GetFullName()
				.. ":"
				.. root:GetFullName()
		)
		return false
	end
	self.assetIdentities[assetId] = root
	local replaced = root:GetAttribute("RoleplayOSReplacesAssetId")
	if replaced ~= nil then
		if
			type(replaced) ~= "string"
			or replaced == ""
			or replaced == assetId
			or #replaced > 80
		then
			table.insert(self.report.Invalid, "Asset:" .. assetId .. ":INVALID_REPLACEMENT_ID")
			return false
		end
		self.replacements[assetId] = replaced
	end
	return true
end

function ContentValidationService:_verifyReplacements()
	for assetId, replacedId in self.replacements do
		if self.assetIdentities[replacedId] then
			table.insert(
				self.report.Invalid,
				"Asset:" .. assetId .. ":OBSOLETE_REPLACED_ASSET_STILL_PRESENT:" .. replacedId
			)
		end
	end
end

function ContentValidationService:_indexUnmanagedIdentities(roots: { Instance })
	for _, container in roots do
		for _, instance in container:GetDescendants() do
			local rawId = instance:GetAttribute("RoleplayOSAssetId")
			if type(rawId) == "string" and rawId ~= "" and not self.assetIdentities[rawId] then
				if self:_registerIdentity(instance, rawId) then
					local issue = "Asset:"
						.. rawId
						.. ":UNMANAGED_ASSET_ID:"
						.. instance:GetFullName()
					if self.context.Configuration.Framework.Environment == "Production" then
						table.insert(self.report.Invalid, issue)
					else
						table.insert(self.report.Missing, issue)
					end
				end
			end
		end
	end
end

local function worldQualityIssue(root: Instance, configuration: any): string?
	local quality = configuration.ContentQuality
	if not root:IsA("Model") then
		return "WORLD_ASSET_MODEL_REQUIRED"
	end
	if root:GetAttribute("RoleplayOSAssetKind") == nil then
		return "WORLD_ASSET_KIND_REQUIRED"
	end
	local certification = qualityIssue(root, "WorldAsset", configuration, nil)
	if certification then
		return certification
	end
	local extent = root:GetExtentsSize()
	if
		extent.X < quality.MinimumWorldAssetExtentStuds
		or extent.Y < quality.MinimumWorldAssetExtentStuds
		or extent.Z < quality.MinimumWorldAssetExtentStuds
	then
		return "WORLD_ASSET_SCALE_TOO_SMALL"
	end
	if
		extent.X > quality.MaximumWorldAssetExtentStuds
		or extent.Y > quality.MaximumWorldAssetExtentStuds
		or extent.Z > quality.MaximumWorldAssetExtentStuds
	then
		return "WORLD_ASSET_SCALE_TOO_LARGE"
	end
	return nil
end

function ContentValidationService:_checkWorldAssets()
	local quality = self.context.Configuration.ContentQuality
	local foundKinds = {}
	local worldRoot = workspace:FindFirstChild(quality.WorldAssetRootName)
	for _, root in CollectionService:GetTagged(quality.WorldAssetTag) do
		if not root:IsDescendantOf(workspace) then
			table.insert(self.report.Invalid, "WorldAsset:" .. root.Name .. ":NOT_IN_WORKSPACE")
			continue
		end
		local unsafe = unsafeDescendant(root)
		if unsafe then
			table.insert(
				self.report.Invalid,
				"WorldAsset:" .. root:GetFullName() .. ":UNSAFE_" .. string.upper(unsafe.ClassName)
			)
			continue
		end
		local problem = worldQualityIssue(root, self.context.Configuration)
		if problem then
			table.insert(self.report.Invalid, "WorldAsset:" .. root:GetFullName() .. ":" .. problem)
			continue
		end
		local kind = root:GetAttribute("RoleplayOSAssetKind")
		if type(kind) ~= "string" or not table.find(quality.RequiredWorldAssetKinds, kind) then
			table.insert(
				self.report.Invalid,
				"WorldAsset:" .. root:GetFullName() .. ":UNKNOWN_KIND"
			)
			continue
		end
		if
			not worldRoot
			or not root.Parent
			or root.Parent.Name ~= kind
			or root.Parent.Parent ~= worldRoot
		then
			table.insert(
				self.report.Invalid,
				"WorldAsset:" .. root:GetFullName() .. ":WRONG_WORLD_ASSET_FOLDER"
			)
			continue
		end
		local rawId = root:GetAttribute("RoleplayOSAssetId")
		if type(rawId) ~= "string" or rawId == "" then
			table.insert(
				self.report.Invalid,
				"WorldAsset:" .. root:GetFullName() .. ":ASSET_ID_REQUIRED"
			)
			continue
		end
		if not self:_registerIdentity(root, rawId) then
			continue
		end
		foundKinds[kind] = true
		table.insert(self.report.WorldReady, kind .. ":" .. root:GetFullName())
	end
	for _, kind in quality.RequiredWorldAssetKinds do
		if not foundKinds[kind] then
			local issue = "WorldAssetKind:" .. kind .. ":CERTIFIED_ASSET_REQUIRED"
			if self.context.Configuration.Framework.Environment == "Production" then
				table.insert(self.report.Invalid, issue)
			else
				table.insert(self.report.Missing, issue)
			end
		end
	end
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
		local issue = kind .. ":" .. id .. ":" .. table.concat(path, "/")
		if self.context.Configuration.Framework.Environment == "Production" then
			table.insert(self.report.Invalid, issue .. ":REQUIRED_TEMPLATE_MISSING")
		else
			table.insert(self.report.Missing, issue)
		end
		return
	end
	if not template:IsA(expectedClass) then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":WRONG_CLASS")
		return
	end
	local declaredId = template:GetAttribute("RoleplayOSAssetId")
	if declaredId ~= nil and declaredId ~= id then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":CONFIG_ID_MISMATCH")
		return
	end
	local manifest = self.context.Configuration.ContentQuality.CertifiedAssets[id]
	local unsafe =
		unsafeDescendant(template, if manifest then manifest.AllowedUnsafeDescendants else nil)
	if unsafe then
		table.insert(
			self.report.Invalid,
			kind .. ":" .. id .. ":UNSAFE_" .. string.upper(unsafe.ClassName)
		)
		return
	end
	local qualityProblem = qualityIssue(template, expectedClass, self.context.Configuration, id)
	if qualityProblem then
		table.insert(self.report.Invalid, kind .. ":" .. id .. ":" .. qualityProblem)
		return
	end
	if not self:_registerIdentity(template, id) then
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
	local quality = self.context.Configuration.ContentQuality
	local quarantine = workspace:FindFirstChild(quality.QuarantineRootName)
		or ServerStorage:FindFirstChild(quality.QuarantineRootName)
	if quarantine and #quarantine:GetDescendants() > 0 then
		local issue = "Quarantine:"
			.. quarantine:GetFullName()
			.. ":OBSOLETE_ASSETS_MUST_BE_DELETED"
		if self.context.Configuration.Framework.Environment == "Production" then
			table.insert(self.report.Invalid, issue)
		else
			table.insert(self.report.Missing, issue)
		end
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	if not assets then
		if self.context.Configuration.Framework.Environment == "Production" then
			table.insert(self.report.Invalid, "ContentRoot:RoleplayOSAssets:REQUIRED")
		else
			self.context.Logger:Warning("RoleplayOS content root is missing", {})
		end
	else
		self:_discover(assets)
		for id, definition in self.context.Configuration.Vehicles do
			self:_check(assets, "Vehicle", id, definition, "Model")
		end
		for id, definition in self.context.Configuration.Tools do
			self:_check(assets, "Tool", id, definition, "Tool")
		end
	end
	self:_checkWorldAssets()
	local identityRoots = {}
	local worldRoot = workspace:FindFirstChild(quality.WorldAssetRootName)
	if worldRoot then
		table.insert(identityRoots, worldRoot)
	end
	if quarantine then
		table.insert(identityRoots, quarantine)
	end
	if assets then
		table.insert(identityRoots, assets)
	end
	self:_indexUnmanagedIdentities(identityRoots)
	self:_verifyReplacements()
	self.context.Logger:Info("RoleplayOS content audit complete", {
		Ready = #self.report.Ready,
		Missing = #self.report.Missing,
		Invalid = #self.report.Invalid,
		Discovered = #self.report.Discovered,
		WorldReady = #self.report.WorldReady,
	})
	for _, issue in self.report.Invalid do
		self.context.Logger:Error("Invalid RoleplayOS content", { Issue = issue })
	end
	for _, issue in self.report.Missing do
		self.context.Logger:Warning("Missing RoleplayOS content", { Issue = issue })
	end
	-- The development baseplate is where unsafe imports are deliberately opened,
	-- audited and replaced. Keep them unavailable and visible in its report, but
	-- do not empty the test server before developers can inspect the problem.
	-- Production remains fail-closed: no live server starts with rejected content.
	if
		#self.report.Invalid > 0
		and self.context.Configuration.Framework.Environment == "Production"
	then
		error("RoleplayOS content audit rejected unsafe or invalid required content")
	end
end

function ContentValidationService:GetReport(): any
	return {
		Ready = table.clone(self.report.Ready),
		Missing = table.clone(self.report.Missing),
		Invalid = table.clone(self.report.Invalid),
		Discovered = table.clone(self.report.Discovered),
		WorldReady = table.clone(self.report.WorldReady),
	}
end

function ContentValidationService:Destroy()
	table.clear(self.report.Ready)
	table.clear(self.report.Missing)
	table.clear(self.report.Invalid)
	table.clear(self.report.Discovered)
	table.clear(self.report.WorldReady)
	table.clear(self.assetIdentities)
	table.clear(self.replacements)
end

return ContentValidationService
