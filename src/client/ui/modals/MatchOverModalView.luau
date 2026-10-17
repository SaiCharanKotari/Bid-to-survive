--!strict
-- src/client/ui/modals/MatchOverModalView.luau
-- Manages the Match Over / Results podium modal (1st, 2nd, 3rd places),
-- avatar headshots, survival time pills, responsive scaling, and victory animations.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RESULTS_BG_ASSET = "rbxassetid://136247699248783"

local MatchOverModalView = {}
MatchOverModalView.__index = MatchOverModalView

export type MatchOverModal = {
	ModalFrame: Frame,
	CardFrame: Frame,
	PodiumContainer: Frame,
	CloseResultsBtn: TextButton,
	Show: (self: MatchOverModal, data: any, localPlayer: Player) -> (),
	Hide: (self: MatchOverModal) -> (),
	IsVisible: (self: MatchOverModal) -> boolean,
	SetVisible: (self: MatchOverModal, visible: boolean) -> (),
}

local function formatSurvivalTime(seconds: number?): string
	local totalSecs = math.max(0, math.floor(seconds or 83))
	local m = math.floor(totalSecs / 60)
	local s = totalSecs % 60
	return string.format("Time:- %dm %02d sec", m, s)
end

local function formatPodiumName(name: string?): string
	local str = tostring(name or "Player")
	if string.sub(str, 1, 1) == "@" then
		return str
	end
	return "@" .. str
end

local function getAvatarHeadshot(userId: number?): string
	local id = tonumber(userId)
	if id and id > 0 then
		return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", id)
	end
	return "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150"
end

local function createPodiumColumn(parent: Frame, rank: number, data: any, config: any, localPlayer: Player)
	local col = Instance.new("Frame")
	col.Name = "Col_" .. rank
	col.Size = UDim2.new(0, 122, 1, 0)
	col.Position = config.colPosition
	col.AnchorPoint = config.colAnchor
	col.BackgroundTransparency = 1
	col.BorderSizePixel = 0
	col.ZIndex = 46

	local isMe = localPlayer and ((data.UserId == localPlayer.UserId) or (data.Name == localPlayer.Name) or (data.DisplayName == localPlayer.DisplayName))

	-- 1. Profile Box
	local profileBox = Instance.new("Frame")
	profileBox.Name = "ProfileBox"
	profileBox.Size = UDim2.new(0, 122, 0, 111)
	profileBox.Position = UDim2.new(0.5, 0, 0, config.boxY)
	profileBox.AnchorPoint = Vector2.new(0.5, 0)
	profileBox.BackgroundColor3 = Color3.fromRGB(217, 217, 217)
	profileBox.BorderSizePixel = 0
	profileBox.ZIndex = 46

	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(0, 4)
	pbCorner.Parent = profileBox

	local pbStroke = Instance.new("UIStroke")
	if isMe then
		pbStroke.Color = Color3.fromRGB(255, 215, 0)
		pbStroke.Thickness = 3.5
	else
		pbStroke.Color = Color3.fromRGB(0, 0, 0)
		pbStroke.Thickness = 2.5
	end
	pbStroke.Parent = profileBox

	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Name = "AvatarImg"
	avatarImg.Size = UDim2.new(1, -4, 1, -4)
	avatarImg.Position = UDim2.new(0.5, 0, 0.5, 0)
	avatarImg.AnchorPoint = Vector2.new(0.5, 0.5)
	avatarImg.BackgroundTransparency = 1
	avatarImg.Image = getAvatarHeadshot(data.UserId)
	avatarImg.ScaleType = Enum.ScaleType.Fit
	avatarImg.ZIndex = 47

	local avCorner = Instance.new("UICorner")
	avCorner.CornerRadius = UDim.new(0, 3)
	avCorner.Parent = avatarImg
	avatarImg.Parent = profileBox
	profileBox.Parent = col

	-- 2. Username Pill
	local userPill = Instance.new("Frame")
	userPill.Name = "UserPill"
	userPill.Size = UDim2.new(0, 110, 0, 24)
	userPill.Position = UDim2.new(0.5, 0, 0, config.pill1Y)
	userPill.AnchorPoint = Vector2.new(0.5, 0)
	userPill.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
	userPill.BorderSizePixel = 0
	userPill.ZIndex = 47

	local upCorner = Instance.new("UICorner")
	upCorner.CornerRadius = UDim.new(0, 12)
	upCorner.Parent = userPill

	local upStroke = Instance.new("UIStroke")
	upStroke.Color = isMe and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
	upStroke.Thickness = isMe and 2 or 1.5
	upStroke.Parent = userPill

	local userLabel = Instance.new("TextLabel")
	userLabel.Size = UDim2.new(1, -10, 1, 0)
	userLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	userLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	userLabel.BackgroundTransparency = 1
	local podiumDispName = (isMe and localPlayer.DisplayName) or data.DisplayName
	if (not podiumDispName or podiumDispName == data.Name) and data.UserId and data.UserId > 0 then
		local pObj = Players:GetPlayerByUserId(data.UserId)
		if pObj then podiumDispName = pObj.DisplayName end
	end
	userLabel.Text = formatPodiumName(podiumDispName or data.Name or "Player")
	userLabel.Font = Enum.Font.GothamBold
	userLabel.TextSize = 11
	userLabel.TextScaled = true
	userLabel.TextColor3 = isMe and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(255, 255, 255)
	userLabel.TextTruncate = Enum.TextTruncate.AtEnd
	userLabel.TextXAlignment = Enum.TextXAlignment.Center
	userLabel.ZIndex = 48

	local userSizeConstraint = Instance.new("UITextSizeConstraint")
	userSizeConstraint.MaxTextSize = 12
	userSizeConstraint.MinTextSize = 8
	userSizeConstraint.Parent = userLabel
	userLabel.Parent = userPill
	userPill.Parent = col

	-- 3. Time Pill
	local timePill = Instance.new("Frame")
	timePill.Name = "TimePill"
	timePill.Size = UDim2.new(0, 110, 0, 24)
	timePill.Position = UDim2.new(0.5, 0, 0, config.pill2Y)
	timePill.AnchorPoint = Vector2.new(0.5, 0)
	timePill.BackgroundColor3 = Color3.fromRGB(33, 33, 33)
	timePill.BorderSizePixel = 0
	timePill.ZIndex = 47

	local tpCorner = Instance.new("UICorner")
	tpCorner.CornerRadius = UDim.new(0, 12)
	tpCorner.Parent = timePill

	local tpStroke = Instance.new("UIStroke")
	tpStroke.Color = Color3.fromRGB(255, 255, 255)
	tpStroke.Thickness = 1.5
	tpStroke.Parent = timePill

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Size = UDim2.new(1, -10, 1, 0)
	timeLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	timeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = formatSurvivalTime(data.SurvivalTime)
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.TextSize = 10
	timeLabel.TextScaled = true
	timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	timeLabel.TextXAlignment = Enum.TextXAlignment.Center
	timeLabel.ZIndex = 48

	local timeSizeConstraint = Instance.new("UITextSizeConstraint")
	timeSizeConstraint.MaxTextSize = 11
	timeSizeConstraint.MinTextSize = 7
	timeSizeConstraint.Parent = timeLabel
	timeLabel.Parent = timePill
	timePill.Parent = col

	-- 4. Big Bold Rank Text
	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.Size = UDim2.new(0, 108, 0, 48)
	rankLabel.Position = UDim2.new(0.5, 0, 0, config.rankY)
	rankLabel.AnchorPoint = Vector2.new(0.5, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = "#" .. tostring(rank)
	rankLabel.Font = Enum.Font.GothamBlack
	rankLabel.TextSize = config.rankSize
	rankLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	rankLabel.ZIndex = 49

	local rkStroke = Instance.new("UIStroke")
	rkStroke.Color = Color3.fromRGB(0, 0, 0)
	rkStroke.Thickness = config.rankStroke
	rkStroke.Parent = rankLabel
	rankLabel.Parent = col

	col.Parent = parent
	return col
end

function MatchOverModalView.new(gui: ScreenGui, onVisibilityChanged: (() -> ())?): MatchOverModal
	local self = setmetatable({}, MatchOverModalView) :: any

	local matchOverModal = (gui:WaitForChild("MatchOverModal", 5) or gui:FindFirstChild("MatchOverModal")) :: Frame?
	if not matchOverModal then
		matchOverModal = Instance.new("Frame")
		matchOverModal.Name = "MatchOverModal"
		matchOverModal.AnchorPoint = Vector2.new(0.5, 0.5)
		matchOverModal.Position = UDim2.new(0.5, 0, 0.5, 0)
		matchOverModal.Size = UDim2.new(0, 560, 0, 420)
		matchOverModal.BackgroundTransparency = 1
		matchOverModal.BorderSizePixel = 0
		matchOverModal.ZIndex = 40
		matchOverModal.Visible = false
		matchOverModal.Parent = gui
	end
	self.ModalFrame = matchOverModal

	-- Responsive UIScale
	local uiScale = matchOverModal:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	uiScale.Parent = matchOverModal
	local cam = Workspace.CurrentCamera
	local function updateResultsScale()
		if not cam then return end
		local vp = cam.ViewportSize
		local scaleW = vp.X / 580
		local scaleH = vp.Y / 440
		uiScale.Scale = math.clamp(math.min(scaleW, scaleH), 0.5, 1.0)
	end
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResultsScale)
		updateResultsScale()
	end

	for _, child in ipairs(matchOverModal:GetChildren()) do
		if child.Name == "Title" or child.Name == "WinnerName" or child.Name == "Subtitle" then
			child.Visible = false
		end
	end

	-- Shadow Frame
	local shadowFrame = matchOverModal:FindFirstChild("ShadowFrame") :: Frame?
	if not shadowFrame then
		shadowFrame = Instance.new("Frame")
		shadowFrame.Name = "ShadowFrame"
		shadowFrame.Size = UDim2.new(1, -12, 1, -12)
		shadowFrame.Position = UDim2.new(0, 12, 0, 12)
		shadowFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		shadowFrame.BorderSizePixel = 0
		shadowFrame.ZIndex = 40

		local sCorner = Instance.new("UICorner")
		sCorner.CornerRadius = UDim.new(0, 8)
		sCorner.Parent = shadowFrame
		shadowFrame.Parent = matchOverModal
	end

	-- Border Frame
	local borderFrame = matchOverModal:FindFirstChild("BorderFrame") :: Frame?
	if not borderFrame then
		borderFrame = Instance.new("Frame")
		borderFrame.Name = "BorderFrame"
		borderFrame.Size = UDim2.new(1, -10, 1, -10)
		borderFrame.Position = UDim2.new(0, 0, 0, 0)
		borderFrame.BackgroundTransparency = 1
		borderFrame.BorderSizePixel = 0
		borderFrame.ZIndex = 41

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 8)
		bCorner.Parent = borderFrame

		local bStroke = Instance.new("UIStroke")
		bStroke.Color = Color3.fromRGB(0, 175, 255)
		bStroke.Thickness = 2.5
		bStroke.LineJoinMode = Enum.LineJoinMode.Round
		bStroke.Parent = borderFrame

		borderFrame.Parent = matchOverModal
	end

	-- Card Frame
	local cardFrame = matchOverModal:FindFirstChild("CardFrame") :: Frame?
	if not cardFrame then
		cardFrame = Instance.new("Frame")
		cardFrame.Name = "CardFrame"
		cardFrame.Size = UDim2.new(1, -12, 1, -12)
		cardFrame.Position = UDim2.new(0, 0, 0, 0)
		cardFrame.BackgroundColor3 = Color3.fromRGB(242, 118, 16)
		cardFrame.BorderSizePixel = 0
		cardFrame.ZIndex = 42

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 8)
		cCorner.Parent = cardFrame

		local cStroke = Instance.new("UIStroke")
		cStroke.Name = "CardStroke"
		cStroke.Color = Color3.fromRGB(0, 0, 0)
		cStroke.Thickness = 4.5
		cStroke.LineJoinMode = Enum.LineJoinMode.Round
		cStroke.Parent = cardFrame

		local bgImage = Instance.new("ImageLabel")
		bgImage.Name = "BgImage"
		bgImage.Size = UDim2.new(1, 0, 1, 0)
		bgImage.Position = UDim2.new(0, 0, 0, 0)
		bgImage.BackgroundTransparency = 1
		bgImage.Image = RESULTS_BG_ASSET
		bgImage.ScaleType = Enum.ScaleType.Crop
		bgImage.ZIndex = 43

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 8)
		bgCorner.Parent = bgImage
		bgImage.Parent = cardFrame

		cardFrame.Parent = matchOverModal
	end
	self.CardFrame = cardFrame

	-- Title
	local titleLabel = cardFrame:FindFirstChild("TitleLabel") :: TextLabel?
	if not titleLabel then
		titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.Size = UDim2.new(0, 240, 0, 48)
		titleLabel.Position = UDim2.new(0.5, 0, 0, 10)
		titleLabel.AnchorPoint = Vector2.new(0.5, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = "Results"
		titleLabel.Font = Enum.Font.FredokaOne
		titleLabel.TextSize = 38
		titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		titleLabel.ZIndex = 48

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = Color3.fromRGB(0, 0, 0)
		tStroke.Thickness = 4.5
		tStroke.Parent = titleLabel
		titleLabel.Parent = cardFrame
	end

	-- Close Results Button
	local closeResultsBtn = cardFrame:FindFirstChild("CloseResultsBtn") :: TextButton?
	if not closeResultsBtn then
		closeResultsBtn = Instance.new("TextButton")
		closeResultsBtn.Name = "CloseResultsBtn"
		closeResultsBtn.Size = UDim2.new(0, 36, 0, 36)
		closeResultsBtn.Position = UDim2.new(1, -14, 0, 14)
		closeResultsBtn.AnchorPoint = Vector2.new(1, 0)
		closeResultsBtn.BackgroundColor3 = Color3.fromRGB(235, 25, 25)
		closeResultsBtn.Text = "X"
		closeResultsBtn.Font = Enum.Font.GothamBlack
		closeResultsBtn.TextSize = 20
		closeResultsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeResultsBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		closeResultsBtn.TextStrokeTransparency = 0
		closeResultsBtn.ZIndex = 50

		local crCorner = Instance.new("UICorner")
		crCorner.CornerRadius = UDim.new(0, 6)
		crCorner.Parent = closeResultsBtn

		local crStroke = Instance.new("UIStroke")
		crStroke.Color = Color3.fromRGB(0, 0, 0)
		crStroke.Thickness = 2.5
		crStroke.Parent = closeResultsBtn

		closeResultsBtn.MouseEnter:Connect(function()
			TweenService:Create(closeResultsBtn, TweenInfo.new(0.12), {
				BackgroundColor3 = Color3.fromRGB(255, 60, 60),
				Size = UDim2.new(0, 38, 0, 38),
			}):Play()
		end)
		closeResultsBtn.MouseLeave:Connect(function()
			TweenService:Create(closeResultsBtn, TweenInfo.new(0.12), {
				BackgroundColor3 = Color3.fromRGB(235, 25, 25),
				Size = UDim2.new(0, 36, 0, 36),
			}):Play()
		end)

		closeResultsBtn.Parent = cardFrame
	end
	self.CloseResultsBtn = closeResultsBtn

	closeResultsBtn.MouseButton1Click:Connect(function()
		self:Hide()
		if onVisibilityChanged then onVisibilityChanged() end
	end)

	-- Podium Container
	local podiumContainer = cardFrame:FindFirstChild("PodiumContainer") :: Frame?
	if not podiumContainer then
		podiumContainer = Instance.new("Frame")
		podiumContainer.Name = "PodiumContainer"
		podiumContainer.Size = UDim2.new(1, 0, 1, 0)
		podiumContainer.Position = UDim2.new(0, 0, 0, 0)
		podiumContainer.BackgroundTransparency = 1
		podiumContainer.BorderSizePixel = 0
		podiumContainer.ZIndex = 45
		podiumContainer.Parent = cardFrame
	end
	self.PodiumContainer = podiumContainer

	function self:Show(data: any, localPlayer: Player)
		for _, child in ipairs(self.PodiumContainer:GetChildren()) do
			child:Destroy()
		end

		local rawPodium = data and data.Podium or {}
		local winnerNameStr = data and data.Winner or "Winner"
		local totalDur = data and data.TotalDuration or 83

		local p1 = rawPodium[1] or { Rank = 1, UserId = localPlayer.UserId, Name = winnerNameStr, DisplayName = winnerNameStr, SurvivalTime = totalDur }
		local p2 = rawPodium[2] or { Rank = 2, UserId = 1, Name = "RunnerUp", DisplayName = "RunnerUp", SurvivalTime = math.max(1, totalDur - 12) }
		local p3 = rawPodium[3] or { Rank = 3, UserId = 2, Name = "Contender", DisplayName = "Contender", SurvivalTime = math.max(1, totalDur - 25) }

		local cfg1 = {
			colPosition = UDim2.new(0.5, 0, 0, 0),
			colAnchor = Vector2.new(0.5, 0),
			boxY = 68,
			pill1Y = 186,
			pill2Y = 213,
			rankY = 244,
			rankSize = 48,
			rankStroke = 5,
		}
		local cfg2 = {
			colPosition = UDim2.new(0, 97, 0, 0),
			colAnchor = Vector2.new(0.5, 0),
			boxY = 124,
			pill1Y = 242,
			pill2Y = 269,
			rankY = 302,
			rankSize = 44,
			rankStroke = 4.5,
		}
		local cfg3 = {
			colPosition = UDim2.new(1, -97, 0, 0),
			colAnchor = Vector2.new(0.5, 0),
			boxY = 180,
			pill1Y = 298,
			pill2Y = 325,
			rankY = 356,
			rankSize = 44,
			rankStroke = 4.5,
		}

		createPodiumColumn(self.PodiumContainer, 1, p1, cfg1, localPlayer)
		createPodiumColumn(self.PodiumContainer, 2, p2, cfg2, localPlayer)
		createPodiumColumn(self.PodiumContainer, 3, p3, cfg3, localPlayer)

		self.ModalFrame.Size = UDim2.new(0, 480, 0, 360)
		self.ModalFrame.Visible = true
		TweenService:Create(self.ModalFrame, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 560, 0, 420),
		}):Play()

		pcall(function()
			local popSound = Instance.new("Sound")
			popSound.SoundId = "rbxasset://sounds/action_get_up.mp3"
			popSound.Volume = 0.8
			popSound.Parent = self.ModalFrame
			popSound:Play()
			Debris:AddItem(popSound, 2)
		end)

		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:Hide()
		self.ModalFrame.Visible = false
		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:IsVisible(): boolean
		return self.ModalFrame.Visible
	end

	function self:SetVisible(visible: boolean)
		self.ModalFrame.Visible = visible
		if onVisibilityChanged then onVisibilityChanged() end
	end

	return self
end

return MatchOverModalView
