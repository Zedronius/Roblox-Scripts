local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DataService = require(script.Parent:WaitForChild("DataService"))
local TroopCatalog = require(ServerStorage:WaitForChild("TroopCatalog"))

local REMOTE_FOLDER_NAME = "Remotes"
local PLACEMENT_FOLDER_NAME = "Placement"
local MAX_PLACEMENTS_PER_PLAYER = 15
local UNIT_COLLISION_GROUP = "Units"
local remotes = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
local placementFolder = remotes:FindFirstChild(PLACEMENT_FOLDER_NAME)
local placeTroop = placementFolder:FindFirstChild("PlaceTroop")

local placeTroopRemote = placeTroop

local function collisionGroupExists(name)
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if group.name == name then
			return true
		end
	end
	return false
end

local function ensureCollisionGroup(name)
	if collisionGroupExists(name) then
		return
	end
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not ok then
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
end

local function configureUnitCollisions()
	ensureCollisionGroup(UNIT_COLLISION_GROUP)
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(UNIT_COLLISION_GROUP, UNIT_COLLISION_GROUP, false)
	end)
	if not ok then
		warn("[PlacementService] Failed to configure unit collision group:", err)
	end
end

configureUnitCollisions()

local function getRoundMoney(player)
	local value = player:GetAttribute("RoundMoney")
	return value
end

local function getPlacementCount(player)
	local value = player:GetAttribute("PlacementCount")
	if type(value) ~= "number" then
		value = 0
		player:SetAttribute("PlacementCount", value)
	end
	return value
end

local function setPlacementCount(player, value)
	player:SetAttribute("PlacementCount", value)
end

local function initPlayer(player)
	getPlacementCount(player)
end

Players.PlayerAdded:Connect(initPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end

local function normalizeArea(area)
	if type(area) ~= "string" then
		return "Ground"
	end
	local lower = string.lower(area)
	if lower == "hill" then
		return "Hill"
	end
	return "Ground"
end

local function getPlacementSurface(areaName)
	local placementFolder = Workspace:FindFirstChild("Placement")

	local surface = placementFolder:FindFirstChild(areaName)

	return surface
end

local function getSurfaceHit(position, surface)
	local rayOrigin = position + Vector3.new(0, 200, 0)
	local rayDirection = Vector3.new(0, -400, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { surface }
	rayParams.IgnoreWater = true
	return Workspace:Raycast(rayOrigin, rayDirection, rayParams)
end

local function getPlacementBounds(template, placementCFrame)
	local boxCFrame, boxSize = template:GetBoundingBox()
	local pivot = template:GetPivot()
	local relativeBox = pivot:ToObjectSpace(boxCFrame)
	return placementCFrame * relativeBox, boxSize
end

local function getModelBaseOffset(model)
	local boxCFrame, boxSize = model:GetBoundingBox()
	if not boxSize then
		return 0
	end
	local pivot = model:GetPivot()
	local relativeBox = pivot:ToObjectSpace(boxCFrame)
	local bottomLocalY = relativeBox.Position.Y - (boxSize.Y * 0.5)
	return -bottomLocalY
end

local function applyPlacementOffset(model, placementCFrame)
	local offsetY = getModelBaseOffset(model)
	if offsetY == 0 then
		return placementCFrame
	end
	return placementCFrame * CFrame.new(0, offsetY, 0)
end

local function hideNameplates(model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Humanoid") then
			desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			desc.NameDisplayDistance = 0
			desc.HealthDisplayDistance = 0
		end
	end
end

local function setModelCollidable(model, collidable)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = collidable
		end
	end
end

local function isOverlapping(placementCFrame, template)
	local placedFolder = Workspace:FindFirstChild("PlacedTroops")
	if not placedFolder then
		return false
	end
	local boxCFrame, boxSize = getPlacementBounds(template, placementCFrame)
	if not boxSize then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { placedFolder }
	params.MaxParts = 1
	local parts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)
	return #parts > 0
end

local function getPlacedFolder()
	local placed = Workspace:FindFirstChild("PlacedTroops")
	if not placed then
		placed = Instance.new("Folder")
		placed.Name = "PlacedTroops"
		placed.Parent = Workspace
	end
	return placed
end

local function getTemplate(troopId)
	local troopsFolder = ReplicatedStorage:FindFirstChild("Troops")
	if not troopsFolder then
		return nil, "Troops folder missing."
	end
	local template = troopsFolder:FindFirstChild(troopId)
	if not template or not template:IsA("Model") then
		return nil, "Troop model missing."
	end
	return template
end

placeTroopRemote.OnServerInvoke = function(player, troopId, targetCFrame)
	if type(troopId) ~= "string" then
		return false, "Invalid troop."
	end
	initPlayer(player)
	if not TroopCatalog.IsValid(troopId) then
		return false, "Unknown troop."
	end

	local profile = DataService.WaitForProfile(player, 10)
	if not profile then
		return false, "Profile not loaded."
	end

	local equipped = profile.Data.Inventory and profile.Data.Inventory.EquippedTroops or {}
	if table.find(equipped, troopId) == nil then
		return false, "Troop not equipped."
	end
	local def = TroopCatalog.Get(troopId)
	local areaName = normalizeArea(def and def.Stats and def.Stats.Area)
	local surface, surfaceErr = getPlacementSurface(areaName)
	if not surface then
		return false, surfaceErr
	end
	if getPlacementCount(player) >= MAX_PLACEMENTS_PER_PLAYER then
		return false, "Max placements reached."
	end

	local placementCFrame
	if typeof(targetCFrame) == "CFrame" then
		placementCFrame = targetCFrame
	elseif typeof(targetCFrame) == "Vector3" then
		placementCFrame = CFrame.new(targetCFrame)
	else
		return false, "Invalid placement."
	end

	local template, err = getTemplate(troopId)
	if not template then
		return false, err
	end

	local hit = getSurfaceHit(placementCFrame.Position, surface)
	if not hit then
		return false, "Invalid placement surface."
	end

	local cost = def and def.Stats and tonumber(def.Stats.PlacementCost) or 0
	local currentMoney = getRoundMoney(player)
	if currentMoney < cost then
		return false, "Not enough round money."
	end

	local rotationOnly = placementCFrame - placementCFrame.Position
	local placementAt = applyPlacementOffset(template, CFrame.new(hit.Position) * rotationOnly)
	if isOverlapping(placementAt, template) then
		return false, "Placement blocked."
	end

	local clone = template:Clone()
	clone.Parent = getPlacedFolder()
	clone:PivotTo(placementAt)
	setModelCollidable(clone, true)
	hideNameplates(clone)

	setPlacementCount(player, getPlacementCount(player) + 1)

	return true
end
