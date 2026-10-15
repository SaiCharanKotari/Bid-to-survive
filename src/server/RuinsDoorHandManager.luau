--!strict
-- ServerScriptService/RuinsDoorHandManager.luau
-- Authoritative server hazard manager for Workspace["Ruins door"]
-- Features 80% Red Danger Circle telegraph, greedy loser targeting,
-- razor-thin bottleneck timing, dynamic slam trajectory, and edge-grazing dive tumble.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local RuinsDoorHandManager = {}

-- Ensure RemoteEvents exist in ReplicatedStorage & Network
local Network = ReplicatedStorage:FindFirstChild("Network")

local ImpactRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsHandImpactEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsHandImpactEvent") :: any
if not ImpactRemote then
	ImpactRemote = Instance.new("RemoteEvent")
	ImpactRemote.Name = "RuinsHandImpactEvent"
	ImpactRemote.Parent = Network or ReplicatedStorage
end

local PortalRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsPortalEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsPortalEvent") :: any
if not PortalRemote then
	PortalRemote = Instance.new("RemoteEvent")
	PortalRemote.Name = "RuinsPortalEvent"
	PortalRemote.Parent = Network or ReplicatedStorage
end

local TelegraphRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsTelegraphEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsTelegraphEvent") :: any
if not TelegraphRemote then
	TelegraphRemote = Instance.new("RemoteEvent")
	TelegraphRemote.Name = "RuinsTelegraphEvent"
	TelegraphRemote.Parent = Network or ReplicatedStorage
end

local ResetHUDRemote: RemoteEvent = (Network and Network:FindFirstChild("ResetHUDStateEvent"))
	or ReplicatedStorage:FindFirstChild("ResetHUDStateEvent") :: any
if not ResetHUDRemote then
	ResetHUDRemote = Instance.new("RemoteEvent")
	ResetHUDRemote.Name = "ResetHUDStateEvent"
	ResetHUDRemote.Parent = Network or ReplicatedStorage
end

-- Helper: Converts Studio Position + Studio Orientation (YXZ degrees) to exact CFrame
local function toStudioCFrame(pos: Vector3, rotDeg: Vector3): CFrame
	return CFrame.new(pos) * CFrame.fromOrientation(
		math.rad(rotDeg.X),
		math.rad(rotDeg.Y),
		math.rad(rotDeg.Z)
	)
end

-- ============================================================================
-- EXACT STUDIO COORDINATES & ORIENTATIONS (YXZ DEGREES)
-- ============================================================================
local POSES = {
	DoorOrigin = toStudioCFrame(Vector3.new(-258.076, 102.018, -30.455), Vector3.new(-90, -90, 0)),
	DoorOpen   = toStudioCFrame(Vector3.new(-258.076, 102.018, -77.145), Vector3.new(-90, -90, 0)),

	BlackHoleTargetScale = 3.804,

	-- Shoulder / Portal pivot inside the Ruins Door
	PortalShoulderPivot = Vector3.new(-245.0, 102.018, -30.455),

	-- 1) Emerge Out of Portal
	Emerge = {
		MainHand = toStudioCFrame(Vector3.new(-198.174, 91.394, -29.243), Vector3.new(18.125, -166.564, -31.134)),
		SubHand  = toStudioCFrame(Vector3.new(-179.856, 154.081, -54.716), Vector3.new(18.125, -166.564, -76.133)),
		LowerArm = toStudioCFrame(Vector3.new(-229.323, 133.593, -37.418), Vector3.new(18.125, -166.564, -139.682)),
	},

	-- 2) Raise of Hand (Apex Wind-up)
	Raise = {
		MainHand = toStudioCFrame(Vector3.new(-207.17, 129.235, -39.829), Vector3.new(18.125, -166.564, -76.134)),
		SubHand  = toStudioCFrame(Vector3.new(-207.17, 129.235, -39.829), Vector3.new(18.125, -166.564, -76.134)),
		LowerArm = toStudioCFrame(Vector3.new(-229.323, 133.593, -37.418), Vector3.new(18.125, -166.564, -139.682)),
	},

	-- 3) Hitting Ground (Violent Slam Base Pose)
	HitGround = {
		MainHand = toStudioCFrame(Vector3.new(-218.412, 65.568, -15.716), Vector3.new(18.125, -166.564, 1.374)),
		SubHand  = toStudioCFrame(Vector3.new(-151.714, 61.17, -30.17),   Vector3.new(18.125, -166.564, -88.626)),
		LowerArm = toStudioCFrame(Vector3.new(-220.23, 86.704, -23.81),   Vector3.new(18.125, -166.564, -62.174)),
	}
}

-- ============================================================================
-- KINEMATIC SHOULDER-ANCHORED SOLVER & ANATOMICAL WRIST HINGE
-- ============================================================================
local PORTAL_PIVOT = POSES.PortalShoulderPivot -- Vector3.new(-245.0, 102.018, -30.455)
local BASE_HIT_ARM = POSES.HitGround.LowerArm
local BASE_HIT_SUB = POSES.HitGround.SubHand
local BASE_HIT_MAIN = POSES.HitGround.MainHand

-- Visual anatomical wrist joint locations:
-- LowerArm: size (17.52, 91.09, 24.47), wrist tip is at -Y (-45.54 studs)
-- SubHand:  size (25.07, 55.82, 32.11), wrist base is at +Y (+27.91 studs)
local ARM_WRIST_LOCAL  = Vector3.new(0, -45.54, 0)
local HAND_WRIST_LOCAL = Vector3.new(-5.368, 27.981, 1.308)

local HIT_REL_HAND_TO_ARM = BASE_HIT_ARM:Inverse() * BASE_HIT_SUB
local HIT_REL_MAIN_TO_HAND = BASE_HIT_SUB:Inverse() * BASE_HIT_MAIN

local BASE_RAISE_ARM = POSES.Raise.LowerArm
local BASE_RAISE_SUB = POSES.Raise.SubHand
local BASE_RAISE_MAIN = POSES.Raise.MainHand
local RAISE_REL_HAND_TO_ARM = BASE_RAISE_ARM:Inverse() * BASE_RAISE_SUB
local RAISE_REL_MAIN_TO_HAND = BASE_RAISE_SUB:Inverse() * BASE_RAISE_MAIN

-- Authored strike direction and distance from portal pivot
local AUTHORED_DIR_XZ = Vector3.new(BASE_HIT_SUB.Position.X - PORTAL_PIVOT.X, 0, BASE_HIT_SUB.Position.Z - PORTAL_PIVOT.Z)
local AUTHORED_DIST = AUTHORED_DIR_XZ.Magnitude -- ~93.3 studs
local AUTHORED_YAW = math.atan2(-AUTHORED_DIR_XZ.X, -AUTHORED_DIR_XZ.Z)

-- Calculates the exact shoulder-anchored Raise and HitGround poses for ANY target point
local function computeArticulatedPosesForTarget(circleCenter: Vector3)
	local targetDirXZ = Vector3.new(circleCenter.X - PORTAL_PIVOT.X, 0, circleCenter.Z - PORTAL_PIVOT.Z)
	local targetDist = targetDirXZ.Magnitude
	local targetYaw = math.atan2(-targetDirXZ.X, -targetDirXZ.Z)

	-- 1. Clamp lateral yaw swing to [-22 deg, +22 deg] so the 91-stud arm stays cleanly
	-- inside the portal doorway and never slices sideways through the stone pillar columns.
	local deltaYaw = math.atan2(math.sin(targetYaw - AUTHORED_YAW), math.cos(targetYaw - AUTHORED_YAW))
	deltaYaw = math.clamp(deltaYaw, math.rad(-22), math.rad(22))

	-- 2. Clamp target reach distance to natural anatomical reach [0.75, 1.15] (70 to 108 studs).
	-- Applies a controlled telescoping offset along the strike ray so the proximal shoulder tip
	-- ALWAYS remains rooted inside the black hole portal opening!
	local reachFactor = math.clamp(targetDist / math.max(AUTHORED_DIST, 1), 0.75, 1.15)
	local aimUnit = (targetDist > 0.001) and (targetDirXZ / targetDist) or Vector3.new(1, 0, 0)
	local extensionOffset = aimUnit * ((reachFactor - 1.0) * AUTHORED_DIST * 0.5)

	-- 3. Shoulder-Rooted Ground Impact Pose (Rigid wrist = 0.00 studs separation anywhere)
	local hitPivotCF = CFrame.new(PORTAL_PIVOT) * CFrame.Angles(0, deltaYaw, 0) * CFrame.new(-PORTAL_PIVOT)
	local solvedHitArm = (hitPivotCF * BASE_HIT_ARM) + extensionOffset
	local solvedHitSub = solvedHitArm * HIT_REL_HAND_TO_ARM
	local solvedHitMain = solvedHitSub * HIT_REL_MAIN_TO_HAND

	local dynamicHitPose = {
		LowerArm = solvedHitArm,
		SubHand  = solvedHitSub,
		MainHand = solvedHitMain,
	}

	-- 4. Shoulder-Rooted Raise / Apex Wind-up Pose (Rotates arm toward target from portal hinge)
	local raisePivotCF = CFrame.new(PORTAL_PIVOT) * CFrame.Angles(0, deltaYaw * 0.60, 0) * CFrame.new(-PORTAL_PIVOT)
	local solvedRaiseArm = raisePivotCF * BASE_RAISE_ARM
	local solvedRaiseSub = solvedRaiseArm * RAISE_REL_HAND_TO_ARM
	local solvedRaiseMain = solvedRaiseSub * RAISE_REL_MAIN_TO_HAND

	local dynamicRaisePose = {
		LowerArm = solvedRaiseArm,
		SubHand  = solvedRaiseSub,
		MainHand = solvedRaiseMain,
	}

	return dynamicRaisePose, dynamicHitPose
end

-- ============================================================================
-- CALL THIS AT THE START OF EVERY NEW GAME TO FIX HP STUCK AT 0!
-- ============================================================================
function RuinsDoorHandManager.ResetAllPlayersForNewGame()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		-- If player died in Game 1, respawn them cleanly for Game 2
		if not char or not hum or hum.Health <= 0 then
			player:LoadCharacter()
			char = player.Character or player.CharacterAdded:Wait()
			hum = char:WaitForChild("Humanoid", 5)
		end

		if hum then
			hum.MaxHealth = 100
			hum.Health = hum.MaxHealth
		end

		-- Reset any custom HP/round attributes used by Bid-to-survive
		player:SetAttribute("HP", 100)
		player:SetAttribute("Health", 100)
		player:SetAttribute("LostBet", nil)
	end

	-- Force all Client HUDs to re-bind and fill HP + Energy to 100%
	ResetHUDRemote:FireAllClients()
end

local DANGER_CIRCLE_RATIO = 0.80

-- ============================================================================
-- DYNAMIC WORKSPACE RESOLUTION
-- ============================================================================
local function resolveHazardInstances()
	local ruinsDoor = Workspace:FindFirstChild("Ruins door") or Workspace:FindFirstChild("RuinsDoor")
	local doorSlide: BasePart? = nil
	local blackHole: Instance? = nil

	if ruinsDoor then
		doorSlide = ruinsDoor:FindFirstChild("doorSlide", true) :: BasePart?
		blackHole = ruinsDoor:FindFirstChild("Blackhole", true)
			or ruinsDoor:FindFirstChild("BlackHole", true)
			or ruinsDoor:FindFirstChild("black hole", true)
	end

	-- Ensure Blackhole parts are strictly anchored and non-colliding
	if blackHole then
		for _, d in ipairs(blackHole:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
	end

	-- Resolve Hand model and its articulated parts
	local handModel = (ruinsDoor and (ruinsDoor:FindFirstChild("hand", true) or ruinsDoor:FindFirstChild("Hand", true)))
		or Workspace:FindFirstChild("hand")
		or Workspace:FindFirstChild("Hand")

	local subHand: BasePart? = nil
	local lowerArm: BasePart? = nil
	local mainHandPart: BasePart? = nil

	if handModel then
		subHand = (handModel:FindFirstChild("LeftHand") or handModel:FindFirstChild("Hand") or handModel:FindFirstChild("hand")) :: BasePart?
		lowerArm = (handModel:FindFirstChild("LeftLowerArm") or handModel:FindFirstChild("LowerArm") or handModel:FindFirstChild("lowerarm") or handModel:FindFirstChild("lower arm")) :: BasePart?
		
		local candidateMain = handModel:FindFirstChild("MainHand") or handModel:FindFirstChild("UpperArm") or handModel:FindFirstChild("LeftUpperArm")
		if candidateMain and candidateMain:IsA("BasePart") then
			mainHandPart = candidateMain
		elseif handModel:IsA("BasePart") and handModel ~= subHand and handModel ~= lowerArm then
			mainHandPart = handModel
		end
	end

	if not subHand then
		subHand = Workspace:FindFirstChild("LeftHand", true) :: BasePart?
	end
	if not lowerArm then
		lowerArm = (Workspace:FindFirstChild("LeftLowerArm", true) or Workspace:FindFirstChild("LowerArm", true)) :: BasePart?
	end

	return ruinsDoor, doorSlide, blackHole, handModel, subHand, lowerArm, mainHandPart
end

-- Helper: Computes GameplayArea Walkway Bounds, Top Surface Y, Size, Color, and Material
local function getGameplayAreaBounds(): (Vector3, Vector3, Color3, Enum.Material)
	local map = Workspace:FindFirstChild("BidToSurviveMap")
	local gameplayArea = (map and map:FindFirstChild("GameplayArea"))
		or Workspace:FindFirstChild("GameplayArea")
		or Workspace:FindFirstChild("Arena")

	local walkway = (gameplayArea and gameplayArea:FindFirstChild("Walkway", true))
		or Workspace:FindFirstChild("Walkway", true)

	if walkway and walkway:IsA("BasePart") then
		local topY = walkway.Position.Y + (walkway.Size.Y * 0.5)
		return Vector3.new(walkway.Position.X, topY, walkway.Position.Z), walkway.Size, walkway.Color, walkway.Material
	elseif gameplayArea and gameplayArea:IsA("BasePart") then
		local topY = gameplayArea.Position.Y + (gameplayArea.Size.Y * 0.5)
		return Vector3.new(gameplayArea.Position.X, topY, gameplayArea.Position.Z), gameplayArea.Size, gameplayArea.Color, gameplayArea.Material
	elseif gameplayArea and gameplayArea:IsA("Model") then
		local cf, size = gameplayArea:GetBoundingBox()
		local basePart = gameplayArea.PrimaryPart or gameplayArea:FindFirstChildWhichIsA("BasePart", true)
		local topY = cf.Position.Y + (size.Y * 0.5)
		local color = basePart and basePart.Color or Color3.fromRGB(58, 125, 21)
		local mat = basePart and basePart.Material or Enum.Material.Plastic
		return Vector3.new(cf.Position.X, topY, cf.Position.Z), size, color, mat
	end

	-- Absolute studio fallback coordinates
	return Vector3.new(-161.53, 58.65, -24.93), Vector3.new(140, 1, 140), Color3.fromRGB(58, 125, 21), Enum.Material.Plastic
end

-- Helper: Reads a player's betting metrics from custom data table, attributes, or leaderstats
local function getPlayerBettingData(player: Player, customDataMap: any?)
	if customDataMap then
		local uid = player.UserId
		local d = customDataMap[uid] or customDataMap[player]
		if d then
			return d.Money or d.Wallet or 0, d.CurrentBid or d.Bid or 0, d.SubmitTime or d.BetTime or 10.0, d.LostBet
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local walletObj = leaderstats and (leaderstats:FindFirstChild("Wallet") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Cash"))
	local bidObj = leaderstats and (leaderstats:FindFirstChild("Bid") or leaderstats:FindFirstChild("CurrentBid"))

	local wallet = player:GetAttribute("Wallet") or player:GetAttribute("Money") or (walletObj and walletObj.Value) or 0
	local bid = player:GetAttribute("CurrentBid") or player:GetAttribute("Bid") or (bidObj and bidObj.Value) or 0
	local betTime = player:GetAttribute("SubmitTime") or player:GetAttribute("BetTime") or 10.0
	local explicitLostBet = player:GetAttribute("LostBet")

	return wallet, bid, betTime, explicitLostBet
end

-- ============================================================================
-- LEADERBOARD-MATCHED TARGETING:
-- 1. Bottom 50% Bet Losers
-- 2. Primary: Highest Wallet Money
-- 3. Tie-breaker: Fastest Bet Timestamp (lowest SubmitTime)
-- ============================================================================
function RuinsDoorHandManager.CalculateTargetDangerCircle(customPlayerData: any?): (Vector3, number, Color3, Enum.Material, any?)
	local arenaCenter, arenaSize, floorColor, floorMat = getGameplayAreaBounds()
	local arenaSpan = math.min(arenaSize.X, arenaSize.Z)

	-- 80% Danger Circle Radius
	local circleRadius = (arenaSpan * DANGER_CIRCLE_RATIO) * 0.5

	local activeEntries = {}

	if customPlayerData and typeof(customPlayerData) == "table" then
		for id, data in pairs(customPlayerData) do
			if typeof(data) == "table" and data.IsAlive and not data.IsAFK and (data.ParticipationState == nil or data.ParticipationState == "Active") then
				local char = data.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					local wallet = data.Money or data.Wallet or 0
					local bid = data.CurrentBid or data.Bid or 0
					local betTime = data.SubmitTime or data.BetTime or 10.0
					local explicitLostBet = data.LostBet
					table.insert(activeEntries, {
						Player = (typeof(id) == "number" and id > 0) and Players:GetPlayerByUserId(id) or char,
						UserId = id,
						Character = char,
						Root = root,
						Wallet = wallet,
						Bid = bid,
						BetTime = betTime,
						LostBet = explicitLostBet,
					})
				end
			end
		end
	end

	if #activeEntries == 0 then
		for _, player in ipairs(Players:GetPlayers()) do
			if not player:GetAttribute("IsAFK") then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					local wallet, bid, betTime, explicitLostBet = getPlayerBettingData(player, customPlayerData)
					table.insert(activeEntries, {
						Player = player,
						UserId = player.UserId,
						Character = char,
						Root = root,
						Wallet = wallet,
						Bid = bid,
						BetTime = betTime,
						LostBet = explicitLostBet,
					})
				end
			end
		end
	end

	if #activeEntries == 0 then
		return arenaCenter, circleRadius, floorColor, floorMat, nil
	end

	-- 1. Isolate the 50% who lost the bet
	local betLosers = {}
	for _, entry in ipairs(activeEntries) do
		if entry.LostBet == true then
			table.insert(betLosers, entry)
		end
	end

	if #betLosers == 0 then
		-- Sort by Bid ascending (lowest bid loses; later bet loses tie)
		table.sort(activeEntries, function(a, b)
			if math.abs(a.Bid - b.Bid) > 0.001 then
				return a.Bid < b.Bid
			end
			return a.BetTime > b.BetTime
		end)

		local loserCount = math.max(1, math.ceil(#activeEntries * 0.5))
		for i = 1, loserCount do
			table.insert(betLosers, activeEntries[i])
		end
	end

	-- 2. Among Bet Losers: Rank by HIGHEST WALLET MONEY
	-- Tie-breaker: FASTEST BET TIMESTAMP (lowest BetTime wins tie)
	table.sort(betLosers, function(a, b)
		if math.abs(a.Wallet - b.Wallet) > 0.001 then
			return a.Wallet > b.Wallet
		end
		return a.BetTime < b.BetTime
	end)

	local primaryTarget = betLosers[1]
	local targetPos = primaryTarget.Root.Position

	-- Clamp circle so at least ~20% of the arena floor remains safe on the opposite side
	local maxOffsetX = (arenaSize.X * 0.5) - (circleRadius * 0.45)
	local maxOffsetZ = (arenaSize.Z * 0.5) - (circleRadius * 0.45)

	local clampedX = math.clamp(targetPos.X, arenaCenter.X - maxOffsetX, arenaCenter.X + maxOffsetX)
	local clampedZ = math.clamp(targetPos.Z, arenaCenter.Z - maxOffsetZ, arenaCenter.Z + maxOffsetZ)

	local finalCircleCenter = Vector3.new(clampedX, arenaCenter.Y, clampedZ)
	return finalCircleCenter, circleRadius, floorColor, floorMat, primaryTarget.Player or primaryTarget.Character
end

-- Attaches pulsing overhead "GREEDY TARGET" marker during the 2.20s Stalking Phase
local function markGreedyTargetPlayer(targetPlayer: any?, stalkDuration: number)
	if not targetPlayer then return end
	local character = (typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player")) and targetPlayer.Character or targetPlayer
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local existing = head:FindFirstChild("GreedyTargetMarker")
	if existing then existing:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "GreedyTargetMarker"
	bb.Size = UDim2.new(0, 190, 0, 52)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "⚠ TARGET LOCKED ⚠\n[RUN AWAY FROM THEM!]"
	label.TextColor3 = Color3.fromRGB(255, 45, 55)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = bb

	task.delay(stalkDuration, function()
		if bb.Parent then bb:Destroy() end
	end)
end

-- ============================================================================
-- TWEEN & SCALE HELPERS
-- ============================================================================
local function tweenObjectCFrame(instance: Instance?, targetCFrame: CFrame, tweenInfo: TweenInfo): Tween?
	if not instance then return nil end

	if instance:IsA("BasePart") then
		instance.Anchored = true
		local tween = TweenService:Create(instance, tweenInfo, { CFrame = targetCFrame })
		tween:Play()
		return tween
	elseif instance:IsA("Model") then
		local cfValue = Instance.new("CFrameValue")
		cfValue.Value = instance:GetPivot()
		local conn = cfValue.Changed:Connect(function(newCF)
			instance:PivotTo(newCF)
		end)
		local tween = TweenService:Create(cfValue, tweenInfo, { Value = targetCFrame })
		tween.Completed:Once(function()
			conn:Disconnect()
			cfValue:Destroy()
		end)
		tween:Play()
		return tween
	end
	return nil
end

local function setBlackholeParticlesEnabled(bhInstance: Instance?, enabled: boolean)
	if not bhInstance then return end
	for _, desc in ipairs(bhInstance:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = enabled
		end
	end
end

local function tweenBlackHoleScale(bhInstance: Instance?, startScale: number, endScale: number, duration: number, easingStyle: Enum.EasingStyle, easingDir: Enum.EasingDirection?)
	if not bhInstance then return end
	local safeStart = math.max(startScale, 0.001)
	local safeEnd = math.max(endScale, 0.001)
	local direction = easingDir or Enum.EasingDirection.Out
	local startTime = os.clock()
	local isExpanding = (safeEnd > safeStart)
	local lastEmit = 0

	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local alpha = TweenService:GetValue(progress, easingStyle, direction)
		local currentScale = safeStart + (safeEnd - safeStart) * alpha
		local safeScale = math.max(currentScale, 0.001)

		if bhInstance:IsA("Model") then
			bhInstance:ScaleTo(safeScale)
		elseif bhInstance:IsA("BasePart") then
			local mesh = bhInstance:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.Scale = Vector3.new(safeScale, safeScale, safeScale)
			end
		end

		if isExpanding and (elapsed - lastEmit >= 0.18) then
			lastEmit = elapsed
			for _, desc in ipairs(bhInstance:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then
					desc:Emit(1)
				end
			end
		end

		if progress >= 1 then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if isExpanding then
				for _, desc in ipairs(bhInstance:GetDescendants()) do
					if desc:IsA("ParticleEmitter") then
						desc:Emit(3)
					end
				end
			else
				for _, desc in ipairs(bhInstance:GetDescendants()) do
					if desc:IsA("ParticleEmitter") then
						desc:Clear()
					end
				end
			end
		end
	end)
end

local function setHandPartsState(subHand: BasePart?, lowerArm: BasePart?, mainHandPart: BasePart?, isVisible: boolean)
	local parts = { subHand, lowerArm, mainHandPart }
	for _, part in ipairs(parts) do
		if part and part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = isVisible and 0 or 1
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("RigidConstraint") then
					child.Enabled = not isVisible
				end
			end
		end
	end
end

local function setDoorBlockerVisibility(ruinsDoor: Instance?, isOpen: boolean)
	if not ruinsDoor then return end
	for _, desc in ipairs(ruinsDoor:GetDescendants()) do
		local nameLower = desc.Name:lower()
		if nameLower:find("partinvinciblewhenopening") or nameLower:find("partinvisiblewhenopening") then
			if desc:IsA("BasePart") then
				desc.Transparency = isOpen and 1 or 0
				desc.CanCollide = not isOpen
			end
		end
	end
end

local function tweenHandPose(subHand: BasePart?, lowerArm: BasePart?, mainHandPart: BasePart?, poseTable: any, tweenInfo: TweenInfo): Tween?
	local t1 = mainHandPart and tweenObjectCFrame(mainHandPart, poseTable.MainHand, tweenInfo) or nil
	local t2 = subHand and tweenObjectCFrame(subHand, poseTable.SubHand, tweenInfo) or nil
	local t3 = lowerArm and tweenObjectCFrame(lowerArm, poseTable.LowerArm, tweenInfo) or nil
	return t2 or t3 or t1
end

-- Kinematic Arm & Hand Driver: Pins the wrist attachment point of SubHand to LowerArm
-- on every single Heartbeat frame, eliminating linear tween chord separation mid-swing!
local function tweenArticulatedArm(
	subHand: BasePart?,
	lowerArm: BasePart?,
	mainHandPart: BasePart?,
	targetPose: any,
	tweenInfo: TweenInfo
): Tween?
	if not lowerArm or not subHand then
		return tweenHandPose(subHand, lowerArm, mainHandPart, targetPose, tweenInfo)
	end

	local startArmCF = lowerArm.CFrame
	local targetArmCF = targetPose.LowerArm
	local startSubCF = subHand.CFrame
	local targetSubCF = targetPose.SubHand

	local startRelRot = startArmCF.Rotation:Inverse() * startSubCF.Rotation
	local targetRelRot = targetArmCF.Rotation:Inverse() * targetSubCF.Rotation

	local armTween = tweenObjectCFrame(lowerArm, targetArmCF, tweenInfo)
	if not armTween then return nil end

	local startTime = os.clock()
	local duration = tweenInfo.Time
	local style = tweenInfo.EasingStyle
	local dir = tweenInfo.EasingDirection

	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if not lowerArm or not lowerArm.Parent or not subHand or not subHand.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local elapsed = os.clock() - startTime
		local progress = math.clamp(elapsed / math.max(duration, 0.001), 0, 1)
		local alpha = TweenService:GetValue(progress, style, dir)

		local curArmCF = lowerArm.CFrame
		local curRelRot = startRelRot:Lerp(targetRelRot, alpha)
		local armWristWorld = curArmCF:PointToWorldSpace(ARM_WRIST_LOCAL)
		local curSubCF = CFrame.new(armWristWorld) * (curArmCF.Rotation * curRelRot) * CFrame.new(-HAND_WRIST_LOCAL)

		subHand.CFrame = curSubCF
		if mainHandPart and targetPose.MainHand then
			mainHandPart.CFrame = curSubCF * HIT_REL_MAIN_TO_HAND
		end
	end)

	armTween.Completed:Once(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if subHand then subHand.CFrame = targetPose.SubHand end
		if mainHandPart and targetPose.MainHand then mainHandPart.CFrame = targetPose.MainHand end
	end)

	return armTween
end

-- ============================================================================
-- AUTHORITATIVE SEQUENCE EXECUTION
-- ============================================================================
local isSequenceActive = false

function RuinsDoorHandManager.ExecuteSequenceAndDamage(
	damageAmountOrCallback: any?,
	customPlayerData: any?,
	setDoorPartsVisibilityCallback: ((isOpen: boolean) -> ())?
)
	if isSequenceActive then
		warn("[RuinsDoorHandManager] Sequence already active! Bypassing duplicate call.")
		return
	end
	isSequenceActive = true

	local success, err = pcall(function()
		local ruinsDoor, doorSlide, blackHole, handModel, subHand, lowerArm, mainHandPart = resolveHazardInstances()

		print("[RuinsDoorHandManager] Starting 5-Stage Cinematic Sequence...")

		if setDoorPartsVisibilityCallback then
			setDoorPartsVisibilityCallback(true)
		else
			setDoorBlockerVisibility(ruinsDoor, true)
		end

		setBlackholeParticlesEnabled(blackHole, false)
		if blackHole and blackHole:IsA("Model") then
			blackHole:ScaleTo(0.001)
		end

		if doorSlide then
			doorSlide.CFrame = POSES.DoorOrigin
		end

		-- Pre-calculate initial target candidate for Stalking phase marker
		local initialCenter, initialRadius, floorColor, floorMat, stalkTarget =
			RuinsDoorHandManager.CalculateTargetDangerCircle(customPlayerData)

		-- ------------------------------------------------------------------------
		-- STAGE 1: DOOR SLIDE & BLACK HOLE EXPANSION (1.35s) - STALKING PHASE
		-- ------------------------------------------------------------------------
		local doorOpenTime = 1.35

		if RunService:IsRunning() and RunService:IsServer() then
			PortalRemote:FireAllClients(true, doorOpenTime, POSES.BlackHoleTargetScale)
		end

		-- Mark the #1 Greedy Bet Loser so everyone scatters away from them!
		markGreedyTargetPlayer(stalkTarget, 2.20)

		local doorTween = tweenObjectCFrame(
			doorSlide,
			POSES.DoorOpen,
			TweenInfo.new(doorOpenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		)

		setBlackholeParticlesEnabled(blackHole, true)
		tweenBlackHoleScale(blackHole, 0.001, POSES.BlackHoleTargetScale, doorOpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		if doorTween then doorTween.Completed:Wait() else task.wait(doorOpenTime) end

		-- ------------------------------------------------------------------------
		-- STAGE 2: HAND EMERGES OUT OF PORTAL (0.85s)
		-- ------------------------------------------------------------------------
		setHandPartsState(subHand, lowerArm, mainHandPart, true)

		if subHand then subHand.CFrame = POSES.Emerge.SubHand * CFrame.new(0, 0, 30) end
		if lowerArm then lowerArm.CFrame = POSES.Emerge.LowerArm * CFrame.new(0, 0, 30) end

		local emergeTween = tweenHandPose(
			subHand,
			lowerArm,
			mainHandPart,
			POSES.Emerge,
			TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		)
		if emergeTween then emergeTween.Completed:Wait() else task.wait(0.85) end

		-- ------------------------------------------------------------------------
		-- STAGE 3: HAND RAISE / APEX WIND-UP - HARD LOCK 80% RED CIRCLE
		-- ------------------------------------------------------------------------
		-- Recalculate target position right as hand raises so target cannot pre-run
		local circleCenter, circleRadius, currentFloorColor, currentFloorMat, lockedTarget =
			RuinsDoorHandManager.CalculateTargetDangerCircle(customPlayerData)

		-- Razor-Thin Bottleneck formula: (circleRadius * 0.72) / SPRINT_SPEED
		local lockedWarningTime = math.clamp((circleRadius * 0.72) / 21, 0.90, 1.35)
		local slamTime = 0.22
		local raiseDuration = math.max(0.60, lockedWarningTime - slamTime - 0.12)

		-- Fire 80% Red Warning Circle to all clients NOW!
		if RunService:IsRunning() and RunService:IsServer() then
			TelegraphRemote:FireAllClients(circleCenter, circleRadius, lockedWarningTime, lockedTarget)
		end

		local dynamicRaisePose, dynamicHitPose = computeArticulatedPosesForTarget(circleCenter)

		local raiseTween = tweenArticulatedArm(
			subHand,
			lowerArm,
			mainHandPart,
			dynamicRaisePose,
			TweenInfo.new(raiseDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		)
		if raiseTween then raiseTween.Completed:Wait() else task.wait(raiseDuration) end

		-- Dramatic apex hang-time before plunge
		task.wait(0.12)

		-- ------------------------------------------------------------------------
		-- STAGE 4: GROUND SLAM & SYNCHRONIZED PLAYER DAMAGE (0.22s)
		-- ------------------------------------------------------------------------
		local slamTween = tweenArticulatedArm(
			subHand,
			lowerArm,
			mainHandPart,
			dynamicHitPose,
			TweenInfo.new(slamTime, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
		)
		if slamTween then slamTween.Completed:Wait() else task.wait(slamTime) end

		-- EXACT MILLISECOND OF IMPACT: VFX & DAMAGE CHECK
		local handFootprint = Vector3.new(circleRadius * 2, 14, circleRadius * 2)
		if RunService:IsRunning() and RunService:IsServer() then
			ImpactRemote:FireAllClients(circleCenter, handFootprint, currentFloorColor or floorColor, currentFloorMat or floorMat, circleRadius)
		else
			print(string.format("[RuinsDoorHandManager] Impact at %s (radius=%.1f)", tostring(circleCenter), circleRadius))
		end

		local hitPlayers = {}
		local escapedPlayers = {}

		-- Distance check against 80% Red Circle
		local participantsToCheck = {}
		if customPlayerData and typeof(customPlayerData) == "table" then
			for id, data in pairs(customPlayerData) do
				if typeof(data) == "table" and data.IsAlive and not data.IsAFK then
					local char = data.Character
					local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and hum and hum.Health > 0 then
						local pObj = (typeof(id) == "number" and id > 0) and Players:GetPlayerByUserId(id) or char
						table.insert(participantsToCheck, { Target = pObj, Root = root, Hum = hum })
					end
				end
			end
		end

		if #participantsToCheck == 0 then
			for _, player in ipairs(Players:GetPlayers()) do
				if not player:GetAttribute("IsAFK") then
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and hum and hum.Health > 0 then
						table.insert(participantsToCheck, { Target = player, Root = root, Hum = hum })
					end
				end
			end
		end

		for _, item in ipairs(participantsToCheck) do
			local target = item.Target
			local root = item.Root
			local hum = item.Hum
			local flatVector = Vector3.new(root.Position.X - circleCenter.X, 0, root.Position.Z - circleCenter.Z)
			local flatDist = flatVector.Magnitude

			if flatDist <= circleRadius then
				-- Inside 80% Red Circle: Full Damage!
				table.insert(hitPlayers, target)
				if typeof(damageAmountOrCallback) == "number" then
					hum:TakeDamage(damageAmountOrCallback)
				end
			elseif flatDist <= (circleRadius * 1.15) then
				-- Edge-Grazing Shockwave Wave (escaped by < 15% margin): 0 damage + dive tumble!
				table.insert(escapedPlayers, target)
				local blastDir = (flatDist > 0.1) and flatVector.Unit or Vector3.new(0, 0, 1)
				root.AssemblyLinearVelocity = (blastDir * 58) + Vector3.new(0, 32, 0)
				hum.PlatformStand = true
				task.delay(0.45, function()
					if hum and hum.Health > 0 then
						hum.PlatformStand = false
					end
				end)
			else
				-- Cleanly escaped
				table.insert(escapedPlayers, target)
			end
		end

		if typeof(damageAmountOrCallback) == "function" then
			task.spawn(damageAmountOrCallback, escapedPlayers, hitPlayers)
		end

		print(string.format("[RuinsDoorHandManager] Impact registered! Hit=%d, Escaped=%d (circleRadius=%.1f)", #hitPlayers, #escapedPlayers, circleRadius))

		-- ------------------------------------------------------------------------
		-- STAGE 5: IMPACT HOLD, RETRACT & SEAL (0.75s + 0.65s + 1.0s)
		-- ------------------------------------------------------------------------
		task.wait(0.75)

		local retractTween = tweenArticulatedArm(
			subHand,
			lowerArm,
			mainHandPart,
			POSES.Emerge,
			TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		)
		if retractTween then retractTween.Completed:Wait() else task.wait(0.65) end

		setHandPartsState(subHand, lowerArm, mainHandPart, false)

		if RunService:IsRunning() and RunService:IsServer() then
			PortalRemote:FireAllClients(false, 1.0, 0.001)
		end
		tweenBlackHoleScale(blackHole, POSES.BlackHoleTargetScale, 0.001, 1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

		local closeTween = tweenObjectCFrame(
			doorSlide,
			POSES.DoorOrigin,
			TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		)
		if closeTween then closeTween.Completed:Wait() else task.wait(1.0) end

		setBlackholeParticlesEnabled(blackHole, false)

		if setDoorPartsVisibilityCallback then
			setDoorPartsVisibilityCallback(false)
		else
			setDoorBlockerVisibility(ruinsDoor, false)
		end

		print("[RuinsDoorHandManager] Sequence complete. Door sealed.")
	end)

	isSequenceActive = false
	if not success then
		warn("[RuinsDoorHandManager] Error in sequence execution: " .. tostring(err))
	end
end

RuinsDoorHandManager.POSES = POSES
RuinsDoorHandManager.ResolveInstances = resolveHazardInstances
RuinsDoorHandManager.ResetActiveState = function() isSequenceActive = false end
RuinsDoorHandManager.IsActive = function() return isSequenceActive end

return RuinsDoorHandManager
