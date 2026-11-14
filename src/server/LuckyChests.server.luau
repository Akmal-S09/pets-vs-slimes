-- LuckyChests.server.luau  ✨ SURPRISE UPDATE ✨
-- Every 120 seconds, a Lucky Chest spawns somewhere inside each unlocked zone.
-- The first player to reach it and collect it gets a big Goop bonus.
-- An announcement fires to all clients so everyone knows to hunt for them.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")

local Config     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerData = require(script.Parent.PlayerData)
local Remotes    = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local RNG = Random.new()

-- Goop reward per zone (scales with zone difficulty)
local ZONE_REWARD = {
	forest  =  300,
	desert  = 1200,
	volcano = 4000,
	crystal = 12000,
	sky     = 35000,
	abyss   = 100000,
}

-- Spawn bounds per zone (x range, z range)
local ZONE_BOUNDS = {
	forest  = { x1=-100, x2=100, z1= 30,  z2=270  },
	desert  = { x1=-100, x2=100, z1=320,  z2=570  },
	volcano = { x1= -90, x2= 90, z1=620,  z2=880  },
	crystal = { x1= -90, x2= 90, z1=920,  z2=1180 },
	sky     = { x1= -90, x2= 90, z1=1220, z2=1480 },
	abyss   = { x1= -90, x2= 90, z1=1520, z2=1780 },
}

-- Build a gold chest at the given position, returns the chest Part
local function buildChest(pos, zoneId)
	local reward = ZONE_REWARD[zoneId] or 300
	local folder = Instance.new("Folder")
	folder.Name  = "LuckyChest_"..zoneId
	folder.Parent = workspace

	-- Chest body
	local body = Instance.new("Part")
	body.Name      = "ChestBody"
	body.Size      = Vector3.new(3.2, 2.4, 2.2)
	body.CFrame    = CFrame.new(pos)
	body.Color     = Color3.fromRGB(185, 130, 20)
	body.Material  = Enum.Material.SmoothPlastic
	body.Anchored  = true
	body.CanCollide = true
	body.CastShadow = false
	body.Parent    = folder

	-- Lid (slightly raised)
	local lid = Instance.new("Part")
	lid.Name   = "ChestLid"
	lid.Size   = Vector3.new(3.2, 0.8, 2.2)
	lid.CFrame = CFrame.new(pos + Vector3.new(0, 1.6, 0))
	lid.Color  = Color3.fromRGB(210, 155, 30)
	lid.Material = Enum.Material.SmoothPlastic
	lid.Anchored = true; lid.CanCollide = false; lid.CastShadow = false
	lid.Parent = folder

	-- Gold lock strip
	local lock = Instance.new("Part")
	lock.Size  = Vector3.new(0.5, 2.4, 0.5)
	lock.CFrame = CFrame.new(pos + Vector3.new(0, 0, -1.2))
	lock.Color  = Color3.fromRGB(255, 215, 50)
	lock.Material = Enum.Material.SmoothPlastic
	lock.Anchored = true; lock.CanCollide = false; lock.CastShadow = false
	lock.Parent = folder

	-- Neon glow ring at base
	local glow = Instance.new("Part")
	glow.Size  = Vector3.new(4.4, 0.4, 3.4)
	glow.CFrame = CFrame.new(pos + Vector3.new(0, -1.1, 0))
	glow.Color  = Color3.fromRGB(255, 210, 50)
	glow.Material = Enum.Material.Neon
	glow.Anchored = true; glow.CanCollide = false; glow.CastShadow = false
	glow.Transparency = 0.35
	glow.Parent = folder

	-- Point light
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 200, 50)
	pl.Range = 24; pl.Brightness = 3.5
	pl.Parent = body

	-- Floating "LUCKY CHEST" billboard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 55)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = false; bb.MaxDistance = 60
	bb.Adornee = body; bb.Parent = body

	local bgtitle = Instance.new("TextLabel")
	bgtitle.Size = UDim2.new(1,0,0.55,0); bgtitle.Position = UDim2.new(0,0,0,0)
	bgtitle.BackgroundTransparency = 1
	bgtitle.Text = "✨  LUCKY CHEST"
	bgtitle.TextColor3 = Color3.fromRGB(255, 215, 55)
	bgtitle.TextSize = 20; bgtitle.Font = Enum.Font.GothamBlack
	bgtitle.TextStrokeTransparency = 0.3
	bgtitle.Parent = bb

	local bgsub = Instance.new("TextLabel")
	bgsub.Size = UDim2.new(1,0,0.45,0); bgsub.Position = UDim2.new(0,0,0.55,0)
	bgsub.BackgroundTransparency = 1
	bgsub.Text = "💰 "..tostring(reward).." Coins"
	bgsub.TextColor3 = Color3.fromRGB(200, 240, 200)
	bgsub.TextSize = 16; bgsub.Font = Enum.Font.GothamBold
	bgsub.TextStrokeTransparency = 0.45
	bgsub.Parent = bb

	-- ProximityPrompt to collect
	local pp = Instance.new("ProximityPrompt")
	pp.ObjectText       = "Lucky Chest"
	pp.ActionText       = "Collect  💰 " .. tostring(reward)
	pp.KeyboardKeyCode  = Enum.KeyCode.F
	pp.MaxActivationDistance = 8
	pp.HoldDuration     = 0.6
	pp.RequiresLineOfSight = false
	pp.Parent = body

	local collected = false
	pp.Triggered:Connect(function(player)
		if collected then return end
		collected = true

		-- Award goop
		local d = PlayerData.get(player)
		d.coins = d.coins + reward
		Remotes.UpdateCoins:FireClient(player, d.coins)
		Remotes.FloatText:FireClient(player, "💰 +"..tostring(reward).." Coins!")

		-- Broadcast to all
		for _, p in ipairs(Players:GetPlayers()) do
			Remotes.NotifyPurchase:FireClient(p,
				player.Name.." found a Lucky Chest!  💰 +"..tostring(reward), "luck")
		end

		-- Pop animation: scale up then shrink + destroy
		TweenService:Create(body, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = Vector3.new(4.5, 3.4, 3.2)}):Play()
		task.delay(0.14, function()
			TweenService:Create(body, TweenInfo.new(0.18),
				{Size = Vector3.new(0.1, 0.1, 0.1)}):Play()
			task.delay(0.22, function() folder:Destroy() end)
		end)
	end)

	-- Auto-despawn after 90 seconds if uncollected
	Debris:AddItem(folder, 90)

	return body
end

-- Check which zones are currently unlocked via workspace barriers
local function getUnlockedZones()
	local unlocked = { "forest" }   -- forest always open
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name:sub(1,12) == "ZoneBarrier_" then
			local zName = obj.Name:sub(13):lower()
			-- Barrier is removed (Transparency = 1 and CanCollide = false) when unlocked
			if not obj.CanCollide then
				table.insert(unlocked, zName)
			end
		end
	end
	return unlocked
end

-- Wait for world to finish building
task.wait(6)

print("[LuckyChests] Surprise update active — chests spawn every 120s!")

-- Main loop: spawn chests every 120 seconds
while true do
	task.wait(120)

	local zones = getUnlockedZones()
	if #Players:GetPlayers() == 0 then continue end

	-- Announce to all players
	for _, p in ipairs(Players:GetPlayers()) do
		Remotes.NotifyPurchase:FireClient(p,
			"✨ Lucky Chests appeared in all zones! Find them!", "luck")
	end

	-- Spawn one chest per unlocked zone
	for _, zoneId in ipairs(zones) do
		local b = ZONE_BOUNDS[zoneId]
		if not b then continue end
		local x = RNG:NextNumber(b.x1, b.x2)
		local z = RNG:NextNumber(b.z1, b.z2)
		buildChest(Vector3.new(x, 2.2, z), zoneId)
	end
end

