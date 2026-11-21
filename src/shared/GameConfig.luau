-- ============================================================================
--!nonstrict
-- GameConfig: every static number, table and tunable in Paper Wings.
--
-- This file is data only. Anything that decides whether a run is legal lives
-- on the server (GameService); anything cosmetic reads from here.
--
-- Naming note: `Mult` on shields is a *damage divisor* (higher = tankier).
-- `CoinMult` on planes/passes is a *payout multiplier*.

local GameConfig = {}

-- Distance / movement -------------------------------------------------------
GameConfig.MetersPerStud = 0.25 -- 4 studs == 1 m
GameConfig.Corridor = {
	HalfWidth = 36,
	MinHeight = 8, -- enemy/coin lower spawn band; aircraft can land below this
	MaxHeight = 44,
	GroundY = 0,
	PlaneGroundClearance = 1.6,
}

GameConfig.BaseSpeed = 56
GameConfig.BaseHealth = 100
GameConfig.BaseDamage = 10

-- Enemy scaling --------------------------------------------------------------
-- The design doc's "+8% per 100 m" is exponential: by 10 km it multiplies
-- health by ~2,200x, which makes every zone past the third impossible. These
-- curves keep the same early feel but stay solvable: health is ~20x at 10 km
-- and ~45x at 20 km, while damage grows far more slowly so runs stay survivable.
GameConfig.EnemyHealthScalePer100m = 0.08 -- kept for tooling/reference
GameConfig.EnemyDamageScalePer100m = 0.04

function GameConfig.EnemyHealthMult(distance: number): number
	local units = math.max(0, distance) / 1000
	-- Linear-in-kilometres. Player damage grows ~5x over 40 upgrade levels and
	-- weapons add 1-2.4x on top, so health must not outrun that: at 20 km this
	-- is 21x, which a well-upgraded player clears in ~2-4 s per enemy.
	return 1 + units
end

function GameConfig.EnemyDamageMult(distance: number): number
	local units = math.max(0, distance) / 2000
	return (1 + units) ^ 0.85
end

GameConfig.FireRange = 62
GameConfig.FireInterval = 0.35
GameConfig.CoinPickupRadius = 8

-- Server-authoritative reward rates, per metre of distance. Zone multipliers
-- (below) make deeper runs worth far more than farming the first zone.
GameConfig.CoinPerMeter = 0.9
GameConfig.GemPerMeter = 0.006
GameConfig.KillCoinFlat = 6

-- Combo ---------------------------------------------------------------------
-- Killing enemies in quick succession builds a payout multiplier. It decays
-- back to 1x when you stop killing, so it rewards aggression without being a
-- permanent free multiplier.
GameConfig.Combo = {
	Window = 2.6, -- seconds since the last kill before the chain resets
	BonusPerKill = 0.04, -- +4% coins per chain step
	MaxBonus = 1.0, -- capped at +100%
	MaxSteps = 25,
}

-- Boost (speed burst) -------------------------------------------------------
GameConfig.Boost = {
	ChargeMax = 100,
	ChargePerKill = 9,
	DrainPerSecond = 36,
	SpeedMult = 1.85,
	MinChargeToStart = 25,
}

-- Zones ---------------------------------------------------------------------
-- `Style` selects the scenery recipe in WorldBuilder. `Enemies` is the spawn
-- pool for that zone; `Elite` is the rare high-value variant pool.
GameConfig.Zones = {
	{
		Id = "PaperTown",
		CoinMult = 1,
		Name = "PAPER TOWN",
		Style = "town",
		Min = 0,
		Max = 1200,
		SkyTop = Color3.fromRGB(120, 190, 235),
		SkyBottom = Color3.fromRGB(205, 238, 250),
		Ambient = Color3.fromRGB(150, 170, 190),
		FogColor = Color3.fromRGB(205, 232, 245),
		FogEnd = 900,
		Ground = Color3.fromRGB(126, 190, 92),
		Path = Color3.fromRGB(233, 206, 150),
		Accent = Color3.fromRGB(255, 202, 76),
		Enemies = { "Crane", "Crane", "InkBat", "PaperManta" },
		Elite = { "StapleShooter" },
		Song = "town",
	},
	{
		Id = "NotebookCanyon",
		CoinMult = 1.4,
		Name = "NOTEBOOK CANYON",
		Style = "canyon",
		Min = 1200,
		Max = 3500,
		SkyTop = Color3.fromRGB(140, 190, 240),
		SkyBottom = Color3.fromRGB(220, 235, 250),
		Ambient = Color3.fromRGB(160, 175, 195),
		FogColor = Color3.fromRGB(210, 225, 240),
		FogEnd = 850,
		Ground = Color3.fromRGB(206, 214, 222),
		Path = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(90, 140, 220),
		Enemies = { "InkBat", "StapleShooter", "Crane", "PaperWasp", "PaperManta" },
		Elite = { "HolePunch" },
		Song = "canyon",
	},
	{
		Id = "InkOcean",
		CoinMult = 1.9,
		Name = "INK OCEAN",
		Style = "ocean",
		Min = 3500,
		Max = 7000,
		SkyTop = Color3.fromRGB(90, 70, 150),
		SkyBottom = Color3.fromRGB(170, 120, 190),
		Ambient = Color3.fromRGB(90, 70, 130),
		FogColor = Color3.fromRGB(70, 50, 120),
		FogEnd = 700,
		Ground = Color3.fromRGB(35, 30, 70),
		Path = Color3.fromRGB(40, 34, 80),
		Accent = Color3.fromRGB(176, 111, 225),
		Enemies = { "InkBlob", "EraserGolem", "InkBat", "GlueTrap", "InkMine" },
		Elite = { "MarkerSniper" },
		Song = "ocean",
	},
	{
		Id = "ScissorStorm",
		CoinMult = 2.6,
		Name = "SCISSOR STORM",
		Style = "storm",
		Min = 7000,
		Max = 11000,
		SkyTop = Color3.fromRGB(60, 60, 90),
		SkyBottom = Color3.fromRGB(120, 110, 130),
		Ambient = Color3.fromRGB(80, 75, 90),
		FogColor = Color3.fromRGB(55, 52, 70),
		FogEnd = 650,
		Ground = Color3.fromRGB(55, 48, 60),
		Path = Color3.fromRGB(70, 60, 70),
		Accent = Color3.fromRGB(190, 190, 200),
		Enemies = { "PaperWasp", "StapleShooter", "EraserGolem", "InkBlob", "MarkerSniper", "PaperManta", "MirrorSentinel" },
		Elite = { "HolePunch", "EraserGolem" },
		Song = "storm",
	},
	{
		Id = "CloudForge",
		CoinMult = 3.4,
		Name = "CLOUD FORGE",
		Style = "clouds",
		Min = 11000,
		Max = 16000,
		SkyTop = Color3.fromRGB(255, 190, 120),
		SkyBottom = Color3.fromRGB(255, 236, 200),
		Ambient = Color3.fromRGB(230, 205, 180),
		FogColor = Color3.fromRGB(255, 232, 205),
		FogEnd = 1000,
		Ground = Color3.fromRGB(250, 240, 226),
		Path = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(255, 140, 90),
		Enemies = { "PaperWasp", "GlueTrap", "MarkerSniper", "StapleShooter", "InkMine" },
		Elite = { "EraserGolem", "HolePunch" },
		Song = "clouds",
	},
	{
		Id = "TheGreatFold",
		CoinMult = 4.5,
		Name = "THE GREAT FOLD",
		Style = "fold",
		Min = 16000,
		Max = math.huge,
		SkyTop = Color3.fromRGB(20, 20, 34),
		SkyBottom = Color3.fromRGB(60, 55, 90),
		Ambient = Color3.fromRGB(70, 66, 95),
		FogColor = Color3.fromRGB(30, 28, 46),
		FogEnd = 800,
		Ground = Color3.fromRGB(28, 26, 42),
		Path = Color3.fromRGB(255, 214, 120),
		Accent = Color3.fromRGB(255, 202, 76),
		Enemies = { "MarkerSniper", "HolePunch", "EraserGolem", "PaperWasp", "InkBlob", "MirrorSentinel" },
		Elite = { "EraserGolem", "MarkerSniper" },
		Song = "fold",
	},
}

-- Enemies -------------------------------------------------------------------
-- Behavior is one of: straight | zigzag | ranged | split | tank | charger | mine | phase
GameConfig.Enemies = {
	Crane = {
		Name = "Paper Crane",
		Behavior = "straight",
		Health = 20,
		Speed = 26,
		Damage = 10,
		Coins = 5,
		Gems = 0,
		Color = Color3.fromRGB(246, 246, 250),
		Accent = Color3.fromRGB(198, 210, 224),
		Scale = 1.15,
	},
	InkBat = {
		Name = "Ink Bat",
		Behavior = "zigzag",
		Health = 16,
		Speed = 34,
		Damage = 8,
		Coins = 6,
		Gems = 0,
		Color = Color3.fromRGB(44, 40, 66),
		Accent = Color3.fromRGB(126, 110, 190),
		Scale = 1.3,
	},
	StapleShooter = {
		Name = "Staple Shooter",
		Behavior = "ranged",
		Health = 48,
		Speed = 20,
		Damage = 12,
		Coins = 12,
		Gems = 1,
		Color = Color3.fromRGB(176, 176, 188),
		Accent = Color3.fromRGB(226, 226, 236),
		Scale = 1.2,
		FireInterval = 2.4,
		ProjectileSpeed = 34,
	},
	InkBlob = {
		Name = "Ink Blob",
		Behavior = "split",
		Health = 42,
		Speed = 14,
		Damage = 10,
		Coins = 12,
		Gems = 1,
		Color = Color3.fromRGB(52, 46, 100),
		Accent = Color3.fromRGB(140, 116, 226),
		Scale = 1.15,
	},
	EraserGolem = {
		Name = "Eraser Golem",
		Behavior = "tank",
		Health = 170,
		Speed = 9,
		Damage = 22,
		Coins = 30,
		Gems = 3,
		Color = Color3.fromRGB(232, 138, 164),
		Accent = Color3.fromRGB(255, 208, 220),
		Scale = 2.2,
	},
	PaperWasp = {
		Name = "Paper Wasp",
		Behavior = "zigzag",
		Health = 26,
		Speed = 46,
		Damage = 9,
		Coins = 8,
		Gems = 0,
		Color = Color3.fromRGB(255, 214, 90),
		Accent = Color3.fromRGB(60, 52, 40),
		Scale = 1.0,
	},
	GlueTrap = {
		Name = "Glue Trap",
		Behavior = "straight",
		Health = 90,
		Speed = 4,
		Damage = 26,
		Coins = 18,
		Gems = 1,
		Color = Color3.fromRGB(250, 236, 180),
		Accent = Color3.fromRGB(214, 190, 110),
		Scale = 1.4,
	},
	MarkerSniper = {
		Name = "Marker Sniper",
		Behavior = "ranged",
		Health = 60,
		Speed = 12,
		Damage = 16,
		Coins = 16,
		Gems = 2,
		Color = Color3.fromRGB(90, 90, 110),
		Accent = Color3.fromRGB(255, 120, 120),
		Scale = 1.3,
		FireInterval = 3.2,
		ProjectileSpeed = 46,
	},
	HolePunch = {
		Name = "Hole Punch",
		Behavior = "tank",
		Health = 120,
		Speed = 16,
		Damage = 18,
		Coins = 22,
		Gems = 2,
		Color = Color3.fromRGB(120, 130, 150),
		Accent = Color3.fromRGB(80, 88, 104),
		Scale = 1.62,
	},
	PaperManta = {
		Name = "Paper Manta",
		Behavior = "charger",
		Health = 58,
		Speed = 31,
		Damage = 16,
		Coins = 20,
		Gems = 1,
		Color = Color3.fromRGB(75, 170, 205),
		Accent = Color3.fromRGB(180, 245, 255),
		Scale = 1.55,
		AbilityInterval = 3.4,
	},
	InkMine = {
		Name = "Ink Mine",
		Behavior = "mine",
		Health = 82,
		Speed = 0,
		Damage = 26,
		Coins = 24,
		Gems = 2,
		Color = Color3.fromRGB(62, 45, 108),
		Accent = Color3.fromRGB(255, 92, 128),
		Scale = 1.45,
		FireInterval = 2.8,
		ProjectileSpeed = 34,
		ProjectileDamage = 12,
	},
	MirrorSentinel = {
		Name = "Mirror Sentinel",
		Behavior = "phase",
		Health = 76,
		Speed = 22,
		Damage = 15,
		Coins = 28,
		Gems = 2,
		Color = Color3.fromRGB(120, 190, 210),
		Accent = Color3.fromRGB(220, 250, 255),
		Scale = 1.5,
		AbilityInterval = 2.2,
		FireInterval = 2.5,
		ProjectileSpeed = 38,
		ProjectileDamage = 13,
	},
}

-- Bosses: one per zone, spawned once the player passes `Distance` inside that
-- zone. `Model` selects the build recipe; `ProjectileDamage` overrides the
-- default per-boss shot damage.
GameConfig.Bosses = {
	{
		Zone = "PaperTown",
		Distance = 1100,
		Key = "GiantScissors",
		Model = "GiantScissors",
		Name = "GIANT SCISSORS",
		Health = 600,
		Damage = 25,
		ProjectileDamage = 12,
		Coins = 250,
		Gems = 15,
		Scale = 3.4,
	},
	{
		Zone = "NotebookCanyon",
		Distance = 3300,
		Key = "PencilTitan",
		Model = "PencilTitan",
		Name = "PENCIL TITAN",
		Health = 1000,
		Damage = 35,
		ProjectileDamage = 18,
		Coins = 600,
		Gems = 30,
		Scale = 4,
	},
	{
		Zone = "InkOcean",
		Distance = 6800,
		Key = "InkLeviathan",
		Model = "InkLeviathan",
		Name = "INK LEVIATHAN",
		Health = 1400,
		Damage = 45,
		ProjectileDamage = 22,
		Coins = 1200,
		Gems = 60,
		Scale = 4.5,
	},
	{
		Zone = "ScissorStorm",
		Distance = 10500,
		Key = "StormShears",
		Model = "StormShears",
		Name = "STORM SHEARS",
		Health = 1900,
		Damage = 60,
		ProjectileDamage = 28,
		Coins = 2500,
		Gems = 100,
		Scale = 5,
	},
	{
		Zone = "CloudForge",
		Distance = 15500,
		Key = "CloudColossus",
		Model = "CloudColossus",
		Name = "CLOUD COLOSSUS",
		Health = 2400,
		Damage = 70,
		ProjectileDamage = 32,
		Coins = 4000,
		Gems = 150,
		Scale = 5.5,
	},
	{
		Zone = "TheGreatFold",
		Distance = 20000,
		Key = "GreatFold",
		Model = "GreatFold",
		Name = "THE GREAT FOLD",
		Health = 3000,
		Damage = 85,
		ProjectileDamage = 38,
		Coins = 7000,
		Gems = 250,
		Scale = 6,
	},
}

-- Hangars -------------------------------------------------------------------
-- Cosmetic homes. Each one has its own palette, featured egg and decorated
-- prop set; the equipped hangar is saved per player.
GameConfig.Hangars = {
	Cardboard = {
		Name = "CARDBOARD HANGAR",
		Tagline = "HOME OF EVERY PAPER PILOT",
		Floor = Color3.fromRGB(176, 136, 92),
		Wall = Color3.fromRGB(204, 166, 116),
		Trim = Color3.fromRGB(134, 98, 62),
		Accent = Color3.fromRGB(255, 202, 76),
		Sky = Color3.fromRGB(186, 222, 238),
		Egg = "Common",
		Zone = "Paper Town",
	},
	Ember = {
		Name = "EMBER HANGAR",
		Tagline = "WHERE PAPER LEARNS TO BURN",
		Floor = Color3.fromRGB(62, 42, 44),
		Wall = Color3.fromRGB(112, 58, 48),
		Trim = Color3.fromRGB(40, 28, 32),
		Accent = Color3.fromRGB(255, 122, 52),
		Sky = Color3.fromRGB(255, 168, 110),
		Egg = "Rare",
		Zone = "Scissor Storm",
	},
	Flash = {
		Name = "FLASH HANGAR",
		Tagline = "FAST PLANES, BRIGHT LIGHTS",
		Floor = Color3.fromRGB(62, 74, 94),
		Wall = Color3.fromRGB(104, 132, 172),
		Trim = Color3.fromRGB(38, 48, 68),
		Accent = Color3.fromRGB(255, 240, 110),
		Sky = Color3.fromRGB(146, 210, 255),
		Egg = "Rare",
		Zone = "Cloud Forge",
	},
	Tide = {
		Name = "TIDE HANGAR",
		Tagline = "A HARBOR FOR WINGED THINGS",
		Floor = Color3.fromRGB(40, 92, 112),
		Wall = Color3.fromRGB(78, 148, 168),
		Trim = Color3.fromRGB(24, 58, 76),
		Accent = Color3.fromRGB(120, 244, 226),
		Sky = Color3.fromRGB(166, 232, 244),
		Egg = "Legendary",
		Zone = "Ink Ocean",
	},
	Void = {
		Name = "VOID HANGAR",
		Tagline = "PARKED BETWEEN THE STARS",
		Floor = Color3.fromRGB(34, 28, 56),
		Wall = Color3.fromRGB(66, 52, 100),
		Trim = Color3.fromRGB(20, 16, 34),
		Accent = Color3.fromRGB(180, 126, 255),
		Sky = Color3.fromRGB(88, 64, 136),
		Egg = "Mythic",
		Zone = "The Great Fold",
	},
	Umbra = {
		Name = "UMBRA HANGAR",
		Tagline = "THE QUIET HOME OF SHADOWS",
		Floor = Color3.fromRGB(30, 30, 38),
		Wall = Color3.fromRGB(58, 58, 70),
		Trim = Color3.fromRGB(16, 16, 22),
		Accent = Color3.fromRGB(255, 84, 118),
		Sky = Color3.fromRGB(54, 46, 66),
		Egg = "Legendary",
		Zone = "Notebook Canyon",
	},
}
GameConfig.HangarOrder = { "Cardboard", "Ember", "Flash", "Tide", "Void", "Umbra" }

-- Upgrades ------------------------------------------------------------------
-- cost(level) = BaseCost * Growth ^ (level - 1)
GameConfig.Upgrades = {
	Damage = { Name = "Damage", Desc = "More damage per shot", BaseCost = 100, Growth = 1.22, PerLevel = 0.12, Max = math.huge },
	Health = { Name = "Health", Desc = "More max health", BaseCost = 150, Growth = 1.24, PerLevel = 0.10, Max = math.huge },
	Speed = { Name = "Speed", Desc = "Faster flight", BaseCost = 200, Growth = 1.28, PerLevel = 0.03, Max = 0.60 },
	Magnet = { Name = "Magnet", Desc = "Bigger coin pickup range", BaseCost = 250, Growth = 1.30, PerLevel = 0.08, Max = 2.50 },
	Luck = { Name = "Luck", Desc = "Better gem and egg drops", BaseCost = 300, Growth = 1.35, PerLevel = 0.05, Max = 1.00 },
	FireRate = { Name = "Fire Rate", Desc = "Shoot more frequently while holding fire", BaseCost = 140, Growth = 1.28, PerLevel = 0.08, Max = 2.40 },
}
GameConfig.UpgradeOrder = { "Damage", "Health", "Speed", "Magnet", "Luck", "FireRate" }

-- Prestige -------------------------------------------------------------------
-- Permanent, gem-priced boosts. Unlike upgrades these survive rebirth, so they
-- are the long-term sink for gems once the collection is filled.
GameConfig.Prestige = {
	HeadStart = {
		Name = "Head Start",
		Desc = "+1 starting level in every upgrade",
		BaseCost = 50,
		Growth = 1.6,
		Max = 5,
	},
	Coins = {
		Name = "Coin Training",
		Desc = "+5% coins from every flight",
		BaseCost = 80,
		Growth = 1.5,
		Max = 10,
	},
	Armor = {
		Name = "Armor Plating",
		Desc = "+5% max health",
		BaseCost = 80,
		Growth = 1.5,
		Max = 10,
	},
	Gems = {
		Name = "Salvage",
		Desc = "+5% gems from every flight",
		BaseCost = 100,
		Growth = 1.6,
		Max = 10,
	},
}
GameConfig.PrestigeOrder = { "HeadStart", "Coins", "Armor", "Gems" }

function GameConfig.PrestigeCost(kind: string, rank: number): number
	local entry = GameConfig.Prestige[kind]
	if not entry or rank >= entry.Max then
		return math.huge
	end
	return math.floor(entry.BaseCost * entry.Growth ^ math.max(0, rank) + 0.5)
end

-- Planes --------------------------------------------------------------------
GameConfig.Planes = {
	Classic = {
		Name = "Classic Folded",
		SpeedMult = 1.0,
		HealthMult = 1.0,
		DamageMult = 1.0,
		CoinMult = 1.0,
		Cost = 0,
		UnlockLevel = 0,
		Color = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(180, 190, 205),
		Desc = "Balanced in every way.",
	},
	Glider = {
		Name = "Lightweight Glider",
		SpeedMult = 1.35,
		HealthMult = 0.7,
		DamageMult = 1.0,
		CoinMult = 1.0,
		Cost = 40,
		UnlockLevel = 10,
		Color = Color3.fromRGB(255, 205, 90),
		Accent = Color3.fromRGB(255, 240, 160),
		Desc = "Fast and fragile.",
	},
	Bomber = {
		Name = "Thick Cardboard Bomber",
		SpeedMult = 0.85,
		HealthMult = 1.6,
		DamageMult = 1.15,
		CoinMult = 1.05,
		Cost = 60,
		UnlockLevel = 12,
		Color = Color3.fromRGB(150, 105, 70),
		Accent = Color3.fromRGB(190, 140, 95),
		Desc = "Slow, heavy, hard to kill.",
	},
	OrigamiCrane = {
		Name = "Elegant Origami Crane",
		SpeedMult = 1.05,
		HealthMult = 0.85,
		DamageMult = 1.6,
		CoinMult = 1.0,
		Cost = 120,
		UnlockLevel = 15,
		Color = Color3.fromRGB(220, 120, 200),
		Accent = Color3.fromRGB(255, 200, 245),
		Desc = "A glass cannon with wings.",
	},
	Jetstream = {
		Name = "Jetstream Interceptor",
		SpeedMult = 1.5,
		HealthMult = 0.8,
		DamageMult = 1.2,
		CoinMult = 1.1,
		Cost = 250,
		UnlockLevel = 20,
		Color = Color3.fromRGB(90, 190, 245),
		Accent = Color3.fromRGB(230, 248, 255),
		Desc = "Built for distance records.",
	},
	GoldenFold = {
		Name = "Golden Fold",
		SpeedMult = 1.35,
		HealthMult = 1.35,
		DamageMult = 1.35,
		CoinMult = 1.25,
		Cost = 0,
		UnlockLevel = 0,
		RequiresPass = "GoldenWings",
		Color = Color3.fromRGB(255, 205, 80),
		Accent = Color3.fromRGB(255, 246, 200),
		Desc = "Gamepass exclusive. Rewards every run.",
	},
}

-- Weapons -------------------------------------------------------------------
GameConfig.Weapons = {
	Dart = {
		Name = "Paper Dart Shooter",
		DamageMult = 1.0,
		FireInterval = 0.35,
		Projectiles = 1,
		Spread = 0,
		Cost = 0,
		Color = Color3.fromRGB(255, 255, 255),
		Desc = "Single shot, reliable.",
	},
	StapleBurst = {
		Name = "Staple Burst",
		DamageMult = 0.7,
		FireInterval = 0.5,
		Projectiles = 3,
		Spread = 6,
		Cost = 90,
		Color = Color3.fromRGB(200, 200, 215),
		Desc = "Three staples per shot.",
	},
	InkSpray = {
		Name = "Ink Spray",
		DamageMult = 1.8,
		FireInterval = 0.45,
		Projectiles = 1,
		Spread = 0,
		RangeMult = 0.55,
		Cost = 140,
		Color = Color3.fromRGB(70, 60, 130),
		Desc = "Short range, huge damage.",
	},
	Boomerang = {
		Name = "Origami Boomerang",
		DamageMult = 1.4,
		FireInterval = 0.8,
		Projectiles = 1,
		Spread = 0,
		HitsTwice = true,
		Cost = 220,
		Color = Color3.fromRGB(240, 170, 90),
		Desc = "Hits twice per throw.",
	},
	PrismLance = {
		Name = "Prism Lance",
		DamageMult = 2.4,
		FireInterval = 0.3,
		Projectiles = 1,
		Spread = 0,
		Pierce = 2,
		Cost = 0,
		RequiresPass = "PrismLance",
		Color = Color3.fromRGB(160, 240, 255),
		Desc = "Gamepass exclusive. Pierces enemies.",
	},
}

-- Allies --------------------------------------------------------------------
GameConfig.Allies = {
	Bird = {
		Name = "Origami Bird",
		Damage = 6,
		FireInterval = 0.7,
		Cost = 60,
		Color = Color3.fromRGB(120, 190, 255),
		Desc = "Small, fast, chirpy.",
	},
	Wingman = {
		Name = "Wingman Plane",
		Damage = 9,
		FireInterval = 0.6,
		Cost = 120,
		Color = Color3.fromRGB(255, 235, 140),
		Desc = "A tiny plane with a tiny gun.",
	},
	InkSpirit = {
		Name = "Ink Spirit",
		Damage = 22,
		FireInterval = 1.6,
		Splash = 14,
		Cost = 260,
		Color = Color3.fromRGB(90, 70, 160),
		Desc = "Splashes groups of enemies.",
	},
	Dragon = {
		Name = "Pocket Dragon",
		Damage = 40,
		FireInterval = 1.3,
		Splash = 18,
		Cost = 420,
		Color = Color3.fromRGB(230, 90, 70),
		Desc = "Breathes folded fire.",
	},
	PaperWolf = {
		Name = "Paper Wolf",
		Damage = 15,
		FireInterval = 0.35,
		Cost = 320,
		Color = Color3.fromRGB(200, 205, 220),
		Desc = "Very fast attacks.",
	},
	StarMoth = {
		Name = "Star Moth",
		Damage = 55,
		FireInterval = 2.0,
		Splash = 26,
		Cost = 700,
		Color = Color3.fromRGB(255, 230, 140),
		Desc = "Slow but devastating blasts.",
	},
}

GameConfig.MaxAllies = 3
GameConfig.MaxAllySlots = 5

GameConfig.Shields = {
	None = { Name = "No Shield", Mult = 1.0, Cost = 0, Desc = "Nothing between you and the ink." },
	Paper = { Name = "Paper Shield", Mult = 1.15, Cost = 80, Desc = "Takes 13% less damage." },
	Cardboard = { Name = "Cardboard Shield", Mult = 1.35, Cost = 180, Desc = "Takes 26% less damage." },
	Metal = { Name = "Metal Shield", Mult = 1.6, Cost = 320, Desc = "Takes 38% less damage." },
}

GameConfig.Characters = {
	Pilot = { Name = "Pilot", Color = Color3.fromRGB(40, 90, 200) },
	Explorer = { Name = "Explorer", Color = Color3.fromRGB(90, 160, 120) },
	Ace = { Name = "Ace", Color = Color3.fromRGB(200, 60, 60) },
}

GameConfig.Eggs = {
	Common = { Name = "Common Egg", Cost = 50, Pets = { "Bird", "Wingman" }, Color = Color3.fromRGB(200, 200, 200) },
	Rare = { Name = "Rare Egg", Cost = 150, Pets = { "InkSpirit", "PaperWolf" }, Color = Color3.fromRGB(90, 160, 240) },
	Legendary = { Name = "Legendary Egg", Cost = 400, Pets = { "Dragon" }, Color = Color3.fromRGB(255, 205, 70) },
	Mythic = { Name = "Mythic Egg", Cost = 1200, Pets = { "StarMoth" }, Color = Color3.fromRGB(230, 120, 255) },
}
GameConfig.Pets = GameConfig.Allies
GameConfig.MaxPets = GameConfig.MaxAllies

-- Rebirth -------------------------------------------------------------------
GameConfig.Rebirth = {
	RequiredLevel = 25,
	AltBossCount = 2,
	CoinBonus = 0.25,
	DamageBonus = 0.10,
	HealthBonus = 0.05,
}

-- Daily rewards -------------------------------------------------------------
-- Streak is capped at the last entry and stays there.
GameConfig.DailyRewards = {
	{ Coins = 250, Gems = 0 },
	{ Coins = 500, Gems = 1 },
	{ Coins = 900, Gems = 2 },
	{ Coins = 1400, Gems = 3 },
	{ Coins = 2000, Gems = 5 },
	{ Coins = 3000, Gems = 8 },
	{ Coins = 5000, Gems = 15 },
}

-- Helpers -------------------------------------------------------------------
function GameConfig.GetZoneForDistance(distance: number)
	for _, zone in ipairs(GameConfig.Zones) do
		if distance >= zone.Min and distance < zone.Max then
			return zone
		end
	end
	return GameConfig.Zones[#GameConfig.Zones]
end

function GameConfig.GetZoneIndex(distance: number): number
	for i, zone in ipairs(GameConfig.Zones) do
		if distance >= zone.Min and distance < zone.Max then
			return i
		end
	end
	return #GameConfig.Zones
end

function GameConfig.GetZoneById(id: string)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.Id == id then
			return zone
		end
	end
	return nil
end

function GameConfig.GetBossForZone(zoneId: string)
	for _, boss in ipairs(GameConfig.Bosses) do
		if boss.Zone == zoneId then
			return boss
		end
	end
	return nil
end

-- Live-ops events ------------------------------------------------------------
-- Day-of-week bonuses give a reason to log in on a specific day. `Days` uses
-- os.date's wday: 1 = Sunday ... 7 = Saturday, in UTC.
GameConfig.Events = {
	{
		Id = "WeekendRush",
		Name = "WEEKEND RUSH",
		Desc = "+50% coins from every flight",
		CoinMult = 1.5,
		Days = { 1, 7 },
	},
	{
		Id = "MidweekGems",
		Name = "MIDWEEK GEMS",
		Desc = "+50% gems from every flight",
		GemMult = 1.5,
		Days = { 4 },
	},
}

function GameConfig.GetActiveEvent(timestamp: number?)
	local ok, date = pcall(function()
		return os.date("!*t", timestamp or os.time())
	end)
	if not ok or type(date) ~= "table" then
		return nil
	end
	for _, event in ipairs(GameConfig.Events) do
		for _, day in ipairs(event.Days) do
			if day == date.wday then
				return event
			end
		end
	end
	return nil
end

function GameConfig.UpgradeCost(kind: string, level: number): number
	local u = GameConfig.Upgrades[kind]
	if not u then
		return math.huge
	end
	return math.floor(u.BaseCost * (u.Growth ^ math.max(0, level - 1)) + 0.5)
end

function GameConfig.PlaneStats(planeId: string, upgradeLevels: { [string]: number })
	local plane = GameConfig.Planes[planeId] or GameConfig.Planes.Classic
	local dmgLevel = math.max(1, upgradeLevels.Damage or 1)
	local hpLevel = math.max(1, upgradeLevels.Health or 1)
	local spLevel = math.max(1, upgradeLevels.Speed or 1)
	local magLevel = math.max(1, upgradeLevels.Magnet or 1)
	local luckLevel = math.max(1, upgradeLevels.Luck or 1)
	local fireRateLevel = math.max(1, upgradeLevels.FireRate or 1)

	local dmgMult = 1 + (dmgLevel - 1) * GameConfig.Upgrades.Damage.PerLevel
	local hpMult = 1 + (hpLevel - 1) * GameConfig.Upgrades.Health.PerLevel
	local spMult = 1 + (spLevel - 1) * GameConfig.Upgrades.Speed.PerLevel
	local magMult = 1 + (magLevel - 1) * GameConfig.Upgrades.Magnet.PerLevel
	local luckMult = 1 + (luckLevel - 1) * GameConfig.Upgrades.Luck.PerLevel
	local fireRateMult = 1 + (fireRateLevel - 1) * GameConfig.Upgrades.FireRate.PerLevel
	fireRateMult = math.min(fireRateMult, 1 + GameConfig.Upgrades.FireRate.Max)

	return {
		Damage = GameConfig.BaseDamage * plane.DamageMult * dmgMult,
		MaxHealth = GameConfig.BaseHealth * plane.HealthMult * hpMult,
		Speed = GameConfig.BaseSpeed * plane.SpeedMult * math.min(spMult, 1 + GameConfig.Upgrades.Speed.Max),
		CoinMult = plane.CoinMult or 1,
		MagnetRadius = GameConfig.CoinPickupRadius * math.min(magMult, 1 + GameConfig.Upgrades.Magnet.Max),
		Luck = math.min(luckMult, 1 + GameConfig.Upgrades.Luck.Max),
		FireRateMultiplier = fireRateMult,
	}
end

return GameConfig
