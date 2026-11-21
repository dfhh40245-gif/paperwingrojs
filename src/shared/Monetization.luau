--!nonstrict
-- Monetization: gamepass and developer-product catalogue.
--
-- `Id` values are placeholders (0). Replace them with the real asset ids from
-- the Creator Dashboard once the passes/products exist; anything with Id == 0
-- is treated as "not configured": the server ignores it and the client shows an
-- "unavailable" label instead of prompting a purchase that cannot succeed.
--
-- Perk aggregation is multiplicative for multipliers and additive for counts,
-- so passes stack predictably and never fight each other.

local Monetization = {}

Monetization.Gamepasses = {
	GoldenWings = {
		Id = 0,
		Name = "Golden Wings",
		Tagline = "The flagship pass.",
		Price = 399,
		Color = Color3.fromRGB(255, 205, 80),
		PerkLines = {
			"+25% coins and +10% damage",
			"+1 ally slot",
			"Unlocks the Golden Fold plane",
			"Golden name tag in the hangar",
		},
		Perks = {
			Vip = true,
			CoinMult = 1.25,
			DamageMult = 1.10,
			ExtraAllySlots = 1,
			UnlockPlanes = { "GoldenFold" },
		},
	},
	DoubleCoins = {
		Id = 0,
		Name = "Double Coins",
		Tagline = "Every coin, twice.",
		Price = 199,
		Color = Color3.fromRGB(255, 202, 76),
		PerkLines = { "x2 coins from every run", "Stacks with rebirth bonuses" },
		Perks = { CoinMult = 2 },
	},
	DoubleGems = {
		Id = 0,
		Name = "Double Gems",
		Tagline = "Rare currency, twice as often.",
		Price = 249,
		Color = Color3.fromRGB(69, 157, 221),
		PerkLines = { "x2 gems from bosses and drops" },
		Perks = { GemMult = 2 },
	},
	ExtraLife = {
		Id = 0,
		Name = "Extra Life",
		Tagline = "One more chance, every run.",
		Price = 299,
		Color = Color3.fromRGB(239, 83, 83),
		PerkLines = { "Revive once per run at 50% health", "No timer, no cooldown" },
		Perks = { Revives = 1 },
	},
	TripleShot = {
		Id = 0,
		Name = "Triple Shot",
		Tagline = "Three darts, every shot.",
		Price = 349,
		Color = Color3.fromRGB(85, 202, 126),
		PerkLines = { "+2 extra projectiles on every weapon" },
		Perks = { ExtraProjectiles = 2 },
	},
	MegaMagnet = {
		Id = 0,
		Name = "Mega Magnet",
		Tagline = "Coins come to you.",
		Price = 149,
		Color = Color3.fromRGB(176, 111, 225),
		PerkLines = { "Coins are collected from much further away" },
		Perks = { MagnetMult = 2.5, AutoCollect = true },
	},
	AllySlots = {
		Id = 0,
		Name = "Ally Squad",
		Tagline = "Two more friends.",
		Price = 179,
		Color = Color3.fromRGB(120, 190, 255),
		PerkLines = { "+2 ally slots (up to 5)" },
		Perks = { ExtraAllySlots = 2 },
	},
	LuckyEggs = {
		Id = 0,
		Name = "Lucky Eggs",
		Tagline = "Better odds on every hatch.",
		Price = 199,
		Color = Color3.fromRGB(255, 230, 140),
		PerkLines = { "Better pet odds from eggs", "+50% gem drops" },
		Perks = { LuckMult = 1.5, GemMult = 1.5 },
	},
	PrismLance = {
		Id = 0,
		Name = "Prism Lance",
		Tagline = "The piercing weapon.",
		Price = 449,
		Color = Color3.fromRGB(160, 240, 255),
		PerkLines = { "Unlocks the Prism Lance weapon", "Pierces up to 2 extra enemies" },
		Perks = { UnlockWeapons = { "PrismLance" } },
	},
}

-- Display order for the store tab.
Monetization.GamepassOrder = {
	"GoldenWings",
	"DoubleCoins",
	"DoubleGems",
	"ExtraLife",
	"TripleShot",
	"MegaMagnet",
	"AllySlots",
	"LuckyEggs",
	"PrismLance",
}

Monetization.Products = {
	Revive = {
		Id = 0,
		Name = "Revive",
		Description = "Get back up right where you fell.",
		Price = 49,
		Coins = 0,
		Gems = 0,
		Revive = true,
	},
	CoinsSmall = {
		Id = 0,
		Name = "Pocket Change",
		Description = "2,500 coins.",
		Price = 49,
		Coins = 2500,
	},
	CoinsLarge = {
		Id = 0,
		Name = "Coin Crate",
		Description = "15,000 coins.",
		Price = 199,
		Coins = 15000,
	},
	CoinsHuge = {
		Id = 0,
		Name = "Coin Vault",
		Description = "75,000 coins.",
		Price = 799,
		Coins = 75000,
	},
	GemsSmall = {
		Id = 0,
		Name = "Gem Pouch",
		Description = "100 gems.",
		Price = 99,
		Gems = 100,
	},
	GemsLarge = {
		Id = 0,
		Name = "Gem Chest",
		Description = "600 gems.",
		Price = 399,
		Gems = 600,
	},
}

Monetization.ProductOrder = { "Revive", "CoinsSmall", "CoinsLarge", "CoinsHuge", "GemsSmall", "GemsLarge" }

-- Empty perk bag. Every field is present so callers never need nil checks.
function Monetization.EmptyPerks()
	return {
		CoinMult = 1,
		GemMult = 1,
		DamageMult = 1,
		HealthMult = 1,
		SpeedMult = 1,
		MagnetMult = 1,
		LuckMult = 1,
		Revives = 0,
		ExtraAllySlots = 0,
		ExtraProjectiles = 0,
		AutoCollect = false,
		Vip = false,
		UnlockPlanes = {},
		UnlockWeapons = {},
	}
end

-- `owned` is a set of gamepass keys: { GoldenWings = true, ... }
function Monetization.Aggregate(owned)
	local perks = Monetization.EmptyPerks()
	for key, pass in pairs(Monetization.Gamepasses) do
		if owned[key] then
			local p = pass.Perks or {}
			perks.CoinMult *= p.CoinMult or 1
			perks.GemMult *= p.GemMult or 1
			perks.DamageMult *= p.DamageMult or 1
			perks.HealthMult *= p.HealthMult or 1
			perks.SpeedMult *= p.SpeedMult or 1
			perks.MagnetMult *= p.MagnetMult or 1
			perks.LuckMult *= p.LuckMult or 1
			perks.Revives += p.Revives or 0
			perks.ExtraAllySlots += p.ExtraAllySlots or 0
			perks.ExtraProjectiles += p.ExtraProjectiles or 0
			perks.AutoCollect = perks.AutoCollect or p.AutoCollect or false
			perks.Vip = perks.Vip or p.Vip or false
			for _, planeId in ipairs(p.UnlockPlanes or {}) do
				perks.UnlockPlanes[planeId] = true
			end
			for _, weaponId in ipairs(p.UnlockWeapons or {}) do
				perks.UnlockWeapons[weaponId] = true
			end
		end
	end
	return perks
end

function Monetization.GetGamepass(key: string)
	return Monetization.Gamepasses[key]
end

function Monetization.PassProductId(key: string)
	local pass = Monetization.Gamepasses[key]
	return pass and pass.Id or 0
end

function Monetization.ProductByAssetId(assetId: number)
	for key, product in pairs(Monetization.Products) do
		if product.Id ~= 0 and product.Id == assetId then
			return key, product
		end
	end
	return nil, nil
end

function Monetization.IsConfigured(id: number?): boolean
	return type(id) == "number" and id > 0
end

return Monetization
