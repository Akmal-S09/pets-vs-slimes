-- AdminCommands.server.luau
-- Chat commands for testing — grant pets, coins, luck, etc. without grinding rolls.
-- LOCKED to a single account: only "notoriusgb" can use these (Studio or live).
--
-- Type these in the chat box (press / to open chat):
--   /help                 list every command
--   /give all             grant one of every pet
--   /give shiny           grant a shiny of every pet
--   /give <id|name>       grant a specific pet  (e.g. /give mini_dragon  or  /give Frost Bunny)
--   /coins <n>            add n Goop            (e.g. /coins 1000000)
--   /luck <n>             set luck multiplier   (e.g. /luck 50)
--   /maxlevel             max-level every owned pet
--   /rebirth <n>          set rebirth count
--   /clear                empty your inventory

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Shared            = ReplicatedStorage:WaitForChild("Shared")

local Config     = require(Shared:WaitForChild("Config"))
local Remotes     = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent.PlayerData)

-- ════════════════════════════════════════════════════════════════════════════
-- STUDIO-ONLY MODULE. These commands grant free coins/items, so in a LIVE game
-- they would be an exploit. We bail out completely outside Studio — no remote
-- handlers, no chat hooks, nothing connected — so there is ZERO admin attack
-- surface for exploiters in the published game.
-- ════════════════════════════════════════════════════════════════════════════
if not RunService:IsStudio() then
	return
end

local function isAdmin(_plr)
	return true   -- only reached in Studio (guarded by the early return above)
end

-- ── Pet lookup (by id or by display name, case/space-insensitive) ───────────
local petByKey = {}
local function norm(s) return (s:lower():gsub("%s+", "")) end
for _, p in ipairs(Config.PETS) do
	petByKey[norm(p.id)]   = p
	petByKey[norm(p.name)] = p
end

-- ── Sync helpers ────────────────────────────────────────────────────────────
local function pushAll(plr, d)
	Remotes.UpdateCoins:FireClient(plr, d.coins)
	Remotes.UpdateInventory:FireClient(plr, d.inventory)
	Remotes.UpdateEquipped:FireClient(plr, d.equipped)
	Remotes.UpdateStats:FireClient(plr, PlayerData.snapshot(plr))
end

local function notify(plr, msg)
	Remotes.FloatText:FireClient(plr, msg)
end

local function grant(d, baseId, shiny)
	local fullId = shiny and ("shiny:" .. baseId) or baseId
	if #d.inventory < 60 then table.insert(d.inventory, fullId) end
	if not d.seenPets then d.seenPets = {} end
	d.seenPets[baseId] = true
end

-- ── Command handlers ────────────────────────────────────────────────────────
-- De-dupe: both chat systems may be wired, so ignore an identical command
-- from the same player within a short window.
local lastCmd = {}

local function handle(plr, raw)
	if type(raw) ~= "string" or not raw:match("^/") then return end
	if not isAdmin(plr) then return end

	local now = os.clock()
	local lc  = lastCmd[plr.UserId]
	if lc and lc.raw == raw and (now - lc.t) < 0.5 then return end
	lastCmd[plr.UserId] = { raw = raw, t = now }

	local args = {}
	for w in raw:gmatch("%S+") do table.insert(args, w) end
	local cmd = args[1]:lower()
	local d   = PlayerData.get(plr)

	if cmd == "/help" then
		notify(plr, "Cmds: /give all | /give shiny | /give <pet> | /coins n | /luck n | /maxlevel | /rebirth n | /clear")

	elseif cmd == "/give" then
		local what = (args[2] or ""):lower()
		if what == "all" or what == "shiny" then
			local shiny = (what == "shiny")
			for _, p in ipairs(Config.PETS) do grant(d, p.id, shiny) end
			notify(plr, (shiny and "✨ Granted a SHINY of every pet!" or "🎁 Granted every pet!"))
		else
			-- join args 2..n so multi-word names work ("/give Frost Bunny")
			local key = norm(table.concat(args, "", 2))
			local p   = petByKey[key]
			if p then grant(d, p.id, false); notify(plr, "🎁 Granted "..p.name.."!")
			else notify(plr, "❓ No pet '"..(args[2] or "").."'. Use the pet id or name.") end
		end
		pushAll(plr, d)

	elseif cmd == "/coins" or cmd == "/goop" then
		local n = tonumber(args[2]) or 0
		d.coins = math.max(0, d.coins + n)
		notify(plr, "💰 +"..n.." Coins")
		pushAll(plr, d)

	elseif cmd == "/luck" then
		local n = tonumber(args[2])
		if n then d.luckMult = n; notify(plr, "🍀 Luck set to "..n.."×"); pushAll(plr, d) end

	elseif cmd == "/maxlevel" then
		if not d.petLevels then d.petLevels = {} end
		for _, p in ipairs(Config.PETS) do d.petLevels[p.id] = Config.PET_MAX_LEVEL end
		notify(plr, "⬆ All pets max level!")
		pushAll(plr, d)

	elseif cmd == "/rebirth" then
		local n = tonumber(args[2])
		if n then
			d.rebirths = math.max(0, math.floor(n))
			local upgLuck = Config.LUCK_LEVELS[(d.upgrades.luck or 0) + 1]
			d.luckMult = upgLuck + (d.rebirths * Config.REBIRTH_LUCK_BONUS)
			notify(plr, "🔄 Rebirths set to "..d.rebirths)
			pushAll(plr, d)
		end

	elseif cmd == "/autoroll" then
		local arg = (args[2] or ""):lower()
		if arg == "on" then d.upgrades.autoroll = 1
		elseif arg == "off" then d.upgrades.autoroll = 0
		else d.upgrades.autoroll = (d.upgrades.autoroll > 0) and 0 or 1 end
		notify(plr, d.upgrades.autoroll > 0 and "🔄 Auto-roll ON" or "⏹ Auto-roll OFF")
		pushAll(plr, d)

	elseif cmd == "/clear" then
		d.inventory = {}
		notify(plr, "🗑 Inventory cleared")
		pushAll(plr, d)
	end
end

-- ── Wire up to whichever chat system the game uses ──────────────────────────
local TextChatService = game:GetService("TextChatService")

local ALIASES = { "/give", "/coins", "/goop", "/luck", "/maxlevel", "/rebirth", "/clear", "/help" }

local function wireTextChatCommands()
	for _, alias in ipairs(ALIASES) do
		local cmd = Instance.new("TextChatCommand")
		cmd.Name        = "Admin" .. alias:gsub("%W", "")
		cmd.PrimaryAlias = alias
		cmd.AutocompleteVisible = false
		cmd.Triggered:Connect(function(textSource, text)
			local plr = Players:GetPlayerByUserId(textSource.UserId)
			if plr then handle(plr, text) end
		end)
		cmd.Parent = TextChatService
	end
end

local function wireLegacyChat()
	local function hook(plr) plr.Chatted:Connect(function(msg) handle(plr, msg) end) end
	Players.PlayerAdded:Connect(hook)
	for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
end

-- Wire BOTH systems — the debounce in handle() prevents double execution.
-- This way commands work whether the place uses TextChatService or legacy chat.
pcall(wireTextChatCommands)
pcall(wireLegacyChat)

-- ── PRIMARY PATH: Admin GUI panel (chat-independent, always works) ──────────
-- The client admin panel fires a command string; we run it through handle(),
-- which already enforces isAdmin().
Remotes.AdminCmd.OnServerEvent:Connect(function(plr, text)
	if type(text) == "string" then handle(plr, text) end
end)

print("[AdminCommands] Ready (STUDIO ONLY — disabled in live games).")

