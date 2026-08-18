--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TaserPoseController = { connections = {}, watched = {} }

function TaserPoseController:Init(_context: any) end

local function isTaser(tool: Instance): boolean
	return tool:IsA("Tool")
		and (tool.Name == "Taser" or tool:GetAttribute("RoleplayOSToolId") == "Taser")
end

local AIM_PITCH = math.rad(-88)

function TaserPoseController:_clear(tool: Tool)
	local state = self.watched[tool]
	if not state then
		return
	end
	if state.Control and state.Control.Parent then
		state.Control:Destroy()
	end
	if state.Target and state.Target.Parent then
		state.Target:Destroy()
	end
	if state.PoseConnection then
		state.PoseConnection:Disconnect()
	end
	if state.RightShoulder and state.RightShoulder.Parent then
		state.RightShoulder.Transform = CFrame.identity
	end
	if state.Track then
		pcall(function()
			state.Track:Stop(0.15)
		end)
		state.Track = nil
	end
	state.Control = nil
	state.Target = nil
	state.PoseConnection = nil
	state.RightShoulder = nil
end

-- Imported animation IDs can be unavailable to a group-owned experience even
-- when Animator:LoadAnimation returns a track. This local R15 IK pose is an
-- ownership-independent fallback: the right hand retains Roblox's Tool grip and
-- the support hand is brought onto the device. It exists only while equipped.
-- An authored hold, if the tool was issued with one.
--
-- The IK pose below exists because imported animation ids can be unavailable to
-- a group-owned experience, which makes a hand-built pose the only thing that
-- always works. That reasoning does not apply to an animation the group itself
-- owns: it loads, and a hand-authored hold beats anything assembled from an
-- IKControl and a shoulder angle. Tried first, and the pose stays as the answer
-- for every tool that has none.
function TaserPoseController:_animated(tool: Tool): boolean
	local animation = tool:FindFirstChild("Idle")
	if not (animation and animation:IsA("Animation")) or animation.AnimationId == "" then
		return false
	end
	local character = tool.Parent
	local humanoid = character
		and character:IsA("Model")
		and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return false
	end
	-- Idle priority so the walk and run underneath it still read, and looped
	-- because a hold is held rather than played once.
	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	track:Play(0.15)
	local state = self.watched[tool]
	if state then
		state.Track = track
	end
	return true
end

function TaserPoseController:_pose(tool: Tool)
	self:_clear(tool)
	if self:_animated(tool) then
		return
	end
	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local upperArm = character:FindFirstChild("LeftUpperArm")
	local hand = character:FindFirstChild("LeftHand")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local rightShoulder = upperTorso and upperTorso:FindFirstChild("RightShoulder")
	local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)
	if
		not humanoid
		or not upperArm
		or not hand
		or not rightShoulder
		or not rightShoulder:IsA("Motor6D")
		or not handle
		or not handle:IsA("BasePart")
	then
		return
	end

	local target = Instance.new("Attachment")
	target.Name = "RoleplayOSTaserSupportGrip"
	-- Positioned slightly behind and to the left of the primary grip. This keeps
	-- elbows natural across standard Roblox body proportions.
	target.CFrame = CFrame.new(-0.18, -0.08, 0.22) * CFrame.Angles(0, math.rad(90), 0)
	target.Parent = handle

	local control = Instance.new("IKControl")
	control.Name = "RoleplayOSTaserSupportHand"
	control.Type = Enum.IKControlType.Position
	control.ChainRoot = upperArm
	control.EndEffector = hand
	control.Target = target
	control.SmoothTime = 0.08
	control.Weight = 1
	control.Priority = 20
	control.Parent = humanoid

	local state = self.watched[tool]
	if state then
		state.Control = control
		state.Target = target
		state.RightShoulder = rightShoulder
		state.PoseConnection = RunService.PreSimulation:Connect(function()
			if tool.Parent ~= character then
				return
			end
			-- Raise the gripping arm into a forward presentation. PreSimulation runs
			-- after Animator evaluation, so an unavailable imported idle animation
			-- cannot leave the device hanging toward the floor.
			-- Motor6D shoulder pitch is negative toward the front of an R15 rig.
			-- The previous positive pitch folded the weapon arm down the torso, which
			-- is the exact one-handed/downward pose this fallback is meant to prevent.
			rightShoulder.Transform = CFrame.Angles(AIM_PITCH, 0, math.rad(-7))
		end)
	end
end

function TaserPoseController:_watch(tool: Tool)
	if self.watched[tool] then
		return
	end
	local state = {
		Connections = {},
		Control = nil,
		Target = nil,
		PoseConnection = nil,
		RightShoulder = nil,
		Track = nil,
	}
	self.watched[tool] = state
	table.insert(
		state.Connections,
		tool.Equipped:Connect(function()
			task.defer(function()
				if tool.Parent then
					self:_pose(tool)
				end
			end)
		end)
	)
	table.insert(
		state.Connections,
		tool.Unequipped:Connect(function()
			self:_clear(tool)
		end)
	)
	table.insert(
		state.Connections,
		tool.Destroying:Connect(function()
			self:_clear(tool)
			for _, connection in state.Connections do
				connection:Disconnect()
			end
			self.watched[tool] = nil
		end)
	)
	if tool.Parent and tool.Parent:IsA("Model") then
		self:_pose(tool)
	end
end

function TaserPoseController:_scan(container: Instance)
	for _, child in container:GetChildren() do
		if isTaser(child) then
			self:_watch(child :: Tool)
		end
	end
	table.insert(
		self.connections,
		container.ChildAdded:Connect(function(child)
			if isTaser(child) then
				self:_watch(child :: Tool)
			end
		end)
	)
end

function TaserPoseController:Start()
	local player = Players.LocalPlayer
	self:_scan(player:WaitForChild("Backpack"))
	if player.Character then
		self:_scan(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self:_scan(character)
		end)
	)
end

function TaserPoseController:Destroy()
	for tool, state in self.watched do
		self:_clear(tool)
		for _, connection in state.Connections do
			connection:Disconnect()
		end
		self.watched[tool] = nil
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return TaserPoseController
