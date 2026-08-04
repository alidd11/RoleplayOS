--!strict

local Registry = {}
Registry.__index = Registry

function Registry.new()
	return setmetatable({ services = {}, order = {} }, Registry)
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

function Registry:Initialise(context: any)
	for _, name in self.order do
		local service = self.services[name]
		local ok, errorMessage = pcall(service.Init, service, context)
		if not ok then
			error(
				string.format("Service %s failed to initialise: %s", name, tostring(errorMessage)),
				0
			)
		end
		context.Logger:Info("Initialised service", { Service = name })
	end
end

function Registry:Start(context: any)
	for _, name in self.order do
		local service = self.services[name]
		local ok, errorMessage = pcall(service.Start, service)
		if not ok then
			-- Reported and stepped over, whether the service is optional or not.
			--
			-- Raising here stopped every later service from starting, and since
			-- the raise propagated out of the bootstrap it also removed the
			-- server's own shutdown handler. One missing service became a whole
			-- server that could not save anybody.
			--
			-- A service that fails is still Destroyed, so it releases whatever it
			-- managed to acquire before it threw.
			local level = if service.Optional then "Warning" else "Error"
			context.Logger[level](context.Logger, "Service failed to start", {
				Service = name,
				Optional = service.Optional == true,
				Error = tostring(errorMessage),
			})
		end
	end
end

function Registry:Destroy(context: any)
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
