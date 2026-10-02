--!strict
local fs = require("@lune/fs")
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

	local function sprayFixture(lineOfSight: boolean): any
		local runtime = Runtime.new()
		local tasks = table.clone(runtime.globals.task)
		tasks.delay = function()
			return nil
		end
		runtime.globals.task = tasks
		local services = runtime.services.ServerScriptService.RoleplayOS.Services
		local pava = runtime.require(services.PAVAService)

		local actorCharacter = runtime.globals.Instance.new("Model")
		actorCharacter.Name = "ActorCharacter"
		local actorRoot = runtime.globals.Instance.new("Part")
		actorRoot.Name = "HumanoidRootPart"
		actorRoot.Position = runtime.globals.Vector3.new(0, 0, 0)
		actorRoot.Parent = actorCharacter
		local backpack = runtime.globals.Instance.new("Folder")
		backpack.Name = "Backpack"
		local tool = runtime.globals.Instance.new("Tool")
		tool.Name = "PAVA"
		tool:SetAttribute("RoleplayOSToolId", "PAVA")
		tool.Parent = actorCharacter

		local targetCharacter = runtime.globals.Instance.new("Model")
		targetCharacter.Name = "TargetCharacter"
		local targetRoot = runtime.globals.Instance.new("Part")
		targetRoot.Name = "HumanoidRootPart"
		targetRoot.Position = runtime.globals.Vector3.new(8, 0, 0)
		targetRoot.Parent = targetCharacter
		local targetHumanoid = runtime.globals.Instance.new("Humanoid")
		targetHumanoid.Health = 100
		targetHumanoid.WalkSpeed = 16
		targetHumanoid.Parent = targetCharacter

		local actor: any = {
			UserId = 1,
			Parent = runtime.services.Players,
			Character = actorCharacter,
		}
		function actor:FindFirstChildOfClass(className: string)
			return if className == "Backpack" then backpack else nil
		end
		local targetAttributes = {}
		local target: any = {
			UserId = 2,
			Parent = runtime.services.Players,
			Character = targetCharacter,
		}
		function target:SetAttribute(name: string, value: any)
			targetAttributes[name] = value
		end
		function target:GetAttribute(name: string)
			return targetAttributes[name]
		end
		runtime.services.Players.GetPlayerByUserId = function(_self, userId)
			if userId == actor.UserId then
				return actor
			elseif userId == target.UserId then
				return target
			end
			return nil
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
		pava._lineOfSight = function()
			return lineOfSight
		end
		return {
			Runtime = runtime,
			Service = pava,
			Actor = actor,
			Target = target,
			TargetHumanoid = targetHumanoid,
		}
	end

	local function taserServerSource(): string
		local asset = fs.readFile("server-assets/Tools/Services/Police/Shared/Taser.rbxmx")
		local nameMarker = '<string name="Name">RoleplayOSTaserServer</string>'
		local _, nameEnd = string.find(asset, nameMarker, 1, true)
		assert(nameEnd, "Taser server script marker is missing")
		local sourceTag = '<string name="Source">'
		local _, sourceTagEnd = string.find(asset, sourceTag, nameEnd + 1, true)
		assert(sourceTagEnd, "Taser server source is missing")
		local sourceEnd = string.find(asset, "</string>", sourceTagEnd + 1, true)
		assert(sourceEnd, "Taser server source terminator is missing")
		return string.sub(asset, sourceTagEnd + 1, sourceEnd - 1)
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
	H.test("actual PAVA service rejects an obstructed nearby target", function()
		local f = sprayFixture(false)
		local sprayed, reason = f.Service:Spray(f.Actor, f.Target.UserId)
		H.expect(not sprayed, "obstructed PAVA target was accepted")
		H.expect(reason == "PAVA_TARGET_OBSTRUCTED", "obstructed target did not report obstruction")
	end)
	H.test("actual PAVA service accepts a clear nearby target", function()
		local f = sprayFixture(true)
		local sprayed, reason = f.Service:Spray(f.Actor, f.Target.UserId)
		H.expect(sprayed and reason == nil, "clear PAVA target was refused")
	end)
	H.test("actual PAVA movement reduction survives a Needs speed tick", function()
		local f = sprayFixture(true)
		local sprayed, reason = f.Service:Spray(f.Actor, f.Target.UserId)
		H.expect(sprayed and reason == nil, "PAVA setup failed")
		H.expect(f.TargetHumanoid.WalkSpeed == 10, "PAVA did not apply its movement reduction")

		local needs = f.Runtime.require(
			f.Runtime.services.ServerScriptService.RoleplayOS.Services.NeedsService
		)
		local config = f.Runtime.require(f.Runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		needs.context = { Configuration = config }
		local needsHumanoid: any = { WalkSpeed = f.TargetHumanoid.WalkSpeed }
		function needsHumanoid:GetAttribute(name: string)
			return f.TargetHumanoid:GetAttribute(name)
		end
		function needsHumanoid:SetStateEnabled() end
		needs:_applySpeed(
			f.Target,
			{ Sprinting = false, Hunger = 100, Stamina = 100 },
			needsHumanoid
		)
		H.expect(needsHumanoid.WalkSpeed == 10, "Needs tick cancelled the active PAVA slowdown")
	end)
	H.test("Taser server authority covers every configured Taser loadout", function()
		local runtime = Runtime.new()
		local config = runtime.require(runtime.services.ReplicatedStorage.RoleplayOS.Config.Config)
		local source = taserServerSource()
		local trustsServerIssuance = string.find(source, "RoleplayOSDutyIssued", 1, true) ~= nil
			and string.find(source, "RoleplayOSToolId", 1, true) ~= nil
		for loadoutId, loadout in config.Loadouts do
			if table.find(loadout.ToolIds or {}, "Taser") then
				H.expect(
					trustsServerIssuance or string.find(source, loadoutId, 1, true) ~= nil,
					"Taser server gate denies configured loadout " .. loadoutId
				)
			end
		end
	end)
end
