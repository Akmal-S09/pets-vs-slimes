Warning: truncated output (original token count: 40553)
Total output lines: 3614

-- RollClient.client.luau
-- Layout inspired by screenshot: top-right coin stack, left leaderboard+stat pills,
-- floating bottom buttons, right sidebar stack, Robux shop modal.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local MarketplaceService= game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Spin / roll SFX ──────────────────────────────────────────────────────────
-- Classic "spin the wheel" ratchet: a built-in tick that fires fast then slows
-- down over the spin. (rbxasset:// sounds ship with the client, always load.)
-- Services kept inside the function to avoid bloating the main-chunk local count.
local function playSpinTicks(duration)
	task.spawn(function()
		local SoundService = game:GetService("SoundService")
		local Debris       = game:GetService("Debris")
		-- A real "wheel slowing down" ratchet: the gap between ticks grows on a
		-- smooth ease-out curve (quadratic), so it starts as a fast even whirr
		-- and gradually spaces out — no random pitch, no clunky jumps.
		local MIN_GAP, MAX_GAP = 0.05, 0.34
		local t = 0
		while t < duration do
			local s = Instance.new("Sound")
			s.SoundId       = "rbxasset://sounds/button.wav"
			s.Volume        = 0.26
			s.PlaybackSpeed = 1.0
			s.Parent = SoundService; s:Play()
			Debris:AddItem(s, 1)

			local frac    = math.clamp(t / duration, 0, 1)   -- 0 → 1 over the spin
			local gap     = MIN_GAP + (frac * frac) * (MAX_GAP - MIN_GAP)
			task.wait(gap)
			t = t + gap
		end
		-- Satisfying final "ding" when the wheel lands.
		local ding = Instance.new("Sound")
		ding.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		ding.Volume  = 0.45; ding.PlaybackSpeed = 1.5
		ding.Parent  = SoundService; ding:Play()
		Debris:AddItem(ding, 2)
	end)
end

local PET_MAP = {}
for _, p in ipairs(Config.PETS) do PET_MAP[p.id] = p end

-- ─── Pet ID resolver (handles shiny/evolved prefixes) ────────────────────────
local function resolvePet(fullId)
	local stripped  = (fullId:gsub("#.*$", ""))   -- drop the unique "#uid" suffix
	local isShiny   = stripped:sub(1,6)   == "shiny:"
	local rest      = isShiny and stripped:sub(7) or stripped
	local isEvolved = rest:sub(1,8)     == "evolved:"
	local baseId    = isEvolved and rest:sub(9) or rest
	local base      = PET_MAP[baseId]
	if not base then return nil end
	local r = {
		id=fullId, baseId=baseId, isShiny=isShiny, isEvolved=isEvolved,
		name=base.name, rarity=base.rarity, label=base.label,
		labelColor=base.labelColor, color=base.color,
		goop=base.goop, sz=base.sz, ability=base.ability,
	}
	if isEvolved then
		local evo = Config.PET_EVOLUTIONS and Config.PET_EVOLUTIONS[baseId]
		if evo then r.name=evo.name; r.color=evo.color end
	end
	if isShiny then
		-- Keep the pet's real colour; the shiny look is a uniform golden sheen
		-- applied to the WHOLE model in buildPetModel (so it matches the normal
		-- version's shape/features instead of just gold-ing the body).
		r.name = "✨ "..r.name
	end
	return r
end

-- ─── Palette ──────────────────────────────────────────────────────────────────
-- One table instead of ~19 separate locals (keeps the main chunk under Luau's
-- 200-register limit). Referenced as C.GOLD, C.RED, etc.
local C = {
	BG=Color3.fromRGB(12,14,26),    PANEL=Color3.fromRGB(20,22,36),  PANHI=Color3.fromRGB(30,32,50),
	GOLD=Color3.fromRGB(255,200,55),AMBER=Color3.fromRGB(220,130,35),AMBER2=Color3.fromRGB(155,85,15),
	PURPLE=Color3.fromRGB(110,60,200), PURPLE2=Color3.fromRGB(65,28,140),
	RED=Color3.fromRGB(210,48,48),  RED2=Color3.fromRGB(140,22,22),
	BLUE=Color3.fromRGB(38,98,210), BLUE2=Color3.fromRGB(18,55,140),
	GREEN=Color3.fromRGB(42,175,68),GREEN2=Color3.fromRGB(18,105,35),
	ROBUXC=Color3.fromRGB(0,162,255), ROBUX2=Color3.fromRGB(0,90,175),
	WHITE=Color3.fromRGB(255,245,230), DIM=Color3.fromRGB(155,155,172), STROKE=Color3.fromRGB(255,210,90),
}

-- ─── State ────────────────────────────────────────────────────────────────────
local coins           = 0
local stats           = {}
local onCooldown      = false
local cooldownStart   = -999
local pendingPet = nil
local followers       = {}
local floatT          = 0
local leaderboardRows    = {}
local loadingDone        = false   -- loading screen flag
local pendingUnlockZone  = nil     -- current zone name shown on the HUD unlock button
local unlockedZoneNames  = {}      -- client-side mirror of unlocked zones
local dailyInfo          = {}      -- latest DailyData payload from server
local inventory          = {}      -- ordered list of owned creatureIds
local selectedInvIdx     = nil     -- which inventory slot is highlighted in backpack
local wheelSpinReady     = false
local dailyClaimReady    = false
local wheelSpinning      = false   -- lock during animation
local refreshBackpack           -- forward declare
local refreshUpgrades
local refreshIndex
local refreshRebirth
local refreshWheel
local refreshDaily
local refreshShop


-- ─── Root GUI ─────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "SlimeDiceHUD"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

-- ─── LOADING SCREEN ──────────────────────────────────────────────────────────
-- Separate ScreenGui with DisplayOrder=10 so it sits on top of the HUD.
-- Uses CanvasGroup so a single GroupTransparency tween fades everything.
do
	local loadGui = Instance.new("ScreenGui")
	loadGui.Name           = "SlimeDiceLoading"
	loadGui.ResetOnSpawn   = false
	loadGui.IgnoreGuiInset = true
	loadGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	loadGui.DisplayOrder   = 10
	loadGui.Parent         = playerGui

	local canvas = Instance.new("CanvasGroup")
	canvas.Size                 = UDim2.new(1,0,1,0)
	canvas.BackgroundTransparency = 1
	canvas.ZIndex               = 1
	canvas.Parent               = loadGui

	-- Dark gradient background
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1,0,1,0)
	bg.BackgroundColor3 = Color3.fromRGB(8,10,20)
	bg.BorderSizePixel  = 0
	bg.ZIndex           = 1
	bg.Parent           = canvas
	do
		local g = Instance.new("UIGradient"); g.Rotation = 135
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(18, 8, 35)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB( 8,10, 20)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB( 5,14, 30)),
		}); g.Parent = bg
	end

	-- Soft glow ring
	local glow = Instance.new("Frame")
	glow.Size             = UDim2.fromOffset(200,200)
	glow.AnchorPoint      = Vector2.new(0.5,0.5)
	glow.Position         = UDim2.new(0.5,0, 0.37,0)
	glow.BackgroundColor3 = Color3.fromRGB(110,60,200)
	glow.BackgroundTransparency = 0.62
	glow.BorderSizePixel  = 0
	glow.ZIndex           = 2
	glow.Parent           = canvas
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = glow
		local g = Instance.new("UIGradient"); g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}); g.Parent = glow
	end

	-- Bouncing dice label
	local dice = Instance.new("TextLabel")
	dice.Size               = UDim2.fromOffset(110,110)
	dice.AnchorPoint        = Vector2.new(0.5,0.5)
	dice.Position           = UDim2.new(0.5,0, 0.37,0)
	dice.BackgroundTransparency = 1
	dice.Text               = "🎲"
	dice.TextSize            = 76
	dice.ZIndex             = 3
	dice.Parent             = canvas
	do
		local ok = pcall(function()
			dice.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
		end)
		if not ok then dice.Font = Enum.Font.Gotham end
	end
	-- Bounce loop
	task.spawn(function()
		while canvas.Parent do
			TweenService:Create(dice, TweenInfo.new(0.52,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
				{Position=UDim2.new(0.5,0,0.37,-22)}):Play()
			task.wait(0.55)
			TweenService:Create(dice, TweenInfo.new(0.42,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
				{Position=UDim2.new(0.5,0,0.37,0)}):Play()
			task.wait(0.48)
		end
	end)

	-- Title
	local title = Instance.new("TextLabel")
	title.Size               = UDim2.fromOffset(560,68)
	title.AnchorPoint        = Vector2.new(0.5,0)
	title.Position           = UDim2.new(0.5,0, 0.52,0)
	title.BackgroundTransparency = 1
	title.Text               = "PETS VS SLIMES"
	title.TextColor3         = Color3.fromRGB(255,200,55)
	title.TextSize            = 44
	title.TextStrokeTransparency = 0.55
	title.ZIndex             = 3
	title.Parent             = canvas
	do
		local ok = pcall(function()
			title.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
		end)
		if not ok then title.Font = Enum.Font.GothamBlack end
	end

	-- Subtitle
	local sub = Instance.new("TextLabel")
	sub.Size               = UDim2.fromOffset(360,26)
	sub.AnchorPoint        = Vector2.new(0.5,0)
	sub.Position           = UDim2.new(0.5,0, 0.625,0)
	sub.BackgroundTransparency = 1
	sub.Text               = "[ RELEASE ]  •  Rolling the world…"
	sub.TextColor3         = Color3.fromRGB(155,155,172)
	sub.TextSize            = 15
	sub.ZIndex             = 3
	sub.Parent             = canvas
	do
		local ok = pcall(function()
			sub.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
		end)
		if not ok then sub.Font = Enum.Font.Gotham end
	end

	-- Progress bar
	local barBg = Instance.new("Frame")
	barBg.Size             = UDim2.fromOffset(260,6)
	barBg.AnchorPoint      = Vector2.new(0.5,0)
	barBg.Position         = UDim2.new(0.5,0, 0.695,0)
	barBg.BackgroundColor3 = Color3.fromRGB(22,25,42)
	barBg.BorderSizePixel  = 0
	barBg.ZIndex           = 3
	barBg.Parent           = canvas
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,3); c.Parent=barBg end

	local barFill = Instance.new("Frame")
	barFill.Size             = UDim2.new(0,0,1,0)
	barFill.BackgroundColor3 = Color3.fromRGB(110,60,200)
	barFill.BorderSizePixel  = 0
	barFill.ZIndex           = 4
	barFill.Parent           = barBg
	do
		local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,3); c.Parent=barFill
		local g=Instance.new("UIGradient"); g.Rotation=0
		g.Color=ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(110,60,200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180,100,255)),
		}); g.Parent=barFill
	end
	-- Auto-fill to 85% over 3 s
	TweenService:Create(barFill,
		TweenInfo.new(3.0,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),
		{Size=UDim2.new(0.85,0,1,0)}):Play()

	-- Version tag
	local ver = Instance.new("TextLabel")
	ver.Size               = UDim2.fromOffset(280,18)
	ver.AnchorPoint        = Vector2.new(0.5,1)
	ver.Position           = UDim2.new(0.5,0, 1,-14)
	ver.BackgroundTransparency = 1
	ver.Text               = "Pets vs Slimes  •  v1.0"
	ver.TextColor3         = Color3.fromRGB(55,55,75)
	ver.TextSize            = 11
	ver.ZIndex             = 3
	ver.Parent             = canvas
	do
		local ok = pcall(function()
			ver.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
		end)
		if not ok then ver.Font = Enum.Font.Gotham end
	end

	-- Dismiss function (called when stats arrive, or after 7s max)
	local function dismissLoading()
		if loadingDone then return end
		loadingDone = true
		-- Snap bar to full, then fade
		TweenService:Create(barFill, TweenInfo.new(0.18), {Size=UDim2.new(1,0,1,0)}):Play()
		task.delay(0.22, function()
			TweenService:Create(canvas,
				TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{GroupTransparency=1}):Play()
			task.delay(0.72, function()
				if loadGui and loadGui.Parent then loadGui:Destroy() end
			end)
		end)
	end

	-- Expose dismissLoading to the outer scope via upvalue trick
	-- (we store it so UpdateStats can call it)
	_G.__slimeDiceLoadingDismiss = dismissLoading

	-- Safety: auto-dismiss after 7 seconds
	task.delay(7, dismissLoading)
end

-- ─── Font helper ─────────────────────────────────────────────────────────────
local function setFont(lbl, weight)
	weight = weight or Enum.FontWeight.Bold
	local ok = pcall(function()
		lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", weight)
	end)
	if not ok then
		lbl.Font = weight == Enum.FontWeight.Heavy and Enum.Font.GothamBlack
			or weight == Enum.FontWeight.Bold  and Enum.Font.GothamBold
			or Enum.Font.Gotham
	end
end

-- ─── UI primitives ───────────────────────────────────────────────────────────
local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 12); c.Parent=p; return c end
local function stroke(p, col, thick, tr)
	local s=Instance.new("UIStroke"); s.Color=col or C.STROKE; s.Thickness=thick or 1.5
	s.Transparency=tr or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=p; return s
end
local function grad(p, rot, cols, trs)
	local g=Instance.new("UIGradient"); g.Rotation=rot or 90
	if cols then g.Color=cols end; if trs then g.Transparency=trs end
	g.Parent=p; return g
end
local function mkF(parent, size, pos, bg, tr, z, anch)
	local f=Instance.new("Frame"); f.Size=size; f.Position=pos
	f.BackgroundColor3=bg or C.BG; f.BackgroundTransparency=tr or 0
	f.BorderSizePixel=0
	if z    then f.ZIndex=z end
	if anch then f.AnchorPoint=anch end
	f.Parent=parent; return f
end
local function mkL(parent, txt, sz, col, z, xa, ya, wrp)
	local l=Instance.new("TextLabel"); l.BackgroundTransparency=1
	l.Size=UDim2.new(1,0,1,0); l.Text=txt; l.TextColor3=col or C.WHITE; l.TextSize=sz or 16
	l.TextXAlignment=xa or Enum.TextXAlignment.Center
	l.TextYAlignment=ya or Enum.TextYAlignment.Center
	if wrp  then l.TextWrapped=true end
	if z    then l.ZIndex=z end
	setFont(l, Enum.FontWeight.Bold); l.Parent=parent; return l
end
local function mkB(parent, txt, sz, bg, col, z, size, pos, anch)
	local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.BorderSizePixel=0
	b.Size=size or UDim2.new(1,0,1,0)
	if pos  then b.Position=pos end
	if anch then b.AnchorPoint=anch end
	b.BackgroundColor3=bg or C.GREEN; b.Text=txt; b.TextColor3=col or C.WHITE; b.TextSize=sz or 18
	if z then b.ZIndex=z end
	setFont(b, Enum.FontWeight.Bold); b.Parent=parent; return b
end
local function hover(b, n, h)
	b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(0.12,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundColor3=h}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(0.18,Enum.EasingStyle.Quint,Enum.EasingDirection.In),{BackgroundColor3=n}):Play() end)
end

-- Bevel gradient on a button (top brighter → bottom darker)
local function bevel(b, col)
	grad(b, 90,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, col:Lerp(C.WHITE, 0.28)),
			ColorSequenceKeypoint.new(0.45, col),
			ColorSequenceKeypoint.new(1, col:Lerp(Color3.new(0,0,0), 0.32)),
		}), nil)
end

-- Notification badge (top-right corner of a button)
local function mkBadge(parent, z)
	local bg = mkF(parent, UDim2.fromOffset(22,22), UDim2.new(1,2,0,-6),
		Color3.fromRGB(215,45,45), 0, z or 20, Vector2.new(1,0))
	corner(bg, 11)
	local lbl = mkL(bg, "0", 12, C.WHITE, (z or 20)+1)
	setFont(lbl, Enum.FontWeight.Heavy)
	bg.Visible = false
	return bg, lbl
end

-- Float text rising from top-left
local function floatText(txt, col)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromOffset(210,38); lbl.AnchorPoint=Vector2.new(0,1)
	lbl.Position=UDim2.new(0,16,0,90)
	lbl.BackgroundTransparency=1; lbl.Text=txt
	lbl.TextColor3=col or C.GOLD; lbl.TextSize=26
	lbl.TextStrokeTransparency=0.25; lbl.ZIndex=80
	setFont(lbl, Enum.FontWeight.Heavy); lbl.Parent=gui
	TweenService:Create(lbl, TweenInfo.new(1.5,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{
		Position=UDim2.new(0,16,0,20), TextTransparency=1, TextStrokeTransparency=1
	}):Play()
	task.delay(1.6, function() lbl:Destroy() end)
end

-- ─── TOP-RIGHT COIN STACK ────────────────────────────────────────────────────
-- Goop counter
local goopPill = mkF(gui, UDim2.fromOffset(210,50), UDim2.new(1,-10,0,10), C.BG, 0.05,
	10, Vector2.new(1,0))
corner(goopPill, 14)
stroke(goopPill, C.STROKE, 1.8, 0.15)
grad(goopPill, 130,
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255,210,70)),
		ColorSequenceKeypoint.new(0.3, C.BG),
		ColorSequenceKeypoint.new(1, C.BG),
	}),
	NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.3, 0.94),
		NumberSequenceKeypoint.new(1, 0.94),
	})
)
-- Custom gold coin disc (replaces broken 🪙 emoji)
local gIconBg = mkF(goopPill, UDim2.fromOffset(38,38), UDim2.new(0,7,0.5,-19),
	Color3.fromRGB(190,135,8), 0, 11)
corner(gIconBg, 19)
grad(gIconBg, 135, ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255,224,55)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(168,110,8)),
}), nil)
do
	local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(255,210,40)
	s.Thickness=1.5; s.Transparency=0.35; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=gIconBg
end
do
	local inner = mkF(gIconBg, UDim2.fromOffset(22,22), UDim2.new(0.5,-11,0.5,-11),
		Color3.fromRGB(130,85,5), 0, 12); corner(inner, 11)
	local lbl = mkL(inner, "C", 13, Color3.fromRGB(255,215,55), 13)
	setFont(lbl, Enum.FontWeight.Heavy)
end
local goopLabel = Instance.new("TextLabel")
goopLabel.Size=UDim2.new(1,-58,0,28); goopLabel.Position=UDim2.new(0,52,0,6)
goopLabel.BackgroundTransparency=1; goopLabel.Text="0"; goopLabel.TextColor3=C.GOLD
goopLabel.TextSize=22; goopLabel.TextXAlignment=Enum.TextXAlignment.Left; goopLabel.ZIndex=11
setFont(goopLabel, Enum.FontWeight.Heavy); goopLabel.Parent=goopPill
local goopSub = Instance.new("TextLabel")
goopSub.Size=UDim2.new(1,-58,0,16); goopSub.Position=UDim2.new(0,52,0,33)
goopSub.BackgroundTransparency=1; goopSub.Text="Coins"; goopSub.TextColor3=Color3.fromRGB(185,145,45)
goopSub.TextSize=11; goopSub.TextXAlignment=Enum.TextXAlignment.Left; goopSub.ZIndex=11
setFont(goopSub, Enum.FontWeight.Regular); goopSub.Parent=goopPill
-- Plus button (shortcut to shop)
local goopPlus = mkB(goopPill, "+", 18, C.GREEN, C.WHITE, 12, UDim2.fromOffset(28,28),
	UDim2.new(1,-34,0.5,-14))
corner(goopPlus, 8)
hover(goopPlus, C.GREEN, Color3.fromRGB(70,210,100))

-- Rebirth/gem counter
local gemPill = mkF(gui, UDim2.fromOffset(210,42), UDim2.new(1,-10,0,66), C.BG, 0.05,
	10, Vector2.new(1,0))
corner(gemPill, 12)
stroke(gemPill, C.PURPLE, 1.5, 0.35)
local gm2Bg = mkF(gemPill, UDim2.fromOffset(34,34), UDim2.new(0,6,0.5,-17), Color3.fromRGB(40,20,70), 0, 11)
corner(gm2Bg, 17)
mkL(gm2Bg, "♦", 19, Color3.fromRGB(180,100,255), 12)
local rebirthCountLbl = Instance.new("TextLabel")
rebirthCountLbl.Size=UDim2.new(1,-54,0,24); rebirthCountLbl.Position=UDim2.new(0,46,0,5)
rebirthCountLbl.BackgroundTransparency=1; rebirthCountLbl.Text="0"; rebirthCountLbl.TextColor3=Color3.fromRGB(200,140,255)
rebirthCountLbl.TextSize=20; rebirthCountLbl.TextXAlignment=Enum.TextXAlignment.Left; rebirthCountLbl.ZIndex=11
setFont(rebirthCountLbl, Enum.FontWeight.Heavy); rebirthCountLbl.Parent=gemPill
local rebSub = Instance.new("TextLabel")
rebSub.Size=UDim2.new(1,-54,0,14); rebSub.Position=UDim2.new(0,46,0,27)
rebSub.BackgroundTransparency=1; rebSub.Text="Rebirths"; rebSub.TextColor3=C.DIM
rebSub.TextSize=11; rebSub.TextXAlignment=Enum.TextXAlignment.Left; rebSub.ZIndex=11
setFont(rebSub, Enum.FontWeight.Regular); rebSub.Parent=gemPill
local gemPlus = mkB(gemPill, "+", 16, C.PURPLE, C.WHITE, 12, UDim2.fromOffset(24,24),
	UDim2.new(1,-30,0.5,-12))
corner(gemPlus, 7)
hover(gemPlus, C.PURPLE, Color3.fromRGB(145,90,240))

-- Zone unlock button
local zoneBtn = mkB(gui, "🔓  UNLOCK DESERT  —  500", 14,
	Color3.fromRGB(30,140,55), C.WHITE, 10,
	UDim2.fromOffset(210,34), UDim2.new(1,-10,0,114), Vector2.new(1,0))
corner(zoneBtn, 10)
bevel(zoneBtn, Color3.fromRGB(35,160,60))
hover(zoneBtn, Color3.fromRGB(35,160,60), Color3.fromRGB(55,200,85))
zoneBtn.MouseButton1Click:Connect(function()
	if pendingUnlockZone then
		Remotes.UnlockZone:FireServer(pendingUnlockZone)
	end
end)

-- Teleport to the furthest zone you've unlocked (left side, under the leaderboard)
local tpBtn = mkB(gui, "⤴  TELEPORT TO LATEST ZONE", 12,
	Color3.fromRGB(60,110,210), Color3.fromRGB(255,255,255), 10,
	UDim2.fromOffset(220,36), UDim2.new(0,10,0,220), Vector2.new(0,0))
corner(tpBtn, 10)
bevel(tpBtn, Color3.fromRGB(70,130,235))
hover(tpBtn, Color3.fromRGB(60,110,210), Color3.fromRGB(80,150,255))
setFont(tpBtn, Enum.FontWeight.Heavy)
tpBtn.TextStrokeTransparency = 0.4   -- crisp, bright text on the blue button
tpBtn.MouseButton1Click:Connect(function()
	Remotes.TeleportZone:FireServer()
end)

-- ─── LEFT LEADERBOARD ────────────────────────────────────────────────────────
local lbPanel = mkF(gui, UDim2.fromOffset(190,200), UDim2.new(0,10,0,10),
	Color3.fromRGB(8,10,20), 0.08, 10)
corner(lbPanel, 12)
stroke(lbPanel, Color3.fromRGB(55,60,90), 1.5, 0.35)

-- Header bar — solid dark with white title (reference style)
local lbHdr = mkF(lbPanel, UDim2.new(1,0,0,32), UDim2.new(0,0,0,0),
	Color3.fromRGB(12,14,28), 0, 11)
corner(lbHdr, 12)
do
	local hs = Instance.new("UIStroke"); hs.Color = C.GOLD; hs.Thickness = 0
	-- bottom separator line
	local sep = mkF(lbPanel, UDim2.new(1,-10,0,1), UDim2.new(0,5,0,31),
		Color3.fromRGB(50,55,85), 0, 12)
end
local lbTitle = mkL(lbHdr, "LEADERBOARD", 12, C.WHITE, 12)
setFont(lbTitle, Enum.FontWeight.Heavy)

-- Row frames (up to 6)
local lbRows = {}
for i = 1, 6 do
	local row = mkF(lbPanel, UDim2.new(1,-10,0,26),
		UDim2.new(0,5,0,32+(i-1)*27), Color3.fromRGB(0,0,0), 1, 11)
	-- Rank
	local rank = mkL(row, tostring(i)..".", 12, C.DIM, 12, Enum.TextXAlignment.Left)
	rank.Size=UDim2.fromOffset(22,26); rank.Position=UDim2.new(0,4,0,0)
	setFont(rank, Enum.FontWeight.Bold)
	-- Name
	local name = mkL(row, "---", 12, C.WHITE, 12, Enum.TextXAlignment.Left)
	name.Size=UDim2.new(1,-82,0,26); name.Position=UDim2.new(0,26,0,0)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	setFont(name, Enum.FontWeight.Bold)
	-- Score
	local score = mkL(row, "", 12, C.GOLD, 12, Enum.TextXAlignment.Right)
	score.Size=UDim2.fromOffset(52,26); score.AnchorPoint=Vector2.new(1,0)
	score.Position=UDim2.new(1,-2,0,0)
	setFont(score, Enum.FontWeight.Heavy)
	lbRows[i] = {row=row, rank=rank, name=name, score=score}
end
lbPanel.Size = UDim2.fromOffset(190, 36 + 6*27 + 6)

local function refreshLeaderboard()
	local localName = player.Name
	for i = 1, 6 do
		local data = leaderboardRows[i]
		local r    = lbRows[i]
		if data then
			r.row.BackgroundTransparency = 1
			r.name.Text  = data.name == localName and "you" or data.name
			r.score.Text = data.display
			if data.name == localName then
				r.name.TextColor3  = C.GOLD
				r.score.TextColor3 = C.GOLD
				r.rank.TextColor3  = C.GOLD
			else
				r.name.TextColor3  = C.WHITE
				r.score.TextColor3 = Color3.fromRGB(180,230,130)
				r.rank.TextColor3  = C.DIM
			end
		else
			r.name.Text = "---"; r.score.Text = ""
		end
	end
end

-- ─── LEFT STAT PILLS ─────────────────────────────────────────────────────────
local statPillData = {}   -- {pill, valLbl} refs for updating

local function mkStatPill(yFromBottom, icon, iconCol)
	local pill = mkF(gui, UDim2.fromOffset(155,34),
		UDim2.new(0,10,1,yFromBottom), C.BG, 0.06, 10, Vector2.new(0,1))
	corner(pill, 10)
	stroke(pill, iconCol, 1.2, 0.5)
	local iconBg = mkF(pill, UDim2.fromOffset(26,26), UDim2.new(0,4,0.5,-13),
		iconCol:Lerp(Color3.new(0,0,0),0.55), 0, 11)
	corner(iconBg, 13)
	mkL(iconBg, icon, 15, C.WHITE, 12)
	local valLbl = Instance.new("TextLabel")
	valLbl.Size=UDim2.new(1,-36,1,0); valLbl.Position=UDim2.new(0,34,0,0)
	valLbl.BackgroundTransparency=1; valLbl.Text="—"
	valLbl.TextColor3=C.WHITE; valLbl.TextSize=14
	valLbl.TextXAlignment=Enum.TextXAlignment.Left; valLbl.ZIndex=11
	setFont(valLbl, Enum.FontWeight.Bold); valLbl.Parent=pill
	return pill, valLbl
end

local _, incomeLbl  = mkStatPill(-110, "🟢", Color3.fromRGB( 50,190, 80))
local _, cdLblStat  = mkStatPill( -70, "🎲", Color3.fromRGB(110, 60,200))
local _, luckLbl    = mkStatPill( -30, "🍀", Color3.fromRGB( 50,180,100))

-- ─── MODAL SYSTEM ────────────────────────────────────────────────────────────
local dimOverlay = mkF(gui, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0),
	Color3.new(0,0,0), 0.52, 30)
dimOverlay.Visible = false

local activeModal = nil

local function closeModal()
	if activeModal then
		local m = activeModal
		TweenService:Create(m, TweenInfo.new(0.15,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{Size=UDim2.fromOffset(8,8)}):Play()
		task.delay(0.18, function() m.Visible=false; if activeModal==m then activeModal=nil end end)
	end
	dimOverlay.Visible = false
end

local function openModal(f)
	if activeModal and activeModal~=f then activeModal.Visible=false end
	activeModal=f; f.Size=UDim2.fromOffset(8,8); f.Visible=true; dimOverlay.Visible=true
	TweenService:Create(f, TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Size=f:GetAttribute("OpenSize") or UDim2.fromOffset(400,460)}):Play()
end

local function makeModal(w, h, accentCol)
	accentCol = accentCol or C.GOLD
	local f = mkF(gui, UDim2.fromOffset(8,8), UDim2.new(0.5,-w/2,0.5,-h/2), C.BG, 0.04, 40)
	f:SetAttribute("OpenSize", UDim2.fromOffset(w,h))
	f.Visible = false; corner(f,18); stroke(f, accentCol, 2, 0.4)
	-- Top accent bar
	local bar = mkF(f, UDim2.new(1,-4,0,3), UDim2.new(0,2,0,0), accentCol, 0, 42)
	corner(bar, 2)
	grad(bar, 0, ColorSequence.new({
		ColorSequenceKeypoint.new(0, accentCol:Lerp(C.WHITE,0.5)),
		ColorSequenceKeypoint.new(0.5, accentCol),
		ColorSequenceKeypoint.new(1, accentCol:Lerp(C.WHITE,0.5)),
	}), nil)
	-- X button
	local x = mkB(f, "✖", 14, Color3.fromRGB(55,28,28), Color3.fromRGB(210,130,130),
		50, UDim2.fromOffset(30,30), UDim2.new(1,-36,0,7))
	corner(x,8); hover(x, Color3.fromRGB(55,28,28), C.RED)
	x.MouseButton1Click:Connect(closeModal)
	return f
end

-- Modal header helper
local function modalHeader(parent, txt, col)
	local hdr = mkF(parent, UDim2.new(1,0,0,52), UDim2.new(0,0,0,0), C.BG, 0.15, 41)
	corner(hdr, 18)
	local t = mkL(hdr, txt, 20, C.WHITE, 42)
	setFont(t, Enum.FontWeight.Heavy)
	return hdr
end

-- Card template
local function mkCard(parent, yOff, h, accentCol)
	local c = mkF(parent, UDim2.new(1,-22,0,h), UDim2.new(0,11,0,yOff), C.PANHI, 0, 41)
	corner(c, 13)
	if accentCol then stroke(c, accentCol, 1.5, 0.55) end
	return c
end

-- ─── SCALABLE PET FACE ─────────────────────────────────────────────────────
-- Draws eyes + smile + species features as children of a coloured circle `circ`
-- of diameter S px. Used by backpack inventory tiles & equipped slots so the
-- pet designs show up everywhere (not just the roll cards / 3D models).
local FACE_PROFILE = {
	blob_slime     = { eye=0.18, mouth=0.30, my=0.55 },
	fire_pup       = { eye=0.20, mouth=0.24, my=0.55 },
	flame_fox      = { eye=0.19, mouth=0.20, my=0.57 },
	shadow_cat     = { eye=0.23, mouth=0.13, my=0.59 },
	frost_bunny    = { eye=0.22, mouth=0.13, my=0.59 },
	mini_dragon    = { eye=0.20, mouth=0.18, my=0.56 },   -- big cute eyes
	storm_hawk     = { eye=0.17, mouth=0.16, my=0.57 },
	crystal_phoenix= { eye=0.21, mouth=0.18, my=0.56 },
	chicken        = { eye=0.17, mouth=0.10, my=0.50 },
	emperor_snake= { eye=0.18, mouth=0.10, my=0.50 },
}

local function mkPetFace(circ, baseId, col, S, zBase)
	local INK = Color3.fromRGB(20,14,28)
	zBase = zBase or 43
	local zF, zE, zP, zS = zBase+1, zBase+2, zBase+3, zBase+4   -- feature / eye / pupil / shine
	local function P(f) return math.max(1, math.floor(f*S + 0.5)) end
	local ex = FACE_PROFILE[baseId] or { eye=0.19, mouth=0.22, my=0.57 }

	-- ── eyes (white, dark pupil, shine) ──
	local eyeD = P(ex.eye)
	local function eye(cx)
		local e = mkF(circ, UDim2.fromOffset(eyeD, eyeD), UDim2.new(cx, -eyeD/2, 0, P(0.30)), C.WHITE, 0, zE)
		corner(e, eyeD//2)
		local pd = math.max(2, math.floor(eyeD*0.56))
		local p  = mkF(e, UDim2.fromOffset(pd, pd), UDim2.new(0.5,-pd//2,0.5,-pd//2+1), INK, 0, zP)
		corner(p, pd//2)
		if eyeD >= 9 then
			local s = math.max(2, pd//3)
			local sh = mkF(p, UDim2.fromOffset(s,s), UDim2.new(0,1,0,1), C.WHITE, 0, zS); corner(sh,2)
		end
	end
	eye(0.30); eye(0.70)

	-- ── smile (bottom half of a circle = U) ──
	local mW = P(ex.mouth); local mH = math.max(2, math.floor(mW*0.5))
	local clip = Instance.new("Frame")
	clip.Size = UDim2.fromOffset(mW, mH); clip.AnchorPoint = Vector2.new(0.5,0)
	clip.Position = UDim2.new(0.5,0,0,P(ex.my)); clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true; clip.ZIndex = zE; clip.Parent = circ
	local arc = Instance.new("Frame"); arc.Size = UDim2.fromOffset(mW, mW)
	arc.Position = UDim2.new(0,0,0,-(mW-mH)); arc.BackgroundColor3 = INK
	arc.BorderSizePixel = 0; arc.ZIndex = zE; arc.Parent = clip
	local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1,0); ac.Parent = arc

	-- ── feature helper (rounded rects, can extend above the circle) ──
	local function feat(cx, yf, wf, hf, c, ang, z)
		local w, h = P(wf), P(hf)
		local f = mkF(circ, UDim2.fromOffset(w,h), UDim2.new(cx, -w/2, 0, math.floor(yf*S)), c, 0, z or zF)
		corner(f, math.max(2, math.min(w,h)//2))
		if ang then f.Rotation = ang end
		return f
	end
	local pink   = Color3.fromRGB(248,150,178)
	local dark   = col:Lerp(Color3.new(0,0,0), 0.25)
	local lite   = col:Lerp(C.WHITE, 0.4)

	if baseId == "shadow_cat" then
		feat(0.22,-0.04,0.26,0.34, col, -22); feat(0.78,-0.04,0.26,0.34, col, 22)
		feat(0.22, 0.00,0.13,0.20, Color3.fromRGB(190,110,245), -22)
		feat(0.78, 0.00,0.13,0.20, Color3.fromRGB(190,110,245),  22)
		feat(0.50, 0.49,0.11,0.08, Color3.fromRGB(245,140,165), nil, zP)
	elseif baseId == "frost_bunny" then
		feat(0.34,-0.30,0.17,0.52, col); feat(0.66,-0.30,0.17,0.52, col)
		feat(0.34,-0.24,0.09,0.40, Color3.fromRGB(248,205,228)); feat(0.66,-0.24,0.09,0.40, Color3.fromRGB(248,205,228))
		feat(0.16, 0.52,0.16,0.13, Color3.fromRGB(250,185,208), nil, zF); feat(0.84,0.52,0.16,0.13, Color3.fromRGB(250,185,208), nil, zF)
		feat(0.50, 0.49,0.09,0.07, pink, nil, zP)
	elseif baseId == "mini_dragon" then
		-- horns + little side wings (NO pig snout)
		feat(0.30,-0.10,0.13,0.26, Color3.fromRGB(244,205,150), -28); feat(0.70,-0.10,0.13,0.26, Color3.fromRGB(244,205,150), 28)
		feat(0.04, 0.28,0.20,0.30, dark, -18); feat(0.96,0.28,0.20,0.30, dark, 18)
	elseif baseId == "fire_pup" then
		feat(0.16,-0.05,0.24,0.24, col); feat(0.84,-0.05,0.24,0.24, col)
		feat(0.16,-0.01,0.15,0.15, dark); feat(0.84,-0.01,0.15,0.15, dark)
		feat(0.50, 0.50,0.09,0.07, Color3.fromRGB(40,22,16), nil, zP)
	elseif baseId == "flame_fox" then
		feat(0.14,-0.04,0.18,0.28, col, -22); feat(0.86,-0.04,0.18,0.28, col, 22)
		feat(0.14, 0.00,0.10,0.18, lite, -22); feat(0.86,0.00,0.10,0.18, lite, 22)
	elseif baseId == "storm_hawk" then
		feat(0.30,-0.04,0.24,0.12, col, -16); feat(0.70,-0.04,0.24,0.12, col, 16)
		feat(0.50, 0.46,0.13,0.11, Color3.fromRGB(255,200,40), 45, zP)  -- beak (diamond)
	elseif baseId == "crystal_phoenix" then
		local gem = feat(0.50,-0.10,0.16,0.18, Color3.fromRGB(255,95,215), nil, zF); corner(gem, P(0.04))
		feat(0.08, 0.12,0.18,0.12, lite, -20); feat(0.92,0.12,0.18,0.12, lite, 20)
	elseif baseId == "blob_slime" then
		feat(0.34,-0.16,0.07,0.20, col, -12); feat(0.66,-0.16,0.07,0.20, col, 12)
		feat(0.34,-0.20,0.11,0.10, col); feat(0.66,-0.20,0.11,0.10, col)
	elseif baseId == "chicken" then
		feat(0.42,-0.10,0.14,0.16, Color3.fromRGB(228,55,55))   -- red comb
		feat(0.56,-0.12,0.10,0.13, Color3.fromRGB(228,55,55))
		feat(0.50, 0.50,0.13,0.10, Color3.fromRGB(255,170,40), nil, zP)  -- beak
	elseif baseId == "emperor_snake" then
		feat(0.50,-0.16,0.40,0.10, Color3.fromRGB(255,212,60))  -- gold halo bar
		feat(0.06, 0.28,0.18,0.34, Color3.fromRGB(255,218,80), -18)  -- gold wings
		feat(0.94, 0.28,0.18,0.34, Color3.fromRGB(255,218,80),  18)
		feat(0.50, 0.50,0.11,0.09, Color3.fromRGB(255,175,45), nil, zP)  -- beak
	end
end

-- ─── BACKPACK MODAL ───────────────────────────────────────────────────────────
-- Top section: equipment slots.  Bottom section: inventory grid with Equip/Sell.
local backpackModal = makeModal(440, 580, C.GOLD)
backpackModal:SetAttribute("OpenSize", UDim2.fromOffset(440,580))

do
	modalHeader(backpackModal, "🎒  Backpack", C.GOLD)

	-- ── Auto-sell row (MULTI-SELECT — toggle any rarities to auto-sell) ──────────
	local asHdr = Instance.new("TextLabel")
	asHdr.Size=UDim2.new(1,-20,0,14); asHdr.Position=UDim2.new(0,10,0,56)
	asHdr.BackgroundTransparency=1; asHdr.Text="AUTO-SELL  (tap to toggle — highlighted = auto-selling)"
	asHdr.TextColor3=C.DIM; asHdr.TextSize=10; asHdr.TextXAlignment=Enum.TextXAlignment.Left
	asHdr.ZIndex=42; setFont(asHdr, Enum.FontWeight.Regular); asHdr.Parent=backpackModal

	-- One toggle per rarity (multi-select) + an "Off" clear-all
	local AS_OPTS = { "Off", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine" }
	local AS_COLS = {
		Off       = Color3.fromRGB(55,60,85),
		Common    = Color3.fromRGB(120,120,120),
		Uncommon  = Color3.fromRGB(40,170,90),
		Rare      = Color3.fromRGB(60,110,235),
		Epic      = Color3.fromRGB(150,60,235),
		Legendary = Color3.fromRGB(230,180,40),
		Mythic    = Color3.fromRGB(255,90,190),
		Divine    = Color3.fromRGB(255,225,90),
	}
	local asSel  = {}      -- current selection set
	local asBtns = {}
	local asBtnW = math.floor((440-22) / #AS_OPTS) - 2
	-- ON  = full bright colour + thick white glow border + bright text
	-- OFF = darkened, dim text, no border  → the difference is obvious
	local function refreshAsBtns()
		for opt, btn in pairs(asBtns) do
			local stk = btn:FindFirstChildOfClass("UIStroke")
			if opt == "Off" then
				btn.BackgroundColor3 = AS_COLS.Off
				btn.BackgroundTransparency = 0.15
				btn.TextColor3 = C.WHITE
				if stk then stk.Transparency = 1 end
			elseif asSel[opt] then
				btn.BackgroundColor3 = AS_COLS[opt]
				btn.BackgroundTransparency = 0
				btn.TextColor3 = C.WHITE
				if stk then stk.Transparency = 0 end
			else
				btn.BackgroundColor3 = AS_COLS[opt]:Lerp(Color3.new(0,0,0), 0.66)
				btn.BackgroundTransparency = 0.2
				btn.TextColor3 = Color3.fromRGB(150,156,178)
				if stk then stk.Transparency = 1 end
			end
		end
	end
	for i, opt in ipairs(AS_OPTS) do
		local bx = 10 + (i-1)*(asBtnW+2)
		local ab = mkB(backpackModal, opt:sub(1,4), 9, AS_COLS[opt], C.WHITE, 42,
			UDim2.fromOffset(asBtnW, 22), UDim2.new(0, bx, 0, 72))
		corner(ab, 6)
		do
			local stk = Instance.new("UIStroke")
			stk.Color = C.WHITE; stk.Thickness = 2; stk.Transparency = 1
			stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stk.Parent = ab
		end
		asBtns[opt] = ab
		ab.MouseButton1Click:Connect(function()
			if opt == "Off" then
				asSel = {}
			else
				asSel[opt] = (not asSel[opt]) or nil
			end
			Remotes.SetAutoSell:FireServer(asSel)
			refreshAsBtns()
		end)
	end
	-- expose so refreshBackpack can sync from server stats
	function syncAutoSell(set)
		asSel = {}
		if type(set)=="table" then for k,v in pairs(set) do if v then asSel[k]=true end end end
		refreshAsBtns()
	end
	refreshAsBtns()

	-- Evolve button (shown when selected inv item is level 10)
	local evolveBtn = mkB(backpackModal, "🌟 EVOLVE", 13, Color3.fromRGB(80,40,150), C.GOLD, 42,
		UDim2.fromOffset(110, 30), UDim2.new(1,-120, 0, 58))
	corner(evolveBtn, 9); bevel(evolveBtn, Color3.fromRGB(130,60,220))
	hover(evolveBtn, Color3.fromRGB(80,40,150), Color3.fromRGB(140,70,240))
	evolveBtn.Visible = false
	evolveBtn.MouseButton1Click:Connect(function()
		if selectedInvIdx then Remotes.EvolvePet:FireServer(selectedInvIdx) end
	end)

	-- ── Equipment section ────────────────────────────────────────────────────────
	local eqHdr = Instance.new("TextLabel")
	eqHdr.Size=UDim2.new(1,-20,0,16); eqHdr.Position=UDim2.new(0,10,0,100)
	eqHdr.BackgroundTransparency=1; eqHdr.Text="EQUIPPED"
	eqHdr.TextColor3=C.GOLD; eqHdr.TextSize=11
	eqHdr.TextXAlignment=Enum.TextXAlignment.Left; eqHdr.ZIndex=42
	setFont(eqHdr, Enum.FontWeight.Heavy); eqHdr.Parent=backpackModal

	-- Equipment slot frames (up to 5, rendered in a horizontal strip)
	local eqSlots  = {}   -- [i] = frame
	local EQ_Y     = 120
	local EQ_SZ    = 72
	local EQ_GAP   = 8
	for i = 1, 5 do
		local sx = 10 + (i-1)*(EQ_SZ+EQ_GAP)
		local sf = mkF(backpackModal, UDim2.fromOffset(EQ_SZ,EQ_SZ), UDim2.new(0,sx,0,EQ_Y),
			Color3.fromRGB(18,20,34), 0, 42)
		corner(sf, 12); stroke(sf, Color3.fromRGB(42,46,68), 1.5, 0.5)
		eqSlots[i] = sf
	end

	-- ── Divider ─────────────────────────────────────────────────────────────────
	local divY = EQ_Y + EQ_SZ + 8
	mkF(backpackModal, UDim2.new(1,-20,0,1), UDim2.new(0,10,0,divY), Color3.fromRGB(42,46,68), 0, 42)

	-- ── Inventory header ─────────────────────────────────────────────────────────
	local invHdrLbl = Instance.new("TextLabel")
	invHdrLbl.Size=UDim2.new(1,-20,0,16); invHdrLbl.Position=UDim2.new(0,10,0,divY+6)
	invHdrLbl.BackgroundTransparency=1; invHdrLbl.Text="INVENTORY  (0)"
	invHdrLbl.TextColor3=C.DIM; invHdrLbl.TextSize=11
	invHdrLbl.TextXAlignment=Enum.TextXAlignment.Left; invHdrLbl.ZIndex=42
	setFont(invHdrLbl, Enum.FontWeight.Heavy); invHdrLbl.Parent=backpackModal

	-- ── Inventory scroll grid ────────────────────────────────────────────────────
	local INV_Y      = divY + 26
	local ACTION_H   = 52
	local INV_H      = 580 - INV_Y - ACTION_H - 8

	local invScroll = Instance.new("ScrollingFrame")
	invScroll.Size=UDim2.new(1,-16,0,INV_H); invScroll.Position=UDim2.new(0,8,0,INV_Y)
	invScroll.BackgroundTransparency=1; invScroll.BorderSizePixel=0
	invScroll.ScrollBarThickness=4; invScroll.ScrollBarImageColor3=C.GOLD
	invScroll.ZIndex=41; invScroll.Parent=backpackModal

	-- ── Action bar (Equip + Sell, appears when inv item selected) ────────────────
	local actionBar = mkF(backpackModal,
		UDim2.new(1,-16,0,ACTION_H-4), UDim2.new(0,8,1,-(ACTION_H)),
		Color3.fromRGB(16,18,30), 0, 41)
	corner(actionBar, 12); stroke(actionBar, C.GOLD, 1.5, 0.5)
	actionBar.Visible = false

	local actNameLbl = mkL(actionBar, "Select a slime", 13, C.WHITE, 42)
	actNameLbl.Size=UDim2.new(1,-186,1,0); actNameLbl.Position=UDim2.new(0,10,0,0)
	actNameLbl.TextXAlignment=Enum.TextXAlignment.Left
	setFont(actNameLbl, Enum.FontWeight.Bold)

	local equipInvBtn = mkB(actionBar,"⚔️  Equip",13,C.GREEN,C.WHITE,43,
		UDim2.fromOffset(82,34), UDim2.new(1,-174,0.5,-17))
	corner(equipInvBtn,9); bevel(equipInvBtn,C.GREEN); hover(equipInvBtn,C.GREEN,Color3.fromRGB(70,220,100))

	local sellInvBtn = mkB(actionBar,"💰  Sell",13,C.AMBER,C.WHITE,43,
		UDim2.fromOffset(82,34), UDim2.new(1,-88,0.5,-17))
	corner(sellInvBtn,9); bevel(sellInvBtn,C.AMBER); hover(sellInvBtn,C.AMBER,Color3.fromRGB(255,170,60))

	-- ── Internal state ───────────────────────────────────────────────────────────
	local invCardFrames = {}   -- [i] = frame (rebuilt on refresh)

	local function clearSelection()
		selectedInvIdx = nil
		actionBar.Visible = false
		for _, f in ipairs(invCardFrames) do
			if f and f.Parent then
				TweenService:Create(f, TweenInfo.new(0.08), {BackgroundTransparency=0}):Play()
			end
		end
	end

	local function selectInvItem(idx, cData)
		selectedInvIdx = idx
		actionBar.Visible = true
		local baseId = cData.baseId or cData.id
		local fid  = inventory[idx]                       -- unique instance id
		local lvl  = (stats.petLevels or {})[fid] or 1
		local mult = 1 + (lvl-1)*Config.PET_LEVEL_BONUS
		local sell = math.floor(cData.goop * mult * 3)
		actNameLbl.Text    = cData.name .. "  Lv." .. lvl
		actNameLbl.TextColor3 = cData.labelColor
		sellInvBtn.Text    = "💰  Sell (" .. sell .. ")"
		-- Show evolve button if at max level and not already evolved
		local canEvolve = lvl >= Config.PET_MAX_LEVEL and not cData.isEvolved
			and Config.PET_EVOLUTIONS and Config.PET_EVOLUTIONS[baseId]
		evolveBtn.Visible = canEvolve and true or false
		for i, f in ipairs(invCardFrames) do
			if f and f.Parent then
				local t = (i == idx) and 0.18 or 0.6
				TweenService:Create(f, TweenInfo.new(0.08), {BackgroundTransparency=t}):Play()
			end
		end
	end

	equipInvBtn.MouseButton1Click:Connect(function()
		if not selectedInvIdx then return end
		local cId = inventory[selectedInvIdx]
		if cId then Remotes.EquipCreature:FireServer(cId) end
		clearSelection()
	end)

	sellInvBtn.MouseButton1Click:Connect(function()
		if not selectedInvIdx then return end
		Remotes.SellCreature:FireServer(selectedInvIdx)
		clearSelection()
	end)

	-- ── Equipment slot builder ───────────────────────────────────────────────────
	local function rebuildEqSlots()
		local maxSlots = stats.maxSlots or Config.MAX_EQUIPPED
		local equipped = stats.equipped or {}
		for i = 1, 5 do
			local sf = eqSlots[i]
			-- Clear old children except UICorner/UIStroke
			for _, ch in ipairs(sf:GetChildren()) do
				if not ch:IsA("UICorner") and not ch:IsA("UIStroke") then ch:Destroy() end
			end
			if i > maxSlots then
				sf.BackgroundColor3 = Color3.fromRGB(10,12,22)
				sf.BackgroundTransparency = 0.4
			else
				local cId   = equipped[i]
				local cData = cId and resolvePet(cId)
				sf.BackgroundColor3 = cData and cData.color:Lerp(Color3.new(0,0,0),0.55)
					or Color3.fromRGB(18,20,34)
				sf.BackgroundTransparency = 0

				-- Colored inner circle
				if cData then
					local circ = mkF(sf, UDim2.fromOffset(44,44), UDim2.new(0.5,-22,0,4), cData.color, 0, 43)
						mkPetFace(circ, cData.baseId or cData.id, cData.color, 44)
					corner(circ,9)
					grad(circ,135,ColorSequence.new({
						ColorSequenceKeypoint.new(0,cData.color:Lerp(C.WHITE,0.4)),
						ColorSequenceKeypoint.new(1,cData.color:Lerp(Color3.new(0,0,0),0.38)),
					}),nil)
				end
				-- Slot label / name
				local txt = Instance.new("TextLabel")
				txt.Size=UDim2.new(1,-2,0,14); txt.AnchorPoint=Vector2.new(0.5,1)
				txt.Position=UDim2.new(0.5,0,1,-2); txt.BackgroundTransparency=1
				txt.Text = cData and cData.name or ("Slot "..i)
				txt.TextColor3 = cData and cData.labelColor or Color3.fromRGB(55,60,85)
				txt.TextSize=8; txt.TextTruncate=Enum.TextTruncate.AtEnd; txt.ZIndex=43
				setFont(txt, Enum.FontWeight.Bold); txt.Parent=sf

				-- Click = unequip
				if cData then
					local si=i
					local ub = Instance.new("TextButton"); ub.Size=UDim2.new(1,0,1,0)
					ub.BackgroundTransparency=1; ub.Text=""; ub.ZIndex=44; ub.Parent=sf
					ub.MouseButton1Click:Connect(function() Remotes.UnequipCreature:FireServer(si) end)
				end

				-- Locked overlay
				if i > maxSlots then
					local lock = mkL(sf,"🔒",18,C.DIM,44); lock.Size=UDim2.new(1,0,1,0)
				end
			end
		end
	end

	-- ── Inventory grid builder ───────────────────────────────────────────────────
	local COLS   = 4
	local TILE_W = 96
	local TILE_H = 88
	local TILE_G = 6

	function refreshBackpack()
		clearSelection()
		if syncAutoSell then syncAutoSell(stats.autoSellSet) end
		for _, f in ipairs(invCardFrames) do if f then f:Destroy() end end
		invCardFrames = {}

		rebuildEqSlots()

		invHdrLbl.Text = "INVENTORY  (" .. #inventory .. " / 60)"

		local rows = math.ceil(math.max(#inventory,1) / COLS)
		invScroll.CanvasSize = UDim2.fromOffset(0, rows*(TILE_H+TILE_G)+TILE_G+4)

		for idx, cId in ipairs(inventory) do
			local cData = resolvePet(cId)
			if not cData then continue end

			local col = (idx-1) % COLS
			local row = math.floor((idx-1) / COLS)
			local tx  = TILE_G + col*(TILE_W+TILE_G)
			local ty  = TILE_G + row*(TILE_H+TILE_G)

			local tile = mkF(invScroll, UDim2.fromOffset(TILE_W,TILE_H),
				UDim2.new(0,tx,0,ty),
				cData.color:Lerp(Color3.new(0,0,0),0.52), 0, 42)
			corner(tile,12); stroke(tile, cData.labelColor, 1.5, 0.45)
			grad(tile,135,ColorSequence.new({
				ColorSequenceKeypoint.new(0,cData.color:Lerp(C.WHITE,0.12)),
				ColorSequenceKeypoint.new(1,cData.color:Lerp(Color3.new(0,0,0),0.48)),
			}),nil)
			invCardFrames[idx] = tile

			-- Colored circle
			local circ = mkF(tile, UDim2.fromOffset(52,52), UDim2.new(0.5,-26,0,4), cData.color, 0, 43)
				mkPetFace(circ, cData.baseId or cData.id, cData.color, 52)
			corner(circ,11)
			grad(circ,135,ColorSequence.new({
				ColorSequenceKeypoint.new(0,cData.color:Lerp(C.WHITE,0.45)),
				ColorSequenceKeypoint.new(1,cData.color:Lerp(Color3.new(0,0,0),0.38)),
			}),nil)

			-- Level badge (keyed by this pet's UNIQUE instance id → per-pet level)
			local lvl = (stats.petLevels or {})[cId] or 1
			local lvlBadge = mkF(tile, UDim2.fromOffset(22,16), UDim2.new(1,-24,0,4),
				Color3.fromRGB(18,20,34), 0, 43); corner(lvlBadge,4)
			mkL(lvlBadge,"Lv"..lvl,8,C.GOLD,44); setFont(mkL(lvlBadge,"",0,C.WHITE,44), Enum.FontWeight.Heavy)

			-- Name
			local nl=mkL(tile,cData.name,9,C.WHITE,43)
			nl.Size=UDim2.new(1,-4,0,13); nl.Position=UDim2.new(0,2,0,56)
			nl.TextTruncate=Enum.TextTruncate.AtEnd; setFont(nl,Enum.FontWeight.Bold)

			-- Rarity
			local rl=mkL(tile,cData.label,8,cData.labelColor,43)
			rl.Size=UDim2.new(1,-4,0,11); rl.Position=UDim2.new(0,2,0,69)
			setFont(rl,Enum.FontWeight.Regular)

			-- XP bar (per individual pet; full gold bar when maxed)
			local pxp  = (stats.petXP or {})[cId] or 0
			local need = (lvl < Config.PET_MAX_LEVEL)
				and math.floor(Config.PET_XP_BASE * (Config.PET_XP_SCALE ^ (lvl - 1))) or 0
			local pct  = (need > 0) and math.clamp(pxp/need, 0, 1) or 1
			local xpBg = mkF(tile, UDim2.new(1,-8,0,5), UDim2.new(0,4,1,-8),
				Color3.fromRGB(12,14,24), 0, 43); corner(xpBg, 2)
			local xpFill = mkF(xpBg, UDim2.new(pct,0,1,0), UDim2.new(0,0,0,0),
				(lvl >= Config.PET_MAX_LEVEL) and C.GOLD or cData.color:Lerp(C.WHITE,0.25), 0, 44)
			corner(xpFill, 2)

			-- Click to select
			local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0)
			btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=44; btn.Parent=tile
			local ii=idx; local cd=cData
			btn.MouseButton1Click:Connect(function()
				if selectedInvIdx == ii then clearSelection()
				else selectInvItem(ii, cd) end
			end)
		end
	end
end

-- ─── UPGRADES MODAL ───────────────────────────────────────────────────────────
local upgradesModal = makeModal(430,372,C.GREEN)
upgradesModal:SetAttribute("OpenSize", UDim2.fromOffset(430,372))
upgradesModal.BackgroundTransparency = 0.55   -- show the world behind the upgrade tree

do
	modalHeader(upgradesModal, "⚡  Upgrades", C.GREEN)

	local UPG_COLS = { slots=C.ROBUXC, speed=C.AMBER, luck=C.GREEN,
		power=C.RED, greed=C.GOLD, fortune=Color3.fromRGB(255,120,235) }

	local function upgCurVal(id, lvl)
		if     id=="slots"   then return (Config.MAX_EQUIPPED + lvl).." Slots"
		elseif id=="speed"   then return Config.SPEED_LEVELS[lvl+1].."s"
		elseif id=="luck"    then return Config.LUCK_LEVELS[lvl+1].."× Luck"
		elseif id=="power"   then return Config.POWER_LEVELS[lvl+1].."× DMG"
		elseif id=="greed"   then return Config.COIN_LEVELS[lvl+1].."× Coins"
		elseif id=="fortune" then return Config.FORTUNE_LEVELS[lvl+1].."× Shiny"
		end; return ""
	end
	local function upgByID(id) for _,u in ipairs(Config.UPGRADES) do if u.id==id then return u end end end

	-- Upgrades unlock as you buy their prerequisite.
	local PREREQ = { speed="slots", power="slots", luck="speed", greed="luck", fortune="power" }

	-- Honeycomb layout (offset rows, generous gaps so nothing overlaps).
	-- role: "upg" key=id | "link" backpack | "lock" (?)
	local CELL = 80
	local LAYOUT = {
		{  -48, -86,"upg","power" }, {  48, -86,"upg","speed" },
		{  -96,   0,"link","backpack" }, {   0,   0,"upg","slots" }, {  96,   0,"upg","greed" },
		{  -48,  86,"upg","fortune" }, {  48,  86,"upg","luck" },
	}

	local uCards = {}
	function refreshUpgrades()
		for _,c in ipairs(uCards) do c:Destroy() end; uCards={}
		local cur      = stats.upgrades or {slots=0,speed=0,luck=0}
		local myCoins  = stats.coins or 0
		local affordCount = 0

		for _, cell in ipairs(LAYOUT) do
			local dx, dy, role, key = cell[1], cell[2], cell[3], cell[4]
			local tile = mkF(upgradesModal, UDim2.fromOffset(CELL, CELL),
				UDim2.new(0.5, dx, 0.5, dy + 24), Color3.fromRGB(16,18,30), 0, 42)
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.BackgroundTransparency = 0.12   -- world shows faintly through
			corner(tile, 16)
			table.insert(uCards, tile)

			if role == "lock" then
				tile.BackgroundColor3 = Color3.fromRGB(28,30,46)
				stroke(tile, Color3.fromRGB(48,52,76), 1.5, 0.45)
				setFont(mkL(tile, "?", 28, Color3.fromRGB(74,80,110), 43), Enum.FontWeight.Heavy)

			elseif role == "link" then
				tile.BackgroundColor3 = Color3.fromRGB(44,36,12)
				stroke(tile, C.GOLD, 2, 0.3)
				mkL(tile, "🎒", 28, C.WHITE, 43).Position = UDim2.new(0,0,0,8)
				local n = mkL(tile, "Backpack", 11, C.WHITE, 43)
				n.Position = UDim2.new(0,0,1,-22); n.Size = UDim2.new(1,0,0,18); setFont(n, Enum.FontWeight.Bold)
				local btn = Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0)
				btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=44; btn.Parent=tile
				btn.MouseButton1Click:Connect(function() closeModal(); openModal(backpackModal); refreshBackpack() end)

			else -- "upg"
				local uDef     = upgByID(key)
				local lvl      = cur[key] or 0
				local maxLvl   = #uDef.levels
				local isMax    = lvl >= maxLvl
				local unlocked = (not PREREQ[key]) or ((cur[PREREQ[key]] or 0) >= 1)
				local cost     = not isMax and uDef.levels[lvl+1].cost or 0
				local afford   = unlocked and not isMax and myCoins >= cost
				if afford then affordCount = affordCount + 1 end
				local ac = UPG_COLS[key] or C.GREEN

				if not unlocked then
					-- locked until the prerequisite upgrade is bought
					tile.BackgroundColor3 = Color3.fromRGB(24,26,40)
					stroke(tile, Color3.fromRGB(48,52,76), 1.5, 0.45)
					local ic = mkL(tile, uDef.icon, 24, Color3.fromRGB(120,124,150), 43); ic.Position=UDim2.new(0,0,0,6)
					setFont(mkL(tile, "🔒", 18, Color3.fromRGB(150,155,180), 44), Enum.FontWeight.Heavy)
					local n = mkL(tile, uDef.name, 10, C.DIM, 43)
					n.Position = UDim2.new(0,2,1,-18); n.Size = UDim2.new(1,-4,0,14); setFont(n, Enum.FontWeight.Bold)
				else
					tile.BackgroundColor3 = isMax and Color3.fromRGB(44,36,12)
						or afford and ac:Lerp(Color3.new(0,0,0),0.5) or Color3.fromRGB(22,24,38)
					stroke(tile, isMax and C.GOLD or (afford and ac or Color3.fromRGB(52,56,80)), 2, isMax and 0.15 or 0.45)

					mkL(tile, uDef.icon, 24, C.WHITE, 43).Position = UDim2.new(0,0,0,3)
					local n = mkL(tile, uDef.name, 11, C.WHITE, 43)
					n.Position = UDim2.new(0,2,0,30); n.Size = UDim2.new(1,-4,0,14); setFont(n, Enum.FontWeight.Bold)
					local v = mkL(tile, upgCurVal(key, lvl), 9, isMax and C.GOLD or C.DIM, 43)
					v.Position = UDim2.new(0,2,0,43); v.Size = UDim2.new(1,-4,0,12)

					local pill = mkF(tile, UDim2.new(1,-12,0,18), UDim2.new(0,6,1,-23),
						isMax and Color3.fromRGB(60,52,16) or (afford and ac or Color3.fromRGB(36,38,56)), 0, 43)
					corner(pill, 6)
					setFont(mkL(pill, isMax and "MAX ✓" or ("💰 "..Config.fmtNum(cost)), 10,
						isMax and C.GOLD or C.WHITE, 44), Enum.FontWeight.Bold)

					-- level badge (top-right corner, like the reference)
					if lvl > 0 then
						local badge = mkF(tile, UDim2.fromOffset(20,20), UDim2.new(1,-18,0,-2),
							isMax and C.GOLD or C.RED, 0, 45)
						badge.AnchorPoint = Vector2.new(0.5,0.5); corner(badge, 10)
						stroke(badge, C.WHITE, 1.5, 0.3)
						setFont(mkL(badge, tostring(lvl), 11, C.WHITE, 46), Enum.FontWeight.Heavy)
					end

					if afford then
						local btn = Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0)
						btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=46; btn.Parent=tile
						hover(tile, tile.BackgroundColor3, ac:Lerp(C.WHITE,0.2))
						btn.MouseButton1Click:Connect(function() Remotes.BuyUpgrade:FireServer(key) end)
					end
				end
			end
		end
		return affordCount
	end
end

-- ─── REBIRTH MODAL ────────────────────────────────────────────────────────────
-- Before / after comparison layout (inspired by screenshot)
local rebirthModal = makeModal(420,410,Color3.fromRGB(170,80,240))
rebirthModal:SetAttribute("OpenSize", UDim2.fromOffset(420,410))
local rebirthCostLbl, rebirthInfoLbl   -- kept for legacy compat
local rebBef = {}    -- [1]=coins [2]=rebirths [3]=luck  (before labels)
local rebAft = {}    -- [1]=coins [2]=rebirths [3]=luck  (after labels)

do
	local PRPL = Color3.fromRGB(170,80,240)
	modalHeader(rebirthModal, "♻️  Rebirth", PRPL)

	-- "items kept" subtitle
	local kept = Instance.new("TextLabel")
	kept.Size=UDim2.new(1,-20,0,18); kept.Position=UDim2.new(0,10,0,56)
	kept.BackgroundTransparency=1
	kept.Text="✅  Slimes, upgrades and items are all kept!"
	kept.TextColor3=Color3.fromRGB(80,210,100); kept.TextSize=12
	kept.TextXAlignment=Enum.TextXAlignment.Left; kept.ZIndex=42
	setFont(kept, Enum.FontWeight.Regular); kept.Parent=rebirthModal

	-- Column headers
	local bHdr=mkL(rebirthModal,"BEFORE",11,C.DIM,42)
	bHdr.Size=UDim2.fromOffset(150,16); bHdr.Position=UDim2.new(0,18,0,78)
	bHdr.TextXAlignment=Enum.TextXAlignment.Left; setFont(bHdr, Enum.FontWeight.Regular)
	local aHdr=mkL(rebirthModal,"AFTER",11,Color3.fromRGB(80,210,100),42)
	aHdr.Size=UDim2.fromOffset(150,16); aHdr.AnchorPoint=Vector2.new(1,0)
	aHdr.Position=UDim2.new(1,-18,0,78)
	aHdr.TextXAlignment=Enum.TextXAlignment.Right; setFont(aHdr, Enum.FontWeight.Regular)

	-- Three comparison rows
	local ROW_ICONS = { "💰", "♦", "🍀" }
	local ROW_COLS  = { C.GOLD, Color3.fromRGB(200,150,255), Color3.fromRGB(80,220,100) }
	for i = 1, 3 do
		local yOff = 98 + (i-1)*74

		local rowBg = mkF(rebirthModal, UDim2.new(1,-20,0,62), UDim2.new(0,10,0,yOff),
			Color3.fromRGB(15,17,30), 0, 41)
		corner(rowBg,12)

		-- BEFORE box (left half)
		local bBox = mkF(rowBg, UDim2.new(0.44,-4,1,-10), UDim2.new(0,5,0,5),
			Color3.fromRGB(24,26,44), 0, 42)
		corner(bBox,9)
		local biL = mkL(bBox, ROW_ICONS[i], 20, C.WHITE, 43)
		biL.Size=UDim2.fromOffset(30,42); biL.Position=UDim2.new(0,5,0,0)
		biL.TextXAlignment=Enum.TextXAlignment.Center
		local bvL = Instance.new("TextLabel")
		bvL.Size=UDim2.new(1,-38,1,0); bvL.Position=UDim2.new(0,36,0,0)
		bvL.BackgroundTransparency=1; bvL.Text="—"
		bvL.TextColor3=C.WHITE; bvL.TextSize=15
		bvL.TextXAlignment=Enum.TextXAlignment.Left; bvL.ZIndex=43
		setFont(bvL, Enum.FontWeight.Heavy); bvL.Parent=bBox
		rebBef[i] = bvL

		-- Arrow
		local arL = mkL(rowBg, "→", 18, Color3.fromRGB(75,75,110), 43)
		arL.Size=UDim2.fromOffset(26,62); arL.AnchorPoint=Vector2.new(0.5,0)
		arL.Position=UDim2.new(0.5,-13,0,0)

		-- AFTER box (right half)
		local aBox = mkF(rowBg, UDim2.new(0.44,-4,1,-10), UDim2.new(0,0,0,0),
			Color3.fromRGB(24,26,44), 0, 42)
		aBox.AnchorPoint=Vector2.new(1,0); aBox.Position=UDim2.new(1,-5,0,5)
		corner(aBox,9)
		local aiL = mkL(aBox, ROW_ICONS[i], 20, C.WHITE, 43)
		aiL.Size=UDim2.fromOffset(30,42); aiL.Position=UDim2.new(0,5,0,0)
		aiL.TextXAlignment=Enum.TextXAlignment.Center
		local avL = Instance.new("TextLabel")
		avL.Size=UDim2.new(1,-38,1,0); avL.Position=UDim2.new(0,36,0,0)
		avL.BackgroundTransparency=1; avL.Text="—"
		avL.TextColor3=ROW_COLS[i]; avL.TextSize=15
		avL.TextXAlignment=Enum.TextXAlignment.Left; avL.ZIndex=43
		setFont(avL, Enum.FontWeight.Heavy); avL.Parent=aBox
		rebAft[i] = avL
	end

	-- Cost bar
	local costBg = mkF(rebirthModal, UDim2.new(1,-20,0,34), UDim2.new(0,10,0,326),
		Color3.fromRGB(22,20,8), 0, 41)
	corner(costBg,10); stroke(costBg, C.GOLD, 1.5, 0.35)
	rebirthCostLbl = mkL(costBg, "Cost:  💰 500", 15, C.GOLD, 42)
	rebirthCostLbl.Size=UDim2.new(1,-12,1,0); rebirthCostLbl.Position=UDim2.new(0,10,0,0)
	rebirthCostLbl.TextXAlignment=Enum.TextXAlignment.Left

	-- Info
	rebirthInfoLbl = Instance.new("TextLabel")
	rebirthInfoLbl.Size=UDim2.new(1,-20,0,16); rebirthInfoLbl.Position=UDim2.new(0,10,0,368)
	rebirthInfoLbl.BackgroundTransparency=1; rebirthInfoLbl.Text="Rebirths: 0  •  Luck: 1.00×"
	rebirthInfoLbl.TextColor3=C.DIM; rebirthInfoLbl.TextSize=12
	rebirthInfoLbl.TextXAlignment=Enum.TextXAlignment.Left; rebirthInfoLbl.ZIndex=42
	setFont(rebirthInfoLbl, Enum.FontWeight.Regular); rebirthInfoLbl.Parent=rebirthModal

	-- REBIRTH button
	local confirmBtn=mkB(rebirthModal,"♻️  REBIRTH",17,Color3.fromRGB(130,55,175),C.WHITE,
		43, UDim2.new(1,-20,0,48), UDim2.new(0,10,0,380))
	corner(confirmBtn,13); bevel(confirmBtn, Color3.fromRGB(170,80,240))
	hover(confirmBtn, Color3.fromRGB(130,55,175), Color3.fromRGB(180,100,245))
	confirmBtn.MouseButton1Click:Connect(function()
		Remotes.RequestRebirth:FireServer(); closeModal()
	end)

	-- Refresh function: updates all before/after labels from current stats
	function refreshRebirth()
		if not stats or not stats.coins then return end
		local s    = stats
		local cost = Config.REBIRTH_BASE_COST * ((s.rebirths or 0) + 1)
		local newR = (s.rebirths or 0) + 1
		local upgL = Config.LUCK_LEVELS[((s.upgrades and s.upgrades.luck) or 0) + 1] or 1
		local newL = upgL + newR * Config.REBIRTH_LUCK_BONUS
		if s.passMegaLuck then newL = newL * Config.MEGA_LUCK_MULT end   -- match server luck math
		local canAff = (s.coins or 0) >= cos…10553 tokens truncated… → white highlight dot
-- Mouth: upward-arc "U" using a clipping frame trick (not a frown bar)
-- (PET_FACE_EXPR removed — the card faces use mkPetFace now.)
local DEFAULT_EXPR = { eyeW=14, eyeH=14, mouthW=20, mouthH=10, mouthY=34 }

local function buildFace(parent, expr, faceSize)
	-- parent is the coloured body circle frame (faceSize px wide/tall)
	expr = expr or DEFAULT_EXPR
	local INK = Color3.fromRGB(18,12,25)  -- always dark ink, never pet-colour

	-- Left eye
	local eL = mkF(parent, UDim2.fromOffset(expr.eyeW, expr.eyeH),
		UDim2.new(0, math.floor(faceSize*0.17), 0, math.floor(faceSize*0.22)), C.WHITE, 0, 7)
	corner(eL, math.floor(expr.eyeH/2))
	local pL = mkF(eL, UDim2.fromOffset(math.floor(expr.eyeW*0.52), math.floor(expr.eyeH*0.60)),
		UDim2.new(0.5,-math.floor(expr.eyeW*0.26), 0, math.floor(expr.eyeH*0.18)), INK, 0, 8)
	corner(pL, math.floor(expr.eyeH*0.25))
	-- Kawaii highlight dot
	mkF(pL, UDim2.fromOffset(3,3), UDim2.new(0,1,0,1), C.WHITE, 0, 9)

	-- Right eye
	local eR = mkF(parent, UDim2.fromOffset(expr.eyeW, expr.eyeH),
		UDim2.new(0, math.floor(faceSize*0.83-expr.eyeW), 0, math.floor(faceSize*0.22)), C.WHITE, 0, 7)
	corner(eR, math.floor(expr.eyeH/2))
	local pR = mkF(eR, UDim2.fromOffset(math.floor(expr.eyeW*0.52), math.floor(expr.eyeH*0.60)),
		UDim2.new(0.5,-math.floor(expr.eyeW*0.26), 0, math.floor(expr.eyeH*0.18)), INK, 0, 8)
	corner(pR, math.floor(expr.eyeH*0.25))
	mkF(pR, UDim2.fromOffset(3,3), UDim2.new(0,1,0,1), C.WHITE, 0, 9)

	-- Upward-arc smile (clipping trick: show only BOTTOM half of a circle = U shape)
	local mW, mH = expr.mouthW, expr.mouthH
	local clip = Instance.new("Frame")
	clip.Size = UDim2.fromOffset(mW, mH)
	clip.AnchorPoint = Vector2.new(0.5, 0)
	clip.Position = UDim2.new(0.5, 0, 0, expr.mouthY)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = 7; clip.Parent = parent

	local arc = Instance.new("Frame")
	arc.Size = UDim2.fromOffset(mW, mW)       -- full circle diameter
	arc.Position = UDim2.new(0, 0, 0, -(mW - mH))  -- shift up so only bottom mH shows
	arc.BackgroundColor3 = INK
	arc.BorderSizePixel = 0; arc.ZIndex = 8; arc.Parent = clip
	local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1,0); ac.Parent = arc

	return {eL=eL,eR=eR,pL=pL,pR=pR,clip=clip,arc=arc}
end

-- (addCardFeatures removed — card faces use mkPetFace now.)

-- 60 card slots — 116px tall (feature zone 0-20, face 22-80, labels 82-110)
local rCards = {}
for i = 1, NUM_CARDS do
	local xOff = (i-1)*CARD_SLOT
	local card = mkF(rStrip, UDim2.fromOffset(CARD_W, STRIP_H), UDim2.new(0, xOff, 0, 0),
		Color3.fromRGB(20,22,38), 0, 5)
	corner(card, 10)

	-- Face circle — positioned lower to leave room for features above
	local circ = mkF(card, UDim2.fromOffset(58,58), UDim2.new(0.5,-29,0,22),
		Color3.fromRGB(40,42,60), 0, 6)
	corner(circ, 12)
	buildFace(circ, DEFAULT_EXPR, 58)

	-- Shiny star
	local star = mkL(circ, "⭐", 9, C.GOLD, 7)
	star.Size=UDim2.fromOffset(13,13); star.AnchorPoint=Vector2.new(1,0)
	star.Position=UDim2.new(1,-1,0,1); star.Visible=false

	-- Name (below face)
	local nl = mkL(card, "", 9, C.WHITE, 6)
	nl.Size=UDim2.new(1,-4,0,13); nl.Position=UDim2.new(0,2,0,82)
	nl.TextTruncate=Enum.TextTruncate.AtEnd; setFont(nl,Enum.FontWeight.Bold)

	-- Rarity
	local rl = mkL(card, "", 8, C.DIM, 6)
	rl.Size=UDim2.new(1,-4,0,11); rl.Position=UDim2.new(0,2,0,95)
	setFont(rl,Enum.FontWeight.Regular)

	rCards[i] = {frame=card, circ=circ, nl=nl, rl=rl, star=star}
end

-- ── Odds bar (visible while spinning, hidden when result shows) ──────────────
local ODDS_Y = 54 + STRIP_H + 6   -- 176: just below strip

-- Compute base rarity odds from Config
local _oddsTotal = 0
for _, p in ipairs(Config.PETS) do _oddsTotal = _oddsTotal + 1/p.rarity end
local _tierPct = {}
for _, tier in ipairs({"Common","Uncommon","Rare","Epic","Legendary","Mythic"}) do
	local w = 0
	for _, p in ipairs(Config.PETS) do
		if p.label == tier then w = w + 1/p.rarity end
	end
	_tierPct[tier] = w / _oddsTotal * 100
end

local TIER_COLS = {
	Common=Color3.fromRGB(180,180,180), Uncommon=Color3.fromRGB(60,200,110),
	Rare=Color3.fromRGB(80,140,255),    Epic=Color3.fromRGB(180,70,245),
	Legendary=Color3.fromRGB(255,210,50), Mythic=Color3.fromRGB(255,90,190),
}
local oddsBar = mkF(rCard, UDim2.new(1,-20,0,26), UDim2.new(0,10,0,ODDS_Y),
	Color3.fromRGB(12,14,26), 0, 3)
corner(oddsBar, 8)
local oddsLayout = Instance.new("UIListLayout", oddsBar)
oddsLayout.FillDirection = Enum.FillDirection.Horizontal
oddsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
oddsLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
oddsLayout.Padding = UDim.new(0, 6)
for _, tier in ipairs({"Common","Uncommon","Rare","Epic","Legendary","Mythic"}) do
	local pct = _tierPct[tier] or 0
	local pill = mkF(oddsBar, UDim2.fromOffset(0, 18), UDim2.new(0,0,0,0),
		TIER_COLS[tier]:Lerp(Color3.new(0,0,0),0.55), 0, 4)
	-- Size by list layout with AutomaticSize
	pill.AutomaticSize = Enum.AutomaticSize.X
	corner(pill, 5)
	local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency=1
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size=UDim2.fromOffset(0,18)
	lbl.Text = (pct >= 1 and string.format("%.1f%%",pct) or string.format("%.2f%%",pct))
	lbl.TextColor3=TIER_COLS[tier]; lbl.TextSize=9; lbl.ZIndex=5
	local lpad=Instance.new("UIPadding",pill); lpad.PaddingLeft=UDim.new(0,4); lpad.PaddingRight=UDim.new(0,4)
	setFont(lbl, Enum.FontWeight.Bold); lbl.Parent=pill
end

-- Skip button lives INSIDE the odds bar area (right side)
local rSkipBtn = mkB(rCard, "⏭  Skip", 12, Color3.fromRGB(40,44,65), C.DIM, 4,
	UDim2.fromOffset(80,26), UDim2.new(1,-90, 0, ODDS_Y))
corner(rSkipBtn, 7); rSkipBtn.Visible = false

-- ── Result section (hidden while spinning) ────────────────────────────────────
local RES_Y = ODDS_Y   -- result replaces odds bar after spin

local rResultName = mkL(rCard, "", 25, C.WHITE, 3)
rResultName.Size=UDim2.new(1,-20,0,30); rResultName.Position=UDim2.new(0,10,0,RES_Y)
setFont(rResultName, Enum.FontWeight.Heavy)

local rResultSub = mkL(rCard, "", 13, C.DIM, 3)
rResultSub.Size=UDim2.new(1,-20,0,18); rResultSub.Position=UDim2.new(0,10,0,RES_Y+31)
setFont(rResultSub, Enum.FontWeight.Regular)

-- Action buttons (compact row at bottom)
local rEquipBtn = mkB(rCard,"⚔️  Equip",14,C.GREEN,Color3.fromRGB(10,28,10),4,
	UDim2.fromOffset(116,38), UDim2.new(0,10,1,-50))
corner(rEquipBtn,11); bevel(rEquipBtn,C.GREEN); hover(rEquipBtn,C.GREEN,Color3.fromRGB(60,210,90))

local rSellBtn = mkB(rCard,"💰  Sell",14,C.AMBER,Color3.fromRGB(30,18,4),4,
	UDim2.fromOffset(98,38), UDim2.new(0.5,-49,1,-50))
corner(rSellBtn,11); bevel(rSellBtn,C.AMBER); hover(rSellBtn,C.AMBER,Color3.fromRGB(245,165,55))

local rKeepBtn = mkB(rCard,"✖  Keep",13,C.RED2,C.WHITE,4,
	UDim2.fromOffset(82,38), UDim2.new(1,-92,1,-50))
corner(rKeepBtn,11); hover(rKeepBtn,C.RED2,C.RED)

-- Shiny badge
local rShinyBadge = mkF(rCard, UDim2.fromOffset(110,26), UDim2.new(0.5,-55,0,RES_Y+34),
	Color3.fromRGB(60,45,5), 0, 4)
corner(rShinyBadge,10); stroke(rShinyBadge, C.GOLD, 2, 0)
local rShinyLbl = mkL(rShinyBadge, "⭐ SHINY!", 13, C.GOLD, 5)
setFont(rShinyLbl, Enum.FontWeight.Heavy)
rShinyBadge.Visible = false

-- Auto-sold banner (shown when pet is auto-sold)
local rAutoSold = mkF(rCard, UDim2.fromOffset(180,28), UDim2.new(0.5,-90,0,174),
	Color3.fromRGB(40,28,5), 0, 4)
corner(rAutoSold,10); stroke(rAutoSold, C.AMBER, 1.5, 0.2)
mkL(rAutoSold, "💰 Auto-Sold!", 13, C.AMBER, 5).TextStrokeTransparency=0.5
rAutoSold.Visible = false

-- ── In-card SPIN / Roll Again button (below the pet strip, above action row) ──
-- Shown in idle state; hidden during spin; reappears after Equip/Sell/Keep.
local rSpinInsideBtn = mkB(rCard, "🎲  SPIN", 18, C.PURPLE, C.WHITE, 4,
	UDim2.new(1,-20,0,44), UDim2.new(0,10,0,207))
corner(rSpinInsideBtn, 13)
grad(rSpinInsideBtn, 90, ColorSequence.new({
	ColorSequenceKeypoint.new(0, C.PURPLE:Lerp(C.WHITE,0.24)),
	ColorSequenceKeypoint.new(1, C.PURPLE:Lerp(Color3.new(0,0,0),0.30)),
}), nil)
hover(rSpinInsideBtn, C.PURPLE, C.PURPLE:Lerp(C.WHITE,0.32))
stroke(rSpinInsideBtn, C.WHITE, 2, 0.55)

-- X close button — always visible in top-right of the roulette card
local rCloseBtn = mkB(rCard, "✖", 14, Color3.fromRGB(55,28,28), Color3.fromRGB(210,130,130),
	4, UDim2.fromOffset(30,30), UDim2.new(1,-36,0,7))
corner(rCloseBtn, 8)
hover(rCloseBtn, Color3.fromRGB(55,28,28), C.RED)

-- Internal roulette state
local rouletteSpinning = false

local function hideRoulette()
	-- Fully close the roulette overlay (called by the X button)
	pendingPet         = nil
	rouletteGui.Enabled = false
	rDim.Visible       = false
	rouletteSpinning   = false
	dimOverlay.Visible = false
end

local function resetRouletteIdle()
	-- Keep the card visible but clear the result — player can roll again without reopening
	pendingPet          = nil
	rouletteSpinning    = false
	rDim.Visible        = false
	dimOverlay.Visible  = false
	rResultName.Visible = false; rResultSub.Visible  = false
	rEquipBtn.Visible   = false; rSellBtn.Visible    = false
	rKeepBtn.Visible    = false; rSkipBtn.Visible    = false
	rShinyBadge.Visible = false; rAutoSold.Visible   = false
	oddsBar.Visible            = true
	rSpinInsideBtn.Text        = "🎲  Roll Again"
	rSpinInsideBtn.Visible     = true
	rTitle.Text = "🎲  Roll for a pet!"
end

local function populateStrip(winnerId)
	local allIds = {}
	for _, p in ipairs(Config.PETS) do table.insert(allIds, p.id) end

	for i = 1, NUM_CARDS do
		local pid = (i == WINNER_POS) and winnerId
			or allIds[math.random(1, #allIds)]
		local p   = resolvePet(pid) or resolvePet(allIds[1])
		local rc  = rCards[i]
		local isW = (i == WINNER_POS)

		-- Body colour + gradient
		rc.circ.BackgroundColor3 = p.color
		for _, ch in ipairs(rc.circ:GetChildren()) do
			-- Wipe old face elements so we can rebuild fresh
			if not ch:IsA("UIStroke") and not ch:IsA("UICorner") then ch:Destroy() end
		end
		grad(rc.circ, 135, ColorSequence.new({
			ColorSequenceKeypoint.new(0, p.color:Lerp(C.WHITE, 0.44)),
			ColorSequenceKeypoint.new(1, p.color:Lerp(Color3.new(0,0,0), 0.42)),
		}), nil)

		-- Cuter unified face (same system as the backpack/index)
		mkPetFace(rc.circ, p.baseId, p.color, 58, 6)

		-- Shiny star
		local star = mkL(rc.circ, "⭐", 9, C.GOLD, 7)
		star.Size=UDim2.fromOffset(13,13); star.AnchorPoint=Vector2.new(1,0)
		star.Position=UDim2.new(1,-1,0,1); star.Visible = p.isShiny == true
		rc.star = star

		-- Labels
		rc.nl.Text       = p.name
		rc.nl.TextColor3 = C.WHITE
		rc.rl.Text       = p.label
		rc.rl.TextColor3 = p.labelColor

		-- Border
		for _, ch in ipairs(rc.frame:GetChildren()) do
			if ch:IsA("UIStroke") then ch:Destroy() end
		end
		local s=Instance.new("UIStroke"); s.Color=p.labelColor
		s.Thickness    = isW and 2.5 or 1.5
		s.Transparency = isW and 0 or 0.70
		s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=rc.frame
		rc.frame.BackgroundColor3 = p.color:Lerp(Color3.new(0,0,0), isW and 0.28 or 0.56)
	end
end

-- Extracted result display — called by timer OR skip button
local rouletteResultPending = nil  -- {pet, wasAutoSold}

local function showRouletteResult()
	if not rouletteSpinning or not rouletteResultPending then return end
	local pet        = rouletteResultPending.pet
	local wasAutoSold= rouletteResultPending.wasAutoSold
	rSkipBtn.Visible = false
	oddsBar.Visible  = false   -- swap odds for result

	-- Winner card bounce
	TweenService:Create(rCards[WINNER_POS].frame,
		TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size=UDim2.fromOffset(CARD_W+14, 112)}):Play()
	task.delay(0.18, function()
		TweenService:Create(rCards[WINNER_POS].frame, TweenInfo.new(0.10),
			{Size=UDim2.fromOffset(CARD_W, 100)}):Play()
	end)

	-- Labels
	local r = pet.rarity
	rResultName.Text      = pet.name
	rResultName.TextColor3= pet.isShiny and C.GOLD or pet.labelColor
	rResultSub.Text       = pet.label.."  •  1/"..(r>=1000 and string.format("%.1fK",r/1000) or r)
		.."  •  "..pet.ability.name
	rResultSub.TextColor3 = pet.labelColor
	rResultName.Visible = true; rResultSub.Visible = true
	rShinyBadge.Visible = pet.isShiny == true
	rAutoSold.Visible   = wasAutoSold == true
	if not wasAutoSold then
		rEquipBtn.Visible = true; rSellBtn.Visible = true
	end
	rKeepBtn.Visible  = true
	rTitle.Text       = "✨  You rolled..."
	-- Lift the dim — player can interact with HUD while reading the result
	rDim.Visible      = false
	dimOverlay.Visible = false
	rouletteSpinning  = false
end

local function spinRoulette(fullPetId, wasAutoSold)
	if rouletteSpinning then return end
	rouletteSpinning = true

	local pet = resolvePet(fullPetId)
	if not pet then rouletteSpinning=false; return end
	pendingPet = pet
	rouletteResultPending = { pet=pet, wasAutoSold=wasAutoSold }

	-- Reset UI
	rResultName.Visible    = false; rResultSub.Visible    = false
	rEquipBtn.Visible      = false; rSellBtn.Visible      = false
	rKeepBtn.Visible       = false; rSkipBtn.Visible      = false
	rShinyBadge.Visible    = false; rAutoSold.Visible     = false
	rSpinInsideBtn.Visible = false   -- hidden while the strip is moving
	oddsBar.Visible        = true    -- show odds while spinning

	-- Reset strip
	rStrip.Position = UDim2.new(0, 0, 0, 0)
	populateStrip(pet.baseId)

	-- Compute target X: winner card centred in 620px frame
	local frameW   = 620
	local winnerCX = (WINNER_POS - 1) * CARD_SLOT + CARD_W / 2
	local offset   = math.random(-28, 28)
	local targetX  = -(winnerCX - frameW/2 + offset)
	rouletteTargetX = targetX

	rouletteGui.Enabled = true
	rDim.Visible        = true   -- full-screen dim during spin only
	dimOverlay.Visible  = true

	-- Show skip after 0.6s
	task.delay(0.6, function()
		if rouletteSpinning then rSkipBtn.Visible = true end
	end)

	-- Animate
	local ti = TweenInfo.new(5.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	activeTween = TweenService:Create(rStrip, ti, {Position=UDim2.new(0, targetX, 0, 0)})
	activeTween:Play()
	playSpinTicks(5.3)   -- classic spin sound

	task.delay(5.65, function()
		if rouletteSpinning then showRouletteResult() end
	end)
end

-- Skip button wiring
rSkipBtn.MouseButton1Click:Connect(function()
	if not rouletteSpinning then return end
	if activeTween then activeTween:Cancel(); activeTween=nil end
	rStrip.Position = UDim2.new(0, rouletteTargetX, 0, 0)
	showRouletteResult()
end)

local function showPopup(fullId, wasAutoSold)
	spinRoulette(fullId, wasAutoSold)
end

local function hidePopup()
	hideRoulette()
end

-- Roulette button wiring
rEquipBtn.MouseButton1Click:Connect(function()
	if not pendingPet then return end
	Remotes.EquipCreature:FireServer(pendingPet.id)
	resetRouletteIdle()   -- keep card open, clear result
end)

rSellBtn.MouseButton1Click:Connect(function()
	if not pendingPet then return end
	local idx = nil
	for i = #inventory, 1, -1 do
		if inventory[i] == pendingPet.id then idx = i; break end
	end
	if idx then Remotes.SellCreature:FireServer(idx) end
	resetRouletteIdle()   -- keep card open, clear result
end)

rKeepBtn.MouseButton1Click:Connect(resetRouletteIdle)   -- keep card, clear result
rCloseBtn.MouseButton1Click:Connect(hideRoulette)        -- ✖ actually closes the overlay

-- In-card spin button — same logic as the external roll button
rSpinInsideBtn.MouseButton1Click:Connect(function()
	if onCooldown or rouletteSpinning then return end
	onCooldown = true; cooldownStart = tick()
	TweenService:Create(rollBtn, TweenInfo.new(0.1), {BackgroundColor3=ROLL_CD}):Play()
	rollBtn.Text = ""; cdOverlay.Text = "..."
	rSpinInsideBtn.Text = "⏳  Rolling..."
	Remotes.RequestRoll:FireServer()
end)

-- ─── PET MODELS ───────────────────────────────────────────────────────────────
-- ── Pet Simulator–style blocky pets ───────────────────────────────────────────
-- Cube/ball body, big glossy eyes, little feet, species-correct features.
-- Ball-bodied species (round): blob_slime, mini_dragon, storm_hawk, crystal_phoenix
-- Cube-bodied species (blocky): fire_pup, flame_fox, shadow_cat, frost_bunny
local BALL_BODY = { blob_slime=true }

local function buildPetModel(slot, pet)
	if followers[slot] then followers[slot].model:Destroy(); followers[slot]=nil end
	if not pet then return end

	local sz    = 3 * pet.sz
	local col   = pet.color
	local BLACK = Color3.new(0,0,0)
	local WHT   = Color3.new(1,1,1)
	local model = Instance.new("Model")
	model.Name = "PetModel_"..slot; model.Parent = workspace

	local function sphere(s,c,mat,tr)
		local p=Instance.new("Part"); p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(s,s,s)
		p.Color=c; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CastShadow=false
		p.Transparency=tr or 0; p.Parent=model; return p
	end
	local function block(sx,sy,sz_,c,mat,tr)
		local p=Instance.new("Part"); p.Size=Vector3.new(sx,sy,sz_)
		p.Color=c; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CastShadow=false
		p.Transparency=tr or 0; p.Parent=model; return p
	end
	local function wedge(thick,height,base,c,mat)  -- triangle facing front when Y-rotated 90°
		local p=Instance.new("WedgePart"); p.Size=Vector3.new(thick,height,base)
		p.Color=c; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CastShadow=false; p.Parent=model; return p
	end

	-- ── Common body + face ──────────────────────────────────────────────────
	local body = block(sz*0.96, sz*0.92, sz*0.86, col)
	if BALL_BODY[pet.baseId] then
		body.Shape = Enum.PartType.Ball
		body.Size  = Vector3.new(sz, sz, sz) * 0.96
	end
	local glow = sphere(sz*1.02, col, Enum.Material.SmoothPlastic, 0.92)   -- very faint outline (no neon halo)
	local e1   = sphere(sz*0.30, WHT)
	local e2   = sphere(sz*0.30, WHT)
	local p1   = sphere(sz*0.155, Color3.fromRGB(14,14,26))
	local p2   = sphere(sz*0.155, Color3.fromRGB(14,14,26))
	local sh1  = sphere(sz*0.07, WHT)   -- glossy eye shine
	local sh2  = sphere(sz*0.07, WHT)
	local foot1= block(sz*0.26, sz*0.18, sz*0.30, col:Lerp(BLACK,0.30))
	local foot2= block(sz*0.26, sz*0.18, sz*0.30, col:Lerp(BLACK,0.30))
	local x    = {}  -- pet-specific extras

	-- Slimes have no feet
	if pet.baseId == "blob_slime" then foot1.Transparency=1; foot2.Transparency=1 end
	-- Dragon: slightly larger round pupils (not huge)
	if pet.baseId == "mini_dragon" then
		p1.Size = Vector3.new(sz*0.17, sz*0.17, sz*0.17); p2.Size = p1.Size
	end

	if pet.baseId == "blob_slime" then
		x.smile = block(sz*0.30, sz*0.07, sz*0.05, Color3.fromRGB(18,120,30), Enum.Material.Neon)
		x.drip  = sphere(sz*0.18, col)
		x.shine = sphere(sz*0.16, col:Lerp(WHT,0.55), Enum.Material.SmoothPlastic, 0.25)

	elseif pet.baseId == "fire_pup" then
		x.snout = block(sz*0.34, sz*0.26, sz*0.24, col:Lerp(WHT,0.45))
		x.nose  = sphere(sz*0.12, Color3.fromRGB(36,18,12))
		x.ear1  = block(sz*0.20, sz*0.34, sz*0.10, col:Lerp(BLACK,0.18))  -- floppy ears
		x.ear2  = block(sz*0.20, sz*0.34, sz*0.10, col:Lerp(BLACK,0.18))
		x.tail  = block(sz*0.16, sz*0.42, sz*0.16, col)

	elseif pet.baseId == "flame_fox" then
		x.ear1  = wedge(sz*0.07, sz*0.34, sz*0.24, col)
		x.ear2  = wedge(sz*0.07, sz*0.34, sz*0.24, col)
		x.iear1 = wedge(sz*0.05, sz*0.20, sz*0.14, Color3.fromRGB(255,242,210))
		x.iear2 = wedge(sz*0.05, sz*0.20, sz*0.14, Color3.fromRGB(255,242,210))
		x.snout = block(sz*0.26, sz*0.20, sz*0.22, col:Lerp(WHT,0.4))
		x.nose  = sphere(sz*0.10, Color3.fromRGB(40,18,10))
		x.tailB = sphere(sz*0.30, col)
		x.tailT = sphere(sz*0.30, Color3.fromRGB(255,242,200))

	elseif pet.baseId == "shadow_cat" then
		-- CAT (ref #1): cube head, pointed ears, whiskers, cute smile
		x.ear1  = wedge(sz*0.07, sz*0.32, sz*0.24, col)
		x.ear2  = wedge(sz*0.07, sz*0.32, sz*0.24, col)
		x.iear1 = wedge(sz*0.05, sz*0.18, sz*0.15, Color3.fromRGB(190,110,245), Enum.Material.Neon)
		x.iear2 = wedge(sz*0.05, sz*0.18, sz*0.15, Color3.fromRGB(190,110,245), Enum.Material.Neon)
		x.nose  = sphere(sz*0.085, Color3.fromRGB(245,140,165))
		x.smile = block(sz*0.20, sz*0.05, sz*0.04, Color3.fromRGB(20,8,34))
		x.wh1   = block(sz*0.34, sz*0.025, sz*0.025, WHT)
		x.wh2   = block(sz*0.34, sz*0.025, sz*0.025, WHT)
		x.wh3   = block(sz*0.34, sz*0.025, sz*0.025, WHT)
		x.wh4   = block(sz*0.34, sz*0.025, sz*0.025, WHT)
		x.tail  = block(sz*0.11, sz*0.55, sz*0.11, col)

	elseif pet.baseId == "frost_bunny" then
		-- BUNNY (ref #3): cube head, tall ears w/ pink inner, pink cheeks, smile
		x.ear1  = block(sz*0.17, sz*0.66, sz*0.11, col)
		x.ear2  = block(sz*0.17, sz*0.66, sz*0.11, col)
		x.iear1 = block(sz*0.09, sz*0.48, sz*0.06, Color3.fromRGB(248,205,228))
		x.iear2 = block(sz*0.09, sz*0.48, sz*0.06, Color3.fromRGB(248,205,228))
		x.cheek1= sphere(sz*0.15, Color3.fromRGB(250,185,208))
		x.cheek2= sphere(sz*0.15, Color3.fromRGB(250,185,208))
		x.nose  = sphere(sz*0.085, Color3.fromRGB(240,115,145))
		x.smile = block(sz*0.16, sz*0.045, sz*0.04, Color3.fromRGB(70,80,110))
		x.tail  = sphere(sz*0.26, WHT)

	elseif pet.baseId == "mini_dragon" then
		-- DRAGON (ref: green cube dragon) — same cute cube formula as cat/bunny:
		-- big eyes + smile, plus horns, clean bat wings, a fang and a spaded tail.
		local mem = col:Lerp(BLACK, 0.16)        -- wing membrane
		x.belly = block(sz*0.46, sz*0.50, sz*0.06, col:Lerp(Color3.fromRGB(215,255,175),0.5))
		x.smile = block(sz*0.20, sz*0.05, sz*0.04, Color3.fromRGB(22,70,24))
		x.horn1 = wedge(sz*0.08, sz*0.34, sz*0.18, col:Lerp(BLACK,0.20))   -- tall pointed ears
		x.horn2 = wedge(sz*0.08, sz*0.34, sz*0.18, col:Lerp(BLACK,0.20))
		x.wing1 = block(sz*0.42, sz*0.46, sz*0.05, mem)
		x.wing2 = block(sz*0.42, sz*0.46, sz*0.05, mem)
		x.fang1 = wedge(sz*0.04, sz*0.09, sz*0.06, WHT)
		x.fang2 = wedge(sz*0.04, sz*0.09, sz*0.06, WHT)
		x.tail  = block(sz*0.12, sz*0.50, sz*0.12, col)
		x.tailtip = wedge(sz*0.05, sz*0.20, sz*0.24, col:Lerp(BLACK,0.2))

	elseif pet.baseId == "storm_hawk" then
		-- STORM (ref: dark stormy titan) — glowing eyes, jagged wings, electric spikes
		local dk = Color3.fromRGB(36, 78, 175)
		x.wing1 = block(sz*0.70, sz*0.26, sz*0.05, dk)
		x.wing2 = block(sz*0.70, sz*0.26, sz*0.05, dk)
		x.wtip1 = wedge(sz*0.06, sz*0.30, sz*0.34, Color3.fromRGB(28,60,150))
		x.wtip2 = wedge(sz*0.06, sz*0.30, sz*0.34, Color3.fromRGB(28,60,150))
		x.beak  = wedge(sz*0.14, sz*0.16, sz*0.20, Color3.fromRGB(255,200,40))
		x.crest1= wedge(sz*0.05, sz*0.34, sz*0.18, Color3.fromRGB(70,130,235))   -- solid (no neon)
		x.crest2= wedge(sz*0.05, sz*0.26, sz*0.14, Color3.fromRGB(70,130,235))
		x.spike1= wedge(sz*0.05, sz*0.38, sz*0.12, Color3.fromRGB(95,165,250))   -- solid spikes
		x.spike2= wedge(sz*0.05, sz*0.38, sz*0.12, Color3.fromRGB(95,165,250))
		x.bolt  = sphere(sz*0.12, Color3.fromRGB(210,235,255), Enum.Material.Neon, 0.3)

	elseif pet.baseId == "crystal_phoenix" then
		-- PHOENIX (ref: cyan owl) — layered feather wings, glowing eyes, crest, gem
		x.w1a = block(sz*0.46, sz*0.16, sz*0.05, Color3.fromRGB(190,242,255))
		x.w1b = block(sz*0.58, sz*0.16, sz*0.05, Color3.fromRGB(150,226,255))
		x.w1c = block(sz*0.48, sz*0.16, sz*0.05, Color3.fromRGB(120,210,255))
		x.w2a = block(sz*0.46, sz*0.16, sz*0.05, Color3.fromRGB(190,242,255))
		x.w2b = block(sz*0.58, sz*0.16, sz*0.05, Color3.fromRGB(150,226,255))
		x.w2c = block(sz*0.48, sz*0.16, sz*0.05, Color3.fromRGB(120,210,255))
		x.gem   = sphere(sz*0.18, Color3.fromRGB(120,235,255), Enum.Material.Neon, 0.25)
		x.crest1= wedge(sz*0.05, sz*0.30, sz*0.16, Color3.fromRGB(150,220,255))   -- solid (no neon)
		x.crest2= wedge(sz*0.05, sz*0.38, sz*0.16, Color3.fromRGB(120,205,255))
		x.crest3= wedge(sz*0.05, sz*0.30, sz*0.16, Color3.fromRGB(150,220,255))
		x.tail1 = block(sz*0.09, sz*0.50, sz*0.06, Color3.fromRGB(205,248,255))
		x.tail2 = block(sz*0.09, sz*0.46, sz*0.06, Color3.fromRGB(165,232,255))
		x.tail3 = block(sz*0.09, sz*0.42, sz*0.06, Color3.fromRGB(130,216,255))

	elseif pet.baseId == "chicken" then
		-- white cube chick: red comb, orange beak + wattle, little wings
		foot1.Color = Color3.fromRGB(245,170,40); foot2.Color = Color3.fromRGB(245,170,40)
		x.comb1 = block(sz*0.12, sz*0.16, sz*0.12, Color3.fromRGB(228,55,55))
		x.comb2 = block(sz*0.12, sz*0.20, sz*0.12, Color3.fromRGB(228,55,55))
		x.comb3 = block(sz*0.12, sz*0.16, sz*0.12, Color3.fromRGB(228,55,55))
		x.beak  = wedge(sz*0.12, sz*0.12, sz*0.16, Color3.fromRGB(255,170,40))
		x.wattle= sphere(sz*0.10, Color3.fromRGB(228,55,55))
		x.wing1 = block(sz*0.10, sz*0.30, sz*0.26, col)
		x.wing2 = block(sz*0.10, sz*0.30, sz*0.26, col)

	elseif pet.baseId == "emperor_snake" then
		-- DIVINE EMPEROR SNAKE: white cube, gold gear-halo + wings, NORMAL eyes
		-- (same as every other pet), forked tongue, gold crown + chest medallion.
		local GLD = Color3.fromRGB(255, 212, 70)
		x.nose  = sphere(sz*0.06, GLD)
		x.tongue1 = block(sz*0.03, sz*0.16, sz*0.03, Color3.fromRGB(255,90,90))   -- forked tongue
		x.tongue2 = block(sz*0.03, sz*0.16, sz*0.03, Color3.fromRGB(255,90,90))
		-- gold gear halo ring (segments)
		x.halo = {}
		for k = 1, 10 do
			x.halo[k] = block(sz*0.07, sz*0.05, sz*0.10, GLD)
		end
		-- gold layered wings
		x.w1a = block(sz*0.46, sz*0.15, sz*0.05, GLD)
		x.w1b = block(sz*0.56, sz*0.15, sz*0.05, GLD:Lerp(WHT,0.2))
		x.w2a = block(sz*0.46, sz*0.15, sz*0.05, GLD)
		x.w2b = block(sz*0.56, sz*0.15, sz*0.05, GLD:Lerp(WHT,0.2))
		x.chest = block(sz*0.22, sz*0.22, sz*0.06, GLD)   -- chest medallion
		x.comb1 = block(sz*0.10, sz*0.16, sz*0.10, GLD)
	end

	local pl=Instance.new("PointLight"); pl.Color=col; pl.Range=7; pl.Brightness=0.6; pl.Parent=body

	-- ── SHINY: same model as normal, with a uniform golden metallic sheen on
	-- the body + every feature (eyes kept white) + sparkle particles + star. ──
	if pet.isShiny then
		local function tint(p)
			if typeof(p) == "Instance" and p:IsA("BasePart") then
				p.Color    = p.Color:Lerp(C.GOLD, 0.5)
				p.Material  = Enum.Material.Metal
			elseif type(p) == "table" then
				for _, q in pairs(p) do tint(q) end   -- e.g. halo segment list
			end
		end
		tint(body); tint(foot1); tint(foot2)
		for _, v in pairs(x) do tint(v) end          -- all species features
		pl.Color = C.GOLD; pl.Brightness = 2.4; pl.Range = 14
		-- bright shimmer shell around the pet
		glow.Color = C.GOLD; glow.Transparency = 0.55; glow.Material = Enum.Material.Neon
		-- sparkle particles
		local att = Instance.new("Attachment"); att.Parent = body
		local pe = Instance.new("ParticleEmitter")
		pe.Texture          = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color            = ColorSequence.new(C.GOLD, Color3.fromRGB(255,255,210))
		pe.Size             = NumberSequence.new({
			NumberSequenceKeypoint.new(0, sz*0.30),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency     = NumberSequence.new(0.1)
		pe.Lifetime         = NumberRange.new(0.5, 0.9)
		pe.Rate             = 22
		pe.Speed            = NumberRange.new(1.5, 3)
		pe.SpreadAngle      = Vector2.new(180, 180)
		pe.LightEmission    = 1
		pe.Rotation         = NumberRange.new(0, 360)
		pe.Parent           = att
		-- gold "star" crown sparkle
		local star = sphere(sz*0.14, C.GOLD, Enum.Material.Neon, 0.05)
		x.shinyStar = star
	end

	local bb=Instance.new("BillboardGui"); bb.Size=UDim2.fromOffset(120,22)
	bb.StudsOffset=Vector3.new(0,sz/2+1.5,0); bb.MaxDistance=38; bb.Adornee=body; bb.Parent=body
	local tag=Instance.new("TextLabel"); tag.Size=UDim2.new(1,0,1,0); tag.BackgroundTransparency=1
	tag.Text=pet.name; tag.TextColor3=pet.labelColor
	tag.Font=Enum.Font.GothamBold; tag.TextSize=11; tag.TextStrokeTransparency=0.3; tag.Parent=bb

	-- Health bar (just under the name tag)
	local hpbb=Instance.new("BillboardGui"); hpbb.Size=UDim2.fromOffset(58,9)
	hpbb.StudsOffset=Vector3.new(0,sz/2+0.7,0); hpbb.MaxDistance=38; hpbb.Adornee=body; hpbb.Parent=body
	local hpBg=Instance.new("Frame"); hpBg.Size=UDim2.new(1,0,1,0)
	hpBg.BackgroundColor3=Color3.fromRGB(22,14,14); hpBg.BorderSizePixel=0; hpBg.Parent=hpbb
	local hbc=Instance.new("UICorner"); hbc.CornerRadius=UDim.new(0,3); hbc.Parent=hpBg
	local hbs=Instance.new("UIStroke"); hbs.Color=Color3.fromRGB(0,0,0); hbs.Thickness=1; hbs.Transparency=0.4; hbs.Parent=hpBg
	local hpFill=Instance.new("Frame"); hpFill.Size=UDim2.new(1,0,1,0)
	hpFill.BackgroundColor3=Color3.fromRGB(80,220,70); hpFill.BorderSizePixel=0; hpFill.Parent=hpBg
	local hfc=Instance.new("UICorner"); hfc.CornerRadius=UDim.new(0,3); hfc.Parent=hpFill

	followers[slot]={model=model,body=body,glow=glow,e1=e1,e2=e2,p1=p1,p2=p2,
		sh1=sh1,sh2=sh2,foot1=foot1,foot2=foot2,
		extras=x,sz=sz,pet=pet,phase=(slot-1)*(math.pi*2/5),
		hpBar=hpbb, hpFill=hpFill}
end

-- ─── NOTIFICATION TOAST ───────────────────────────────────────────────────────
local function showToast(txt, col)
	local t=mkF(gui, UDim2.fromOffset(280,48), UDim2.new(0.5,-140,1,-110), col or C.GREEN, 0, 90)
	corner(t, 14); stroke(t, C.WHITE, 1.5, 0.6)
	mkL(t, txt, 15, C.WHITE, 91); setFont(mkL(t,"",0,C.WHITE,91), Enum.FontWeight.Bold)
	t.BackgroundTransparency=0.12
	TweenService:Create(t, TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Position=UDim2.new(0.5,-140,1,-100)}):Play()
	task.delay(2.8, function()
		TweenService:Create(t, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{Position=UDim2.new(0.5,-140,1,-60),BackgroundTransparency=1}):Play()
		task.delay(0.3, function() t:Destroy() end)
	end)
end

-- ─── BUTTON WIRING ────────────────────────────────────────────────────────────
local ROLL_READY=C.PURPLE; local ROLL_CD=C.PURPLE2

rollBtn.MouseButton1Click:Connect(function()
	if onCooldown or rouletteSpinning then return end
	onCooldown=true; cooldownStart=tick()
	TweenService:Create(rollBtn, TweenInfo.new(0.1), {BackgroundColor3=ROLL_CD}):Play()
	rollBtn.Text=""; cdOverlay.Text="..."
	Remotes.RequestRoll:FireServer()
end)

-- Toggle: clicking the same button a second time closes the modal
local function toggleModal(modal, refreshFn)
	if activeModal == modal then
		closeModal()
	else
		if refreshFn then refreshFn() end
		openModal(modal)
	end
end

bpBtn.MouseButton1Click:Connect(function() toggleModal(backpackModal,  refreshBackpack) end)
upBtn.MouseButton1Click:Connect(function()
	if activeModal == upgradesModal then
		closeModal()
	else
		refreshUpgrades(); openModal(upgradesModal)
		dimOverlay.Visible = false   -- keep the world visible behind the upgrade tree
	end
end)
shopSideBtn.MouseButton1Click:Connect(function() toggleModal(robuxModal, refreshShop) end)
rebirthSideBtn.MouseButton1Click:Connect(function() toggleModal(rebirthModal, refreshRebirth) end)
indexSideBtn.MouseButton1Click:Connect(function() toggleModal(indexModal,   refreshIndex) end)
robuxSideBtn.MouseButton1Click:Connect(function() toggleModal(robuxModal, refreshShop) end)
dailySideBtn.MouseButton1Click:Connect(function()
	if activeModal == wheelModal then
		closeModal(); openModal(dailyModal); refreshDaily()
	elseif activeModal == dailyModal then
		closeModal(); openModal(wheelModal); refreshWheel()
	else
		openModal(wheelModal); refreshWheel()
	end
end)
levelSideBtn.MouseButton1Click:Connect(function() toggleModal(levelModal, refreshLevel) end)
goopPlus.MouseButton1Click:Connect(function() toggleModal(robuxModal, refreshShop) end)
gemPlus.MouseButton1Click:Connect(function() toggleModal(rebirthModal, refreshRebirth) end)

-- (Roulette buttons are wired inside the roulette do-block above)

-- ─── REMOTE LISTENERS ─────────────────────────────────────────────────────────
Remotes.UpdateCoins.OnClientEvent:Connect(function(amount)
	coins=amount; goopLabel.Text=Config.fmtNum(amount)
	TweenService:Create(goopPill, TweenInfo.new(0.1,Enum.EasingStyle.Back),
		{Size=UDim2.fromOffset(228,56)}):Play()
	task.delay(0.13, function()
		TweenService:Create(goopPill, TweenInfo.new(0.15), {Size=UDim2.fromOffset(210,50)}):Play()
	end)
end)

Remotes.RollResult.OnClientEvent:Connect(function(fullPetId, isAuto, wasAutoSold)
	if isAuto then
		-- Auto-roll: just a quick toast, no roulette
		local p = resolvePet(fullPetId)
		if p then showToast((p.isShiny and "✨ " or "").."Auto: "..p.name, p.labelColor) end
	else
		showPopup(fullPetId, wasAutoSold)
	end
end)

Remotes.UpdateEquipped.OnClientEvent:Connect(function(equipped)
	stats.equipped=equipped
	for slot=1,5 do
		local pId=equipped[slot]; buildPetModel(slot, pId and resolvePet(pId) or nil)
	end
	if backpackModal.Visible then refreshBackpack() end
end)

Remotes.UpdateInventory.OnClientEvent:Connect(function(inv)
	inventory = inv or {}
	if backpackModal.Visible then refreshBackpack() end
end)

-- Pet HP / downed status (slot → { hp, max, reviveIn })
Remotes.PetStatus.OnClientEvent:Connect(function(map)
	if type(map) ~= "table" then return end
	for slot, info in pairs(map) do
		local f = followers[slot]
		if f and type(info) == "table" then
			local reviveIn = info.reviveIn or 0
			if reviveIn > 0 then
				f.reviveAt = tick() + reviveIn
				if f.hpBar then f.hpBar.Enabled = false end
				if not f.downed then
					f.downed = true
					for _, p in ipairs(f.model:GetDescendants()) do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end
					local bb = Instance.new("BillboardGui")
					bb.Name = "DownTimer"; bb.Size = UDim2.fromOffset(120, 26)
					bb.StudsOffset = Vector3.new(0, 1.8, 0); bb.AlwaysOnTop = true
					bb.Adornee = f.body; bb.Parent = f.body
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.new(1,0,1,0); tl.BackgroundTransparency = 1
					tl.Text = "💤 " .. reviveIn .. "s"; tl.TextColor3 = Color3.fromRGB(255,120,120)
					tl.Font = Enum.Font.GothamBold; tl.TextSize = 14
					tl.TextStrokeTransparency = 0.3; tl.Parent = bb
					f.downTimer = tl
				end
			else
				if f.downed and f.pet then
					buildPetModel(slot, f.pet)   -- rebuild fresh (clears the downed look)
					f = followers[slot]
				end
				-- Update the health bar fill + colour.
				if f and f.hpFill and info.max and info.max > 0 then
					local pct = math.clamp(info.hp / info.max, 0, 1)
					f.hpFill.Size = UDim2.new(pct, 0, 1, 0)
					f.hpFill.BackgroundColor3 = (pct > 0.5) and Color3.fromRGB(80,220,70)
						or (pct > 0.25) and Color3.fromRGB(240,200,50)
						or Color3.fromRGB(225,60,60)
					if f.hpBar then f.hpBar.Enabled = true end
				end
			end
		end
	end
end)

-- A slime hits one of my pets: flash the pet red + a quick projectile.
Remotes.EnemyAttack.OnClientEvent:Connect(function(enemyName, slot)
	local f = followers[slot]
	if not f or f.downed or not f.body then return end
	local body = f.body
	local orig = body.Color
	body.Color = Color3.fromRGB(255, 70, 70)
	task.delay(0.18, function()
		if body and body.Parent then body.Color = orig end
	end)
	local enemy = workspace:FindFirstChild(enemyName)
	if enemy then
		local proj = Instance.new("Part")
		proj.Shape = Enum.PartType.Ball; proj.Size = Vector3.new(1.3,1.3,1.3)
		proj.Color = enemy.Color; proj.Material = Enum.Material.Neon
		proj.Anchored = true; proj.CanCollide = false; proj.CastShadow = false
		proj.CFrame = CFrame.new(enemy.Position); proj.Parent = workspace
		TweenService:Create(proj, TweenInfo.new(0.16, Enum.EasingStyle.Quad),
			{ CFrame = CFrame.new(body.Position), Size = Vector3.new(0.3,0.3,0.3) }):Play()
		game:GetService("Debris"):AddItem(proj, 0.3)
	end
end)

-- ─── PET ATTACK — render local projectile visual ──────────────────────────────
local Debris = game:GetService("Debris")
Remotes.PetAttack.OnClientEvent:Connect(function(_attacker, _slot, enemyName, abilityId, fromPos, toPos)
	local abilDef = nil
	for _, p in ipairs(Config.PETS) do
		if p.ability.id == abilityId then abilDef = p.ability; break end
	end
	if not abilDef then return end

	local projCol = abilDef.projectileColor
	local projSz  = abilDef.projectileSize * 2.2

	-- Muzzle flash
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size  = Vector3.new(projSz*1.5, projSz*1.5, projSz*1.5)
	flash.Color = projCol; flash.Material = Enum.Material.Neon
	flash.Anchored=true; flash.CanCollide=false; flash.CastShadow=false
	flash.CFrame = CFrame.new(fromPos); flash.Parent = workspace
	Debris:AddItem(flash, 0.07)

	-- Projectile part
	local proj = Instance.new("Part")
	if abilDef.shape == "bolt" then
		proj.Size = Vector3.new(projSz*0.38, projSz*0.38, projSz*3.0)
	elseif abilDef.shape == "shard" then
		proj.Size = Vector3.new(projSz*0.48, projSz*1.9,  projSz*0.48)
	else
		proj.Shape = Enum.PartType.Ball
		proj.Size  = Vector3.new(projSz, projSz, projSz)
	end
	proj.Color    = projCol; proj.Material = Enum.Material.Neon
	proj.Anchored = true; proj.CanCollide = false; proj.CastShadow = false
	proj.CFrame   = CFrame.new(fromPos, toPos); proj.Parent = workspace

	local pl = Instance.new("PointLight")
	pl.Color = projCol; pl.Range = 7; pl.Brightness = 2; pl.Parent = proj

	local dir      = (toPos - fromPos).Unit
	local speed    = Config.PROJECTILE_SPEED
	local maxDist  = Config.PROJECTILE_MAX_DIST
	local traveled = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		traveled = traveled + speed * dt
		if traveled >= maxDist or not proj.Parent then
			conn:Disconnect()
			if proj.Parent then
				proj.Size = proj.Size * 1.9
				Debris:AddItem(proj, 0.05)
			end
			return
		end
		local np = fromPos + dir * traveled
		if abilDef.shape == "ball" then
			proj.CFrame = CFrame.new(np)
		else
			proj.CFrame = CFrame.new(np, np + dir)
		end
	end)
	Debris:AddItem(proj, 5)
end)

-- ─── ENEMY DAMAGED — nothing extra needed (server updates billboard directly) ──
Remotes.EnemyDamaged.OnClientEvent:Connect(function() end)

-- ─── COMBO KILL — flash a big combo counter on screen ────────────────────────
Remotes.ComboKill.OnClientEvent:Connect(function(count)
	local lbl = Instance.new("TextLabel")
	lbl.Size              = UDim2.fromOffset(300, 60)
	lbl.AnchorPoint       = Vector2.new(0.5, 0.5)
	lbl.Position          = UDim2.new(0.5, 0, 0.38, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text              = "⚡ COMBO  ×" .. count
	lbl.TextColor3        = C.GOLD
	lbl.TextSize          = count >= 5 and 48 or count >= 3 and 40 or 34
	lbl.TextStrokeTransparency = 0.25
	lbl.ZIndex            = 85
	setFont(lbl, Enum.FontWeight.Heavy)
	lbl.Parent = gui

	TweenService:Create(lbl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size=UDim2.fromOffset(360, 72)}):Play()
	task.delay(0.9, function()
		TweenService:Create(lbl, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{TextTransparency=1, TextStrokeTransparency=1, Position=UDim2.new(0.5,0,0.30,0)}):Play()
		task.delay(0.35, function() lbl:Destroy() end)
	end)
end)

Remotes.FloatText.OnClientEvent:Connect(function(txt) floatText(txt, C.GOLD) end)

Remotes.NotifyPurchase.OnClientEvent:Connect(function(txt, kind)
	local col = kind=="pass" and C.GOLD or kind=="luck" and C.GREEN or C.ROBUXC
	showToast(txt, col)
	floatText(txt, col)
end)

Remotes.UpdateLeaderboard.OnClientEvent:Connect(function(rows, localName)
	leaderboardRows = rows
	refreshLeaderboard()
	-- Update zone unlock button
	local nextZone = nil
	for _, z in ipairs(Config.ZONES) do
		if z.unlockCost > 0 and not unlockedZoneNames[z.name] then
			nextZone = z; break
		end
	end
	if nextZone then
		pendingUnlockZone = nextZone.name
		local canAfford = (stats.coins or 0) >= nextZone.unlockCost
		zoneBtn.Text = (canAfford and "🔓" or "🔒").."  UNLOCK "..
			string.upper(nextZone.name).."  —  "..Config.fmtNum(nextZone.unlockCost)
		zoneBtn.BackgroundColor3 = canAfford and Color3.fromRGB(30,140,55) or Color3.fromRGB(80,35,35)
		zoneBtn.Visible = true
	else
		pendingUnlockZone = nil
		zoneBtn.Text = "✅  ALL ZONES OPEN"
		zoneBtn.BackgroundColor3 = Color3.fromRGB(30,95,30)
	end
end)

-- Apply this player's unlocked-zone set locally: open their gates (drop
-- CanCollide + hide), keep locked ones solid, and refresh the HUD unlock button.
-- CanCollide is set client-side so it only affects THIS player (per-player gates).
local function applyGates()
	local set = (stats and stats.unlockedZones) or {}
	unlockedZoneNames = {}
	for k, v in pairs(set) do if v then unlockedZoneNames[k] = true end end

	local nextZone = nil
	for _, z in ipairs(Config.ZONES) do
		local unlocked = (z.unlockCost == 0) or (set[z.name] == true)
		if (not unlocked) and z.unlockCost > 0 and not nextZone then nextZone = z end
		local gf = workspace:FindFirstChild("Gate_" .. z.name)
		if gf then
			for _, d in ipairs(gf:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide   = not unlocked
					d.Transparency = unlocked and 1 or 0
				elseif d:IsA("SurfaceGui") then
					d.Enabled = not unlocked
				elseif d:IsA("ProximityPrompt") then
					d.Enabled = not unlocked
				end
			end
		end
	end

	if nextZone then
		pendingUnlockZone = nextZone.name
		local canAfford = ((stats and stats.coins) or 0) >= nextZone.unlockCost
		zoneBtn.Text = (canAfford and "🔓" or "🔒").."  UNLOCK "..
			string.upper(nextZone.name).."  —  "..Config.fmtNum(nextZone.unlockCost)
		zoneBtn.BackgroundColor3 = canAfford and Color3.fromRGB(30,140,55) or Color3.fromRGB(80,35,35)
	else
		pendingUnlockZone = nil
		zoneBtn.Text = "✅  ALL ZONES OPEN"
		zoneBtn.BackgroundColor3 = Color3.fromRGB(30,95,30)
	end
end

Remotes.UpdateStats.OnClientEvent:Connect(function(s)
	-- Dismiss loading screen on first stats packet
	if not loadingDone then
		local fn = _G.__slimeDiceLoadingDismiss
		if fn then fn() end
	end

	stats=s; coins=s.coins
	applyGates()   -- reflect this player's saved zone unlocks (gates + HUD)
	if s.inventory then inventory = s.inventory end
	goopLabel.Text=Config.fmtNum(s.coins)
	rebirthCountLbl.Text=tostring(s.rebirths or 0)

	-- Rebirth badge
	local reb=s.rebirths or 0
	rebBadgeBg.Visible=reb>0; rebBadgeLbl.Text=tostring(reb)

	-- Stat pills
	local cd=s.rollCooldown or Config.ROLL_COOLDOWN
	cdLblStat.Text=string.format("%.1fs  roll", cd)
	luckLbl.Text=string.format("%.2f×  luck", s.luckMult or 1)

	-- DPS estimate: sum per-pet damage/fireRate with level bonus
	local equipped=s.equipped or {}
	local petLvls=s.petLevels or {}
	local totalDps=0
	for _,pId in pairs(equipped) do
		local rp=resolvePet(pId)
		local pd=rp and PET_MAP[rp.baseId]
		if pd then
			local lvl=petLvls[pId] or 1
			local bonus=1+(lvl-1)*Config.PET_LEVEL_BONUS
			totalDps=totalDps+pd.ability.damage*bonus/pd.ability.fireRate
		end
	end
	incomeLbl.Text=string.format("%.0f DPS", totalDps)

	-- Rebirth modal (refresh if open; data is always fresh on open via toggleModal)
	if rebirthModal.Visible then refreshRebirth() end

	-- Upgrade badge (how many can you afford)
	local affordCount=0
	local cur=s.upgrades or {}
	for _,uDef in ipairs(Config.UPGRADES) do
		local lvl=cur[uDef.id] or 0
		if lvl<#uDef.levels and (s.coins or 0)>=uDef.levels[lvl+1].cost then
			affordCount=affordCount+1
		end
	end
	upBadgeBg.Visible=affordCount>0; upBadgeLbl.Text=tostring(affordCount)

	if upgradesModal.Visible then refreshUpgrades() end
	if indexModal.Visible    then refreshIndex()    end
	if backpackModal.Visible then refreshBackpack()  end
	if levelModal.Visible    then refreshLevel()    end
end)

-- ─── HEARTBEAT ────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	floatT=floatT+dt

	-- Roll cooldown
	if onCooldown then
		local cd=stats.rollCooldown or Config.ROLL_COOLDOWN
		local rem=cd-(tick()-cooldownStart)
		if rem<=0 then
			onCooldown=false
			TweenService:Create(rollBtn,TweenInfo.new(0.18),{BackgroundColor3=ROLL_READY}):Play()
			rollBtn.Text="🎲"; cdOverlay.Text=""
			-- Restore in-card spin button when ready
			if rouletteGui.Enabled and not rouletteSpinning then
				rSpinInsideBtn.Text = "🎲  Roll Again"
				TweenService:Create(rSpinInsideBtn,TweenInfo.new(0.18),{BackgroundColor3=C.PURPLE}):Play()
			end
		else
			cdOverlay.Text=string.format("%.1f", rem)
			-- Show countdown on in-card button too
			if rouletteGui.Enabled and not rouletteSpinning and rSpinInsideBtn.Visible then
				rSpinInsideBtn.Text = "⏳  "..string.format("%.1fs", rem)
				TweenService:Create(rSpinInsideBtn,TweenInfo.new(0.1),{BackgroundColor3=C.PURPLE2}):Play()
			end
		end
	end

	-- Pet follow-behind formation — all face the same way as the player.
	-- V-shape: close pair behind player, wider pair further back, one centre.
	-- Offsets are in HumanoidRootPart local space: +X=right, +Z=backward for rigs.
	local FORM = {
		Vector3.new( 3.5, 0,  4.5),
		Vector3.new(-3.5, 0,  4.5),
		Vector3.new( 6.5, 0,  8.0),
		Vector3.new(-6.5, 0,  8.0),
		Vector3.new( 0.0, 0,  6.5),
	}
	local char=player.Character; if not char then return end
	local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local t=tick()
	for slot,f in pairs(followers) do
		if f.downed and f.downTimer then
			f.downTimer.Text = "💤 " .. math.max(0, math.ceil((f.reviveAt or 0) - t)) .. "s"
		end
		local idx   = ((slot-1) % #FORM) + 1
		local off   = FORM[idx]
		local phase = (idx-1)*(math.pi*2/5)   -- used by per-pet wing/ear/feet anim
		local bobY  = math.sin(t*2.4 + phase)*0.38
		local tilt  = math.sin(t*2.4 + phase)*0.09
		-- Convert local offset to world space
		local worldOff = hrp.CFrame:VectorToWorldSpace(off)
		local target = hrp.Position + worldOff + Vector3.new(0, Config.PET_ORBIT_HEIGHT+bobY, 0)
		local alpha  = 1-math.exp(-8*dt)
		local newPos = f.body.Position:Lerp(target, alpha)
		-- Face same direction as player
		local look  = hrp.CFrame.LookVector
		local cf    = CFrame.new(newPos, newPos+look)*CFrame.Angles(tilt,0,0)
		local sz = f.sz
		f.body.CFrame=cf; f.glow.CFrame=cf
		-- Front face is -Z. Big glossy eyes sit on the front of the cube/ball.
		local fr = -sz*0.44
		f.e1.CFrame=cf*CFrame.new(-sz*0.22, sz*0.10, fr)
		f.e2.CFrame=cf*CFrame.new( sz*0.22, sz*0.10, fr)
		f.p1.CFrame=cf*CFrame.new(-sz*0.21, sz*0.08, fr-sz*0.10)
		f.p2.CFrame=cf*CFrame.new( sz*0.21, sz*0.08, fr-sz*0.10)
		if f.sh1 then f.sh1.CFrame=cf*CFrame.new(-sz*0.27, sz*0.16, fr-sz*0.13) end
		if f.sh2 then f.sh2.CFrame=cf*CFrame.new( sz*0.17, sz*0.16, fr-sz*0.13) end
		-- Little feet do a walking shuffle
		local step = math.sin(t*5+phase)*sz*0.06
		if f.foot1 then f.foot1.CFrame=cf*CFrame.new(-sz*0.22, -sz*0.50+math.max(0, step), -sz*0.14) end
		if f.foot2 then f.foot2.CFrame=cf*CFrame.new( sz*0.22, -sz*0.50+math.max(0,-step), -sz*0.14) end
		-- Pet-specific extras
		local pet=f.pet; local x=f.extras
		if x and pet then
			if x.shinyStar then x.shinyStar.CFrame = cf*CFrame.new(0, sz*0.66, 0)*CFrame.Angles(0, t*3, 0) end
			if pet.baseId=="blob_slime" then
				if x.smile then x.smile.CFrame=cf*CFrame.new(0,-sz*0.12,fr) end
				if x.drip  then x.drip.CFrame =cf*CFrame.new(sz*0.30,sz*0.30,fr+sz*0.12) end
				if x.shine then x.shine.CFrame=cf*CFrame.new(-sz*0.24,sz*0.26,fr+sz*0.04) end
			elseif pet.baseId=="fire_pup" then
				if x.snout then x.snout.CFrame=cf*CFrame.new(0,-sz*0.06,fr-sz*0.06) end
				if x.nose  then x.nose.CFrame =cf*CFrame.new(0,-sz*0.02,fr-sz*0.18) end
				if x.ear1  then x.ear1.CFrame =cf*CFrame.new(-sz*0.44,sz*0.28,-sz*0.04)*CFrame.Angles(0,0, 0.5) end
				if x.ear2  then x.ear2.CFrame =cf*CFrame.new( sz*0.44,sz*0.28,-sz*0.04)*CFrame.Angles(0,0,-0.5) end
				if x.tail  then x.tail.CFrame =cf*CFrame.new(0,sz*0.06,sz*0.50)*CFrame.Angles(-0.6,0,0) end
			elseif pet.baseId=="flame_fox" then
				if x.ear1  then x.ear1.CFrame =cf*CFrame.new(-sz*0.26,sz*0.52,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,-0.12) end
				if x.ear2  then x.ear2.CFrame =cf*CFrame.new( sz*0.26,sz*0.52,-sz*0.02)*CFrame.Angles(0, math.pi/2,0)*CFrame.Angles(0,0, 0.12) end
				if x.iear1 then x.iear1.CFrame=cf*CFrame.new(-sz*0.26,sz*0.50,-sz*0.05)*CFrame.Angles(0,-math.pi/2,0) end
				if x.iear2 then x.iear2.CFrame=cf*CFrame.new( sz*0.26,sz*0.50,-sz*0.05)*CFrame.Angles(0, math.pi/2,0) end
				if x.snout then x.snout.CFrame=cf*CFrame.new(0,-sz*0.06,fr-sz*0.04) end
				if x.nose  then x.nose.CFrame =cf*CFrame.new(0,-sz*0.02,fr-sz*0.16) end
				if x.tailB then x.tailB.CFrame=cf*CFrame.new(0,-sz*0.04,sz*0.46) end
				if x.tailT then x.tailT.CFrame=cf*CFrame.new(0, sz*0.12,sz*0.62) end
			elseif pet.baseId=="shadow_cat" then
				if x.ear1  then x.ear1.CFrame =cf*CFrame.new(-sz*0.26,sz*0.50,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,-0.10) end
				if x.ear2  then x.ear2.CFrame =cf*CFrame.new( sz*0.26,sz*0.50,-sz*0.02)*CFrame.Angles(0, math.pi/2,0)*CFrame.Angles(0,0, 0.10) end
				if x.iear1 then x.iear1.CFrame=cf*CFrame.new(-sz*0.26,sz*0.48,-sz*0.05)*CFrame.Angles(0,-math.pi/2,0) end
				if x.iear2 then x.iear2.CFrame=cf*CFrame.new( sz*0.26,sz*0.48,-sz*0.05)*CFrame.Angles(0, math.pi/2,0) end
				if x.nose  then x.nose.CFrame =cf*CFrame.new(0,-sz*0.02,fr-sz*0.04) end
				if x.smile then x.smile.CFrame=cf*CFrame.new(0,-sz*0.13,fr) end
				if x.wh1   then x.wh1.CFrame  =cf*CFrame.new(-sz*0.40,-sz*0.02,fr+sz*0.02)*CFrame.Angles(0,0, 0.12) end
				if x.wh2   then x.wh2.CFrame  =cf*CFrame.new(-sz*0.40,-sz*0.11,fr+sz*0.02)*CFrame.Angles(0,0,-0.12) end
				if x.wh3   then x.wh3.CFrame  =cf*CFrame.new( sz*0.40,-sz*0.02,fr+sz*0.02)*CFrame.Angles(0,0,-0.12) end
				if x.wh4   then x.wh4.CFrame  =cf*CFrame.new( sz*0.40,-sz*0.11,fr+sz*0.02)*CFrame.Angles(0,0, 0.12) end
				if x.tail  then x.tail.CFrame =cf*CFrame.new(0,sz*0.06,sz*0.46)*CFrame.Angles(-0.9,0,0) end
			elseif pet.baseId=="frost_bunny" then
				local ew = math.sin(t*3+phase)*0.06
				if x.ear1  then x.ear1.CFrame =cf*CFrame.new(-sz*0.16,sz*0.62,-sz*0.02)*CFrame.Angles(0,0, 0.10+ew) end
				if x.ear2  then x.ear2.CFrame =cf*CFrame.new( sz*0.16,sz*0.62,-sz*0.02)*CFrame.Angles(0,0,-0.10-ew) end
				if x.iear1 then x.iear1.CFrame=cf*CFrame.new(-sz*0.16,sz*0.62,-sz*0.07)*CFrame.Angles(0,0, 0.10+ew) end
				if x.iear2 then x.iear2.CFrame=cf*CFrame.new( sz*0.16,sz*0.62,-sz*0.07)*CFrame.Angles(0,0,-0.10-ew) end
				if x.cheek1 then x.cheek1.CFrame=cf*CFrame.new(-sz*0.34,-sz*0.04,fr+sz*0.07) end
				if x.cheek2 then x.cheek2.CFrame=cf*CFrame.new( sz*0.34,-sz*0.04,fr+sz*0.07) end
				if x.nose  then x.nose.CFrame =cf*CFrame.new(0,-sz*0.02,fr-sz*0.04) end
				if x.smile then x.smile.CFrame=cf*CFrame.new(0,-sz*0.13,fr) end
				if x.tail  then x.tail.CFrame =cf*CFrame.new(0,-sz*0.10,sz*0.46) end
			elseif pet.baseId=="mini_dragon" then
				if x.belly then x.belly.CFrame=cf*CFrame.new(0,-sz*0.10,fr+sz*0.02) end
				if x.smile then x.smile.CFrame=cf*CFrame.new(0,-sz*0.13,fr) end
				if x.horn1 then x.horn1.CFrame=cf*CFrame.new(-sz*0.28,sz*0.46,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,-0.18) end
				if x.horn2 then x.horn2.CFrame=cf*CFrame.new( sz*0.28,sz*0.46,-sz*0.02)*CFrame.Angles(0, math.pi/2,0)*CFrame.Angles(0,0,-0.18) end
				local wf=math.sin(t*6.5+phase)*0.5
				if x.wing1 then x.wing1.CFrame=cf*CFrame.new(-sz*0.50,sz*0.10,sz*0.20)*CFrame.Angles(0, 0.5, wf) end
				if x.wing2 then x.wing2.CFrame=cf*CFrame.new( sz*0.50,sz*0.10,sz*0.20)*CFrame.Angles(0,-0.5,-wf) end
				if x.fang1 then x.fang1.CFrame=cf*CFrame.new(-sz*0.06,-sz*0.17,fr+sz*0.01)*CFrame.Angles(math.pi,0,0) end
				if x.fang2 then x.fang2.CFrame=cf*CFrame.new( sz*0.06,-sz*0.17,fr+sz*0.01)*CFrame.Angles(math.pi,0,0) end
				if x.tail  then x.tail.CFrame =cf*CFrame.new(0,-sz*0.10,sz*0.50)*CFrame.Angles(-0.5,0,0) end
				if x.tailtip then x.tailtip.CFrame=cf*CFrame.new(0,sz*0.02,sz*0.74)*CFrame.Angles(0,math.pi/2,0)*CFrame.Angles(0,0,-0.5) end
			elseif pet.baseId=="storm_hawk" then
				local wf=math.sin(t*9+phase)*0.55
				if x.wing1 then x.wing1.CFrame=cf*CFrame.new(-sz*0.64,sz*0.06,sz*0.05)*CFrame.Angles(0,0,-(wf+0.30)) end
				if x.wing2 then x.wing2.CFrame=cf*CFrame.new( sz*0.64,sz*0.06,sz*0.05)*CFrame.Angles(0,0,  wf+0.30)  end
				if x.wtip1 then x.wtip1.CFrame=cf*CFrame.new(-sz*0.98,sz*0.06,sz*0.05)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,-(wf+0.30)) end
				if x.wtip2 then x.wtip2.CFrame=cf*CFrame.new( sz*0.98,sz*0.06,sz*0.05)*CFrame.Angles(0, math.pi/2,0)*CFrame.Angles(0,0,  wf+0.30)  end
				if x.beak  then x.beak.CFrame =cf*CFrame.new(0,-sz*0.04,fr-sz*0.04)*CFrame.Angles(math.pi/2,0,0) end
				if x.crest1 then x.crest1.CFrame=cf*CFrame.new(0,sz*0.52,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0) end
				if x.crest2 then x.crest2.CFrame=cf*CFrame.new(0,sz*0.50,sz*0.12)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,0.5) end
				local sp=math.sin(t*12+phase)*0.22
				if x.spike1 then x.spike1.CFrame=cf*CFrame.new(-sz*0.42,sz*0.30,0)*CFrame.Angles(0,math.pi/2,0)*CFrame.Angles(0,0,-(1.0+sp)) end
				if x.spike2 then x.spike2.CFrame=cf*CFrame.new( sz*0.42,sz*0.30,0)*CFrame.Angles(0,math.pi/2,0)*CFrame.Angles(0,0, (1.0+sp)) end
				if x.bolt  then x.bolt.CFrame =cf*CFrame.new(0, sz*0.56,0) end
			elseif pet.baseId=="crystal_phoenix" then
				local wf=math.sin(t*5.5+phase)*0.30
				if x.w1a then x.w1a.CFrame=cf*CFrame.new(-sz*0.50,sz*0.22,sz*0.05)*CFrame.Angles(0,0,-(wf+0.10)) end
				if x.w1b then x.w1b.CFrame=cf*CFrame.new(-sz*0.58,sz*0.06,sz*0.05)*CFrame.Angles(0,0,-(wf+0.30)) end
				if x.w1c then x.w1c.CFrame=cf*CFrame.new(-sz*0.50,-sz*0.10,sz*0.05)*CFrame.Angles(0,0,-(wf+0.52)) end
				if x.w2a then x.w2a.CFrame=cf*CFrame.new( sz*0.50,sz*0.22,sz*0.05)*CFrame.Angles(0,0, (wf+0.10)) end
				if x.w2b then x.w2b.CFrame=cf*CFrame.new( sz*0.58,sz*0.06,sz*0.05)*CFrame.Angles(0,0, (wf+0.30)) end
				if x.w2c then x.w2c.CFrame=cf*CFrame.new( sz*0.50,-sz*0.10,sz*0.05)*CFrame.Angles(0,0, (wf+0.52)) end
				if x.gem   then x.gem.CFrame  =cf*CFrame.new(0,-sz*0.04,fr+sz*0.02) end
				if x.crest1 then x.crest1.CFrame=cf*CFrame.new(-sz*0.11,sz*0.52,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,-0.30) end
				if x.crest2 then x.crest2.CFrame=cf*CFrame.new(0,sz*0.56,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0) end
				if x.crest3 then x.crest3.CFrame=cf*CFrame.new( sz*0.11,sz*0.52,-sz*0.02)*CFrame.Angles(0,-math.pi/2,0)*CFrame.Angles(0,0,0.30) end
				if x.tail1 then x.tail1.CFrame=cf*CFrame.new(-sz*0.12,-sz*0.30,sz*0.48)*CFrame.Angles(-0.6,0,-0.25) end
				if x.tail2 then x.tail2.CFrame=cf*CFrame.new(0,-sz*0.34,sz*0.50)*CFrame.Angles(-0.7,0,0) end
				if x.tail3 then x.tail3.CFrame=cf*CFrame.new( sz*0.12,-sz*0.30,sz*0.48)*CFrame.Angles(-0.6,0,0.25) end
			elseif pet.baseId=="chicken" then
				if x.comb1 then x.comb1.CFrame=cf*CFrame.new(-sz*0.10,sz*0.52,-sz*0.02) end
				if x.comb2 then x.comb2.CFrame=cf*CFrame.new( 0,      sz*0.55,-sz*0.02) end
				if x.comb3 then x.comb3.CFrame=cf*CFrame.new( sz*0.10,sz*0.52,-sz*0.02) end
				if x.beak  then x.beak.CFrame =cf*CFrame.new(0,-sz*0.06,fr-sz*0.02)*CFrame.Angles(math.pi/2,0,0) end
				if x.wattle then x.wattle.CFrame=cf*CFrame.new(0,-sz*0.16,fr-sz*0.02) end
				local wf=math.sin(t*7+phase)*0.25
				if x.wing1 then x.wing1.CFrame=cf*CFrame.new(-sz*0.42,0,sz*0.04)*CFrame.Angles(0,0,wf) end
				if x.wing2 then x.wing2.CFrame=cf*CFrame.new( sz*0.42,0,sz*0.04)*CFrame.Angles(0,0,-wf) end
			elseif pet.baseId=="emperor_snake" then
				if x.nose then x.nose.CFrame=cf*CFrame.new(0,-sz*0.06,fr) end
				local tw=math.sin(t*8+phase)*0.10
				if x.tongue1 then x.tongue1.CFrame=cf*CFrame.new(-sz*0.04,-sz*0.20,fr-sz*0.02)*CFrame.Angles(0.5,0, 0.25+tw) end
				if x.tongue2 then x.tongue2.CFrame=cf*CFrame.new( sz*0.04,-sz*0.20,fr-sz*0.02)*CFrame.Angles(0.5,0,-0.25-tw) end
				if x.comb1 then x.comb1.CFrame=cf*CFrame.new(0,sz*0.56,-sz*0.02) end
				if x.chest then x.chest.CFrame=cf*CFrame.new(0,-sz*0.06,fr+sz*0.02) end
				-- spinning gold gear halo
				if x.halo then
					for k, seg in ipairs(x.halo) do
						local a = (k/#x.halo)*math.pi*2 + t*1.2
						seg.CFrame = cf * CFrame.new(math.cos(a)*sz*0.42, sz*0.66, math.sin(a)*sz*0.42)
							* CFrame.Angles(0, -a, 0)
					end
				end
				local wf=math.sin(t*5+phase)*0.3
				if x.w1a then x.w1a.CFrame=cf*CFrame.new(-sz*0.50,sz*0.16,sz*0.05)*CFrame.Angles(0,0,-(wf+0.12)) end
				if x.w1b then x.w1b.CFrame=cf*CFrame.new(-sz*0.58,-sz*0.02,sz*0.05)*CFrame.Angles(0,0,-(wf+0.34)) end
				if x.w2a then x.w2a.CFrame=cf*CFrame.new( sz*0.50,sz*0.16,sz*0.05)*CFrame.Angles(0,0,(wf+0.12)) end
				if x.w2b then x.w2b.CFrame=cf*CFrame.new( sz*0.58,-sz*0.02,sz*0.05)*CFrame.Angles(0,0,(wf+0.34)) end
			end
		end
	end
end)

-- ─── DAILY DATA listener ─────────────────────────────────────────────────────
Remotes.DailyData.OnClientEvent:Connect(function(info)
	dailyInfo = info
	wheelSpinReady  = info.spinReady  == true
	dailyClaimReady = info.dailyReady == true
	-- Badge: show if anything is ready
	local anyReady = wheelSpinReady or dailyClaimReady
	dailyBadgeBg.Visible  = anyReady
	dailyBadgeLbl.Text    = anyReady and "!" or ""
	-- Refresh open modals
	if wheelModal.Visible then refreshWheel() end
	if dailyModal.Visible then refreshDaily() end
end)

-- ─── WHEEL RESULT listener ────────────────────────────────────────────────────
Remotes.WheelResult.OnClientEvent:Connect(function(prizeIdx, label, amount)
	-- Spin animation: tween Rotation to land on winning segment
	local N       = #Config.WHEEL_PRIZES
	local segDeg  = 360 / N
	-- Pointer is fixed at the top. Tile i starts at clockwise angle (i-1)*segDeg,
	-- so to bring tile prizeIdx UP to the pointer we must rotate by the NEGATIVE
	-- of that angle (i.e. 360 - angle). (The old code used +angle, which landed a
	-- mirrored segment under the pointer — hence the mismatch with the result.)
	local landAngle = (360 - (prizeIdx - 1) * segDeg) % 360
	local startRot  = wheelRotFrame.Rotation
	-- Spin 4 full revolutions, then settle so the winning segment is at the top.
	local targetRot = startRot + (1440 - (startRot % 360)) + landAngle

	local ti = TweenInfo.new(3.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(wheelRotFrame, ti, {Rotation = targetRot}):Play()
	playSpinTicks(3.4)   -- classic spin sound

	task.delay(3.6, function()
		wheelSpinning = false
		local col = Config.WHEEL_PRIZES[prizeIdx] and Config.WHEEL_PRIZES[prizeIdx].color or C.GOLD
		wheelResultLbl.Text      = "🎉  You won: " .. label .. (amount>0 and (" ("..amount..")") or "")
		wheelResultLbl.TextColor3= col
		showToast("🎡  Won: "..label, col)
		refreshWheel()
	end)
end)

-- ─── Zone unlock notification ─────────────────────────────────────────────────
Remotes.ZoneUnlocked.OnClientEvent:Connect(function(zoneName)
	if stats then
		stats.unlockedZones = stats.unlockedZones or {}
		stats.unlockedZones[zoneName] = true
	end
	applyGates()   -- opens this gate for me + refreshes the HUD button
	showToast("🔓  "..zoneName.." Zone Unlocked!", Color3.fromRGB(50,210,80))
end)

-- Rebirth re-locks all of this player's stage gates.
Remotes.ZonesReset.OnClientEvent:Connect(function()
	if stats then stats.unlockedZones = {} end
	applyGates()
	showToast("🔄  Rebirth!  Stages reset.", Color3.fromRGB(180,100,255))
end)

-- Seed initial leaderboard display
refreshLeaderboard()
refreshIndex()

print("[RollClient] Ready.")

