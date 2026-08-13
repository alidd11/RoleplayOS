--!strict

-- Rotates the six avatar-based StreetDealer vendors through six map points.
--
-- The avatar models and map locations intentionally remain Studio-authored
-- content: a Roblox avatar is not reproducible from source files. This service
-- supplies the repeatable server-side wiring once those models are tagged.

local CollectionService = game:GetService("CollectionService")

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
