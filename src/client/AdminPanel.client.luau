-- AdminPanel.client.luau
-- Standalone developer panel (its own ScreenGui / LocalScript so it never
-- competes for register space with the main HUD script).
-- Visible only to the developer; fires Remotes.AdminCmd straight to the server.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local player  = Players.LocalPlayer

-- Only the developer (or anyone in Studio testing) gets the panel
local ADMIN = "notoriusgb"
if not (RunService:IsStudio() or player.Name:lower() == ADMIN:lower()) then
	return
end

local pg = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name           = "AdminPanelGui"
screen.ResetOnSpawn   = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder   = 50
screen.Parent         = pg

-- Toggle button (left edge)
local toggle = Instance.new("TextButton")
toggle.Name = "AdminToggle"
toggle.Size = UDim2.fromOffset(44, 44)
toggle.Position = UDim2.new(0, 14, 0.5, 110)
toggle.AnchorPoint = Vector2.new(0, 0.5)
toggle.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
toggle.Text = "🛠"
toggle.TextSize = 22
toggle.AutoButtonColor = true
toggle.Parent = screen
local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 11); tc.Parent = toggle
local tstr = Instance.new("UIStroke"); tstr.Color = Color3.fromRGB(140, 100, 235); tstr.Thickness = 2; tstr.Parent = toggle

-- Panel
local panel = Instance.new("Frame")
panel.Name = "AdminPanel"
panel.Size = UDim2.fromOffset(252, 438)
panel.Position = UDim2.new(0, 64, 0.5, 0)
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(18, 16, 30)
panel.BackgroundTransparency = 0.04
panel.Visible = false
panel.Parent = screen
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
local pstr = Instance.new("UIStroke"); pstr.Color = Color3.fromRGB(140, 100, 235); pstr.Thickness = 2; pstr.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.Position = UDim2.new(0, 0, 0, 6)
title.BackgroundTransparency = 1
title.Text = "🛠  ADMIN  (RightShift)"
title.TextColor3 = Color3.fromRGB(205, 175, 255)
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.Parent = panel

local BUTTONS = {
	{ "🎁  Give All Pets",     Color3.fromRGB( 50,150, 70), "/give all"      },
	{ "✨  Give All Shiny",    Color3.fromRGB(165,120, 35), "/give shiny"    },
	{ "💰  +1,000,000 Coins",  Color3.fromRGB( 35,115,185), "/coins 1000000" },
	{ "⬆  Max-Level All Pets", Color3.fromRGB(120, 55,185), "/maxlevel"      },
	{ "🍀  Luck ×100",         Color3.fromRGB( 35,160, 95), "/luck 100"      },
	{ "🔄  Set 10 Rebirths",   Color3.fromRGB(185, 95, 40), "/rebirth 10"    },
	{ "♻️  Toggle Auto-Roll",  Color3.fromRGB( 60,120,160), "/autoroll"      },
	{ "🗑  Clear Inventory",   Color3.fromRGB(160, 50, 50), "/clear"         },
}

for i, def in ipairs(BUTTONS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -20, 0, 36)
	b.Position = UDim2.new(0, 10, 0, 40 + (i - 1) * 42)
	b.BackgroundColor3 = def[2]
	b.Text = def[1]
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.AutoButtonColor = true
	b.Parent = panel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = b
	local cmd = def[3]
	b.MouseButton1Click:Connect(function()
		Remotes.AdminCmd:FireServer(cmd)
	end)
end

-- ── Flight (client-side) ────────────────────────────────────────────────────
-- WASD = move along camera, Space = up, LeftControl = down. Toggle = button or G.
local flyBtn = Instance.new("TextButton")
flyBtn.Size = UDim2.new(1, -20, 0, 36)
flyBtn.Position = UDim2.new(0, 10, 0, 40 + (#BUTTONS) * 42)
flyBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
flyBtn.Text = "✈️  Toggle Flight (G)"
flyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
flyBtn.Font = Enum.Font.GothamBold
flyBtn.TextSize = 14
flyBtn.AutoButtonColor = true
flyBtn.Parent = panel
local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 9); fc.Parent = flyBtn

local FLY_SPEED = 95
local flying = false
local flyConn = nil

local function stopFlight()
	flying = false
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hrp then local v = hrp:FindFirstChild("AdminFlyVel"); if v then v:Destroy() end end
		if hum then hum.PlatformStand = false end
	end
	flyBtn.Text = "✈️  Toggle Flight (G)"; flyBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
end

local function startFlight()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) then return end
	flying = true
	hum.PlatformStand = true
	local bv = Instance.new("BodyVelocity")
	bv.Name = "AdminFlyVel"
	bv.MaxForce = Vector3.new(1, 1, 1) * 1e6
	bv.P = 1.25e4
	bv.Velocity = Vector3.zero
	bv.Parent = hrp
	flyConn = RunService.RenderStepped:Connect(function()
		if not flying then return end
		local cam = workspace.CurrentCamera
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W)           then dir += cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S)           then dir -= cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D)           then dir += cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A)           then dir -= cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end
		if dir.Magnitude > 0 then dir = dir.Unit end
		bv.Velocity = dir * FLY_SPEED
	end)
	flyBtn.Text = "✈️  Flight: ON"; flyBtn.BackgroundColor3 = Color3.fromRGB(40, 155, 95)
end

local function toggleFlight()
	if flying then stopFlight() else startFlight() end
end

flyBtn.MouseButton1Click:Connect(toggleFlight)

player.CharacterAdded:Connect(function()
	flying = false
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	flyBtn.Text = "✈️  Toggle Flight (G)"; flyBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
end)

toggle.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		panel.Visible = not panel.Visible
	elseif input.KeyCode == Enum.KeyCode.G then
		toggleFlight()
	end
end)

print("[AdminPanel] Ready for " .. player.Name)

