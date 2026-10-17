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

local StarterGui = game:GetService("StarterGui")

-- Guarantee default Roblox top-right Health Bar is eliminated
task.spawn(function()
	local maxRetries = 20
	while maxRetries > 0 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then break end
		task.wait(0.2)
		maxRetries -= 1
	end
end)

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

-- ============================================================================
-- JETPACK BURST SOUND & TIMING TUNING (Tweak these constants anytime!)
-- ============================================================================
local JETPACK_BURST_SOUND_ID       = "rbxasset://sounds/jetpack-sound.mp3"
local JETPACK_BURST_VOLUME         = 0.90
local JETPACK_PLAYBACK_SPEED       = 1.35 -- Playback speed multiplier (1.35X)
local JETPACK_SOUND_START_OFFSET   = 0.10 -- [CUT FRONT]: Skips first 0.10s of audio (removes slow wind-up/silence)
local JETPACK_SOUND_CUT_LAST       = 0.70 -- [CUT BACK]: Cuts trailing audio at end of sound (0.50s)
local JETPACK_SOUND_FADE_DURATION  = 0.80 -- [FADE DURATION]: Audio time (in seconds) used to smoothly fade out volume from full to 0
local JETPACK_PRE_LAUNCH_DELAY     = 0.02 -- [LAUNCH DELAY]: Delay before movement launches (0.02s = instant launch!)

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
-- 2. UNIFIED HP, ENERGY & DYNAMIC LOBBY/GAME CURRENCY HUD (STATUS HUD VIEW)
-- ============================================================================
local ClientUI = ReplicatedStorage:WaitForChild("ClientUI")
local StatusHUDView = require(ClientUI:WaitForChild("components"):WaitForChild("StatusHUDView")) :: any
local statusHUD = StatusHUDView.new(player)

local function updateHPDisplay(health: number, maxHealth: number)
	statusHUD:UpdateHealth(health, maxHealth)
end

local function updateCurrencyUI()
	local isInGame = (player:GetAttribute("IsInGame") == true)
	local overallCash = player:GetAttribute("OverallCash") or 0
	local matchWallet = player:GetAttribute("Wallet") or 20
	statusHUD:UpdateCurrencyUI(isInGame, overallCash, matchWallet)
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
	statusHUD:HandlePayout(earnedCash, secondsSurvived, newOverall)
end

local PayoutRemote: RemoteEvent? = (ReplicatedStorage:FindFirstChild("CashPayoutEvent") :: any)
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
local function isShiftPressed(): boolean
	local keyHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	-- If neither Shift key is physically held on keyboard, auto-clear isHoldingShift
	if not keyHeld and isHoldingShift then
		isHoldingShift = false
	end
	return isHoldingShift or keyHeld
end

local function syncMovementTracks()
	if not activeHum or activeHum.Health <= 0 or isBursting then return end

	-- Check if character is airborne (jumping or in freefall with feet in air)
	local humState = activeHum:GetState()
	local isAirborne = (activeHum.FloorMaterial == Enum.Material.Air) and (
		(humState == Enum.HumanoidStateType.Jumping)
		or (humState == Enum.HumanoidStateType.Freefall)
		or (humState == Enum.HumanoidStateType.FallingDown)
	)

	local isMoving = activeHum.MoveDirection.Magnitude > 0.05
	local hasShift = isShiftPressed()
	local wantSprint = hasShift and isMoving and (not exhaustedLockout) and (currentEnergy > 0)

	isSprinting = wantSprint
	activeHum.WalkSpeed = wantSprint and SPRINT_WALK_SPEED or BASE_WALK_SPEED

	if camera then
		TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = wantSprint and 77 or 70
		}):Play()
	end

	-- When airborne, smoothly fade out walk & sprint tracks so native jump/fall animations play cleanly!
	if isAirborne then
		if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.15) end
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.15) end
		lastMovementState = "Airborne"
		return
	end

	local newState = "Idle"
	if isMoving then
		newState = wantSprint and "Sprinting" or "Walking"
	end

	if newState == "Idle" then
		-- Smoothly fade out movement tracks; Action priority fading allows default Core Idle to seamlessly show
		if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.2) end
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.2) end
	elseif newState == "Sprinting" then
		if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.15) end
		if runTrack then
			if not runTrack.IsPlaying then
				runTrack:Play(0.15, 1, 1.0)
			end
			local speedRatio = activeHum.WalkSpeed / SPRINT_WALK_SPEED
			runTrack:AdjustSpeed(math.clamp(speedRatio, 0.8, 1.3))
		end
	elseif newState == "Walking" then
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.15) end
		if walkTrack then
			if not walkTrack.IsPlaying then
				walkTrack:Play(0.15, 1, 1.0)
			end
			local speedRatio = activeHum.WalkSpeed / BASE_WALK_SPEED
			walkTrack:AdjustSpeed(math.clamp(speedRatio, 0.8, 1.3))
		end
	end

	if newState ~= lastMovementState then
		lastMovementState = newState
	end
end

-- ============================================================================
-- 4. POLISHED PURE-WHITE JETPACK BACKSIDE SPEED TRAILS, SOUNDS & VISUAL EFFECTS
-- ============================================================================
local function playJetpackBurstSound(character: Model?, isLocal: boolean): Sound?
	if not character then return nil end
	local jetpack = character:FindFirstChild("Jetpack")
	local handle = jetpack and jetpack:FindFirstChild("Handle") :: BasePart?
	local parentPart = handle or character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character.PrimaryPart or character

	local sound = Instance.new("Sound")
	sound.Name = "JetpackBurstSound"
	sound.SoundId = JETPACK_BURST_SOUND_ID
	sound.Volume = isLocal and JETPACK_BURST_VOLUME or (JETPACK_BURST_VOLUME * 0.70)
	sound.PlaybackSpeed = JETPACK_PLAYBACK_SPEED
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = isLocal and 15 or 10
	sound.RollOffMaxDistance = isLocal and 160 or 120
	sound.Parent = parentPart

	-- Exact timing configuration using top-level constants
	pcall(function()
		local timeLength = (sound.TimeLength > 0) and sound.TimeLength or 2.736
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(
			JETPACK_SOUND_START_OFFSET,
			math.max(JETPACK_SOUND_START_OFFSET + 0.05, timeLength - JETPACK_SOUND_CUT_LAST)
		)
	end)

	pcall(function()
		sound:Play()
		sound.TimePosition = JETPACK_SOUND_START_OFFSET
	end)

	-- Accurate cleanup: play at full volume until the final 1.0s of audio, then smoothly fade volume to 0
	task.spawn(function()
		local t0 = os.clock()
		while sound and sound.Parent and sound.TimeLength <= 0 and (os.clock() - t0) < 0.5 do
			task.wait(0.02)
		end
		local totalLength = (sound and sound.TimeLength > 0) and sound.TimeLength or 2.736
		local activeAudio = math.max(0.1, totalLength - JETPACK_SOUND_START_OFFSET - JETPACK_SOUND_CUT_LAST)
		local realPlayDuration = activeAudio / sound.PlaybackSpeed

		-- User-configured fade duration controlled by top-level JETPACK_SOUND_FADE_DURATION
		local fadeAudioDuration = math.clamp(JETPACK_SOUND_FADE_DURATION, 0.05, activeAudio)
		local fadeRealDuration = math.min(realPlayDuration, fadeAudioDuration / sound.PlaybackSpeed)
		local fullVolumeDuration = math.max(0, realPlayDuration - fadeRealDuration)

		if fullVolumeDuration > 0 then
			task.wait(fullVolumeDuration)
		end

		if sound and sound.Parent then
			local fadeTween = TweenService:Create(sound, TweenInfo.new(fadeRealDuration, Enum.EasingStyle.Linear), {
				Volume = 0,
			})
			fadeTween:Play()
			task.wait(fadeRealDuration)
		end

		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end)

	return sound
end

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

-- ============================================================================
-- JETPACK WARNING NOTIFICATION (Pure red text at top, smooth fade out, zero UI overlap)
-- ============================================================================
local warningToastFrame: Frame? = nil
local warningToastLabel: TextLabel? = nil
local warningSessionToken = 0

local function getOrCreateWarningToast(): (Frame, TextLabel)
	if warningToastFrame and warningToastFrame.Parent and warningToastLabel then
		return warningToastFrame, warningToastLabel
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local targetGui: ScreenGui = (playerGui:FindFirstChild("BidToSurviveUI") :: ScreenGui?)
		or statusHUD.ScreenGui

	local yOffset = targetGui.IgnoreGuiInset and 108 or 72

	local toastFrame = Instance.new("Frame")
	toastFrame.Name = "JetpackWarningToast"
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.Position = UDim2.new(0.5, 0, 0, yOffset)
	toastFrame.Size = UDim2.new(0, 320, 0, 28)
	toastFrame.BackgroundTransparency = 1
	toastFrame.BorderSizePixel = 0
	toastFrame.ZIndex = 45
	toastFrame.Visible = false

	local label = Instance.new("TextLabel")
	label.Name = "WarningLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(255, 60, 60)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 46
	label.Parent = toastFrame

	toastFrame.Parent = targetGui
	warningToastFrame = toastFrame
	warningToastLabel = label

	return toastFrame, label
end

local function showJetpackWarning(message: string)
	local frame, label = getOrCreateWarningToast()
	warningSessionToken = warningSessionToken + 1
	local myToken = warningSessionToken

	label.Text = message
	frame.Visible = true

	local targetGui = frame:FindFirstAncestorWhichIsA("ScreenGui")
	local baseY = (targetGui and targetGui.IgnoreGuiInset) and 108 or 72

	frame.Position = UDim2.new(0.5, 0, 0, baseY - 6)

	-- Smooth fade-in (pure text)
	TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, baseY),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.25,
	}):Play()

	-- Subtle error feedback audio
	pcall(function()
		local errorTick = Instance.new("Sound")
		errorTick.SoundId = "rbxassetid://6895079853"
		errorTick.PlaybackSpeed = 0.65
		errorTick.Volume = 0.35
		errorTick.Parent = frame
		errorTick:Play()
		Debris:AddItem(errorTick, 0.4)
	end)

	-- Hold for 1.25s then smooth fade-out
	task.delay(1.25, function()
		if myToken ~= warningSessionToken then return end
		local fadeOutInfo = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tFrame = TweenService:Create(frame, fadeOutInfo, {
			Position = UDim2.new(0.5, 0, 0, baseY - 6),
		})
		local tLabel = TweenService:Create(label, fadeOutInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tFrame:Play()
		tLabel:Play()

		tFrame.Completed:Once(function()
			if myToken == warningSessionToken then
				frame.Visible = false
			end
		end)
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
	local hasShift = isShiftPressed()

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
	pcall(function()
		activeHRP.CFrame = CFrame.lookAt(activeHRP.Position, activeHRP.Position + flatDir)
	end)

	-- 1. PLAY SOUND BEFORE ANIMATION / MOVEMENT STARTS
	pcall(function()
		playJetpackBurstSound(activeChar, true)
	end)
	if JETPACK_PRE_LAUNCH_DELAY > 0 then
		task.wait(JETPACK_PRE_LAUNCH_DELAY)
	end

	if not activeHRP or not activeHum or activeHum.Health <= 0 then
		isBursting = false
		return
	end

	local burstAtt: Attachment? = nil
	local burstVel: LinearVelocity? = nil

	local ok, burstErr = pcall(function()
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
		pcall(function()
			emitJetpackVisuals(activeChar, estimatedDuration, true)
		end)
		if JetpackBurstEvent then
			JetpackBurstEvent:FireServer(flatDir)
		end

		if maxDistance >= 0.5 and activeHRP and activeHum and activeHum.Health > 0 then
			-- BOOST WalkSpeed and apply high-force LinearVelocity so character accelerates massively!
			activeHum.WalkSpeed = JETPACK_BURST_SPEED

			burstAtt = Instance.new("Attachment")
			burstAtt.Name = "JetpackBurstAttachment"
			burstAtt.Position = Vector3.zero
			burstAtt.Parent = activeHRP

			burstVel = Instance.new("LinearVelocity")
			burstVel.Name = "JetpackBurstVelocity"
			burstVel.Attachment0 = burstAtt
			burstVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			burstVel.RelativeTo = Enum.ActuatorRelativeTo.World
			burstVel.ForceLimitsEnabled = true
			burstVel.MaxAxesForce = Vector3.new(2000000, 0, 2000000)
			burstVel.VectorVelocity = flatDir * JETPACK_BURST_SPEED
			burstVel.Parent = activeHRP

			-- Initial kick
			activeHRP.AssemblyLinearVelocity = Vector3.new(flatDir.X * JETPACK_BURST_SPEED, activeHRP.AssemblyLinearVelocity.Y, flatDir.Z * JETPACK_BURST_SPEED)

			local burstStart = os.clock()
			local startPos = activeHRP.Position
			local maxTimeout = 0.30 -- Hard safety timeout

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
		end
	end)

	if not ok then
		warn("[Movement][Jetpack] Error executing burst:", burstErr)
	end

	-- GUARANTEED CLEANUP: Physics controller removal
	if burstVel then pcall(function() burstVel:Destroy() end) end
	if burstAtt then pcall(function() burstAtt:Destroy() end) end

	-- Seamlessly restore normal movement / sprint speed
	if activeHRP and activeHum and activeHum.Health > 0 then
		local hasShift = isShiftPressed()
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

	-- In R6, Roblox default Animate uses "run" for all ground locomotion.
	-- Setting both "walk" and "run" in Animate to currentWalkAnimId guarantees default movement
	-- is ALWAYS the clean walk animation without playing the sprint animation during regular walking.
	-- Custom Sprint is cleanly driven with Action priority on top!
	local animateScript = character:WaitForChild("Animate", 3)
	if animateScript and animateScript:IsA("LocalScript") then
		for _, folderName in ipairs({ "walk", "run" }) do
			local folder = animateScript:FindFirstChild(folderName)
			if folder then
				for _, anim in ipairs(folder:GetChildren()) do
					if anim:IsA("Animation") then
						anim.AnimationId = currentWalkAnimId
					end
				end
			end
		end
	end

	local animator = activeHum:WaitForChild("Animator", 5) :: Animator
	if animator then
		-- Cleanly release any stale tracks from previous character spawn
		if walkTrack then
			pcall(function()
				walkTrack:Stop(0)
				walkTrack:Destroy()
			end)
			walkTrack = nil
		end
		if runTrack then
			pcall(function()
				runTrack:Stop(0)
				runTrack:Destroy()
			end)
			runTrack = nil
		end

		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = currentWalkAnimId

		local runAnim = Instance.new("Animation")
		runAnim.AnimationId = currentRunAnimId

		pcall(function()
			ContentProvider:PreloadAsync({ walkAnim, runAnim })
		end)

		-- Action priority ensures walk/run cleanly overrides core/movement without killing default Idle
		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Action
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

	activeHum.StateChanged:Connect(function(oldState, newState)
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
		local hasShift = isShiftPressed()
		if hasShift or isSprinting then
			if canPerformBurst() then
				print("[Movement][Input] ⌨️ Shift + Move + Space -> Triggering High-Speed Jetpack Burst!")
				task.spawn(performJetpackBurst)
				return Enum.ContextActionResult.Sink
			else
				if exhaustedLockout or currentEnergy < JETPACK_ENERGY_COST then
					showJetpackWarning("Out of energy!")
					return Enum.ContextActionResult.Sink
				elseif (os.clock() - lastBurstTime) < JETPACK_COOLDOWN then
					showJetpackWarning("Too frequent!")
					return Enum.ContextActionResult.Sink
				end
			end
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
		local hasShift = isShiftPressed()
		if hasShift or isSprinting then
			if canPerformBurst() then
				print("[Movement][Input] ⌨️ Spacebar fallback detected -> Triggering Jetpack Burst!")
				task.spawn(performJetpackBurst)
			else
				if exhaustedLockout or currentEnergy < JETPACK_ENERGY_COST then
					showJetpackWarning("Out of energy!")
				elseif (os.clock() - lastBurstTime) < JETPACK_COOLDOWN then
					showJetpackWarning("Too frequent!")
				end
			end
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
	statusHUD:UpdateEnergy(currentEnergy, MAX_ENERGY)

	-- Instant Water Fall Recovery (Play Area -> Walkway)
	if activeHRP and activeHum and activeHum.Health > 0 then
		local inPlayArea = (activeHRP.Position.X < -50) or (player:GetAttribute("IsInGame") == true)
		if inPlayArea and (activeHRP.Position.Y <= 34.5 or activeHum:GetState() == Enum.HumanoidStateType.Swimming) then
			local map = Workspace:FindFirstChild("BidToSurviveMap")
			local gameArea = map and map:FindFirstChild("GameplayArea")
			local walkway = gameArea and gameArea:FindFirstChild("Walkway")
			local targetPos = walkway and Vector3.new(walkway.Position.X, walkway.Position.Y + 3.5, walkway.Position.Z)
				or Vector3.new(-161.5, 72.5, -24.9)

			activeHRP.AssemblyLinearVelocity = Vector3.zero
			activeHRP.AssemblyAngularVelocity = Vector3.zero
			if player.Character then
				player.Character:PivotTo(CFrame.new(targetPos))
			end
			activeHum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end)

print("[MovementDiveAndHUDClient] Initialized: Walk (90697464892050), Run (125757170550820), High-Speed Jetpack Burst (15-stud) & Unified Stacked HUD.")
