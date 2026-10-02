--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(equipped: boolean): any
		local runtime = Runtime.new()
		local services = runtime.services.ServerScriptService.RoleplayOS.Services
		local pava = runtime.require(services.PAVAService)

		local character = runtime.globals.Instance.new("Model")
		character.Name = "Character"
		local backpack = runtime.globals.Instance.new("Folder")
		backpack.Name = "Backpack"
		local tool = runtime.globals.Instance.new("Tool")
		tool.Name = "PAVA"
		tool:SetAttribute("RoleplayOSToolId", "PAVA")
		tool.Parent = if equipped then character else backpack

		local actor: any = {
			UserId = 1,
			Parent = runtime.services.Players,
			Character = character,
		}
		function actor:FindFirstChildOfClass(className: string)
			return if className == "Backpack" then backpack else nil
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, userId)
			return if userId == actor.UserId then actor else nil
		end

		local context = {
			Services = {
				Get = function(_self, name)
					assert(name == "DutyService", "Unexpected PAVA dependency")
					return {
						Get = function()
							return { DepartmentId = "Police" }
						end,
					}
				end,
			},
			Network = {
				RegisterEvent = function()
					return { FireClient = function() end }
				end,
			},
			Logger = { Audit = function() end },
		}
		pava:Init(context)
		pava.running = true
		return { Service = pava, Actor = actor }
	end

	H.test("actual PAVA service rejects a backpack-only canister", function()
		local f = fixture(false)
		local sprayed, reason = f.Service:Spray(f.Actor, 2)
		H.expect(not sprayed, "backpack-only PAVA was accepted")
		H.expect(reason == "PAVA_NOT_EQUIPPED", "backpack-only PAVA reached target validation")
	end)

	H.test(
		"actual PAVA service recognises an equipped canister before target validation",
		function()
			local f = fixture(true)
			local sprayed, reason = f.Service:Spray(f.Actor, 2)
			H.expect(not sprayed, "missing target unexpectedly accepted")
			H.expect(reason == "PAVA_TARGET_INVALID", "equipped PAVA was treated as unequipped")
		end
	)
end
