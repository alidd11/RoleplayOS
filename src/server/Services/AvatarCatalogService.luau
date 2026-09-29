--!strict

-- Catalogue browsing for the in-game character creator.
--
-- Roblox's own catalogue is the item source. This service is the only thing that
-- talks to it, for three reasons: the search runs against a shared quota that a
-- room full of players typing would exhaust in seconds, identical searches are
-- overwhelmingly common (everybody opens the creator on "hair" first), and the
-- results decide which asset ids the client is later allowed to ask for.
--
-- Nothing here trusts or blocks the client on its own. CharacterService still
-- sanitises whatever comes back from the editor, because a player can call the
-- write endpoint without ever calling this one.

local AvatarEditorService = game:GetService("AvatarEditorService")

local AvatarCatalogService = {
	-- A broken catalogue degrades the creator only. It must never stop the server
	-- starting, so this is deliberately not critical.
	Critical = false,
	running = false,
	cache = {},
	cacheOrder = {},
	searching = {},
}

-- What the creator can browse, and the HumanoidDescription field each fills.
--
-- Keyed by a plain string rather than the enum so the client can name a category
-- without being able to reach anything the enum happens to expose.
local CATEGORIES: { [string]: { AssetType: Enum.AvatarAssetType, Field: string } } = {
	Hair = { AssetType = Enum.AvatarAssetType.HairAccessory, Field = "HairAccessory" },
	Hat = { AssetType = Enum.AvatarAssetType.Hat, Field = "HatAccessory" },
	Face = { AssetType = Enum.AvatarAssetType.Face, Field = "Face" },
	FaceAccessory = { AssetType = Enum.AvatarAssetType.FaceAccessory, Field = "FaceAccessory" },
	Neck = { AssetType = Enum.AvatarAssetType.NeckAccessory, Field = "NeckAccessory" },
	Shoulder = { AssetType = Enum.AvatarAssetType.ShoulderAccessory, Field = "ShoulderAccessory" },
	Front = { AssetType = Enum.AvatarAssetType.FrontAccessory, Field = "FrontAccessory" },
	Back = { AssetType = Enum.AvatarAssetType.BackAccessory, Field = "BackAccessory" },
	Waist = { AssetType = Enum.AvatarAssetType.WaistAccessory, Field = "WaistAccessory" },
	Shirt = { AssetType = Enum.AvatarAssetType.Shirt, Field = "Shirt" },
	Trousers = { AssetType = Enum.AvatarAssetType.Pants, Field = "Pants" },
	TShirt = { AssetType = Enum.AvatarAssetType.TShirt, Field = "GraphicTShirt" },
}

local CACHE_SECONDS = 300
local CACHE_ENTRIES = 60
local MAXIMUM_RESULTS = 40

function AvatarCatalogService:Init(context: any)
	self.context = context
	self.running = false
	self.cache = {}
	self.cacheOrder = {}
	self.searching = {}
end

function AvatarCatalogService:Start()
	self.running = true
end

-- The categories the client is allowed to ask for, so the creator builds its
-- tabs from the server's list rather than from one hardcoded in the interface
-- that can drift out of step with it.
function AvatarCatalogService:Categories(): { any }
	local names = {}
	for name in CATEGORIES do
		table.insert(names, name)
	end
	table.sort(names)
	local result = {}
	for _, name in names do
		table.insert(result, { Id = name, Field = CATEGORIES[name].Field })
	end
	return result
end

-- Drops the oldest entries once the cache is full.
--
-- Bounded rather than cleared: a server that has been up for hours has a warm
-- cache of the searches people actually run, and throwing all of it away because
-- one new search arrived would send every one of them back to Roblox at once.
function AvatarCatalogService:_remember(key: string, payload: any)
	if self.cache[key] == nil then
		table.insert(self.cacheOrder, key)
	end
	self.cache[key] = { At = os.clock(), Payload = payload }
	while #self.cacheOrder > CACHE_ENTRIES do
		local oldest = table.remove(self.cacheOrder, 1)
		if oldest then
			self.cache[oldest] = nil
		end
	end
end

function AvatarCatalogService:_cached(key: string): any?
	local entry = self.cache[key]
	if not entry then
		return nil
	end
	if os.clock() - entry.At > CACHE_SECONDS then
		self.cache[key] = nil
		local index = table.find(self.cacheOrder, key)
		if index then
			table.remove(self.cacheOrder, index)
		end
		return nil
	end
	return entry.Payload
end

-- Searches one category, optionally filtered by keyword.
--
-- Returns a trimmed shape rather than the raw catalogue rows: the creator needs
-- an id to wear, a name to label it and nothing else, and the raw rows carry
-- pricing and creator metadata that would triple the payload for no benefit.
function AvatarCatalogService:Search(categoryId: any, keyword: any): (any?, string?)
	if not self.running then
		return nil, "CATALOGUE_UNAVAILABLE"
	end
	local category = type(categoryId) == "string" and CATEGORIES[categoryId]
	if not category then
		return nil, "UNKNOWN_CATEGORY"
	end
	local search = ""
	if type(keyword) == "string" then
		-- Trimmed and bounded. The keyword reaches an external service, so its
		-- length is not the client's to decide.
		search = string.sub(string.match(keyword, "^%s*(.-)%s*$") or "", 1, 60)
	end
	local key = categoryId .. "\0" .. string.lower(search)
	local cached = self:_cached(key)
	if cached then
		return cached, nil
	end

	-- Cache entries only exist after Roblox has answered. Without a single-flight
	-- claim, a room full of players opening the same uncached category together
	-- all miss the cache and spend the shared catalogue quota independently.
	-- Waiters stay below the RemoteFunction handler deadline, then either reuse
	-- the completed cache entry or fail without issuing another Roblox request.
	local existingSearch = self.searching[key]
	if existingSearch then
		local handlerTimeout = tonumber(self.context.Configuration.Network.HandlerTimeoutSeconds)
			or 8
		local deadline = os.clock() + math.max(0.1, handlerTimeout - 0.5)
		while self.running and self.searching[key] == existingSearch and os.clock() < deadline do
			task.wait(0.03)
		end
		if not self.running then
			return nil, "CATALOGUE_UNAVAILABLE"
		end
		local shared = self:_cached(key)
		if shared then
			return shared, nil
		end
		return nil, "CATALOGUE_UNAVAILABLE"
	end

	local searchToken = {}
	self.searching[key] = searchToken
	local searchOk, result, resultReason = pcall(function(): (any?, string?)
		local parameters = CatalogSearchParams.new()
		parameters.AssetTypes = { category.AssetType }
		if search ~= "" then
			parameters.SearchKeyword = search
		end

		local ok, pages = pcall(function()
			return AvatarEditorService:SearchCatalog(parameters)
		end)
		-- The catalogue call yields. Shutdown may clear the cache while it is in
		-- flight, so a late result must not recreate service state after Destroy.
		if not self.running then
			return nil, "CATALOGUE_UNAVAILABLE"
		end
		if not ok or not pages then
			-- Reported rather than raised. The catalogue being briefly unavailable is
			-- an ordinary outcome that the creator should show as an empty shelf, not
			-- an error that takes the menu down.
			self.context.Logger:Warning("Avatar catalogue search failed", {
				Category = categoryId,
				Error = tostring(pages),
			})
			return nil, "CATALOGUE_UNAVAILABLE"
		end

		local pageOk, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not self.running then
			return nil, "CATALOGUE_UNAVAILABLE"
		end
		if not pageOk or type(page) ~= "table" then
			return nil, "CATALOGUE_UNAVAILABLE"
		end

		local items = {}
		for _, entry in page do
			local id = tonumber(entry.Id)
			if id and id > 0 then
				table.insert(items, {
					Id = id,
					Name = if type(entry.Name) == "string" then entry.Name else "Item",
					Field = category.Field,
				})
			end
			if #items >= MAXIMUM_RESULTS then
				break
			end
		end

		local payload = { CategoryId = categoryId, Field = category.Field, Items = items }
		self:_remember(key, payload)
		return payload, nil
	end)

	if self.searching[key] == searchToken then
		self.searching[key] = nil
	end
	if not searchOk then
		error(result)
	end
	return result, resultReason
end

function AvatarCatalogService:Destroy()
	self.running = false
	table.clear(self.searching)
	table.clear(self.cache)
	table.clear(self.cacheOrder)
end

return AvatarCatalogService
