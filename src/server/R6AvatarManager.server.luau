--!strict
-- ServerScriptService/R6AvatarManager.server.luau
-- Authoritative server-side R6 avatar pipeline for Bid-to-survive.
-- Guarantees that every player spawns as an authentic Roblox R6 character wearing their
-- exact live Roblox avatar appearance (skin tone, shirt, pants, face, hair & accessories)
-- so custom R6 animations (Walk: 90697464892050, Run: 125757170550820, Dive: 137603926461078)
-- articulate every joint natively with zero blank/black dummy issues.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

-- 1. SAFETY CLEANUP: Destroy any blank StarterCharacter dummy that causes the "Black Mamba" bug!
local badStarterChar = StarterPlayer:FindFirstChild("StarterCharacter")
if badStarterChar then
	warn("[R6AvatarManager] Removed blank StarterCharacter from StarterPlayer so real avatars load!")
	badStarterChar:Destroy()
end

-- Fallback UserId for Studio Local Server test players (UserId <= 0)
local FALLBACK_USER_ID = (game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0) and game.CreatorId or 4883714528

local convertingPlayers: { [Player]: boolean } = {}

local function getCleanR6Description(player: Player): HumanoidDescription
	local targetUserId = (player.UserId > 0) and player.UserId or FALLBACK_USER_ID

	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(targetUserId)
	end)

	if not ok or not desc then
		desc = Instance.new("HumanoidDescription")
		-- Warm natural skin tone fallback instead of pitch black (0,0,0)
		local defaultSkin = Color3.fromRGB(234, 184, 146)
		desc.HeadColor = defaultSkin
		desc.TorsoColor = Color3.fromRGB(45, 110, 210)
		desc.LeftArmColor = defaultSkin
		desc.RightArmColor = defaultSkin
		desc.LeftLegColor = Color3.fromRGB(40, 45, 55)
		desc.RightLegColor = Color3.fromRGB(40, 45, 55)
	end

	-- Clear R15 body package mesh overrides so R6 limbs remain classic blocky R6
	-- while preserving ALL clothing, skin colors, face, t-shirt, and accessories!
	desc.Torso = 0
	desc.LeftArm = 0
	desc.RightArm = 0
	desc.LeftLeg = 0
	desc.RightLeg = 0

	return desc
end

local function ensureAuthenticR6Avatar(player: Player, character: Model)
	if convertingPlayers[player] then return end

	local hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not hum then return end

	local function stripDefaultRobloxHealth(char: Model)
		local defaultHealth = char:FindFirstChild("Health")
		if defaultHealth and defaultHealth:IsA("Script") then
			defaultHealth.Disabled = true
			defaultHealth:Destroy()
		end
	end

	-- If already R6, verify BodyColors is not pitch black from an empty template
	if hum.RigType == Enum.HumanoidRigType.R6 then
		stripDefaultRobloxHealth(character)
		local bodyColors = character:FindFirstChildOfClass("BodyColors")
		if bodyColors and bodyColors.HeadColor3 == Color3.new(0, 0, 0) and not character:FindFirstChildOfClass("Shirt") then
			convertingPlayers[player] = true
			local desc = getCleanR6Description(player)
			pcall(function()
				hum:ApplyDescription(desc)
			end)
			convertingPlayers[player] = false
		end
		print(string.format("[R6AvatarManager] ✅ %s is authentic R6 with full avatar appearance.", player.Name))
		player:SetAttribute("R6RigReady", true)
		print(string.format("[BOOT HIERARCHY] 👤 Step 1: %s verified authentic R6 character. R6RigReady=true.", player.Name))
		return
	end

	-- Convert R15 -> Official Roblox R6 Model with full avatar clothing, skin, face & accessories!
	convertingPlayers[player] = true

	local spawnCF = character:GetPivot()
	local desc = getCleanR6Description(player)

	local ok, r6Model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)

	if ok and r6Model then
		r6Model.Name = player.Name
		stripDefaultRobloxHealth(r6Model)

		-- Copy StarterCharacterScripts into the new R6 character
		local scs = StarterPlayer:FindFirstChild("StarterCharacterScripts")
		if scs then
			for _, item in ipairs(scs:GetChildren()) do
				if not r6Model:FindFirstChild(item.Name) then
					item:Clone().Parent = r6Model
				end
			end
		end

		r6Model:PivotTo(spawnCF)
		r6Model.Parent = Workspace
		player.Character = r6Model
		task.defer(function()
			if character and character.Parent then
				character:Destroy()
			end
		end)

		player:SetAttribute("R6RigReady", true)
		print(string.format("[R6AvatarManager] 🔄 Converted %s from R15 to authentic R6 with full avatar appearance!", player.Name))
		print(string.format("[BOOT HIERARCHY] 👤 Step 1: %s converted to authentic R6 character. R6RigReady=true.", player.Name))
	else
		warn(string.format("[R6AvatarManager] Failed to build R6 model for %s: %s", player.Name, tostring(r6Model)))
	end

	task.delay(0.1, function()
		convertingPlayers[player] = false
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(ensureAuthenticR6Avatar, player, character)
	end)
	if player.Character then
		task.defer(ensureAuthenticR6Avatar, player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

print("[R6AvatarManager] Initialized: Authentic Roblox R6 Avatar Pipeline active.")
