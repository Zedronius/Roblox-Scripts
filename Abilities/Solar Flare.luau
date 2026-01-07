local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local StunHandler = ServerStorage:FindFirstChild("Modules") and require(ServerStorage.Modules:WaitForChild("StunHandler"))
local AnimationService = ServerStorage:FindFirstChild("Modules") and require(ServerStorage.Modules:WaitForChild("AnimationService"))
local SoundsModule = ServerStorage:FindFirstChild("Modules") and require(ServerStorage.Modules:WaitForChild("SoundsModule"))

local Assets = ServerStorage:FindFirstChild("Assets")
local Sounds = Assets and Assets:FindFirstChild("Sounds")
local MoveSounds = Sounds and Sounds:FindFirstChild("Moves")

local WIZARD_FOLDER = "Fire Wizard"
local ABILITY_NAME = "Solar Flare"

local PROJECTILE_SPEED = 45
local EXPLODE_AFTER = 0.5
local BLIND_DURATION = 1.5
local RANGE = 55
local FACE_DOT_THRESHOLD = 0.85
local START_FORWARD_OFFSET = 5
local CLEANUP_AFTER = 1
local ASCENT_SPEED = 20

local function getMoveSound(name, soundName)
	if not MoveSounds then return nil end
	local folder = MoveSounds:FindFirstChild(WIZARD_FOLDER)
	if not folder then return nil end
	local move = folder:FindFirstChild(name)
	if not move then return nil end
	return move:FindFirstChild(soundName or "Cast")
end

local function getCaster(character: Model)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character == character then
			return plr
		end
	end
	return nil
end

local function findUnderScript(name: string)
	return script:FindFirstChild(name)
end

local function enableAllDescendantEmitters(root: Instance, enabled: boolean)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = enabled
		end
	end
end

local function safeFindHead(model: Model): BasePart?
	return model:FindFirstChild("Head") :: BasePart
		or model:FindFirstChild("UpperTorso") :: BasePart
		or model:FindFirstChild("Torso") :: BasePart
end

local function isLookingAt(head: BasePart, targetPos: Vector3, dotThreshold: number, ignoreList: {Instance}): boolean
	local toTarget = (targetPos - head.Position)
	local distance = toTarget.Magnitude
	if distance <= 0.001 then return false end
	local dir = toTarget.Unit
	local forward = head.CFrame.LookVector
	local dot = forward:Dot(dir)
	if dot < dotThreshold then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList
	params.IgnoreWater = true

	local result = Workspace:Raycast(head.Position, dir * distance, params)
	return (result == nil)
end

local function blindPlayerFor(player: Player, duration: number, blindTemplate: Attachment)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		local blindGui = pg:FindFirstChild("BlindScreen")
		if blindGui and blindGui:IsA("ScreenGui") then
			blindGui.Enabled = true
			task.delay(duration, function()
				if blindGui then
					blindGui.Enabled = false
				end
			end)
		end
	end

	local char = player.Character
	if not char then return end
	local head = safeFindHead(char)
	if not head then return end

	if blindTemplate and blindTemplate:IsA("Attachment") then
		local att = blindTemplate:Clone()
		att.Parent = head
		Debris:AddItem(att, duration + 0.1)
	end
end

return {
	Start = function(player: Player, tool: Tool)
		local character = player and player.Character
		if not character then return end

		local root = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return end

		local flareTemplate = findUnderScript("flare")
		local blindTemplate = findUnderScript("blind")
		if not (flareTemplate and flareTemplate:IsA("BasePart")) then return end
		if not (blindTemplate and blindTemplate:IsA("Attachment")) then return end
		
		local castSound = getMoveSound(ABILITY_NAME, "Cast")
		if castSound then
			SoundsModule:PlaySound(castSound, root)
		end
		
		local forward = root.CFrame.LookVector
		if forward.Magnitude < 0.001 then forward = Vector3.new(0,0,-1) end
		forward = forward.Unit

		local startPos = root.Position + forward * START_FORWARD_OFFSET
		local flare = flareTemplate:Clone()
		flare.Name = "SolarFlare_Projectile"
		flare.CFrame = CFrame.new(startPos, startPos + forward)
		flare.CanCollide = false
		flare.CanTouch = false
		flare.CanQuery = true
		flare.Anchored = false
		flare.Massless = true
		flare.Parent = Workspace:FindFirstChild("Effects") or Workspace
		Debris:AddItem(flare, CLEANUP_AFTER + 2)

		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e7, 1e7, 1e7)
		bv.Velocity = forward * PROJECTILE_SPEED + Vector3.new(0, ASCENT_SPEED, 0)
		bv.Parent = flare
		flare:SetNetworkOwner(nil)

		task.delay(EXPLODE_AFTER, function()
			if not flare or not flare.Parent then return end
			if bv then bv:Destroy() end
			flare.Anchored = true

			local mainAttach = flare:FindFirstChild("Main", true)
			if mainAttach and mainAttach:IsA("Attachment") then
				enableAllDescendantEmitters(mainAttach, true)
			end

			local explosionPos = flare.Position
			local caster = getCaster(character)
			local ignoreRay = { flare, character }

			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= caster then
					local ch = plr.Character
					local ph = ch and safeFindHead(ch)
					local hum2 = ch and ch:FindFirstChildOfClass("Humanoid")
					if ph and hum2 and hum2.Health > 0 then
						if (ph.Position - explosionPos).Magnitude <= RANGE then
							if isLookingAt(ph, explosionPos, FACE_DOT_THRESHOLD, ignoreRay) then
								blindPlayerFor(plr, BLIND_DURATION, blindTemplate)
							end
						end
					end
				end
			end

			task.delay(CLEANUP_AFTER, function()
				if flare and flare.Parent then flare:Destroy() end
			end)
		end)
	end,
}
