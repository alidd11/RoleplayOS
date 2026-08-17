--!strict
local ServerStorage = game:GetService("ServerStorage")
local ToolFactory = require(script.Parent.Parent.Systems.ToolFactory)
local LoadoutService = {}
local function resolve(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for index = 1, #path do
		current = current and current:FindFirstChild(path[index]) or nil
	end
	return current
end

function LoadoutService:Init(context: any)
	self.context = context
end
function LoadoutService:Start() end

function LoadoutService:_toolDefinition(toolId: string): any?
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetToolDefinition then
		return validator:GetToolDefinition(toolId)
	end
	return self.context.Configuration.Tools[toolId]
end

function LoadoutService:_toolIds(loadoutId: string, definition: any): { string }
	local configured = definition.ToolIds or definition.ToolNames or {}
	local validator = self.context.Services:Get("ContentValidationService")
	if validator and validator.GetLoadoutToolIds then
		return validator:GetLoadoutToolIds(loadoutId, configured)
	end
	return table.clone(configured)
end
local function canonicalizeTool(tool: Tool, toolId: string)
	if tool.Name ~= toolId then
		if tool:GetAttribute("RoleplayOSAssetName") == nil then
			tool:SetAttribute("RoleplayOSAssetName", tool.Name)
		end
		tool.Name = toolId
	end
	tool:SetAttribute("RoleplayOSToolId", toolId)
end

local function issue(tool: Tool, backpack: Instance, loadoutId: string, toolId: string)
	canonicalizeTool(tool, toolId)
	tool:SetAttribute("RoleplayOSDutyIssued", true)
	tool:SetAttribute("RoleplayOSLoadoutId", loadoutId)
	tool:SetAttribute("RoleplayOSToolId", toolId)
	tool.Parent = backpack
end

local function prepareVisibleTool(tool: Tool, toolId: string, definition: any?)
	local isWeapon = toolId == "Knife" or toolId == "Machete" or toolId == "ZKnife"
	if toolId ~= "Handcuffs" and toolId ~= "PAVA" and not isWeapon then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		handle = tool:FindFirstChildWhichIsA("BasePart", true)
	end
	if not handle then
		local created = Instance.new("Part")
		created.Name = "Handle"
		created.Size = Vector3.new(0.2, 0.2, 0.2)
		created.Transparency = 1
		created.Parent = tool
		handle = created
	end
	-- PAVA's authored visual is the Spray part. The source package used a
	-- transparent placeholder, which made the issued tool appear empty even
	-- though its server interaction worked. Keep the handle hidden, but make
	-- the reviewed body visible when it is issued.
	if toolId == "PAVA" then
		local spray = tool:FindFirstChild("Spray", true)
		if spray and spray:IsA("BasePart") then
			spray.Transparency = 0
		end
	end
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- How the tool sits in the hand.
	--
	-- A model carries whatever grip it was exported with, which is a property of
	-- whoever assembled it rather than of how the thing should be held, so the
	-- grip is named in configuration where one is known. That has to be decided
	-- here rather than by an earlier caller: this function is where every
	-- issuance path converges, and setting the grip before this point only to
	-- have the defaults below overwrite it is how the configured knife grips
	-- came to have no effect at all.
	--
	-- Below is the fallback for a tool configuration says nothing about. The
	-- authored model is left intact either way; only its Tool grip is set.
	if definition and typeof(definition.Grip) == "CFrame" then
		tool.Grip = definition.Grip
	else
		-- The angled hold, which reads as forward-facing once the equip pose
		-- raises the arm. Anything whose model needs something other than this
		-- says so in configuration; there is deliberately no second table of
		-- per-tool grips here for that to disagree with.
		tool.Grip = CFrame.new(0, -0.08, -0.72)
			* CFrame.Angles(math.rad(82), math.rad(4), math.rad(90))
	end
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= handle and not descendant:FindFirstChild("RoleplayOSHeldToolWeld") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "RoleplayOSHeldToolWeld"
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
end

-- Imported presentation objects are intentionally retained. The asset
-- validator removes executable third-party content at the template boundary,
-- while Animation, ParticleEmitter, MeshPart and Sound instances remain
-- available to the reviewed RoleplayOS controllers and the asset's own
-- published ownership permissions.

-- Loadouts overlap: several police loadouts issue handcuffs, and applying one
-- again on respawn would issue a second set. An officer should carry one of
-- each, so a tool already held is not issued again. The equipped tool lives on
-- the character rather than in the backpack, so both are checked.
local function alreadyIssued(player: Player, toolId: string): boolean
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("RoleplayOSToolId") == toolId then
					return true
				end
			end
		end
	end
	return false
end

function LoadoutService:Apply(player: Player, loadoutId: string): (boolean, string?)
	local definition = self.context.Configuration.Loadouts[loadoutId]
	if not definition then
		return false, "LOADOUT_NOT_FOUND"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "BACKPACK_UNAVAILABLE"
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local tools = if assets then assets:FindFirstChild("Tools") else nil
	if not tools then
		self.context.Logger:Warning("Loadout assets are unavailable", { LoadoutId = loadoutId })
		return true, nil
	end
	for _, toolId in self:_toolIds(loadoutId, definition) do
		if alreadyIssued(player, toolId) then
			continue
		end
		local toolDefinition = self:_toolDefinition(toolId)
		local template = if toolDefinition and type(toolDefinition.AssetPath) == "table"
			then resolve(assets, toolDefinition.AssetPath)
			else tools:FindFirstChild(toolId)
		if toolId == "MDT" and not template then
			issue(ToolFactory.mdt(), backpack, loadoutId, toolId)
		elseif toolId == "Radio" and not template then
			issue(ToolFactory.radio(), backpack, loadoutId, toolId)
		elseif toolId == "Handcuffs" and not template then
			issue(ToolFactory.handcuffs(), backpack, loadoutId, toolId)
		elseif toolId == "MedicalBag" and not template then
			issue(ToolFactory.medicalBag(), backpack, loadoutId, toolId)
		elseif not template and toolDefinition and toolDefinition.Weapon then
			local fallback = ToolFactory.weapon(toolId)
			prepareVisibleTool(fallback, toolId, toolDefinition)
			fallback.CanBeDropped = false
			issue(fallback, backpack, loadoutId, toolId)
		elseif template and template:IsA("Tool") then
			local clone = template:Clone()
			canonicalizeTool(clone, toolId)
			prepareVisibleTool(clone, toolId, toolDefinition)
			clone.CanBeDropped = false
			issue(clone, backpack, loadoutId, toolId)
		else
			self.context.Logger:Warning(
				"Loadout tool is unavailable",
				{ LoadoutId = loadoutId, Tool = toolId }
			)
		end
	end
	return true, nil
end
-- Puts one tool in a player's backpack, by the same asset rules the loadouts
-- use. Returns false when the asset is missing, so a caller that has taken
-- payment can refund rather than charging for nothing.
--
-- Not marked as duty issued: this is for things the player owns, and clearing a
-- shift destroys duty items.
function LoadoutService:GiveTool(
	player: Player,
	toolId: string,
	source: string?
): (boolean, string?)
	if alreadyIssued(player, toolId) then
		return false, "ALREADY_HELD"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "BACKPACK_UNAVAILABLE"
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local tools = if assets then assets:FindFirstChild("Tools") else nil
	if not tools then
		return false, "TOOL_UNAVAILABLE"
	end
	local toolDefinition = self:_toolDefinition(toolId)
	local template = if toolDefinition and type(toolDefinition.AssetPath) == "table"
		then resolve(assets, toolDefinition.AssetPath)
		else tools:FindFirstChild(toolId)
	if not template and toolDefinition and toolDefinition.Weapon then
		local fallback = ToolFactory.weapon(toolId)
		fallback:SetAttribute("RoleplayOSToolId", toolId)
		fallback:SetAttribute("RoleplayOSWeaponId", toolId)
		fallback:SetAttribute("RoleplayOSWeaponPurchase", source == "Vendor")
		prepareVisibleTool(fallback, toolId, toolDefinition)
		if source then
			fallback:SetAttribute("RoleplayOSToolSource", source)
		end
		fallback.Parent = backpack
		return true, nil
	end
	if not template or not template:IsA("Tool") then
		self.context.Logger:Warning(
			"Tool asset is unavailable",
			{ Tool = toolId, Source = source, UserId = player.UserId }
		)
		return false, "TOOL_UNAVAILABLE"
	end
	local clone = template:Clone()
	canonicalizeTool(clone, toolId)
	if toolDefinition and toolDefinition.Weapon then
		clone:SetAttribute("RoleplayOSWeaponId", toolId)
		clone:SetAttribute("RoleplayOSWeaponPurchase", source == "Vendor")
	end
	prepareVisibleTool(clone, toolId, toolDefinition)
	if source then
		clone:SetAttribute("RoleplayOSToolSource", source)
	end
	clone.Parent = backpack
	return true, nil
end

-- Issues the items a player has bought a gamepass for.
--
-- EquipmentPasses maps a gamepass to the tools it unlocks, and nothing read it,
-- so the four civilian weapon passes took Robux and granted nothing: ownership
-- was checked and cached, and then never used to give anybody anything.
--
-- These are not duty issued. Marking them so would have ClearIssued destroy them
-- when a shift ends, taking away something the player owns rather than something
-- the job lent them.
function LoadoutService:ApplyEquipmentPasses(player: Player): (boolean, string?)
	local passes = self.context.Configuration.EquipmentPasses
	if type(passes) ~= "table" then
		return true, nil
	end
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local cache = session and session.Profile and session.Profile.GamepassCache
	if type(cache) ~= "table" then
		return false, "PROFILE_UNAVAILABLE"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "BACKPACK_UNAVAILABLE"
	end
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local tools = if assets then assets:FindFirstChild("Tools") else nil
	if not tools then
		return true, nil
	end
	for passId, definition in passes do
		if type(definition.GamepassId) ~= "number" or definition.GamepassId <= 0 then
			continue
		end
		if cache[tostring(definition.GamepassId)] ~= true then
			continue
		end
		-- A pass may be limited to one team, so a civilian weapon does not follow
		-- its owner onto a police shift.
		local team = player.Team
		if definition.TeamName and (not team or team.Name ~= definition.TeamName) then
			continue
		end
		for _, toolId in definition.ToolNames or {} do
			if alreadyIssued(player, toolId) then
				continue
			end
			local toolDefinition = self:_toolDefinition(toolId)
			local template = if toolDefinition
					and type(toolDefinition.AssetPath) == "table"
				then resolve(assets, toolDefinition.AssetPath)
				else tools:FindFirstChild(toolId)
			if not template and toolDefinition and toolDefinition.Weapon then
				-- Gamepass ownership must remain useful while an authored mesh is
				-- being reviewed. Issue the same server-created weapon used by the
				-- cash vendor, keeping purchase, damage and seizure behaviour intact.
				local fallback = ToolFactory.weapon(toolId)
				canonicalizeTool(fallback, toolId)
				fallback:SetAttribute("RoleplayOSWeaponId", toolId)
				fallback:SetAttribute("RoleplayOSWeaponPurchase", false)
				fallback:SetAttribute("RoleplayOSEquipmentPassId", passId)
				prepareVisibleTool(fallback, toolId, toolDefinition)
				fallback.Parent = backpack
			elseif template and template:IsA("Tool") then
				local clone = template:Clone()
				clone:SetAttribute("RoleplayOSToolId", toolId)
				if toolDefinition and toolDefinition.Weapon then
					clone:SetAttribute("RoleplayOSWeaponId", toolId)
					clone:SetAttribute("RoleplayOSWeaponPurchase", false)
				end
				clone:SetAttribute("RoleplayOSEquipmentPassId", passId)
				prepareVisibleTool(clone, toolId, toolDefinition)
				clone.Parent = backpack
			else
				self.context.Logger:Warning("Gamepass equipment is unavailable", {
					Pass = passId,
					Tool = toolId,
					UserId = player.UserId,
				})
			end
		end
	end
	return true, nil
end

function LoadoutService:ClearIssued(player: Player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("RoleplayOSDutyIssued") == true then
					child:Destroy()
				end
			end
		end
	end
end
function LoadoutService:Destroy() end
return LoadoutService
