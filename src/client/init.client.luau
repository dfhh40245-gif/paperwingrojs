--!nonstrict
-- Client bootstrap for Paper Wings.
-- This LocalScript is the "Client" container; its siblings are client modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local State = require(script:WaitForChild("State"))
local Flight = require(script:WaitForChild("Flight"))
local UI = require(script:WaitForChild("UI"))

Remotes.Get(Remotes.DataLoaded).OnClientEvent:Connect(function(data)
	State.ApplyLoaded(data)
end)

Remotes.Get(Remotes.DataUpdate).OnClientEvent:Connect(function(data)
	State.ApplyUpdate(data)
end)

Remotes.Get(Remotes.Notify).OnClientEvent:Connect(function(text)
	State.EmitNotify(tostring(text))
end)

-- Ask for the snapshot now that the handlers above are connected. The server may
-- have pushed it before this script finished loading, so retry until it lands.
task.spawn(function()
	for _ = 1, 10 do
		if State.Data then
			return
		end
		Remotes.Get(Remotes.RequestData):FireServer()
		task.wait(1)
	end
	warn("[PaperWings] no data after 10s")
end)

Flight.Init()
UI.Init()

-- Live handles. Rojo re-creates module instances when it re-syncs, so anything
-- that needs the *running* state (tests, debug tools) must go through this
-- instead of requiring the modules again.
_G.PaperWings = { State = State, Flight = Flight, UI = UI, Remotes = Remotes }

print("[PaperWings] Client ready")
