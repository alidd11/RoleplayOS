--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ImportedSystemAdapterService = { Critical = false }

type WiringReport = {
	BankSource: boolean,
	BankMounted: boolean,
	BankInteraction: boolean,
	EpauletteSource: boolean,
}

local function blankReport(): WiringReport
	return {
		BankSource = false,
		BankMounted = false,
		BankInteraction = false,
		EpauletteSource = false,
	}
end

local EPAULETTE_FOLDER = "RoleplayOSIssuedEpaulettes"
-- Rank insignia boards, indexed by the police rank ladder in Config.
--
-- There is deliberately no entry for a constable. In the British services the
-- junior rank wears its shoulder number and takes rank insignia only further up
-- the ladder, which is the same distinction Config records as Numbered. The
-- placeholder that used to sit here was rbxassetid://0, and because it was also
-- the fallback for any rank without a board, every constable going on duty
-- asked Roblox for asset zero and got an invalid-asset error back for each
-- shoulder. A blank texture leaves the board bare and asks for nothing.
local RANK_TEXTURES = {
	[2] = "rbxassetid://6188309917",
	[3] = "rbxassetid://1312054043",
	[4] = "rbxassetid://6188309143",
	[5] = "rbxassetid://1312053836",
	[6] = "rbxassetid://6188313580",
	[7] = "rbxassetid://6189209049",
	[8] = "rbxassetid://6189212295",
	[9] = "rbxassetid://6189207777",
}

local function sourceRoot(): Instance?
	return ServerStorage:FindFirstChild("RoleplayOSImportedSources")
end

local function findFirstNamed(root: Instance?, names: { string }): Instance?
	if not root then
		return nil
	end
	for _, name in names do
		local child = root:FindFirstChild(name)
		if child then
			return child
		end
	end
	return nil
end

local function stripExecutableContent(root: Instance)
	for _, descendant in root:GetDescendants() do
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
end

local function mergeChildren(source: Instance?, destination: Instance, stripCode: boolean?)
	if not source then
		return
	end
	for _, child in source:GetChildren() do
		if not destination:FindFirstChild(child.Name) then
			local clone = child:Clone()
			if stripCode then
				stripExecutableContent(clone)
			end
			clone.Parent = destination
		end
	end
end

local function nearestPart(instance: Instance?): BasePart?
	local current = instance
	while current do
		if current:IsA("BasePart") then
			return current
		end
		current = current.Parent
	end
	return nil
end

function ImportedSystemAdapterService:Init(context: any)
	self.context = context
	self.report = blankReport()
end

function ImportedSystemAdapterService:_adoptStudioImports()
	local root = sourceRoot()
	if not root then
		return
	end
	local bank = findFirstNamed(workspace, {
		"Bank Robbery V2 | Version Beta+",
		"Bank Robbery V2 | Version Beta",
	})
	if bank then
		-- Scripts nested inside an installer model still execute in Workspace. Move
		-- the untouched source package to inert storage before cloning its children
		-- into the services named by the vendor's own instructions.
		bank.Parent = root
		self.bankPackage = bank
	end
	local epaulettes = workspace:FindFirstChild("UNGROUP")
	if epaulettes then
		-- Preserve the purchased source exactly, but stop its R6/group-12345 click
		-- giver from running against players. RoleplayOS reads its visual pieces from
		-- here and fits them through the authoritative duty pipeline instead.
		epaulettes.Parent = root
		self.epaulettePackage = epaulettes
	end
end

function ImportedSystemAdapterService:_installBank()
	-- These purchased scripts are retained exactly as supplied, but only mounted
	-- automatically in the development baseplate. Production places must receive
	-- an explicitly reviewed release build instead of inheriting an external file.
	if self.context.Configuration.Framework.Environment == "Production" then
		return
	end
	local source = sourceRoot()
	local package = self.bankPackage or (source and source:FindFirstChild("BankRobberySource"))
	if not package then
		self.context.Logger:Warning("Bank robbery source package is unavailable", {})
		return
	end
	self.report.BankSource = true
	local replicatedInstaller =
		package:FindFirstChild("Put me in  ReplicatedStorage and ungroup me")
	local workspaceInstaller = package:FindFirstChild("Put me in WorkSpace and ungroup me ")
	local serverInstaller = package:FindFirstChild("Put me in  ServerScriptService and ungroup me")
	if not replicatedInstaller or not workspaceInstaller or not serverInstaller then
		local mapped = source and source:FindFirstChild("BankRobberySource")
		if mapped and mapped ~= package then
			package = mapped
			replicatedInstaller =
				package:FindFirstChild("Put me in  ReplicatedStorage and ungroup me")
			workspaceInstaller = package:FindFirstChild("Put me in WorkSpace and ungroup me ")
			serverInstaller =
				package:FindFirstChild("Put me in  ServerScriptService and ungroup me")
		end
	end
	if not replicatedInstaller or not workspaceInstaller or not serverInstaller then
		self.context.Logger:Warning("Bank robbery package has incomplete installer folders", {
			ReplicatedStorage = replicatedInstaller ~= nil,
			Workspace = workspaceInstaller ~= nil,
			ServerScriptService = serverInstaller ~= nil,
		})
		return
	end
	mergeChildren(replicatedInstaller, ReplicatedStorage)
	mergeChildren(workspaceInstaller, workspace, true)
	-- Do not mount the vendor's executable server installer. The supplied
	-- package contains obfuscated third-party code that requires external assets
	-- and HTTP, while RoleplayOS owns the server-authoritative robbery flow in
	-- BankRobberyService. Keeping the package's server scripts inert prevents
	-- duplicate prompts, unauthorized requests and startup errors.
	self.report.BankMounted = true

	local bank = workspace:FindFirstChild("Bank Robbery System V2")
	if not bank then
		self.context.Logger:Warning("Bank robbery workspace model is unavailable", {})
		return
	end
	-- The package contains dozens of cash-pickup prompts. The vault's prompt is
	-- explicitly named Hack; binding the first descendant would incorrectly raise
	-- the alarm only when somebody touched the first bundle of notes returned by
	-- an arbitrary tree traversal.
	local hack = bank:FindFirstChild("Hack", true)
	local prompt = if hack and hack:IsA("ProximityPrompt") then hack else nil
	local target = nearestPart(prompt)
	if not target then
		target = bank:FindFirstChild("DetectorPart", true) :: BasePart?
		if target then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RoleplayOSBankRobberyPrompt"
			prompt.ActionText = "Begin robbery"
			prompt.ObjectText = "Security system"
			prompt.HoldDuration = 2
			prompt.RequiresLineOfSight = true
			prompt.Parent = target
		end
	end
	if target and prompt then
		target:SetAttribute("Location", "Portsmouth Bank")
		CollectionService:AddTag(target, self.context.Configuration.BankRobbery.Tag)
		self.report.BankInteraction = true
		self.context.Logger:Info("Bank robbery package connected", {
			Target = target:GetFullName(),
		})
	else
		self.context.Logger:Warning("Bank robbery package has no usable interaction point", {})
	end
end

function ImportedSystemAdapterService:_auditEpauletteSource()
	local source = sourceRoot()
	local package = self.epaulettePackage
		or (source and source:FindFirstChild("PoliceEpaulettesSource"))
	local display = if package
			and package:FindFirstChild("Arm1")
			and findFirstNamed(package, { "Arm2", "MArm2w", "Arm2w" })
		then package
		else package and package:FindFirstChild("PolEppauls", true)
	self.report.EpauletteSource = display ~= nil
	if not display then
		self.context.Logger:Warning("Police epaulette visual source is unavailable", {})
	end
	return display
end

function ImportedSystemAdapterService:ClearEpaulettes(player: Player)
	local character = player.Character
	local issued = character and character:FindFirstChild(EPAULETTE_FOLDER)
	if issued then
		issued:Destroy()
	end
end

local function setIdentity(part: BasePart, numberText: string, rankTexture: string)
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Text = numberText
		elseif descendant:IsA("Decal") then
			descendant.Texture = rankTexture
		end
	end
end

function ImportedSystemAdapterService:ApplyEpaulettes(
	player: Player,
	profile: any
): (boolean, string?)
	self:ClearEpaulettes(player)
	local character = player.Character
	if not character or type(profile) ~= "table" or profile.DepartmentId ~= "Police" then
		return false, "POLICE_DUTY_REQUIRED"
	end
	local display = self:_auditEpauletteSource()
	if not display then
		return false, "EPAULETTE_SOURCE_MISSING"
	end
	local number = self.context.Services:Get("ShoulderNumberService"):Resolve(player, profile)
	local numberText = if number
		then self.context.Services:Get("ShoulderNumberService"):Format(number)
		else "----"
	local rank = math.clamp(math.floor(tonumber(profile.Rank) or 1), 1, 9)
	local texture = RANK_TEXTURES[rank] or ""
	local issued = Instance.new("Folder")
	issued.Name = EPAULETTE_FOLDER
	issued.Parent = character
	local fitted = 0
	for _, specification in
		{
			{
				SourceNames = { "Arm1" },
				R15 = "LeftUpperArm",
				R6 = "Left Arm",
				Inward = 0.2,
				Facing = CFrame.Angles(0, math.rad(180), 0),
			},
			{
				SourceNames = { "Arm2", "MArm2w", "Arm2w" },
				R15 = "RightUpperArm",
				R6 = "Right Arm",
				Inward = -0.2,
				Facing = CFrame.Angles(0, math.rad(180), 0),
			},
		}
	do
		local armModel = findFirstNamed(display, specification.SourceNames)
		local reference = armModel and armModel:FindFirstChild("Middle")
		local target = character:FindFirstChild(specification.R15)
			or character:FindFirstChild(specification.R6)
		if
			not armModel
			or not reference
			or not reference:IsA("BasePart")
			or not target
			or not target:IsA("BasePart")
		then
			continue
		end
		for _, sourcePart in armModel:GetChildren() do
			if not sourcePart:IsA("BasePart") or sourcePart == reference then
				continue
			end
			local clone = sourcePart:Clone()
			clone.Anchored = false
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Massless = true
			local sourceOffset = reference.CFrame:ToObjectSpace(sourcePart.CFrame)
			local sourcePosition = sourceOffset.Position
			local sourceRotation = sourceOffset - sourcePosition
			-- The vendor model uses an invisible 2-stud R6 arm as its origin. An R15
			-- upper arm is shorter, so copying that transform placed the boards almost
			-- half a stud above and outside the real shoulder. Rebase them onto the
			-- target arm's actual top surface, scale the small assembly slightly and
			-- pull each side toward the collar.
			local visualScale = if target.Name == specification.R15 then 0.82 else 1
			clone.Size = clone.Size * visualScale
			local shoulderTop = CFrame.new(
				specification.Inward,
				target.Size.Y * 0.5 - reference.Size.Y * 0.5 * visualScale + 0.025,
				0
			)
			-- Rotate the vendor assembly around the shoulder origin, including every
			-- piece's position. Rotating each piece around its own centre left the
			-- number board looking unchanged and could separate its trim.
			clone.CFrame = target.CFrame
				* shoulderTop
				* specification.Facing
				* CFrame.new(sourcePosition * visualScale)
				* sourceRotation
			setIdentity(clone, numberText, texture)
			clone.Parent = issued
			local weld = Instance.new("WeldConstraint")
			weld.Name = "RoleplayOSEpauletteWeld"
			weld.Part0 = target
			weld.Part1 = clone
			weld.Parent = clone
			fitted += 1
		end
	end
	if fitted == 0 then
		issued:Destroy()
		return false, "EPAULETTE_FIT_FAILED"
	end
	return true, nil
end

function ImportedSystemAdapterService:Start()
	self:_adoptStudioImports()
	self:_installBank()
	self:_auditEpauletteSource()
	self.context.Logger:Info("Imported asset wiring audit complete", self.report)
end

function ImportedSystemAdapterService:GetWiringReport(): WiringReport
	return table.clone(self.report)
end

function ImportedSystemAdapterService:Destroy()
	self.report = blankReport()
end

return ImportedSystemAdapterService
