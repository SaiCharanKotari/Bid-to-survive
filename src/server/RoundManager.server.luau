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
        if data.IsAlive and not data.IsAFK and data.ParticipationState == "Active" then
            table.insert(active, data)
        end
    end
    return active
end

local function GetActiveRealPlayers()
    local active = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        if data and data.IsAlive and not data.IsAFK and data.ParticipationState == "Active" then
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
        if data and not data.IsAlive and not data.IsAFK and data.ParticipationState == "Eliminated" then
            table.insert(spectators, player)
        end
    end
    return spectators
end

local function GetReadyEligiblePlayers()
    local ready = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        local isAfk = player:GetAttribute("IsAFK") or (data and data.IsAFK)
        local isClientReady = player:GetAttribute("ClientReady") == true
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local isR6 = hum and hum.RigType == Enum.HumanoidRigType.R6
        local isLiving = hum and hum.Health > 0
        if not isAfk and isClientReady and isR6 and isLiving then
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
    local realActiveCount = #GetLivingRealPlayers()
    local botsNeeded = math.max(0, targetTotal - realActiveCount)
    local botNames = {"ApeSlayer", "ShadowRunner", "LuckyBids", "AlphaTitan", "RiskHunter"}
    local wPos = Walkway.Position
    
    for i = 1, botsNeeded do
        local bName = botNames[i] or ("Bot_" .. i)
        local bId = -200 - i
        local spawnPos = Vector3.new(wPos.X + (i * 20 - 40), wPos.Y + 3.5, wPos.Z + math.random(-20, 20))
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
    for _, player in ipairs(Players:GetPlayers()) do
        local existing = PlayerData[player.UserId]
        local isAfk = (existing ~= nil) and existing.IsAFK or false
        local partState = isAfk and "AFK" or "WaitingInLobby"
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
    end
    
    SetupCompanionBots(4)
    CashAndWalletManager.StartGameForPlayers(GetReadyEligiblePlayers())
    SyncAllStats()
    ClearWinnerGlow()
end

local function RunMatch(session)
    InitMatch()
    
    while MatchActive do
        if session ~= CurrentRoundSession then
            print("[ROUND] Obsolete session cancelled.")
            break
        end
        
        CurrentRound = CurrentRound + 1
        
        -- Safely admit all eligible waiting players into this active round!
        for _, player in ipairs(Players:GetPlayers()) do
            local data = PlayerData[player.UserId]
            if data and not data.IsAFK and data.IsAlive then
                data.ParticipationState = "Active"
                SyncStats(player)
            end
        end
        for _, bot in ipairs(ActiveBots) do
            if bot.IsAlive then
                bot.ParticipationState = "Active"
            end
        end
        
        local living = GetActivePlayers()
        
        -- Check Sole Survivor / Win condition
        if #living <= 1 then
            local winner = living[1]
            local winName = winner and winner.Name or "No One"
            print("[ROUND MANAGER] Match Ended! Sole Survivor: " .. winName)
            CashAndWalletManager.EndGameAndRewardSurvivors()
            BroadcastState("MatchOver", 6, { Winner = winName })
            MatchOver:FireAllClients({
                Winner = winName,
                RoundsSurvived = CurrentRound - 1
            })
            task.wait(6)
            for _, p in ipairs(Players:GetPlayers()) do
                TeleportToLobby(p)
                local pData = PlayerData[p.UserId]
                if pData and not pData.IsAFK then
                    pData.ParticipationState = "WaitingInLobby"
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
        
        -- Reset bots to arena
        local wPos = Walkway.Position
        for i, b in ipairs(ActiveBots) do
            if b.IsAlive and b.Character then
                b.Character:PivotTo(CFrame.new(wPos.X + (i * 20 - 30), wPos.Y + 3.5, wPos.Z + math.random(-25, 25)))
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
        
        ------------------------------------------------------------------------
        -- PHASE 2: ANONYMOUS VOTE (From Round 2+ if spectators exist)
        ------------------------------------------------------------------------
        ExposedPlayerId = nil
        local spectators = GetSpectatorPlayers()
        if CurrentRound >= 2 and #spectators > 0 and #living >= 2 then
            local voteDuration = GameConfig.VoteTime or 7.0
            print(string.format("[ROUND] AnonymousVote START duration=%.1f", voteDuration))
            local p2Start = os.clock()
            for _, d in pairs(PlayerData) do d.Votes = 0 end
            BroadcastState("Phase2_Vote", voteDuration, { Candidates = living })
            PromptVote:FireAllClients({ Duration = voteDuration, Candidates = living })
            task.wait(voteDuration)
            
            local topVotes = 0
            local targetId = nil
            local tie = false
            for _, d in ipairs(living) do
                if d.Votes > topVotes then
                    topVotes = d.Votes
                    targetId = d.UserId
                    tie = false
                elseif d.Votes == topVotes and topVotes > 0 then
                    tie = true
                end
            end
            if not tie and targetId then
                ExposedPlayerId = targetId
            end
            print(string.format("[ROUND] AnonymousVote END elapsed=%.2f", os.clock() - p2Start))
        end
        
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
            local bidderInfo = {
                UserId = d.UserId,
                Name = d.Name,
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
        
        ------------------------------------------------------------------------
        -- PHASE 7: SETTLEMENT & ELIMINATIONS (4 Seconds)
        ------------------------------------------------------------------------
        local settlementDuration = GameConfig.SettlementTime or 4.0
        print(string.format("[ROUND] Settlement START duration=%.1f", settlementDuration))
        local p7Start = os.clock()
        
        for _, bInfo in ipairs(topBidders) do
            local realData = PlayerData[bInfo.UserId]
            if realData and not realData.IsAFK and realData.ParticipationState == "Active" then
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
                table.insert(elims, d.Name .. " (Eliminated)")
                if not d.IsBot then
                    local p = Players:GetPlayerByUserId(d.UserId)
                    if p then
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
    end
end

--------------------------------------------------------------------------------
-- EVENT LISTENERS
--------------------------------------------------------------------------------

BidSubmitted.OnServerEvent:Connect(function(player, amount)
    local data = PlayerData[player.UserId]
    if data and data.IsAlive and not data.IsAFK and data.ParticipationState == "Active" and CurrentPhase == "Phase3_Bid" then
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
        print(string.format("[ROUND MANAGER] %s placed bid: $%.2f in %.2fs (Wallet remaining: $%d)", player.Name, data.CurrentBid, data.SubmitTime, player:GetAttribute("Wallet") or 0))
    else
        warn(string.format("[SECURITY] Rejected bid from inactive/AFK player %s", player.Name))
    end
end)

VoteSubmitted.OnServerEvent:Connect(function(player, targetUserId)
    local data = PlayerData[player.UserId]
    if data and not data.IsAlive and not data.IsAFK and data.ParticipationState == "Eliminated" and CurrentPhase == "Phase2_Vote" then
        local target = PlayerData[targetUserId]
        if target and target.IsAlive and target.ParticipationState == "Active" then
            target.Votes = target.Votes + 1
        end
    end
end)

-- AFK toggle listener (Default is OFF upon joining; players toggle between ON/OFF)
SetAFK.OnServerEvent:Connect(function(player, isAfk)
    local data = PlayerData[player.UserId]
    if not data then
        InitPlayer(player)
        data = PlayerData[player.UserId]
    end
    if not data then return end
    
    local wantAfk = (isAfk == true)
    data.IsAFK = wantAfk
    
    if wantAfk then
        data.ParticipationState = "AFK"
        -- Clear any active round artifacts
        data.CurrentBid = 0
        data.SubmitTime = nil
        if player.Character then
            local hl = player.Character:FindFirstChild("SafeBidGlow")
            if hl then hl:Destroy() end
        end
        TeleportToLobby(player)
        print(string.format("[ROUND MANAGER] %s enabled AFK (removed from active round, moved to lobby)", player.Name))
    else
        -- Switched to AFK: OFF
        -- Keep player safely in the lobby until the next eligible round admits them
        data.ParticipationState = "WaitingInLobby"
        TeleportToLobby(player)
        print(string.format("[ROUND MANAGER] %s turned AFK OFF (waiting in lobby for next eligible round)", player.Name))
    end
    SyncStats(player)
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
        PlayerData[player.UserId] = {
            UserId = player.UserId,
            Name = player.DisplayName,
            Money = 0,
            Wallet = 0,
            Health = GameConfig.MaxHealth,
            IsAlive = true,
            IsAFK = false, -- Default OFF as requested
            ParticipationState = "WaitingInLobby",
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
        if not data or data.IsAFK or data.ParticipationState ~= "Active" then
            TeleportToLobby(player)
        else
            -- Active player respawned after death
            data.Health = 0
            data.IsAlive = false
            data.ParticipationState = "Eliminated"
            CashAndWalletManager.SettlePlayerGameCash(player, "Eliminated")
            SyncStats(player)
            TeleportToLobby(player)
        end
    end)
    if player.Character then
        task.spawn(function()
            task.wait(0.5)
            TeleportToLobby(player)
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
