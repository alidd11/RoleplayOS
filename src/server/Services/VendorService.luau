--!strict

-- People standing around the map who sell things.
--
-- The economy could only ever drain before this existed, and then not even that:
-- wages went in, and the endpoints for spending money had no way to be reached,
-- so there was nothing to do with it. Vendors are where money leaves again.
--
-- A vendor is any tagged model with a RoleplayOSVendorId attribute naming a
-- definition in the configuration. Interaction is a ProximityPrompt, which
-- Roblox renders and drives itself on every input device, so the stall is
-- reachable on a phone without a single line of touch handling.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local VendorService = { connections = {}, prompts = {}, promptConnections = {} }

function VendorService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.Vendors
	self.openEvent = context.Network:RegisterEvent("VendorOpened")
end

function VendorService:_definition(vendorId: any): any?
	if type(vendorId) ~= "string" then
		return nil
	end
	return self.settings.Definitions[vendorId]
end

function VendorService:_anchor(model: Instance): BasePart?
	if not model:IsA("Model") then
		return if model:IsA("BasePart") then model else nil
	end
	local anchor = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChildWhichIsA("BasePart")
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

-- What the player is shown. Prices are resolved here rather than on the client,
-- so a stall cannot be made to display a price the server would not honour.
-- True while the player is in the uniform of a service that would not be
-- buying from this stall.
--
-- Teams carry the Emergency flag rather than this reading a hardcoded list,
-- because which services count is a game decision and belongs with the roster.
function VendorService:_isEmergency(player: Player): boolean
	local team = player.Team
	if not team then
		return false
	end
	local definition = self.context.Configuration.Teams[team.Name]
	return type(definition) == "table" and definition.Emergency == true
end

function VendorService:_catalogue(player: Player, definition: any): { any }
	local rows = {}
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local cache = session and session.Profile and session.Profile.GamepassCache or {}
	local emergency = self:_isEmergency(player)
	for _, item in definition.Items do
		-- Hidden rather than shown-and-refused. A row that cannot be bought reads
		-- as a broken stall, and an officer has no business being offered one.
		if item.EmergencyRestricted and emergency then
			continue
		end
		local price, owned = item.Price, nil
		if item.Kind == "Food" then
			local food = self.context.Configuration.Needs.Foods[item.FoodId]
			if not food then
				continue
			end
			price = food.Price
		elseif type(item.GamepassId) == "number" and item.GamepassId > 0 then
			owned = cache[tostring(item.GamepassId)] == true
			-- Owning the pass hands it over for nothing, so no price is shown even
			-- where one exists for everybody else.
			if owned then
				price = nil
			end
		end
		table.insert(rows, {
			Id = item.Id,
			Name = item.Name
				or (
					item.Kind == "Food"
						and self.context.Configuration.Needs.Foods[item.FoodId].Name
					or item.Id
				),
			Kind = item.Kind,
			Price = price,
			GamepassId = item.GamepassId,
			Owned = owned,
		})
	end
	return rows
end

function VendorService:_watch(model: Instance)
	if self.prompts[model] then
		return
	end
	local anchor = self:_anchor(model)
	local definition = self:_definition(model:GetAttribute("RoleplayOSVendorId"))
	if not anchor then
		self.context.Logger:Warning("Vendor has no part to attach a prompt to", {
			Vendor = model.Name,
		})
		return
	end
	if not definition then
		self.context.Logger:Warning("Vendor has no usable RoleplayOSVendorId attribute", {
			Vendor = model.Name,
			VendorId = tostring(model:GetAttribute("RoleplayOSVendorId")),
		})
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoleplayOSVendorPrompt"
	prompt.ObjectText = definition.Name
	prompt.ActionText = definition.Subtitle or "Browse"
	prompt.HoldDuration = self.settings.HoldSeconds
	prompt.MaxActivationDistance = self.settings.ActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.ClickablePrompt = true
	prompt.Parent = anchor
	self.prompts[model] = prompt
	-- Held against the model so removing the tag releases the connection with the
	-- prompt. Kept in the shared list it would accumulate for the life of the
	-- server as vendors stream in and out.
	self.promptConnections[model] = prompt.Triggered:Connect(function(player)
		self.openEvent:FireClient(player, {
			VendorId = model:GetAttribute("RoleplayOSVendorId"),
			Name = definition.Name,
			Subtitle = definition.Subtitle,
			Items = self:_catalogue(player, definition),
		})
	end)
end

function VendorService:_unwatch(model: Instance)
	local connection = self.promptConnections[model]
	if connection then
		connection:Disconnect()
		self.promptConnections[model] = nil
	end
	local prompt = self.prompts[model]
	if prompt then
		prompt:Destroy()
		self.prompts[model] = nil
	end
end

-- Distance is re-checked here because the client asked for this. Without it a
-- stall anywhere on the map could be bought from anywhere else on it.
function VendorService:_inRange(player: Player, vendorId: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	for model in self.prompts do
		if model:GetAttribute("RoleplayOSVendorId") == vendorId then
			local anchor = self:_anchor(model)
			if
				anchor
				and (anchor.Position - root.Position).Magnitude
					<= self.settings.MaximumPurchaseDistance
			then
				return true
			end
		end
	end
	return false
end

function VendorService:Purchase(player: Player, payload: any): (any?, string?)
	if type(payload) ~= "table" then
		return nil, "INVALID_REQUEST"
	end
	local definition = self:_definition(payload.VendorId)
	if not definition then
		return nil, "VENDOR_NOT_FOUND"
	end
	if not self:_inRange(player, payload.VendorId) then
		return nil, "VENDOR_OUT_OF_RANGE"
	end
	local item = nil
	for _, candidate in definition.Items do
		if candidate.Id == payload.ItemId then
			item = candidate
			break
		end
	end
	if not item then
		return nil, "ITEM_NOT_FOUND"
	end
	-- Rechecked here because the catalogue only decides what is drawn, and the
	-- request names the item directly.
	if item.EmergencyRestricted and self:_isEmergency(player) then
		return nil, "EMERGENCY_SERVICE_RESTRICTED"
	end

	if item.Kind == "Food" then
		local result, reason =
			self.context.Services:Get("NeedsService"):PurchaseFood(player, item.FoodId)
		if not result then
			return nil, reason
		end
		return { Kind = "Food", Hunger = result.Hunger }, nil
	end

	local loadouts = self.context.Services:Get("LoadoutService")

	-- An item may carry a pass, a price, or both, and the three cases are all
	-- ordinary. Owning the pass is the cheapest way to have it, so that is checked
	-- first and hands the item over without charging.
	if type(item.GamepassId) == "number" and item.GamepassId > 0 then
		-- Checked live rather than from the cache. The cache is written once and
		-- never revisited, so a refunded or revoked pass would go on handing out a
		-- weapon for nothing. A failed check falls back to what was cached, since
		-- a Roblox outage should not take away something already paid for.
		local owned = self.context.Services
			:Get("GamepassService")
			:Refresh(player, { GamepassId = item.GamepassId })
		local session = self.context.Services:Get("DataService"):GetSession(player)
		local cache = session and session.Profile and session.Profile.GamepassCache or {}
		if owned == true or cache[tostring(item.GamepassId)] == true then
			local given, giveReason = loadouts:GiveTool(player, item.ToolId, "Vendor")
			if not given then
				return nil, giveReason
			end
			return { Kind = "Tool", ToolId = item.ToolId, Paid = false }, nil
		end
		-- No pass and no cash price means the pass is the only way to have it, so
		-- the purchase is offered rather than refused: a bare refusal reads as the
		-- stall being broken.
		if not item.Price then
			return { Kind = "Gamepass", GamepassId = item.GamepassId, Owned = false }, nil
		end
	end

	-- Charged first, then handed over, and refunded if the asset turns out to be
	-- missing. Handing over first would let a failed payment still arm someone.
	local paid, payReason = self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = self:_characterId(player),
		Amount = item.Price,
		Direction = "Debit",
		ReasonCode = "Vendor.Purchase",
		RelatedEntityId = item.Id,
	})
	if not paid then
		return nil, payReason
	end
	local given, giveReason = loadouts:GiveTool(player, item.ToolId, "Vendor")
	if not given then
		self.context.Services:Get("EconomyService"):Apply(player, {
			TransactionId = HttpService:GenerateGUID(false),
			CharacterId = self:_characterId(player),
			Amount = item.Price,
			Direction = "Credit",
			ReasonCode = "Vendor.Refund",
			RelatedEntityId = item.Id,
		})
		return nil, giveReason
	end
	return { Kind = "Tool", ToolId = item.ToolId }, nil
end

function VendorService:_characterId(player: Player): string?
	local session = self.context.Services:Get("DataService"):GetSession(player)
	return session and session.ActiveCharacterId
end

function VendorService:Start()
	local tag = self.settings.Tag
	for _, model in CollectionService:GetTagged(tag) do
		self:_watch(model)
	end
	table.insert(
		self.connections,
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
			self:_watch(model)
		end)
	)
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
			self:_unwatch(model)
		end)
	)
end

function VendorService:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for model in self.prompts do
		self:_unwatch(model)
	end
	table.clear(self.prompts)
end

return VendorService
