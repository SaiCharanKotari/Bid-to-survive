--!strict
-- src/client/ui/components/ControlsDockView.luau
-- Manages the middle-left controls dock: Settings gear button and AFK toggle button.

local GuiService = game:GetService("GuiService")

local ControlsDockView = {}
ControlsDockView.__index = ControlsDockView

export type ControlsDock = {
	DockFrame: Frame,
	SettingsButton: ImageButton,
	AFKButton: TextButton,
	IsAFK: boolean,
	SetAFK: (self: ControlsDock, isAFK: boolean) -> (),
	GetAFK: (self: ControlsDock) -> boolean,
	SetVisible: (self: ControlsDock, visible: boolean) -> (),
}

function ControlsDockView.new(gui: ScreenGui, setAFKRemote: RemoteEvent?): ControlsDock
	local self = setmetatable({}, ControlsDockView) :: any
	self.IsAFK = false

	-- Clean up legacy root-level buttons to avoid duplicate instances
	local legacySettings = gui:FindFirstChild("SettingsButton")
	if legacySettings and legacySettings.Parent == gui then
		legacySettings:Destroy()
	end
	local legacyAFK = gui:FindFirstChild("AFKButton")
	if legacyAFK and legacyAFK.Parent == gui then
		legacyAFK:Destroy()
	end

	-- Root LeftControlsDock frame
	local leftControlsDock = gui:FindFirstChild("LeftControlsDock") :: Frame?
	if not leftControlsDock then
		leftControlsDock = Instance.new("Frame")
		leftControlsDock.Name = "LeftControlsDock"
		leftControlsDock.AnchorPoint = Vector2.new(0, 0.5)
		leftControlsDock.Position = UDim2.new(0, 24, 0.5, 0)
		leftControlsDock.Size = UDim2.new(0, 134, 0, 84)
		leftControlsDock.BackgroundTransparency = 1
		leftControlsDock.ZIndex = 20
		leftControlsDock.Parent = gui
	end
	self.DockFrame = leftControlsDock

	-- 1. Settings gear button
	local settingsButton = leftControlsDock:FindFirstChild("SettingsButton") :: ImageButton?
	if not settingsButton then
		settingsButton = Instance.new("ImageButton")
		settingsButton.Name = "SettingsButton"
		settingsButton.AnchorPoint = Vector2.new(0, 0)
		settingsButton.Position = UDim2.new(0, 0, 0, 0)
		settingsButton.Size = UDim2.new(0, 36, 0, 36)
		settingsButton.BackgroundTransparency = 1
		settingsButton.Image = "rbxassetid://6031280882"
		settingsButton.ImageColor3 = Color3.fromRGB(240, 240, 240)
		settingsButton.ZIndex = 21
		settingsButton.Parent = leftControlsDock
	end
	self.SettingsButton = settingsButton

	settingsButton.MouseButton1Click:Connect(function()
		pcall(function()
			GuiService:SetMenuIsOpen(true)
		end)
	end)

	-- 2. AFK toggle button
	local afkButton = leftControlsDock:FindFirstChild("AFKButton") :: TextButton?
	if not afkButton then
		afkButton = Instance.new("TextButton")
		afkButton.Name = "AFKButton"
		afkButton.AnchorPoint = Vector2.new(0, 0)
		afkButton.Position = UDim2.new(0, 0, 0, 44)
		afkButton.Size = UDim2.new(0, 130, 0, 34)
		afkButton.Font = Enum.Font.GothamBold
		afkButton.TextSize = 14
		afkButton.TextColor3 = Color3.fromRGB(0, 0, 0)
		afkButton.ZIndex = 21
		afkButton.AutoButtonColor = false

		local afkCorner = Instance.new("UICorner")
		afkCorner.CornerRadius = UDim.new(0, 4)
		afkCorner.Parent = afkButton

		local afkStroke = Instance.new("UIStroke")
		afkStroke.Thickness = 2
		afkStroke.Color = Color3.fromRGB(0, 0, 0)
		afkStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		afkStroke.Parent = afkButton

		afkButton.Parent = leftControlsDock
	end
	self.AFKButton = afkButton

	local function updateAFKVisual()
		if self.IsAFK then
			afkButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Yellow when ON
			afkButton.Text = "AFK: ON"
		else
			afkButton.BackgroundColor3 = Color3.fromRGB(0, 200, 80) -- Clean green when OFF
			afkButton.Text = "AFK: OFF"
		end
	end

	updateAFKVisual()

	afkButton.MouseButton1Click:Connect(function()
		self.IsAFK = not self.IsAFK
		updateAFKVisual()
		if setAFKRemote then
			setAFKRemote:FireServer(self.IsAFK)
		end
	end)

	function self:SetAFK(isAFK: boolean)
		self.IsAFK = isAFK
		updateAFKVisual()
	end

	function self:GetAFK(): boolean
		return self.IsAFK
	end

	function self:SetVisible(visible: boolean)
		self.DockFrame.Visible = visible
	end

	return self
end

return ControlsDockView
