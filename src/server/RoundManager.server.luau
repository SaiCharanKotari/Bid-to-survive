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
local CurrentPhase = "Intermission"
local PhaseTimer = 0
local CurrentRarity = GameConfig.HammerRarities.Common
local MatchActive = false

-- Player Data Store { [UserId] = { Money, Health, IsAlive, CurrentBid, Votes, IsBot, Name, UserId, Character } }
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
    print(string.format("[ROUND MANAGER] Phase: %s | Round: %d | Duration: %ds | Living: %d", phaseName, CurrentRound, PhaseTimer, livingCount))
    StateChanged:FireAllClients({
        Phase = CurrentPhase,
        Duration = PhaseTimer,
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
        char:PivotTo(CFrame.new(targetPos)) -- Double call to guarantee physics synchronization
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
    -- Place across 140x140 walkway
    local rx = math.random(-45, 45)
    local rz = math.random(-35, 35)
    local targetPos = Vector3.new(wPos.X + rx, wPos.Y + 3.5, wPos.Z + rz)
    TeleportCharacter(char, targetPos)
end

--------------------------------------------------------------------------------
-- BOT CREATION (FOR VISIBLE COMPANIONS IN SOLO/SMALL TESTING)
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
    
    -- Strip dummy scripts/tools
    for _, c in ipairs(botModel:GetDescendants()) do
        if c:IsA("LuaSourceContainer") or c:IsA("Tool") or c.Name == "PlayPrompt" then
            c:Destroy()
        end
    end
    
    -- Give bot distinct color shirt/body
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
    
    -- Setup real players
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
    
    -- Setup bots if testing with fewer than 4 players
    local totalReal = #Players:GetPlayers()
    if totalReal < 4 then
        SetupCompanionBots(4)
    end
    
    SyncAllStats()
    ClearSafeTiles()
end

local function RunMatch()
    InitMatch()
    
    while MatchActive do
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
        
        -- Roll Rarity
        CurrentRarity = GameConfig.RollRarity()
        
        ------------------------------------------------------------------------
        -- PHASE 1: SPAWN / ROUND START
        ------------------------------------------------------------------------
        print("[ROUND MANAGER] Teleporting players to arena for Round " .. CurrentRound)
        for _, p in ipairs(GetLivingRealPlayers()) do
            TeleportToArena(p)
        end
        -- Reset bots to arena
        local wPos = Walkway.Position
        for i, b in ipairs(ActiveBots) do
            if b.IsAlive and b.Character then
                b.Character:PivotTo(CFrame.new(wPos.X + (i * 20 - 30), wPos.Y + 3.5, wPos.Z + math.random(-25, 25)))
            end
        end
        
        BroadcastState("Phase1_Spawn", 3, { Round = CurrentRound, Rarity = CurrentRarity })
        task.wait(3)
        
        ------------------------------------------------------------------------
        -- PHASE 2: ANONYMOUS VOTE (From Round 2+ if spectators exist)
        ------------------------------------------------------------------------
        ExposedPlayerId = nil
        local spectators = GetSpectatorPlayers()
        if CurrentRound >= 2 and #spectators > 0 and #living >= 2 then
            for _, d in pairs(PlayerData) do d.Votes = 0 end
            BroadcastState("Phase2_Vote", GameConfig.VoteTime, { Candidates = living })
            PromptVote:FireAllClients({ Duration = GameConfig.VoteTime, Candidates = living })
            task.wait(GameConfig.VoteTime)
            
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
        end
        
        ------------------------------------------------------------------------
        -- PHASE 3: BID FOR SURVIVAL (10 Seconds)
        ------------------------------------------------------------------------
        for _, d in ipairs(living) do
            d.CurrentBid = 0
            if d.IsBot then
                local maxB = math.min(d.Money, math.random(15, 65) / 10)
                d.CurrentBid = math.floor(maxB * 10) / 10
            end
        end
        
        BroadcastState("Phase3_Bid", GameConfig.BidTime, { ExposedPlayerId = ExposedPlayerId })
        PromptBid:FireAllClients({
            Duration = GameConfig.BidTime,
            ExposedPlayer = ExposedPlayerId and PlayerData[ExposedPlayerId] and PlayerData[ExposedPlayerId].Name or nil
        })
        task.wait(GameConfig.BidTime)
        
        ------------------------------------------------------------------------
        -- PHASE 4: REVEAL THE RANKINGS (5 Seconds)
        ------------------------------------------------------------------------
        table.sort(living, function(a, b)
            return a.CurrentBid > b.CurrentBid
        end)
        
        local safeCount = math.max(1, math.ceil(#living * 0.5))
        local topBidders = {}
        local bottomBidders = {}
        
        for i, d in ipairs(living) do
            if i <= safeCount then
                table.insert(topBidders, d)
            else
                table.insert(bottomBidders, d)
            end
        end
        
        RankingsRevealed:FireAllClients({
            Duration = GameConfig.RevealRankingsTime,
            TopBidders = topBidders,
            BottomBidders = bottomBidders,
            SafeCount = safeCount
        })
        BroadcastState("Phase4_Reveal", GameConfig.RevealRankingsTime, {
            TopBidders = topBidders,
            BottomBidders = bottomBidders
        })
        task.wait(GameConfig.RevealRankingsTime)
        
        ------------------------------------------------------------------------
        -- PHASE 5: THE SCRAMBLE (Safe Tiles appear, 9s scramble)
        ------------------------------------------------------------------------
        local tiles = SpawnSafeTiles(safeCount)
        BroadcastState("Phase5_Scramble", GameConfig.ScrambleTime, { SafeCount = safeCount })
        
        -- Make top-bidding bots move toward safe tiles!
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
        
        task.wait(GameConfig.ScrambleTime)
        
        ------------------------------------------------------------------------
        -- PHASE 6: HAMMER SMASH
        ------------------------------------------------------------------------
        BroadcastState("Phase6_Smash", 3, { Rarity = CurrentRarity })
        TriggerHammerSmash(CurrentRarity)
        task.wait(1.33) -- Impact timing
        
        local dmg = math.floor((GameConfig.MaxHealth * CurrentRarity.DamagePercent) / 100)
        
        -- Check real players
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
        
        -- Check bot players
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
        
        ------------------------------------------------------------------------
        -- PHASE 7: SETTLEMENT & ELIMINATIONS
        ------------------------------------------------------------------------
        -- Top half: bid deducted. Bottom half: bid refunded.
        for _, d in ipairs(topBidders) do
            d.Money = math.max(0, math.floor((d.Money - d.CurrentBid) * 100) / 100)
        end
        
        -- Lowest bid tie-breaker elimination
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
        
        -- Health 0 eliminations
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
            Duration = GameConfig.SettlementTime,
            Eliminations = elims,
            Round = CurrentRound
        })
        BroadcastState("Phase7_Settlement", GameConfig.SettlementTime, { Eliminations = elims })
        task.wait(GameConfig.SettlementTime)
    end
end

--------------------------------------------------------------------------------
-- EVENT LISTENERS
--------------------------------------------------------------------------------

BidSubmitted.OnServerEvent:Connect(function(player, amount)
    local data = PlayerData[player.UserId]
    if data and data.IsAlive and CurrentPhase == "Phase3_Bid" then
        local bid = tonumber(amount) or 0
        bid = math.clamp(bid, 0, data.Money)
        data.CurrentBid = math.floor(bid * 100) / 100
        print(string.format("[ROUND MANAGER] %s placed bid: $%.2f", player.Name, data.CurrentBid))
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
    task.wait(2)
    while true do
        local count = #Players:GetPlayers()
        if count >= GameConfig.MinPlayersToStart then
            BroadcastState("Intermission", GameConfig.IntermissionTime)
            task.wait(GameConfig.IntermissionTime)
            RunMatch()
        else
            BroadcastState("WaitingForPlayers", 0, { Needed = GameConfig.MinPlayersToStart })
            task.wait(2)
        end
    end
end)
