--!strict
-- ReplicatedStorage/HammerRarityRoller.luau
-- Authoritative module for 5-hammer rarities, round probability weights,
-- and rarity-weighted anti-repeat spinner reel generation.

local HammerRarityRoller = {}

export type HammerRarity = "Common" | "Uncommon" | "Rare" | "Legendary" | "Mythical"

export type HammerData = {
	Rarity: HammerRarity,
	DamagePercent: number,
}

-- Exact 5 Hammers (30% to 70% DMG)
local HAMMERS: { [HammerRarity]: HammerData } = {
	Common    = { Rarity = "Common",    DamagePercent = 30 },
	Uncommon  = { Rarity = "Uncommon",  DamagePercent = 40 },
	Rare      = { Rarity = "Rare",      DamagePercent = 50 },
	Legendary = { Rarity = "Legendary", DamagePercent = 60 },
	Mythical  = { Rarity = "Mythical",  DamagePercent = 70 },
}
HammerRarityRoller.HAMMERS = HAMMERS

local RARITY_ORDER: { HammerRarity } = { "Common", "Uncommon", "Rare", "Legendary", "Mythical" }

-- Round-by-Round Probability Weights (Sums to 100 every round)
-- Rounds 1-2: Common + Uncommon = 70%
-- Round 3:    Common + Uncommon = 50%
-- Round 4:    Common + Uncommon = 40%
-- Round 5:    Common + Uncommon = 25%
-- Round 6+:   Common + Uncommon = 10%
local ROUND_RARITY_WEIGHTS: { [number]: { [HammerRarity]: number } } = {
	[1] = { Common = 40, Uncommon = 30, Rare = 18, Legendary = 9,  Mythical = 3  },
	[2] = { Common = 32, Uncommon = 38, Rare = 16, Legendary = 10, Mythical = 4  },
	[3] = { Common = 25, Uncommon = 25, Rare = 25, Legendary = 16, Mythical = 9  },
	[4] = { Common = 18, Uncommon = 22, Rare = 25, Legendary = 21, Mythical = 14 },
	[5] = { Common = 10, Uncommon = 15, Rare = 25, Legendary = 28, Mythical = 22 },
	[6] = { Common = 4,  Uncommon = 6,  Rare = 20, Legendary = 35, Mythical = 35 },
}

local rng = Random.new()

-- 1. Roll the Winning Hammer for the Round based on Rarity Weights
function HammerRarityRoller.RollWinningHammer(roundNumber: number): HammerData
	local clampedRound = math.clamp(roundNumber or 1, 1, 6)
	local weights = ROUND_RARITY_WEIGHTS[clampedRound]

	local totalWeight = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		totalWeight += weights[rarity]
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cumulative = 0

	for _, rarity in ipairs(RARITY_ORDER) do
		cumulative += weights[rarity]
		if roll <= cumulative then
			return HammerRarityRoller.HAMMERS[rarity]
		end
	end

	return HammerRarityRoller.HAMMERS.Common
end

-- 2. Generate a Rarity-Weighted Random Image Sequence for the Existing Spinner UI
-- (Replaces predictable Common -> Uncommon -> Rare -> Legendary -> Mythical sequence)
function HammerRarityRoller.BuildRandomSpinnerStrip(roundNumber: number, totalSlots: number, winningSlotIndex: number, winningRarity: HammerRarity): { HammerRarity }
	local clampedRound = math.clamp(roundNumber or 1, 1, 6)
	local weights = ROUND_RARITY_WEIGHTS[clampedRound]

	local strip: { HammerRarity } = table.create(totalSlots)
	local previousRarity: HammerRarity? = nil

	for i = 1, totalSlots do
		if i == winningSlotIndex then
			strip[i] = winningRarity
			previousRarity = winningRarity
		else
			-- Roll a random hammer weighted by rarity, ensuring no two adjacent images are the same!
			local candidatePool = {}
			local poolWeight = 0

			for _, rarity in ipairs(RARITY_ORDER) do
				local isAdjacentToWinner = (i == winningSlotIndex - 1 or i == winningSlotIndex + 1) and (rarity == winningRarity)
				if rarity ~= previousRarity and not isAdjacentToWinner then
					-- Keep rarity weighting + minimum visual weight (8) so high-tier hammers still flash by during early spins
					local visualWeight = math.max(weights[rarity], 8)
					poolWeight += visualWeight
					table.insert(candidatePool, { Rarity = rarity, Weight = visualWeight })
				end
			end

			local pickRoll = rng:NextNumber(0, poolWeight)
			local accum = 0
			local chosen: HammerRarity = "Common"

			for _, entry in ipairs(candidatePool) do
				accum += entry.Weight
				if pickRoll <= accum then
					chosen = entry.Rarity
					break
				end
			end

			strip[i] = chosen
			previousRarity = chosen
		end
	end

	return strip
end

return HammerRarityRoller
