--!strict

local Players = game:GetService("Players")
local IdentificationService = {}
function IdentificationService:Init(context: any)
	self.context = context
end

function IdentificationService:_give(player: Player)
	if not player.Team or player.Team.Name ~= "Civilian" then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild("ID Card") then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "ID Card"
	tool.ToolTip = "Present identification"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.8, 1.1, 0.08)
	handle.Color = Color3.fromRGB(226, 224, 211)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.Parent = handle
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 52, 78)
	label.Font = Enum.Font.GothamBold
	label.Text = "UK\nIDENTITY CARD"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = gui
	tool.Parent = backpack
end

function IdentificationService:Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				self:_give(player)
			end)
		end)
		player:GetPropertyChangedSignal("Team"):Connect(function()
			self:_give(player)
		end)
		if player.Character then
			self:_give(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function IdentificationService:Present(actor: Player, targetUserId: number): (any?, string?)
	if not actor.Team or actor.Team.Name ~= "Civilian" then
		return nil, "CIVILIAN_REQUIRED"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local ar = actor.Character and actor.Character:FindFirstChild("HumanoidRootPart")
	local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if
		not ar
		or not tr
		or (ar.Position - tr.Position).Magnitude
			> self.context.Configuration.Identification.MaximumPresentationDistance
	then
		return nil, "TARGET_OUT_OF_RANGE"
	end
	local session = self.context.Services:Get("DataService"):GetSession(actor)
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	if not character then
		return nil, "CHARACTER_UNAVAILABLE"
	end
	return {
		FullName = character.Identity.FirstName .. " " .. character.Identity.LastName,
		DateOfBirth = character.Identity.DateOfBirth,
		DocumentNumber = string.upper(
			string.sub(string.gsub(character.CharacterId, "%-", ""), 1, 12)
		),
		PresentedByUserId = actor.UserId,
	},
		nil
end

function IdentificationService:Destroy() end
return IdentificationService
