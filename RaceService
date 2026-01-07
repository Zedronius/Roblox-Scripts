-- \\ @ Zedronius

local require = require(script.Parent.loader).load(script)

local players = game:GetService("Players")

local userService = require("UserService")
local tycoonService = require("TycoonService")
local form = require("Form")
local e = require("EternityNum")

local RACE_INTERVAL_SECONDS = 60 * 10
local JOIN_WINDOW_SECONDS = 30
local RACE_DURATION_SECONDS = 60 * 3
local INITIAL_DELAY_SECONDS = 0
local PLACE_MULTIPLIERS = {
	[1] = 3,
	[2] = 2,
	[3] = 1.5,
}

local raceService = {}
raceService.ServiceName = "RaceService"
raceService.Client = {
	Signals = {
		"RaceState",
		"CheckpointUpdate",
		"ParticipantState",
		"PlacementUpdate",
	},
}

local function indexNumberedParts(folder: Instance)
	local byIndex = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local index = tonumber(child.Name)
			if index then
				byIndex[index] = child
			end
		end
	end
	local indices = {}
	for index in pairs(byIndex) do
		table.insert(indices, index)
	end
	table.sort(indices)
	return byIndex, indices
end

function raceService:Init()
	self._participants = {}
	self._raceActive = false
	self._joinOpen = false
	self._nextLineupSlot = 1
	self._phase = "Next"
	self._phaseEndTime = os.time() + RACE_INTERVAL_SECONDS
	self._placements = {}

	self:_resolveTrack()
end

function raceService:Start()
	if not self._raceFolder then
		return
	end

	task.spawn(function()
		if INITIAL_DELAY_SECONDS > 0 then
			self:_setPhase("Next", INITIAL_DELAY_SECONDS)
			task.wait(INITIAL_DELAY_SECONDS)
		end

		while true do
			self:_setPhase("Next", RACE_INTERVAL_SECONDS)
			task.wait(RACE_INTERVAL_SECONDS)
			self:_openJoinWindow()
			self:_setPhase("Join", JOIN_WINDOW_SECONDS)
			task.wait(JOIN_WINDOW_SECONDS)

			self._joinOpen = false
			if not self:_hasParticipants() then
				self._participants = {}
				self._placements = {}
				continue
			end

			self:_startRace()
			self:_setPhase("Race", RACE_DURATION_SECONDS)
			task.wait(RACE_DURATION_SECONDS)

			self:_endRace()
		end
	end)
end

function raceService:UserRemoving(user: userService.User)
	local player = user:GetPlayer()
	self._participants[player] = nil
end

function raceService:UserAdded(user: userService.User)
	self:_sendStateToPlayer(user:GetPlayer())
end

function raceService:_resolveTrack()
	local raceFolder = workspace:WaitForChild("ZedRace", 10)
	if not raceFolder then
		return
	end

	local checkpointFolder = raceFolder:FindFirstChild("Checkpoint")
	local lineupFolder = raceFolder:FindFirstChild("Lineup")
	if not checkpointFolder or not lineupFolder then
		return
	end

	self._raceFolder = raceFolder
	self._checkpointFolder = checkpointFolder
	self._lineupFolder = lineupFolder

	self._checkpointsByIndex, self._checkpointIndices = indexNumberedParts(checkpointFolder)
	self._lineupByIndex, self._lineupIndices = indexNumberedParts(lineupFolder)

	local filtered = {}
	for _, index in ipairs(self._checkpointIndices) do
		if index <= 19 then
			table.insert(filtered, index)
		end
	end
	self._checkpointIndices = filtered

	self:_buildCheckpointState()
	self:_connectCheckpoints()
	self:_setCheckpointTouchEnabled(false)
end

function raceService:_buildCheckpointState()
	self._checkpointNextIndex = {}
	self._checkpointOriginalCanTouch = {}

	for i, index in ipairs(self._checkpointIndices) do
		local part = self._checkpointsByIndex[index]
		part.Transparency = 0.5
		self._checkpointOriginalCanTouch[part] = part.CanTouch
		self._checkpointNextIndex[index] = self._checkpointIndices[i + 1]
	end

	self._firstCheckpointIndex = self._checkpointIndices[1]
	if self._checkpointsByIndex[19] then
		self._lastCheckpointIndex = 19
	else
		self._lastCheckpointIndex = self._checkpointIndices[#self._checkpointIndices]
	end
end

function raceService:_connectCheckpoints()
	for _, index in ipairs(self._checkpointIndices) do
		local part = self._checkpointsByIndex[index]
		part.Touched:Connect(function(hit: BasePart)
			self:_onCheckpointTouched(index, hit)
		end)
	end
end

function raceService:_setCheckpointTouchEnabled(enabled: boolean)
	for _, index in ipairs(self._checkpointIndices) do
		local part = self._checkpointsByIndex[index]
		part.CanTouch = enabled and true or self._checkpointOriginalCanTouch[part] ~= false
	end
end

function raceService:_openJoinWindow()
	self._participants = {}
	self._raceActive = false
	self._joinOpen = true
	self._nextLineupSlot = 1
	self._placements = {}
end

function raceService:_startRace()
	self._joinOpen = false
	self._raceActive = true
	self:_setCheckpointTouchEnabled(true)
	for _, participant in pairs(self._participants) do
		if participant and participant.vehicleModel then
			self:_setVehicleMovementEnabled(participant.vehicleModel, true)
		end
	end
end

function raceService:_endRace()
	self._raceActive = false
	self._joinOpen = false
	for player, participant in pairs(self._participants) do
		if participant and participant.vehicleModel then
			self:_setVehicleMovementEnabled(participant.vehicleModel, true)
		end
		if player and player.Parent == players then
			if self.Client.ParticipantState then
				self.Client.ParticipantState:Fire(player, false)
			end
			if self.Client.CheckpointUpdate then
				self.Client.CheckpointUpdate:Fire(player, nil)
			end
		end
	end
	self._participants = {}
	self._placements = {}
	self:_setCheckpointTouchEnabled(false)
end

function raceService:_handleJoin(user: userService.User)
	if not self._joinOpen then
		return false, "Race joining is closed."
	end

	local player = user:GetPlayer()
	if self._participants[player] then
		return false, "You're already in the race."
	end

	local sellerBuilding = self:_getSellerBuilding(user)
	local carLevel = self:_getCarLevel(sellerBuilding)
	if carLevel < 3 then
		return false, "Car needs to be Level 3 to race."
	end

	local slot = self._nextLineupSlot
	local lineupIndex = self._lineupIndices[slot]
	local lineupPart = lineupIndex and self._lineupByIndex[lineupIndex] or nil
	if not lineupPart then
		return false, "Race is full."
	end

	local success, err, vehicleModel = self:_teleportToLineup(user, lineupPart, sellerBuilding)
	if not success then
		return false, err or "Unable to join race right now."
	end

	self._nextLineupSlot += 1
	self._participants[player] = {
		nextCheckpoint = self._firstCheckpointIndex,
		vehicleModel = vehicleModel,
	}

	if vehicleModel then
		self:_setVehicleMovementEnabled(vehicleModel, false)
	end

	if self.Client.ParticipantState then
		self.Client.ParticipantState:Fire(player, true)
	end
	if self.Client.CheckpointUpdate then
		self.Client.CheckpointUpdate:Fire(player, self._firstCheckpointIndex)
	end

	return true, self._firstCheckpointIndex
end

function raceService:_teleportToLineup(user: userService.User, lineupPart: BasePart, sellerBuilding): (boolean, string?, Model?)
	local character = user:GetCharacter()
	if not character then
		return false, "Character not ready."
	end

	local humanoid = user:GetHumanoid()
	if not humanoid then
		return false, "Character not ready."
	end

	local seatPart = self:_getVehicleSeat(user, sellerBuilding)
	if not seatPart then
		return false, "Vehicle not found."
	end

	if seatPart.Occupant and seatPart.Occupant ~= humanoid then
		return false, "Vehicle seat is occupied."
	end

	seatPart:Sit(humanoid)
	task.wait()

	local vehicleModel = seatPart:FindFirstAncestorOfClass("Model")
	if vehicleModel then
		vehicleModel:PivotTo(form.placeAt(vehicleModel, lineupPart))
		return true, nil, vehicleModel
	end

	user:PivotTo(form.placeAt(character, lineupPart))
	return true, nil, nil
end

function raceService:_getPlayerFromHit(hit: BasePart): Player?
	if not hit or not hit.Parent then
		return nil
	end

	local player = players:GetPlayerFromCharacter(hit.Parent)
	if player then
		return player
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)
	if seat and seat.Occupant then
		return players:GetPlayerFromCharacter(seat.Occupant.Parent)
	end

	return nil
end

function raceService:_hasParticipants(): boolean
	for player in pairs(self._participants) do
		if player and player.Parent == players then
			return true
		end
	end
	return false
end

function raceService:_setVehicleMovementEnabled(vehicleModel: Model?, enabled: boolean)
	if not vehicleModel or not vehicleModel.Parent then
		return
	end

	local chassis = vehicleModel:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return
	end

	local vectorForce = chassis:FindFirstChild("VectorForce")
	if vectorForce and vectorForce:IsA("VectorForce") then
		vectorForce.Enabled = enabled
	end

	local angularVelocity = chassis:FindFirstChild("AngularVelocity")
	if angularVelocity and angularVelocity:IsA("AngularVelocity") then
		angularVelocity.Enabled = enabled
	end

	if not enabled then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
end

function raceService:_onCheckpointTouched(index: number, hit: BasePart)
	if not self._raceActive then
		return
	end

	local player = self:_getPlayerFromHit(hit)
	if not player then
		return
	end

	local participant = self._participants[player]
	if not participant then
		return
	end

	if participant.completed then
		return
	end

	if participant.nextCheckpoint ~= index then
		return
	end

	local user = userService:GetUserFromPlayer(player)
	if not user then
		return
	end

	local userData = user:GetData()
	local reward = self:_getCheckpointReward(userData, index)
	userData:AddStat("Cash", reward, "RaceCheckpoint")

	local nextIndex = self._checkpointNextIndex[index]
	if nextIndex then
		participant.nextCheckpoint = nextIndex
	else
		participant.nextCheckpoint = nil
		participant.completed = true

		local baseBonus = e.mul(reward, 2)
		local place = self:_assignPlacement(user)
		local placeMultiplier = PLACE_MULTIPLIERS[place] or 1
		local bonus = e.mul(baseBonus, placeMultiplier)
		userData:AddStat("Cash", bonus, "RaceCompletion")
		user:Success("RACE COMPLETED")
	end

	if self.Client.CheckpointUpdate then
		self.Client.CheckpointUpdate:Fire(player, participant.nextCheckpoint)
	end
end

function raceService:_setPhase(phase: string, durationSeconds: number)
	self._phase = phase
	self._phaseEndTime = os.time() + math.max(durationSeconds or 0, 0)
	if self.Client.RaceState then
		self.Client.RaceState:FireAll(self._phase, self._phaseEndTime)
	end
end

function raceService:_sendStateToPlayer(player: Player)
	if not player then
		return
	end

	if self.Client.RaceState then
		self.Client.RaceState:Fire(player, self._phase, self._phaseEndTime)
	end

	if self._participants[player] then
		if self.Client.ParticipantState then
			self.Client.ParticipantState:Fire(player, true)
		end
		if self.Client.CheckpointUpdate then
			self.Client.CheckpointUpdate:Fire(player, self._participants[player].nextCheckpoint)
		end
		if self.Client.PlacementUpdate then
			for place, entry in pairs(self._placements) do
				local name = entry
				local userId = nil
				if typeof(entry) == "table" then
					name = entry.name
					userId = entry.userId
				end
				self.Client.PlacementUpdate:Fire(player, place, name, userId)
			end
		end
	else
		if self.Client.ParticipantState then
			self.Client.ParticipantState:Fire(player, false)
		end
	end
end

function raceService.Client:JoinRace(user: userService.User)
	return self.Server:_handleJoin(user)
end

function raceService:_getState()
	return self._phase, self._phaseEndTime
end

function raceService.Client:GetState(user: userService.User)
	return self.Server:_getState()
end

function raceService:_getSellerBuilding(user: userService.User)
	local tycoon = tycoonService:GetTycoonFromUser(user)
	if not tycoon then
		return nil
	end
	return tycoon:GetBuilding("Seller")
end

function raceService:_getCarLevel(sellerBuilding): number
	if not sellerBuilding then
		return 0
	end
	local level = sellerBuilding:Get("Level") or 0
	if e.is(level) then
		return e.toNumber(level)
	end
	return tonumber(level) or 0
end

function raceService:_getVehicleSeat(user: userService.User, sellerBuilding): Seat?
	if sellerBuilding then
		local model = sellerBuilding:GetModel()
		if model then
			local seat = model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true)
			if seat then
				return seat
			end
		end
	end

	local humanoid = user:GetHumanoid()
	if humanoid and humanoid.SeatPart then
		return humanoid.SeatPart
	end

	return nil
end

function raceService:_getCheckpointScale(index: number): number
	if not self._lastCheckpointIndex or self._lastCheckpointIndex <= 1 then
		return 0.1
	end
	local t = (index - 1) / (self._lastCheckpointIndex - 1)
	return 0.1 + (0.5 - 0.1) * t
end

function raceService:_getCheckpointReward(userData: userService.UserData, index: number)
	local current = userData:Get("Cash") or e(0)
	local scale = self:_getCheckpointScale(index)
	local minReward = e.mul(scale, 100)
	return e.max(e.mul(current, scale), minReward)
end

function raceService:_assignPlacement(user: userService.User): number
	local place = #self._placements + 1
	if place <= 3 then
		self._placements[place] = {
			name = user:GetDisplayName(),
			userId = user:GetId(),
		}
		self:_broadcastPlacement(place, self._placements[place])
	end
	return place
end

function raceService:_broadcastPlacement(place: number, entry: { [string]: any } | string)
	if not self.Client.PlacementUpdate then
		return
	end
	local name = entry
	local userId = nil
	if typeof(entry) == "table" then
		name = entry.name
		userId = entry.userId
	end
	local recipients = {}
	for player in pairs(self._participants) do
		if player and player.Parent == players then
			table.insert(recipients, player)
		end
	end
	if #recipients > 0 then
		self.Client.PlacementUpdate:FireFor(recipients, place, name, userId)
	end
end

return raceService
