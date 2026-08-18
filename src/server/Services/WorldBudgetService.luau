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
	Shadows: number,
	-- Counted apart from "nothing needed changing", because the two look
	-- identical in a total of zero and mean opposite things.
	Refused: number,
}

local function newCounts(): Counts
	return { Meshes = 0, Models = 0, Lights = 0, Sounds = 0, Shadows = 0, Refused = 0 }
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

	-- Small parts stop casting shadows.
	--
	-- Every part in a map casts by default, and the sun's shadow pass draws all of
	-- them whether or not the result is visible. A part smaller than a couple of
	-- studs cubed -- a handle, a mirror, a bolt, a light lens -- contributes a
	-- shadow of a few pixels that nobody has ever looked at, while costing the same
	-- per-part work as a wall.
	--
	-- Deliberately a volume test and not a count or a distance: it removes only
	-- shadows that were never legible, so nothing that reads on screen changes.
	-- Checked before the MeshPart branch because a small MeshPart wants both this
	-- and its detail setting.
	if instance:IsA("BasePart") and settings.ShadowlessPartVolume > 0 then
		local size = instance.Size
		if instance.CastShadow and size.X * size.Y * size.Z < settings.ShadowlessPartVolume then
			instance.CastShadow = false
			counts.Shadows += 1
		end
	end

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
			elseif not ok then
				counts.Refused += 1
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
			elseif not ok then
				counts.Refused += 1
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
	-- Read one property at a time.
	--
	-- These were read together inside a single pcall, so the first unreadable one
	-- took the whole report down with it and the log said only that the settings
	-- could not be read. StreamingIntegrityMode turns out to be another of the
	-- Workspace properties Studio displays but scripts may not read, exactly like
	-- StreamingMinRadius before it, so in practice this reported nothing at all
	-- and the one line telling us whether streaming is even on never appeared.
	local detail: { [string]: any } = {}
	local function record(name: string, read: () -> any)
		local ok, value = pcall(read)
		detail[name] = if ok then value else "unreadable"
	end
	record("TargetRadius", function()
		return Workspace.StreamingTargetRadius
	end)
	record("IntegrityMode", function()
		return Workspace.StreamingIntegrityMode.Name
	end)
	record("ModelBehaviour", function()
		return Workspace.ModelStreamingMode.Name
	end)
	local enabledOk, enabled = pcall(function()
		return Workspace.StreamingEnabled
	end)
	if not enabledOk then
		self.context.Logger:Warning("Could not read whether streaming is on", detail)
		return
	end
	if enabled then
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
			SmallPartsNoLongerCastingShadows = counts.Shadows,
			SoundsGivenAFalloff = counts.Sounds,
			RefusedByEngine = counts.Refused,
		})
		-- Said out loud rather than left as a zero on the line above.
		--
		-- Roblox restricts writes to RenderFidelity and Model.LevelOfDetail to
		-- threads holding the plugin capability, and a server Script does not hold
		-- it. Every attempt is refused, and because each is wrapped in a pcall so
		-- it can never break a vehicle spawn, the level of detail pass reported a
		-- tidy zero and read as having found nothing to do. It is the largest
		-- saving this service exists to make and it has never once been applied.
		-- Baking the values into the templates in Studio is how to get it.
		if counts.Refused > 0 then
			self.context.Logger:Warning("Level of detail could not be applied at runtime", {
				Refused = counts.Refused,
				Reason = "Roblox restricts these properties to plugin threads",
				Remedy = "Set RenderFidelity and LevelOfDetail on the models in Studio",
			})
		end
	end)
end

function WorldBudgetService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return WorldBudgetService
