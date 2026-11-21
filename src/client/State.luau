--!nonstrict
-- Client-side player state for Paper Wings.
--
-- The server always sends a complete snapshot, but updates are merged over the
-- previous table anyway: a partial payload must never be able to blank out
-- collection data (that bug wiped UnlockedPlanes and reset the shop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stats = require(Shared:WaitForChild("Stats"))

local State = {
	Data = nil,
	Stats = nil,
}

local updateEvent = Instance.new("BindableEvent")
local loadedEvent = Instance.new("BindableEvent")
local runUpdateEvent = Instance.new("BindableEvent")
local runEndedEvent = Instance.new("BindableEvent")
local notifyEvent = Instance.new("BindableEvent")

function State.OnUpdate(callback)
	return updateEvent.Event:Connect(callback)
end

function State.OnLoaded(callback)
	-- Data can arrive before a late subscriber (Flight/UI init after the first
	-- DataLoaded), so replay the loaded event for anyone who asks afterwards.
	if State.Data then
		task.defer(callback, State.Data, State.Stats)
	end
	return loadedEvent.Event:Connect(callback)
end

function State.OnRunUpdate(callback)
	return runUpdateEvent.Event:Connect(callback)
end

function State.OnRunEnded(callback)
	return runEndedEvent.Event:Connect(callback)
end

function State.OnNotify(callback)
	return notifyEvent.Event:Connect(callback)
end

function State.EmitRunUpdate(...)
	runUpdateEvent:Fire(...)
end

function State.EmitRunEnded(result)
	runEndedEvent:Fire(result)
end

function State.EmitNotify(text)
	notifyEvent:Fire(text)
end

local function merge(base, incoming)
	local merged = table.clone(base or {})
	for key, value in pairs(incoming) do
		merged[key] = value
	end
	return merged
end

local function apply(data, isFull: boolean)
	if type(data) ~= "table" then
		return
	end
	State.Data = merge(State.Data, data)
	State.Stats = Stats.Compute(State.Data)
	if isFull then
		loadedEvent:Fire(State.Data, State.Stats)
	else
		updateEvent:Fire(State.Data, State.Stats)
	end
end

function State.ApplyUpdate(data)
	apply(data, false)
end

function State.ApplyLoaded(data)
	apply(data, true)
end

-- Convenience accessors used by the UI.
function State.Coins(): number
	return (State.Data and State.Data.Coins) or 0
end

function State.Gems(): number
	return (State.Data and State.Data.Gems) or 0
end

function State.Level(): number
	return (State.Stats and State.Stats.Level) or 1
end

return State
