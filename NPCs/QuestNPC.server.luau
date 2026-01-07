local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local QuestService = require(ServerStorage.Modules.QuestService)

local questRemote = QuestService:GetRemote()

local function findDetector(root: Instance?): ClickDetector?
	if not root then
		return nil
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ClickDetector") then
			return descendant
		end
	end

	return nil
end


local function openDialogueFor(player: Player)
	local status = QuestService.GetStatus(player)

	local buttons = {}

	if status.questActive then
		table.insert(buttons, {
			text = "Abandon Contract",
			action = "AbandonQuest",
			style = "danger",
		})
		table.insert(buttons, {
			text = "Close",
			style = "secondary",
		})

		questRemote:FireClient(player, "OpenDialogue", {
			message = ("Your current contract targets %s.\nEliminate them for %d Gold."):format(status.targetName or "Unknown", status.reward),
			buttons = buttons,
			title = "Quest Giver",
		})
		return
	end

	local cooldownRemaining = status.cooldownRemaining or 0
	if cooldownRemaining > 0 then
		table.insert(buttons, {
			text = "Close",
			style = "secondary",
		})

		questRemote:FireClient(player, "OpenDialogue", {
			message = ("I have no contracts for you yet. Come back in %d seconds."):format(cooldownRemaining),
			buttons = buttons,
			title = "Quest Giver",
		})
		return
	end

	table.insert(buttons, {
		text = "Accept Contract",
		action = "AcceptQuest",
		style = "primary",
	})
	table.insert(buttons, {
		text = "Maybe Later",
		style = "secondary",
	})

	questRemote:FireClient(player, "OpenDialogue", {
		message = ("I have a contract ready. Eliminate the mark I assign you and I'll pay %d Gold. Interested?"):format(status.reward),
		buttons = buttons,
		title = "Quest Giver",
	})
end

local function bindNpcInteractions()
	local liveFolder = Workspace:FindFirstChild("NPCS")
	local questNpc = liveFolder:FindFirstChild("QuestNPC")

	if not questNpc then
		return
	end

	local clickDetector = findDetector(questNpc)

	if clickDetector then
		clickDetector.MouseClick:Connect(openDialogueFor)
	end
end

bindNpcInteractions()

questRemote.OnServerEvent:Connect(function(player: Player, action: string?)
	if action == "AcceptQuest" then
		local success, errorMessage = QuestService.AssignQuest(player)
		if not success and errorMessage then
			questRemote:FireClient(player, "QuestError", {
				message = errorMessage,
			})
		end
	elseif action == "AbandonQuest" then
		QuestService.AbandonQuest(player, "You chose to abandon the contract.")
	else
		questRemote:FireClient(player, "QuestError", {
			message = "??",
		})
	end
end)
