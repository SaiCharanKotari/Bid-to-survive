-- ClientUIController: Handles all BID TO SURVIVE UI interactions, Hammer Roulette, HUD, and 4-Column Leaderboard
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Network = ReplicatedStorage:WaitForChild("Network")

local StateChanged = Network:WaitForChild("StateChanged")
local PromptBid = Network:WaitForChild("PromptBid")
local BidSubmitted = Network:WaitForChild("BidSubmitted")
local RankingsRevealed = Network:WaitForChild("RankingsRevealed")
local PromptVote = Network:WaitForChild("PromptVote")
local VoteSubmitted = Network:WaitForChild("VoteSubmitted")
local HammerSmash = Network:WaitForChild("HammerSmash")
local RoundOver = Network:WaitForChild("RoundOver")
local MatchOver = Network:WaitForChild("MatchOver")
local StatsUpdated = Network:WaitForChild("StatsUpdated")

-- RemoteEvent for AFK toggle
local SetAFK = Network:FindFirstChild("SetAFK")
if not SetAFK then
    SetAFK = Instance.new("RemoteEvent")
    SetAFK.Name = "SetAFK"
    SetAFK.Parent = Network
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = script:FindFirstAncestorWhichIsA("ScreenGui") or playerGui:WaitForChild("BidToSurviveUI")

local topBanner = gui:WaitForChild("TopBanner")
local phaseTitle = topBanner:WaitForChild("PhaseTitle")
local timerLabel = topBanner:WaitForChild("TimerLabel")
local infoLabel = topBanner:WaitForChild("InfoLabel")

local statsCard = gui:WaitForChild("StatsCard")
local cashLabel = statsCard:WaitForChild("CashLabel")
local healthBarBg = statsCard:WaitForChild("HealthBarBg")
local healthBarFill = healthBarBg:WaitForChild("Fill")
local healthText = healthBarBg:WaitForChild("HealthText")
local roundLabel = statsCard:WaitForChild("RoundLabel")

local rarityBadge = gui:FindFirstChild("RarityBadge")
local biddingModal = gui:WaitForChild("BiddingModal")
local bidInput = biddingModal:WaitForChild("BidInput")
local submitBtn = biddingModal:WaitForChild("SubmitBtn")
local submittedNotice = biddingModal:WaitForChild("SubmittedNotice")
local quickFrame = biddingModal:WaitForChild("QuickFrame")

local rankingsModal = gui:WaitForChild("RankingsModal")
local voteModal = gui:WaitForChild("VoteModal")
local candidateContainer = voteModal:WaitForChild("CandidateContainer")

local matchOverModal = gui:WaitForChild("MatchOverModal")
local winnerName = matchOverModal:WaitForChild("WinnerName")

local screenFlash = gui:WaitForChild("ScreenFlash")

-- Local State
local CurrentMoney = GameConfig.StartingMoney or 20.00
local CurrentHealth = GameConfig.MaxHealth or 100
local IsAlive = true
local IsAFK = true -- Default ON as requested
local CurrentPhaseDeadline = 0
local HasSubmitted = false
local IsRoulettePlaying = false

-- Known verified base hammer asset (Rare is 100% loaded and verified on Roblox CDN)
local VERIFIED_BASE_HAMMER = "rbxassetid://130593511073820"
local PendingAssets = {}

-- Preload probe for all rarity assets
task.spawn(function()
    for _, rarityName in ipairs(GameConfig.RarityOrder) do
        local rData = GameConfig.HammerRarities[rarityName]
        if rData and rData.AssetId then
            local testImg = Instance.new("ImageLabel")
            testImg.Image = rData.AssetId
            ContentProvider:PreloadAsync({testImg}, function(assetId, status)
                if status == Enum.AssetFetchStatus.Failure then
                    PendingAssets[assetId] = true
                end
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- 1. HUD STYLING (HEALTH BAR, MONEY BOX & AFK BUTTON)
--------------------------------------------------------------------------------
statsCard.BackgroundTransparency = 1
local oldCardStroke = statsCard:FindFirstChildOfClass("UIStroke")
if oldCardStroke then oldCardStroke:Destroy() end
local oldCardCorner = statsCard:FindFirstChildOfClass("UICorner")
if oldCardCorner then oldCardCorner:Destroy() end

statsCard.Size = UDim2.new(0, 240, 0, 95)
statsCard.Position = UDim2.new(0, 20, 1, -115)

-- Compact black money box (NO coin icon, text-only balance)
cashLabel.Size = UDim2.new(0, 140, 0, 28)
cashLabel.Position = UDim2.new(0, 0, 0, 0)
cashLabel.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
cashLabel.BackgroundTransparency = 0
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 15
cashLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
cashLabel.TextXAlignment = Enum.TextXAlignment.Center
cashLabel.Text = string.format("$%.2f", CurrentMoney)

local cashCorner = cashLabel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
cashCorner.CornerRadius = UDim.new(0, 4)
cashCorner.Parent = cashLabel

local cashStroke = cashLabel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
cashStroke.Color = Color3.fromRGB(36, 40, 52)
cashStroke.Thickness = 1
cashStroke.Parent = cashLabel

-- Noticeably taller rectangular red health bar (26px)
healthBarBg.Size = UDim2.new(0, 220, 0, 26)
healthBarBg.Position = UDim2.new(0, 0, 0, 34)
healthBarBg.BackgroundColor3 = Color3.fromRGB(48, 14, 18)
healthBarBg.BackgroundTransparency = 0

local hpBgCorner = healthBarBg:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
hpBgCorner.CornerRadius = UDim.new(0, 4)
hpBgCorner.Parent = healthBarBg

local hpBgStroke = healthBarBg:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
hpBgStroke.Color = Color3.fromRGB(72, 22, 28)
hpBgStroke.Thickness = 1
hpBgStroke.Parent = healthBarBg

-- Animated Fill
healthBarFill.BackgroundColor3 = Color3.fromRGB(225, 40, 50)
local fillCorner = healthBarFill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 3)
fillCorner.Parent = healthBarFill

-- Centered bold white text 100 / 100
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.Position = UDim2.new(0, 0, 0, 0)
healthText.BackgroundTransparency = 1
healthText.Font = Enum.Font.GothamBold
healthText.TextSize = 13
healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
healthText.TextStrokeTransparency = 0.3
healthText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
healthText.TextXAlignment = Enum.TextXAlignment.Center
healthText.TextYAlignment = Enum.TextYAlignment.Center
healthText.ZIndex = 5
healthText.Text = string.format("%d / 100", CurrentHealth)

-- Round Label
roundLabel.Position = UDim2.new(0, 0, 0, 66)
roundLabel.Size = UDim2.new(0, 220, 0, 18)
roundLabel.TextXAlignment = Enum.TextXAlignment.Left
roundLabel.TextColor3 = Color3.fromRGB(150, 165, 185)
roundLabel.Font = Enum.Font.GothamMedium
roundLabel.TextSize = 12

if rarityBadge then
    rarityBadge.Visible = false
end

--------------------------------------------------------------------------------
-- AFK BUTTON ON LEFT SIDE (DEFAULT ON)
--------------------------------------------------------------------------------
local afkButton = gui:FindFirstChild("AFKButton") or Instance.new("TextButton")
afkButton.Name = "AFKButton"
afkButton.Size = UDim2.new(0, 175, 0, 36)
afkButton.Position = UDim2.new(0, 20, 1, -165)
afkButton.BackgroundColor3 = Color3.fromRGB(24, 18, 14)
afkButton.Font = Enum.Font.GothamBold
afkButton.TextSize = 13
afkButton.ZIndex = 20
afkButton.AutoButtonColor = false

local afkCorner = afkButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
afkCorner.CornerRadius = UDim.new(0, 6)
afkCorner.Parent = afkButton

local afkStroke = afkButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
afkStroke.Color = Color3.fromRGB(240, 150, 30)
afkStroke.Thickness = 1.5
afkStroke.Parent = afkButton

local function UpdateAFKVisual()
    if IsAFK then
        afkButton.BackgroundColor3 = Color3.fromRGB(28, 18, 12)
        afkButton.TextColor3 = Color3.fromRGB(255, 175, 50)
        afkButton.Text = "💤 AFK: ON (Click to Play)"
        afkStroke.Color = Color3.fromRGB(240, 150, 30)
    else
        afkButton.BackgroundColor3 = Color3.fromRGB(14, 28, 18)
        afkButton.TextColor3 = Color3.fromRGB(60, 230, 110)
        afkButton.Text = "⚔️ READY (In Game)"
        afkStroke.Color = Color3.fromRGB(40, 210, 95)
    end
end

UpdateAFKVisual()
afkButton.Parent = gui

-- Initialize server state to AFK ON
task.spawn(function()
    task.wait(0.5)
    SetAFK:FireServer(true)
end)

afkButton.MouseButton1Click:Connect(function()
    IsAFK = not IsAFK
    UpdateAFKVisual()
    SetAFK:FireServer(IsAFK)
end)

--------------------------------------------------------------------------------
-- REOPEN BUTTONS (MIDDLE AND LITTLE TOP)
--------------------------------------------------------------------------------
local reopenContainer = gui:FindFirstChild("ReopenContainer") or Instance.new("Frame")
reopenContainer.Name = "ReopenContainer"
reopenContainer.Size = UDim2.new(0, 320, 0, 34)
reopenContainer.Position = UDim2.new(0.5, -160, 0, 96)
reopenContainer.BackgroundTransparency = 1
reopenContainer.ZIndex = 35
reopenContainer.Parent = gui

local reopenBidBtn = reopenContainer:FindFirstChild("ReopenBidBtn") or Instance.new("TextButton")
reopenBidBtn.Name = "ReopenBidBtn"
reopenBidBtn.Size = UDim2.new(0, 150, 0, 32)
reopenBidBtn.Position = UDim2.new(0, 0, 0, 0)
reopenBidBtn.BackgroundColor3 = Color3.fromRGB(16, 24, 20)
reopenBidBtn.Text = "💵 OPEN BID CARD"
reopenBidBtn.TextColor3 = Color3.fromRGB(60, 220, 110)
reopenBidBtn.Font = Enum.Font.GothamBold
reopenBidBtn.TextSize = 12
reopenBidBtn.Visible = false
reopenBidBtn.ZIndex = 36
local rbbCorner = Instance.new("UICorner")
rbbCorner.CornerRadius = UDim.new(0, 6)
rbbCorner.Parent = reopenBidBtn
local rbbStroke = Instance.new("UIStroke")
rbbStroke.Color = Color3.fromRGB(40, 180, 90)
rbbStroke.Thickness = 1
rbbStroke.Parent = reopenBidBtn
reopenBidBtn.Parent = reopenContainer

local reopenRankBtn = reopenContainer:FindFirstChild("ReopenRankBtn") or Instance.new("TextButton")
reopenRankBtn.Name = "ReopenRankBtn"
reopenRankBtn.Size = UDim2.new(0, 150, 0, 32)
reopenRankBtn.Position = UDim2.new(0, 160, 0, 0)
reopenRankBtn.BackgroundColor3 = Color3.fromRGB(16, 22, 32)
reopenRankBtn.Text = "🏆 LEADERBOARD"
reopenRankBtn.TextColor3 = Color3.fromRGB(0, 210, 255)
reopenRankBtn.Font = Enum.Font.GothamBold
reopenRankBtn.TextSize = 12
reopenRankBtn.Visible = false
reopenRankBtn.ZIndex = 36
local rrbCorner = Instance.new("UICorner")
rrbCorner.CornerRadius = UDim.new(0, 6)
rrbCorner.Parent = reopenRankBtn
local rrbStroke = Instance.new("UIStroke")
rrbStroke.Color = Color3.fromRGB(0, 180, 220)
rrbStroke.Thickness = 1
rrbStroke.Parent = reopenRankBtn
reopenRankBtn.Parent = reopenContainer

reopenBidBtn.MouseButton1Click:Connect(function()
    biddingModal.Visible = true
    reopenBidBtn.Visible = false
end)

reopenRankBtn.MouseButton1Click:Connect(function()
    rankingsModal.Visible = true
    reopenRankBtn.Visible = false
end)

--------------------------------------------------------------------------------
-- 2. HAMMER ROULETTE (GUARANTEED 100% VISIBLE WITH WORKING ASSET FALLBACK)
--------------------------------------------------------------------------------
local rouletteContainer = gui:FindFirstChild("RouletteContainer") or Instance.new("Frame")
rouletteContainer.Name = "RouletteContainer"
rouletteContainer.Size = UDim2.new(0, 340, 0, 340)
rouletteContainer.Position = UDim2.new(0.5, -170, 0.42, -170)
rouletteContainer.BackgroundTransparency = 1
rouletteContainer.Visible = false
rouletteContainer.ZIndex = 30
rouletteContainer.Parent = gui

local glowHalo = rouletteContainer:FindFirstChild("GlowHalo") or Instance.new("ImageLabel")
glowHalo.Name = "GlowHalo"
glowHalo.Size = UDim2.new(0, 280, 0, 280)
glowHalo.Position = UDim2.new(0.5, -140, 0, 5)
glowHalo.BackgroundTransparency = 1
glowHalo.Image = "rbxassetid://5028857084"
glowHalo.ImageTransparency = 0.4
glowHalo.ZIndex = 31
glowHalo.Parent = rouletteContainer

local hammerIcon = rouletteContainer:FindFirstChild("HammerIcon") or Instance.new("ImageLabel")
hammerIcon.Name = "HammerIcon"
hammerIcon.Size = UDim2.new(0, 220, 0, 220)
hammerIcon.Position = UDim2.new(0.5, -110, 0, 30)
hammerIcon.BackgroundTransparency = 1
hammerIcon.ScaleType = Enum.ScaleType.Fit
hammerIcon.ZIndex = 33
hammerIcon.Parent = rouletteContainer

local rarityTitle = rouletteContainer:FindFirstChild("RarityTitle") or Instance.new("TextLabel")
rarityTitle.Name = "RarityTitle"
rarityTitle.Size = UDim2.new(1, 0, 0, 32)
rarityTitle.Position = UDim2.new(0, 0, 0, 255)
rarityTitle.BackgroundTransparency = 1
rarityTitle.Font = Enum.Font.GothamBlack
rarityTitle.TextSize = 24
rarityTitle.TextXAlignment = Enum.TextXAlignment.Center
rarityTitle.TextStrokeTransparency = 0.25
rarityTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
rarityTitle.ZIndex = 33
rarityTitle.Parent = rouletteContainer

local damageTitle = rouletteContainer:FindFirstChild("DamageTitle") or Instance.new("TextLabel")
damageTitle.Name = "DamageTitle"
damageTitle.Size = UDim2.new(1, 0, 0, 22)
damageTitle.Position = UDim2.new(0, 0, 0, 288)
damageTitle.BackgroundTransparency = 1
damageTitle.Font = Enum.Font.GothamBold
damageTitle.TextSize = 16
damageTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
damageTitle.TextStrokeTransparency = 0.35
damageTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
damageTitle.TextXAlignment = Enum.TextXAlignment.Center
damageTitle.ZIndex = 33
damageTitle.Parent = rouletteContainer

local function SetHammerVisual(rarityData)
    if not rarityData then return end
    
    -- If the specific asset failed preload or is pending moderation, seamlessly fall back to verified base asset
    local assetId = rarityData.AssetId
    if not assetId or assetId == "" or PendingAssets[assetId] then
        assetId = VERIFIED_BASE_HAMMER
    end
    
    hammerIcon.Image = assetId
    -- Color tint ensures every single tier is vividly distinguished
    hammerIcon.ImageColor3 = rarityData.GlowColor or rarityData.Color or Color3.fromRGB(255, 255, 255)
    glowHalo.ImageColor3 = rarityData.GlowColor or rarityData.Color or Color3.fromRGB(255, 255, 255)
    rarityTitle.Text = string.format("🔨 %s HAMMER", (rarityData.Name or "COMMON"):upper())
    rarityTitle.TextColor3 = rarityData.GlowColor or rarityData.Color or Color3.fromRGB(255, 255, 255)
    damageTitle.Text = string.format("DEALS %d%% HP DAMAGE", rarityData.DamagePercent or 30)
end

local function PlayHammerRoulette(targetRarity, totalDuration)
    if IsRoulettePlaying then return end
    IsRoulettePlaying = true
    
    rouletteContainer.Visible = true
    glowHalo.ImageTransparency = 0.4
    hammerIcon.ImageTransparency = 0
    rarityTitle.TextTransparency = 0
    damageTitle.TextTransparency = 0
    
    local rarities = GameConfig.GetRarityList()
    local delays = {
        0.10, 0.10, 0.11, 0.11, 0.12, 0.13, 0.14, 0.16,
        0.18, 0.20, 0.23, 0.27, 0.31, 0.36, 0.42, 0.50,
        0.60, 0.72, 0.85
    }
    
    local currentIdx = 1
    for i, delay in ipairs(delays) do
        currentIdx = (currentIdx % #rarities) + 1
        local r = rarities[currentIdx]
        SetHammerVisual(r)
        
        local tiltAngle = (i % 2 == 0) and 4 or -4
        hammerIcon.Rotation = tiltAngle
        
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 235, 0, 235),
            Position = UDim2.new(0.5, -117, 0, 22)
        }):Play()
        
        task.wait(delay * 0.5)
        
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 220, 0, 220),
            Position = UDim2.new(0.5, -110, 0, 30)
        }):Play()
        
        task.wait(delay * 0.5)
    end
    
    -- Stop EXACTLY on the server-authoritative rarity
    SetHammerVisual(targetRarity)
    hammerIcon.Rotation = 0
    
    TweenService:Create(hammerIcon, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 260, 0, 260),
        Position = UDim2.new(0.5, -130, 0, 10)
    }):Play()
    
    TweenService:Create(glowHalo, TweenInfo.new(0.35), {
        ImageTransparency = 0.05,
        Size = UDim2.new(0, 320, 0, 320),
        Position = UDim2.new(0.5, -160, 0, -15)
    }):Play()
    
    task.wait(1.5)
    
    TweenService:Create(hammerIcon, TweenInfo.new(0.4), {
        ImageTransparency = 1,
        Size = UDim2.new(0, 190, 0, 190)
    }):Play()
    TweenService:Create(glowHalo, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
    TweenService:Create(rarityTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    TweenService:Create(damageTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    
    task.wait(0.4)
    rouletteContainer.Visible = false
    IsRoulettePlaying = false
end

--------------------------------------------------------------------------------
-- 3. FRAME-ACCURATE AUTHORITATIVE COUNTDOWN TICKER
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    if CurrentPhaseDeadline > 0 then
        local remaining = math.max(0, math.ceil(CurrentPhaseDeadline - os.clock()))
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        timerLabel.Text = string.format("%02d:%02d", mins, secs)
    else
        timerLabel.Text = "00:00"
    end
end)

--------------------------------------------------------------------------------
-- 4. STATS SYNC
--------------------------------------------------------------------------------
StatsUpdated.OnClientEvent:Connect(function(stats)
    local oldHealth = CurrentHealth
    CurrentMoney = stats.Money or CurrentMoney
    CurrentHealth = stats.Health or CurrentHealth
    IsAlive = (stats.IsAlive ~= nil) and stats.IsAlive or IsAlive
    
    cashLabel.Text = string.format("$%.2f", CurrentMoney)
    
    local hpPct = math.clamp(CurrentHealth / 100, 0, 1)
    TweenService:Create(healthBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(hpPct, 0, 1, 0)
    }):Play()
    healthText.Text = string.format("%d / 100", CurrentHealth)
    
    if CurrentHealth < oldHealth then
        screenFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        screenFlash.BackgroundTransparency = 0.45
        TweenService:Create(screenFlash, TweenInfo.new(0.5), {
            BackgroundTransparency = 1
        }):Play()
    end
end)

--------------------------------------------------------------------------------
-- 5. PHASE STATE HANDLER
--------------------------------------------------------------------------------
StateChanged.OnClientEvent:Connect(function(data)
    local phase = data.Phase
    local round = data.Round or 1
    local rarity = data.Rarity
    local living = data.LivingCount or 1
    
    CurrentPhaseDeadline = data.Deadline or (os.clock() + (data.Duration or 0))
    roundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
    
    -- Auto-hide reopen buttons when switching phases
    reopenBidBtn.Visible = false
    reopenRankBtn.Visible = false
    
    if phase == "Intermission" then
        topBanner.Visible = true
        phaseTitle.Text = "LOBBY COUNTDOWN"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Match starting shortly... Toggle AFK to enter play area"
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        matchOverModal.Visible = false
        rouletteContainer.Visible = false
        
    elseif phase == "Phase1_Spawn" then
        topBanner.Visible = true
        phaseTitle.Text = string.format("ROUND %d — HAMMER REVEAL", round)
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "Deciding this round's executioner hammer..."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        
        if rarity then
            task.spawn(function()
                PlayHammerRoulette(rarity, data.RouletteDuration or 6.0)
            end)
        end
        
    elseif phase == "Phase2_Vote" then
        topBanner.Visible = true
        phaseTitle.Text = "PHASE 2 — ANONYMOUS VOTE"
        phaseTitle.TextColor3 = Color3.fromRGB(200, 120, 255)
        infoLabel.Text = "Eliminated spectators are voting to expose 1 player's bid!"
        rouletteContainer.Visible = false
        
    elseif phase == "Phase3_Bid" then
        topBanner.Visible = true
        phaseTitle.Text = "PHASE 3 — BID FOR SURVIVAL"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 170, 0)
        rouletteContainer.Visible = false
        if data.ExposedPlayer then
            infoLabel.Text = string.format("⚠️ ALERT: %s was voted! Their bid will be EXPOSED!", data.ExposedPlayer)
            infoLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        else
            infoLabel.Text = "Enter your secret bid! Top 50% glow neon green and survive!"
            infoLabel.TextColor3 = Color3.fromRGB(160, 175, 200)
        end
        
    elseif phase == "Phase4_Reveal" then
        topBanner.Visible = false
        biddingModal.Visible = false
        
    elseif phase == "Phase5_Scramble" then
        topBanner.Visible = true
        rankingsModal.Visible = false
        biddingModal.Visible = false
        phaseTitle.Text = "PHASE 5 — NEON SHIELD ACTIVE!"
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "WINNING BIDDERS GLOW NEON GREEN AND ARE SHIELDED FROM DAMAGE!"
        
    elseif phase == "Phase6_Smash" then
        topBanner.Visible = true
        phaseTitle.Text = "PHASE 6 — HAMMER SMASH!"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 50, 50)
        infoLabel.Text = "BRACE FOR IMPACT! NON-GLOWING PLAYERS TAKE DAMAGE!"
        
    elseif phase == "Phase7_Settlement" then
        topBanner.Visible = true
        phaseTitle.Text = "PHASE 7 — SETTLEMENT"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Bids processed. Checking survival status..."
        
    elseif phase == "MatchOver" then
        topBanner.Visible = true
        phaseTitle.Text = "MATCH OVER"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Match concluded."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        rouletteContainer.Visible = false
    end
end)

--------------------------------------------------------------------------------
-- 6. BIDDING MODAL (WITH RED X CLOSE BUTTON & REOPEN BUTTON)
--------------------------------------------------------------------------------
-- Attach Red X Close Button to BiddingModal
local closeBidBtn = biddingModal:FindFirstChild("CloseBidBtn") or Instance.new("TextButton")
closeBidBtn.Name = "CloseBidBtn"
closeBidBtn.Size = UDim2.new(0, 26, 0, 26)
closeBidBtn.Position = UDim2.new(1, -34, 0, 8)
closeBidBtn.BackgroundColor3 = Color3.fromRGB(220, 45, 55)
closeBidBtn.Text = "✕"
closeBidBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBidBtn.Font = Enum.Font.GothamBold
closeBidBtn.TextSize = 14
closeBidBtn.ZIndex = 25
local cbbCorner = Instance.new("UICorner")
cbbCorner.CornerRadius = UDim.new(0, 13)
cbbCorner.Parent = closeBidBtn
closeBidBtn.Parent = biddingModal

closeBidBtn.MouseButton1Click:Connect(function()
    biddingModal.Visible = false
    reopenBidBtn.Visible = true
end)

PromptBid.OnClientEvent:Connect(function(data)
    if not IsAlive or IsAFK then return end
    HasSubmitted = false
    bidInput.Text = ""
    submittedNotice.Text = ""
    submitBtn.Text = "SUBMIT BID"
    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 175, 90)
    biddingModal.Visible = true
    reopenBidBtn.Visible = false
end)

local function setBidFraction(frac)
    local amt = math.floor((CurrentMoney * frac) * 100) / 100
    bidInput.Text = string.format("%.2f", amt)
end

for _, btn in ipairs(quickFrame:GetChildren()) do
    if btn:IsA("TextButton") then
        btn.MouseButton1Click:Connect(function()
            if btn.Text == "25%" then setBidFraction(0.25)
            elseif btn.Text == "50%" then setBidFraction(0.50)
            elseif btn.Text == "75%" then setBidFraction(0.75)
            elseif btn.Text == "MAX" then setBidFraction(1.00)
            elseif btn.Text == "CLEAR" then bidInput.Text = "0.00" end
        end)
    end
end

submitBtn.MouseButton1Click:Connect(function()
    if HasSubmitted then return end
    local val = tonumber(bidInput.Text) or 0
    val = math.clamp(val, 0, CurrentMoney)
    val = math.floor(val * 100) / 100
    
    HasSubmitted = true
    BidSubmitted:FireServer(val)
    
    submitBtn.Text = "BID SUBMITTED!"
    submitBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 72)
    submittedNotice.Text = string.format("Secret Bid Registered: $%.2f", val)
end)

--------------------------------------------------------------------------------
-- 7. LEADERBOARD: PREMIUM CONTENT-ADAPTIVE 4-COLUMN TABLE WITH RED X
--------------------------------------------------------------------------------
-- Columns: SI.NO | PLAYER NAME | BID | TIME
RankingsRevealed.OnClientEvent:Connect(function(data)
    topBanner.Visible = false
    
    local allBidders = {}
    local safeCount = data.SafeCount or 1
    for _, p in ipairs(data.TopBidders or {}) do table.insert(allBidders, p) end
    for _, p in ipairs(data.BottomBidders or {}) do table.insert(allBidders, p) end
    
    local rowCount = #allBidders
    local rowHeight = 36
    local rowPadding = 4
    local tableContentHeight = rowCount * (rowHeight + rowPadding)
    
    local desiredHeight = 96 + tableContentHeight + 16
    local modalHeight = math.clamp(desiredHeight, 220, 390)
    
    rankingsModal.Size = UDim2.new(0, 580, 0, modalHeight)
    rankingsModal.Position = UDim2.new(0.5, -290, 0.5, -modalHeight / 2)
    rankingsModal.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
    rankingsModal.BackgroundTransparency = 0
    
    local mCorner = rankingsModal:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    mCorner.CornerRadius = UDim.new(0, 6)
    mCorner.Parent = rankingsModal
    
    local mStroke = rankingsModal:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    mStroke.Color = Color3.fromRGB(36, 40, 52)
    mStroke.Thickness = 1
    mStroke.Parent = rankingsModal
    
    -- Red X Close Button for RankingsModal
    local closeRankBtn = rankingsModal:FindFirstChild("CloseRankBtn") or Instance.new("TextButton")
    closeRankBtn.Name = "CloseRankBtn"
    closeRankBtn.Size = UDim2.new(0, 26, 0, 26)
    closeRankBtn.Position = UDim2.new(1, -34, 0, 8)
    closeRankBtn.BackgroundColor3 = Color3.fromRGB(220, 45, 55)
    closeRankBtn.Text = "✕"
    closeRankBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeRankBtn.Font = Enum.Font.GothamBold
    closeRankBtn.TextSize = 14
    closeRankBtn.ZIndex = 30
    local crbCorner = Instance.new("UICorner")
    crbCorner.CornerRadius = UDim.new(0, 13)
    crbCorner.Parent = closeRankBtn
    closeRankBtn.Parent = rankingsModal
    
    closeRankBtn.MouseButton1Click:Connect(function()
        rankingsModal.Visible = false
        reopenRankBtn.Visible = true
    end)
    
    -- Clear previous dynamic contents
    for _, child in ipairs(rankingsModal:GetChildren()) do
        if child.Name == "HeaderFrame" or child.Name == "LeaderboardScroll" or child.Name == "TitleHeader" then
            child:Destroy()
        elseif child:IsA("ScrollingFrame") or (child:IsA("TextLabel") and child.Name ~= "TitleHeader") then
            child.Visible = false
        end
    end
    
    -- Integrated Title Header Container
    local titleHeader = Instance.new("Frame")
    titleHeader.Name = "TitleHeader"
    titleHeader.Size = UDim2.new(1, -60, 0, 50)
    titleHeader.Position = UDim2.new(0, 12, 0, 10)
    titleHeader.BackgroundTransparency = 1
    titleHeader.Parent = rankingsModal
    
    -- Phase Badge (Cyan Pill)
    local phaseBadge = Instance.new("Frame")
    phaseBadge.Size = UDim2.new(0, 175, 0, 20)
    phaseBadge.Position = UDim2.new(0, 0, 0, 0)
    phaseBadge.BackgroundColor3 = Color3.fromRGB(18, 32, 42)
    local pbCorner = Instance.new("UICorner")
    pbCorner.CornerRadius = UDim.new(0, 4)
    pbCorner.Parent = phaseBadge
    local pbStroke = Instance.new("UIStroke")
    pbStroke.Color = Color3.fromRGB(0, 180, 220)
    pbStroke.Thickness = 1
    pbStroke.Parent = phaseBadge
    
    local pbText = Instance.new("TextLabel")
    pbText.Size = UDim2.new(1, 0, 1, 0)
    pbText.BackgroundTransparency = 1
    pbText.Text = "PHASE 4 • BID RANKINGS"
    pbText.Font = Enum.Font.GothamBold
    pbText.TextSize = 10
    pbText.TextColor3 = Color3.fromRGB(0, 210, 255)
    pbText.TextXAlignment = Enum.TextXAlignment.Center
    pbText.Parent = phaseBadge
    phaseBadge.Parent = titleHeader
    
    -- Main Leaderboard Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 22)
    titleLabel.Position = UDim2.new(0, 0, 0, 24)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "SURVIVAL BID LEADERBOARD"
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextSize = 16
    titleLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleHeader
    
    -- Subtitle explaining rules
    local subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, 0, 0, 16)
    subLabel.Position = UDim2.new(0, 0, 0, 46)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "Top 50% glow neon green & survive • Earliest submission wins tie-breakers"
    subLabel.Font = Enum.Font.GothamMedium
    subLabel.TextSize = 11
    subLabel.TextColor3 = Color3.fromRGB(150, 165, 185)
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.Parent = titleHeader
    
    -- Table Header Frame: SI.NO | PLAYER NAME | BID | TIME
    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "HeaderFrame"
    headerFrame.Size = UDim2.new(1, -24, 0, 26)
    headerFrame.Position = UDim2.new(0, 12, 0, 68)
    headerFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    headerFrame.BorderSizePixel = 0
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 4)
    hCorner.Parent = headerFrame
    
    local function makeHeaderCell(text, size, pos, align)
        local hCell = Instance.new("TextLabel")
        hCell.Size = size
        hCell.Position = pos
        hCell.BackgroundTransparency = 1
        hCell.Text = text
        hCell.Font = Enum.Font.GothamBold
        hCell.TextSize = 11
        hCell.TextColor3 = Color3.fromRGB(150, 160, 180)
        hCell.TextXAlignment = align
        hCell.Parent = headerFrame
        return hCell
    end
    
    makeHeaderCell("SI.NO", UDim2.new(0.10, 0, 1, 0), UDim2.new(0, 6, 0, 0), Enum.TextXAlignment.Center)
    makeHeaderCell("PLAYER NAME", UDim2.new(0.50, -12, 1, 0), UDim2.new(0.10, 12, 0, 0), Enum.TextXAlignment.Left)
    makeHeaderCell("BID", UDim2.new(0.20, -10, 1, 0), UDim2.new(0.60, 0, 0, 0), Enum.TextXAlignment.Right)
    makeHeaderCell("TIME", UDim2.new(0.20, -12, 1, 0), UDim2.new(0.80, 0, 0, 0), Enum.TextXAlignment.Right)
    headerFrame.Parent = rankingsModal
    
    -- Scrolling Container for Rows
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "LeaderboardScroll"
    scroll.Size = UDim2.new(1, -24, 1, -104)
    scroll.Position = UDim2.new(0, 12, 0, 98)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = (desiredHeight > 390) and 4 or 0
    scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 68, 85)
    scroll.ScrollingEnabled = (desiredHeight > 390)
    scroll.CanvasSize = UDim2.new(0, 0, 0, tableContentHeight)
    
    local uiList = Instance.new("UIListLayout")
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Padding = UDim.new(0, rowPadding)
    uiList.Parent = scroll
    
    for i, p in ipairs(allBidders) do
        local isSafe = (i <= safeCount)
        local row = Instance.new("Frame")
        row.Name = "Row_" .. i
        row.Size = UDim2.new(1, (desiredHeight > 390) and -8 or 0, 0, rowHeight)
        row.LayoutOrder = i
        row.BorderSizePixel = 0
        row.BackgroundColor3 = isSafe and Color3.fromRGB(16, 22, 26) or Color3.fromRGB(22, 16, 20)
        
        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 4)
        rCorner.Parent = row
        
        local rStroke = Instance.new("UIStroke")
        rStroke.Color = isSafe and Color3.fromRGB(30, 52, 40) or Color3.fromRGB(48, 28, 34)
        rStroke.Thickness = 1
        rStroke.Parent = row
        
        -- Col 1: SI.NO Rank Pill (#1, #2...)
        local c1 = Instance.new("TextLabel")
        c1.Size = UDim2.new(0.10, 0, 1, 0)
        c1.Position = UDim2.new(0, 6, 0, 0)
        c1.BackgroundTransparency = 1
        c1.Text = "#" .. tostring(i)
        c1.Font = Enum.Font.GothamBold
        c1.TextSize = 13
        c1.TextColor3 = (i == 1) and Color3.fromRGB(255, 215, 0) or (isSafe and Color3.fromRGB(60, 220, 110) or Color3.fromRGB(255, 90, 100))
        c1.TextXAlignment = Enum.TextXAlignment.Center
        c1.Parent = row
        
        -- Col 2: Real Roblox Username / Display Name
        local c2 = Instance.new("TextLabel")
        c2.Size = UDim2.new(0.50, -12, 1, 0)
        c2.Position = UDim2.new(0.10, 12, 0, 0)
        c2.BackgroundTransparency = 1
        c2.Text = p.Name or "Unknown"
        c2.Font = Enum.Font.GothamBold
        c2.TextSize = 13
        c2.TextColor3 = Color3.fromRGB(240, 245, 255)
        c2.TextXAlignment = Enum.TextXAlignment.Left
        c2.Parent = row
        
        -- Col 3: BID (Right aligned, Gold $X.XX)
        local c3 = Instance.new("TextLabel")
        c3.Size = UDim2.new(0.20, -10, 1, 0)
        c3.Position = UDim2.new(0.60, 0, 0, 0)
        c3.BackgroundTransparency = 1
        c3.Text = string.format("$%.2f", p.CurrentBid or 0)
        c3.Font = Enum.Font.GothamBlack
        c3.TextSize = 13
        c3.TextColor3 = Color3.fromRGB(255, 210, 60)
        c3.TextXAlignment = Enum.TextXAlignment.Right
        c3.Parent = row
        
        -- Col 4: TIME (Right aligned, Slate/Cyan Y.YYs)
        local c4 = Instance.new("TextLabel")
        c4.Size = UDim2.new(0.20, -12, 1, 0)
        c4.Position = UDim2.new(0.80, 0, 0, 0)
        c4.BackgroundTransparency = 1
        local elapsed = p.SubmitTime or 10.00
        c4.Text = string.format("%.2fs", elapsed)
        c4.Font = Enum.Font.GothamMedium
        c4.TextSize = 13
        c4.TextColor3 = Color3.fromRGB(160, 185, 215)
        c4.TextXAlignment = Enum.TextXAlignment.Right
        c4.Parent = row
        
        row.Parent = scroll
    end
    
    scroll.Parent = rankingsModal
    rankingsModal.Visible = true
    reopenRankBtn.Visible = false
end)

--------------------------------------------------------------------------------
-- 8. SPECTATOR VOTE POPULATOR
--------------------------------------------------------------------------------
PromptVote.OnClientEvent:Connect(function(data)
    if IsAlive or IsAFK then return end
    for _, c in ipairs(candidateContainer:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    
    for _, candidate in ipairs(data.Candidates or {}) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(40, 32, 60)
        local cr = Instance.new("UICorner")
        cr.CornerRadius = UDim.new(0, 8)
        cr.Parent = row
        
        local nameLab = Instance.new("TextLabel")
        nameLab.Size = UDim2.new(1, -90, 1, 0)
        nameLab.Position = UDim2.new(0, 10, 0, 0)
        nameLab.BackgroundTransparency = 1
        nameLab.Text = candidate.Name
        nameLab.TextColor3 = Color3.fromRGB(240, 240, 255)
        nameLab.Font = Enum.Font.GothamBold
        nameLab.TextSize = 14
        nameLab.TextXAlignment = Enum.TextXAlignment.Left
        nameLab.Parent = row
        
        local voteBtn = Instance.new("TextButton")
        voteBtn.Size = UDim2.new(0, 75, 0, 28)
        voteBtn.Position = UDim2.new(1, -85, 0.5, -14)
        voteBtn.BackgroundColor3 = Color3.fromRGB(150, 70, 255)
        local cBtn = Instance.new("UICorner")
        cBtn.CornerRadius = UDim.new(0, 6)
        cBtn.Parent = voteBtn
        voteBtn.Text = "EXPOSE"
        voteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        voteBtn.Font = Enum.Font.GothamBold
        voteBtn.TextSize = 12
        voteBtn.Parent = row
        
        voteBtn.MouseButton1Click:Connect(function()
            VoteSubmitted:FireServer(candidate.UserId)
            voteModal.Visible = false
        end)
        
        row.Parent = candidateContainer
    end
    
    voteModal.Visible = true
end)

--------------------------------------------------------------------------------
-- 9. CAMERA SHAKE & SMASH IMPACT FX
--------------------------------------------------------------------------------
local function DoCameraShake(intensity, duration)
    local startTime = tick()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        if elapsed > duration then
            conn:Disconnect()
            return
        end
        local factor = (1 - (elapsed / duration)) * intensity
        local shakeX = (math.random() - 0.5) * factor * 0.8
        local shakeY = (math.random() - 0.5) * factor * 0.8
        local shakeZ = (math.random() - 0.5) * factor * 0.4
        Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(shakeX), math.rad(shakeY), math.rad(shakeZ))
    end)
end

HammerSmash.OnClientEvent:Connect(function(data)
    local rarity = data.Rarity
    local impactDelay = data.ImpactDelay or 1.33
    
    task.delay(impactDelay, function()
        local intensity = rarity and rarity.CameraShake or 1.0
        DoCameraShake(intensity * 3, 0.8)
    end)
end)

--------------------------------------------------------------------------------
-- 10. MATCH OVER / WINNER CELEBRATION
--------------------------------------------------------------------------------
MatchOver.OnClientEvent:Connect(function(data)
    winnerName.Text = (data.Winner or "No One") .. " WINS!"
    matchOverModal.Visible = true
end)
