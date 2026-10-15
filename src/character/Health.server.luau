--!strict
-- StarterCharacterScripts/Health.server.luau
-- Disables Roblox's default passive health regeneration.
-- Health in "Bid to Survive" only resets to 100 at the start of a brand-new match (CurrentRound == 0).
-- Damage sustained in Round 1 carries over into subsequent rounds without passive healing.

-- Do nothing: deliberately omit any Humanoid.Health regeneration loop.
