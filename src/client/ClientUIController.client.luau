-- ClientUIController: Handles all BID TO SURVIVE UI interactions and visual effects
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

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

local gui = script.Parent
local topBanner = gui:WaitForChild("TopBanner")
local phaseTitle = topBanner:WaitForChild("PhaseTitle")
local timerLabel = topBanner:WaitForChild("TimerLabel")
local infoLabel = topBanner:WaitForChild("InfoLabel")

local statsCard = gui:WaitForChild("StatsCard")
local cashLabel = statsCard:WaitForChild("CashLabel")
local healthBarFill = statsCard:WaitForChild("HealthBarBg"):WaitForChild("Fill")
local healthText = statsCard:WaitForChild("HealthBarBg"):WaitForChild("HealthText")
local roundLabel = statsCard:WaitForChild("RoundLabel")

local rarityBadge = gui:WaitForChild("RarityBadge")
local rarityText = rarityBadge:WaitForChild("RarityText")

local biddingModal = gui:WaitForChild("BiddingModal")
local bidInput = biddingModal:WaitForChild("BidInput")
local submitBtn = biddingModal:WaitForChild("SubmitBtn")
local submittedNotice = biddingModal:WaitForChild("SubmittedNotice")
local quickFrame = biddingModal:WaitForChild("QuickFrame")

local rankingsModal = gui:WaitForChild("RankingsModal")
local topContainer = rankingsModal:WaitForChild("TopContainer")
local botContainer = rankingsModal:WaitForChild("BottomContainer")

local voteModal = gui:WaitForChild("VoteModal")
local candidateContainer = voteModal:WaitForChild("CandidateContainer")

local matchOverModal = gui:WaitForChild("MatchOverModal")
local winnerName = matchOverModal:WaitForChild("WinnerName")

local screenFlash = gui:WaitForChild("ScreenFlash")

-- Local State
local CurrentMoney = 20.00
local CurrentHealth = 100
local IsAlive = true
local ActiveCountdown = 0
local HasSubmitted = false

--------------------------------------------------------------------------------
-- COUNTDOWN TICKER
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
-- STATS SYNC
--------------------------------------------------------------------------------
StatsUpdated.OnClientEvent:Connect(function(stats)
    local oldHealth = CurrentHealth
    CurrentMoney = stats.Money or CurrentMoney
    CurrentHealth = stats.Health or CurrentHealth
    IsAlive = (stats.IsAlive ~= nil) and stats.IsAlive or IsAlive
    
    cashLabel.Text = string.format("💰 $%.2f", CurrentMoney)
    
    local hpPct = math.clamp(CurrentHealth / 100, 0, 1)
    TweenService:Create(healthBarFill, TweenInfo.new(0.3), {
        Size = UDim2.new(hpPct, 0, 1, 0)
    }):Play()
    healthText.Text = string.format("%d / 100 HP", CurrentHealth)
    
    -- Red screen flash on damage taken
    if CurrentHealth < oldHealth then
        screenFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        screenFlash.BackgroundTransparency = 0.5
        TweenService:Create(screenFlash, TweenInfo.new(0.5), {
            BackgroundTransparency = 1
        }):Play()
    end
end)

--------------------------------------------------------------------------------
-- PHASE STATE HANDLER
--------------------------------------------------------------------------------
StateChanged.OnClientEvent:Connect(function(data)
    local phase = data.Phase
    ActiveCountdown = data.Duration or 0
    local round = data.Round or 1
    local rarity = data.Rarity
    local living = data.LivingCount or 1
    
    roundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
    
    if rarity then
        rarityText.Text = string.format("🔨 %s\n%d%% DAMAGE", rarity.Name:upper(), rarity.DamagePercent)
        rarityText.TextColor3 = rarity.Color
    end
    
    -- Phase specific UI updates
    if phase == "Intermission" then
        phaseTitle.Text = "INTERMISSION"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Teleporting to arena shortly..."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        matchOverModal.Visible = false
        
    elseif phase == "Phase1_Spawn" then
        phaseTitle.Text = string.format("ROUND %d — ARENA SPAWN", round)
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = string.format("Hammer Rarity: %s (%d%% Damage). Get ready!", rarity and rarity.Name or "Common", rarity and rarity.DamagePercent or 30)
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        
    elseif phase == "Phase2_Vote" then
        phaseTitle.Text = "PHASE 2 — ANONYMOUS VOTE"
        phaseTitle.TextColor3 = Color3.fromRGB(200, 120, 255)
        infoLabel.Text = "Eliminated players are voting to expose 1 living player's bid!"
        
    elseif phase == "Phase3_Bid" then
        phaseTitle.Text = "PHASE 3 — BID FOR SURVIVAL"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 170, 0)
        if data.ExposedPlayer then
            infoLabel.Text = string.format("⚠️ ALERT: %s was voted! Their bid will be EXPOSED!", data.ExposedPlayer)
            infoLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        else
            infoLabel.Text = "Enter your secret bid! Top 50% earn safe tile access."
            infoLabel.TextColor3 = Color3.fromRGB(160, 175, 200)
        end
        
    elseif phase == "Phase4_Reveal" then
        phaseTitle.Text = "PHASE 4 — BID RANKINGS REVEALED"
        phaseTitle.TextColor3 = Color3.fromRGB(0, 220, 255)
        infoLabel.Text = "Review the top vs bottom bidders!"
        biddingModal.Visible = false
        
    elseif phase == "Phase5_Scramble" then
        phaseTitle.Text = "PHASE 5 — THE SCRAMBLE!"
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "RUN TO A GREEN SAFE TILE BEFORE THE HAMMER DROPS!"
        rankingsModal.Visible = false
        biddingModal.Visible = false
        
    elseif phase == "Phase6_Smash" then
        phaseTitle.Text = "PHASE 6 — HAMMER SMASH!"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 50, 50)
        infoLabel.Text = "BRACE FOR IMPACT!"
        
    elseif phase == "Phase7_Settlement" then
        phaseTitle.Text = "PHASE 7 — SETTLEMENT"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Top bids deducted. Bottom bids refunded. Checking health..."
        
    elseif phase == "MatchOver" then
        phaseTitle.Text = "MATCH OVER"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Match concluded."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
    end
end)

--------------------------------------------------------------------------------
-- BIDDING MODAL INTERACTIONS
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
-- RANKINGS BOARD POPULATOR
--------------------------------------------------------------------------------
local function makePlayerCard(container, rank, name, bid, isSafe)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -10, 0, 36)
    card.BackgroundColor3 = isSafe and Color3.fromRGB(30, 55, 40) or Color3.fromRGB(55, 30, 35)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = card
    
    local rLabel = Instance.new("TextLabel")
    rLabel.Size = UDim2.new(0, 30, 1, 0)
    rLabel.Position = UDim2.new(0, 6, 0, 0)
    rLabel.BackgroundTransparency = 1
    rLabel.Text = "#" .. rank
    rLabel.TextColor3 = isSafe and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 100, 120)
    rLabel.Font = Enum.Font.GothamBold
    rLabel.TextSize = 13
    rLabel.Parent = card
    
    local nLabel = Instance.new("TextLabel")
    nLabel.Size = UDim2.new(1, -120, 1, 0)
    nLabel.Position = UDim2.new(0, 36, 0, 0)
    nLabel.BackgroundTransparency = 1
    nLabel.Text = name
    nLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nLabel.Font = Enum.Font.GothamBold
    nLabel.TextSize = 13
    nLabel.TextXAlignment = Enum.TextXAlignment.Left
    nLabel.Parent = card
    
    local bLabel = Instance.new("TextLabel")
    bLabel.Size = UDim2.new(0, 70, 1, 0)
    bLabel.Position = UDim2.new(1, -76, 0, 0)
    bLabel.BackgroundTransparency = 1
    bLabel.Text = string.format("$%.2f", bid or 0)
    bLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    bLabel.Font = Enum.Font.GothamBlack
    bLabel.TextSize = 13
    bLabel.TextXAlignment = Enum.TextXAlignment.Right
    bLabel.Parent = card
    
    card.Parent = container
end

RankingsRevealed.OnClientEvent:Connect(function(data)
    -- Clear previous items (except header)
    for _, c in ipairs(topContainer:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for _, c in ipairs(botContainer:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    
    local topBidders = data.TopBidders or {}
    local botBidders = data.BottomBidders or {}
    
    for i, p in ipairs(topBidders) do
        makePlayerCard(topContainer, i, p.Name, p.CurrentBid, true)
    end
    for i, p in ipairs(botBidders) do
        makePlayerCard(botContainer, #topBidders + i, p.Name, p.CurrentBid, false)
    end
    
    rankingsModal.Visible = true
end)

--------------------------------------------------------------------------------
-- SPECTATOR VOTE POPULATOR
--------------------------------------------------------------------------------
PromptVote.OnClientEvent:Connect(function(data)
    if IsAlive then return end -- only spectators vote!
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
-- CAMERA SHAKE & SMASH IMPACT FX
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
        -- Camera shake
        local intensity = rarity and rarity.CameraShake or 1.0
        DoCameraShake(intensity * 3, 0.8)
    end)
end)

--------------------------------------------------------------------------------
-- MATCH OVER / WINNER CELEBRATION
--------------------------------------------------------------------------------
MatchOver.OnClientEvent:Connect(function(data)
    winnerName.Text = (data.Winner or "No One") .. " WINS!"
    matchOverModal.Visible = true
end)
