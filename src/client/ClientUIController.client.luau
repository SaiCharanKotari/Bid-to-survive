-- ClientUIController: Handles all BID TO SURVIVE UI interactions, Hammer Roulette, HUD, and 4-Column Leaderboard
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

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
local ActiveCountdown = 0
local HasSubmitted = false
local IsRoulettePlaying = false

--------------------------------------------------------------------------------
-- 1. HUD STYLING (HEALTH BAR & MONEY BOX)
--------------------------------------------------------------------------------
-- Remove outer grey box and borders
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
cashLabel.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
cashLabel.BackgroundTransparency = 0
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 15
cashLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
cashLabel.TextXAlignment = Enum.TextXAlignment.Center
cashLabel.Text = string.format("$%.2f", CurrentMoney)

local cashCorner = cashLabel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
cashCorner.CornerRadius = UDim.new(0, 3)
cashCorner.Parent = cashLabel

local cashStroke = cashLabel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
cashStroke.Color = Color3.fromRGB(35, 35, 45)
cashStroke.Thickness = 1
cashStroke.Parent = cashLabel

-- Noticeably taller rectangular red health bar
healthBarBg.Size = UDim2.new(0, 220, 0, 26)
healthBarBg.Position = UDim2.new(0, 0, 0, 34)
healthBarBg.BackgroundColor3 = Color3.fromRGB(45, 12, 16)
healthBarBg.BackgroundTransparency = 0

local hpBgCorner = healthBarBg:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
hpBgCorner.CornerRadius = UDim.new(0, 2)
hpBgCorner.Parent = healthBarBg

local hpBgStroke = healthBarBg:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
hpBgStroke.Color = Color3.fromRGB(65, 18, 24)
hpBgStroke.Thickness = 1
hpBgStroke.Parent = healthBarBg

-- Fill
healthBarFill.BackgroundColor3 = Color3.fromRGB(220, 35, 45)
local fillCorner = healthBarFill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 2)
fillCorner.Parent = healthBarFill

-- Centered bold white text 100 / 100
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.Position = UDim2.new(0, 0, 0, 0)
healthText.BackgroundTransparency = 1
healthText.Font = Enum.Font.GothamBold
healthText.TextSize = 14
healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
healthText.TextStrokeTransparency = 0.35
healthText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
healthText.TextXAlignment = Enum.TextXAlignment.Center
healthText.TextYAlignment = Enum.TextYAlignment.Center
healthText.ZIndex = 5
healthText.Text = string.format("%d / 100", CurrentHealth)

-- Round Label
roundLabel.Position = UDim2.new(0, 0, 0, 66)
roundLabel.Size = UDim2.new(0, 220, 0, 18)
roundLabel.TextXAlignment = Enum.TextXAlignment.Left
roundLabel.TextColor3 = Color3.fromRGB(160, 170, 190)
roundLabel.Font = Enum.Font.GothamMedium
roundLabel.TextSize = 12

-- Hide old static rarity badge if present
if rarityBadge then
    rarityBadge.Visible = false
end

--------------------------------------------------------------------------------
-- 2. HAMMER ROULETTE (ONE SINGLE FLOATING ICON)
--------------------------------------------------------------------------------
local rouletteContainer = gui:FindFirstChild("RouletteContainer") or Instance.new("Frame")
rouletteContainer.Name = "RouletteContainer"
rouletteContainer.Size = UDim2.new(0, 320, 0, 320)
rouletteContainer.Position = UDim2.new(0.5, -160, 0.44, -160)
rouletteContainer.BackgroundTransparency = 1 -- NO background box, pure floating
rouletteContainer.Visible = false
rouletteContainer.ZIndex = 25
rouletteContainer.Parent = gui

-- Soft neon glow halo behind hammer
local glowHalo = rouletteContainer:FindFirstChild("GlowHalo") or Instance.new("ImageLabel")
glowHalo.Name = "GlowHalo"
glowHalo.Size = UDim2.new(0, 260, 0, 260)
glowHalo.Position = UDim2.new(0.5, -130, 0, 5)
glowHalo.BackgroundTransparency = 1
glowHalo.Image = "rbxassetid://5028857084" -- Soft radial blur halo
glowHalo.ImageTransparency = 0.35
glowHalo.ZIndex = 26
glowHalo.Parent = rouletteContainer

-- Centered floating hammer icon
local hammerIcon = rouletteContainer:FindFirstChild("HammerIcon") or Instance.new("ImageLabel")
hammerIcon.Name = "HammerIcon"
hammerIcon.Size = UDim2.new(0, 200, 0, 200)
hammerIcon.Position = UDim2.new(0.5, -100, 0, 35)
hammerIcon.BackgroundTransparency = 1
hammerIcon.ScaleType = Enum.ScaleType.Fit
hammerIcon.ZIndex = 28
hammerIcon.Parent = rouletteContainer

-- Final rarity text below hammer
local rarityTitle = rouletteContainer:FindFirstChild("RarityTitle") or Instance.new("TextLabel")
rarityTitle.Name = "RarityTitle"
rarityTitle.Size = UDim2.new(1, 0, 0, 32)
rarityTitle.Position = UDim2.new(0, 0, 0, 240)
rarityTitle.BackgroundTransparency = 1
rarityTitle.Font = Enum.Font.GothamBlack
rarityTitle.TextSize = 24
rarityTitle.TextXAlignment = Enum.TextXAlignment.Center
rarityTitle.TextStrokeTransparency = 0.3
rarityTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
rarityTitle.ZIndex = 28
rarityTitle.Parent = rouletteContainer

-- Damage % label
local damageTitle = rouletteContainer:FindFirstChild("DamageTitle") or Instance.new("TextLabel")
damageTitle.Name = "DamageTitle"
damageTitle.Size = UDim2.new(1, 0, 0, 22)
damageTitle.Position = UDim2.new(0, 0, 0, 274)
damageTitle.BackgroundTransparency = 1
damageTitle.Font = Enum.Font.GothamBold
damageTitle.TextSize = 16
damageTitle.TextColor3 = Color3.fromRGB(240, 240, 255)
damageTitle.TextStrokeTransparency = 0.4
damageTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
damageTitle.TextXAlignment = Enum.TextXAlignment.Center
damageTitle.ZIndex = 28
damageTitle.Parent = rouletteContainer

local function SetHammerVisual(rarityData)
    if not rarityData then return end
    hammerIcon.Image = rarityData.AssetId or ""
    glowHalo.ImageColor3 = rarityData.GlowColor or rarityData.Color or Color3.fromRGB(255, 255, 255)
    rarityTitle.Text = string.format("🔨 %s HAMMER", (rarityData.Name or "COMMON"):upper())
    rarityTitle.TextColor3 = rarityData.Color or Color3.fromRGB(255, 255, 255)
    damageTitle.Text = string.format("%d%% HAMMER DAMAGE", rarityData.DamagePercent or 30)
end

local function PlayHammerRoulette(targetRarity, totalDuration)
    if IsRoulettePlaying then return end
    IsRoulettePlaying = true
    
    totalDuration = totalDuration or (GameConfig.RouletteDuration or 3.2)
    rouletteContainer.Visible = true
    glowHalo.ImageTransparency = 0.4
    hammerIcon.ImageTransparency = 0
    rarityTitle.TextTransparency = 0
    damageTitle.TextTransparency = 0
    
    local rarities = GameConfig.GetRarityList()
    local stepCount = 20
    local delays = {
        0.04, 0.04, 0.04, 0.05, 0.05,
        0.06, 0.07, 0.08, 0.10, 0.12,
        0.15, 0.19, 0.24, 0.30, 0.38,
        0.48
    }
    
    local currentIdx = 1
    for i, delay in ipairs(delays) do
        currentIdx = (currentIdx % #rarities) + 1
        local r = rarities[currentIdx]
        SetHammerVisual(r)
        
        -- Subtle tilt and pulse
        local tiltAngle = (i % 2 == 0) and 7 or -7
        hammerIcon.Rotation = tiltAngle
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.4), {
            Size = UDim2.new(0, 215, 0, 215),
            Position = UDim2.new(0.5, -107, 0, 28)
        }):Play()
        
        task.wait(delay * 0.5)
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.5), {
            Size = UDim2.new(0, 200, 0, 200),
            Position = UDim2.new(0.5, -100, 0, 35)
        }):Play()
        task.wait(delay * 0.5)
    end
    
    -- Land on real server-selected target rarity
    SetHammerVisual(targetRarity)
    hammerIcon.Rotation = 0
    
    -- Final punch emphasis
    TweenService:Create(hammerIcon, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 230, 0, 230),
        Position = UDim2.new(0.5, -115, 0, 20)
    }):Play()
    
    TweenService:Create(glowHalo, TweenInfo.new(0.3), {
        ImageTransparency = 0.05,
        Size = UDim2.new(0, 300, 0, 300),
        Position = UDim2.new(0.5, -150, 0, -15)
    }):Play()
    
    task.wait(1.4)
    
    -- Clean fade-out into Bidding phase
    TweenService:Create(hammerIcon, TweenInfo.new(0.4), {
        ImageTransparency = 1,
        Size = UDim2.new(0, 180, 0, 180)
    }):Play()
    TweenService:Create(glowHalo, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
    TweenService:Create(rarityTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    TweenService:Create(damageTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    
    task.wait(0.4)
    rouletteContainer.Visible = false
    IsRoulettePlaying = false
end

--------------------------------------------------------------------------------
-- 3. COUNTDOWN TICKER
--------------------------------------------------------------------------------
task.spawn(function()
    while true do
        if ActiveCountdown > 0 then
            ActiveCountdown = ActiveCountdown - 1
            local mins = math.floor(ActiveCountdown / 60)
            local secs = ActiveCountdown % 60
            timerLabel.Text = string.format("%02d:%02d", mins, secs)
        else
            timerLabel.Text = "00:00"
        end
        task.wait(1)
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
    
    -- Format without coin emoji
    cashLabel.Text = string.format("$%.2f", CurrentMoney)
    
    local hpPct = math.clamp(CurrentHealth / 100, 0, 1)
    TweenService:Create(healthBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(hpPct, 0, 1, 0)
    }):Play()
    healthText.Text = string.format("%d / 100", CurrentHealth)
    
    -- Red screen flash on damage taken
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
    ActiveCountdown = data.Duration or 0
    local round = data.Round or 1
    local rarity = data.Rarity
    local living = data.LivingCount or 1
    
    roundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
    
    if phase == "Intermission" then
        phaseTitle.Text = "INTERMISSION"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Teleporting to arena shortly..."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        matchOverModal.Visible = false
        rouletteContainer.Visible = false
        
    elseif phase == "Phase1_Spawn" then
        phaseTitle.Text = string.format("ROUND %d — HAMMER REVEAL", round)
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "Watching the Hammer Roulette spin..."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        
        -- Trigger synchronized single-icon roulette animation
        if rarity then
            task.spawn(function()
                PlayHammerRoulette(rarity, data.RouletteDuration or 3.2)
            end)
        end
        
    elseif phase == "Phase2_Vote" then
        phaseTitle.Text = "PHASE 2 — ANONYMOUS VOTE"
        phaseTitle.TextColor3 = Color3.fromRGB(200, 120, 255)
        infoLabel.Text = "Eliminated spectators are voting to expose 1 player's bid!"
        rouletteContainer.Visible = false
        
    elseif phase == "Phase3_Bid" then
        phaseTitle.Text = "PHASE 3 — BID FOR SURVIVAL"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 170, 0)
        rouletteContainer.Visible = false
        if data.ExposedPlayer then
            infoLabel.Text = string.format("⚠️ ALERT: %s was voted! Their bid will be EXPOSED!", data.ExposedPlayer)
            infoLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        else
            infoLabel.Text = "Enter your secret bid! Top 50% earn green safe tiles."
            infoLabel.TextColor3 = Color3.fromRGB(160, 175, 200)
        end
        
    elseif phase == "Phase4_Reveal" then
        phaseTitle.Text = "PHASE 4 — BID RANKINGS REVEALED"
        phaseTitle.TextColor3 = Color3.fromRGB(0, 220, 255)
        infoLabel.Text = "Leaderboard: Top 50% earned safe tile access!"
        biddingModal.Visible = false
        
    elseif phase == "Phase5_Scramble" then
        phaseTitle.Text = "PHASE 5 — THE SCRAMBLE!"
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "RUN TO A GREEN SAFE TILE BEFORE IMPACT!"
        rankingsModal.Visible = false
        biddingModal.Visible = false
        
    elseif phase == "Phase6_Smash" then
        phaseTitle.Text = "PHASE 6 — HAMMER SMASH!"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 50, 50)
        infoLabel.Text = "BRACE FOR IMPACT!"
        
    elseif phase == "Phase7_Settlement" then
        phaseTitle.Text = "PHASE 7 — SETTLEMENT"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Bids processed. Checking health..."
        
    elseif phase == "MatchOver" then
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
-- 6. BIDDING MODAL (PRESERVED FUNCTIONALITY & LAYOUT)
--------------------------------------------------------------------------------
PromptBid.OnClientEvent:Connect(function(data)
    if not IsAlive then return end
    HasSubmitted = false
    bidInput.Text = ""
    submittedNotice.Text = ""
    submitBtn.Text = "SUBMIT BID"
    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 175, 90)
    biddingModal.Visible = true
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
    submitBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 75)
    submittedNotice.Text = string.format("Submitted Secret Bid: $%.2f", val)
    
    task.delay(1.5, function()
        if biddingModal.Visible and HasSubmitted then
            biddingModal.Visible = false
        end
    end)
end)

--------------------------------------------------------------------------------
-- 7. LEADERBOARD: UNIFIED FOUR-COLUMN TABLE
--------------------------------------------------------------------------------
-- SI.NO | PLAYER NAME | BID | TIME
RankingsRevealed.OnClientEvent:Connect(function(data)
    -- Configure clean rectangular dark dashboard
    rankingsModal.Size = UDim2.new(0, 560, 0, 360)
    rankingsModal.Position = UDim2.new(0.5, -280, 0.5, -180)
    rankingsModal.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    rankingsModal.BackgroundTransparency = 0
    
    local mCorner = rankingsModal:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    mCorner.CornerRadius = UDim.new(0, 4)
    mCorner.Parent = rankingsModal
    
    local mStroke = rankingsModal:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    mStroke.Color = Color3.fromRGB(35, 35, 45)
    mStroke.Thickness = 1
    mStroke.Parent = rankingsModal
    
    -- Clear previous containers/rows
    for _, child in ipairs(rankingsModal:GetChildren()) do
        if child.Name == "HeaderFrame" or child.Name == "LeaderboardScroll" or child.Name == "TitleLabel" or child.Name == "SubLabel" then
            child:Destroy()
        elseif child:IsA("ScrollingFrame") then
            child.Visible = false
        end
    end
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, -20, 0, 24)
    titleLabel.Position = UDim2.new(0, 12, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "BID RANKINGS — ROUND REVEAL"
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextSize = 16
    titleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = rankingsModal
    
    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "SubLabel"
    subLabel.Size = UDim2.new(1, -20, 0, 18)
    subLabel.Position = UDim2.new(0, 12, 0, 34)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "Top 50% are safe from the hammer smash • Tied bids ranked by submission time"
    subLabel.Font = Enum.Font.GothamMedium
    subLabel.TextSize = 12
    subLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.Parent = rankingsModal
    
    -- Four Column Header Frame: SI.NO | PLAYER NAME | BID | TIME
    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "HeaderFrame"
    headerFrame.Size = UDim2.new(1, -24, 0, 28)
    headerFrame.Position = UDim2.new(0, 12, 0, 60)
    headerFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    headerFrame.BorderSizePixel = 0
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 3)
    hCorner.Parent = headerFrame
    
    local function makeHeaderCell(text, size, pos, align)
        local hCell = Instance.new("TextLabel")
        hCell.Size = size
        hCell.Position = pos
        hCell.BackgroundTransparency = 1
        hCell.Text = text
        hCell.Font = Enum.Font.GothamBold
        hCell.TextSize = 11
        hCell.TextColor3 = Color3.fromRGB(160, 165, 180)
        hCell.TextXAlignment = align
        hCell.Parent = headerFrame
        return hCell
    end
    
    makeHeaderCell("SI.NO", UDim2.new(0.12, 0, 1, 0), UDim2.new(0, 6, 0, 0), Enum.TextXAlignment.Center)
    makeHeaderCell("PLAYER NAME", UDim2.new(0.48, -12, 1, 0), UDim2.new(0.12, 12, 0, 0), Enum.TextXAlignment.Left)
    makeHeaderCell("BID", UDim2.new(0.20, -10, 1, 0), UDim2.new(0.60, 0, 0, 0), Enum.TextXAlignment.Right)
    makeHeaderCell("TIME", UDim2.new(0.20, -12, 1, 0), UDim2.new(0.80, 0, 0, 0), Enum.TextXAlignment.Right)
    headerFrame.Parent = rankingsModal
    
    -- Scrolling rows container
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "LeaderboardScroll"
    scroll.Size = UDim2.new(1, -24, 1, -104)
    scroll.Position = UDim2.new(0, 12, 0, 94)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 75)
    
    local uiList = Instance.new("UIListLayout")
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Padding = UDim.new(0, 4)
    uiList.Parent = scroll
    
    -- Combine top & bottom bidders in order
    local allBidders = {}
    local safeCount = data.SafeCount or 1
    for _, p in ipairs(data.TopBidders or {}) do table.insert(allBidders, p) end
    for _, p in ipairs(data.BottomBidders or {}) do table.insert(allBidders, p) end
    
    for i, p in ipairs(allBidders) do
        local isSafe = (i <= safeCount)
        local row = Instance.new("Frame")
        row.Name = "Row_" .. i
        row.Size = UDim2.new(1, -6, 0, 34)
        row.LayoutOrder = i
        row.BorderSizePixel = 0
        row.BackgroundColor3 = isSafe and Color3.fromRGB(18, 36, 26) or Color3.fromRGB(26, 20, 24)
        
        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 3)
        rCorner.Parent = row
        
        -- Row separator line
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, 0, 0, 1)
        sep.Position = UDim2.new(0, 0, 1, -1)
        sep.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
        sep.BorderSizePixel = 0
        sep.Parent = row
        
        -- Col 1: SI.NO
        local c1 = Instance.new("TextLabel")
        c1.Size = UDim2.new(0.12, 0, 1, 0)
        c1.Position = UDim2.new(0, 6, 0, 0)
        c1.BackgroundTransparency = 1
        c1.Text = tostring(i)
        c1.Font = Enum.Font.GothamBold
        c1.TextSize = 13
        c1.TextColor3 = isSafe and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 110, 120)
        c1.TextXAlignment = Enum.TextXAlignment.Center
        c1.Parent = row
        
        -- Col 2: PLAYER NAME (real username)
        local c2 = Instance.new("TextLabel")
        c2.Size = UDim2.new(0.48, -12, 1, 0)
        c2.Position = UDim2.new(0.12, 12, 0, 0)
        c2.BackgroundTransparency = 1
        c2.Text = p.Name or "Unknown"
        c2.Font = Enum.Font.GothamBold
        c2.TextSize = 13
        c2.TextColor3 = Color3.fromRGB(255, 255, 255)
        c2.TextXAlignment = Enum.TextXAlignment.Left
        c2.Parent = row
        
        -- Col 3: BID (accepted bid formatted to 2 decimals)
        local c3 = Instance.new("TextLabel")
        c3.Size = UDim2.new(0.20, -10, 1, 0)
        c3.Position = UDim2.new(0.60, 0, 0, 0)
        c3.BackgroundTransparency = 1
        c3.Text = string.format("$%.2f", p.CurrentBid or 0)
        c3.Font = Enum.Font.GothamBlack
        c3.TextSize = 13
        c3.TextColor3 = Color3.fromRGB(255, 215, 0)
        c3.TextXAlignment = Enum.TextXAlignment.Right
        c3.Parent = row
        
        -- Col 4: TIME (elapsed seconds formatted to 2 decimals)
        local c4 = Instance.new("TextLabel")
        c4.Size = UDim2.new(0.20, -12, 1, 0)
        c4.Position = UDim2.new(0.80, 0, 0, 0)
        c4.BackgroundTransparency = 1
        local elapsed = p.SubmitTime or 10.00
        c4.Text = string.format("%.2fs", elapsed)
        c4.Font = Enum.Font.GothamMedium
        c4.TextSize = 13
        c4.TextColor3 = Color3.fromRGB(180, 195, 220)
        c4.TextXAlignment = Enum.TextXAlignment.Right
        c4.Parent = row
        
        row.Parent = scroll
    end
    
    scroll.CanvasSize = UDim2.new(0, 0, 0, #allBidders * 38)
    scroll.Parent = rankingsModal
    rankingsModal.Visible = true
end)

--------------------------------------------------------------------------------
-- 8. SPECTATOR VOTE POPULATOR
--------------------------------------------------------------------------------
PromptVote.OnClientEvent:Connect(function(data)
    if IsAlive then return end
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
