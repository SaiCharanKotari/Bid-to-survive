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
local DIVE_FORWARD_SPEED = 32 -- Slightly decreased forward dive impulse for tighter, more athletic control
local DIVE_DURATION      = 0.68 -- Fallback duration if track length hasn't loaded
local DIVE_LANDING_DELAY = 0.22 -- Recovery delay on ground before returning to normal standing

-- Energy Settings (White Bar)
local MAX_ENERGY        = 100
local SPRINT_DRAIN_RATE = 24 -- Energy drained per second while running
local DIVE_ENERGY_COST  = 28 -- Burst energy consumed on Spacebar Dive
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
-- 2. UNIFIED MONEY, HP & WHITE ENERGY HUD BUILDER
-- ============================================================================
local function createOrUpdateStatusHUD()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("BidToSurviveStatusHUD")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BidToSurviveStatusHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Unified Bottom-Left Container for Money, HP, and White Energy Bar
	local container = Instance.new("Frame")
	container.Name = "StatusStack"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 24, 1, -24)
	container.Size = UDim2.new(0, 260, 0, 118)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = container

	local function createThemedBar(order: number, name: string, labelText: string, fillColor: Color3)
		local bg = Instance.new("Frame")
		bg.Name = name .. "Frame"
		bg.LayoutOrder = order
		bg.Size = UDim2.new(1, 0, 0, 32)
		bg.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		bg.BackgroundTransparency = 0.15
		bg.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = bg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(55, 60, 75)
		stroke.Thickness = 1.5
		stroke.Parent = bg

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = fillColor
		fill.BorderSizePixel = 0
		fill.Parent = bg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 8)
		fillCorner.Parent = fill

		local label = Instance.new("TextLabel")
		label.Name = "ValueLabel"
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = (fillColor == Color3.fromRGB(255, 255, 255))
			and Color3.fromRGB(30, 35, 45)
			or Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = (fillColor == Color3.fromRGB(255, 255, 255)) and 0.85 or 0.35
		label.Text = labelText
		label.ZIndex = 2
		label.Parent = bg

		return bg, fill, label
	end

	-- 1) Money Bar (Aligned directly above HP & Energy in the same theme)
	local _, moneyFill, moneyLabel = createThemedBar(1, "Money", "WALLET: $0.00", Color3.fromRGB(46, 175, 95))
	moneyFill.Size = UDim2.new(1, 0, 1, 0)

	-- 2) HP Bar (Crimson Red)
	local _, hpFill, hpLabel = createThemedBar(2, "HP", "HP: 100 / 100", Color3.fromRGB(235, 55, 65))

	-- 3) Energy Bar (Pure White #FFFFFF)
	local _, energyFill, energyLabel = createThemedBar(3, "Energy", "ENERGY: 100%", Color3.fromRGB(255, 255, 255))

	return moneyLabel, hpFill, hpLabel, energyFill, energyLabel
end

local moneyLabel, hpFill, hpLabel, energyFill, energyLabel = createOrUpdateStatusHUD()

local function updateHPDisplay(health: number, maxHealth: number)
	local safeMax = (maxHealth > 0) and maxHealth or 100
	local ratio = math.clamp(health / safeMax, 0, 1)
	hpLabel.Text = string.format("HP: %d / %d", math.ceil(health), math.ceil(safeMax))
	TweenService:Create(hpFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
end

local function updateMoneyDisplay(explicitVal: number?)
	local moneyVal = explicitVal
	if moneyVal == nil then
		local ls = player:FindFirstChild("leaderstats")
		local walletObj = ls and (ls:FindFirstChild("Wallet") or ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
		local attrVal = player:GetAttribute("Wallet") or player:GetAttribute("Money")
		moneyVal = (typeof(attrVal) == "number" and attrVal)
			or (walletObj and typeof(walletObj.Value) == "number" and walletObj.Value)
			or 0
	end
	moneyLabel.Text = string.format("WALLET: $%.2f", tonumber(moneyVal) or 0)
end

player.AttributeChanged:Connect(function(attr)
	if attr == "Wallet" or attr == "Money" then
		updateMoneyDisplay()
	elseif attr == "HP" or attr == "Health" then
		local h = player:GetAttribute(attr)
		if typeof(h) == "number" and activeHum then
			updateHPDisplay(h, activeHum.MaxHealth)
		end
	end
end)

if StatsUpdated then
	StatsUpdated.OnClientEvent:Connect(function(stats)
		if stats then
			if stats.Money ~= nil then
				updateMoneyDisplay(stats.Money)
			end
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
	print(string.format("[Movement][Dive] 🏊 Spacebar Dive initiated! (Direction: %s, Energy before: %d%%, Cost: %d%%)", tostring(flatDir), math.floor(currentEnergy + DIVE_ENERGY_COST), DIVE_ENERGY_COST))

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

	local visualTorso = activeChar:FindFirstChild("LowerTorso") or activeChar:FindFirstChild("Torso")
	local diveDuration = 0.68 -- Dynamic fallback if metadata hasn't loaded yet

	if diveTrack then
		diveTrack:Play(0.08, 1, 1.0)
		if diveTrack.Length and diveTrack.Length > 0.05 then
			diveDuration = diveTrack.Length
		end
		print(string.format("[Movement][Dive] 🎬 DiveTrack playing (Length: %.2fs, Priority: %s)", diveDuration, diveTrack.Priority.Name))
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { activeChar }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local torso = activeChar:FindFirstChild("Torso")
	local head = activeChar:FindFirstChild("Head")

	-- 1. CRITICAL: Disable Torso and Head CanCollide during roll so rotating body parts
	-- NEVER collide into or penetrate the 1-stud thick floor parts!
	if torso and torso:IsA("BasePart") then torso.CanCollide = false end
	if head and head:IsA("BasePart") then head.CanCollide = false end

	-- 2. Apply horizontal physics impulse with MaxForce.Y = 0
	-- Vertical axis is handled 100% by Roblox's native floor suspension, making it physically impossible to fall through the floor!
	local bv = Instance.new("BodyVelocity")
	bv.Name = "DiveImpulse"
	bv.MaxForce = Vector3.new(150000, 0, 150000)
	bv.Velocity = flatDir * DIVE_FORWARD_SPEED
	bv.Parent = activeHRP

	local startTime = os.clock()
	while (os.clock() - startTime) < diveDuration do
		task.wait(0.03)
		if not activeHRP or not activeHum or activeHum.Health <= 0 then break end

		local elapsed = os.clock() - startTime
		local alpha = math.clamp(elapsed / diveDuration, 0, 1)
		local curSpeed = DIVE_FORWARD_SPEED * (1 - (alpha * 0.55))

		-- Edge & cliff protection: verify solid ground still exists 3.5 studs ahead
		local checkPos = activeHRP.Position + (flatDir * 3.5)
		local floorAhead = Workspace:Raycast(checkPos + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), rayParams)
		if floorAhead then
			bv.Velocity = flatDir * curSpeed
		else
			-- Edge detected! Cut velocity so character stays safely on the platform
			bv.Velocity = Vector3.zero
		end
	end

	-- Clean up impulse and restore body collisions
	if bv and bv.Parent then
		bv:Destroy()
	end
	if torso and torso:IsA("BasePart") then torso.CanCollide = true end
	if head and head:IsA("BasePart") then head.CanCollide = true end

	print(string.format("[Movement][Dive] 🎯 Dive complete and safely landed on floor at %s", tostring(activeHRP.Position)))

	-- Fade and cleanly clean up motion trail
	diveTrail.Enabled = false
	Debris:AddItem(diveTrail, 0.35)
	Debris:AddItem(trailAtt0, 0.35)
	Debris:AddItem(trailAtt1, 0.35)

	-- Ground recovery delay: damp speed briefly so character absorbs the landing before springing back up
	if activeHum and activeHum.Health > 0 then
		activeHum.WalkSpeed = 6 -- Momentarily dampened crawl/recovery speed
	end

	-- Slight delay on the ground before returning to normal standing posture
	task.wait(DIVE_LANDING_DELAY)

	-- Smoothly stop Dive track as player recovers into standing
	if diveTrack and diveTrack.IsPlaying then
		diveTrack:Stop(0.12)
	end

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

	-- Update White Energy Bar UI
	local energyRatio = math.clamp(currentEnergy / MAX_ENERGY, 0, 1)
	energyFill.Size = UDim2.new(energyRatio, 0, 1, 0)
	energyLabel.Text = string.format("ENERGY: %d%%", math.floor(currentEnergy))
end)

print("[MovementDiveAndHUDClient] Initialized: Walk (90697464892050), Run (125757170550820), Dive (137603926461078) & Unified Stacked HUD.")
