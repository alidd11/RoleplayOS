--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")

local function await(predicate: () -> boolean)
	local deadline = os.clock() + 1
	while not predicate() and os.clock() < deadline do
		task.wait(0.001)
	end
	assert(predicate(), "Access fixture missed its bounded checkpoint")
end

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local scheduler = table.clone(task)
		runtime.globals.task = scheduler
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local config = table.clone(runtime.require(shared.Config.Config))
		config.Framework = table.clone(config.Framework)
		config.Framework.GrantMockEmergencyAccessInStudio = false
		config.Groups = table.clone(config.Groups)
		config.Groups.LookupTimeoutSeconds = 0.03
		config.Groups.MaximumConcurrentLookups = 1
		config.ExperienceAccess = table.clone(config.ExperienceAccess)
		config.ExperienceAccess.VerifyAttempts = 1
		config.Roles = {
			Test = {
				TeamName = "Police",
				Access = { AccessType = "Group", GroupLinkId = "Police" },
			},
		}
		local group = runtime.require(root.GroupService)
		local access = runtime.require(root.AccessService)
		local role = runtime.require(root.RoleService)
		local entry = runtime.require(root.ExperienceAccessService)
		local players, logs = {}, {}
		local f = {
			Scheduler = scheduler,
			Logs = logs,
			Group = group,
			Access = access,
			Role = role,
			Entry = entry,
			Config = config,
			Calls = 0,
		}
		f.Session = { Profile = runtime.require(shared.Shared.ProfileSchema).default(10) }
		f.Rank = function(_player, _groupId)
			return 10
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, userId)
			return players[userId]
		end
		function f:Player(userId: number): any
			local player = { UserId = userId, Parent = runtime.services.Players }
			player.GetRankInGroup = function(candidate, groupId)
				f.Calls += 1
				return f.Rank(candidate, groupId)
			end
			player.IsDescendantOf = function(candidate, parent)
				return candidate.Parent == parent
			end
			player.Kick = function(candidate, message)
				candidate.Kicked = message
			end
			players[userId] = player
			return player
		end
		f.Player10 = f:Player(10)
		local team = { Name = "Police" }
		local services = {
			GroupService = group,
			AccessService = access,
			DataService = {
				GetSession = function(_self, player)
					return if players[player.UserId] == player then f.Session else nil
				end,
			},
			ServerModeService = {
				Kind = function()
					return "Whitelisted"
				end,
				RequiredGroupLinkId = function()
					return "Police"
				end,
			},
			OfficialServerService = {
				CurrentEntry = function()
					return { Whitelisted = true, RequiredGroupLinkId = "Police" }
				end,
			},
			TeamService = {
				Get = function()
					return team
				end,
			},
		}
		local logger = {}
		for _, level in { "Info", "Warning", "Error", "Security" } do
			logger[level] = function(_self, message, fields)
				table.insert(logs, { Level = level, Message = message, Fields = fields })
			end
		end
		local context = {
			Configuration = config,
			Logger = logger,
			Services = {
				Get = function(_self, name)
					return assert(services[name], "Unconfigured access fixture dependency")
				end,
			},
		}
		for _, service in { group, access, role, entry } do
			service:Init(context)
		end
		-- Entry/player signals and prefetch are not simulated; exercise public methods directly.
		group.running, role.running, entry.running = true, true, true
		function f:Destroy()
			entry:Destroy()
			role:Destroy()
			group:Destroy()
		end
		return f
	end

	H.test("actual group cache expires and cached failures do not grant membership", function()
		local f = fixture()
		local result = f.Group:GetMembership(f.Player10, "Police")
		H.expect(result.IsMember and f.Calls == 1, "valid group lookup failed")
		H.expect(
			f.Group:GetMembership(f.Player10, "Police") == result and f.Calls == 1,
			"cache repeated RPC"
		)
		result.ExpiresAt = 0
		f.Rank = function()
			error("injected group outage")
		end
		result = f.Group:GetMembership(f.Player10, "Police")
		H.expect(result.Failed and f.Calls == 2, "expired lookup did not fail closed")
		H.expect(
			f.Group:GetMembership(f.Player10, "Police") == result and f.Calls == 2,
			"negative cache repeated RPC"
		)
		H.expect(
			not f.Access:Evaluate(f.Player10, f.Config.Roles.Test.Access).Allowed,
			"failed group cache granted access"
		)
		f.Group:Invalidate(f.Player10, "Police")
		f.Rank = function()
			return 10
		end
		H.expect(
			f.Group:GetMembership(f.Player10, "Police").IsMember and f.Calls == 3,
			"recovery remained poisoned"
		)
		f:Destroy()
	end)

	H.test("unconfigured group and insufficient ranks deny actual role assignment", function()
		local f = fixture()
		H.expect(
			f.Group:GetMembershipByGroupId(f.Player10, 0).NotConfigured and f.Calls == 0,
			"unconfigured group contacted Roblox"
		)
		f.Rank = function()
			return 0
		end
		local assigned, reason = f.Role:Assign(f.Player10, "Test")
		H.expect(
			not assigned and reason == "GROUP_REQUIRED" and f.Player10.Team == nil,
			"non-member assigned role"
		)
		f.Group:Invalidate(f.Player10)
		f.Rank = function()
			return 10
		end
		H.expect(
			f.Role:Assign(f.Player10, "Test") and f.Player10.Team.Name == "Police",
			"valid role assignment refused"
		)
		f:Destroy()
	end)

	H.test("actual role assignment fences profile replacement during a group lookup", function()
		local f = fixture()
		f.Rank = function()
			task.wait(0.001)
			f.Session = { Profile = f.Session.Profile }
			return 10
		end
		local assigned, reason = f.Role:Assign(f.Player10, "Test")
		H.expect(
			not assigned and reason == "ROLE_UNAVAILABLE" and f.Player10.Team == nil,
			"stale profile assigned role"
		)
		f:Destroy()
	end)

	H.test("actual group lookup does not cache a departed player's late result", function()
		local f = fixture()
		f.Rank = function()
			task.wait(0.001)
			f.Player10.Parent = nil
			return 10
		end
		local result = f.Group:GetMembership(f.Player10, "Police")
		H.expect(
			result.Failed and result.Reason == "PLAYER_UNAVAILABLE",
			"departed result remained authoritative"
		)
		H.expect(not f.Group.cache[10] or next(f.Group.cache[10]) == nil, "late result cached")
		f:Destroy()
	end)

	local function stall(f: any): () -> ()
		local release = false
		f.Rank = function()
			local deadline = os.clock() + 0.5
			while not release and os.clock() < deadline do
				task.wait(0.001)
			end
			return 10
		end
		return function()
			release = true
		end
	end

	H.test("actual group lookup returns a bounded failure when the rank RPC stalls", function()
		local f = fixture()
		local release = stall(f)
		local result
		task.spawn(function()
			result = f.Group:GetMembership(f.Player10, "Police")
		end)
		await(function()
			return f.Calls == 1
		end)
		task.wait(0.1)
		local bounded = result ~= nil and result.Failed == true
		local released = f.Group.activeLookupCount == 0 and next(f.Group.lookupSlots) == nil
		release()
		await(function()
			return result ~= nil
		end)
		f:Destroy()
		H.expect(
			bounded and released,
			"stalled rank RPC bypassed deadline or retained cancelled worker"
		)
	end)

	H.test("actual group lookup bounds shared RPC admission across players", function()
		local f = fixture()
		f.Config.Groups.LookupTimeoutSeconds = 0.4
		local release = stall(f)
		local first, second
		task.spawn(function()
			first = f.Group:GetMembership(f.Player10, "Police")
		end)
		await(function()
			return f.Calls == 1
		end)
		local other = f:Player(20)
		task.spawn(function()
			second = f.Group:GetMembership(other, "Police")
		end)
		task.wait(0.05)
		local bounded = second ~= nil and second.Failed == true and f.Calls == 1
		release()
		await(function()
			return first ~= nil and second ~= nil
		end)
		f:Destroy()
		H.expect(bounded, "simultaneous lookups exceeded the shared admission cap")
	end)

	H.test("actual entry verification fails closed within the lookup deadline", function()
		local f = fixture()
		local release = stall(f)
		local finished = false
		task.spawn(function()
			f.Entry:_check(f.Player10)
			finished = true
		end)
		await(function()
			return f.Calls == 1
		end)
		task.wait(0.1)
		local bounded = finished and f.Player10.Kicked ~= nil and not f.Entry:IsVerified(f.Player10)
		release()
		await(function()
			return finished
		end)
		f:Destroy()
		H.expect(bounded, "stalled entry verification did not terminate fail-closed")
	end)

	H.test("uncancellable group workers retain admission until completion", function()
		local f = fixture()
		f.Scheduler.cancel = function()
			error("injected cancellation refusal")
		end
		local release = stall(f)
		local result = f.Group:GetMembership(f.Player10, "Police")
		H.expect(
			result.Failed and f.Group.activeLookupCount == 1,
			"uncancellable worker lost its slot"
		)
		local other = f:Player(20)
		H.expect(
			f.Group:GetMembership(other, "Police").Failed and f.Calls == 1,
			"timeout admitted replacement worker"
		)
		release()
		await(function()
			return f.Group.activeLookupCount == 0
		end)
		H.expect(next(f.Group.lookupSlots) == nil, "completion retained worker tracking")
		f:Destroy()
	end)

	H.test("group teardown fences late results and clears outstanding admission", function()
		local f = fixture()
		f.Config.Groups.LookupTimeoutSeconds = 0.4
		f.Scheduler.cancel = function()
			error("injected cancellation refusal")
		end
		local release = stall(f)
		local result
		task.spawn(function()
			result = f.Group:GetMembership(f.Player10, "Police")
		end)
		await(function()
			return f.Calls == 1
		end)
		f:Destroy()
		await(function()
			return result ~= nil
		end)
		H.expect(
			result.Failed and result.Reason == "PLAYER_UNAVAILABLE",
			"teardown returned authoritative rank"
		)
		release()
		task.wait(0.02)
		H.expect(
			f.Group.activeLookupCount == 0
				and next(f.Group.lookupSlots) == nil
				and next(f.Group.cache) == nil,
			"late worker resurrected state"
		)
	end)

	H.test("group lookup configuration rejects invalid durations and admission bounds", function()
		local runtime = Runtime.new()
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local original = runtime.require(root.Config.Config)
		local validator = runtime.require(root.Shared.ConfigValidator)
		for _, field in
			{
				"LookupTimeoutSeconds",
				"CacheSeconds",
				"MaximumFailureBackoffSeconds",
				"MaximumConcurrentLookups",
			}
		do
			for _, value in { 0, -1, "4", 0 / 0, math.huge, -math.huge } do
				local config = table.clone(original)
				config.Groups = table.clone(config.Groups)
				config.Groups[field] = value
				local valid = validator.validate(config)
				H.expect(not valid, "invalid group bound accepted: " .. field)
			end
		end
		for _, value in { 1.5, 65 } do
			local config = table.clone(original)
			config.Groups = table.clone(config.Groups)
			config.Groups.MaximumConcurrentLookups = value
			H.expect(not validator.validate(config), "invalid admission count accepted")
		end
		H.expect(validator.validate(original), "valid group bounds refused")
	end)
end
