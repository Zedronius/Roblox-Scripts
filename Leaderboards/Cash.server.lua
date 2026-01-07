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

local e = require("EternityNum")
local userService = require("UserService")

local DSName = "Cash"
local Max = 100
local UPDATE = 120

local dataStore = DataStoreService:GetOrderedDataStore(DSName .. "Leaderboard")

local lb = workspace:WaitForChild("MoneyLeaderboard")
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

local function encodeValue(value)
	return e.lbencode(value or 0)
end

local function decodeValue(value)
	return e.lbdecode(value or 0)
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
		warn("[CashLeaderboard] Failed to resolve username:", err)
		task.wait(0.05)
	end

	return username
end

local function renderBoard(entries)
	clearBoard()

	for position, entry in ipairs(dedupeEntries(entries)) do
		local encoded = entry.value
		local cashValue = decodeValue(encoded)

		if e.le(cashValue, 0) then
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
		item.Stat.Text = "$" .. e.format(cashValue)
		item.Parent = contents
	end
end

local function fetchEntries()
	local success, data = pcall(function()
		return dataStore:GetSortedAsync(false, Max)
	end)

	if not success then
		warn("[CashLeaderboard] Failed to fetch leaderboard:", data)
		return {}
	end

	return data:GetCurrentPage()
end

local function pushPlayerValue(user)
	local userData = user and user:GetData()
	if not userData then
		return
	end

	local cash = userData.Cash
	if not cash or e.le(cash, 0) then
		return
	end

	local encoded = encodeValue(cash)
	if typeof(encoded) ~= "number" then
		warn("[CashLeaderboard] lbencode must return number, got", typeof(encoded))
		return
	end
	local player = user:GetPlayer()
	if not player then
		return
	end

	local success, err = pcall(function()
		dataStore:UpdateAsync(player.UserId, function()
			return encoded
		end)
	end)

	if not success then
		warn("[CashLeaderboard] Failed to update value:", err)
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
			warn("[CashLeaderboard] UserService:GetUsers() failed:", result)
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

while task.wait(UPDATE) do
	updateLeaderboard()
end
