--!strict

local Utils = require(script.Parent.Utils)
local C = Utils.C
local corner = Utils.corner
local text = Utils.text
local button = Utils.button
local departmentUI = Utils.departmentUI

return function(MDTController)
	function MDTController:_renderTabs()
		-- Nothing to return to from the home screen itself, so the control only
		-- appears once the officer has opened a page.
		self.homeTab.Visible = self.recordType ~= "Home"
		-- Home and the map each replace the records surface rather than sharing it,
		-- so the search controls cannot be used against a page that has no search.
		local mapping = self.recordType == "Map"
		local home = self.recordType == "Home"
		local records = not mapping and not home
		self.input.Visible = records
		self.searchAction.Visible = records
		self.status.Visible = records
		self.results.Visible = records
		self.detail.Visible = records
		self.home.Visible = home
		self.map:SetVisible(mapping)
	end

	-- One home tile: a titled card describing what the page is for, so the terminal
	-- explains itself rather than relying on four unlabelled tabs.

	function MDTController:_homeTile(order: number, name: string, detail: string, page: string)
		local tile = button(self.home, "")
		tile.LayoutOrder = order
		tile.BackgroundColor3 = C.Raised
		corner(tile, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Color = C.Border
		stroke.Transparency = 0.4
		stroke.Parent = tile
		local title = text(tile, name, 16, true)
		title.Position = UDim2.fromOffset(16, 16)
		title.Size = UDim2.new(1, -32, 0, 24)
		local body = text(tile, detail, 11)
		body.Position = UDim2.fromOffset(16, 42)
		body.Size = UDim2.new(1, -32, 0, 40)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = C.Muted
		tile.Activated:Connect(function()
			self.recordType = page
			self:_renderTabs()
			if page == "Map" then
				self:RefreshMap()
			elseif page == "Incident" then
				self:_performSearch()
			end
		end)
	end

	function MDTController:_buildHome()
		for _, child in self.home:GetChildren() do
			if not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end
		for order, tile in departmentUI(self.departmentId).Tiles do
			self:_homeTile(order, tile[1], tile[2], tile[3])
		end
	end

	-- Pulls a fresh server snapshot. The map only ever renders what the server
	-- reports, so an unauthorised duty simply sees an empty picture.
	-- Mirrors the tablet's status clock. Local time, like the handset: the device
	-- belongs to the officer carrying it.

	function MDTController:_updateClock()
		if self.statusClock then
			self.statusClock.Text = os.date("%H:%M")
		end
	end

	function MDTController:RefreshMap()
		self:_updateClock()
		if self.recordType ~= "Map" then
			return
		end
		local response =
			self.context.Controllers.NetworkController:Request("GetDispatchSnapshot", {})
		self.map:Update(if response.Success then response.Data else nil)
	end
end
