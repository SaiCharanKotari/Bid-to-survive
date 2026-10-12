-- AnimationPlayer: Plays 'A powerful' animation on animation-maker
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local animObj = character:WaitForChild("A powerful")

local track = animator:LoadAnimation(animObj)
track.Priority = Enum.AnimationPriority.Action

-- Play initially
task.wait(1)
track:Play()

-- Replay periodically
track.Ended:Connect(function()
    task.wait(3)
    if track and character.Parent then
        track:Play()
    end
end)

-- ProximityPrompt for players to trigger on demand
local hrp = character:WaitForChild("HumanoidRootPart")
local prompt = hrp:FindFirstChild("PlayPrompt") or Instance.new("ProximityPrompt")
prompt.Name = "PlayPrompt"
prompt.ActionText = "Play Attack"
prompt.ObjectText = "A Powerful Animation"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 15
prompt.Parent = hrp

prompt.Triggered:Connect(function(player)
    if track.IsPlaying then
        track:Stop(0.1)
    end
    track:Play()
end)
