--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(state: any?): any
		local runtime = Runtime.new()
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(root.Config.Config)
		config.Progression.MaximumHistory = 2
		config.Progression.MaximumRewardIds = 3
		local schema = runtime.require(root.Shared.ProfileSchema)
		local profile = schema.default(10)
		local character = { CharacterId = "owned", Progression = state }
		profile.Characters.owned = character
		local migrated, problem = schema.migrate(profile, 10)
		assert(migrated == profile and problem == nil, "Fixture did not pass current migration")
		local player = { UserId = 10 }
		local session = { ActiveCharacterId = "owned", Profile = profile }
		local dirty, audits, events = 0, {}, {}
		local services = {
			DataService = {
				GetSession = function(_self, candidate)
					return if candidate == player then session else nil
				end,
				MarkDirty = function()
					dirty += 1
				end,
			},
			AuditService = {
				Record = function(_self, entry)
					table.insert(audits, entry)
				end,
			},
			ServerModeService = {
				Kind = function()
					return "Public"
				end,
			},
		}
		local service = runtime.require(
			runtime.services.ServerScriptService.RoleplayOS.Services.ProgressionService
		)
		service:Init({
			Configuration = config,
			Services = {
				Get = function(_self, name)
					return assert(services[name], "Unconfigured progression fixture dependency")
				end,
			},
			Network = {
				RegisterEvent = function()
					return {
						FireClient = function(_self, _player, value)
							table.insert(events, value)
						end,
					}
				end,
			},
		})
		return {
			Service = service,
			Player = player,
			Character = character,
			Config = config,
			Audits = audits,
			Events = events,
			Dirty = function()
				return dirty
			end,
		}
	end

	local function state(): any
		return {
			TotalXP = 100,
			Tracks = { ["Job:DeliveryDriver"] = 50 },
			RewardIds = {},
			RewardOrder = {},
			History = {},
		}
	end

	local function grant(f: any, id: string): (any?, string?)
		return f.Service:Grant(
			f.Player,
			"owned",
			id,
			"Job:DeliveryDriver",
			25,
			"JOB_TASK_COMPLETED"
		)
	end

	H.test("progression preserves present unreadable XP instead of resetting it", function()
		for _, persisted in
			{
				"damaged",
				4,
				{ TotalXP = "100" },
				{ TotalXP = -1 },
				{ TotalXP = 0.5 },
				{ TotalXP = math.huge },
				{ TotalXP = 0 / 0 },
			}
		do
			local f = fixture(persisted)
			local value, reason = f.Service:Get(f.Player)
			H.expect(
				value == nil and reason == "INVALID_PROGRESSION_STATE",
				"unreadable XP became a zero-XP summary"
			)
			local awarded, awardReason = grant(f, "reward")
			H.expect(
				awarded == nil and awardReason == "INVALID_PROGRESSION_STATE",
				"unreadable XP accepted a reward"
			)
			H.expect(
				f.Character.Progression == persisted and f.Dirty() == 0 and #f.Audits == 0,
				"unreadable source changed"
			)
		end
	end)

	for _, field in { "RewardIds", "RewardOrder", "History" } do
		H.test("progression validates " .. field .. " before changing XP or replay IDs", function()
			for _, corrupt in { 4, "damaged" } do
				local persisted = state()
				persisted[field] = corrupt
				local f = fixture(persisted)
				local completed, awarded, reason = pcall(grant, f, "reward")
				H.expect(
					completed and awarded == nil and reason == "INVALID_PROGRESSION_STATE",
					"malformed "
						.. field
						.. " was not safely refused; XP: "
						.. tostring(persisted.TotalXP)
				)
				H.expect(
					persisted.TotalXP == 100
						and persisted.Tracks["Job:DeliveryDriver"] == 50
						and persisted[field] == corrupt,
					"refusal partially changed XP"
				)
				H.expect(
					f.Dirty() == 0 and #f.Audits == 0 and #f.Events == 0,
					"refusal published a grant"
				)
			end
		end)
	end

	H.test("progression refuses sparse retention lists without dropping their source", function()
		for _, field in { "RewardOrder", "History" } do
			local persisted = state()
			local corrupt = { [2] = if field == "RewardOrder" then "old" else { Amount = 10 } }
			persisted[field] = corrupt
			local f = fixture(persisted)
			local awarded, reason = grant(f, "reward")
			H.expect(
				awarded == nil and reason == "INVALID_PROGRESSION_STATE",
				"sparse retention list accepted a grant"
			)
			H.expect(
				persisted.TotalXP == 100 and persisted[field] == corrupt and f.Dirty() == 0,
				"sparse source changed"
			)
		end
	end)

	H.test("progression refuses unreadable track values", function()
		for _, trackXp in { "50", -1, 0.5, math.huge, 0 / 0 } do
			local persisted = state()
			persisted.Tracks["Job:DeliveryDriver"] = trackXp
			local f = fixture(persisted)
			local completed, awarded, reason = pcall(grant, f, "reward")
			H.expect(
				completed and awarded == nil and reason == "INVALID_PROGRESSION_STATE",
				"unreadable track accepted a grant"
			)
			H.expect(persisted.TotalXP == 100 and f.Dirty() == 0, "refusal changed overall XP")
		end
	end)

	H.test("progression preserves partial legacy state while backfilling absent fields", function()
		local tracks = { ["Job:DeliveryDriver"] = 50 }
		local persisted = { Tracks = tracks }
		local f = fixture(persisted)
		H.expect(grant(f, "legacy") ~= nil, "absent legacy fields were not backfilled")
		H.expect(
			f.Character.Progression == persisted
				and persisted.Tracks == tracks
				and tracks["Job:DeliveryDriver"] == 75
				and persisted.TotalXP == 25,
			"backfill erased valid legacy tracks"
		)
	end)

	H.test(
		"progression grants remain idempotent with bounded replay and newest-first history",
		function()
			local f = fixture()
			for index = 1, 4 do
				H.expect(grant(f, "reward-" .. index) ~= nil, "valid reward refused")
			end
			local persisted = f.Character.Progression
			local value, reason = grant(f, "reward-4")
			H.expect(value == nil and reason == "DUPLICATE_XP_REWARD", "reward replayed")
			H.expect(
				persisted.TotalXP == 100
					and persisted.Tracks["Job:DeliveryDriver"] == 100
					and f.Dirty() == 4
					and #f.Audits == 4,
				"grants did not commit once"
			)
			H.expect(
				#persisted.History == 2
					and persisted.History[1].RewardId == "reward-4"
					and persisted.History[2].RewardId == "reward-3",
				"history order or cap wrong"
			)
			H.expect(
				#persisted.RewardOrder == 3
					and persisted.RewardIds["reward-1"] == nil
					and persisted.RewardIds["reward-4"] ~= nil,
				"replay retention wrong"
			)
		end
	)
end
