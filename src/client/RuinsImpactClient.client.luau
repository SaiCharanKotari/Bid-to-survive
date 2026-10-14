--!strict
-- StarterPlayer/StarterPlayerScripts/RuinsImpactClient.client.luau
-- Client-side 80% Red Danger Zone Telegraph, Black Hole inward suction,
-- portal animation, and hand slam impact VFX system.

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

-- Lighting ColorCorrection for high-energy impact flash
local impactCC = Lighting:FindFirstChild("RuinsImpactCC") :: ColorCorrectionEffect?
if not impactCC then
	impactCC = Instance.new("ColorCorrectionEffect")
	impactCC.Name = "RuinsImpactCC"
	impactCC.Parent = Lighting
end

-- ============================================================================
-- 1. TELEGRAPH RED WARNING CIRCLE & BLACK HOLE SUCTION
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

	-- D) Extra 1: Black Hole Radial Inward Suction (4.5 studs/sec)
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
-- 2. HAND SLAM IMPACT VFX
-- ============================================================================
local function playSlamAudio(impactPos: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = impactPos
	attachment.Parent = Workspace.Terrain

	local slamSound = Instance.new("Sound")
	slamSound.Name = "RuinsEarthquakeSlam"
	slamSound.SoundId = "rbxassetid://9120386436"
	slamSound.Volume = 2.8
	slamSound.PlaybackSpeed = 0.78
	slamSound.RollOffMaxDistance = 450
	slamSound.RollOffMode = Enum.RollOffMode.InverseTapered
	slamSound.Parent = attachment
	slamSound:Play()

	local debrisSound = Instance.new("Sound")
	debrisSound.Name = "RuinsDebrisCrunch"
	debrisSound.SoundId = "rbxassetid://9120386436"
	debrisSound.Volume = 1.4
	debrisSound.PlaybackSpeed = 1.35
	debrisSound.RollOffMaxDistance = 350
	debrisSound.RollOffMode = Enum.RollOffMode.InverseTapered
	debrisSound.Parent = attachment
	debrisSound:Play()

	task.delay(4.5, function()
		attachment:Destroy()
	end)
end

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

	-- 3. Crater Rim Rock Slabs Along the 80% Circle Perimeter
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
-- 3. PORTAL & BLACK HOLE CLIENT ANIMATION
-- ============================================================================
local portalConn: RBXScriptConnection? = nil

local function animateClientPortal(isOpen: boolean, duration: number, targetScale: number)
	local ruinsDoor = Workspace:FindFirstChild("Ruins door") or Workspace:FindFirstChild("RuinsDoor")
	if not ruinsDoor then return end
	local bh = ruinsDoor:FindFirstChild("Blackhole", true) or ruinsDoor:FindFirstChild("BlackHole", true)
	if not bh or not bh:IsA("Model") then return end

	for _, d in ipairs(bh:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
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

		local mainPart = bh:FindFirstChild("Main")
		if mainPart and mainPart:IsA("BasePart") then
			local sound = Instance.new("Sound")
			sound.Name = "RuinsPortalOpenAudio"
			sound.SoundId = "rbxassetid://9120386436"
			sound.Volume = 1.6
			sound.PlaybackSpeed = 1.45
			sound.RollOffMaxDistance = 350
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.Parent = mainPart
			sound:Play()
			task.delay(4, function() sound:Destroy() end)
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
-- REMOTE EVENT LISTENERS
-- ============================================================================
TelegraphRemote.OnClientEvent:Connect(showRedDangerTelegraph)

PortalRemote.OnClientEvent:Connect(function(isOpen: boolean, duration: number, targetScale: number)
	animateClientPortal(isOpen, duration or (isOpen and 1.35 or 1.0), targetScale or (isOpen and 3.804 or 0.001))
end)

ImpactRemote.OnClientEvent:Connect(function(impactPos, handSize, floorColor, floorMaterial, circleRadius)
	local radius = circleRadius or (math.max(handSize.X, handSize.Z) * 0.5)
	playSlamAudio(impactPos)
	spawnGroundDestruction(impactPos, radius, floorColor or Color3.fromRGB(58, 125, 21), floorMaterial or Enum.Material.Plastic)
	shakeCamera(impactPos, radius)
end)

print("[RuinsImpactClient] Loaded and listening for RuinsHandImpactEvent, RuinsPortalEvent, and RuinsTelegraphEvent.")
