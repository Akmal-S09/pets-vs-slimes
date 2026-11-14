-- Remotes.luau — all RemoteEvents for SlimeDice

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")

local Remotes = {}

if RunService:IsServer() then
	local function make(name)
		local e        = Instance.new("RemoteEvent")
		e.Name         = name
		e.Parent       = Shared
		return e
	end
	-- client → server
	Remotes.RequestRoll      = make("RequestRoll")
	Remotes.EquipCreature    = make("EquipCreature")
	Remotes.UnequipCreature  = make("UnequipCreature")
	Remotes.BuyUpgrade       = make("BuyUpgrade")
	Remotes.RequestRebirth   = make("RequestRebirth")
	Remotes.PromptProduct    = make("PromptProduct")    -- client asks server to prompt purchase
	Remotes.UnlockZone       = make("UnlockZone")       -- client → server: unlock zone by name
	Remotes.TeleportZone     = make("TeleportZone")     -- client → server: warp to furthest unlocked zone
	Remotes.SellCreature     = make("SellCreature")     -- client → server: sell by inventory index
	Remotes.AdminCmd         = make("AdminCmd")         -- client → server: admin panel command string
	Remotes.UpdateInventory  = make("UpdateInventory")  -- server → client: full inventory array
	Remotes.SetAutoSell      = make("SetAutoSell")      -- client → server: set auto-sell rarity threshold
	Remotes.ToggleAutoRoll   = make("ToggleAutoRoll")   -- client → server: flip auto-roll on/off
	Remotes.BuyAutoRoll      = make("BuyAutoRoll")      -- client → server: buy timed auto-roll with coins
	Remotes.EvolvePet        = make("EvolvePet")        -- client → server: petId to evolve (from inventory)
	-- Pet combat
	Remotes.PetAttack        = make("PetAttack")        -- server → all clients: spawn projectile visual
	Remotes.EnemyDamaged     = make("EnemyDamaged")     -- server → all clients: HP bar update
	Remotes.ComboKill        = make("ComboKill")        -- server → client: combo count for UI flash
	Remotes.PetStatus        = make("PetStatus")        -- server → client: slot → {hp,max,reviveIn}
	Remotes.EnemyAttack      = make("EnemyAttack")      -- server → client: slime hits a pet (enemyName, slot)
	-- daily / wheel
	Remotes.SpinWheel        = make("SpinWheel")       -- client → server
	Remotes.ClaimDaily       = make("ClaimDaily")      -- client → server
	Remotes.WheelResult      = make("WheelResult")     -- server → client: prizeIdx
	Remotes.DailyData        = make("DailyData")       -- server → client: streak, nextIn, prizes
	-- server → client
	Remotes.RollResult       = make("RollResult")
	Remotes.UpdateCoins      = make("UpdateCoins")
	Remotes.UpdateEquipped   = make("UpdateEquipped")
	Remotes.UpdateStats      = make("UpdateStats")
	Remotes.FloatText        = make("FloatText")
	Remotes.UpdateLeaderboard= make("UpdateLeaderboard")
	Remotes.NotifyPurchase   = make("NotifyPurchase")   -- server → client on successful buy
	Remotes.ZoneUnlocked     = make("ZoneUnlocked")     -- server → all clients when zone opens
	Remotes.ZonesReset       = make("ZonesReset")       -- server → all clients: all stage gates re-locked (rebirth)
	-- Trading
	Remotes.TradeInvite      = make("TradeInvite")       -- client → server: invite userId to trade
	Remotes.TradeRespond     = make("TradeRespond")      -- client → server: accept/decline an invite (bool)
	Remotes.TradeToggleItem  = make("TradeToggleItem")   -- client → server: add/remove inventory index from offer
	Remotes.TradeLock        = make("TradeLock")         -- client → server: toggle my ready/lock
	Remotes.TradeCancel      = make("TradeCancel")       -- client → server: leave/cancel trade
	Remotes.TradeState       = make("TradeState")        -- server → client: full trade state (or nil)
	Remotes.TradeInviteIn    = make("TradeInviteIn")     -- server → client: incoming invite {fromName, fromId}
	Remotes.TradePopup       = make("TradePopup")        -- server → client: notification string
else
	local function get(name)
		return Shared:WaitForChild(name)
	end
	Remotes.RequestRoll      = get("RequestRoll")
	Remotes.EquipCreature    = get("EquipCreature")
	Remotes.UnequipCreature  = get("UnequipCreature")
	Remotes.BuyUpgrade       = get("BuyUpgrade")
	Remotes.RequestRebirth   = get("RequestRebirth")
	Remotes.PromptProduct    = get("PromptProduct")
	Remotes.UnlockZone       = get("UnlockZone")
	Remotes.TeleportZone     = get("TeleportZone")
	Remotes.SellCreature     = get("SellCreature")
	Remotes.AdminCmd         = get("AdminCmd")
	Remotes.UpdateInventory  = get("UpdateInventory")
	Remotes.SetAutoSell      = get("SetAutoSell")
	Remotes.ToggleAutoRoll   = get("ToggleAutoRoll")
	Remotes.BuyAutoRoll      = get("BuyAutoRoll")
	Remotes.EvolvePet        = get("EvolvePet")
	Remotes.PetAttack        = get("PetAttack")
	Remotes.EnemyDamaged     = get("EnemyDamaged")
	Remotes.ComboKill        = get("ComboKill")
	Remotes.PetStatus        = get("PetStatus")
	Remotes.EnemyAttack      = get("EnemyAttack")
	Remotes.RollResult       = get("RollResult")
	Remotes.UpdateCoins      = get("UpdateCoins")
	Remotes.UpdateEquipped   = get("UpdateEquipped")
	Remotes.UpdateStats      = get("UpdateStats")
	Remotes.FloatText        = get("FloatText")
	Remotes.UpdateLeaderboard= get("UpdateLeaderboard")
	Remotes.NotifyPurchase   = get("NotifyPurchase")
	Remotes.ZoneUnlocked     = get("ZoneUnlocked")
	Remotes.ZonesReset       = get("ZonesReset")
	Remotes.TradeInvite      = get("TradeInvite")
	Remotes.TradeRespond     = get("TradeRespond")
	Remotes.TradeToggleItem  = get("TradeToggleItem")
	Remotes.TradeLock        = get("TradeLock")
	Remotes.TradeCancel      = get("TradeCancel")
	Remotes.TradeState       = get("TradeState")
	Remotes.TradeInviteIn    = get("TradeInviteIn")
	Remotes.TradePopup       = get("TradePopup")
	Remotes.SpinWheel        = get("SpinWheel")
	Remotes.ClaimDaily       = get("ClaimDaily")
	Remotes.WheelResult      = get("WheelResult")
	Remotes.DailyData        = get("DailyData")
end

return Remotes

