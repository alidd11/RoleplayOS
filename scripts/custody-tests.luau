--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		-- Services used by module declarations; world signals are not started.
		runtime.services.CollectionService = {}
		runtime.services.TextChatService = {}
		runtime.services.MarketplaceService = {}
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local schema = runtime.require(shared.Shared.ProfileSchema)
		local config = runtime.require(shared.Config.Config)
		local profile = schema.default(10)
		profile.Consumables.EarlyReleaseCredits = 1
		profile.CustodySentence.RemainingSeconds = 60
		local attributes = {}
		local player: any = {
			UserId = 10,
			Parent = runtime.services.Players,
			Team = { Name = "Prison" },
			SetAttribute = function(_self, name, value)
				attributes[name] = value
			end,
		}
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return if id == 10 and player.Parent == runtime.services.Players then player else nil
		end
		local f: any = {
			Profile = profile,
			Player = player,
			Dirty = 0,
			Saves = {},
			Events = {},
			FailLoad = false,
		}
		local session = { Profile = profile }
		local dependencies: any = {
			DataService = {
				GetSession = function(_self, candidate)
					return if candidate == player then session else nil
				end,
				MarkDirty = function()
					f.Dirty += 1
				end,
				Save = function()
					table.insert(f.Saves, profile.Consumables.EarlyReleaseCredits)
					return true, nil
				end,
			},
			ServerModeService = {
				Kind = function()
					return "Public"
				end,
			},
			AccessService = {
				Evaluate = function()
					return { Allowed = true }
				end,
			},
			TeamService = {
				Get = function()
					return { Name = "Civilian" }
				end,
			},
			AuditService = { Record = function() end },
		}
		local context = {
			Configuration = config,
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "Unexpected custody dependency: " .. name)
				end,
			},
			Network = {
				RegisterEvent = function()
					return {
						FireClient = function(_self, _player, payload)
							table.insert(f.Events, payload)
						end,
					}
				end,
			},
			Logger = { Error = function() end, Info = function() end },
		}
		local services = runtime.services.ServerScriptService.RoleplayOS.Services
		local custody = runtime.require(services.CustodyService)
		local role = runtime.require(services.RoleService)
		local spawn = runtime.require(services.SpawnService)
		local products = runtime.require(services.DeveloperProductService)
		dependencies.CustodyService, dependencies.RoleService, dependencies.SpawnService =
			custody, role, spawn
		custody:Init(context)
		custody.running = true
		role:Init(context)
		role:Start()
		spawn:Init(context)
		spawn.running = true
		-- Resolve is the presentation boundary; actual Spawn still calls the
		-- yielding character-load RPC and handles its failure.
		spawn.Resolve = function(_self, request)
			assert(request.RoleId == "Civilian", "Unexpected release role")
			return { Name = "Civilian" }, nil
		end
		player.LoadCharacterAsync = function()
			if f.OnLoad then
				f.OnLoad()
			end
			task.wait(0.01)
			if f.FailLoad then
				error("Injected character-load failure")
			end
			player.Character = {}
		end
		products:Init(context)
		-- Fixture ID only: no marketplace request or production product is used.
		products.products[123] = { Credits = 2 }
		f.Custody, f.Products = custody, products
		f.Receipt = { ProductId = 123, PlayerId = 10, PurchaseId = "receipt-during-release" }
		function f:GrantDuringLoad()
			self.OnLoad = function()
				self.OnLoad = nil
				task.defer(function()
					self.ReceiptDecision = products:_process(self.Receipt)
				end)
			end
		end
		function f:Release()
			assert(schema.migrate(profile, 10) == profile, "Fixture current migration failed")
			return custody:UseEarlyReleaseCredit(player)
		end
		return f
	end

	H.test(
		"actual failed custody release preserves a receipt grant during character loading",
		function()
			local f = fixture()
			f.FailLoad = true
			f:GrantDuringLoad()
			local released, reason = f:Release()
			H.expect(
				not released and reason == "CHARACTER_SPAWN_FAILED",
				"load failure was not refused"
			)
			H.expect(
				f.ReceiptDecision.Name == "PurchaseGranted",
				"overlapping receipt was not granted"
			)
			H.expect(f.Saves[1] == 2, "receipt grant was not saved during the pending release")
			H.expect(
				f.Profile.Consumables.EarlyReleaseCredits == 3,
				"rollback overwrote newly granted credits"
			)
			H.expect(
				f.Profile.CustodySentence.RemainingSeconds == 60,
				"failed release ended the sentence"
			)
			H.expect(
				f.Custody.completing[f.Player] == nil and #f.Events == 0,
				"failed release retained claim or success event"
			)
			local decision = f.Products:_process(f.Receipt)
			H.expect(decision.Name == "PurchaseGranted", "receipt replay was not acknowledged")
			H.expect(
				f.Profile.Consumables.EarlyReleaseCredits == 3 and #f.Saves == 2 and f.Saves[2] == 3,
				"receipt replay duplicated or lost credits"
			)
		end
	)

	H.test(
		"actual successful custody release reports credits granted during character loading",
		function()
			local f = fixture()
			f:GrantDuringLoad()
			local released, reason = f:Release()
			H.expect(released and reason == nil, "valid release failed")
			H.expect(
				f.Profile.Consumables.EarlyReleaseCredits == 2,
				"success consumed newly granted credits"
			)
			H.expect(
				f.Profile.CustodySentence.RemainingSeconds == 0,
				"successful release kept the sentence active"
			)
			H.expect(
				#f.Events == 1 and f.Events[1].Credits == 2,
				"release notification reported stale credit count"
			)
			local replay, replayReason = f:Release()
			H.expect(
				not replay and replayReason == "NO_ACTIVE_CUSTODY_SENTENCE",
				"release replay spent another credit"
			)
			H.expect(
				f.Profile.Consumables.EarlyReleaseCredits == 2,
				"release replay changed credits"
			)
		end
	)

	H.test(
		"actual ordinary custody release preserves refusal and single-credit behaviour",
		function()
			for _, fails in { false, true } do
				local f = fixture()
				f.FailLoad = fails
				local released, reason = f:Release()
				H.expect(released == not fails, "ordinary release outcome changed")
				H.expect(
					f.Profile.Consumables.EarlyReleaseCredits == (if fails then 1 else 0),
					"ordinary credit accounting changed"
				)
				H.expect(
					f.Custody.completing[f.Player] == nil,
					"ordinary release retained completion claim"
				)
				if fails then
					H.expect(reason == "CHARACTER_SPAWN_FAILED", "spawn refusal reason changed")
				end
			end
		end
	)
	H.test("Needs uses the configured cuffed walk speed", function()
		local runtime = Runtime.new()
		local config = runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		local needs =
			runtime.require(runtime.services.ServerScriptService.RoleplayOS.Services.NeedsService)
		needs.context = { Configuration = config }
		local player: any = {}
		function player:GetAttribute(name: string)
			return if name == "RoleplayOSCuffed" then true else nil
		end
		local humanoid: any = { WalkSpeed = config.Needs.WalkSpeed }
		function humanoid:GetAttribute()
			return nil
		end
		function humanoid:SetStateEnabled() end
		needs:_applySpeed(player, { Sprinting = false, Hunger = 100, Stamina = 100 }, humanoid)
		H.expect(
			humanoid.WalkSpeed == config.Custody.CuffedWalkSpeed,
			"Needs ignored the configured cuffed walk speed"
		)
	end)
end
