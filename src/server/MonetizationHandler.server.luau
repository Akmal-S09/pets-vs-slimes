-- MonetizationHandler.server.luau
-- Handles Robux dev-product purchases (ProcessReceipt) and
-- game-pass grants. Replace productId/passId = 0 values in
-- Config with real IDs from the Creator Dashboard before publishing.

local Players              = game:GetService("Players")
local MarketplaceService   = game:GetService("MarketplaceService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Shared               = ReplicatedStorage:WaitForChild("Shared")

local Config     = require(Shared:WaitForChild("Config"))
local Remotes    = require(Shared:WaitForChild("Remotes"))
local PlayerData = require(script.Parent.PlayerData)

-- ─── Build lookup tables ──────────────────────────────────────────────────────
local productById = {}  -- productId → product def
for _, p in ipairs(Config.ROBUX_PRODUCTS) do
	if p.productId ~= 0 then
		productById[p.productId] = p
	end
end

local passBypassId = {}  -- passId → pass def
for _, p in ipairs(Config.ROBUX_PASSES) do
	if p.passId ~= 0 then
		passBypassId[p.passId] = p
	end
end

-- ─── Apply a product reward ───────────────────────────────────────────────────
local function applyProductReward(player, productDef)
	local d = PlayerData.get(player)
	if productDef.reward == "coins" then
		-- Scales with the player's current coins (with a flat floor) so coin
		-- packs stay meaningful at every stage of the game.
		local granted = math.max(productDef.amount or 0,
			math.floor(d.coins * (productDef.pct or 0)))
		d.coins = d.coins + granted
		Remotes.UpdateCoins:FireClient(player, d.coins)
		Remotes.FloatText:FireClient(player, "+" .. Config.fmtNum(granted) .. " 💰")
		Remotes.NotifyPurchase:FireClient(player, "🎉  +" .. Config.fmtNum(granted) .. " Coins!", "coins")
	elseif productDef.reward == "luck_boost" then
		-- luck boost lasts (amount) minutes
		d.luckBoostEnd = tick() + productDef.amount * 60
		Remotes.FloatText:FireClient(player, "🍀 3× Luck for " .. productDef.amount .. "m!")
		Remotes.NotifyPurchase:FireClient(player, "🍀  3× Luck for " .. productDef.amount .. " minutes!", "luck")
	end
	-- Push full stats so client updates
	Remotes.UpdateStats:FireClient(player, PlayerData.snapshot(player))
end

-- ─── Apply a gamepass grant (idempotent — safe to call every join/purchase) ──
local function applyPass(player, passDef, announce)
	local d  = PlayerData.get(player)
	local id = passDef.id

	if id == "vip" then
		d.passVIP = true
	elseif id == "auto_pass" then
		d.passAutoRoll = true                 -- permanent auto-roll (the loop checks this)
		PlayerData.recomputeRollCooldown(d)   -- + the 0.5s faster-roll bonus
	elseif id == "mega_luck" then
		d.passMegaLuck = true
		PlayerData.recomputeLuck(d)
	elseif id == "big_slots" then
		d.passBigSlots = true
		PlayerData.recomputeMaxSlots(d)   -- deterministic; never doubles
	end

	if announce then
		Remotes.NotifyPurchase:FireClient(player, "⭐  " .. passDef.name .. " activated!", "pass")
	end
	Remotes.UpdateStats:FireClient(player, PlayerData.snapshot(player))
end

-- ─── ProcessReceipt (dev products) ───────────────────────────────────────────
-- Idempotency: Roblox may call this more than once for the same purchase, so we
-- remember granted PurchaseIds per player and never grant twice. (Session-only,
-- which matches this game's session-only economy. Move to a DataStore if/when
-- coins persist across sessions.)
local processedReceipts = {}   -- [PlayerId] = { [PurchaseId] = true }
Players.PlayerRemoving:Connect(function(p) processedReceipts[p.UserId] = nil end)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		-- Player left; retry on next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local seen = processedReceipts[info.PlayerId]
	if seen and seen[info.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted   -- already granted
	end

	local def = productById[info.ProductId]
	if not def then
		-- Not a product we know — don't silently consume the player's Robux.
		warn("[Monetization] Unknown ProductId " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = pcall(applyProductReward, player, def)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet   -- failed; retry later
	end

	processedReceipts[info.PlayerId] = seen or {}
	processedReceipts[info.PlayerId][info.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ─── Re-derive owned passes on join (authoritative — passes can't "run out") ─
-- We NEVER persist pass flags; ownership is re-checked from Roblox every join,
-- with retries so a transient API hiccup doesn't drop a pass for the session.
local function ownsPass(userId, passId)
	for _ = 1, 3 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		if ok then return owns end
		task.wait(2)
	end
	return nil   -- nil = couldn't determine (don't treat as "doesn't own")
end

local function checkPasses(player)
	PlayerData.waitForLoad(player)
	for _, passDef in ipairs(Config.ROBUX_PASSES) do
		if passDef.passId ~= 0 and ownsPass(player.UserId, passDef.passId) then
			applyPass(player, passDef, false)   -- silent on join
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	-- Apply as soon as data is loaded; doesn't need to wait for the character.
	task.spawn(checkPasses, player)
end)

-- ─── Instant grant the moment a pass is bought (no rejoin needed) ────────────
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	local def = passBypassId[gamePassId]
	if def then applyPass(player, def, true) end
end)

-- ─── Client requests a product/pass prompt ───────────────────────────────────
-- Client fires PromptProduct with (productType, id)
-- productType = "product" or "pass"
-- id = the id string from Config
Remotes.PromptProduct.OnServerEvent:Connect(function(player, productType, id)
	if productType == "product" then
		for _, def in ipairs(Config.ROBUX_PRODUCTS) do
			if def.id == id then
				if def.productId ~= 0 then
					pcall(function() MarketplaceService:PromptProductPurchase(player, def.productId) end)
				else
					Remotes.NotifyPurchase:FireClient(player, "🛠️  " .. def.name .. " — coming soon!", "info")
				end
				return
			end
		end
	elseif productType == "pass" then
		for _, def in ipairs(Config.ROBUX_PASSES) do
			if def.id == id then
				if def.passId ~= 0 then
					pcall(function() MarketplaceService:PromptGamePassPurchase(player, def.passId) end)
				else
					Remotes.NotifyPurchase:FireClient(player, "🛠️  " .. def.name .. " — coming soon!", "info")
				end
				return
			end
		end
	end
end)

-- ─── Startup audit: list any IDs still left at 0 so you know what to fill in ──
do
	local missing = {}
	for _, p in ipairs(Config.ROBUX_PRODUCTS) do
		if p.productId == 0 then missing[#missing+1] = "product '" .. p.id .. "'" end
	end
	for _, p in ipairs(Config.ROBUX_PASSES) do
		if p.passId == 0 then missing[#missing+1] = "pass '" .. p.id .. "'" end
	end
	if #missing == 0 then
		print("[MonetizationHandler] Ready — all Robux IDs configured. ✅")
	else
		warn("[MonetizationHandler] Ready, but these IDs are still 0 (set them in Config to go live): "
			.. table.concat(missing, ", "))
	end
end

