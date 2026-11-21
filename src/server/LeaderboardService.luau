--!nonstrict
-- LeaderboardService: global "furthest flight" rankings via OrderedDataStore.
--
-- Writes are throttled per player and only happen when a personal best improves.
-- The top list is cached for a minute so a busy server does not hammer the
-- DataStore. In Studio (no API access) it falls back to session-only entries so
-- the UI still has something real to show.

local Players = game:GetService("Players")

local DataService = require(script.Parent:WaitForChild("DataService"))

local LeaderboardService = {}

local STORE_NAME = "PaperWings_Distance_v2"
local CACHE_SECONDS = 60
local MAX_ENTRIES = 25

local submitted: { [Player]: number } = {}
local sessionBest: { [number]: number } = {}
local nameCache: { [number]: string } = {}
local cache = { entries = {}, at = 0 }

local function ordered()
	return DataService.GetOrderedStore(STORE_NAME)
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else "Pilot " .. tostring(userId)
	nameCache[userId] = resolved
	return resolved
end

-- Returns the entries for this session's fallback board (Studio only).
local function sessionEntries(limit: number)
	local entries = {}
	for userId, distance in pairs(sessionBest) do
		table.insert(entries, { UserId = userId, Distance = distance })
	end
	table.sort(entries, function(a, b)
		return a.Distance > b.Distance
	end)
	for index, entry in ipairs(entries) do
		entry.Rank = index
		entry.Name = nameFor(entry.UserId)
		if index >= limit then
			break
		end
	end
	return entries
end

function LeaderboardService.Submit(player: Player, distance: number)
	if distance <= 0 then
		return
	end
	local previous = submitted[player]
	if previous and distance <= previous then
		return
	end
	submitted[player] = distance
	sessionBest[player.UserId] = math.max(sessionBest[player.UserId] or 0, distance)
	cache.at = 0

	local store = ordered()
	if not store then
		return
	end

	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(tostring(player.UserId), math.floor(distance))
		end)
		if not ok then
			warn("[Leaderboard] submit failed:", err)
		end
	end)
end

function LeaderboardService.GetTop(limit: number)
	limit = math.clamp(limit or 10, 1, MAX_ENTRIES)
	if os.time() - cache.at < CACHE_SECONDS and #cache.entries > 0 then
		return cache.entries
	end

	local entries = {}
	local store = ordered()

	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, limit)
		end)
		if ok and pages then
			local pageOk, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if pageOk and page then
				for rank, item in ipairs(page) do
					local userId = tonumber(item.key)
					if userId then
						table.insert(entries, {
							Rank = rank,
							UserId = userId,
							Name = nameFor(userId),
							Distance = item.value,
						})
					end
				end
			end
		else
			warn("[Leaderboard] read failed:", pages)
		end
	end

	-- Studio / offline: fall back to this session's flights.
	if #entries == 0 then
		entries = sessionEntries(limit)
	end

	cache.entries = entries
	cache.at = os.time()
	return entries
end

function LeaderboardService.Forget(player: Player)
	submitted[player] = nil
end

return LeaderboardService
