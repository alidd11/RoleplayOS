--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

-- The joint that swings, on either rig.
--
-- R15 keeps the shoulder inside the upper arm; R6 keeps it on the torso and
-- spells it with a space. Returning whichever exists means the swing does not
-- care which rig a player is on, and returns nothing for a character that has
-- neither rather than guessing.
local function swingJoint(character: Model): Motor6D?
	local r15 = character:FindFirstChild("RightUpperArm")
	local joint = r15 and r15:FindFirstChild("RightShoulder")
	if not joint then
		local torso = character:FindFirstChild("Torso")
		joint = torso and torso:FindFirstChild("Right Shoulder")
	end
	return if joint and joint:IsA("Motor6D") then joint else nil
end

-- A swing built from the arm rather than from an uploaded animation.
--
-- Roblox's animator writes every joint's Transform each frame, so setting one
-- and walking away is overwritten before it draws. Writing it every frame at a
-- render step bound after the animator is what makes it stick, and unbinding at
-- the end hands the arm straight back to whatever was playing.
--
-- This is deliberately a fallback. A hand-authored animation looks better than
-- anything derived from a sine curve, and the loop above will prefer one the
-- moment a tool carries it: drop an Animation named Swing inside the tool with
-- a real AnimationId and this code stops running. Until then a knife that does
-- damage should at least look like it was used.
local SWING_SECONDS = 0.26
local SWING_RADIANS = math.rad(115)

local function proceduralSwing(character: Model)
	local joint = swingJoint(character)
	if not joint then
		return
	end
	local existing = character:FindFirstChild("RoleplayOSSwing")
	if existing then
		return
	end
	local marker = Instance.new("BoolValue")
	marker.Name = "RoleplayOSSwing"
	marker.Parent = character

	local started = os.clock()
	local binding = "RoleplayOSMeleeSwing"
	RunService:BindToRenderStep(binding, Enum.RenderPriority.Character.Value + 1, function()
		local elapsed = os.clock() - started
		if elapsed >= SWING_SECONDS or not joint.Parent or not marker.Parent then
			RunService:UnbindFromRenderStep(binding)
			marker:Destroy()
			return
		end
		-- Out fast and back slower, which is how a blade is actually swung.
		local progress = elapsed / SWING_SECONDS
		local curve = math.sin(progress * math.pi)
		joint.Transform = joint.Transform * CFrame.Angles(-SWING_RADIANS * curve, 0, 0)
	end)
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
	proceduralSwing(character)
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
			if response and response.Success and character and character:IsA("Model") then
				attackAnimation(tool, character)
			end
			if response and not response.Success and response.Code ~= "WEAPON_COOLDOWN" then
				self.context.Controllers.NotificationController:Show(
					response.Message or "That item could not be used.",
					"Equipment"
				)
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
