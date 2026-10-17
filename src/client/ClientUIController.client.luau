--!strict
-- src/client/ClientUIController.client.luau
-- Authoritative Client UI Orchestrator: Connects ReplicatedStorage.Network events
-- to modular UI views (Docks, Banner, Modals, Hammer Spinner, Effects).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local StarterGui = game:GetService("StarterGui")

-- Eliminate default Roblox top-right Health Bar completely
task.spawn(function()
	local maxRetries = 20
	while maxRetries > 0 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then break end
		task.wait(0.2)
		maxRetries -= 1
	end
end)

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local gui = (script:FindFirstAncestorWhichIsA("ScreenGui") or playerGui:WaitForChild("BidToSurviveUI")) :: ScreenGui

-- Shared Modules & Network
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig")) :: any
local Network = ReplicatedStorage:WaitForChild("Network")

local StateChanged = Network:WaitForChild("StateChanged") :: RemoteEvent
local PromptBid = Network:WaitForChild("PromptBid") :: RemoteEvent
local BidSubmitted = Network:WaitForChild("BidSubmitted") :: RemoteEvent
local RankingsRevealed = Network:WaitForChild("RankingsRevealed") :: RemoteEvent
local HammerSmash = Network:WaitForChild("HammerSmash") :: RemoteEvent
local RoundOver = Network:WaitForChild("RoundOver") :: RemoteEvent
local MatchOver = Network:WaitForChild("MatchOver") :: RemoteEvent
local StatsUpdated = Network:WaitForChild("StatsUpdated") :: RemoteEvent

local SetAFK = Network:FindFirstChild("SetAFK") :: RemoteEvent?
if not SetAFK then
	SetAFK = Instance.new("RemoteEvent")
	SetAFK.Name = "SetAFK"
	SetAFK.Parent = Network
end

local ParticipationChanged = Network:FindFirstChild("ParticipationChanged") :: RemoteEvent?
if not ParticipationChanged then
	ParticipationChanged = Instance.new("RemoteEvent")
	ParticipationChanged.Name = "ParticipationChanged"
	ParticipationChanged.Parent = Network
end

-- Modular UI Views
local ClientUI = ReplicatedStorage:WaitForChild("ClientUI")
local ControlsDockView = require(ClientUI:WaitForChild("components"):WaitForChild("ControlsDockView")) :: any
local PhaseBannerView = require(ClientUI:WaitForChild("components"):WaitForChild("PhaseBannerView")) :: any
local ActionDockView = require(ClientUI:WaitForChild("components"):WaitForChild("ActionDockView")) :: any
local HammerRouletteView = require(ClientUI:WaitForChild("components"):WaitForChild("HammerRouletteView")) :: any
local BiddingModalView = require(ClientUI:WaitForChild("modals"):WaitForChild("BiddingModalView")) :: any
local RankingsModalView = require(ClientUI:WaitForChild("modals"):WaitForChild("RankingsModalView")) :: any
local MatchOverModalView = require(ClientUI:WaitForChild("modals"):WaitForChild("MatchOverModalView")) :: any
local ScreenEffectsView = require(ClientUI:WaitForChild("effects"):WaitForChild("ScreenEffectsView")) :: any

-- State
local CurrentMoney = GameConfig.StartingMoney or 20.00
local CurrentHealth = GameConfig.MaxHealth or 100
local IsAlive = true
local IsAFK = false
local CurrentParticipationState = "WaitingInLobby"
local CurrentPhase = "Intermission"
local CurrentRound = 0
local SessionToken = 0

local function IsActiveInRound(): boolean
	return (CurrentParticipationState == "Active") or (LocalPlayer:GetAttribute("IsInGame") == true)
end

-- Clean up obsolete legacy StatsCard if present
local oldStatsCard = gui:FindFirstChild("StatsCard")
if oldStatsCard then
	oldStatsCard:Destroy()
end
local legacyStatsCard = playerGui:FindFirstChild("BidToSurviveUI") and playerGui.BidToSurviveUI:FindFirstChild("StatsCard")
if legacyStatsCard then
	legacyStatsCard:Destroy()
end

-- Initialize Components
local screenEffects = ScreenEffectsView.new(gui)
local controlsDock = ControlsDockView.new(gui, SetAFK)
local phaseBanner = PhaseBannerView.new(gui)
local biddingModal = BiddingModalView.new(gui, BidSubmitted, nil)
local rankingsModal = RankingsModalView.new(gui, nil)
local matchOverModal = MatchOverModalView.new(gui, nil)

local actionDock = ActionDockView.new(gui, function()
	if IsActiveInRound() and CurrentPhase == "Phase3_Bid" then
		biddingModal:Open(CurrentMoney)
	end
end, function()
	if IsActiveInRound() and CurrentPhase == "Phase4_Reveal" then
		rankingsModal:Open()
	end
end)

local hammerRoulette = HammerRouletteView.new(gui, GameConfig, function(intensity, duration)
	screenEffects:ShakeCamera(intensity, duration, IsActiveInRound)
end)

local function updateActionButtons()
	actionDock:UpdateVisibility(CurrentPhase, IsActiveInRound(), biddingModal:IsVisible(), rankingsModal:IsVisible())
end

-- Link visibility change callbacks to actionDock
biddingModal.ModalFrame:GetPropertyChangedSignal("Visible"):Connect(updateActionButtons)
rankingsModal.ModalFrame:GetPropertyChangedSignal("Visible"):Connect(updateActionButtons)

-- Bind damage flash
if LocalPlayer.Character then
	screenEffects:BindCharacterHealth(LocalPlayer.Character, IsActiveInRound)
end
LocalPlayer.CharacterAdded:Connect(function(newChar)
	screenEffects:BindCharacterHealth(newChar, IsActiveInRound)
end)

local function forceHideAllRoundUI()
	biddingModal:Close()
	rankingsModal:Close()
	matchOverModal:Hide()
	hammerRoulette:Stop()
	actionDock:SetVisible(false)
	if CurrentPhase ~= "Intermission" then
		phaseBanner:SetVisible(false)
	end
end

-- Network Listeners
StateChanged.OnClientEvent:Connect(function(arg1, arg2)
	local phase: string = ""
	local data: any = nil
	if typeof(arg1) == "table" then
		data = arg1
		phase = arg1.Phase or ""
	else
		phase = tostring(arg1 or "")
		data = arg2 or {}
	end

	CurrentPhase = phase
	SessionToken += 1
	local myToken = SessionToken

	local deadline = (data and data.Deadline) or 0
	local round = (data and (data.Round or data.CurrentRound)) or CurrentRound
	CurrentRound = round
	local living = (data and data.LivingCount) or (data and data.Living) or 0

	phaseBanner:UpdateParticipation(IsActiveInRound(), IsAFK)
	phaseBanner:SetPhase(phase, round, living, deadline)

	if not IsActiveInRound() then
		forceHideAllRoundUI()
		if phase == "Intermission" then
			phaseBanner:SetVisible(not IsAFK)
		else
			phaseBanner:SetVisible(false)
		end
		return
	end

	updateActionButtons()

	if phase == "Intermission" then
		phaseBanner:SetVisible(true)
		forceHideAllRoundUI()
	elseif phase == "Phase1_Spawn" then
		phaseBanner:SetVisible(true)
		biddingModal:Close()
		rankingsModal:Close()
		local rarity = data and data.Rarity
		if rarity then
			local spinnerReel = (data.Extra and data.Extra.SpinnerReel) or data.SpinnerReel
			task.spawn(function()
				hammerRoulette:Play(rarity, data.RouletteDuration or 6.0, spinnerReel, IsActiveInRound, myToken, function() return SessionToken end)
			end)
		end
	elseif phase == "Phase2_Vote" then
		phaseBanner:SetVisible(true)
		hammerRoulette:Stop()
		biddingModal:Close()
		rankingsModal:Close()
	elseif phase == "Phase3_Bid" then
		phaseBanner:SetVisible(true)
		hammerRoulette:Stop()
		rankingsModal:Close()
	elseif phase == "Phase4_Reveal" then
		phaseBanner:SetVisible(false)
		hammerRoulette:Stop()
		biddingModal:Close()
		biddingModal:Reset()
	elseif phase == "Phase5_Scramble" then
		phaseBanner:SetVisible(true)
		hammerRoulette:Stop()
		rankingsModal:Close()
		biddingModal:Close()
		biddingModal:Reset()
	elseif phase == "Phase6_Smash" then
		phaseBanner:SetVisible(true)
		hammerRoulette:Stop()
		biddingModal:Close()
		rankingsModal:Close()
	elseif phase == "Phase7_Settlement" then
		phaseBanner:SetVisible(true)
		hammerRoulette:Stop()
		biddingModal:Close()
		rankingsModal:Close()
	elseif phase == "MatchOver" then
		phaseBanner:SetVisible(false)
		hammerRoulette:Stop()
		biddingModal:Close()
		biddingModal:Reset()
		rankingsModal:Close()
	end

	updateActionButtons()
end)

PromptBid.OnClientEvent:Connect(function(_data)
	CurrentPhase = "Phase3_Bid"
	if not IsActiveInRound() then
		biddingModal:Close()
		updateActionButtons()
		return
	end
	biddingModal:Reset()
	biddingModal:Open(CurrentMoney)
	updateActionButtons()
end)

RankingsRevealed.OnClientEvent:Connect(function(data)
	CurrentPhase = "Phase4_Reveal"
	if not IsActiveInRound() then
		rankingsModal:Close()
		updateActionButtons()
		return
	end
	phaseBanner:SetVisible(false)
	rankingsModal:Populate(data, LocalPlayer, CurrentRound)
	updateActionButtons()
end)

HammerSmash.OnClientEvent:Connect(function(data)
	if not IsActiveInRound() then return end
	local rarity = data and data.Rarity
	local impactDelay = (data and data.ImpactDelay) or 1.33
	local myToken = SessionToken

	task.delay(impactDelay, function()
		if (not IsActiveInRound()) or myToken ~= SessionToken then return end
		local intensity = (rarity and rarity.CameraShake) or 1.0
		screenEffects:ShakeCamera(intensity * 3, 0.8, IsActiveInRound)
	end)
end)

RoundOver.OnClientEvent:Connect(function()
	rankingsModal:Close()
	biddingModal:Close()
	updateActionButtons()
end)

MatchOver.OnClientEvent:Connect(function(data)
	if IsAFK then return end
	matchOverModal:Show(data, LocalPlayer)
end)

StatsUpdated.OnClientEvent:Connect(function(stats)
	CurrentMoney = stats.Money or CurrentMoney
	CurrentHealth = stats.Health or CurrentHealth
	IsAlive = (stats.IsAlive ~= nil) and stats.IsAlive or IsAlive
	if stats.IsAFK ~= nil then
		IsAFK = stats.IsAFK
		controlsDock:SetAFK(IsAFK)
	end
	if stats.ParticipationState ~= nil then
		CurrentParticipationState = stats.ParticipationState
	end

	phaseBanner:UpdateParticipation(IsActiveInRound(), IsAFK)
	if not IsActiveInRound() then
		forceHideAllRoundUI()
	else
		updateActionButtons()
	end
end)

if ParticipationChanged then
	ParticipationChanged.OnClientEvent:Connect(function(newState: string)
		CurrentParticipationState = newState
		phaseBanner:UpdateParticipation(IsActiveInRound(), IsAFK)
		if not IsActiveInRound() then
			forceHideAllRoundUI()
		else
			updateActionButtons()
		end
	end)
end

LocalPlayer:GetAttributeChangedSignal("IsInGame"):Connect(function()
	phaseBanner:UpdateParticipation(IsActiveInRound(), IsAFK)
	if not IsActiveInRound() then
		forceHideAllRoundUI()
	else
		updateActionButtons()
	end
end)

-- Developer hotkey F4 to test Results UI in Studio
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F4 then
		matchOverModal:Show({
			Winner = LocalPlayer.DisplayName,
			TotalDuration = 83,
			Podium = {
				{ Rank = 1, UserId = LocalPlayer.UserId, Name = LocalPlayer.Name, DisplayName = LocalPlayer.DisplayName, SurvivalTime = 83 },
				{ Rank = 2, UserId = 1, Name = "RunnerUp", DisplayName = "RunnerUp", SurvivalTime = 72 },
				{ Rank = 3, UserId = 2, Name = "Contender", DisplayName = "Contender", SurvivalTime = 58 },
			},
		}, LocalPlayer)
	end
end)
