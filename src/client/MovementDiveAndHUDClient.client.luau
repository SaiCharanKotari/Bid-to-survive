--!strict
-- StarterPlayer/StarterPlayerScripts/MovementDiveAndHUDClient.client.luau
-- Authoritative client movement controller, High-Speed Jetpack Burst, and unified status HUD for Bid-to-survive.
-- Features:
-- 1. Custom Walk (90697464892050) & Run (125757170550820)
-- 2. Spacebar Jetpack Burst (15 studs, blazing speed acceleration, pure white backside & thruster speed trails, upright posture)
-- 3. Unified Stacked HUD (Money, HP, and Pure White Energy Bar)
-- 4. Guaranteed Game-2 HP re-bind lifecycle

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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

local JetpackBurstEvent: RemoteEvent? = (Network and Network:FindFirstChild("JetpackBurstEvent") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("JetpackBurstEvent") :: RemoteEvent?)

local JetpackBurstReplicatedEvent: RemoteEvent? = (Network and Network:FindFirstChild("JetpackBurstReplicatedEvent") :: RemoteEvent?)
	or (ReplicatedStorage:FindFirstChild("JetpackBurstReplicatedEvent") :: RemoteEvent?)

-- ============================================================================
-- 1. ANIMATION IDs & MOVEMENT TUNING
-- ============================================================================
-- R6 Custom Author Animations (Authored by sai_charank)
local R6_WALK_ANIM_ID = "rbxassetid://90697464892050"
local R6_RUN_ANIM_ID  = "rbxassetid://125757170550820"

-- R15 Compatible Animations (Used if avatar spawns as R15)
local R15_WALK_ANIM_ID = "rbxassetid://913402848"
local R15_RUN_ANIM_ID  = "rbxassetid://913376220"

local currentWalkAnimId = R6_WALK_ANIM_ID
local currentRunAnimId  = R6_RUN_ANIM_ID

local BASE_WALK_SPEED           = 14
local SPRINT_WALK_SPEED         = 21

-- High-Speed Jetpack Burst Tuning:
-- Explodes speed forward to 85 studs/sec until exactly 15 studs traveled
local JETPACK_BURST_DISTANCE    = 15.0
local JETPACK_BURST_SPEED       = 85.0 -- High-speed acceleration feeling (4x sprint speed!)
local JETPACK_COOLDOWN          = 1.25
local JETPACK_ENERGY_COST       = 20

-- Author-provided Jetpack Sound (assets/jetpack-sound.mp3)
local JETPACK_BURST_SOUND_ID    = "rbxasset://sounds/jetpack-sound.mp3"
local JETPACK_BURST_VOLUME      = 0.85

-- Energy Settings (White / Cyan EP Bar)
local MAX_ENERGY        = 100
local SPRINT_DRAIN_RATE = 18 -- Energy drained per second while running
local ENERGY_REGEN_RATE = 18 -- Energy regenerated per second when walking/idle

local currentEnergy     = MAX_ENERGY
local isHoldingShift    = false
local isSprinting       = false
local isBursting        = false
local lastBurstTime     = 0
local exhaustedLockout  = false
local lastMovementState = "None"

-- Active Character References
local activeChar: Model?        = nil
local activeHum: Humanoid?      = nil
local activeHRP: BasePart?       = nil
local walkTrack: AnimationTrack? = nil
local runTrack: AnimationTrack?  = nil
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

	-- COMIC POP-ART STATUS STACK: Lifetime Cash, HP (Red), and EP (Cyan) - Sleek & Compact
	local statusStack = Instance.new("Frame")
	statusStack.Name = "BottomLeftStatusStack"
	statusStack.AnchorPoint = Vector2.new(0, 1)
	statusStack.Position = UDim2.new(0, 24, 1, -24)
	statusStack.Size = UDim2.new(0, 240, 0, 106)
	statusStack.BackgroundTransparency = 1
	statusStack.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = statusStack

	local function createComicBar(order: number, name: string, tagText: string, fillColor: Color3, underlayColor: Color3)
		local bg = Instance.new("Frame")
		bg.Name = name .. "Frame"
		bg.LayoutOrder = order
		bg.Size = UDim2.new(1, 0, 0, 34)
		bg.BackgroundColor3 = underlayColor
		bg.BorderSizePixel = 0
		bg.Parent = statusStack

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = bg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 2
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
		tagLabel.Size = UDim2.new(0, 36, 1, 0)
		tagLabel.Position = UDim2.new(0, 10, 0.5, 0)
		tagLabel.AnchorPoint = Vector2.new(0, 0.5)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.GothamBlack
		tagLabel.TextSize = 14
		tagLabel.TextXAlignment = Enum.TextXAlignment.Left
		tagLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		tagLabel.Text = tagText
		tagLabel.ZIndex = 3
		tagLabel.Parent = bg

		local tagStroke = Instance.new("UIStroke")
		tagStroke.Thickness = 2
		tagStroke.Color = Color3.fromRGB(0, 0, 0)
		tagStroke.Parent = tagLabel

		-- Right Numeric Value Label (e.g. "100")
		local valLabel = Instance.new("TextLabel")
		valLabel.Name = "ValueLabel"
		valLabel.Size = UDim2.new(0, 56, 1, 0)
		valLabel.Position = UDim2.new(1, -10, 0.5, 0)
		valLabel.AnchorPoint = Vector2.new(1, 0.5)
		valLabel.BackgroundTransparency = 1
		valLabel.Font = Enum.Font.GothamBlack
		valLabel.TextSize = 14
		valLabel.TextXAlignment = Enum.TextXAlignment.Right
		valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		valLabel.Text = "100"
		valLabel.ZIndex = 3
		valLabel.Parent = bg

		local valStroke = Instance.new("UIStroke")
		valStroke.Thickness = 2
		valStroke.Color = Color3.fromRGB(0, 0, 0)
		valStroke.Parent = valLabel

		return bg, fill, valLabel
	end

	-- Red HP Bar (#FF0000 with 2px black stroke, white HP & number)
	local hpBg, hpFill, hpLabel = createComicBar(2, "HP", "HP", Color3.fromRGB(255, 0, 0), Color3.fromRGB(60, 10, 15))
	-- Cyan EP Bar (#00FFF2 with 2px black stroke, white EP & number)
	local _, energyFill, energyLabel = createComicBar(3, "Energy", "EP", Color3.fromRGB(0, 255, 242), Color3.fromRGB(10, 45, 50))

	-- Comic Green Lifetime Cash Frame (+0 $) with "CASH" badge
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "LifetimeCashFrame"
	moneyFrame.LayoutOrder = 1
	moneyFrame.Size = UDim2.new(1, 0, 0, 24)
	moneyFrame.BackgroundTransparency = 1
	moneyFrame.Parent = statusStack

	local cashBadge = Instance.new("Frame")
	cashBadge.Name = "CashBadge"
	cashBadge.Size = UDim2.new(0, 44, 0, 18)
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
	badgeLabel.TextSize = 10
	badgeLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	badgeLabel.Text = "CASH"
	badgeLabel.Parent = cashBadge

	local lifetimeCashLabel = Instance.new("TextLabel")
	lifetimeCashLabel.Name = "LifetimeCashLabel"
	lifetimeCashLabel.Size = UDim2.new(1, -52, 1, 0)
	lifetimeCashLabel.Position = UDim2.new(0, 52, 0.5, 0)
	lifetimeCashLabel.AnchorPoint = Vector2.new(0, 0.5)
	lifetimeCashLabel.BackgroundTransparency = 1
	lifetimeCashLabel.Font = Enum.Font.GothamBlack
	lifetimeCashLabel.TextSize = 18
	lifetimeCashLabel.TextXAlignment = Enum.TextXAlignment.Left
	lifetimeCashLabel.TextColor3 = Color3.fromRGB(0, 230, 0)
	lifetimeCashLabel.Text = "+0 $"
	lifetimeCashLabel.ZIndex = 3
	lifetimeCashLabel.Parent = moneyFrame

	local moneyStroke = Instance.new("UIStroke")
	moneyStroke.Thickness = 2
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

	-- BOTTOM-RIGHT WALLET CARD
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
	walletBadge.BackgroundColor3 = Color3.fromRGB(255, 185, 0)
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

	hpBg.Visible = isInGame
	statusStack.Size = isInGame and UDim2.new(0, 315, 0, 134) or UDim2.new(0, 315, 0, 82)

	if countUpThread == nil then
		displayedOverallCash = overallCash
		lifetimeCashLabel.Text = string.format("+%d $", math.floor(overallCash))
	end

	if matchWallet ~= lastWalletVal then
		if matchWallet < lastWalletVal then
			animateWalletScalePunch()
		end
		lastWalletVal = matchWallet
	end
	walletValLabel.Text = string.format("$%.2f", matchWallet)
end

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
	if not activeHum or activeHum.Health <= 0 or isBursting then return end

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
		if activeHum then
			for _, tr in ipairs(activeHum:GetPlayingAnimationTracks()) do
				if tr ~= runTrack and tr ~= walkTrack and (tr.Priority == Enum.AnimationPriority.Movement or tr.Priority == Enum.AnimationPriority.Core) then
					tr:Stop(0.1)
				end
			end
		end
	else
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.12) end
		if walkTrack and not walkTrack.IsPlaying then walkTrack:Play(0.12, 1, 1.0) end
		if activeHum then
			for _, tr in ipairs(activeHum:GetPlayingAnimationTracks()) do
				if tr ~= walkTrack and tr ~= runTrack and (tr.Priority == Enum.AnimationPriority.Movement or tr.Priority == Enum.AnimationPriority.Core) then
					tr:Stop(0.1)
				end
			end
		end
	end
end

-- ============================================================================
-- 4. POLISHED PURE-WHITE JETPACK BACKSIDE SPEED TRAILS & VISUAL EFFECTS
-- ============================================================================
local function emitJetpackVisuals(character: Model, duration: number, isLocal: boolean)
	local jetpack = character:FindFirstChild("Jetpack")
	if not jetpack then return end

	local handle = jetpack:FindFirstChild("Handle") :: BasePart?
	local nozzles: { Attachment } = {}

	for _, desc in ipairs(jetpack:GetDescendants()) do
		if desc:IsA("Attachment") and (desc.Name == "LeftNozzle" or desc.Name == "RightNozzle" or string.find(desc.Name, "Nozzle")) then
			table.insert(nozzles, desc)
		end
	end

	if #nozzles == 0 then
		for _, child in ipairs(jetpack:GetChildren()) do
			if child:IsA("MeshPart") then
				local att = Instance.new("Attachment")
				att.Name = "DynamicNozzle"
				att.Position = Vector3.new(0, -child.Size.Y / 2, 0)
				att.Parent = child
				table.insert(nozzles, att)
			end
		end
	end

	local cleanups: { Instance } = {}

	-- 1. GLORIOUS PURE-WHITE BACKSIDE SPEED TRAIL (Centered on Jetpack Handle)
	-- Attached with 1.8 studs of vertical height so it is 100% visible from behind in 3rd person!
	if handle then
		local attTop = Instance.new("Attachment")
		attTop.Name = "BackTrailTop"
		attTop.Position = Vector3.new(0, 0.85, 0.45)
		attTop.Parent = handle

		local attBottom = Instance.new("Attachment")
		attBottom.Name = "BackTrailBottom"
		attBottom.Position = Vector3.new(0, -0.85, 0.45)
		attBottom.Parent = handle

		local backTrail = Instance.new("Trail")
		backTrail.Name = "JetpackBackSpeedTrail"
		backTrail.Attachment0 = attTop
		backTrail.Attachment1 = attBottom
		backTrail.FaceCamera = true
		backTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		backTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.65, 0.35),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		backTrail.Lifetime = 0.32
		backTrail.LightEmission = 1.0
		backTrail.LightInfluence = 0
		backTrail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.0),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		backTrail.Parent = handle
		table.insert(cleanups, backTrail)
		table.insert(cleanups, attTop)
		table.insert(cleanups, attBottom)
	end

	-- 2. DUAL THRUSTER NOZZLE PARTICLES & STREAMING ENGINE TRAILS
	for _, nozzle in ipairs(nozzles) do
		-- Dense pure-white exhaust burst
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "ThrusterExhaust"
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.LightEmission = 1.0
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.60),
			NumberSequenceKeypoint.new(1, 0.10),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		emitter.Lifetime = NumberRange.new(0.15, 0.22)
		emitter.Speed = NumberRange.new(14, 22)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Rate = 120
		emitter.Parent = nozzle
		table.insert(cleanups, emitter)

		-- Individual engine ribbons streaming backwards
		if nozzle.Parent and nozzle.Parent:IsA("BasePart") then
			local nAtt0 = Instance.new("Attachment")
			nAtt0.Name = "NozzleTrail0"
			nAtt0.Position = Vector3.new(0, 0.3, 0)
			nAtt0.Parent = nozzle.Parent

			local nAtt1 = Instance.new("Attachment")
			nAtt1.Name = "NozzleTrail1"
			nAtt1.Position = Vector3.new(0, -0.3, 0)
			nAtt1.Parent = nozzle.Parent

			local nTrail = Instance.new("Trail")
			nTrail.Name = "NozzleStreamTrail"
			nTrail.Attachment0 = nAtt0
			nTrail.Attachment1 = nAtt1
			nTrail.FaceCamera = true
			nTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			nTrail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.10),
				NumberSequenceKeypoint.new(0.7, 0.40),
				NumberSequenceKeypoint.new(1, 1.0),
			})
			nTrail.Lifetime = 0.25
			nTrail.LightEmission = 1.0
			nTrail.LightInfluence = 0
			nTrail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.8),
				NumberSequenceKeypoint.new(1, 0.1),
			})
			nTrail.Parent = nozzle.Parent
			table.insert(cleanups, nTrail)
			table.insert(cleanups, nAtt0)
			table.insert(cleanups, nAtt1)
		end
	end

local function playJetpackBurstSound(character: Model, isLocal: boolean): Sound?
	local jetpack = character:FindFirstChild("Jetpack")
	local handle = jetpack and jetpack:FindFirstChild("Handle") :: BasePart?
	local parentPart = handle or character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character.PrimaryPart or character

	local sound = Instance.new("Sound")
	sound.Name = "JetpackBurstSound"
	sound.SoundId = JETPACK_BURST_SOUND_ID
	sound.Volume = isLocal and JETPACK_BURST_VOLUME or (JETPACK_BURST_VOLUME * 0.70)
	sound.PlaybackSpeed = 1.20 -- 1.20X playback speed as requested
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = isLocal and 15 or 10
	sound.RollOffMaxDistance = isLocal and 160 or 120
	sound.Parent = parentPart
	sound:Play()

	task.spawn(function()
		local t0 = os.clock()
		while sound and sound.Parent and sound.TimeLength <= 0 and (os.clock() - t0) < 1.0 do
			task.wait(0.03)
		end
		local timeLength = (sound and sound.TimeLength > 0) and sound.TimeLength or 2.736
		-- Cut last 0.3 seconds from the audio track
		local cutDuration = math.max(0.1, (timeLength - 0.3) / sound.PlaybackSpeed)
		task.wait(cutDuration)
		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end)

	return sound
end

	-- 3. Local Camera FOV Punch (+6 degrees)
	if isLocal and camera then
		local curFOV = camera.FieldOfView
		local burstFOV = math.min(100, curFOV + 6)
		TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = burstFOV
		}):Play()
	end

	-- Safe cleanup after burst duration
	task.delay(duration, function()
		for _, inst in ipairs(cleanups) do
			if inst:IsA("ParticleEmitter") then
				inst.Enabled = false
				Debris:AddItem(inst, 0.3)
			elseif inst:IsA("Trail") then
				inst.Enabled = false
				Debris:AddItem(inst, 0.3)
			else
				Debris:AddItem(inst, 0.3)
			end
		end

		if isLocal and camera then
			local targetBaselineFOV = isSprinting and 77 or 70
			TweenService:Create(camera, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = targetBaselineFOV
			}):Play()
		end
	end)
end

-- Ultra-Responsive Check: whether Shift + Movement + Space conditions are satisfied
local function canPerformBurst(): boolean
	if isBursting then return false end
	if not activeChar or not activeHum or not activeHRP then return false end
	if activeHum.Health <= 0 then return false end
	if player:GetAttribute("IsAFK") == true and player:GetAttribute("IsInGame") ~= true then return false end
	if exhaustedLockout or currentEnergy < JETPACK_ENERGY_COST then return false end
	if (os.clock() - lastBurstTime) < JETPACK_COOLDOWN then return false end

	-- Check if player is holding Shift (or sprinting) AND moving
	local hasShift = isHoldingShift
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	local isMoving = (activeHum.MoveDirection.Magnitude > 0.05)
		or UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.A)
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.D)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)

	if not (hasShift and isMoving) then
		return false
	end

	return true
end

-- ============================================================================
-- 5. EXPLOSIVE 15-STUD HIGH-SPEED JETPACK BURST
-- ============================================================================
local function performJetpackBurst()
	if not canPerformBurst() or not activeChar or not activeHum or not activeHRP then return end

	-- Determine burst direction along horizontal movement direction (or character facing direction)
	local moveDir = activeHum.MoveDirection
	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	if flatDir.Magnitude < 0.05 then
		local look = activeHRP.CFrame.LookVector
		flatDir = Vector3.new(look.X, 0, look.Z)
	end
	if flatDir.Magnitude < 0.05 then return end
	flatDir = flatDir.Unit

	isBursting = true
	lastBurstTime = os.clock()
	currentEnergy = math.max(0, currentEnergy - JETPACK_ENERGY_COST)

	print(string.format("[Movement][Jetpack] 🚀 Explosive Jetpack Burst! Dir: (%.2f, 0, %.2f), Energy: %d%%",
		flatDir.X, flatDir.Z, math.floor(currentEnergy)))

	-- Turn character forward along burst direction (keeping upright)
	activeHRP.CFrame = CFrame.lookAt(activeHRP.Position, activeHRP.Position + flatDir)

	-- 1. PLAY SOUND BEFORE ANIMATION / MOVEMENT STARTS
	playJetpackBurstSound(activeChar, true)
	task.wait(0.06) -- Crisp pre-ignition beat so sound begins before animation/movement kicks in

	if not activeHRP or not activeHum or activeHum.Health <= 0 then
		isBursting = false
		return
	end

	-- Wall / Obstacle Collision Pre-check: prevent passing through walls
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { activeChar }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local maxDistance = JETPACK_BURST_DISTANCE
	local wallRay = Workspace:Raycast(activeHRP.Position, flatDir * (JETPACK_BURST_DISTANCE + 1.2), rayParams)
	if wallRay then
		maxDistance = math.max(0, wallRay.Distance - 1.2)
	end

	local estimatedDuration = math.clamp(maxDistance / JETPACK_BURST_SPEED, 0.12, 0.25)

	-- Emit visuals (White Backside Trail + Dual Engine Trails + Exhaust) & notify server
	emitJetpackVisuals(activeChar, estimatedDuration, true)
	if JetpackBurstEvent then
		JetpackBurstEvent:FireServer(flatDir)
	end

	if maxDistance < 0.5 then
		-- Pressed directly against wall: abort movement safely without clipping
		isBursting = false
		syncMovementTracks()
		return
	end

	-- BOOST WalkSpeed and apply high-force LinearVelocity so character accelerates massively!
	activeHum.WalkSpeed = JETPACK_BURST_SPEED

	local burstAtt = Instance.new("Attachment")
	burstAtt.Name = "JetpackBurstAttachment"
	burstAtt.Position = Vector3.zero
	burstAtt.Parent = activeHRP

	local burstVel = Instance.new("LinearVelocity")
	burstVel.Name = "JetpackBurstVelocity"
	burstVel.Attachment0 = burstAtt
	burstVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	burstVel.RelativeTo = Enum.ActuatorRelativeTo.World
	burstVel.ForceLimitsEnabled = true
	burstVel.MaxAxesForce = Vector3.new(2000000, 0, 2000000) -- Massive horizontal propulsion, 0 vertical force!
	burstVel.VectorVelocity = flatDir * JETPACK_BURST_SPEED
	burstVel.Parent = activeHRP

	-- Initial kick
	activeHRP.AssemblyLinearVelocity = Vector3.new(flatDir.X * JETPACK_BURST_SPEED, activeHRP.AssemblyLinearVelocity.Y, flatDir.Z * JETPACK_BURST_SPEED)

	local burstStart = os.clock()
	local startPos = activeHRP.Position
	local maxTimeout = 0.30 -- Hard safety timeout

	-- Frame-by-frame precision distance tracker: exactly 15 studs!
	while true do
		RunService.Heartbeat:Wait()
		if not activeHRP or not activeHum or activeHum.Health <= 0 then break end

		local currentPos = activeHRP.Position
		local horizontalDist = ((currentPos - startPos) * Vector3.new(1, 0, 1)).Magnitude
		if horizontalDist >= maxDistance then
			break
		end

		if (os.clock() - burstStart) >= maxTimeout then
			break
		end

		local aheadRay = Workspace:Raycast(currentPos, flatDir * 1.5, rayParams)
		if aheadRay and aheadRay.Distance < 1.0 then
			break
		end
	end

	local finalPos = activeHRP and activeHRP.Position or startPos
	local totalTraveled = ((finalPos - startPos) * Vector3.new(1, 0, 1)).Magnitude
	print(string.format("[Movement][Jetpack] 🏁 Burst complete! Traveled: %.2f studs (Target: %.1f, Speed: %.1f)",
		totalTraveled, maxDistance, JETPACK_BURST_SPEED))

	-- Cleanup physics controller
	burstVel:Destroy()
	burstAtt:Destroy()

	-- Seamlessly restore normal movement / sprint speed
	if activeHRP and activeHum and activeHum.Health > 0 then
		local hasShift = isHoldingShift
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local normalSpeed = hasShift and SPRINT_WALK_SPEED or BASE_WALK_SPEED
		activeHum.WalkSpeed = normalSpeed

		local yVel = activeHRP.AssemblyLinearVelocity.Y
		activeHRP.AssemblyLinearVelocity = Vector3.new(flatDir.X * normalSpeed, yVel, flatDir.Z * normalSpeed)
	end

	isBursting = false
	syncMovementTracks()
end

-- ============================================================================
-- 6. CHARACTER SETUP & GAME-2 HP RESET FIX
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

	isBursting = false
	currentEnergy = MAX_ENERGY
	lastMovementState = "None"

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
		print(string.format("[Movement][Init] ✅ R6 Avatar detected! Loading custom animations:\n  • Walk: %s\n  • Run: %s", currentWalkAnimId, currentRunAnimId))
	else
		currentWalkAnimId = R15_WALK_ANIM_ID
		currentRunAnimId  = R15_RUN_ANIM_ID
		warn(string.format("[Movement][Init] ⚠️ R15 Avatar detected! Loaded R15-compatible animations:\n  • Walk: %s\n  • Run: %s", currentWalkAnimId, currentRunAnimId))
	end

	-- Disable default Roblox 'Animate' script's walk/run interference on R6
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
		for _, playingTrack in ipairs(animator:GetPlayingAnimationTracks()) do
			if playingTrack.Priority == Enum.AnimationPriority.Movement or playingTrack.Priority == Enum.AnimationPriority.Core then
				playingTrack:Stop(0)
			end
		end

		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = currentWalkAnimId

		local runAnim = Instance.new("Animation")
		runAnim.AnimationId = currentRunAnimId

		pcall(function()
			ContentProvider:PreloadAsync({ walkAnim, runAnim })
		end)

		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Movement
		walkTrack.Looped = true

		runTrack = animator:LoadAnimation(runAnim)
		runTrack.Priority = Enum.AnimationPriority.Action
		runTrack.Looped = true

		local loadStart = os.clock()
		while (walkTrack.Length <= 0 or runTrack.Length <= 0) and (os.clock() - loadStart < 5.0) do
			task.wait(0.05)
		end

		print(string.format("[Movement][Init] 🎬 Tracks loaded on Animator:\n  • WalkTrack: Length=%.2fs, Priority=%s, Looped=%s\n  • RunTrack:  Length=%.2fs, Priority=%s, Looped=%s",
			walkTrack and walkTrack.Length or 0, walkTrack and walkTrack.Priority.Name or "nil", tostring(walkTrack and walkTrack.Looped),
			runTrack and runTrack.Length or 0, runTrack and runTrack.Priority.Name or "nil", tostring(runTrack and runTrack.Looped)))

		-- Step 2 Completion Check: Verify Workspace Map and Ruins Door are ready on client
		task.spawn(function()
			local map = Workspace:FindFirstChild("BidToSurviveMap") or Workspace
			if map then
				local _ = map:FindFirstChild("Ruins door") or Workspace:WaitForChild("Ruins door", 5)
				local _ = map:FindFirstChild("GameplayArea") or Workspace:WaitForChild("GameplayArea", 5)
			end

			print(string.format("[BOOT HIERARCHY] 🎬 Step 2: Animations verified (Walk: %.2fs, Run: %.2fs) & map assets ready. Firing ClientLoadReadyEvent.",
				walkTrack.Length, runTrack.Length))

			if ClientLoadReadyEvent then
				ClientLoadReadyEvent:FireServer()
			end
		end)
	end

	-- Re-bind HP listener on EVERY new character/game
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
-- 7. INPUT HANDLING & MULTIPLAYER REPLICATION
-- ============================================================================
-- ContextActionService binding for Space:
-- Sinks Space when sprinting to perform Jetpack Burst (blocking normal jump).
-- Passes Space to Roblox default controls for normal jumping when not sprinting.
local function handleSpaceAction(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		if canPerformBurst() then
			print("[Movement][Input] ⌨️ Shift + Move + Space -> Triggering High-Speed Jetpack Burst!")
			task.spawn(performJetpackBurst)
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
	"JetpackBurstContextAction",
	handleSpaceAction,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.Space
)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isHoldingShift = true
		print(string.format("[Movement][Input] ⌨️ Shift pressed (isHoldingShift=true, Energy=%d%%, ExhaustedLockout=%s)", math.floor(currentEnergy), tostring(exhaustedLockout)))
		syncMovementTracks()
	elseif input.KeyCode == Enum.KeyCode.Space then
		-- Fallback check in case ContextActionService was bypassed
		if canPerformBurst() then
			print("[Movement][Input] ⌨️ Spacebar fallback detected -> Triggering Jetpack Burst!")
			task.spawn(performJetpackBurst)
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

-- Replicate other players' jetpack bursts in multiplayer
if JetpackBurstReplicatedEvent then
	JetpackBurstReplicatedEvent.OnClientEvent:Connect(function(burstingPlayer: Player, flatDir: Vector3)
		if burstingPlayer ~= player and burstingPlayer.Character then
			playJetpackBurstSound(burstingPlayer.Character, false)
			emitJetpackVisuals(burstingPlayer.Character, 0.22, false)
		end
	end)
end

RunService.RenderStepped:Connect(function(dt)
	if not activeHum or activeHum.Health <= 0 then return end

	syncMovementTracks()

	-- Drain White Energy while sprinting; regenerate when walking or standing still
	if isSprinting and not isBursting then
		currentEnergy = math.max(0, currentEnergy - (SPRINT_DRAIN_RATE * dt))
		if currentEnergy <= 0 and not exhaustedLockout then
			exhaustedLockout = true
			print("[Movement][Energy] ⚠️ ENERGY EXHAUSTED (0%) -> Sprint lockout engaged until energy reaches 20%")
			syncMovementTracks()
		end
	elseif not isBursting then
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

	-- Instant Water Fall Recovery (Play Area -> Walkway)
	if activeHrp and activeHum and activeHum.Health > 0 then
		local inPlayArea = (activeHrp.Position.X < -50) or (player:GetAttribute("IsInGame") == true)
		if inPlayArea and (activeHrp.Position.Y <= 34.5 or activeHum:GetState() == Enum.HumanoidStateType.Swimming) then
			local map = Workspace:FindFirstChild("BidToSurviveMap")
			local gameArea = map and map:FindFirstChild("GameplayArea")
			local walkway = gameArea and gameArea:FindFirstChild("Walkway")
			local targetPos = walkway and Vector3.new(walkway.Position.X, walkway.Position.Y + 3.5, walkway.Position.Z)
				or Vector3.new(-161.5, 72.5, -24.9)

			activeHrp.AssemblyLinearVelocity = Vector3.zero
			activeHrp.AssemblyAngularVelocity = Vector3.zero
			if player.Character then
				player.Character:PivotTo(CFrame.new(targetPos))
			end
			activeHum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end)

print("[MovementDiveAndHUDClient] Initialized: Walk (90697464892050), Run (125757170550820), High-Speed Jetpack Burst (15-stud) & Unified Stacked HUD.")
