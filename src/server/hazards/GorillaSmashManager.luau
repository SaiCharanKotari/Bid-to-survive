--!strict
--for now we are not using this code for agents are any one dont read this 
-- GorillaSmashManager: Drives Gorilla-gem's authoritative 91-frame bone transform animation,
-- synchronizes frame-accurate impact timing at Frame 40 (t=1.33s), executes hit-stop weight,
-- triggers procedural VFX broadcast, and applies player damage.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local GorillaSmashManager = {}

-- Load 91-frame authoritative motion data
local ServerScriptService = game:GetService("ServerScriptService")
local motionDataModule = ReplicatedStorage:FindFirstChild("GorillaMotionData") or ServerScriptService:WaitForChild("GorillaMotionData", 10)
local frames: {{number}} = if motionDataModule then require(motionDataModule) else {}

-- RemoteEvent setup for Client VFX, Shockwave, & Camera Shake
local Network = ReplicatedStorage:FindFirstChild("Network")
local ImpactRemote = (Network and Network:FindFirstChild("GorillaImpactEvent"))
	or ReplicatedStorage:FindFirstChild("GorillaImpactEvent")

if not ImpactRemote then
	ImpactRemote = Instance.new("RemoteEvent")
	ImpactRemote.Name = "GorillaImpactEvent"
	ImpactRemote.Parent = Network or ReplicatedStorage
end

local function findGorillaModel(): Model?
	return Workspace:FindFirstChild("Gorilla-gem")
		or Workspace:FindFirstChild("Gorilla-gem", true)
		or Workspace:FindFirstChild("MainGorilla", true)
end

local function findGameplayArea(): Instance?
	local map = Workspace:FindFirstChild("BidToSurviveMap")
	if map and map:FindFirstChild("GameplayArea") then
		return map.GameplayArea
	end
	return Workspace:FindFirstChild("GameplayArea", true)
end

-- Retrieve surface center, color, material, and radius from GameplayArea / Walkway
local function getGameplaySurfaceData(): (Vector3, Color3, Enum.Material, number)
	local gameplayArea = findGameplayArea()
	if not gameplayArea then
		warn("[GorillaSmash] GameplayArea not found in Workspace!")
		return Vector3.new(0, 0, 0), Color3.fromRGB(115, 110, 100), Enum.Material.Slate, 45
	end

	local walkway = gameplayArea:FindFirstChild("Walkway", true)
	if walkway and walkway:IsA("BasePart") then
		local topPos = walkway.Position + Vector3.new(0, walkway.Size.Y * 0.5, 0)
		local radius = math.max(walkway.Size.X, walkway.Size.Z) * 0.5
		return topPos, walkway.Color, walkway.Material, radius
	end

	if gameplayArea:IsA("BasePart") then
		local topPos = gameplayArea.Position + Vector3.new(0, gameplayArea.Size.Y * 0.5, 0)
		return topPos, gameplayArea.Color, gameplayArea.Material, math.max(gameplayArea.Size.X, gameplayArea.Size.Z) * 0.5
	elseif gameplayArea:IsA("Model") then
		local cf, size = gameplayArea:GetBoundingBox()
		local basePart = gameplayArea.PrimaryPart or gameplayArea:FindFirstChildWhichIsA("BasePart", true)
		local topPos = cf.Position + Vector3.new(0, size.Y * 0.5, 0)
		local color = basePart and basePart.Color or Color3.fromRGB(115, 110, 100)
		local mat = basePart and basePart.Material or Enum.Material.Slate
		return topPos, color, mat, math.max(size.X, size.Z) * 0.5
	end

	return Vector3.new(0, 0, 0), Color3.fromRGB(115, 110, 100), Enum.Material.Slate, 45
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

-- Rig state cache
local gorillaModel: Model? = nil
local char1Mesh: MeshPart? = nil
local cachedBones: {[string]: Bone} = {}
local isPlaying = false

local function prepareRig()
	gorillaModel = findGorillaModel()
	if not gorillaModel then
		warn("[GorillaSmash] FATAL: Gorilla-gem model not found in Workspace!")
		return false
	end

	char1Mesh = gorillaModel:FindFirstChild("char1", true) :: MeshPart?
	if not char1Mesh then
		warn("[GorillaSmash] FATAL: char1 MeshPart not found in Gorilla-gem!")
		return false
	end

	gorillaModel.PrimaryPart = char1Mesh
	char1Mesh.Anchored = true

	-- Unanchor hammer parts so RigidConstraint can move hammer with hand bone
	local hammer = gorillaModel:FindFirstChild("Thors Hammer", true) or Workspace:FindFirstChild("Thors Hammer")
	if hammer and hammer.Parent ~= gorillaModel then
		hammer.Parent = gorillaModel
	end

	local unanchoredCount = 0
	for _, desc in ipairs(gorillaModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= char1Mesh then
			desc.Anchored = false
			desc.CanCollide = false
			if hammer and desc:IsDescendantOf(hammer) then
				desc.Massless = true
			end
			unanchoredCount += 1
		end
	end

	-- Cache all 15 active bones
	cachedBones = {
		Hips = findBone(char1Mesh, "Hips") :: Bone,
		Spine = findBone(char1Mesh, "Spine") :: Bone,
		Head = findBone(char1Mesh, "Head") :: Bone,
		RightArm = findBone(char1Mesh, "RightArm") :: Bone,
		RightForeArm = findBone(char1Mesh, "RightForeArm") :: Bone,
		RightHand = findBone(char1Mesh, "RightHand") :: Bone,
		LeftArm = findBone(char1Mesh, "LeftArm") :: Bone,
		LeftForeArm = findBone(char1Mesh, "LeftForeArm") :: Bone,
		LeftHand = findBone(char1Mesh, "LeftHand") :: Bone,
		RightUpLeg = findBone(char1Mesh, "RightUpLeg") :: Bone,
		RightLeg = findBone(char1Mesh, "RightLeg") :: Bone,
		RightFoot = findBone(char1Mesh, "RightFoot") :: Bone,
		LeftUpLeg = findBone(char1Mesh, "LeftUpLeg") :: Bone,
		LeftLeg = findBone(char1Mesh, "LeftLeg") :: Bone,
		LeftFoot = findBone(char1Mesh, "LeftFoot") :: Bone,
	}

	print(string.format("[GorillaSmash] [RIG] Rig ready! 1 Anchored (char1), %d unanchored (hammer). 15/15 Bones mapped.", unanchoredCount))
	return true
end

-- Public: Execute 91-frame hammer smash with frame-accurate impact at frame 40
function GorillaSmashManager.ExecuteSmashAndDamage(onImpactDamageCallback: (() -> ())?)
	if isPlaying then
		warn("[GorillaSmash] Smash already in progress, ignoring duplicate call.")
		return
	end

	if not prepareRig() or not gorillaModel then
		warn("[GorillaSmash] Rig could not be prepared, firing callback immediately.")
		if onImpactDamageCallback then task.spawn(onImpactDamageCallback) end
		return
	end

	isPlaying = true

	local impactPos, floorColor, floorMaterial, arenaRadius = getGameplaySurfaceData()
	print(string.format("[GorillaSmash] [EXECUTE] Target arena: pos=%s, radius=%.1f", tostring(impactPos), arenaRadius))

	-- Orient Gorilla-gem horizontally towards impact center
	local rootCFrame = gorillaModel:GetPivot()
	local lookTarget = Vector3.new(impactPos.X, rootCFrame.Position.Y, impactPos.Z)
	if (lookTarget - rootCFrame.Position).Magnitude > 0.5 then
		gorillaModel:PivotTo(CFrame.lookAt(rootCFrame.Position, lookTarget))
		print("[GorillaSmash] [EXECUTE] Gorilla pivoted to face arena center.")
	end

	-- Trigger swing audio on hammer handle
	local hammer = gorillaModel:FindFirstChild("Thors Hammer", true) or Workspace:FindFirstChild("Thors Hammer")
	local handle = hammer and hammer:FindFirstChild("Handle")
	if handle then
		local swingSound = handle:FindFirstChild("SwingSound") or handle:FindFirstChild("slash")
		if not swingSound then
			swingSound = Instance.new("Sound")
			swingSound.Name = "SwingSound"
			swingSound.SoundId = "rbxassetid://12222216"
			swingSound.Volume = 2.0
			swingSound.PlaybackSpeed = 0.95
			swingSound.Parent = handle
		end
		swingSound:Play()
		print("[GorillaSmash] [AUDIO] Swing sound triggered.")
	end

	-- Broadcast SMASH_START to all clients so they run the 91-frame bone playback locally
	ImpactRemote:FireAllClients("SMASH_START", impactPos, floorColor, floorMaterial, arenaRadius)
	print("[GorillaSmash] [NETWORK] Broadcast 'SMASH_START' to all clients.")

	-- Execute the 91-frame bone motion playback on server as well
	task.spawn(function()
		local totalFrames = #frames
		local fps = 30
		local frameDur = 1 / fps
		local impactTriggered = false
		local IMPACT_FRAME = 40 -- Authoritative ground strike frame (40 / 30fps = 1.33s)

		print(string.format("[GorillaSmash] [ANIMATION] Starting 91-frame motion playback (%d frames @ 30 FPS)...", totalFrames))

		for i = 1, totalFrames do
			local fd = frames[i]
			if not fd then continue end

			local dx, dy, dz = fd[2], fd[3], fd[4]
			local rrx, rry, rrz = fd[5], fd[6], fd[7]

			-- Hips root translation and rotation
			if cachedBones.Hips then
				cachedBones.Hips.Transform = CFrame.new(dx, dy, dz) * ang(rrx, rry, rrz)
			end

			-- Torso pitch & head
			if cachedBones.Spine then cachedBones.Spine.Transform = ang(fd[8], fd[9], fd[10]) end
			if cachedBones.Head then cachedBones.Head.Transform = ang(fd[11], fd[12], fd[13]) end

			-- Right Arm (holding Thor's Hammer via RigidConstraint)
			if cachedBones.RightArm then cachedBones.RightArm.Transform = ang(fd[14], fd[15], fd[16]) end
			if cachedBones.RightForeArm then cachedBones.RightForeArm.Transform = ang(fd[17], fd[18], fd[19]) end
			if cachedBones.RightHand then cachedBones.RightHand.Transform = ang(fd[20], fd[21], fd[22]) end

			-- Left Arm (two-handed grip on hammer handle)
			if cachedBones.LeftArm then cachedBones.LeftArm.Transform = ang(fd[23], fd[24], fd[25]) end
			if cachedBones.LeftForeArm then cachedBones.LeftForeArm.Transform = ang(fd[26], fd[27], fd[28]) end
			if cachedBones.LeftHand then cachedBones.LeftHand.Transform = ang(fd[29], fd[30], fd[31]) end

			-- Legs & feet
			if cachedBones.RightUpLeg then cachedBones.RightUpLeg.Transform = ang(fd[32], fd[33], fd[34]) end
			if cachedBones.RightLeg then cachedBones.RightLeg.Transform = ang(fd[35], fd[36], fd[37]) end
			if cachedBones.RightFoot then cachedBones.RightFoot.Transform = ang(fd[38], fd[39], fd[40]) end

			if cachedBones.LeftUpLeg then cachedBones.LeftUpLeg.Transform = ang(fd[41], fd[42], fd[43]) end
			if cachedBones.LeftLeg then cachedBones.LeftLeg.Transform = ang(fd[44], fd[45], fd[46]) end
			if cachedBones.LeftFoot then cachedBones.LeftFoot.Transform = ang(fd[47], fd[48], fd[49]) end

			-- Frame 40: EXACT GROUND SMASH IMPACT!
			if i == IMPACT_FRAME and not impactTriggered then
				impactTriggered = true
				print(string.format("[GorillaSmash] [IMPACT] 💥💥💥 FRAME %d IMPACT FIRED! 💥💥💥", i))

				-- 1. Broadcast Client VFX, Shockwave Rings, Camera Trauma & Sub-Bass Audio
				ImpactRemote:FireAllClients(impactPos, floorColor, floorMaterial, arenaRadius)

				-- 2. Execute server player damage on exact impact frame
				if onImpactDamageCallback then
					task.spawn(onImpactDamageCallback)
				end

				-- 3. Heavy hit-stop pause on impact (0.12s)
				print("[GorillaSmash] [HIT-STOP] Applying 0.12s hit-stop freeze...")
				task.wait(0.12)
				print("[GorillaSmash] [HIT-STOP] Hit-stop ended. Continuing follow-through.")
			else
				task.wait(frameDur)
			end
		end

		print("[GorillaSmash] [ANIMATION] Smash animation finished. Blending bones back to rest pose.")

		-- Smoothly reset bone transforms back to identity rest pose over 0.25s
		local steps = 8
		for s = 1, steps do
			local alpha = 1 - (s / steps)
			for _, bone in pairs(cachedBones) do
				bone.Transform = bone.Transform:Lerp(CFrame.new(), 1 - alpha)
			end
			task.wait(0.03)
		end

		for _, bone in pairs(cachedBones) do
			bone.Transform = CFrame.new()
		end

		isPlaying = false
		print("[GorillaSmash] [ANIMATION] Rest pose restored. Ready for next smash.")
	end)
end

-- Manual trigger listener (e.g. from pressing 'E' key)
ImpactRemote.OnServerEvent:Connect(function(player: Player, action: any)
	if action == "TRIGGER_SMASH" or action == "TEST_SMASH" then
		print(string.format("[GorillaSmash] 🕹️ Manual smash triggered by player: %s (Key 'E')", player.Name))
		GorillaSmashManager.ExecuteSmashAndDamage(function()
			print("[GorillaSmash] 💥 Manual impact executed successfully!")
		end)
	end
end)

-- Initialize on server startup
task.spawn(function()
	task.wait(1)
	prepareRig()
end)

return GorillaSmashManager
