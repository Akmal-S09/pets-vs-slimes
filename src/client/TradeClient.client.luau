-- TradeClient.client.luau (LocalScript)
-- Self-contained trading UI (own ScreenGui so it never inflates the main HUD's
-- local count). Talks to TradeHandler.server.luau over the Trade* remotes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Config   = require(Shared:WaitForChild("Config"))
local Remotes  = require(Shared:WaitForChild("Remotes"))
local PetFace  = require(Shared:WaitForChild("PetFace"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Pet resolver ──────────────────────────────────────────────────────────────
local PET_MAP = {}
for _, p in ipairs(Config.PETS) do PET_MAP[p.id] = p end

local function resolve(fullId)
	fullId = (fullId:gsub("#.*$", ""))   -- strip unique "#uid" suffix
	local isShiny   = fullId:sub(1,6) == "shiny:"
	local rest      = isShiny and fullId:sub(7) or fullId
	local isEvolved = rest:sub(1,8) == "evolved:"
	local baseId    = isEvolved and rest:sub(9) or rest
	local base      = PET_MAP[baseId]
	if not base then return { name = "?", color = Color3.new(1,1,1), tag = "" } end
	local name = base.name
	local bodyCol = base.color
	if isEvolved and Config.PET_EVOLUTIONS[baseId] then
		name = Config.PET_EVOLUTIONS[baseId].name
		bodyCol = Config.PET_EVOLUTIONS[baseId].color or bodyCol
	end
	local tag = (isShiny and "✨ " or "") .. (isEvolved and "⭐ " or "")
	return { name = name, color = base.labelColor or Color3.new(1,1,1),
		bodyColor = bodyCol or Color3.new(1,1,1), baseId = baseId, tag = tag }
end

-- ─── Small UI helpers ───────────────────────────────────────────────────────────
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o end
local function stroke(o, col, th, tr)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 1.5
	s.Transparency = tr or 0.4; s.Parent = o; return s
end
local function frame(parent, size, pos, col, tr)
	local f = Instance.new("Frame"); f.Size = size; f.Position = pos
	f.BackgroundColor3 = col; f.BackgroundTransparency = tr or 0; f.BorderSizePixel = 0
	f.Parent = parent; return f
end
local function label(parent, text, size, col, sz, pos)
	local l = Instance.new("TextLabel"); l.Size = sz or UDim2.new(1,0,0,18); l.Position = pos or UDim2.new(0,0,0,0)
	l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = col or Color3.new(1,1,1)
	l.TextSize = size or 14; l.Font = Enum.Font.GothamBold; l.Parent = parent; return l
end
local function button(parent, text, size, pos, bg, fg)
	local b = Instance.new("TextButton"); b.Size = size; b.Position = pos
	b.BackgroundColor3 = bg; b.Text = text; b.TextColor3 = fg or Color3.new(1,1,1)
	b.TextSize = 14; b.Font = Enum.Font.GothamBold; b.BorderSizePixel = 0
	b.AutoButtonColor = true; b.Parent = parent; corner(b, 8); return b
end

local BG    = Color3.fromRGB(18, 20, 34)
local PANEL = Color3.fromRGB(28, 30, 50)
local GREEN = Color3.fromRGB(45, 175, 80)
local RED   = Color3.fromRGB(180, 55, 55)
local DIM   = Color3.fromRGB(150, 155, 180)

-- ─── Root GUI ────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "TradeUI"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 8
gui.Parent         = playerGui

-- Toast
local toast = label(gui, "", 16, Color3.new(1,1,1),
	UDim2.fromOffset(420, 32), UDim2.new(0.5, -210, 0, 70))
toast.AnchorPoint = Vector2.new(0.5, 0); toast.TextStrokeTransparency = 0.4; toast.Visible = false
local function showToast(msg)
	toast.Text = msg; toast.Visible = true
	task.delay(3, function() if toast.Text == msg then toast.Visible = false end end)
end

-- Open button (bottom-right, sitting just above the music controls)
local openBtn = button(gui, "🤝  TRADE", UDim2.fromOffset(118, 34),
	UDim2.new(1, -12, 1, -54), Color3.fromRGB(120, 70, 200))
openBtn.AnchorPoint = Vector2.new(1, 1); stroke(openBtn, Color3.fromRGB(170,110,250), 1.2, 0.3)

-- ─── Player picker ──────────────────────────────────────────────────────────
local pickFrame = frame(gui, UDim2.fromOffset(300, 320), UDim2.new(0.5,-150,0.5,-160), BG, 0.02)
corner(pickFrame, 14); stroke(pickFrame, Color3.fromRGB(120,70,200), 1.5, 0.3); pickFrame.Visible = false
label(pickFrame, "Choose a player to trade", 15, Color3.new(1,1,1),
	UDim2.new(1,-20,0,24), UDim2.new(0,10,0,10))
local pickClose = button(pickFrame, "✕", UDim2.fromOffset(28,28), UDim2.new(1,-36,0,8), RED)
local pickList = Instance.new("ScrollingFrame")
pickList.Size = UDim2.new(1,-20,1,-50); pickList.Position = UDim2.new(0,10,0,42)
pickList.BackgroundTransparency = 1; pickList.BorderSizePixel = 0
pickList.ScrollBarThickness = 5; pickList.CanvasSize = UDim2.new(0,0,0,0)
pickList.AutomaticCanvasSize = Enum.AutomaticSize.Y; pickList.Parent = pickFrame
local pickLayout = Instance.new("UIListLayout"); pickLayout.Padding = UDim.new(0,6)
pickLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickLayout.Parent = pickList

local function rebuildPickList()
	for _, c in ipairs(pickList:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then others[#others+1] = p end
	end
	if #others == 0 then
		local none = frame(pickList, UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), PANEL, 0.2)
		corner(none, 8); label(none, "No other players online", 13, DIM)
		return
	end
	for _, p in ipairs(others) do
		local row = frame(pickList, UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), PANEL, 0.1)
		corner(row, 8)
		label(row, p.Name, 14, Color3.new(1,1,1), UDim2.new(1,-90,1,0), UDim2.new(0,10,0,0)).TextXAlignment = Enum.TextXAlignment.Left
		local inv = button(row, "Invite", UDim2.fromOffset(72,28), UDim2.new(1,-80,0.5,-14), GREEN)
		inv.MouseButton1Click:Connect(function()
			Remotes.TradeInvite:FireServer(p.UserId)
			pickFrame.Visible = false
		end)
	end
end

openBtn.MouseButton1Click:Connect(function()
	pickFrame.Visible = not pickFrame.Visible
	if pickFrame.Visible then rebuildPickList() end
end)
pickClose.MouseButton1Click:Connect(function() pickFrame.Visible = false end)
Players.PlayerAdded:Connect(function() if pickFrame.Visible then rebuildPickList() end end)
Players.PlayerRemoving:Connect(function() if pickFrame.Visible then rebuildPickList() end end)

-- ─── Incoming invite popup ──────────────────────────────────────────────────
local inviteFrame = frame(gui, UDim2.fromOffset(320, 130), UDim2.new(0.5,-160,0,90), BG, 0.02)
corner(inviteFrame, 14); stroke(inviteFrame, GREEN, 1.5, 0.3); inviteFrame.Visible = false
local inviteLbl = label(inviteFrame, "", 15, Color3.new(1,1,1), UDim2.new(1,-20,0,50), UDim2.new(0,10,0,12))
inviteLbl.TextWrapped = true
local accBtn = button(inviteFrame, "✔ Accept", UDim2.fromOffset(130,34), UDim2.new(0,14,1,-46), GREEN)
local decBtn = button(inviteFrame, "✕ Decline", UDim2.fromOffset(130,34), UDim2.new(1,-144,1,-46), RED)
accBtn.MouseButton1Click:Connect(function() Remotes.TradeRespond:FireServer(true);  inviteFrame.Visible = false end)
decBtn.MouseButton1Click:Connect(function() Remotes.TradeRespond:FireServer(false); inviteFrame.Visible = false end)

Remotes.TradeInviteIn.OnClientEvent:Connect(function(info)
	inviteLbl.Text = "🤝  " .. info.fromName .. " wants to trade with you!"
	inviteFrame.Visible = true
	task.delay(30, function() inviteFrame.Visible = false end)
end)

-- ─── Trade window ─────────────────────────────────────────────────────────────
local myInventory = {}    -- array of fullIds (mirrors server)
local lastState   = nil

local tradeFrame = frame(gui, UDim2.fromOffset(580, 380), UDim2.new(0.5,-290,0.5,-190), BG, 0.02)
corner(tradeFrame, 16); stroke(tradeFrame, Color3.fromRGB(120,70,200), 2, 0.25); tradeFrame.Visible = false

local titleLbl = label(tradeFrame, "Trade", 17, Color3.new(1,1,1), UDim2.new(1,-20,0,26), UDim2.new(0,12,0,10))
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Offer panels
local function offerPanel(x, headColor)
	local p = frame(tradeFrame, UDim2.fromOffset(270, 120), UDim2.new(0, x, 0, 44), PANEL, 0.1)
	corner(p, 10)
	local head = label(p, "", 13, headColor, UDim2.new(1,-12,0,18), UDim2.new(0,8,0,6))
	head.TextXAlignment = Enum.TextXAlignment.Left
	local lock = label(p, "", 12, GREEN, UDim2.fromOffset(70,18), UDim2.new(1,-76,0,6))
	lock.TextXAlignment = Enum.TextXAlignment.Right
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1,-12,1,-32); list.Position = UDim2.new(0,6,0,28)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0,0,0,0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.Parent = p
	local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0,3); lay.Parent = list
	return { head = head, lock = lock, list = list }
end
local mineP   = offerPanel(12,  Color3.fromRGB(90,200,255))
local theirsP = offerPanel(298, Color3.fromRGB(255,170,80))

local function renderChips(panel, fullIds)
	for _, c in ipairs(panel.list:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	for _, fid in ipairs(fullIds) do
		local r = resolve(fid)
		local chip = frame(panel.list, UDim2.new(1,0,0,30), UDim2.new(0,0,0,0), Color3.fromRGB(20,22,38), 0.15)
		corner(chip, 6)
		-- Pet face (coloured circle, same design as the rest of the game)
		local circ = frame(chip, UDim2.fromOffset(24,24), UDim2.new(0,4,0.5,-12), r.bodyColor, 0)
		corner(circ, 12); circ.ZIndex = 3
		if r.baseId then PetFace.draw(circ, r.baseId, r.bodyColor, 24, 3) end
		local nl = label(chip, r.tag .. r.name, 12, r.color, UDim2.new(1,-36,1,0), UDim2.new(0,32,0,0))
		nl.TextXAlignment = Enum.TextXAlignment.Left; nl.ZIndex = 3
	end
end

-- Inventory grid (click to add/remove from your offer)
label(tradeFrame, "Your inventory — click pets to add/remove", 12, DIM,
	UDim2.new(1,-20,0,16), UDim2.new(0,12,0,170))
local invScroll = Instance.new("ScrollingFrame")
invScroll.Size = UDim2.new(1,-24,0,118); invScroll.Position = UDim2.new(0,12,0,190)
invScroll.BackgroundColor3 = PANEL; invScroll.BackgroundTransparency = 0.3; invScroll.BorderSizePixel = 0
invScroll.ScrollBarThickness = 6; invScroll.CanvasSize = UDim2.new(0,0,0,0)
invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; invScroll.Parent = tradeFrame
corner(invScroll, 10)
local invGrid = Instance.new("UIGridLayout")
invGrid.CellSize = UDim2.fromOffset(128, 26); invGrid.CellPadding = UDim2.fromOffset(6,6)
invGrid.Parent = invScroll
local invPad = Instance.new("UIPadding"); invPad.PaddingTop = UDim.new(0,6); invPad.PaddingLeft = UDim.new(0,6); invPad.Parent = invScroll

local function offeredSet()
	local set = {}
	if lastState and lastState.mineIdx then
		for _, i in ipairs(lastState.mineIdx) do set[i] = true end
	end
	return set
end

local function rebuildInvGrid()
	for _, c in ipairs(invScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	local offered = offeredSet()
	for i, fid in ipairs(myInventory) do
		local r = resolve(fid)
		local on = offered[i]
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = on and GREEN or Color3.fromRGB(22,24,40)
		b.Text = ""; b.BorderSizePixel = 0; b.AutoButtonColor = true; b.Parent = invScroll
		corner(b, 6)
		-- Pet face on the left
		local circ = frame(b, UDim2.fromOffset(20,20), UDim2.new(0,4,0.5,-10), r.bodyColor, 0)
		corner(circ, 10); circ.ZIndex = 3
		if r.baseId then PetFace.draw(circ, r.baseId, r.bodyColor, 20, 3) end
		-- Name to the right of the face
		local nl = label(b, r.tag .. r.name, 11, on and Color3.new(1,1,1) or r.color,
			UDim2.new(1,-30,1,0), UDim2.new(0,28,0,0))
		nl.TextXAlignment = Enum.TextXAlignment.Left
		nl.TextTruncate = Enum.TextTruncate.AtEnd; nl.ZIndex = 3
		b.MouseButton1Click:Connect(function()
			Remotes.TradeToggleItem:FireServer(i)
		end)
	end
end

-- Bottom buttons
local lockBtn   = button(tradeFrame, "🔒 LOCK OFFER", UDim2.fromOffset(270,40), UDim2.new(0,12,1,-50), Color3.fromRGB(60,130,210))
local cancelBtn = button(tradeFrame, "✕ CANCEL", UDim2.fromOffset(270,40), UDim2.new(1,-282,1,-50), RED)
lockBtn.MouseButton1Click:Connect(function() Remotes.TradeLock:FireServer() end)
cancelBtn.MouseButton1Click:Connect(function() Remotes.TradeCancel:FireServer() end)

-- Keep our inventory mirror in sync (the main HUD also listens — that's fine).
Remotes.UpdateInventory.OnClientEvent:Connect(function(inv)
	myInventory = inv or {}
	if tradeFrame.Visible then rebuildInvGrid() end
end)

-- Trade state drives the whole window.
Remotes.TradeState.OnClientEvent:Connect(function(state)
	lastState = state
	if not state then
		tradeFrame.Visible = false
		return
	end
	pickFrame.Visible = false
	inviteFrame.Visible = false
	tradeFrame.Visible = true

	titleLbl.Text     = "🤝  Trading with " .. state.partner
	mineP.head.Text   = "Your offer"
	theirsP.head.Text = state.partner .. "'s offer"
	mineP.lock.Text   = state.myLocked    and "✓ READY" or ""
	theirsP.lock.Text = state.theirLocked and "✓ READY" or ""

	renderChips(mineP,   state.mine)
	renderChips(theirsP, state.theirs)
	rebuildInvGrid()

	if state.myLocked then
		lockBtn.Text = "✓ READY (click to edit)"
		lockBtn.BackgroundColor3 = GREEN
	else
		lockBtn.Text = "🔒 LOCK OFFER"
		lockBtn.BackgroundColor3 = Color3.fromRGB(60,130,210)
	end
end)

Remotes.TradePopup.OnClientEvent:Connect(function(msg)
	showToast(msg)
end)

