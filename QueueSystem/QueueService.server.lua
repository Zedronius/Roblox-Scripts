local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local QueueFolder = Workspace:WaitForChild("Queue")

local REMOTES = ReplicatedStorage:FindFirstChild("Remotes")
local queueRemotes = REMOTES:FindFirstChild("Queue")
local QueueUpdated = queueRemotes:FindFirstChild("QueueUpdated")
local LeaveQueue = queueRemotes:FindFirstChild("LeaveQueue")
local SetLeaderSettings = queueRemotes:FindFirstChild("SetLeaderSettings")

local MAX_QUEUE_PLAYERS = 4
local DEFAULT_COUNTDOWN = 30
local mapOptions = {
	{ Name = "ZED'S SPECIAL", Image = "", PlaceId = 126753205221914 },
	{ Name = "thing 2", Image = "", PlaceId = 0 }
}

local queues = {}
local playerQueue = {}

local function updateWorldGui(model)
	local data = queues[model]
	if not data then
		return
	end

	local function findChildCaseInsensitive(parent, targetName)
		if not parent then
			return nil
		end
		local exact = parent:FindFirstChild(targetName)
		if exact then
			return exact
		end
		local targetLower = string.lower(targetName)
		for _, child in ipairs(parent:GetChildren()) do
			if string.lower(child.Name) == targetLower then
				return child
			end
		end
		return nil
	end

	local function setLabel(containerName, text)
		local container = findChildCaseInsensitive(model, containerName)
		if not container then
			return
		end
		local gui = findChildCaseInsensitive(container, "gui") or container
		local label = gui:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = text
		end
	end

	setLabel("queue", string.format("%d/%d", #data.players, data.maxPlayers))
	setLabel("time", string.format("%ds", math.max(0, math.floor(data.countdown))))

	local mapFolder = findChildCaseInsensitive(model, "map")
	if mapFolder then
		local gui = findChildCaseInsensitive(mapFolder, "gui") or mapFolder
		local textLabel = gui:FindFirstChildWhichIsA("TextLabel", true)
		if textLabel then
			textLabel.Text = data.map.Name
		end
		local imageLabel = gui:FindFirstChildWhichIsA("ImageLabel", true)
		if imageLabel then
			imageLabel.Image = data.map.Image or ""
		end
	end
end

local function serializeForPlayer(model, player)
	local data = queues[model]
	if not data then
		return nil
	end
	local playersList = {}
	for _, plr in ipairs(data.players) do
		table.insert(playersList, { UserId = plr.UserId, Name = plr.Name })
	end
	return {
		QueueName = model.Name,
		Players = playersList,
		LeaderUserId = data.leader and data.leader.UserId or nil,
		MaxPlayers = data.maxPlayers,
		Map = data.map,
		Countdown = data.countdown,
		IsLeader = data.leader == player,
	}
end

local function broadcast(model)
	local data = queues[model]
	if not data then
		return
	end
	for _, plr in ipairs(data.players) do
		QueueUpdated:FireClient(plr, serializeForPlayer(model, plr))
	end
	updateWorldGui(model)
end

local function stopTimer(model)
	local data = queues[model]
	if data and data.timerConn then
		data.timerConn:Disconnect()
		data.timerConn = nil
	end
end

local function removePlayer(player)
	local model = playerQueue[player]
	if not model then
		return
	end
	local data = queues[model]
	if not data then
		playerQueue[player] = nil
		return
	end
	for i, plr in ipairs(data.players) do
		if plr == player then
			table.remove(data.players, i)
			break
		end
	end
	playerQueue[player] = nil
	if data.leader == player then
		data.leader = data.players[1]
		if #data.players == 0 then
			data.countdown = DEFAULT_COUNTDOWN
			stopTimer(model)
		end
	end
	if data.out and data.out:IsA("BasePart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = player.Character.HumanoidRootPart
		hrp.CFrame = data.out.CFrame + Vector3.new(0, hrp.Size.Y, 0)
	end
	broadcast(model)
end

local function ensureTimer(model)
	local data = queues[model]
	if not data or data.timerConn then
		return
	end
	local lastSecond = math.floor(data.countdown)
	data.timerConn = RunService.Heartbeat:Connect(function(dt)
		if #data.players == 0 then
			data.countdown = DEFAULT_COUNTDOWN
			stopTimer(model)
			updateWorldGui(model)
			return
		end
		data.countdown -= dt
		local currentSecond = math.floor(math.max(0, data.countdown))
		if currentSecond ~= lastSecond then
			lastSecond = currentSecond
			updateWorldGui(model)
			broadcast(model)
		end
		if data.countdown <= 0 then
			data.countdown = 0
			local placeId = data.map.PlaceId or 0
			if placeId ~= 0 then
				local plrs = {}
				for _, p in ipairs(data.players) do
					table.insert(plrs, p)
				end
				local ok, err = pcall(function()
					TeleportService:TeleportAsync(placeId, plrs)
				end)
				if not ok then
					for _, p in ipairs(data.players) do
						removePlayer(p)
					end
					warn("[QueueService] Teleport failed:", err)
				end
			end
			for _, p in ipairs(data.players) do
				playerQueue[p] = nil
			end
			data.players = {}
			data.leader = nil
			data.countdown = DEFAULT_COUNTDOWN
			stopTimer(model)
			updateWorldGui(model)
			broadcast(model)
		end
	end)
end

local function setLeader(model, leader)
	local data = queues[model]
	if not data then
		return
	end
	data.leader = leader
end


local function joinQueue(player, model)
	if playerQueue[player] then
		return false, "Already in a queue."
	end
	local data = queues[model]
	if not data then
		data = {
			players = {},
			leader = nil,
			maxPlayers = MAX_QUEUE_PLAYERS,
			map = mapOptions[1],
			mapIndex = 1,
			countdown = DEFAULT_COUNTDOWN,
			timerConn = nil,
			area = model:FindFirstChild("area"),
			out = model:FindFirstChild("out"),
		}
		queues[model] = data
	end
	if #data.players >= data.maxPlayers then
		return false, "Queue is full."
	end

	table.insert(data.players, player)
	playerQueue[player] = model
	if not data.leader then
		setLeader(model, player)
		data.countdown = DEFAULT_COUNTDOWN
		ensureTimer(model)
	end

	if data.area and data.area:IsA("BasePart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = player.Character.HumanoidRootPart
		hrp.CFrame = data.area.CFrame + Vector3.new(0, hrp.Size.Y, 0)
	end

	broadcast(model)
	return true
end

local function handleTouch(model, tpPart)
	tpPart.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			joinQueue(player, model)
		end
	end)
end

for _, model in ipairs(QueueFolder:GetChildren()) do
	local tp = model:FindFirstChild("tp")
	if tp and tp:IsA("BasePart") then
		handleTouch(model, tp)
	end
	queues[model] = {
		players = {},
		leader = nil,
		maxPlayers = MAX_QUEUE_PLAYERS,
		map = mapOptions[1],
		mapIndex = 1,
		countdown = DEFAULT_COUNTDOWN,
		timerConn = nil,
		area = model:FindFirstChild("area"),
		out = model:FindFirstChild("out"),
	}
	updateWorldGui(model)
end

QueueFolder.ChildAdded:Connect(function(model)
	local tp = model:WaitForChild("tp", 5)
	if tp and tp:IsA("BasePart") then
		handleTouch(model, tp)
	end
	queues[model] = {
		players = {},
		leader = nil,
		maxPlayers = MAX_QUEUE_PLAYERS,
		map = mapOptions[1],
		mapIndex = 1,
		countdown = DEFAULT_COUNTDOWN,
		timerConn = nil,
		area = model:FindFirstChild("area"),
		out = model:FindFirstChild("out"),
	}
	updateWorldGui(model)
end)

LeaveQueue.OnServerInvoke = function(player)
	removePlayer(player)
	return true
end

SetLeaderSettings.OnServerInvoke = function(player, settings)
	local model = playerQueue[player]
	if not model then
		return false, "Not in a queue."
	end
	local data = queues[model]
	if not data or data.leader ~= player then
		return false, "Not leader."
	end
	if settings then
		if settings.maxPlayers then
			local clamped = math.clamp(math.floor(settings.maxPlayers), 1, MAX_QUEUE_PLAYERS)
			data.maxPlayers = clamped
		end
		if settings.mapIndex and mapOptions[settings.mapIndex] then
			data.mapIndex = settings.mapIndex
			data.map = mapOptions[settings.mapIndex]
		end
	end
	broadcast(model)
	return true
end

Players.PlayerRemoving:Connect(function(plr)
	removePlayer(plr)
end)
