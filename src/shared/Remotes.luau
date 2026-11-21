--!strict
-- Remote channel names for Paper Wings.
-- The server creates these under ReplicatedStorage.Remotes on startup.
-- The client waits for them by name; nothing here creates instances.

local Remotes = {}

Remotes.Folder = "Remotes"

-- client -> server
Remotes.RunResult = "RunResult" -- run outcome (validated server-side)
Remotes.Purchase = "Purchase" -- buy upgrade / plane / weapon / ally / shield / egg
Remotes.Rebirth = "Rebirth" -- perform rebirth
Remotes.RequestStart = "RequestStart" -- ask to begin a run
Remotes.RequestData = "RequestData" -- ask for the full player snapshot
Remotes.PromptPass = "PromptPass" -- request a gamepass purchase prompt
Remotes.PromptProduct = "PromptProduct" -- request a dev-product purchase prompt
Remotes.ClaimQuest = "ClaimQuest" -- claim a completed daily quest
Remotes.ClaimDaily = "ClaimDaily" -- claim today's login reward
Remotes.RedeemCode = "RedeemCode" -- redeem a promo code
Remotes.RequestLeaderboard = "RequestLeaderboard" -- ask for the global top flights
Remotes.UseRevive = "UseRevive" -- consume a purchased revive token

-- server -> client
Remotes.LeaderboardData = "LeaderboardData" -- leaderboard payload
Remotes.DataLoaded = "DataLoaded" -- full player snapshot
Remotes.DataUpdate = "DataUpdate" -- full player snapshot after a change
Remotes.RunEvent = "RunEvent" -- run lifecycle (ended, zone, etc.)
Remotes.ShopSync = "ShopSync" -- purchase result (success, message)
Remotes.Notify = "Notify" -- transient toast message

function Remotes.GetFolder(): Folder
	return game:GetService("ReplicatedStorage"):WaitForChild(Remotes.Folder)
end

function Remotes.Get(name: string): RemoteEvent
	return Remotes.GetFolder():WaitForChild(name) :: RemoteEvent
end

return Remotes
