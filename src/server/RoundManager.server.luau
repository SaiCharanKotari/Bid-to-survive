-- BID TO SURVIVE - Master Round Manager
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local GetGameState = Network:WaitForChild("GetGameState")

local Map = workspace:WaitForChild("BidToSurviveMap")
local SpawnArea = Map:WaitForChild("SpawnArea")
local GameplayArea = Map:WaitForChild("GameplayArea")
local Walkway = GameplayArea:WaitForChild("Walkway")
local SafeTilesFolder = GameplayArea:WaitForChild("SafeTiles")
local Executioner = GameplayArea:FindFirstChild("Executioner")

-- State Variables
local CurrentRound = 0
local CurrentRoundSession = 0
local CurrentPhase = "Intermission"
local PhaseTimer = 0
local CurrentRarity = GameConfig.HammerRarities.Common
local MatchActive = false
local PhaseStartTime = 0

-- Player Data Store { [UserId] = { Money, Health, IsAlive, CurrentBid, Votes, IsBot, Name, UserId, Character, SubmitTime } }
local PlayerData = {}
local ExposedPlayerId = nil
local ActiveBots = {}

local TILE_SIZE = Vector3.new(12, 0.6, 12)

--------------------------------------------------------------------------------
-- UTILITY & STATS
--------------------------------------------------------------------------------

local function GetLivingPlayers()
    local living = {}
    for id, data in pairs(PlayerData) do
        if data.IsAlive then
            table.insert(living, data)
        end
    end
    return living
end

local function GetLivingRealPlayers()
    local living = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        if data and data.IsAlive then
            table.insert(living, player)
        end
    end
    return living
end

local function GetSpectatorPlayers()
    local spectators = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData[player.UserId]
        if data and not data.IsAlive then
            table.insert(spectators, player)
        end
    end
    return spectators
end

local function BroadcastState(phaseName, duration, extra)
    CurrentPhase = phaseName
    PhaseTimer = duration or 0
    local livingCount = #GetLivingPlayers()
    local deadline = os.clock() + (duration or 0)
    
    print(string.format("[ROUND MANAGER] Phase: %s | Round: %d | Duration: %ds | Living: %d", phaseName, CurrentRound, PhaseTimer, livingCount))
    StateChanged:FireAllClients({
        Phase = CurrentPhase,
        Duration = PhaseTimer,
        Deadline = deadline,
        Round = CurrentRound,
        Rarity = CurrentRarity,
        LivingCount = livingCount,
        ExposedPlayer = ExposedPlayerId and PlayerData[ExposedPlayerId] and PlayerData[ExposedPlayerId].Name or nil,
        Extra = extra
    })
end

local function SyncStats(player)
    local data = PlayerData[player.UserId]
    if data then
        StatsUpdated:FireClient(player, {
            Money = data.Money,
            Health = data.Health,
            IsAlive = data.IsAlive,
            Round = CurrentRound
        })
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
        char:PivotTo(CFrame.new(targetPos)) -- Physics sync
    end
end

local function TeleportToLobby(player)
    local char = player.Character
    if not char then return end
    local lobbySpawn = SpawnArea:FindFirstChild("LobbySpawn")
    local basePos = lobbySpawn and lobbySpawn.Position or Vector3.new(39.5, 93, -27.7)
    local offset = Vector3.new(math.random(-5, 5), 3, math.random(-5, 5))
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
    local realCount = #Players:GetPlayers()
    local botsNeeded = math.max(0, targetTotal - realCount)
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
-- SAFE TILES MANAGEMENT
--------------------------------------------------------------------------------

local function ClearSafeTiles()
    SafeTilesFolder:ClearAllChildren()
end

local function CreateSafeTile(cframe, index)
    local tile = Instance.new("Part")
    tile.Name = "SafeTile_" .. index
    tile.Size = TILE_SIZE
    tile.CFrame = cframe
    tile.Anchored = true
    tile.CanCollide = true
    tile.Material = Enum.Material.Neon
    tile.Color = Color3.fromRGB(0, 255, 120)
    tile.Transparency = 1
    
    local border = Instance.new("SelectionBox")
    border.Color3 = Color3.fromRGB(220, 255, 220)
    border.LineThickness = 0.08
    border.Adornee = tile
    border.Parent = tile
    
    local sg = Instance.new("SurfaceGui")
    sg.Face = Enum.NormalId.Top
    sg.CanvasSize = Vector2.new(256, 256)
    sg.Parent = tile
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "SAFE TILE\n#" .. index
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = sg
    
    tile.Parent = SafeTilesFolder
    
    TweenService:Create(tile, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 0.2
    }):Play()
    
    return tile
end

local function SpawnSafeTiles(count)
    ClearSafeTiles()
    local spawned = {}
    local wPos = Walkway.Position
    local minDistance = 22
    
    for i = 1, count do
        local attempts = 0
        local pos = nil
        while attempts < 30 do
            attempts = attempts + 1
            local rx = math.random(-48, 48)
            local rz = math.random(-45, 30)
            local testPos = Vector3.new(wPos.X + rx, wPos.Y + 0.35, wPos.Z + rz)
            
            local tooClose = false
            for _, existing in ipairs(spawned) do
                if (existing.Position - testPos).Magnitude < minDistance then
                    tooClose = true
                    break
                end
            end
            if not tooClose then
                pos = testPos
                break
            end
        end
        
        pos = pos or Vector3.new(wPos.X + (i * 18 - 36), wPos.Y + 0.35, wPos.Z)
        local tile = CreateSafeTile(CFrame.new(pos), i)
        table.insert(spawned, tile)
    end
    
    return spawned
end

local function IsPositionOnSafeTile(pos)
    for _, tile in ipairs(SafeTilesFolder:GetChildren()) do
        if tile:IsA("BasePart") then
            local tPos = tile.Position
            local tSize = tile.Size
            local inX = math.abs(pos.X - tPos.X) <= (tSize.X / 2 + 1.5)
            local inZ = math.abs(pos.Z - tPos.Z) <= (tSize.Z / 2 + 1.5)
            local inY = (pos.Y >= tPos.Y - 1.5) and (pos.Y <= tPos.Y + 7)
            if inX and inZ and inY then
                return true
            end
        end
    end
    return false
end

local function IsPlayerOnSafeTile(player)
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return IsPositionOnSafeTile(hrp.Position)
end

--------------------------------------------------------------------------------
-- HAMMER SMASH EXECUTION
--------------------------------------------------------------------------------

local function TriggerHammerSmash(rarity)
    local exec = GameplayArea:FindFirstChild("Executioner")
    local repAnim = ReplicatedStorage:WaitForChild("Animations"):FindFirstChild("A powerful")
    
    if exec then
        local hammerModel = exec:FindFirstChild("ExecutionerHammer") or exec:FindFirstChild("Thors Hammer")
        if hammerModel then
            local handle = hammerModel:FindFirstChild("Handle")
            if handle then
                handle.Color = rarity.Color
                handle.Material = rarity.Neon and Enum.Material.Neon or Enum.Material.Metal
                local slashSound = handle:FindFirstChild("slash")
                if slashSound then
                    slashSound.PlaybackSpeed = rarity.SoundPitch
                    slashSound:Play()
                end
            end
        end
        
        local humanoid = exec:FindFirstChild("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator and repAnim then
            local track = animator:LoadAnimation(repAnim)
            track.Priority = Enum.AnimationPriority.Action
            track:Play(0.1)
        end
    end
    
    HammerSmash:FireAllClients({
        Rarity = rarity,
        ImpactDelay = 1.33
    })
end

--------------------------------------------------------------------------------
-- MATCH LIFECYCLE
--------------------------------------------------------------------------------

local function InitMatch()
    CurrentRound = 0
    MatchActive = true
    PlayerData = {}
    ExposedPlayerId = nil
    
    for _, player in ipairs(Players:GetPlayers()) do
        PlayerData[player.UserId] = {
            UserId = player.UserId,
            Name = player.DisplayName,
            Money = GameConfig.StartingMoney,
            Health = GameConfig.MaxHealth,
            IsAlive = true,
            CurrentBid = 0,
            Votes = 0,
            IsBot = false,
            Character = player.Character
        }
    end
    
    local totalReal = #Players:GetPlayers()
    if totalReal < 4 then
        SetupCompanionBots(4)
    end
    
    SyncAllStats()
    ClearSafeTiles()
end

local function RunMatch(session)
    InitMatch()
    
    while MatchActive do
        if session ~= CurrentRoundSession then
            print("[ROUND] Obsolete session cancelled.")
            break
        end
        
        CurrentRound = CurrentRound + 1
        local living = GetLivingPlayers()
        
        -- Check Sole Survivor / Win condition
        if #living <= 1 then
            local winner = living[1]
            local winName = winner and winner.Name or "No One"
            print("[ROUND MANAGER] Match Ended! Sole Survivor: " .. winName)
            BroadcastState("MatchOver", 6, { Winner = winName })
            MatchOver:FireAllClients({
                Winner = winName,
                RoundsSurvived = CurrentRound - 1
            })
            task.wait(6)
            for _, p in ipairs(Players:GetPlayers()) do
                TeleportToLobby(p)
            end
            CleanupBots()
            MatchActive = false
            break
        end
        
        -- Roll Server-Authoritative Rarity
        CurrentRarity = GameConfig.RollRarity()
        
        ------------------------------------------------------------------------
        -- PHASE 1: SPAWN / HAMMER ROULETTE REVEAL
        ------------------------------------------------------------------------
        local spawnDuration = GameConfig.SpawnPhaseTime or 8.0
        print(string.format("[ROUND] HammerReveal START duration=%.1f", spawnDuration))
        local p1Start = os.clock()
        
        for _, p in ipairs(GetLivingRealPlayers()) do
            TeleportToArena(p)
        end
        
        local wPos = Walkway.Position
        for i, b in ipairs(ActiveBots) do
            if b.IsAlive and b.Character then
                b.Character:PivotTo(CFrame.new(wPos.X + (i * 20 - 30), wPos.Y + 3.5, wPos.Z + math.random(-25, 25)))
            end
        end
        
        BroadcastState("Phase1_Spawn", spawnDuration, {
            Round = CurrentRound,
            Rarity = CurrentRarity,
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
        -- PHASE 4: REVEAL THE RANKINGS (Exactly 5 Seconds)
        ------------------------------------------------------------------------
        local revealDuration = GameConfig.RevealRankingsTime or 5.0
        print(string.format("[ROUND] Rankings START duration=%.1f", revealDuration))
        local p4Start = os.clock()
        
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
        -- PHASE 5: THE SCRAMBLE (Safe Tiles appear, 9s Scramble)
        ------------------------------------------------------------------------
        local scrambleDuration = GameConfig.ScrambleTime or 9.0
        print(string.format("[ROUND] TileScramble START duration=%.1f", scrambleDuration))
        local p5Start = os.clock()
        
        local tiles = SpawnSafeTiles(safeCount)
        BroadcastState("Phase5_Scramble", scrambleDuration, { SafeCount = safeCount })
        
        for i, bData in ipairs(topBidders) do
            if bData.IsBot and bData.Character and tiles[i] then
                task.spawn(function()
                    task.wait(math.random(1, 3))
                    local bHum = bData.Character:FindFirstChildOfClass("Humanoid")
                    if bHum then
                        bHum:MoveTo(tiles[i].Position + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2)))
                    end
                end)
            end
        end
        
        task.wait(scrambleDuration)
        print(string.format("[ROUND] TileScramble END elapsed=%.2f", os.clock() - p5Start))
        
        ------------------------------------------------------------------------
        -- PHASE 6: HAMMER SMASH (3 Seconds)
        ------------------------------------------------------------------------
        print("[ROUND] HammerSmash START duration=3")
        local p6Start = os.clock()
        
        BroadcastState("Phase6_Smash", 3, { Rarity = CurrentRarity })
        TriggerHammerSmash(CurrentRarity)
        task.wait(1.33) -- Impact timing
        
        local dmg = math.floor((GameConfig.MaxHealth * CurrentRarity.DamagePercent) / 100)
        
        for _, player in ipairs(GetLivingRealPlayers()) do
            local pData = PlayerData[player.UserId]
            local onSafe = IsPlayerOnSafeTile(player)
            if not onSafe then
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
                local hrp = bData.Character:FindFirstChild("HumanoidRootPart")
                local onSafe = hrp and IsPositionOnSafeTile(hrp.Position)
                if not onSafe then
                    bData.Health = math.max(0, bData.Health - dmg)
                    local hum = bData.Character:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Health = bData.Health end
                end
            end
        end
        
        task.wait(1.5)
        ClearSafeTiles()
        print(string.format("[ROUND] HammerSmash END elapsed=%.2f", os.clock() - p6Start))
        
        ------------------------------------------------------------------------
        -- PHASE 7: SETTLEMENT & ELIMINATIONS (4 Seconds)
        ------------------------------------------------------------------------
        local settlementDuration = GameConfig.SettlementTime or 4.0
        print(string.format("[ROUND] Settlement START duration=%.1f", settlementDuration))
        local p7Start = os.clock()
        
        for _, d in ipairs(topBidders) do
            d.Money = math.max(0, math.floor((d.Money - d.CurrentBid) * 100) / 100)
        end
        
        local minBid = living[#living].CurrentBid
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
                table.insert(elims, d.Name .. " (Eliminated)")
                if not d.IsBot then
                    local p = Players:GetPlayerByUserId(d.UserId)
                    if p then TeleportToLobby(p) end
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
    if data and data.IsAlive and CurrentPhase == "Phase3_Bid" then
        if data.SubmitTime ~= nil then
            return -- Only first valid bid is accepted
        end
        local bid = tonumber(amount)
        if not bid or bid ~= bid or bid < 0 or bid > data.Money then
            return -- Reject invalid, negative, NaN or unaffordable bids
        end
        bid = math.floor(bid * 100) / 100
        data.CurrentBid = bid
        local elapsed = math.max(0.01, os.clock() - PhaseStartTime)
        data.SubmitTime = math.floor(elapsed * 100) / 100
        print(string.format("[ROUND MANAGER] %s placed bid: $%.2f in %.2fs", player.Name, data.CurrentBid, data.SubmitTime))
    end
end)

VoteSubmitted.OnServerEvent:Connect(function(player, targetUserId)
    local data = PlayerData[player.UserId]
    if data and not data.IsAlive and CurrentPhase == "Phase2_Vote" then
        local target = PlayerData[targetUserId]
        if target and target.IsAlive then
            target.Votes = target.Votes + 1
        end
    end
end)

GetGameState.OnServerInvoke = function(player)
    return {
        Round = CurrentRound,
        Phase = CurrentPhase,
        Timer = PhaseTimer,
        Rarity = CurrentRarity,
        PlayerData = PlayerData[player.UserId]
    }
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        TeleportToLobby(player)
    end)
end)

-- Main Server Lifecycle Loop
task.spawn(function()
    task.wait(1.5)
    while true do
        local count = #Players:GetPlayers()
        if count >= GameConfig.MinPlayersToStart then
            CurrentRoundSession = CurrentRoundSession + 1
            local session = CurrentRoundSession
            
            local duration = GameConfig.IntermissionTime or 5
            print(string.format("[ROUND] LobbyCountdown START duration=%d", duration))
            local countdownStart = os.clock()
            
            local cancelled = false
            for sec = duration, 1, -1 do
                if #Players:GetPlayers() < GameConfig.MinPlayersToStart or session ~= CurrentRoundSession then
                    print("[ROUND] LobbyCountdown CANCELLED (players left)")
                    cancelled = true
                    break
                end
                BroadcastState("Intermission", sec)
                task.wait(1)
            end
            
            if not cancelled and session == CurrentRoundSession and #Players:GetPlayers() >= GameConfig.MinPlayersToStart then
                print(string.format("[ROUND] LobbyCountdown END elapsed=%.2f", os.clock() - countdownStart))
                RunMatch(session)
            end
        else
            BroadcastState("WaitingForPlayers", 0, { Needed = GameConfig.MinPlayersToStart })
            task.wait(1.5)
        end
    end
end)
