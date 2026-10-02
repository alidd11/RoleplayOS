--!strict
local Runtime = require("./test-runtime")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		runtime.services.MarketplaceService = {}
		local root = runtime.services.ReplicatedStorage.RoleplayOS
		local config = runtime.require(root.Config.Config)
		local schema = runtime.require(root.Shared.ProfileSchema)
		local profile = schema.default(10)
		profile.Consumables.AppearanceEdits = 1
		local character =
			{ CharacterId = "active", AppearanceLocked = true, Appearance = { HeadScale = 0.95 } }
		profile.Characters.active = character
		local session = { Profile = profile, ActiveCharacterId = "active" }
		local player: any =
			{ UserId = 10, Parent = runtime.services.Players, Team = { Name = "Civilian" } }
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return if id == 10 and player.Parent == runtime.services.Players then player else nil
		end
		local f: any = {
			Profile = profile,
			Character = character,
			Player = player,
			Dirty = 0,
			Saves = {},
			ApplyCalls = 0,
		}
		local dependencies: any = {
			DataService = {
				GetSession = function()
					return session
				end,
				MarkDirty = function()
					f.Dirty += 1
				end,
				Save = function()
					table.insert(f.Saves, profile.Consumables.AppearanceEdits)
					return true, nil
				end,
			},
			DutyService = {
				Get = function()
					return nil
				end,
			},
			ServerModeService = {
				Kind = function()
					return "Public"
				end,
			},
			AuditService = { Record = function() end },
			CustodyService = {
				HasActiveSentence = function()
					return false
				end,
			},
		}
		local context = {
			Configuration = config,
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "Unexpected appearance dependency: " .. name)
				end,
			},
		}
		local services = runtime.services.ServerScriptService.RoleplayOS.Services
		local characters = runtime.require(services.CharacterService)
		characters:Init(context)
		characters:Start()
		local products = runtime.require(services.DeveloperProductService)
		products:Init(context)
		-- Fixture product only: no Marketplace RPC or production ID is used.
		products.products[123] = { GrantType = "CharacterAppearanceEdit", Amount = 1 }
		f.Receipt = { ProductId = 123, PlayerId = 10, PurchaseId = "appearance-grant" }
		local humanoid = {
			ApplyDescriptionReset = function()
				f.ApplyCalls += 1
				if f.GrantDuringApply then
					f.GrantDuringApply = false
					task.defer(function()
						f.Decision = products:_process(f.Receipt)
					end)
					local deadline = os.clock() + 1
					while f.Decision == nil and os.clock() < deadline do
						task.wait(0.01)
					end
					assert(f.Decision ~= nil, "Receipt fixture did not finish")
				end
				if f.FailApply then
					error("Injected appearance application failure")
				end
			end,
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
		f.Service, f.Products = characters, products
		function f:Edit()
			assert(schema.migrate(profile, 10) == profile, "Fixture current migration failed")
			return characters:SetAuthoredAppearance(player, "active", { HeadScale = 1 })
		end
		return f
	end

	H.test(
		"actual authored appearance preserves a receipt grant during avatar application",
		function()
			local f = fixture()
			f.GrantDuringApply = true
			local edited, reason = f:Edit()
			H.expect(edited and reason == nil, "valid edit failed")
			H.expect(
				f.Decision.Name == "PurchaseGranted" and f.Saves[1] == 2,
				"overlapping grant was not saved"
			)
			H.expect(
				f.Profile.Consumables.AppearanceEdits == 1,
				"edit overwrote a new receipt grant"
			)
			H.expect(
				f.Character.AppearanceLocked and f.Service.appearanceWrites["10:active"] == nil,
				"edit lock or claim changed"
			)
			local replay = f.Products:_process(f.Receipt)
			H.expect(replay.Name == "PurchaseGranted", "receipt replay was not acknowledged")
			H.expect(
				f.Profile.Consumables.AppearanceEdits == 1 and #f.Saves == 2 and f.Saves[2] == 1,
				"receipt replay duplicated or lost credits"
			)
		end
	)

	H.test(
		"actual failed authored appearance preserves its credit and overlapping receipt",
		function()
			local f = fixture()
			local original = f.Character.Appearance
			f.GrantDuringApply, f.FailApply = true, true
			local edited = f:Edit()
			H.expect(not edited, "failed avatar application was accepted")
			H.expect(f.Decision.Name == "PurchaseGranted", "overlapping receipt was refused")
			H.expect(
				f.Profile.Consumables.AppearanceEdits == 2,
				"failed application consumed credits"
			)
			H.expect(
				f.Character.Appearance == original and f.Dirty == 1,
				"failed application changed persisted appearance"
			)
			H.expect(
				f.Service.appearanceWrites["10:active"] == nil,
				"failed application retained claim"
			)
		end
	)

	H.test(
		"actual authored appearance keeps ordinary paid, free and insufficient-credit behaviour",
		function()
			for _, case in
				{
					{ Locked = true, Credits = 1, Expected = true },
					{ Locked = false, Credits = 0, Expected = true },
					{ Locked = true, Credits = 0, Expected = false },
				}
			do
				local f = fixture()
				f.Character.AppearanceLocked = case.Locked
				f.Profile.Consumables.AppearanceEdits = case.Credits
				local edited, reason = f:Edit()
				H.expect(edited == case.Expected, "ordinary edit outcome changed")
				H.expect(
					f.Profile.Consumables.AppearanceEdits == 0,
					"ordinary credit accounting changed"
				)
				H.expect(
					f.ApplyCalls == (if case.Expected then 1 else 0),
					"refused edit reached avatar RPC"
				)
				if not case.Expected then
					H.expect(reason == "APPEARANCE_EDIT_REQUIRED", "credit refusal reason changed")
				end
			end
		end
	)
end
