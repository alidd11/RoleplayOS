--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MeleeWeaponController = { connections = {}, watched = setmetatable({}, { __mode = "k" }) }

local function targetFromAim(mouse: Mouse?): Player?
	local part = mouse and mouse.Target
	local model = part and part:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if player and player ~= Players.LocalPlayer then
		return player
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X * 0.5, size.Y * 0.5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if Players.LocalPlayer.Character
		then { Players.LocalPlayer.Character }
		else {}
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	local hitModel = result and result.Instance:FindFirstAncestorOfClass("Model")
	local hitPlayer = hitModel and Players:GetPlayerFromCharacter(hitModel)
	return if hitPlayer and hitPlayer ~= Players.LocalPlayer then hitPlayer else nil
end

local function attackAnimation(tool: Tool, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid
		and (humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator"))
	if not animator then
		return
	end
	animator.Parent = humanoid
	for _, name in { "Attack", "Swing", "Slash", "MacheteAttack", "KnifeAttack" } do
		local animation = tool:FindFirstChild(name, true)
		if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.06)
				return
			end
		end
	end
end

function MeleeWeaponController:Init(context: any)
	self.context = context
	self.connections = {}
	self.watched = setmetatable({}, { __mode = "k" })
end

function MeleeWeaponController:_watch(tool: Instance)
	if
		not tool:IsA("Tool")
		or not tool:GetAttribute("RoleplayOSWeaponId")
		or self.watched[tool]
	then
		return
	end
	self.watched[tool] = true
	local mouse: Mouse? = nil
	table.insert(
		self.connections,
		tool.Equipped:Connect(function(value)
			mouse = value
		end)
	)
	table.insert(
		self.connections,
		tool.Unequipped:Connect(function()
			mouse = nil
		end)
	)
	table.insert(
		self.connections,
		tool.Activated:Connect(function()
			local target = targetFromAim(mouse)
			if not target then
				self.context.Controllers.NotificationController:Show(
					"Aim at a nearby player to use this item.",
					"Equipment"
				)
				return
			end
			local response = self.context.Controllers.NetworkController:Request(
				"MeleeStrike",
				{ TargetUserId = target.UserId }
			)
			local character = tool.Parent
			if response.Success and character and character:IsA("Model") then
				attackAnimation(tool, character)
			end
			if not response.Success and response.Code ~= "WEAPON_COOLDOWN" then
				self.context.Controllers.NotificationController:Show(response.Message, "Equipment")
			end
		end)
	)
end

function MeleeWeaponController:_scan(container: Instance)
	for _, child in container:GetChildren() do
		self:_watch(child)
	end
	table.insert(
		self.connections,
		container.ChildAdded:Connect(function(child)
			self:_watch(child)
		end)
	)
end

function MeleeWeaponController:Start()
	local player = Players.LocalPlayer
	self:_scan(player:WaitForChild("Backpack"))
	local function characterAdded(character: Model)
		self:_scan(character)
	end
	if player.Character then
		characterAdded(player.Character)
	end
	table.insert(self.connections, player.CharacterAdded:Connect(characterAdded))
end

function MeleeWeaponController:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.watched = {}
end

return MeleeWeaponController
