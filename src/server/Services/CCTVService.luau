--!strict

local CollectionService = game:GetService("CollectionService")
local CCTVService = { cameras = {}, cameraCount = 0 }

function CCTVService:Init(context: any)
	self.context = context
	self.cameras = {}
	self.cameraCount = 0
end

function CCTVService:_maximumCameras(): number
	return math.max(0, math.floor(tonumber(self.context.Configuration.CCTV.MaximumCameras) or 64))
end

function CCTVService:_register(instance: Instance): boolean
	if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then
		return false
	end
	local id = instance:GetAttribute("CameraId")
	if type(id) ~= "string" or id == "" then
		id = instance.Name
	end
	local existing = self.cameras[id]
	if existing == instance then
		return true
	end
	if existing and existing:IsDescendantOf(workspace) then
		return false
	end
	if existing == nil then
		if self.cameraCount >= self:_maximumCameras() then
			return false
		end
		self.cameraCount += 1
	end
	self.cameras[id] = instance
	return true
end

function CCTVService:_unregister(instance: Instance): boolean
	for id, stored in self.cameras do
		if stored == instance then
			self.cameras[id] = nil
			self.cameraCount = math.max(0, self.cameraCount - 1)
			return true
		end
	end
	return false
end

function CCTVService:_fillCapacity()
	if self.cameraCount >= self:_maximumCameras() then
		return
	end
	for _, camera in CollectionService:GetTagged(self.context.Configuration.CCTV.CameraTag) do
		if self.cameraCount >= self:_maximumCameras() then
			break
		end
		self:_register(camera)
	end
end

function CCTVService:CanView(player: Player): boolean
	local duty = self.context.Services:Get("DutyService"):Get(player)
	return duty ~= nil
		and table.find(self.context.Configuration.CCTV.ViewerDepartments, duty.DepartmentId)
			~= nil
end

function CCTVService:Snapshot(player: Player): (any?, string?)
	if not self:CanView(player) then
		return nil, "CCTV_NOT_AUTHORISED"
	end
	local result = {}
	for id, camera in self.cameras do
		if camera.Parent and #result < self.context.Configuration.CCTV.MaximumCameras then
			local position = camera.Position
			local look = position + camera.CFrame.LookVector * 80
			table.insert(result, {
				CameraId = id,
				Name = camera:GetAttribute("DisplayName") or id,
				Position = { position.X, position.Y, position.Z },
				LookAt = { look.X, look.Y, look.Z },
			})
		end
	end
	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result, nil
end

function CCTVService:Start()
	self:_fillCapacity()
	self.added = CollectionService:GetInstanceAddedSignal(self.context.Configuration.CCTV.CameraTag)
		:Connect(function(camera)
			self:_register(camera)
		end)
	self.removed = CollectionService
		:GetInstanceRemovedSignal(self.context.Configuration.CCTV.CameraTag)
		:Connect(function(camera)
			if self:_unregister(camera) then
				self:_fillCapacity()
			end
		end)
end

function CCTVService:Destroy()
	if self.added then
		self.added:Disconnect()
	end
	if self.removed then
		self.removed:Disconnect()
	end
	table.clear(self.cameras)
	self.cameraCount = 0
end

return CCTVService
