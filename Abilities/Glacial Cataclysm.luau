local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local WorkspaceService = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StunHandler = require(ServerStorage.Modules.StunHandler)
local DamageHandler = require(ServerStorage.Modules.DamageHandler)
local AnimationService = require(ServerStorage.Modules.AnimationService)
local iFramesService = require(ServerStorage.Modules.iFramesService)
local SoundsModule = require(ServerStorage.Modules.SoundsModule)
local HitboxHandler = require(ServerStorage.Modules.HitboxHandler)

local ReplicateEffects_Set = ReplicatedStorage.Remotes.Replicate.Set

local Assets = ServerStorage:FindFirstChild("Assets")
local Animations = Assets and Assets:FindFirstChild("Animations")
local Sounds = Assets and Assets:FindFirstChild("Sounds")
local Effects = Assets and Assets:FindFirstChild("Effects")

local MoveAnims = Animations and Animations:FindFirstChild("Moves")
local MoveSounds = Sounds and Sounds:FindFirstChild("Moves")

local WINDUP_DURATION = 2
local SNOW_SCALE = 0.9
local FIELD_LIFETIME = 4
local FIELD_SIZE = Vector3.new(26, 1.5, 26)
local HITBOX_HEIGHT = 6
local HITBOX_PULSES = 6
local HITBOX_INTERVAL = 0.08
local STUN_DURATION = 3
local DAMAGE_AMOUNT = 5
local RAY_DISTANCE = 60
local WALKSPEED_MULT = 0.35
local ICECUBE_Y_ROT = math.rad(90)
local DEFAULT_WALK_ATTR = "DefaultWalkSpeed"
local DEFAULT_RUN_ATTR = "DefaultRunSpeed"
local CASTER_BUFFER = 2

local function getMoveAsset(folder, moveName, childName)
	if not folder then return nil end
	local moveFolder = folder:FindFirstChild("Ice Wizard")
	local move = moveFolder:FindFirstChild(moveName)
	return move:FindFirstChild(childName)
end

local function getMoveAnim(moveName)
	return getMoveAsset(MoveAnims, moveName, "User")
end

local function getMoveSound(moveName, soundName)
	return getMoveAsset(MoveSounds, moveName, soundName or "Cast")
end

local function playSound(soundObject, origin)
	if soundObject and soundObject:IsA("Sound") then
		SoundsModule:PlaySound(soundObject, origin)
	end
end

local function getLocalAsset(name)
	return script:FindFirstChild(name)
end

local function getFieldTemplate(scriptRef)
	if scriptRef then
		local template = scriptRef:FindFirstChild("ice")
		if template and template:IsA("BasePart") then return template end
	end
end

local function buildDefaultField()
	local part = Instance.new("Part")
	part.Name = "GlacialSweepField"
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Ice
	part.Transparency = 0.35
	part.Color = Color3.fromRGB(160, 220, 255)
	part.Size = FIELD_SIZE
	part.Shape = Enum.PartType.Block
	return part
end

local function groundPointBelow(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	params.IgnoreWater = true
	local result = WorkspaceService:Raycast(position, Vector3.new(0, -RAY_DISTANCE, 0), params)
	return result and result.Position or (position - Vector3.new(0, 4, 0))
end

local function spawnSnowAt(position, fieldSize)
	local snowTemplate = getLocalAsset("Snow")
	if not snowTemplate or not snowTemplate:IsA("BasePart") then return nil end
	local snow = snowTemplate:Clone()
	snow.Anchored = true
	snow.CanCollide = false
	local referenceSize = fieldSize or FIELD_SIZE
	local targetXZ = Vector2.new(referenceSize.X * SNOW_SCALE, referenceSize.Z * SNOW_SCALE)
	snow.Size = Vector3.new(targetXZ.X, snow.Size.Y, targetXZ.Y)
	local yHalf = snow.Size.Y * 0.5
	snow.CFrame = CFrame.new(position + Vector3.new(0, yHalf, 0))
	local snowfall = snow:FindFirstChild("Snowfall")
	if snowfall and snowfall:IsA("ParticleEmitter") then snowfall.Enabled = true end
	local effectsFolder = WorkspaceService:FindFirstChild("Effects") or WorkspaceService
	snow.Parent = effectsFolder
	return snow
end

local function planarForward(cf: CFrame)
	local look = cf.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then return Vector3.new(0, 0, -1) end
	return forward.Unit
end

local function placementOffset(forward: Vector3, fieldSize: Vector3, rootPart: BasePart)
	local rootDepth = rootPart and rootPart.Size and rootPart.Size.Z or 4
	local distance = (fieldSize.Z * 0.5) + (rootDepth * 0.5) + CASTER_BUFFER
	return forward * distance
end

local function getNumberAttribute(instance: Instance?, attributeName: string)
	if not instance then return nil end
	local value = instance:GetAttribute(attributeName)
	return typeof(value) == "number" and value or nil
end

local function attachIcecubeAndSlow(enemyModel: Model, enemyRoot: BasePart, duration: number, slowMult: number, movementDefaults: { walk: number?, run: number? }?)
	local function getLeg(model: Model, side: "Right" | "Left"): BasePart?
		local try = side == "Right" and {"RightLowerLeg","RightUpperLeg","RightFoot","Right Leg"} or {"LeftLowerLeg","LeftUpperLeg","LeftFoot","Left Leg"}
		for _, name in ipairs(try) do
			local p = model:FindFirstChild(name)
			if p and p:IsA("BasePart") then return p end
		end
		return model:FindFirstChild("HumanoidRootPart")
	end

	local tmpl = getLocalAsset("icecube")
	local cubes = {}

	local function attachOne(toPart: BasePart?)
		if not tmpl or not toPart then return nil end
		local cube = tmpl:Clone()
		cube.Name = "IceCube"
		cube.Anchored = false
		cube.CanCollide = false
		cube.CFrame = toPart.CFrame * CFrame.Angles(0, ICECUBE_Y_ROT, 0)
		local effectsFolder = WorkspaceService:FindFirstChild("Effects") or WorkspaceService
		cube.Parent = effectsFolder
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cube
		weld.Part1 = toPart
		weld.Parent = cube
		Debris:AddItem(cube, duration + 2)
		table.insert(cubes, cube)
		return cube
	end

	attachOne(getLeg(enemyModel, "Right"))
	attachOne(getLeg(enemyModel, "Left"))

	local hum: Humanoid? = enemyModel:FindFirstChildOfClass("Humanoid")
	local baseWalk = movementDefaults and movementDefaults.walk
	if typeof(baseWalk) ~= "number" then baseWalk = getNumberAttribute(enemyModel, DEFAULT_WALK_ATTR) or (hum and hum.WalkSpeed) or 16 end
	local baseRun = movementDefaults and movementDefaults.run
	if typeof(baseRun) ~= "number" then baseRun = getNumberAttribute(enemyModel, DEFAULT_RUN_ATTR) or baseWalk end

	local slowMultiplier = slowMult or 1
	local slowedWalk = math.max(0, baseWalk * slowMultiplier)
	local slowedRun = math.max(0, baseRun * slowMultiplier)
	local slowApplied = false

	local function applySlowAttributes()
		if slowApplied then return end
		if not hum or not hum.Parent or not enemyModel.Parent then return end
		slowApplied = true
		enemyModel:SetAttribute(DEFAULT_WALK_ATTR, slowedWalk)
		enemyModel:SetAttribute(DEFAULT_RUN_ATTR, slowedRun)
		hum.WalkSpeed = slowedWalk
		task.delay(duration, function()
			if not enemyModel.Parent then return end
			if enemyModel:GetAttribute(DEFAULT_WALK_ATTR) == slowedWalk then
				enemyModel:SetAttribute(DEFAULT_WALK_ATTR, baseWalk)
				if hum.Parent then hum.WalkSpeed = baseWalk end
			end
			if enemyModel:GetAttribute(DEFAULT_RUN_ATTR) == slowedRun then
				enemyModel:SetAttribute(DEFAULT_RUN_ATTR, baseRun)
			end
		end)
	end

	task.delay(duration, function
		for _, c in ipairs(cubes) do if c and c.Parent then c:Destroy() end end
	end)

	return { applySlow = applySlowAttributes }
end

local function spawnWindupMain(rootPart: BasePart, forward: Vector3)
	local tmpl = getLocalAsset("main")
	if not tmpl or not tmpl:IsA("BasePart") then return nil end
	local forwardDir = forward.Magnitude > 0 and forward.Unit or planarForward(rootPart.CFrame)
	local offset = placementOffset(forwardDir, tmpl.Size, rootPart)
	local position = rootPart.Position + offset
	local part = tmpl:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position, position + (-forwardDir)) * CFrame.Angles(0, math.rad(90), 0)
	local effectsFolder = WorkspaceService:FindFirstChild("Effects") or WorkspaceService
	part.Parent = effectsFolder
	return part
end

return {
	Start = function(player: Player, tool: Tool)
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root: BasePart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then return end
		if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end

		local animation = getMoveAnim("Glacial Sweep")
		local castSound = getMoveSound("Glacial Sweep", "Cast")
		local impactSound = getMoveSound("Glacial Sweep", "Impact")

		local track: AnimationTrack?
		if animation then track = AnimationService:playAnimation(character, animation, 0.625); if track then track.Looped = false end end
		playSound(castSound, root)

		local stunValue = StunHandler:Stun(character, WINDUP_DURATION, true, 0, 0, true)
		humanoid.AutoRotate = false

		local basePosPredicted = groundPointBelow(root.Position, { character })
		local forward = planarForward(root.CFrame)
		local fieldTemplate = getFieldTemplate(script)
		local fieldSizeReference = fieldTemplate and fieldTemplate.Size or FIELD_SIZE
		local forwardOffset = placementOffset(forward, fieldSizeReference, root)
		local snowFx = spawnSnowAt(basePosPredicted + forwardOffset, fieldSizeReference)
		local windupMain = spawnWindupMain(root, forward)

		task.wait(WINDUP_DURATION)

		if windupMain and windupMain.Parent then windupMain:Destroy() end
		humanoid.AutoRotate = true

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { character }
		rayParams.IgnoreWater = true
		local rayResult = WorkspaceService:Raycast(root.Position, Vector3.new(0, -RAY_DISTANCE, 0), rayParams)
		local basePosition = rayResult and rayResult.Position or (root.Position - Vector3.new(0, humanoid.HipHeight, 0))

		local template = fieldTemplate
		local field = template and template:Clone() or buildDefaultField()
		field.Name = "GlacialSweepField"
		local placementCenter = basePosition + forwardOffset
		field.CFrame = CFrame.new(placementCenter + Vector3.new(0, field.Size.Y * 0.5, 0))
		local effectsFolder = WorkspaceService:FindFirstChild("Effects")
		field.Parent = effectsFolder or WorkspaceService
		field.Transparency = 0
		local fadeDuration = FIELD_LIFETIME
		local fade = TweenService:Create(field, TweenInfo.new(fadeDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { Transparency = 1 })
		fade.Completed:Connect(function() if field then field:Destroy() end end)
		fade:Play()
		Debris:AddItem(field, fadeDuration + 1)

		if snowFx and snowFx.Parent then snowFx:Destroy() end

		ReplicateEffects_Set:FireAllClients("Glacial Sweep", { Position = field.Position, Size = field.Size })

		local hitbox = HitboxHandler.new()
		hitbox.Instance = field
		hitbox.Size = Vector3.new(field.Size.X, HITBOX_HEIGHT, field.Size.Z)
		hitbox.Method = "Box"
		hitbox.Ignore = { character }
		hitbox.ResetCharactersList = true

		local impacted: { [Model]: boolean } = {}

		hitbox.onTouch = function(enemy: Model)
			if not enemy or enemy == character or impacted[enemy] then return end
			local enemyHumanoid: Humanoid = enemy:FindFirstChild("Humanoid")
			local enemyRoot: BasePart = enemy:FindFirstChild("HumanoidRootPart")
			if not enemyHumanoid or not enemyRoot then return end
			if enemyHumanoid.Health <= 0 or enemyHumanoid:GetState() == Enum.HumanoidStateType.Dead then return end
			if iFramesService:HasiFrame(enemy, tool.Name) then return end

			impacted[enemy] = true
			local baseWalkAttr = getNumberAttribute(enemy, DEFAULT_WALK_ATTR)
			local baseRunAttr = getNumberAttribute(enemy, DEFAULT_RUN_ATTR)
			local stunObject = StunHandler:Stun(enemy, STUN_DURATION, true, 0, 0, true)
			local slowController = attachIcecubeAndSlow(enemy, enemyRoot, STUN_DURATION, WALKSPEED_MULT, { walk = baseWalkAttr or enemyHumanoid.WalkSpeed, run = baseRunAttr or baseWalkAttr or enemyHumanoid.WalkSpeed })

			task.delay(STUN_DURATION, function()
				if enemy.Parent == nil then return end
				local stillHumanoid: Humanoid = enemy:FindFirstChild("Humanoid")
				local stillRoot: BasePart = enemy:FindFirstChild("HumanoidRootPart")
				if not stillHumanoid or not stillRoot then return end
				if enemy:HasTag("PerfectBlock") then if stunObject then StunHandler:Unstun(enemy, stunObject) end return end
				playSound(impactSound, stillRoot)
				DamageHandler:TakeDamage(character, stillHumanoid, DAMAGE_AMOUNT, nil, nil, false, false, true, true, true, nil, nil)
				if stunObject then StunHandler:Unstun(enemy, stunObject) end
				if slowController and slowController.applySlow then slowController.applySlow() end
			end)
		end

		for _ = 1, HITBOX_PULSES do
			hitbox:Once()
			task.wait(HITBOX_INTERVAL)
		end
		hitbox:Destroy()
		StunHandler:Unstun(character, stunValue)
	end,
}
