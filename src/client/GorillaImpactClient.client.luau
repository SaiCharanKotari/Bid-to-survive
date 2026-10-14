--!strict
-- GorillaImpactClient: Listens for Gorilla boss impact frame. Spawns procedural crater debris,
-- dual shockwave rings, 3D decaying camera trauma, and spatial sub-bass audio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Locate RemoteEvent
local Network = ReplicatedStorage:WaitForChild("Network", 10)
local ImpactRemote = (Network and Network:WaitForChild("GorillaImpactEvent", 10))
	or ReplicatedStorage:WaitForChild("GorillaImpactEvent", 10)

if not ImpactRemote then
	warn("[GorillaImpactClient] GorillaImpactEvent not found!")
	return
end

-- Lighting ColorCorrection effect for impact flash
local impactColorCorrection = Lighting:FindFirstChild("GorillaImpactCC")
if not impactColorCorrection then
	impactColorCorrection = Instance.new("ColorCorrectionEffect")
	impactColorCorrection.Name = "GorillaImpactCC"
	impactColorCorrection.Parent = Lighting
end

local function playImpactAudio(impactPos: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = impactPos
	attachment.Parent = Workspace.Terrain

	local slamSound = Instance.new("Sound")
	slamSound.Name = "EarthSlamSound"
	slamSound.SoundId = "rbxassetid://9120386436" -- Heavy explosion / ground impact thud
	slamSound.Volume = 2.4
	slamSound.PlaybackSpeed = 0.85
	slamSound.RollOffMaxDistance = 300
	slamSound.RollOffMode = Enum.RollOffMode.Linear
	slamSound.Parent = attachment
	slamSound:Play()

	task.delay(4, function()
		attachment:Destroy()
	end)
end

local function spawnShockwaveAndDebris(impactPos: Vector3, floorColor: Color3, floorMaterial: Enum.Material, arenaRadius: number)
	local folder = Instance.new("Folder")
	folder.Name = "GorillaSmashVFX"
	folder.Parent = Workspace

	local maxRadius = math.clamp(arenaRadius or 50, 30, 100)

	-- 1. Inner High-Energy Core Shockwave (#FF8C24, Neon)
	local coreRing = Instance.new("Part")
	coreRing.Name = "CoreShockwave"
	coreRing.Shape = Enum.PartType.Cylinder
	coreRing.Anchored = true
	coreRing.CanCollide = false
	coreRing.CastShadow = false
	coreRing.Material = Enum.Material.Neon
	coreRing.Color = Color3.fromRGB(255, 140, 36)
	coreRing.Size = Vector3.new(0.4, 4, 4)
	coreRing.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	coreRing.Parent = folder

	TweenService:Create(coreRing, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, maxRadius * 0.95, maxRadius * 0.95),
		Transparency = 1
	}):Play()

	-- 2. Outer Dust Shockwave (#D9D2C5, SmoothPlastic)
	local dustRing = Instance.new("Part")
	dustRing.Name = "DustShockwave"
	dustRing.Shape = Enum.PartType.Cylinder
	dustRing.Anchored = true
	dustRing.CanCollide = false
	dustRing.CastShadow = false
	dustRing.Material = Enum.Material.SmoothPlastic
	dustRing.Color = Color3.fromRGB(217, 210, 197)
	dustRing.Transparency = 0.25
	dustRing.Size = Vector3.new(1.2, 6, 6)
	dustRing.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	dustRing.Parent = folder

	TweenService:Create(dustRing, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, maxRadius * 1.15, maxRadius * 1.15),
		Transparency = 1
	}):Play()

	-- 3. Procedural Crater Chunks (inherits GameplayArea color & material)
	local numChunks = 14
	for i = 1, numChunks do
		local angle = (i / numChunks) * math.pi * 2 + (math.random(-15, 15) * 0.01)
		local radiusOffset = math.random(8, 16)
		local spawnOffset = Vector3.new(math.cos(angle) * radiusOffset, -1.5, math.sin(angle) * radiusOffset)
		local targetPos = impactPos + Vector3.new(math.cos(angle) * (radiusOffset + 5), 0.8, math.sin(angle) * (radiusOffset + 5))

		local rock = Instance.new("Part")
		rock.Name = "CraterDebris"
		rock.Anchored = true
		rock.CanCollide = false
		rock.CastShadow = true
		rock.Color = floorColor
		rock.Material = floorMaterial
		rock.Size = Vector3.new(math.random(25, 50) / 10, math.random(15, 35) / 10, math.random(25, 50) / 10)
		rock.CFrame = CFrame.lookAt(impactPos + spawnOffset, impactPos)
			* CFrame.Angles(
				math.rad(math.random(-35, 35)),
				math.rad(math.random(-25, 25)),
				math.rad(math.random(-30, 30))
			)
		rock.Parent = folder

		-- Burst up out of the floor
		local popUp = TweenService:Create(rock, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = targetPos
		})
		popUp:Play()

		-- Sink back into floor after 1.1s
		task.delay(1.1 + (math.random() * 0.35), function()
			if rock.Parent then
				local sink = TweenService:Create(rock, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = targetPos - Vector3.new(0, 4.0, 0),
					Transparency = 1
				})
				sink:Play()
			end
		end)
	end

	task.delay(2.5, function()
		folder:Destroy()
	end)
end

local activeShakeConn: RBXScriptConnection? = nil

local function shakeCamera(impactPos: Vector3)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = root and (root.Position - impactPos).Magnitude or 40
	local intensity = math.clamp(1 - (dist / 140), 0.25, 1) * 2.4

	-- Contrast flash and crimson impact punch
	impactColorCorrection.Contrast = 0.38 * intensity
	impactColorCorrection.TintColor = Color3.fromRGB(255, 210, 205)

	TweenService:Create(impactColorCorrection, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Contrast = 0,
		TintColor = Color3.fromRGB(255, 255, 255)
	}):Play()

	if activeShakeConn then
		activeShakeConn:Disconnect()
		activeShakeConn = nil
	end

	local startTime = os.clock()
	local duration = 0.48
	activeShakeConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			if activeShakeConn then
				activeShakeConn:Disconnect()
				activeShakeConn = nil
			end
			return
		end

		local alpha = 1 - (elapsed / duration)
		local damper = alpha * alpha * intensity
		local offset = Vector3.new(
			(math.random() - 0.5) * damper * 1.2,
			(math.random() - 0.5) * damper * 1.5,
			(math.random() - 0.5) * damper * 1.2
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(
			math.rad((math.random() - 0.5) * damper * 2.0),
			0,
			math.rad((math.random() - 0.5) * damper * 2.0)
		)
	end)
end

-- Authoritative 91-frame motion data for Gorilla-gem
local GorillaMotionData = require(ReplicatedStorage:WaitForChild("GorillaMotionData"))
local frames: {{number}} = GorillaMotionData

local function findGorillaModel(): Model?
	return Workspace:FindFirstChild("Gorilla-gem")
		or Workspace:FindFirstChild("Gorilla-gem", true)
		or Workspace:FindFirstChild("MainGorilla", true)
end

local function findBone(parent: Instance, name: string): Bone?
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Bone") then
			if child.Name == name then return child end
			local f = findBone(child, name)
			if f then return f end
		end
	end
	return nil
end

local function ang(x: number, y: number, z: number): CFrame
	return CFrame.fromEulerAnglesXYZ(x, y, z)
end

local isClientSmashing = false

local function playGorillaSmashAnimation(impactPos: Vector3, floorColor: Color3, floorMaterial: Enum.Material, arenaRadius: number)
	if isClientSmashing then return end
	isClientSmashing = true

	local gorillaModel = findGorillaModel()
	if not gorillaModel then
		warn("[GorillaClient] Gorilla-gem not found for client animation!")
		isClientSmashing = false
		return
	end

	local char1 = gorillaModel:FindFirstChild("char1", true)
	if not char1 then
		warn("[GorillaClient] char1 MeshPart not found in Gorilla-gem!")
		isClientSmashing = false
		return
	end

	local cachedBones = {
		Hips = findBone(char1, "Hips"),
		Spine = findBone(char1, "Spine"),
		Head = findBone(char1, "Head"),
		RightArm = findBone(char1, "RightArm"),
		RightForeArm = findBone(char1, "RightForeArm"),
		RightHand = findBone(char1, "RightHand"),
		LeftArm = findBone(char1, "LeftArm"),
		LeftForeArm = findBone(char1, "LeftForeArm"),
		LeftHand = findBone(char1, "LeftHand"),
		RightUpLeg = findBone(char1, "RightUpLeg"),
		RightLeg = findBone(char1, "RightLeg"),
		RightFoot = findBone(char1, "RightFoot"),
		LeftUpLeg = findBone(char1, "LeftUpLeg"),
		LeftLeg = findBone(char1, "LeftLeg"),
		LeftFoot = findBone(char1, "LeftFoot"),
	}

	-- Play hammer swing audio on handle
	local hammer = gorillaModel:FindFirstChild("Thors Hammer", true) or Workspace:FindFirstChild("Thors Hammer")
	local handle = hammer and hammer:FindFirstChild("Handle")
	if handle then
		local swingSound = handle:FindFirstChild("SwingSound") or handle:FindFirstChild("slash")
		if swingSound and swingSound:IsA("Sound") then
			swingSound:Play()
		end
	end

	task.spawn(function()
		local totalFrames = #frames
		local fps = 30
		local frameDur = 1 / fps
		local IMPACT_FRAME = 40

		print(string.format("[GorillaClient] 🎬 Starting client-side 91-frame bone playback (%d frames @ 30 FPS)...", totalFrames))

		for i = 1, totalFrames do
			local fd = frames[i]
			if not fd then continue end

			local dx, dy, dz = fd[2], fd[3], fd[4]
			local rrx, rry, rrz = fd[5], fd[6], fd[7]

			if cachedBones.Hips then
				cachedBones.Hips.Transform = CFrame.new(dx, dy, dz) * ang(rrx, rry, rrz)
			end
			if cachedBones.Spine then cachedBones.Spine.Transform = ang(fd[8], fd[9], fd[10]) end
			if cachedBones.Head then cachedBones.Head.Transform = ang(fd[11], fd[12], fd[13]) end

			if cachedBones.RightArm then cachedBones.RightArm.Transform = ang(fd[14], fd[15], fd[16]) end
			if cachedBones.RightForeArm then cachedBones.RightForeArm.Transform = ang(fd[17], fd[18], fd[19]) end
			if cachedBones.RightHand then cachedBones.RightHand.Transform = ang(fd[20], fd[21], fd[22]) end

			if cachedBones.LeftArm then cachedBones.LeftArm.Transform = ang(fd[23], fd[24], fd[25]) end
			if cachedBones.LeftForeArm then cachedBones.LeftForeArm.Transform = ang(fd[26], fd[27], fd[28]) end
			if cachedBones.LeftHand then cachedBones.LeftHand.Transform = ang(fd[29], fd[30], fd[31]) end

			if cachedBones.RightUpLeg then cachedBones.RightUpLeg.Transform = ang(fd[32], fd[33], fd[34]) end
			if cachedBones.RightLeg then cachedBones.RightLeg.Transform = ang(fd[35], fd[36], fd[37]) end
			if cachedBones.RightFoot then cachedBones.RightFoot.Transform = ang(fd[38], fd[39], fd[40]) end

			if cachedBones.LeftUpLeg then cachedBones.LeftUpLeg.Transform = ang(fd[41], fd[42], fd[43]) end
			if cachedBones.LeftLeg then cachedBones.LeftLeg.Transform = ang(fd[44], fd[45], fd[46]) end
			if cachedBones.LeftFoot then cachedBones.LeftFoot.Transform = ang(fd[47], fd[48], fd[49]) end

			-- Frame 40: EXACT GROUND SMASH IMPACT!
			if i == IMPACT_FRAME then
				print(string.format("[GorillaClient] 💥💥💥 FRAME %d GROUND SMASH IMPACT! 💥💥💥", i))
				playImpactAudio(impactPos)
				spawnShockwaveAndDebris(impactPos, floorColor, floorMaterial, arenaRadius)
				shakeCamera(impactPos)
				task.wait(0.12) -- 0.12s hit-stop freeze on impact
			else
				task.wait(frameDur)
			end
		end

		print("[GorillaClient] 🎬 Smash motion finished. Blending bones back to rest pose.")

		-- Smoothly blend back to rest pose
		local steps = 8
		for s = 1, steps do
			local alpha = 1 - (s / steps)
			for _, bone in pairs(cachedBones) do
				if bone then
					bone.Transform = bone.Transform:Lerp(CFrame.new(), 1 - alpha)
				end
			end
			task.wait(0.03)
		end

		for _, bone in pairs(cachedBones) do
			if bone then
				bone.Transform = CFrame.new()
			end
		end

		isClientSmashing = false
		print("[GorillaClient] 🎬 Rest pose restored.")
	end)
end

ImpactRemote.OnClientEvent:Connect(function(actionOrPos: any, p2: any, p3: any, p4: any, p5: any)
	if actionOrPos == "SMASH_START" then
		local impactPos: Vector3 = p2 or Vector3.new(0, 0, 0)
		local floorColor: Color3 = p3 or Color3.fromRGB(115, 110, 100)
		local floorMaterial: Enum.Material = p4 or Enum.Material.Slate
		local arenaRadius: number = p5 or 45
		playGorillaSmashAnimation(impactPos, floorColor, floorMaterial, arenaRadius)
	elseif typeof(actionOrPos) == "Vector3" then
		-- Legacy fallback: direct impact trigger
		local impactPos: Vector3 = actionOrPos
		local floorColor: Color3 = p2 or Color3.fromRGB(115, 110, 100)
		local floorMaterial: Enum.Material = p3 or Enum.Material.Slate
		local arenaRadius: number = p4 or 45
		print(string.format("[GorillaClient] 💥 GorillaImpactEvent received! Impact pos: %s | Radius: %.1f", tostring(impactPos), arenaRadius))
		playImpactAudio(impactPos)
		spawnShockwaveAndDebris(impactPos, floorColor, floorMaterial, arenaRadius)
		shakeCamera(impactPos)
	end
end)
