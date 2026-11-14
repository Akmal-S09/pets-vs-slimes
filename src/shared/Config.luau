-- Config.luau — Pet RNG (SlimeDice)

local Config = {}

-- ─── ZONES (30 stages, generated) ────────────────────────────────────────────
-- Each stage is a 300-stud segment further north. Difficulty & rewards grow
-- geometrically so the whole run is a long but steady climb.
local ZONE_LIST = {
	{"forest","Forest",      Color3.fromRGB( 40,160, 60)},
	{"desert","Desert",      Color3.fromRGB(230,180, 40)},
	{"volcano","Volcano",    Color3.fromRGB(255, 80, 20)},
	{"crystal","Crystal",    Color3.fromRGB(120,210,255)},
	{"sky","Sky",            Color3.fromRGB(180,230,255)},
	{"abyss","Abyss",        Color3.fromRGB(150, 50,255)},
	{"inferno","Inferno",    Color3.fromRGB(255, 60,  0)},
	{"glacier","Glacier",    Color3.fromRGB(120,220,235)},
	{"swamp","Swamp",        Color3.fromRGB( 90,140, 70)},
	{"canyon","Canyon",      Color3.fromRGB(205,120, 70)},
	{"tundra","Tundra",      Color3.fromRGB(205,232,245)},
	{"jungle","Jungle",      Color3.fromRGB( 40,150, 70)},
	{"mirage","Mirage",      Color3.fromRGB(240,210,120)},
	{"thunder","Thunder",    Color3.fromRGB(255,225, 80)},
	{"aurora","Aurora",      Color3.fromRGB(130,255,200)},
	{"nebula","Nebula",      Color3.fromRGB(180,100,255)},
	{"meteor","Meteor",      Color3.fromRGB(185, 90, 60)},
	{"eclipse","Eclipse",    Color3.fromRGB( 95, 75,125)},
	{"quantum","Quantum",    Color3.fromRGB( 80,255,230)},
	{"mythril","Mythril",    Color3.fromRGB(165,200,210)},
	{"celestial","Celestial",Color3.fromRGB(255,210,255)},
	{"phantom","Phantom",    Color3.fromRGB(115, 95,165)},
	{"radiant","Radiant",    Color3.fromRGB(255,240,150)},
	{"obsidian","Obsidian",  Color3.fromRGB( 55, 48, 70)},
	{"plasma","Plasma",      Color3.fromRGB(255, 80,200)},
	{"cosmos","Cosmos",      Color3.fromRGB( 90,110,255)},
	{"galaxy","Galaxy",      Color3.fromRGB(150, 80,255)},
	{"infinity","Infinity",  Color3.fromRGB(120,255,255)},
	{"divine","Divine",      Color3.fromRGB(255,235,160)},
	{"eternity","Eternity",  Color3.fromRGB(230,180,255)},
}

-- Clean, nice-looking unlock costs (stage 1 is free). Grows ~2× with tidy
-- numbers, getting expensive toward the end.
local STAGE_COST = {
	0, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000,
	500000, 1e6, 2.5e6, 5e6, 10e6, 25e6, 50e6, 100e6, 250e6, 500e6,
	1e9, 2.5e9, 5e9, 10e9, 25e9, 50e9, 100e9, 250e9, 500e9, 1e12,
}

Config.ZONES       = {}
Config.ENEMY_TYPES = {}
local HP_GROWTH    = 1.5     -- enemy HP grows moderately (stays killable with lvl-30 pets)
local TIER_SUFFIX  = { "Slime", "Brute", "Titan", "King" }
for i, zl in ipairs(ZONE_LIST) do
	local id, name, col = zl[1], zl[2], zl[3]
	local unlockCost = STAGE_COST[i] or (STAGE_COST[#STAGE_COST] * 2)
	table.insert(Config.ZONES, { id=id, name=name, unlockCost=unlockCost, gateZ=(i-1)*300, color=col })

	local baseHp = 25 * HP_GROWTH ^ (i - 1)
	-- Coins per kill scale with the NEXT stage's cost so unlocking always takes
	-- a similar amount of farming (steady pacing, clean numbers).
	local nextCost = STAGE_COST[math.min(i + 1, #STAGE_COST)]
	local baseGoop = math.max(2, nextCost / 220)
	for t = 1, 4 do
		local tm = 1 + 0.55 * (t - 1)
		table.insert(Config.ENEMY_TYPES, {
			zone  = id,
			name  = name .. " " .. TIER_SUFFIX[t],
			color = col:Lerp(Color3.new(0,0,0), 0.12 * (t - 1)),
			goop  = math.max(1, math.floor(baseGoop * tm)),
			-- Size grows with tier AND with zone, so later-stage slimes are
			-- clearly bigger (≈2.7× by the final zone) — they feel stronger.
			sz    = (0.9 + 0.12 * (t - 1)) * (1 + 0.06 * (i - 1)),
			hp    = math.floor(baseHp * tm),
			-- Pet XP multiplier: tougher tiers and later zones give more XP, so
			-- "better slimes give more exp". (Applied to PET_XP_PER_KILL.)
			xpMult = (1 + 0.4 * (t - 1)) * (1 + 0.06 * (i - 1)),
			-- Damage this slime does to a pet when it attacks (scales by zone+tier).
			atk    = math.max(2, math.floor(5 * (1 + 0.5 * (i - 1)) * tm)),
		})
	end
end

Config.VALLEY_WIDTH = 300
Config.ZONE_LENGTH  = 300
Config.SPAWN_Z      = 50

-- ─── ROLL SYSTEM ─────────────────────────────────────────────────────────────
Config.ROLL_COOLDOWN = 3    -- base seconds between rolls
Config.MAX_EQUIPPED  = 2    -- base pet slots

-- ─── AUTO-ROLL ───────────────────────────────────────────────────────────────
-- Timed auto-roll: spend coins for 5 minutes. Permanent auto-roll is the pass.
Config.AUTO_ROLL_COIN_COST = 50000  -- coins for one timed burst
Config.AUTO_ROLL_DURATION  = 300    -- seconds (5 minutes)
Config.AUTO_ROLL_PASS_BONUS = 0.5   -- pass owners also get 0.5s faster cooldown

-- ─── PETS ────────────────────────────────────────────────────────────────────
-- ability.shape: "ball" | "bolt" | "shard"
-- ability.damage: base HP removed from enemy per hit
-- ability.range:  max studs from player centre the pet can target
-- ability.fireRate: seconds between shots
Config.PETS = {
	-- ── Common ───────────────────────────────────────────────────────────────
	{
		id="blob_slime", name="Blob Slime", rarity=3,
		label="Common", labelColor=Color3.fromRGB(210,210,210),
		color=Color3.fromRGB(110,230,90), goop=1, sz=0.90,
		ability={
			id="slimeball", name="Slime Ball",
			projectileColor=Color3.fromRGB(90,220,70),
			projectileSize=0.85, damage=6, range=20, fireRate=2.0, shape="ball",
		},
	},
	{
		id="fire_pup", name="Fire Pup", rarity=5,
		label="Common", labelColor=Color3.fromRGB(210,210,210),
		color=Color3.fromRGB(255,145,40), goop=2, sz=0.85,
		ability={
			id="fire_spit", name="Fire Spit",
			projectileColor=Color3.fromRGB(255,100,20),
			projectileSize=0.65, damage=10, range=22, fireRate=1.8, shape="ball",
		},
	},
	{
		id="chicken", name="Chicken", rarity=4,
		label="Common", labelColor=Color3.fromRGB(210,210,210),
		color=Color3.fromRGB(248,248,248), goop=2, sz=0.88,
		ability={
			id="peck", name="Peck",
			projectileColor=Color3.fromRGB(255,200,60),
			projectileSize=0.60, damage=8, range=20, fireRate=1.9, shape="ball",
		},
	},
	-- ── Uncommon ─────────────────────────────────────────────────────────────
	{
		id="flame_fox", name="Flame Fox", rarity=10,
		label="Uncommon", labelColor=Color3.fromRGB(80,230,140),
		color=Color3.fromRGB(240,120,30), goop=3, sz=1.00,
		ability={
			id="ember_shot", name="Ember Shot",
			projectileColor=Color3.fromRGB(255,90,15),
			projectileSize=0.70, damage=18, range=25, fireRate=1.5, shape="ball",
		},
	},
	{
		id="shadow_cat", name="Shadow Cat", rarity=15,
		label="Uncommon", labelColor=Color3.fromRGB(80,230,140),
		color=Color3.fromRGB(70,35,110), goop=5, sz=0.95,
		ability={
			id="shadow_slash", name="Shadow Slash",
			projectileColor=Color3.fromRGB(140,60,220),
			projectileSize=0.55, damage=25, range=24, fireRate=1.2, shape="bolt",
		},
	},
	-- ── Rare ─────────────────────────────────────────────────────────────────
	{
		id="frost_bunny", name="Frost Bunny", rarity=50,
		label="Rare", labelColor=Color3.fromRGB(110,170,255),
		color=Color3.fromRGB(170,220,255), goop=10, sz=1.00,
		ability={
			id="ice_shard", name="Ice Shard",
			projectileColor=Color3.fromRGB(185,235,255),
			projectileSize=0.72, damage=40, range=22, fireRate=1.4, shape="shard",
		},
	},
	-- ── Epic ─────────────────────────────────────────────────────────────────
	{
		id="mini_dragon", name="Mini Dragon", rarity=200,
		label="Epic", labelColor=Color3.fromRGB(200,80,245),
		color=Color3.fromRGB(200,55,25), goop=30, sz=1.20,
		ability={
			id="flame_bolt", name="Flame Bolt",
			projectileColor=Color3.fromRGB(255,70,10),
			projectileSize=0.62, damage=90, range=30, fireRate=0.90, shape="bolt",
		},
	},
	-- ── Legendary ────────────────────────────────────────────────────────────
	{
		id="storm_hawk", name="Storm Hawk", rarity=1000,
		label="Legendary", labelColor=Color3.fromRGB(255,210,50),
		color=Color3.fromRGB(70,150,255), goop=100, sz=1.15,
		ability={
			id="lightning", name="Lightning Strike",
			projectileColor=Color3.fromRGB(195,220,255),
			projectileSize=0.46, damage=220, range=35, fireRate=0.75, shape="bolt",
		},
	},
	-- ── Mythic ───────────────────────────────────────────────────────────────
	{
		id="crystal_phoenix", name="Crystal Phoenix", rarity=7770,
		label="Mythic", labelColor=Color3.fromRGB(255,90,190),
		color=Color3.fromRGB(185,245,255), goop=500, sz=1.40,
		ability={
			id="prism_burst", name="Prism Burst",
			projectileColor=Color3.fromRGB(220,248,255),
			projectileSize=0.58, damage=650, range=40, fireRate=0.55, shape="shard",
		},
	},
	-- ── Divine (new highest tier) ─────────────────────────────────────────────
	{
		id="emperor_snake", name="Emperor Snake", rarity=50000,
		label="Divine", labelColor=Color3.fromRGB(255,225,90),
		color=Color3.fromRGB(248,248,255), goop=2500, sz=1.45,
		ability={
			id="divine_beam", name="Divine Beam",
			projectileColor=Color3.fromRGB(255,240,150),
			projectileSize=0.60, damage=1600, range=46, fireRate=0.5, shape="bolt",
		},
	},
}

-- ─── PET ORBIT ───────────────────────────────────────────────────────────────
Config.PET_ORBIT_RADIUS = 6.5   -- studs from player centre
Config.PET_ORBIT_SPEED  = 1.1   -- radians/sec  (full orbit ≈ 5.7 s)
Config.PET_ORBIT_HEIGHT = 4.5   -- studs above player Y

-- ─── PROJECTILE ──────────────────────────────────────────────────────────────
Config.PROJECTILE_SPEED    = 55   -- studs/sec
Config.PROJECTILE_MAX_DIST = 65   -- destroy if it travels this far

-- ─── UPGRADES ────────────────────────────────────────────────────────────────
Config.UPGRADES = {
	{
		id="slots", name="Pet Slots", icon="🐾", desc="Hold more pets",
		levels={
			{ cost=50,    label="3 Slots" },
			{ cost=150,   label="4 Slots" },
			{ cost=400,   label="5 Slots" },
			{ cost=2500,  label="6 Slots" },
			{ cost=15000, label="7 Slots" },
			{ cost=80000, label="8 Slots" },
		},
	},
	{
		id="speed", name="Roll Speed", icon="⚡", desc="Faster rolls",
		levels={
			{ cost=30,    label="2.5s" },
			{ cost=80,    label="2.0s" },
			{ cost=200,   label="1.5s" },
			{ cost=2000,  label="1.25s" },
			{ cost=20000, label="1.0s" },
		},
	},
	{
		id="luck", name="Luck", icon="🍀", desc="Better rarities",
		levels={
			{ cost=60,       label="1.5×" },
			{ cost=180,      label="2×"   },
			{ cost=500,      label="3×"   },
			{ cost=6000,     label="4×"   },
			{ cost=60000,    label="5×"   },
			{ cost=750000,   label="7×"   },
			{ cost=25000000, label="10×"  },
		},
	},
	{
		id="power", name="Power", icon="⚔️", desc="More pet damage",
		levels={
			{ cost=1000,     label="1.5×" },
			{ cost=5000,     label="2×"   },
			{ cost=25000,    label="3×"   },
			{ cost=100000,   label="4.5×" },
			{ cost=500000,   label="6×"   },
			{ cost=5000000,  label="8×"   },
			{ cost=50000000, label="12×"  },
		},
	},
	{
		id="greed", name="Greed", icon="💰", desc="More coins per kill",
		levels={
			{ cost=2000,      label="1.4×" },
			{ cost=10000,     label="1.8×" },
			{ cost=50000,     label="2.5×" },
			{ cost=250000,    label="3.5×" },
			{ cost=1000000,   label="5×"   },
			{ cost=10000000,  label="7×"   },
			{ cost=100000000, label="10×"  },
		},
	},
	{
		id="fortune", name="Fortune", icon="✨", desc="Higher shiny chance",
		levels={
			{ cost=5000,       label="1.5×" },
			{ cost=25000,      label="2×"   },
			{ cost=100000,     label="3×"   },
			{ cost=500000,     label="4×"   },
			{ cost=2500000,    label="6×"   },
			{ cost=25000000,   label="8×"   },
			{ cost=250000000,  label="10×"  },
		},
	},
	-- Auto Roll is intentionally NOT here — it is a Robux gamepass only
	-- (see Config.ROBUX_PASSES "auto_pass").
}

Config.SPEED_LEVELS   = { 3, 2.5, 2.0, 1.5, 1.25, 1.0 }
Config.LUCK_LEVELS    = { 1, 1.5, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0 }
Config.POWER_LEVELS   = { 1, 1.5, 2.0, 3.0, 4.5, 6.0, 8.0, 12.0 }   -- pet damage ×
Config.COIN_LEVELS    = { 1, 1.4, 1.8, 2.5, 3.5, 5.0, 7.0, 10.0 }   -- coins per kill ×
Config.FORTUNE_LEVELS = { 1, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0 }   -- shiny chance ×

-- ─── LUCK BONUSES (permanent + temporary) ────────────────────────────────────
-- Both are MULTIPLIERS on your total luck (so they always stay valuable, even
-- once the coin Luck upgrade is maxed). They stack with each other.
Config.MEGA_LUCK_MULT  = 3.0   -- Mega Luck gamepass: ×3 total luck, always
Config.LUCK_BOOST_MULT = 3.0   -- ×3 total luck while a Lucky Charm boost is active

-- ─── VIP GAMEPASS ─────────────────────────────────────────────────────────────
Config.VIP_COIN_MULT  = 2.0    -- VIP pass: all coin income ×2
Config.BIG_SLOTS_BONUS = 3     -- Extra Slots pass: +3 equipped slots

-- ─── REBIRTH ─────────────────────────────────────────────────────────────────
Config.REBIRTH_BASE_COST  = 500
Config.REBIRTH_LUCK_BONUS = 0.5

-- ─── ENEMY SLIMES ────────────────────────────────────────────────────────────
Config.ENEMY_COUNT        = #Config.ZONES * 6   -- ~6 slimes per stage (denser fights)
Config.ENEMY_RESPAWN_TIME = 6

-- ─── PET COMBAT (slimes fight back) ──────────────────────────────────────────
-- Pets have HP. A slime near you periodically attacks one of your active pets;
-- a pet at 0 HP goes DOWN (stops attacking) and revives after PET_DOWN_TIME.
Config.PET_BASE_HP          = 70    -- baseline pet HP (before rarity / level scaling)
Config.PET_DOWN_TIME        = 60    -- seconds a downed pet stays inactive
Config.ENEMY_ATTACK_RANGE   = 15    -- studs from you a slime can hit your pets
Config.ENEMY_ATTACK_INTERVAL= 2.5   -- seconds between a slime's attacks

-- (ENEMY_TYPES is generated above alongside Config.ZONES — 4 tiers per stage.)

-- ─── ROBUX MONETIZATION ──────────────────────────────────────────────────────
-- ⚠️ TO GO LIVE: create each item on the Creator Dashboard, then paste the
--    numeric ID into productId / passId below (replace the 0). The `robux`
--    field here is just the display price — the REAL price is set on the
--    Dashboard when you create the product/pass.
--
--    Dev Products:  Creator Dashboard → your game → Monetization → Developer
--                   Products → Create. Copy the Product ID.
--    Game Passes:   Creator Dashboard → your game → Monetization → Passes →
--                   Create. Open the pass → copy the Pass ID from its URL.
--
-- Everything else (prompting, granting, pass checks, anti-double-charge) is
-- already wired — once the IDs are in, purchases work.
-- Coin packs scale with your CURRENT coins (a %) so they never become useless
-- late game, with a flat minimum so they're still worth it early. The bigger
-- of (pct of coins) and (min amount) is granted.
Config.ROBUX_PRODUCTS = {
	{ id="goop_sm",    productId=3601647623, name="Coin Bag",    icon="💰", robux= 25,  desc="+25% of your coins",  reward="coins", pct=0.25, amount=1000  },
	{ id="goop_md",    productId=3601647725, name="Coin Chest",  icon="🧲", robux= 75,  desc="+75% of your coins",  reward="coins", pct=0.75, amount=5000  },
	{ id="goop_lg",    productId=3601648017, name="Coin Vault",  icon="🏦", robux=200,  desc="+200% of your coins", reward="coins", pct=2.0,  amount=25000 },
	{ id="luck_boost", productId=3601648137, name="Lucky Charm", icon="🍀", robux= 50,  desc="3× Luck for 10 min",  reward="luck_boost", amount=10 },
}

Config.ROBUX_PASSES = {
	{ id="vip",       passId=1861103076, name="VIP",         icon="⭐", robux=299, desc="2× Coin income, always"     },
	{ id="auto_pass", passId=1862678465, name="Auto Roller",  icon="🎲", robux=249, desc="Permanent auto-roll + faster rolls" },
	{ id="mega_luck", passId=1862244926, name="Mega Luck",    icon="🔮", robux=399, desc="3× total Luck, always" },
	{ id="big_slots", passId=1861830945, name="Extra Slots",  icon="🐾", robux=199, desc="+3 extra pet slots"         },
}

-- ─── DAILY WHEEL ─────────────────────────────────────────────────────────────
Config.WHEEL_SPIN_COOLDOWN = 86400

Config.WHEEL_PRIZES = {
	{ label="50 Coins",   reward="coins", amount=50,    weight=28, color=Color3.fromRGB( 80,140,255) },
	{ label="200 Coins",  reward="coins", amount=200,   weight=22, color=Color3.fromRGB( 60,200,100) },
	{ label="1K Coins",   reward="coins", amount=1000,  weight=12, color=Color3.fromRGB(255,180, 40) },
	{ label="5K Coins",   reward="coins", amount=5000,  weight=5,  color=Color3.fromRGB(255,120, 30) },
	{ label="Lucky Charm",reward="luck",  amount=600,   weight=14, color=Color3.fromRGB(140, 80,240) },
	{ label="Mega Luck",  reward="luck",  amount=1800,  weight=6,  color=Color3.fromRGB(220, 60,200) },
	{ label="25K Coins",  reward="coins", amount=25000, weight=2,  color=Color3.fromRGB(255,210, 55) },
	{ label="Try Again",  reward="none",  amount=0,     weight=11, color=Color3.fromRGB( 55, 55, 72) },
}

-- ─── DAILY LOGIN REWARDS ─────────────────────────────────────────────────────
Config.DAILY_REWARD_COOLDOWN = 86400

Config.DAILY_REWARDS = {
	{ day=1, reward="coins", amount=100,   icon="💰", label="100 Coins"  },
	{ day=2, reward="coins", amount=300,   icon="💰", label="300 Coins"  },
	{ day=3, reward="luck",  amount=600,   icon="🍀", label="10m Luck"   },
	{ day=4, reward="coins", amount=750,   icon="💰", label="750 Coins"  },
	{ day=5, reward="coins", amount=2000,  icon="💰", label="2K Coins"   },
	{ day=6, reward="luck",  amount=1800,  icon="🔮", label="30m Luck"   },
	{ day=7, reward="coins", amount=10000, icon="⭐", label="10K Coins"  },
}

-- ─── PET LEVELLING ───────────────────────────────────────────────────────────
-- Pets gain XP mainly by FIGHTING (each kill the pet lands), plus a little when
-- you roll that pet again. XP needed per level grows ~12%/level so early levels
-- come fast and later ones are a real grind (gradually harder).
Config.PET_MAX_LEVEL    = 30
Config.PET_XP_PER_ROLL  = 20     -- XP when you roll this pet type
Config.PET_XP_PER_KILL  = 12     -- XP to the pet that lands a kill (while equipped)
Config.PET_XP_BASE      = 40     -- XP to go from level 1 → 2
Config.PET_XP_SCALE     = 1.12   -- each level needs 12% more XP than the last
Config.PET_LEVEL_BONUS  = 0.5    -- +50%/level (lvl30 ≈ 15.5×) — bigger so the lower cap still scales

-- ─── SHINY PETS ──────────────────────────────────────────────────────────────
-- Shiny IDs stored as "shiny:"..petId in inventory / equipped
Config.SHINY_CHANCE       = 0.01   -- 1% per roll
Config.SHINY_DAMAGE_MULT  = 1.50   -- shiny deals 1.5× base damage
Config.SHINY_GOOP_MULT    = 1.50   -- shiny earns 1.5× goop on kill

-- ─── PET EVOLUTION ───────────────────────────────────────────────────────────
-- Evolving costs this many coins and requires the pet to be at PET_MAX_LEVEL.
-- Evolved IDs stored as "evolved:"..petId  (shiny evolved = "shiny:evolved:petId")
Config.EVOLUTION_COST = 800

Config.PET_EVOLUTIONS = {
	blob_slime     = { name="Mega Blob",       color=Color3.fromRGB( 30,225, 70), damageMult=2.0 },
	fire_pup       = { name="Inferno Pup",     color=Color3.fromRGB(255, 40,  0), damageMult=2.0 },
	flame_fox      = { name="Blaze Fox",       color=Color3.fromRGB(255, 55,  0), damageMult=2.1 },
	shadow_cat     = { name="Void Cat",        color=Color3.fromRGB( 10,  0, 28), damageMult=2.2 },
	frost_bunny    = { name="Blizzard Bunny",  color=Color3.fromRGB( 85,165,255), damageMult=2.2 },
	mini_dragon    = { name="Elder Dragon",    color=Color3.fromRGB(195, 15,  0), damageMult=2.4 },
	storm_hawk     = { name="Thunder Hawk",    color=Color3.fromRGB( 25, 70,255), damageMult=2.5 },
	crystal_phoenix= { name="Void Phoenix",    color=Color3.fromRGB(175, 50,255), damageMult=3.0 },
}

-- ─── AUTO-SELL ───────────────────────────────────────────────────────────────
-- Rarity order for threshold comparisons (lower index = lower rarity)
Config.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine" }
Config.RARITY_RANK  = {}
for i, r in ipairs(Config.RARITY_ORDER) do Config.RARITY_RANK[r] = i end

-- ─── COLLECTION BONUSES ──────────────────────────────────────────────────────
-- Discover every pet in a tier → permanent goop multiplier on kills (stacks)
Config.COLLECTION_BONUSES = {
	{ label="Common",    pets={"blob_slime","fire_pup"},     goop_mult=1.05 },
	{ label="Uncommon",  pets={"flame_fox","shadow_cat"},    goop_mult=1.10 },
	{ label="Rare",      pets={"frost_bunny"},               goop_mult=1.15 },
	{ label="Epic",      pets={"mini_dragon"},               goop_mult=1.20 },
	{ label="Legendary", pets={"storm_hawk"},                goop_mult=1.25 },
	{ label="Mythic",    pets={"crystal_phoenix"},           goop_mult=1.50 },
}

-- ─── COMBO KILLS ─────────────────────────────────────────────────────────────
Config.COMBO_WINDOW  = 0.5    -- seconds between kills to extend combo
Config.COMBO_BONUS   = 0.20   -- +20% goop per combo stack above 1

-- ─── BACKGROUND MUSIC ────────────────────────────────────────────────────────
-- Roblox audio asset IDs played as a shuffled background playlist by
-- MusicPlayer.client.luau. Audio privacy: for a published game make sure each
-- ID is a track you own or that is set "public". Swap these for your own.
Config.MUSIC_VOLUME = 0.35
Config.MUSIC_TRACKS = {
	1837879082,   -- calm / chiptune-style loops (replace with owned/public audio)
	1845756489,
	1843463529,
	1836965135,
}

-- ─── Number formatting (500, 12.5K, 3.4M, 1.2B, 5T) ──────────────────────────
function Config.fmtNum(n)
	n = math.floor((n or 0) + 0.5)
	local function f(v, s)
		local r = string.format("%.1f", v):gsub("%.0$", "")
		return r .. s
	end
	local a = math.abs(n)
	if     a >= 1e12 then return f(n/1e12, "T")
	elseif a >= 1e9  then return f(n/1e9,  "B")
	elseif a >= 1e6  then return f(n/1e6,  "M")
	elseif a >= 1e3  then return f(n/1e3,  "K")
	else return tostring(n) end
end

return Config

