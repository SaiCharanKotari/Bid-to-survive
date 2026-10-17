--!strict
-- src/client/ui/components/PhaseBannerView.luau
-- Manages the top floating banner, phase name display, round counter, and frame-accurate countdown ticker.

local RunService = game:GetService("RunService")

local PhaseBannerView = {}
PhaseBannerView.__index = PhaseBannerView

export type PhaseBanner = {
	BannerFrame: Frame,
	PhaseTitle: TextLabel,
	TimerLabel: TextLabel,
	InfoLabel: TextLabel,
	RoundLabel: TextLabel,
	CurrentPhase: string,
	CurrentDeadline: number,
	IsActiveInRound: boolean,
	IsAFK: boolean,
	HeartbeatConn: RBXScriptConnection?,
	SetPhase: (self: PhaseBanner, phase: string, round: number, living: number, deadline: number) -> (),
	UpdateParticipation: (self: PhaseBanner, isActive: boolean, isAFK: boolean) -> (),
	SetVisible: (self: PhaseBanner, visible: boolean) -> (),
	Destroy: (self: PhaseBanner) -> (),
}

local function getSimplePhaseName(phase: any): string
	if not phase then return "" end
	if typeof(phase) == "table" then
		phase = phase.Phase or phase.Name or ""
	end
	if typeof(phase) ~= "string" then return "" end

	if phase == "Phase6_Smash" then
		return "Smash"
	elseif phase == "Phase5_Scramble" then
		return "Survival Stance"
	elseif phase == "Phase3_Bid" then
		return "Bidding"
	elseif phase == "Phase4_Reveal" then
		return "Rankings"
	elseif phase == "Phase1_Spawn" then
		return "Hammer Reveal"
	elseif phase == "Phase2_Vote" then
		return "Vote"
	elseif phase == "Phase7_Settlement" then
		return "Settlement"
	elseif phase == "Intermission" then
		return "Lobby"
	elseif phase == "MatchOver" then
		return "Match Over"
	else
		return (string.gsub(phase, "^Phase%d*_*", ""))
	end
end

function PhaseBannerView.new(gui: ScreenGui): PhaseBanner
	local self = setmetatable({}, PhaseBannerView) :: any
	self.CurrentPhase = "Intermission"
	self.CurrentDeadline = 0
	self.IsActiveInRound = false
	self.IsAFK = false

	-- 1. TopBanner Frame
	local topBanner = gui:FindFirstChild("TopBanner") :: Frame?
	if not topBanner then
		topBanner = Instance.new("Frame")
		topBanner.Name = "TopBanner"
		topBanner.AnchorPoint = Vector2.new(0.5, 0)
		topBanner.Position = UDim2.new(0.5, 0, 0, 10)
		topBanner.Size = UDim2.new(0, 440, 0, 56)
		topBanner.BackgroundTransparency = 1
		topBanner.BorderSizePixel = 0
		topBanner.ZIndex = 20
		topBanner.Visible = false
		topBanner.Parent = gui
	else
		topBanner.BackgroundTransparency = 1
		topBanner.BorderSizePixel = 0
		topBanner.AnchorPoint = Vector2.new(0.5, 0)
		topBanner.Position = UDim2.new(0.5, 0, 0, 10)
		topBanner.Size = UDim2.new(0, 440, 0, 56)
		local oldStroke = topBanner:FindFirstChildOfClass("UIStroke")
		if oldStroke then oldStroke:Destroy() end
		local oldCorner = topBanner:FindFirstChildOfClass("UICorner")
		if oldCorner then oldCorner:Destroy() end
	end
	self.BannerFrame = topBanner

	-- 2. PhaseTitle TextLabel
	local phaseTitle = topBanner:FindFirstChild("PhaseTitle") :: TextLabel?
	if not phaseTitle then
		phaseTitle = Instance.new("TextLabel")
		phaseTitle.Name = "PhaseTitle"
		phaseTitle.AnchorPoint = Vector2.new(0.5, 0)
		phaseTitle.Position = UDim2.new(0.5, 0, 0, 0)
		phaseTitle.Size = UDim2.new(1, 0, 0, 26)
		phaseTitle.BackgroundTransparency = 1
		phaseTitle.Font = Enum.Font.GothamBlack
		phaseTitle.TextSize = 22
		phaseTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		phaseTitle.TextXAlignment = Enum.TextXAlignment.Center
		phaseTitle.TextYAlignment = Enum.TextYAlignment.Center
		phaseTitle.ZIndex = 22

		local pStroke = Instance.new("UIStroke")
		pStroke.Color = Color3.fromRGB(0, 0, 0)
		pStroke.Thickness = 2.5
		pStroke.Parent = phaseTitle

		phaseTitle.Parent = topBanner
	else
		phaseTitle.AnchorPoint = Vector2.new(0.5, 0)
		phaseTitle.Position = UDim2.new(0.5, 0, 0, 0)
		phaseTitle.Size = UDim2.new(1, 0, 0, 26)
		phaseTitle.BackgroundTransparency = 1
		phaseTitle.Font = Enum.Font.GothamBlack
		phaseTitle.TextSize = 22
		phaseTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		phaseTitle.TextXAlignment = Enum.TextXAlignment.Center
		phaseTitle.TextYAlignment = Enum.TextYAlignment.Center
	end
	self.PhaseTitle = phaseTitle

	-- 3. RoundLabel TextLabel
	local roundLabel = topBanner:FindFirstChild("RoundLabel") :: TextLabel?
	if not roundLabel then
		roundLabel = Instance.new("TextLabel")
		roundLabel.Name = "RoundLabel"
		roundLabel.AnchorPoint = Vector2.new(0.5, 0)
		roundLabel.Position = UDim2.new(0.5, 0, 0, 27)
		roundLabel.Size = UDim2.new(1, 0, 0, 20)
		roundLabel.BackgroundTransparency = 1
		roundLabel.Font = Enum.Font.GothamBold
		roundLabel.TextSize = 13
		roundLabel.TextColor3 = Color3.fromRGB(210, 225, 245)
		roundLabel.TextXAlignment = Enum.TextXAlignment.Center
		roundLabel.TextYAlignment = Enum.TextYAlignment.Center
		roundLabel.ZIndex = 22

		local rStroke = Instance.new("UIStroke")
		rStroke.Color = Color3.fromRGB(0, 0, 0)
		rStroke.Thickness = 2
		rStroke.Parent = roundLabel

		roundLabel.Parent = topBanner
	else
		roundLabel.AnchorPoint = Vector2.new(0.5, 0)
		roundLabel.Position = UDim2.new(0.5, 0, 0, 27)
		roundLabel.Size = UDim2.new(1, 0, 0, 20)
		roundLabel.BackgroundTransparency = 1
		roundLabel.Font = Enum.Font.GothamBold
		roundLabel.TextSize = 13
		roundLabel.TextColor3 = Color3.fromRGB(210, 225, 245)
		roundLabel.TextXAlignment = Enum.TextXAlignment.Center
		roundLabel.TextYAlignment = Enum.TextYAlignment.Center
	end
	self.RoundLabel = roundLabel

	-- 4. TimerLabel & InfoLabel (kept for backwards compatibility)
	local timerLabel = topBanner:FindFirstChild("TimerLabel") :: TextLabel?
	if not timerLabel then
		timerLabel = Instance.new("TextLabel")
		timerLabel.Name = "TimerLabel"
		timerLabel.Visible = false
		timerLabel.Parent = topBanner
	else
		timerLabel.Visible = false
	end
	self.TimerLabel = timerLabel

	local infoLabel = topBanner:FindFirstChild("InfoLabel") :: TextLabel?
	if not infoLabel then
		infoLabel = Instance.new("TextLabel")
		infoLabel.Name = "InfoLabel"
		infoLabel.Visible = false
		infoLabel.Parent = topBanner
	else
		infoLabel.Visible = false
	end
	self.InfoLabel = infoLabel

	-- Frame-accurate ticker heartbeat
	self.HeartbeatConn = RunService.Heartbeat:Connect(function()
		-- Inactive/lobby players should not see countdowns for ongoing match phases
		if not self.IsActiveInRound and self.CurrentPhase ~= "Intermission" then
			if self.BannerFrame.Visible then
				self.BannerFrame.Visible = false
			end
			if self.PhaseTitle.Text ~= "" then
				self.PhaseTitle.Text = ""
			end
			return
		end

		if self.CurrentDeadline > 0 and (self.IsActiveInRound or (self.CurrentPhase == "Intermission" and not self.IsAFK and self.BannerFrame.Visible)) then
			local remaining = math.max(0, math.ceil(self.CurrentDeadline - os.clock()))
			local simpleName = getSimplePhaseName(self.CurrentPhase)
			self.PhaseTitle.Text = string.format("%s - %ds", simpleName, remaining)
		else
			local simpleName = getSimplePhaseName(self.CurrentPhase)
			if simpleName ~= "" and simpleName ~= "Lobby" and self.IsActiveInRound then
				self.PhaseTitle.Text = string.format("%s - 0s", simpleName)
			else
				self.PhaseTitle.Text = ""
			end
		end
	end)

	function self:SetPhase(phase: string, round: number, living: number, deadline: number)
		self.CurrentPhase = phase
		self.CurrentDeadline = deadline or 0
		if round and living then
			self.RoundLabel.Text = string.format("ROUND %d • %d ALIVE", round, living)
		end
	end

	function self:UpdateParticipation(isActive: boolean, isAFK: boolean)
		self.IsActiveInRound = isActive
		self.IsAFK = isAFK
	end

	function self:SetVisible(visible: boolean)
		self.BannerFrame.Visible = visible
	end

	function self:Destroy()
		if self.HeartbeatConn then
			self.HeartbeatConn:Disconnect()
			self.HeartbeatConn = nil
		end
	end

	return self
end

return PhaseBannerView
