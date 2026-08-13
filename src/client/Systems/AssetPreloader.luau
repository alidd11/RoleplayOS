--!strict

local ContentProvider = game:GetService("ContentProvider")

local AssetPreloader = {}
AssetPreloader.__index = AssetPreloader

export type Context = {
	Configuration: any,
}

function AssetPreloader.new(context: Context)
	local self = setmetatable({}, AssetPreloader)
	self.context = context
	self.progress = 0
	self.phase = "idle"
	self.onProgress = Instance.new("BindableEvent")
	self.onPhaseChange = Instance.new("BindableEvent")
	self.criticalAssets = {}
	self.backgroundAssets = {}
	self._started = false
	return self
end

local function addAsset(target: { any }, value: any)
	if typeof(value) == "Instance" or (typeof(value) == "string" and value ~= "") then
		-- Asset ids, paths, and Instances are accepted by PreloadAsync.
		table.insert(target, value)
	end
end

function AssetPreloader:_discoverAssets()
	local config = self.context.Configuration
	local critical = {}
	local background = {}

	local explicit = config.AssetPreload
	if explicit then
		for _, asset in explicit.Critical or {} do
			addAsset(critical, asset)
		end
		for _, asset in explicit.Background or {} do
			addAsset(background, asset)
		end
	end

	local discovered = {}
	if config.Vehicles then
		for _, vehicle in config.Vehicles do
			addAsset(discovered, vehicle.Model)
			addAsset(discovered, vehicle.Template)
		end
	end
	if config.CertifiedAssets then
		for _, asset in config.CertifiedAssets do
			if asset.ModelId and asset.ModelId ~= "" then
				addAsset(discovered, "rbxassetid://" .. tostring(asset.ModelId))
			end
			addAsset(discovered, asset.Image)
		end
	end
	if config.EmergencyLighting then
		for _, value in config.EmergencyLighting do
			if typeof(value) == "string" and string.find(value, "rbxassetid://", 1, true) then
				addAsset(discovered, value)
			end
		end
	end
	if config.Departments then
		for _, department in config.Departments do
			addAsset(discovered, department.BadgeImage)
		end
	end

	local seen = {}
	local function appendUnique(target: { any }, value: any)
		local key = tostring(value)
		if not seen[key] then
			seen[key] = true
			table.insert(target, value)
		end
	end
	for _, asset in critical do
		appendUnique(self.criticalAssets, asset)
	end
	for _, asset in background do
		appendUnique(self.backgroundAssets, asset)
	end

	local remaining = {}
	for _, asset in discovered do
		local key = tostring(asset)
		if not seen[key] then
			table.insert(remaining, asset)
		end
	end
	local splitPoint = math.ceil(#remaining * 0.6)
	for index, asset in remaining do
		appendUnique(
			if index <= splitPoint then self.criticalAssets else self.backgroundAssets,
			asset
		)
	end
end

function AssetPreloader:_setPhase(phase: string)
	self.phase = phase
	self.onPhaseChange:Fire(phase)
end

function AssetPreloader:_preload(assets: { any }, startProgress: number, endProgress: number)
	if #assets == 0 then
		self.progress = endProgress
		self.onProgress:Fire(self.progress)
		return
	end
	for index, asset in assets do
		local success, err = pcall(function()
			ContentProvider:PreloadAsync({ asset })
		end)
		if not success then
			warn("[AssetPreloader] Failed to preload asset", tostring(asset), err)
		end
		self.progress = startProgress + (index / #assets) * (endProgress - startProgress)
		self.onProgress:Fire(self.progress)
	end
end

function AssetPreloader:Start()
	if self._started then
		return
	end
	self._started = true
	self:_discoverAssets()
	task.spawn(function()
		self:_setPhase("critical")
		self:_preload(self.criticalAssets, 0, 0.8)
		self:_setPhase("interactive")
		self:_setPhase("background")
		self:_preload(self.backgroundAssets, 0.8, 1)
		self.progress = 1
		self.onProgress:Fire(1)
		self:_setPhase("complete")
	end)
end

function AssetPreloader:Destroy()
	self.onProgress:Destroy()
	self.onPhaseChange:Destroy()
end

return AssetPreloader
