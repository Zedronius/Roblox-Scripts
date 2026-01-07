local ForceRepel = {}

-- Services
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Libraries/Data
local ReplicatedFirstModules = ReplicatedFirst.Modules
local Connection = require(ReplicatedFirstModules.Connection)

local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")
local ToolsData = require(ReplicatedModules:WaitForChild("ToolsData"))
local Sounds = require(ReplicatedModules:WaitForChild("Sounds"))
local Animations = require(ReplicatedModules:WaitForChild("Animations"))

-- Events
local ForceRepelWindEffectEvent = Connection.Get("RemoteEvent", "ForceRepelWindEffectEvent")

-- Variables
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local MainUI = PlayerGui:WaitForChild("Main")
local BlindScreenFrame = MainUI:WaitForChild("BlindScreen")
local LightsaberFrame = MainUI:WaitForChild("Game"):WaitForChild("LightsaberFrame")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local ForceRepelWindAsset = Assets:WaitForChild("Perks"):WaitForChild("ForcePush"):WaitForChild("ForcePushWind")

local Mouse = Player:GetMouse()
local Camera = workspace.CurrentCamera
local ForceRepelAnimations = {}

function IsPositionBehind(part1, part2)
	local Facing = part1.CFrame.LookVector
	local Vector = (part2 - part1.Position).unit

	local angle = Facing:Dot(Vector)
	return angle < 0, math.deg(math.acos(Facing:Dot(Vector)))
end

function GetAllCharacters(targetCharacter)
	local characters = {}
	for _, plr in pairs(Players:GetPlayers()) do
		if plr.Character and targetCharacter ~= plr.Character then
			table.insert(characters, plr.Character)
		end
	end
	return characters
end

function ForceRepel.Run()
	local Character = Player.Character
	local Humanoid = Character and Character:FindFirstChild("Humanoid") or nil

	if not Humanoid or Humanoid.Health <= 0 then
		return
	end
	local humanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	local playerDivision = Player:GetAttribute("Division")
	local playerClass = Player:GetAttribute("Class")

	local IsValid = "FailedUsage"

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = GetAllCharacters()
	raycastParams.IgnoreWater = true
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local closestPlayer, closestDistance = "FailedUsage", 48
	for _, targetPlayer in pairs(Players:GetPlayers()) do
		if targetPlayer == Player then
			continue
		end
		if not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
			continue
		end
		local targetPlayerDivision = targetPlayer:GetAttribute("Division")
		local targetPlayerClass = targetPlayer:GetAttribute("Class")
		local CanPush = false
		if playerDivision == "Immigrant" then
			if targetPlayerDivision ~= "Immigrant" then
				CanPush = true
			end
		else
			CanPush = true
		end

		if CanPush then
			local targetCharacter = targetPlayer.Character
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChild("Humanoid") or nil

			if targetHumanoid and targetHumanoid.Health > 0 then
				local targetCharacterCFrame = targetCharacter.HumanoidRootPart.CFrame
				if
					(targetCharacterCFrame.Position - Character.HumanoidRootPart.Position).Magnitude <= closestDistance
				then
					local direction = (targetCharacterCFrame.Position - humanoidRootPart.Position).Unit
					raycastParams.FilterDescendantsInstances =
						{ workspace.Map.Barriers, GetAllCharacters(targetCharacter) }

					local raycastResult = workspace:Raycast(humanoidRootPart.Position, direction * 48, raycastParams)
					if raycastResult and raycastResult.Instance:IsDescendantOf(targetCharacter) then
						IsValid = true
						break
					end
				end
			end
		end
	end

	if IsValid then
		Animations.PlayAnimation(ForceRepelAnimations["ForceRepel"], 0.1)
	end

	return IsValid
end

function ForceRepel.Destroy() end

function ForceRepel.InitPlayer(humanoid)
	if humanoid == nil then
		return
	end
	local character = humanoid.Parent

	local ForceRepelTrack = Animations.LoadAnimation(Animations["Force Powers"].ForcePush, humanoid)
	ForceRepelAnimations[ForceRepelTrack.Name] = ForceRepelTrack
end

function ForceRepel.Init()
	ForceRepelWindEffectEvent:ConnectCallback(function(humanoidRootPart, distance)
		if humanoidRootPart:IsDescendantOf(workspace) == false then
			return
		end
		local newWindAsset = ForceRepelWindAsset:Clone()
		distance += 7
		local direction = humanoidRootPart.CFrame.LookVector
		newWindAsset.CFrame = humanoidRootPart.CFrame + (direction * 3)
		local endGoal = humanoidRootPart.CFrame + (direction * distance)
		local timeToTake = 1 / (68 / distance)
		local newTween = TweenService:Create(
			newWindAsset,
			TweenInfo.new(timeToTake, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = endGoal }
		)
		newWindAsset.Parent = workspace
		newTween:Play()
		newTween.Completed:Connect(function()
			newWindAsset:Destroy()
		end)
	end)
end

return ForceRepel
