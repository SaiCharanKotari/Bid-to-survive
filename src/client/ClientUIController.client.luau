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

-- RemoteEvent for participation state
local ParticipationChanged = Network:FindFirstChild("ParticipationChanged")
if not ParticipationChanged then
    ParticipationChanged = Instance.new("RemoteEvent")
    ParticipationChanged.Name = "ParticipationChanged"
    ParticipationChanged.Parent = Network
end

local ResetHUDRemote: RemoteEvent? = (Network and Network:FindFirstChild("ResetHUDStateEvent") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("ResetHUDStateEvent") :: RemoteEvent?)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = script:FindFirstAncestorWhichIsA("ScreenGui") or playerGui:WaitForChild("BidToSurviveUI")

local topBanner = gui:WaitForChild("TopBanner", 5)
if not topBanner then
    topBanner = gui:FindFirstChild("TopBanner")
end
local phaseTitle = topBanner and topBanner:WaitForChild("PhaseTitle", 3)
local timerLabel = topBanner and topBanner:WaitForChild("TimerLabel", 3)
local infoLabel = topBanner and topBanner:WaitForChild("InfoLabel", 3)

local statsCard = gui:WaitForChild("StatsCard", 5)
if not statsCard then
    statsCard = gui:FindFirstChild("StatsCard")
end
local cashLabel = statsCard and statsCard:WaitForChild("CashLabel", 3)
local healthBarBg = statsCard and statsCard:WaitForChild("HealthBarBg", 3)
local healthBarFill = healthBarBg and healthBarBg:WaitForChild("Fill", 3)
local healthText = healthBarBg and healthBarBg:WaitForChild("HealthText", 3)
local roundLabel = statsCard and statsCard:WaitForChild("RoundLabel", 3)

local rarityBadge = gui:FindFirstChild("RarityBadge")
local biddingModal = gui:WaitForChild("BiddingModal")
local cardFrame = biddingModal:WaitForChild("CardFrame", 5) or biddingModal
local bidInput = cardFrame:WaitForChild("BidInput", 5) or biddingModal:WaitForChild("BidInput")
local submitBtn = cardFrame:FindFirstChild("SubmitBtn", true) or biddingModal:WaitForChild("SubmitBtn")
local submittedNotice = cardFrame:FindFirstChild("SubmittedNotice", true) or biddingModal:WaitForChild("SubmittedNotice")
local quickFrame = biddingModal:FindFirstChild("QuickFrame") or cardFrame:FindFirstChild("QuickFrame") or Instance.new("Frame")

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
local IsAFK = false -- Default OFF as requested
local CurrentParticipationState = "WaitingInLobby" -- "AFK", "WaitingInLobby", "Active", "Eliminated"
local CurrentPhase = "Intermission"
local SessionToken = 0
local CurrentPhaseDeadline = 0
local HasSubmitted = false
local IsRoulettePlaying = false
local CurrentShakeConn = nil

-- Known verified base hammer asset (Rare is 100% loaded and verified on Roblox CDN)
local VERIFIED_BASE_HAMMER = "rbxassetid://99122878797775"
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
-- 1. REOPEN BUTTON CONTAINER & ROULETTE CONTAINER SETUP (SVG.3 RED GRADIENT)
--------------------------------------------------------------------------------
local function applySVG3ButtonStyle(button: TextButton, labelText: string, textSize: number?)
    button.AutoButtonColor = false
    button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    button.BackgroundTransparency = 0
    button.BorderSizePixel = 0
    button.Text = "" -- Keep native text blank so UIGradient does NOT tint text red

    local corner = button:FindFirstChildOfClass("UICorner")
    if not corner then
        corner = Instance.new("UICorner")
        corner.Parent = button
    end
    corner.CornerRadius = UDim.new(0, 1)

    local stroke = button:FindFirstChildOfClass("UIStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Parent = button
    end
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Miter

    local gradient = button:FindFirstChildOfClass("UIGradient")
    if not gradient then
        gradient = Instance.new("UIGradient")
        gradient.Parent = button
    end
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromHex("#EC0000")),
        ColorSequenceKeypoint.new(0.54, Color3.fromHex("#F50505")),
        ColorSequenceKeypoint.new(0.78, Color3.fromHex("#E25A5A")),
        ColorSequenceKeypoint.new(1.00, Color3.fromHex("#D6C7C7")),
    })
    gradient.Enabled = true

    -- Independent Crisp White TextLabel (Guaranteed unaffected by UIGradient)
    local label = button:FindFirstChild("BtnLabel") :: TextLabel?
    if not label then
        label = Instance.new("TextLabel")
        label.Name = "BtnLabel"
        label.Size = UDim2.fromScale(1, 1)
        label.Position = UDim2.fromScale(0, 0)
        label.BackgroundTransparency = 1
        label.ZIndex = button.ZIndex + 3
        label.Parent = button
    end
    label.Text = labelText
    label.Font = Enum.Font.GothamMedium
    label.TextSize = textSize or 28
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
end

local centerActionDock = gui:FindFirstChild("CenterActionDock") or gui:FindFirstChild("ReopenContainer") or Instance.new("Frame")
centerActionDock.Name = "CenterActionDock"
centerActionDock.AnchorPoint = Vector2.new(0.5, 0.5)
centerActionDock.Position = UDim2.new(0.5, 0, 0.42, 0) -- Exactly middle and slightly UP
centerActionDock.Size = UDim2.new(0, 460, 0, 62)
centerActionDock.BackgroundTransparency = 1
centerActionDock.ZIndex = 35
centerActionDock.Visible = false
centerActionDock.Parent = gui

local reopenContainer = centerActionDock -- Backward compatibility alias

local reopenBidBtn = centerActionDock:FindFirstChild("ReopenBidBtn") or Instance.new("TextButton")
reopenBidBtn.Name = "ReopenBidBtn"
reopenBidBtn.AnchorPoint = Vector2.new(0.5, 0.5)
reopenBidBtn.Size = UDim2.new(0, 210, 0, 62)
reopenBidBtn.Position = UDim2.new(0.5, -118, 0.5, 0)
reopenBidBtn.ZIndex = 36
reopenBidBtn.Visible = false
reopenBidBtn.Parent = centerActionDock
applySVG3ButtonStyle(reopenBidBtn, "BID", 28)

local reopenRankBtn = centerActionDock:FindFirstChild("ReopenRankBtn") or Instance.new("TextButton")
reopenRankBtn.Name = "ReopenRankBtn"
reopenRankBtn.AnchorPoint = Vector2.new(0.5, 0.5)
reopenRankBtn.Size = UDim2.new(0, 210, 0, 62)
reopenRankBtn.Position = UDim2.new(0.5, 118, 0.5, 0)
reopenRankBtn.ZIndex = 36
reopenRankBtn.Visible = false
reopenRankBtn.Parent = centerActionDock
applySVG3ButtonStyle(reopenRankBtn, "LEADERBOARD", 20)

local function updateCenterDockLayout()
    local bidVis = reopenBidBtn.Visible
    local rankVis = reopenRankBtn.Visible
    centerActionDock.Visible = (bidVis or rankVis)
    if bidVis and rankVis then
        reopenBidBtn.Position = UDim2.new(0.5, -118, 0.5, 0)
        reopenRankBtn.Position = UDim2.new(0.5, 118, 0.5, 0)
    elseif bidVis then
        reopenBidBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    elseif rankVis then
        reopenRankBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    end
end

local rouletteContainer = gui:FindFirstChild("RouletteContainer") or Instance.new("Frame")
rouletteContainer.Name = "RouletteContainer"
rouletteContainer.Size = UDim2.new(0, 340, 0, 340)
rouletteContainer.Position = UDim2.new(0.5, -170, 0.42, -170)
rouletteContainer.BackgroundTransparency = 1
rouletteContainer.BorderSizePixel = 0
rouletteContainer.Visible = false
rouletteContainer.ZIndex = 30
rouletteContainer.Parent = gui

-- Remove any old square GlowHalo shadow to keep floating hammer visuals 100% clean
local oldHalo = rouletteContainer:FindFirstChild("GlowHalo")
if oldHalo then
    oldHalo:Destroy()
end

local hammerIcon = rouletteContainer:FindFirstChild("HammerIcon") or Instance.new("ImageLabel")
hammerIcon.Name = "HammerIcon"
hammerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
hammerIcon.Size = UDim2.new(0, 220, 0, 220)
hammerIcon.Position = UDim2.new(0.5, 0, 0, 135)
hammerIcon.BackgroundTransparency = 1
hammerIcon.BorderSizePixel = 0
hammerIcon.ScaleType = Enum.ScaleType.Fit
hammerIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
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

--------------------------------------------------------------------------------
-- 2. CAMERA SHAKE CONTROLS
--------------------------------------------------------------------------------
local function StopCameraShake()
    if CurrentShakeConn then
        CurrentShakeConn:Disconnect()
        CurrentShakeConn = nil
    end
end

local function DoCameraShake(intensity, duration)
    StopCameraShake()
    local startTime = tick()
    CurrentShakeConn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        if elapsed > duration or IsAFK or (CurrentParticipationState ~= "Active") then
            StopCameraShake()
            return
        end
        local factor = (1 - (elapsed / duration)) * intensity
        local shakeX = (math.random() - 0.5) * factor * 0.8
        local shakeY = (math.random() - 0.5) * factor * 0.8
        local shakeZ = (math.random() - 0.5) * factor * 0.4
        Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(shakeX), math.rad(shakeY), math.rad(shakeZ))
    end)
end

--------------------------------------------------------------------------------
-- 3. STATE AND UI ISOLATION HELPERS
--------------------------------------------------------------------------------
local function IsActiveInRound()
    return (not IsAFK) and (CurrentParticipationState == "Active")
end

local function IsInPlayground()
    return IsActiveInRound() and (CurrentPhase ~= "Intermission") and (CurrentPhase ~= "MatchOver")
end

local function UpdateHUDVisibility()
    local inPlayground = IsInPlayground()
    if healthBarBg then healthBarBg.Visible = false end
    if cashLabel then cashLabel.Visible = false end
    if roundLabel then roundLabel.Position = UDim2.new(0, 0, 0, 0) end
    if statsCard then
        local inGame = (player:GetAttribute("IsInGame") == true)
        statsCard.Position = UDim2.new(0, 24, 1, inGame and -192 or -134)
    end
end

local function ForceHideAllRoundUI()
    SessionToken = SessionToken + 1
    StopCameraShake()
    topBanner.Visible = false
    biddingModal.Visible = false
    rankingsModal.Visible = false
    voteModal.Visible = false
    matchOverModal.Visible = false
    rouletteContainer.Visible = false
    reopenBidBtn.Visible = false
    reopenRankBtn.Visible = false
    updateCenterDockLayout()
    screenFlash.BackgroundTransparency = 1
    IsRoulettePlaying = false
    UpdateHUDVisibility()
end

--------------------------------------------------------------------------------
-- 4. HUD STYLING (ROUND LABEL & AFK TOGGLE BUTTON)
--------------------------------------------------------------------------------
if statsCard then
    statsCard.BackgroundTransparency = 1
    local oldCardStroke = statsCard:FindFirstChildOfClass("UIStroke")
    if oldCardStroke then oldCardStroke:Destroy() end
    local oldCardCorner = statsCard:FindFirstChildOfClass("UICorner")
    if oldCardCorner then oldCardCorner:Destroy() end

    local initialInGame = (player:GetAttribute("IsInGame") == true)
    statsCard.Size = UDim2.new(0, 260, 0, 24)
    statsCard.Position = UDim2.new(0, 24, 1, initialInGame and -192 or -134)
end

-- Hide duplicate cash box & health bar (rendered by unified MovementDiveAndHUDClient)
if cashLabel then cashLabel.Visible = false end
if healthBarBg then healthBarBg.Visible = false end

-- Round Label positioned cleanly above the status stack
if roundLabel then
    roundLabel.Position = UDim2.new(0, 0, 0, 0)
    roundLabel.Size = UDim2.new(1, 0, 1, 0)
    roundLabel.TextXAlignment = Enum.TextXAlignment.Left
    roundLabel.TextColor3 = Color3.fromRGB(150, 165, 185)
    roundLabel.Font = Enum.Font.GothamMedium
    roundLabel.TextSize = 13
end

UpdateHUDVisibility()

if rarityBadge then
    rarityBadge.Visible = false
end

--------------------------------------------------------------------------------
-- SETTINGS GEAR & AFK TOGGLE BUTTON (COMIC POP-ART STYLE MATCHING SVG.2)
--------------------------------------------------------------------------------
local settingsButton = gui:FindFirstChild("SettingsButton") or Instance.new("ImageButton")
settingsButton.Name = "SettingsButton"
settingsButton.Size = UDim2.new(0, 48, 0, 48)
settingsButton.Position = UDim2.new(0, 24, 0, 24)
settingsButton.BackgroundTransparency = 1
settingsButton.Image = "rbxassetid://6031280882" -- Clean vector gear icon
settingsButton.ImageColor3 = Color3.fromRGB(30, 30, 30)
settingsButton.ZIndex = 20
settingsButton.Parent = gui

settingsButton.MouseButton1Click:Connect(function()
    pcall(function()
        game:GetService("GuiService"):SetMenuIsOpen(true)
    end)
end)

local afkButton = gui:FindFirstChild("AFKButton") or Instance.new("TextButton")
afkButton.Name = "AFKButton"
afkButton.Size = UDim2.new(0, 152, 0, 48)
afkButton.Position = UDim2.new(0, 24, 0, 84)
afkButton.Font = Enum.Font.GothamBlack
afkButton.TextSize = 18
afkButton.TextColor3 = Color3.fromRGB(0, 0, 0)
afkButton.ZIndex = 20
afkButton.AutoButtonColor = false

local afkCorner = afkButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
afkCorner.CornerRadius = UDim.new(0, 4)
afkCorner.Parent = afkButton

local afkStroke = afkButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
afkStroke.Thickness = 3
afkStroke.Color = Color3.fromRGB(0, 0, 0)
afkStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
afkStroke.Parent = afkButton

local function UpdateAFKVisual()
    if IsAFK then
        afkButton.BackgroundColor3 = Color3.fromRGB(255, 221, 0) -- Yellow when ON
        afkButton.Text = "AFK:ON"
    else
        afkButton.BackgroundColor3 = Color3.fromRGB(0, 220, 80) -- Green when OFF
        afkButton.Text = "AFK:OFF"
    end
end

UpdateAFKVisual()
afkButton.Parent = gui

afkButton.MouseButton1Click:Connect(function()
    IsAFK = not IsAFK
    UpdateAFKVisual()
    if IsAFK then
        CurrentParticipationState = "AFK"
        ForceHideAllRoundUI()
    else
        CurrentParticipationState = "WaitingInLobby"
        ForceHideAllRoundUI()
    end
    UpdateHUDVisibility()
    SetAFK:FireServer(IsAFK)
end)

--------------------------------------------------------------------------------
-- REOPEN BUTTON CLICKS
--------------------------------------------------------------------------------
reopenBidBtn.MouseButton1Click:Connect(function()
    if not IsActiveInRound() then return end
    biddingModal.Visible = true
    reopenBidBtn.Visible = false
    updateCenterDockLayout()
end)

reopenRankBtn.MouseButton1Click:Connect(function()
    if not IsActiveInRound() then return end
    rankingsModal.Visible = true
    reopenRankBtn.Visible = false
    updateCenterDockLayout()
end)

--------------------------------------------------------------------------------
-- 5. HAMMER ROULETTE (GUARANTEED 100% VISIBLE WITH WORKING ASSET FALLBACK)
--------------------------------------------------------------------------------
local function SetHammerVisual(rarityData)
    if not rarityData then return end
    
    local assetId = rarityData.AssetId
    if not assetId or assetId == "" or PendingAssets[assetId] then
        assetId = VERIFIED_BASE_HAMMER
    end
    
    hammerIcon.Image = assetId
    hammerIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    rarityTitle.Text = string.format("🔨 %s HAMMER", (rarityData.Name or "COMMON"):upper())
    rarityTitle.TextColor3 = rarityData.GlowColor or rarityData.Color or Color3.fromRGB(255, 255, 255)
    damageTitle.Text = string.format("DEALS %d%% HP DAMAGE", rarityData.DamagePercent or 30)
end

local function PlayHammerRoulette(targetRarity, totalDuration, spinnerReel)
    if IsRoulettePlaying or (not IsActiveInRound()) then return end
    IsRoulettePlaying = true
    local myToken = SessionToken
    
    rouletteContainer.Visible = true
    hammerIcon.ImageTransparency = 0
    hammerIcon.Size = UDim2.new(0, 220, 0, 220)
    hammerIcon.Position = UDim2.new(0.5, 0, 0, 135)
    hammerIcon.Rotation = 0
    rarityTitle.TextTransparency = 0
    damageTitle.TextTransparency = 0
    
    local delays = {
        0.10, 0.10, 0.11, 0.11, 0.12, 0.13, 0.14, 0.16,
        0.18, 0.20, 0.23, 0.27, 0.31, 0.36, 0.42, 0.50,
        0.60, 0.72, 0.85
    }
    
    -- Use server-provided anti-repeat randomized reel or generate local fallback
    local reel = spinnerReel
    if not reel or #reel < #delays then
        if GameConfig.BuildRandomSpinnerStrip then
            reel = GameConfig.BuildRandomSpinnerStrip(CurrentRound or 1, #delays, #delays, targetRarity.Name)
        else
            reel = {}
            local order = GameConfig.RarityOrder or {"Common", "Uncommon", "Rare", "Legendary", "Mythical"}
            for i = 1, #delays do
                reel[i] = order[((i - 1) % #order) + 1]
            end
            reel[#delays] = targetRarity.Name
        end
    end
    
    for i, delay in ipairs(delays) do
        if (not IsActiveInRound()) or myToken ~= SessionToken then
            rouletteContainer.Visible = false
            IsRoulettePlaying = false
            return
        end
        
        local stepRarityName = reel[i] or targetRarity.Name
        local r = GameConfig.HammerRarities[stepRarityName] or targetRarity
        SetHammerVisual(r)
        
        local tiltAngle = (i % 2 == 0) and 7 or -7
        hammerIcon.Rotation = tiltAngle
        
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 235, 0, 235),
            Position = UDim2.new(0.5, 0, 0, 132)
        }):Play()
        
        task.wait(delay * 0.5)
        
        if (not IsActiveInRound()) or myToken ~= SessionToken then
            rouletteContainer.Visible = false
            IsRoulettePlaying = false
            return
        end
        
        TweenService:Create(hammerIcon, TweenInfo.new(delay * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 220, 0, 220),
            Position = UDim2.new(0.5, 0, 0, 135)
        }):Play()
        
        task.wait(delay * 0.5)
    end
    
    if (not IsActiveInRound()) or myToken ~= SessionToken then
        rouletteContainer.Visible = false
        IsRoulettePlaying = false
        return
    end
    
    -- Stop EXACTLY on the server-authoritative rarity with celebratory burst
    SetHammerVisual(targetRarity)
    hammerIcon.Rotation = 0
    
    TweenService:Create(hammerIcon, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 270, 0, 270),
        Position = UDim2.new(0.5, 0, 0, 135)
    }):Play()
    
    task.wait(1.5)
    
    if (not IsActiveInRound()) or myToken ~= SessionToken then
        rouletteContainer.Visible = false
        IsRoulettePlaying = false
        return
    end
    
    TweenService:Create(hammerIcon, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        ImageTransparency = 1,
        Size = UDim2.new(0, 180, 0, 180),
        Position = UDim2.new(0.5, 0, 0, 135)
    }):Play()
    TweenService:Create(rarityTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    TweenService:Create(damageTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
    
    task.wait(0.4)
    rouletteContainer.Visible = false
    IsRoulettePlaying = false
end

--------------------------------------------------------------------------------
-- 6. FRAME-ACCURATE AUTHORITATIVE COUNTDOWN TICKER
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    if CurrentPhaseDeadline > 0 and (IsActiveInRound() or (CurrentPhaseDeadline - os.clock() > 0 and not IsAFK and topBanner.Visible)) then
        local remaining = math.max(0, math.ceil(CurrentPhaseDeadline - os.clock()))
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        timerLabel.Text = string.format("%02d:%02d", mins, secs)
    else
        timerLabel.Text = "00:00"
    end
end)

--------------------------------------------------------------------------------
-- 7. STATS & PARTICIPATION SYNC
--------------------------------------------------------------------------------
StatsUpdated.OnClientEvent:Connect(function(stats)
    local oldHealth = CurrentHealth
    CurrentMoney = stats.Money or CurrentMoney
    CurrentHealth = stats.Health or CurrentHealth
    IsAlive = (stats.IsAlive ~= nil) and stats.IsAlive or IsAlive
    if stats.IsAFK ~= nil then
        IsAFK = stats.IsAFK
        UpdateAFKVisual()
    end
    if stats.ParticipationState ~= nil then
        CurrentParticipationState = stats.ParticipationState
    end
    
    if cashLabel then cashLabel.Text = string.format("$%.2f", CurrentMoney) end
    
    if healthBarFill then
        local hpPct = math.clamp(CurrentHealth / 100, 0, 1)
        TweenService:Create(healthBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(hpPct, 0, 1, 0)
        }):Play()
    end
    if healthText then healthText.Text = string.format("%d / 100", CurrentHealth) end
    
    if CurrentHealth < oldHealth and IsActiveInRound() then
        screenFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        screenFlash.BackgroundTransparency = 0.45
        TweenService:Create(screenFlash, TweenInfo.new(0.5), {
            BackgroundTransparency = 1
        }):Play()
    end
    
    UpdateHUDVisibility()
    if not IsActiveInRound() then
        ForceHideAllRoundUI()
    end
end)

ParticipationChanged.OnClientEvent:Connect(function(newState)
    if newState then
        CurrentParticipationState = newState
    end
    UpdateHUDVisibility()
    if not IsActiveInRound() then
        ForceHideAllRoundUI()
    end
end)

local function handleClientHUDReset()
    CurrentHealth = 100
    IsAlive = true
    if healthText then healthText.Text = "100 / 100" end
    if healthBarFill then healthBarFill.Size = UDim2.new(1, 0, 1, 0) end
    UpdateHUDVisibility()
end

if ResetHUDRemote then
    ResetHUDRemote.OnClientEvent:Connect(handleClientHUDReset)
else
    task.spawn(function()
        local remote = ReplicatedStorage:WaitForChild("ResetHUDStateEvent", 15) :: RemoteEvent?
        if remote then
            remote.OnClientEvent:Connect(handleClientHUDReset)
        end
    end)
end

player.CharacterAdded:Connect(function(newChar)
    local hum = newChar:WaitForChild("Humanoid", 5) :: Humanoid?
    if hum then
        CurrentHealth = hum.Health
        local maxH = (hum.MaxHealth > 0) and hum.MaxHealth or 100
        if healthText then healthText.Text = string.format("%d / %d", math.ceil(hum.Health), math.ceil(maxH)) end
        if healthBarFill then healthBarFill.Size = UDim2.new(math.clamp(hum.Health / maxH, 0, 1), 0, 1, 0) end
    end
    UpdateHUDVisibility()
end)

--------------------------------------------------------------------------------
-- 8. PHASE STATE HANDLER
--------------------------------------------------------------------------------
StateChanged.OnClientEvent:Connect(function(data)
    local phase = data.Phase
    CurrentPhase = phase or CurrentPhase
    local round = data.Round or 1
    local rarity = data.Rarity
    local living = data.LivingCount or 1
    
    CurrentPhaseDeadline = data.Deadline or (os.clock() + (data.Duration or 0))
    UpdateHUDVisibility()
    
    if roundLabel then
        if IsActiveInRound() then
            roundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
        elseif IsAFK then
            roundLabel.Text = "LOBBY (AFK)"
        else
            roundLabel.Text = "WAITING IN LOBBY"
        end
    end
    
    if phase == "Intermission" or phase == "MatchOver" or not IsActiveInRound() then
        reopenBidBtn.Visible = false
        reopenRankBtn.Visible = false
        updateCenterDockLayout()
    else
        reopenBidBtn.Visible = not biddingModal.Visible
        reopenRankBtn.Visible = not rankingsModal.Visible
        updateCenterDockLayout()
    end
    
    if phase == "Intermission" then
        if IsAFK then
            ForceHideAllRoundUI()
            return
        end
        topBanner.Visible = true
        phaseTitle.Text = "LOBBY COUNTDOWN"
        phaseTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
        infoLabel.Text = "Match starting shortly... Click AFK to opt out"
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        matchOverModal.Visible = false
        rouletteContainer.Visible = false
        return
    end
    
    -- During running rounds (Phase 1 through 7):
    if not IsActiveInRound() then
        ForceHideAllRoundUI()
        return
    end
    
    if phase == "Phase1_Spawn" then
        topBanner.Visible = true
        phaseTitle.Text = string.format("ROUND %d — HAMMER REVEAL", round)
        phaseTitle.TextColor3 = Color3.fromRGB(85, 255, 127)
        infoLabel.Text = "Deciding this round's executioner hammer..."
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        
        if rarity then
            local spinnerReel = (data.Extra and data.Extra.SpinnerReel) or data.SpinnerReel
            task.spawn(function()
                PlayHammerRoulette(rarity, data.RouletteDuration or 6.0, spinnerReel)
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
-- 9. BIDDING MODAL (COMIC POP-ART STYLE WITH RED X & BID BUTTON)
--------------------------------------------------------------------------------
local closeBidBtn = cardFrame:FindFirstChild("CloseBidBtn", true) or biddingModal:FindFirstChild("CloseBidBtn")
if not closeBidBtn then
    closeBidBtn = Instance.new("TextButton")
    closeBidBtn.Name = "CloseBidBtn"
    closeBidBtn.Size = UDim2.new(0, 36, 0, 34)
    closeBidBtn.Position = UDim2.new(1, -16, 0, 14)
    closeBidBtn.AnchorPoint = Vector2.new(1, 0)
    closeBidBtn.BackgroundColor3 = Color3.fromRGB(245, 0, 0)
    closeBidBtn.Text = "X"
    closeBidBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBidBtn.Font = Enum.Font.GothamBlack
    closeBidBtn.TextSize = 20
    closeBidBtn.ZIndex = 26
    local cbbCorner = Instance.new("UICorner")
    cbbCorner.CornerRadius = UDim.new(0, 6)
    cbbCorner.Parent = closeBidBtn
    local cbbStroke = Instance.new("UIStroke")
    cbbStroke.Thickness = 2
    cbbStroke.Color = Color3.fromRGB(0, 0, 0)
    cbbStroke.Parent = closeBidBtn
    closeBidBtn.Parent = cardFrame
end

closeBidBtn.MouseButton1Click:Connect(function()
    biddingModal.Visible = false
    if IsActiveInRound() then
        reopenBidBtn.Visible = true
        updateCenterDockLayout()
    end
end)

-- 2X Font Size for Bid Input & Strict Dot/Number Filter
bidInput.TextSize = 36
bidInput.Font = Enum.Font.RobotoMono

-- Strictly filter typed input in real-time to numbers and a single decimal point '.'
bidInput:GetPropertyChangedSignal("Text"):Connect(function()
    local text = bidInput.Text
    local filtered = ""
    local hasDot = false
    for i = 1, #text do
        local c = text:sub(i, i)
        if c:match("%d") then
            filtered = filtered .. c
        elseif c == "." and not hasDot then
            filtered = filtered .. c
            hasDot = true
        end
    end
    if text ~= filtered then
        bidInput.Text = filtered
    end
end)

-- Exact SVG.3 Styling for Modal's BID Submit Button
applySVG3ButtonStyle(submitBtn, "BID", 28)

PromptBid.OnClientEvent:Connect(function(data)
    if not IsActiveInRound() then
        biddingModal.Visible = false
        reopenBidBtn.Visible = false
        updateCenterDockLayout()
        return
    end
    HasSubmitted = false
    bidInput.Text = ""
    submittedNotice.Text = ""
    applySVG3ButtonStyle(submitBtn, "BID", 28)
    submitBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    submitBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    submitBtn.Size = UDim2.new(1, 0, 1, 0)
    
    biddingModal.Visible = true
    reopenBidBtn.Visible = false
    updateCenterDockLayout()
    
    -- Smooth pop-in animation
    biddingModal.Size = UDim2.new(0, 540, 0, 304)
    TweenService:Create(biddingModal, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 600, 0, 338)
    }):Play()
end)

local function setBidFraction(frac)
    local wallet = player:GetAttribute("Wallet") or CurrentMoney
    local amt = math.floor((wallet * frac) * 100) / 100
    bidInput.Text = string.format("%.2f", amt)
end

if quickFrame then
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
end

submitBtn.MouseButton1Click:Connect(function()
    if HasSubmitted or not IsActiveInRound() then return end
    local wallet = player:GetAttribute("Wallet") or CurrentMoney
    
    -- Sanitize input: strip any non-digit, non-decimal characters (supports "$2.34", "2.34$", etc.)
    local cleanStr = bidInput.Text:gsub("[^%d%.]", "")
    local val = tonumber(cleanStr) or 0
    val = math.clamp(val, 0, wallet)
    val = math.floor(val * 100) / 100
    
    HasSubmitted = true
    BidSubmitted:FireServer(val)
    
    submitBtn.Text = ""
    local submitGrad = submitBtn:FindFirstChildOfClass("UIGradient")
    if submitGrad then submitGrad.Enabled = false end
    submitBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    local submitLabel = submitBtn:FindFirstChild("BtnLabel") :: TextLabel?
    if submitLabel then
        submitLabel.Text = "SUBMITTED!"
        submitLabel.TextColor3 = Color3.fromRGB(160, 255, 160)
    end
    submittedNotice.Text = string.format("Secret Bid Registered: $%.2f", val)
    
    -- Tactile sound feedback
    pcall(function()
        local clickSound = Instance.new("Sound")
        clickSound.SoundId = "rbxasset://sounds/action_jump.mp3"
        clickSound.Volume = 0.5
        clickSound.Parent = SoundService
        clickSound:Play()
        game:GetService("Debris"):AddItem(clickSound, 1)
    end)
end)

--------------------------------------------------------------------------------
-- 10. LEADERBOARD: PREMIUM CONTENT-ADAPTIVE 4-COLUMN TABLE WITH RED X
--------------------------------------------------------------------------------
RankingsRevealed.OnClientEvent:Connect(function(data)
    if not IsActiveInRound() then
        rankingsModal.Visible = false
        reopenRankBtn.Visible = false
        return
    end
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
    local crbCorner = closeRankBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    crbCorner.CornerRadius = UDim.new(0, 13)
    crbCorner.Parent = closeRankBtn
    closeRankBtn.Parent = rankingsModal
    
    closeRankBtn.MouseButton1Click:Connect(function()
        rankingsModal.Visible = false
        if IsActiveInRound() then
            reopenRankBtn.Visible = true
            updateCenterDockLayout()
        end
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
-- 11. SPECTATOR VOTE POPULATOR
--------------------------------------------------------------------------------
PromptVote.OnClientEvent:Connect(function(data)
    if IsAFK or IsActiveInRound() or CurrentParticipationState ~= "Eliminated" then
        voteModal.Visible = false
        return
    end
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
-- 12. CAMERA SHAKE & SMASH IMPACT FX
--------------------------------------------------------------------------------
HammerSmash.OnClientEvent:Connect(function(data)
    if not IsActiveInRound() then return end
    local rarity = data.Rarity
    local impactDelay = data.ImpactDelay or 1.33
    local myToken = SessionToken
    
    task.delay(impactDelay, function()
        if (not IsActiveInRound()) or myToken ~= SessionToken then return end
        local intensity = rarity and rarity.CameraShake or 1.0
        DoCameraShake(intensity * 3, 0.8)
    end)
end)

RoundOver.OnClientEvent:Connect(function()
    rankingsModal.Visible = false
    reopenRankBtn.Visible = false
    if not reopenBidBtn.Visible then
        reopenContainer.Visible = false
    end
end)

--------------------------------------------------------------------------------
-- 13. MATCH OVER / WINNER CELEBRATION
--------------------------------------------------------------------------------
MatchOver.OnClientEvent:Connect(function(data)
    if IsAFK then return end
    winnerName.Text = (data.Winner or "No One") .. " WINS!"
    matchOverModal.Visible = true
end)
