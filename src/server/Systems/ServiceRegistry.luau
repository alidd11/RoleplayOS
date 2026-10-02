--!strict

local Registry = {}
Registry.__index = Registry

function Registry.new()
	return setmetatable({ services = {}, order = {}, failed = {} }, Registry)
end

function Registry:Register(name: string, service: any)
	assert(self.services[name] == nil, "Duplicate service: " .. name)
	self.services[name] = service
	table.insert(self.order, name)
end

function Registry:Get(name: string): any
	local service = self.services[name]
	assert(service ~= nil, "Unknown service: " .. name)
	return service
end

-- Services that did not start, by name.
--
-- Kept so the health log can say the server is running without its dealership
-- rather than leaving that to be discovered by a player standing in one.
function Registry:Failed(): { string }
	local names = {}
	for name in self.failed do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Required failures abort startup. Degradation is an explicit opt-in for a
-- genuinely optional integration, never inferred from a missing Critical flag.
-- Critical takes precedence over a conflicting Optional flag. A failed optional
-- service stays registered so callers can report its unavailable feature.
function Registry:_handleFailure(context: any, name: string, phase: string, problem: any): boolean
	local service = self.services[name]
	if service.Critical == true or service.Optional ~= true then
		return false
	end
	self.failed[name] = true
	context.Logger:Error("Service failed and was stepped over", {
		Service = name,
		Phase = phase,
		Error = tostring(problem),
	})
	return true
end

function Registry:Initialise(context: any)
	for _, name in self.order do
		local service = self.services[name]
		local ok, errorMessage = pcall(service.Init, service, context)
		if not ok then
			-- Init had no tolerance at all, while Start already had some. The two
			-- phases fail for the same reasons and there was no reason for them to
			-- disagree about what a failure means.
			if not self:_handleFailure(context, name, "Init", errorMessage) then
				error(
					string.format(
						"Required service %s failed to initialise: %s",
						name,
						tostring(errorMessage)
					),
					0
				)
			end
			continue
		end
		context.Logger:Info("Initialised service", { Service = name })
	end
end

function Registry:Start(context: any)
	for _, name in self.order do
		if self.failed[name] then
			-- Never started, because it never initialised.
			continue
		end
		local service = self.services[name]
		local ok, errorMessage = pcall(service.Start, service)
		if not ok then
			if not self:_handleFailure(context, name, "Start", errorMessage) then
				error(
					string.format(
						"Required service %s failed to start: %s",
						name,
						tostring(errorMessage)
					),
					0
				)
			end
		end
	end
end

function Registry:Destroy(context: any)
	-- Reverse order, so DataService, which is registered first, is destroyed
	-- last and writes its profiles after everything else has stopped changing
	-- them.
	for index = #self.order, 1, -1 do
		local name = self.order[index]
		local service = self.services[name]
		local ok, errorMessage = pcall(service.Destroy, service)
		if not ok then
			context.Logger:Error(
				"Service failed to destroy cleanly",
				{ Service = name, Error = tostring(errorMessage) }
			)
		end
	end
end

return Registry
