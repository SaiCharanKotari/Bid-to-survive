--!strict
-- src/client/ui/components/HammerRouletteView.luau
-- Encapsulates the SVG.5 3-slot horizontal hammer spinning roulette, needle kickers,
-- dynamic deceleration curves, multi-pitch audio clicks, and victory celebration flare.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local VERIFIED_BASE_HAMMER = "rbxassetid://99122878797775"

local HammerRouletteView = {}
HammerRouletteView.__index = HammerRouletteView

export type HammerRoulette = {
	Container: Frame,
	RouletteScale: UIScale,
	RouletteBg: ImageLabel,
	RouletteBgFallback: Frame,
	ReelClipper: Frame,
	ReelTrack: Frame,
	CenterSlotFrame: Frame,
	TopPointer: Frame,
	BottomPointer: Frame,
	SunburstRays: ImageLabel,
	IsRoulettePlaying: boolean,
	GameConfig: any,
	ShakeCamera: (intensity: number, duration: number) -> (),
	PendingAssets: {[string]: boolean},
	Play: (self: HammerRoulette, targetRarity: any, totalDuration: number?, spinnerReel: {string}?, isRoundActive: () -> boolean, sessionToken: number, getCurrentToken: () -> number) -> (),
	Stop: (self: HammerRoulette) -> (),
	IsPlaying: (self: HammerRoulette) -> boolean,
	SetVisible: (self: HammerRoulette, visible: boolean) -> (),
}

function HammerRouletteView.new(gui: ScreenGui, gameConfig: any, shakeCameraFn: ((number, number) -> ())?): HammerRoulette
	local self = setmetatable({}, HammerRouletteView) :: any
	self.GameConfig = gameConfig
	self.IsRoulettePlaying = false
	self.PendingAssets = {}
	self.ShakeCamera = shakeCameraFn or function(_i: number, _d: number) end

	-- Preload probe for rarity assets
	task.spawn(function()
		if gameConfig and gameConfig.RarityOrder and gameConfig.HammerRarities then
			for _, rarityName in ipairs(gameConfig.RarityOrder) do
				local rData = gameConfig.HammerRarities[rarityName]
				if rData and rData.AssetId then
					local testImg = Instance.new("ImageLabel")
					testImg.Image = rData.AssetId
					ContentProvider:PreloadAsync({testImg}, function(assetId, status)
						if status == Enum.AssetFetchStatus.Failure then
							self.PendingAssets[assetId] = true
						end
					end)
				end
			end
		end
	end)

	-- Root RouletteContainer
	local rouletteContainer = gui:FindFirstChild("RouletteContainer") :: Frame?
	if not rouletteContainer then
		rouletteContainer = Instance.new("Frame")
		rouletteContainer.Name = "RouletteContainer"
		rouletteContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		rouletteContainer.Position = UDim2.new(0.5, 0, 0.44, 0)
		rouletteContainer.Size = UDim2.new(0, 584, 0, 218)
		rouletteContainer.BackgroundTransparency = 1
		rouletteContainer.ZIndex = 30
		rouletteContainer.Visible = false
		rouletteContainer.Parent = gui
	end
	self.Container = rouletteContainer

	-- UIScale for responsiveness
	local rouletteScale = rouletteContainer:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	rouletteScale.Parent = rouletteContainer
	self.RouletteScale = rouletteScale

	local function updateResponsiveScale()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local scaleW = (vp.X - 32) / 670
		local scaleH = (vp.Y - 120) / 380
		rouletteScale.Scale = 1.20 * math.clamp(math.min(scaleW, scaleH), 0.58, 1.0)
	end
	task.defer(updateResponsiveScale)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateResponsiveScale)

	-- 1. SVG.5 Background & Fallback
	local rouletteBg = rouletteContainer:FindFirstChild("RouletteBg") :: ImageLabel?
	if not rouletteBg then
		rouletteBg = Instance.new("ImageLabel")
		rouletteBg.Name = "RouletteBg"
		rouletteBg.Size = UDim2.new(1, 0, 1, 0)
		rouletteBg.Position = UDim2.new(0, 0, 0, 0)
		rouletteBg.BackgroundTransparency = 1
		rouletteBg.Image = "rbxasset://textures/spin_bg.png"
		rouletteBg.ScaleType = Enum.ScaleType.Fit
		rouletteBg.ZIndex = 31
		rouletteBg.Parent = rouletteContainer
	end
	self.RouletteBg = rouletteBg

	local rouletteBgFallback = rouletteContainer:FindFirstChild("RouletteBgFallback") :: Frame?
	if not rouletteBgFallback then
		rouletteBgFallback = Instance.new("Frame")
		rouletteBgFallback.Name = "RouletteBgFallback"
		rouletteBgFallback.Size = UDim2.new(1, 0, 1, 0)
		rouletteBgFallback.BackgroundColor3 = Color3.fromRGB(255, 119, 0)
		rouletteBgFallback.BackgroundTransparency = 0
		rouletteBgFallback.ZIndex = 30

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 13)
		bgCorner.Parent = rouletteBgFallback

		local bgStroke = Instance.new("UIStroke")
		bgStroke.Color = Color3.fromRGB(0, 0, 0)
		bgStroke.Thickness = 3
		bgStroke.Parent = rouletteBgFallback

		rouletteBgFallback.Parent = rouletteContainer
	end
	self.RouletteBgFallback = rouletteBgFallback

	-- 2. Reel Clipper & Track
	local reelClipper = rouletteContainer:FindFirstChild("ReelClipper") :: Frame?
	if not reelClipper then
		reelClipper = Instance.new("Frame")
		reelClipper.Name = "ReelClipper"
		reelClipper.Size = UDim2.new(0, 566, 0, 200)
		reelClipper.Position = UDim2.new(0.5, 0, 0.5, 0)
		reelClipper.AnchorPoint = Vector2.new(0.5, 0.5)
		reelClipper.BackgroundTransparency = 1
		reelClipper.BorderSizePixel = 0
		reelClipper.ClipsDescendants = true
		reelClipper.ZIndex = 33
		reelClipper.Parent = rouletteContainer

		local clipperGradient = Instance.new("UIGradient")
		clipperGradient.Name = "ClipperGradient"
		clipperGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 1.00),
			NumberSequenceKeypoint.new(0.08, 0.50),
			NumberSequenceKeypoint.new(0.20, 0.00),
			NumberSequenceKeypoint.new(0.80, 0.00),
			NumberSequenceKeypoint.new(0.92, 0.50),
			NumberSequenceKeypoint.new(1.00, 1.00),
		})
		clipperGradient.Parent = reelClipper
	end
	self.ReelClipper = reelClipper

	local reelTrack = reelClipper:FindFirstChild("ReelTrack") :: Frame?
	if not reelTrack then
		reelTrack = Instance.new("Frame")
		reelTrack.Name = "ReelTrack"
		reelTrack.Size = UDim2.new(0, 15000, 1, 0)
		reelTrack.Position = UDim2.new(0, 0, 0, 0)
		reelTrack.BackgroundTransparency = 1
		reelTrack.BorderSizePixel = 0
		reelTrack.ZIndex = 33
		reelTrack.Parent = reelClipper
	end
	self.ReelTrack = reelTrack

	-- 3. Center Result Slot Frame
	local centerSlotFrame = rouletteContainer:FindFirstChild("CenterSlotFrame") :: Frame?
	if not centerSlotFrame then
		centerSlotFrame = Instance.new("Frame")
		centerSlotFrame.Name = "CenterSlotFrame"
		centerSlotFrame.Size = UDim2.new(0, 199, 0, 199)
		centerSlotFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		centerSlotFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		centerSlotFrame.BackgroundTransparency = 1
		centerSlotFrame.BorderSizePixel = 0
		centerSlotFrame.ZIndex = 36

		local csCorner = Instance.new("UICorner")
		csCorner.CornerRadius = UDim.new(0, 5)
		csCorner.Parent = centerSlotFrame

		local csStroke = Instance.new("UIStroke")
		csStroke.Name = "CenterStroke"
		csStroke.Color = Color3.fromRGB(255, 255, 255)
		csStroke.Thickness = 2.5
		csStroke.Parent = centerSlotFrame

		centerSlotFrame.Parent = rouletteContainer
	end
	self.CenterSlotFrame = centerSlotFrame

	-- Top & Bottom Needles
	local topPointer = centerSlotFrame:FindFirstChild("TopPointer") :: Frame?
	if not topPointer then
		topPointer = Instance.new("Frame")
		topPointer.Name = "TopPointer"
		topPointer.Size = UDim2.new(0, 26, 0, 15)
		topPointer.Position = UDim2.new(0.5, 0, 0, -3)
		topPointer.AnchorPoint = Vector2.new(0.5, 1)
		topPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		topPointer.BorderSizePixel = 0
		topPointer.ZIndex = 40

		local tpCorner = Instance.new("UICorner")
		tpCorner.CornerRadius = UDim.new(0, 3)
		tpCorner.Parent = topPointer

		local tpStroke = Instance.new("UIStroke")
		tpStroke.Color = Color3.fromRGB(0, 0, 0)
		tpStroke.Thickness = 2
		tpStroke.Parent = topPointer

		local tpArrow = Instance.new("TextLabel")
		tpArrow.Name = "Arrow"
		tpArrow.Size = UDim2.new(1, 0, 1, 0)
		tpArrow.BackgroundTransparency = 1
		tpArrow.Font = Enum.Font.GothamBlack
		tpArrow.TextSize = 13
		tpArrow.TextColor3 = Color3.fromRGB(0, 0, 0)
		tpArrow.Text = "▼"
		tpArrow.ZIndex = 41
		tpArrow.Parent = topPointer

		topPointer.Parent = centerSlotFrame
	end
	self.TopPointer = topPointer

	local bottomPointer = centerSlotFrame:FindFirstChild("BottomPointer") :: Frame?
	if not bottomPointer then
		bottomPointer = Instance.new("Frame")
		bottomPointer.Name = "BottomPointer"
		bottomPointer.Size = UDim2.new(0, 26, 0, 15)
		bottomPointer.Position = UDim2.new(0.5, 0, 1, 3)
		bottomPointer.AnchorPoint = Vector2.new(0.5, 0)
		bottomPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		bottomPointer.BorderSizePixel = 0
		bottomPointer.ZIndex = 40

		local bpCorner = Instance.new("UICorner")
		bpCorner.CornerRadius = UDim.new(0, 3)
		bpCorner.Parent = bottomPointer

		local bpStroke = Instance.new("UIStroke")
		bpStroke.Color = Color3.fromRGB(0, 0, 0)
		bpStroke.Thickness = 2
		bpStroke.Parent = bottomPointer

		local bpArrow = Instance.new("TextLabel")
		bpArrow.Name = "Arrow"
		bpArrow.Size = UDim2.new(1, 0, 1, 0)
		bpArrow.BackgroundTransparency = 1
		bpArrow.Font = Enum.Font.GothamBlack
		bpArrow.TextSize = 13
		bpArrow.TextColor3 = Color3.fromRGB(0, 0, 0)
		bpArrow.Text = "▲"
		bpArrow.ZIndex = 41
		bpArrow.Parent = bottomPointer

		bottomPointer.Parent = centerSlotFrame
	end
	self.BottomPointer = bottomPointer

	-- Sunburst Rays
	local sunburstRays = centerSlotFrame:FindFirstChild("SunburstRays") :: ImageLabel?
	if not sunburstRays then
		sunburstRays = Instance.new("ImageLabel")
		sunburstRays.Name = "SunburstRays"
		sunburstRays.Size = UDim2.new(0, 185, 0, 185)
		sunburstRays.Position = UDim2.new(0.5, 0, 0.5, -8)
		sunburstRays.AnchorPoint = Vector2.new(0.5, 0.5)
		sunburstRays.BackgroundTransparency = 1
		sunburstRays.Image = "rbxassetid://2583861218"
		sunburstRays.ImageColor3 = Color3.fromRGB(255, 225, 100)
		sunburstRays.ImageTransparency = 1
		sunburstRays.ScaleType = Enum.ScaleType.Fit
		sunburstRays.ZIndex = 32
		sunburstRays.Visible = false
		sunburstRays.Parent = centerSlotFrame
	end
	self.SunburstRays = sunburstRays

	function self:Play(targetRarity: any, totalDuration: number?, spinnerReel: {string}?, isRoundActive: () -> boolean, sessionToken: number, getCurrentToken: () -> number)
		if self.IsRoulettePlaying then return end
		if isRoundActive and not isRoundActive() then return end
		self.IsRoulettePlaying = true
		local myToken = sessionToken

		if typeof(targetRarity) == "string" then
			targetRarity = (self.GameConfig and self.GameConfig.HammerRarities and self.GameConfig.HammerRarities[targetRarity]) or {
				Name = targetRarity,
				DamagePercent = 30,
				Color = Color3.fromRGB(220, 225, 235),
				GlowColor = Color3.fromRGB(240, 240, 255),
				AssetId = VERIFIED_BASE_HAMMER,
			}
		elseif typeof(targetRarity) ~= "table" then
			targetRarity = (self.GameConfig and self.GameConfig.HammerRarities and self.GameConfig.HammerRarities.Common) or {
				Name = "Common",
				DamagePercent = 20,
				Color = Color3.fromRGB(200, 200, 200),
				GlowColor = Color3.fromRGB(220, 220, 220),
				AssetId = VERIFIED_BASE_HAMMER,
			}
		end

		local csStroke = self.CenterSlotFrame:FindFirstChild("CenterStroke") :: UIStroke?
		if csStroke then
			csStroke.Color = Color3.fromRGB(255, 255, 255)
			csStroke.Thickness = 2.0
			csStroke.Transparency = 0
		end

		for _, child in ipairs(self.ReelTrack:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local CARD_STEP = 190
		local TOTAL_CARDS = 60
		local WIN_INDEX = 10
		local SPIN_TRAVEL_CARDS = 35

		local raritiesList = (self.GameConfig and self.GameConfig.GetRarityList and self.GameConfig.GetRarityList()) or {}
		if #raritiesList == 0 and self.GameConfig and self.GameConfig.HammerRarities then
			for _, name in ipairs(self.GameConfig.RarityOrder or {"Common", "Uncommon", "Rare", "Legendary", "Mythical"}) do
				table.insert(raritiesList, self.GameConfig.HammerRarities[name])
			end
		end

		local reelData = {}
		for i = 1, TOTAL_CARDS do
			if i == WIN_INDEX then
				reelData[i] = targetRarity
			elseif i == WIN_INDEX + 1 then
				local alt = (self.GameConfig and self.GameConfig.HammerRarities and (self.GameConfig.HammerRarities.Legendary or self.GameConfig.HammerRarities.Mythical))
				if alt and alt.Name == targetRarity.Name then
					alt = self.GameConfig.HammerRarities.Rare or self.GameConfig.HammerRarities.Common
				end
				reelData[i] = alt or targetRarity
			elseif i == WIN_INDEX - 1 then
				local alt = (self.GameConfig and self.GameConfig.HammerRarities and (self.GameConfig.HammerRarities.Rare or self.GameConfig.HammerRarities.Uncommon))
				if alt and alt.Name == targetRarity.Name then
					alt = self.GameConfig.HammerRarities.Common
				end
				reelData[i] = alt or targetRarity
			elseif spinnerReel and spinnerReel[i] and self.GameConfig and self.GameConfig.HammerRarities and self.GameConfig.HammerRarities[spinnerReel[i]] then
				reelData[i] = self.GameConfig.HammerRarities[spinnerReel[i]]
			else
				local pick = raritiesList[math.random(1, math.max(1, #raritiesList))]
				if i > 1 and reelData[i - 1] and pick and reelData[i - 1].Name == pick.Name then
					local alt = raritiesList[(math.random(1, math.max(1, #raritiesList - 1)))]
					pick = (alt and alt.Name ~= pick.Name) and alt or raritiesList[1]
				end
				reelData[i] = pick or targetRarity
			end
		end

		local items = {}
		for i = 1, TOTAL_CARDS do
			local rData = reelData[i]
			if typeof(rData) == "string" and self.GameConfig and self.GameConfig.HammerRarities then
				rData = self.GameConfig.HammerRarities[rData] or targetRarity
			elseif typeof(rData) ~= "table" then
				rData = targetRarity
			end

			local itemFrame = Instance.new("Frame")
			itemFrame.Name = "HammerItem_" .. i
			itemFrame.Size = UDim2.new(0, 190, 0, 199)
			itemFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			local cardCenterX = (i - 1) * CARD_STEP
			itemFrame.Position = UDim2.new(0, cardCenterX, 0.5, 0)
			itemFrame.BackgroundTransparency = 1
			itemFrame.BorderSizePixel = 0
			itemFrame.ZIndex = 34

			local icon = Instance.new("ImageLabel")
			icon.Name = "HammerIcon"
			icon.Size = UDim2.new(0, 140, 0, 140)
			icon.Position = UDim2.new(0.5, 0, 0, 14)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.BackgroundTransparency = 1
			icon.ScaleType = Enum.ScaleType.Fit
			local assetId = rData.AssetId
			if not assetId or assetId == "" or self.PendingAssets[assetId] then
				assetId = VERIFIED_BASE_HAMMER
			end
			icon.Image = assetId
			icon.ZIndex = 35
			icon.Parent = itemFrame

			local dmgLabel = Instance.new("TextLabel")
			dmgLabel.Name = "DmgLabel"
			dmgLabel.Size = UDim2.new(1, 0, 0, 26)
			dmgLabel.Position = UDim2.new(0.5, 0, 1, -16)
			dmgLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			dmgLabel.BackgroundTransparency = 1
			dmgLabel.Font = Enum.Font.FredokaOne
			dmgLabel.TextSize = 22
			dmgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			dmgLabel.Text = string.format("+%d dmg", rData.DamagePercent or 30)
			dmgLabel.TextXAlignment = Enum.TextXAlignment.Center
			dmgLabel.TextStrokeTransparency = 0.5
			dmgLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			dmgLabel.ZIndex = 36
			dmgLabel.Parent = itemFrame

			itemFrame.Parent = self.ReelTrack
			items[i] = {
				frame = itemFrame,
				icon = icon,
				label = dmgLabel,
				relX = cardCenterX,
			}
		end

		local function updateOpacities(curTrackX)
			for i = 1, TOTAL_CARDS do
				local it = items[i]
				local screenX = curTrackX + it.relX
				local dist = math.abs(screenX - 283)
				if dist >= 270 then
					it.frame.Visible = false
					it.icon.ImageTransparency = 1
					it.label.TextTransparency = 1
				else
					it.frame.Visible = true
					local currentScale = 1.0
					if dist <= 40 then
						it.icon.ImageTransparency = 0
						currentScale = 1.0
					elseif dist <= 190 then
						local t = (dist - 40) / 150
						it.icon.ImageTransparency = t * 0.45
						currentScale = 1.0 - (t * 0.16)
					else
						local t = (dist - 190) / 80
						it.icon.ImageTransparency = math.clamp(0.45 + t * 0.55, 0, 1)
						currentScale = math.clamp(0.84 - (t * 0.16), 0.68, 0.84)
					end

					local iconSize = math.round(140 * currentScale)
					local iconY = math.round(14 + (140 - iconSize) * 0.5)
					it.icon.Size = UDim2.new(0, iconSize, 0, iconSize)
					it.icon.Position = UDim2.new(0.5, 0, 0, iconY)

					if dist <= 25 then
						it.label.TextTransparency = 0
						it.label.Visible = true
					elseif dist <= 55 then
						it.label.TextTransparency = (dist - 25) / 30
						it.label.Visible = true
					else
						it.label.TextTransparency = 1
						it.label.Visible = false
					end
				end
			end
		end

		local targetCardCenter = (WIN_INDEX - 1) * CARD_STEP
		local trackX_final = 283 - targetCardCenter
		local travelDistance = SPIN_TRAVEL_CARDS * CARD_STEP
		local trackX_start = trackX_final - travelDistance
		local trackX_overshoot = trackX_final + 12

		local function kickNeedles()
			if self.TopPointer then
				self.TopPointer.Position = UDim2.new(0.5, 0, 0, -6)
				TweenService:Create(self.TopPointer, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 0, -3),
				}):Play()
			end
			if self.BottomPointer then
				self.BottomPointer.Position = UDim2.new(0.5, 0, 1, 6)
				TweenService:Create(self.BottomPointer, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, 0, 1, 3),
				}):Play()
			end
		end

		self.ReelTrack.Position = UDim2.new(0, math.round(trackX_start), 0, 0)
		updateOpacities(trackX_start)

		-- Stage 1: Fast Spin
		local spinProgress = Instance.new("NumberValue")
		spinProgress.Value = 0

		local lastTickStep = -1
		local progressConn = spinProgress.Changed:Connect(function(val)
			if (isRoundActive and not isRoundActive()) or (getCurrentToken and myToken ~= getCurrentToken()) then return end
			local curX = trackX_start + (trackX_overshoot - trackX_start) * val
			self.ReelTrack.Position = UDim2.new(0, math.round(curX), 0, 0)
			updateOpacities(curX)

			local currentStep = math.floor((curX - trackX_start) / CARD_STEP)
			if currentStep ~= lastTickStep and currentStep >= 0 then
				lastTickStep = currentStep
				kickNeedles()

				pcall(function()
					local tickSound = Instance.new("Sound")
					tickSound.SoundId = "rbxassetid://6895079853"
					local basePitch = 1.55 - (val * 0.70)
					tickSound.PlaybackSpeed = math.clamp(basePitch, 0.85, 1.65)
					-- Increased sound volume by 50%
					tickSound.Volume = (val >= 0.85) and 0.60 or (0.24 + val * 0.21)
					tickSound.Parent = SoundService
					tickSound:Play()
					Debris:AddItem(tickSound, 0.25)

					if val >= 0.85 then
						local thud = Instance.new("Sound")
						thud.SoundId = "rbxasset://sounds/action_jump.mp3"
						thud.PlaybackSpeed = 0.82
						thud.Volume = 0.42 -- Increased by 50% (was 0.28)
						thud.Parent = SoundService
						thud:Play()
						Debris:AddItem(thud, 0.3)
					end
				end)
			end
		end)

		local spinTween1 = TweenService:Create(spinProgress, TweenInfo.new(4.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Value = 1,
		})

		spinTween1:Play()
		self.Container.Visible = true

		spinTween1.Completed:Wait()
		progressConn:Disconnect()
		spinProgress:Destroy()

		if (isRoundActive and not isRoundActive()) or (getCurrentToken and myToken ~= getCurrentToken()) then
			self.Container.Visible = false
			self.IsRoulettePlaying = false
			return
		end

		task.wait(0.06)

		-- Stage 2: Recoil Snap
		local recoilProgress = Instance.new("NumberValue")
		recoilProgress.Value = 0
		local recoilConn = recoilProgress.Changed:Connect(function(rVal)
			if (isRoundActive and not isRoundActive()) or (getCurrentToken and myToken ~= getCurrentToken()) then return end
			local rX = trackX_overshoot + (trackX_final - trackX_overshoot) * rVal
			self.ReelTrack.Position = UDim2.new(0, math.round(rX), 0, 0)
			updateOpacities(rX)
		end)

		local recoilTween = TweenService:Create(recoilProgress, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Value = 1,
		})
		recoilTween:Play()
		kickNeedles()

		pcall(function()
			local lockSound = Instance.new("Sound")
			lockSound.SoundId = "rbxassetid://6895079853"
			lockSound.PlaybackSpeed = 1.05
			lockSound.Volume = 0.83 -- Increased by 50% (was 0.55)
			lockSound.Parent = SoundService
			lockSound:Play()
			Debris:AddItem(lockSound, 0.3)
		end)

		recoilTween.Completed:Wait()
		recoilConn:Disconnect()
		recoilProgress:Destroy()

		if (isRoundActive and not isRoundActive()) or (getCurrentToken and myToken ~= getCurrentToken()) then
			self.Container.Visible = false
			self.IsRoulettePlaying = false
			return
		end

		self.ReelTrack.Position = UDim2.new(0, math.round(trackX_final), 0, 0)
		updateOpacities(trackX_final)

		-- Victory Reveal
		local winningItem = items[WIN_INDEX]
		local raySpinConn = nil

		if self.SunburstRays then
			self.SunburstRays.Visible = true
			self.SunburstRays.ImageTransparency = 0.55
			self.SunburstRays.Rotation = 0
			raySpinConn = RunService.RenderStepped:Connect(function(dt)
				self.SunburstRays.Rotation = (self.SunburstRays.Rotation + dt * 60) % 360
			end)
		end

		if winningItem then
			winningItem.icon.Size = UDim2.new(0, 168, 0, 168)
			winningItem.icon.Position = UDim2.new(0.5, 0, 0, 0)
			winningItem.icon.Rotation = -6
			TweenService:Create(winningItem.icon, TweenInfo.new(0.40, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 148, 0, 148),
				Position = UDim2.new(0.5, 0, 0, 10),
				Rotation = 0,
			}):Play()

			winningItem.label.TextSize = 27
			winningItem.label.TextColor3 = Color3.fromRGB(255, 245, 180)
			TweenService:Create(winningItem.label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextSize = 22,
				TextColor3 = Color3.fromRGB(255, 255, 255),
			}):Play()
		end

		local targetGlowColor = targetRarity.GlowColor or targetRarity.Color or Color3.fromRGB(255, 220, 50)
		if csStroke then
			csStroke.Color = targetGlowColor
			csStroke.Thickness = 4.5
			TweenService:Create(csStroke, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Thickness = 2.5,
			}):Play()
		end

		if self.TopPointer and self.BottomPointer then
			self.TopPointer.BackgroundColor3 = targetGlowColor
			self.BottomPointer.BackgroundColor3 = targetGlowColor
		end

		self.ShakeCamera(targetRarity.CameraShake or 1.1, 0.45)
		pcall(function()
			local winSound = Instance.new("Sound")
			winSound.SoundId = "rbxasset://sounds/action_get_up.mp3"
			winSound.PlaybackSpeed = 1.05
			winSound.Volume = 1.28 -- Increased by 50% (was 0.85)
			winSound.Parent = SoundService
			winSound:Play()
			Debris:AddItem(winSound, 1.8)
		end)

		task.wait(2.0)

		if (isRoundActive and not isRoundActive()) or (getCurrentToken and myToken ~= getCurrentToken()) then
			if raySpinConn then raySpinConn:Disconnect() end
			if self.SunburstRays then self.SunburstRays.Visible = false end
			self.Container.Visible = false
			self.IsRoulettePlaying = false
			return
		end

		-- Fade-out
		local fadeTweens = {}
		table.insert(fadeTweens, TweenService:Create(self.RouletteBg, TweenInfo.new(0.35), { ImageTransparency = 1 }))
		if self.RouletteBgFallback then
			table.insert(fadeTweens, TweenService:Create(self.RouletteBgFallback, TweenInfo.new(0.35), { BackgroundTransparency = 1 }))
		end
		if csStroke then
			table.insert(fadeTweens, TweenService:Create(csStroke, TweenInfo.new(0.35), { Transparency = 1 }))
		end
		if self.CenterSlotFrame then
			table.insert(fadeTweens, TweenService:Create(self.CenterSlotFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }))
		end
		if self.TopPointer and self.BottomPointer then
			local tpSt = self.TopPointer:FindFirstChildOfClass("UIStroke")
			local bpSt = self.BottomPointer:FindFirstChildOfClass("UIStroke")
			if tpSt then table.insert(fadeTweens, TweenService:Create(tpSt, TweenInfo.new(0.35), { Transparency = 1 })) end
			if bpSt then table.insert(fadeTweens, TweenService:Create(bpSt, TweenInfo.new(0.35), { Transparency = 1 })) end
		end
		if self.SunburstRays then
			table.insert(fadeTweens, TweenService:Create(self.SunburstRays, TweenInfo.new(0.35), { ImageTransparency = 1 }))
		end
		if winningItem then
			table.insert(fadeTweens, TweenService:Create(winningItem.icon, TweenInfo.new(0.35), { ImageTransparency = 1 }))
			table.insert(fadeTweens, TweenService:Create(winningItem.label, TweenInfo.new(0.35), { TextTransparency = 1 }))
		end
		for _, tw in ipairs(fadeTweens) do tw:Play() end
		task.wait(0.35)

		if raySpinConn then raySpinConn:Disconnect() end
		if self.SunburstRays then
			self.SunburstRays.Visible = false
			self.SunburstRays.ImageTransparency = 1
		end
		self.Container.Visible = false
		self.RouletteBg.ImageTransparency = 0
		if self.RouletteBgFallback then
			self.RouletteBgFallback.BackgroundTransparency = 0
		end
		if self.CenterSlotFrame then
			self.CenterSlotFrame.BackgroundTransparency = 1
		end
		if csStroke then
			csStroke.Transparency = 0
			csStroke.Thickness = 2.5
			csStroke.Color = Color3.fromRGB(255, 255, 255)
		end
		if self.TopPointer and self.BottomPointer then
			self.TopPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
			self.BottomPointer.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
			local tpSt = self.TopPointer:FindFirstChildOfClass("UIStroke")
			local bpSt = self.BottomPointer:FindFirstChildOfClass("UIStroke")
			if tpSt then tpSt.Transparency = 0 end
			if bpSt then bpSt.Transparency = 0 end
		end
		self.IsRoulettePlaying = false
	end

	function self:Stop()
		self.Container.Visible = false
		self.IsRoulettePlaying = false
	end

	function self:IsPlaying(): boolean
		return self.IsRoulettePlaying
	end

	function self:SetVisible(visible: boolean)
		self.Container.Visible = visible
		if not visible then
			self.IsRoulettePlaying = false
		end
	end

	return self
end

return HammerRouletteView
