--!strict
local fs = require("@lune/fs")
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(): any
		local runtime = Runtime.new()
		local shared = runtime.services.ReplicatedStorage.RoleplayOS
		local schema = runtime.require(shared.Shared.ProfileSchema)
		local profile = schema.default(10)
		local character = {
			Vehicles = {},
			Properties = {},
			Employment = {},
			Economy = { PendingCashDropRefunds = {} },
		}
		profile.Characters.owned = character
		profile.CharacterSlots = { "owned" }
		local player = { UserId = 10, Parent = runtime.services.Players }
		runtime.services.Players.GetPlayerByUserId = function(_self, id)
			return if id == 10 and player.Parent == runtime.services.Players then player else nil
		end
		local f: any = {
			Profile = profile,
			Character = character,
			Player = player,
			Session = { Profile = profile },
			Dirty = 0,
		}
		local data = {
			GetSession = function(_self, candidate)
				return if candidate == player then f.Session else nil
			end,
			MarkDirty = function()
				f.Dirty += 1
			end,
		}
		local service = runtime.require(
			runtime.services.ServerScriptService.RoleplayOS.Services.CharacterService
		)
		service:Init({
			Services = {
				Get = function(_self, name)
					assert(name == "DataService", "Unexpected deletion dependency")
					return data
				end,
			},
		})
		service:Start()
		f.Service = service
		function f:Delete()
			assert(schema.migrate(profile, 10) == profile, "Fixture current migration failed")
			return service:Delete(player, "owned", "owned")
		end
		function f:AssertPreserved()
			H.expect(
				profile.Characters.owned == character
					and profile.CharacterSlots[1] == "owned"
					and self.Dirty == 0,
				"refused deletion changed ownership, slots or dirty state"
			)
		end
		return f
	end

	H.test("actual character deletion preserves dictionary and sparse protected records", function()
		for _, field in { "Vehicles", "Properties", "Employment" } do
			for _, collection in
				{ { legacy = { Id = "protected" } }, { [100] = { Id = "protected" } } }
			do
				local f = fixture()
				f.Character[field] = collection
				local deleted, reason = f:Delete()
				H.expect(
					not deleted and reason == "CHARACTER_HAS_PROTECTED_RECORDS",
					"protected keyed collection allowed deletion: " .. field
				)
				H.expect(f.Character[field] == collection, "protected collection was rewritten")
				f:AssertPreserved()
				f.Service:Destroy()
			end
		end
	end)

	H.test(
		"actual character deletion refuses unreadable protected collections without erasure",
		function()
			for _, field in { "Vehicles", "Properties", "Employment" } do
				for _, value in { 4, "", false } do
					local f = fixture()
					f.Character[field] = value
					local completed, deleted, reason = pcall(function()
						return f:Delete()
					end)
					H.expect(
						completed and not deleted and reason == "CHARACTER_RECORDS_UNREADABLE",
						"unreadable collection raised or allowed deletion: " .. field
					)
					H.expect(f.Character[field] == value, "unreadable collection was rewritten")
					f:AssertPreserved()
					f.Service:Destroy()
				end
			end
		end
	)

	H.test(
		"actual character deletion refuses unreadable recovery and slot state before mutation",
		function()
			for _, state in { "slots", "refunds", "economy" } do
				local f = fixture()
				if state == "slots" then
					f.Profile.CharacterSlots = 4
				elseif state == "refunds" then
					f.Character.Economy.PendingCashDropRefunds = ""
				else
					f.Character.Economy = 4
				end
				local completed, deleted, reason = pcall(function()
					return f:Delete()
				end)
				H.expect(
					completed and not deleted and reason == "CHARACTER_RECORDS_UNREADABLE",
					"unreadable recovery/slots raised or allowed deletion"
				)
				H.expect(
					f.Profile.Characters.owned == f.Character and f.Dirty == 0,
					"unreadable state erased the character"
				)
				H.expect(
					if state == "slots"
						then f.Profile.CharacterSlots == 4
						elseif state == "refunds" then f.Character.Economy.PendingCashDropRefunds
							== ""
						else f.Character.Economy == 4,
					"unreadable state was replaced"
				)
				f.Service:Destroy()
			end
		end
	)

	H.test(
		"actual character deletion retains confirmation, active and recovery refusals",
		function()
			local f = fixture()
			local deleted, reason = f.Service:Delete(f.Player, "owned", "wrong")
			H.expect(
				not deleted and reason == "DELETION_NOT_CONFIRMED",
				"confirmation was bypassed"
			)
			f.Session.ActiveCharacterId = "owned"
			deleted, reason = f:Delete()
			H.expect(not deleted and reason == "CHARACTER_ACTIVE", "active character was deleted")
			f.Session.ActiveCharacterId = nil
			f.Character.Economy.PendingCashDropRefunds.recovery = { Amount = 10 }
			deleted, reason = f:Delete()
			H.expect(
				not deleted and reason == "CHARACTER_HAS_PENDING_RECOVERY",
				"pending recovery was deleted"
			)
			f:AssertPreserved()
			f.Service:Destroy()
		end
	)

	H.test(
		"actual empty inactive character deletion removes its slot and marks dirty once",
		function()
			local f = fixture()
			local deleted, reason = f:Delete()
			H.expect(
				deleted
					and reason == nil
					and f.Profile.Characters.owned == nil
					and #f.Profile.CharacterSlots == 0
					and f.Dirty == 1,
				"valid empty deletion changed"
			)
			f.Service:Destroy()
		end
	)
	H.test("territory civilian spawn rolls back team after interrupted load", function()
		local source = fs.readFile("src/server/Services/SpawnService.luau")
		local territoryStart =
			string.find(source, "function SpawnService:_enterCivilianAtTerritory", 1, true)
		local loadAt = territoryStart
			and string.find(source, "player:LoadCharacterAsync()", territoryStart, true)
		local checkAt = loadAt
			and string.find(
				source,
				"if not self.running or not playerIsCurrent(player) then",
				loadAt,
				true
			)
		local restoreAt = checkAt
			and string.find(source, "player.Team = previousTeam", checkAt, true)
		H.expect(
			loadAt ~= nil and checkAt ~= nil and restoreAt ~= nil,
			"interrupted territory load leaves the civilian team assigned"
		)
	end)
	H.test("dispatch character setup bounds humanoid wait and rejects stale respawns", function()
		local source = fs.readFile("src/client/Controllers/DispatchController.luau")
		H.expect(
			string.find(source, 'character:WaitForChild("Humanoid", 10)', 1, true) ~= nil,
			"dispatch character setup can wait forever for a missing humanoid"
		)
		H.expect(
			string.find(source, "character ~= Players.LocalPlayer.Character", 1, true) ~= nil,
			"dispatch can attach seat listeners to a stale character after yielding"
		)
	end)
end
