--!strict
-- src/client/ui/modals/RankingsModalView.luau
-- Manages the 4-column game-show Rankings Leaderboard (SI.NO, PLAYER NAME, BID, TIME),
-- avatar thumbnails, safe green/danger red dynamic row styling, and modal display.

local Players = game:GetService("Players")

local RankingsModalView = {}
RankingsModalView.__index = RankingsModalView

export type RankingsModal = {
	ModalFrame: Frame,
	ShadowFrame: Frame,
	CardFrame: Frame,
	CloseRankBtn: TextButton?,
	Populate: (self: RankingsModal, data: any, localPlayer: Player, currentRound: number) -> (),
	Open: (self: RankingsModal) -> (),
	Close: (self: RankingsModal) -> (),
	IsVisible: (self: RankingsModal) -> boolean,
	SetVisible: (self: RankingsModal, visible: boolean) -> (),
}

local function resolvePlayerDisplayName(pData, localPlayer: Player): string
	if not pData then return "Player" end
	if localPlayer and pData.UserId == localPlayer.UserId then
		return localPlayer.DisplayName
	end
	if pData.DisplayName and #pData.DisplayName > 0 then
		return pData.DisplayName
	end
	if pData.UserId and pData.UserId > 0 then
		local realP = Players:GetPlayerByUserId(pData.UserId)
		if realP then return realP.DisplayName end
	end
	return pData.Name or "Player"
end

function RankingsModalView.new(gui: ScreenGui, onVisibilityChanged: (() -> ())?): RankingsModal
	local self = setmetatable({}, RankingsModalView) :: any

	local rankingsModal = (gui:WaitForChild("RankingsModal", 5) or gui:FindFirstChild("RankingsModal")) :: Frame?
	if not rankingsModal then
		rankingsModal = Instance.new("Frame")
		rankingsModal.Name = "RankingsModal"
		rankingsModal.AnchorPoint = Vector2.new(0.5, 0.5)
		rankingsModal.Position = UDim2.new(0.5, 0, 0.5, 0)
		rankingsModal.Size = UDim2.new(0, 580, 0, 360)
		rankingsModal.BackgroundTransparency = 1
		rankingsModal.BorderSizePixel = 0
		rankingsModal.Visible = false
		rankingsModal.ZIndex = 60
		rankingsModal.Parent = gui
	else
		rankingsModal.ZIndex = 60
	end
	self.ModalFrame = rankingsModal

	local shadowFrame = rankingsModal:FindFirstChild("ShadowFrame") :: Frame?
	if not shadowFrame then
		shadowFrame = Instance.new("Frame")
		shadowFrame.Name = "ShadowFrame"
		shadowFrame.Size = UDim2.new(1, -8, 1, -8)
		shadowFrame.Position = UDim2.new(0, 8, 0, 8)
		shadowFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		shadowFrame.BackgroundTransparency = 0.55
		shadowFrame.BorderSizePixel = 0
		shadowFrame.ZIndex = 58

		local sCorner = Instance.new("UICorner")
		sCorner.CornerRadius = UDim.new(0, 4)
		sCorner.Parent = shadowFrame
		shadowFrame.Parent = rankingsModal
	else
		shadowFrame.ZIndex = 58
	end
	self.ShadowFrame = shadowFrame

	local cardFrame = rankingsModal:FindFirstChild("CardFrame") :: Frame?
	if not cardFrame then
		cardFrame = Instance.new("Frame")
		cardFrame.Name = "CardFrame"
		cardFrame.Size = UDim2.new(1, -8, 1, -8)
		cardFrame.Position = UDim2.new(0, 0, 0, 0)
		cardFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
		cardFrame.BorderSizePixel = 0
		cardFrame.ZIndex = 60

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 4)
		cCorner.Parent = cardFrame

		local cStroke = Instance.new("UIStroke")
		cStroke.Name = "CardStroke"
		cStroke.Color = Color3.fromRGB(0, 0, 0)
		cStroke.Thickness = 2
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStroke.LineJoinMode = Enum.LineJoinMode.Miter
		cStroke.Parent = cardFrame

		local bgImage = Instance.new("ImageLabel")
		bgImage.Name = "BgImage"
		bgImage.Size = UDim2.new(1, 0, 1, 0)
		bgImage.Position = UDim2.new(0, 0, 0, 0)
		bgImage.BackgroundTransparency = 0
		bgImage.Image = "rbxasset://textures/bid-leaderboard-background.jpg"
		bgImage.ScaleType = Enum.ScaleType.Crop
		bgImage.ZIndex = 61
		bgImage.Visible = true

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 4)
		bgCorner.Parent = bgImage
		bgImage.Parent = cardFrame

		cardFrame.Parent = rankingsModal
	else
		cardFrame.ZIndex = 60
	end
	self.CardFrame = cardFrame

	-- Close Button (Created once in new(), permanent across all states and re-opens)
	local closeRankBtn = cardFrame:FindFirstChild("CloseRankBtn") :: TextButton?
	if not closeRankBtn then
		closeRankBtn = Instance.new("TextButton")
		closeRankBtn.Name = "CloseRankBtn"
		closeRankBtn.Size = UDim2.new(0, 32, 0, 32)
		closeRankBtn.Position = UDim2.new(1, -12, 0, 10)
		closeRankBtn.AnchorPoint = Vector2.new(1, 0)
		closeRankBtn.BackgroundColor3 = Color3.fromRGB(230, 35, 35)

		local crbCorner = Instance.new("UICorner")
		crbCorner.CornerRadius = UDim.new(0, 5)
		crbCorner.Parent = closeRankBtn

		local crbStroke = Instance.new("UIStroke")
		crbStroke.Color = Color3.fromRGB(0, 0, 0)
		crbStroke.Thickness = 2
		crbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		crbStroke.Parent = closeRankBtn

		closeRankBtn.Parent = cardFrame
	end

	-- Always guarantee button text, styling and crisp XLabel overlay
	closeRankBtn.Text = "X"
	closeRankBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeRankBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	closeRankBtn.TextStrokeTransparency = 0
	closeRankBtn.Font = Enum.Font.GothamBlack
	closeRankBtn.TextSize = 18
	closeRankBtn.ZIndex = 65
	closeRankBtn.Active = true
	closeRankBtn.Selectable = true
	closeRankBtn.Visible = true

	closeRankBtn.MouseEnter:Connect(function()
		closeRankBtn.BackgroundColor3 = Color3.fromRGB(255, 65, 65)
	end)
	closeRankBtn.MouseLeave:Connect(function()
		closeRankBtn.BackgroundColor3 = Color3.fromRGB(230, 35, 35)
	end)

	local function handleCloseClick()
		self:Close()
	end
	closeRankBtn.MouseButton1Click:Connect(handleCloseClick)
	closeRankBtn.Activated:Connect(handleCloseClick)

	local xLabel = closeRankBtn:FindFirstChild("XLabel") :: TextLabel?
	if not xLabel then
		xLabel = Instance.new("TextLabel")
		xLabel.Name = "XLabel"
		xLabel.Size = UDim2.fromScale(1, 1)
		xLabel.Position = UDim2.fromScale(0, 0)
		xLabel.BackgroundTransparency = 1
		xLabel.Active = false
		xLabel.Selectable = false
		xLabel.Parent = closeRankBtn
	end
	xLabel.Text = "X"
	xLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	xLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	xLabel.TextStrokeTransparency = 0
	xLabel.Font = Enum.Font.GothamBlack
	xLabel.TextSize = 18
	xLabel.TextXAlignment = Enum.TextXAlignment.Center
	xLabel.TextYAlignment = Enum.TextYAlignment.Center
	xLabel.ZIndex = 66
	xLabel.Active = false
	xLabel.Selectable = false
	xLabel.Visible = true

	self.CloseRankBtn = closeRankBtn

	function self:Populate(data: any, localPlayer: Player, currentRound: number)
		local allBidders = {}
		local safeCount = data.SafeCount or 1
		for _, p in ipairs(data.TopBidders or {}) do table.insert(allBidders, p) end
		for _, p in ipairs(data.BottomBidders or {}) do table.insert(allBidders, p) end

		local rowCount = #allBidders
		local rowHeight = 36
		local rowPadding = 4
		local tableContentHeight = rowCount * (rowHeight + rowPadding)

		local desiredHeight = 110 + tableContentHeight + 12
		local modalHeight = math.clamp(desiredHeight, 260, 560)

		self.ModalFrame.Size = UDim2.new(0, 580, 0, modalHeight)
		self.ModalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		self.ModalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

		-- Clean up table content (keep CloseRankBtn and BgImage intact)
		for _, child in ipairs(self.CardFrame:GetChildren()) do
			if child.Name == "HeaderFrame" or child.Name == "LeaderboardScroll" or child.Name == "TitleHeader" or child.Name == "FooterStatement" then
				child:Destroy()
			end
		end

		if self.CloseRankBtn then
			self.CloseRankBtn.Visible = true
			self.CloseRankBtn.ZIndex = 65
			self.CloseRankBtn.Parent = self.CardFrame
		end

		-- Title Header: "BID LEADERBOARD"
		local titleHeader = Instance.new("Frame")
		titleHeader.Name = "TitleHeader"
		titleHeader.Size = UDim2.new(1, -70, 0, 32)
		titleHeader.Position = UDim2.new(0, 16, 0, 12)
		titleHeader.BackgroundTransparency = 1
		titleHeader.ZIndex = 28
		titleHeader.Parent = self.CardFrame

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, 0, 1, 0)
		titleLabel.Position = UDim2.new(0, 0, 0, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = "BID LEADERBOARD"
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextSize = 18
		titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.ZIndex = 29
		titleLabel.Parent = titleHeader

		-- Header Frame
		local headerFrame = Instance.new("Frame")
		headerFrame.Name = "HeaderFrame"
		headerFrame.Size = UDim2.new(1, -32, 0, 26)
		headerFrame.Position = UDim2.new(0, 16, 0, 52)
		headerFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		headerFrame.BorderSizePixel = 0
		headerFrame.ZIndex = 28

		local hCorner = Instance.new("UICorner")
		hCorner.CornerRadius = UDim.new(0, 3)
		hCorner.Parent = headerFrame

		local hStroke = Instance.new("UIStroke")
		hStroke.Color = Color3.fromRGB(42, 42, 54)
		hStroke.Thickness = 1
		hStroke.Parent = headerFrame

		local function makeHeaderCell(text, size, pos, align)
			local hCell = Instance.new("TextLabel")
			hCell.Size = size
			hCell.Position = pos
			hCell.BackgroundTransparency = 1
			hCell.Text = text
			hCell.Font = Enum.Font.GothamBold
			hCell.TextSize = 10
			hCell.TextColor3 = Color3.fromRGB(150, 155, 170)
			hCell.TextXAlignment = align
			hCell.ZIndex = 29
			hCell.Parent = headerFrame
			return hCell
		end

		makeHeaderCell("SI.NO", UDim2.new(0.12, 0, 1, 0), UDim2.new(0, 4, 0, 0), Enum.TextXAlignment.Center)
		makeHeaderCell("PLAYER NAME", UDim2.new(0.46, -10, 1, 0), UDim2.new(0.12, 10, 0, 0), Enum.TextXAlignment.Left)
		makeHeaderCell("BID", UDim2.new(0.21, 0, 1, 0), UDim2.new(0.58, 0, 0, 0), Enum.TextXAlignment.Right)
		makeHeaderCell("TIME", UDim2.new(0.21, -8, 1, 0), UDim2.new(0.79, -8, 0, 0), Enum.TextXAlignment.Right)
		headerFrame.Parent = self.CardFrame

		-- Scrolling Frame
		local isScrollable = (tableContentHeight > (modalHeight - 96))
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "LeaderboardScroll"
		scroll.Size = UDim2.new(1, -32, 1, -90)
		scroll.Position = UDim2.new(0, 16, 0, 82)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = isScrollable and 4 or 0
		scroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 85)
		scroll.ScrollingEnabled = isScrollable
		scroll.CanvasSize = UDim2.new(0, 0, 0, tableContentHeight + 4)
		scroll.ZIndex = 28

		local sPadding = Instance.new("UIPadding")
		sPadding.PaddingLeft = UDim.new(0, 2)
		sPadding.PaddingRight = UDim.new(0, isScrollable and 8 or 2)
		sPadding.PaddingTop = UDim.new(0, 2)
		sPadding.PaddingBottom = UDim.new(0, 2)
		sPadding.Parent = scroll

		local uiList = Instance.new("UIListLayout")
		uiList.SortOrder = Enum.SortOrder.LayoutOrder
		uiList.Padding = UDim.new(0, rowPadding)
		uiList.Parent = scroll

		for i, p in ipairs(allBidders) do
			local isSafe = (i <= safeCount)
			local isMe = localPlayer and ((p.UserId == localPlayer.UserId) or (p.Name == localPlayer.Name) or (p.DisplayName == localPlayer.DisplayName))
			local dispName = resolvePlayerDisplayName(p, localPlayer)

			local row = Instance.new("Frame")
			row.Name = "Row_" .. i
			row.Size = UDim2.new(1, 0, 0, rowHeight)
			row.LayoutOrder = i
			row.BorderSizePixel = 0
			row.ZIndex = 28

			local rCorner = Instance.new("UICorner")
			rCorner.CornerRadius = UDim.new(0, 3)
			rCorner.Parent = row

			local rStroke = Instance.new("UIStroke")
			rStroke.LineJoinMode = Enum.LineJoinMode.Miter
			rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

			if isMe then
				row.BackgroundColor3 = Color3.fromRGB(34, 28, 18)
				rStroke.Color = Color3.fromRGB(245, 158, 11)
				rStroke.Thickness = 1.5
			elseif isSafe then
				row.BackgroundColor3 = Color3.fromRGB(14, 25, 19)
				rStroke.Color = Color3.fromRGB(34, 197, 94)
				rStroke.Thickness = 1
			else
				row.BackgroundColor3 = Color3.fromRGB(26, 15, 17)
				rStroke.Color = Color3.fromRGB(239, 68, 68)
				rStroke.Thickness = 1
			end
			rStroke.Parent = row

			-- Column 1: SI.NO
			local c1 = Instance.new("TextLabel")
			c1.Size = UDim2.new(0.12, 0, 1, 0)
			c1.Position = UDim2.new(0, 4, 0, 0)
			c1.BackgroundTransparency = 1
			c1.Text = "#" .. tostring(i)
			c1.Font = Enum.Font.GothamBold
			c1.TextSize = 12
			c1.TextColor3 = isMe and Color3.fromRGB(245, 195, 65) or (isSafe and Color3.fromRGB(110, 235, 155) or Color3.fromRGB(245, 110, 120))
			c1.TextXAlignment = Enum.TextXAlignment.Center
			c1.ZIndex = 30
			c1.Parent = row

			-- Column 2: PLAYER NAME
			local playerColFrame = Instance.new("Frame")
			playerColFrame.Size = UDim2.new(0.46, -10, 1, 0)
			playerColFrame.Position = UDim2.new(0.12, 10, 0, 0)
			playerColFrame.BackgroundTransparency = 1
			playerColFrame.ZIndex = 29

			local avImg = Instance.new("ImageLabel")
			avImg.Size = UDim2.new(0, 24, 0, 24)
			avImg.Position = UDim2.new(0, 0, 0.5, 0)
			avImg.AnchorPoint = Vector2.new(0, 0.5)
			avImg.BackgroundTransparency = 1
			local thumbId = (p.UserId and p.UserId > 0) and p.UserId or 1
			avImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", thumbId)
			avImg.ScaleType = Enum.ScaleType.Fit
			avImg.ZIndex = 31

			local aviCorner = Instance.new("UICorner")
			aviCorner.CornerRadius = UDim.new(0, 3)
			aviCorner.Parent = avImg
			avImg.Parent = playerColFrame

			local c2 = Instance.new("TextLabel")
			c2.Size = UDim2.new(1, -30, 1, 0)
			c2.Position = UDim2.new(0, 30, 0, 0)
			c2.BackgroundTransparency = 1
			if isMe then
				c2.Text = string.format("%s (YOU)", dispName)
				c2.Font = Enum.Font.GothamBold
				c2.TextSize = 12
				c2.TextColor3 = Color3.fromRGB(255, 230, 110)
			else
				c2.Text = dispName
				c2.Font = Enum.Font.GothamMedium
				c2.TextSize = 12
				c2.TextColor3 = Color3.fromRGB(245, 245, 250)
			end
			c2.TextXAlignment = Enum.TextXAlignment.Left
			c2.TextTruncate = Enum.TextTruncate.AtEnd
			c2.ZIndex = 30
			c2.Parent = playerColFrame
			playerColFrame.Parent = row

			-- Column 3: BID
			local c3 = Instance.new("TextLabel")
			c3.Size = UDim2.new(0.21, 0, 1, 0)
			c3.Position = UDim2.new(0.58, 0, 0, 0)
			c3.BackgroundTransparency = 1
			c3.Text = string.format("$%.2f", p.CurrentBid or 0)
			c3.Font = Enum.Font.GothamBold
			c3.TextSize = 13
			c3.TextColor3 = Color3.fromRGB(245, 195, 65)
			c3.TextXAlignment = Enum.TextXAlignment.Right
			c3.ZIndex = 29
			c3.Parent = row

			-- Column 4: TIME
			local c4 = Instance.new("TextLabel")
			c4.Size = UDim2.new(0.21, -8, 1, 0)
			c4.Position = UDim2.new(0.79, -8, 0, 0)
			c4.BackgroundTransparency = 1
			local elapsed = p.SubmitTime or 10.00
			c4.Text = string.format("%.2fs", elapsed)
			c4.Font = Enum.Font.GothamMedium
			c4.TextSize = 12
			c4.TextColor3 = Color3.fromRGB(180, 185, 200)
			c4.TextXAlignment = Enum.TextXAlignment.Right
			c4.ZIndex = 29
			c4.Parent = row

			row.Parent = scroll
		end

		scroll.Parent = self.CardFrame
		self.ModalFrame.Visible = true
		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:Open()
		self.ModalFrame.Visible = true
		if self.CloseRankBtn then
			self.CloseRankBtn.Visible = true
			self.CloseRankBtn.ZIndex = 65
			self.CloseRankBtn.Parent = self.CardFrame
		end
		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:Close()
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

return RankingsModalView
