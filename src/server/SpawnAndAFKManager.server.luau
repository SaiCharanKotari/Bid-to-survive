--!strict
-- ServerScriptService/SpawnAndAFKManager.server.luau
-- Manages invisible/non-collidable spawn pads, procedural fence perimeter barrier walls,
-- and AFK teleport logic.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 1. Ensure RemoteEvents exist in ReplicatedStorage & Network
local Network = ReplicatedStorage:FindFirstChild("Network")
local AFKRemote: RemoteEvent = (Network and Network:FindFirstChild("AFKToggleEvent"))
	or ReplicatedStorage:FindFirstChild("AFKToggleEvent") :: any

if not AFKRemote then
	AFKRemote = Instance.new("RemoteEvent")
	AFKRemote.Name = "AFKToggleEvent"
	AFKRemote.Parent = Network or ReplicatedStorage
end

local SetAFK: RemoteEvent = (Network and Network:FindFirstChild("SetAFK"))
	or ReplicatedStorage:FindFirstChild("SetAFK") :: any

-- 2. Make all SpawnLocations Invisible & Non-Collidable
local primarySpawnCFrame = CFrame.new(48.11, 85.14, 2.92)

for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("SpawnLocation") then
		desc.Transparency = 1
		desc.CanCollide = false
		desc.CanQuery = false
		desc.CanTouch = false
		primarySpawnCFrame = desc.CFrame

		-- Hide default Spawn decal if present
		for _, child in ipairs(desc:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				child.Transparency = 1
			end
		end
	end
end

-- 3. Calculate Invisible Bounding Box around Spawn from Fences
local function buildSpawnBoxFromFences()
	local existingBox = Workspace:FindFirstChild("SpawnFenceBarrierBox")
	if existingBox then
		existingBox:Destroy()
	end

	local fenceParts = {}

	-- Searches for any model/folder/parts named "Fence" or "Fences" near Spawn
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local nameLower = string.lower(desc.Name)
			local parentNameLower = desc.Parent and string.lower(desc.Parent.Name) or ""
			if string.find(nameLower, "fence") or string.find(parentNameLower, "fence") then
				if (desc.Position - primarySpawnCFrame.Position).Magnitude < 250 then
					table.insert(fenceParts, desc)
				end
			end
		end
	end

	if #fenceParts == 0 then
		warn("[SpawnAndAFKManager] No Fence parts found near Spawn!")
		return
	end

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge

	for _, part in ipairs(fenceParts) do
		local cf = part.CFrame
		local half = part.Size * 0.5
		for _, sx in ipairs({-1, 1}) do
			for _, sy in ipairs({-1, 1}) do
				for _, sz in ipairs({-1, 1}) do
					local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					minX = math.min(minX, corner.X)
					maxX = math.max(maxX, corner.X)
					minY = math.min(minY, corner.Y)
					maxY = math.max(maxY, corner.Y)
					minZ = math.min(minZ, corner.Z)
					maxZ = math.max(maxZ, corner.Z)
				end
			end
		end
	end

	local boxFolder = Instance.new("Folder")
	boxFolder.Name = "SpawnFenceBarrierBox"
	boxFolder.Parent = Workspace

	local wallHeight = 45
	local wallThickness = 2
	local centerX = (minX + maxX) * 0.5
	local centerZ = (minZ + maxZ) * 0.5
	local centerY = minY + (wallHeight * 0.5)
	local widthX = (maxX - minX) + wallThickness
	local depthZ = (maxZ - minZ) + wallThickness

	local walls = {
		-- North & South Walls (along X)
		{ Name = "SpawnBarrierWall_North", Size = Vector3.new(widthX, wallHeight, wallThickness), Pos = Vector3.new(centerX, centerY, minZ) },
		{ Name = "SpawnBarrierWall_South", Size = Vector3.new(widthX, wallHeight, wallThickness), Pos = Vector3.new(centerX, centerY, maxZ) },
		-- East & West Walls (along Z)
		{ Name = "SpawnBarrierWall_West",  Size = Vector3.new(wallThickness, wallHeight, depthZ), Pos = Vector3.new(minX, centerY, centerZ) },
		{ Name = "SpawnBarrierWall_East",  Size = Vector3.new(wallThickness, wallHeight, depthZ), Pos = Vector3.new(maxX, centerY, centerZ) },
	}

	for _, w in ipairs(walls) do
		local barrier = Instance.new("Part")
		barrier.Name = w.Name
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.CanQuery = false
		barrier.Transparency = 1
		barrier.Size = w.Size
		barrier.Position = w.Pos
		barrier.Parent = boxFolder
	end

	print(string.format("[SpawnAndAFKManager] Built 4 fence safety walls around Spawn (Width=%.1f, Depth=%.1f, Height=%.1f)", widthX, depthZ, wallHeight))
end

buildSpawnBoxFromFences()

-- 4. Unified AFK Teleport & Attribute Handler
local function handleAFKToggle(player: Player, isAFK: boolean?)
	local currentAFK = player:GetAttribute("IsAFK") or false
	local newAFK = (isAFK ~= nil) and isAFK or (not currentAFK)
	player:SetAttribute("IsAFK", newAFK)

	local character = player.Character
	if character and newAFK then
		-- Offset +3.5 studs up so players stand cleanly on solid floor beneath non-collidable spawn
		character:PivotTo(primarySpawnCFrame * CFrame.new(0, 3.5, 0))
	end
end

AFKRemote.OnServerEvent:Connect(handleAFKToggle)
if SetAFK then
	SetAFK.OnServerEvent:Connect(handleAFKToggle)
end

print("[SpawnAndAFKManager] Initialized successfully.")
