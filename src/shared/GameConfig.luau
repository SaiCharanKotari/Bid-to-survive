local GameConfig = {}

GameConfig.StartingMoney = 20.00
GameConfig.MaxHealth = 100
GameConfig.MinPlayersToStart = 1
GameConfig.MaxPlayers = 10

-- Exact Authoritative Phase Timings
GameConfig.IntermissionTime = 5       -- Lobby Countdown (5 full seconds)
GameConfig.RouletteDuration = 6.0     -- Visible decelerating roulette animation
GameConfig.RouletteHoldTime = 1.5     -- Hold revealed hammer before transition
GameConfig.SpawnPhaseTime = 8.0       -- Total Phase 1 duration (6.0s + 1.5s + 0.5s pause)
GameConfig.VoteTime = 7               -- Anonymous Vote (Round 2+)
GameConfig.BidTime = 10               -- Bidding Phase (Exactly 10 seconds)
GameConfig.RevealRankingsTime = 5     -- Leaderboard reveal (5 full seconds)
GameConfig.ScrambleTime = 9           -- Safe tile scramble (9 seconds)
GameConfig.SmashDelay = 2.5           -- Executioner windup
GameConfig.SettlementTime = 4         -- Round settlement and eliminations

GameConfig.HammerRarities = {
    Common = {
        Name = "Common",
        Chance = 0.35,
        DamagePercent = 30,
        Color = Color3.fromRGB(220, 225, 235),
        GlowColor = Color3.fromRGB(240, 240, 255),
        Neon = false,
        SoundPitch = 1.0,
        CameraShake = 0.5,
        AssetFile = "hammer_common.png",
        AssetId = "rbxassetid://99687163311393",
    },
    Uncommon = {
        Name = "Uncommon",
        Chance = 0.30,
        DamagePercent = 40,
        Color = Color3.fromRGB(80, 220, 100),
        GlowColor = Color3.fromRGB(60, 255, 120),
        Neon = false,
        SoundPitch = 0.95,
        CameraShake = 0.8,
        AssetFile = "hammer_uncommon.png",
        AssetId = "rbxassetid://94906827959757",
    },
    Rare = {
        Name = "Rare",
        Chance = 0.20,
        DamagePercent = 50,
        Color = Color3.fromRGB(70, 160, 255),
        GlowColor = Color3.fromRGB(0, 195, 255),
        Neon = true,
        SoundPitch = 0.9,
        CameraShake = 1.2,
        AssetFile = "hammer_rare.png",
        AssetId = "rbxassetid://99122878797775",
    },
    Legendary = {
        Name = "Legendary",
        Chance = 0.10,
        DamagePercent = 60,
        Color = Color3.fromRGB(255, 170, 0),
        GlowColor = Color3.fromRGB(255, 200, 30),
        Neon = true,
        SoundPitch = 0.85,
        CameraShake = 1.6,
        AssetFile = "hammer_legendary.png",
        AssetId = "rbxassetid://134660087390735",
    },
    Mythical = {
        Name = "Mythical",
        Chance = 0.05,
        DamagePercent = 70,
        Color = Color3.fromRGB(255, 0, 120),
        GlowColor = Color3.fromRGB(255, 40, 180),
        Neon = true,
        SoundPitch = 0.75,
        CameraShake = 2.2,
        AssetFile = "hammer_mythical.png",
        AssetId = "rbxassetid://105142270694831",
    }
}

GameConfig.RarityOrder = {"Common", "Uncommon", "Rare", "Legendary", "Mythical"}

function GameConfig.GetRarityList()
    local list = {}
    for _, name in ipairs(GameConfig.RarityOrder) do
        table.insert(list, GameConfig.HammerRarities[name])
    end
    return list
end

function GameConfig.RollRarity()
    local roll = math.random()
    local cumulative = 0
    for _, name in ipairs(GameConfig.RarityOrder) do
        local data = GameConfig.HammerRarities[name]
        if data then
            cumulative = cumulative + data.Chance
            if roll <= cumulative then
                return data
            end
        end
    end
    return GameConfig.HammerRarities.Common
end

return GameConfig
