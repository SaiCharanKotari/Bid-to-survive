--!strict
-- src/client/ui/components/ActionDockView.luau
-- Manages the center action dock with "BID" and "LEADERBOARD" quick-reopen buttons.

local ActionDockView = {}
ActionDockView.__index = ActionDockView

export type ActionDock = {
	DockFrame: Frame,
	ReopenBidBtn: TextButton,
	ReopenRankBtn: TextButton,
	UpdateVisibility: (self: ActionDock, phase: string, isActiveInRound: boolean, bidModalVisible: boolean, rankModalVisible: boolean) -> (),
	SetVisible: (self: ActionDock, visible: boolean) -> (),
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

function ActionDockView.new(gui: ScreenGui, onOpenBid: () -> (), onOpenRank: () -> ()): ActionDock
	local self = setmetatable({}, ActionDockView) :: any

	local centerActionDock = (gui:FindFirstChild("CenterActionDock") or gui:FindFirstChild("ReopenContainer")) :: Frame?
	if not centerActionDock then
		centerActionDock = Instance.new("Frame")
		centerActionDock.Name = "CenterActionDock"
		centerActionDock.AnchorPoint = Vector2.new(0.5, 0.5)
		centerActionDock.Position = UDim2.new(0.5, 0, 0.25, 0)
		centerActionDock.Size = UDim2.new(0, 184, 0, 50)
		centerActionDock.BackgroundTransparency = 1
		centerActionDock.ZIndex = 35
		centerActionDock.Visible = false
		centerActionDock.Parent = gui
	else
		centerActionDock.AnchorPoint = Vector2.new(0.5, 0.5)
		centerActionDock.Position = UDim2.new(0.5, 0, 0.25, 0)
		centerActionDock.Size = UDim2.new(0, 184, 0, 50)
	end
	self.DockFrame = centerActionDock

	-- 1. ReopenBidBtn
	local reopenBidBtn = centerActionDock:FindFirstChild("ReopenBidBtn") :: TextButton?
	if not reopenBidBtn then
		reopenBidBtn = Instance.new("TextButton")
		reopenBidBtn.Name = "ReopenBidBtn"
		reopenBidBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		reopenBidBtn.Size = UDim2.new(0, 184, 0, 50)
		reopenBidBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
		reopenBidBtn.ZIndex = 36
		reopenBidBtn.Visible = false
		reopenBidBtn.Parent = centerActionDock
	end
	applySVG3ButtonStyle(reopenBidBtn, "BID", 24)
	self.ReopenBidBtn = reopenBidBtn

	-- 2. ReopenRankBtn
	local reopenRankBtn = centerActionDock:FindFirstChild("ReopenRankBtn") :: TextButton?
	if not reopenRankBtn then
		reopenRankBtn = Instance.new("TextButton")
		reopenRankBtn.Name = "ReopenRankBtn"
		reopenRankBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		reopenRankBtn.Size = UDim2.new(0, 184, 0, 50)
		reopenRankBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
		reopenRankBtn.ZIndex = 36
		reopenRankBtn.Visible = false
		reopenRankBtn.Parent = centerActionDock
	end
	applySVG3ButtonStyle(reopenRankBtn, "LEADERBOARD", 18)
	self.ReopenRankBtn = reopenRankBtn

	reopenBidBtn.MouseButton1Click:Connect(function()
		if onOpenBid then onOpenBid() end
	end)

	reopenRankBtn.MouseButton1Click:Connect(function()
		if onOpenRank then onOpenRank() end
	end)

	function self:UpdateVisibility(phase: string, isActiveInRound: boolean, bidModalVisible: boolean, rankModalVisible: boolean)
		if not isActiveInRound then
			self.ReopenBidBtn.Visible = false
			self.ReopenRankBtn.Visible = false
			self.DockFrame.Visible = false
			return
		end

		if phase == "Phase3_Bid" then
			self.ReopenBidBtn.Visible = not bidModalVisible
			self.ReopenRankBtn.Visible = false
		elseif phase == "Phase4_Reveal" then
			self.ReopenBidBtn.Visible = false
			self.ReopenRankBtn.Visible = not rankModalVisible
		else
			self.ReopenBidBtn.Visible = false
			self.ReopenRankBtn.Visible = false
		end

		self.DockFrame.Visible = (self.ReopenBidBtn.Visible or self.ReopenRankBtn.Visible)
	end

	function self:SetVisible(visible: boolean)
		self.DockFrame.Visible = visible
	end

	return self
end

return ActionDockView
