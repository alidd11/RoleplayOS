--!strict
local FeatureController = {}
function FeatureController.new(name: string)
	local controller = { Name = name, ViewModel = {}, Enabled = true }
	function controller:Init(context: any)
		self.Context = context
	end
	function controller:Start() end
	function controller:SetViewModel(value: any)
		self.ViewModel = value
	end
	function controller:Destroy()
		self.Enabled = false
	end
	return controller
end
return FeatureController
