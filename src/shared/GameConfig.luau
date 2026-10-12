local GameConfig = {}

GameConfig.StartingMoney = 20.00
GameConfig.MaxHealth = 100
GameConfig.MinPlayersToStart = 1
GameConfig.MaxPlayers = 10

GameConfig.IntermissionTime = 5
GameConfig.VoteTime = 7
GameConfig.BidTime = 10
GameConfig.RevealRankingsTime = 5
GameConfig.ScrambleTime = 9
GameConfig.SmashDelay = 2.5
GameConfig.SettlementTime = 4
GameConfig.RouletteDuration = 3.2

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
        AssetId = "rbxassetid://1791823957588",
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
        AssetId = "rbxassetid://1791823992854",
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
        AssetId = "rbxassetid://1791824031208",
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
        AssetId = "rbxassetid://1791824078399",
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
        AssetId = "rbxassetid://1791824115905",
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
