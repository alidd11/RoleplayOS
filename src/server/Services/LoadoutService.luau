--!strict
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ToolFactory = require(script.Parent.Parent.Systems.ToolFactory)
local LoadoutService = {}
local function resolve(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for index = 1, #path do
		current = current and current:FindFirstChild(path[index]) or nil
	end
	return current
end

local function importedHandcuffTool(source: Instance): Tool
	if source:IsA("Tool") then
		return source:Clone()
	end
	local nested = source:FindFirstChildWhichIsA("Tool", true)
	if nested then
		return nested:Clone()
	end
	-- Toolbox models are not always authored as Tools. Wrap the chosen visual
	-- around a safe invisible handle so it remains equipable without its scripts.
	local tool = Instance.new("Tool")
	tool.Name = "Handcuffs"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool
	local visual = source:Clone()
	visual.Name = "Visual"
	visual.Parent = tool
	local firstPart = visual:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		handle.CFrame = firstPart.CFrame
	end
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	return tool
end
function LoadoutService:Init(context: any)
	self.context = context
	local imported = Workspace:FindFirstChild("Quarantine_Handcuffs_11545634427")
	if imported then
		-- Adopt the user's chosen physical model, but never execute code or accept
		-- networking objects bundled with a third-party asset.
		for _, descendant in imported:GetDescendants() do
			if
				descendant:IsA("LuaSourceContainer")
				or descendant:IsA("RemoteEvent")
				or descendant:IsA("RemoteFunction")
				or descendant:IsA("BindableEvent")
				or descendant:IsA("BindableFunction")
			then
				descendant:Destroy()
			end
		end
		imported.Parent = ServerStorage
		self.importedHandcuffs = imported
	end
end
function LoadoutService:Start() end
local function issue(tool: Tool, backpack: Instance, loadoutId: string, toolId: string)
	tool:SetAttribute("RoleplayOSDutyIssued", true)
	tool:SetAttribute("RoleplayOSLoadoutId", loadoutId)
	tool:SetAttribute("RoleplayOSToolId", toolId)
	tool.Parent = backpack
end

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
	for _, toolId in definition.ToolIds or definition.ToolNames or {} do
		if alreadyIssued(player, toolId) then
			continue
		end
		local toolDefinition = self.context.Configuration.Tools[toolId]
		local template = if toolDefinition and type(toolDefinition.AssetPath) == "table"
			then resolve(assets, toolDefinition.AssetPath)
			else tools:FindFirstChild(toolId)
		if toolId == "Handcuffs" and self.importedHandcuffs then
			local importedTool = if self.importedHandcuffs:IsA("Tool")
				then self.importedHandcuffs
				else self.importedHandcuffs:FindFirstChildWhichIsA("Tool", true)
			if importedTool then
				template = importedTool
			end
		end
		if toolId == "MDT" and not template then
			issue(ToolFactory.mdt(), backpack, loadoutId, toolId)
		elseif toolId == "Handcuffs" and self.importedHandcuffs then
			local clone = importedHandcuffTool(self.importedHandcuffs)
			clone.Name = "Handcuffs"
			clone.CanBeDropped = false
			issue(clone, backpack, loadoutId, toolId)
		elseif toolId == "Handcuffs" and not template then
			issue(ToolFactory.handcuffs(), backpack, loadoutId, toolId)
		elseif template and template:IsA("Tool") then
			local clone = template:Clone()
			clone.Name = if toolId == "Handcuffs" then "Handcuffs" else clone.Name
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
	local toolDefinition = self.context.Configuration.Tools[toolId]
	local template = if toolDefinition and type(toolDefinition.AssetPath) == "table"
		then resolve(assets, toolDefinition.AssetPath)
		else tools:FindFirstChild(toolId)
	if not template or not template:IsA("Tool") then
		self.context.Logger:Warning(
			"Tool asset is unavailable",
			{ Tool = toolId, Source = source, UserId = player.UserId }
		)
		return false, "TOOL_UNAVAILABLE"
	end
	local clone = template:Clone()
	clone:SetAttribute("RoleplayOSToolId", toolId)
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
			local toolDefinition = self.context.Configuration.Tools[toolId]
			local template = if toolDefinition
					and type(toolDefinition.AssetPath) == "table"
				then resolve(assets, toolDefinition.AssetPath)
				else tools:FindFirstChild(toolId)
			if template and template:IsA("Tool") then
				local clone = template:Clone()
				clone:SetAttribute("RoleplayOSToolId", toolId)
				clone:SetAttribute("RoleplayOSEquipmentPassId", passId)
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
