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

GameConfig.HammerRarities = {
    Common = {
        Name = "Common",
        Chance = 0.35,
        DamagePercent = 30,
        Color = Color3.fromRGB(180, 180, 180),
        Neon = false,
        SoundPitch = 1.0,
        CameraShake = 0.5
    },
    Uncommon = {
        Name = "Uncommon",
        Chance = 0.30,
        DamagePercent = 40,
        Color = Color3.fromRGB(80, 220, 100),
        Neon = false,
        SoundPitch = 0.95,
        CameraShake = 0.8
    },
    Rare = {
        Name = "Rare",
        Chance = 0.20,
        DamagePercent = 50,
        Color = Color3.fromRGB(70, 160, 255),
        Neon = true,
        SoundPitch = 0.9,
        CameraShake = 1.2
    },
    Legendary = {
        Name = "Legendary",
        Chance = 0.10,
        DamagePercent = 60,
        Color = Color3.fromRGB(255, 170, 0),
        Neon = true,
        SoundPitch = 0.85,
        CameraShake = 1.6
    },
    Mythical = {
        Name = "Mythical",
        Chance = 0.05,
        DamagePercent = 70,
        Color = Color3.fromRGB(255, 0, 80),
        Neon = true,
        SoundPitch = 0.75,
        CameraShake = 2.2
    }
}

function GameConfig.RollRarity()
    local roll = math.random()
    local cumulative = 0
    local order = {"Common", "Uncommon", "Rare", "Legendary", "Mythical"}
    for _, name in ipairs(order) do
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
