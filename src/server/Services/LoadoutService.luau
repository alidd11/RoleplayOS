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

-- The bundled battering ram's Handle ships Anchored -- live-confirmed on the
-- issued clone, not merely suspected. Equipping welds the character's hand to
-- Handle through Roblox's own grip system; an anchored part cannot be moved
-- by that weld, so the solver drags the character to Handle's fixed position
-- instead, reported live as equipping the tool teleporting the character
-- elsewhere on the map and holding it there until the tool comes back off.
-- None of the tool's own scripts ever unanchor Handle itself -- the "Welding"
-- script welds every other part in the model *to* Handle and unanchors those,
-- but Handle is never a target of its own Weld, so nothing in the kit ever
-- clears the flag that was authored on it.
--
-- The tool also carries two separate arm-rigging scripts, WeldArm and
-- WeldArms, both firing on Tool.Equipped with the same intent -- weld Left
-- and Right Arm to Torso -- but with each arm's offset swapped between the
-- two, which would double-weld each arm to two contradictory targets at
-- once. Confirmed harmless on this fleet's R15 rig, since both scripts only
-- know the R6 part names ("Torso", "Left Arm", "Right Arm") and silently
-- find nothing to weld -- but silencing the duplicate now costs nothing and
-- removes a real conflict waiting for whatever R6 gets added next. WeldArm is
-- kept: it clears the native Left/Right Shoulder joints before adding its
-- replacement Welds, where WeldArms adds its Weld on top of the still-live
-- native shoulder motors.
local function patchBatteringRam(tool: Tool, toolId: string)
	if toolId ~= "Battering Ram" then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		handle.Anchored = false
	end
	local duplicate = tool:FindFirstChild("WeldArms")
	if duplicate and duplicate:IsA("BaseScript") then
		duplicate.Disabled = true
	end
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
	-- PAVA used to be issued as a stand-in whose only visible part was a box
	-- called Spray, so this revealed it to stop the tool appearing empty. On the
	-- purchased canister that name belongs to the nozzle rather than the body -
	-- a fifth of a stud, deliberately invisible, holding the plume emitter - and
	-- revealing it put a small cube in front of the spray head of an asset that
	-- already has geometry of its own. Whatever a package chooses to show is now
	-- left as its author set it.
	handle.Name = "Handle"
	-- Authored size is whoever modelled it's business, and it is not always a
	-- size a person could hold. The cuffs arrive two studs long against a five
	-- stud character, which is a scaffolding pole. Scaling here rather than in
	-- the model means the authored asset is untouched and the number is visible
	-- next to the grip it was chosen with.
	if definition and type(definition.Scale) == "number" and definition.Scale ~= 1 then
		local scaler = Instance.new("Model")
		local moved = {}
		for _, descendant in tool:GetDescendants() do
			if descendant:IsA("BasePart") then
				moved[descendant] = descendant.Parent
				descendant.Parent = scaler
			end
		end
		scaler.PrimaryPart = handle
		scaler:ScaleTo(definition.Scale)
		for descendant, parent in moved do
			descendant.Parent = parent
		end
		scaler:Destroy()
	end
	-- Animations the configuration names for this tool.
	--
	-- The clients look for an Animation instance inside the tool - Swing for a
	-- blade, Idle for a held pose - and fall back to procedural motion when they
	-- find none. Nine animations were published under the group in May 2025 and
	-- not one was ever referenced, because referencing them meant opening each
	-- .rbxm, adding an instance and re-exporting. Attaching them at issue instead
	-- means an animation is one line of configuration and the authored asset is
	-- never touched, which is the same reasoning as Grip and Scale above.
	if definition and type(definition.Animations) == "table" then
		for role, assetId in definition.Animations do
			if type(role) == "string" and type(assetId) == "number" and assetId > 0 then
				-- Replaced rather than added to, so re-issuing a tool cannot stack
				-- duplicates that LoadAnimation would then pick between at random.
				local existing = tool:FindFirstChild(role)
				if existing and existing:IsA("Animation") then
					existing:Destroy()
				end
				local animation = Instance.new("Animation")
				animation.Name = role
				animation.AnimationId = "rbxassetid://" .. tostring(assetId)
				animation.Parent = tool
			end
		end
	end
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
			patchBatteringRam(clone, toolId)
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
