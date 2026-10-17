--!strict
-- src/client/ui/effects/ScreenEffectsView.luau
-- Manages fullscreen flashes (damage/phase transition) and camera shake spring oscillations.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ScreenEffectsView = {}
ScreenEffectsView.__index = ScreenEffectsView

export type ScreenEffects = {
	FlashFrame: Frame,
	ActiveFlashTween: Tween?,
	ShakeConn: RBXScriptConnection?,
	LastRecordedHealth: number,
	Flash: (self: ScreenEffects, color: Color3?, transparency: number?, duration: number?) -> (),
	ShakeCamera: (self: ScreenEffects, intensity: number, duration: number, isRoundActive: (() -> boolean)?) -> (),
	StopShake: (self: ScreenEffects) -> (),
	BindCharacterHealth: (self: ScreenEffects, char: Model, isRoundActive: () -> boolean) -> (),
}

function ScreenEffectsView.new(gui: ScreenGui): ScreenEffects
	local self = setmetatable({}, ScreenEffectsView) :: any
	self.LastRecordedHealth = 100

	-- ScreenFlash Frame
	local screenFlash = gui:FindFirstChild("ScreenFlash") :: Frame?
	if not screenFlash then
		screenFlash = Instance.new("Frame")
		screenFlash.Name = "ScreenFlash"
		screenFlash.Size = UDim2.fromScale(1, 1)
		screenFlash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		screenFlash.BackgroundTransparency = 1
		screenFlash.Visible = false
		screenFlash.Active = false
		screenFlash.ZIndex = 25
		screenFlash.Parent = gui
	else
		screenFlash.Visible = false
		screenFlash.Active = false
		screenFlash.ZIndex = 25
	end
	self.FlashFrame = screenFlash

	function self:Flash(color: Color3?, transparency: number?, duration: number?)
		if self.ActiveFlashTween then
			self.ActiveFlashTween:Cancel()
			self.ActiveFlashTween = nil
		end
		self.FlashFrame.Visible = true
		self.FlashFrame.BackgroundColor3 = color or Color3.fromRGB(220, 20, 20)
		self.FlashFrame.BackgroundTransparency = transparency or 0.65

		self.ActiveFlashTween = TweenService:Create(self.FlashFrame, TweenInfo.new(duration or 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		self.ActiveFlashTween:Play()
		self.ActiveFlashTween.Completed:Once(function()
			if self.FlashFrame.BackgroundTransparency >= 0.99 then
				self.FlashFrame.Visible = false
			end
		end)
	end

	function self:StopShake()
		if self.ShakeConn then
			self.ShakeConn:Disconnect()
			self.ShakeConn = nil
		end
	end

	function self:ShakeCamera(intensity: number, duration: number, isRoundActive: (() -> boolean)?)
		self:StopShake()
		local cam = Workspace.CurrentCamera
		if not cam then return end

		local startTime = os.clock()
		self.ShakeConn = RunService.RenderStepped:Connect(function()
			local elapsed = os.clock() - startTime
			if elapsed > duration or (isRoundActive and not isRoundActive()) then
				self:StopShake()
				return
			end
			local factor = (1 - (elapsed / duration)) * intensity
			local shakeX = (math.random() - 0.5) * factor * 0.8
			local shakeY = (math.random() - 0.5) * factor * 0.8
			local shakeZ = (math.random() - 0.5) * factor * 0.4
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(shakeX), math.rad(shakeY), math.rad(shakeZ))
		end)
	end

	function self:BindCharacterHealth(char: Model, isRoundActive: () -> boolean)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if not hum then return end
		self.LastRecordedHealth = hum.Health

		hum.HealthChanged:Connect(function(newHealth)
			if newHealth < self.LastRecordedHealth and newHealth > 0 and isRoundActive() then
				self:Flash(Color3.fromRGB(220, 20, 20), 0.65, 0.24)
			end
			self.LastRecordedHealth = newHealth
		end)
	end

	return self
end

return ScreenEffectsView
