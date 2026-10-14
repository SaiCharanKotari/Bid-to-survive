--!strict
-- StarterPlayer/StarterPlayerScripts/MovementAndSprintClient.client.luau
-- Overrides default walk/run animations and provides responsive Shift-to-Sprint controller
-- with 1.6s stamina burst cap, RootJoint athletic lean, FOV punch, and animation rate shifting.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ============================================================================
-- TUNING CONSTANTS
-- ============================================================================
local BASE_WALK_SPEED = 14
local SPRINT_WALK_SPEED = 21

local BASE_FOV = 70
local SPRINT_FOV = 76

-- 1.6s Sprint Stamina Burst (Mandates tactical sprint conservation during Red Circle)
local MAX_SPRINT_STAMINA = 1.6
local STAMINA_REGEN_RATE = 0.45 -- Regens in ~3.5s
local currentStamina = MAX_SPRINT_STAMINA
local exhaustedLockout = false

-- Stylish R15 Action Walk & Run IDs
local CUSTOM_WALK_ANIM_ID = "rbxassetid://656121766"
local CUSTOM_RUN_ANIM_ID  = "rbxassetid://656118852"

local isHoldingShift = false
local activeHumanoid: Humanoid? = nil
local rootMotor: Motor6D? = nil
local baseRootC0: CFrame? = nil

local function applyCustomWalkAnimations(character: Model)
	local animateScript = character:WaitForChild("Animate", 6)
	if not animateScript then return end

	local walkVal = animateScript:FindFirstChild("walk")
	local walkAnim = walkVal and walkVal:FindFirstChildWhichIsA("Animation")
	if walkAnim then
		walkAnim.AnimationId = CUSTOM_WALK_ANIM_ID
	end

	local runVal = animateScript:FindFirstChild("run")
	local runAnim = runVal and runVal:FindFirstChildWhichIsA("Animation")
	if runAnim then
		runAnim.AnimationId = CUSTOM_RUN_ANIM_ID
	end
end

local function updateSprintState(sprinting: boolean)
	isHoldingShift = sprinting
	if not activeHumanoid or activeHumanoid.Health <= 0 then return end

	local canSprint = sprinting and (not exhaustedLockout) and (currentStamina > 0)
	local targetSpeed = canSprint and SPRINT_WALK_SPEED or BASE_WALK_SPEED
	local targetFOV = canSprint and SPRINT_FOV or BASE_FOV

	TweenService:Create(activeHumanoid, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		WalkSpeed = targetSpeed
	}):Play()

	if camera then
		TweenService:Create(camera, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = targetFOV
		}):Play()
	end

	-- Shift active movement animation track playback speed
	local animator = activeHumanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Movement or track.Name == "WalkAnim" or track.Name == "RunAnim" then
				track:AdjustSpeed(canSprint and 1.28 or 1.0)
			end
		end
	end

	-- Subtle athletic forward lean on RootJoint
	if rootMotor and baseRootC0 then
		local leanGoal = canSprint and (baseRootC0 * CFrame.Angles(math.rad(-8), 0, 0)) or baseRootC0
		TweenService:Create(rootMotor, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			C0 = leanGoal
		}):Play()
	end
end

local function setupCharacter(character: Model)
	activeHumanoid = character:WaitForChild("Humanoid", 6) :: Humanoid?
	if not activeHumanoid then return end

	activeHumanoid.WalkSpeed = BASE_WALK_SPEED
	currentStamina = MAX_SPRINT_STAMINA
	exhaustedLockout = false
	isHoldingShift = false

	-- Locate RootMotor for subtle posture shift
	local lowerTorso = character:WaitForChild("LowerTorso", 4)
	local hrp = character:WaitForChild("HumanoidRootPart", 4)
	rootMotor = (lowerTorso and lowerTorso:FindFirstChild("Root") :: Motor6D?)
		or (hrp and hrp:FindFirstChild("RootJoint") :: Motor6D?)
	baseRootC0 = rootMotor and rootMotor.C0 or nil

	task.spawn(applyCustomWalkAnimations, character)

	-- Retain animation speed adjustment whenever movement tracks loop / restart
	activeHumanoid.Running:Connect(function(speed)
		if isHoldingShift and not exhaustedLockout and speed > 1 then
			local animator = activeHumanoid and activeHumanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if track.Priority == Enum.AnimationPriority.Movement or track.Name == "WalkAnim" or track.Name == "RunAnim" then
						track:AdjustSpeed(1.28)
					end
				end
			end
		end
	end)
end

if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

-- Input Listeners for Left & Right Shift
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		updateSprintState(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		updateSprintState(false)
	end
end)

-- Stamina Meter Loop
RunService.RenderStepped:Connect(function(dt)
	local isMoving = activeHumanoid and activeHumanoid.MoveDirection.Magnitude > 0.05
	if isHoldingShift and not exhaustedLockout and isMoving then
		currentStamina = math.max(0, currentStamina - dt)
		if currentStamina <= 0 then
			exhaustedLockout = true
			updateSprintState(false) -- Exhausted: drop to 14 WalkSpeed!
		end
	else
		currentStamina = math.min(MAX_SPRINT_STAMINA, currentStamina + (STAMINA_REGEN_RATE * dt))
		if exhaustedLockout and currentStamina >= (MAX_SPRINT_STAMINA * 0.60) then
			exhaustedLockout = false
			if isHoldingShift then
				updateSprintState(true)
			end
		end
	end
end)

print("[MovementAndSprintClient] Initialized with 14 Walk / 21 Sprint & 1.6s Stamina Burst.")
