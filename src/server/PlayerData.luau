--!nonstrict
-- PlayerData: default schema, derived values, validation and the client snapshot.
--
-- Every value that crosses the network is produced by `PlayerData.Snapshot`, so
-- the client always receives a complete picture and never has to merge partial
-- updates (a partial payload used to blank out `UnlockedPlanes` and friends).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Quests = require(Shared:WaitForChild("Quests"))
local Stats = require(Shared:WaitForChild("Stats"))

local PlayerData = {}

local SAVE_VERSION = 2

function PlayerData.Default()
	return {
		Version = SAVE_VERSION,
		Coins = 0,
		Gems = 0,
		Upgrades = { Damage = 1, Health = 1, Speed = 1, Magnet = 1, Luck = 1 },
		UnlockedPlanes = { Classic = true },
		UnlockedWeapons = { Dart = true },
		UnlockedAllies = {},
		UnlockedShields = { None = true },
		Eggs = {},
		EquippedPlane = "Classic",
		EquippedCharacter = "Pilot",
		EquippedHangar = "Cardboard",
		EquippedShield = "None",
		EquippedWeapon = "Dart",
		Allies = {},
		Rebirths = 0,
		Prestige = { HeadStart = 0, Coins = 0, Armor = 0, Gems = 0 },
		BestDistance = 0,
		BestKills = 0,
		TotalKills = 0,
		TotalDistance = 0,
		TotalCoinsEarned = 0,
		TotalGemsEarned = 0,
		Runs = 0,
		BossesBeaten = {},
		DailyStreak = 0,
		LastDailyDay = 0,
		ReviveTokens = 0,
		Quests = { Day = 0, List = {} },
		Achievements = {},
		CodesRedeemed = {},
		CreatedAt = os.time(),
		LastSeen = os.time(),
	}
end

function PlayerData.UpgradeLevel(data, kind: string): number
	local v = data.Upgrades and data.Upgrades[kind]
	if type(v) ~= "number" then
		return 1
	end
	return math.max(1, math.floor(v))
end

function PlayerData.GetLevel(data): number
	local totalDistance = tonumber(data.TotalDistance) or 0
	local rebirths = tonumber(data.Rebirths) or 0
	return 1 + math.floor(totalDistance / 150) + rebirths * 4
end

function PlayerData.GetStats(data, perks)
	return Stats.Compute({
		Upgrades = data.Upgrades,
		EquippedPlane = data.EquippedPlane,
		EquippedWeapon = data.EquippedWeapon,
		EquippedShield = data.EquippedShield,
		Allies = data.Allies,
		Rebirths = data.Rebirths,
		TotalDistance = data.TotalDistance,
		Perks = perks,
	})
end

function PlayerData.UpgradeCost(kind: string, level: number): number
	return GameConfig.UpgradeCost(kind, level)
end

function PlayerData.AllyLimit(data, perks): number
	local extra = (perks and perks.ExtraAllySlots) or 0
	return math.min(GameConfig.MaxAllySlots, GameConfig.MaxAllies + extra)
end

function PlayerData.CanRebirth(data): boolean
	if PlayerData.GetLevel(data) >= GameConfig.Rebirth.RequiredLevel then
		return true
	end
	local beaten = 0
	if type(data.BossesBeaten) == "table" then
		for _ in pairs(data.BossesBeaten) do
			beaten += 1
		end
	end
	return beaten >= GameConfig.Rebirth.AltBossCount
end

-- Coerce unknown/garbage saved values into a safe schema.
function PlayerData.Sanitize(data)
	local clean = PlayerData.Default()
	if type(data) ~= "table" then
		return clean
	end

	local function int(value, minimum: number?, maximum: number?): number
		local n = math.floor(tonumber(value) or 0)
		if minimum then
			n = math.max(minimum, n)
		end
		if maximum then
			n = math.min(maximum, n)
		end
		return n
	end

	clean.Coins = int(data.Coins, 0, 1e12)
	clean.Gems = int(data.Gems, 0, 1e9)
	clean.Rebirths = int(data.Rebirths, 0, 500)
	clean.BestDistance = int(data.BestDistance, 0, 1e7)
	clean.BestKills = int(data.BestKills, 0, 1e6)
	clean.TotalKills = int(data.TotalKills, 0, 1e8)
	clean.TotalDistance = int(data.TotalDistance, 0, 1e9)
	clean.TotalCoinsEarned = int(data.TotalCoinsEarned, 0, 1e12)
	clean.TotalGemsEarned = int(data.TotalGemsEarned, 0, 1e9)
	clean.Runs = int(data.Runs, 0, 1e7)
	clean.DailyStreak = int(data.DailyStreak, 0, 365)
	clean.LastDailyDay = int(data.LastDailyDay, 0, 1e9)
	clean.ReviveTokens = int(data.ReviveTokens, 0, 99)
	clean.CreatedAt = int(data.CreatedAt, 0, os.time() + 86400)
	clean.LastSeen = int(data.LastSeen, 0, os.time() + 86400)

	if type(data.Upgrades) == "table" then
		for kind in pairs(GameConfig.Upgrades) do
			local v = tonumber(data.Upgrades[kind])
			if v then
				clean.Upgrades[kind] = int(v, 1, 1e6)
			end
		end
	end

	local function unlocked(source, catalogue, into, always)
		if type(source) == "table" then
			for id in pairs(source) do
				if catalogue[id] then
					into[id] = true
				end
			end
		end
		if always then
			into[always] = true
		end
	end

	unlocked(data.UnlockedPlanes, GameConfig.Planes, clean.UnlockedPlanes, "Classic")
	unlocked(data.UnlockedWeapons, GameConfig.Weapons, clean.UnlockedWeapons, "Dart")
	unlocked(data.UnlockedAllies, GameConfig.Allies, clean.UnlockedAllies)
	unlocked(data.UnlockedShields, GameConfig.Shields, clean.UnlockedShields, "None")
	unlocked(data.BossesBeaten, { [""] = true }, clean.BossesBeaten)

	-- Boss keys are zone ids, not catalogue keys, so validate them directly.
	if type(data.BossesBeaten) == "table" then
		table.clear(clean.BossesBeaten)
		for zoneId in pairs(data.BossesBeaten) do
			if GameConfig.GetZoneById(zoneId) then
				clean.BossesBeaten[zoneId] = true
			end
		end
	end

	if type(data.Eggs) == "table" then
		for _, eggId in ipairs(data.Eggs) do
			if GameConfig.Eggs[eggId] and #clean.Eggs < 50 then
				table.insert(clean.Eggs, eggId)
			end
		end
	end

	local allyLimit = GameConfig.MaxAllySlots
	if type(data.Allies) == "table" then
		for _, id in ipairs(data.Allies) do
			if GameConfig.Allies[id] and #clean.Allies < allyLimit then
				table.insert(clean.Allies, id)
				clean.UnlockedAllies[id] = true
			end
		end
	end

	if GameConfig.Characters[data.EquippedCharacter] then
		clean.EquippedCharacter = data.EquippedCharacter
	end
	if GameConfig.Hangars[data.EquippedHangar] then
		clean.EquippedHangar = data.EquippedHangar
	end
	if GameConfig.Shields[data.EquippedShield] then
		clean.EquippedShield = data.EquippedShield
	end
	if GameConfig.Planes[data.EquippedPlane] and clean.UnlockedPlanes[data.EquippedPlane] then
		clean.EquippedPlane = data.EquippedPlane
	end
	if GameConfig.Weapons[data.EquippedWeapon] and clean.UnlockedWeapons[data.EquippedWeapon] then
		clean.EquippedWeapon = data.EquippedWeapon
	end

	if type(data.Achievements) == "table" then
		for id in pairs(data.Achievements) do
			if id == "list" or type(id) == "string" then
				clean.Achievements[id] = true
			end
		end
	end
	if type(data.CodesRedeemed) == "table" then
		for code in pairs(data.CodesRedeemed) do
			if type(code) == "string" and #clean.CodesRedeemed < 200 then
				clean.CodesRedeemed[string.upper(code)] = true
			end
		end
	end

	if type(data.Prestige) == "table" then
		for kind, entry in pairs(GameConfig.Prestige) do
			local value = tonumber(data.Prestige[kind])
			if value then
				clean.Prestige[kind] = int(value, 0, entry.Max)
			end
		end
	end

	if type(data.Quests) == "table" and type(data.Quests.List) == "table" then
		clean.Quests.Day = int(data.Quests.Day, 0, 1e9)
		for _, entry in ipairs(data.Quests.List) do
			if type(entry) == "table" and type(entry.Id) == "string" and #clean.Quests.List < 12 then
				table.insert(clean.Quests.List, {
					Id = entry.Id,
					Progress = int(entry.Progress, 0, 1e9),
					Claimed = entry.Claimed == true,
				})
			end
		end
	end

	return clean
end

-- Build (or refresh) today's daily quest list. Returns true if it changed.
function PlayerData.EnsureDailyQuests(data): boolean
	local day = Quests.UtcDay()
	if data.Quests.Day == day and #data.Quests.List > 0 then
		return false
	end
	local rotation = Quests.RotationForDay(day)
	local list = {}
	for _, template in ipairs(rotation) do
		table.insert(list, { Id = template.Id, Progress = 0, Claimed = false })
	end
	data.Quests = { Day = day, List = list }
	return true
end

function PlayerData.FindQuestTemplate(id: string)
	for _, template in ipairs(Quests.Templates) do
		if template.Id == id then
			return template
		end
	end
	return nil
end

-- The single payload the client receives, both on load and on every update.
function PlayerData.Snapshot(data, perks, ownedPasses)
	return {
		Coins = data.Coins,
		Gems = data.Gems,
		Upgrades = data.Upgrades,
		UnlockedPlanes = data.UnlockedPlanes,
		UnlockedWeapons = data.UnlockedWeapons,
		UnlockedAllies = data.UnlockedAllies,
		UnlockedShields = data.UnlockedShields,
		Eggs = data.Eggs,
		EquippedPlane = data.EquippedPlane,
		EquippedWeapon = data.EquippedWeapon,
		EquippedShield = data.EquippedShield,
		EquippedCharacter = data.EquippedCharacter,
		EquippedHangar = data.EquippedHangar,
		Allies = data.Allies,
		Rebirths = data.Rebirths,
		Prestige = data.Prestige,
		BestDistance = data.BestDistance,
		BestKills = data.BestKills,
		TotalKills = data.TotalKills,
		TotalDistance = data.TotalDistance,
		TotalCoinsEarned = data.TotalCoinsEarned,
		TotalGemsEarned = data.TotalGemsEarned,
		Runs = data.Runs,
		BossesBeaten = data.BossesBeaten,
		DailyStreak = data.DailyStreak,
		LastDailyDay = data.LastDailyDay,
		ReviveTokens = data.ReviveTokens or 0,
		Quests = data.Quests,
		Achievements = data.Achievements,
		CodesRedeemed = data.CodesRedeemed,
		Level = PlayerData.GetLevel(data),
		CanRebirth = PlayerData.CanRebirth(data),
		Day = Quests.UtcDay(),
		Perks = perks or Monetization.EmptyPerks(),
		OwnedPasses = ownedPasses or {},
		Event = GameConfig.GetActiveEvent(),
		AllyLimit = PlayerData.AllyLimit(data, perks),
	}
end

return PlayerData
