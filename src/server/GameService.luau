--!nonstrict
-- GameService: the authoritative server for Paper Wings.
--
-- The client simulates flight for responsiveness, but it never decides a payout.
-- A run must be started through RequestStart and reported once through
-- RunResult; the reward is derived from the *validated* distance and kill count,
-- clamped against the wall-clock time the run actually took.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Quests = require(Shared:WaitForChild("Quests"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local GameService = {}

-- Anti-cheat ceilings. A legitimate run can never exceed these: top speed with
-- every multiplier and boost is ~62 m/s, and kills are bounded by spawn rate.
local MAX_METERS_PER_SECOND = 72
local MAX_KILLS_PER_SECOND = 12
local MIN_RUN_SECONDS = 2
local SAVE_INTERVAL = 45

local dataByPlayer: { [Player]: any } = {}
local runByPlayer: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local remotes = {}

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- ---------------------------------------------------------------- helpers ---
local function getData(player: Player)
	return dataByPlayer[player]
end

local function notify(player: Player, text: string)
	if remotes.Notify then
		remotes.Notify:FireClient(player, text)
	end
end

local function pushSnapshot(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	local snapshot = PlayerData.Snapshot(data, MonetizationService.GetPerks(player), MonetizationService.GetOwnedKeys(player))
	if remotes.DataUpdate then
		remotes.DataUpdate:FireClient(player, snapshot)
	end
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local distance = stats:FindFirstChild("Distance")
		if distance then
			distance.Value = data.BestDistance
		end
		local rebirths = stats:FindFirstChild("Rebirths")
		if rebirths then
			rebirths.Value = data.Rebirths
		end
		local level = stats:FindFirstChild("Level")
		if level then
			level.Value = PlayerData.GetLevel(data)
		end
	end
end

local function markDirty(player: Player)
	dirty[player] = true
end

local function saveNow(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.LastSeen = os.time()
	dirty[player] = false
	task.spawn(function()
		DataService.Save(keyFor(player), data)
	end)
end

-- ------------------------------------------------------------ quests ------
local function addQuestProgress(data, kind: string, amount: number)
	if amount <= 0 then
		return
	end
	PlayerData.EnsureDailyQuests(data)
	for _, entry in ipairs(data.Quests.List) do
		local template = PlayerData.FindQuestTemplate(entry.Id)
		if template and template.Type == kind and not entry.Claimed then
			entry.Progress = math.min(template.Amount, entry.Progress + amount)
		end
	end
end

local ACHIEVEMENT_VALUES = {
	Runs = function(data)
		return data.Runs
	end,
	TotalDistance = function(data)
		return data.TotalDistance
	end,
	TotalKills = function(data)
		return data.TotalKills
	end,
	Rebirths = function(data)
		return data.Rebirths
	end,
	Bosses = function(data)
		local count = 0
		for _ in pairs(data.BossesBeaten) do
			count += 1
		end
		return count
	end,
}

local function checkAchievements(player: Player, data)
	for _, achievement in ipairs(Quests.Achievements) do
		if not data.Achievements[achievement.Id] then
			local getter = ACHIEVEMENT_VALUES[achievement.Type]
			if getter and getter(data) >= achievement.Amount then
				data.Achievements[achievement.Id] = true
				data.Coins += achievement.Coins or 0
				data.Gems += achievement.Gems or 0
				notify(
					player,
					string.format("Achievement unlocked: %s  (+%d coins)", achievement.Name, achievement.Coins or 0)
				)
			end
		end
	end
end

-- ------------------------------------------------------------- rewards ----
local function computeReward(data, perks, distance: number, kills: number, comboSteps: number, bossZone: string?)
	local stats = PlayerData.GetStats(data, perks)

	local comboBonus = math.min(GameConfig.Combo.MaxBonus, comboSteps * GameConfig.Combo.BonusPerKill)
	local coinMult = (stats.CoinMult or 1) * (1 + comboBonus)
	local gemMult = stats.GemMult or 1

	-- Deeper zones pay more per metre, so pushing distance always beats farming
	-- the first zone. The multiplier is based on how far the run actually got.
	local zoneCoinMult = GameConfig.GetZoneForDistance(distance).CoinMult or 1

	-- Live-ops bonus (weekend rush, midweek gems, ...).
	local event = GameConfig.GetActiveEvent()
	local eventCoinMult = (event and event.CoinMult) or 1
	local eventGemMult = (event and event.GemMult) or 1

	local coins = distance * GameConfig.CoinPerMeter * zoneCoinMult * coinMult * eventCoinMult
	coins += kills * GameConfig.KillCoinFlat * zoneCoinMult * coinMult * eventCoinMult
	local gems = distance * GameConfig.GemPerMeter * zoneCoinMult * gemMult * eventGemMult

	local bossReward = nil
	if bossZone then
		local boss = GameConfig.GetBossForZone(bossZone)
		if boss then
			coins += boss.Coins * (stats.CoinMult or 1)
			gems += boss.Gems * gemMult
			bossReward = { Zone = bossZone, Name = boss.Name, Coins = boss.Coins, Gems = boss.Gems }
		end
	end

	return math.floor(coins + 0.5), math.floor(gems + 0.5), bossReward, comboBonus
end

-- -------------------------------------------------------------- runs ------
local function handleRequestStart(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	local state = runByPlayer[player]
	if state and state.active then
		-- A previous run never reported back (client error, reconnect, abandoned
		-- run). Rather than locking the player out of flying forever, close that
		-- run out silently and let the new one start. No reward is granted for
		-- the abandoned attempt.
		runByPlayer[player] = { active = false, endedAt = now() }
	end
	-- No cooldown: a start carries no reward, and dropping a legitimate start
	-- (for example "Fly Again" clicked instantly) would silently void the run.
	runByPlayer[player] = { active = true, startedAt = now() }
	if remotes.DataLoaded then
		remotes.DataLoaded:FireClient(player, PlayerData.Snapshot(data, MonetizationService.GetPerks(player), MonetizationService.GetOwnedKeys(player)))
	end
end

local function handleRunResult(player: Player, payload: any)
	local data = dataByPlayer[player]
	local state = runByPlayer[player]
	if not data or not state or not state.active then
		return
	end
	state.active = false
	state.endedAt = now()

	local elapsed = math.max(0, now() - (state.startedAt or now()))
	if type(payload) ~= "table" or elapsed < MIN_RUN_SECONDS then
		runByPlayer[player] = { active = false, endedAt = now() }
		return
	end

	-- Clamp everything the client claims to what the clock allows.
	local maxDistance = elapsed * MAX_METERS_PER_SECOND + 150
	local claimedDistance = math.floor(tonumber(payload.Distance) or 0)
	local distance = math.clamp(claimedDistance, 0, math.min(maxDistance, 1e6))

	local maxKills = elapsed * MAX_KILLS_PER_SECOND + 30
	local claimedKills = math.floor(tonumber(payload.Kills) or 0)
	local kills = math.clamp(claimedKills, 0, math.min(maxKills, 1e6))

	local comboSteps = math.clamp(math.floor(tonumber(payload.Combo) or 0), 0, GameConfig.Combo.MaxSteps)

	local bossZone = nil
	if type(payload.BossZone) == "string" then
		local boss = GameConfig.GetBossForZone(payload.BossZone)
		if boss and distance >= boss.Distance then
			bossZone = boss.Zone
		end
	end

	local perks = MonetizationService.GetPerks(player)
	local coins, gems, bossReward, comboBonus = computeReward(data, perks, distance, kills, comboSteps, bossZone)

	data.Coins += coins
	data.Gems += gems
	data.TotalKills += kills
	data.TotalDistance += distance
	data.TotalCoinsEarned += coins
	data.TotalGemsEarned += gems
	data.Runs += 1
	data.BestDistance = math.max(data.BestDistance, distance)
	data.BestKills = math.max(data.BestKills, kills)
	if bossZone then
		data.BossesBeaten[bossZone] = true
	end

	addQuestProgress(data, "Kills", kills)
	addQuestProgress(data, "Distance", distance)
	addQuestProgress(data, "Coins", coins)
	addQuestProgress(data, "Gems", gems)
	addQuestProgress(data, "Runs", 1)
	if bossZone then
		addQuestProgress(data, "Bosses", 1)
	end

	checkAchievements(player, data)
	LeaderboardService.Submit(player, data.BestDistance)

	if claimedDistance > maxDistance + 1 or claimedKills > maxKills + 1 then
		warn(
			string.format(
				"[GameService] clamped suspicious run from %s: claimed %d m / %d kills in %.1fs",
				player.Name,
				claimedDistance,
				claimedKills,
				elapsed
			)
		)
	end

	pushSnapshot(player)
	markDirty(player)

	if remotes.RunEvent then
		remotes.RunEvent:FireClient(player, "Ended", {
			Distance = distance,
			Kills = kills,
			Coins = coins,
			Gems = gems,
			Combo = comboBonus,
			Boss = bossReward,
			Level = PlayerData.GetLevel(data),
		})
	end

	runByPlayer[player] = { active = false, endedAt = now() }
end

-- ---------------------------------------------------------- purchases -----
local function maxUpgradeLevel(kind: string): number
	local upgrade = GameConfig.Upgrades[kind]
	if not upgrade or upgrade.Max == math.huge then
		return math.huge
	end
	return math.floor(upgrade.Max / upgrade.PerLevel) + 1
end

local function handleUpgrade(player: Player, data, id: string, result)
	local upgrade = GameConfig.Upgrades[id]
	if not upgrade then
		result.message = "Unknown upgrade"
		return
	end
	local level = PlayerData.UpgradeLevel(data, id)
	if level >= maxUpgradeLevel(id) then
		result.message = "Already maxed"
		return
	end
	local cost = PlayerData.UpgradeCost(id, level)
	if data.Coins < cost then
		result.message = "Not enough coins"
		return
	end
	data.Coins -= cost
	data.Upgrades[id] = level + 1
	result.success = true
end

local function handlePlane(player: Player, data, id: string, perks, result)
	local plane = GameConfig.Planes[id]
	if not plane then
		result.message = "Unknown plane"
		return
	end
	if plane.RequiresPass and not MonetizationService.OwnsPass(player, plane.RequiresPass) then
		result.message = "Requires the " .. (Monetization.Gamepasses[plane.RequiresPass]
			and Monetization.Gamepasses[plane.RequiresPass].Name or "gamepass")
		return
	end
	if data.UnlockedPlanes[id] then
		data.EquippedPlane = id
		result.success = true
		return
	end
	if PlayerData.GetLevel(data) < (plane.UnlockLevel or 0) then
		result.message = "Reach level " .. plane.UnlockLevel
		return
	end
	if data.Gems < plane.Cost then
		result.message = "Not enough gems"
		return
	end
	data.Gems -= plane.Cost
	data.UnlockedPlanes[id] = true
	data.EquippedPlane = id
	result.success = true
end

local function handleWeapon(player: Player, data, id: string, result)
	local weapon = GameConfig.Weapons[id]
	if not weapon then
		result.message = "Unknown weapon"
		return
	end
	if weapon.RequiresPass and not MonetizationService.OwnsPass(player, weapon.RequiresPass) then
		result.message = "Gamepass exclusive"
		return
	end
	if data.UnlockedWeapons[id] then
		data.EquippedWeapon = id
		result.success = true
		return
	end
	if data.Gems < weapon.Cost then
		result.message = "Not enough gems"
		return
	end
	data.Gems -= weapon.Cost
	data.UnlockedWeapons[id] = true
	data.EquippedWeapon = id
	result.success = true
end

local function handleShield(player: Player, data, id: string, result)
	local shield = GameConfig.Shields[id]
	if not shield then
		result.message = "Unknown shield"
		return
	end
	if data.UnlockedShields[id] then
		data.EquippedShield = id
		result.success = true
		return
	end
	if data.Gems < shield.Cost then
		result.message = "Not enough gems"
		return
	end
	data.Gems -= shield.Cost
	data.UnlockedShields[id] = true
	data.EquippedShield = id
	result.success = true
end

local function handleAlly(player: Player, data, id: string, perks, result)
	local ally = GameConfig.Allies[id]
	if not ally then
		result.message = "Unknown ally"
		return
	end

	local limit = PlayerData.AllyLimit(data, perks)
	for _, equipped in ipairs(data.Allies) do
		if equipped == id then
			result.message = "Already in your squad"
			return
		end
	end

	if data.UnlockedAllies[id] then
		if #data.Allies >= limit then
			result.message = "Squad is full"
			return
		end
		table.insert(data.Allies, id)
		result.success = true
		return
	end

	if #data.Allies >= limit then
		result.message = "Squad is full"
		return
	end
	if data.Gems < ally.Cost then
		result.message = "Not enough gems"
		return
	end
	data.Gems -= ally.Cost
	data.UnlockedAllies[id] = true
	table.insert(data.Allies, id)
	result.success = true
end

local function handleEgg(player: Player, data, id: string, perks, result)
	local egg = GameConfig.Eggs[id]
	if not egg then
		result.message = "Unknown egg"
		return
	end
	if data.Gems < egg.Cost then
		result.message = "Not enough gems"
		return
	end
	if #egg.Pets == 0 then
		result.message = "This egg is empty"
		return
	end

	data.Gems -= egg.Cost
	local luck = 1 + ((perks.LuckMult or 1) - 1) + (data.Upgrades.Luck - 1) * GameConfig.Upgrades.Luck.PerLevel

	-- The last entry in each egg's pool is the rare one; luck biases toward it.
	local index = math.random(1, #egg.Pets)
	if luck > 1 and math.random() < math.min(0.6, (luck - 1) * 0.35) then
		index = #egg.Pets
	end
	local petId = egg.Pets[index]
	local petName = GameConfig.Allies[petId] and GameConfig.Allies[petId].Name or petId

	data.UnlockedAllies[petId] = true
	table.insert(data.Eggs, id)
	if #data.Eggs > 50 then
		table.remove(data.Eggs, 1)
	end

	local limit = PlayerData.AllyLimit(data, perks)
	if #data.Allies < limit then
		table.insert(data.Allies, petId)
		result.message = "Hatched " .. petName .. "!"
	else
		result.message = "Hatched " .. petName .. " (squad full)"
	end
	result.success = true
end

local function handlePrestige(data, id: string, result)
	local entry = GameConfig.Prestige[id]
	if not entry then
		result.message = "Unknown prestige"
		return
	end
	local rank = math.max(0, math.floor(tonumber(data.Prestige[id]) or 0))
	if rank >= entry.Max then
		result.message = "Already maxed"
		return
	end
	local cost = GameConfig.PrestigeCost(id, rank)
	if data.Gems < cost then
		result.message = "Not enough gems"
		return
	end
	data.Gems -= cost
	data.Prestige[id] = rank + 1
	result.success = true
end

local function handlePurchase(player: Player, payload: any)
	local data = dataByPlayer[player]
	if not data or type(payload) ~= "table" then
		return
	end

	local action = payload.Action
	local id = payload.Id
	local perks = MonetizationService.GetPerks(player)
	local result = { success = false, message = "" }

	if action == "upgrade" then
		handleUpgrade(player, data, tostring(id), result)
	elseif action == "plane" then
		handlePlane(player, data, tostring(id), perks, result)
	elseif action == "weapon" then
		handleWeapon(player, data, tostring(id), result)
	elseif action == "shield" then
		handleShield(player, data, tostring(id), result)
	elseif action == "ally" then
		handleAlly(player, data, tostring(id), perks, result)
	elseif action == "egg" then
		handleEgg(player, data, tostring(id), perks, result)
	elseif action == "prestige" then
		handlePrestige(data, tostring(id), result)
	elseif action == "hangar" then
		local hangar = GameConfig.Hangars[tostring(id)]
		if hangar then
			data.EquippedHangar = tostring(id)
			result.success = true
			result.message = "Home set to " .. hangar.Name
		else
			result.message = "Unknown hangar"
		end
	elseif action == "removeAlly" then
		for index, equipped in ipairs(data.Allies) do
			if equipped == id then
				table.remove(data.Allies, index)
				result.success = true
				break
			end
		end
	else
		result.message = "Unknown action"
	end

	if result.success then
		pushSnapshot(player)
		markDirty(player)
	end

	if remotes.ShopSync then
		remotes.ShopSync:FireClient(player, result.success, result.message)
	end
end

-- ------------------------------------------------------------- rebirth ----
local function handleRebirth(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if not PlayerData.CanRebirth(data) then
		if remotes.ShopSync then
			remotes.ShopSync:FireClient(player, false, "Rebirth needs level " .. GameConfig.Rebirth.RequiredLevel)
		end
		return
	end

	data.Coins = 0
	data.Upgrades = { Damage = 1, Health = 1, Speed = 1, Magnet = 1, Luck = 1 }
	data.Rebirths += 1

	checkAchievements(player, data)
	pushSnapshot(player)
	markDirty(player)

	if remotes.ShopSync then
		remotes.ShopSync:FireClient(player, true, "Rebirth " .. data.Rebirths .. "!")
	end
	if remotes.RunEvent then
		remotes.RunEvent:FireClient(player, "Rebirth", { Rebirths = data.Rebirths })
	end
end

-- --------------------------------------------------------------- daily ----
local function handleClaimDaily(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end

	local day = Quests.UtcDay()
	if data.LastDailyDay == day then
		notify(player, "Already claimed today")
		return
	end

	data.DailyStreak = if data.LastDailyDay == day - 1 then math.min(365, data.DailyStreak + 1) else 1
	data.LastDailyDay = day

	local rewards = GameConfig.DailyRewards
	local entry = rewards[math.min(data.DailyStreak, #rewards)]
	data.Coins += entry.Coins or 0
	data.Gems += entry.Gems or 0

	pushSnapshot(player)
	markDirty(player)
	notify(player, string.format("Day %d reward: +%d coins, +%d gems", data.DailyStreak, entry.Coins or 0, entry.Gems or 0))
end

local function handleClaimQuest(player: Player, index: any)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	PlayerData.EnsureDailyQuests(data)

	local slot = math.floor(tonumber(index) or 0)
	local entry = data.Quests.List[slot]
	if not entry then
		return
	end
	if entry.Claimed then
		notify(player, "Already claimed")
		return
	end
	local template = PlayerData.FindQuestTemplate(entry.Id)
	if not template or entry.Progress < template.Amount then
		notify(player, "Quest not complete")
		return
	end

	entry.Claimed = true
	data.Coins += template.Coins or 0
	data.Gems += template.Gems or 0

	pushSnapshot(player)
	markDirty(player)
	notify(player, string.format("Quest complete: +%d coins, +%d gems", template.Coins or 0, template.Gems or 0))
end

local function handleRedeemCode(player: Player, rawCode: any)
	local data = dataByPlayer[player]
	if not data or type(rawCode) ~= "string" then
		return
	end
	local code = string.upper(string.gsub(rawCode, "%s", ""))
	if #code == 0 or #code > 32 then
		return
	end
	local reward = Quests.Codes[code]
	if not reward then
		notify(player, "Invalid code")
		return
	end
	if data.CodesRedeemed[code] then
		notify(player, "Code already used")
		return
	end

	data.CodesRedeemed[code] = true
	data.Coins += reward.Coins or 0
	data.Gems += reward.Gems or 0

	pushSnapshot(player)
	markDirty(player)
	notify(player, string.format("Code %s: +%d coins, +%d gems", code, reward.Coins or 0, reward.Gems or 0))
end

-- --------------------------------------------------------------- joins ----
local function buildLeaderstats(player: Player, data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local distance = Instance.new("IntValue")
	distance.Name = "Distance"
	distance.Value = data.BestDistance
	distance.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = leaderstats

	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = PlayerData.GetLevel(data)
	level.Parent = leaderstats

	leaderstats.Parent = player
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local loaded = DataService.Load(keyFor(player))
		if not player.Parent then
			return
		end

		local data = PlayerData.Sanitize(loaded)
		dataByPlayer[player] = data
		runByPlayer[player] = { active = false }
		PlayerData.EnsureDailyQuests(data)

		MonetizationService.Refresh(player)
		-- A pass that unlocks a plane/weapon also grants it permanently.
		local perks = MonetizationService.GetPerks(player)
		for planeId in pairs(perks.UnlockPlanes) do
			data.UnlockedPlanes[planeId] = true
		end
		for weaponId in pairs(perks.UnlockWeapons) do
			data.UnlockedWeapons[weaponId] = true
		end

		if not player.Parent then
			dataByPlayer[player] = nil
			return
		end

		buildLeaderstats(player, data)

		if remotes.DataLoaded then
			remotes.DataLoaded:FireClient(player, PlayerData.Snapshot(data, perks, MonetizationService.GetOwnedKeys(player)))
		end
		pushSnapshot(player)

		print(string.format("[GameService] loaded %s (level %d, %d coins)", player.Name, PlayerData.GetLevel(data), data.Coins))
	end)
end

local function onPlayerRemoving(player: Player)
	runByPlayer[player] = nil
	if dataByPlayer[player] then
		saveNow(player)
	end
	dataByPlayer[player] = nil
	dirty[player] = nil
	MonetizationService.Forget(player)
	LeaderboardService.Forget(player)
end

-- ----------------------------------------------------------------- boot ---
local function buildRemotes()
	local folder = Instance.new("Folder")
	folder.Name = Remotes.Folder

	local function make(name: string)
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	remotes.RunResult = make(Remotes.RunResult)
	remotes.Purchase = make(Remotes.Purchase)
	remotes.Rebirth = make(Remotes.Rebirth)
	remotes.RequestStart = make(Remotes.RequestStart)
	remotes.RequestData = make(Remotes.RequestData)
	remotes.PromptPass = make(Remotes.PromptPass)
	remotes.PromptProduct = make(Remotes.PromptProduct)
	remotes.ClaimQuest = make(Remotes.ClaimQuest)
	remotes.ClaimDaily = make(Remotes.ClaimDaily)
	remotes.RedeemCode = make(Remotes.RedeemCode)
	remotes.RequestLeaderboard = make(Remotes.RequestLeaderboard)
	remotes.UseRevive = make(Remotes.UseRevive)
	remotes.DataLoaded = make(Remotes.DataLoaded)
	remotes.DataUpdate = make(Remotes.DataUpdate)
	remotes.RunEvent = make(Remotes.RunEvent)
	remotes.ShopSync = make(Remotes.ShopSync)
	remotes.Notify = make(Remotes.Notify)
	remotes.LeaderboardData = make(Remotes.LeaderboardData)

	folder.Parent = ReplicatedStorage
end

local function handleProduct(player: Player, key: string, product): boolean
	local data = dataByPlayer[player]
	if not data then
		return false
	end

	if product.Coins and product.Coins > 0 then
		data.Coins += product.Coins
	end
	if product.Gems and product.Gems > 0 then
		data.Gems += product.Gems
	end
	if product.Revive then
		data.ReviveTokens = (data.ReviveTokens or 0) + 1
	end

	pushSnapshot(player)
	markDirty(player)
	notify(player, product.Name .. " delivered!")
	return true
end

function GameService.Start()
	buildRemotes()

	MonetizationService.SetProductHandler(handleProduct)
	MonetizationService.OnPerksChanged = function(player)
		pushSnapshot(player)
	end
	MonetizationService.OnPassPurchased = function(player, _key)
		local data = dataByPlayer[player]
		if not data then
			return
		end
		local perks = MonetizationService.GetPerks(player)
		for planeId in pairs(perks.UnlockPlanes) do
			data.UnlockedPlanes[planeId] = true
		end
		for weaponId in pairs(perks.UnlockWeapons) do
			data.UnlockedWeapons[weaponId] = true
		end
		pushSnapshot(player)
		markDirty(player)
	end
	MonetizationService.Start()

	remotes.RunResult.OnServerEvent:Connect(handleRunResult)
	remotes.Purchase.OnServerEvent:Connect(handlePurchase)
	remotes.Rebirth.OnServerEvent:Connect(handleRebirth)
	remotes.RequestStart.OnServerEvent:Connect(handleRequestStart)
	-- The client connects its handlers after the server may have already sent
	-- the join snapshot, so it asks again once it is ready.
	remotes.RequestData.OnServerEvent:Connect(function(player)
		local data = dataByPlayer[player]
		if not data then
			return
		end
		if remotes.DataLoaded then
			remotes.DataLoaded:FireClient(
				player,
				PlayerData.Snapshot(data, MonetizationService.GetPerks(player), MonetizationService.GetOwnedKeys(player))
			)
		end
	end)
	remotes.PromptPass.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			return
		end
		local ok, message = MonetizationService.PromptPass(player, key)
		if not ok then
			notify(player, message)
		end
	end)
	remotes.PromptProduct.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			return
		end
		local ok, message = MonetizationService.PromptProduct(player, key)
		if not ok then
			notify(player, message)
		end
	end)
	remotes.ClaimQuest.OnServerEvent:Connect(handleClaimQuest)
	remotes.ClaimDaily.OnServerEvent:Connect(handleClaimDaily)
	remotes.RedeemCode.OnServerEvent:Connect(handleRedeemCode)
	remotes.RequestLeaderboard.OnServerEvent:Connect(function(player)
		local data = dataByPlayer[player]
		if remotes.LeaderboardData then
			remotes.LeaderboardData:FireClient(player, {
				Entries = LeaderboardService.GetTop(10),
				Personal = if data then data.BestDistance else 0,
			})
		end
	end)
	remotes.UseRevive.OnServerEvent:Connect(function(player)
		local data = dataByPlayer[player]
		if not data then
			return
		end
		if (data.ReviveTokens or 0) <= 0 then
			return
		end
		data.ReviveTokens -= 1
		pushSnapshot(player)
		markDirty(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for player in pairs(dirty) do
				if player.Parent and dataByPlayer[player] then
					saveNow(player)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local data = dataByPlayer[player]
			if data then
				data.LastSeen = os.time()
				DataService.Save(keyFor(player), data)
			end
		end
	end)

	print("[GameService] Started")
end

return GameService
