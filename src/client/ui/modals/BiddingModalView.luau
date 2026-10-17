--!strict
-- src/client/ui/modals/BiddingModalView.luau
-- Manages the Bidding modal, numeric input sanitization, percentage quick-bid buttons, and bid submission.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local BiddingModalView = {}
BiddingModalView.__index = BiddingModalView

export type BiddingModal = {
	ModalFrame: Frame,
	CardFrame: Frame,
	BidInput: TextBox,
	SubmitBtn: TextButton,
	SubmittedNotice: TextLabel,
	CloseBidBtn: TextButton,
	HasSubmitted: boolean,
	SubmittedAmount: number?,
	CurrentWallet: number,
	Open: (self: BiddingModal, currentWallet: number) -> (),
	Close: (self: BiddingModal) -> (),
	Reset: (self: BiddingModal) -> (),
	IsVisible: (self: BiddingModal) -> boolean,
	SetVisible: (self: BiddingModal, visible: boolean) -> (),
}

local function applySVG3ButtonStyle(button: TextButton, labelText: string, textSize: number?)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.Text = ""

	local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 1)
	corner.Parent = button

	local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = button

	local gradient = button:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHex("#EC0000")),
		ColorSequenceKeypoint.new(0.54, Color3.fromHex("#F50505")),
		ColorSequenceKeypoint.new(0.78, Color3.fromHex("#E25A5A")),
		ColorSequenceKeypoint.new(1.00, Color3.fromHex("#D6C7C7")),
	})
	gradient.Enabled = true
	gradient.Parent = button

	local label = button:FindFirstChild("BtnLabel") :: TextLabel?
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "BtnLabel"
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromScale(0, 0)
		label.BackgroundTransparency = 1
		label.ZIndex = button.ZIndex + 3
		label.Parent = button
	end
	label.Text = labelText
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize or 24
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
end

function BiddingModalView.new(gui: ScreenGui, bidSubmittedRemote: RemoteEvent?, onVisibilityChanged: (() -> ())?): BiddingModal
	local self = setmetatable({}, BiddingModalView) :: any
	self.HasSubmitted = false
	self.SubmittedAmount = nil :: number?
	self.CurrentWallet = 20.00

	-- BiddingModal Frame
	local biddingModal = (gui:WaitForChild("BiddingModal", 5) or gui:FindFirstChild("BiddingModal")) :: Frame?
	if not biddingModal then
		biddingModal = Instance.new("Frame")
		biddingModal.Name = "BiddingModal"
		biddingModal.AnchorPoint = Vector2.new(0.5, 0.5)
		biddingModal.Position = UDim2.new(0.5, 0, 0.5, 0)
		biddingModal.Size = UDim2.new(0, 480, 0, 250)
		biddingModal.BackgroundTransparency = 1
		biddingModal.Visible = false
		biddingModal.Parent = gui
	end
	self.ModalFrame = biddingModal

	local cardFrame = (biddingModal:WaitForChild("CardFrame", 3) or biddingModal:FindFirstChild("CardFrame") or biddingModal) :: Frame
	self.CardFrame = cardFrame

	-- Close Button
	local closeBidBtn = (cardFrame:FindFirstChild("CloseBidBtn", true) or biddingModal:FindFirstChild("CloseBidBtn")) :: TextButton?
	if not closeBidBtn then
		closeBidBtn = Instance.new("TextButton")
		closeBidBtn.Name = "CloseBidBtn"
		closeBidBtn.Size = UDim2.new(0, 32, 0, 30)
		closeBidBtn.Position = UDim2.new(1, -14, 0, 12)
		closeBidBtn.AnchorPoint = Vector2.new(1, 0)
		closeBidBtn.BackgroundColor3 = Color3.fromRGB(245, 0, 0)
		closeBidBtn.Text = "X"
		closeBidBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeBidBtn.Font = Enum.Font.GothamBlack
		closeBidBtn.TextSize = 18
		closeBidBtn.ZIndex = 26

		local cbbCorner = Instance.new("UICorner")
		cbbCorner.CornerRadius = UDim.new(0, 6)
		cbbCorner.Parent = closeBidBtn

		local cbbStroke = Instance.new("UIStroke")
		cbbStroke.Thickness = 2
		cbbStroke.Color = Color3.fromRGB(0, 0, 0)
		cbbStroke.Parent = closeBidBtn

		closeBidBtn.Parent = cardFrame
	end
	self.CloseBidBtn = closeBidBtn

	closeBidBtn.MouseButton1Click:Connect(function()
		self:Close()
		if onVisibilityChanged then onVisibilityChanged() end
	end)

	-- Bid Input TextBox
	local bidInput = (cardFrame:WaitForChild("BidInput", 3) or cardFrame:FindFirstChild("BidInput", true)) :: TextBox
	self.BidInput = bidInput
	bidInput.TextSize = 30
	bidInput.Font = Enum.Font.RobotoMono

	self.IsOpening = false

	local function unlockBidSubmit()
		if self.IsOpening then return end
		if self.HasSubmitted then
			self.HasSubmitted = false
			applySVG3ButtonStyle(self.SubmitBtn, "BID", 24)
			if self.SubmittedNotice and self.SubmittedAmount ~= nil then
				self.SubmittedNotice.Text = string.format("Last Submitted: $%.2f (Press BID to update)", self.SubmittedAmount)
				self.SubmittedNotice.TextColor3 = Color3.fromRGB(255, 230, 130)
			end
		end
	end

	-- Strict numeric and decimal filtering
	bidInput:GetPropertyChangedSignal("Text"):Connect(function()
		local text = bidInput.Text
		local filtered = ""
		local hasDot = false
		for i = 1, #text do
			local c = text:sub(i, i)
			if c:match("%d") then
				filtered = filtered .. c
			elseif c == "." and not hasDot then
				filtered = filtered .. c
				hasDot = true
			end
		end
		if text ~= filtered then
			bidInput.Text = filtered
		end

		-- If user changes/retypes bid value, restore BID button to allow re-submitting!
		if not self.IsOpening then
			unlockBidSubmit()
		end
	end)

	bidInput.Focused:Connect(function()
		unlockBidSubmit()
	end)

	bidInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			handleSubmitBid()
		end
	end)

	-- Submit Button
	local submitBtn = (cardFrame:FindFirstChild("SubmitBtn", true) or cardFrame:FindFirstChild("SubmitBtn")) :: TextButton
	self.SubmitBtn = submitBtn
	applySVG3ButtonStyle(submitBtn, "BID", 24)

	local submittedNotice = (cardFrame:FindFirstChild("SubmittedNotice", true) or cardFrame:FindFirstChild("SubmittedNotice")) :: TextLabel?
	if not submittedNotice then
		submittedNotice = Instance.new("TextLabel")
		submittedNotice.Name = "SubmittedNotice"
		submittedNotice.AnchorPoint = Vector2.new(0.5, 0)
		submittedNotice.Position = UDim2.new(0.5, 0, 0, 192)
		submittedNotice.Size = UDim2.new(0.85, 0, 0, 20)
		submittedNotice.BackgroundTransparency = 1
		submittedNotice.Font = Enum.Font.GothamBold
		submittedNotice.TextSize = 13
		submittedNotice.TextColor3 = Color3.fromRGB(160, 255, 160)
		submittedNotice.Text = ""
		submittedNotice.ZIndex = 25
		submittedNotice.Parent = cardFrame
	end
	self.SubmittedNotice = submittedNotice

	-- Quick fraction buttons
	local quickFrame = (biddingModal:FindFirstChild("QuickFrame") or cardFrame:FindFirstChild("QuickFrame")) :: Frame?
	if quickFrame then
		local function setBidFraction(frac: number)
			local amtCents = math.round((self.CurrentWallet * frac) * 100)
			local amt = amtCents / 100
			bidInput.Text = string.format("%.2f", amt)
			unlockBidSubmit()
		end

		for _, btn in ipairs(quickFrame:GetChildren()) do
			if btn:IsA("TextButton") then
				btn.MouseButton1Click:Connect(function()
					if btn.Text == "25%" then setBidFraction(0.25)
					elseif btn.Text == "50%" then setBidFraction(0.50)
					elseif btn.Text == "75%" then setBidFraction(0.75)
					elseif btn.Text == "MAX" then setBidFraction(1.00)
					elseif btn.Text == "CLEAR" then
						bidInput.Text = "0.00"
						unlockBidSubmit()
					end
				end)
			end
		end
	end

	-- Submit Click Handler
	local function handleSubmitBid()
		if self.HasSubmitted then return end

		local cleanStr = bidInput.Text:gsub("[^%d%.]", "")
		local rawVal = tonumber(cleanStr) or 0
		local walletCents = math.round(self.CurrentWallet * 100)
		local valCents = math.clamp(math.round(rawVal * 100), 0, walletCents)
		local val = valCents / 100

		self.HasSubmitted = true
		self.SubmittedAmount = val
		if bidSubmittedRemote then
			bidSubmittedRemote:FireServer(val)
		end

		submitBtn.Text = ""
		local submitGrad = submitBtn:FindFirstChildOfClass("UIGradient")
		if submitGrad then submitGrad.Enabled = false end
		submitBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		local submitLabel = submitBtn:FindFirstChild("BtnLabel") :: TextLabel?
		if submitLabel then
			submitLabel.Text = "SUBMITTED!"
			submitLabel.TextColor3 = Color3.fromRGB(160, 255, 160)
		end
		submittedNotice.Text = string.format("Secret Bid Registered: $%.2f", val)

		pcall(function()
			local clickSound = Instance.new("Sound")
			clickSound.SoundId = "rbxasset://sounds/action_jump.mp3"
			clickSound.Volume = 0.5
			clickSound.Parent = SoundService
			clickSound:Play()
			Debris:AddItem(clickSound, 1)
		end)
	end

	submitBtn.MouseButton1Click:Connect(handleSubmitBid)
	submitBtn.Activated:Connect(handleSubmitBid)

	function self:Open(currentWallet: number)
		self.CurrentWallet = currentWallet or 20.00
		self.IsOpening = true

		if self.HasSubmitted and self.SubmittedAmount ~= nil then
			-- Retain submitted amount and notice until the bidding round completes
			self.BidInput.Text = string.format("%.2f", self.SubmittedAmount)
			self.SubmittedNotice.Text = string.format("Secret Bid Registered: $%.2f", self.SubmittedAmount)
			self.SubmittedNotice.TextColor3 = Color3.fromRGB(160, 255, 160)

			self.SubmitBtn.Text = ""
			local submitGrad = self.SubmitBtn:FindFirstChildOfClass("UIGradient")
			if submitGrad then submitGrad.Enabled = false end
			self.SubmitBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
			local submitLabel = self.SubmitBtn:FindFirstChild("BtnLabel") :: TextLabel?
			if submitLabel then
				submitLabel.Text = "SUBMITTED!"
				submitLabel.TextColor3 = Color3.fromRGB(160, 255, 160)
			end
		else
			self.BidInput.Text = ""
			self.SubmittedNotice.Text = ""
			applySVG3ButtonStyle(self.SubmitBtn, "BID", 24)
		end
		self.IsOpening = false

		self.ModalFrame.Visible = true
		self.ModalFrame.Size = UDim2.new(0, 430, 0, 220)
		TweenService:Create(self.ModalFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 480, 0, 250),
		}):Play()

		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:Close()
		self.ModalFrame.Visible = false
		if onVisibilityChanged then onVisibilityChanged() end
	end

	function self:Reset()
		self.HasSubmitted = false
		self.SubmittedAmount = nil
		self.BidInput.Text = ""
		self.SubmittedNotice.Text = ""
		applySVG3ButtonStyle(self.SubmitBtn, "BID", 24)
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

return BiddingModalView
