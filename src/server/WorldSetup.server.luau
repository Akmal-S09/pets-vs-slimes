-- WorldSetup.server.luau
-- Builds terrain, decorations, and zone gates once on server start.

local Terrain = workspace.Terrain
local RNG     = Random.new(99421)   -- seeded → same layout every run

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local LAST_Z  = Config.ZONES[#Config.ZONES].gateZ + 300   -- north end of the map (~9000)

-- ─── SpawnLocation — must exist BEFORE anything else so players never land in void ──
local spawnPad        = Instance.new("SpawnLocation")
spawnPad.Name         = "SpawnLocation"
spawnPad.Size         = Vector3.new(16, 1, 16)
-- Spawn plaza sits SOUTH of the forest (negative Z); face +Z so the player
-- looks at the leaderboards and walks forward into Zone 1 (the Forest).
-- Sit flush with the raised plaza floor (top ≈ y2.1) so players don't spawn on
-- an invisible block and drop. (Pad is 1 thick → centre 1.6 puts its top at 2.1.)
spawnPad.CFrame       = CFrame.new(Vector3.new(0, 1.6, -96), Vector3.new(0, 1.6, 0))
spawnPad.Neutral      = true
spawnPad.Duration     = 0
spawnPad.Transparency = 1
spawnPad.CanCollide   = true
spawnPad.Anchored     = true
spawnPad.Parent       = workspace

-- ─── Palette ─────────────────────────────────────────────────────────────────
local C = {
	brown      = Color3.fromRGB(124,  82,  46),
	darkGreen  = Color3.fromRGB( 62, 168,  78),
	midGreen   = Color3.fromRGB( 86, 196,  96),
	lightGreen = Color3.fromRGB(124, 220, 120),
	leafLime   = Color3.fromRGB(168, 240, 140),
	rock       = Color3.fromRGB(150, 150, 162),
	mushWhite  = Color3.fromRGB(252, 248, 240),
	spotWhite  = Color3.fromRGB(255, 255, 255),
	desertRock = Color3.fromRGB(214, 178, 118),
	cactus     = Color3.fromRGB( 72, 142,  82),
	gateBlue   = Color3.fromRGB( 80, 190, 250),
	gateOrange = Color3.fromRGB(255, 130,  50),
	gateDark   = Color3.fromRGB( 38,  40,  78),
	gold       = Color3.fromRGB(255, 210,  80),
	flowerStem = Color3.fromRGB( 96, 200, 110),
}

-- ─── Part helpers ─────────────────────────────────────────────────────────────
local DECOR      = Instance.new("Folder")
DECOR.Name       = "WorldDecor"
DECOR.Parent     = workspace

local function mk(sz, cf, col, mat, parent, noCol, tr)
	local p        = Instance.new("Part")
	p.Size         = sz
	p.CFrame       = cf
	p.Color        = col
	p.Material     = mat
	p.Anchored     = true
	p.CanCollide   = not noCol
	p.CastShadow   = false
	p.Transparency = tr or 0
	p.Parent       = parent
	return p
end

local function neon(sz, cf, col, parent)
	-- NOTE: not actually Neon anymore — solid plastic so the map isn't a
	-- blown-out glowing mess. Keeps the bright colour without the bloom wash.
	return mk(sz, cf, col, Enum.Material.SmoothPlastic, parent, true)
end

-- Sphere-mesh ball (decorative blobs, no collision)
local function ball(sz, cf, col, parent, mat)
	local p = mk(sz, cf, col, mat or Enum.Material.SmoothPlastic, parent, true)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent   = p
	return p
end

-- Vertical cylinder (for trunks, cacti, etc.)
local function vcyl(dia, height, x, y, z, col, parent, mat)
	local p = mk(Vector3.new(height, dia, dia), CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi/2),
		col, mat or Enum.Material.SmoothPlastic, parent, true)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- ─── Billboard helper ─────────────────────────────────────────────────────────
local function addBillboard(adornee, line1, line2, col1, col2)
	local bb       = Instance.new("BillboardGui")
	bb.Size        = UDim2.fromOffset(280, 80)
	bb.StudsOffset = Vector3.new(0, 1, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 100
	bb.Adornee     = adornee
	bb.Parent      = adornee

	local t1 = Instance.new("TextLabel")
	t1.Size  = UDim2.new(1, 0, 0.5, 0)
	t1.BackgroundTransparency = 1
	t1.Text  = line1
	t1.TextColor3 = col1
	t1.Font  = Enum.Font.GothamBold
	t1.TextSize = 22
	t1.TextStrokeTransparency = 0.4
	t1.Parent = bb

	local t2 = Instance.new("TextLabel")
	t2.Size     = UDim2.new(1, 0, 0.5, 0)
	t2.Position = UDim2.new(0, 0, 0.5, 0)
	t2.BackgroundTransparency = 1
	t2.Text  = line2
	t2.TextColor3 = col2
	t2.Font  = Enum.Font.Gotham
	t2.TextSize = 18
	t2.TextStrokeTransparency = 0.5
	t2.Parent = bb
end

-- ─── Terrain ─────────────────────────────────────────────────────────────────
-- Valley floor surface sits at Y = 0.
-- FillBlock centre at Y = -5, height 10  →  fills Y = -10 to Y = 0.
local VW = 210   -- valley X width (compressed corridor, like the reference)

pcall(function()
	Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB( 88, 198,  78))
	Terrain:SetMaterialColor(Enum.Material.Sand,  Color3.fromRGB(240, 208, 138))
	Terrain:SetMaterialColor(Enum.Material.Rock,  Color3.fromRGB(120,  80,  52))  -- warm brown cliffs (like the reference)
end)

-- Grass valley (forest + desert zones: Z 0 → 600)  — VW+80 fills to mountain base
Terrain:FillBlock(CFrame.new(0, -5, 300), Vector3.new(VW+80, 10, 600), Enum.Material.Grass)

-- Spawn plaza ground (south of the forest: Z -125 → 8)
Terrain:FillBlock(CFrame.new(0, -5, -58), Vector3.new(VW+80, 10, 134), Enum.Material.Grass)

-- ── Raised plateau at the back of the forest (adds visual depth) ──────────────
Terrain:FillBlock(CFrame.new(0, 3, 140), Vector3.new(80, 6, 60), Enum.Material.Grass)
Terrain:FillCylinder(CFrame.new(-32, 3, 115), 6, 24, Enum.Material.Grass)
Terrain:FillCylinder(CFrame.new( 32, 3, 165), 6, 20, Enum.Material.Grass)

-- ── Central forest pond ────────────────────────────────────────────────────────
Terrain:FillCylinder(CFrame.new(0, -0.5, 160), 2.5, 26, Enum.Material.Water)
-- Shore ring
Terrain:FillCylinder(CFrame.new(0, -0.8, 160), 1.8, 30, Enum.Material.Mud)

-- ── Rocky outcrops near the pond ─────────────────────────────────────────────
for _, rc in ipairs({ {-22,148},{20,172},{-18,175},{26,150} }) do
	Terrain:FillCylinder(CFrame.new(rc[1], 1.5, rc[2]), 3, 5, Enum.Material.Rock)
end

-- Sand overlay for desert zone (Z 300 → 600)
Terrain:FillBlock(CFrame.new(0, -1.5, 450), Vector3.new(VW+80, 3, 300), Enum.Material.Sand)

-- ── Sand dunes (low raised mounds in the desert) ─────────────────────────────
for _, d in ipairs({ {-50,360},{60,400},{-30,450},{40,490},{-65,530},{20,560} }) do
	Terrain:FillCylinder(CFrame.new(d[1], 1.5, d[2]), 2.8, 18+RNG:NextInteger(-4,4), Enum.Material.Sand)
end

-- Bedrock under everything
Terrain:FillBlock(CFrame.new(0, -18, 300), Vector3.new(VW + 200, 16, 700), Enum.Material.Rock)

pcall(function()
	Terrain:SetMaterialColor(Enum.Material.Water, Color3.fromRGB(60,160,255))
	Terrain:SetMaterialColor(Enum.Material.Mud,   Color3.fromRGB(130,105,70))
end)

-- Ground colour variation: sphere-mesh discs create natural bright/dark patches
local PATCH_COLS = {
	Color3.fromRGB( 72, 192,  58),
	Color3.fromRGB( 46, 145,  38),
	Color3.fromRGB( 90, 215,  74),
	Color3.fromRGB( 58, 168,  50),
}
for i = 1, 38 do
	local r   = 6 + RNG:NextNumber(0, 20)
	local col = PATCH_COLS[((i-1) % #PATCH_COLS) + 1]
	local p   = mk(
		Vector3.new(r*2, 0.06, r*2),
		CFrame.new(RNG:NextNumber(-84,84), 0.03, RNG:NextNumber(10,292)),
		col, Enum.Material.SmoothPlastic, DECOR, true, 0.44)
	local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere
	m.Scale = Vector3.new(1, 0.04, 1); m.Parent = p
end

-- Mountain ridges (span the whole 30-stage map)
local function mountainRidge(baseX, flip)
	local steps = math.ceil((LAST_Z + 60) / 90)
	for i = 0, steps do
		local zc   = i * 90 - 20
		-- Material varies by region
		local mat = Enum.Material.Rock
		if zc > 1490 then mat = Enum.Material.Basalt
		elseif zc > 1190 then mat = Enum.Material.Sandstone
		elseif zc > 890  then mat = Enum.Material.Rock
		elseif zc > 590  then mat = Enum.Material.Basalt
		end
		local w    = 90 + RNG:NextNumber(-15, 20)
		local h    = 65 + RNG:NextNumber(-12, 18) + (zc > 590 and 15 or 0)
		local xOff = RNG:NextNumber(-10, 10) * flip
		Terrain:FillBlock(
			CFrame.new(baseX + xOff, -(h / 2) + h * 0.55, zc),
			Vector3.new(w, h, 110), mat)
		Terrain:FillCylinder(
			CFrame.new(baseX + xOff, h * 0.55 - 8, zc),
			h * 0.5, w * 0.35, mat)
	end
end

mountainRidge(-150,  1)
mountainRidge( 150, -1)

-- ── Solid continuous rock backing behind both mountain ridges ──
-- The decorative ridges have random notches you could see sky/void through.
-- These full-length tall walls sit just behind them so the map reads solid.
Terrain:FillBlock(CFrame.new(-138, 35, LAST_Z/2 - 60), Vector3.new(80, 130, LAST_Z + 400), Enum.Material.Rock)
Terrain:FillBlock(CFrame.new( 138, 35, LAST_Z/2 - 60), Vector3.new(80, 130, LAST_Z + 400), Enum.Material.Rock)

-- Back rock cliff — pushed back to make room for a large spawn plaza
Terrain:FillBlock(CFrame.new(0,  10, -150), Vector3.new(VW + 200, 60,  50), Enum.Material.Rock)

-- North rock cliff — closes off the far end of the map (past the last stage)
Terrain:FillBlock(CFrame.new(0, 45, LAST_Z + 30), Vector3.new(VW + 220, 150, 70), Enum.Material.Rock)

-- ── Bedrock base under the valley (kills fall-through holes) ──
Terrain:FillBlock(CFrame.new(0, -13, LAST_Z/2 - 60), Vector3.new(VW, 16, LAST_Z + 400), Enum.Material.Rock)

-- ── Side ground strips filled UP TO the surface (Y=0) so there is no canyon /
-- step-down beside the valley. They run the whole map length and meet the
-- mountains, turning the old gap into solid rocky ground.
-- (side-strip fills removed — terrain fills now widen to VW+80 to close mountain gaps)

-- ─── Decorations ─────────────────────────────────────────────────────────────

-- Conical pine / fir tree — matches the Slime RNG reference look.
-- Tall narrow trunk, 5 disc-tiers tapering from wide base to a pointed spire.
local BARK     = Color3.fromRGB( 88,  52,  28)
local BARK2    = Color3.fromRGB(108,  68,  38)
local PINE_D   = Color3.fromRGB( 38,  92,  46)   -- dark base tier
local PINE_M   = Color3.fromRGB( 52, 118,  58)   -- mid
local PINE_L   = Color3.fromRGB( 72, 148,  68)   -- light upper
local PINE_T   = Color3.fromRGB( 92, 168,  78)   -- top tip
local LG = Enum.Material.LeafyGrass

-- Cone helper. Roblox has no native cone mesh-type, so we use the Creator-Store
-- cone mesh. If it ever fails to load the part falls back to a tapered block.
local CONE_MESH = "rbxassetid://12263066077"   -- "cone mesh" (Creator Store)
local function cone(dia, height, x, y, z, col, mat)
	local p = mk(Vector3.new(dia*0.7, height, dia*0.7), CFrame.new(x, y, z), col, mat or LG, DECOR, true)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId   = CONE_MESH
	m.Scale    = Vector3.new(dia, height, dia)
	m.Parent   = p
	return p
end

local function makeTree(x, z, scl)
	scl = scl or 1

	-- Tall reddish-brown trunk
	vcyl(2.6*scl, 11*scl, x, 5.5*scl,  z, BARK,  DECOR, Enum.Material.Wood)
	vcyl(1.9*scl,  9*scl, x, 12.5*scl, z, BARK2, DECOR, Enum.Material.Wood)

	-- Stacked drooping tiers from SQUASHED spheres (guaranteed to render — no
	-- mesh asset). Wide flared base tapering to a pointed top = conifer look.
	local TIERS = {
		{ y=10.5, r=5.6, c=PINE_D },
		{ y=13.0, r=4.7, c=PINE_D },
		{ y=15.2, r=3.9, c=PINE_M },
		{ y=17.2, r=3.1, c=PINE_M },
		{ y=19.0, r=2.4, c=PINE_L },
		{ y=20.6, r=1.7, c=PINE_L },
		{ y=22.0, r=1.0, c=PINE_T },   -- pointed tip
	}
	for _, ti in ipairs(TIERS) do
		-- slimmer tiers (height = 1.3 × radius) — pointed conifer, not bushy
		ball(Vector3.new(ti.r*2*scl, ti.r*1.3*scl, ti.r*2*scl),
			CFrame.new(x, ti.y*scl, z), ti.c, DECOR, LG)
	end
end

local function makeMushroom(x, z, col, scl)
	scl = scl or 1
	-- Stem: actual cylinder proportions (not a sphere)
	mk(Vector3.new(0.85 * scl, 2.6 * scl, 0.85 * scl),
		CFrame.new(x, 1.3 * scl, z),
		C.mushWhite, Enum.Material.SmoothPlastic, DECOR, true)
	-- Slight flare at base
	mk(Vector3.new(1.3 * scl, 0.5 * scl, 1.3 * scl),
		CFrame.new(x, 0.25 * scl, z),
		C.mushWhite, Enum.Material.SmoothPlastic, DECOR, true)

	-- Domed cap: sphere mesh squashed on Y
	local cap = ball(Vector3.new(3.4 * scl, 2.6 * scl, 3.4 * scl),
		CFrame.new(x, 2.9 * scl, z), col, DECOR)
	local mesh = cap:FindFirstChildOfClass("SpecialMesh")
	if mesh then mesh.Scale = Vector3.new(1, 0.72, 1) end

	-- 4 evenly-spaced white spots on the cap rim
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + 0.4
		ball(Vector3.new(0.65 * scl, 0.38 * scl, 0.65 * scl),
			CFrame.new(x + math.cos(a) * 0.9 * scl, 3.0 * scl, z + math.sin(a) * 0.9 * scl),
			C.spotWhite, DECOR)
	end
	-- Centre spot
	ball(Vector3.new(0.6 * scl, 0.35 * scl, 0.6 * scl),
		CFrame.new(x, 3.35 * scl, z), C.spotWhite, DECOR)

	-- Soft glow ring at gills
	neon(Vector3.new(2.2 * scl, 0.12, 2.2 * scl), CFrame.new(x, 2.05 * scl, z), col, DECOR)
end

local function makeRock(x, z, scl, isDesert)
	local col = isDesert and C.desertRock or C.rock
	local w   = (3.0 + RNG:NextNumber(0, 1.8)) * scl
	local h   = (2.0 + RNG:NextNumber(0, 1.4)) * scl
	local d   = (2.6 + RNG:NextNumber(0, 1.6)) * scl
	ball(Vector3.new(w, h, d),
		CFrame.new(x, h * 0.42, z)
			* CFrame.Angles(RNG:NextNumber(-0.1, 0.1), RNG:NextNumber(0, math.pi), RNG:NextNumber(-0.08, 0.08)),
		col, DECOR)
end

local FLOWER_COLS = {
	Color3.fromRGB(255, 110, 170),
	Color3.fromRGB(255, 220,  70),
	Color3.fromRGB(150, 130, 255),
	Color3.fromRGB(255, 140,  90),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 255, 255),
}
local function makeFlower(x, z, scl)
	scl = scl or 1
	local col = FLOWER_COLS[RNG:NextInteger(1, #FLOWER_COLS)]
	mk(Vector3.new(0.2 * scl, 1.4 * scl, 0.2 * scl),
		CFrame.new(x, 0.7 * scl, z),
		C.flowerStem, Enum.Material.SmoothPlastic, DECOR, true)
	local hy = 1.5 * scl
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		ball(Vector3.new(0.55 * scl, 0.28 * scl, 0.55 * scl),
			CFrame.new(x + math.cos(a) * 0.42 * scl, hy, z + math.sin(a) * 0.42 * scl),
			col, DECOR)
	end
	ball(Vector3.new(0.45 * scl, 0.35 * scl, 0.45 * scl),
		CFrame.new(x, hy + 0.08 * scl, z),
		Color3.fromRGB(255, 224, 90), DECOR)
end

local function makeLog(x, z)
	local ang = RNG:NextNumber(0, math.pi)
	mk(Vector3.new(6.5, 1.1, 1.1), CFrame.new(x, 0.6, z) * CFrame.Angles(0, ang, 0.12),
		C.brown, Enum.Material.Wood, DECOR, true)
end

-- Small round bush (2-3 overlapping sphere blobs at ground level)
local function makeBush(x, z, scl)
	scl = scl or 1
	local cr = 2.1 * scl
	-- Main blob
	ball(Vector3.new(cr*2, cr*1.55, cr*2),    CFrame.new(x,          cr*0.75, z),            C.darkGreen,  DECOR)
	-- Two accent blobs
	ball(Vector3.new(cr*1.4, cr*1.25, cr*1.4), CFrame.new(x+cr*0.7,  cr*0.6,  z-cr*0.5),    C.midGreen,   DECOR)
	ball(Vector3.new(cr*1.1, cr*1.0,  cr*1.1), CFrame.new(x-cr*0.55, cr*0.5,  z+cr*0.45),   C.lightGreen, DECOR)
end

local function makeGrassTuft(x, z)
	for _ = 1, 4 do
		local ox = RNG:NextNumber(-1, 1)
		local oz = RNG:NextNumber(-0.8, 0.8)
		local h  = RNG:NextNumber(0.8, 1.8)
		mk(Vector3.new(0.25, h, 0.25),
			CFrame.new(x + ox, h / 2, z + oz)
				* CFrame.Angles(RNG:NextNumber(-0.2, 0.2), 0, RNG:NextNumber(-0.15, 0.15)),
			C.lightGreen, Enum.Material.SmoothPlastic, DECOR, true)
	end
end

-- Helper: upright cylinder (stands along Y).  len=height, dia=diameter.
local function cylUp(len, dia, cx, cy, cz)
	local p = Instance.new("Part")
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = Vector3.new(len, dia, dia)
	-- Rotate 90° around Z so the cylinder's X-axis points up
	p.CFrame   = CFrame.new(cx, cy, cz) * CFrame.Angles(0, 0, math.pi/2)
	p.Color    = C.cactus; p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false; p.Parent = DECOR
	return p
end
-- Helper: horizontal cylinder (along X).  len=length, dia=diameter.
local function cylSide(len, dia, cx, cy, cz)
	local p = Instance.new("Part")
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = Vector3.new(len, dia, dia)
	p.CFrame   = CFrame.new(cx, cy, cz)   -- default = along X
	p.Color    = C.cactus; p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false; p.Parent = DECOR
	return p
end

local function makeCactus(x, z)
	local h  = 9 + RNG:NextNumber(0, 4)   -- taller
	local dia = 2.0

	-- ── Main trunk ────────────────────────────────────────────────────────────
	cylUp(h, dia, x, h/2, z)
	-- Rounded bottom & top caps
	ball(Vector3.new(dia+0.3, dia+0.3, dia+0.3), CFrame.new(x, 0.4, z), C.cactus, DECOR)
	ball(Vector3.new(dia+0.2, dia+0.6, dia+0.2), CFrame.new(x, h+0.4, z), C.cactus, DECOR)
	-- Tiny flower on very top
	ball(Vector3.new(1.2,1.2,1.2), CFrame.new(x, h+1.2, z), Color3.fromRGB(255,200,110), DECOR)

	-- ── Left arm: horizontal jut then vertical rise ───────────────────────────
	local laW = 3.5 + RNG:NextNumber(0, 2)          -- horizontal length
	local laY = h * (0.40 + RNG:NextNumber(0, 0.12)) -- attachment height
	local laH = laW * (0.70 + RNG:NextNumber(0,0.25)) -- vertical rise

	-- Horizontal section (along -X from trunk centre)
	cylSide(laW, dia*0.80, x - laW/2 - dia*0.4, laY, z)
	-- Ball at the corner (elbow)
	ball(Vector3.new(dia*0.9,dia*0.9,dia*0.9), CFrame.new(x-laW-dia*0.3, laY, z), C.cactus, DECOR)
	-- Vertical rise
	cylUp(laH, dia*0.80, x - laW - dia*0.3, laY + laH/2, z)
	-- Rounded arm tip
	ball(Vector3.new(dia*0.85+0.2, dia*0.85+0.5, dia*0.85+0.2),
		CFrame.new(x-laW-dia*0.3, laY+laH+0.3, z), C.cactus, DECOR)
	-- Small flower on arm tip
	ball(Vector3.new(0.9,0.9,0.9), CFrame.new(x-laW-dia*0.3, laY+laH+1.0, z),
		Color3.fromRGB(255,200,110), DECOR)

	-- ── Right arm: higher, different size ─────────────────────────────────────
	local raW = 3.0 + RNG:NextNumber(0, 1.8)
	local raY = h * (0.62 + RNG:NextNumber(0, 0.12))
	local raH = raW * (0.65 + RNG:NextNumber(0,0.25))

	cylSide(raW, dia*0.80, x + raW/2 + dia*0.4, raY, z)
	ball(Vector3.new(dia*0.9,dia*0.9,dia*0.9), CFrame.new(x+raW+dia*0.3, raY, z), C.cactus, DECOR)
	cylUp(raH, dia*0.80, x + raW + dia*0.3, raY + raH/2, z)
	ball(Vector3.new(dia*0.85+0.2, dia*0.85+0.5, dia*0.85+0.2),
		CFrame.new(x+raW+dia*0.3, raY+raH+0.3, z), C.cactus, DECOR)
	ball(Vector3.new(0.9,0.9,0.9), CFrame.new(x+raW+dia*0.3, raY+raH+1.0, z),
		Color3.fromRGB(255,200,110), DECOR)
end

local function makeDeadTree(x, z)
	local col = Color3.fromRGB(105, 80, 55)
	local h   = 6 + RNG:NextNumber(0, 3)
	mk(Vector3.new(1, h, 1), CFrame.new(x, h/2, z), col, Enum.Material.Wood, DECOR, true)
	mk(Vector3.new(3, 0.6, 0.6), CFrame.new(x-1.5, h*0.7, z) * CFrame.Angles(0,0,math.rad(35)),
		col, Enum.Material.Wood, DECOR, true)
	mk(Vector3.new(2.5, 0.5, 0.5), CFrame.new(x+1.2, h*0.85, z) * CFrame.Angles(0,0,math.rad(-25)),
		col, Enum.Material.Wood, DECOR, true)
end

-- ─── Forest scatter (Z 0 → 295) ──────────────────────────────────────────────
local TREE_POS = {
	{-90,40},{-80,110},{-92,200},{-72,260},{-86,150},{-78,75},
	{90,55},{80,130},{92,215},{74,270},{88,170},{78,95},
}
for _, t in ipairs(TREE_POS) do
	makeTree(t[1], t[2], 0.85 + RNG:NextNumber(0, 0.55))
end

local MUSH_COLS = {
	Color3.fromRGB(220, 75,145), Color3.fromRGB(155,55,200),
	Color3.fromRGB(240, 55, 55), Color3.fromRGB( 75,175,230),
	Color3.fromRGB(245,175, 35), Color3.fromRGB( 80,220,120),
}
for i = 1, 12 do
	local col = MUSH_COLS[((i-1) % #MUSH_COLS) + 1]
	makeMushroom(RNG:NextNumber(-85,85), RNG:NextNumber(8,288), col, 0.7 + RNG:NextNumber(0,0.6))
end

for _ = 1, 8 do
	makeRock(RNG:NextNumber(-85,85), RNG:NextNumber(15,285), 0.55 + RNG:NextNumber(0,0.8))
end
for _ = 1, 4 do
	makeLog(RNG:NextNumber(-82,82), RNG:NextNumber(25,275))
end
for _ = 1, 14 do
	makeGrassTuft(RNG:NextNumber(-86,86), RNG:NextNumber(5,292))
end
for _ = 1, 18 do
	makeFlower(RNG:NextNumber(-86,86), RNG:NextNumber(5,292), 0.8 + RNG:NextNumber(0,0.7))
end

-- Bushes: a few small round shrubs filling gaps
for _ = 1, 10 do
	makeBush(RNG:NextNumber(-85,85), RNG:NextNumber(8,290), 0.6 + RNG:NextNumber(0,0.65))
end

-- ── Pond-side rocks & extra flowers ──────────────────────────────────────────
for _, pr in ipairs({ {-26,148},{22,160},{-20,172},{28,155},{-12,178} }) do
	makeRock(pr[1], pr[2], 0.5 + RNG:NextNumber(0,0.6))
end
for _ = 1, 12 do
	makeFlower(RNG:NextNumber(-28,28), RNG:NextNumber(138,182), 0.9+RNG:NextNumber(0,0.4))
end
-- Pond lily pads (flat green circles floating on water)
for i = 1, 5 do
	local a = (i/5)*math.pi*2
	mk(Vector3.new(4.5,0.15,4.5), CFrame.new(math.cos(a)*11, 0.05, 160+math.sin(a)*10),
		Color3.fromRGB(55,160,65), Enum.Material.SmoothPlastic, DECOR, true, 0.05)
end

-- ─── Desert scatter (Z 305 → 595) ────────────────────────────────────────────
for _ = 1, 8 do
	makeCactus(RNG:NextNumber(-84,84), RNG:NextNumber(318,582))
end
for _ = 1, 4 do
	makeDeadTree(RNG:NextNumber(-78,78), RNG:NextNumber(320,578))
end
for _ = 1, 12 do
	makeRock(RNG:NextNumber(-85,85), RNG:NextNumber(312,588), 0.7 + RNG:NextNumber(0,1.4), true)
end
-- Desert bones / skulls (flavour objects — flat disc + sphere)
for i = 1, 3 do
	local bx = RNG:NextNumber(-90,90); local bz = RNG:NextNumber(330,570)
	mk(Vector3.new(3,0.4,1.2), CFrame.new(bx, 0.2, bz)*CFrame.Angles(0,RNG:NextNumber(0,math.pi),0),
		Color3.fromRGB(240,235,210), Enum.Material.SmoothPlastic, DECOR, true)
	ball(Vector3.new(1.4,1.1,1.4), CFrame.new(bx+1.2,0.5,bz), Color3.fromRGB(240,235,210), DECOR)
end

-- ─── Volcano zone terrain (Z 605 → 895) ─────────────────────────────────────
pcall(function()
	Terrain:SetMaterialColor(Enum.Material.Basalt,      Color3.fromRGB( 52,  42,  38))
	Terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(255, 100,  20))
	Terrain:SetMaterialColor(Enum.Material.Slate,       Color3.fromRGB( 64,  56,  52))
end)

-- Dark basalt base
Terrain:FillBlock(CFrame.new(0, -5, 750), Vector3.new(VW+80, 10, 300), Enum.Material.Basalt)

-- Lava pools (CrackedLava craters)
local LAVA_POOLS = {
	{  18, 680, 22 }, { -38, 710, 18 }, {  55, 740, 16 },
	{ -15, 775, 26 }, {  38, 800, 20 }, { -50, 830, 18 },
	{   0, 860, 14 },
}
for _, lp in ipairs(LAVA_POOLS) do
	Terrain:FillCylinder(CFrame.new(lp[1], -0.8, lp[2]), 2.2, lp[3], Enum.Material.CrackedLava)
	-- Glowing neon ring around each pool
	neon(Vector3.new(lp[3]*2+2, 0.6, lp[3]*2+2),
		CFrame.new(lp[1], 0.3, lp[2]), Color3.fromRGB(255,90,15), DECOR)
end

-- Slate/ash patches between pools
for _ = 1, 8 do
	local px = RNG:NextNumber(-84, 84)
	local pz = RNG:NextNumber(610, 890)
	local pr = 6 + RNG:NextNumber(0, 14)
	Terrain:FillCylinder(CFrame.new(px, -1.4, pz), 1.6, pr, Enum.Material.Slate)
end

-- (Removed the stepped volcano cone — it sat at the crystal-zone border and looked off.)

-- ── Obsidian spires (tall thin pillars) ───────────────────────────────────────
local OBSIDIAN = Color3.fromRGB(28, 22, 32)
local SPIRE_SPOTS = {
	{-88,622},{88,640},{-70,668},{72,695},{-95,730},{90,755},
	{-60,790},{65,815},{-82,848},{78,868},
}
for _, sp in ipairs(SPIRE_SPOTS) do
	local h = 8 + RNG:NextNumber(0, 14)
	local w = 2.0 + RNG:NextNumber(0, 1.5)
	-- Main spire
	mk(Vector3.new(w, h, w),       CFrame.new(sp[1], h/2,    sp[2]), OBSIDIAN, Enum.Material.SmoothPlastic, DECOR, true)
	-- Thinner sub-spire beside it
	mk(Vector3.new(w*0.55, h*0.65, w*0.55),
		CFrame.new(sp[1]+w*1.1, h*0.325, sp[2]+w*0.6) * CFrame.Angles(RNG:NextNumber(-0.12,0.12),0,RNG:NextNumber(-0.08,0.08)),
		OBSIDIAN, Enum.Material.SmoothPlastic, DECOR, true)
	-- Orange neon crack glow
	neon(Vector3.new(0.25, h*0.9, 0.25), CFrame.new(sp[1]+w*0.35, h*0.45, sp[2]-w*0.35),
		Color3.fromRGB(255,80,10), DECOR)
end

-- ── Steam vents (vertical neon shafts + billowing ball puffs) ─────────────────
local STEAM_SPOTS = {
	{-30,645},{40,672},{-55,720},{20,758},{-20,802},{48,842},
}
local steamWhite = Color3.fromRGB(220,210,200)
for _, sv in ipairs(STEAM_SPOTS) do
	-- Vent shaft
	neon(Vector3.new(1.2,6,1.2), CFrame.new(sv[1], 3, sv[2]), Color3.fromRGB(200,180,160), DECOR)
	-- Steam puffs rising upward
	for j = 1, 4 do
		local py = 5 + j*3.5
		local pr = 2.5 - j*0.35
		ball(Vector3.new(pr*2, pr*1.4, pr*2), CFrame.new(sv[1], py, sv[2]), steamWhite, DECOR)
	end
	-- Point light at vent
	local pl  = Instance.new("PointLight")
	pl.Color  = Color3.fromRGB(255,160,80); pl.Range=12; pl.Brightness=1.2
	local vp  = neon(Vector3.new(0.5,0.5,0.5), CFrame.new(sv[1],1,sv[2]), Color3.fromRGB(255,120,30), DECOR)
	pl.Parent = vp
end

-- ── Lava rivers (narrow neon trenches connecting pools) ───────────────────────
local RIVERS = {
	{ {18,680}, {-38,710} }, { {-15,775}, {38,800} }, { {0,860}, {-50,830} },
}
for _, rv in ipairs(RIVERS) do
	local ax,az = rv[1][1], rv[1][2]
	local bx,bz = rv[2][1], rv[2][2]
	local cx,cz = (ax+bx)/2, (az+bz)/2
	local len   = math.sqrt((bx-ax)^2+(bz-az)^2)
	local ang   = math.atan2(bz-az, bx-ax)
	Terrain:FillBlock(
		CFrame.new(cx,-0.5,cz)*CFrame.Angles(0,ang,0),
		Vector3.new(len, 2, 5), Enum.Material.CrackedLava)
end

-- ── Ash boulders (dark reddish rocks scattered throughout) ────────────────────
for _ = 1, 10 do
	local px = RNG:NextNumber(-84, 84)
	local pz = RNG:NextNumber(612, 888)
	local scl = 0.6 + RNG:NextNumber(0, 1.2)
	ball(Vector3.new(scl*3.5, scl*2.5, scl*3.5),
		CFrame.new(px, scl*1.1, pz) * CFrame.Angles(0, RNG:NextNumber(0, math.pi), 0),
		Color3.fromRGB(65,42,36), DECOR)
end

-- ── Floating lava drips (neon teardrops that add atmosphere) ──────────────────
for _ = 1, 18 do
	local px = RNG:NextNumber(-82,82); local pz = RNG:NextNumber(612,888)
	local py = RNG:NextNumber(2, 8)
	local ps = 0.35 + RNG:NextNumber(0, 0.5)
	neon(Vector3.new(ps,ps*1.8,ps), CFrame.new(px,py,pz), Color3.fromRGB(255,80,15), DECOR)
end

print("[WorldSetup] Volcano zone built.")

-- ─── Crystal Cavern zone (Z 905–1195) ────────────────────────────────────────
-- Deep underground crystal cave feel: ice-blue ground, giant glowing spires,
-- crystal clusters, shimmering neon pools.

pcall(function()
	Terrain:SetMaterialColor(Enum.Material.Ice,       Color3.fromRGB(108, 162, 220))  -- deeper blue ice (less white)
	Terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(196, 214, 238))  -- soft blue-grey (not near-white)
end)

Terrain:FillBlock(CFrame.new(0, -5, 1050), Vector3.new(VW+80, 10, 300), Enum.Material.Ice)
-- Cracked ice overlay patches
for _ = 1, 18 do
	local px = RNG:NextNumber(-82, 82)
	local pz = RNG:NextNumber(915, 1185)
	Terrain:FillCylinder(CFrame.new(px, -1.2, pz), 1.4, 10+RNG:NextNumber(0,18), Enum.Material.Ice)
end

-- Crystal spire builder
local function makeCrystalSpire(x, z, col, h, w)
	h = h or (8 + RNG:NextNumber(0, 14)); w = w or (1.2 + RNG:NextNumber(0, 1.0))
	-- Main shaft (tapered via stacked parts)
	for seg = 1, 4 do
		local sy = (seg - 1) * (h / 4)
		local sw = w * (1.2 - seg * 0.22)
		mk(Vector3.new(sw, h/4 + 0.2, sw),
			CFrame.new(x, sy + h/8, z) * CFrame.Angles(RNG:NextNumber(-0.08,0.08), 0, RNG:NextNumber(-0.06,0.06)),
			col, Enum.Material.SmoothPlastic, DECOR, true)
	end
	-- Neon glow crack down the center
	neon(Vector3.new(0.2, h * 0.8, 0.2), CFrame.new(x, h * 0.4, z),
		col:Lerp(Color3.fromRGB(255,255,255), 0.55), DECOR)
	-- Point light at tip
	local tip = neon(Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, h + 0.3, z), col, DECOR)
	local pl  = Instance.new("PointLight")
	pl.Color = col; pl.Range = 16; pl.Brightness = 1.8; pl.Parent = tip
end

-- Crystal cluster (group of 3-5 short spires)
local function makeCrystalCluster(cx, cz, col)
	local n = RNG:NextInteger(3, 5)
	for i = 1, n do
		local ox = RNG:NextNumber(-3, 3); local oz = RNG:NextNumber(-3, 3)
		local h  = 3 + RNG:NextNumber(0, 6)
		makeCrystalSpire(cx + ox, cz + oz, col, h, 0.8 + RNG:NextNumber(0, 0.6))
	end
end

local CRYSTAL_COLS = {
	Color3.fromRGB(120, 210, 255),  -- ice blue
	Color3.fromRGB(185, 120, 255),  -- amethyst
	Color3.fromRGB( 80, 200, 210),  -- teal
	Color3.fromRGB(210, 240, 255),  -- white crystal
	Color3.fromRGB(155,  90, 255),  -- deep violet
}

-- Large feature spires
for _, sp in ipairs({
	{-85,930},{90,955},{-70,990},{80,1020},{-90,1055},{75,1080},{-65,1115},{88,1145},{-80,1175},
}) do
	local col = CRYSTAL_COLS[RNG:NextInteger(1,#CRYSTAL_COLS)]
	makeCrystalSpire(sp[1], sp[2], col, 12+RNG:NextNumber(0,10), 1.8+RNG:NextNumber(0,1.2))
end

-- Mid-zone crystal clusters
for _ = 1, 8 do
	local col = CRYSTAL_COLS[RNG:NextInteger(1,#CRYSTAL_COLS)]
	makeCrystalCluster(RNG:NextNumber(-80, 80), RNG:NextNumber(920, 1180), col)
end

-- Glowing crystal pools (shallow neon discs)
local POOL_SPOTS = {{0,940},{-40,975},{55,1010},{-25,1060},{40,1100},{-60,1145},{20,1175}}
for _, ps in ipairs(POOL_SPOTS) do
	local col = CRYSTAL_COLS[RNG:NextInteger(1,#CRYSTAL_COLS)]
	neon(Vector3.new(ps[1]>0 and 14 or 18, 0.4, ps[1]>0 and 18 or 14),
		CFrame.new(ps[1], 0.2, ps[2]), col, DECOR)
	local glpl = Instance.new("PointLight")
	glpl.Color = col; glpl.Range = 22; glpl.Brightness = 1.4
	local gp = neon(Vector3.new(0.5,0.5,0.5), CFrame.new(ps[1],0.5,ps[2]), col, DECOR)
	glpl.Parent = gp
end

-- Ice boulders
for _ = 1, 9 do
	local scl = 0.7 + RNG:NextNumber(0, 1.0)
	ball(Vector3.new(scl*3.8, scl*2.6, scl*3.8),
		CFrame.new(RNG:NextNumber(-84,84), scl*1.2, RNG:NextNumber(918,1182)) * CFrame.Angles(0,RNG:NextNumber(0,math.pi),0),
		Color3.fromRGB(200, 235, 255), DECOR)
end

-- Crystal cave arch at center (decorative mega-crystal)
makeCrystalSpire(-12, 1050, Color3.fromRGB(185,120,255), 24, 3.2)
makeCrystalSpire( 12, 1050, Color3.fromRGB(120,210,255), 22, 2.8)
makeCrystalSpire(  0, 1048, Color3.fromRGB(210,240,255), 28, 2.2)

print("[WorldSetup] Crystal Cavern built.")

-- ─── Sky Realm zone (Z 1205–1495) ────────────────────────────────────────────
-- Elevated cloudscape feel: pale white ground, cloud puffs, sky pillars,
-- rainbow arcs, floating island chunks high above.

Terrain:FillBlock(CFrame.new(0, -5, 1350), Vector3.new(VW+80, 10, 300), Enum.Material.Sandstone)
-- Bright cloud-white patches on top
for _ = 1, 8 do
	local px = RNG:NextNumber(-84, 84)
	local pz = RNG:NextNumber(1210, 1490)
	Terrain:FillCylinder(CFrame.new(px, -0.8, pz), 1.2, 12+RNG:NextNumber(0,20), Enum.Material.Sandstone)
end

-- Cloud puff builder (clusters of white spheres)
local cloudWhite = Color3.fromRGB(248, 252, 255)
local function makeCloudPuff(cx, cy, cz, scl)
	scl = scl or 1
	local r = 3.5 * scl
	ball(Vector3.new(r*2.2, r*1.4, r*2.2), CFrame.new(cx, cy, cz), cloudWhite, DECOR)
	for i = 1, 5 do
		local a = (i/5)*math.pi*2
		local br = r * (0.7+RNG:NextNumber(0,0.3))
		ball(Vector3.new(br*1.8, br*1.2, br*1.8),
			CFrame.new(cx + math.cos(a)*r*0.75, cy + RNG:NextNumber(-0.5,0.5)*scl, cz + math.sin(a)*r*0.75),
			cloudWhite, DECOR)
	end
end

-- Ground-level cloud puffs
for _ = 1, 8 do
	makeCloudPuff(RNG:NextNumber(-84,84), RNG:NextNumber(2,5), RNG:NextNumber(1215,1485),
		0.6 + RNG:NextNumber(0,0.8))
end

-- Tall sky pillars (white/pale blue columns reaching upward)
local SKY_PILLAR_SPOTS = {
	{-88,1225},{88,1245},{-70,1280},{72,1305},{-90,1345},{85,1370},
	{-65,1410},{80,1435},{-82,1465},{78,1485},
}
for _, sp in ipairs(SKY_PILLAR_SPOTS) do
	local h = 18 + RNG:NextNumber(0, 22)
	local w = 2.2 + RNG:NextNumber(0, 1.2)
	mk(Vector3.new(w, h, w), CFrame.new(sp[1], h/2, sp[2]),
		Color3.fromRGB(235, 248, 255), Enum.Material.SmoothPlastic, DECOR, true)
	-- Glowing top
	local tipCol = Color3.fromRGB(180, 230, 255)
	local tipP = neon(Vector3.new(w+0.4, 1.2, w+0.4), CFrame.new(sp[1], h+0.6, sp[2]), tipCol, DECOR)
	local pl = Instance.new("PointLight"); pl.Color=tipCol; pl.Range=18; pl.Brightness=1.6; pl.Parent=tipP
end

-- Floating islands high above (platform chunks at Y=35-55)
local FLOAT_ISLANDS = {
	{-30,1260,42, 18,8,18}, {50,1320,38, 14,6,16}, {-55,1380,46, 20,7,20},
	{25,1440,40, 16,6,14},  {0,1350,50, 24,8,22},
}
for _, fi in ipairs(FLOAT_ISLANDS) do
	local x,z,y,w,h,d = fi[1],fi[2],fi[3],fi[4],fi[5],fi[6]
	-- Island base (grassy top, rock underside)
	mk(Vector3.new(w,h/2,d), CFrame.new(x,y,z), Color3.fromRGB(80,180,80), Enum.Material.SmoothPlastic, DECOR, true)
	mk(Vector3.new(w-2,h/2,d-2), CFrame.new(x,y-h/4,z), Color3.fromRGB(140,120,90), Enum.Material.Rock, DECOR, true)
	-- Tiny cloud puffs around each island
	for i=1,3 do
		local a=(i/3)*math.pi*2
		makeCloudPuff(x+math.cos(a)*(w*0.4), y+1, z+math.sin(a)*(d*0.4), 0.4)
	end
end

-- Rainbow arc (colored thin bar strips bridging center)
local RAINBOW = {
	Color3.fromRGB(255,80,80), Color3.fromRGB(255,180,60), Color3.fromRGB(255,240,80),
	Color3.fromRGB(80,220,80), Color3.fromRGB(80,180,255), Color3.fromRGB(140,80,255),
}
for i, col in ipairs(RAINBOW) do
	local r = 32 + i * 2.8
	for seg = 1, 12 do
		local a = (seg/12) * math.pi  -- 180° arc
		local rx = math.cos(a) * r
		local ry = math.sin(a) * r * 0.55 + 10  -- arch up
		neon(Vector3.new(4, 1.2, 1.2), CFrame.new(rx, ry, 1350) * CFrame.Angles(0, 0, a),
			col, DECOR)
	end
end

-- Wind spiral pillars (twisted look via stacked offset parts)
for _, ws in ipairs({{-38,1280},{45,1400},{-20,1460}}) do
	for j=1,8 do
		local a = j * 0.45
		local ox = math.cos(a)*1.5; local oy = j*2.8; local oz = math.sin(a)*1.5
		neon(Vector3.new(0.6,2.8,0.6), CFrame.new(ws[1]+ox, oy, ws[2]+oz),
			Color3.fromRGB(200,235,255), DECOR)
	end
end

print("[WorldSetup] Sky Realm built.")

-- ─── Shadow Abyss zone (Z 1505–1795) ─────────────────────────────────────────
-- Endgame dark dimension: void-black ground, towering obsidian monoliths,
-- purple neon rifts, floating dark orbs, eerie light sources.

Terrain:FillBlock(CFrame.new(0, -5, 1650), Vector3.new(VW+80, 10, 300), Enum.Material.Basalt)
pcall(function()
	-- Note: material colors set at start; Basalt already set dark for volcano.
	-- The abyss uses the same dark material.
end)

-- Dark void ground patches (even darker)
for _ = 1, 8 do
	local px = RNG:NextNumber(-84, 84)
	local pz = RNG:NextNumber(1510, 1790)
	Terrain:FillCylinder(CFrame.new(px, -1.5, pz), 1.8, 10+RNG:NextNumber(0,22), Enum.Material.Basalt)
end

-- Void rift builder (glowing vertical portal-like slab)
local function makeVoidRift(x, z, col, h)
	h = h or 10
	-- Dark frame
	mk(Vector3.new(0.8, h, 0.8), CFrame.new(x-2, h/2, z),
		Color3.fromRGB(12,8,20), Enum.Material.SmoothPlastic, DECOR, true)
	mk(Vector3.new(0.8, h, 0.8), CFrame.new(x+2, h/2, z),
		Color3.fromRGB(12,8,20), Enum.Material.SmoothPlastic, DECOR, true)
	mk(Vector3.new(5.6, 0.8, 0.8), CFrame.new(x, h+0.4, z),
		Color3.fromRGB(12,8,20), Enum.Material.SmoothPlastic, DECOR, true)
	-- Neon glow interior
	neon(Vector3.new(3.2, h*0.9, 0.4), CFrame.new(x, h*0.5, z), col, DECOR)
	local pl = Instance.new("PointLight")
	pl.Color=col; pl.Range=20; pl.Brightness=2.2
	local rp = neon(Vector3.new(0.4,0.4,0.4), CFrame.new(x,h*0.5,z), col, DECOR)
	pl.Parent = rp
end

local ABYSS_COLS = {
	Color3.fromRGB(150, 50, 255),   -- deep purple
	Color3.fromRGB(200, 30, 120),   -- magenta
	Color3.fromRGB( 60, 10, 200),   -- indigo
	Color3.fromRGB(255, 50, 200),   -- neon pink
}

-- Void rifts scattered across abyss
local RIFT_SPOTS = {
	{0,1540},{-55,1570},{60,1600},{-30,1640},{45,1680},
	{-70,1710},{35,1750},{-40,1780},
}
for _, rs in ipairs(RIFT_SPOTS) do
	local col = ABYSS_COLS[RNG:NextInteger(1,#ABYSS_COLS)]
	makeVoidRift(rs[1], rs[2], col, 8+RNG:NextNumber(0,8))
end

-- Massive obsidian monoliths (tall black slabs, the defining feature)
local OBSIDIAN2 = Color3.fromRGB(12, 8, 22)
local MONO_SPOTS = {
	{-92,1520},{90,1545},{-75,1590},{80,1620},{-88,1660},{85,1695},{-70,1730},{88,1760},
}
for _, ms in ipairs(MONO_SPOTS) do
	local h = 16 + RNG:NextNumber(0, 20)
	local w = 2.8 + RNG:NextNumber(0, 1.4)
	local d = 1.4 + RNG:NextNumber(0, 0.8)
	mk(Vector3.new(w, h, d), CFrame.new(ms[1], h/2, ms[2]),
		OBSIDIAN2, Enum.Material.SmoothPlastic, DECOR, true)
	-- Subtle purple crack lines
	local crCol = ABYSS_COLS[RNG:NextInteger(1,#ABYSS_COLS)]
	neon(Vector3.new(0.2, h*0.75, 0.2), CFrame.new(ms[1]+w*0.3, h*0.42, ms[2]),  crCol, DECOR)
	neon(Vector3.new(0.2, h*0.55, 0.2), CFrame.new(ms[1]-w*0.25, h*0.52, ms[2]), crCol, DECOR)
end

-- Floating dark orbs (anchored parts at varying heights)
for _ = 1, 9 do
	local ox = RNG:NextNumber(-82, 82)
	local oz = RNG:NextNumber(1518, 1782)
	local oy = RNG:NextNumber(4, 18)
	local os = 1.2 + RNG:NextNumber(0, 1.8)
	local oc = ABYSS_COLS[RNG:NextInteger(1,#ABYSS_COLS)]
	ball(Vector3.new(os*2, os*2, os*2), CFrame.new(ox, oy, oz), OBSIDIAN2, DECOR)
	-- Glow ring
	neon(Vector3.new(os*2.4, 0.3, os*2.4), CFrame.new(ox, oy-os*0.9, oz), oc, DECOR)
	local pl = Instance.new("PointLight"); pl.Color=oc; pl.Range=10; pl.Brightness=1.2
	local gp = neon(Vector3.new(0.4,0.4,0.4), CFrame.new(ox,oy,oz), oc, DECOR)
	pl.Parent = gp
end

-- Dark ground embers (low neon wisps at ground level)
for _ = 1, 10 do
	local ex = RNG:NextNumber(-84, 84)
	local ez = RNG:NextNumber(1515, 1785)
	local ec = ABYSS_COLS[RNG:NextInteger(1,#ABYSS_COLS)]
	neon(Vector3.new(0.4, 1.2+RNG:NextNumber(0,2.0), 0.4), CFrame.new(ex, 0.6+RNG:NextNumber(0,1), ez), ec, DECOR)
end

-- (Removed the giant void monolith — with 30 zones it sat right at the Inferno
-- gate (z≈1800) and poked up above the black wall, looking like one black mass.)

print("[WorldSetup] Shadow Abyss built.")

-- ─── Zone gates ───────────────────────────────────────────────────────────────
local function buildGate(gateZ, zoneName, cost, accentCol, emoji)
	local gf    = Instance.new("Folder")
	gf.Name     = "Gate_" .. zoneName
	gf.Parent   = workspace

	-- (No neon trim / posts — just the plain black wall with the name + price.)

	-- Solid near-BLACK wall to the next stage. Full valley width, too tall to
	-- jump, reaches below the surface.
	local barrier = mk(Vector3.new(VW,40,2.5), CFrame.new(0,16,gateZ+1.5),
		Color3.fromRGB(6, 7, 14), Enum.Material.SmoothPlastic, gf, false, 0.0)
	barrier.Name = "ZoneBarrier_" .. zoneName
	barrier:SetAttribute("UnlockCost", cost)
	barrier:SetAttribute("ZoneName",   zoneName)

	-- Clean text painted on the wall (SurfaceGui, like the leaderboard — no
	-- floating billboard, no emoji boxes). Double-sided so it reads both ways.
	local costStr = Config.fmtNum(cost) .. " Coins"
	local function gateFace(face)
		local sg = Instance.new("SurfaceGui")
		sg.Name           = "GateGui_" .. face.Name
		sg.Adornee        = barrier
		sg.Face           = face
		sg.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud  = 18
		sg.LightInfluence = 0
		sg.Parent         = barrier

		local ttl = Instance.new("TextLabel")
		ttl.Size = UDim2.new(0.46,0,0.40,0); ttl.Position = UDim2.new(0.27,0,0.12,0)
		ttl.BackgroundTransparency = 1
		ttl.Text = string.upper(zoneName)
		ttl.TextColor3 = accentCol
		ttl.Font = Enum.Font.GothamBlack
		ttl.TextScaled = true; ttl.TextStrokeTransparency = 0.35
		ttl.Parent = sg

		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(0.46,0,0.26,0); sub.Position = UDim2.new(0.27,0,0.56,0)
		sub.BackgroundTransparency = 1
		sub.Text = "Unlock  •  " .. costStr
		sub.TextColor3 = Color3.fromRGB(255, 225, 90)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		local sc = Instance.new("UITextSizeConstraint"); sc.MaxTextSize = 60; sc.Parent = sub
		sub.Parent = sg
	end
	gateFace(Enum.NormalId.Front)
	gateFace(Enum.NormalId.Back)

	local pp = Instance.new("ProximityPrompt")
	pp.ObjectText   = zoneName .. " Zone"
	pp.ActionText   = "Unlock  " .. costStr
	pp.KeyboardKeyCode = Enum.KeyCode.F
	pp.MaxActivationDistance = 14
	pp.HoldDuration  = 0
	pp.RequiresLineOfSight = false
	pp.Parent = barrier

	return barrier
end

-- One gate at the entrance of every stage after the first (data-driven, 30 stages).
for i = 2, #Config.ZONES do
	local z = Config.ZONES[i]
	buildGate(z.gateZ, z.name, z.unlockCost, z.color, "")
end

-- ── Procedural themed stages 7-30 ──────────────────────────────────────────
-- Stages 1-6 are hand-built; the rest get a clean themed arena: a paved floor
-- with a border + medallion, framing lamp pillars, crystal clusters, and a
-- floating gem centrepiece. Simple, tidy, and colour-themed per stage.
do
	local floors = Instance.new("Folder"); floors.Name = "StageFloors"; floors.Parent = workspace
	local WHT, BLK = Color3.new(1,1,1), Color3.new(0,0,0)

	-- A crystal shard: a diamond prism with a brighter tip (glass = no glow wash)
	local function shard(x, z, h, col)
		mk(Vector3.new(2.6, h, 2.6), CFrame.new(x, h*0.5, z) * CFrame.Angles(0, math.pi/4, 0),
			col:Lerp(WHT, 0.10), Enum.Material.Glass, floors, true)
		mk(Vector3.new(1.5, h*0.45, 1.5), CFrame.new(x, h*0.95, z) * CFrame.Angles(0, math.pi/4, 0),
			col:Lerp(WHT, 0.45), Enum.Material.Glass, floors, true)
	end
	local function cluster(cx, cz, col)
		shard(cx,     cz,     9 + RNG:NextNumber(0,5), col)
		shard(cx-3.2, cz+1.6, 6 + RNG:NextNumber(0,4), col)
		shard(cx+2.9, cz-1.4, 7 + RNG:NextNumber(0,4), col)
	end
	-- A clean framing pillar with a coloured cap + orb
	local function pillar(x, z, col)
		mk(Vector3.new(3, 15, 3),   CFrame.new(x, 7.5, z),  Color3.fromRGB(58,60,72), Enum.Material.Slate, floors, true)
		mk(Vector3.new(4.4, 1.8, 4.4), CFrame.new(x, 15.4, z), col, Enum.Material.SmoothPlastic, floors, true)
		local orb = mk(Vector3.new(2.8,2.8,2.8), CFrame.new(x, 17, z), col:Lerp(WHT,0.3), Enum.Material.SmoothPlastic, floors, true)
		orb.Shape = Enum.PartType.Ball
	end

	local STONE = Color3.fromRGB(58,60,72)
	local function floatGem(cz, col, y)
		mk(Vector3.new(7, 9, 7), CFrame.new(0, y or 12, cz) * CFrame.Angles(0.35, math.pi/4, 0),
			col:Lerp(WHT, 0.2), Enum.Material.Glass, floors, true)
		mk(Vector3.new(3, (y or 12)-1, 3), CFrame.new(0, ((y or 12)-1)/2, cz), STONE, Enum.Material.Slate, floors, true)
	end
	local function spike(x, z, h, col)
		mk(Vector3.new(2.0, h, 2.0), CFrame.new(x, h*0.5, z) * CFrame.Angles(0, math.pi/4, 0.04),
			col:Lerp(WHT, 0.12), Enum.Material.Glass, floors, true)
	end
	local function platform(x, z, y, s, col)
		mk(Vector3.new(s, 2, s), CFrame.new(x, y, z), col:Lerp(STONE, 0.4), Enum.Material.SmoothPlastic, floors)
		mk(Vector3.new(2.4, y, 2.4), CFrame.new(x, y/2, z), STONE, Enum.Material.Slate, floors, true)
	end

	local function J(n) return RNG:NextNumber(-n, n) end
	local function orbAt(x, y, z, col)
		local o = mk(Vector3.new(5.5,5.5,5.5), CFrame.new(x,y,z), col:Lerp(WHT,0.3), Enum.Material.SmoothPlastic, floors, true)
		o.Shape = Enum.PartType.Ball; return o
	end

	-- ── 7 templates. Props live around the EDGES/CORNERS — the centre stays
	-- open (clear walking path). Per-stage jitter keeps repeats looking different.
	local TEMPLATES = {
		-- 1: Crystal — edge clusters (no dark pillars; they merged with the gate wall)
		function(cz, col)
			cluster(-92,cz+J(24),col); cluster(92,cz+J(24),col); cluster(J(24),cz-94,col); cluster(J(24),cz+94,col)
			cluster(-92,cz-40+J(16),col); cluster(92,cz+40+J(16),col)
		end,
		-- 2: Ruins — broken pillars around the rim + a few fallen blocks at edges
		function(cz, col)
			for _, p in ipairs({ {-92,cz-60,16},{92,cz-40,11},{-90,cz+55,13},{90,cz+72,8},{-55,cz-94,14},{58,cz+94,10} }) do
				mk(Vector3.new(5,p[3],5), CFrame.new(p[1]+J(5), p[3]/2, p[2]+J(6))*CFrame.Angles(0,RNG:NextNumber(0,3),J(0.12)),
					col:Lerp(STONE,0.55), Enum.Material.Slate, floors, true)
			end
			for _=1,3 do
				local sx = (RNG:NextNumber(0,1)<0.5 and -1 or 1) * RNG:NextNumber(78,95)
				mk(Vector3.new(6,3,6), CFrame.new(sx,1.5,cz+J(95))*CFrame.Angles(0,RNG:NextNumber(0,3),0), col:Lerp(STONE,0.5), Enum.Material.Slate, floors, true)
			end
		end,
		-- 3: Floating platforms in the corners
		function(cz, col)
			platform(-86+J(6),cz-78+J(6),8,28,col); platform(86+J(6),cz-78+J(6),12,26,col)
			platform(-86+J(6),cz+78+J(6),14,24,col); platform(86+J(6),cz+78+J(6),9,28,col)
		end,
		-- 4: Spike field — clusters hugging the edges
		function(cz, col)
			for _, c in ipairs({ {-90,cz-50},{92,cz-30},{-90,cz+58},{92,cz+62},{J(24),cz-96},{J(24),cz+96} }) do
				spike(c[1]+J(4),c[2]+J(5),11+RNG:NextNumber(0,8),col)
				spike(c[1]-3.5,c[2]+2,6+RNG:NextNumber(0,5),col); spike(c[1]+3.2,c[2]-2,7+RNG:NextNumber(0,5),col)
			end
		end,
		-- 5: Orb-ring around the rim
		function(cz, col)
			for k=1,8 do local a=(k/8)*math.pi*2+J(0.15); orbAt(math.cos(a)*92, 3, cz+math.sin(a)*92, col) end
			cluster(J(20),cz-94,col); cluster(J(20),cz+94,col)
		end,
		-- 6: Orb ring (open centre)
		function(cz, col)
			for k=1,10 do local a=(k/10)*math.pi*2+J(0.18); orbAt(math.cos(a)*90, 3+RNG:NextNumber(0,2), cz+math.sin(a)*90, col) end
		end,
		-- 7: Side platforms + edge crystals
		function(cz, col)
			platform(-86,cz,9,30,col); platform(86,cz,11,30,col)
			cluster(J(24),cz-94,col); cluster(J(24),cz+94,col)
		end,
	}

	for i = 7, #Config.ZONES do
		local z   = Config.ZONES[i]
		local cz  = z.gateZ + 150
		local col = z.color

		-- paved floor + border curbs + centre medallion (common to every stage)
		mk(Vector3.new(300, 4, 300), CFrame.new(0, -2, cz), col:Lerp(Color3.fromRGB(58,62,74), 0.58),
			Enum.Material.SmoothPlastic, floors)
		mk(Vector3.new(300, 1.2, 10), CFrame.new(0, 0.3, cz-145), col:Lerp(BLK,0.35), Enum.Material.SmoothPlastic, floors, true)
		mk(Vector3.new(300, 1.2, 10), CFrame.new(0, 0.3, cz+145), col:Lerp(BLK,0.35), Enum.Material.SmoothPlastic, floors, true)

		TEMPLATES[((i - 7) % #TEMPLATES) + 1](cz, col)
	end
end

-- ── Invisible side walls (tall) — confine players to the valley so they can't
-- walk around the gates. Original invisible style, just much taller.
do
	local walls = Instance.new("Folder"); walls.Name = "SideWalls"; walls.Parent = workspace
	for _, sx in ipairs({ -98, 98 }) do
		local w = mk(Vector3.new(4, 240, LAST_Z + 400), CFrame.new(sx, 110, LAST_Z/2 - 60),
			Color3.fromRGB(120,120,130), Enum.Material.SmoothPlastic, walls, false, 1)
		w.Name = "SideWall"
	end
end

-- ─── Ambient mushroom glows ───────────────────────────────────────────────────
for i = 1, 6 do
	local col = MUSH_COLS[((i-1) % #MUSH_COLS) + 1]
	local gp  = neon(Vector3.new(0.5,0.5,0.5),
		CFrame.new(RNG:NextNumber(-78,78), 1.5, RNG:NextNumber(20,260)),
		col, DECOR)
	gp.Transparency = 0.9
	local pl = Instance.new("PointLight")
	pl.Range = 14; pl.Brightness = 1; pl.Color = col; pl.Parent = gp
end

-- ─── Leaderboard Monuments (spawn area) ──────────────────────────────────────
-- Two-post noticeboard style matching the reference:
-- cylindrical posts with disc caps → wide flat board between them.
-- Positioned at Z≈85 so players see them right after spawning at Z=50.

local MON_BOARD  = Color3.fromRGB(175, 115, 140)   -- warm pink-purple board
local MON_PILLAR = Color3.fromRGB(140,  90, 165)   -- purple pillar
local MON_CAP    = Color3.fromRGB( 90, 115, 215)   -- blue cap discs
local MON_TRIM   = Color3.fromRGB(125,  75, 150)   -- darker trim strip

-- Helpers specific to monuments (parents to a folder)
local function mcyl(len, dia, cx, cy, cz, col, parent)
	local p = Instance.new("Part")
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = Vector3.new(len, dia, dia)
	p.CFrame   = CFrame.new(cx, cy, cz) * CFrame.Angles(0, 0, math.pi/2)
	p.Color    = col; p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = true; p.CastShadow = false; p.Parent = parent
	return p
end
local function mbox(sx, sy, sz_, cx, cy, cz, col, parent)
	return mk(Vector3.new(sx,sy,sz_), CFrame.new(cx,cy,cz), col, Enum.Material.SmoothPlastic, parent)
end

-- Leaderboards live in the SPAWN PLAZA (south of the forest, negative Z).
-- Player spawns at z=-28 facing +Z and reads these before walking into the forest.
local MON_DEFS = {
	{ x=-62, z=-20, title="Most Coins",    unit="Coins",    attr="coins"      },
	{ x=  0, z=-20, title="Most Rolls",    unit="Rolls",    attr="totalRolls" },
	{ x= 62, z=-20, title="Most Rebirths", unit="Rebirths", attr="rebirths"   },
}

local BW  = 16    -- board width
local BH  = 12    -- board height
local PH  = 17    -- pillar height (sticks up above board)
local PD  = 1.8   -- pillar diameter
local CD  = 2.8   -- cap disc diameter
local PX  = BW/2 + PD*0.5 + 0.3   -- pillar X offset from centre

-- Build a leaderboard panel on one face of the board (called for Front + Back)
local function buildBoardFace(sign, face, title)
	local sg = Instance.new("SurfaceGui")
	sg.Name           = "LBGui_" .. face.Name
	sg.Adornee        = sign
	sg.Face           = face
	sg.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud  = 48
	sg.LightInfluence = 0
	sg.Parent         = sign

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1,1); bg.BackgroundColor3 = Color3.fromRGB(26,16,40)
	bg.BackgroundTransparency = 0.12; bg.BorderSizePixel = 0; bg.Parent = sg

	local ttl = Instance.new("TextLabel")
	ttl.Size = UDim2.new(0.96,0,0.17,0); ttl.Position = UDim2.new(0.02,0,0.02,0)
	ttl.BackgroundTransparency = 1
	ttl.Text = title
	ttl.TextColor3 = Color3.fromRGB(255,225,55)
	ttl.Font = Enum.Font.GothamBlack
	ttl.TextScaled = true; ttl.TextStrokeTransparency = 0.3
	local tc = Instance.new("UITextSizeConstraint"); tc.MaxTextSize = 64; tc.Parent = ttl
	ttl.Parent = bg

	for row = 1, 5 do
		local rl = Instance.new("TextLabel")
		rl.Name = "Row"..row
		rl.Size = UDim2.new(0.92,0,0.142,0)
		rl.Position = UDim2.new(0.04,0,0.205 + (row-1)*0.155,0)
		rl.BackgroundColor3 = Color3.fromRGB(255,255,255); rl.BackgroundTransparency = 0.88
		rl.BorderSizePixel = 0
		rl.Text = row..".   —"
		rl.TextColor3 = Color3.fromRGB(235,228,245)
		rl.Font = Enum.Font.GothamBold
		rl.TextScaled = true
		rl.TextXAlignment = Enum.TextXAlignment.Left
		local rc = Instance.new("UITextSizeConstraint"); rc.MaxTextSize = 34; rc.Parent = rl
		local rpad = Instance.new("UIPadding"); rpad.PaddingLeft = UDim.new(0,10); rpad.Parent = rl
		local rcorner = Instance.new("UICorner"); rcorner.CornerRadius = UDim.new(0,6); rcorner.Parent = rl
		rl.Parent = bg
	end
end

for _, md in ipairs(MON_DEFS) do
	local x, z = md.x, md.z
	local mf   = Instance.new("Folder"); mf.Name="Monument_"..md.attr; mf.Parent=workspace

	-- ── Left post ────────────────────────────────────────────────────────────
	mcyl(PH, PD, x-PX, PH/2, z, MON_PILLAR, mf)
	mcyl(0.9, CD, x-PX, 0.45, z, MON_CAP, mf)
	mcyl(0.9, CD, x-PX, PH/2, z, MON_CAP, mf)
	mcyl(0.9, CD+0.4, x-PX, PH+0.45, z, MON_CAP, mf)

	-- ── Right post ───────────────────────────────────────────────────────────
	mcyl(PH, PD, x+PX, PH/2, z, MON_PILLAR, mf)
	mcyl(0.9, CD, x+PX, 0.45, z, MON_CAP, mf)
	mcyl(0.9, CD, x+PX, PH/2, z, MON_CAP, mf)
	mcyl(0.9, CD+0.4, x+PX, PH+0.45, z, MON_CAP, mf)

	-- ── Board ──────────────────────────────────────────────────────────────────
	mbox(BW+1.2, BH+1.2, 0.6, x, PH/2, z, MON_TRIM, mf)
	local sign = mbox(BW, BH, 0.8, x, PH/2, z, MON_BOARD, mf)
	sign.Name  = "LBSign_"..md.attr

	local pl = Instance.new("PointLight"); pl.Color=Color3.fromRGB(255,230,200)
	pl.Range=22; pl.Brightness=0.9; pl.Parent=sign

	-- Double-sided so it reads from either approach direction
	buildBoardFace(sign, Enum.NormalId.Front, md.title)
	buildBoardFace(sign, Enum.NormalId.Back,  md.title)

	sign:SetAttribute("MonumentAttr", md.attr)
end

-- ─── SPAWN PLAZA + FOREST ENTRANCE ─────────────────────────────────────────
-- A large RAISED stone plaza backed by the rock cliff: leaderboards, lamp
-- posts, planters and a tiered fountain. Walk north (+Z) through the arch to
-- enter Zone 1 (the Forest).
do
	local plaza = Instance.new("Folder"); plaza.Name = "SpawnPlaza"; plaza.Parent = workspace
	local STONE = Color3.fromRGB(206, 202, 214)
	local STON2 = Color3.fromRGB(176, 172, 188)
	local STON3 = Color3.fromRGB(148, 144, 160)
	local WOOD  = Color3.fromRGB(124, 82, 46)
	local WOOD2 = Color3.fromRGB(152, 104, 60)
	local LAMP  = Color3.fromRGB(255, 226, 150)
	local WATER = Color3.fromRGB(95, 180, 255)

	local CX, CZ = 0, -58          -- plaza centre
	local HW, HD = 80, 64          -- half sizes  (160 x 128)
	local FT     = 2.0             -- floor top height (raised above grass)

	-- Box sitting ON the plaza floor (base at FT)
	local function onFloor(sx, sy, sz_, px, pz, col, mat, noCol)
		return mk(Vector3.new(sx,sy,sz_), CFrame.new(px, FT + sy/2, pz), col, mat or Enum.Material.SmoothPlastic, plaza, noCol)
	end

	-- ── Raised paved floor (two slate slabs + medallion) ──
	mk(Vector3.new(HW*2, FT+0.4, HD*2),     CFrame.new(CX, (FT+0.4)/2 - 0.2, CZ), STON3, Enum.Material.Slate, plaza)
	mk(Vector3.new(HW*2-4, 0.5, HD*2-4),    CFrame.new(CX, FT+0.05, CZ),          STONE, Enum.Material.Slate, plaza)
	mk(Vector3.new(HW*2-30, 0.5, HD*2-30),  CFrame.new(CX, FT+0.12, CZ),          STON2, Enum.Material.Slate, plaza)
	mcyl(0.5, 34, CX, FT+0.25, CZ, STONE, plaza)
	mcyl(0.4, 24, CX, FT+0.32, CZ, STON2, plaza)

	-- Entrance steps (north edge, lead down toward the forest)
	mk(Vector3.new(40, FT, 4), CFrame.new(CX, FT/2, CZ+HD+1.5), STON2, Enum.Material.Slate, plaza)
	mk(Vector3.new(40, FT*0.55, 4), CFrame.new(CX, (FT*0.55)/2, CZ+HD+4.5), STON3, Enum.Material.Slate, plaza)

	-- ── Corner + mid lamp posts ──
	local function lamp(px, pz)
		onFloor(1.6, 15, 1.6, px, pz, STON3, Enum.Material.Slate)
		local orb = neon(Vector3.new(3.2,3.2,3.2), CFrame.new(px, FT+16, pz), LAMP, plaza)
		orb.Shape = Enum.PartType.Ball
		local pl = Instance.new("PointLight"); pl.Color=LAMP; pl.Range=30; pl.Brightness=2.4; pl.Parent=orb
	end
	lamp(CX-HW+7, CZ-HD+7); lamp(CX+HW-7, CZ-HD+7)
	lamp(CX-HW+7, CZ+HD-7); lamp(CX+HW-7, CZ+HD-7)
	lamp(CX-HW+7, CZ-28);   lamp(CX+HW-7, CZ-28)
	lamp(CX-HW+7, CZ+28);   lamp(CX+HW-7, CZ+28)

	-- ── Planters with bushes along the back ──
	local function planter(px, pz)
		onFloor(9, 3, 6, px, pz, WOOD, Enum.Material.WoodPlanks)
		local b1 = mk(Vector3.new(6,6,6), CFrame.new(px-1.8, FT+4, pz), C.darkGreen, Enum.Material.Grass, plaza, true); b1.Shape=Enum.PartType.Ball
		local b2 = mk(Vector3.new(6,6,6), CFrame.new(px+1.8, FT+4, pz), C.midGreen,  Enum.Material.Grass, plaza, true); b2.Shape=Enum.PartType.Ball
	end
	-- back row
	planter(CX-54, CZ-HD+6); planter(CX-30, CZ-HD+6); planter(CX-6, CZ-HD+6)
	planter(CX+18, CZ-HD+6); planter(CX+42, CZ-HD+6); planter(CX+66, CZ-HD+6)
	-- side rows
	planter(CX-HW+9, CZ-44); planter(CX-HW+9, CZ+16)
	planter(CX+HW-9, CZ-44); planter(CX+HW-9, CZ+16)

	-- ── Tiered fountain (centre) ──
	-- Lower basin
	mcyl(2.4, 22, CX, FT+1.2, CZ, STON2, plaza)
	mcyl(2.0, 19, CX, FT+1.5, CZ, STON3, plaza)
	mcyl(1.2, 17, CX, FT+2.1, CZ, WATER, plaza)                 -- lower water
	-- Pedestal
	mcyl(5.0, 4.5, CX, FT+4.2, CZ, STONE, plaza)
	-- Upper basin
	mcyl(1.6, 11, CX, FT+6.6, CZ, STON2, plaza)
	mcyl(1.0, 8.5, CX, FT+7.1, CZ, WATER, plaza)                -- upper water
	-- Finial + jets
	mcyl(3.2, 1.6, CX, FT+8.6, CZ, STONE, plaza)
	local jet = neon(Vector3.new(1.6, 4.5, 1.6), CFrame.new(CX, FT+11, CZ), Color3.fromRGB(170,220,255), plaza)
	jet.Shape = Enum.PartType.Cylinder; jet.CFrame = CFrame.new(CX, FT+11, CZ) * CFrame.Angles(0,0,math.pi/2)
	jet.Transparency = 0.35
	local top = neon(Vector3.new(2.4,2.4,2.4), CFrame.new(CX, FT+13, CZ), Color3.fromRGB(190,230,255), plaza)
	top.Shape = Enum.PartType.Ball; top.Transparency = 0.25
	local fpl = Instance.new("PointLight"); fpl.Color=WATER; fpl.Range=28; fpl.Brightness=1.6; fpl.Parent=top

	-- ── Forest entrance arch (north edge) ──
	local AZ = CZ + HD - 1
	onFloor(4, 20, 4, -28, AZ, WOOD, Enum.Material.WoodPlanks)
	onFloor(4, 20, 4,  28, AZ, WOOD, Enum.Material.WoodPlanks)
	mk(Vector3.new(64, 5.5, 4), CFrame.new(0, FT+21, AZ), WOOD2, Enum.Material.WoodPlanks, plaza)
	local t1 = mk(Vector3.new(9,7,9), CFrame.new(-28, FT+22, AZ), C.midGreen,  Enum.Material.Grass, plaza, true); t1.Shape=Enum.PartType.Ball
	local t2 = mk(Vector3.new(9,7,9), CFrame.new( 28, FT+22, AZ), C.darkGreen, Enum.Material.Grass, plaza, true); t2.Shape=Enum.PartType.Ball

	local signPart = mk(Vector3.new(42, 8, 1.2), CFrame.new(0, FT+21, AZ-1.2), WOOD2, Enum.Material.WoodPlanks, plaza, true)
	-- Clean SurfaceGui text on both faces (no emoji boxes), like the gates.
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Adornee = signPart; sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 22; sg.LightInfluence = 0; sg.Parent = signPart
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.92,0,0.7,0); lbl.Position = UDim2.new(0.04,0,0.15,0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "ZONE 1  ·  FOREST"
		lbl.TextColor3 = Color3.fromRGB(255, 240, 200)
		lbl.Font = Enum.Font.GothamBlack; lbl.TextScaled = true; lbl.TextStrokeTransparency = 0.3
		lbl.Parent = sg
	end

	-- ── Floating "SPAWN" marker over the fountain ──
	local marker = mk(Vector3.new(1,1,1), CFrame.new(CX, FT+15, CZ), STONE, Enum.Material.SmoothPlastic, plaza, true, 1)
	local mbb = Instance.new("BillboardGui")
	mbb.Size = UDim2.fromOffset(200, 44); mbb.StudsOffset = Vector3.new(0, 3, 0)
	mbb.AlwaysOnTop = true; mbb.MaxDistance = 160; mbb.Adornee = marker; mbb.Parent = marker
	local mlbl = Instance.new("TextLabel")
	mlbl.Size = UDim2.fromScale(1,1); mlbl.BackgroundTransparency = 1
	mlbl.Text = "SPAWN"; mlbl.TextColor3 = Color3.fromRGB(255, 225, 120)
	mlbl.Font = Enum.Font.GothamBlack; mlbl.TextScaled = true; mlbl.TextStrokeTransparency = 0.35
	mlbl.Parent = mbb
end

print("[WorldSetup] Done.")

