-- BID TO SURVIVE - Master Round Manager
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RuinsDoorHandManager = require(ServerScriptService:WaitForChild("RuinsDoorHandManager"))
local CashAndWalletManager = require(ServerScriptService:WaitForChild("CashAndWalletManager"))
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
local GetGameState = Network:WaitForChild("GetGameState")

-- Ensure SetAFK RemoteEvent exists
local SetAFK = Network:FindFirstChild("SetAFK")
if not SetAFK then
    SetAFK = Instance.new("RemoteEvent")
    SetAFK.Name = "SetAFK"
    SetAFK.Parent = Network
end

-- Ensure ParticipationChanged RemoteEvent exists
local ParticipationChanged = Network:FindFirstChild("ParticipationChanged")
if not ParticipationChanged then
    ParticipationChanged = Instance.new("RemoteEvent")
    ParticipationChanged.Name = "ParticipationChanged"
    ParticipationChanged.Parent = Network
end

-- Ensure ClientLoadReadyEvent RemoteEvent exists
local ClientLoadReadyEvent = Network:FindFirstChild("ClientLoadReadyEvent")
if not ClientLoadReadyEvent then
    ClientLoadReadyEvent = Instance.new("RemoteEvent")
    ClientLoadReadyEvent.Name = "ClientLoadReadyEvent"
    ClientLoadReadyEvent.Parent = Network
end

ClientLoadReadyEvent.OnServerEvent:Connect(function(player)
    player:SetAttribute("ClientReady", true)
    print(string.format("[BOOT HIERARCHY] 📥 Received ClientLoadReadyEvent from %s. ClientReady=true", player.Name))
end)

local Map = workspace:WaitForChild("BidToSurviveMap")
local SpawnArea = Map:WaitForChild("SpawnArea")
local GameplayArea = Map:WaitForChild("GameplayArea")
local Walkway = GameplayArea:WaitForChild("Walkway")
local Executioner = GameplayArea:FindFirstChild("Executioner")

-- State Variables
local CurrentRound = 0
local CurrentRoundSession = 0
local CurrentPhase = "Intermission"
local PhaseTimer = 0
local CurrentRarity = GameConfig.HammerRarities.Common
local MatchActive = false
local PhaseStartTime = 0

-- Player Data Store { [UserId] = { Money, Health, IsAlive, IsAFK, CurrentBid, Votes, IsBot, Name, UserId, Character, SubmitTime } }
local PlayerData = {}
local ExposedPlayerId = nil
local ActiveBots = {}

--------------------------------------------------------------------------------
-- UTILITY & STATS
--------------------------------------------------------------------------------

local function GetActivePlayers()
    local active = {}
    for id, data in pairs(PlayerData) do
        if data.IsAlive and data.ParticipationState == "Active" then
            table.insert(active, data)
        end
    end
    return active
end

local function GetActiveRealPlayers()
    local active = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        if data and data.IsAlive and data.ParticipationState == "Active" then
            table.insert(active, player)
        end
    end
    return active
end

local function GetLivingPlayers()
    return GetActivePlayers()
end

local function GetLivingRealPlayers()
    return GetActiveRealPlayers()
end

local function GetSpectatorPlayers()
    local spectators = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        if data and not data.IsAlive and data.ParticipationState == "Eliminated" then
            table.insert(spectators, player)
        end
    end
    return spectators
end

local function GetReadyEligiblePlayers()
    local ready = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local isAfk = (player:GetAttribute("IsAFK") == true)
        local isClientReady = (player:GetAttribute("ClientReady") == true)
        local isR6Ready = (player:GetAttribute("R6RigReady") == true)
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local isLiving = (hum ~= nil and hum.Health > 0)
        local isR6 = (hum ~= nil and hum.RigType == Enum.HumanoidRigType.R6)
        local isReady = isLiving and (hrp ~= nil) and (isClientReady or isR6Ready or isR6)

        if not isAfk and isReady then
            table.insert(ready, player)
        end
    end
    return ready
end

local function BroadcastState(phaseName, duration, extra)
    CurrentPhase = phaseName
    PhaseTimer = duration or 0
    local livingCount = #GetActivePlayers()
    local deadline = os.clock() + (duration or 0)
    
    print(string.format("[ROUND MANAGER] Phase: %s | Round: %d | Duration: %ds | Active Living: %d", phaseName, CurrentRound, PhaseTimer, livingCount))
    StateChanged:FireAllClients({
        Phase = CurrentPhase,
        Duration = PhaseTimer,
        Deadline = deadline,
        Round = CurrentRound,
        Rarity = CurrentRarity,
        LivingCount = livingCount,
        ExposedPlayer = ExposedPlayerId and PlayerData[ExposedPlayerId] and PlayerData[ExposedPlayerId].Name or nil,
        Extra = extra,
        SpinnerReel = extra and extra.SpinnerReel or nil,
    })
end

local function SyncStats(player)
    local data = PlayerData[player.UserId]
    if data then
        local pState = data.ParticipationState or (data.IsAFK and "AFK" or "WaitingInLobby")
        player:SetAttribute("Money", data.Money)
        player:SetAttribute("Wallet", data.Money)
        player:SetAttribute("Health", data.Health)
        player:SetAttribute("HP", data.Health)
        StatsUpdated:FireClient(player, {
            Money = data.Money,
            Health = data.Health,
            IsAlive = data.IsAlive,
            IsAFK = data.IsAFK,
            ParticipationState = pState,
            Round = CurrentRound
        })
        if ParticipationChanged then
            ParticipationChanged:FireClient(player, pState)
        end
    end
end

local function SyncAllStats()
    for _, player in ipairs(Players:GetPlayers()) do
        SyncStats(player)
    end
end

--------------------------------------------------------------------------------
-- TELEPORTATION SYSTEM
--------------------------------------------------------------------------------

local function TeleportCharacter(char, targetPos)
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 3)
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        char:PivotTo(CFrame.new(targetPos))
        task.wait(0.05)
        char:PivotTo(CFrame.new(targetPos))
    end
end

local function TeleportToLobby(player)
    local char = player.Character
    if not char then return end
    local lobbySpawn = SpawnArea:FindFirstChild("LobbySpawn")
    local basePos = lobbySpawn and lobbySpawn.Position or Vector3.new(48.11, 85.14, 2.92)
    local offset = Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
    TeleportCharacter(char, basePos + offset)
end

local function TeleportToArena(player)
    local char = player.Character
    if not char then return end
    local wPos = Walkway.Position
    local rx = math.random(-45, 45)
    local rz = math.random(-35, 35)
    local targetPos = Vector3.new(wPos.X + rx, wPos.Y + 3.5, wPos.Z + rz)
    TeleportCharacter(char, targetPos)
end

--------------------------------------------------------------------------------
-- BOT CREATION
--------------------------------------------------------------------------------

local function CleanupBots()
    for _, botData in ipairs(ActiveBots) do
        if botData.Character and botData.Character.Parent then
            botData.Character:Destroy()
        end
    end
    ActiveBots = {}
end

local function CreateBotDummy(name, id, startPos)
    local animMaker = workspace:FindFirstChild("animation-maker")
    local botModel
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
    botModel.Parent = GameplayArea
    
    local botData = {
        UserId = id,
        Name = name,
        Money = GameConfig.StartingMoney,
        Health = GameConfig.MaxHealth,
        IsAlive = true,
        IsAFK = false,
        ParticipationState = "Active",
        CurrentBid = 0,
        Votes = 0,
        IsBot = true,
        Character = botModel
    }
    
    table.insert(ActiveBots, botData)
    PlayerData[id] = botData
    return botData
end

local function SetupCompanionBots(targetTotal)
    CleanupBots()
    local realEligibleCount = #GetReadyEligiblePlayers()
    if realEligibleCount == 0 then
        realEligibleCount = #GetLivingRealPlayers()
    end
    if realEligibleCount == 0 then
        realEligibleCount = #Players:GetPlayers()
    end
    local botsNeeded = math.max(0, targetTotal - realEligibleCount)
    local botNames = {
        "ApeSlayer", "ShadowRunner", "LuckyBids", "AlphaTitan", "RiskHunter",
        "ViperStrike", "CyberGhost", "BlazeWarrior", "EchoPhantom", "IronClaw"
    }
    local wPos = Walkway.Position
    
    for i = 1, botsNeeded do
        local bName = botNames[i] or ("Bot_" .. i)
        local bId = -200 - i
        local angle = (i / math.max(1, botsNeeded)) * math.pi * 2
        local radius = 22 + (i % 3) * 14
        local spawnPos = Vector3.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius)
        CreateBotDummy(bName, bId, spawnPos)
    end
end

--------------------------------------------------------------------------------
-- NEON GREEN BID WINNER GLOW SHIELD (REPLACES TILES)
--------------------------------------------------------------------------------

local function ClearWinnerGlow()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local hl = player.Character:FindFirstChild("SafeBidGlow")
            if hl then hl:Destroy() end
        end
    end
    for _, bot in ipairs(ActiveBots) do
        if bot.Character then
            local hl = bot.Character:FindFirstChild("SafeBidGlow")
            if hl then hl:Destroy() end
        end
    end
end

local function ApplyWinnerGlow(char)
    if not char then return end
    local old = char:FindFirstChild("SafeBidGlow")
    if old then old:Destroy() end
    local hl = Instance.new("Highlight")
    hl.Name = "SafeBidGlow"
    hl.FillColor = Color3.fromRGB(0, 255, 120)
    hl.OutlineColor = Color3.fromRGB(220, 255, 230)
    hl.FillTransparency = 0.25
    hl.OutlineTransparency = 0
    hl.Parent = char
end

--------------------------------------------------------------------------------
-- HAMMER SMASH EXECUTION
--------------------------------------------------------------------------------

local function TriggerHammerSmash(rarity, onImpactCallback, customPlayerData)
    HammerSmash:FireAllClients({
        Rarity = rarity,
        ImpactDelay = 3.27
    })
    
    RuinsDoorHandManager.ExecuteSequenceAndDamage(
        onImpactCallback,
        customPlayerData,
        function(isOpen)
            local map = workspace:FindFirstChild("BidToSurviveMap")
            local ruinsDoor = (map and (map:FindFirstChild("Ruins door") or map:FindFirstChild("RuinsDoor")))
                or workspace:FindFirstChild("Ruins door")
                or workspace:FindFirstChild("RuinsDoor")
            if ruinsDoor then
                for _, desc in ipairs(ruinsDoor:GetDescendants()) do
                    local nameLower = desc.Name:lower()
                    if nameLower:find("partinvinciblewhenopening") or nameLower:find("partinvisiblewhenopening") then
                        if desc:IsA("BasePart") then
                            desc.Transparency = isOpen and 1 or 0
                            desc.CanCollide = not isOpen
                        end
                    end
                end
            end
        end
    )
end

--------------------------------------------------------------------------------
-- MATCH LIFECYCLE
--------------------------------------------------------------------------------

local function InitMatch()
    CurrentRound = 0
    MatchActive = true
    ExposedPlayerId = nil
    
    -- Cleanly respawn any dead players, restore 100 HP, reset attributes, and fire ResetHUDStateEvent
    RuinsDoorHandManager.ResetAllPlayersForNewGame()
    
    local startingWallet = CashAndWalletManager.STARTING_GAME_WALLET or 20
    local eligibleToEnter = {}

    for _, player in ipairs(Players:GetPlayers()) do
        -- AFK IS EVALUATED ONLY HERE: AT GAME START BEFORE TAKING PLAYERS TO THE GAME AREA!
        local isAfk = (player:GetAttribute("IsAFK") == true)
        local isClientReady = (player:GetAttribute("ClientReady") == true)
        local isR6Ready = (player:GetAttribute("R6RigReady") == true)
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local isLiving = (hum ~= nil and hum.Health > 0)
        local isR6 = (hum ~= nil and hum.RigType == Enum.HumanoidRigType.R6)
        local isReady = isLiving and (hrp ~= nil) and (isClientReady or isR6Ready or isR6)

        local admittedToGame = (not isAfk) and isReady
        local partState
        if isAfk then
            partState = "AFK"
        elseif admittedToGame then
            partState = "Active"
            table.insert(eligibleToEnter, player)
        else
            partState = "WaitingInLobby"
        end

        PlayerData[player.UserId] = {
            UserId = player.UserId,
            Name = player.DisplayName,
            Money = startingWallet,
            Wallet = startingWallet,
            Health = GameConfig.MaxHealth,
            IsAlive = true,
            IsAFK = isAfk,
            ParticipationState = partState,
            CurrentBid = 0,
            Votes = 0,
            IsBot = false,
            Character = player.Character
        }
        player:SetAttribute("Money", startingWallet)
        player:SetAttribute("Wallet", startingWallet)
        player:SetAttribute("Health", GameConfig.MaxHealth)
        player:SetAttribute("HP", GameConfig.MaxHealth)
        player:SetAttribute("IsInGame", partState == "Active")

        if partState ~= "Active" then
            TeleportToLobby(player)
        end
    end
    
    SetupCompanionBots(10)
    CashAndWalletManager.StartGameForPlayers(eligibleToEnter)
    SyncAllStats()
    ClearWinnerGlow()
end

local function RunMatch(session)
    InitMatch()
    local matchStartTime = os.clock()
    local matchEliminations = {}
    
    while MatchActive do
        if session ~= CurrentRoundSession then
            print("[ROUND] Obsolete session cancelled.")
            break
        end
        
        CurrentRound = CurrentRound + 1
        
        -- Bots remain active if alive
        for _, bot in ipairs(ActiveBots) do
            if bot.IsAlive then
                bot.ParticipationState = "Active"
            end
        end
        
        -- Sync stats for current round
        SyncAllStats()
        
        local living = GetActivePlayers()
        
        -- Check Sole Survivor / Win condition
        if #living <= 1 then
            local winner = living[1]
            local winRealName = winner and winner.Name or "No One"
            local winDisplayName = winRealName
            if winner then
                if winner.DisplayName then
                    winDisplayName = winner.DisplayName
                elseif not winner.IsBot and winner.UserId and winner.UserId > 0 then
                    local pObj = Players:GetPlayerByUserId(winner.UserId)
                    if pObj then
                        winDisplayName = pObj.DisplayName
                        winRealName = pObj.Name
                    end
                end
            end
            local totalDuration = math.max(1, math.floor(os.clock() - matchStartTime))
            print("[ROUND MANAGER] Match Ended! Sole Survivor: " .. winDisplayName .. " (" .. winRealName .. ")")
            CashAndWalletManager.EndGameAndRewardSurvivors()
            BroadcastState("MatchOver", 8, { Winner = winDisplayName, WinnerRealName = winRealName })

            local podium = {}
            if winner then
                table.insert(podium, {
                    Rank = 1,
                    UserId = winner.UserId or 1,
                    Name = winRealName,
                    DisplayName = winDisplayName,
                    SurvivalTime = totalDuration,
                    IsBot = winner.IsBot == true,
                })
            else
                table.insert(podium, {
                    Rank = 1,
                    UserId = 1,
                    Name = winRealName,
                    DisplayName = winDisplayName,
                    SurvivalTime = totalDuration,
                    IsBot = false,
                })
            end

            -- Rank 2 (last eliminated before winner)
            if #matchEliminations >= 1 then
                local p2 = matchEliminations[#matchEliminations]
                local p2Disp = p2.DisplayName or p2.Name or "RunnerUp"
                if not p2.IsBot and p2.UserId and p2.UserId > 0 then
                    local pObj = Players:GetPlayerByUserId(p2.UserId)
                    if pObj then p2Disp = pObj.DisplayName end
                end
                table.insert(podium, {
                    Rank = 2,
                    UserId = p2.UserId or 1,
                    Name = p2.Name or "RunnerUp",
                    DisplayName = p2Disp,
                    SurvivalTime = p2.SurvivalTime or math.max(1, totalDuration - 12),
                    IsBot = p2.IsBot == true,
                })
            else
                table.insert(podium, {
                    Rank = 2,
                    UserId = 1,
                    Name = "RunnerUp",
                    DisplayName = "RunnerUp",
                    SurvivalTime = math.max(1, totalDuration - 12),
                    IsBot = true,
                })
            end

            -- Rank 3 (second-to-last eliminated)
            if #matchEliminations >= 2 then
                local p3 = matchEliminations[#matchEliminations - 1]
                local p3Disp = p3.DisplayName or p3.Name or "Contender"
                if not p3.IsBot and p3.UserId and p3.UserId > 0 then
                    local pObj = Players:GetPlayerByUserId(p3.UserId)
                    if pObj then p3Disp = pObj.DisplayName end
                end
                table.insert(podium, {
                    Rank = 3,
                    UserId = p3.UserId or 2,
                    Name = p3.Name or "Contender",
                    DisplayName = p3Disp,
                    SurvivalTime = p3.SurvivalTime or math.max(1, totalDuration - 25),
                    IsBot = p3.IsBot == true,
                })
            else
                table.insert(podium, {
                    Rank = 3,
                    UserId = 2,
                    Name = "Contender",
                    DisplayName = "Contender",
                    SurvivalTime = math.max(1, totalDuration - 25),
                    IsBot = true,
                })
            end

            MatchOver:FireAllClients({
                Winner = winDisplayName,
                WinnerRealName = winRealName,
                RoundsSurvived = CurrentRound - 1,
                TotalDuration = totalDuration,
                Podium = podium,
            })
            task.wait(8)
            for _, p in ipairs(Players:GetPlayers()) do
                TeleportToLobby(p)
                p:SetAttribute("IsInGame", false)
                local pData = PlayerData[p.UserId]
                if pData then
                    local isAfk = (p:GetAttribute("IsAFK") == true)
                    pData.IsAFK = isAfk
                    pData.ParticipationState = isAfk and "AFK" or "WaitingInLobby"
                    SyncStats(p)
                end
            end
            CleanupBots()
            ClearWinnerGlow()
            MatchActive = false
            break
        end
        
        -- Roll Server-Authoritative Rarity using Round-by-Round Probability Weights
        CurrentRarity = GameConfig.RollRarity(CurrentRound)
        local spinnerReel = GameConfig.BuildRandomSpinnerStrip(CurrentRound, 19, 19, CurrentRarity.Name)
        print(string.format("[ROUND] Rolled Hammer for Round %d: %s (%d%% DMG)", CurrentRound, CurrentRarity.Name, CurrentRarity.DamagePercent))
        
        ------------------------------------------------------------------------
        -- PHASE 1: SPAWN / HAMMER ROULETTE REVEAL
        ------------------------------------------------------------------------
        local spawnDuration = GameConfig.SpawnPhaseTime or 8.0
        print(string.format("[ROUND] HammerReveal START duration=%.1f", spawnDuration))
        local p1Start = os.clock()
        
        -- Only teleport active real players to the arena!
        for _, p in ipairs(GetActiveRealPlayers()) do
            TeleportToArena(p)
        end
        
        -- Reset bots to arena in natural circular scatter
        local wPos = Walkway.Position
        for i, b in ipairs(ActiveBots) do
            if b.IsAlive and b.Character then
                local angle = (i / math.max(1, #ActiveBots)) * math.pi * 2
                local radius = 22 + (i % 3) * 14
                b.Character:PivotTo(CFrame.new(wPos.X + math.cos(angle) * radius, wPos.Y + 3.5, wPos.Z + math.sin(angle) * radius))
            end
        end
        
        BroadcastState("Phase1_Spawn", spawnDuration, {
            Round = CurrentRound,
            Rarity = CurrentRarity,
            SpinnerReel = spinnerReel,
            RouletteDuration = GameConfig.RouletteDuration or 6.0,
            HoldDuration = GameConfig.RouletteHoldTime or 1.5,
        })
        task.wait(spawnDuration)
        print(string.format("[ROUND] HammerReveal END elapsed=%.2f", os.clock() - p1Start))
        task.wait(1.5) -- 1.5s delay before bidding phase begins
        
        ------------------------------------------------------------------------
        -- PHASE 3: BID FOR SURVIVAL (Exactly 10 Seconds)
        ------------------------------------------------------------------------
        local bidDuration = GameConfig.BidTime or 10.0
        print(string.format("[ROUND] Bidding START duration=%.1f", bidDuration))
        PhaseStartTime = os.clock()
        
        for _, d in ipairs(living) do
            d.CurrentBid = 0
            d.SubmitTime = nil
            if d.IsBot then
                local maxB = math.min(d.Money, math.random(15, 65) / 10)
                d.CurrentBid = math.floor(maxB * 10) / 10
                d.SubmitTime = math.random(80, 750) / 100
                d.Money = math.max(0, d.Money - d.CurrentBid)
                d.Wallet = d.Money
            end
        end
        
        BroadcastState("Phase3_Bid", bidDuration, { ExposedPlayerId = ExposedPlayerId })
        PromptBid:FireAllClients({
            Duration = bidDuration,
            ExposedPlayer = ExposedPlayerId and PlayerData[ExposedPlayerId] and PlayerData[ExposedPlayerId].Name or nil
        })
        
        -- Strictly enforce the full 10-second duration even if all players bid early!
        task.wait(bidDuration)
        print(string.format("[ROUND] Bidding END elapsed=%.2f", os.clock() - PhaseStartTime))
        task.wait(1.5) -- 1.5s delay between phases
        
        ------------------------------------------------------------------------
        -- PHASE 4: REVEAL THE RANKINGS & APPLY NEON GREEN SHIELD GLOW
        ------------------------------------------------------------------------
        local revealDuration = GameConfig.RevealRankingsTime or 5.0
        print(string.format("[ROUND] Rankings START duration=%.1f", revealDuration))
        local p4Start = os.clock()
        
        -- Re-filter active players to guarantee anyone who toggled AFK mid-round is excluded from rankings and safe count
        living = GetActivePlayers()
        
        -- Tie-breaker sort: Bid DESC, earliest SubmitTime ASC
        table.sort(living, function(a, b)
            if math.abs(a.CurrentBid - b.CurrentBid) > 0.001 then
                return a.CurrentBid > b.CurrentBid
            end
            return (a.SubmitTime or 999) < (b.SubmitTime or 999)
        end)
        
        local safeCount = math.max(1, math.ceil(#living * 0.5))
        local topBidders = {}
        local bottomBidders = {}
        
        for i, d in ipairs(living) do
            local pName = d.Name
            local pDisp = d.DisplayName or d.Name
            if not d.IsBot and d.UserId and d.UserId > 0 then
                local realP = Players:GetPlayerByUserId(d.UserId)
                if realP then
                    pName = realP.Name
                    pDisp = realP.DisplayName
                end
            end
            local bidderInfo = {
                UserId = d.UserId,
                Name = pName,
                DisplayName = pDisp,
                CurrentBid = d.CurrentBid,
                SubmitTime = d.SubmitTime or 10.00,
                IsBot = d.IsBot,
                Money = d.Money,
                Health = d.Health
            }
            if i <= safeCount then
                table.insert(topBidders, bidderInfo)
            else
                table.insert(bottomBidders, bidderInfo)
            end
        end
        
        -- Apply vibrant neon green glow to all winning bid characters!
        ClearWinnerGlow()
        for _, bidder in ipairs(topBidders) do
            if bidder.IsBot and bidder.Character then
                ApplyWinnerGlow(bidder.Character)
            else
                local p = Players:GetPlayerByUserId(bidder.UserId)
                if p and p.Character then
                    ApplyWinnerGlow(p.Character)
                end
            end
        end
        
        RankingsRevealed:FireAllClients({
            Duration = revealDuration,
            TopBidders = topBidders,
            BottomBidders = bottomBidders,
            SafeCount = safeCount
        })
        BroadcastState("Phase4_Reveal", revealDuration, {
            TopBidders = topBidders,
            BottomBidders = bottomBidders
        })
        task.wait(revealDuration)
        print(string.format("[ROUND] Rankings END elapsed=%.2f", os.clock() - p4Start))
        task.wait(1.5) -- 1.5s delay between phases
        
        ------------------------------------------------------------------------
        -- PHASE 5: THE SURVIVAL STANCE & RUINS DOOR HAZARD SMASH (9s)
        ------------------------------------------------------------------------
        local scrambleDuration = GameConfig.ScrambleTime or 9.0
        print(string.format("[ROUND] SurvivalStance START duration=%.1f", scrambleDuration))
        local p5Start = os.clock()
        
        BroadcastState("Phase5_Scramble", scrambleDuration, { SafeCount = safeCount })
        
        local dmg = math.floor((GameConfig.MaxHealth * CurrentRarity.DamagePercent) / 100)
        
        -- Trigger Phase 6 Hammer Smash notification as the arm apex raise/slam approaches
        task.delay(1.5, function()
            BroadcastState("Phase6_Smash", 4.0, { Rarity = CurrentRarity })
        end)
        
        TriggerHammerSmash(CurrentRarity, function(escapedPlayers, hitPlayers)
            -- Impact damage applied ONLY to players caught inside the 80% Red Circle and unprotected!
            local hitSet = {}
            if hitPlayers then
                for _, p in ipairs(hitPlayers) do
                    hitSet[p] = true
                    if typeof(p) == "Instance" and p:IsA("Player") then
                        hitSet[p.UserId] = true
                    end
                end
            end

            for _, player in ipairs(GetLivingRealPlayers()) do
                local pData = PlayerData[player.UserId]
                local isProtected = (player.Character and player.Character:FindFirstChild("SafeBidGlow") ~= nil)
                local wasCaught = (hitPlayers == nil) or (hitSet[player] or hitSet[player.UserId])
                if not isProtected and wasCaught and pData then
                    pData.Health = math.max(0, pData.Health - dmg)
                    local char = player.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.Health = pData.Health
                    end
                end
            end
            
            for _, bData in ipairs(living) do
                if bData.IsBot and bData.Character then
                    local isProtected = (bData.Character:FindFirstChild("SafeBidGlow") ~= nil)
                    if not isProtected then
                        bData.Health = math.max(0, bData.Health - dmg)
                        local hum = bData.Character:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Health = bData.Health end
                    end
                end
            end
        end, PlayerData)
        
        ClearWinnerGlow()
        print(string.format("[ROUND] SurvivalStance & Smash END elapsed=%.2f", os.clock() - p5Start))
        task.wait(1.5) -- 1.5s delay between phases
        
        ------------------------------------------------------------------------
        -- PHASE 7: SETTLEMENT & ELIMINATIONS (4 Seconds)
        ------------------------------------------------------------------------
        local settlementDuration = GameConfig.SettlementTime or 4.0
        print(string.format("[ROUND] Settlement START duration=%.1f", settlementDuration))
        local p7Start = os.clock()
        
        for _, bInfo in ipairs(topBidders) do
            local realData = PlayerData[bInfo.UserId]
            if realData and realData.ParticipationState == "Active" then
                if realData.IsBot then
                    realData.Money = math.max(0, math.floor((realData.Money - realData.CurrentBid) * 100) / 100)
                end
            end
        end
        
        local minBid = (living[#living] and living[#living].CurrentBid) or 0
        local lowestTieCount = 0
        for _, d in ipairs(living) do
            if math.abs(d.CurrentBid - minBid) < 0.001 then
                lowestTieCount = lowestTieCount + 1
            end
        end
        
        local elims = {}
        if lowestTieCount > 1 and #living > lowestTieCount then
            for _, d in ipairs(living) do
                if math.abs(d.CurrentBid - minBid) < 0.001 then
                    d.Health = 0
                    table.insert(elims, d.Name .. " (Lowest Bid Tie)")
                end
            end
        end
        
        for _, d in ipairs(living) do
            if d.Health <= 0 and d.IsAlive then
                d.IsAlive = false
                d.ParticipationState = "Eliminated"
                local survTime = math.max(1, math.floor(os.clock() - matchStartTime))
                table.insert(matchEliminations, {
                    UserId = d.UserId or 1,
                    Name = d.Name or "Player",
                    DisplayName = d.DisplayName or d.Name or "Player",
                    SurvivalTime = survTime,
                    IsBot = d.IsBot == true,
                })
                table.insert(elims, d.Name .. " (Eliminated)")
                if not d.IsBot then
                    local p = Players:GetPlayerByUserId(d.UserId)
                    if p then
                        p:SetAttribute("IsInGame", false)
                        CashAndWalletManager.SettlePlayerGameCash(p, "Eliminated")
                        TeleportToLobby(p)
                    end
                elseif d.Character then
                    d.Character:Destroy()
                end
            end
        end
        
        SyncAllStats()
        
        RoundOver:FireAllClients({
            Duration = settlementDuration,
            Eliminations = elims,
            Round = CurrentRound
        })
        BroadcastState("Phase7_Settlement", settlementDuration, { Eliminations = elims })
        task.wait(settlementDuration)
        print(string.format("[ROUND] Settlement END elapsed=%.2f", os.clock() - p7Start))
        task.wait(1.5) -- 1.5s delay before next round begins
    end
end

--------------------------------------------------------------------------------
-- EVENT LISTENERS
--------------------------------------------------------------------------------

BidSubmitted.OnServerEvent:Connect(function(player, amount)
    local data = PlayerData[player.UserId]
    if data and data.IsAlive and data.ParticipationState == "Active" and CurrentPhase == "Phase3_Bid" then
        if data.SubmitTime ~= nil then
            return -- Only first valid bid is accepted
        end
        local bid = tonumber(amount)
        if not bid or bid ~= bid or bid < 0 then
            return
        end
        local ok, actualBid = CashAndWalletManager.TrySpendFromWallet(player, bid)
        if not ok then return end
        data.CurrentBid = actualBid
        data.Money = player:GetAttribute("Wallet") or (data.Money - actualBid)
        data.Wallet = data.Money
        local elapsed = math.max(0.01, os.clock() - PhaseStartTime)
        data.SubmitTime = math.floor(elapsed * 100) / 100
        print(string.format("[ROUND MANAGER] %s placed bid: $%.2f in %.2fs (Wallet remaining: $%.2f)", player.Name, data.CurrentBid, data.SubmitTime, player:GetAttribute("Wallet") or 0))
    else
        warn(string.format("[SECURITY] Rejected bid from inactive/eliminated player %s", player.Name))
    end
end)

-- Dead player vote sabotage removed per requirements

-- AFK toggle listener (Stores preference; evaluated ONLY when next game starts before taking players to game area)
SetAFK.OnServerEvent:Connect(function(player, isAfk)
    local data = PlayerData[player.UserId]
    if not data then
        InitPlayer(player)
        data = PlayerData[player.UserId]
    end
    if not data then return end
    
    local wantAfk = (isAfk == true)
    data.IsAFK = wantAfk
    player:SetAttribute("IsAFK", wantAfk)
    
    -- ONLY update participation state if player is NOT in an active game
    if data.ParticipationState ~= "Active" then
        data.ParticipationState = wantAfk and "AFK" or "WaitingInLobby"
        SyncStats(player)
        print(string.format("[ROUND MANAGER] %s updated lobby AFK state to %s", player.Name, tostring(wantAfk)))
    else
        -- Player is actively playing in the game area.
        -- Specifications: Just store the value and consider only when next game starts!
        print(string.format("[ROUND MANAGER] %s toggled AFK = %s in game area (stored for next game; current active gameplay unaffected)", player.Name, tostring(wantAfk)))
    end
end)

GetGameState.OnServerInvoke = function(player)
    local pData = PlayerData[player.UserId]
    return {
        Round = CurrentRound,
        Phase = CurrentPhase,
        Timer = PhaseTimer,
        Rarity = CurrentRarity,
        PlayerData = pData,
        ParticipationState = pData and pData.ParticipationState or "WaitingInLobby"
    }
end

local function InitPlayer(player)
    if not PlayerData[player.UserId] then
        local isAfk = (player:GetAttribute("IsAFK") == true)
        PlayerData[player.UserId] = {
            UserId = player.UserId,
            Name = player.DisplayName,
            Money = CashAndWalletManager.STARTING_GAME_WALLET or 20,
            Wallet = CashAndWalletManager.STARTING_GAME_WALLET or 20,
            Health = GameConfig.MaxHealth,
            IsAlive = true,
            IsAFK = isAfk,
            ParticipationState = isAfk and "AFK" or "WaitingInLobby",
            CurrentBid = 0,
            Votes = 0,
            IsBot = false,
            Character = player.Character
        }
        player:SetAttribute("IsInGame", false)
    end
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        local data = PlayerData[player.UserId]
        if not data or data.ParticipationState ~= "Active" then
            TeleportToLobby(player)
        else
            -- Active player respawned after death
            data.Health = 0
            data.IsAlive = false
            data.ParticipationState = "Eliminated"
            player:SetAttribute("IsInGame", false)
            CashAndWalletManager.SettlePlayerGameCash(player, "Eliminated")
            SyncStats(player)
            TeleportToLobby(player)
        end
    end)
    if player.Character then
        task.spawn(function()
            task.wait(0.5)
            local data = PlayerData[player.UserId]
            if not data or data.ParticipationState ~= "Active" then
                TeleportToLobby(player)
            end
        end)
    end
    SyncStats(player)
end

for _, p in ipairs(Players:GetPlayers()) do
    InitPlayer(p)
end
Players.PlayerAdded:Connect(InitPlayer)

Players.PlayerRemoving:Connect(function(player)
    PlayerData[player.UserId] = nil
end)

-- Main Server Lifecycle Loop
task.spawn(function()
    while true do
        local readyPlayers = GetReadyEligiblePlayers()
        if #readyPlayers < GameConfig.MinPlayersToStart then
            BroadcastState("WaitingForPlayers", 0, { Needed = GameConfig.MinPlayersToStart, Reason = "Waiting for R6 avatar, animations and map to load" })
            task.wait(0.5)
        else
            print("[BOOT HIERARCHY] ✅ Step 1 (R6 Rig) -> Step 2 (Walk/Run/Dive Anims) -> Step 3 (Ruins Door Ready) complete! Starting LobbyCountdown.")
            CurrentRoundSession = CurrentRoundSession + 1
            local session = CurrentRoundSession
            
            local duration = GameConfig.IntermissionTime or 5
            print(string.format("[ROUND] LobbyCountdown START duration=%d", duration))
            local countdownStart = os.clock()
            
            local cancelled = false
            for sec = duration, 1, -1 do
                local curReady = GetReadyEligiblePlayers()
                if #curReady < GameConfig.MinPlayersToStart or session ~= CurrentRoundSession then
                    print("[ROUND] LobbyCountdown CANCELLED (players left or unready)")
                    cancelled = true
                    break
                end
                BroadcastState("Intermission", sec)
                task.wait(1)
            end
            
            if not cancelled and session == CurrentRoundSession and #GetReadyEligiblePlayers() >= GameConfig.MinPlayersToStart then
                print(string.format("[ROUND] LobbyCountdown END elapsed=%.2f", os.clock() - countdownStart))
                RunMatch(session)
            end
        end
    end
end)
