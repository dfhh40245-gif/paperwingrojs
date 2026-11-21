--!strict
-- Server bootstrap for Paper Wings.
-- This script is the "Server" container; its siblings are the server modules.

local GameService = require(script:WaitForChild("GameService"))

GameService.Start()
