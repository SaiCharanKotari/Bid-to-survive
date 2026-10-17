--!strict
-- src/client/ui/components/StatusHUDView.luau
-- Manages the bottom-left HP, Energy, and Lifetime Cash status stack,
-- and the bottom-right Wallet balance card with smooth tweens and payout toasts.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local StatusHUDView = {}
StatusHUDView.__index = StatusHUDView

export type StatusHUD = {
	ScreenGui: ScreenGui,
	StatusStack: Frame,
	HpBg: Frame,
	HpFill: Frame,
	HpLabel: TextLabel,
	EnergyFill: Frame,
	EnergyLabel: TextLabel,
	LifetimeCashLabel: TextLabel,
	PayoutToast: TextLabel,
	WalletCard: Frame,
	WalletValLabel: TextLabel,
	WalletScale: UIScale,
	DisplayedOverallCash: number,
	CountUpThread: thread?,
	LastWalletVal: number,
	UpdateHealth: (self: StatusHUD, current: number, max: number) -> (),
	UpdateEnergy: (self: StatusHUD, current: number, max: number) -> (),
	UpdateCurrencyUI: (self: StatusHUD, isInGame: boolean, overallCash: number, matchWallet: number) -> (),
	RollOverallCash: (self: StatusHUD, targetCash: number) -> (),
	PunchWallet: (self: StatusHUD) -> (),
	HandlePayout: (self: StatusHUD, earnedCash: number, secondsSurvived: number, newOverall: number) -> (),
	SetInGame: (self: StatusHUD, isInGame: boolean) -> (),
	SetVisible: (self: StatusHUD, visible: boolean) -> (),
}

function StatusHUDView.new(player: Player?): StatusHUD
	local self = setmetatable({}, StatusHUDView) :: any
	local localPlayer = player or Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("BidToSurviveStatusHUD")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BidToSurviveStatusHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui
	self.ScreenGui = screenGui

	-- Bottom-Left Status Stack
	local statusStack = Instance.new("Frame")
	statusStack.Name = "BottomLeftStatusStack"
	statusStack.AnchorPoint = Vector2.new(0, 1)
	statusStack.Position = UDim2.new(0, 24, 1, -34)
	statusStack.Size = UDim2.new(0, 315, 0, 96)
	statusStack.BackgroundTransparency = 1
	statusStack.Parent = screenGui
	self.StatusStack = statusStack

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	listLayout.Parent = statusStack

	local function createComicBar(order: number, name: string, tagText: string, fillColor: Color3, underlayColor: Color3)
		local bg = Instance.new("Frame")
		bg.Name = name .. "Frame"
		bg.LayoutOrder = order
		bg.Size = UDim2.new(1, 0, 0, 34)
		bg.BackgroundColor3 = underlayColor
		bg.BorderSizePixel = 0
		bg.Parent = statusStack

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = bg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = bg

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = fillColor
		fill.BorderSizePixel = 0
		fill.Parent = bg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill

		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = "TagLabel"
		tagLabel.Size = UDim2.new(0, 36, 1, 0)
		tagLabel.Position = UDim2.new(0, 10, 0.5, 0)
		tagLabel.AnchorPoint = Vector2.new(0, 0.5)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.GothamBlack
		tagLabel.TextSize = 14
		tagLabel.TextXAlignment = Enum.TextXAlignment.Left
		tagLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		tagLabel.Text = tagText
		tagLabel.ZIndex = 3
		tagLabel.Parent = bg

		local tagStroke = Instance.new("UIStroke")
		tagStroke.Thickness = 2
		tagStroke.Color = Color3.fromRGB(0, 0, 0)
		tagStroke.Parent = tagLabel

		local valLabel = Instance.new("TextLabel")
		valLabel.Name = "ValueLabel"
		valLabel.Size = UDim2.new(0, 56, 1, 0)
		valLabel.Position = UDim2.new(1, -10, 0.5, 0)
		valLabel.AnchorPoint = Vector2.new(1, 0.5)
		valLabel.BackgroundTransparency = 1
		valLabel.Font = Enum.Font.GothamBlack
		valLabel.TextSize = 14
		valLabel.TextXAlignment = Enum.TextXAlignment.Right
		valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		valLabel.Text = "100"
		valLabel.ZIndex = 3
		valLabel.Parent = bg

		local valStroke = Instance.new("UIStroke")
		valStroke.Thickness = 2
		valStroke.Color = Color3.fromRGB(0, 0, 0)
		valStroke.Parent = valLabel

		return bg, fill, valLabel
	end

	local hpBg, hpFill, hpLabel = createComicBar(2, "HP", "HP", Color3.fromRGB(255, 0, 0), Color3.fromRGB(60, 10, 15))
	hpBg.Visible = false
	self.HpBg = hpBg
	self.HpFill = hpFill
	self.HpLabel = hpLabel

	local _, energyFill, energyLabel = createComicBar(3, "Energy", "EP", Color3.fromRGB(0, 255, 242), Color3.fromRGB(10, 45, 50))
	self.EnergyFill = energyFill
	self.EnergyLabel = energyLabel

	-- Lifetime Cash Frame
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "LifetimeCashFrame"
	moneyFrame.LayoutOrder = 1
	moneyFrame.Size = UDim2.new(1, 0, 0, 42)
	moneyFrame.BackgroundTransparency = 1
	moneyFrame.Parent = statusStack

	local lifetimeCashLabel = Instance.new("TextLabel")
	lifetimeCashLabel.Name = "LifetimeCashLabel"
	lifetimeCashLabel.Size = UDim2.new(1, 0, 1, 0)
	lifetimeCashLabel.Position = UDim2.new(0, 0, 0.5, 0)
	lifetimeCashLabel.AnchorPoint = Vector2.new(0, 0.5)
	lifetimeCashLabel.BackgroundTransparency = 1
	lifetimeCashLabel.Font = Enum.Font.GothamBlack
	lifetimeCashLabel.TextSize = 36
	lifetimeCashLabel.TextXAlignment = Enum.TextXAlignment.Left
	lifetimeCashLabel.TextColor3 = Color3.fromRGB(0, 230, 0)
	lifetimeCashLabel.Text = "+0 $"
	lifetimeCashLabel.ZIndex = 3
	lifetimeCashLabel.Parent = moneyFrame
	self.LifetimeCashLabel = lifetimeCashLabel

	local moneyStroke = Instance.new("UIStroke")
	moneyStroke.Thickness = 3
	moneyStroke.Color = Color3.fromRGB(0, 0, 0)
	moneyStroke.Parent = lifetimeCashLabel

	-- Floating Payout Toast
	local payoutToast = Instance.new("TextLabel")
	payoutToast.Name = "PayoutToast"
	payoutToast.Size = UDim2.new(1, 40, 0, 24)
	payoutToast.Position = UDim2.new(0, 0, 0, -26)
	payoutToast.BackgroundTransparency = 1
	payoutToast.Font = Enum.Font.GothamBlack
	payoutToast.TextSize = 15
	payoutToast.TextXAlignment = Enum.TextXAlignment.Left
	payoutToast.TextColor3 = Color3.fromRGB(52, 211, 153)
	payoutToast.TextStrokeTransparency = 0.2
	payoutToast.TextTransparency = 1
	payoutToast.Text = ""
	payoutToast.Parent = moneyFrame
	self.PayoutToast = payoutToast

	-- Bottom-Right Wallet Card
	local walletCard = Instance.new("Frame")
	walletCard.Name = "BottomRightWalletCard"
	walletCard.AnchorPoint = Vector2.new(1, 1)
	walletCard.Position = UDim2.new(1, -24, 1, -34)
	walletCard.Size = UDim2.new(0, 240, 0, 56)
	walletCard.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	walletCard.BorderSizePixel = 0
	walletCard.Parent = screenGui
	self.WalletCard = walletCard

	local walletCorner = Instance.new("UICorner")
	walletCorner.CornerRadius = UDim.new(0, 4)
	walletCorner.Parent = walletCard

	local walletStroke = Instance.new("UIStroke")
	walletStroke.Thickness = 3
	walletStroke.Color = Color3.fromRGB(0, 0, 0)
	walletStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	walletStroke.Parent = walletCard

	local walletBadge = Instance.new("Frame")
	walletBadge.Name = "WalletBadge"
	walletBadge.Size = UDim2.new(0, 76, 0, 32)
	walletBadge.Position = UDim2.new(0, 10, 0.5, 0)
	walletBadge.AnchorPoint = Vector2.new(0, 0.5)
	walletBadge.BackgroundColor3 = Color3.fromRGB(255, 185, 0)
	walletBadge.BorderSizePixel = 0
	walletBadge.Parent = walletCard

	local wbCorner = Instance.new("UICorner")
	wbCorner.CornerRadius = UDim.new(0, 4)
	wbCorner.Parent = walletBadge

	local wbStroke = Instance.new("UIStroke")
	wbStroke.Thickness = 2
	wbStroke.Color = Color3.fromRGB(0, 0, 0)
	wbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	wbStroke.Parent = walletBadge

	local wbText = Instance.new("TextLabel")
	wbText.Name = "BadgeText"
	wbText.Size = UDim2.new(1, 0, 1, 0)
	wbText.BackgroundTransparency = 1
	wbText.Font = Enum.Font.GothamBlack
	wbText.TextSize = 15
	wbText.TextColor3 = Color3.fromRGB(0, 0, 0)
	wbText.Text = "WALLET"
	wbText.Parent = walletBadge

	local walletValLabel = Instance.new("TextLabel")
	walletValLabel.Name = "WalletValueLabel"
	walletValLabel.Size = UDim2.new(1, -96, 1, 0)
	walletValLabel.Position = UDim2.new(1, -12, 0.5, 0)
	walletValLabel.AnchorPoint = Vector2.new(1, 0.5)
	walletValLabel.BackgroundTransparency = 1
	walletValLabel.Font = Enum.Font.GothamBlack
	walletValLabel.TextSize = 36
	walletValLabel.TextXAlignment = Enum.TextXAlignment.Right
	walletValLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	walletValLabel.Text = "$20.00"
	walletValLabel.ZIndex = 3
	walletValLabel.Parent = walletCard
	self.WalletValLabel = walletValLabel

	local walletValStroke = Instance.new("UIStroke")
	walletValStroke.Thickness = 3
	walletValStroke.Color = Color3.fromRGB(0, 0, 0)
	walletValStroke.Parent = walletValLabel

	local walletScale = Instance.new("UIScale")
	walletScale.Scale = 1.0
	walletScale.Parent = walletCard
	self.WalletScale = walletScale

	self.DisplayedOverallCash = 0
	self.CountUpThread = nil
	self.LastWalletVal = 20

	function self:UpdateHealth(health: number, maxHealth: number)
		local safeMax = (maxHealth > 0) and maxHealth or 100
		local ratio = math.clamp(health / safeMax, 0, 1)
		self.HpLabel.Text = string.format("%d", math.ceil(health))
		TweenService:Create(self.HpFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(ratio, 0, 1, 0),
		}):Play()
	end

	function self:UpdateEnergy(currentEnergy: number, maxEnergy: number)
		local safeMax = (maxEnergy > 0) and maxEnergy or 100
		local ratio = math.clamp(currentEnergy / safeMax, 0, 1)
		self.EnergyLabel.Text = string.format("%d", math.ceil(currentEnergy))
		self.EnergyFill.Size = UDim2.new(ratio, 0, 1, 0)
	end

	function self:PunchWallet()
		self.WalletScale.Scale = 1.10
		TweenService:Create(self.WalletScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.0,
		}):Play()
	end

	function self:RollOverallCash(targetCash: number)
		if self.CountUpThread then
			task.cancel(self.CountUpThread)
			self.CountUpThread = nil
		end

		local startVal = self.DisplayedOverallCash
		local diff = targetCash - startVal
		if math.abs(diff) <= 0.01 then
			self.DisplayedOverallCash = targetCash
			self.LifetimeCashLabel.Text = string.format("+%d $", math.floor(targetCash))
			return
		end

		self.CountUpThread = task.spawn(function()
			local duration = 1.0
			local startTime = os.clock()
			while true do
				local elapsed = os.clock() - startTime
				local progress = math.clamp(elapsed / duration, 0, 1)
				local alpha = TweenService:GetValue(progress, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
				local cur = math.floor(startVal + (diff * alpha))
				self.DisplayedOverallCash = cur
				self.LifetimeCashLabel.Text = string.format("+%d $", cur)
				if progress >= 1 then break end
				task.wait(0.03)
			end
			self.DisplayedOverallCash = targetCash
			self.LifetimeCashLabel.Text = string.format("+%d $", math.floor(targetCash))
			self.CountUpThread = nil
		end)
	end

	function self:SetInGame(isInGame: boolean)
		self.HpBg.Visible = isInGame
		self.StatusStack.Size = isInGame and UDim2.new(0, 315, 0, 134) or UDim2.new(0, 315, 0, 82)
	end

	function self:UpdateCurrencyUI(isInGame: boolean, overallCash: number, matchWallet: number)
		self:SetInGame(isInGame)

		if self.CountUpThread == nil then
			self.DisplayedOverallCash = overallCash
			self.LifetimeCashLabel.Text = string.format("+%d $", math.floor(overallCash))
		end

		if matchWallet ~= self.LastWalletVal then
			if matchWallet < self.LastWalletVal then
				self:PunchWallet()
			end
			self.LastWalletVal = matchWallet
		end
		self.WalletValLabel.Text = string.format("$%.2f", matchWallet)
	end

	function self:HandlePayout(earnedCash: number, secondsSurvived: number, newOverall: number)
		self:RollOverallCash(newOverall)

		self.PayoutToast.Text = string.format("+$%d (%ds Survived × $20)", earnedCash, secondsSurvived)
		self.PayoutToast.Position = UDim2.new(0, 0, 0, -18)
		self.PayoutToast.TextTransparency = 0

		TweenService:Create(self.PayoutToast, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 0, -32),
		}):Play()

		task.delay(4.0, function()
			TweenService:Create(self.PayoutToast, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			}):Play()
		end)
	end

	function self:SetVisible(visible: boolean)
		self.ScreenGui.Enabled = visible
	end

	return self
end

return StatusHUDView
