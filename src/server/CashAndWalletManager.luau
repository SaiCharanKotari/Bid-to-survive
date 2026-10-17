--!strict
-- ServerScriptService/CashAndWalletManager.luau
-- Authoritative server economy manager for Bid-to-survive.
-- Separates Persistent Lobby Cash (Inventory Money) from In-Game Starting Wallet ($20).
-- Manages survival-time payout formula: Earned Cash = floor(Seconds Survived) * 20.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local CashAndWalletManager = {}

local STARTING_GAME_WALLET = 20 -- $20 given at the start of every game
local CASH_PER_SECOND_SURVIVED = 20 -- Survived Time (s) * 20 = Earned Cash

-- RemoteEvent for Payout Popup Animation in Lobby
local PayoutRemote: RemoteEvent = (ReplicatedStorage:FindFirstChild("CashPayoutEvent") :: any)
if not PayoutRemote then
	PayoutRemote = Instance.new("RemoteEvent")
	PayoutRemote.Name = "CashPayoutEvent"
	PayoutRemote.Parent = ReplicatedStorage
end

-- Persistent DataStore for Inventory/Overall Cash across sessions
local cashStore = nil
pcall(function()
	cashStore = DataStoreService:GetDataStore("BidToSurvive_OverallCash_v1")
end)

-- Active survival start timestamps per player for the current game
local gameStartTimestamps: { [Player]: number } = {}
local deathConnections: { [Player]: RBXScriptConnection } = {}

local function syncLeaderstats(player: Player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local cashStat = ls:FindFirstChild("Cash") :: IntValue?
	if not cashStat then
		cashStat = Instance.new("IntValue")
		cashStat.Name = "Cash"
		cashStat.Parent = ls
	end
	cashStat.Value = player:GetAttribute("OverallCash") or 0

	-- Ensure Wallet is removed from leaderstats (only Cash is visible on leaderboard)
	local oldWallet = ls:FindFirstChild("Wallet")
	if oldWallet then
		oldWallet:Destroy()
	end
end

local function setupPlayerEconomy(player: Player)
	local savedCash = 0
	if cashStore and player.UserId > 0 then
		local ok, result = pcall(function()
			return cashStore:GetAsync("Player_" .. tostring(player.UserId))
		end)
		if ok and typeof(result) == "number" then
			savedCash = result
		end
	end

	player:SetAttribute("OverallCash", savedCash)
	player:SetAttribute("Wallet", STARTING_GAME_WALLET)
	player:SetAttribute("Money", STARTING_GAME_WALLET)
	player:SetAttribute("IsInGame", false)
	syncLeaderstats(player)

	player.AttributeChanged:Connect(function(attr)
		if attr == "OverallCash" or attr == "Wallet" then
			syncLeaderstats(player)
		end
	end)
end

local function savePlayerOverallCash(player: Player)
	if not cashStore or player.UserId <= 0 then return end
	local overall = player:GetAttribute("OverallCash") or 0
	pcall(function()
		cashStore:SetAsync("Player_" .. tostring(player.UserId), overall)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayerEconomy, p)
end
Players.PlayerAdded:Connect(setupPlayerEconomy)

Players.PlayerRemoving:Connect(function(player)
	gameStartTimestamps[player] = nil
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end
	savePlayerOverallCash(player)
end)

-- ============================================================================
-- 1. CALL WHEN A NEW GAME STARTS (Right before Round 1 begins!)
-- Gives every participating player $20 in their Bottom-Right Wallet & starts timer
-- ============================================================================
function CashAndWalletManager.StartGameForPlayers(activePlayers: { Player }?)
	local participants = activePlayers or Players:GetPlayers()
	local now = os.clock()

	for _, player in ipairs(participants) do
		if not player:GetAttribute("IsAFK") then
			-- Set $20 Starting Wallet & switch UI from Lobby (Left) to In-Game (Bottom-Right)
			player:SetAttribute("Wallet", STARTING_GAME_WALLET)
			player:SetAttribute("Money", STARTING_GAME_WALLET) -- Compatibility alias
			player:SetAttribute("CurrentBid", 0)
			player:SetAttribute("IsInGame", true)

			gameStartTimestamps[player] = now

			-- Automatically settle survival cash if the player dies mid-game
			if deathConnections[player] then
				deathConnections[player]:Disconnect()
				deathConnections[player] = nil
			end

			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				deathConnections[player] = hum.Died:Once(function()
					CashAndWalletManager.SettlePlayerGameCash(player, "Eliminated")
				end)
			end

			print(string.format("[Economy] 💵 %s entered Game with Wallet = $%d", player.Name, STARTING_GAME_WALLET))
		end
	end
end

-- ============================================================================
-- 2. SPEND FROM THE $20 WALLET DURING BIDDING PHASE
-- ============================================================================
function CashAndWalletManager.TrySpendFromWallet(player: Player, bidAmount: number): (boolean, number)
	local currentWallet = player:GetAttribute("Wallet") or 0
	local cleanBid = math.clamp(math.floor(bidAmount * 100) / 100, 0, currentWallet)

	local newWallet = math.floor((currentWallet - cleanBid) * 100) / 100
	player:SetAttribute("Wallet", newWallet)
	player:SetAttribute("Money", newWallet)
	player:SetAttribute("CurrentBid", cleanBid)
	player:SetAttribute("BetTimestamp", os.clock())

	return true, cleanBid
end

-- ============================================================================
-- 3. SETTLE SURVIVAL PAYOUT WHEN PLAYER DIES OR GAME ENDS
-- Formula: Time Survived (seconds) * 20 = Earned Cash -> Added to Lobby OverallCash
-- ============================================================================
function CashAndWalletManager.SettlePlayerGameCash(player: Player, reason: string?): (number, number)
	local startTime = gameStartTimestamps[player]
	if not startTime then
		-- Already settled this game
		player:SetAttribute("IsInGame", false)
		return 0, 0
	end

	gameStartTimestamps[player] = nil
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end

	local secondsSurvived = math.max(0, math.floor(os.clock() - startTime))
	local earnedCash = secondsSurvived * CASH_PER_SECOND_SURVIVED
	local previousOverall = player:GetAttribute("OverallCash") or 0
	local newOverall = previousOverall + earnedCash

	-- Update Persistent Lifetime Cash & Reset Playable Session Wallet for Next Match
	player:SetAttribute("OverallCash", newOverall)
	player:SetAttribute("Wallet", STARTING_GAME_WALLET)
	player:SetAttribute("Money", STARTING_GAME_WALLET)
	player:SetAttribute("IsInGame", false)

	-- Notify Client UI to show the "+$Earned (Survived Xs * 20)" animation on the Left Side
	PayoutRemote:FireClient(player, earnedCash, secondsSurvived, newOverall, reason or "Game Over")

	task.spawn(savePlayerOverallCash, player)

	print(string.format(
		"[Economy] 🏆 %s (%s) Survived %ds * 20 = +$%d Earned! Total Lobby Cash = $%d",
		player.Name,
		reason or "Finished",
		secondsSurvived,
		earnedCash,
		newOverall
	))

	return earnedCash, secondsSurvived
end

-- ============================================================================
-- 4. CALL WHEN THE ENTIRE GAME ENDS (Settles all remaining survivors!)
-- ============================================================================
function CashAndWalletManager.EndGameAndRewardSurvivors()
	for _, player in ipairs(Players:GetPlayers()) do
		if gameStartTimestamps[player] then
			CashAndWalletManager.SettlePlayerGameCash(player, "Survived Game")
		else
			player:SetAttribute("IsInGame", false)
		end
	end
end

CashAndWalletManager.STARTING_GAME_WALLET = STARTING_GAME_WALLET
CashAndWalletManager.CASH_PER_SECOND_SURVIVED = CASH_PER_SECOND_SURVIVED

return CashAndWalletManager
