--!strict

local Players = game:GetService("Players")

local PAVAController = { connections = {}, watched = {} }

local function targetPlayer(mouse: Mouse): Player?
	local part = mouse.Target
	local character = part and part:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function playAnimation(tool: Tool, character: Model, name: string)
	local animation = tool:FindFirstChild(name)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if
		not animation
		or not animation:IsA("Animation")
		or animation.AnimationId == ""
		or not humanoid
	then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.08)
	end
end

function PAVAController:Init(context: any)
	self.context = context
	self.connections = {}
	self.watched = setmetatable({}, { __mode = "k" })
	self.mouse = nil
end

function PAVAController:_watch(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "PAVA" or self.watched[tool] then
		return
	end
	self.watched[tool] = true
	table.insert(
		self.connections,
		tool.Equipped:Connect(function(mouse)
			self.mouse = mouse
			local character = tool.Parent
			if character and character:IsA("Model") then
				playAnimation(tool, character, "PAVA Equipping")
			end
		end)
	)
	table.insert(
		self.connections,
		tool.Activated:Connect(function()
			local mouse = self.mouse
			local target = mouse and targetPlayer(mouse)
			if not target then
				self.context.Controllers.NotificationController:Show(
					"Aim at a nearby player to deploy PAVA.",
					"PAVA"
				)
				return
			end
			local response = self.context.Controllers.NetworkController:Request("PAVASpray", {
				TargetUserId = target.UserId,
			})
			if not response.Success then
				self.context.Controllers.NotificationController:Show(response.Message, "PAVA")
			end
		end)
	)
	table.insert(
		self.connections,
		tool.Unequipped:Connect(function()
			self.mouse = nil
		end)
	)
end

function PAVAController:_watchContainer(container: Instance)
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

function PAVAController:Start()
	local player = Players.LocalPlayer
	local backpack = player:WaitForChild("Backpack")
	self:_watchContainer(backpack)
	local function onCharacter(character: Model)
		self:_watchContainer(character)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	table.insert(self.connections, player.CharacterAdded:Connect(onCharacter))
	local event = self.context.Controllers.NetworkController:ResolveEvent("PAVAEffect")
	if event then
		table.insert(
			self.connections,
			event.OnClientEvent:Connect(function(data)
				if data and data.Active then
					self.context.Controllers.NotificationController:Show(
						"Temporary eye irritation applied. Follow the roleplay effect prompt.",
						"PAVA"
					)
				end
			end)
		)
	end
end

function PAVAController:Destroy()
	for _, connection in self.connections or {} do
		connection:Disconnect()
	end
	table.clear(self.connections or {})
	self.watched = {}
	self.mouse = nil
end

return PAVAController
