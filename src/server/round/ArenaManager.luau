--!strict
-- src/server/round/ArenaManager.luau
-- Manages arena and lobby teleportation, winner safety glow highlights,
-- and the instant water fall rescue monitor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ArenaManager = {}
ArenaManager.__index = ArenaManager

local spawnArea: Instance? = nil
local gameplayArea: Instance? = nil
local walkway: BasePart? = nil
local waterRescueConn: RBXScriptConnection? = nil
local lastWaterRescue: {[number]: number} = {}

function ArenaManager.Init(sArea: Instance?, gpArea: Instance?, walkPart: BasePart?)
	spawnArea = sArea
	gameplayArea = gpArea
	walkway = walkPart
end

function ArenaManager.TeleportCharacter(char: Model, targetPos: Vector3)
	if not char or not char.Parent then return end
	local hrp = char:WaitForChild("HumanoidRootPart", 3) :: BasePart?
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		char:PivotTo(CFrame.new(targetPos))
		task.wait(0.05)
		char:PivotTo(CFrame.new(targetPos))
	end
end

function ArenaManager.TeleportToLobby(player: Player)
	local char = player.Character
	if not char then return end
	local lobbySpawn = spawnArea and spawnArea:FindFirstChild("LobbySpawn") :: BasePart?
	local basePos = lobbySpawn and lobbySpawn.Position or Vector3.new(48.11, 85.14, 2.92)
	local offset = Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
	ArenaManager.TeleportCharacter(char, basePos + offset)
end

function ArenaManager.TeleportToArena(player: Player)
	local char = player.Character
	if not char or not walkway then return end
	local wPos = walkway.Position
	local rx = math.random(-45, 45)
	local rz = math.random(-35, 35)
	local targetPos = Vector3.new(wPos.X + rx, wPos.Y + 3.5, wPos.Z + rz)
	ArenaManager.TeleportCharacter(char, targetPos)
end

function ArenaManager.RecoverToPlayArea(char: Model)
	if not char or not char.Parent or not walkway then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		local wPos = walkway.Position
		local rx = math.random(-30, 30)
		local rz = math.random(-30, 30)
		local safePos = Vector3.new(wPos.X + rx, wPos.Y + 3.5, wPos.Z + rz)
		char:PivotTo(CFrame.new(safePos))
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

function ArenaManager.ApplyWinnerGlow(char: Model?)
	if not char then return end
	local old = char:FindFirstChild("SafeBidGlow")
	if old then old:Destroy() end

	local hl = Instance.new("Highlight")
	hl.Name = "SafeBidGlow"
	hl.FillColor = Color3.fromRGB(0, 255, 120)
	hl.OutlineColor = Color3.fromRGB(220, 255, 230)
	hl.FillTransparency = 0.25
	hl.OutlineTransparency = 0
	hl.Parent = char
end

function ArenaManager.ClearWinnerGlow(activeBots: {any}?)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local hl = player.Character:FindFirstChild("SafeBidGlow")
			if hl then hl:Destroy() end
		end
	end
	if activeBots then
		for _, bot in ipairs(activeBots) do
			if bot.Character then
				local hl = bot.Character:FindFirstChild("SafeBidGlow")
				if hl then hl:Destroy() end
			end
		end
	end
end

function ArenaManager.StartWaterRescueMonitor(playerDataGetter: () -> {[number]: any})
	if waterRescueConn then
		waterRescueConn:Disconnect()
		waterRescueConn = nil
	end

	waterRescueConn = RunService.Heartbeat:Connect(function()
		if not walkway then return end
		local now = os.clock()
		local playerData = playerDataGetter and playerDataGetter()

		if playerData then
			for userId, data in pairs(playerData) do
				if data.IsAlive and data.ParticipationState == "Active" then
					local char = data.Character
					if not char or not char.Parent then
						if not data.IsBot then
							local p = Players:GetPlayerByUserId(userId)
							char = p and p.Character
							data.Character = char
						end
					end

					if char and char.Parent then
						local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
						local hum = char:FindFirstChildOfClass("Humanoid")
						if hrp and hum and hum.Health > 0 then
							local inPlayArea = (hrp.Position.X < -50)
							local hitWater = (hrp.Position.Y <= 34.5) or (hum:GetState() == Enum.HumanoidStateType.Swimming)

							if inPlayArea and hitWater then
								if not lastWaterRescue[userId] or (now - lastWaterRescue[userId]) > 0.15 then
									lastWaterRescue[userId] = now
									ArenaManager.RecoverToPlayArea(char)
								end
							end
						end
					end
				end
			end
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local inPlayArea = (hrp.Position.X < -50) or (player:GetAttribute("IsInGame") == true and hrp.Position.X < 0)
				local hitWater = (hrp.Position.Y <= 34.5) or (hum:GetState() == Enum.HumanoidStateType.Swimming)
				if inPlayArea and hitWater then
					if not lastWaterRescue[player.UserId] or (now - lastWaterRescue[player.UserId]) > 0.15 then
						lastWaterRescue[player.UserId] = now
						ArenaManager.RecoverToPlayArea(char)
					end
				end
			end
		end
	end)
end

function ArenaManager.StopWaterRescueMonitor()
	if waterRescueConn then
		waterRescueConn:Disconnect()
		waterRescueConn = nil
	end
end

return ArenaManager
