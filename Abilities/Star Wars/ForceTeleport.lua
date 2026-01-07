local ForceTeleport = {}

-- Services
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- Libraries/Data
local ReplicatedFirstModules = ReplicatedFirst.Modules
local Connection = require(ReplicatedFirstModules.Connection)

-- Variables
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local Camera = Workspace.CurrentCamera

-- Events
local RunForceTeleportEvent = Connection.Get("RemoteEvent", "RunForceTeleportEvent")

function ForceTeleport.GTP()
	local Character = Player.Character
	if not Character then return nil end

	local humanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end

	local rcp = RaycastParams.new()
	rcp.FilterDescendantsInstances = {Character, Camera}
	rcp.FilterType = Enum.RaycastFilterType.Blacklist

	local rcr = Workspace:Raycast(
		Camera.CFrame.Position,
		(Mouse.Hit.Position - Camera.CFrame.Position).Unit * 100,
		rcp
	)

	if rcr then
		local gc = Workspace:Raycast(
			rcr.Position + Vector3.new(0, 5, 0),
			Vector3.new(0, -10, 0),
			rcp
		)

		if gc and (humanoidRootPart.Position - gc.Position).Magnitude <= 50 then
			return gc.Position
		end
	end

	return nil
end

function ForceTeleport.Run()
	local Character = Player.Character
	if not Character then return end

	local humanoid = Character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local po = ForceTeleport.GTP()
	if po then
		RunForceTeleportEvent:Call(po)
	end

	return po and "Success" or "FailedUsage"
end

function ForceTeleport.Destroy() end

function ForceTeleport.InitPlayer(humanoid)
end

function ForceTeleport.Init()
end

return ForceTeleport
