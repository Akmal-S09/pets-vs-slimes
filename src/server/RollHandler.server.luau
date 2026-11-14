-- RollHandler.server.luau
-- Roll logic, upgrade purchases, rebirths, player data management.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Shared            = ReplicatedStorage:WaitForChild("Shared")

local Config     = require(Shared:WaitForChild("Config"))
local Remotes    = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent.PlayerData)

-- ─── Weighted roll table ──────────────────────────────────────────────────────
local weights     = {}
local totalWeight = 0
for _, p in ipairs(Config.PETS) do
	local w = 1 / p.rarity
	table.insert(weights, w)
	totalWeight = totalWeight + w
end

local function rollPet(luckMult)
	luckMult = luckMult or 1
	-- Build the luck-boosted weight table AND its matching total, so the
	-- random pick is normalised against the same numbers (otherwise high luck
	-- overshoots and always returns the first boosted pet).
	local boosted = {}
	local total   = 0
	for i, p in ipairs(Config.PETS) do
		local w = weights[i]
		-- Luck boosts every non-Common pet (rarity-based, so it's correct
		-- regardless of the order pets appear in the list).
		if p.label ~= "Common" then w = w * luckMult end
		boosted[i] = w
		total = total + w
	end
	local roll = math.random() * total
	local cum  = 0
	for i, p in ipairs(Config.PETS) do
		cum = cum + boosted[i]
		if roll <= cum then return p end
	end
	return Config.PETS[1]
end

-- ─── Helper: push full stats to client ───────────────────────────────────────
local function pushStats(player)
	Remotes.UpdateStats:FireClient(player, PlayerData.snapshot(player))
end

-- ─── Roll ─────────────────────────────────────────────────────────────────────
-- ─── Pet ID helpers ──────────────────────────────────────────────────────────
local function makeFullId(baseId, isShiny)
	return isShiny and ("shiny:" .. baseId) or baseId
end

local function parseFullId(fullId)
	fullId = (fullId:gsub("#.*$", ""))   -- strip the unique "#uid" instance suffix
	local isShiny   = fullId:sub(1,6)   == "shiny:"
	local rest      = isShiny and fullId:sub(7) or fullId
	local isEvolved = rest:sub(1,8)     == "evolved:"
	local baseId    = isEvolved and rest:sub(9) or rest
	return baseId, isShiny, isEvolved
end

-- ─── Roll ─────────────────────────────────────────────────────────────────────
local function doRoll(player, isAuto)
	local d   = PlayerData.get(player)
	local now = tick()
	if now - d.lastRoll < d.rollCooldown then return end
	d.lastRoll   = now
	d.totalRolls = d.totalRolls + 1

	-- Effective luck = permanent luck × any active temporary Lucky Charm boost.
	local effLuck = d.luckMult or 1
	if (d.luckBoostEnd or 0) > now then
		effLuck = effLuck * Config.LUCK_BOOST_MULT
	end
	local pet    = rollPet(effLuck)
	local fortuneM = Config.FORTUNE_LEVELS[(d.upgrades.fortune or 0) + 1] or 1
	local isShiny = math.random() < Config.SHINY_CHANCE * fortuneM

	if not d.seenPets then d.seenPets = {} end
	d.seenPets[pet.id] = true

	-- Each rolled pet is a brand-new instance (starts at Lv.1 and levels on its
	-- own by fighting). A unique "#uid" suffix keeps it distinct from every
	-- other copy of the same species.
	d.petUid = (d.petUid or 0) + 1
	local fullId = makeFullId(pet.id, isShiny) .. "#" .. player.UserId .. "-" .. d.petUid

	-- ── Auto-sell check (multi-select: sell any rarity that's toggled on) ──────
	if d.autoSellSet and d.autoSellSet[pet.label] then
		do
			local vipM = d.passVIP and Config.VIP_COIN_MULT or 1
			local sellPrice = math.floor(pet.goop * (isShiny and Config.SHINY_GOOP_MULT or 1) * 3 * vipM)
			d.coins = d.coins + sellPrice
			Remotes.UpdateCoins:FireClient(player, d.coins)
			if not isAuto then
				local tag = isShiny and "✨ Shiny " or ""
				Remotes.FloatText:FireClient(player, "💰 Auto-sold "..tag..pet.name.."  +"..sellPrice)
				Remotes.RollResult:FireClient(player, fullId, true)  -- true = show roulette but mark sold
			end
			pushStats(player)
			return
		end
	end

	-- ── Add to inventory ──────────────────────────────────────────────────────
	if not d.inventory then d.inventory = {} end
	if #d.inventory < 60 then
		table.insert(d.inventory, fullId)
	end

	local vipM = d.passVIP and Config.VIP_COIN_MULT or 1
	d.coins = d.coins + math.floor(pet.goop * (isShiny and Config.SHINY_GOOP_MULT or 1) * vipM)

	Remotes.UpdateCoins:FireClient(player, d.coins)
	Remotes.UpdateInventory:FireClient(player, d.inventory)
	-- isAuto=true tells client to skip roulette animation
	Remotes.RollResult:FireClient(player, fullId, isAuto == true)
	pushStats(player)
end

Remotes.RequestRoll.OnServerEvent:Connect(function(player) doRoll(player, false) end)

-- ─── Auto-roll: throttled loop (not every frame) ─────────────────────────────
task.spawn(function()
	while true do
		task.wait(0.1)   -- poll every 100 ms; cooldown inside doRoll guards actual rate
		local now = tick()
		for _, player in ipairs(Players:GetPlayers()) do
			local d = PlayerData.get(player)
			local hasAuto = d and (d.passAutoRoll or (d.autoRollEnd or 0) > now)
			if hasAuto and d.autoRollOn then
				doRoll(player, true)
			end
		end
	end
end)

-- ─── Auto-sell (multi-select) ────────────────────────────────────────────────
-- Client sends a table { ["Common"]=true, ["Rare"]=true, ... } of rarities to
-- auto-sell. Validate keys against known rarities.
Remotes.SetAutoSell.OnServerEvent:Connect(function(player, set)
	local d = PlayerData.get(player)
	local clean = {}
	if type(set) == "table" then
		for rarity, on in pairs(set) do
			if on and Config.RARITY_RANK[rarity] then clean[rarity] = true end
		end
	end
	d.autoSellSet = clean
	pushStats(player)
end)

-- ─── Auto-roll: toggle on/off ────────────────────────────────────────────────
Remotes.ToggleAutoRoll.OnServerEvent:Connect(function(player)
	local d = PlayerData.get(player)
	local hasAuto = d.passAutoRoll or (d.autoRollEnd or 0) > tick()
	if not hasAuto then return end
	d.autoRollOn = not d.autoRollOn
	pushStats(player)
end)

-- ─── Auto-roll: buy 5 min burst for 50k coins ────────────────────────────────
Remotes.BuyAutoRoll.OnServerEvent:Connect(function(player)
	local d = PlayerData.get(player)
	if d.passAutoRoll then
		d.autoRollOn = true; pushStats(player); return
	end
	if d.coins < Config.AUTO_ROLL_COIN_COST then
		Remotes.FloatText:FireClient(player, "❌ Need " .. Config.fmtNum(Config.AUTO_ROLL_COIN_COST) .. " coins")
		return
	end
	d.coins       = d.coins - Config.AUTO_ROLL_COIN_COST
	d.autoRollEnd = math.max(tick(), d.autoRollEnd or 0) + Config.AUTO_ROLL_DURATION
	d.autoRollOn  = true
	Remotes.UpdateCoins:FireClient(player, d.coins)
	Remotes.FloatText:FireClient(player, "🔁 Auto-Roll for 5 minutes!")
	pushStats(player)
end)

-- ─── Evolve pet ──────────────────────────────────────────────────────────────
Remotes.EvolvePet.OnServerEvent:Connect(function(player, invIdx)
	local d = PlayerData.get(player)
	if d.inTrade then return end   -- inventory locked during a trade
	if not d.inventory then return end
	if type(invIdx) ~= "number" then return end
	invIdx = math.floor(invIdx)
	if invIdx < 1 or invIdx > #d.inventory then return end

	local fullId            = d.inventory[invIdx]
	local baseId, isShiny, isEvolved = parseFullId(fullId)
	if isEvolved then return end   -- already evolved

	-- This specific pet must be max level (level/XP keyed by its unique id).
	local lvl = (d.petLevels or {})[fullId] or 1
	if lvl < Config.PET_MAX_LEVEL then return end

	-- Check cost
	if d.coins < Config.EVOLUTION_COST then return end

	-- Check evolution exists
	if not Config.PET_EVOLUTIONS[baseId] then return end

	d.coins = d.coins - Config.EVOLUTION_COST

	-- Replace in inventory, keeping the same unique "#uid" suffix + level/XP.
	local uid       = fullId:match("#(.*)$")
	local evolvedId = (isShiny and "shiny:" or "") .. "evolved:" .. baseId .. (uid and ("#" .. uid) or "")
	d.inventory[invIdx] = evolvedId
	if d.petLevels then d.petLevels[evolvedId] = d.petLevels[fullId]; d.petLevels[fullId] = nil end
	if d.petXP     then d.petXP[evolvedId]     = d.petXP[fullId];     d.petXP[fullId]     = nil end

	Remotes.UpdateCoins:FireClient(player, d.coins)
	Remotes.UpdateInventory:FireClient(player, d.inventory)
	Remotes.FloatText:FireClient(player, "🌟 " .. Config.PET_EVOLUTIONS[baseId].name .. " evolved!")
	pushStats(player)
end)

-- ─── Equip (from inventory) ───────────────────────────────────────────────────
Remotes.EquipCreature.OnServerEvent:Connect(function(player, petId)
	if type(petId) ~= "string" then return end   -- never trust the client's arg
	local d = PlayerData.get(player)
	if d.inTrade then return end   -- inventory locked during a trade
	if not d.inventory then d.inventory = {} end

	-- Validate by BASE id so shiny:/evolved: pets are accepted too
	local baseId  = parseFullId(petId)
	local petDef = nil
	for _, p in ipairs(Config.PETS) do
		if p.id == baseId then petDef = p; break end
	end
	if not petDef then return end

	-- Find first occurrence in inventory
	local invIdx = nil
	for i, id in ipairs(d.inventory) do
		if id == petId then invIdx = i; break end
	end
	if not invIdx then return end

	-- Find a free equipment slot
	local slot = nil
	for i = 1, d.maxSlots do
		if not d.equipped[i] then slot = i; break end
	end

	if not slot then
		-- All slots full — bump slot 1 back to inventory
		table.insert(d.inventory, d.equipped[1])
		slot = 1
	end

	table.remove(d.inventory, invIdx)
	d.equipped[slot] = petId

	Remotes.UpdateEquipped:FireClient(player, d.equipped)
	Remotes.UpdateInventory:FireClient(player, d.inventory)
	pushStats(player)
end)

-- ─── Unequip (send back to inventory) ────────────────────────────────────────
Remotes.UnequipCreature.OnServerEvent:Connect(function(player, slotIdx)
	local d = PlayerData.get(player)
	if d.inTrade then return end   -- inventory locked during a trade
	if not d.inventory then d.inventory = {} end
	if type(slotIdx) ~= "number" then return end
	slotIdx = math.floor(slotIdx)
	if slotIdx < 1 or slotIdx > d.maxSlots then return end
	if d.equipped[slotIdx] then
		if #d.inventory < 60 then
			table.insert(d.inventory, d.equipped[slotIdx])
		end
		d.equipped[slotIdx] = nil
	end
	Remotes.UpdateEquipped:FireClient(player, d.equipped)
	Remotes.UpdateInventory:FireClient(player, d.inventory)
	pushStats(player)
end)

-- ─── Sell pet from inventory ──────────────────────────────────────────────────
Remotes.SellCreature.OnServerEvent:Connect(function(player, invIdx)
	local d = PlayerData.get(player)
	if d.inTrade then return end   -- inventory locked during a trade
	if not d.inventory then return end
	if type(invIdx) ~= "number" then return end
	invIdx = math.floor(invIdx)
	if invIdx < 1 or invIdx > #d.inventory then return end

	local petId     = d.inventory[invIdx]
	local baseId, isShiny = parseFullId(petId)   -- shiny:/evolved:/#uid
	local sellPrice = 0
	for _, p in ipairs(Config.PETS) do
		if p.id == baseId then
			-- Level/XP are keyed by this pet's UNIQUE instance id.
			local lvl      = (d.petLevels or {})[petId] or 1
			local goopMult = 1 + (lvl - 1) * Config.PET_LEVEL_BONUS
			local shinyM   = isShiny and Config.SHINY_GOOP_MULT or 1
			sellPrice = math.floor(p.goop * goopMult * shinyM * 3)
			break
		end
	end

	table.remove(d.inventory, invIdx)
	if d.petLevels then d.petLevels[petId] = nil end   -- free this instance's level
	if d.petXP     then d.petXP[petId]     = nil end
	d.coins = d.coins + sellPrice

	Remotes.UpdateCoins:FireClient(player, d.coins)
	Remotes.UpdateInventory:FireClient(player, d.inventory)
	Remotes.FloatText:FireClient(player, "💰  Sold for " .. sellPrice)
	pushStats(player)
end)

-- ─── Buy upgrade ─────────────────────────────────────────────────────────────
Remotes.BuyUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	if type(upgradeId) ~= "string" then return end
	local d    = PlayerData.get(player)
	local def  = nil
	for _, u in ipairs(Config.UPGRADES) do
		if u.id == upgradeId then def = u break end
	end
	if not def then return end

	local curLvl  = d.upgrades[upgradeId] or 0
	local nextLvl = curLvl + 1
	if nextLvl > #def.levels then return end   -- already max

	local cost = def.levels[nextLvl].cost
	if d.coins < cost then return end

	d.coins               = d.coins - cost
	d.upgrades[upgradeId] = nextLvl

	-- Apply effects
	if upgradeId == "slots" then
		PlayerData.recomputeMaxSlots(d)
	elseif upgradeId == "speed" then
		PlayerData.recomputeRollCooldown(d)
	elseif upgradeId == "luck" then
		PlayerData.recomputeLuck(d)
	end

	Remotes.UpdateCoins:FireClient(player, d.coins)
	pushStats(player)
end)

-- ─── Zone unlock (PER-PLAYER and PERSISTED) ──────────────────────────────────
-- Each player owns their own set of unlocked zones (d.unlockedZones), saved to
-- their data — so unlocks survive rejoins and aren't shared/reset by others.
-- The gate WALLS are made passable per-player on the client (it locally drops
-- CanCollide for gates that player has unlocked); the server just tracks the
-- set and validates combat against it.
local function processZoneUnlock(player, zoneName)
	if type(zoneName) ~= "string" then return end
	local d = PlayerData.get(player)
	d.unlockedZones = d.unlockedZones or {}
	if d.unlockedZones[zoneName] then return end        -- already open for them
	local cost = 0
	for _, z in ipairs(Config.ZONES) do
		if z.name == zoneName then cost = z.unlockCost; break end
	end
	if cost == 0 then return end                        -- unknown zone
	if d.coins < cost then return end                   -- can't afford

	d.coins              = d.coins - cost
	d.unlockedZones[zoneName] = true

	Remotes.UpdateCoins:FireClient(player, d.coins)
	pushStats(player)
	Remotes.FloatText:FireClient(player, "🔓  " .. zoneName .. " Unlocked!")
	Remotes.ZoneUnlocked:FireClient(player, zoneName)   -- only this player's gate opens
end

Remotes.UnlockZone.OnServerEvent:Connect(processZoneUnlock)

-- ─── Teleport to the furthest zone the player has unlocked ───────────────────
Remotes.TeleportZone.OnServerEvent:Connect(function(player)
	local d    = PlayerData.get(player)
	local char = player.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
	local bestZ = Config.ZONES[1].gateZ   -- forest is always reachable
	for _, z in ipairs(Config.ZONES) do
		if (z.unlockCost == 0) or (d.unlockedZones and d.unlockedZones[z.name]) then
			if z.gateZ > bestZ then bestZ = z.gateZ end
		end
	end
	char:PivotTo(CFrame.new(0, 8, bestZ + 40))   -- drop in just inside that zone
end)

-- Also wire ProximityPrompts created by WorldSetup
task.spawn(function()
	task.wait(3)
	for _, gf in ipairs(workspace:GetChildren()) do
		if gf.Name:sub(1, 5) == "Gate_" then
			local zoneName = gf.Name:sub(6)
			for _, desc in ipairs(gf:GetDescendants()) do
				if desc:IsA("ProximityPrompt") then
					desc.Triggered:Connect(function(player)
						processZoneUnlock(player, zoneName)
					end)
				end
			end
		end
	end
	print("[RollHandler] ProximityPrompts wired.")
end)

-- ─── Rebirth ─────────────────────────────────────────────────────────────────
Remotes.RequestRebirth.OnServerEvent:Connect(function(player)
	local d    = PlayerData.get(player)
	local cost = Config.REBIRTH_BASE_COST * (d.rebirths + 1)
	if d.coins < cost then return end

	-- Rebirth wipes ALL your coins (not just the cost) but keeps your pets,
	-- upgrades and items. In exchange your luck multiplier goes up.
	d.coins    = 0
	d.rebirths = d.rebirths + 1

	-- Luck multiplier stacks (rebirth bonus + upgrade bonus + mega luck pass)
	PlayerData.recomputeLuck(d)

	-- Re-lock all of THIS player's stage gates so they climb the zones again.
	d.unlockedZones = {}
	Remotes.ZonesReset:FireClient(player)

	-- Send you back to the spawn plaza.
	local char = player.Character
	local pad  = workspace:FindFirstChild("SpawnLocation")
	if char and pad then
		char:PivotTo(pad.CFrame + Vector3.new(0, 3, 0))
	end

	Remotes.UpdateCoins:FireClient(player, d.coins)
	pushStats(player)
end)

-- ─── Helper: push daily data to a single client ──────────────────────────────
local function pushDailyData(player)
	local d   = PlayerData.get(player)
	local now = tick()
	local spinReady  = (now - d.lastSpin)       >= Config.WHEEL_SPIN_COOLDOWN
	local dailyReady = (now - d.lastDailyClaim) >= Config.DAILY_REWARD_COOLDOWN
	local spinIn  = spinReady  and 0 or math.ceil(Config.WHEEL_SPIN_COOLDOWN  - (now - d.lastSpin))
	local dailyIn = dailyReady and 0 or math.ceil(Config.DAILY_REWARD_COOLDOWN - (now - d.lastDailyClaim))
	Remotes.DailyData:FireClient(player, {
		spinReady   = spinReady,
		spinIn      = spinIn,
		dailyReady  = dailyReady,
		dailyIn     = dailyIn,
		streak      = d.dailyStreak,
	})
end

-- ─── Daily Wheel spin ────────────────────────────────────────────────────────
Remotes.SpinWheel.OnServerEvent:Connect(function(player)
	local d   = PlayerData.get(player)
	local now = tick()
	if (now - d.lastSpin) < Config.WHEEL_SPIN_COOLDOWN then return end
	d.lastSpin = now

	-- Weighted random
	local total = 0
	for _, p in ipairs(Config.WHEEL_PRIZES) do total = total + p.weight end
	local roll = math.random() * total
	local cum  = 0
	local prizeIdx = 1
	for i, p in ipairs(Config.WHEEL_PRIZES) do
		cum = cum + p.weight
		if roll <= cum then prizeIdx = i; break end
	end

	local prize = Config.WHEEL_PRIZES[prizeIdx]
	if prize.reward == "coins" then
		d.coins = d.coins + prize.amount
		Remotes.UpdateCoins:FireClient(player, d.coins)
	elseif prize.reward == "luck" then
		d.luckBoostEnd = tick() + prize.amount
	end

	Remotes.WheelResult:FireClient(player, prizeIdx, prize.label, prize.amount)
	pushStats(player)
	pushDailyData(player)
end)

-- ─── Daily login reward ──────────────────────────────────────────────────────
Remotes.ClaimDaily.OnServerEvent:Connect(function(player)
	local d   = PlayerData.get(player)
	local now = tick()
	if (now - d.lastDailyClaim) < Config.DAILY_REWARD_COOLDOWN then return end

	-- Reset streak if more than 48 h gap
	if d.lastDailyClaim > 0 and (now - d.lastDailyClaim) > 172800 then
		d.dailyStreak = 0
	end

	d.lastDailyClaim = now
	d.dailyStreak    = (d.dailyStreak % #Config.DAILY_REWARDS) + 1
	local reward = Config.DAILY_REWARDS[d.dailyStreak]

	if reward.reward == "coins" then
		d.coins = d.coins + reward.amount
		Remotes.UpdateCoins:FireClient(player, d.coins)
	elseif reward.reward == "luck" then
		d.luckBoostEnd = tick() + reward.amount
	end

	Remotes.FloatText:FireClient(player, reward.icon.."  Day "..d.dailyStreak.."  "..reward.label.."!")
	pushStats(player)
	pushDailyData(player)
end)

-- ─── Send initial stats on join ───────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)              -- let client scripts load
		PlayerData.waitForLoad(player)   -- make sure we send their SAVED data
		pushStats(player)
		Remotes.UpdateCoins:FireClient(player, PlayerData.get(player).coins)
		Remotes.UpdateInventory:FireClient(player, PlayerData.get(player).inventory)
		Remotes.UpdateEquipped:FireClient(player, PlayerData.get(player).equipped)
		pushDailyData(player)
	end)
end)

-- (Player save + cleanup on leave is handled centrally in PlayerData, so the
-- profile is saved before it's cleared — don't remove it here.)

-- ─── Leaderboard broadcast ───────────────────────────────────────────────────
local function fmtCoins(n)
	if n >= 1000000 then return string.format("%.1fM", n/1000000)
	elseif n >= 1000 then return string.format("%.1fK", n/1000)
	else return tostring(n) end
end

task.spawn(function()
	while true do
		task.wait(4)
		local rows = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local d = PlayerData.get(p)
			table.insert(rows, { name = p.Name, coins = d.coins, display = fmtCoins(d.coins) })
		end
		table.sort(rows, function(a, b) return a.coins > b.coins end)
		if #rows > 8 then
			while #rows > 8 do table.remove(rows) end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			Remotes.UpdateLeaderboard:FireClient(p, rows, p.Name)
		end
	end
end)

print("[RollHandler] Ready.")

