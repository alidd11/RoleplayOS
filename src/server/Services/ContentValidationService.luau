--!strict

local ServerStorage = game:GetService("ServerStorage")

local ContentValidationService = { report = { Ready = {}, Missing = {}, Invalid = {} } }

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
	self.report = { Ready = {}, Missing = {}, Invalid = {} }
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
	}
end

function ContentValidationService:Destroy()
	table.clear(self.report.Ready)
	table.clear(self.report.Missing)
	table.clear(self.report.Invalid)
end

return ContentValidationService
