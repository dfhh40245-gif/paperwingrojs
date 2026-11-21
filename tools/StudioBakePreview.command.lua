-- Paper Wings: build a static six-zone visual preview in Studio Edit mode.
-- Run this script from Roblox Studio's Command Bar after Rojo has synced the project.
-- It creates Workspace.PaperWings_EditorPreview. Delete that folder before publishing
-- if you do not want the off-corridor preview models shipped with the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(shared:WaitForChild("GameConfig"))
local clientContainer = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
local WorldBuilder = require(clientContainer:WaitForChild("WorldBuilder"))

local folderName = "PaperWings_EditorPreview"
local previous = workspace:FindFirstChild(folderName)
if previous then
    previous:Destroy()
end

local preview = Instance.new("Folder")
preview.Name = folderName
preview:SetAttribute("EditorPreviewOnly", true)
preview.Parent = workspace

local segmentSpacing = 460
for index, zone in ipairs(GameConfig.Zones) do
    local chunk = WorldBuilder.BuildChunk(zone.Id, -210, 210, 91000 + index * 7919)
    chunk.Name = string.format("PREVIEW_%02d_%s", index, zone.Id)
    chunk:TranslateBy(Vector3.new((index - 1) * segmentSpacing, 0, 0))
    chunk.Parent = preview
end

print(string.format("[PaperWings] Baked %d environment previews into Workspace.%s", #GameConfig.Zones, folderName))
print("These preview sections are arranged side-by-side, outside the playable corridor.")
