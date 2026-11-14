-- TradeHandler.server.luau
-- Server-authoritative player-to-player trading.
--
-- Flow: A invites B → B accepts → both add inventory pets to their offer →
-- both press LOCK → when BOTH are locked the swap executes atomically.
-- Changing an offer un-locks both sides (standard anti-scam).
--
-- Safety:
--   • While in a trade a player's inventory is frozen for index-shifting ops
--     (sell/equip/unequip/evolve are rejected in RollHandler via d.inTrade),
--     so the offered indices stay valid. Rolls only append, which is safe.
--   • The swap re-validates every offered index and the 60-pet cap before
--     moving anything, and removes by descending index so nothing dupes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")

local Remotes    = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent.PlayerData)

local MAX_INV       = 60
local INVITE_EXPIRE = 30   -- seconds

-- ─── State ────────────────────────────────────────────────────────────────────
local sessionByPlayer = {}   -- player → session
local pendingInvite   = {}   -- targetPlayer → { from = invitingPlayer, at = tick() }

-- session = {
--   a, b           : the two players
--   offer  = { [player] = { [invIdx]=true } }
--   locked = { [player] = bool }
-- }

local function snapshotStats(player)
	Remotes.UpdateStats:FireClient(player, PlayerData.snapshot(player))
end

-- Resolve a player's offered indices → array of fullId strings (valid only).
local function offeredFullIds(player, session)
	local d   = PlayerData.get(player)
	local inv = d.inventory or {}
	local ids = {}
	for idx in pairs(session.offer[player]) do
		local fid = inv[idx]
		if fid then ids[#ids+1] = fid end
	end
	return ids
end

local function offeredIndices(player, session)
	local idxs = {}
	for idx in pairs(session.offer[player]) do idxs[#idxs+1] = idx end
	table.sort(idxs)
	return idxs
end

local function sendState(session)
	for _, p in ipairs({ session.a, session.b }) do
		local other = (p == session.a) and session.b or session.a
		Remotes.TradeState:FireClient(p, {
			partner     = other.Name,
			mine        = offeredFullIds(p, session),
			mineIdx     = offeredIndices(p, session),
			theirs      = offeredFullIds(other, session),
			myLocked    = session.locked[p] == true,
			theirLocked = session.locked[other] == true,
		})
	end
end

local function resetLocks(session)
	session.locked[session.a] = false
	session.locked[session.b] = false
end

local function endSession(session, msgA, msgB)
	sessionByPlayer[session.a] = nil
	sessionByPlayer[session.b] = nil
	PlayerData.get(session.a).inTrade = false
	PlayerData.get(session.b).inTrade = false
	-- clear UI on both clients
	if session.a.Parent then Remotes.TradeState:FireClient(session.a, nil) end
	if session.b.Parent then Remotes.TradeState:FireClient(session.b, nil) end
	if msgA and session.a.Parent then Remotes.TradePopup:FireClient(session.a, msgA) end
	if msgB and session.b.Parent then Remotes.TradePopup:FireClient(session.b, msgB) end
end

local function startSession(a, b)
	local session = {
		a = a, b = b,
		offer  = { [a] = {}, [b] = {} },
		locked = { [a] = false, [b] = false },
	}
	sessionByPlayer[a] = session
	sessionByPlayer[b] = session
	PlayerData.get(a).inTrade = true
	PlayerData.get(b).inTrade = true
	sendState(session)
end

-- ─── Swap ─────────────────────────────────────────────────────────────────────
local function executeTrade(session)
	local a, b   = session.a, session.b
	local da, db = PlayerData.get(a), PlayerData.get(b)
	da.inventory = da.inventory or {}
	db.inventory = db.inventory or {}

	-- Collect offered indices (descending so removal keeps indices valid).
	local function collect(p)
		local idxs = {}
		for idx in pairs(session.offer[p]) do idxs[#idxs+1] = idx end
		table.sort(idxs, function(x, y) return x > y end)
		return idxs
	end
	local aIdx, bIdx = collect(a), collect(b)

	-- Validate indices are still in range.
	for _, i in ipairs(aIdx) do if not da.inventory[i] then resetLocks(session); sendState(session); return end end
	for _, i in ipairs(bIdx) do if not db.inventory[i] then resetLocks(session); sendState(session); return end end

	-- Capacity check (each side loses its offer, gains the other's).
	local aFinal = #da.inventory - #aIdx + #bIdx
	local bFinal = #db.inventory - #bIdx + #aIdx
	if aFinal > MAX_INV or bFinal > MAX_INV then
		resetLocks(session); sendState(session)
		Remotes.TradePopup:FireClient(a, "❌ Not enough inventory space.")
		Remotes.TradePopup:FireClient(b, "❌ Not enough inventory space.")
		return
	end

	-- Pull offered items out (descending order).
	local aItems, bItems = {}, {}
	for _, i in ipairs(aIdx) do aItems[#aItems+1] = table.remove(da.inventory, i) end
	for _, i in ipairs(bIdx) do bItems[#bItems+1] = table.remove(db.inventory, i) end

	da.petLevels = da.petLevels or {}; da.petXP = da.petXP or {}
	db.petLevels = db.petLevels or {}; db.petXP = db.petXP or {}

	-- Move each pet's level/XP along with it (ids are globally unique, no clash).
	local function handover(items, fromD, toD)
		for _, fid in ipairs(items) do
			table.insert(toD.inventory, fid)
			toD.petLevels[fid] = fromD.petLevels[fid]; fromD.petLevels[fid] = nil
			toD.petXP[fid]     = fromD.petXP[fid];     fromD.petXP[fid]     = nil
		end
	end
	handover(aItems, da, db)
	handover(bItems, db, da)

	Remotes.UpdateInventory:FireClient(a, da.inventory)
	Remotes.UpdateInventory:FireClient(b, db.inventory)
	snapshotStats(a); snapshotStats(b)

	endSession(session, "✅ Trade complete!", "✅ Trade complete!")
end

-- ─── Remote handlers ───────────────────────────────────────────────────────────
Remotes.TradeInvite.OnServerEvent:Connect(function(player, targetUserId)
	if type(targetUserId) ~= "number" then return end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then return end
	if sessionByPlayer[player] or sessionByPlayer[target] then
		Remotes.TradePopup:FireClient(player, "❌ That player is busy.")
		return
	end
	pendingInvite[target] = { from = player, at = tick() }
	Remotes.TradeInviteIn:FireClient(target, { fromName = player.Name, fromId = player.UserId })
	Remotes.TradePopup:FireClient(player, "📨 Trade request sent to " .. target.Name .. ".")
end)

Remotes.TradeRespond.OnServerEvent:Connect(function(player, accept)
	local inv = pendingInvite[player]
	pendingInvite[player] = nil
	if not inv then return end
	local from = inv.from
	if (tick() - inv.at) > INVITE_EXPIRE then return end
	if not from.Parent then return end

	if not accept then
		Remotes.TradePopup:FireClient(from, "🚫 " .. player.Name .. " declined the trade.")
		return
	end
	if sessionByPlayer[player] or sessionByPlayer[from] then
		Remotes.TradePopup:FireClient(player, "❌ That player is busy.")
		return
	end
	startSession(from, player)
end)

Remotes.TradeToggleItem.OnServerEvent:Connect(function(player, invIdx)
	local session = sessionByPlayer[player]
	if not session then return end
	if type(invIdx) ~= "number" then return end
	invIdx = math.floor(invIdx)
	local d = PlayerData.get(player)
	if invIdx < 1 or invIdx > #(d.inventory or {}) then return end

	local off = session.offer[player]
	off[invIdx] = (not off[invIdx]) or nil
	resetLocks(session)   -- any change un-readies both sides
	sendState(session)
end)

Remotes.TradeLock.OnServerEvent:Connect(function(player)
	local session = sessionByPlayer[player]
	if not session then return end
	session.locked[player] = not session.locked[player]
	sendState(session)
	if session.locked[session.a] and session.locked[session.b] then
		executeTrade(session)
	end
end)

Remotes.TradeCancel.OnServerEvent:Connect(function(player)
	local session = sessionByPlayer[player]
	if not session then return end
	local other = (player == session.a) and session.b or session.a
	endSession(session, "🚫 Trade cancelled.", "🚫 " .. player.Name .. " cancelled the trade.")
end)

-- ─── Cleanup on leave ──────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	local session = sessionByPlayer[player]
	if session then
		local other = (player == session.a) and session.b or session.a
		endSession(session, nil, "🚫 " .. player.Name .. " left — trade cancelled.")
	end
	pendingInvite[player] = nil
	for target, inv in pairs(pendingInvite) do
		if inv.from == player then pendingInvite[target] = nil end
	end
end)

print("[TradeHandler] Ready.")

