-- CombatHandler.server.luau
-- Spawns enemy slimes that wander their zone.
-- Equipped pets automatically attack nearby enemies — server-authoritative damage.
-- Clients receive PetAttack events to render local projectile visuals.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")

local Config     = require(Shared:WaitForChild("Config"))
local Remotes    = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent.PlayerData)

local RNG = Random.new()

-- ─── Pet lookup (id → def) ────────────────────────────────────────────────────
local PET_MAP = {}
for _, p in ipairs(Config.PETS) do PET_MAP[p.id] = p end

-- ─── Parse full pet ID (may have "shiny:" / "evolved:" prefixes) ─────────────
local function parsePetId(fullId)
	fullId = (fullId:gsub("#.*$", ""))   -- strip the unique "#uid" instance suffix
	local isShiny   = fullId:sub(1,6)   == "shiny:"
	local rest      = isShiny and fullId:sub(7) or fullId
	local isEvolved = rest:sub(1,8)     == "evolved:"
	local baseId    = isEvolved and rest:sub(9) or rest
	return baseId, isShiny, isEvolved
end

local function resolvePetDef(fullId)
	local baseId, isShiny, isEvolved = parsePetId(fullId)
	local petDef = PET_MAP[baseId]
	if not petDef then return nil, 1.0 end
	local extraMult = 1.0
	if isEvolved then
		local evo = Config.PET_EVOLUTIONS and Config.PET_EVOLUTIONS[baseId]
		if evo then extraMult = extraMult * evo.damageMult end
	end
	if isShiny then extraMult = extraMult * Config.SHINY_DAMAGE_MULT end
	return petDef, extraMult, baseId
end

-- ─── Pet XP / levelling (driven by combat) ───────────────────────────────────
-- Awards XP to ONE pet instance (keyed by its unique inventory id) and levels
-- it up while it has enough. XP needed per level grows by PET_XP_SCALE.
local lastXpPush = {}   -- player → tick() of last throttled stats push
local function addPetXP(player, d, fid, amount)
	if not fid then return end
	d.petLevels = d.petLevels or {}
	d.petXP     = d.petXP or {}
	local lvl = d.petLevels[fid] or 1
	if lvl >= Config.PET_MAX_LEVEL then return end

	d.petXP[fid] = (d.petXP[fid] or 0) + amount
	local leveled = false
	while lvl < Config.PET_MAX_LEVEL do
		local need = math.floor(Config.PET_XP_BASE * (Config.PET_XP_SCALE ^ (lvl - 1)))
		if d.petXP[fid] >= need then
			d.petXP[fid] = d.petXP[fid] - need
			lvl = lvl + 1
			leveled = true
		else
			break
		end
	end
	if leveled then
		d.petLevels[fid] = lvl
		if lvl >= Config.PET_MAX_LEVEL then d.petXP[fid] = 0 end
		local petDef = PET_MAP[(parsePetId(fid))]
		Remotes.FloatText:FireClient(player, "⬆ " .. (petDef and petDef.name or "Pet") .. " → Lv." .. lvl .. "!")
	end
	-- Push fresh stats on level-up, otherwise throttle so the XP bars still
	-- advance live during combat without spamming a full snapshot every kill.
	local now = tick()
	if leveled or (now - (lastXpPush[player] or 0)) > 1.5 then
		lastXpPush[player] = now
		Remotes.UpdateStats:FireClient(player, PlayerData.snapshot(player))
	end
end

-- ─── Collection bonus calculator ─────────────────────────────────────────────
local function collectionMult(d)
	local seen = d.seenPets or {}
	local mult = 1.0
	for _, cb in ipairs(Config.COLLECTION_BONUSES) do
		local ok = true
		for _, pid in ipairs(cb.pets) do
			if not seen[pid] then ok = false; break end
		end
		if ok then mult = mult * cb.goop_mult end
	end
	return mult
end

-- ─── Combo kill tracking ─────────────────────────────────────────────────────
local comboCount    = {}   -- [userId] = count
local comboLastTime = {}   -- [userId] = tick()

-- ─── Zone definitions ─────────────────────────────────────────────────────────
-- Derived from Config.ZONES so all 30 stages get enemy spawns automatically.
local ZONE_DEFS = {}
local ZONE_NAME = {}   -- zoneId → display name (gates are named by display name)
for _, z in ipairs(Config.ZONES) do
	table.insert(ZONE_DEFS, { id=z.id, x1=-88, x2=88, z1=z.gateZ+15, z2=z.gateZ+285 })
	ZONE_NAME[z.id] = z.name
end

-- ─── Anti-exploit: pets only attack enemies in zones the PLAYER has unlocked,
-- so a flying/teleporting exploiter can't farm zones they haven't paid for.
-- (Per-player now, matching the persisted per-player unlock set.) ──
local FIRST_ZONE_ID = Config.ZONES[1].id   -- always-open starting zone
local function playerHasZone(d, zoneId)
	if zoneId == FIRST_ZONE_ID then return true end
	local name = ZONE_NAME[zoneId]
	return name ~= nil and d.unlockedZones ~= nil and d.unlockedZones[name] == true
end

local ZONE_TYPES = {}
for _, zd in ipairs(ZONE_DEFS) do
	local pool = {}
	for _, et in ipairs(Config.ENEMY_TYPES) do
		if et.zone == zd.id then table.insert(pool, et) end
	end
	ZONE_TYPES[zd.id] = pool
end

local PER_ZONE = math.floor(Config.ENEMY_COUNT / #ZONE_DEFS)

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function randPosInZone(zd)
	return Vector3.new(
		RNG:NextNumber(zd.x1, zd.x2), 2.5,
		RNG:NextNumber(zd.z1, zd.z2))
end

local function pickZoneType(zoneId)
	local pool = ZONE_TYPES[zoneId]
	if not pool or #pool == 0 then return Config.ENEMY_TYPES[1] end
	return pool[RNG:NextInteger(1, #pool)]
end

local function getHRP(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- ─── Enemy state ─────────────────────────────────────────────────────────────
local enemies = {}   -- [idx] → enemy struct

local function makeHpBar(body, sz, etype)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(70, 10)
	bb.StudsOffset = Vector3.new(0, sz/2 + 1.4, 0)
	bb.MaxDistance = 35; bb.Adornee = body; bb.Parent = body

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1,0,1,0)
	bg.BackgroundColor3 = Color3.fromRGB(35,8,8)
	bg.BorderSizePixel = 0; bg.Parent = bb
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=bg end

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1,0,1,0)
	fill.BackgroundColor3 = Color3.fromRGB(75,220,60)
	fill.BorderSizePixel = 0; fill.Parent = bg
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=fill end

	return fill
end

local function spawnEnemy(idx, zoneId)
	local zd    = ZONE_DEFS[1]
	for _, z in ipairs(ZONE_DEFS) do if z.id == zoneId then zd = z; break end end
	local etype = pickZoneType(zoneId)
	local sz    = 3 * etype.sz
	local pos   = randPosInZone(zd)

	-- Body (sphere)
	local body          = Instance.new("Part")
	body.Shape          = Enum.PartType.Ball
	body.Size           = Vector3.new(sz, sz, sz)
	body.Color          = etype.color
	body.Material       = Enum.Material.SmoothPlastic
	body.Anchored       = true
	body.CanCollide     = false
	body.CastShadow     = false
	body.CFrame         = CFrame.new(pos.X, sz/2 + 2, pos.Z)   -- sit clear of the terrain surface
	body.Name           = "EnemySlime_" .. idx
	body.Parent         = workspace

	-- ── Cute welded face: white eyes + pupils + shine, smile, glossy highlight,
	-- little antennae. Welded to the body so it moves as one piece. ──
	local W, INK = Color3.new(1,1,1), Color3.fromRGB(28,22,38)
	local BALL = Enum.PartType.Ball
	local function facePart(shape, size, col, mat, tr, offset)
		local p = Instance.new("Part")
		p.Shape = shape; p.Size = size; p.Color = col
		p.Material = mat or Enum.Material.SmoothPlastic
		p.CanCollide=false; p.CastShadow=false; p.Anchored=false; p.Transparency = tr or 0
		p:SetAttribute("baseTr", tr or 0)
		p.CFrame = body.CFrame * offset
		p.Parent = body
		local wc = Instance.new("WeldConstraint"); wc.Part0=body; wc.Part1=p; wc.Parent=p
		return p
	end
	local antCol = etype.color:Lerp(Color3.fromRGB(255,160,40), 0.55)
	local face = {
		facePart(BALL, Vector3.new(sz*0.27,sz*0.27,sz*0.20), W,   nil, 0, CFrame.new(-sz*0.20, sz*0.12, -sz*0.36)),
		facePart(BALL, Vector3.new(sz*0.27,sz*0.27,sz*0.20), W,   nil, 0, CFrame.new( sz*0.20, sz*0.12, -sz*0.36)),
		facePart(BALL, Vector3.new(sz*0.13,sz*0.13,sz*0.10), INK, nil, 0, CFrame.new(-sz*0.20, sz*0.10, -sz*0.46)),
		facePart(BALL, Vector3.new(sz*0.13,sz*0.13,sz*0.10), INK, nil, 0, CFrame.new( sz*0.20, sz*0.10, -sz*0.46)),
		facePart(BALL, Vector3.new(sz*0.06,sz*0.06,sz*0.05), W,   nil, 0, CFrame.new(-sz*0.23, sz*0.16, -sz*0.49)),
		facePart(BALL, Vector3.new(sz*0.06,sz*0.06,sz*0.05), W,   nil, 0, CFrame.new( sz*0.17, sz*0.16, -sz*0.49)),
		facePart(BALL, Vector3.new(sz*0.17,sz*0.11,sz*0.09), Color3.fromRGB(120,30,42), nil, 0, CFrame.new(0, -sz*0.07, -sz*0.45)),  -- smile
		facePart(BALL, Vector3.new(sz*0.5,sz*0.5,sz*0.5), W, Enum.Material.SmoothPlastic, 0.72, CFrame.new(-sz*0.18, sz*0.22, -sz*0.20)),  -- gloss
		facePart(Enum.PartType.Block, Vector3.new(sz*0.06,sz*0.26,sz*0.06), antCol, nil, 0, CFrame.new(-sz*0.12, sz*0.52, 0)*CFrame.Angles(0,0, 0.25)),
		facePart(Enum.PartType.Block, Vector3.new(sz*0.06,sz*0.26,sz*0.06), antCol, nil, 0, CFrame.new( sz*0.12, sz*0.52, 0)*CFrame.Angles(0,0,-0.25)),
		facePart(BALL, Vector3.new(sz*0.11,sz*0.11,sz*0.11), Color3.fromRGB(255,150,40), nil, 0, CFrame.new(-sz*0.16, sz*0.64, 0)),
		facePart(BALL, Vector3.new(sz*0.11,sz*0.11,sz*0.11), Color3.fromRGB(255,150,40), nil, 0, CFrame.new( sz*0.16, sz*0.64, 0)),
	}

	-- HP bar
	local hpFill = makeHpBar(body, sz, etype)

	-- Name tag
	local nameBb = Instance.new("BillboardGui")
	nameBb.Size = UDim2.fromOffset(120, 18)
	nameBb.StudsOffset = Vector3.new(0, sz/2 + 2.2, 0)
	nameBb.MaxDistance = 30; nameBb.Adornee = body; nameBb.Parent = body
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1,0,1,0); tag.BackgroundTransparency = 1
	tag.Text = etype.name; tag.TextColor3 = etype.color
	tag.Font = Enum.Font.GothamBold; tag.TextSize = 11
	tag.TextStrokeTransparency = 0.3; tag.Parent = nameBb

	-- Point light
	local pl = Instance.new("PointLight")
	pl.Color = etype.color; pl.Range = 8; pl.Brightness = 0.8; pl.Parent = body

	enemies[idx] = {
		part       = body,
		face       = face,
		hpFill     = hpFill,
		pl         = pl,
		etype      = etype,
		zoneId     = zoneId,
		zd         = zd,
		sz         = sz,
		bobPhase   = RNG:NextNumber(0, 6.28),
		currentHp  = etype.hp,
		maxHp      = etype.hp,
		dir        = Vector3.new(RNG:NextNumber(-1,1), 0, RNG:NextNumber(-1,1)).Unit,
		dirTimer   = RNG:NextNumber(2, 5),
		dead       = false,
		deadTimer  = 0,
		flashTimer = 0,
		flashT     = 0,
		atkTimer   = RNG:NextNumber(0, Config.ENEMY_ATTACK_INTERVAL),
	}
end

-- Initial spawn
local idx = 1
for _, zd in ipairs(ZONE_DEFS) do
	for _ = 1, PER_ZONE do spawnEnemy(idx, zd.id); idx = idx + 1 end
end
while idx <= Config.ENEMY_COUNT do spawnEnemy(idx, "forest"); idx = idx + 1 end

-- ─── Per-pet attack timers ────────────────────────────────────────────────────
-- petAttackState[userId][slotIndex] = { timer = seconds_until_next_shot }
local petAttackState = {}

Players.PlayerRemoving:Connect(function(p) petAttackState[p.UserId] = nil end)

-- ─── Pet HP / "downed" state ──────────────────────────────────────────────────
-- petState[userId][slot] = { id=fullId, hp=, max=, reviveAt= }.  Slimes near a
-- player damage a random active pet; at 0 HP the pet goes down for PET_DOWN_TIME.
local petState = {}
Players.PlayerRemoving:Connect(function(p) petState[p.UserId] = nil end)

local function petMaxHP(petDef, lvl, extraMult)
	local rarityBonus = (petDef.rarity ^ 0.25) * 25     -- rarer pets are tankier
	local base = Config.PET_BASE_HP + rarityBonus
	return math.floor(base * (1 + (lvl - 1) * Config.PET_LEVEL_BONUS) * (extraMult or 1))
end

local function sendPetStatus(player)
	local d   = PlayerData.get(player)
	local st  = petState[player.UserId]
	local now = tick()
	local map = {}
	for slot = 1, d.maxSlots do
		local s = st and st[slot]
		if s then
			map[slot] = {
				hp       = s.hp,
				max      = s.max,
				reviveIn = (s.reviveAt > now) and math.ceil(s.reviveAt - now) or 0,
			}
		end
	end
	Remotes.PetStatus:FireClient(player, map)
end

-- Get / lazily (re)initialise the HP state for the pet currently in `slot`.
local function petSlotState(player, d, slot)
	local fullId = d.equipped[slot]
	if not fullId then return nil end
	local petDef, extraMult, baseId = resolvePetDef(fullId)
	if not petDef then return nil end
	local uid = player.UserId
	petState[uid] = petState[uid] or {}
	local s = petState[uid][slot]
	if not s or s.id ~= fullId then
		local lvl = ((d.petLevels or {})[fullId]) or 1   -- unique-instance level
		local max = petMaxHP(petDef, lvl, extraMult)
		s = { id = fullId, hp = max, max = max, reviveAt = 0 }
		petState[uid][slot] = s
		sendPetStatus(player)   -- show the full bar as soon as a pet is equipped
	end
	return s, petDef
end

local function damagePet(player, d, slot, dmg)
	local s = petState[player.UserId] and petState[player.UserId][slot]
	local now = tick()
	if not s or s.reviveAt > now or s.hp <= 0 then return end
	s.hp = s.hp - dmg
	if s.hp <= 0 then
		s.hp = 0
		s.reviveAt = now + Config.PET_DOWN_TIME
		local petDef = resolvePetDef(s.id)
		Remotes.FloatText:FireClient(player,
			"💀 " .. (petDef and petDef.name or "Pet") .. " downed!  (" .. Config.PET_DOWN_TIME .. "s)")
	end
	sendPetStatus(player)   -- update the health bar (and downed state) every hit
end

-- ─── Main loop ────────────────────────────────────────────────────────────────
local MOVE_SPEED  = 6
local AGGRO_RANGE = 22   -- studs at which a slime stops wandering and locks onto a player
local RESPAWN     = Config.ENEMY_RESPAWN_TIME
local boundsTimer = 0    -- throttle for the anti-fly boundary check

RunService.Heartbeat:Connect(function(dt)

	-- Snapshot online players' positions once (used by enemy → pet attacks).
	local plist = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local hrp = getHRP(pl)
		if hrp then
			plist[#plist + 1] = { player = pl, d = PlayerData.get(pl), pos = hrp.Position }
		end
	end

	-- ── Anti-fly boundary: if a player has flown/teleported PAST the gate of a
	-- zone they haven't unlocked, shove them back to the unlocked side. Checked
	-- a few times a second; legit players are wall-blocked so this only hits
	-- exploiters. ──
	boundsTimer = boundsTimer - dt
	if boundsTimer <= 0 then
		boundsTimer = 0.4
		for _, pe in ipairs(plist) do
			local char = pe.player.Character
			local limitZ
			for i = 2, #Config.ZONES do
				local z = Config.ZONES[i]
				if not (pe.d.unlockedZones and pe.d.unlockedZones[z.name]) then
					limitZ = z.gateZ; break          -- entrance to first locked zone
				end
			end
			if char and limitZ and pe.pos.Z > limitZ + 6 then
				-- Flew past a locked gate → back to the unlocked side (and ground).
				char:PivotTo(CFrame.new(0, 8, limitZ - 14))
			elseif char and pe.pos.Y > 35 then
				-- Flying way up → pull them back down to the ground where they are.
				char:PivotTo(CFrame.new(math.clamp(pe.pos.X, -85, 85), 8, pe.pos.Z))
			end
		end
	end

	-- ── Enemy movement + respawn ────────────────────────────────────────────
	for eidx, e in pairs(enemies) do
		local part = e.part
		if not part or not part.Parent then enemies[eidx] = nil; continue end

		if e.dead then
			e.deadTimer = e.deadTimer - dt
			if e.deadTimer <= 0 then
				-- Revive the SAME slime (keeps its welded face/size) at a new spot.
				local pos   = randPosInZone(e.zd)
				part.CFrame = CFrame.new(pos.X, e.sz/2 + 2, pos.Z)
				part.Transparency = 0
				for _, fp in ipairs(e.face) do fp.Transparency = fp:GetAttribute("baseTr") or 0 end
				e.currentHp = e.maxHp
				e.hpFill.Size = UDim2.new(1, 0, 1, 0)
				e.hpFill.BackgroundColor3 = Color3.fromRGB(75, 220, 60)
				e.dead = false
			end
			continue
		end

		-- Flash on hit
		if e.flashTimer > 0 then
			e.flashTimer = e.flashTimer - dt
			e.flashT     = e.flashT + dt * 14
			local f = (math.sin(e.flashT) + 1) * 0.4
			part.Color = e.etype.color:Lerp(Color3.new(1,1,1), f)
		else
			part.Color = e.etype.color
		end

		local zd   = e.zd
		local bobY = e.sz/2 + 2 + math.sin(tick()*2.5 + (e.bobPhase or 0)) * 0.5

		-- Is a player close enough to aggro onto?
		local aggroPos, aggroD
		for _, pe in ipairs(plist) do
			local dd = (pe.pos - part.Position).Magnitude
			if dd <= AGGRO_RANGE and (not aggroD or dd < aggroD) then aggroPos, aggroD = pe.pos, dd end
		end

		if aggroPos then
			-- LOCK ON: stop wandering, turn to face the player, and bob in place
			-- (the attack itself fires from the atkTimer block below).
			local here = Vector3.new(part.Position.X, bobY, part.Position.Z)
			local yaw  = math.atan2(aggroPos.X - here.X, aggroPos.Z - here.Z)
			part.CFrame = CFrame.new(here) * CFrame.Angles(0, yaw, 0)
		else
			-- Wander
			e.dirTimer = e.dirTimer - dt
			if e.dirTimer <= 0 then
				e.dir = Vector3.new(RNG:NextNumber(-1,1), 0, RNG:NextNumber(-1,1)).Unit
				e.dirTimer = RNG:NextNumber(2, 5)
			end
			local newPos = part.Position + e.dir * MOVE_SPEED * dt
			newPos = Vector3.new(
				math.clamp(newPos.X, zd.x1, zd.x2),
				bobY,
				math.clamp(newPos.Z, zd.z1, zd.z2))
			if newPos.X == zd.x1 or newPos.X == zd.x2 then e.dir = Vector3.new(-e.dir.X, 0, e.dir.Z) end
			if newPos.Z == zd.z1 or newPos.Z == zd.z2 then e.dir = Vector3.new(e.dir.X, 0, -e.dir.Z) end
			part.CFrame = CFrame.new(newPos) * CFrame.Angles(0, math.atan2(e.dir.X, e.dir.Z), 0)
		end
		-- (face is welded to the body, so it follows automatically)

		-- ── Slime attacks a nearby player's pet ───────────────────────────────
		e.atkTimer = (e.atkTimer or 0) - dt
		if e.atkTimer <= 0 then
			local best, bestDist
			for _, pe in ipairs(plist) do
				local dd = (pe.pos - part.Position).Magnitude
				if dd <= Config.ENEMY_ATTACK_RANGE and (not bestDist or dd < bestDist) then
					best, bestDist = pe, dd
				end
			end
			if best then
				local now    = tick()
				local stp    = petState[best.player.UserId]
				local active = {}
				for slot = 1, best.d.maxSlots do
					if best.d.equipped[slot] then
						local s = stp and stp[slot]
						if (not s) or (s.reviveAt <= now and s.hp > 0) then
							petSlotState(best.player, best.d, slot)   -- ensure HP exists
							active[#active + 1] = slot
						end
					end
				end
				if #active > 0 then
					local slot = active[RNG:NextInteger(1, #active)]
					-- Tell the owner to render the lunge / hit effect on that pet.
					Remotes.EnemyAttack:FireClient(best.player, "EnemySlime_" .. eidx, slot)
					damagePet(best.player, best.d, slot, e.etype.atk or 5)
					e.atkTimer = Config.ENEMY_ATTACK_INTERVAL
				else
					e.atkTimer = 1.0   -- no live pets to hit; check again soon
				end
			else
				e.atkTimer = 0.5       -- no player in range
			end
		end
	end

	-- ── Pet attacks ─────────────────────────────────────────────────────────
	for _, player in ipairs(Players:GetPlayers()) do
		local d   = PlayerData.get(player)
		local hrp = getHRP(player)
		if not hrp then continue end
		local ppos = hrp.Position

		local uid = player.UserId
		if not petAttackState[uid] then petAttackState[uid] = {} end

		for slot = 1, d.maxSlots do
			local fullPetId = d.equipped[slot]
			if not fullPetId then continue end

			local petDef, extraMult, baseId = resolvePetDef(fullPetId)
			if not petDef then continue end

			-- Pet HP / downed state: revive when the timer is up, skip if still down.
			local pstate = petSlotState(player, d, slot)
			if pstate then
				if pstate.reviveAt > 0 and tick() >= pstate.reviveAt then
					pstate.hp = pstate.max; pstate.reviveAt = 0
					Remotes.FloatText:FireClient(player, "✨ " .. petDef.name .. " revived!")
					sendPetStatus(player)
				end
				if pstate.reviveAt > tick() then continue end   -- downed → can't attack
			end

			local lvl     = ((d.petLevels or {})[fullPetId]) or 1   -- this instance's level
			local bonus   = 1 + (lvl - 1) * Config.PET_LEVEL_BONUS
			local powMult = Config.POWER_LEVELS[(d.upgrades.power or 0) + 1] or 1
			local damage  = math.floor(petDef.ability.damage * bonus * extraMult * powMult)
			local range   = petDef.ability.range

			local state = petAttackState[uid][slot]
			if not state then
				-- Stagger initial shots so all pets don't fire at once
				petAttackState[uid][slot] = { timer = (slot - 1) * 0.35 }
				state = petAttackState[uid][slot]
			end

			state.timer = state.timer - dt
			if state.timer > 0 then continue end

			-- Find nearest alive enemy in range (only in UNLOCKED zones, so a
			-- flying/teleporting exploiter can't farm zones they haven't unlocked).
			local best     = nil
			local bestDist = math.huge
			for eidx, e in pairs(enemies) do
				if e.dead then continue end
				if not playerHasZone(d, e.zoneId) then continue end
				local dist = (e.part.Position - ppos).Magnitude
				if dist <= range and dist < bestDist then
					bestDist = dist; best = { idx = eidx, e = e }
				end
			end

			if best then
				local e = best.e

				-- Apply damage
				e.currentHp  = e.currentHp - damage
				e.flashTimer = 0.22

				-- Estimate pet world-position (it orbits the player client-side)
				local phase     = (slot - 1) * (math.pi * 2 / math.max(d.maxSlots, 1))
				local t         = tick()
				local orbitX    = Config.PET_ORBIT_RADIUS * math.cos(t * Config.PET_ORBIT_SPEED + phase)
				local orbitZ    = Config.PET_ORBIT_RADIUS * math.sin(t * Config.PET_ORBIT_SPEED + phase)
				local fromPos   = ppos + Vector3.new(orbitX, Config.PET_ORBIT_HEIGHT, orbitZ)
				local toPos     = e.part.Position

				-- Tell all clients to render the projectile
				Remotes.PetAttack:FireAllClients(
					player.Name, slot,
					"EnemySlime_" .. best.idx,
					petDef.ability.id,
					fromPos, toPos)

				if e.currentHp <= 0 then
					-- ── Combo tracking ────────────────────────────────────────
					local uid2  = player.UserId
					local now2  = tick()
					if comboLastTime[uid2] and (now2 - comboLastTime[uid2]) < Config.COMBO_WINDOW then
						comboCount[uid2] = (comboCount[uid2] or 1) + 1
					else
						comboCount[uid2] = 1
					end
					comboLastTime[uid2] = now2
					local combo = comboCount[uid2]

					-- ── Goop: all multipliers ─────────────────────────────────
					local colMult  = collectionMult(d)
					local combMult = 1 + math.max(0, combo - 1) * Config.COMBO_BONUS
					local greedM   = Config.COIN_LEVELS[(d.upgrades.greed or 0) + 1] or 1
					local vipM     = d.passVIP and Config.VIP_COIN_MULT or 1
					local goopGain = math.floor(e.etype.goop * bonus * extraMult * colMult * combMult * greedM * vipM)
					d.coins = d.coins + goopGain
					Remotes.UpdateCoins:FireClient(player, d.coins)

					-- The pet that landed the kill earns XP toward its next level.
					-- Stronger slimes (higher tier / later zone) grant more XP.
					local killXP = math.max(1, math.floor(Config.PET_XP_PER_KILL * (e.etype.xpMult or 1)))
					addPetXP(player, d, fullPetId, killXP)
					if combo >= 2 then
						Remotes.ComboKill:FireClient(player, combo)
						Remotes.FloatText:FireClient(player, "⚡ COMBO ×"..combo.."  +"..goopGain.." 💰")
					else
						Remotes.FloatText:FireClient(player, "+" .. goopGain .. " 💰")
					end

					e.part.Transparency = 1
					for _, fp in ipairs(e.face) do fp.Transparency = 1 end
					e.hpFill.Size       = UDim2.new(0, 0, 1, 0)
					e.dead              = true
					e.deadTimer         = RESPAWN
					Remotes.EnemyDamaged:FireAllClients("EnemySlime_" .. best.idx, 0)
				else
					local hpPct = math.max(0, e.currentHp / e.maxHp)
					e.hpFill.Size = UDim2.new(hpPct, 0, 1, 0)
					-- Tint bar red as HP falls
					local barR = math.floor(75 + (1 - hpPct) * 180)
					local barG = math.floor(220 * hpPct)
					e.hpFill.BackgroundColor3 = Color3.fromRGB(barR, barG, 30)
					Remotes.EnemyDamaged:FireAllClients("EnemySlime_" .. best.idx, hpPct)
				end

				state.timer = petDef.ability.fireRate
			else
				state.timer = 0.2   -- no target found; retry soon
			end
		end
	end
end)

print("[CombatHandler] " .. Config.ENEMY_COUNT .. " enemy slimes spawned (pet combat mode).")

