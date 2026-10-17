--!strict
-- StarterPlayer/StarterPlayerScripts/RuinsImpactClient.client.luau
-- Authoritative client-side cinematic audio, telegraph, suction, and impact VFX system.
-- Synchronizes the 4 author-provided Workspace sound objects:
-- 1. "Heavy stone door slide" (rbxassetid://83419164428609)
-- 2. "Blackhole Loop" (rbxassetid://1160209243)
-- 3. "Skeleton_Emerge" (rbxassetid://102911549900922)
-- 4. "Skeleton_SlamImpact" (rbxassetid://74149238738530)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Locate RemoteEvents
local Network = ReplicatedStorage:WaitForChild("Network", 8)

local ImpactRemote: RemoteEvent = (Network and Network:WaitForChild("RuinsHandImpactEvent", 8))
	or ReplicatedStorage:WaitForChild("RuinsHandImpactEvent", 8) :: any
if not ImpactRemote then
	local fallback = Instance.new("RemoteEvent")
	fallback.Name = "RuinsHandImpactEvent"
	fallback.Parent = Network or ReplicatedStorage
	ImpactRemote = fallback :: RemoteEvent
end

local PortalRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsPortalEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsPortalEvent") :: any
if not PortalRemote then
	local fallback = Instance.new("RemoteEvent")
	fallback.Name = "RuinsPortalEvent"
	fallback.Parent = Network or ReplicatedStorage
	PortalRemote = fallback :: RemoteEvent
end

local TelegraphRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsTelegraphEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsTelegraphEvent") :: any
if not TelegraphRemote then
	local fallback = Instance.new("RemoteEvent")
	fallback.Name = "RuinsTelegraphEvent"
	fallback.Parent = Network or ReplicatedStorage
	TelegraphRemote = fallback :: RemoteEvent
end

local EmergeRemote: RemoteEvent = (Network and Network:FindFirstChild("RuinsHandEmergeEvent"))
	or ReplicatedStorage:FindFirstChild("RuinsHandEmergeEvent") :: any
if not EmergeRemote then
	local fallback = Instance.new("RemoteEvent")
	fallback.Name = "RuinsHandEmergeEvent"
	fallback.Parent = Network or ReplicatedStorage
	EmergeRemote = fallback :: RemoteEvent
end

-- Lighting ColorCorrection for high-energy impact flash
local impactCC = Lighting:FindFirstChild("RuinsImpactCC") :: ColorCorrectionEffect?
if not impactCC then
	impactCC = Instance.new("ColorCorrectionEffect")
	impactCC.Name = "RuinsImpactCC"
	impactCC.Parent = Lighting
end

-- ============================================================================
-- 1. SOUND TEMPLATES & CLEAN 3D POSITIONAL AUDIO MIX
-- ============================================================================
local SOUND_NAMES = {
	DoorSlide = "Heavy stone door slide",
	BlackholeLoop = "Blackhole Loop",
	HandEmerge = "Skeleton_Emerge",
	SlamImpact = "Skeleton_SlamImpact",
}

-- ============================================================================
-- [USER VOLUME CONTROLS] Modify any of the 4 sound volume values below:
-- ============================================================================
local AUDIO_VOLUMES = {
	DoorSlide     = 1.37,  -- Heavy stone door slide (Opening & Closing)
	BlackholeLoop = 0.20,  -- Blackhole atmospheric loop
	HandEmerge    = 1.69,  -- Skeleton hand emergence
	SlamImpact    = 2.97,  -- Skeleton ground slam impact
}

local function getSoundTemplate(soundName: string): Sound?
	local template = Workspace:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		template = Workspace:FindFirstChild(soundName, true) :: any
	end
	if not template or not template:IsA("Sound") then
		template = Workspace:WaitForChild(soundName, 3) :: any
	end
	if template and template:IsA("Sound") then
		return template
	end
	warn(string.format("[RuinsAudio] Sound template '%s' not found in Workspace!", soundName))
	return nil
end

local activeBlackholeSound: Sound? = nil
local activeBlackholeFadeTween: Tween? = nil
local activeDoorSound: Sound? = nil
local activeEmergeSound: Sound? = nil
local sequenceStartTime: number = 0

local function cleanupActiveAudio()
	if activeBlackholeFadeTween then
		activeBlackholeFadeTween:Cancel()
		activeBlackholeFadeTween = nil
	end
	if activeBlackholeSound then
		pcall(function()
			activeBlackholeSound:Stop()
			activeBlackholeSound:Destroy()
		end)
		activeBlackholeSound = nil
	end
	if activeDoorSound then
		pcall(function()
			activeDoorSound:Stop()
			activeDoorSound:Destroy()
		end)
		activeDoorSound = nil
	end
	if activeEmergeSound then
		pcall(function()
			activeEmergeSound:Stop()
			activeEmergeSound:Destroy()
		end)
		activeEmergeSound = nil
	end
end

local function resolveRuinsInstances(): (BasePart?, Model?, BasePart?)
	local map = Workspace:FindFirstChild("BidToSurviveMap")
	local ruinsDoor = (map and (map:FindFirstChild("Ruins door") or map:FindFirstChild("RuinsDoor")))
		or Workspace:FindFirstChild("Ruins door")
		or Workspace:FindFirstChild("RuinsDoor")
		or Workspace:FindFirstChild("Ruins door", true)

	local doorSlide: BasePart? = nil
	local blackHole: Model? = nil
	local mainPart: BasePart? = nil

	if ruinsDoor then
		doorSlide = (ruinsDoor:FindFirstChild("doorSlide", true) or ruinsDoor:FindFirstChild("DoorSlide", true)) :: BasePart?
		local bh = ruinsDoor:FindFirstChild("Blackhole", true) or ruinsDoor:FindFirstChild("BlackHole", true)
		if bh and bh:IsA("Model") then
			blackHole = bh
			mainPart = (bh:FindFirstChild("Main") or bh.PrimaryPart or bh:FindFirstChildWhichIsA("BasePart", true)) :: BasePart?
		end
	end

	return doorSlide, blackHole, mainPart
end

local function playDoorSlideAudio(doorSlide: BasePart?, isOpening: boolean)
	local template = getSoundTemplate(SOUND_NAMES.DoorSlide)
	if not template then return end

	if activeDoorSound then
		pcall(function()
			activeDoorSound:Stop()
			activeDoorSound:Destroy()
		end)
		activeDoorSound = nil
	end

	local s = template:Clone()
	s.Name = isOpening and "RuinsDoorSlide_Open" or "RuinsDoorSlide_Close"
	s.Volume = AUDIO_VOLUMES.DoorSlide
	s.PlaybackSpeed = isOpening and 1.0 or 0.96
	s.Looped = false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 25
	s.RollOffMaxDistance = 450

	if doorSlide then
		s.Parent = doorSlide
	else
		local att = Instance.new("Attachment")
		att.WorldPosition = Vector3.new(-258.08, 112.78, -30.45)
		att.Parent = Workspace.Terrain
		s.Parent = att
	end

	activeDoorSound = s
	s:Play()

	s.Ended:Once(function()
		if activeDoorSound == s then
			activeDoorSound = nil
		end
		s:Destroy()
	end)
end

local function startBlackholeLoopAudio(mainPart: BasePart?)
	local template = getSoundTemplate(SOUND_NAMES.BlackholeLoop)
	if not template then return end

	if activeBlackholeFadeTween then
		activeBlackholeFadeTween:Cancel()
		activeBlackholeFadeTween = nil
	end

	if activeBlackholeSound then
		pcall(function()
			activeBlackholeSound:Stop()
			activeBlackholeSound:Destroy()
		end)
		activeBlackholeSound = nil
	end

	local s = template:Clone()
	s.Name = "RuinsBlackholeLoop_Active"
	s.Volume = AUDIO_VOLUMES.BlackholeLoop
	s.PlaybackSpeed = 1.0
	s.Looped = false -- Play black hole sound exactly 1 time
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 350

	if mainPart then
		s.Parent = mainPart
	else
		local att = Instance.new("Attachment")
		att.WorldPosition = Vector3.new(-266.31, 112.78, -30.45)
		att.Parent = Workspace.Terrain
		s.Parent = att
	end

	activeBlackholeSound = s
	s:Play()
	s.Ended:Once(function()
		if activeBlackholeSound == s then
			activeBlackholeSound = nil
		end
		s:Destroy()
	end)
end

local function stopBlackholeLoopAudio(fadeDuration: number?)
	local s = activeBlackholeSound
	if not s or not s.IsPlaying then
		if s then
			pcall(function() s:Destroy() end)
			activeBlackholeSound = nil
		end
		return
	end

	local duration = math.clamp(fadeDuration or 0.28, 0.20, 0.35)
	if activeBlackholeFadeTween then
		activeBlackholeFadeTween:Cancel()
		activeBlackholeFadeTween = nil
	end

	local tween = TweenService:Create(s, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Volume = 0
	})
	activeBlackholeFadeTween = tween

	tween.Completed:Once(function()
		if activeBlackholeSound == s then
			activeBlackholeSound = nil
		end
		pcall(function()
			s:Stop()
			s:Destroy()
		end)
		if activeBlackholeFadeTween == tween then
			activeBlackholeFadeTween = nil
		end
	end)
	tween:Play()
end

local function playHandEmergeAudio(emergencePos: Vector3)
	local template = getSoundTemplate(SOUND_NAMES.HandEmerge)
	if not template then return end

	if activeEmergeSound then
		pcall(function()
			activeEmergeSound:Stop()
			activeEmergeSound:Destroy()
		end)
		activeEmergeSound = nil
	end

	local att = Instance.new("Attachment")
	att.Name = "RuinsEmergeAudioAttachment"
	att.WorldPosition = emergencePos
	att.Parent = Workspace.Terrain

	local s = template:Clone()
	s.Name = "RuinsHandEmerge_Active"
	s.Volume = AUDIO_VOLUMES.HandEmerge
	s.PlaybackSpeed = 1.0
	s.Looped = false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 25
	s.RollOffMaxDistance = 450
	s.Parent = att

	activeEmergeSound = s
	s:Play()

	s.Ended:Once(function()
		if activeEmergeSound == s then
			activeEmergeSound = nil
		end
		s:Destroy()
		att:Destroy()
	end)

	task.delay(s.TimeLength + 0.5, function()
		if att.Parent then
			att:Destroy()
		end
	end)
end

local function playSlamImpactAudio(impactPos: Vector3)
	local template = getSoundTemplate(SOUND_NAMES.SlamImpact)
	if not template then return end

	local att = Instance.new("Attachment")
	att.Name = "RuinsImpactAudioAttachment"
	att.WorldPosition = impactPos
	att.Parent = Workspace.Terrain

	local s = template:Clone()
	s.Name = "RuinsSlamImpact_Active"
	s.Volume = AUDIO_VOLUMES.SlamImpact
	s.PlaybackSpeed = 1.0
	s.Looped = false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 35
	s.RollOffMaxDistance = 550
	s.Parent = att

	s:Play()

	s.Ended:Once(function()
		s:Destroy()
		att:Destroy()
	end)

	task.delay(s.TimeLength + 0.5, function()
		if att.Parent then
			att:Destroy()
		end
	end)
end

-- ============================================================================
-- 2. TELEGRAPH RED WARNING CIRCLE & BLACK HOLE SUCTION
-- ============================================================================
local activeSuctionConn: RBXScriptConnection? = nil

local function showRedDangerTelegraph(centerPos: Vector3, radius: number, duration: number, targetedPlayer: Player?)
	local folder = Instance.new("Folder")
	folder.Name = "RedDangerTelegraph"
	folder.Parent = Workspace

	local diameter = radius * 2

	-- A) Translucent Pulsing Red Danger Disc
	local dangerDisc = Instance.new("Part")
	dangerDisc.Name = "DangerFillDisc"
	dangerDisc.Shape = Enum.PartType.Cylinder
	dangerDisc.Anchored = true
	dangerDisc.CanCollide = false
	dangerDisc.CanQuery = false
	dangerDisc.Material = Enum.Material.Neon
	dangerDisc.Color = Color3.fromRGB(255, 30, 45)
	dangerDisc.Transparency = 0.72
	dangerDisc.Size = Vector3.new(0.15, 2, 2)
	dangerDisc.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	dangerDisc.Parent = folder

	TweenService:Create(dangerDisc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, diameter, diameter)
	}):Play()

	-- Urgent transparency pulse until slam
	local pulseCount = math.max(1, math.floor(duration / 0.35))
	TweenService:Create(dangerDisc, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, pulseCount, true), {
		Transparency = 0.45
	}):Play()

	-- B) Outer High-Contrast Glowing Boundary Ring
	local boundaryRing = Instance.new("Part")
	boundaryRing.Name = "DangerBoundaryRing"
	boundaryRing.Shape = Enum.PartType.Cylinder
	boundaryRing.Anchored = true
	boundaryRing.CanCollide = false
	boundaryRing.CanQuery = false
	boundaryRing.Material = Enum.Material.Neon
	boundaryRing.Color = Color3.fromRGB(255, 45, 55)
	boundaryRing.Transparency = 0.15
	boundaryRing.Size = Vector3.new(0.20, diameter, diameter)
	boundaryRing.CFrame = CFrame.new(centerPos + Vector3.new(0, 0.10, 0)) * CFrame.Angles(0, 0, math.rad(90))
	boundaryRing.Parent = folder

	-- C) Inner Countdown Timing Ring (Expands from center to edge right as Hand hits!)
	local timingRing = dangerDisc:Clone()
	timingRing.Name = "CountdownFillRing"
	timingRing.Color = Color3.fromRGB(255, 95, 70)
	timingRing.Transparency = 0.35
	timingRing.Size = Vector3.new(0.22, 1, 1)
	timingRing.Parent = folder

	TweenService:Create(timingRing, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.22, diameter, diameter),
		Color = Color3.fromRGB(255, 15, 15),
		Transparency = 0.15
	}):Play()

	-- D) Extra: Black Hole Radial Inward Suction (4.5 studs/sec)
	if activeSuctionConn then
		activeSuctionConn:Disconnect()
		activeSuctionConn = nil
	end

	local PULL_STRENGTH = 4.5
	activeSuctionConn = RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then return end

		local flatOffset = Vector3.new(centerPos.X - root.Position.X, 0, centerPos.Z - root.Position.Z)
		local dist = flatOffset.Magnitude

		if dist > 1.5 and dist <= (radius * 1.15) then
			local pullDir = flatOffset.Unit
			local edgeFactor = math.clamp(dist / radius, 0.55, 1.15)
			root.CFrame = root.CFrame + (pullDir * (PULL_STRENGTH * edgeFactor * dt))
		end
	end)

	task.delay(duration + 0.05, function()
		if activeSuctionConn then
			activeSuctionConn:Disconnect()
			activeSuctionConn = nil
		end
		if folder.Parent then
			folder:Destroy()
		end
	end)
end

-- ============================================================================
-- 3. GROUND SMASH CRATER & CAMERA SHAKE
-- ============================================================================
local function spawnGroundDestruction(impactPos: Vector3, circleRadius: number, floorColor: Color3, floorMaterial: Enum.Material)
	local folder = Instance.new("Folder")
	folder.Name = "HandGroundSmashVFX"
	folder.Parent = Workspace

	local diameter = circleRadius * 2

	-- 1. Crimson & Amber Flash Ring
	local coreRing = Instance.new("Part")
	coreRing.Name = "ImpactCoreRing"
	coreRing.Shape = Enum.PartType.Cylinder
	coreRing.Anchored = true
	coreRing.CanCollide = false
	coreRing.Material = Enum.Material.Neon
	coreRing.Color = Color3.fromRGB(255, 70, 35)
	coreRing.Transparency = 0.1
	coreRing.Size = Vector3.new(0.8, diameter * 0.85, diameter * 0.85)
	coreRing.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	coreRing.Parent = folder

	TweenService:Create(coreRing, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, diameter * 1.15, diameter * 1.15),
		Transparency = 1
	}):Play()

	-- 2. Outer Dust Wave
	local dustRing = coreRing:Clone()
	dustRing.Name = "ImpactDustWave"
	dustRing.Material = Enum.Material.SmoothPlastic
	dustRing.Color = Color3.fromRGB(217, 210, 197)
	dustRing.Transparency = 0.25
	dustRing.Size = Vector3.new(1.8, diameter * 0.90, diameter * 0.90)
	dustRing.Parent = folder

	TweenService:Create(dustRing, TweenInfo.new(0.70, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.25, diameter * 1.35, diameter * 1.35),
		Transparency = 1
	}):Play()

	-- 3. Crater Rim Rock Slabs Along the Perimeter
	local numChunks = 20
	local chunkScale = math.clamp(circleRadius / 16, 1.2, 3.2)

	for i = 1, numChunks do
		local angle = (i / numChunks) * math.pi * 2 + (math.random(-10, 10) * 0.01)
		local rimDist = circleRadius * 0.92
		local spawnOffset = Vector3.new(math.cos(angle) * rimDist, -1.8 * chunkScale, math.sin(angle) * rimDist)
		local targetPos = impactPos + Vector3.new(math.cos(angle) * circleRadius, 0.9 * chunkScale, math.sin(angle) * circleRadius)

		local rock = Instance.new("Part")
		rock.Name = "CraterRimSlab"
		rock.Anchored = true
		rock.CanCollide = false
		rock.Color = floorColor
		rock.Material = floorMaterial
		rock.Size = Vector3.new(
			(math.random(30, 52) / 10) * chunkScale,
			(math.random(16, 30) / 10) * chunkScale,
			(math.random(30, 52) / 10) * chunkScale
		)
		rock.CFrame = CFrame.lookAt(impactPos + spawnOffset, impactPos)
			* CFrame.Angles(math.rad(math.random(-35, 35)), math.rad(math.random(-20, 20)), math.rad(math.random(-25, 25)))
		rock.Parent = folder

		TweenService:Create(rock, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = targetPos
		}):Play()

		task.delay(1.15 + (math.random() * 0.35), function()
			if rock.Parent then
				TweenService:Create(rock, TweenInfo.new(0.50, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = targetPos - Vector3.new(0, 4.5 * chunkScale, 0),
					Transparency = 1
				}):Play()
			end
		end)
	end

	task.delay(2.5, function()
		if folder.Parent then folder:Destroy() end
	end)
end

local function shakeCamera(impactPos: Vector3, circleRadius: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local flatDist = root and Vector2.new(root.Position.X - impactPos.X, root.Position.Z - impactPos.Z).Magnitude or 40
	local wasHit = flatDist <= circleRadius

	local intensity = wasHit and 2.8 or 1.1

	if impactCC then
		impactCC.Contrast = wasHit and 0.45 or 0.15
		impactCC.TintColor = wasHit and Color3.fromRGB(255, 165, 165) or Color3.fromRGB(255, 235, 230)
		TweenService:Create(impactCC, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Contrast = 0,
			TintColor = Color3.fromRGB(255, 255, 255)
		}):Play()
	end

	local defaultFOV = 70
	camera.FieldOfView = math.max(45, defaultFOV - (wasHit and 6.0 or 2.5))
	TweenService:Create(camera, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		FieldOfView = defaultFOV
	}):Play()

	local startTime = os.clock()
	local duration = 0.50
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			if conn then conn:Disconnect() conn = nil end
			return
		end

		local alpha = 1 - (elapsed / duration)
		local damper = alpha * alpha * intensity
		local offset = Vector3.new(
			(math.random() - 0.5) * damper * 0.9,
			(math.random() - 0.5) * damper * 1.1,
			(math.random() - 0.5) * damper * 0.9
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(
			math.rad((math.random() - 0.5) * damper * 2.0),
			math.rad((math.random() - 0.5) * damper * 1.2),
			math.rad((math.random() - 0.5) * damper * 2.0)
		)
	end)
end

-- ============================================================================
-- 4. PORTAL & BLACK HOLE CLIENT ANIMATION (Synchronized Visuals)
-- ============================================================================
local portalConn: RBXScriptConnection? = nil

local function animateClientPortal(isOpen: boolean, duration: number, targetScale: number)
	local doorSlide, bh, mainPart = resolveRuinsInstances()
	if not bh or not bh:IsA("Model") then return end

	for _, d in ipairs(bh:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- Center black hole only on opening using fixed doorway coordinates so it never snaps to the open door position on close!
	if isOpen then
		local FIXED_DOORWAY_Y = 112.776
		local FIXED_DOORWAY_Z = -30.455
		local doorwayCenter = Vector3.new(bh:GetPivot().Position.X, FIXED_DOORWAY_Y, FIXED_DOORWAY_Z)
		bh:PivotTo(CFrame.new(doorwayCenter) * bh:GetPivot().Rotation)
	end

	if portalConn then
		portalConn:Disconnect()
		portalConn = nil
	end

	local startScale = bh:GetScale()
	local endScale = isOpen and targetScale or 0.001
	local easingStyle = isOpen and Enum.EasingStyle.Back or Enum.EasingStyle.Quad
	local easingDir = isOpen and Enum.EasingDirection.Out or Enum.EasingDirection.InOut

	if isOpen then
		for _, d in ipairs(bh:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = true
				d:Clear()
			end
		end
	end

	local startTime = os.clock()
	local lastEmit = 0

	portalConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local alpha = TweenService:GetValue(progress, easingStyle, easingDir)
		local currentScale = math.max(startScale + (endScale - startScale) * alpha, 0.001)

		bh:ScaleTo(currentScale)

		if isOpen and (elapsed - lastEmit >= 0.15) then
			lastEmit = elapsed
			for _, d in ipairs(bh:GetDescendants()) do
				if d:IsA("ParticleEmitter") then
					d:Emit(1)
				end
			end
		end

		if progress >= 1 then
			if portalConn then
				portalConn:Disconnect()
				portalConn = nil
			end

			if isOpen then
				bh:ScaleTo(targetScale)
				for _, d in ipairs(bh:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d:Emit(3)
					end
				end
			else
				bh:ScaleTo(0.001)
				for _, d in ipairs(bh:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = false
						d:Clear()
					end
				end
			end
		end
	end)
end

-- ============================================================================
-- 5. REMOTE EVENT LISTENERS (Authoritative Synchronization)
-- ============================================================================
TelegraphRemote.OnClientEvent:Connect(showRedDangerTelegraph)

PortalRemote.OnClientEvent:Connect(function(isOpen: boolean, duration: number, targetScale: number)
	local doorSlide, bh, mainPart = resolveRuinsInstances()
	local animDuration = duration or (isOpen and 1.35 or 1.0)
	local finalScale = targetScale or (isOpen and 5.0 or 0.001)

	if isOpen then
		-- Phase 1 & 2: Clean up any previous round audio and start synchronized opening
		cleanupActiveAudio()
		sequenceStartTime = os.clock()

		print(string.format("[RuinsAudio] [T+0.00s] Door opening: Heavy stone door slide & Blackhole Loop started (duration=%.2fs, scale=%.1f)", animDuration, finalScale))
		playDoorSlideAudio(doorSlide, true)
		startBlackholeLoopAudio(mainPart)
		animateClientPortal(true, animDuration, finalScale)
	else
		-- Phase 3: Portal closing, loop audio fades out over ~0.28s, door closing replay
		local elapsed = (sequenceStartTime > 0) and (os.clock() - sequenceStartTime) or 0
		print(string.format("[RuinsAudio] [T+%.2fs] Portal closing: Blackhole Loop fading out, Heavy stone door slide replay (duration=%.2fs)", elapsed, animDuration))
		stopBlackholeLoopAudio(0.28)
		playDoorSlideAudio(doorSlide, false)
		animateClientPortal(false, animDuration, 0.001)
	end
end)

EmergeRemote.OnClientEvent:Connect(function(emergencePos: Vector3, duration: number)
	local elapsed = (sequenceStartTime > 0) and (os.clock() - sequenceStartTime) or 0
	print(string.format("[RuinsAudio] [T+%.2fs] Hand emergence: Skeleton_Emerge triggered at %s", elapsed, tostring(emergencePos)))
	playHandEmergeAudio(emergencePos)
end)

ImpactRemote.OnClientEvent:Connect(function(impactPos, handSize, floorColor, floorMaterial, circleRadius)
	local elapsed = (sequenceStartTime > 0) and (os.clock() - sequenceStartTime) or 0
	local radius = circleRadius or (math.max(handSize.X, handSize.Z) * 0.5)

	print(string.format("[RuinsAudio] [T+%.2fs] Ground impact: Skeleton_SlamImpact triggered at %s (radius=%.1f)", elapsed, tostring(impactPos), radius))
	playSlamImpactAudio(impactPos)
	spawnGroundDestruction(impactPos, radius, floorColor or Color3.fromRGB(58, 125, 21), floorMaterial or Enum.Material.Plastic)
	shakeCamera(impactPos, radius)
end)

print("[RuinsImpactClient] Professional 3D Audio System loaded with 4 Workspace sound templates.")
