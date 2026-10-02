--!strict
local Runtime = require("./test-runtime")
local roblox = require("@lune/roblox")

return function(H: any)
	local function fixture(inventory: any?): any
		local runtime = Runtime.new()
		local player = { UserId = 10, Parent = runtime.services.Players }
		local character = { CharacterId = "owned", Inventory = inventory }
		local session =
			{ ActiveCharacterId = "owned", Profile = { Characters = { owned = character } } }
		local dirty = 0
		local data = {}
		function data:GetSession(candidate)
			return if candidate == player then session else nil
		end
		function data:MarkDirty(_candidate)
			dirty += 1
		end
		local modules = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(modules.InventoryService)
		local configuration =
			runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		local services = { DataService = data, InventoryService = service }
		local context = {
			Configuration = configuration,
			Services = {
				Get = function(_self, name)
					return assert(services[name], "Unconfigured inventory fixture dependency")
				end,
			},
			Network = {
				RegisterEvent = function(_self, _name)
					return { FireClient = function() end }
				end,
			},
		}
		service:Init(context)
		return {
			Runtime = runtime,
			Player = player,
			Character = character,
			Service = service,
			Context = context,
			Dirty = function()
				return dirty
			end,
		}
	end

	H.test("inventory preserves unreadable persisted containers without dirtying them", function()
		for _, persisted in { "damaged", true, 4 } do
			local f = fixture(persisted)
			local added, reason = f.Service:Add(f.Player, "owned", "Sandwich", 1)
			H.expect(
				not added and reason == "INVALID_INVENTORY",
				"unreadable inventory was replaced"
			)
			local removed, removeReason = f.Service:Remove(f.Player, "owned", "Sandwich", 1)
			H.expect(
				not removed and removeReason == "INVALID_INVENTORY",
				"unreadable inventory was consumed"
			)
			H.expect(not f.Service:Has(f.Character, "Sandwich"), "unreadable inventory was usable")
			H.expect(
				f.Character.Inventory == persisted and f.Dirty() == 0,
				"damaged source was mutated"
			)
		end
	end)

	H.test("inventory enforces the stack limit for the first grant", function()
		local f = fixture({})
		local added, reason = f.Service:Add(f.Player, "owned", "Sandwich", 2)
		H.expect(not added and reason == "STACK_LIMIT", "first stack exceeded its configured limit")
		H.expect(
			next(f.Character.Inventory) == nil and f.Dirty() == 0,
			"refused grant changed inventory"
		)
	end)

	H.test("inventory validates caller quantities without throwing or mutating", function()
		for _, quantity in { "1", true, {}, 0, -1, 0.5, 0 / 0, math.huge, -math.huge } do
			local f = fixture({})
			local added, reason = f.Service:Add(f.Player, "owned", "Sandwich", quantity)
			H.expect(not added and reason == "INVALID_ITEM", "invalid addition accepted")
			local removed, removeReason = f.Service:Remove(f.Player, "owned", "Sandwich", quantity)
			H.expect(not removed and removeReason == "INVALID_ITEM", "invalid removal accepted")
			H.expect(
				next(f.Character.Inventory) == nil and f.Dirty() == 0,
				"invalid quantity changed data"
			)
		end
	end)

	H.test("inventory ignores unrelated malformed rows without deleting them", function()
		local f = fixture({ 4, { DefinitionId = "Unknown", Quantity = "unreadable" } })
		H.expect(
			f.Service:Add(f.Player, "owned", "Sandwich", 1),
			"malformed unrelated row blocked grant"
		)
		H.expect(f.Service:Has(f.Character, "Sandwich"), "valid held item hidden")
		H.expect(f.Service:Remove(f.Player, "owned", "Sandwich", 1), "valid removal blocked")
		H.expect(
			f.Character.Inventory[1] == 4 and #f.Character.Inventory == 2 and f.Dirty() == 2,
			"unrelated rows were rewritten"
		)
	end)

	H.test("inventory refuses unreadable matching quantities without erasing ownership", function()
		for _, quantity in { "1", {}, 0, -1, 0.5, 0 / 0, math.huge } do
			local item = { ItemId = "original", DefinitionId = "Sandwich", Quantity = quantity }
			local f = fixture({ item })
			local added, reason = f.Service:Add(f.Player, "owned", "Sandwich", 1)
			H.expect(
				not added and reason == "INVALID_ITEM_STATE",
				"invalid held quantity accepted addition"
			)
			local removed, removeReason = f.Service:Remove(f.Player, "owned", "Sandwich", 1)
			H.expect(
				not removed and removeReason == "INVALID_ITEM_STATE",
				"invalid held quantity accepted removal"
			)
			H.expect(
				not f.Service:Has(f.Character, "Sandwich"),
				"unreadable quantity treated as usable"
			)
			H.expect(
				f.Character.Inventory[1] == item and #f.Character.Inventory == 1 and f.Dirty() == 0,
				"invalid ownership row changed"
			)
		end
	end)

	H.test(
		"inventory retains legacy missing-container backfill and valid stack consumption",
		function()
			local f = fixture()
			H.expect(
				f.Service:Add(f.Player, "owned", "Parcel", 4),
				"missing container not backfilled"
			)
			H.expect(f.Service:Add(f.Player, "owned", "Parcel", 6), "valid stack top-up refused")
			local added, reason = f.Service:Add(f.Player, "owned", "Parcel", 1)
			H.expect(not added and reason == "STACK_LIMIT", "existing stack exceeded limit")
			H.expect(
				f.Service:Remove(f.Player, "owned", "Parcel", 3),
				"partial consumption refused"
			)
			H.expect(f.Character.Inventory[1].Quantity == 7, "partial consumption wrong")
			H.expect(f.Service:Remove(f.Player, "owned", "Parcel", 7), "final consumption refused")
			H.expect(
				next(f.Character.Inventory) == nil and f.Dirty() == 4,
				"stack not removed exactly once"
			)
		end
	)

	H.test("inventory refuses another character and unavailable sessions", function()
		local f = fixture({})
		H.expect(
			not f.Service:Add(f.Player, "other", "Sandwich", 1),
			"foreign character granted item"
		)
		H.expect(
			not f.Service:Add({ UserId = 10 }, "owned", "Sandwich", 1),
			"wrong player acquired inventory"
		)
		H.expect(f.Dirty() == 0, "refused ownership marked data dirty")
	end)

	H.test(
		"actual starter-food grant survives unrelated malformed inventory and stays idempotent",
		function()
			local f = fixture({ 4 })
			local backpack = roblox.Instance.new("Backpack")
			f.Player.FindFirstChildOfClass = function(_self, name)
				return if name == "Backpack" then backpack else nil
			end
			local needs = f.Runtime.require(
				f.Runtime.services.ServerScriptService.RoleplayOS.Services.NeedsService
			)
			needs:Init(f.Context)
			needs.running = true
			-- Explicit presentation double: native tool wiring/activation remains Studio-only.
			needs._makeFoodTool = function(_self, name, foodId)
				return { Name = name, FoodId = foodId, Activated = { Connect = function() end } }
			end
			needs:EnsureStarterFood(f.Player)
			needs:EnsureStarterFood(f.Player)
			H.expect(
				f.Character.StarterFoodGranted == true and #f.Character.Inventory == 2,
				"starter grant failed or duplicated"
			)
			H.expect(
				f.Character.Inventory[1] == 4 and f.Service:Has(f.Character, "Sandwich"),
				"grant destroyed legacy data"
			)
			H.expect(f.Dirty() == 2, "repeated starter grant dirtied profile again")
			needs.running = false
		end
	)
end
