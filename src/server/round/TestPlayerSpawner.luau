--!strict
-- src/server/round/TestPlayerSpawner.luau
-- Authoritative Test Player & Bot Spawning Engine for Bid-to-survive.
-- Spawns fully-rigged R6 Humanoid characters that the game engine treats as real players.
-- Features:
-- 1. Authentic R6 Humanoid Rigs with limbs, HumanoidRootPart, and distinct avatar appearances.
-- 2. Overhead Name, HP Bar & Wallet BillboardGui for in-world live match tracking.
-- 3. Smart Proportional Bidding AI (conserves wallet so matches can run for unlimited rounds).
-- 4. Autonomous Scramble & Dodge AI (unprotected bots actively sprint out of the danger circle).
-- 5. Organic damage & elimination (only taking damage when caught inside red circle and unprotected).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local TestPlayerSpawner = {}
TestPlayerSpawner.__index = TestPlayerSpawner

export type TestPlayerData = {
	UserId: number,
	Name: string,
	DisplayName: string,
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
	IsTestPlayer: boolean,
	Character: Model?,
	Billboard: BillboardGui?,
}

local activeTestPlayers: {TestPlayerData} = {}
local gameplayArea: Instance? = nil
local walkway: BasePart? = nil
local gameConfig: any = nil

local BOT_NAMES = {
	"ApeSlayer", "ShadowRunner", "LuckyBids", "AlphaTitan", "RiskHunter",
	"ViperStrike", "CyberGhost", "BlazeWarrior", "EchoPhantom", "IronClaw",
	"ThunderVolt", "FrostBite", "NeonReaper", "QuantumDash", "ApexPredator",
}

local AVATAR_PALETTES = {
	{ Torso = Color3.fromRGB(35, 115, 230), Legs = Color3.fromRGB(40, 45, 55), Skin = Color3.fromRGB(234, 184, 146) },
	{ Torso = Color3.fromRGB(220, 50, 50),   Legs = Color3.fromRGB(30, 30, 35), Skin = Color3.fromRGB(212, 161, 126) },
	{ Torso = Color3.fromRGB(45, 185, 95),  Legs = Color3.fromRGB(50, 55, 65), Skin = Color3.fromRGB(240, 200, 165) },
	{ Torso = Color3.fromRGB(245, 160, 25), Legs = Color3.fromRGB(35, 35, 40), Skin = Color3.fromRGB(195, 145, 110) },
	{ Torso = Color3.fromRGB(160, 45, 215), Legs = Color3.fromRGB(25, 25, 30), Skin = Color3.fromRGB(225, 175, 135) },
	{ Torso = Color3.fromRGB(30, 195, 205), Legs = Color3.fromRGB(45, 50, 60), Skin = Color3.fromRGB(234, 184, 146) },
	{ Torso = Color3.fromRGB(235, 70, 150), Legs = Color3.fromRGB(35, 40, 50), Skin = Color3.fromRGB(215, 165, 130) },
	{ Torso = Color3.fromRGB(220, 215, 50), Legs = Color3.fromRGB(40, 45, 55), Skin = Color3.fromRGB(240, 200, 165) },
	{ Torso = Color3.fromRGB(90, 100, 120), Legs = Color3.fromRGB(25, 30, 35), Skin = Color3.fromRGB(180, 130, 95) },
	{ Torso = Color3.fromRGB(180, 40, 40),  Legs = Color3.fromRGB(20, 20, 25), Skin = Color3.fromRGB(230, 180, 140) },
}

function TestPlayerSpawner.Init(config: any, gpArea: Instance, walkPart: BasePart)
	gameConfig = config
	gameplayArea = gpArea
	walkway = walkPart
end

function TestPlayerSpawner.CleanupTestPlayers()
	for _, data in ipairs(activeTestPlayers) do
		if data.Character and data.Character.Parent then
			data.Character:Destroy()
		end
	end
	table.clear(activeTestPlayers)
end

-- Builds a clean overhead status billboard for in-world match observation
local function attachOverheadHUD(character: Model, name: string, startHealth: number, startWallet: number): BillboardGui?
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return nil end

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "TestPlayerOverhead"
	bbg.Adornee = head
	bbg.Size = UDim2.new(0, 130, 0, 46)
	bbg.StudsOffset = Vector3.new(0, 2.8, 0)
	bbg.AlwaysOnTop = true
	bbg.MaxDistance = 140
	bbg.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Text = name
	nameLabel.Parent = bbg

	local barBg = Instance.new("Frame")
	barBg.Name = "HPBarBg"
	barBg.Size = UDim2.new(1, -12, 0, 8)
	barBg.Position = UDim2.new(0, 6, 0, 20)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 10, 15)
	barBg.BorderSizePixel = 0
	barBg.Parent = bbg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(math.clamp(startHealth / 100, 0, 1), 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill

	local walletLabel = Instance.new("TextLabel")
	walletLabel.Name = "WalletLabel"
	walletLabel.Size = UDim2.new(1, 0, 0, 14)
	walletLabel.Position = UDim2.new(0, 0, 0, 30)
	walletLabel.BackgroundTransparency = 1
	walletLabel.Font = Enum.Font.GothamBold
	walletLabel.TextSize = 11
	walletLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	walletLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	walletLabel.TextStrokeTransparency = 0.4
	walletLabel.Text = string.format("$%.2f", startWallet)
	walletLabel.Parent = bbg

	return bbg
end

local function updateOverheadHUD(data: TestPlayerData)
	if not data.Billboard or not data.Billboard.Parent then return end
	local barBg = data.Billboard:FindFirstChild("HPBarBg") :: Frame?
	local fill = barBg and barBg:FindFirstChild("Fill") :: Frame?
	local walletLabel = data.Billboard:FindFirstChild("WalletLabel") :: TextLabel?

	if fill then
		local hpRatio = math.clamp(data.Health / 100, 0, 1)
		fill.Size = UDim2.new(hpRatio, 0, 1, 0)
		if hpRatio > 0.5 then
			fill.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		elseif hpRatio > 0.25 then
			fill.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
		else
			fill.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
		end
	end

	if walletLabel then
		walletLabel.Text = string.format("$%.2f", data.Money)
	end
end

-- Creates an authentic, fully articulated R6 Humanoid Character
local function buildR6CharacterModel(name: string, paletteIndex: number, spawnPos: Vector3): Model
	local palette = AVATAR_PALETTES[((paletteIndex - 1) % #AVATAR_PALETTES) + 1]

	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = palette.Skin
	desc.TorsoColor = palette.Torso
	desc.LeftArmColor = palette.Skin
	desc.RightArmColor = palette.Skin
	desc.LeftLegColor = palette.Legs
	desc.RightLegColor = palette.Legs

	local model: Model
	local ok, created = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)

	if ok and created then
		model = created
	else
		-- Fallback manual R6 construct
		model = Instance.new("Model")
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3.new(2, 2, 1)
		hrp.Transparency = 1
		hrp.CanCollide = false
		hrp.Parent = model
		model.PrimaryPart = hrp

		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Size = Vector3.new(2, 2, 1)
		torso.Color = palette.Torso
		torso.Parent = model

		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.Color = palette.Skin
		head.Parent = model

		local hum = Instance.new("Humanoid")
		hum.RigType = Enum.HumanoidRigType.R6
		hum.MaxHealth = 100
		hum.Health = 100
		hum.WalkSpeed = 16
		hum.Parent = model

		local rootJoint = Instance.new("Motor6D")
		rootJoint.Name = "RootJoint"
		rootJoint.Part0 = hrp
		rootJoint.Part1 = torso
		rootJoint.Parent = hrp
	end

	model.Name = name

	-- Ensure humanoid properties are tuned for match play
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = 100
		hum.Health = 100
		hum.WalkSpeed = 16
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Prevent default death sound / prompt collisions
	for _, c in ipairs(model:GetDescendants()) do
		if c:IsA("LuaSourceContainer") or c:IsA("Tool") or c.Name == "PlayPrompt" then
			c:Destroy()
		end
	end

	model:PivotTo(CFrame.new(spawnPos))
	return model
end

function TestPlayerSpawner.CreateTestPlayer(name: string, id: number, paletteIdx: number, startPos: Vector3, playerData: {[number]: any}): TestPlayerData
	local char = buildR6CharacterModel(name, paletteIdx, startPos)

	local startMoney = (gameConfig and gameConfig.StartingMoney) or 20.00
	local maxHealth = (gameConfig and gameConfig.MaxHealth) or 100

	local bbg = attachOverheadHUD(char, name, maxHealth, startMoney)

	char:SetAttribute("UserId", id)
	char:SetAttribute("Name", name)
	char:SetAttribute("DisplayName", name)
	char:SetAttribute("Money", startMoney)
	char:SetAttribute("Wallet", startMoney)
	char:SetAttribute("Health", maxHealth)
	char:SetAttribute("HP", maxHealth)
	char:SetAttribute("IsInGame", true)

	if gameplayArea then
		char.Parent = gameplayArea
	else
		char.Parent = Workspace
	end

	local data: TestPlayerData = {
		UserId = id,
		Name = name,
		DisplayName = name,
		Money = startMoney,
		Wallet = startMoney,
		Health = maxHealth,
		IsAlive = true,
		IsAFK = false,
		ParticipationState = "Active",
		CurrentBid = 0,
		Votes = 0,
		IsBot = true,
		IsTestPlayer = true,
		Character = char,
		Billboard = bbg,
	}

	table.insert(activeTestPlayers, data)
	if playerData then
		playerData[id] = data
	end

	return data
end

function TestPlayerSpawner.SpawnTestPlayers(targetTotal: number, realEligibleCount: number, playerData: {[number]: any}): {TestPlayerData}
	TestPlayerSpawner.CleanupTestPlayers()
	local botsNeeded = math.max(0, targetTotal - realEligibleCount)
	if botsNeeded == 0 or not walkway then
		return activeTestPlayers
	end

	local wPos = walkway.Position
	for i = 1, botsNeeded do
		local bName = BOT_NAMES[i] or ("PlayerBot_" .. i)
		local bId = -100 - i
		local angle = (i / math.max(1, botsNeeded)) * math.pi * 2
		local radius = 22 + (i % 3) * 14
		local spawnPos = Vector3.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius)
		TestPlayerSpawner.CreateTestPlayer(bName, bId, i, spawnPos, playerData)
	end

	print(string.format("[TestPlayerSpawner] 🤖 Spawned %d Authentic R6 Test Players into match! Total participants: %d", botsNeeded, targetTotal))
	return activeTestPlayers
end

-- Smart Proportional Bidding AI: Scales bids to remaining wallet so matches run for unlimited rounds!
function TestPlayerSpawner.GenerateBids(livingPlayers: {any})
	for _, d in ipairs(livingPlayers) do
		if d.IsBot and d.IsAlive then
			local walletCents = math.round((d.Money or 0) * 100)
			local bidCents = 0

			if walletCents >= 1200 then
				-- High wallet: Conservative early bids ($0.50 to $2.25)
				bidCents = math.random(50, 225)
			elseif walletCents >= 500 then
				-- Mid wallet: Strategic bids ($0.30 to $1.50)
				local maxBid = math.min(walletCents, 150)
				bidCents = math.random(30, maxBid)
			elseif walletCents >= 100 then
				-- Low wallet: Budget survival bids ($0.15 to $0.75)
				local maxBid = math.min(walletCents, 75)
				bidCents = math.random(15, maxBid)
			elseif walletCents > 0 then
				-- Critical cents left: Spend remaining change ($0.05 to wallet)
				bidCents = math.random(5, walletCents)
			else
				-- Empty wallet: $0.00 bid (relies purely on physical dodge survival)
				bidCents = 0
			end

			local finalBid = bidCents / 100
			d.CurrentBid = finalBid
			d.SubmitTime = math.random(120, 880) / 100 -- Authentic 1.2s to 8.8s submit delay
			d.Money = math.max(0, (walletCents - bidCents) / 100)
			d.Wallet = d.Money

			if d.Character then
				d.Character:SetAttribute("Money", d.Money)
				d.Character:SetAttribute("Wallet", d.Money)
			end
			updateOverheadHUD(d)
		end
	end
end

-- Autonomous Scramble & Dodge AI: Unprotected test players sprint away from danger circle!
function TestPlayerSpawner.ScrambleTestPlayers(dangerCenter: Vector3, dangerRadius: number)
	if not walkway then return end
	local wPos = walkway.Position
	local walkwayRadius = 48

	for _, d in ipairs(activeTestPlayers) do
		if d.IsAlive and d.Character then
			local char = d.Character
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local isProtected = char:FindFirstChild("SafeBidGlow") ~= nil

			if hum and root and hum.Health > 0 then
				if isProtected then
					-- Protected bots with neon green shield can idle or take small confident steps
					local smallAngle = math.random() * math.pi * 2
					local targetPos = root.Position + Vector3.new(math.cos(smallAngle) * 4, 0, math.sin(smallAngle) * 4)
					hum:MoveTo(targetPos)
				else
					-- UNPROTECTED BOT: Check proximity to danger circle and actively DODGE!
					local flatToDanger = Vector3.new(root.Position.X - dangerCenter.X, 0, root.Position.Z - dangerCenter.Z)
					local distToDanger = flatToDanger.Magnitude

					if distToDanger < (dangerRadius + 14) then
						-- Inside or near blast zone: sprint outward away from danger center towards walkway ring!
						local escapeDir = (distToDanger > 1) and flatToDanger.Unit or Vector3.new(1, 0, 0)
						local escapeTarget = root.Position + (escapeDir * (dangerRadius + 8))

						-- Clamp within walkway boundaries
						local toWalkway = Vector3.new(escapeTarget.X - wPos.X, 0, escapeTarget.Z - wPos.Z)
						if toWalkway.Magnitude > walkwayRadius then
							escapeTarget = Vector3.new(wPos.X, root.Position.Y, wPos.Z) + (toWalkway.Unit * (walkwayRadius - 4))
						end

						hum.WalkSpeed = 22 -- Sprint speed during scramble!
						hum:MoveTo(escapeTarget)
					end
				end
			end
		end
	end
end

-- Repositions living test players along the walkway ring between rounds
function TestPlayerSpawner.ScatterTestPlayers()
	if not walkway then return end
	local wPos = walkway.Position
	for i, d in ipairs(activeTestPlayers) do
		if d.IsAlive and d.Character then
			local hum = d.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 16 end
			local angle = (i / math.max(1, #activeTestPlayers)) * math.pi * 2
			local radius = 22 + (i % 3) * 14
			d.Character:PivotTo(CFrame.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius))
		end
	end
end

-- Applies damage strictly to test players that were caught inside the danger zone and NOT protected
function TestPlayerSpawner.ApplyImpactDamage(hitParticipants: {any}?, dmg: number)
	local hitSet = {}
	if hitParticipants then
		for _, item in ipairs(hitParticipants) do
			hitSet[item] = true
			if typeof(item) == "Instance" then
				hitSet[item.Name] = true
			end
		end
	end

	for _, d in ipairs(activeTestPlayers) do
		if d.IsAlive and d.Character then
			local char = d.Character
			local hum = char:FindFirstChildOfClass("Humanoid")
			local isProtected = (char:FindFirstChild("SafeBidGlow") ~= nil)
			local wasHit = (hitParticipants == nil) or (hitSet[char] or hitSet[char.Name] or hitSet[d.UserId])

			if not isProtected and wasHit and hum and hum.Health > 0 then
				d.Health = math.max(0, d.Health - dmg)
				hum.Health = d.Health
				char:SetAttribute("Health", d.Health)
				char:SetAttribute("HP", d.Health)
				updateOverheadHUD(d)

				if d.Health <= 0 then
					d.IsAlive = false
					d.ParticipationState = "Eliminated"
					char:BreakJoints()
					task.delay(3.5, function()
						if char and char.Parent then
							char:Destroy()
						end
					end)
				end
			end
		end
	end
end

function TestPlayerSpawner.ResetParticipation()
	for _, data in ipairs(activeTestPlayers) do
		if data.IsAlive then
			data.ParticipationState = "Active"
			updateOverheadHUD(data)
		end
	end
end

function TestPlayerSpawner.GetActiveTestPlayers(): {TestPlayerData}
	return activeTestPlayers
end

return TestPlayerSpawner
