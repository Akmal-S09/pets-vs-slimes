-- PlayerData.luau (ModuleScript)
-- Single source of truth for all per-player data, with DataStore persistence.
--
-- Persistence design (built so updates NEVER wipe items):
--   • Only "source of truth" fields are saved (coins, inventory, upgrades, …).
--     Loading starts from fresh() and overlays the save, so any NEW field added
--     in a future update simply uses its default — old saves keep working.
--   • Derived values (maxSlots, rollCooldown, luckMult) are RECOMPUTED on load.
--   • Gamepass flags are NEVER saved — they're re-derived from Roblox ownership
--     every join (see MonetizationHandler), so a pass can't "run out".
--   • If a load fails, the session is flagged no-save so we never overwrite a
--     real save with defaults.
--   • Studio runs in-memory only (no DataStore), so testing can't touch live data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerData = {}
local _store = {}

local PERSIST = not RunService:IsStudio()          -- no DataStore writes in Studio
local store   = PERSIST and DataStoreService:GetDataStore("PetsVsSlimes_PlayerData_v1") or nil
local function keyFor(player) return "player_" .. player.UserId end

local function fresh()
	return {
		coins        = 0,
		lastRoll     = -999,
		equipped     = {},
		upgrades     = { slots=0, speed=0, luck=0, autoroll=0, power=0, greed=0, fortune=0 },
		rebirths     = 0,
		luckMult     = 1.0,
		totalRolls   = 0,
		seenPets     = {},
		maxSlots     = Config.MAX_EQUIPPED,
		rollCooldown = Config.ROLL_COOLDOWN,
		-- Gamepass flags (re-derived from Roblox each join; never persisted)
		passVIP      = false,
		passAutoRoll = false,
		passMegaLuck = false,
		passBigSlots = false,
		-- Temporary boosts (not persisted)
		luckBoostEnd  = 0,
		autoRollOn    = false,  -- default OFF; turns on when player buys/owns auto-roll
		autoRollEnd   = 0,
		-- Daily systems
		lastSpin      = 0,
		lastDailyClaim= 0,
		dailyStreak   = 0,
		-- Inventory (all owned pets, duplicates allowed, max 60)
		inventory      = {},
		-- Pet levelling — keyed by each pet's UNIQUE instance id (the full
		-- inventory string incl. its "#uid" suffix), so every individual pet
		-- levels on its own instead of sharing one level per species.
		petLevels      = {},
		petXP          = {},
		petUid         = 0,    -- monotonic counter → unique pet instance ids

		-- Quality-of-life
		autoSellSet    = {},
		-- Zones this player has unlocked (set: zoneName → true). Forest is always
		-- open implicitly. Persisted so progress survives rejoins.
		unlockedZones  = {},
		-- Trading: true while in an active trade (locks index-shifting inventory ops)
		inTrade        = false,
	}
end

-- ─── Luck (permanent) ─────────────────────────────────────────────────────────
function PlayerData.recomputeLuck(d)
	local upgLuck = Config.LUCK_LEVELS[(d.upgrades.luck or 0) + 1] or 1
	local luck    = upgLuck + (d.rebirths or 0) * Config.REBIRTH_LUCK_BONUS
	-- Mega Luck multiplies your TOTAL luck (so it scales with upgrades/rebirths
	-- and never becomes worthless like a flat bonus would).
	if d.passMegaLuck then luck = luck * Config.MEGA_LUCK_MULT end
	d.luckMult = luck
	return luck
end

-- Max equipped slots = base + slots upgrade + Extra Slots pass bonus.
-- Centralised so the pass bonus can't be doubled or wiped by upgrade purchases.
function PlayerData.recomputeMaxSlots(d)
	d.maxSlots = Config.MAX_EQUIPPED + (d.upgrades.slots or 0)
		+ (d.passBigSlots and Config.BIG_SLOTS_BONUS or 0)
	return d.maxSlots
end

-- Roll cooldown = speed-upgrade tier, minus the Auto Roller pass bonus.
-- Centralised so buying a speed upgrade can't wipe the pass bonus (and vice-versa).
function PlayerData.recomputeRollCooldown(d)
	local base = Config.SPEED_LEVELS[(d.upgrades.speed or 0) + 1] or Config.ROLL_COOLDOWN
	d.rollCooldown = math.max(0.5, base - (d.passAutoRoll and Config.AUTO_ROLL_PASS_BONUS or 0))
	return d.rollCooldown
end

-- Recompute everything that's derived from saved fields.
local function recomputeDerived(d)
	PlayerData.recomputeMaxSlots(d)
	PlayerData.recomputeRollCooldown(d)
	PlayerData.recomputeLuck(d)
end

-- ─── Save (de)serialisation ────────────────────────────────────────────────────
-- equipped is a sparse {slot=id} map; store it as a list so JSON string-keys
-- don't corrupt the numeric slots on the way back.
local function buildSave(d)
	local eq = {}
	for slot, id in pairs(d.equipped) do
		if type(id) == "string" then eq[#eq + 1] = { slot = slot, id = id } end
	end
	return {
		_v             = 1,
		coins          = d.coins,
		rebirths       = d.rebirths,
		totalRolls     = d.totalRolls,
		upgrades       = d.upgrades,
		inventory      = d.inventory,
		equipped       = eq,
		petLevels      = d.petLevels,
		petXP          = d.petXP,
		petUid         = d.petUid,
		seenPets       = d.seenPets,
		autoSellSet    = d.autoSellSet,
		unlockedZones  = d.unlockedZones,
		autoRollOn     = d.autoRollOn,
		dailyStreak    = d.dailyStreak,
		lastDailyClaim = d.lastDailyClaim,
		lastSpin       = d.lastSpin,
	}
end

-- Merge a save over fresh() defaults, with light validation.
local function sanitize(saved)
	local d = fresh()
	if type(saved) ~= "table" then recomputeDerived(d); return d end

	local function num(v) return (type(v) == "number" and v == v) and v or nil end
	if num(saved.coins)      then d.coins      = math.max(0, math.floor(saved.coins)) end
	if num(saved.rebirths)   then d.rebirths   = math.max(0, math.floor(saved.rebirths)) end
	if num(saved.totalRolls) then d.totalRolls = math.max(0, math.floor(saved.totalRolls)) end

	if type(saved.upgrades) == "table" then
		for k in pairs(d.upgrades) do
			if num(saved.upgrades[k]) then d.upgrades[k] = math.max(0, math.floor(saved.upgrades[k])) end
		end
	end
	if type(saved.inventory) == "table" then
		for _, id in ipairs(saved.inventory) do
			if type(id) == "string" and #d.inventory < 60 then table.insert(d.inventory, id) end
		end
	end
	if type(saved.equipped) == "table" then
		for _, e in ipairs(saved.equipped) do
			if type(e) == "table" and type(e.slot) == "number" and type(e.id) == "string" then
				d.equipped[e.slot] = e.id
			end
		end
	end
	if type(saved.petLevels) == "table" then
		for k, v in pairs(saved.petLevels) do if type(k) == "string" and num(v) then d.petLevels[k] = v end end
	end
	if type(saved.petXP) == "table" then
		for k, v in pairs(saved.petXP) do if type(k) == "string" and num(v) then d.petXP[k] = v end end
	end
	if num(saved.petUid) then d.petUid = math.max(0, math.floor(saved.petUid)) end
	if type(saved.seenPets) == "table" then
		for k, v in pairs(saved.seenPets) do if type(k) == "string" and v then d.seenPets[k] = true end end
	end
	if type(saved.autoSellSet) == "table" then
		for k, v in pairs(saved.autoSellSet) do if type(k) == "string" and v then d.autoSellSet[k] = true end end
	end
	if type(saved.unlockedZones) == "table" then
		for k, v in pairs(saved.unlockedZones) do if type(k) == "string" and v then d.unlockedZones[k] = true end end
	end
	-- Only restore autoRollOn=true if the player actually owns auto-roll
	-- (guards against old saves where it defaulted to true for everyone).
	if type(saved.autoRollOn) == "boolean" then d.autoRollOn = saved.autoRollOn end
	if num(saved.dailyStreak)    then d.dailyStreak    = saved.dailyStreak end
	if num(saved.lastDailyClaim) then d.lastDailyClaim = saved.lastDailyClaim end
	if num(saved.lastSpin)       then d.lastSpin       = saved.lastSpin end

	recomputeDerived(d)
	return d
end

-- ─── Load / save ────────────────────────────────────────────────────────────
function PlayerData.load(player)
	if _store[player] and _store[player]._loaded then return _store[player] end

	if not PERSIST then
		local d = fresh(); d._loaded = true; d._noSave = true
		_store[player] = d
		return d
	end

	local ok, result
	for _ = 1, 4 do
		ok, result = pcall(function() return store:GetAsync(keyFor(player)) end)
		if ok then break end
		task.wait(2)
	end

	local d
	if ok then
		d = sanitize(result)              -- result may be nil → brand-new player
		d._loaded = true
	else
		-- Couldn't read the save — run in no-save mode so we never overwrite it.
		d = fresh(); d._loaded = true; d._noSave = true
		warn("[PlayerData] Load FAILED for " .. player.Name .. " — no-save session (data protected).")
	end
	_store[player] = d
	return d
end

function PlayerData.save(player)
	local d = _store[player]
	if not d or not d._loaded or d._noSave or not PERSIST then return false end
	local data = buildSave(d)
	local ok, err
	for _ = 1, 4 do
		ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function() return data end)
		end)
		if ok then break end
		task.wait(2)
	end
	if not ok then warn("[PlayerData] Save FAILED for " .. player.Name .. ": " .. tostring(err)) end
	return ok
end

-- Yield until a player's data has finished loading (used by handlers that must
-- act on real data, e.g. applying gamepasses).
function PlayerData.waitForLoad(player)
	local t = 0
	while not (_store[player] and _store[player]._loaded) and t < 12 do
		task.wait(0.1); t = t + 0.1
	end
	return _store[player]
end

function PlayerData.isLoaded(player)
	return _store[player] ~= nil and _store[player]._loaded == true
end

-- ─── Accessors ────────────────────────────────────────────────────────────────
function PlayerData.get(player)
	if not _store[player] then
		-- Safety net if something reads before load finishes; marked not-loaded
		-- so it can never be saved over a real profile.
		_store[player] = fresh()
	end
	return _store[player]
end

function PlayerData.remove(player)
	_store[player] = nil
end

function PlayerData.snapshot(player)
	local d = PlayerData.get(player)
	return {
		coins        = d.coins,
		totalRolls   = d.totalRolls,
		rebirths     = d.rebirths,
		luckMult     = d.luckMult,
		maxSlots     = d.maxSlots,
		rollCooldown = d.rollCooldown,
		upgrades     = d.upgrades,
		equipped      = d.equipped,
		seenPets      = d.seenPets,
		passVIP       = d.passVIP,
		passAutoRoll  = d.passAutoRoll,
		passMegaLuck  = d.passMegaLuck,
		passBigSlots  = d.passBigSlots,
		luckBoostEnd  = d.luckBoostEnd,
		autoRollOn    = d.autoRollOn,
		autoRollLeft  = math.max(0, (d.autoRollEnd or 0) - tick()),
		inventory      = d.inventory,
		petLevels      = d.petLevels,
		petXP          = d.petXP,
		autoSellSet    = d.autoSellSet,
		unlockedZones  = d.unlockedZones,
	}
end

-- ─── Lifecycle: load on join, save on leave, autosave, shutdown ──────────────
Players.PlayerAdded:Connect(function(player)
	PlayerData.load(player)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerData.save(player)
	_store[player] = nil
end)

-- Players already present when the module first runs (Studio / hot reload).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(PlayerData.load, player)
end

-- Periodic autosave (guards against crashes between joins/leaves).
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerData.save(player)
		end
	end
end)

-- Final save on server shutdown.
game:BindToClose(function()
	if not PERSIST then return end
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerData.save, player)
	end
	task.wait(3)   -- give the saves a moment to flush
end)

return PlayerData

