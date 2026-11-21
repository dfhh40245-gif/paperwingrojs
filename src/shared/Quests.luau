--!nonstrict
-- Quests: daily missions, achievements and redeemable codes.
--
-- Three daily quests are picked deterministically from `Templates` using the
-- UTC day number as the seed, so every server agrees on today's rotation
-- without storing anything extra. Progress accumulates from run results and is
-- persisted per player.

local Quests = {}

Quests.DailyCount = 3

-- `Type` is the counter the server increments:
--   Kills | Distance | Coins | Bosses | Runs | Gems
Quests.Templates = {
	{ Id = "kill20", Type = "Kills", Amount = 20, Coins = 200, Gems = 1, Text = "Destroy %d enemies" },
	{ Id = "kill60", Type = "Kills", Amount = 60, Coins = 450, Gems = 2, Text = "Destroy %d enemies" },
	{ Id = "kill150", Type = "Kills", Amount = 150, Coins = 900, Gems = 3, Text = "Destroy %d enemies" },
	{ Id = "dist500", Type = "Distance", Amount = 500, Coins = 250, Gems = 1, Text = "Fly %d m in one day" },
	{ Id = "dist1500", Type = "Distance", Amount = 1500, Coins = 550, Gems = 2, Text = "Fly %d m in one day" },
	{ Id = "dist4000", Type = "Distance", Amount = 4000, Coins = 1100, Gems = 3, Text = "Fly %d m in one day" },
	{ Id = "coins2k", Type = "Coins", Amount = 2000, Coins = 300, Gems = 1, Text = "Earn %d coins" },
	{ Id = "coins6k", Type = "Coins", Amount = 6000, Coins = 700, Gems = 2, Text = "Earn %d coins" },
	{ Id = "boss1", Type = "Bosses", Amount = 1, Coins = 600, Gems = 3, Text = "Defeat %d zone boss" },
	{ Id = "runs3", Type = "Runs", Amount = 3, Coins = 300, Gems = 1, Text = "Complete %d flights" },
	{ Id = "runs8", Type = "Runs", Amount = 8, Coins = 650, Gems = 2, Text = "Complete %d flights" },
	{ Id = "gems5", Type = "Gems", Amount = 5, Coins = 400, Gems = 2, Text = "Collect %d gems in one day" },
}

-- Achievements are permanent, lifetime counters. They are checked after every
-- run; `Reward` is granted once.
Quests.Achievements = {
	{ Id = "first_flight", Type = "Runs", Amount = 1, Coins = 100, Gems = 1, Name = "First Flight" },
	{ Id = "ten_runs", Type = "Runs", Amount = 10, Coins = 400, Gems = 2, Name = "Frequent Flyer" },
	{ Id = "hundred_runs", Type = "Runs", Amount = 100, Coins = 2000, Gems = 10, Name = "Sky Veteran" },
	{ Id = "km1", Type = "TotalDistance", Amount = 1000, Coins = 250, Gems = 1, Name = "First Kilometre" },
	{ Id = "km10", Type = "TotalDistance", Amount = 10000, Coins = 1500, Gems = 5, Name = "Ten Thousand" },
	{ Id = "km100", Type = "TotalDistance", Amount = 100000, Coins = 10000, Gems = 25, Name = "Hundred K" },
	{ Id = "kills100", Type = "TotalKills", Amount = 100, Coins = 500, Gems = 2, Name = "Pest Control" },
	{ Id = "kills1000", Type = "TotalKills", Amount = 1000, Coins = 4000, Gems = 12, Name = "Exterminator" },
	{ Id = "boss1", Type = "Bosses", Amount = 1, Coins = 500, Gems = 5, Name = "Giant Slayer" },
	{ Id = "boss6", Type = "Bosses", Amount = 6, Coins = 5000, Gems = 30, Name = "Boss Hunter" },
	{ Id = "rebirth1", Type = "Rebirths", Amount = 1, Coins = 1000, Gems = 10, Name = "Reborn" },
	{ Id = "rebirth10", Type = "Rebirths", Amount = 10, Coins = 8000, Gems = 50, Name = "Cycle Master" },
}

-- Codes are permanent one-off grants. Case-insensitive on redeem.
Quests.Codes = {
	PAPERWINGS = { Coins = 1000, Gems = 3, Note = "Launch code" },
	ORIGAMI = { Coins = 1500, Gems = 5, Note = "Fold it" },
	FIRSTFLIGHT = { Coins = 500, Gems = 1, Note = "Welcome aboard" },
	SCISSORS = { Coins = 2500, Gems = 8, Note = "Snip snip" },
	INKY = { Coins = 2000, Gems = 6, Note = "Mind the ink" },
	STORMCHASER = { Coins = 3000, Gems = 10, Note = "Into the storm" },
	THANKS = { Coins = 750, Gems = 2, Note = "Thanks for playing" },
}

function Quests.UtcDay(now: number?): number
	local t = now or os.time()
	return math.floor(t / 86400)
end

-- Stable per-day selection: same day -> same quests on every server.
function Quests.RotationForDay(day: number)
	local pool = {}
	for i, template in ipairs(Quests.Templates) do
		pool[i] = template
	end

	-- Deterministic Fisher-Yates seeded by the day number.
	local seed = day % 2147483647
	local function nextRandom()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for i = #pool, 2, -1 do
		local j = math.floor(nextRandom() * i) + 1
		pool[i], pool[j] = pool[j], pool[i]
	end

	local picked = {}
	for i = 1, math.min(Quests.DailyCount, #pool) do
		picked[i] = pool[i]
	end
	return picked
end

function Quests.QuestText(template)
	return string.format(template.Text, template.Amount)
end

return Quests
