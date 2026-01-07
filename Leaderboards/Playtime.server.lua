-- \\ Zedronius

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function getSource()
	local fromServer = ServerScriptService:FindFirstChild("source")
	if fromServer then
		return fromServer
	end

	local ok, fromReplicated = pcall(function()
		return RS:WaitForChild("source", 30)
	end)
	if ok and fromReplicated then
		return fromReplicated
	end
end

local source = getSource()

local loaderMarker = source:FindFirstChild("LoaderUtils", true) or source:WaitForChild("LoaderUtils", 10)

local require = require(loaderMarker.Parent).bootstrapGame(source)

local timeLib = require("TimeLib")
local userService = require("UserService")

local STATS_NAME = "Playtime"
local MAX_ITEMS = 100
local UPDATE_EVERY = 120

local dataStore = DataStoreService:GetOrderedDataStore(STATS_NAME .. "Leaderboard")

local lb = workspace:WaitForChild("PlaytimeLeaderboard")
local frame = lb.Leaderboard.SurfaceGui
local contents = frame:WaitForChild("Leaderboard")
local template = script:WaitForChild("Player")

local usernameCache = {}

local COLORS = {
	Default = Color3.fromRGB(197, 197, 197),
	Gold = Color3.fromRGB(255, 215, 0),
	Silver = Color3.fromRGB(192, 192, 192),
	Bronze = Color3.fromRGB(205, 127, 50),
}

local function formatPlaytime(seconds: number)
	seconds = math.max(0, tonumber(seconds) or 0)

	local weeks = math.floor(seconds / timeLib.ToSeconds.Week)
	seconds -= weeks * timeLib.ToSeconds.Week

	local days = math.floor(seconds / timeLib.ToSeconds.Day)
	seconds -= days * timeLib.ToSeconds.Day

	local hours = math.floor(seconds / timeLib.ToSeconds.Hour)
	seconds -= hours * timeLib.ToSeconds.Hour

	local minutes = math.floor(seconds / timeLib.ToSeconds.Minute)

	local parts = {}
	if weeks > 0 then table.insert(parts, (`{weeks}w`)) end
	if days > 0 then table.insert(parts, (`{days}d`)) end
	if hours > 0 then table.insert(parts, (`{hours}h`)) end
	if minutes > 0 or #parts == 0 then table.insert(parts, (`{minutes}m`)) end

	return table.concat(parts, " ")
end

local function clearBoard()
	for _, item in ipairs(contents:GetChildren()) do
		if item:IsA("Frame") then
			item:Destroy()
		end
	end
end

local function dedupeEntries(entries)
	local unique = {}
	local seen = {}

	for _, entry in ipairs(entries) do
		local userId = tonumber(entry.key)
		if userId and not seen[userId] then
			seen[userId] = true
			table.insert(unique, entry)
		end
	end

	return unique
end

local function getUsername(userId: number)
	if usernameCache[userId] then
		return usernameCache[userId]
	end

	local username = "[Not Available]"
	local ok, err = pcall(function()
		username = Players:GetNameFromUserIdAsync(userId)
	end)

	if ok then
		usernameCache[userId] = username
	else
		warn("[PlaytimeLeaderboard] Failed to resolve username:", err)
		task.wait(0.05)
	end

	return username
end

local function renderBoard(entries)
	clearBoard()

	for position, entry in ipairs(dedupeEntries(entries)) do
		local playtimeSeconds = tonumber(entry.value) or 0
		if playtimeSeconds <= 0 then
			continue
		end

		local userId = tonumber(entry.key)
		local username = getUsername(userId)

		local color = COLORS.Default
		if position == 1 then
			color = COLORS.Gold
		elseif position == 2 then
			color = COLORS.Silver
		elseif position == 3 then
			color = COLORS.Bronze
		end

		local item = template:Clone()
		item.Visible = true
		item.Name = username
		item.LayoutOrder = position
		item.Pos.TextColor3 = color
		item.Pos.Text = "#" .. position
		item.Username.Text = username
		item.Stat.Text = formatPlaytime(playtimeSeconds)
		item.Parent = contents
	end
end

local function fetchEntries()
	local success, data = pcall(function()
		return dataStore:GetSortedAsync(false, MAX_ITEMS)
	end)

	if not success then
		warn("[PlaytimeLeaderboard] Failed to fetch leaderboard:", data)
		return {}
	end

	return data:GetCurrentPage()
end

local function pushPlayerValue(user)
	local userData = user and user:GetData()
	if not userData then
		return
	end

	local playtime = nil
	if userData.GetPlaytime then
		local ok, result = pcall(function()
			return userData:GetPlaytime()
		end)
		if ok then
			playtime = result
		end
	end

	if playtime == nil then
		return
	end

	local playtimeSeconds = tonumber(playtime) or 0
	if playtimeSeconds <= 0 then
		return
	end

	local player = user.GetPlayer and user:GetPlayer()
	if not player then
		return
	end

	local success, err = pcall(function()
		dataStore:UpdateAsync(player.UserId, function()
			return math.floor(playtimeSeconds)
		end)
	end)

	if not success then
		warn("[PlaytimeLeaderboard] Failed to update value:", err)
	end
end

local function updateLeaderboard()
	local users

	if userService and userService.GetUsers then
		local ok, result = pcall(function()
			return userService:GetUsers()
		end)
		if ok and typeof(result) == "table" then
			users = result
		elseif ok and result == nil then
			return
		else
			warn("[PlaytimeLeaderboard] UserService:GetUsers() failed:", result)
			return
		end
	end

	if not users then
		return
	end

	for _, user in pairs(users) do
		pushPlayerValue(user)
	end

	renderBoard(fetchEntries())
end

while true do
	local ok, users = pcall(function()
		return userService and userService.GetUsers and userService:GetUsers()
	end)
	if ok and typeof(users) == "table" then
		break
	end
	task.wait(0.1)
end

updateLeaderboard()

if userService and userService.BindUserAdded then
	userService:BindUserAdded(function(user)
		pushPlayerValue(user)
		renderBoard(fetchEntries())
	end)
end

while task.wait(UPDATE_EVERY) do
	updateLeaderboard()
end
