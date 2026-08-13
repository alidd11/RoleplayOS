--!strict

-- Rotates the six avatar-based StreetDealer vendors through six map points.
--
-- The avatar models and map locations intentionally remain Studio-authored
-- content: a Roblox avatar is not reproducible from source files. This service
-- supplies the repeatable server-side wiring once those models are tagged.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DealerRotationService = {}

local function sortByAttribute(instances: { Instance }, attributeName: string): { Instance }
	table.sort(instances, function(left, right)
		local leftId = tostring(left:GetAttribute(attributeName) or left.Name)
		local rightId = tostring(right:GetAttribute(attributeName) or right.Name)
		return leftId < rightId
	end)
	return instances
end

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

function DealerRotationService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.DealerRotation
	self.lastRotation = nil
	self.connections = {}
end

function DealerRotationService:_generatedFolder(): Folder
	local name = self.settings.GeneratedFolderName
	local folder = workspace:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = workspace
	return created
end

function DealerRotationService:_fallbackAnchor(): CFrame
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and instance:GetAttribute("SpawnId") == "CityCivilian" then
			return instance.CFrame
		end
	end
	return CFrame.new(0, 3, 0)
end

function DealerRotationService:_createPoints()
	if #self:_points() > 0 then
		return
	end
	local folder = self:_generatedFolder()
	local anchor = self:_fallbackAnchor()
	for index, offset in self.settings.FallbackPointOffsets do
		local point = Instance.new("Part")
		point.Name = string.format("DealerPoint%d", index)
		point.Size = Vector3.new(2, 0.2, 2)
		point.Transparency = 1
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point.CFrame = anchor + offset
		point:SetAttribute("RoleplayOSDealerPointId", string.format("DealerPoint%d", index))
		point.Parent = folder
		CollectionService:AddTag(point, self.settings.PointTag)
	end
end

function DealerRotationService:_prepareAvatar(model: Model, index: number)
	model.Name = string.format("Dealer%d", index)
	model:SetAttribute("RoleplayOSDealerId", string.format("Dealer%d", index))
	model:SetAttribute("RoleplayOSDealerOwnerUserId", self.settings.AvatarUserId)
	model:SetAttribute("RoleplayOSVendorId", self.settings.VendorId)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end
	if not CollectionService:HasTag(model, self.settings.DealerTag) then
		CollectionService:AddTag(model, self.settings.DealerTag)
	end
end

function DealerRotationService:_createAvatars()
	if #self:_dealers() > 0 then
		return
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(self.settings.AvatarUserId)
	end)
	if not ok or not description then
		self.context.Logger:Error("Dealer avatar could not be loaded", {
			UserId = self.settings.AvatarUserId,
			Error = tostring(description),
		})
		return
	end
	local folder = self:_generatedFolder()
	for index = 1, self.settings.ExpectedDealerCount do
		local created, model = pcall(function()
			return Players:CreateHumanoidModelFromDescriptionAsync(
				description,
				Enum.HumanoidRigType.R15
			)
		end)
		if not created or not model or not model:IsA("Model") then
			self.context.Logger:Error("Dealer avatar copy could not be created", {
				Index = index,
				Error = tostring(model),
			})
			continue
		end
		model.Parent = folder
		self:_prepareAvatar(model, index)
	end
end

function DealerRotationService:_dealers(): { Instance }
	return sortByAttribute(
		CollectionService:GetTagged(self.settings.DealerTag),
		"RoleplayOSDealerId"
	)
end

function DealerRotationService:_points(): { Instance }
	return sortByAttribute(
		CollectionService:GetTagged(self.settings.PointTag),
		"RoleplayOSDealerPointId"
	)
end

function DealerRotationService:_rotate(rotationIndex: number)
	local dealers = self:_dealers()
	local points = self:_points()
	if #dealers == 0 or #points == 0 then
		self.context.Logger:Warning("Dealer rotation is waiting for tagged avatars and points", {
			Dealers = #dealers,
			Points = #points,
			ExpectedDealers = self.settings.ExpectedDealerCount,
			ExpectedPoints = self.settings.ExpectedPointCount,
		})
		return
	end
	if
		#dealers ~= self.settings.ExpectedDealerCount
		or #points ~= self.settings.ExpectedPointCount
	then
		self.context.Logger:Warning("Dealer rotation count does not match configuration", {
			Dealers = #dealers,
			Points = #points,
			ExpectedDealers = self.settings.ExpectedDealerCount,
			ExpectedPoints = self.settings.ExpectedPointCount,
		})
	end

	for dealerIndex, dealer in dealers do
		if dealer:IsA("Model") then
			local point = points[((dealerIndex - 1 + rotationIndex) % #points) + 1]
			local target = pivotOf(point)
			if target then
				dealer:PivotTo(target)
			end
			dealer:SetAttribute("RoleplayOSVendorId", self.settings.VendorId)
			if not CollectionService:HasTag(dealer, self.settings.VendorTag) then
				CollectionService:AddTag(dealer, self.settings.VendorTag)
			end
			dealer:SetAttribute("RoleplayOSDealerRotation", rotationIndex)
		end
	end
	self.context.Logger:Info("StreetDealer locations rotated", {
		Rotation = rotationIndex,
		Dealers = #dealers,
		Points = #points,
	})
end

function DealerRotationService:Start()
	if not self.settings.Enabled then
		return
	end
	if self.settings.AutoCreate then
		self:_createPoints()
		self:_createAvatars()
	end
	local period = math.max(60, self.settings.RotationPeriodSeconds)
	task.spawn(function()
		while true do
			local rotationIndex = math.floor(os.time() / period)
			if rotationIndex ~= self.lastRotation then
				self.lastRotation = rotationIndex
				self:_rotate(rotationIndex)
			end
			task.wait(60)
		end
	end)
	self.connections[#self.connections + 1] = CollectionService
		:GetInstanceAddedSignal(self.settings.DealerTag)
		:Connect(function()
			self.lastRotation = nil
		end)
	self.connections[#self.connections + 1] = CollectionService
		:GetInstanceAddedSignal(self.settings.PointTag)
		:Connect(function()
			self.lastRotation = nil
		end)
end

function DealerRotationService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

return DealerRotationService
