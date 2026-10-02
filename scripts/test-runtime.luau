--!strict
-- Headless contract-test environment, not a Roblox engine or online-service emulator.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local datetime = require("@lune/datetime")
local task = require("@lune/task")

local Runtime = {}

local function serviceDouble(name: string, members: any?): any
	return setmetatable(members or {}, {
		__index = function(_self, key)
			error(string.format("Unsupported headless service call: %s.%s", name, tostring(key)), 2)
		end,
	})
end

local function date(value: any): any
	return {
		ToUniversalTime = function()
			local fields = value:toUniversalTime()
			return {
				Year = fields.year,
				Month = fields.month,
				Day = fields.day,
				Hour = fields.hour,
				Minute = fields.minute,
				Second = fields.second,
			}
		end,
	}
end

function Runtime.new(): any
	local sources, cache, loading = {}, {}, {}
	local function folder(name: string, parent: any?): any
		local instance = roblox.Instance.new("Folder")
		instance.Name, instance.Parent = name, parent
		return instance
	end
	local function mount(path: string, parent: any)
		local entries = fs.readDir(path)
		table.sort(entries)
		for _, entry in entries do
			local childPath = path .. "/" .. entry
			if fs.isDir(childPath) then
				local child
				if fs.isFile(childPath .. "/init.luau") then
					child = roblox.Instance.new("ModuleScript")
					child.Name, child.Parent = entry, parent
					sources[child] = childPath .. "/init.luau"
				else
					child = folder(entry, parent)
				end
				mount(childPath, child)
			elseif
				entry ~= "init.luau"
				and string.match(entry, "%.luau$")
				and not string.match(entry, "%.server%.luau$")
			then
				local instance = roblox.Instance.new("ModuleScript")
				instance.Name = string.gsub(entry, "%.luau$", "")
				instance.Parent = parent
				sources[instance] = childPath
			end
		end
	end

	local replicated = folder("ReplicatedStorage")
	local sharedRoot = folder("RoleplayOS", replicated)
	mount("src/shared/Utility", folder("Shared", sharedRoot))
	mount("src/shared/Config", folder("Config", sharedRoot))
	mount("src/shared/Types", folder("Types", sharedRoot))
	mount("src/shared/Network", folder("Network", sharedRoot))
	local server = folder("ServerScriptService")
	local serverRoot = folder("RoleplayOS", server)
	mount("src/server/Services", folder("Services", serverRoot))
	mount("src/server/Systems", folder("Systems", serverRoot))
	local tests = folder("Tests")
	mount("tests", tests)
	local workspace = roblox.Instance.new("Workspace")
	local nextId = 0
	local services = {
		ReplicatedStorage = replicated,
		ServerScriptService = server,
		Workspace = workspace,
		HttpService = serviceDouble("HttpService", {
			GenerateGUID = function()
				nextId += 1
				return string.format("00000000-0000-4000-8000-%012d", nextId)
			end,
		}),
		Players = serviceDouble("Players", {
			GetPlayers = function()
				return {}
			end,
			GetPlayerByUserId = function()
				return nil
			end,
		}),
		RunService = serviceDouble("RunService", {
			IsStudio = function()
				return true
			end,
		}),
		TextService = serviceDouble("TextService"),
		DataStoreService = serviceDouble("DataStoreService"),
		MemoryStoreService = serviceDouble("MemoryStoreService"),
		TeleportService = serviceDouble("TeleportService"),
	}
	local game = serviceDouble("game", {
		PlaceId = 1,
		JobId = "headless-test-server",
		GetService = function(_self, name)
			assert(services[name], "Unsupported headless service: " .. name)
			return services[name]
		end,
	})
	local globals = {
		game = game,
		workspace = workspace,
		task = task,
		DateTime = {
			now = function()
				return date(datetime.now())
			end,
			fromUniversalTime = function(year, month, day, hour, minute, second)
				return date(datetime.fromUniversalTime({
					year = year,
					month = month,
					day = day,
					hour = hour or 0,
					minute = minute or 0,
					second = second or 0,
				}))
			end,
		},
		-- Deterministic test random numbers: not Roblox's production PRNG.
		Random = {
			new = function(seed)
				local state = math.max(1, math.floor(seed or 1) % 2147483647)
				return {
					NextInteger = function(_self, minimum, maximum)
						state = (state * 16807) % 2147483647
						return minimum + state % (maximum - minimum + 1)
					end,
				}
			end,
		},
	}
	for name, value in roblox do
		globals[name] = value
	end

	local function loadModule(instance: any): any
		local path = sources[instance]
		assert(path, "Only mounted repository ModuleScripts may be required")
		if cache[instance] ~= nil then
			return cache[instance]
		end
		assert(not loading[instance], "Circular module dependency: " .. path)
		loading[instance] = true
		local environment = table.clone(globals)
		environment.script = instance
		environment.require = loadModule
		local ok, value = pcall(function()
			return luau.load(fs.readFile(path), {
				debugName = path,
				environment = environment,
				injectGlobals = true,
			})()
		end)
		loading[instance] = nil
		if not ok then
			error(value, 0)
		end
		assert(value ~= nil, "Module returned nil: " .. path)
		cache[instance] = value
		return value
	end
	return { require = loadModule, tests = tests, services = services }
end

return Runtime
