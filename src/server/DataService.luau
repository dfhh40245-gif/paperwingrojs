--!nonstrict
-- DataService: persistence with a Studio-safe fallback.
--
-- In Studio (or when the DataStore API is unavailable) every request falls
-- through to an in-memory store, so joins are instant and the console stays
-- clean instead of blocking on three retries of a request that cannot succeed.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataService = {}

local STORE_NAME = "PaperWings_v2"
local RETRIES = 3
local RETRY_BASE = 1

local isStudio = RunService:IsStudio()
local memory: { [string]: any } = {}

local store = nil
if not isStudio then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

function DataService.IsPersistent(): boolean
	return store ~= nil
end

local function safeRequest(action, fallback)
	local lastErr
	for attempt = 1, RETRIES do
		local ok, result = pcall(action)
		if ok then
			return result
		end
		lastErr = result
		if attempt < RETRIES then
			task.wait(RETRY_BASE * attempt)
		end
	end
	warn("[DataService] request failed:", lastErr)
	return fallback
end

function DataService.Load(key: string)
	if not store then
		local cached = memory[key]
		return if cached then table.clone(cached) else nil
	end
	return safeRequest(function()
		return store:GetAsync(key)
	end, nil)
end

function DataService.Save(key: string, data): boolean
	if not store then
		memory[key] = table.clone(data)
		return true
	end
	return safeRequest(function()
		store:SetAsync(key, data)
		return true
	end, false)
end

-- UpdateAsync variant used for the global leaderboard so concurrent writes from
-- several servers cannot lose entries.
function DataService.Update(key: string, transform)
	if not store then
		return nil
	end
	return safeRequest(function()
		return store:UpdateAsync(key, transform)
	end, nil)
end

function DataService.GetOrderedStore(name: string)
	if not store then
		return nil
	end
	local ok, ordered = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then ordered else nil
end

return DataService
