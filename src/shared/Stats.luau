-- ============================================================================
--!nonstrict
-- Stats: shared derivation of a player's effective combat numbers.
-- Used by the server (for reward math) and the client (for the HUD), so both
-- sides always agree on what the player's loadout is worth.

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))

local Stats = {}

function Stats.Compute(data)
	local upgrades = data.Upgrades or {}
	local levels = {
		Damage = math.max(1, math.floor(tonumber(upgrades.Damage) or 1)),
		Health = math.max(1, math.floor(tonumber(upgrades.Health) or 1)),
		Speed = math.max(1, math.floor(tonumber(upgrades.Speed) or 1)),
		Magnet = math.max(1, math.floor(tonumber(upgrades.Magnet) or 1)),
		Luck = math.max(1, math.floor(tonumber(upgrades.Luck) or 1)),
		FireRate = math.max(1, math.floor(tonumber(upgrades.FireRate) or 1)),
	}

	local planeId = data.EquippedPlane or "Classic"
	if not GameConfig.Planes[planeId] then
		planeId = "Classic"
	end

	-- Prestige head start raises every upgrade level before plane multipliers.
	local prestige = data.Prestige or {}
	local headStart = math.max(0, math.floor(tonumber(prestige.HeadStart) or 0))
	if headStart > 0 then
		for kind in pairs(levels) do
			levels[kind] += headStart
		end
	end

	local base = GameConfig.PlaneStats(planeId, levels)
	local rebirths = math.max(0, math.floor(tonumber(data.Rebirths) or 0))
	local perks = data.Perks or Monetization.EmptyPerks()

	-- Rebirth is additive-then-multiplicative so its value is legible.
	base.Damage *= (1 + GameConfig.Rebirth.DamageBonus) ^ rebirths
	base.MaxHealth *= (1 + GameConfig.Rebirth.HealthBonus) ^ rebirths
	base.CoinMult *= (1 + GameConfig.Rebirth.CoinBonus) ^ rebirths

	-- Gamepass/gamepass-like perks.
	base.Damage *= perks.DamageMult or 1
	base.MaxHealth *= perks.HealthMult or 1
	base.Speed *= perks.SpeedMult or 1
	base.CoinMult *= perks.CoinMult or 1
	base.GemMult = (perks.GemMult or 1) * (1 + 0.10 * rebirths)
	base.MagnetRadius *= perks.MagnetMult or 1
	base.Luck *= perks.LuckMult or 1

	-- Crafted prestige ranks (permanent, survive rebirth).
	base.CoinMult *= 1 + 0.05 * math.max(0, math.floor(tonumber(prestige.Coins) or 0))
	base.MaxHealth *= 1 + 0.05 * math.max(0, math.floor(tonumber(prestige.Armor) or 0))
	base.GemMult *= 1 + 0.05 * math.max(0, math.floor(tonumber(prestige.Gems) or 0))
	base.PrestigeHeadStart = headStart
	base.ExtraProjectiles = perks.ExtraProjectiles or 0
	base.Revives = perks.Revives or 0
	base.AutoCollect = perks.AutoCollect or false
	base.Vip = perks.Vip or false
	base.ExtraAllySlots = perks.ExtraAllySlots or 0

	base.Rebirths = rebirths
	base.PlaneId = planeId
	base.WeaponId = data.EquippedWeapon or "Dart"
	base.ShieldId = data.EquippedShield or "None"
	base.Allies = data.Allies or {}
	base.Pets = data.Allies or {}
	base.Level = 1 + math.floor((tonumber(data.TotalDistance) or 0) / 150) + rebirths * 4
	base.UpgradeLevels = levels

	return base
end

return Stats
