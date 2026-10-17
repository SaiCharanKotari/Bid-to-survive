-- ClientUIController: Handles all BID TO SURVIVE UI interactions, Hammer Roulette, HUD, and 4-Column Leaderboard
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local player = LocalPlayer
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

local function IsActiveInRound()
    return (CurrentParticipationState == "Active") or (player:GetAttribute("IsInGame") == true)
end

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
    stroke.Thickness = 4
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
    label.TextSize = textSize or 24
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
end

local centerActionDock = gui:FindFirstChild("CenterActionDock") or gui:FindFirstChild("ReopenContainer") or Instance.new("Frame")
centerActionDock.Name = "CenterActionDock"
centerActionDock.AnchorPoint = Vector2.new(0.5, 0.5)
centerActionDock.Position = UDim2.new(0.5, 0, 0.25, 0) -- Exactly middle of upper half (Y = 0.25)
centerActionDock.Size = UDim2.new(0, 184, 0, 50) -- Compact footprint
centerActionDock.BackgroundTransparency = 1
centerActionDock.ZIndex = 35
centerActionDock.Visible = false
centerActionDock.Parent = gui

local reopenContainer = centerActionDock -- Backward compatibility alias

local reopenBidBtn = centerActionDock:FindFirstChild("ReopenBidBtn") or Instance.new("TextButton")
reopenBidBtn.Name = "ReopenBidBtn"
reopenBidBtn.AnchorPoint = Vector2.new(0.5, 0.5)
reopenBidBtn.Size = UDim2.new(0, 184, 0, 50)
reopenBidBtn.Position = UDim2.new(0.5, 0, 0.5, 0) -- Dead-center inside dock
reopenBidBtn.ZIndex = 36
reopenBidBtn.Visible = false
reopenBidBtn.Parent = centerActionDock
applySVG3ButtonStyle(reopenBidBtn, "BID", 24)

local reopenRankBtn = centerActionDock:FindFirstChild("ReopenRankBtn") or Instance.new("TextButton")
reopenRankBtn.Name = "ReopenRankBtn"
reopenRankBtn.AnchorPoint = Vector2.new(0.5, 0.5)
reopenRankBtn.Size = UDim2.new(0, 184, 0, 50)
reopenRankBtn.Position = UDim2.new(0.5, 0, 0.5, 0) -- Exact same position!
reopenRankBtn.ZIndex = 36
reopenRankBtn.Visible = false
reopenRankBtn.Parent = centerActionDock
applySVG3ButtonStyle(reopenRankBtn, "LEADERBOARD", 18)

-- Authoritative visibility controller: strictly dictates BID and LEADERBOARD presence based on game state
local function updateActionButtonsVisibility()
    -- Never show action buttons to lobby players or eliminated/inactive spectators
    if not IsActiveInRound() then
        reopenBidBtn.Visible = false
        reopenRankBtn.Visible = false
        centerActionDock.Visible = false
        return
    end

    if CurrentPhase == "Phase3_Bid" then
        -- During bidding, show BID button ONLY when bidding modal is closed
        local showBid = not biddingModal.Visible
        reopenBidBtn.Visible = showBid
        reopenRankBtn.Visible = false
        centerActionDock.Visible = showBid
    elseif CurrentPhase == "Phase4_Reveal" then
        -- During results/rankings, show LEADERBOARD button in exact same spot ONLY when rankings modal is closed
        local showRank = not rankingsModal.Visible
        reopenBidBtn.Visible = false
        reopenRankBtn.Visible = showRank
        centerActionDock.Visible = showRank
    else
        -- All other phases (Lobby countdown, hammer roulette, voting, tile scramble, smash, settlement, match over): HIDDEN
        reopenBidBtn.Visible = false
        reopenRankBtn.Visible = false
        centerActionDock.Visible = false
    end
end

-- Compatibility wrapper
local function updateCenterDockLayout()
    updateActionButtonsVisibility()
end

local rouletteContainer = gui:FindFirstChild("RouletteContainer") or Instance.new("Frame")
rouletteContainer.Name = "RouletteContainer"
rouletteContainer.Size = UDim2.new(0, 646, 0, 257)
rouletteContainer.Position = UDim2.new(0.5, 0, 0.40, 0)
rouletteContainer.AnchorPoint = Vector2.new(0.5, 0.5)
rouletteContainer.BackgroundTransparency = 1
rouletteContainer.BorderSizePixel = 0
rouletteContainer.Visible = false
rouletteContainer.ZIndex = 30
rouletteContainer.Parent = gui

-- Dynamic Responsive Scaling (Scale 1.25x size as requested, cleanly adapted to viewport)
local rouletteScale = rouletteContainer:FindFirstChild("RouletteScale") or Instance.new("UIScale")
rouletteScale.Name = "RouletteScale"
rouletteScale.Parent = rouletteContainer

local function updateRouletteResponsiveScale()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local scaleW = (vp.X - 32) / 670
    local scaleH = (vp.Y - 120) / 380
    -- Multiplied by 1.25x to make the hammer SVG size 1.25x as requested!
    rouletteScale.Scale = 1.25 * math.clamp(math.min(scaleW, scaleH), 0.52, 1.0)
end
task.defer(updateRouletteResponsiveScale)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    updateRouletteResponsiveScale()
end)

-- 1. SVG.5 BACKGROUND CONTAINER (#FF7700 with rounded corners, 3px black stroke, and 3 slots)
local rouletteBg = rouletteContainer:FindFirstChild("RouletteBg") or Instance.new("ImageLabel")
rouletteBg.Name = "RouletteBg"
rouletteBg.Size = UDim2.new(1, 0, 1, 0)
rouletteBg.Position = UDim2.new(0, 0, 0, 0)
rouletteBg.BackgroundTransparency = 1
rouletteBg.Image = "rbxasset://textures/spin_bg.png"
rouletteBg.ScaleType = Enum.ScaleType.Fit
rouletteBg.ZIndex = 31
rouletteBg.Parent = rouletteContainer

-- Fallback Frame in case local texture is loading
local rouletteBgFallback = rouletteContainer:FindFirstChild("RouletteBgFallback") or Instance.new("Frame")
rouletteBgFallback.Name = "RouletteBgFallback"
rouletteBgFallback.Size = UDim2.new(1, 0, 1, 0)
rouletteBgFallback.BackgroundColor3 = Color3.fromRGB(255, 119, 0)
rouletteBgFallback.BackgroundTransparency = 0
rouletteBgFallback.ZIndex = 30
local bgCorner = Instance.new("UICorner")
bgCorner.CornerRadius = UDim.new(0, 13)
bgCorner.Parent = rouletteBgFallback
local bgStroke = Instance.new("UIStroke")
bgStroke.Color = Color3.fromRGB(0, 0, 0)
bgStroke.Thickness = 3
bgStroke.Parent = rouletteBgFallback
rouletteBgFallback.Parent = rouletteContainer

-- 2. REEL CLIPPER VIEWPORT (Clipped to the 3-slot arena)
-- Coordinates aligned with svg.5 slots: width 566, height 200, centered
local reelClipper = rouletteContainer:FindFirstChild("ReelClipper") or Instance.new("Frame")
reelClipper.Name = "ReelClipper"
reelClipper.Size = UDim2.new(0, 566, 0, 200)
reelClipper.Position = UDim2.new(0.5, 0, 0.5, 0)
reelClipper.AnchorPoint = Vector2.new(0.5, 0.5)
reelClipper.BackgroundTransparency = 1
reelClipper.BorderSizePixel = 0
reelClipper.ClipsDescendants = true
reelClipper.ZIndex = 33
reelClipper.Parent = rouletteContainer

-- Fade Gradient over edges of the Reel (blends cards into the Left & Right tapered orange gradients)
local clipperGradient = reelClipper:FindFirstChild("ClipperGradient") or Instance.new("UIGradient")
clipperGradient.Name = "ClipperGradient"
clipperGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1.00),
    NumberSequenceKeypoint.new(0.08, 0.50),
    NumberSequenceKeypoint.new(0.20, 0.00),
    NumberSequenceKeypoint.new(0.80, 0.00),
    NumberSequenceKeypoint.new(0.92, 0.50),
    NumberSequenceKeypoint.new(1.00, 1.00),
})
clipperGradient.Parent = reelClipper

-- Moving Track for Cards
local reelTrack = reelClipper:FindFirstChild("ReelTrack") or Instance.new("Frame")
reelTrack.Name = "ReelTrack"
reelTrack.Size = UDim2.new(0, 15000, 1, 0)
reelTrack.Position = UDim2.new(0, 0, 0, 0)
reelTrack.BackgroundTransparency = 1
reelTrack.BorderSizePixel = 0
reelTrack.ZIndex = 33
reelTrack.Parent = reelClipper

-- 3. CENTER RESULT SLOT FRAME (Prominent White-Bordered Window from svg.5)
local centerSlotFrame = rouletteContainer:FindFirstChild("CenterSlotFrame") or Instance.new("Frame")
centerSlotFrame.Name = "CenterSlotFrame"
centerSlotFrame.Size = UDim2.new(0, 199, 0, 199)
centerSlotFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
centerSlotFrame.AnchorPoint = Vector2.new(0.5, 0.5)
centerSlotFrame.BackgroundTransparency = 1
centerSlotFrame.BorderSizePixel = 0
centerSlotFrame.ZIndex = 36
local csCorner = Instance.new("UICorner")
csCorner.CornerRadius = UDim.new(0, 5)
csCorner.Parent = centerSlotFrame
local csStroke = Instance.new("UIStroke")
csStroke.Name = "CenterStroke"
csStroke.Color = Color3.fromRGB(255, 255, 255)
csStroke.Thickness = 2.5
csStroke.Parent = centerSlotFrame

-- Top Target Indicator Chevron (Pointing down into winning middle slot)
local topPointer = centerSlotFrame:FindFirstChild("TopPointer") or Instance.new("Frame")
topPointer.Name = "TopPointer"
topPointer.Size = UDim2.new(0, 26, 0, 15)
topPointer.Position = UDim2.new(0.5, 0, 0, -3)
topPointer.AnchorPoint = Vector2.new(0.5, 1)
topPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
topPointer.BorderSizePixel = 0
topPointer.ZIndex = 40
local tpCorner = topPointer:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
tpCorner.CornerRadius = UDim.new(0, 3)
tpCorner.Parent = topPointer
local tpStroke = topPointer:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
tpStroke.Color = Color3.fromRGB(0, 0, 0)
tpStroke.Thickness = 2
tpStroke.Parent = topPointer
local tpArrow = topPointer:FindFirstChild("Arrow") or Instance.new("TextLabel")
tpArrow.Name = "Arrow"
tpArrow.Size = UDim2.new(1, 0, 1, 0)
tpArrow.BackgroundTransparency = 1
tpArrow.Font = Enum.Font.GothamBlack
tpArrow.TextSize = 13
tpArrow.TextColor3 = Color3.fromRGB(0, 0, 0)
tpArrow.Text = "▼"
tpArrow.ZIndex = 41
tpArrow.Parent = topPointer
topPointer.Parent = centerSlotFrame

-- Bottom Target Indicator Chevron (Pointing up into winning middle slot)
local bottomPointer = centerSlotFrame:FindFirstChild("BottomPointer") or Instance.new("Frame")
bottomPointer.Name = "BottomPointer"
bottomPointer.Size = UDim2.new(0, 26, 0, 15)
bottomPointer.Position = UDim2.new(0.5, 0, 1, 3)
bottomPointer.AnchorPoint = Vector2.new(0.5, 0)
bottomPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
bottomPointer.BorderSizePixel = 0
bottomPointer.ZIndex = 40
local bpCorner = bottomPointer:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
bpCorner.CornerRadius = UDim.new(0, 3)
bpCorner.Parent = bottomPointer
local bpStroke = bottomPointer:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
bpStroke.Color = Color3.fromRGB(0, 0, 0)
bpStroke.Thickness = 2
bpStroke.Parent = bottomPointer
local bpArrow = bottomPointer:FindFirstChild("Arrow") or Instance.new("TextLabel")
bpArrow.Name = "Arrow"
bpArrow.Size = UDim2.new(1, 0, 1, 0)
bpArrow.BackgroundTransparency = 1
bpArrow.Font = Enum.Font.GothamBlack
bpArrow.TextSize = 13
bpArrow.TextColor3 = Color3.fromRGB(0, 0, 0)
bpArrow.Text = "▲"
bpArrow.ZIndex = 41
bpArrow.Parent = bottomPointer
bottomPointer.Parent = centerSlotFrame

-- Golden Victory Sunburst Rays (Rotating behind winning hammer)
local sunburstRays = centerSlotFrame:FindFirstChild("SunburstRays") or Instance.new("ImageLabel")
sunburstRays.Name = "SunburstRays"
sunburstRays.Size = UDim2.new(0, 185, 0, 185)
sunburstRays.Position = UDim2.new(0.5, 0, 0.5, -8)
sunburstRays.AnchorPoint = Vector2.new(0.5, 0.5)
sunburstRays.BackgroundTransparency = 1
sunburstRays.Image = "rbxassetid://2583861218"
sunburstRays.ImageColor3 = Color3.fromRGB(255, 225, 100)
sunburstRays.ImageTransparency = 1
sunburstRays.ScaleType = Enum.ScaleType.Fit
sunburstRays.ZIndex = 32
sunburstRays.Visible = false
sunburstRays.Parent = centerSlotFrame

centerSlotFrame.Parent = rouletteContainer

-- 4. BELOW CONTAINER: RARITY TITLE & DAMAGE BADGE/TITLE (Hidden; damage shown directly inside middle slot as +XX dmg)
local rarityTitle = rouletteContainer:FindFirstChild("RarityTitle") or Instance.new("TextLabel")
rarityTitle.Name = "RarityTitle"
rarityTitle.Size = UDim2.new(1, 0, 0, 32)
rarityTitle.Position = UDim2.new(0.5, 0, 1, 12)
rarityTitle.AnchorPoint = Vector2.new(0.5, 0)
rarityTitle.BackgroundTransparency = 1
rarityTitle.Font = Enum.Font.GothamBlack
rarityTitle.TextSize = 24
rarityTitle.TextXAlignment = Enum.TextXAlignment.Center
rarityTitle.TextStrokeTransparency = 0.15
rarityTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
rarityTitle.Visible = false
rarityTitle.ZIndex = 35
rarityTitle.Parent = rouletteContainer

local damageTitle = rouletteContainer:FindFirstChild("DamageTitle") or Instance.new("TextLabel")
damageTitle.Name = "DamageTitle"
damageTitle.Size = UDim2.new(1, 0, 0, 24)
damageTitle.Position = UDim2.new(0.5, 0, 1, 44)
damageTitle.AnchorPoint = Vector2.new(0.5, 0)
damageTitle.BackgroundTransparency = 1
damageTitle.Font = Enum.Font.GothamBold
damageTitle.TextSize = 17
damageTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
damageTitle.TextStrokeTransparency = 0.25
damageTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
damageTitle.TextXAlignment = Enum.TextXAlignment.Center
damageTitle.Visible = false
damageTitle.ZIndex = 35
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
        if elapsed > duration or not IsActiveInRound() then
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
local function IsInPlayground()
    return IsActiveInRound() and (CurrentPhase ~= "Intermission") and (CurrentPhase ~= "MatchOver")
end

local function UpdateHUDVisibility()
    local inPlayground = IsInPlayground()
    if healthBarBg then healthBarBg.Visible = false end
    if cashLabel then cashLabel.Visible = false end
    if statsCard then statsCard.Visible = false end
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
-- 4. TOP PHASE BANNER & ROUND LABEL STYLING (CLEAN FLOATING TEXT, NO BLACK BG)
--------------------------------------------------------------------------------
if topBanner then
    topBanner.BackgroundTransparency = 1
    topBanner.BorderSizePixel = 0
    topBanner.AnchorPoint = Vector2.new(0.5, 0)
    topBanner.Position = UDim2.new(0.5, 0, 0, 10) -- Moved up towards top edge
    topBanner.Size = UDim2.new(0, 420, 0, 54)

    local oldBannerStroke = topBanner:FindFirstChildOfClass("UIStroke")
    if oldBannerStroke then oldBannerStroke:Destroy() end
    local oldBannerCorner = topBanner:FindFirstChildOfClass("UICorner")
    if oldBannerCorner then oldBannerCorner:Destroy() end
end

if infoLabel then
    infoLabel.Visible = false
end

if timerLabel then
    timerLabel.Visible = false
end

if phaseTitle then
    phaseTitle.AnchorPoint = Vector2.new(0.5, 0)
    phaseTitle.Position = UDim2.new(0.5, 0, 0, 0)
    phaseTitle.Size = UDim2.new(1, 0, 0, 26)
    phaseTitle.BackgroundTransparency = 1
    phaseTitle.Font = Enum.Font.GothamBlack
    phaseTitle.TextSize = 22
    phaseTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    phaseTitle.TextXAlignment = Enum.TextXAlignment.Center
    phaseTitle.TextYAlignment = Enum.TextYAlignment.Center

    local pStroke = phaseTitle:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    pStroke.Color = Color3.fromRGB(0, 0, 0)
    pStroke.Thickness = 2.5
    pStroke.Parent = phaseTitle
end

if roundLabel and topBanner then
    roundLabel.Parent = topBanner
    roundLabel.AnchorPoint = Vector2.new(0.5, 0)
    roundLabel.Position = UDim2.new(0.5, 0, 0, 27) -- Cleanly positioned directly below the phase text
    roundLabel.Size = UDim2.new(1, 0, 0, 20)
    roundLabel.BackgroundTransparency = 1
    roundLabel.Font = Enum.Font.GothamBold
    roundLabel.TextSize = 13
    roundLabel.TextColor3 = Color3.fromRGB(210, 225, 245)
    roundLabel.TextXAlignment = Enum.TextXAlignment.Center
    roundLabel.TextYAlignment = Enum.TextYAlignment.Center

    local rStroke = roundLabel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    rStroke.Color = Color3.fromRGB(0, 0, 0)
    rStroke.Thickness = 2
    rStroke.Parent = roundLabel
end

if statsCard then
    statsCard.Visible = false
end

UpdateHUDVisibility()

if rarityBadge then
    rarityBadge.Visible = false
end

--------------------------------------------------------------------------------
-- SETTINGS GEAR & AFK TOGGLE BUTTON (MIDDLE-LEFT DOCK)
--------------------------------------------------------------------------------
-- Clean up any legacy top-left instances directly under gui to prevent duplicates
local legacySettings = gui:FindFirstChild("SettingsButton")
if legacySettings and legacySettings.Parent == gui then legacySettings:Destroy() end
local legacyAFK = gui:FindFirstChild("AFKButton")
if legacyAFK and legacyAFK.Parent == gui then legacyAFK:Destroy() end

local leftControlsDock = gui:FindFirstChild("LeftControlsDock") or Instance.new("Frame")
leftControlsDock.Name = "LeftControlsDock"
leftControlsDock.AnchorPoint = Vector2.new(0, 0.5)
leftControlsDock.Position = UDim2.new(0, 24, 0.5, 0) -- Responsive middle-left with safe margins
leftControlsDock.Size = UDim2.new(0, 134, 0, 84)
leftControlsDock.BackgroundTransparency = 1
leftControlsDock.ZIndex = 20
leftControlsDock.Parent = gui

local settingsButton = leftControlsDock:FindFirstChild("SettingsButton") or Instance.new("ImageButton")
settingsButton.Name = "SettingsButton"
settingsButton.AnchorPoint = Vector2.new(0, 0)
settingsButton.Position = UDim2.new(0, 0, 0, 0)
settingsButton.Size = UDim2.new(0, 36, 0, 36) -- Compact 36x36 (down from 48x48)
settingsButton.BackgroundTransparency = 1
settingsButton.Image = "rbxassetid://6031280882" -- Clean vector gear icon
settingsButton.ImageColor3 = Color3.fromRGB(240, 240, 240)
settingsButton.ZIndex = 21
settingsButton.Parent = leftControlsDock

settingsButton.MouseButton1Click:Connect(function()
    pcall(function()
        game:GetService("GuiService"):SetMenuIsOpen(true)
    end)
end)

local afkButton = leftControlsDock:FindFirstChild("AFKButton") or Instance.new("TextButton")
afkButton.Name = "AFKButton"
afkButton.AnchorPoint = Vector2.new(0, 0)
afkButton.Position = UDim2.new(0, 0, 0, 44) -- Directly below Settings with clean 8px gap
afkButton.Size = UDim2.new(0, 130, 0, 34) -- Compact 130x34 (target: 125-135px wide, 32-38px tall)
afkButton.Font = Enum.Font.GothamBold
afkButton.TextSize = 14 -- Restrained, clear font size
afkButton.TextColor3 = Color3.fromRGB(0, 0, 0)
afkButton.ZIndex = 21
afkButton.AutoButtonColor = false

local afkCorner = afkButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
afkCorner.CornerRadius = UDim.new(0, 4)
afkCorner.Parent = afkButton

local afkStroke = afkButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
afkStroke.Thickness = 2 -- Reduced from heavy 3px to clean 2px
afkStroke.Color = Color3.fromRGB(0, 0, 0)
afkStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
afkStroke.Parent = afkButton

local function UpdateAFKVisual()
    if IsAFK then
        afkButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Yellow when ON
        afkButton.Text = "AFK: ON" -- Text with clean space as requested
    else
        afkButton.BackgroundColor3 = Color3.fromRGB(0, 200, 80) -- Clean green when OFF
        afkButton.Text = "AFK: OFF"
    end
end

UpdateAFKVisual()
afkButton.Parent = leftControlsDock

afkButton.MouseButton1Click:Connect(function()
    IsAFK = not IsAFK
    UpdateAFKVisual()
    SetAFK:FireServer(IsAFK)
end)

--------------------------------------------------------------------------------
-- REOPEN BUTTON CLICKS
--------------------------------------------------------------------------------
reopenBidBtn.MouseButton1Click:Connect(function()
    if not IsActiveInRound() or CurrentPhase ~= "Phase3_Bid" then return end
    biddingModal.Visible = true
    updateActionButtonsVisibility()
end)

reopenRankBtn.MouseButton1Click:Connect(function()
    if not IsActiveInRound() or CurrentPhase ~= "Phase4_Reveal" then return end
    rankingsModal.Visible = true
    updateActionButtonsVisibility()
end)

--------------------------------------------------------------------------------
-- 5. NEW 3-SLOT HORIZONTAL LEFT-TO-RIGHT HAMMER SPIN SYSTEM (SVG.5)
--------------------------------------------------------------------------------
local function PlayHammerRoulette(targetRarity, totalDuration, spinnerReel)
    if IsRoulettePlaying or (not IsActiveInRound()) then return end
    IsRoulettePlaying = true
    local myToken = SessionToken
    
    updateRouletteResponsiveScale()
    
    -- Ensure external titles below box stay hidden (user image shows only the 646x257 box)
    rarityTitle.Visible = false
    damageTitle.Visible = false
    
    -- Reset center highlight stroke to pristine white
    local csStroke = centerSlotFrame:FindFirstChild("CenterStroke") :: UIStroke?
    if csStroke then
        csStroke.Color = Color3.fromRGB(255, 255, 255)
        csStroke.Thickness = 2.0
        csStroke.Transparency = 0
    end
    
    -- Clear previous items on reelTrack
    for _, child in ipairs(reelTrack:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    
    local CARD_STEP = 190 -- Exactly 190px spacing between left (93), center (283), and right (473)
    local TOTAL_CARDS = 60 -- Big array of hammers!
    local WIN_INDEX = 10 -- Target hammer arrives at index 10
    local SPIN_TRAVEL_CARDS = 35 -- 35 cards glide past from left to right!
    
    -- Build randomized reel with diverse rarities ending on targetRarity
    local raritiesList = GameConfig.GetRarityList and GameConfig.GetRarityList() or {}
    if #raritiesList == 0 then
        for _, name in ipairs(GameConfig.RarityOrder or {"Common", "Uncommon", "Rare", "Legendary", "Mythical"}) do
            table.insert(raritiesList, GameConfig.HammerRarities[name])
        end
    end
    
    local reelData = {}
    for i = 1, TOTAL_CARDS do
        if i == WIN_INDEX then
            reelData[i] = targetRarity
        elseif i == WIN_INDEX + 1 then
            -- Hammer that lands in the right slot: golden Legendary/Mythical hammer like mockup
            local alt = GameConfig.HammerRarities.Legendary or GameConfig.HammerRarities.Mythical
            if alt and alt.Name == targetRarity.Name then
                alt = GameConfig.HammerRarities.Rare or GameConfig.HammerRarities.Common
            end
            reelData[i] = alt or targetRarity
        elseif i == WIN_INDEX - 1 then
            -- Hammer that lands in the left slot
            local alt = GameConfig.HammerRarities.Rare or GameConfig.HammerRarities.Uncommon
            if alt and alt.Name == targetRarity.Name then
                alt = GameConfig.HammerRarities.Common
            end
            reelData[i] = alt or targetRarity
        elseif spinnerReel and spinnerReel[i] and GameConfig.HammerRarities[spinnerReel[i]] then
            reelData[i] = GameConfig.HammerRarities[spinnerReel[i]]
        else
            local pick = raritiesList[math.random(1, #raritiesList)]
            if i > 1 and reelData[i - 1] and reelData[i - 1].Name == pick.Name then
                local alt = raritiesList[(math.random(1, #raritiesList - 1))]
                pick = (alt and alt.Name ~= pick.Name) and alt or raritiesList[1]
            end
            reelData[i] = pick or targetRarity
        end
    end
    
    -- Populate hammer items (NO card backgrounds, NO borders; purely floating hammers + "+XX dmg" text)
    local items = {}
    for i = 1, TOTAL_CARDS do
        local rData = reelData[i]
        local itemFrame = Instance.new("Frame")
        itemFrame.Name = "HammerItem_" .. i
        itemFrame.Size = UDim2.new(0, 190, 0, 199)
        itemFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        local cardCenterX = (i - 1) * CARD_STEP
        itemFrame.Position = UDim2.new(0, cardCenterX, 0.5, 0)
        itemFrame.BackgroundTransparency = 1
        itemFrame.BorderSizePixel = 0
        itemFrame.ZIndex = 34
        
        -- Hammer Icon (140x140, floating directly in the slot)
        local icon = Instance.new("ImageLabel")
        icon.Name = "HammerIcon"
        icon.Size = UDim2.new(0, 140, 0, 140)
        icon.Position = UDim2.new(0.5, 0, 0, 14)
        icon.AnchorPoint = Vector2.new(0.5, 0)
        icon.BackgroundTransparency = 1
        icon.ScaleType = Enum.ScaleType.Fit
        local assetId = rData.AssetId
        if not assetId or assetId == "" or PendingAssets[assetId] then
            assetId = VERIFIED_BASE_HAMMER
        end
        icon.Image = assetId
        icon.ZIndex = 35
        icon.Parent = itemFrame
        
        -- Damage Label: "+60 dmg" directly underneath the hammer (matching user's attached image)
        local dmgLabel = Instance.new("TextLabel")
        dmgLabel.Name = "DmgLabel"
        dmgLabel.Size = UDim2.new(1, 0, 0, 26)
        dmgLabel.Position = UDim2.new(0.5, 0, 1, -16)
        dmgLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        dmgLabel.BackgroundTransparency = 1
        dmgLabel.Font = Enum.Font.FredokaOne
        dmgLabel.TextSize = 22
        dmgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        dmgLabel.Text = string.format("+%d dmg", rData.DamagePercent or 30)
        dmgLabel.TextXAlignment = Enum.TextXAlignment.Center
        dmgLabel.TextStrokeTransparency = 0.5
        dmgLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        dmgLabel.ZIndex = 36
        dmgLabel.Parent = itemFrame
        
        itemFrame.Parent = reelTrack
        items[i] = {
            frame = itemFrame,
            icon = icon,
            label = dmgLabel,
            relX = cardCenterX
        }
    end
    
    -- Slot alignment math:
    -- ReelClipper is 566px wide -> center is X = 283 (which is exactly Middle Slot center!)
    -- Card WIN_INDEX must finish exactly at center (283)
    local targetCardCenter = (WIN_INDEX - 1) * CARD_STEP
    local trackX_final = 283 - targetCardCenter
    
    -- LEFT-TO-RIGHT SPIN:
    -- Cards travel towards the right (+X direction).
    -- Start position is to the left (smaller X) and glides rightwards to trackX_final!
    local travelDistance = SPIN_TRAVEL_CARDS * CARD_STEP
    local trackX_start = trackX_final - travelDistance
    
    -- Real-time 3D Perspective & Opacity updater based on distance from center slot (X = 283)
    -- Middle hammer: full crisp 1.0 scale (140px), 0.0 transparency, and "+XX dmg" text.
    -- Side hammers: tapered 3D depth scaling (0.84 scale, 0.45 transparency in side slots).
    -- Exiting hammers: shrink to 0.68 scale and fade out completely (dist >= 270 -> Visible = false).
    local function updateOpacities(curTrackX)
        for i = 1, TOTAL_CARDS do
            local it = items[i]
            local screenX = curTrackX + it.relX
            local dist = math.abs(screenX - 283)
            if dist >= 270 then
                it.frame.Visible = false
                it.icon.ImageTransparency = 1
                it.label.TextTransparency = 1
            else
                it.frame.Visible = true
                local currentScale = 1.0
                if dist <= 40 then
                    -- Solid center hammer: full size (140px)
                    it.icon.ImageTransparency = 0
                    currentScale = 1.0
                elseif dist <= 190 then
                    -- Smooth fade and 3D perspective depth towards side slots (1.0 -> 0.84 scale, 0.0 -> 0.45 transparency)
                    local t = (dist - 40) / 150
                    it.icon.ImageTransparency = t * 0.45
                    currentScale = 1.0 - (t * 0.16)
                else
                    -- Exiting side slots: shrink to 0.68 scale, fade out to 1.0
                    local t = (dist - 190) / 80
                    it.icon.ImageTransparency = math.clamp(0.45 + t * 0.55, 0, 1)
                    currentScale = math.clamp(0.84 - (t * 0.16), 0.68, 0.84)
                end
                
                local iconSize = math.round(140 * currentScale)
                local iconY = math.round(14 + (140 - iconSize) * 0.5)
                it.icon.Size = UDim2.new(0, iconSize, 0, iconSize)
                it.icon.Position = UDim2.new(0.5, 0, 0, iconY)
                
                -- Damage text "+60 dmg" is only displayed when centered in the middle slot
                if dist <= 25 then
                    it.label.TextTransparency = 0
                    it.label.Visible = true
                elseif dist <= 55 then
                    it.label.TextTransparency = (dist - 25) / 30
                    it.label.Visible = true
                else
                    it.label.TextTransparency = 1
                    it.label.Visible = false
                end
            end
        end
    end
    
    -- Slot alignment math:
    -- ReelClipper is 566px wide -> center is X = 283 (which is exactly Middle Slot center!)
    -- Card WIN_INDEX finishes centered at X = 283
    local targetCardCenter = (WIN_INDEX - 1) * CARD_STEP
    local trackX_final = 283 - targetCardCenter
    
    -- LEFT-TO-RIGHT SPIN:
    -- Cards travel towards the right (+X direction).
    local travelDistance = SPIN_TRAVEL_CARDS * CARD_STEP
    local trackX_start = trackX_final - travelDistance
    -- Stage 1 Overshoot (+12px past center for peak suspense before recoil lock!)
    local trackX_overshoot = trackX_final + 12
    
    -- Micro-kick on top and bottom pointer needles
    local function kickNeedles()
        if topPointer then
            topPointer.Position = UDim2.new(0.5, 0, 0, -6)
            TweenService:Create(topPointer, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0, -3)
            }):Play()
        end
        if bottomPointer then
            bottomPointer.Position = UDim2.new(0.5, 0, 1, 6)
            TweenService:Create(bottomPointer, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 1, 3)
            }):Play()
        end
    end
    
    -- Pre-position and update opacities BEFORE making UI visible (ZERO GAP / NO PAUSE!)
    reelTrack.Position = UDim2.new(0, math.round(trackX_start), 0, 0)
    updateOpacities(trackX_start)
    
    -- STAGE 1: Fast Spin + Quart Deceleration to Overshoot (4.30s)
    local spinProgress = Instance.new("NumberValue")
    spinProgress.Value = 0
    
    local lastTickStep = -1
    local progressConn = spinProgress.Changed:Connect(function(val)
        if (not IsActiveInRound()) or myToken ~= SessionToken then return end
        local curX = trackX_start + (trackX_overshoot - trackX_start) * val
        reelTrack.Position = UDim2.new(0, math.round(curX), 0, 0)
        updateOpacities(curX)
        
        -- Multi-pitch dynamic ticker audio + needle kick
        local currentStep = math.floor((curX - trackX_start) / CARD_STEP)
        if currentStep ~= lastTickStep and currentStep >= 0 then
            lastTickStep = currentStep
            kickNeedles()
            
            pcall(function()
                local tickSound = Instance.new("Sound")
                tickSound.SoundId = "rbxassetid://6895079853" -- Crisp mechanical click
                local basePitch = 1.55 - (val * 0.70) -- Pitch slides down from 1.55 to 0.85
                tickSound.PlaybackSpeed = math.clamp(basePitch, 0.85, 1.65)
                tickSound.Volume = (val >= 0.85) and 0.40 or (0.16 + val * 0.14)
                tickSound.Parent = SoundService
                tickSound:Play()
                Debris:AddItem(tickSound, 0.25)
                
                -- Layer heavier thud on final crawling hammers (intense suspense!)
                if val >= 0.85 then
                    local thud = Instance.new("Sound")
                    thud.SoundId = "rbxasset://sounds/action_jump.mp3"
                    thud.PlaybackSpeed = 0.82
                    thud.Volume = 0.28
                    thud.Parent = SoundService
                    thud:Play()
                    Debris:AddItem(thud, 0.3)
                end
            end)
        end
    end)
    
    -- Award-winning Quart deceleration curve
    local spinTween1 = TweenService:Create(spinProgress, TweenInfo.new(4.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Value = 1
    })
    
    -- Start spinning and reveal UI container simultaneously (ZERO GAP!)
    spinTween1:Play()
    rouletteContainer.Visible = true
    
    spinTween1.Completed:Wait()
    progressConn:Disconnect()
    spinProgress:Destroy()
    
    if (not IsActiveInRound()) or myToken ~= SessionToken then
        rouletteContainer.Visible = false
        IsRoulettePlaying = false
        return
    end
    
    -- STAGE 2: Suspense Breath (0.06s) + Elastic Recoil Snap Lock (-12px back to center)
    task.wait(0.06)
    
    local recoilProgress = Instance.new("NumberValue")
    recoilProgress.Value = 0
    local recoilConn = recoilProgress.Changed:Connect(function(rVal)
        if (not IsActiveInRound()) or myToken ~= SessionToken then return end
        local rX = trackX_overshoot + (trackX_final - trackX_overshoot) * rVal
        reelTrack.Position = UDim2.new(0, math.round(rX), 0, 0)
        updateOpacities(rX)
    end)
    
    local recoilTween = TweenService:Create(recoilProgress, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Value = 1
    })
    recoilTween:Play()
    kickNeedles()
    
    -- Crisp mechanical lock click on recoil snap
    pcall(function()
        local lockSound = Instance.new("Sound")
        lockSound.SoundId = "rbxassetid://6895079853"
        lockSound.PlaybackSpeed = 1.05
        lockSound.Volume = 0.55
        lockSound.Parent = SoundService
        lockSound:Play()
        Debris:AddItem(lockSound, 0.3)
    end)
    
    recoilTween.Completed:Wait()
    recoilConn:Disconnect()
    recoilProgress:Destroy()
    
    if (not IsActiveInRound()) or myToken ~= SessionToken then
        rouletteContainer.Visible = false
        IsRoulettePlaying = false
        return
    end
    
    -- Perfect pixel lock on winning hammer
    reelTrack.Position = UDim2.new(0, math.round(trackX_final), 0, 0)
    updateOpacities(trackX_final)
    
    -- GRAND VICTORY REVEAL & CELEBRATION (Blade Ball / Pet Simulator 99 AAA Juice)
    local winningItem = items[WIN_INDEX]
    local raySpinConn = nil
    
    -- 1. Rotating Golden Victory Sunburst Rays behind winning hammer
    if sunburstRays then
        sunburstRays.Visible = true
        sunburstRays.ImageTransparency = 0.55
        sunburstRays.Rotation = 0
        raySpinConn = RunService.RenderStepped:Connect(function(dt)
            sunburstRays.Rotation = (sunburstRays.Rotation + dt * 60) % 360
        end)
    end
    
    -- 2. Hammer Elastic Scale Punch & Playful Rotation Wiggle
    if winningItem then
        winningItem.icon.Size = UDim2.new(0, 168, 0, 168)
        winningItem.icon.Position = UDim2.new(0.5, 0, 0, 0)
        winningItem.icon.Rotation = -6
        TweenService:Create(winningItem.icon, TweenInfo.new(0.40, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 148, 0, 148),
            Position = UDim2.new(0.5, 0, 0, 10),
            Rotation = 0
        }):Play()
        
        -- Punch on "+XX dmg" text with radiant gold highlight
        winningItem.label.TextSize = 27
        winningItem.label.TextColor3 = Color3.fromRGB(255, 245, 180)
        TweenService:Create(winningItem.label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            TextSize = 22,
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
    end
    
    -- 3. Center Slot Highlight Frame Neon Pulse
    local targetGlowColor = targetRarity.GlowColor or targetRarity.Color or Color3.fromRGB(255, 220, 50)
    if csStroke then
        csStroke.Color = targetGlowColor
        csStroke.Thickness = 4.5
        TweenService:Create(csStroke, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Thickness = 2.5
        }):Play()
    end
    
    -- 4. Target Needles Gold Flare
    if topPointer and bottomPointer then
        topPointer.BackgroundColor3 = targetGlowColor
        bottomPointer.BackgroundColor3 = targetGlowColor
    end
    
    -- 5. Camera Impact & Level-Up Fanfare Audio
    DoCameraShake(targetRarity.CameraShake or 1.1, 0.45)
    pcall(function()
        local winSound = Instance.new("Sound")
        winSound.SoundId = "rbxasset://sounds/action_get_up.mp3"
        winSound.PlaybackSpeed = 1.05
        winSound.Volume = 0.85
        winSound.Parent = SoundService
        winSound:Play()
        Debris:AddItem(winSound, 1.8)
    end)
    
    -- Hold for 2.0 seconds so player admires their new weapon and damage
    task.wait(2.0)
    
    if (not IsActiveInRound()) or myToken ~= SessionToken then
        if raySpinConn then raySpinConn:Disconnect() end
        if sunburstRays then sunburstRays.Visible = false end
        rouletteContainer.Visible = false
        IsRoulettePlaying = false
        return
    end
    
    -- Clean fade-out before next phase
    local fadeTween = TweenService:Create(rouletteBg, TweenInfo.new(0.35), { ImageTransparency = 1 })
    fadeTween:Play()
    if csStroke then
        TweenService:Create(csStroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
    end
    if topPointer and bottomPointer then
        local tpSt = topPointer:FindFirstChildOfClass("UIStroke")
        local bpSt = bottomPointer:FindFirstChildOfClass("UIStroke")
        if tpSt then TweenService:Create(tpSt, TweenInfo.new(0.35), { Transparency = 1 }):Play() end
        if bpSt then TweenService:Create(bpSt, TweenInfo.new(0.35), { Transparency = 1 }):Play() end
    end
    if sunburstRays then
        TweenService:Create(sunburstRays, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
    end
    if winningItem then
        TweenService:Create(winningItem.icon, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
        TweenService:Create(winningItem.label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
    end
    task.wait(0.35)
    
    if raySpinConn then raySpinConn:Disconnect() end
    if sunburstRays then
        sunburstRays.Visible = false
        sunburstRays.ImageTransparency = 1
    end
    rouletteContainer.Visible = false
    rouletteBg.ImageTransparency = 0
    if csStroke then
        csStroke.Transparency = 0
        csStroke.Thickness = 2.5
        csStroke.Color = Color3.fromRGB(255, 255, 255)
    end
    if topPointer and bottomPointer then
        topPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        bottomPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        local tpSt = topPointer:FindFirstChildOfClass("UIStroke")
        local bpSt = bottomPointer:FindFirstChildOfClass("UIStroke")
        if tpSt then tpSt.Transparency = 0 end
        if bpSt then bpSt.Transparency = 0 end
    end
    IsRoulettePlaying = false
end

--------------------------------------------------------------------------------
-- 6. FRAME-ACCURATE AUTHORITATIVE COUNTDOWN TICKER (<Phase> - <time>s)
--------------------------------------------------------------------------------
local function getSimplePhaseName(phase: string?): string
    if not phase then return "" end
    if phase == "Phase6_Smash" then
        return "Smash"
    elseif phase == "Phase5_Scramble" then
        return "Survival Stance"
    elseif phase == "Phase3_Bid" then
        return "Bidding"
    elseif phase == "Phase4_Reveal" then
        return "Rankings"
    elseif phase == "Phase1_Spawn" then
        return "Hammer Reveal"
    elseif phase == "Phase2_Vote" then
        return "Vote"
    elseif phase == "Phase7_Settlement" then
        return "Settlement"
    elseif phase == "Intermission" then
        return "Lobby"
    elseif phase == "MatchOver" then
        return "Match Over"
    else
        return (phase:gsub("^Phase%d*_*", ""))
    end
end

RunService.Heartbeat:Connect(function()
    -- Players in the lobby must NOT see any ongoing game UI or phase countdowns
    if not IsActiveInRound() and CurrentPhase ~= "Intermission" then
        if topBanner and topBanner.Visible then
            topBanner.Visible = false
        end
        if phaseTitle and phaseTitle.Text ~= "" then
            phaseTitle.Text = ""
        end
        return
    end

    if CurrentPhaseDeadline > 0 and (IsActiveInRound() or (CurrentPhase == "Intermission" and not IsAFK and topBanner.Visible)) then
        local remaining = math.max(0, math.ceil(CurrentPhaseDeadline - os.clock()))
        local simpleName = getSimplePhaseName(CurrentPhase)
        if phaseTitle then
            phaseTitle.Text = string.format("%s - %ds", simpleName, remaining)
        end
    elseif phaseTitle then
        local simpleName = getSimplePhaseName(CurrentPhase)
        if simpleName ~= "" and simpleName ~= "Lobby" and IsActiveInRound() then
            phaseTitle.Text = string.format("%s - 0s", simpleName)
        else
            phaseTitle.Text = ""
        end
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
    else
        updateActionButtonsVisibility()
    end
end)

ParticipationChanged.OnClientEvent:Connect(function(newState)
    if newState then
        CurrentParticipationState = newState
    end
    UpdateHUDVisibility()
    if not IsActiveInRound() then
        ForceHideAllRoundUI()
    else
        updateActionButtonsVisibility()
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
    
    -- Strict isolation: Players in lobby must NOT see any ongoing game UI
    if not IsActiveInRound() then
        ForceHideAllRoundUI()
        if phase == "Intermission" then
            if IsAFK then
                topBanner.Visible = false
            else
                topBanner.Visible = true
                if roundLabel then roundLabel.Text = "WAITING IN LOBBY" end
            end
        else
            topBanner.Visible = false
        end
        return
    end

    if roundLabel then
        roundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
    end
    
    updateActionButtonsVisibility()
    
    if phase == "Intermission" then
        topBanner.Visible = true
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        matchOverModal.Visible = false
        rouletteContainer.Visible = false
        updateActionButtonsVisibility()
        return
    end
    
    if phase == "Phase1_Spawn" then
        topBanner.Visible = true
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        updateActionButtonsVisibility()
        
        if rarity then
            local spinnerReel = (data.Extra and data.Extra.SpinnerReel) or data.SpinnerReel
            task.spawn(function()
                PlayHammerRoulette(rarity, data.RouletteDuration or 6.0, spinnerReel)
            end)
        end
        
    elseif phase == "Phase2_Vote" then
        topBanner.Visible = true
        rouletteContainer.Visible = false
        biddingModal.Visible = false
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "Phase3_Bid" then
        topBanner.Visible = true
        rouletteContainer.Visible = false
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "Phase4_Reveal" then
        topBanner.Visible = false
        biddingModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "Phase5_Scramble" then
        topBanner.Visible = true
        rankingsModal.Visible = false
        biddingModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "Phase6_Smash" then
        topBanner.Visible = true
        biddingModal.Visible = false
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "Phase7_Settlement" then
        topBanner.Visible = true
        biddingModal.Visible = false
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
        
    elseif phase == "MatchOver" then
        topBanner.Visible = false
        biddingModal.Visible = false
        rankingsModal.Visible = false
        voteModal.Visible = false
        rouletteContainer.Visible = false
        updateActionButtonsVisibility()
    end
end)

--------------------------------------------------------------------------------
-- 9. BIDDING MODAL (COMIC POP-ART STYLE WITH RED X & BID BUTTON)
--------------------------------------------------------------------------------
local closeBidBtn = cardFrame:FindFirstChild("CloseBidBtn", true) or biddingModal:FindFirstChild("CloseBidBtn")
if not closeBidBtn then
    closeBidBtn = Instance.new("TextButton")
    closeBidBtn.Name = "CloseBidBtn"
    closeBidBtn.Size = UDim2.new(0, 32, 0, 30)
    closeBidBtn.Position = UDim2.new(1, -14, 0, 12)
    closeBidBtn.AnchorPoint = Vector2.new(1, 0)
    closeBidBtn.BackgroundColor3 = Color3.fromRGB(245, 0, 0)
    closeBidBtn.Text = "X"
    closeBidBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBidBtn.Font = Enum.Font.GothamBlack
    closeBidBtn.TextSize = 18
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
    updateActionButtonsVisibility()
end)

-- Sized proportionally for compact modal & Strict Dot/Number Filter
bidInput.TextSize = 30
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
applySVG3ButtonStyle(submitBtn, "BID", 24)

PromptBid.OnClientEvent:Connect(function(data)
    CurrentPhase = "Phase3_Bid"
    if not IsActiveInRound() then
        biddingModal.Visible = false
        updateActionButtonsVisibility()
        return
    end
    HasSubmitted = false
    bidInput.Text = ""
    submittedNotice.Text = ""
    applySVG3ButtonStyle(submitBtn, "BID", 24)
    submitBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    submitBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    submitBtn.Size = UDim2.new(1, 0, 1, 0)
    
    local titleLabel = cardFrame:FindFirstChild("TitleLabel")
    if titleLabel then
        titleLabel.AnchorPoint = Vector2.new(0.5, 0)
        titleLabel.Position = UDim2.new(0.5, 0, 0, 26)
        titleLabel.Size = UDim2.new(0.85, 0, 0, 32)
    end

    bidInput.AnchorPoint = Vector2.new(0.5, 0)
    bidInput.Position = UDim2.new(0.5, 0, 0, 72)
    bidInput.Size = UDim2.new(0, 240, 0, 42)
    bidInput.TextSize = 24
    
    local btnContainer = cardFrame:FindFirstChild("BidBtnContainer")
    if btnContainer then
        btnContainer.AnchorPoint = Vector2.new(0.5, 0)
        btnContainer.Position = UDim2.new(0.5, 0, 0, 134)
        btnContainer.Size = UDim2.new(0, 180, 0, 46)
    end

    local submittedNotice = cardFrame:FindFirstChild("SubmittedNotice")
    if submittedNotice then
        submittedNotice.AnchorPoint = Vector2.new(0.5, 0)
        submittedNotice.Position = UDim2.new(0.5, 0, 0, 192)
        submittedNotice.Size = UDim2.new(0.85, 0, 0, 20)
    end

    biddingModal.Visible = true
    updateActionButtonsVisibility()
    
    -- Smooth pop-in animation (compact 480x250, zero overlap)
    biddingModal.Size = UDim2.new(0, 430, 0, 220)
    TweenService:Create(biddingModal, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 480, 0, 250)
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
-- 10. LEADERBOARD: POP-ART COMIC DESIGN WITH AVATARS, DISPLAY NAMES & ZERO CLIPPING
--------------------------------------------------------------------------------

local RESULTS_BG_ASSET = "rbxassetid://136247699248783"

local function resolvePlayerDisplayName(pData): string
    if not pData then return "Player" end
    if pData.UserId == player.UserId then
        return player.DisplayName
    end
    if pData.DisplayName and #pData.DisplayName > 0 then
        return pData.DisplayName
    end
    if pData.UserId and pData.UserId > 0 then
        local realP = Players:GetPlayerByUserId(pData.UserId)
        if realP then return realP.DisplayName end
    end
    return pData.Name or "Player"
end

local function ensureRankingsStructure()
    rankingsModal.AnchorPoint = Vector2.new(0.5, 0.5)
    rankingsModal.Position = UDim2.new(0.5, 0, 0.5, 0)
    rankingsModal.BackgroundTransparency = 1
    rankingsModal.BorderSizePixel = 0

    local shadowFrame = rankingsModal:FindFirstChild("ShadowFrame") or Instance.new("Frame")
    shadowFrame.Name = "ShadowFrame"
    shadowFrame.Size = UDim2.new(1, -12, 1, -12)
    shadowFrame.Position = UDim2.new(0, 12, 0, 12)
    shadowFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadowFrame.BorderSizePixel = 0
    shadowFrame.ZIndex = 20
    local sCorner = shadowFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    sCorner.CornerRadius = UDim.new(0, 8)
    sCorner.Parent = shadowFrame
    shadowFrame.Parent = rankingsModal

    local cardFrame = rankingsModal:FindFirstChild("CardFrame") or Instance.new("Frame")
    cardFrame.Name = "CardFrame"
    cardFrame.Size = UDim2.new(1, -12, 1, -12)
    cardFrame.Position = UDim2.new(0, 0, 0, 0)
    cardFrame.BackgroundColor3 = Color3.fromRGB(242, 118, 16)
    cardFrame.BorderSizePixel = 0
    cardFrame.ZIndex = 22
    local cCorner = cardFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = cardFrame

    local cStroke = cardFrame:FindFirstChild("CardStroke") or cardFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    cStroke.Name = "CardStroke"
    cStroke.Color = Color3.fromRGB(0, 0, 0)
    cStroke.Thickness = 5
    cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cStroke.LineJoinMode = Enum.LineJoinMode.Round
    cStroke.Parent = cardFrame

    local bgImage = cardFrame:FindFirstChild("BgImage") or Instance.new("ImageLabel")
    bgImage.Name = "BgImage"
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.Position = UDim2.new(0, 0, 0, 0)
    bgImage.BackgroundTransparency = 1
    bgImage.Image = RESULTS_BG_ASSET
    bgImage.ScaleType = Enum.ScaleType.Crop
    bgImage.ZIndex = 23
    local bgCorner = bgImage:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 8)
    bgCorner.Parent = bgImage
    bgImage.Parent = cardFrame

    cardFrame.Parent = rankingsModal

    return shadowFrame, cardFrame
end

RankingsRevealed.OnClientEvent:Connect(function(data)
    CurrentPhase = "Phase4_Reveal"
    if not IsActiveInRound() then
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
        return
    end
    topBanner.Visible = false -- Explicitly hide top banner to prevent collision with modal title!
    
    local allBidders = {}
    local safeCount = data.SafeCount or 1
    for _, p in ipairs(data.TopBidders or {}) do table.insert(allBidders, p) end
    for _, p in ipairs(data.BottomBidders or {}) do table.insert(allBidders, p) end
    
    local rowCount = #allBidders
    local rowHeight = 40
    local rowPadding = 5
    local tableContentHeight = rowCount * (rowHeight + rowPadding)
    
    local desiredHeight = 102 + tableContentHeight + 14
    local modalHeight = math.clamp(desiredHeight, 300, 580)
    
    local shadowFrame, cardFrame = ensureRankingsStructure()
    rankingsModal.Size = UDim2.new(0, 600, 0, modalHeight)
    rankingsModal.AnchorPoint = Vector2.new(0.5, 0.5)
    rankingsModal.Position = UDim2.new(0.5, 0, 0.5, 0)
    
    -- Clear previous dynamic contents inside cardFrame
    for _, child in ipairs(cardFrame:GetChildren()) do
        if child.Name == "HeaderFrame" or child.Name == "LeaderboardScroll" or child.Name == "TitleHeader" or child.Name == "CloseRankBtn" or child.Name == "FooterStatement" then
            child:Destroy()
        end
    end
    -- Also clean any legacy children directly on rankingsModal
    for _, child in ipairs(rankingsModal:GetChildren()) do
        if child.Name == "HeaderFrame" or child.Name == "LeaderboardScroll" or child.Name == "TitleHeader" or child.Name == "CloseRankBtn" or child.Name == "FooterStatement" then
            child:Destroy()
        end
    end
    
    -- Red X Close Button on CardFrame
    local closeRankBtn = Instance.new("TextButton")
    closeRankBtn.Name = "CloseRankBtn"
    closeRankBtn.Size = UDim2.new(0, 32, 0, 30)
    closeRankBtn.Position = UDim2.new(1, -12, 0, 12)
    closeRankBtn.AnchorPoint = Vector2.new(1, 0)
    closeRankBtn.BackgroundColor3 = Color3.fromRGB(245, 0, 0)
    closeRankBtn.Text = "X"
    closeRankBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeRankBtn.Font = Enum.Font.GothamBlack
    closeRankBtn.TextSize = 18
    closeRankBtn.ZIndex = 35
    
    local crbCorner = Instance.new("UICorner")
    crbCorner.CornerRadius = UDim.new(0, 6)
    crbCorner.Parent = closeRankBtn
    
    local crbStroke = Instance.new("UIStroke")
    crbStroke.Color = Color3.fromRGB(0, 0, 0)
    crbStroke.Thickness = 2.5
    crbStroke.Parent = closeRankBtn
    
    closeRankBtn.MouseButton1Click:Connect(function()
        rankingsModal.Visible = false
        updateActionButtonsVisibility()
    end)
    closeRankBtn.Parent = cardFrame
    
    -- Header Title: "BID LEADERBOARD" in matching FredokaOne comic styling
    local titleHeader = Instance.new("Frame")
    titleHeader.Name = "TitleHeader"
    titleHeader.Size = UDim2.new(1, -80, 0, 36)
    titleHeader.Position = UDim2.new(0.5, 0, 0, 10)
    titleHeader.AnchorPoint = Vector2.new(0.5, 0)
    titleHeader.BackgroundTransparency = 1
    titleHeader.ZIndex = 28
    titleHeader.Parent = cardFrame
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 1, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "BID LEADERBOARD"
    titleLabel.Font = Enum.Font.FredokaOne
    titleLabel.TextSize = 25
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.ZIndex = 29
    local tlStroke = Instance.new("UIStroke")
    tlStroke.Color = Color3.fromRGB(0, 0, 0)
    tlStroke.Thickness = 4.5
    tlStroke.Parent = titleLabel
    titleLabel.Parent = titleHeader
    
    -- Table Header Frame: RANK | PLAYER | BID | TIME (Clean Pop-Art Comic Theme)
    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "HeaderFrame"
    headerFrame.Size = UDim2.new(1, -32, 0, 30)
    headerFrame.Position = UDim2.new(0, 16, 0, 48)
    headerFrame.BackgroundColor3 = Color3.fromRGB(22, 18, 17)
    headerFrame.BorderSizePixel = 0
    headerFrame.ZIndex = 28
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 8)
    hCorner.Parent = headerFrame
    local hStroke = Instance.new("UIStroke")
    hStroke.Color = Color3.fromRGB(255, 185, 40)
    hStroke.Thickness = 2
    hStroke.Parent = headerFrame
    
    local function makeHeaderCell(text, size, pos, align)
        local hCell = Instance.new("TextLabel")
        hCell.Size = size
        hCell.Position = pos
        hCell.BackgroundTransparency = 1
        hCell.Text = text
        hCell.Font = Enum.Font.GothamBlack
        hCell.TextSize = 12
        hCell.TextColor3 = Color3.fromRGB(255, 225, 140)
        hCell.TextXAlignment = align
        hCell.ZIndex = 29
        hCell.Parent = headerFrame
        return hCell
    end
    
    makeHeaderCell("RANK", UDim2.new(0.14, 0, 1, 0), UDim2.new(0, 4, 0, 0), Enum.TextXAlignment.Center)
    makeHeaderCell("PLAYER", UDim2.new(0.46, -10, 1, 0), UDim2.new(0.14, 12, 0, 0), Enum.TextXAlignment.Left)
    makeHeaderCell("BID", UDim2.new(0.20, 0, 1, 0), UDim2.new(0.60, 0, 0, 0), Enum.TextXAlignment.Right)
    makeHeaderCell("TIME", UDim2.new(0.20, -10, 1, 0), UDim2.new(0.80, -10, 0, 0), Enum.TextXAlignment.Right)
    headerFrame.Parent = cardFrame
    
    -- Scrolling Container with UIPadding so border strokes are never cut off by ClipsDescendants!
    local isScrollable = (tableContentHeight > (modalHeight - 100))
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "LeaderboardScroll"
    scroll.Size = UDim2.new(1, -32, 1, -98)
    scroll.Position = UDim2.new(0, 16, 0, 84)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = isScrollable and 6 or 0
    scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 180, 0)
    scroll.ScrollingEnabled = isScrollable
    scroll.CanvasSize = UDim2.new(0, 0, 0, tableContentHeight + 8)
    scroll.ZIndex = 28
    
    -- Inset UIPadding prevents the 2-3px row stroke from clipping against scroll bounds!
    local sPadding = Instance.new("UIPadding")
    sPadding.PaddingLeft = UDim.new(0, 6)
    sPadding.PaddingRight = UDim.new(0, isScrollable and 14 or 6)
    sPadding.PaddingTop = UDim.new(0, 4)
    sPadding.PaddingBottom = UDim.new(0, 4)
    sPadding.Parent = scroll
    
    local uiList = Instance.new("UIListLayout")
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Padding = UDim.new(0, rowPadding)
    uiList.Parent = scroll
    
    for i, p in ipairs(allBidders) do
        local isSafe = (i <= safeCount)
        local isMe = (p.UserId == player.UserId) or (p.Name == player.Name) or (p.DisplayName == player.DisplayName)
        local dispName = resolvePlayerDisplayName(p)
        
        local row = Instance.new("Frame")
        row.Name = "Row_" .. i
        row.Size = UDim2.new(1, 0, 0, rowHeight)
        row.LayoutOrder = i
        row.BorderSizePixel = 0
        row.ZIndex = 28
        
        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 8)
        rCorner.Parent = row
        
        local rStroke = Instance.new("UIStroke")
        rStroke.LineJoinMode = Enum.LineJoinMode.Round
        rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        
        -- Rich comic theme matching results aesthetic:
        if isMe then
            row.BackgroundColor3 = Color3.fromRGB(64, 46, 14) -- VIP amber/gold velvet
            rStroke.Color = Color3.fromRGB(255, 215, 0)
            rStroke.Thickness = 3
        elseif isSafe then
            row.BackgroundColor3 = Color3.fromRGB(16, 44, 28) -- Vibrant comic emerald
            rStroke.Color = Color3.fromRGB(42, 172, 98)
            rStroke.Thickness = 2
        else
            row.BackgroundColor3 = Color3.fromRGB(48, 18, 22) -- Deep comic crimson
            rStroke.Color = Color3.fromRGB(218, 48, 62)
            rStroke.Thickness = 2
        end
        rStroke.Parent = row
        
        -- Col 1: RANK Pill (#1, #2...)
        local rankPillFrame = Instance.new("Frame")
        rankPillFrame.Size = UDim2.new(0.14, -6, 0, 28)
        rankPillFrame.Position = UDim2.new(0, 3, 0.5, 0)
        rankPillFrame.AnchorPoint = Vector2.new(0, 0.5)
        rankPillFrame.BackgroundColor3 = isMe and Color3.fromRGB(105, 78, 16) or (isSafe and Color3.fromRGB(24, 68, 42) or Color3.fromRGB(72, 24, 30))
        rankPillFrame.BorderSizePixel = 0
        rankPillFrame.ZIndex = 29
        local rpfCorner = Instance.new("UICorner")
        rpfCorner.CornerRadius = UDim.new(0, 6)
        rpfCorner.Parent = rankPillFrame
        local rpfStroke = Instance.new("UIStroke")
        rpfStroke.Color = Color3.fromRGB(0, 0, 0)
        rpfStroke.Thickness = 1
        rpfStroke.Parent = rankPillFrame
        
        local c1 = Instance.new("TextLabel")
        c1.Size = UDim2.new(1, 0, 1, 0)
        c1.Position = UDim2.new(0, 0, 0, 0)
        c1.BackgroundTransparency = 1
        c1.Text = "#" .. tostring(i)
        c1.Font = Enum.Font.GothamBlack
        c1.TextSize = 14
        c1.TextColor3 = isMe and Color3.fromRGB(255, 235, 80) or (isSafe and Color3.fromRGB(80, 245, 140) or Color3.fromRGB(255, 95, 105))
        c1.TextXAlignment = Enum.TextXAlignment.Center
        c1.ZIndex = 30
        c1.Parent = rankPillFrame
        rankPillFrame.Parent = row
        
        -- Col 2: Player Avatar Thumbnail + Display Name (Balanced, No dead space!)
        local playerColFrame = Instance.new("Frame")
        playerColFrame.Size = UDim2.new(0.46, -6, 1, 0)
        playerColFrame.Position = UDim2.new(0.14, 6, 0, 0)
        playerColFrame.BackgroundTransparency = 1
        playerColFrame.ZIndex = 29
        
        -- 30x30 Avatar Headshot Icon
        local avFrame = Instance.new("Frame")
        avFrame.Size = UDim2.new(0, 30, 0, 30)
        avFrame.Position = UDim2.new(0, 0, 0.5, 0)
        avFrame.AnchorPoint = Vector2.new(0, 0.5)
        avFrame.BackgroundColor3 = Color3.fromRGB(215, 215, 215)
        avFrame.BorderSizePixel = 0
        avFrame.ZIndex = 30
        local avCorner = Instance.new("UICorner")
        avCorner.CornerRadius = UDim.new(0, 6)
        avCorner.Parent = avFrame
        local avStroke = Instance.new("UIStroke")
        avStroke.Color = isMe and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 0, 0)
        avStroke.Thickness = 1.5
        avStroke.Parent = avFrame
        
        local avImg = Instance.new("ImageLabel")
        avImg.Size = UDim2.new(1, -2, 1, -2)
        avImg.Position = UDim2.new(0.5, 0, 0.5, 0)
        avImg.AnchorPoint = Vector2.new(0.5, 0.5)
        avImg.BackgroundTransparency = 1
        local thumbId = (p.UserId and p.UserId > 0) and p.UserId or 1
        avImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", thumbId)
        avImg.ScaleType = Enum.ScaleType.Fit
        avImg.ZIndex = 31
        local aviCorner = Instance.new("UICorner")
        aviCorner.CornerRadius = UDim.new(0, 5)
        aviCorner.Parent = avImg
        avImg.Parent = avFrame
        avFrame.Parent = playerColFrame
        
        -- Display Name Label (No original username, display name only!)
        local c2 = Instance.new("TextLabel")
        c2.Size = UDim2.new(1, -38, 1, 0)
        c2.Position = UDim2.new(0, 36, 0, 0)
        c2.BackgroundTransparency = 1
        if isMe then
            c2.Text = string.format("%s (YOU)", dispName)
            c2.Font = Enum.Font.GothamBlack
            c2.TextSize = 13
            c2.TextColor3 = Color3.fromRGB(255, 235, 100)
        else
            c2.Text = dispName
            c2.Font = Enum.Font.GothamBold
            c2.TextSize = 13
            c2.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
        c2.TextXAlignment = Enum.TextXAlignment.Left
        c2.TextTruncate = Enum.TextTruncate.AtEnd
        c2.ZIndex = 30
        c2.Parent = playerColFrame
        playerColFrame.Parent = row
        
        -- Col 3: BID (Right aligned, Gold $X.XX)
        local c3 = Instance.new("TextLabel")
        c3.Size = UDim2.new(0.20, 0, 1, 0)
        c3.Position = UDim2.new(0.60, 0, 0, 0)
        c3.BackgroundTransparency = 1
        c3.Text = string.format("$%.2f", p.CurrentBid or 0)
        c3.Font = Enum.Font.GothamBlack
        c3.TextSize = 14
        c3.TextColor3 = Color3.fromRGB(255, 215, 60)
        c3.TextXAlignment = Enum.TextXAlignment.Right
        c3.ZIndex = 29
        c3.Parent = row
        
        -- Col 4: TIME (Right aligned, Mint / Coral / White)
        local c4 = Instance.new("TextLabel")
        c4.Size = UDim2.new(0.20, -10, 1, 0)
        c4.Position = UDim2.new(0.80, -10, 0, 0)
        c4.BackgroundTransparency = 1
        local elapsed = p.SubmitTime or 10.00
        c4.Text = string.format("%.2fs", elapsed)
        c4.Font = Enum.Font.GothamBold
        c4.TextSize = 13
        c4.TextColor3 = isMe and Color3.fromRGB(255, 255, 255) or (isSafe and Color3.fromRGB(150, 245, 185) or Color3.fromRGB(255, 155, 165))
        c4.TextXAlignment = Enum.TextXAlignment.Right
        c4.ZIndex = 29
        c4.Parent = row
        
        row.Parent = scroll
    end
    
    scroll.Parent = cardFrame

    rankingsModal.Visible = true
    updateActionButtonsVisibility()
end)

--------------------------------------------------------------------------------
-- 11. SPECTATOR VOTE POPULATOR (DISABLED: SABOTAGE FUNCTION REMOVED)
--------------------------------------------------------------------------------
PromptVote.OnClientEvent:Connect(function(data)
    voteModal.Visible = false
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
    biddingModal.Visible = false
    updateActionButtonsVisibility()
end)

--------------------------------------------------------------------------------
-- 13. MATCH OVER / NEW RESULTS UI REWORK (SVG.4 & RESULTS.JPG PODIUM)
--------------------------------------------------------------------------------

-- (RESULTS_BG_ASSET already defined above in Section 10)

local function formatSurvivalTime(seconds: number?): string
    local totalSecs = math.max(0, math.floor(seconds or 83))
    local m = math.floor(totalSecs / 60)
    local s = totalSecs % 60
    return string.format("Time:- %dm %02d sec", m, s)
end

local function formatPodiumName(name: string?): string
    local str = tostring(name or "Player")
    if string.sub(str, 1, 1) == "@" then
        return str
    end
    return "@" .. str
end

local function getAvatarHeadshot(userId: number?): string
    local id = tonumber(userId)
    if id and id > 0 then
        return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", id)
    end
    return "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150"
end

local function ensureResultsStructure()
    matchOverModal.AnchorPoint = Vector2.new(0.5, 0.5)
    matchOverModal.Position = UDim2.new(0.5, 0, 0.5, 0)
    matchOverModal.Size = UDim2.new(0, 560, 0, 420)
    matchOverModal.BackgroundTransparency = 1
    matchOverModal.BorderSizePixel = 0
    matchOverModal.ZIndex = 40

    -- Responsive UIScale so modal never clips on smaller screens or mobile
    local uiScale = matchOverModal:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
    uiScale.Parent = matchOverModal
    local cam = Workspace.CurrentCamera
    local function updateResultsScale()
        if not cam then return end
        local vp = cam.ViewportSize
        local scaleW = vp.X / 580
        local scaleH = vp.Y / 440
        uiScale.Scale = math.clamp(math.min(scaleW, scaleH), 0.5, 1.0)
    end
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResultsScale)
        updateResultsScale()
    end

    -- Hide any legacy text labels directly on matchOverModal
    for _, child in ipairs(matchOverModal:GetChildren()) do
        if child.Name == "Title" or child.Name == "WinnerName" or child.Name == "Subtitle" then
            child.Visible = false
        end
    end

    -- 1. Shadow Frame (3D drop shadow extrusion)
    local shadowFrame = matchOverModal:FindFirstChild("ShadowFrame") or Instance.new("Frame")
    shadowFrame.Name = "ShadowFrame"
    shadowFrame.Size = UDim2.new(1, -12, 1, -12)
    shadowFrame.Position = UDim2.new(0, 12, 0, 12)
    shadowFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadowFrame.BorderSizePixel = 0
    shadowFrame.ZIndex = 40
    local sCorner = shadowFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    sCorner.CornerRadius = UDim.new(0, 8)
    sCorner.Parent = shadowFrame
    shadowFrame.Parent = matchOverModal

    -- 2. Outer Border Frame (Electric Neon Cyan glow rim from Image 2)
    local borderFrame = matchOverModal:FindFirstChild("BorderFrame") or Instance.new("Frame")
    borderFrame.Name = "BorderFrame"
    borderFrame.Size = UDim2.new(1, -10, 1, -10)
    borderFrame.Position = UDim2.new(0, 0, 0, 0)
    borderFrame.BackgroundTransparency = 1
    borderFrame.BorderSizePixel = 0
    borderFrame.ZIndex = 41
    local bCorner = borderFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 8)
    bCorner.Parent = borderFrame
    local bStroke = borderFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    bStroke.Color = Color3.fromRGB(0, 175, 255)
    bStroke.Thickness = 2.5
    bStroke.LineJoinMode = Enum.LineJoinMode.Round
    bStroke.Parent = borderFrame
    borderFrame.Parent = matchOverModal

    -- 3. Card Frame (Pop-art orange card)
    local cardFrame = matchOverModal:FindFirstChild("CardFrame") or Instance.new("Frame")
    cardFrame.Name = "CardFrame"
    cardFrame.Size = UDim2.new(1, -12, 1, -12)
    cardFrame.Position = UDim2.new(0, 0, 0, 0)
    cardFrame.BackgroundColor3 = Color3.fromRGB(242, 118, 16)
    cardFrame.BorderSizePixel = 0
    cardFrame.ZIndex = 42
    local cCorner = cardFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = cardFrame
    local cStroke = cardFrame:FindFirstChild("CardStroke") or cardFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    cStroke.Name = "CardStroke"
    cStroke.Color = Color3.fromRGB(0, 0, 0)
    cStroke.Thickness = 4.5
    cStroke.LineJoinMode = Enum.LineJoinMode.Round
    cStroke.Parent = cardFrame

    -- Background texture: results.jpg
    local bgImage = cardFrame:FindFirstChild("BgImage") or Instance.new("ImageLabel")
    bgImage.Name = "BgImage"
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.Position = UDim2.new(0, 0, 0, 0)
    bgImage.BackgroundTransparency = 1
    bgImage.Image = RESULTS_BG_ASSET
    bgImage.ScaleType = Enum.ScaleType.Crop
    bgImage.ZIndex = 43
    local bgCorner = bgImage:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 8)
    bgCorner.Parent = bgImage
    bgImage.Parent = cardFrame

    -- 4. Title Header: "Results" (Bubble font with 4.5px black outline)
    local titleLabel = cardFrame:FindFirstChild("TitleLabel") or Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(0, 240, 0, 48)
    titleLabel.Position = UDim2.new(0.5, 0, 0, 10)
    titleLabel.AnchorPoint = Vector2.new(0.5, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Results"
    titleLabel.Font = Enum.Font.FredokaOne
    titleLabel.TextSize = 38
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.ZIndex = 48
    local tStroke = titleLabel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    tStroke.Color = Color3.fromRGB(0, 0, 0)
    tStroke.Thickness = 4.5
    tStroke.Parent = titleLabel
    titleLabel.Parent = cardFrame

    -- 5. Red X Close Button (Top right corner)
    local closeResultsBtn = cardFrame:FindFirstChild("CloseResultsBtn") or Instance.new("TextButton")
    closeResultsBtn.Name = "CloseResultsBtn"
    closeResultsBtn.Size = UDim2.new(0, 36, 0, 36)
    closeResultsBtn.Position = UDim2.new(1, -14, 0, 14)
    closeResultsBtn.AnchorPoint = Vector2.new(1, 0)
    closeResultsBtn.BackgroundColor3 = Color3.fromRGB(235, 25, 25)
    closeResultsBtn.Text = "X"
    closeResultsBtn.Font = Enum.Font.GothamBlack
    closeResultsBtn.TextSize = 20
    closeResultsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeResultsBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    closeResultsBtn.TextStrokeTransparency = 0
    closeResultsBtn.ZIndex = 50
    local crCorner = closeResultsBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    crCorner.CornerRadius = UDim.new(0, 6)
    crCorner.Parent = closeResultsBtn
    local crStroke = closeResultsBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    crStroke.Color = Color3.fromRGB(0, 0, 0)
    crStroke.Thickness = 2.5
    crStroke.Parent = closeResultsBtn

    -- Hover effect on close button
    closeResultsBtn.MouseEnter:Connect(function()
        TweenService:Create(closeResultsBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(255, 60, 60),
            Size = UDim2.new(0, 38, 0, 38)
        }):Play()
    end)
    closeResultsBtn.MouseLeave:Connect(function()
        TweenService:Create(closeResultsBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(235, 25, 25),
            Size = UDim2.new(0, 36, 0, 36)
        }):Play()
    end)

    closeResultsBtn.Parent = cardFrame

    -- 6. Podium Container
    local podiumContainer = cardFrame:FindFirstChild("PodiumContainer") or Instance.new("Frame")
    podiumContainer.Name = "PodiumContainer"
    podiumContainer.Size = UDim2.new(1, 0, 1, 0)
    podiumContainer.Position = UDim2.new(0, 0, 0, 0)
    podiumContainer.BackgroundTransparency = 1
    podiumContainer.BorderSizePixel = 0
    podiumContainer.ZIndex = 45
    podiumContainer.Parent = cardFrame

    cardFrame.Parent = matchOverModal
    return cardFrame, podiumContainer, closeResultsBtn
end

local function createPodiumColumn(parent: Frame, rank: number, data: any, config: any)
    local col = Instance.new("Frame")
    col.Name = "Col_" .. rank
    col.Size = UDim2.new(0, 122, 1, 0)
    col.Position = config.colPosition
    col.AnchorPoint = config.colAnchor
    col.BackgroundTransparency = 1
    col.BorderSizePixel = 0
    col.ZIndex = 46

    local isMe = (data.UserId == player.UserId) or (data.Name == player.Name) or (data.DisplayName == player.DisplayName)

    -- 1. Profile Box (Square with gray background, black stroke, avatar headshot)
    local profileBox = Instance.new("Frame")
    profileBox.Name = "ProfileBox"
    profileBox.Size = UDim2.new(0, 122, 0, 111)
    profileBox.Position = UDim2.new(0.5, 0, 0, config.boxY)
    profileBox.AnchorPoint = Vector2.new(0.5, 0)
    profileBox.BackgroundColor3 = Color3.fromRGB(217, 217, 217) -- #D9D9D9 from svg.4
    profileBox.BorderSizePixel = 0
    profileBox.ZIndex = 46
    local pbCorner = Instance.new("UICorner")
    pbCorner.CornerRadius = UDim.new(0, 4)
    pbCorner.Parent = profileBox
    local pbStroke = Instance.new("UIStroke")
    if isMe then
        pbStroke.Color = Color3.fromRGB(255, 215, 0)
        pbStroke.Thickness = 3.5
    else
        pbStroke.Color = Color3.fromRGB(0, 0, 0)
        pbStroke.Thickness = 2.5
    end
    pbStroke.Parent = profileBox

    -- Avatar Headshot
    local avatarImg = Instance.new("ImageLabel")
    avatarImg.Name = "AvatarImg"
    avatarImg.Size = UDim2.new(1, -4, 1, -4)
    avatarImg.Position = UDim2.new(0.5, 0, 0.5, 0)
    avatarImg.AnchorPoint = Vector2.new(0.5, 0.5)
    avatarImg.BackgroundTransparency = 1
    avatarImg.Image = getAvatarHeadshot(data.UserId)
    avatarImg.ScaleType = Enum.ScaleType.Fit
    avatarImg.ZIndex = 47
    local avCorner = Instance.new("UICorner")
    avCorner.CornerRadius = UDim.new(0, 3)
    avCorner.Parent = avatarImg
    avatarImg.Parent = profileBox

    profileBox.Parent = col

    -- 2. Username Pill (Dark #212121 capsule with white stroke)
    local userPill = Instance.new("Frame")
    userPill.Name = "UserPill"
    userPill.Size = UDim2.new(0, 110, 0, 24)
    userPill.Position = UDim2.new(0.5, 0, 0, config.pill1Y)
    userPill.AnchorPoint = Vector2.new(0.5, 0)
    userPill.BackgroundColor3 = Color3.fromRGB(33, 33, 33) -- #212121 from svg.4
    userPill.BorderSizePixel = 0
    userPill.ZIndex = 47
    local upCorner = Instance.new("UICorner")
    upCorner.CornerRadius = UDim.new(0, 12)
    upCorner.Parent = userPill
    local upStroke = Instance.new("UIStroke")
    upStroke.Color = isMe and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
    upStroke.Thickness = isMe and 2 or 1.5
    upStroke.Parent = userPill

    local userLabel = Instance.new("TextLabel")
    userLabel.Size = UDim2.new(1, -10, 1, 0)
    userLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    userLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    local podiumDispName = (isMe and player.DisplayName) or data.DisplayName
    if (not podiumDispName or podiumDispName == data.Name) and data.UserId and data.UserId > 0 then
        local pObj = Players:GetPlayerByUserId(data.UserId)
        if pObj then podiumDispName = pObj.DisplayName end
    end
    userLabel.Text = formatPodiumName(podiumDispName or data.Name or "Player")
    userLabel.Font = Enum.Font.GothamBold
    userLabel.TextSize = 11
    userLabel.TextScaled = true
    userLabel.TextColor3 = isMe and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(255, 255, 255)
    userLabel.TextTruncate = Enum.TextTruncate.AtEnd
    userLabel.TextXAlignment = Enum.TextXAlignment.Center
    userLabel.ZIndex = 48
    local userSizeConstraint = Instance.new("UITextSizeConstraint")
    userSizeConstraint.MaxTextSize = 12
    userSizeConstraint.MinTextSize = 8
    userSizeConstraint.Parent = userLabel
    userLabel.Parent = userPill
    userPill.Parent = col

    -- 3. Time Pill (Dark #212121 capsule with white stroke: "Time:- 1m 23 sec")
    local timePill = Instance.new("Frame")
    timePill.Name = "TimePill"
    timePill.Size = UDim2.new(0, 110, 0, 24)
    timePill.Position = UDim2.new(0.5, 0, 0, config.pill2Y)
    timePill.AnchorPoint = Vector2.new(0.5, 0)
    timePill.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
    timePill.BorderSizePixel = 0
    timePill.ZIndex = 47
    local tpCorner = Instance.new("UICorner")
    tpCorner.CornerRadius = UDim.new(0, 12)
    tpCorner.Parent = timePill
    local tpStroke = Instance.new("UIStroke")
    tpStroke.Color = Color3.fromRGB(255, 255, 255)
    tpStroke.Thickness = 1.5
    tpStroke.Parent = timePill

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(1, -10, 1, 0)
    timeLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    timeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Text = formatSurvivalTime(data.SurvivalTime)
    timeLabel.Font = Enum.Font.GothamBold
    timeLabel.TextSize = 10
    timeLabel.TextScaled = true
    timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    timeLabel.TextTruncate = Enum.TextTruncate.AtEnd
    timeLabel.TextXAlignment = Enum.TextXAlignment.Center
    timeLabel.ZIndex = 48
    local timeSizeConstraint = Instance.new("UITextSizeConstraint")
    timeSizeConstraint.MaxTextSize = 11
    timeSizeConstraint.MinTextSize = 7
    timeSizeConstraint.Parent = timeLabel
    timeLabel.Parent = timePill
    timePill.Parent = col

    -- 4. Big Bold Rank Text (#1, #2, #3)
    local rankLabel = Instance.new("TextLabel")
    rankLabel.Name = "RankLabel"
    rankLabel.Size = UDim2.new(0, 108, 0, 48)
    rankLabel.Position = UDim2.new(0.5, 0, 0, config.rankY)
    rankLabel.AnchorPoint = Vector2.new(0.5, 0)
    rankLabel.BackgroundTransparency = 1
    rankLabel.Text = "#" .. tostring(rank)
    rankLabel.Font = Enum.Font.GothamBlack
    rankLabel.TextSize = config.rankSize
    rankLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    rankLabel.ZIndex = 49
    local rkStroke = Instance.new("UIStroke")
    rkStroke.Color = Color3.fromRGB(0, 0, 0)
    rkStroke.Thickness = config.rankStroke
    rkStroke.Parent = rankLabel
    rankLabel.Parent = col

    col.Parent = parent
    return col
end

local function showResultsUI(data: any)
    if IsAFK then return end
    local cardFrame, podiumContainer, closeResultsBtn = ensureResultsStructure()

    -- Clear previous podium elements
    for _, child in ipairs(podiumContainer:GetChildren()) do
        child:Destroy()
    end

    -- Close button connection
    closeResultsBtn.MouseButton1Click:Connect(function()
        matchOverModal.Visible = false
        updateActionButtonsVisibility()
    end)

    -- Extract podium data with safe defaults
    local rawPodium = data and data.Podium or {}
    local winnerNameStr = data and data.Winner or "Winner"
    local totalDur = data and data.TotalDuration or 83

    local p1 = rawPodium[1] or { Rank = 1, UserId = player.UserId, Name = winnerNameStr, DisplayName = winnerNameStr, SurvivalTime = totalDur }
    local p2 = rawPodium[2] or { Rank = 2, UserId = 1, Name = "RunnerUp", DisplayName = "RunnerUp", SurvivalTime = math.max(1, totalDur - 12) }
    local p3 = rawPodium[3] or { Rank = 3, UserId = 2, Name = "Contender", DisplayName = "Contender", SurvivalTime = math.max(1, totalDur - 25) }

    -- Layout configurations derived directly from svg.4:
    -- #1 Center (Elevated)
    local cfg1 = {
        colPosition = UDim2.new(0.5, 0, 0, 0),
        colAnchor = Vector2.new(0.5, 0),
        boxY = 68,
        pill1Y = 186,
        pill2Y = 213,
        rankY = 244,
        rankSize = 48,
        rankStroke = 5,
    }
    -- #2 Left (Stepped down)
    local cfg2 = {
        colPosition = UDim2.new(0, 97, 0, 0),
        colAnchor = Vector2.new(0.5, 0),
        boxY = 124,
        pill1Y = 242,
        pill2Y = 269,
        rankY = 302,
        rankSize = 44,
        rankStroke = 4.5,
    }
    -- #3 Right (Stepped down lowest)
    local cfg3 = {
        colPosition = UDim2.new(1, -97, 0, 0),
        colAnchor = Vector2.new(0.5, 0),
        boxY = 180,
        pill1Y = 298,
        pill2Y = 325,
        rankY = 356,
        rankSize = 44,
        rankStroke = 4.5,
    }

    createPodiumColumn(podiumContainer, 1, p1, cfg1)
    createPodiumColumn(podiumContainer, 2, p2, cfg2)
    createPodiumColumn(podiumContainer, 3, p3, cfg3)

    -- Pop-in animation
    matchOverModal.Size = UDim2.new(0, 480, 0, 360)
    matchOverModal.Visible = true
    TweenService:Create(matchOverModal, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 560, 0, 420)
    }):Play()

    -- Celebratory sound pop
    local popSound = Instance.new("Sound")
    popSound.SoundId = "rbxasset://sounds/action_get_up.mp3"
    popSound.Volume = 0.8
    popSound.Parent = matchOverModal
    popSound:Play()
    Debris:AddItem(popSound, 2)
end

MatchOver.OnClientEvent:Connect(function(data)
    showResultsUI(data)
end)

-- Developer hotkey F4 to test/preview Results UI immediately in Studio
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F4 then
        showResultsUI({
            Winner = LocalPlayer.DisplayName,
            TotalDuration = 83,
            Podium = {
                { Rank = 1, UserId = LocalPlayer.UserId, Name = LocalPlayer.Name, DisplayName = LocalPlayer.DisplayName, SurvivalTime = 83 },
                { Rank = 2, UserId = 1, Name = "RunnerUp", DisplayName = "RunnerUp", SurvivalTime = 72 },
                { Rank = 3, UserId = 2, Name = "Contender", DisplayName = "Contender", SurvivalTime = 58 },
            }
        })
    end
end)
