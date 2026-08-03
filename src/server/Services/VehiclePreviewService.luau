--!strict

-- Supplies vehicle preview models for dealership and depot interfaces.
--
-- Vehicle templates live in ServerStorage, so a client cannot see them and
-- cannot render a picture of one. Uploading a thumbnail per vehicle does not
-- scale to a fleet of hundreds and would drift from the real model, so instead
-- the server hands the client a stripped visual copy to draw in a ViewportFrame.
--
-- Copies are produced one at a time, on request, and parented into the
-- requesting player's PlayerGui, which Roblox replicates to that player alone.
-- The whole fleet is never replicated: doing so would cost every client the
-- memory and join time of every vehicle in the game.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local VehiclePreviewService = {}

local PREVIEW_FOLDER = "RoleplayOSVehiclePreviews"

-- Anything that runs, collides, makes noise or listens for input is stripped:
-- a preview is scenery, and a live script inside a client-visible model would
-- be both a performance cost and an attack surface.
local STRIPPED_CLASSES = {
	"Script",
	"LocalScript",
	"ModuleScript",
	"ProximityPrompt",
	"ClickDetector",
	"Sound",
	"ParticleEmitter",
	"Trail",
	"Beam",
	"Fire",
	"Smoke",
	"Explosion",
	"BodyVelocity",
	"VehicleSeat",
	"Seat",
}

function VehiclePreviewService:Init(context: any)
	self.context = context
	self.cache = {}
end

function VehiclePreviewService:Start() end

function VehiclePreviewService:_folder(player: Player): Folder?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local folder = playerGui:FindFirstChild(PREVIEW_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PREVIEW_FOLDER
		folder.Parent = playerGui
	end
	return folder :: Folder
end

function VehiclePreviewService:_strip(model: Model)
	for _, descendant in model:GetDescendants() do
		if table.find(STRIPPED_CLASSES, descendant.ClassName) then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

-- Returns a preview model parented into the player's own PlayerGui, or nil with
-- a reason. The caller renders it in a ViewportFrame; it is never parented to
-- workspace and never participates in physics.
function VehiclePreviewService:Request(player: Player, definitionId: any): (Model?, string?)
	if type(definitionId) ~= "string" then
		return nil, "INVALID_DEFINITION"
	end
	local definition = self.context.Configuration.Vehicles[definitionId]
	if not definition then
		return nil, "VEHICLE_NOT_FOUND"
	end
	local folder = self:_folder(player)
	if not folder then
		return nil, "PREVIEW_TARGET_UNAVAILABLE"
	end
	local existing = folder:FindFirstChild(definitionId)
	if existing and existing:IsA("Model") then
		return existing, nil
	end
	local template = self:_template(definition)
	if not template then
		-- Content, not code: the definition exists but its model has not been
		-- placed yet. The interface shows a placeholder card rather than an error.
		return nil, "VEHICLE_MODEL_UNAVAILABLE"
	end
	local preview = template:Clone()
	preview.Name = definitionId
	self:_strip(preview)
	local limit = self.context.Configuration.VehicleSpawning.MaximumPreviewsPerPlayer or 6
	self:_trim(folder, limit)
	preview.Parent = folder
	return preview, nil
end

-- Keeps only the most recent previews. Without this a player browsing a large
-- depot would accumulate every model they scrolled past.
function VehiclePreviewService:_trim(folder: Folder, limit: number)
	local children = folder:GetChildren()
	for index = 1, #children - math.max(1, limit) + 1 do
		local child = children[index]
		if child then
			child:Destroy()
		end
	end
end

function VehiclePreviewService:_template(definition: any): Model?
	local assets = ServerStorage:FindFirstChild("RoleplayOSAssets")
	local models = assets and assets:FindFirstChild("Vehicles")
	local template: Instance? = assets
	if type(definition.AssetPath) == "table" then
		for _, segment in definition.AssetPath do
			template = template and template:FindFirstChild(segment) or nil
		end
	else
		template = models and models:FindFirstChild(definition.ModelName)
	end
	if not template and models then
		template = models:FindFirstChild(definition.ModelName)
	end
	return if template and template:IsA("Model") then template else nil
end

function VehiclePreviewService:Release(player: Player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local folder = playerGui and playerGui:FindFirstChild(PREVIEW_FOLDER)
	if folder then
		folder:Destroy()
	end
end

function VehiclePreviewService:Destroy()
	for _, player in Players:GetPlayers() do
		self:Release(player)
	end
	table.clear(self.cache)
end

return VehiclePreviewService
