-- StarterPlayer/StarterPlayerScripts/GlobalButtonAndSVG3UI.client.luau
-- Universal SVG.3 Styling & Game-Wide Tactile Button Micro-Interactions Engine

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- 1. GLOBAL UI SOUND PALETTE (Hover Tick & Click Pop)
-- ============================================================================
local hoverSound = SoundService:FindFirstChild("GlobalUIHoverSound") :: Sound?
if not hoverSound then
	hoverSound = Instance.new("Sound")
	hoverSound.Name = "GlobalUIHoverSound"
	hoverSound.SoundId = "rbxassetid://6895079853" -- Crisp subtle UI hover tick
	hoverSound.Volume = 0.35
	hoverSound.PlaybackSpeed = 1.15
	hoverSound.Parent = SoundService
end

local clickPopSound = SoundService:FindFirstChild("GlobalUIClickPopSound") :: Sound?
if not clickPopSound then
	clickPopSound = Instance.new("Sound")
	clickPopSound.Name = "GlobalUIClickPopSound"
	clickPopSound.SoundId = "rbxassetid://6895079853" -- Tactile pop on click
	clickPopSound.Volume = 0.65
	clickPopSound.PlaybackSpeed = 0.92
	clickPopSound.Parent = SoundService
end

-- ============================================================================
-- 2. UNIVERSAL HOVER & CLICK POP ENGINE (Applies to EVERY Button in the Game!)
-- ============================================================================
local hookedButtons: { [GuiButton]: boolean } = {}

local function attachGlobalHoverAndClickPop(button: GuiButton)
	if hookedButtons[button] then return end
	hookedButtons[button] = true

	button.AutoButtonColor = false

	-- Ensure UIScale exists for smooth Hover & Click Pop
	local uiScale = button:FindFirstChild("InteractionScale") :: UIScale?
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "InteractionScale"
		uiScale.Scale = 1.0
		uiScale.Parent = button
	end

	-- Glossy Flash Overlay for Hover & Click Pop punch
	local flashOverlay = button:FindFirstChild("ClickFlashOverlay") :: Frame?
	if not flashOverlay then
		flashOverlay = Instance.new("Frame")
		flashOverlay.Name = "ClickFlashOverlay"
		flashOverlay.Size = UDim2.fromScale(1, 1)
		flashOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flashOverlay.BackgroundTransparency = 1
		flashOverlay.BorderSizePixel = 0
		flashOverlay.ZIndex = button.ZIndex + 1
		flashOverlay.Active = false
		flashOverlay.Parent = button

		local existingCorner = button:FindFirstChildOfClass("UICorner")
		if existingCorner then
			existingCorner:Clone().Parent = flashOverlay
		end
	end

	local isHovered = false

	-- HOVER ENTER (0.16s - 1.07x Scale + Sheen Lift + Hover Tick)
	button.MouseEnter:Connect(function()
		isHovered = true
		pcall(function() hoverSound:Play() end)

		TweenService:Create(uiScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.07
		}):Play()

		TweenService:Create(flashOverlay, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.88
		}):Play()

		local grad = button:FindFirstChildOfClass("UIGradient")
		if grad then
			TweenService:Create(grad, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Offset = Vector2.new(0, -0.06)
			}):Play()
		end
	end)

	-- HOVER LEAVE (0.18s - Reset Scale & Gradient Offset)
	button.MouseLeave:Connect(function()
		isHovered = false

		TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.0
		}):Play()

		TweenService:Create(flashOverlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1.0
		}):Play()

		local grad = button:FindFirstChildOfClass("UIGradient")
		if grad then
			TweenService:Create(grad, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Offset = Vector2.new(0, 0)
			}):Play()
		end
	end)

	-- CLICK PRESS DOWN (0.06s Squash to 0.90x)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 0.90
		}):Play()
	end)

	-- CLICK RELEASE POP (Overshoot 1.13x -> Settle to 1.07x / 1.00x + Flash Pulse)
	button.MouseButton1Up:Connect(function()
		pcall(function() clickPopSound:Play() end)

		-- Bright white pop flash (0.45 -> settle)
		flashOverlay.BackgroundTransparency = 0.45
		TweenService:Create(flashOverlay, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = isHovered and 0.88 or 1.0
		}):Play()

		-- Overshoot to 1.13x then settle
		local popUp = TweenService:Create(uiScale, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.13
		})
		popUp:Play()
		popUp.Completed:Once(function()
			TweenService:Create(uiScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = isHovered and 1.07 or 1.0
			}):Play()
		end)
	end)
end

-- ============================================================================
-- 3. EXACT SVG.3 STYLE BUILDER (Red-to-Silver Gradient + 5px Black Stroke)
-- ============================================================================
local function applySVG3ButtonStyle(button: TextButton, labelText: string, textSize: number?)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- White base allows UIGradient 1:1 color fidelity
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.Text = "" -- Keep native text blank so UIGradient does NOT tint text red

	-- Sharp rectangular silhouette matching svg.3 (0px - 2px)
	local corner = button:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = button
	end
	corner.CornerRadius = UDim.new(0, 1)

	-- Solid Pitch-Black outer border: UIStroke with Thickness = 5, ApplyStrokeMode = Border, LineJoinMode = Miter
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = button
	end
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter

	-- Exact Vertical Red-to-Metallic-Silver Gradient from svg.3
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = button
	end
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHex("#EC0000")), -- Vivid Crimson Top
		ColorSequenceKeypoint.new(0.54, Color3.fromHex("#F50505")), -- Pure Red Mid-Core
		ColorSequenceKeypoint.new(0.78, Color3.fromHex("#E25A5A")), -- Coral Transition
		ColorSequenceKeypoint.new(1.00, Color3.fromHex("#D6C7C7")), -- Metallic Silver-Blush Bottom
	})
	gradient.Enabled = true

	-- Independent Crisp White TextLabel (Guaranteed unaffected by UIGradient)
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
	label.TextSize = textSize or 28
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center

	attachGlobalHoverAndClickPop(button)
end

-- ============================================================================
-- 4. STYLE & POSITION "BID" AND "LEADERBOARD" IN MIDDLE & SLIGHTLY UP (0.5, 0.42)
-- ============================================================================
local function upgradeBidAndLeaderboardButtons()
	local centerDock = playerGui:FindFirstChild("CenterActionDock", true) :: Frame?
		or playerGui:FindFirstChild("ReopenContainer", true) :: Frame?

	if centerDock then
		centerDock.Name = "CenterActionDock"
		centerDock.AnchorPoint = Vector2.new(0.5, 0.5)
		centerDock.Position = UDim2.new(0.5, 0, 0.42, 0)
		centerDock.Size = UDim2.new(0, 460, 0, 62)
		centerDock.BackgroundTransparency = 1

		local bidButton = centerDock:FindFirstChild("ReopenBidBtn") :: TextButton?
			or centerDock:FindFirstChild("BidButton") :: TextButton?
		local leaderboardButton = centerDock:FindFirstChild("ReopenRankBtn") :: TextButton?
			or centerDock:FindFirstChild("LeaderboardButton") :: TextButton?

		if bidButton then
			applySVG3ButtonStyle(bidButton, "BID", 28)
			bidButton.AnchorPoint = Vector2.new(0.5, 0.5)
			bidButton.Size = UDim2.new(0, 210, 0, 62)
			bidButton.Position = UDim2.new(0.5, -118, 0.5, 0)
		end

		if leaderboardButton then
			applySVG3ButtonStyle(leaderboardButton, "LEADERBOARD", 20)
			leaderboardButton.AnchorPoint = Vector2.new(0.5, 0.5)
			leaderboardButton.Size = UDim2.new(0, 210, 0, 62)
			leaderboardButton.Position = UDim2.new(0.5, 118, 0.5, 0)
		end
	end

	-- Also style modal SubmitBtn cleanly inside BidBtnContainer
	local modal = playerGui:FindFirstChild("BiddingModal", true)
	local card = modal and modal:FindFirstChild("CardFrame")
	local btnContainer = card and card:FindFirstChild("BidBtnContainer")
	local submitBtn = btnContainer and btnContainer:FindFirstChild("SubmitBtn") :: TextButton?
	if submitBtn then
		applySVG3ButtonStyle(submitBtn, "BID", 28)
		btnContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		btnContainer.Position = UDim2.new(0.5, 0, 0.68, 0)
		btnContainer.Size = UDim2.new(0, 210, 0, 56)

		local shadow = btnContainer:FindFirstChild("BtnShadow")
		if shadow then
			shadow.AnchorPoint = Vector2.new(0.5, 0.5)
			shadow.Position = UDim2.new(0.5, 4, 0.5, 4)
			shadow.Size = UDim2.new(1, 0, 1, 0)
			shadow.ZIndex = 25
		end

		submitBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		submitBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
		submitBtn.Size = UDim2.new(1, 0, 1, 0)
		submitBtn.ZIndex = 26
	end
end

-- ============================================================================
-- 5. HOOK ALL EXISTING & FUTURE BUTTONS ACROSS THE ENTIRE GAME
-- ============================================================================
for _, desc in ipairs(playerGui:GetDescendants()) do
	if desc:IsA("GuiButton") then
		attachGlobalHoverAndClickPop(desc)
	end
end

upgradeBidAndLeaderboardButtons()

playerGui.DescendantAdded:Connect(function(desc)
	if desc:IsA("GuiButton") then
		task.defer(function()
			attachGlobalHoverAndClickPop(desc)
			local nameLower = string.lower(desc.Name)
			if desc:IsA("TextButton") and (string.find(nameLower, "bid") or string.find(nameLower, "rank") or string.find(nameLower, "leaderboard")) then
				upgradeBidAndLeaderboardButtons()
			end
		end)
	end
end)

print("[GlobalButtonAndSVG3UI] Universal Hover & Click Pop Engine & SVG.3 Button System active.")
