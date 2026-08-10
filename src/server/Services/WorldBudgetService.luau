--!strict

local Workspace = game:GetService("Workspace")

-- Imported content decides how expensive it is to draw, and it almost always
-- decides wrong.
--
-- Streaming answers "how far away does the world stop existing". It does not
-- answer "how much does the world cost while it is here". A vehicle exported
-- from a modelling tool arrives with every mesh at full detail at every
-- distance, every lamp casting a real shadow, and every sound audible across
-- the map, because those are the defaults of the tool it came from rather than
-- choices anybody made about this game.
--
-- Nothing here is a visual decision. Each one replaces "always the most
-- expensive option" with "the expensive option only when it is close enough to
-- see", which is the whole of what a level of detail system is.
local WorldBudgetService = { connections = {}, applied = nil }

type Counts = {
	Meshes: number,
	Models: number,
	Lights: number,
	Sounds: number,
}

local function newCounts(): Counts
	return { Meshes = 0, Models = 0, Lights = 0, Sounds = 0 }
end

function WorldBudgetService:Init(context: any)
	self.context = context
end

function WorldBudgetService:_settings(): any
	return self.context.Configuration.Performance
end

-- Applies the budget to one instance. Returns which counter to bump, so the
-- caller can report what it changed rather than what it looked at.
function WorldBudgetService:_apply(instance: Instance, counts: Counts)
	local settings = self:_settings()

	if instance:IsA("MeshPart") then
		-- Precise holds every triangle at every distance. Automatic is Roblox's
		-- own distance based detail: full detail close up, cheaper further out.
		-- This is the single largest saving available on imported vehicles,
		-- which are exported as Precise almost without exception.
		if settings.MeshLevelOfDetail then
			-- RenderFidelity is visible to ordinary scripts but Roblox currently
			-- restricts writes to plugin-capability threads. A spawn endpoint must
			-- never fail because a cosmetic optimisation is unavailable.
			local ok, changed = pcall(function()
				if instance.RenderFidelity ~= Enum.RenderFidelity.Precise then
					return false
				end
				instance.RenderFidelity = Enum.RenderFidelity.Automatic
				return true
			end)
			if ok and changed then
				counts.Meshes += 1
			end
		end
		return
	end

	if instance:IsA("Model") then
		-- Distant models are drawn as one low detail mesh instead of as all of
		-- their parts. Only meaningful with streaming on, which is why it is set
		-- here and not left to the map.
		-- Roblox currently exposes Model.LevelOfDetail to Studio plugins but can
		-- reject the same read from a server Script with "lacking capability
		-- Plugin". Imported A-Chassis models hit that path while being spawned.
		-- Keep the optimisation best-effort so an engine capability change can
		-- never abort the gameplay endpoint that created the model.
		if settings.ModelLevelOfDetail then
			local ok, changed = pcall(function()
				if instance.LevelOfDetail ~= Enum.ModelLevelOfDetail.Disabled then
					return false
				end
				instance.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
				return true
			end)
			if ok and changed then
				counts.Models += 1
			end
		end
		return
	end

	if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		local changed = false
		-- A shadow casting light is far more expensive than a light, and a
		-- lightbar is a dozen of them strobing. This is the difference between
		-- an emergency vehicle being free to look at and being the reason the
		-- frame rate falls whenever one drives past.
		if settings.DisableLightShadows and instance.Shadows then
			instance.Shadows = false
			changed = true
		end
		if
			settings.MaximumLightRangeStuds > 0
			and instance.Range > settings.MaximumLightRangeStuds
		then
			instance.Range = settings.MaximumLightRangeStuds
			changed = true
		end
		if changed then
			counts.Lights += 1
		end
		return
	end

	if instance:IsA("Sound") then
		-- A siren with the default rolloff is mixed for every player in the
		-- server rather than for the ones near it.
		if
			settings.MaximumSoundDistanceStuds > 0
			and instance.RollOffMaxDistance > settings.MaximumSoundDistanceStuds
		then
			instance.RollOffMaxDistance = settings.MaximumSoundDistanceStuds
			counts.Sounds += 1
		end
	end
end

-- Applies the budget to something the startup walk will never reach.
--
-- Vehicles are cloned from templates held outside the workspace, so a vehicle
-- spawned an hour into a server has never been through the pass below. Without
-- this the budget would apply to the ten vehicles parked in the map and to none
-- of the ones players actually drive.
function WorldBudgetService:Normalise(root: Instance)
	if not self:_settings().Enabled then
		return
	end
	local counts = newCounts()
	self:_apply(root, counts)
	for _, descendant in root:GetDescendants() do
		self:_apply(descendant, counts)
	end
end

-- Reports what streaming is actually set to, rather than what it was asked to
-- be set to.
--
-- These live in the project file because they cannot be set at runtime, so a
-- live sync is the only thing that applies them, and a live sync can apply some
-- and silently skip others. One line in the server log is cheaper than finding
-- that again by clicking through the Explorer.
--
-- `StreamingMinRadius` is deliberately absent. Studio's property grid shows it,
-- but it is not scriptable: reading it throws "not a valid member of Workspace".
-- That is why Rojo skipped it rather than applying it, and reading it here threw
-- during Start and took this entire service down with it, so the render budget
-- below never ran at all. The only reason that was ever noticed is that the
-- health log named the failed service.
--
-- Every read is inside the pcall for the same reason. This function exists to
-- report on the engine, and it must not be the thing that breaks when the
-- engine changes underneath it.
function WorldBudgetService:_reportStreaming()
	local ok, detail = pcall(function()
		return {
			TargetRadius = Workspace.StreamingTargetRadius,
			IntegrityMode = Workspace.StreamingIntegrityMode.Name,
			ModelBehaviour = Workspace.ModelStreamingBehavior.Name,
		}
	end)
	if not ok then
		self.context.Logger:Warning("Could not read the streaming settings", {
			Error = tostring(detail),
		})
		return
	end
	if Workspace.StreamingEnabled then
		self.context.Logger:Info("Streaming is on", detail)
	else
		self.context.Logger:Warning(
			"Streaming is OFF: every client is holding the whole map",
			detail
		)
	end
end

function WorldBudgetService:Start()
	self:_reportStreaming()
	local settings = self:_settings()
	if not settings.Enabled then
		return
	end

	-- Spawned and paced, for the same reason the camera walk is. Every service
	-- after this one waits for Start to return, and the network endpoints are
	-- registered by the last of them, so a walk that holds the frame here is not
	-- a slow startup: it is a server that answers nothing until it finishes.
	task.spawn(function()
		local counts = newCounts()
		local scanned = 0
		for _, instance in Workspace:GetDescendants() do
			self:_apply(instance, counts)
			scanned += 1
			if scanned % settings.InstancesPerStep == 0 then
				task.wait()
			end
		end
		self.applied = counts
		self.context.Logger:Info("World render budget applied", {
			Scanned = scanned,
			MeshesReducedToAutomaticDetail = counts.Meshes,
			ModelsGivenDistantDetail = counts.Models,
			LightsMadeCheaper = counts.Lights,
			SoundsGivenAFalloff = counts.Sounds,
		})
	end)
end

function WorldBudgetService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return WorldBudgetService
