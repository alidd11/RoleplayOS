--!strict
-- Actual cash-drop and economy methods; world presentation/signals are explicit doubles.
local Runtime = require("./test-runtime")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local config = runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		local service = runtime.require(root.MoneyDropService)
		local economy = runtime.require(root.EconomyService)
		local f: any = { Players = {}, Sessions = {}, Logs = {}, Dirty = 0 }
		local origin = roblox.Vector3.new(0, 0, 0)
		for _, id in { 10, 20 } do
			local model = roblox.Instance.new("Model")
			local part = roblox.Instance.new("Part")
			part.Name, part.Parent = "HumanoidRootPart", model
			part.Position, part.CFrame = origin, roblox.CFrame.new(origin)
			local humanoid = roblox.Instance.new("Humanoid")
			humanoid.Health, humanoid.Parent = 100, model
			f.Players[id] = { UserId = id, Parent = runtime.services.Players, Character = model }
			f.Sessions[id] = {
				ActiveCharacterId = "owned",
				Profile = {
					Characters = {
						owned = {
							Economy = {
								Cash = 100,
								Balance = 50,
								Transactions = {},
								PendingCashDropRefunds = {},
							},
						},
					},
				},
			}
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			local player = f.Players[id]
			return if player and player.Parent == runtime.services.Players then player else nil
		end
		local dependencies = {
			EconomyService = economy,
			DutyService = {
				Get = function(_self, player)
					return if f.DutyQuery then f.DutyQuery(player) else nil
				end,
			},
			DataService = {
				GetSession = function(_self, player)
					return if f.Players[player.UserId] == player
						then f.Sessions[player.UserId]
						else nil
				end,
				MarkDirty = function()
					f.Dirty += 1
				end,
			},
			AuditService = { Record = function() end },
		}
		local logger = {}
		for _, level in { "Error", "Warning" } do
			logger[level] = function(_self, message)
				table.insert(f.Logs, message)
			end
		end
		local context = {
			Configuration = config,
			Logger = logger,
			Services = {
				Get = function(_self, name)
					return assert(dependencies[name], "Unexpected cash-drop fixture dependency")
				end,
			},
		}
		service:Init(context)
		economy:Init(context)
		service.running, economy.running = true, true
		-- Native prompt signals and expiry scheduling belong to engine acceptance.
		service._create = function(self, id, amount, userId, characterId, position)
			if f.CreationFails then
				error("injected world creation failure")
			end
			local part = roblox.Instance.new("Part")
			part.Position = position
			local record = {
				Part = part,
				Amount = amount,
				OwnerUserId = userId,
				OwnerCharacterId = characterId,
				CreatedAt = 1,
				Collecting = false,
			}
			self.drops[id] = record
			return record
		end
		f.Service, f.Economy = service, economy
		function f:Character(id)
			return self.Sessions[id].Profile.Characters.owned
		end
		function f:Drop()
			local result, reason = service:Drop(self.Players[10], 10)
			assert(result and reason == nil, "Fixture cash drop failed: " .. tostring(reason))
			return result.DropId
		end
		function f:Destroy()
			service:Destroy()
			economy:Destroy()
			for _, player in self.Players do
				player.Character:Destroy()
			end
		end
		return f
	end

	H.test("actual cash drop debits cash and one pickup credits cash exactly once", function()
		local f = fixture()
		local id = f:Drop()
		H.expect(f:Character(10).Economy.Cash == 90, "drop did not debit cash")
		f.Service:_collect(id, f.Players[20])
		f.Service:_collect(id, f.Players[20])
		H.expect(
			f:Character(20).Economy.Cash == 110 and f.Service.drops[id] == nil,
			"pickup duplicated or lost credit"
		)
		H.expect(
			f:Character(10).Economy.Balance == 50 and f:Character(20).Economy.Balance == 50,
			"drop changed bank funds"
		)
		H.expect(
			#f:Character(20).Economy.Transactions == 1 and f.Service.pendingDrops == 0,
			"pickup or reservation retained state"
		)
		f:Destroy()
	end)

	H.test("actual cash pickup claims the drop before yielding duty lookup", function()
		local f = fixture()
		local id = f:Drop()
		local entered, finished, release = false, false, false
		f.DutyQuery = function()
			entered = true
			local deadline = os.clock() + 1
			while not release and os.clock() < deadline do
				task.wait(0.001)
			end
			return nil
		end
		task.spawn(function()
			f.Service:_collect(id, f.Players[20])
			finished = true
		end)
		local deadline = os.clock() + 1
		while not entered and os.clock() < deadline do
			task.wait(0.001)
		end
		assert(entered, "pickup did not reach duty checkpoint")
		f.Service:_collect(id, f.Players[20])
		release = true
		while not finished and os.clock() < deadline do
			task.wait(0.001)
		end
		H.expect(
			finished
				and f:Character(20).Economy.Cash == 110
				and #f:Character(20).Economy.Transactions == 1,
			"concurrent pickup duplicated credit"
		)
		f:Destroy()
	end)

	H.test("actual expired cash drop cannot be credited after a yielding duty lookup", function()
		local f = fixture()
		local id = f:Drop()
		f.DutyQuery = function()
			task.wait(0.001)
			f.Service:_remove(id, "Expired")
			return nil
		end
		f.Service:_collect(id, f.Players[20])
		H.expect(
			f:Character(20).Economy.Cash == 100 and f:Character(10).Economy.Cash == 90,
			"expiry credited or refunded normal loss"
		)
		f:Destroy()
	end)

	H.test("actual cash pickup refusal releases its claim for a healthy retry", function()
		for _, missingCharacter in { false, true } do
			local f = fixture()
			local id = f:Drop()
			if missingCharacter then
				f.Sessions[20].ActiveCharacterId = nil
			else
				f.Economy.transferring[20] = true
			end
			f.Service:_collect(id, f.Players[20])
			H.expect(
				not f.Service.drops[id].Collecting and f:Character(20).Economy.Cash == 100,
				"refused pickup retained claim or paid"
			)
			f.Sessions[20].ActiveCharacterId = "owned"
			f.Economy.transferring[20] = nil
			f.Service:_collect(id, f.Players[20])
			H.expect(f:Character(20).Economy.Cash == 110, "healthy retry remained blocked")
			f:Destroy()
		end
	end)

	H.test(
		"actual cash-drop admission reserves pending capacity without debiting refusals",
		function()
			local f = fixture()
			f.Service.settings = table.clone(f.Service.settings)
			f.Service.settings.MaximumActiveGlobal = 1
			local claim = f.Service:_claimDropSlot(f.Players[10])
			assert(claim, "fixture reservation refused")
			local result, reason = f.Service:Drop(f.Players[20], 10)
			H.expect(
				result == nil
					and reason == "SERVER_DROP_LIMIT"
					and f:Character(20).Economy.Cash == 100,
				"pending capacity was not reserved"
			)
			f.Service:_releaseDropSlot(10, claim)
			f.Service:_releaseDropSlot(10, claim)
			H.expect(f.Service.pendingDrops == 0, "reservation release was not idempotent")
			f:Drop()
			f:Destroy()
		end
	)

	H.test("actual cash-drop request fences departure and teardown after duty lookup", function()
		for _, teardown in { false, true } do
			local f = fixture()
			f.DutyQuery = function()
				task.wait(0.001)
				if teardown then
					f.Service:Destroy()
				else
					f.Players[10].Parent = nil
				end
				return nil
			end
			local result, reason = f.Service:Drop(f.Players[10], 10)
			H.expect(
				result == nil
					and reason == "MONEY_DROP_UNAVAILABLE"
					and f:Character(10).Economy.Cash == 100
					and next(f.Service.drops) == nil,
				"late request debited or recreated a world drop"
			)
			f:Destroy()
		end
	end)

	H.test("actual failed cash-drop creation refunds the debit and releases admission", function()
		local f = fixture()
		f.CreationFails = true
		local result, reason = f.Service:Drop(f.Players[10], 10)
		H.expect(
			result == nil
				and reason == "DROP_CREATION_FAILED"
				and f:Character(10).Economy.Cash == 100,
			"failed creation lost debit"
		)
		H.expect(
			f.Service.pendingDrops == 0
				and next(f.Service.dropping) == nil
				and next(f.Service.drops) == nil,
			"failed creation retained reservation"
		)
		H.expect(#f:Character(10).Economy.Transactions == 2, "refund did not pass through economy")
		f:Destroy()
	end)

	H.test(
		"actual cash-drop shutdown queues inactive-character refunds and replays once",
		function()
			local f = fixture()
			local id = f:Drop()
			f.Sessions[10].ActiveCharacterId = nil
			f.Service:Destroy()
			local pending = f:Character(10).Economy.PendingCashDropRefunds
			H.expect(
				pending[id] and pending[id].Amount == 10 and f:Character(10).Economy.Cash == 90,
				"inactive refund lost or paid wrong character"
			)
			H.expect(next(f.Service.drops) == nil, "shutdown retained world drop")
			local recovery = table.clone(pending[id])
			f.Sessions[10].ActiveCharacterId = "owned"
			H.expect(
				f.Economy:ReconcileMoneyDropRefunds(f.Players[10], "owned"),
				"refund did not recover"
			)
			-- Replay a stale recovery row, not merely an empty second read.
			pending[id] = recovery
			H.expect(
				f.Economy:ReconcileMoneyDropRefunds(f.Players[10], "owned"),
				"stale recovery row did not reconcile"
			)
			H.expect(
				f:Character(10).Economy.Cash == 100
					and next(pending) == nil
					and #f:Character(10).Economy.Transactions == 2,
				"refund replay duplicated or lost money"
			)
			f:Destroy()
		end
	)
end
