--!strict
-- ServerScriptService/JetpackManager.server.luau
-- Authoritative server-side Jetpack Attachment Manager for Bid-to-survive.
-- Guarantees every player automatically receives their own visible Jetpack model
-- securely attached to their back on spawn and every respawn.
-- Also manages server-side validation and multiplayer visual replication for the Jetpack Burst.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Network = ReplicatedStorage:FindFirstChild("Network")
if not Network then
	Network = Instance.new("Folder")
	Network.Name = "Network"
	Network.Parent = ReplicatedStorage
end

local JetpackBurstEvent: RemoteEvent = (Network:FindFirstChild("JetpackBurstEvent") :: RemoteEvent?)
	or Instance.new("RemoteEvent")
JetpackBurstEvent.Name = "JetpackBurstEvent"
JetpackBurstEvent.Parent = Network

local JetpackBurstReplicatedEvent: RemoteEvent = (Network:FindFirstChild("JetpackBurstReplicatedEvent") :: RemoteEvent?)
	or Instance.new("RemoteEvent")
JetpackBurstReplicatedEvent.Name = "JetpackBurstReplicatedEvent"
JetpackBurstReplicatedEvent.Parent = Network

-- 1. JETPACK TEMPLATE RETRIEVAL & INITIALIZATION
local function getOrCreateJetpackTemplate(): Model?
	local template = ServerStorage:FindFirstChild("JetpackTemplate") :: Model?
	if template then return template end

	-- Fallback if template is still in Workspace
	local wsJetpack = Workspace:FindFirstChild("Jetpack") :: Model?
	if wsJetpack then
		local newTemplate = wsJetpack:Clone()
		newTemplate.Name = "JetpackTemplate"
		local handle = newTemplate:FindFirstChild("Handle") :: BasePart?
		if handle then
			newTemplate.PrimaryPart = handle
			for _, child in ipairs(newTemplate:GetChildren()) do
				if child:IsA("BasePart") then
					child.Anchored = false
					child.CanCollide = false
					child.Massless = true
					if child ~= handle then
						local wc = Instance.new("WeldConstraint")
						wc.Name = child.Name .. "Weld"
						wc.Part0 = handle
						wc.Part1 = child
						wc.Parent = handle
					end
				end
			end
		end
		newTemplate.Parent = ServerStorage
		wsJetpack:Destroy()
		return newTemplate
	end

	warn("[JetpackManager] ⚠️ JetpackTemplate not found in ServerStorage or Workspace!")
	return nil
end

-- 2. JETPACK ATTACHMENT PIPELINE
local function attachJetpackToCharacter(player: Player, character: Model)
	if not character or not character.Parent then return end
	if character:FindFirstChild("Jetpack") then return end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then return end

	local template = getOrCreateJetpackTemplate()
	if not template then return end

	-- Support both R6 and R15 rigs
	local torso: BasePart? = nil
	local offset: CFrame = CFrame.identity

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		torso = character:WaitForChild("Torso", 5) :: BasePart?
		-- R6 Torso size is (2, 2, 1). Offset Z = 0.85 places Handle flush against back
		offset = CFrame.new(0, 0.10, 0.85)
	else
		torso = (character:WaitForChild("UpperTorso", 5) :: BasePart?)
			or (character:FindFirstChild("Torso") :: BasePart?)
		-- R15 UpperTorso size is (1.94, 1.70, 1.00). Offset Z = 0.85 aligns with BodyBackAttachment
		offset = CFrame.new(0, -0.10, 0.85)
	end

	if not torso or not character.Parent then return end

	-- Double-check after yields to avoid race conditions
	if character:FindFirstChild("Jetpack") then return end

	local jetpack = template:Clone()
	jetpack.Name = "Jetpack"
	local handle = jetpack:FindFirstChild("Handle") :: BasePart?
	if not handle then
		jetpack:Destroy()
		return
	end
	jetpack.PrimaryPart = handle

	-- Ensure all parts are unanchored, non-colliding, and massless
	for _, part in ipairs(jetpack:GetChildren()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end

	-- Position jetpack flush to torso and weld
	jetpack:PivotTo(torso.CFrame * offset)
	jetpack.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Name = "TorsoAttachmentWeld"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.Parent = handle

	print(string.format("[JetpackManager] 🎒 Attached Jetpack to %s (%s rig)", player.Name, humanoid.RigType.Name))
end

-- 3. PLAYER & CHARACTER LIFECYCLE MANAGEMENT
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(attachJetpackToCharacter, player, character)
	end)

	-- Handle R15-to-R6 model swap or delayed rig ready state
	player:GetAttributeChangedSignal("R6RigReady"):Connect(function()
		if player:GetAttribute("R6RigReady") == true and player.Character then
			task.defer(attachJetpackToCharacter, player, player.Character)
		end
	end)

	if player.Character then
		task.defer(attachJetpackToCharacter, player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- 4. BURST VALIDATION & MULTIPLAYER REPLICATION
local lastPlayerBurstTimes: { [Player]: number } = {}

JetpackBurstEvent.OnServerEvent:Connect(function(player: Player, flatDir: any)
	local now = os.clock()
	local lastTime = lastPlayerBurstTimes[player] or 0
	if (now - lastTime) < 1.05 then
		-- Cooldown throttle
		return
	end

	local char = player.Character
	if not char or not char.Parent then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if player:GetAttribute("IsAFK") == true and player:GetAttribute("IsInGame") ~= true then return end

	lastPlayerBurstTimes[player] = now

	-- Replicate burst visuals to all clients (including direction)
	if typeof(flatDir) ~= "Vector3" or flatDir.Magnitude < 0.1 then
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			flatDir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
		else
			flatDir = Vector3.new(0, 0, -1)
		end
	else
		flatDir = flatDir.Unit
	end

	JetpackBurstReplicatedEvent:FireAllClients(player, flatDir)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastPlayerBurstTimes[player] = nil
end)

print("[JetpackManager] Initialized: Server Jetpack Attachment & Burst Replication active.")
