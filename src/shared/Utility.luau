--!strict
-- Small shared helpers used by both server and client.

local Utility = {}

local GameConfigRef = require(script.Parent:WaitForChild("GameConfig"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

function Utility.GetShared()
	return ReplicatedStorage:WaitForChild("Shared")
end

function Utility.Clamp(value: number, min: number, max: number): number
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

function Utility.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Utility.LerpVector3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, Utility.Clamp(t, 0, 1))
end

local suffixes = { "", "K", "M", "B", "T", "Q" }

function Utility.FormatNumber(value: number): string
	local n = math.floor(value + 0.5)
	if n < 1000 then
		return tostring(n)
	end
	local idx = 1
	local v = n
	while v >= 1000 and idx < #suffixes do
		v = v / 1000
		idx += 1
	end
	return string.format("%.1f%s", v, suffixes[idx])
end

function Utility.Round(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

-- Smooth enemy scaling (see GameConfig.EnemyHealthMult for the reasoning).
function Utility.ScaleHealth(base: number, distance: number): number
	return base * GameConfigRef.EnemyHealthMult(distance)
end

function Utility.ScaleDamage(base: number, distance: number): number
	return base * GameConfigRef.EnemyDamageMult(distance)
end

return Utility
