-- MusicPlayer.client.luau (LocalScript)
-- Shuffled background-music playlist with a small mute / skip control.
-- Tracks + volume come from Config.MUSIC_TRACKS / Config.MUSIC_VOLUME.
-- Self-contained (own ScreenGui) so it never touches the main HUD's locals.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Config  = require(Shared:WaitForChild("Config"))

local TRACKS  = Config.MUSIC_TRACKS or {}
local VOLUME  = Config.MUSIC_VOLUME or 0.35

if #TRACKS == 0 then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Playlist (shuffled) ──────────────────────────────────────────────────────
local order = {}
for i = 1, #TRACKS do order[i] = i end
for i = #order, 2, -1 do
	local j = math.random(1, i)
	order[i], order[j] = order[j], order[i]
end

local sound = Instance.new("Sound")
sound.Name       = "BackgroundMusic"
sound.Volume     = VOLUME
sound.Looped     = false
sound.Parent     = SoundService

local muted   = false
local idx     = 0
local playGen = 0   -- guards against overlapping play loops after a skip
local dead    = {}  -- order-position → true once a track fails to load (a "dud")

local function liveCount()
	local n = 0
	for i = 1, #order do if not dead[i] then n += 1 end end
	return n
end

local function playNext()
	if liveCount() == 0 then sound:Stop(); return end   -- nothing playable
	playGen += 1
	local myGen = playGen
	-- Advance to the next track that hasn't been marked a dud, so SKIP only
	-- ever lands on songs that actually play (it just toggles the good ones).
	repeat idx = idx % #order + 1 until not dead[idx]
	sound:Stop()
	sound.SoundId = "rbxassetid://" .. TRACKS[order[idx]]
	sound.TimePosition = 0
	if not muted then sound:Play() end

	-- If it doesn't load quickly it's a privated/invalid id — mark it dead so
	-- it's never chosen again, and move straight on.
	task.spawn(function()
		local waited = 0
		while (not sound.IsLoaded) and waited < 3 and myGen == playGen do
			task.wait(0.2); waited += 0.2
		end
		if myGen ~= playGen then return end
		if not sound.IsLoaded then
			dead[idx] = true
			playNext()
		end
	end)
end

-- Auto-advance when a track finishes.
sound.Ended:Connect(function()
	playNext()
end)

-- ─── Mute / skip control ──────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "MusicControls"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 5
gui.Parent         = playerGui

local function makeBtn(text, xFromRight)
	local b = Instance.new("TextButton")
	b.Size                   = UDim2.fromOffset(34, 34)
	-- Bottom-right corner (clear of the HUD stat pills on the bottom-left).
	b.Position               = UDim2.new(1, xFromRight, 1, -12)
	b.AnchorPoint            = Vector2.new(1, 1)
	b.BackgroundColor3       = Color3.fromRGB(24, 26, 44)
	b.BackgroundTransparency = 0.15
	b.Text                   = text
	b.TextColor3             = Color3.fromRGB(235, 235, 245)
	b.TextSize               = 16
	b.Font                   = Enum.Font.GothamBold
	b.AutoButtonColor        = true
	b.Parent                 = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = b
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(90, 95, 130)
	s.Thickness = 1.2; s.Transparency = 0.4; s.Parent = b
	return b
end

local skipBtn = makeBtn("⏭", -12)
local muteBtn = makeBtn("🔊", -52)

muteBtn.MouseButton1Click:Connect(function()
	muted = not muted
	muteBtn.Text = muted and "🔇" or "🔊"
	if muted then
		sound:Pause()
	else
		sound:Resume()
		if not sound.IsPlaying then playNext() end
	end
end)

skipBtn.MouseButton1Click:Connect(function()
	playNext()
end)

-- Kick things off.
playNext()

