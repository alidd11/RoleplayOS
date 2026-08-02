--!strict

local CollectionService = game:GetService("CollectionService")
local CCTVService = { cameras = {} }

function CCTVService:Init(context: any)
	self.context = context
end

function CCTVService:_register(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local id = instance:GetAttribute("CameraId")
	if type(id) ~= "string" or id == "" then
		id = instance.Name
	end
	self.cameras[id] = instance
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
	for _, camera in CollectionService:GetTagged(self.context.Configuration.CCTV.CameraTag) do
		self:_register(camera)
	end
	self.added = CollectionService:GetInstanceAddedSignal(self.context.Configuration.CCTV.CameraTag)
		:Connect(function(camera)
			self:_register(camera)
		end)
	self.removed = CollectionService
		:GetInstanceRemovedSignal(self.context.Configuration.CCTV.CameraTag)
		:Connect(function(camera)
			for id, stored in self.cameras do
				if stored == camera then
					self.cameras[id] = nil
				end
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
end

return CCTVService
