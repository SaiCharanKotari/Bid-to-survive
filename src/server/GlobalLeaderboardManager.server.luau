--!strict
-- GlobalLeaderboardManager.server.luau
-- Manages the in-world GLOBOL-LEADERBOARD in SpawnArea displaying the Top 100 Cash Holders

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local RESULTS_BG_ASSET = "rbxassetid://136247699248783"
local DATA_STORE_NAME = "BidToSurvive_GlobalCash_v2"

local orderedStore: OrderedDataStore? = nil
pcall(function()
	orderedStore = DataStoreService:GetOrderedDataStore(DATA_STORE_NAME)
end)

-- Cache for username lookups to stay well within API rate limits
local usernameCache: { [number]: string } = {}

local function getUsernameFromUserId(userId: number): string
	if userId <= 0 then
		return "Contender_" .. math.abs(userId)
	end
	if usernameCache[userId] then
		return usernameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and typeof(name) == "string" and #name > 0 then
		usernameCache[userId] = name
		return name
	end
	return "Player_" .. tostring(userId)
end

local function formatCash(amount: number): string
	local formatted = string.format("$%.2f", amount)
	-- Format commas in thousands: e.g. $12,500.00
	local intPart, decPart = string.match(formatted, "^%$(%d+)(%.%d%d)$")
	if intPart and decPart then
		local k: string
		while true do
			intPart, k = string.gsub(intPart, "^(-?%d+)(%d%d%d)", "%1,%2")
			if k == 0 then break end
		end
		return "$" .. intPart .. decPart
	end
	return formatted
end

-- Find the target part in SpawnArea
local function getLeaderboardPart(): BasePart?
	local sa = Workspace:FindFirstChild("BidToSurviveMap", true) 
		and Workspace.BidToSurviveMap:FindFirstChild("SpawnArea")
	local lbModel = sa and sa:FindFirstChild("Leaderboard")
	if lbModel then
		local part = lbModel:FindFirstChild("LeaderStats(NOT SCRIPTED)") :: BasePart?
			or lbModel:FindFirstChild("LeaderboardDisplayPart") :: BasePart?
			or lbModel:FindFirstChildWhichIsA("BasePart")
		if part then return part end
	end
	-- Fallback search anywhere in Workspace
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") and (desc.Name == "LeaderStats(NOT SCRIPTED)" or desc.Name == "LeaderboardDisplayPart") then
			return desc
		end
	end
	return nil
end

local function setupSurfaceGui(part: BasePart): (SurfaceGui, ScrollingFrame)
	local existing = part:FindFirstChild("GlobalLeaderboardGui") :: SurfaceGui?
	if existing then
		existing:Destroy()
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "GlobalLeaderboardGui"
	surfaceGui.Face = Enum.NormalId.Back -- Faces spawn area
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceGui.CanvasSize = Vector2.new(800, 1000) -- Clean 18x22 aspect ratio with high legibility
	surfaceGui.LightInfluence = 0
	surfaceGui.AlwaysOnTop = false
	surfaceGui.ToolPunchThroughDistance = 1000
	surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Outer Container with 3D Pop-Art Border
	local mainCard = Instance.new("Frame")
	mainCard.Name = "MainCard"
	mainCard.Size = UDim2.new(1, 0, 1, 0)
	mainCard.Position = UDim2.new(0, 0, 0, 0)
	mainCard.BackgroundColor3 = Color3.fromRGB(242, 118, 16)
	mainCard.BorderSizePixel = 0
	mainCard.Parent = surfaceGui

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(0, 0, 0)
	cardStroke.Thickness = 8
	cardStroke.Parent = mainCard

	-- Orange Texture Background
	local bgImg = Instance.new("ImageLabel")
	bgImg.Name = "BgImg"
	bgImg.Size = UDim2.new(1, 0, 1, 0)
	bgImg.BackgroundTransparency = 1
	bgImg.Image = RESULTS_BG_ASSET
	bgImg.ScaleType = Enum.ScaleType.Crop
	bgImg.ZIndex = 1
	bgImg.Parent = mainCard

	-- Header Panel
	local headerPanel = Instance.new("Frame")
	headerPanel.Name = "HeaderPanel"
	headerPanel.Size = UDim2.new(1, -28, 0, 116)
	headerPanel.Position = UDim2.new(0, 14, 0, 14)
	headerPanel.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
	headerPanel.BorderSizePixel = 0
	headerPanel.ZIndex = 2
	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 12)
	hpCorner.Parent = headerPanel
	local hpStroke = Instance.new("UIStroke")
	hpStroke.Color = Color3.fromRGB(255, 185, 35)
	hpStroke.Thickness = 3.5
	hpStroke.Parent = headerPanel
	headerPanel.Parent = mainCard

	local mainTitle = Instance.new("TextLabel")
	mainTitle.Size = UDim2.new(1, 0, 0, 52)
	mainTitle.Position = UDim2.new(0, 0, 0, 8)
	mainTitle.BackgroundTransparency = 1
	mainTitle.Text = "GLOBAL TOP 100 CASH"
	mainTitle.Font = Enum.Font.FredokaOne
	mainTitle.TextSize = 44
	mainTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	mainTitle.ZIndex = 3
	local mtStroke = Instance.new("UIStroke")
	mtStroke.Color = Color3.fromRGB(0, 0, 0)
	mtStroke.Thickness = 5
	mtStroke.Parent = mainTitle
	mainTitle.Parent = headerPanel

	local subTitle = Instance.new("TextLabel")
	subTitle.Size = UDim2.new(1, 0, 0, 28)
	subTitle.Position = UDim2.new(0, 0, 0, 62)
	subTitle.BackgroundTransparency = 1
	subTitle.Text = "★ ALL-TIME RICHEST SURVIVORS • SCROLL DOWN FOR ALL 100 ★"
	subTitle.Font = Enum.Font.GothamBlack
	subTitle.TextSize = 16
	subTitle.TextColor3 = Color3.fromRGB(255, 215, 80)
	subTitle.ZIndex = 3
	subTitle.Parent = headerPanel

	-- Columns Title Bar
	local colBar = Instance.new("Frame")
	colBar.Name = "ColBar"
	colBar.Size = UDim2.new(1, -28, 0, 42)
	colBar.Position = UDim2.new(0, 14, 0, 138)
	colBar.BackgroundColor3 = Color3.fromRGB(25, 20, 18)
	colBar.BorderSizePixel = 0
	colBar.ZIndex = 2
	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 8)
	cbCorner.Parent = colBar
	local cbStroke = Instance.new("UIStroke")
	cbStroke.Color = Color3.fromRGB(0, 0, 0)
	cbStroke.Thickness = 2
	cbStroke.Parent = colBar

	local function makeColHeader(text: string, size: UDim2, pos: UDim2, align: Enum.TextXAlignment)
		local lbl = Instance.new("TextLabel")
		lbl.Size = size
		lbl.Position = pos
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextSize = 17
		lbl.TextColor3 = Color3.fromRGB(255, 225, 140)
		lbl.TextXAlignment = align
		lbl.ZIndex = 3
		lbl.Parent = colBar
	end

	makeColHeader("RANK", UDim2.new(0, 95, 1, 0), UDim2.new(0, 10, 0, 0), Enum.TextXAlignment.Center)
	makeColHeader("AVATAR", UDim2.new(0, 80, 1, 0), UDim2.new(0, 110, 0, 0), Enum.TextXAlignment.Center)
	makeColHeader("USERNAME", UDim2.new(0, 310, 1, 0), UDim2.new(0, 195, 0, 0), Enum.TextXAlignment.Left)
	makeColHeader("TOTAL CASH", UDim2.new(0, 240, 1, 0), UDim2.new(1, -250, 0, 0), Enum.TextXAlignment.Right)
	colBar.Parent = mainCard

	-- Scrollable Container for Top 100 rows
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "LeaderboardScroll"
	scroll.Size = UDim2.new(1, -28, 1, -192)
	scroll.Position = UDim2.new(0, 14, 0, 186)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 12
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 180, 0)
	scroll.ScrollingEnabled = true
	scroll.CanvasSize = UDim2.new(0, 0, 0, 100 * 64)
	scroll.ZIndex = 2

	local sPadding = Instance.new("UIPadding")
	sPadding.PaddingLeft = UDim.new(0, 4)
	sPadding.PaddingRight = UDim.new(0, 16)
	sPadding.PaddingTop = UDim.new(0, 4)
	sPadding.PaddingBottom = UDim.new(0, 8)
	sPadding.Parent = scroll

	local uiList = Instance.new("UIListLayout")
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 6)
	uiList.Parent = scroll

	scroll.Parent = mainCard
	surfaceGui.Parent = part

	return surfaceGui, scroll
end

local function populateLeaderboardRows(scroll: ScrollingFrame, entries: { { Rank: number, UserId: number, Username: string, Cash: number } })
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for _, entry in ipairs(entries) do
		local rank = entry.Rank
		local row = Instance.new("Frame")
		row.Name = "Row_" .. rank
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = rank
		row.BorderSizePixel = 0
		row.ZIndex = 3

		-- Rank styling: Gold for #1, Silver for #2, Bronze for #3
		local rStroke = Instance.new("UIStroke")
		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 8)
		rCorner.Parent = row

		if rank == 1 then
			row.BackgroundColor3 = Color3.fromRGB(48, 38, 12)
			rStroke.Color = Color3.fromRGB(255, 215, 0)
			rStroke.Thickness = 3
		elseif rank == 2 then
			row.BackgroundColor3 = Color3.fromRGB(36, 40, 48)
			rStroke.Color = Color3.fromRGB(210, 225, 240)
			rStroke.Thickness = 2.5
		elseif rank == 3 then
			row.BackgroundColor3 = Color3.fromRGB(42, 28, 16)
			rStroke.Color = Color3.fromRGB(220, 140, 60)
			rStroke.Thickness = 2.5
		else
			row.BackgroundColor3 = (rank % 2 == 0) and Color3.fromRGB(22, 18, 16) or Color3.fromRGB(28, 22, 18)
			rStroke.Color = Color3.fromRGB(0, 0, 0)
			rStroke.Thickness = 1.5
		end
		rStroke.Parent = row

		-- 1. Rank Label
		local rankPill = Instance.new("TextLabel")
		rankPill.Size = UDim2.new(0, 85, 0, 38)
		rankPill.Position = UDim2.new(0, 10, 0.5, 0)
		rankPill.AnchorPoint = Vector2.new(0, 0.5)
		rankPill.BackgroundTransparency = 1
		rankPill.Text = "#" .. tostring(rank)
		rankPill.Font = Enum.Font.GothamBlack
		rankPill.TextSize = (rank <= 3) and 24 or 20
		if rank == 1 then
			rankPill.TextColor3 = Color3.fromRGB(255, 225, 60)
		elseif rank == 2 then
			rankPill.TextColor3 = Color3.fromRGB(225, 235, 255)
		elseif rank == 3 then
			rankPill.TextColor3 = Color3.fromRGB(255, 175, 90)
		else
			rankPill.TextColor3 = Color3.fromRGB(220, 225, 235)
		end
		rankPill.TextXAlignment = Enum.TextXAlignment.Center
		rankPill.ZIndex = 4
		rankPill.Parent = row

		-- 2. Avatar Thumbnail
		local avFrame = Instance.new("Frame")
		avFrame.Size = UDim2.new(0, 46, 0, 46)
		avFrame.Position = UDim2.new(0, 125, 0.5, 0)
		avFrame.AnchorPoint = Vector2.new(0, 0.5)
		avFrame.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		avFrame.BorderSizePixel = 0
		avFrame.ZIndex = 4
		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(0, 7)
		avCorner.Parent = avFrame
		local avStroke = Instance.new("UIStroke")
		avStroke.Color = Color3.fromRGB(0, 0, 0)
		avStroke.Thickness = 1.5
		avStroke.Parent = avFrame

		local avImg = Instance.new("ImageLabel")
		avImg.Size = UDim2.new(1, -2, 1, -2)
		avImg.Position = UDim2.new(0.5, 0, 0.5, 0)
		avImg.AnchorPoint = Vector2.new(0.5, 0.5)
		avImg.BackgroundTransparency = 1
		avImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId > 0 and entry.UserId or 1)
		avImg.ScaleType = Enum.ScaleType.Fit
		avImg.ZIndex = 5
		local aviCorner = Instance.new("UICorner")
		aviCorner.CornerRadius = UDim.new(0, 6)
		aviCorner.Parent = avImg
		avImg.Parent = avFrame
		avFrame.Parent = row

		-- 3. Username (Real Roblox Username as specified)
		local userLbl = Instance.new("TextLabel")
		userLbl.Size = UDim2.new(0, 310, 1, 0)
		userLbl.Position = UDim2.new(0, 185, 0, 0)
		userLbl.BackgroundTransparency = 1
		userLbl.Text = entry.Username
		userLbl.Font = Enum.Font.GothamBold
		userLbl.TextSize = 20
		userLbl.TextColor3 = (rank == 1) and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(255, 255, 255)
		userLbl.TextXAlignment = Enum.TextXAlignment.Left
		userLbl.TextTruncate = Enum.TextTruncate.AtEnd
		userLbl.ZIndex = 4
		userLbl.Parent = row

		-- 4. Total Cash
		local cashLbl = Instance.new("TextLabel")
		cashLbl.Size = UDim2.new(0, 240, 1, 0)
		cashLbl.Position = UDim2.new(1, -250, 0, 0)
		cashLbl.BackgroundTransparency = 1
		cashLbl.Text = formatCash(entry.Cash)
		cashLbl.Font = Enum.Font.GothamBlack
		cashLbl.TextSize = 21
		cashLbl.TextColor3 = Color3.fromRGB(255, 215, 60)
		cashLbl.TextXAlignment = Enum.TextXAlignment.Right
		cashLbl.ZIndex = 4
		cashLbl.Parent = row

		row.Parent = scroll
	end
end

-- Generate fallback / mock top 100 entries so the board is always populated
local function generateFallbackTop100(): { { Rank: number, UserId: number, Username: string, Cash: number } }
	local list = {}
	local famous = {
		{ id = 1, name = "Roblox", cash = 1000000 },
		{ id = 156, name = "Builderman", cash = 750000 },
		{ id = 261, name = "Shedletsky", cash = 520000 },
		{ id = 80425, name = "Stickmasterluke", cash = 410000 },
		{ id = 68061, name = "Telamon", cash = 330000 },
		{ id = 1686, name = "Clockwork", cash = 280000 },
	}

	-- Add active real players currently in game at top tiers
	local rankIdx = 1
	for _, p in ipairs(Players:GetPlayers()) do
		local pCash = p:GetAttribute("OverallCash") or 50000
		table.insert(list, {
			Rank = rankIdx,
			UserId = p.UserId,
			Username = p.Name, -- Real username
			Cash = math.max(120000, pCash),
		})
		rankIdx = rankIdx + 1
	end

	for _, f in ipairs(famous) do
		if rankIdx <= 100 then
			table.insert(list, {
				Rank = rankIdx,
				UserId = f.id,
				Username = f.name,
				Cash = f.cash,
			})
			rankIdx = rankIdx + 1
		end
	end

	local mockNames = {
		"ApexBidder", "ShadowStrike", "HammerLord", "RuinsKing", "RiskTaker",
		"VaultMaster", "GoldHunter", "CyberBidder", "Fortress", "BlazeSurv",
		"NeonBids", "SilentWinner", "TitanShield", "OmegaCash", "EchoHunter",
		"ViperCash", "LuckyBids", "GhostSurv", "KrakenBid", "StormCash"
	}

	while rankIdx <= 100 do
		local namePattern = mockNames[((rankIdx - 1) % #mockNames) + 1] .. tostring(math.floor(rankIdx * 7))
		local baseCash = math.max(100, math.floor(250000 * math.exp(-rankIdx / 25)))
		table.insert(list, {
			Rank = rankIdx,
			UserId = 1,
			Username = namePattern,
			Cash = baseCash,
		})
		rankIdx = rankIdx + 1
	end

	return list
end

local function refreshGlobalLeaderboard(scroll: ScrollingFrame)
	local entries = {}
	local success = false

	if orderedStore then
		local ok, pages = pcall(function()
			return orderedStore:GetSortedAsync(false, 100)
		end)
		if ok and pages then
			local rawData = pages:GetCurrentPage()
			if rawData and #rawData >= 5 then
				success = true
				for rank, item in ipairs(rawData) do
					local uId = tonumber(item.key) or 1
					local cashVal = item.value or 0
					local realUsername = getUsernameFromUserId(uId)
					table.insert(entries, {
						Rank = rank,
						UserId = uId,
						Username = realUsername,
						Cash = cashVal,
					})
				end
			end
		end
	end

	if not success or #entries < 20 then
		entries = generateFallbackTop100()
	end

	populateLeaderboardRows(scroll, entries)
end

-- Save player cash to OrderedDataStore on stat change or leave
local function registerPlayerSave(player: Player)
	local function saveCash()
		if not orderedStore or player.UserId <= 0 then return end
		local cash = player:GetAttribute("OverallCash")
		if typeof(cash) == "number" and cash > 0 then
			pcall(function()
				orderedStore:SetAsync(tostring(player.UserId), math.floor(cash))
			end)
		end
	end

	player:GetAttributeChangedSignal("OverallCash"):Connect(saveCash)
end

-- Initialize Leaderboard
task.spawn(function()
	task.wait(2)
	local part = getLeaderboardPart()
	if not part then
		warn("[GlobalLeaderboard] Leaderboard part not found in Workspace.")
		return
	end

	part.Name = "LeaderboardDisplayPart"
	part.CanCollide = false
	part.Anchored = true
	local _, scroll = setupSurfaceGui(part)

	refreshGlobalLeaderboard(scroll)

	-- Periodically refresh every 60 seconds
	while true do
		task.wait(60)
		pcall(function()
			refreshGlobalLeaderboard(scroll)
		end)
	end
end)

for _, p in ipairs(Players:GetPlayers()) do
	registerPlayerSave(p)
end
Players.PlayerAdded:Connect(registerPlayerSave)

print("[GlobalLeaderboardManager] Initialized Global Top 100 Cash Leaderboard successfully.")
