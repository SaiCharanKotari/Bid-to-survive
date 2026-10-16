--!strict
-- StarterPlayer/StarterPlayerScripts/MovementDiveAndHUDClient.client.luau
-- Authoritative client movement controller and unified status HUD for Bid-to-survive.
-- Features:
-- 1. Custom Walk (90697464892050) & Run (125757170550820)
-- 2. Spacebar Dive (137603926461078) with wall-checked forward raycasting and landed-bone projection (zero snap-back)
-- 3. Unified Stacked HUD (Money, HP, and Pure White Energy Bar)
-- 4. Guaranteed Game-2 HP re-bind lifecycle

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Network = ReplicatedStorage:FindFirstChild("Network")
local ResetHUDRemote: RemoteEvent? = (Network and Network:FindFirstChild("ResetHUDStateEvent") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("ResetHUDStateEvent") :: RemoteEvent?)

local StatsUpdated: RemoteEvent? = (Network and Network:FindFirstChild("StatsUpdated") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("StatsUpdated") :: RemoteEvent?)

local ClientLoadReadyEvent: RemoteEvent? = (Network and Network:FindFirstChild("ClientLoadReadyEvent") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("ClientLoadReadyEvent") :: RemoteEvent?)
if not ClientLoadReadyEvent then
	ClientLoadReadyEvent = Instance.new("RemoteEvent")
	ClientLoadReadyEvent.Name = "ClientLoadReadyEvent"
	ClientLoadReadyEvent.Parent = Network or ReplicatedStorage
end

-- ============================================================================
-- 1. ANIMATION IDs & MOVEMENT TUNING
-- ============================================================================
-- R6 Custom Author Animations (Authored by sai_charank)
local R6_WALK_ANIM_ID = "rbxassetid://90697464892050"
local R6_RUN_ANIM_ID  = "rbxassetid://125757170550820"
local R6_DIVE_ANIM_ID = "rbxassetid://137603926461078"

-- R15 Compatible Animations (Used if avatar spawns as R15)
local R15_WALK_ANIM_ID = "rbxassetid://913402848"
local R15_RUN_ANIM_ID  = "rbxassetid://913376220"
local R15_DIVE_ANIM_ID = "rbxassetid://507765000"

local currentWalkAnimId = R6_WALK_ANIM_ID
local currentRunAnimId  = R6_RUN_ANIM_ID
local currentDiveAnimId = R6_DIVE_ANIM_ID

local BASE_WALK_SPEED    = 14
local SPRINT_WALK_SPEED  = 21
local DIVE_FORWARD_SPEED = 32 -- Fallback speed if root motion is not available
local DIVE_DURATION      = 0.68 -- Fallback duration if track length hasn't loaded

-- ============================================================================
-- DIVE TRAJECTORY & LANDING DISTANCE CONFIGURATION
-- During the dive roll, the animation plays naturally without displacement tampering.
-- In the exact millisecond the animation completes, the character lands forward at:
-- Total Distance = (DIVE_ANIMATION_BASE_DISTANCE * DIVE_FORWARD_SCALE) + DIVE_LANDING_FORWARD_OFFSET
-- ============================================================================
-- 1. DIVE_ANIMATION_BASE_DISTANCE: Base forward distance in studs authored in the animation
--    • Default: 12.0 studs (the natural travel of animation 137603926461078)
local DIVE_ANIMATION_BASE_DISTANCE = 12.0

-- 2. DIVE_FORWARD_SCALE: Multiplier applied to the base animation distance
--    • 1.00 = 100% of authored animation distance (12.0 studs)
--    • Value Range: 0.50 (short 6 studs) to 1.50 (long 18 studs)
local DIVE_FORWARD_SCALE = 1.00

-- 3. DIVE_LANDING_FORWARD_OFFSET: Direct forward snap adjustment applied at the landing moment (in studs)
--    • Currently set to 6.0: Total landing distance = 12.0 + 6.0 = 18.0 studs!
--    • Value Range: -6.0 to +12.0 studs
local DIVE_LANDING_FORWARD_OFFSET = 6.0

-- 4. DIVE_LANDING_DELAY: Ground recovery time in seconds (0.0 = instant standing like normal)
local DIVE_LANDING_DELAY = 0.0

-- Energy Settings (White Bar)
local MAX_ENERGY        = 100
local SPRINT_DRAIN_RATE = 18 -- Energy drained per second while running
local DIVE_ENERGY_COST  = 20 -- Burst energy consumed on Spacebar Dive
local ENERGY_REGEN_RATE = 18 -- Energy regenerated per second when walking/idle

local currentEnergy = MAX_ENERGY
local isHoldingShift = false
local isSprinting = false
local isDiving = false
local exhaustedLockout = false
local lastMovementState = "None"

-- Active Character References
local activeChar: Model? = nil
local activeHum: Humanoid? = nil
local activeHRP: BasePart? = nil
local walkTrack: AnimationTrack? = nil
local runTrack: AnimationTrack? = nil
local diveTrack: AnimationTrack? = nil
local healthConn: RBXScriptConnection? = nil

-- ============================================================================
-- 2. UNIFIED HP, ENERGY & DYNAMIC LOBBY/GAME CURRENCY HUD BUILDER
-- ============================================================================
local PayoutRemote: RemoteEvent? = (ReplicatedStorage:FindFirstChild("CashPayoutEvent") :: any)

local function createOrUpdateStatusHUD()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("BidToSurviveStatusHUD")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BidToSurviveStatusHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- ========================================================================
	-- COMIC POP-ART STATUS STACK: Lifetime Cash, HP (Red), and EP (Cyan)
	-- Slightly reduced dimensions (width: 315px, height: 44px, text: 19px)
	-- ========================================================================
	local statusStack = Instance.new("Frame")
	statusStack.Name = "BottomLeftStatusStack"
	statusStack.AnchorPoint = Vector2.new(0, 1)
	statusStack.Position = UDim2.new(0, 24, 1, -24)
	statusStack.Size = UDim2.new(0, 315, 0, 134)
	statusStack.BackgroundTransparency = 1
	statusStack.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = statusStack

	local function createComicBar(order: number, name: string, tagText: string, fillColor: Color3, underlayColor: Color3)
		local bg = Instance.new("Frame")
		bg.Name = name .. "Frame"
		bg.LayoutOrder = order
		bg.Size = UDim2.new(1, 0, 0, 44)
		bg.BackgroundColor3 = underlayColor
		bg.BorderSizePixel = 0
		bg.Parent = statusStack

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = bg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = bg

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = fillColor
		fill.BorderSizePixel = 0
		fill.Parent = bg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill

		-- Left Label (e.g. "HP" or "EP")
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = "TagLabel"
		tagLabel.Size = UDim2.new(0, 44, 1, 0)
		tagLabel.Position = UDim2.new(0, 12, 0.5, 0)
		tagLabel.AnchorPoint = Vector2.new(0, 0.5)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.GothamBlack
		tagLabel.TextSize = 19
		tagLabel.TextXAlignment = Enum.TextXAlignment.Left
		tagLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		tagLabel.Text = tagText
		tagLabel.ZIndex = 3
		tagLabel.Parent = bg

		local tagStroke = Instance.new("UIStroke")
		tagStroke.Thickness = 2.5
		tagStroke.Color = Color3.fromRGB(0, 0, 0)
		tagStroke.Parent = tagLabel

		-- Right Numeric Value Label (e.g. "100")
		local valLabel = Instance.new("TextLabel")
		valLabel.Name = "ValueLabel"
		valLabel.Size = UDim2.new(0, 75, 1, 0)
		valLabel.Position = UDim2.new(1, -12, 0.5, 0)
		valLabel.AnchorPoint = Vector2.new(1, 0.5)
		valLabel.BackgroundTransparency = 1
		valLabel.Font = Enum.Font.GothamBlack
		valLabel.TextSize = 19
		valLabel.TextXAlignment = Enum.TextXAlignment.Right
		valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		valLabel.Text = "100"
		valLabel.ZIndex = 3
		valLabel.Parent = bg

		local valStroke = Instance.new("UIStroke")
		valStroke.Thickness = 2.5
		valStroke.Color = Color3.fromRGB(0, 0, 0)
		valStroke.Parent = valLabel

		return bg, fill, valLabel
	end

	-- Red HP Bar (#FF0000 with 3px black stroke, white HP & number)
	local hpBg, hpFill, hpLabel = createComicBar(2, "HP", "HP", Color3.fromRGB(255, 0, 0), Color3.fromRGB(60, 10, 15))
	-- Cyan EP Bar (#00FFF2 with 3px black stroke, white EP & number)
	local _, energyFill, energyLabel = createComicBar(3, "Energy", "EP", Color3.fromRGB(0, 255, 242), Color3.fromRGB(10, 45, 50))

	-- Comic Green Lifetime Cash Frame (+0 $) with "CASH" badge
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "LifetimeCashFrame"
	moneyFrame.LayoutOrder = 1
	moneyFrame.Size = UDim2.new(1, 0, 0, 30)
	moneyFrame.BackgroundTransparency = 1
	moneyFrame.Parent = statusStack

	local cashBadge = Instance.new("Frame")
	cashBadge.Name = "CashBadge"
	cashBadge.Size = UDim2.new(0, 52, 0, 22)
	cashBadge.Position = UDim2.new(0, 0, 0.5, 0)
	cashBadge.AnchorPoint = Vector2.new(0, 0.5)
	cashBadge.BackgroundColor3 = Color3.fromRGB(0, 204, 0)
	cashBadge.BorderSizePixel = 0
	cashBadge.Parent = moneyFrame

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = cashBadge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Thickness = 2
	badgeStroke.Color = Color3.fromRGB(0, 0, 0)
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Parent = cashBadge

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "BadgeText"
	badgeLabel.Size = UDim2.new(1, 0, 1, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Font = Enum.Font.GothamBlack
	badgeLabel.TextSize = 12
	badgeLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	badgeLabel.Text = "CASH"
	badgeLabel.Parent = cashBadge

	local lifetimeCashLabel = Instance.new("TextLabel")
	lifetimeCashLabel.Name = "LifetimeCashLabel"
	lifetimeCashLabel.Size = UDim2.new(1, -60, 1, 0)
	lifetimeCashLabel.Position = UDim2.new(0, 60, 0.5, 0)
	lifetimeCashLabel.AnchorPoint = Vector2.new(0, 0.5)
	lifetimeCashLabel.BackgroundTransparency = 1
	lifetimeCashLabel.Font = Enum.Font.GothamBlack
	lifetimeCashLabel.TextSize = 24
	lifetimeCashLabel.TextXAlignment = Enum.TextXAlignment.Left
	lifetimeCashLabel.TextColor3 = Color3.fromRGB(0, 230, 0) -- Lime green #00E600
	lifetimeCashLabel.Text = "+0 $"
	lifetimeCashLabel.ZIndex = 3
	lifetimeCashLabel.Parent = moneyFrame

	local moneyStroke = Instance.new("UIStroke")
	moneyStroke.Thickness = 3
	moneyStroke.Color = Color3.fromRGB(0, 0, 0)
	moneyStroke.Parent = lifetimeCashLabel

	local lifetimeCashScale = Instance.new("UIScale")
	lifetimeCashScale.Scale = 1.0
	lifetimeCashScale.Parent = lifetimeCashLabel

	-- Floating Payout Toast
	local payoutToast = Instance.new("TextLabel")
	payoutToast.Name = "PayoutToast"
	payoutToast.Size = UDim2.new(1, 40, 0, 24)
	payoutToast.Position = UDim2.new(0, 0, 0, -26)
	payoutToast.BackgroundTransparency = 1
	payoutToast.Font = Enum.Font.GothamBlack
	payoutToast.TextSize = 15
	payoutToast.TextXAlignment = Enum.TextXAlignment.Left
	payoutToast.TextColor3 = Color3.fromRGB(52, 211, 153)
	payoutToast.TextStrokeTransparency = 0.2
	payoutToast.TextTransparency = 1
	payoutToast.Text = ""
	payoutToast.Parent = moneyFrame

	-- ========================================================================
	-- BOTTOM-RIGHT WALLET CARD: "WALLET" badge + current playable session funds ($20.00)
	-- Mirrored against bottom-left status stack, non-overlapping, comic style
	-- ========================================================================
	local walletCard = Instance.new("Frame")
	walletCard.Name = "BottomRightWalletCard"
	walletCard.AnchorPoint = Vector2.new(1, 1)
	walletCard.Position = UDim2.new(1, -24, 1, -24)
	walletCard.Size = UDim2.new(0, 185, 0, 44)
	walletCard.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	walletCard.BorderSizePixel = 0
	walletCard.Parent = screenGui

	local walletCorner = Instance.new("UICorner")
	walletCorner.CornerRadius = UDim.new(0, 4)
	walletCorner.Parent = walletCard

	local walletStroke = Instance.new("UIStroke")
	walletStroke.Thickness = 3
	walletStroke.Color = Color3.fromRGB(0, 0, 0)
	walletStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	walletStroke.Parent = walletCard

	-- "WALLET" Badge on left of card
	local walletBadge = Instance.new("Frame")
	walletBadge.Name = "WalletBadge"
	walletBadge.Size = UDim2.new(0, 68, 0, 26)
	walletBadge.Position = UDim2.new(0, 9, 0.5, 0)
	walletBadge.AnchorPoint = Vector2.new(0, 0.5)
	walletBadge.BackgroundColor3 = Color3.fromRGB(255, 185, 0) -- Bold comic gold/yellow
	walletBadge.BorderSizePixel = 0
	walletBadge.Parent = walletCard

	local wbCorner = Instance.new("UICorner")
	wbCorner.CornerRadius = UDim.new(0, 4)
	wbCorner.Parent = walletBadge

	local wbStroke = Instance.new("UIStroke")
	wbStroke.Thickness = 2
	wbStroke.Color = Color3.fromRGB(0, 0, 0)
	wbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	wbStroke.Parent = walletBadge

	local wbText = Instance.new("TextLabel")
	wbText.Name = "BadgeText"
	wbText.Size = UDim2.new(1, 0, 1, 0)
	wbText.BackgroundTransparency = 1
	wbText.Font = Enum.Font.GothamBlack
	wbText.TextSize = 13
	wbText.TextColor3 = Color3.fromRGB(0, 0, 0)
	wbText.Text = "WALLET"
	wbText.Parent = walletBadge

	-- Numeric Wallet Value (e.g. "$20.00")
	local walletValLabel = Instance.new("TextLabel")
	walletValLabel.Name = "WalletValueLabel"
	walletValLabel.Size = UDim2.new(1, -88, 1, 0)
	walletValLabel.Position = UDim2.new(1, -12, 0.5, 0)
	walletValLabel.AnchorPoint = Vector2.new(1, 0.5)
	walletValLabel.BackgroundTransparency = 1
	walletValLabel.Font = Enum.Font.GothamBlack
	walletValLabel.TextSize = 19
	walletValLabel.TextXAlignment = Enum.TextXAlignment.Right
	walletValLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	walletValLabel.Text = "$20.00"
	walletValLabel.ZIndex = 3
	walletValLabel.Parent = walletCard

	local walletValStroke = Instance.new("UIStroke")
	walletValStroke.Thickness = 2.5
	walletValStroke.Color = Color3.fromRGB(0, 0, 0)
	walletValStroke.Parent = walletValLabel

	local walletScale = Instance.new("UIScale")
	walletScale.Scale = 1.0
	walletScale.Parent = walletCard

	return hpBg, hpFill, hpLabel, energyFill, energyLabel, statusStack, lifetimeCashLabel, payoutToast, walletCard, walletValLabel, walletScale
end

local hpBg, hpFill, hpLabel, energyFill, energyLabel, statusStack, lifetimeCashLabel, payoutToast, walletCard, walletValLabel, walletScale =
	createOrUpdateStatusHUD()

local function updateHPDisplay(health: number, maxHealth: number)
	local safeMax = (maxHealth > 0) and maxHealth or 100
	local ratio = math.clamp(health / safeMax, 0, 1)
	hpLabel.Text = string.format("%d", math.ceil(health))
	TweenService:Create(hpFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
end

local displayedOverallCash = 0
local countUpThread: thread? = nil
local lastWalletVal = 20

local function animateWalletScalePunch()
	walletScale.Scale = 1.10
	TweenService:Create(walletScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.0
	}):Play()
end

local function rollOverallCash(targetCash: number)
	if countUpThread then
		task.cancel(countUpThread)
		countUpThread = nil
	end

	local startVal = displayedOverallCash
	local diff = targetCash - startVal
	if math.abs(diff) <= 0.01 then
		displayedOverallCash = targetCash
		lifetimeCashLabel.Text = string.format("+%d $", math.floor(targetCash))
		return
	end

	countUpThread = task.spawn(function()
		local duration = 1.0
		local startTime = os.clock()
		while true do
			local elapsed = os.clock() - startTime
			local progress = math.clamp(elapsed / duration, 0, 1)
			local alpha = TweenService:GetValue(progress, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local cur = math.floor(startVal + (diff * alpha))
			displayedOverallCash = cur
			lifetimeCashLabel.Text = string.format("+%d $", cur)
			if progress >= 1 then break end
			task.wait(0.03)
		end
		displayedOverallCash = targetCash
		lifetimeCashLabel.Text = string.format("+%d $", math.floor(targetCash))
		countUpThread = nil
	end)
end

local function updateCurrencyUI()
	local isInGame = (player:GetAttribute("IsInGame") == true)
	local overallCash = player:GetAttribute("OverallCash") or 0
	local matchWallet = player:GetAttribute("Wallet") or 20

	-- Manage status stack sizing based on in-game state
	hpBg.Visible = isInGame
	statusStack.Size = isInGame and UDim2.new(0, 315, 0, 134) or UDim2.new(0, 315, 0, 82)

	-- 1. LEFT DISPLAY: Always authoritative Lifetime Cash
	if countUpThread == nil then
		displayedOverallCash = overallCash
		lifetimeCashLabel.Text = string.format("+%d $", math.floor(overallCash))
	end

	-- 2. RIGHT DISPLAY: Current session Wallet
	if matchWallet ~= lastWalletVal then
		if matchWallet < lastWalletVal then
			animateWalletScalePunch()
		end
		lastWalletVal = matchWallet
	end
	walletValLabel.Text = string.format("$%.2f", matchWallet)
end

-- Backward compatibility alias
local function updateMoneyDisplay()
	updateCurrencyUI()
end

updateCurrencyUI()

player.AttributeChanged:Connect(function(attr)
	if attr == "OverallCash" or attr == "Wallet" or attr == "IsInGame" or attr == "Money" then
		updateCurrencyUI()
	elseif attr == "HP" or attr == "Health" then
		local h = player:GetAttribute(attr)
		if typeof(h) == "number" and activeHum then
			updateHPDisplay(h, activeHum.MaxHealth)
		end
	end
end)

local function handlePayout(earnedCash: number, secondsSurvived: number, newOverall: number)
	updateCurrencyUI()
	rollOverallCash(newOverall)

	payoutToast.Text = string.format("+$%d (%ds Survived × $20)", earnedCash, secondsSurvived)
	payoutToast.Position = UDim2.new(0, 0, 0, -18)
	payoutToast.TextTransparency = 0

	TweenService:Create(payoutToast, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, -32)
	}):Play()

	task.delay(4.0, function()
		TweenService:Create(payoutToast, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()
	end)
end

if PayoutRemote then
	PayoutRemote.OnClientEvent:Connect(handlePayout)
else
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("CashPayoutEvent", 15) :: RemoteEvent?
		if remote then
			PayoutRemote = remote
			remote.OnClientEvent:Connect(handlePayout)
		end
	end)
end

if StatsUpdated then
	StatsUpdated.OnClientEvent:Connect(function(stats)
		if stats then
			updateCurrencyUI()
			if stats.Health ~= nil and activeHum then
				updateHPDisplay(stats.Health, activeHum.MaxHealth)
			end
		end
	end)
end

-- ============================================================================
-- 3. CUSTOM WALK & RUN ANIMATION CONTROLLER
-- ============================================================================
local function syncMovementTracks()
	if not activeHum or activeHum.Health <= 0 or isDiving then return end

	local isMoving = activeHum.MoveDirection.Magnitude > 0.05
	local wantSprint = isHoldingShift and isMoving and (not exhaustedLockout) and (currentEnergy > 0)

	isSprinting = wantSprint
	activeHum.WalkSpeed = wantSprint and SPRINT_WALK_SPEED or BASE_WALK_SPEED

	if camera then
		TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = wantSprint and 77 or 70
		}):Play()
	end

	local newState = "Idle"
	if isMoving then
		newState = wantSprint and "Sprinting" or "Walking"
	end

	if newState ~= lastMovementState then
		if newState == "Idle" then
			print(string.format("[Movement][State] 🛑 IDLE (WalkSpeed: %.1f, MoveMag: %.2f) -> Stopped movement tracks", activeHum.WalkSpeed, activeHum.MoveDirection.Magnitude))
		elseif newState == "Walking" then
			print(string.format("[Movement][State] 🚶 WALKING (WalkSpeed: %.1f, MoveMag: %.2f) -> Playing WalkTrack (ID: %s, Priority: %s)", activeHum.WalkSpeed, activeHum.MoveDirection.Magnitude, currentWalkAnimId, walkTrack and walkTrack.Priority.Name or "nil"))
		elseif newState == "Sprinting" then
			print(string.format("[Movement][State] ⚡ SPRINTING (WalkSpeed: %.1f, Energy: %d%%) -> Playing RunTrack (ID: %s, Priority: %s)", activeHum.WalkSpeed, math.floor(currentEnergy), currentRunAnimId, runTrack and runTrack.Priority.Name or "nil"))
		end
		lastMovementState = newState
	end

	if not isMoving then
		if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.15) end
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.15) end
	elseif wantSprint then
		if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.12) end
		if runTrack and not runTrack.IsPlaying then runTrack:Play(0.12, 1, 1.0) end
		-- Suppress default Animate movement tracks so custom sprint animation displays without interference
		if activeHum then
			for _, tr in ipairs(activeHum:GetPlayingAnimationTracks()) do
				if tr ~= runTrack and tr ~= diveTrack and tr ~= walkTrack and (tr.Priority == Enum.AnimationPriority.Movement or tr.Priority == Enum.AnimationPriority.Core) then
					tr:Stop(0.1)
				end
			end
		end
	else
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.12) end
		if walkTrack and not walkTrack.IsPlaying then walkTrack:Play(0.12, 1, 1.0) end
		-- Suppress default Animate movement tracks so custom walk animation displays without interference
		if activeHum then
			for _, tr in ipairs(activeHum:GetPlayingAnimationTracks()) do
				if tr ~= walkTrack and tr ~= diveTrack and tr ~= runTrack and (tr.Priority == Enum.AnimationPriority.Movement or tr.Priority == Enum.AnimationPriority.Core) then
					tr:Stop(0.1)
				end
			end
		end
	end
end

-- ============================================================================
-- 4. SPACEBAR DIVE WITH FORWARD LANDING CALCULATION (NO SNAP-BACK!)
-- ============================================================================
local function performRunningDive()
	if isDiving or not activeChar or not activeHum or not activeHRP then return end
	if activeHum.Health <= 0 or currentEnergy < 10 then return end

	-- Lock dive direction along the player's current movement / look direction
	local moveDir = activeHum.MoveDirection
	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	if flatDir.Magnitude < 0.1 then
		local look = activeHRP.CFrame.LookVector
		flatDir = Vector3.new(look.X, 0, look.Z)
	end
	flatDir = flatDir.Unit

	isDiving = true
	currentEnergy = math.max(0, currentEnergy - DIVE_ENERGY_COST)

	local startPos = activeHRP.Position
	print(string.format("[Movement][Dive] 🏊 Running dive initiated! StartPos: (%.2f, %.2f, %.2f), Dir: (%.2f, 0, %.2f), Energy: %d%%",
		startPos.X, startPos.Y, startPos.Z, flatDir.X, flatDir.Z, math.floor(currentEnergy)))

	-- Stop normal jump so pressing Space while running triggers Dive instead of jumping
	activeHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.1) end
	if runTrack and runTrack.IsPlaying then runTrack:Stop(0.1) end

	-- Face character cleanly in the dive direction
	activeHRP.CFrame = CFrame.lookAt(activeHRP.Position, activeHRP.Position + flatDir)

	-- Motion Design: Aerodynamic pure white motion trail during dive roll
	local trailAtt0 = Instance.new("Attachment")
	trailAtt0.Name = "DiveTrailAtt0"
	trailAtt0.Position = Vector3.new(0, 1.1, 0)
	trailAtt0.Parent = activeHRP

	local trailAtt1 = Instance.new("Attachment")
	trailAtt1.Name = "DiveTrailAtt1"
	trailAtt1.Position = Vector3.new(0, -1.1, 0)
	trailAtt1.Parent = activeHRP

	local diveTrail = Instance.new("Trail")
	diveTrail.Name = "DiveMotionTrail"
	diveTrail.Attachment0 = trailAtt0
	diveTrail.Attachment1 = trailAtt1
	diveTrail.FaceCamera = true
	diveTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	diveTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	diveTrail.Lifetime = 0.25
	diveTrail.LightEmission = 0.85
	diveTrail.LightInfluence = 0.1
	diveTrail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	diveTrail.Parent = activeHRP

	local torso = activeChar:FindFirstChild("Torso") or activeChar:FindFirstChild("UpperTorso")
	local head = activeChar:FindFirstChild("Head")

	-- 1. Disable Torso and Head CanCollide during roll so rotating body parts never snag on floor
	if torso and torso:IsA("BasePart") then torso.CanCollide = false end
	if head and head:IsA("BasePart") then head.CanCollide = false end

	-- Locate RootJoint (Torso.RootJoint for R6, LowerTorso.Root for R15)
	local rootJoint = nil
	if torso then
		rootJoint = torso:FindFirstChild("RootJoint") or torso:FindFirstChild("Root")
	end
	if not rootJoint and activeChar:FindFirstChild("LowerTorso") then
		local lt = activeChar.LowerTorso
		rootJoint = lt:FindFirstChild("Root") or lt:FindFirstChild("RootJoint")
	end

	local diveDuration = 0.68
	if diveTrack then
		diveTrack:Play(0.06, 1, 1.0)
		if diveTrack.Length and diveTrack.Length > 0.05 then
			diveDuration = diveTrack.Length
		end
		print(string.format("[Movement][Dive] 🎬 DiveTrack playing (Length: %.2fs, Priority: %s)", diveDuration, diveTrack.Priority.Name))
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { activeChar }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- STEP 1: Let the dive animation play completely without per-frame displacement tampering
	local diveStartTime = os.clock()
	while (os.clock() - diveStartTime) < diveDuration do
		task.wait(0.02)
		if not activeHRP or not activeHum or activeHum.Health <= 0 then break end
	end

	-- STEP 2: In the exact millisecond the animation completes, calculate and apply landing forward distance!
	-- Formula: (DIVE_ANIMATION_BASE_DISTANCE * DIVE_FORWARD_SCALE) + DIVE_LANDING_FORWARD_OFFSET
	local totalLandingDistance = (DIVE_ANIMATION_BASE_DISTANCE * DIVE_FORWARD_SCALE) + DIVE_LANDING_FORWARD_OFFSET

	-- Wall collision safety check: prevent passing through walls/obstacles
	local wallRay = Workspace:Raycast(startPos, flatDir * (totalLandingDistance + 1.2), rayParams)
	if wallRay then
		totalLandingDistance = math.max(0, wallRay.Distance - 1.2)
	end

	local targetPos = startPos + (flatDir * totalLandingDistance)

	-- Floor snap raycast: ensure character lands solidly on the ground
	local floorRay = Workspace:Raycast(targetPos + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), rayParams)
	local hipHeight = (activeHum.RigType == Enum.HumanoidRigType.R6) and 2.8 or (activeHum.HipHeight + activeHRP.Size.Y * 0.5)
	local targetY = floorRay and (floorRay.Position.Y + hipHeight) or targetPos.Y

	local landingPos = Vector3.new(targetPos.X, targetY, targetPos.Z)
	activeHRP.CFrame = CFrame.lookAt(landingPos, landingPos + flatDir)
	activeHRP.AssemblyLinearVelocity = Vector3.zero

	-- Instantly stop dive animation with 0s fade to eliminate reverse recovery blending
	if diveTrack and diveTrack.IsPlaying then
		diveTrack:Stop(0)
	end

	-- Instantly reset all character joints to clean upright standing posture
	if activeChar then
		for _, motor in ipairs(activeChar:GetDescendants()) do
			if motor:IsA("Motor6D") then
				motor.Transform = CFrame.identity
			end
		end
	end

	print(string.format("[Movement][Dive] 🛬 Animation ended! Placed in results area: (%.2f, %.2f, %.2f), TotalTravel: %.2f studs (Base: %.1f, Scale: %.2fx, Offset: %.1f)",
		landingPos.X, landingPos.Y, landingPos.Z, totalLandingDistance, DIVE_ANIMATION_BASE_DISTANCE, DIVE_FORWARD_SCALE, DIVE_LANDING_FORWARD_OFFSET))

	-- Restore collision
	if torso and torso:IsA("BasePart") then torso.CanCollide = true end
	if head and head:IsA("BasePart") then head.CanCollide = true end

	-- Clean up motion trail
	diveTrail.Enabled = false
	Debris:AddItem(diveTrail, 0.3)
	Debris:AddItem(trailAtt0, 0.3)
	Debris:AddItem(trailAtt1, 0.3)

	-- Ground recovery delay: only wait if user configured a delay > 0
	if DIVE_LANDING_DELAY > 0 then
		if activeHum and activeHum.Health > 0 then
			activeHum.WalkSpeed = 6
		end
		task.wait(DIVE_LANDING_DELAY)
	end

	local finalPos = activeHRP and activeHRP.Position or Vector3.zero
	local landingToFinalDiff = (finalPos - landingPos).Magnitude
	print(string.format("[Movement][Dive] 🧍 Instant standing complete! FinalPos: (%.2f, %.2f, %.2f), Landing-to-Final Diff: %.4f studs (Clean Normal Standing!)",
		finalPos.X, finalPos.Y, finalPos.Z, landingToFinalDiff))

	activeHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	isDiving = false
	syncMovementTracks()
end

-- ============================================================================
-- 5. CHARACTER SETUP & GAME-2 HP RESET FIX
-- ============================================================================
local function bindCameraToHumanoid(hum: Humanoid)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = hum
	print(string.format("[Movement][Camera] 🎥 CameraSubject bound to %s (Parent: %s)", hum.Name, hum.Parent and hum.Parent.Name or "nil"))
end

local function setupCharacter(character: Model)
	activeChar = character
	activeHum = character:WaitForChild("Humanoid") :: Humanoid
	activeHRP = character:WaitForChild("HumanoidRootPart") :: BasePart

	isDiving = false
	currentEnergy = MAX_ENERGY
	lastMovementState = "None"

	-- 0. CAMERA TRACKING: Guarantee camera follows the active character seamlessly
	bindCameraToHumanoid(activeHum)

	task.spawn(function()
		for _ = 1, 15 do
			local cam = Workspace.CurrentCamera
			if cam and activeHum and activeHum.Parent then
				if cam.CameraSubject ~= activeHum or cam.CameraType ~= Enum.CameraType.Custom then
					cam.CameraType = Enum.CameraType.Custom
					cam.CameraSubject = activeHum
				end
			end
			task.wait(0.08)
		end
	end)

	local rigType = activeHum.RigType
	print(string.format("[Movement][Init] 👤 Setting up character: %s | RigType: %s", character.Name, rigType.Name))

	if rigType == Enum.HumanoidRigType.R6 then
		currentWalkAnimId = R6_WALK_ANIM_ID
		currentRunAnimId  = R6_RUN_ANIM_ID
		currentDiveAnimId = R6_DIVE_ANIM_ID
		print(string.format("[Movement][Init] ✅ R6 Avatar detected! Loading custom animations:\n  • Walk: %s\n  • Run: %s\n  • Dive: %s", currentWalkAnimId, currentRunAnimId, currentDiveAnimId))
	else
		currentWalkAnimId = R15_WALK_ANIM_ID
		currentRunAnimId  = R15_RUN_ANIM_ID
		currentDiveAnimId = R15_DIVE_ANIM_ID
		warn(string.format("[Movement][Init] ⚠️ R15 Avatar detected! The custom animations (90697464892050, 125757170550820, 137603926461078) were authored for R6 (Torso, Left/Right Arm, Left/Right Leg) and cannot articulate R15 bones. Loaded R15-compatible animations:\n  • Walk: %s\n  • Run: %s\n  • Dive: %s\n  💡 TIP: To use your custom animations, keep StarterPlayer.StarterCharacter as R6 or set Game Settings -> Avatar -> R6.", currentWalkAnimId, currentRunAnimId, currentDiveAnimId))
	end

	-- 1. Disable default Roblox 'Animate' script's walk/run interference on R6
	local animateScript = character:WaitForChild("Animate", 3)
	if animateScript and animateScript:IsA("LocalScript") then
		for _, folderName in ipairs({ "walk", "run" }) do
			local folder = animateScript:FindFirstChild(folderName)
			if folder then
				for _, anim in ipairs(folder:GetChildren()) do
					if anim:IsA("Animation") then
						anim.AnimationId = (folderName == "walk") and currentWalkAnimId or currentRunAnimId
					end
				end
			end
		end
	end

	local animator = activeHum:WaitForChild("Animator", 5) :: Animator
	if animator then
		-- 2. Stop any lingering default movement tracks on the Animator
		for _, playingTrack in ipairs(animator:GetPlayingAnimationTracks()) do
			if playingTrack.Priority == Enum.AnimationPriority.Movement or playingTrack.Priority == Enum.AnimationPriority.Core then
				playingTrack:Stop(0)
			end
		end

		-- 3. Create & Preload Custom Animations so Length is NEVER 0.00s
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = currentWalkAnimId

		local runAnim = Instance.new("Animation")
		runAnim.AnimationId = currentRunAnimId

		local diveAnim = Instance.new("Animation")
		diveAnim.AnimationId = currentDiveAnimId

		pcall(function()
			ContentProvider:PreloadAsync({ walkAnim, runAnim, diveAnim })
		end)

		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Movement
		walkTrack.Looped = true

		runTrack = animator:LoadAnimation(runAnim)
		runTrack.Priority = Enum.AnimationPriority.Action
		runTrack.Looped = true

		diveTrack = animator:LoadAnimation(diveAnim)
		diveTrack.Priority = Enum.AnimationPriority.Action4
		diveTrack.Looped = false

		-- Yield in loop until all 3 track lengths are strictly > 0s (up to 5s timeout)
		local loadStart = os.clock()
		while (walkTrack.Length <= 0 or runTrack.Length <= 0 or diveTrack.Length <= 0) and (os.clock() - loadStart < 5.0) do
			task.wait(0.05)
		end

		print(string.format("[Movement][Init] 🎬 Tracks loaded on Animator:\n  • WalkTrack: Length=%.2fs, Priority=%s, Looped=%s\n  • RunTrack:  Length=%.2fs, Priority=%s, Looped=%s\n  • DiveTrack: Length=%.2fs, Priority=%s, Looped=%s",
			walkTrack and walkTrack.Length or 0, walkTrack and walkTrack.Priority.Name or "nil", tostring(walkTrack and walkTrack.Looped),
			runTrack and runTrack.Length or 0, runTrack and runTrack.Priority.Name or "nil", tostring(runTrack and runTrack.Looped),
			diveTrack and diveTrack.Length or 0, diveTrack and diveTrack.Priority.Name or "nil", tostring(diveTrack and diveTrack.Looped)))

		-- Step 2 Completion Check: Verify Workspace Map and Ruins Door are ready on client
		task.spawn(function()
			local map = Workspace:WaitForChild("BidToSurviveMap", 8)
			if map then
				map:WaitForChild("Ruins door", 8)
				map:WaitForChild("GameplayArea", 8)
			end

			print(string.format("[BOOT HIERARCHY] 🎬 Step 2: Animations verified (Walk: %.2fs, Run: %.2fs, Dive: %.2fs) & map assets ready. Firing ClientLoadReadyEvent.",
				walkTrack.Length, runTrack.Length, diveTrack.Length))

			if ClientLoadReadyEvent then
				ClientLoadReadyEvent:FireServer()
			end
		end)
	end

	-- Re-bind HP listener on EVERY new character/game so Game 2 never stays stuck at 0 HP!
	if healthConn then healthConn:Disconnect() end
	updateHPDisplay(activeHum.Health, activeHum.MaxHealth)
	updateMoneyDisplay()

	healthConn = activeHum.HealthChanged:Connect(function(newHealth)
		updateHPDisplay(newHealth, activeHum.MaxHealth)
	end)

	activeHum.Running:Connect(function(speed)
		syncMovementTracks()
	end)
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

-- Monitor camera to prevent camera detachment when characters are converted or respawned
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
	if activeHum and activeHum.Parent then
		bindCameraToHumanoid(activeHum)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		local currentCam = Workspace.CurrentCamera
		if currentCam and activeHum and activeHum.Parent then
			if currentCam.CameraSubject ~= activeHum then
				bindCameraToHumanoid(activeHum)
			end
		end
	end
end)

local function handleHUDReset()
	currentEnergy = MAX_ENERGY
	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			updateHPDisplay(hum.Health, hum.MaxHealth)
		end
	end
	updateMoneyDisplay()
end

if ResetHUDRemote then
	ResetHUDRemote.OnClientEvent:Connect(handleHUDReset)
else
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("ResetHUDStateEvent", 15) :: RemoteEvent?
		if remote then
			remote.OnClientEvent:Connect(handleHUDReset)
		end
	end)
end

-- ============================================================================
-- 6. INPUT & WHITE ENERGY BAR LOOP
-- ============================================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isHoldingShift = true
		print(string.format("[Movement][Input] ⌨️ Shift pressed (isHoldingShift=true, Energy=%d%%, ExhaustedLockout=%s)", math.floor(currentEnergy), tostring(exhaustedLockout)))
		syncMovementTracks()
	elseif input.KeyCode == Enum.KeyCode.Space then
		-- If running (holding Shift while moving), Space triggers DIVE instead of normal jump!
		if isSprinting and not isDiving and activeHum and activeHum.MoveDirection.Magnitude > 0.1 then
			print("[Movement][Input] ⌨️ Spacebar pressed while sprinting -> Triggering running dive!")
			performRunningDive()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isHoldingShift = false
		print("[Movement][Input] ⌨️ Shift released (isHoldingShift=false)")
		syncMovementTracks()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not activeHum or activeHum.Health <= 0 then return end

	syncMovementTracks()

	-- Drain White Energy while running; regenerate when walking or standing still
	if isSprinting and not isDiving then
		currentEnergy = math.max(0, currentEnergy - (SPRINT_DRAIN_RATE * dt))
		if currentEnergy <= 0 and not exhaustedLockout then
			exhaustedLockout = true
			print("[Movement][Energy] ⚠️ ENERGY EXHAUSTED (0%) -> Sprint lockout engaged until energy reaches 20%")
			syncMovementTracks()
		end
	elseif not isDiving then
		currentEnergy = math.min(MAX_ENERGY, currentEnergy + (ENERGY_REGEN_RATE * dt))
		if exhaustedLockout and currentEnergy >= 20 then
			exhaustedLockout = false
			print(string.format("[Movement][Energy] 🔋 ENERGY RECOVERED (%d%%) -> Sprint lockout cleared", math.floor(currentEnergy)))
		end
	end

	-- Update Comic EP Bar UI
	local energyRatio = math.clamp(currentEnergy / MAX_ENERGY, 0, 1)
	energyFill.Size = UDim2.new(energyRatio, 0, 1, 0)
	energyLabel.Text = string.format("%d", math.floor(currentEnergy))
end)

print("[MovementDiveAndHUDClient] Initialized: Walk (90697464892050), Run (125757170550820), Dive (137603926461078) & Unified Stacked HUD.")
