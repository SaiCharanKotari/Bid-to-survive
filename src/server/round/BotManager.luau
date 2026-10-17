--!strict
-- src/server/round/BotManager.luau
-- Manages companion bot dummy creation, appearance, positioning, bidding AI, and cleanup.

local Workspace = game:GetService("Workspace")

local BotManager = {}
BotManager.__index = BotManager

export type BotData = {
	UserId: number,
	Name: string,
	Money: number,
	Wallet: number?,
	Health: number,
	IsAlive: boolean,
	IsAFK: boolean,
	ParticipationState: string,
	CurrentBid: number,
	SubmitTime: number?,
	Votes: number,
	IsBot: boolean,
	Character: Model?,
}

local activeBots: {BotData} = {}
local gameplayArea: Instance? = nil
local walkway: BasePart? = nil
local gameConfig: any = nil

local BOT_NAMES = {
	"ApeSlayer", "ShadowRunner", "LuckyBids", "AlphaTitan", "RiskHunter",
	"ViperStrike", "CyberGhost", "BlazeWarrior", "EchoPhantom", "IronClaw",
}

function BotManager.Init(config: any, gpArea: Instance, walkPart: BasePart)
	gameConfig = config
	gameplayArea = gpArea
	walkway = walkPart
end

function BotManager.CleanupBots()
	for _, botData in ipairs(activeBots) do
		if botData.Character and botData.Character.Parent then
			botData.Character:Destroy()
		end
	end
	table.clear(activeBots)
end

function BotManager.CreateBotDummy(name: string, id: number, startPos: Vector3, playerData: {[number]: any}): BotData
	local animMaker = Workspace:FindFirstChild("animation-maker")
	local botModel: Model
	if animMaker then
		botModel = animMaker:Clone()
	else
		botModel = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Size = Vector3.new(2, 2, 1)
		part.Parent = botModel
		local hum = Instance.new("Humanoid")
		hum.Parent = botModel
	end

	botModel.Name = name

	for _, c in ipairs(botModel:GetDescendants()) do
		if c:IsA("LuaSourceContainer") or c:IsA("Tool") or c.Name == "PlayPrompt" then
			c:Destroy()
		end
	end

	local bodyColors = botModel:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.TorsoColor3 = Color3.fromRGB(math.random(50, 200), math.random(50, 200), math.random(50, 200))
	end

	botModel:PivotTo(CFrame.new(startPos))
	if gameplayArea then
		botModel.Parent = gameplayArea
	end

	local startMoney = (gameConfig and gameConfig.StartingMoney) or 20.00
	local maxHealth = (gameConfig and gameConfig.MaxHealth) or 100

	local botData: BotData = {
		UserId = id,
		Name = name,
		Money = startMoney,
		Wallet = startMoney,
		Health = maxHealth,
		IsAlive = true,
		IsAFK = false,
		ParticipationState = "Active",
		CurrentBid = 0,
		Votes = 0,
		IsBot = true,
		Character = botModel,
	}

	table.insert(activeBots, botData)
	if playerData then
		playerData[id] = botData
	end
	return botData
end

function BotManager.SetupCompanionBots(targetTotal: number, realEligibleCount: number, playerData: {[number]: any}): {BotData}
	BotManager.CleanupBots()
	local botsNeeded = math.max(0, targetTotal - realEligibleCount)
	if botsNeeded == 0 or not walkway then
		return activeBots
	end

	local wPos = walkway.Position
	for i = 1, botsNeeded do
		local bName = BOT_NAMES[i] or ("Bot_" .. i)
		local bId = -200 - i
		local angle = (i / math.max(1, botsNeeded)) * math.pi * 2
		local radius = 22 + (i % 3) * 14
		local spawnPos = Vector3.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius)
		BotManager.CreateBotDummy(bName, bId, spawnPos, playerData)
	end

	return activeBots
end

function BotManager.ScatterBots()
	if not walkway then return end
	local wPos = walkway.Position
	for i, b in ipairs(activeBots) do
		if b.IsAlive and b.Character then
			local angle = (i / math.max(1, #activeBots)) * math.pi * 2
			local radius = 22 + (i % 3) * 14
			b.Character:PivotTo(CFrame.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius))
		end
	end
end

function BotManager.GenerateBids(livingPlayers: {any})
	for _, d in ipairs(livingPlayers) do
		if d.IsBot and d.IsAlive then
			local walletCents = math.round((d.Money or 20) * 100)
			local maxBCents = math.min(walletCents, math.random(150, 650))
			d.CurrentBid = maxBCents / 100
			d.SubmitTime = math.random(80, 750) / 100
			d.Money = math.max(0, (walletCents - maxBCents) / 100)
			d.Wallet = d.Money
		end
	end
end

function BotManager.ResetParticipation()
	for _, bot in ipairs(activeBots) do
		if bot.IsAlive then
			bot.ParticipationState = "Active"
		end
	end
end

function BotManager.GetActiveBots(): {BotData}
	return activeBots
end

return BotManager
