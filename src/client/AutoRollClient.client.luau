-- AutoRollClient.client.luau (LocalScript)
-- Self-contained AUTO-ROLL toggle button (own ScreenGui so it doesn't touch the
-- main HUD's locals). Sits just above the ROLL button.
--   • Don't own auto-roll  → button BUYS a timed burst with coins.
--   • Own it (gamepass or timed) → button TOGGLES auto-roll on/off.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Config   = require(Shared:WaitForChild("Config"))
local Remotes  = require(Shared:WaitForChild("Remotes"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Local mirror of the relevant stats (autoRollLeft counts down locally).
local st = { passAutoRoll = false, autoRollOn = false, autoRollLeft = 0, recv = tick() }

local gui = Instance.new("ScreenGui")
gui.Name = "AutoRollUI"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.DisplayOrder = 6; gui.Parent = playerGui

local btn = Instance.new("TextButton")
btn.Size           = UDim2.fromOffset(150, 32)
btn.AnchorPoint    = Vector2.new(0.5, 1)
btn.Position       = UDim2.new(0.5, 0, 1, -120)
btn.BackgroundColor3 = Color3.fromRGB(45, 120, 210)
btn.TextColor3     = Color3.new(1, 1, 1)
btn.Font           = Enum.Font.GothamBold
btn.TextSize       = 13
btn.BorderSizePixel = 0
btn.AutoButtonColor = true
btn.Text           = "🔁 AUTO ROLL"
btn.Parent         = gui
local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = btn
local s = Instance.new("UIStroke"); s.Color = Color3.new(1,1,1); s.Thickness = 1.5
s.Transparency = 0.55; s.Parent = btn

local function timeLeft()
	return math.max(0, (st.autoRollLeft or 0) - (tick() - (st.recv or tick())))
end

local function fmt(sec)
	sec = math.floor(sec + 0.5)
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function refresh()
	local left      = timeLeft()
	local available = st.passAutoRoll or left > 0
	if available then
		if st.autoRollOn then
			btn.BackgroundColor3 = Color3.fromRGB(45, 175, 80)
			btn.Text = st.passAutoRoll and "⏸  AUTO: ON" or ("⏸  AUTO: ON  " .. fmt(left))
		else
			btn.BackgroundColor3 = Color3.fromRGB(65, 70, 90)
			btn.Text = st.passAutoRoll and "▶  AUTO: OFF" or ("▶  AUTO: OFF  " .. fmt(left))
		end
	else
		btn.BackgroundColor3 = Color3.fromRGB(45, 120, 210)
		btn.Text = "🔁 AUTO  " .. Config.fmtNum(Config.AUTO_ROLL_COIN_COST)
	end
end

btn.MouseButton1Click:Connect(function()
	if st.passAutoRoll or timeLeft() > 0 then
		Remotes.ToggleAutoRoll:FireServer()
	else
		Remotes.BuyAutoRoll:FireServer()
	end
end)

Remotes.UpdateStats.OnClientEvent:Connect(function(snap)
	if type(snap) ~= "table" then return end
	st.passAutoRoll = snap.passAutoRoll == true
	st.autoRollOn   = snap.autoRollOn == true
	st.autoRollLeft = snap.autoRollLeft or 0
	st.recv         = tick()
	refresh()
end)

-- Tick the countdown / state display.
task.spawn(function()
	while true do
		refresh()
		task.wait(0.5)
	end
end)

