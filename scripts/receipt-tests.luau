--!strict
local Runtime = require("./test-runtime")
local roblox = require("@lune/roblox")

return function(H: any)
	local function fixture(definition: any): any
		local runtime = Runtime.new()
		runtime.services.MarketplaceService = {}
		local services = runtime.services.ServerScriptService.RoleplayOS.Services
		local Data = runtime.require(services.DataService)
		local copy = runtime.require(services.DataService.Utils).deepCopy
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local schema = runtime.require(root.Shared.ProfileSchema)
		local config = runtime.require(root.Config.Config)
		config.Framework.MaxSaveAttempts = 1
		local player: any =
			{ UserId = 10, Parent = runtime.services.Players, Team = { Name = "Civilian" } }
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return if id == 10 and player.Parent == runtime.services.Players then player else nil
		end
		local profile = schema.default(10)
		profile.Characters.active =
			{ CharacterId = "active", AppearanceLocked = true, Appearance = { HeadScale = 0.95 } }
		local session = {
			Player = player,
			Profile = profile,
			Revision = 0,
			DataKey = "10",
			ActiveCharacterId = "active",
		}
		local store: any = { Value = copy(profile), Updates = 0 }
		function store:UpdateAsync(_key, transform)
			self.Updates += 1
			if self.Before then
				self.Before()
			end
			local updated
			for _ = 1, 2 do
				updated = transform(copy(self.Value))
			end
			self.Value = copy(updated)
			if self.After then
				self.After()
			end
			return copy(self.Value)
		end
		local logger = { Error = function() end, Warning = function() end }
		local data = setmetatable({
			sessions = { [10] = session },
			serverId = "receipt-owner",
			store = store,
			context = { Configuration = config, Logger = logger },
			_awaitBudget = function() end,
			_measure = function() end,
		}, { __index = Data })
		local f: any = {
			Profile = profile,
			Session = session,
			Store = store,
			Data = data,
			Player = player,
			CustodyCalls = 0,
		}
		local dependencies: any = {
			DataService = data,
			ServerModeService = {
				Kind = function()
					return "Public"
				end,
			},
			DutyService = {
				Get = function()
					return nil
				end,
			},
			AuditService = { Record = function() end },
			CustodyService = {
				HasActiveSentence = function()
					f.CustodyCalls += 1
					return false
				end,
			},
		}
		local context = {
			Configuration = config,
			Logger = logger,
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name])
				end,
			},
		}
		local products = runtime.require(services.DeveloperProductService)
		products:Init(context)
		products.products[123] = definition
		local characters = runtime.require(services.CharacterService)
		characters:Init(context)
		characters:Start()
		local humanoid = {
			ApplyDescriptionReset = function() end,
			GetAppliedDescription = function()
				return roblox.Instance.new("HumanoidDescription")
			end,
		}
		player.Character = {
			FindFirstChildOfClass = function(_self, name)
				return if name == "Humanoid" then humanoid else nil
			end,
			SetAttribute = function() end,
		}
		f.Receipt = { ProductId = 123, PlayerId = 10, PurchaseId = "save-fault" }
		function f:Process()
			return products:_process(self.Receipt)
		end
		function f:Edit()
			return characters:SetAuthoredAppearance(player, "active", { HeadScale = 1 })
		end
		return f
	end

	local grants = {
		{
			Definition = { GrantType = "CharacterAppearanceEdit", Amount = 1 },
			Field = "AppearanceEdits",
			Amount = 1,
		},
		{
			Definition = { GrantType = "ExtraCharacterSlot", Amount = 1 },
			Field = "ExtraCharacterSlots",
			Amount = 1,
		},
		{ Definition = { Credits = 2 }, Field = "EarlyReleaseCredits", Amount = 2 },
	}

	H.test(
		"actual receipt retries preserve grants and markers after precommit and ambiguous save faults",
		function()
			for _, grant in grants do
				for _, boundary in { "Before", "After" } do
					local f = fixture(grant.Definition)
					f.Store[boundary] = function()
						error("Injected receipt save fault")
					end
					H.expect(
						f:Process().Name == "NotProcessedYet",
						"failed save acknowledged delivery"
					)
					H.expect(
						f.Profile.Consumables[grant.Field] == grant.Amount
							and f.Profile.Consumables.ProcessedDeveloperReceipts["save-fault"]
								~= nil,
						"failed save rewound applied grant or marker"
					)
					H.expect(
						f.Store.Value.Consumables[grant.Field]
							== (if boundary == "After" then grant.Amount else 0),
						"fault boundary was not exercised"
					)
					f.Store[boundary] = nil
					H.expect(
						f:Process().Name == "PurchaseGranted",
						"healthy retry did not acknowledge"
					)
					H.expect(
						f.Profile.Consumables[grant.Field] == grant.Amount
							and f.Store.Value.Consumables[grant.Field] == grant.Amount,
						"retry duplicated or lost grant"
					)
					H.expect(
						f:Process().Name == "PurchaseGranted"
							and f.Profile.Consumables[grant.Field] == grant.Amount,
						"durable replay duplicated grant"
					)
				end
			end
		end
	)

	H.test(
		"actual receipt retry does not grant another edit after spending during a failed save",
		function()
			local f = fixture(grants[1].Definition)
			local edited
			f.Store.Before = function()
				edited = f:Edit()
				error("Injected receipt save fault after edit")
			end
			H.expect(
				f:Process().Name == "NotProcessedYet" and edited == true,
				"edit/save overlap was not exercised"
			)
			f.Store.Before = nil
			H.expect(f:Process().Name == "PurchaseGranted", "healthy retry failed")
			H.expect(
				f.Profile.Consumables.AppearanceEdits == 0
					and f.Store.Value.Consumables.AppearanceEdits == 0,
				"retry awarded a second edit"
			)
			H.expect(
				f.Store.Value.Characters.active.Appearance.HeadScale == 1
					and f.Store.Value.Consumables.ProcessedDeveloperReceipts["save-fault"]
						~= nil,
				"spent grant and appearance were not saved together"
			)
		end
	)

	H.test(
		"actual receipt replay refuses acknowledgement while its profile save is in flight",
		function()
			local f = fixture(grants[1].Definition)
			local replay
			f.Store.Before = function()
				replay = f:Process()
				error("Injected original save fault")
			end
			H.expect(f:Process().Name == "NotProcessedYet", "failed original save acknowledged")
			H.expect(replay.Name == "NotProcessedYet", "replay acknowledged an unsaved grant")
			f.Store.Before = nil
			H.expect(
				f:Process().Name == "PurchaseGranted"
					and f.Store.Value.Consumables.AppearanceEdits == 1,
				"pending grant did not recover once"
			)
		end
	)

	H.test(
		"actual receipt replay rechecks persistence and preserves additions during a failed save",
		function()
			local f = fixture(grants[1].Definition)
			f.Store.Before = function()
				f.Profile.Consumables.AppearanceEdits += 2
				f.Data:MarkDirty(f.Player)
				error("Injected save fault after another mutation")
			end
			H.expect(
				f:Process().Name == "NotProcessedYet" and f.Profile.Consumables.AppearanceEdits == 3,
				"rollback erased a later mutation"
			)
			f.Store.Before = function()
				error("Injected replay save fault")
			end
			H.expect(f:Process().Name == "NotProcessedYet", "existing marker bypassed persistence")
			f.Store.Before = nil
			H.expect(
				f:Process().Name == "PurchaseGranted"
					and f.Store.Value.Consumables.AppearanceEdits == 3,
				"healthy replay lost credits"
			)
		end
	)

	H.test("actual durable receipt avoids custody work after departure during its save", function()
		local f = fixture(grants[3].Definition)
		f.Store.After = function()
			f.Player.Parent = nil
		end
		H.expect(f:Process().Name == "PurchaseGranted", "durable grant was not acknowledged")
		H.expect(
			f.CustodyCalls == 0 and f.Store.Value.Consumables.EarlyReleaseCredits == 2,
			"stale player reached custody or lost durable credits"
		)
	end)
end
