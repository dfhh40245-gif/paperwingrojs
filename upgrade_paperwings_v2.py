
from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

FILES = {
    "flight": Path("src/client/Flight.luau"),
    "ui": Path("src/client/UI.luau"),
    "world": Path("src/client/WorldBuilder.luau"),
    "plane": Path("src/client/PlaneBuilder.luau"),
    "effects": Path("src/client/Effects.luau"),
    "config": Path("src/shared/GameConfig.luau"),
}


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count == 0 and new in source:
        return source
    if count != 1:
        raise RuntimeError(f"{label}: expected one source anchor, found {count}.")
    return source.replace(old, new, 1)


def replace_section(source: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(
        pattern,
        lambda _match: replacement,
        source,
        count=1,
        flags=re.MULTILINE | re.DOTALL,
    )
    if count == 0:
        raise RuntimeError(f"{label}: expected source section was not found.")
    return updated


def transform_flight(source: str) -> str:
    required = ("VERTICAL_CONTROL_MULTIPLIER", "headingYaw", "wrongWay", "BRAKE_DRAG")
    missing = [token for token in required if token not in source]
    if missing:
        raise RuntimeError(
            "Flight.luau is missing the earlier control update markers "
            f"({', '.join(missing)}). No files were changed."
        )

    source = replace_once(source, "local VERTICAL_CONTROL_MULTIPLIER = 1.08",
                          "local VERTICAL_CONTROL_MULTIPLIER = 1.02", "vertical control")
    source = replace_once(source, "local MAX_VERTICAL_SPEED_FACTOR = 0.74",
                          "local MAX_VERTICAL_SPEED_FACTOR = 0.73", "vertical speed cap")
    source = replace_once(source, "local HANGAR_SPAWN = CFrame.new(0, 5.3, 32)",
                          "local HANGAR_SPAWN = CFrame.new(0, 5.3, 42)", "hangar spawn")
    source = replace_once(
        source,
        "local HANGAR_PLANE_PARK = CFrame.new(-38, 7, 6) * CFrame.Angles(0, -math.pi / 2, 0)",
        "local HANGAR_PLANE_PARK = CFrame.new(-54, 7, -4) * CFrame.Angles(0, -math.pi / 2, 0)",
        "plane display centre",
    )
    source = replace_once(source, "local MAX_ACTIVE_ENEMIES = 48",
                          "local MAX_ACTIVE_ENEMIES = 60", "enemy capacity")
    source = replace_once(
        source,
        "\t\t\t\tEffects.DamageNumber(enemy.Pos, shotDamage, weapon.Color)\n",
        "\t\t\t\tEffects.DamageNumber(enemy.Pos, shotDamage, weapon.Color)\n"
        "\t\t\t\tEffects.Impact(enemy.Pos, weapon.Color)\n",
        "weapon hit feedback",
    )
    source = replace_once(
        source,
        "local spawnInterval = math.max(0.7, 1.8 - distance / 4000)",
        "local spawnInterval = math.max(0.62, 1.65 - distance / 4200)",
        "enemy encounter pacing",
    )

    if "eggMesh.MeshType = Enum.MeshType.Head" not in source:
        source = replace_once(
            source,
            "\t\tegg.Shape = Enum.PartType.Ball\n",
            "\t\tegg.Shape = Enum.PartType.Ball\n"
            "\t\tlocal eggMesh = Instance.new(\"SpecialMesh\")\n"
            "\t\teggMesh.MeshType = Enum.MeshType.Head\n"
            "\t\teggMesh.Scale = Vector3.new(1.05, 1.18, 1.05)\n"
            "\t\teggMesh.Parent = egg\n",
            "egg shape",
        )

    if "AbilityTimer = cfg.AbilityInterval" not in source:
        source = replace_once(
            source,
            "\t\tPassed = false,\n",
            "\t\tPassed = false,\n"
            "\t\tAbilityTimer = cfg.AbilityInterval or 2.8,\n"
            "\t\tDashTimer = 0,\n"
            "\t\tPhaseSide = 1,\n",
            "enemy ability state",
        )

    enemy_update = r'''local function updateEnemies(dt: number)
	local corridor = GameConfig.Corridor

	for index = #enemies, 1, -1 do
		local enemy = enemies[index]
		if not enemy.Alive then
			table.remove(enemies, index)
			continue
		end

		enemy.T += dt
		local behavior = enemy.Cfg.Behavior

		if enemy.Boss then
			updateBoss(enemy, dt)
		else
			local aheadDistance = planePos.Z - enemy.Pos.Z
			if not enemy.Passed and aheadDistance <= 0 then
				enemy.Passed = true
			elseif not enemy.Passed and aheadDistance <= ENEMY_WAKE_DISTANCE then
				enemy.Engaged = true
			end

			local nextX, nextY, nextZ = enemy.Pos.X, enemy.Pos.Y, enemy.Pos.Z
			local playerMoving = Vector3.new(planeVelocity.X, 0, planeVelocity.Z).Magnitude > 3

			if not enemy.Passed and enemy.Engaged and playerMoving and behavior ~= "mine" then
				local approachSpeed = math.max(enemy.Speed or 0, ENEMY_MIN_APPROACH_SPEED)

				if behavior == "charger" then
					enemy.AbilityTimer -= dt
					if enemy.AbilityTimer <= 0 then
						enemy.AbilityTimer = enemy.Cfg.AbilityInterval or 3.4
						enemy.DashTimer = 0.55
					end
					if enemy.DashTimer > 0 then
						approachSpeed *= 2.6
						enemy.DashTimer = math.max(0, enemy.DashTimer - dt)
					else
						approachSpeed *= 0.65
					end
				end

				local desiredZ = planePos.Z - ENEMY_STANDOFF_DISTANCE
				if nextZ < desiredZ then
					nextZ = math.min(desiredZ, nextZ + approachSpeed * dt)
				end

				local targetX, targetY = planePos.X, planePos.Y
				if behavior == "zigzag" then
					targetX += math.sin(enemy.T * 2.2) * 4
					targetY += math.cos(enemy.T * 1.6) * 2
				elseif behavior == "phase" then
					enemy.AbilityTimer -= dt
					if enemy.AbilityTimer <= 0 then
						enemy.PhaseSide = -(enemy.PhaseSide or 1)
						enemy.AbilityTimer = enemy.Cfg.AbilityInterval or 2.2
					end
					targetX += (enemy.PhaseSide or 1) * 13
					targetY += math.sin(enemy.T * 2) * 4
				end

				local alpha = math.clamp(dt * ENEMY_TRACKING_RATE, 0, 1)
				nextX = Utility.Lerp(nextX, targetX, alpha)
				nextY = Utility.Lerp(nextY, targetY, alpha)
			elseif not enemy.Passed and not enemy.Engaged and behavior == "zigzag" then
				local baseX, baseY = enemy.BaseX or enemy.Pos.X, enemy.BaseY or enemy.Pos.Y
				nextX = Utility.Clamp(baseX + math.sin(enemy.T * 3) * 22,
					-corridor.HalfWidth + 3, corridor.HalfWidth - 3)
				nextY = Utility.Clamp(baseY + math.cos(enemy.T * 2) * 8,
					corridor.MinHeight, corridor.MaxHeight)
			elseif enemy.Engaged and not playerMoving then
				-- Brake/stop means the enemy freezes at its current position.
				nextX, nextY, nextZ = enemy.Pos.X, enemy.Pos.Y, enemy.Pos.Z
			end

			if not enemy.Passed then
				enemy.Pos = clampToCorridor(Vector3.new(nextX, nextY, nextZ))
			end

			if behavior == "mine" and enemy.Engaged and not enemy.Passed then
				enemy.FireTimer -= dt
				if enemy.FireTimer <= 0 then
					enemy.FireTimer = math.max(1.2, enemy.Cfg.FireInterval or 2.8)
					local aim = planePos - enemy.Pos
					if aim.Magnitude > 0.01 then
						local forward = aim.Unit
						local right = Vector3.yAxis:Cross(forward)
						if right.Magnitude < 0.01 then right = Vector3.xAxis else right = right.Unit end
						for _, spread in ipairs({ -0.16, 0, 0.16 }) do
							spawnEnemyProjectile(enemy.Pos, (forward + right * spread).Unit,
								enemy.Cfg.ProjectileSpeed or 32,
								enemy.Cfg.ProjectileDamage or DEFAULT_PROJECTILE_DAMAGE,
								false, 1.8)
						end
					end
				end
			elseif (behavior == "ranged" or behavior == "phase") and enemy.Engaged and not enemy.Passed then
				enemy.FireTimer -= dt
				if enemy.FireTimer <= 0 and enemy.Pos.Z < planePos.Z - ENEMY_STANDOFF_DISTANCE * 0.75 then
					enemy.FireTimer = math.max(0.9, enemy.Cfg.FireInterval or 2)
					spawnEnemyProjectile(enemy.Pos, nil,
						math.max(1, enemy.Cfg.ProjectileSpeed or 40),
						enemy.Cfg.ProjectileDamage or DEFAULT_PROJECTILE_DAMAGE,
						true, nil)
				end
			end
		end

		if enemy.Model and enemy.Model.Parent then
			enemy.Model:PivotTo(CFrame.lookAt(enemy.Pos, enemy.Pos + Vector3.new(0, 0, 1)))
		end

		local contactDistance = (enemy.Pos - planePos).Magnitude
		if contactDistance < 5 and runTime >= (enemy.NextContactDamage or 0) then
			enemy.NextContactDamage = runTime + (if enemy.Boss then BOSS_CONTACT_COOLDOWN else CONTACT_COOLDOWN)
			damagePlayer(enemy.Damage or 0)
			if not enemy.Boss then
				if behavior == "tank" or behavior == "mine" then
					enemy.Health -= 20
					if enemy.Health <= 0 then killEnemy(enemy, true) end
				else
					killEnemy(enemy, false)
				end
			end
		end

		if enemy.Alive and not enemy.Boss and (enemy.Pos - planePos).Magnitude > 340 then
			despawnEnemy(enemy)
		end
		if not enemy.Alive then
			table.remove(enemies, index)
		end
	end
end

'''
    source = replace_section(
        source,
        r"^local function updateEnemies\(dt: number\)\n.*?^local function distanceToSegment\(",
        enemy_update + "local function distanceToSegment(",
        "enemy movement and abilities",
    )

    crash_block = r'''	local nextPosition = planePos + planeVelocity * dt
	local boundaryX = corridor.HalfWidth - BOUNDARY_MARGIN
	local boundaryY = corridor.MaxHeight - BOUNDARY_MARGIN
	local hitSide = math.abs(nextPosition.X) >= boundaryX
	local hitCeiling = nextPosition.Y >= boundaryY
	local hitGround = not wasGrounded and nextPosition.Y <= floorY

	if hitSide or hitCeiling or hitGround then
		planePos = Vector3.new(
			math.clamp(nextPosition.X, -boundaryX, boundaryX),
			math.min(nextPosition.Y, boundaryY),
			nextPosition.Z
		)

		if hitGround then
			planePos = Vector3.new(planePos.X, floorY + 6, planePos.Z)
			crashReason = "ground impact"
			planeVelocity = Vector3.new(planeVelocity.X * 0.3,
				-math.max(24, math.abs(planeVelocity.Y)), planeVelocity.Z * 0.3)
		else
			if planePos.Y <= floorY + 0.25 then
				planePos = Vector3.new(planePos.X, floorY + 7, planePos.Z)
			end
			crashReason = if hitSide then "side barrier" else "upper barrier"
			planeVelocity = Vector3.new(planeVelocity.X * 0.25,
				-math.max(18, math.abs(planeVelocity.Y) * 0.45), planeVelocity.Z * 0.3)
		end

		crashing = true
		crashElapsed = 0
		resetPointerInput()
		Effects.Explosion(planePos,
			if hitGround then Color3.fromRGB(255, 145, 70) else Color3.fromRGB(100, 220, 255),
			if hitGround then 19 else 15)
		Effects.Play("Hit", nil, 0.65)
		State.EmitNotify(
			if hitGround then "GROUND IMPACT — AIRCRAFT DESTROYED"
			else "ELECTRICAL BARRIER — " .. string.upper(crashReason) .. " — CRITICAL DAMAGE"
		)
	else
		planePos = nextPosition
	end

	if not crashing and planePos.Y <= floorY then
		planePos = Vector3.new(planePos.X, floorY, planePos.Z)
		if planeVelocity.Y < 0 then
			planeVelocity = Vector3.new(planeVelocity.X, 0, planeVelocity.Z)
		end
		grounded = true
	else
		grounded = false
	end

'''
    source = replace_section(
        source,
        r"^\tlocal nextPosition = planePos \+ planeVelocity \* dt\n.*?^\t-- Record furthest forward progress\.",
        crash_block + "\t-- Record furthest forward progress.",
        "ground collision and crash animation",
    )

    source = replace_once(source,
        "\t\tapplyZoneLighting(zone)\n\t\temitRunUpdate(true)\n",
        "\t\tapplyZoneLighting(zone)\n\t\tEffects.PlayMusic(zone.Song)\n\t\temitRunUpdate(true)\n",
        "music on zone change")
    source = replace_once(source,
        "\tapplyZoneLighting(zone, true)\n\tsetDefaultControlsEnabled(false)\n",
        "\tapplyZoneLighting(zone, true)\n\tEffects.PlayMusic(zone.Song)\n\tsetDefaultControlsEnabled(false)\n",
        "music at run start")

    for marker in ("VERTICAL_CONTROL_MULTIPLIER = 1.02", "CFrame.new(-54, 7, -4)",
                   "CFrame.new(0, 5.3, 42)", "local hitGround = not wasGrounded and nextPosition.Y <= floorY",
                   'behavior == "charger"', 'behavior == "mine"', 'behavior == "phase"',
                   "Effects.PlayMusic(zone.Song)"):
        if marker not in source:
            raise RuntimeError(f"Flight validation failed: {marker}")
    return source


def transform_config(source: str) -> str:
    source = replace_once(source, "\tHalfWidth = 26,", "\tHalfWidth = 36,", "corridor width")
    source = replace_once(source, "-- Behavior is one of: straight | zigzag | ranged | split | tank", "-- Behavior is one of: straight | zigzag | ranged | split | tank | charger | mine | phase", "enemy behavior documentation")

    extra = r'''	PaperManta = {
		Name = "Paper Manta",
		Behavior = "charger",
		Health = 58,
		Speed = 31,
		Damage = 16,
		Coins = 20,
		Gems = 1,
		Color = Color3.fromRGB(75, 170, 205),
		Accent = Color3.fromRGB(180, 245, 255),
		Scale = 1.55,
		AbilityInterval = 3.4,
	},
	InkMine = {
		Name = "Ink Mine",
		Behavior = "mine",
		Health = 82,
		Speed = 0,
		Damage = 26,
		Coins = 24,
		Gems = 2,
		Color = Color3.fromRGB(62, 45, 108),
		Accent = Color3.fromRGB(255, 92, 128),
		Scale = 1.45,
		FireInterval = 2.8,
		ProjectileSpeed = 34,
		ProjectileDamage = 12,
	},
	MirrorSentinel = {
		Name = "Mirror Sentinel",
		Behavior = "phase",
		Health = 76,
		Speed = 22,
		Damage = 15,
		Coins = 28,
		Gems = 2,
		Color = Color3.fromRGB(120, 190, 210),
		Accent = Color3.fromRGB(220, 250, 255),
		Scale = 1.5,
		AbilityInterval = 2.2,
		FireInterval = 2.5,
		ProjectileSpeed = 38,
		ProjectileDamage = 13,
	},
'''
    if "PaperManta = {" not in source:
        old = (
            '\tHolePunch = {\n'
            '\t\tName = "Hole Punch",\n'
            '\t\tBehavior = "tank",\n'
            '\t\tHealth = 120,\n'
            '\t\tSpeed = 16,\n'
            '\t\tDamage = 18,\n'
            '\t\tCoins = 22,\n'
            '\t\tGems = 2,\n'
            '\t\tColor = Color3.fromRGB(120, 130, 150),\n'
            '\t\tAccent = Color3.fromRGB(80, 88, 104),\n'
            '\t\tScale = 1.62,\n'
            '\t},\n'
            '}\n\n-- Bosses'
        )
        new = old.replace('\t},\n}\n\n-- Bosses', '\t},\n' + extra + '}\n\n-- Bosses')
        source = replace_once(source, old, new, "new enemy definitions")

    zones = [
        ('Enemies = { "Crane", "Crane", "InkBat" },',
         'Enemies = { "Crane", "Crane", "InkBat", "PaperManta" },'),
        ('Enemies = { "InkBat", "StapleShooter", "Crane", "PaperWasp" },',
         'Enemies = { "InkBat", "StapleShooter", "Crane", "PaperWasp", "PaperManta" },'),
        ('Enemies = { "InkBlob", "EraserGolem", "InkBat", "GlueTrap" },',
         'Enemies = { "InkBlob", "EraserGolem", "InkBat", "GlueTrap", "InkMine" },'),
        ('Enemies = { "PaperWasp", "StapleShooter", "EraserGolem", "InkBlob", "MarkerSniper" },',
         'Enemies = { "PaperWasp", "StapleShooter", "EraserGolem", "InkBlob", "MarkerSniper", "PaperManta", "MirrorSentinel" },'),
        ('Enemies = { "PaperWasp", "GlueTrap", "MarkerSniper", "StapleShooter" },',
         'Enemies = { "PaperWasp", "GlueTrap", "MarkerSniper", "StapleShooter", "InkMine" },'),
        ('Enemies = { "MarkerSniper", "HolePunch", "EraserGolem", "PaperWasp", "InkBlob" },',
         'Enemies = { "MarkerSniper", "HolePunch", "EraserGolem", "PaperWasp", "InkBlob", "MirrorSentinel" },'),
    ]
    for old, new in zones:
        source = replace_once(source, old, new, "zone enemy list")

    for marker in ("HalfWidth = 36", "PaperManta = {", "InkMine = {", "MirrorSentinel = {"):
        if marker not in source:
            raise RuntimeError(f"GameConfig validation failed: {marker}")
    return source


def transform_world(source: str) -> str:
    barriers = r'''local function buildElectricalBoundaries(parent, zone, centerZ, halfLength, rng)
	local corridor = GameConfig.Corridor
	local width = corridor.HalfWidth
	local top = corridor.MaxHeight
	local length = halfLength * 2
	local cyan = Color3.fromRGB(90, 225, 255)
	local warning = Color3.fromRGB(255, 82, 62)
	local gold = Color3.fromRGB(255, 210, 82)

	for _, side in ipairs({ -1, 1 }) do
		local wall = part(parent, "ElectricalWall", Vector3.new(0.7, top, length),
			Vector3.new(side * width, top * 0.5, centerZ), cyan, Enum.Material.ForceField)
		wall.Transparency = 0.82
		wall.Reflectance = 0.08

		for _, y in ipairs({ 1.4, top - 1.2 }) do
			local rail = part(parent, "HighVoltageRail", Vector3.new(1.0, 0.8, length),
				Vector3.new(side * width, y, centerZ), warning, NEON)
			rail.Transparency = 0.05
		end

		for postIndex = -2, 2 do
			local z = centerZ + postIndex * 38
			local post = part(parent, "WarningPost", Vector3.new(1.4, top - 5, 1.4),
				Vector3.new(side * (width - 1.4), (top - 5) * 0.5 + 2.5, z), warning, NEON)
			post.Transparency = 0.12
			part(parent, "WarningPostCap", Vector3.new(3.2, 1.0, 2.4),
				Vector3.new(side * (width - 1.4), top - 2.5, z), gold, NEON)

			for stripe = -1, 1 do
				local slash = part(parent, "DoNotTouchStripe", Vector3.new(0.18, 5.2, 0.3),
					Vector3.new(side * (width - 1.4) - side * 0.85, 7 + stripe * 7, z + stripe * 0.5),
					gold, NEON, 0, 0, -22)
				slash.Transparency = 0.02
			end

			local sign = Instance.new("BillboardGui")
			sign.Name = "DangerSign"
			sign.Size = UDim2.fromOffset(118, 34)
			sign.StudsOffset = Vector3.new(0, 3.8, 0)
			sign.AlwaysOnTop = true
			sign.MaxDistance = 240
			sign.Parent = post
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(45, 20, 25)
			label.BackgroundTransparency = 0.08
			label.Text = "DANGER  ⚡"
			label.TextColor3 = gold
			label.TextStrokeTransparency = 0.4
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.Parent = sign
		end

		for boltIndex = 1, 7 do
			local boltZ = centerZ + rng:NextNumber(-halfLength * 0.9, halfLength * 0.9)
			local boltY = rng:NextNumber(7, top - 7)
			local previous = Vector3.new(side * (width - 0.8), boltY, boltZ)
			for segmentIndex = 1, 4 do
				local nextPoint = previous + Vector3.new(side * rng:NextNumber(-1.7, 1.7),
					rng:NextNumber(-5, 5), rng:NextNumber(3, 8))
				local delta = nextPoint - previous
				local arc = part(parent, "ElectricalArc", Vector3.new(0.32, 0.32, math.max(0.1, delta.Magnitude)),
					(previous + nextPoint) * 0.5, if segmentIndex % 2 == 0 then gold else cyan, NEON)
				arc.CFrame = CFrame.lookAt(arc.Position, nextPoint)
				arc.Transparency = 0.02
				previous = nextPoint
			end
		end
	end

	local ceiling = part(parent, "ElectricalCeiling", Vector3.new(width * 2, 0.6, length),
		Vector3.new(0, top, centerZ), cyan, Enum.Material.ForceField)
	ceiling.Transparency = 0.88
	ceiling.CanCollide = false
	for _, x in ipairs({ -width + 4, 0, width - 4 }) do
		local rail = part(parent, "CeilingWarningRail", Vector3.new(0.65, 0.55, length),
			Vector3.new(x, top - 0.8, centerZ), warning, NEON)
		rail.Transparency = 0.08
	end
	local ceilingEdge = part(parent, "ElectricalCeilingEdge", Vector3.new(width * 2, 0.55, 0.7),
		Vector3.new(0, top, centerZ - halfLength), gold, NEON)
	ceilingEdge.Transparency = 0.08
end

'''
    source = replace_section(
        source,
        r"^local function buildElectricalBoundaries\(parent, zone, centerZ, halfLength, rng\)\n.*?^end\n\n-- -+ chunks",
        barriers + "-- ------------------------------------------------------------------ chunks",
        "visible electrical boundaries",
    )

    # Add themed landmarks at the edges of the widened corridor.
    landmarks = r'''local function buildMapLandmarks(parent, zone, centerZ, halfLength, rng)
	local width = GameConfig.Corridor.HalfWidth
	for side = -1, 1, 2 do
		local x = side * (width + 28 + rng:NextNumber(0, 12))
		local z = centerZ + rng:NextNumber(-halfLength * 0.8, halfLength * 0.8)
		local y = rng:NextNumber(16, 34)
		local accent = zone.Accent
		if zone.Style == "town" then
			local balloon = ball(parent, "TownBalloon", 5.5, Vector3.new(x, y, z), accent, NEON)
			balloon.Transparency = 0.12
			part(parent, "BalloonBasket", Vector3.new(2, 1.5, 2), Vector3.new(x, y - 5, z), Color3.fromRGB(150, 105, 72), PAPER)
		elseif zone.Style == "canyon" then
			part(parent, "CanyonMarker", Vector3.new(3, 28, 3), Vector3.new(x, y, z), Color3.fromRGB(200, 110, 72), PAPER, 0, 0, side * 14)
			wedge(parent, "CanyonFlag", Vector3.new(8, 3, 1), Vector3.new(x - side * 4, y + 10, z), accent, NEON, 0, 0, side * 8)
		elseif zone.Style == "ocean" then
			local orb = ball(parent, "DeepSeaOrb", 6, Vector3.new(x, y, z), accent, NEON)
			orb.Transparency = 0.22
			for ring = 1, 2 do
				part(parent, "SeaPrism", Vector3.new(1, 12, 12), Vector3.new(x, y + ring * 5, z), Color3.fromRGB(110, 80, 190), FOIL, 0, ring * 35, 90)
			end
		elseif zone.Style == "storm" then
			wedge(parent, "StormShard", Vector3.new(5, 24, 4), Vector3.new(x, y, z), accent, NEON, 0, 0, side * 18)
			ball(parent, "StormPulse", 4, Vector3.new(x, y + 13, z), Color3.fromRGB(115, 210, 255), NEON)
		elseif zone.Style == "clouds" then
			local cloud = WorldBuilder.BuildCloud(Vector3.new(x, y, z), 1.35)
			cloud.Parent = parent
			part(parent, "CloudForgeSpire", Vector3.new(2.5, 17, 2.5), Vector3.new(x, y - 9, z), accent, NEON)
		else
			part(parent, "FoldMonolith", Vector3.new(5, 28, 5), Vector3.new(x, y, z), Color3.fromRGB(38, 32, 64), FOIL, 12, 0, side * 16)
			ball(parent, "FoldStar", 3.6, Vector3.new(x, y + 16, z), accent, NEON)
		end
	end
end

'''
    if "local function buildMapLandmarks(" not in source:
        source = replace_once(source, "function WorldBuilder.BuildChunk(", landmarks + "function WorldBuilder.BuildChunk(", "themed map landmarks")
        source = replace_once(
            source,
            "\trecipe(model, zone, centerZ, halfLength, rng)\n\tbuildElectricalBoundaries(model, zone, centerZ, halfLength, rng)\n",
            "\trecipe(model, zone, centerZ, halfLength, rng)\n"
            "\tbuildMapLandmarks(model, zone, centerZ, halfLength, rng)\n"
            "\tbuildElectricalBoundaries(model, zone, centerZ, halfLength, rng)\n",
            "add scenery landmarks to chunks",
        )

    enemy_models = '''local enemyBuilderAliases = {
	Crane = "DartDrone",
	InkBat = "ShredderWasp",
	StapleShooter = "StaplerTank",
	InkBlob = "InkBlob",
	EraserGolem = "StaplerTank",
	PaperWasp = "ShredderWasp",
	GlueTrap = "InkBlob",
	MarkerSniper = "ScissorBot",
	HolePunch = "ScissorBot",
	PaperManta = "PaperManta",
	InkMine = "InkMine",
	MirrorSentinel = "MirrorSentinel",
}

enemyBuilders.PaperManta = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_PaperManta"
	local body = ellipsoid(m, "Body", Vector3.new(4.2, 1.8, 8.2), Vector3.zero, config.Color, PAPER)
	wedge(m, "WingL", Vector3.new(8.5, 0.18, 5.6), Vector3.new(-5.2, 0, 0.5), config.Accent, PAPER, 0, 0, 15)
	wedge(m, "WingR", Vector3.new(8.5, 0.18, 5.6), Vector3.new(5.2, 0, 0.5), config.Accent, PAPER, 0, 0, -15)
	ball(m, "EyeL", 0.9, Vector3.new(-1.0, 0.6, 3.4), Color3.fromRGB(255, 70, 90), NEON)
	ball(m, "EyeR", 0.9, Vector3.new(1.0, 0.6, 3.4), Color3.fromRGB(255, 70, 90), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.InkMine = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_InkMine"
	local body = ball(m, "Core", 5.5, Vector3.zero, config.Color, FOIL)
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		wedge(m, "MineSpike" .. i, Vector3.new(1.2, 3.4, 1.2),
			Vector3.new(math.cos(angle) * 3.3, math.sin(angle) * 3.3, 0),
			config.Accent, NEON, 0, 0, math.deg(angle))
	end
	ball(m, "WarningCore", 1.8, Vector3.new(0, 0, 2.8), Color3.fromRGB(255, 65, 90), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.MirrorSentinel = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_MirrorSentinel"
	local body = part(m, "Core", Vector3.new(4.2, 5.8, 2.8), Vector3.zero, config.Color, FOIL)
	for side = -1, 1, 2 do
		local shard = wedge(m, "MirrorShard" .. side, Vector3.new(2.0, 7.2, 1.1),
			Vector3.new(side * 3.2, 0.6, 0), config.Accent, GLASS, 0, 0, side * -18)
		shard.Transparency = 0.22
	end
	ball(m, "Eye", 1.3, Vector3.new(0, 0.5, 1.8), Color3.fromRGB(255, 245, 170), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

function WorldBuilder.BuildEnemy(enemyId: string, scale: number?): Model
	local config = GameConfig.Enemies[enemyId] or GameConfig.Enemies.InkBlob
	local builderId = enemyBuilderAliases[enemyId] or enemyId
	local build = enemyBuilders[builderId] or enemyBuilders.InkBlob
	return build(config, scale or config.Scale or 1)
end'''
    source = replace_once(
        source,
        '''function WorldBuilder.BuildEnemy(enemyId: string, scale: number?): Model
	local config = GameConfig.Enemies[enemyId] or GameConfig.Enemies.InkBlob
	local build = enemyBuilders[enemyId] or enemyBuilders.InkBlob
	return build(config, scale or config.Scale or 1)
end''',
        enemy_models,
        "enemy visual mappings",
    )

    boss_details = r'''	local bossModel = bossDef.Model
	if bossModel == "GiantScissors" then
		wedge(m, "ScissorBladeL", Vector3.new(3.2, 25, 2.4), Vector3.new(-12, 4, 5), Color3.fromRGB(220, 230, 245), FOIL, 0, 0, 18)
		wedge(m, "ScissorBladeR", Vector3.new(3.2, 25, 2.4), Vector3.new(12, 4, 5), Color3.fromRGB(220, 230, 245), FOIL, 0, 0, -18)
		ball(m, "PivotBolt", 3.2, Vector3.new(0, 1, 7), accent, NEON)
	elseif bossModel == "PencilTitan" then
		part(m, "PencilShaft", Vector3.new(4.5, 28, 4.5), Vector3.new(0, 23, -2), Color3.fromRGB(245, 190, 55), PAPER)
		wedge(m, "PencilTip", Vector3.new(4.5, 8, 4.5), Vector3.new(0, 41, -2), Color3.fromRGB(70, 58, 46), PAPER)
		part(m, "EraserCap", Vector3.new(6, 5, 6), Vector3.new(0, 7, -2), Color3.fromRGB(235, 110, 145), PAPER)
	elseif bossModel == "InkLeviathan" then
		for i = 1, 5 do
			ellipsoid(m, "LeviathanFin" .. i, Vector3.new(6, 4, 7),
				Vector3.new((if i % 2 == 0 then 1 else -1) * 8, -5 - i * 1.5, -8 - i * 5), accent, NEON)
		end
		part(m, "InkCrest", Vector3.new(2, 18, 18), Vector3.new(0, 14, -8), accent, NEON)
	elseif bossModel == "StormShears" then
		for side = -1, 1, 2 do
			wedge(m, "StormBlade" .. side, Vector3.new(4, 28, 3), Vector3.new(side * 14, 6, 4), accent, NEON, 0, 0, side * 24)
			ball(m, "StormOrb" .. side, 4, Vector3.new(side * 18, 18, 0), Color3.fromRGB(120, 220, 255), NEON)
		end
	elseif bossModel == "CloudColossus" then
		for i = 1, 7 do
			local angle = i / 7 * math.pi * 2
			ellipsoid(m, "CloudShoulder" .. i, Vector3.new(7, 6, 7),
				Vector3.new(math.cos(angle) * 14, 8 + math.sin(angle) * 4, -3), Color3.fromRGB(245, 245, 255), PAPER)
		end
	elseif bossModel == "GreatFold" then
		part(m, "GoldenFoldCrown", Vector3.new(22, 2, 22), Vector3.new(0, 23, 0), accent, NEON, 0, 0, 45)
		part(m, "FoldCore", Vector3.new(5, 22, 5), Vector3.new(0, 1, 7), Color3.fromRGB(255, 232, 150), FOIL)
	end

'''
    source = replace_once(
        source,
        '\tball(m, "EyeR", 2.2, Vector3.new(2.4, 13, 4.6), Color3.fromRGB(255, 60, 60), NEON)\n\tm.PrimaryPart = torso',
        '\tball(m, "EyeR", 2.2, Vector3.new(2.4, 13, 4.6), Color3.fromRGB(255, 60, 60), NEON)\n'
        + boss_details + '\tm.PrimaryPart = torso',
        "boss silhouettes",
    )

    for marker in ("DangerSign", "buildMapLandmarks", "enemyBuilderAliases", "PaperManta",
                   "InkMine", "MirrorSentinel", 'bossModel == "GiantScissors"',
                   'bossModel == "GreatFold"'):
        if marker not in source:
            raise RuntimeError(f"WorldBuilder validation failed: {marker}")
    return source


def transform_plane(source: str) -> str:
    if 'descendant.Name == "PilotBody"' not in source:
        source = replace_once(
            source,
            "\taddAircraftFinish(model, config, planeId)\n",
            "\taddAircraftFinish(model, config, planeId)\n"
            "\t-- Aircraft only: remove the decorative person from every plane.\n"
            "\tfor _, descendant in ipairs(model:GetDescendants()) do\n"
            "\t\tif descendant.Name == \"PilotBody\" or descendant.Name == \"PilotHead\" then\n"
            "\t\t\tdescendant:Destroy()\n"
            "\t\tend\n"
            "\tend\n",
            "remove the plane pilot",
        )
    return source


def transform_effects(source: str) -> str:
    if "local MUSIC_TRACKS =" not in source:
        source = replace_once(
            source,
            "local Effects = {}\n",
            "local Effects = {}\n\n"
            "local MUSIC_TRACKS = {\n"
            '\ttown = "",\n\tcanyon = "",\n\tocean = "",\n\tstorm = "",\n\tclouds = "",\n\tfold = "",\n'
            "}\n"
            "local currentMusic: Sound? = nil\n"
            "local currentMusicKey: string? = nil\n",
            "music track settings",
        )

    if "function Effects.PlayMusic(" not in source:
        music = r'''function Effects.PlayMusic(trackName: string?)
	local key = if type(trackName) == "string" then string.lower(trackName) else ""
	if currentMusicKey == key and currentMusic and currentMusic.IsPlaying then
		return
	end
	if currentMusic then
		local old = currentMusic
		currentMusic = nil
		currentMusicKey = nil
		TweenService:Create(old, TweenInfo.new(0.45), { Volume = 0 }):Play()
		task.delay(0.5, function()
			if old.Parent then old:Stop(); old:Destroy() end
		end)
	end
	local assetId = MUSIC_TRACKS[key]
	if not assetId or assetId == "" then return end
	local sound = Instance.new("Sound")
	sound.Name = "PaperWingsMusic"
	sound.SoundId = assetId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(1.2), { Volume = 0.28 }):Play()
	currentMusic = sound
	currentMusicKey = key
end

'''
        source = replace_once(source, "function Effects.MuzzleFlash(", music + "function Effects.MuzzleFlash(", "music playback function")

    if "function Effects.Impact(" not in source:
        impact = r'''function Effects.Impact(origin: Vector3, color: Color3?)
	local c = color or Color3.fromRGB(255, 230, 150)
	local flash = part(Vector3.new(0.7, 0.7, 0.7), CFrame.new(origin), c, Enum.Material.Neon, 0.18)
	flash.Shape = Enum.PartType.Ball
	TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.2, 4.2, 4.2),
		Transparency = 1,
	}):Play()
	Effects.Burst(origin, c, 7, 8)
end

'''
        source = replace_once(source, "function Effects.CoinPop(", impact + "function Effects.CoinPop(", "hit impact effect")

    old = (
        "local beam = part(Vector3.new(0.28, 0.28, dist), CFrame.lookAt(fromPos, toPos) * CFrame.new(0, 0, -dist * 0.5), c, Enum.Material.Neon, 0.14)\n"
        "\tTweenService:Create(beam, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {\n"
        "\t\tSize = Vector3.new(0.02, 0.02, dist),"
    )
    new = (
        "local beam = part(Vector3.new(0.38, 0.38, dist), CFrame.lookAt(fromPos, toPos) * CFrame.new(0, 0, -dist * 0.5), c, Enum.Material.Neon, 0.19)\n"
        "\tTweenService:Create(beam, TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {\n"
        "\t\tSize = Vector3.new(0.025, 0.025, dist),"
    )
    source = replace_once(source, old, new, "tracer visual improvement")

    for marker in ("local MUSIC_TRACKS =", "function Effects.PlayMusic(", "function Effects.Impact("):
        if marker not in source:
            raise RuntimeError(f"Effects validation failed: {marker}")
    return source


def transform_ui(source: str) -> str:
    if "local pendingEggId: string? = nil" not in source:
        source = replace_once(
            source,
            "local bindingButtons: { [string]: TextButton } = {}\n",
            "local bindingButtons: { [string]: TextButton } = {}\nlocal pendingEggId: string? = nil\n",
            "egg hatch request state",
        )

    source = replace_once(
        source,
        "\t\tif not enabled then\n\t\t\treturn\n\t\tend\n\t\tonClick()\n",
        "\t\tif not enabled then\n\t\t\treturn\n\t\tend\n"
        "\t\tif pendingEggId then\n\t\t\ttoast(\"PLEASE WAIT FOR THE EGG HATCH\")\n\t\t\treturn\n\t\tend\n"
        "\t\tonClick()\n",
        "prevent overlapping shop transactions during hatch",
    )

    hatch = r'''local function playEggHatch(eggId: string, resultMessage: string?)
	if not gui or not gui.Parent then return end
	local eggConfig = GameConfig.Eggs[eggId]
	local eggColor = if eggConfig then eggConfig.Color or C.Grape else C.Grape
	local petName = if type(resultMessage) == "string"
		then (resultMessage:match("^Hatched (.-)!") or resultMessage:match("^Hatched (.-) %(") or "A NEW COMPANION")
		else "A NEW COMPANION"

	local overlay = new("Frame", {
		Name = "EggHatchOverlay", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink, BackgroundTransparency = 0.18,
		BorderSizePixel = 0, ZIndex = 80,
	}, gui)
	local title = new("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.25), Size = UDim2.new(0.8, 0, 0, 44),
		BackgroundTransparency = 1, Text = "EGG HATCHING",
		TextColor3 = C.White, Font = FONT, TextSize = 27, ZIndex = 82,
	}, overlay)
	local egg = new("Frame", {
		Name = "Egg", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.49), Size = UDim2.fromOffset(94, 124),
		BackgroundColor3 = eggColor, BorderSizePixel = 0, ZIndex = 83,
	}, overlay)
	corner(egg, 48)
	outline(egg, C.White, 4, 0.05)
	gradient(egg, eggColor:Lerp(C.White, 0.28), eggColor:Lerp(C.Ink, 0.12), 90)
	local shine = new("Frame", {
		Name = "Shine", Position = UDim2.new(0, 16, 0, 18),
		Size = UDim2.new(0, 13, 0, 40), BackgroundColor3 = C.White,
		BackgroundTransparency = 0.18, BorderSizePixel = 0, Rotation = 20, ZIndex = 84,
	}, egg)
	corner(shine, 12)
	local subtitle = new("TextLabel", {
		Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(0.85, 0, 0, 34),
		BackgroundTransparency = 1, Text = "A COMPANION IS INSIDE...",
		TextColor3 = C.PaperDim, Font = FONT_BOLD, TextSize = 16, ZIndex = 82,
	}, overlay)
	local reveal = new("TextLabel", {
		Name = "Reveal", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.new(0.9, 0, 0, 48),
		BackgroundTransparency = 1, Text = "", TextColor3 = eggColor,
		Font = FONT, TextSize = 28, TextTransparency = 1, ZIndex = 82,
	}, overlay)

	TweenService:Create(egg,
		TweenInfo.new(0.38, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true),
		{ Size = UDim2.fromOffset(110, 142) }):Play()

	task.spawn(function()
		for _ = 1, 5 do
			if not egg.Parent then return end
			for _, angle in ipairs({ -13, 13, -9, 9, 0 }) do
				TweenService:Create(egg, TweenInfo.new(0.075, Enum.EasingStyle.Quad), { Rotation = angle }):Play()
				task.wait(0.075)
			end
		end
	end)

	task.delay(1.55, function()
		if not overlay.Parent then return end
		title.Text = "NEW COMPANION!"
		subtitle.Text = "ADDED TO YOUR COLLECTION"
		egg.Visible = false
		reveal.Text = string.upper(petName)
		TweenService:Create(reveal, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ TextTransparency = 0, TextSize = 34 }):Play()
		Effects.Play("Upgrade", nil, 0.65)
	end)
	task.delay(3.8, function()
		if overlay.Parent then
			TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			task.wait(0.28)
			if overlay.Parent then overlay:Destroy() end
		end
	end)
end

'''
    if "local function playEggHatch(" not in source:
        source = replace_once(source, "renderers.Eggs = function()\n", hatch + "renderers.Eggs = function()\n", "egg hatch UI")

    source = replace_once(
        source,
        '''		addRow(egg.Name, "HATCH A RANDOM PET  •  LUCK IMPROVES THE ODDS", "HATCH  " .. egg.Cost .. " GEMS", egg.Color or C.Grape, State.Gems() >= egg.Cost, function()
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "egg", Id = id })
		end)''',
        '''		addRow(egg.Name, "HATCH A RANDOM PET  •  LUCK IMPROVES THE ODDS", "HATCH  " .. egg.Cost .. " GEMS", egg.Color or C.Grape, State.Gems() >= egg.Cost, function()
			if pendingEggId then
				toast("AN EGG IS ALREADY HATCHING")
				return
			end
			pendingEggId = id
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "egg", Id = id })
		end)''',
        "egg purchase request",
    )

    source = replace_once(
        source,
        '''	Remotes.Get(Remotes.ShopSync).OnClientEvent:Connect(function(success, message)
		if success then
			Effects.Play("Upgrade", nil, 0.4)
			if message and message ~= "" then
				toast(message)
			end
		elseif message and message ~= "" then
			toast(message)
		end
		UI.RefreshTop()
		UI.RefreshShop()
	end)''',
        '''	Remotes.Get(Remotes.ShopSync).OnClientEvent:Connect(function(success, message)
		local completedEggId = pendingEggId
		pendingEggId = nil
		if success then
			Effects.Play("Upgrade", nil, 0.4)
			if completedEggId then
				playEggHatch(completedEggId, message)
			elseif message and message ~= "" then
				toast(message)
			end
		elseif message and message ~= "" then
			toast(message)
		end
		UI.RefreshTop()
		UI.RefreshShop()
	end)''',
        "server-approved hatch display",
    )
    if "playEggHatch(completedEggId, message)" not in source:
        raise RuntimeError("UI validation failed: hatch animation is not connected to the server response.")
    return source


def transform_all(root: Path) -> dict[Path, str]:
    original = {}
    for rel in FILES.values():
        path = root / rel
        if not path.is_file():
            raise RuntimeError(f"Required project file not found: {path}")
        original[path] = path.read_text(encoding="utf-8")

    return {
        root / FILES["flight"]: transform_flight(original[root / FILES["flight"]]),
        root / FILES["ui"]: transform_ui(original[root / FILES["ui"]]),
        root / FILES["world"]: transform_world(original[root / FILES["world"]]),
        root / FILES["plane"]: transform_plane(original[root / FILES["plane"]]),
        root / FILES["effects"]: transform_effects(original[root / FILES["effects"]]),
        root / FILES["config"]: transform_config(original[root / FILES["config"]]),
    }


def backup_name(path: Path) -> Path:
    first = path.with_suffix(path.suffix + ".before_overhaul.bak")
    if not first.exists():
        return first
    index = 2
    while True:
        candidate = path.with_suffix(path.suffix + f".before_overhaul_{index}.bak")
        if not candidate.exists():
            return candidate
        index += 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply the Paper Wings gameplay and UI overhaul.")
    parser.add_argument("--repo", type=Path, default=Path.cwd(),
                        help="Project root containing src/client and src/shared.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate changes without writing files.")
    args = parser.parse_args()
    root = args.repo.expanduser().resolve()

    try:
        updated = transform_all(root)
    except Exception as exc:
        print(f"ERROR: {exc}")
        print("No files were changed.")
        return 1

    changed = [path for path, content in updated.items()
               if path.read_text(encoding="utf-8") != content]
    if not changed:
        print("Already up to date. No files were changed.")
        return 0

    if args.dry_run:
        print("DRY RUN PASSED.")
        print(f"Validated {len(updated)} project files; {len(changed)} will be updated:")
        for path in changed:
            print(f"  {path.relative_to(root)}")
        print("No files were written.")
        return 0

    backups = []
    try:
        for path in changed:
            backup = backup_name(path)
            shutil.copy2(path, backup)
            backups.append((path, backup))
        for path in changed:
            temporary = path.with_suffix(path.suffix + ".overhaul.tmp")
            temporary.write_text(updated[path], encoding="utf-8", newline="\n")
            shutil.copyfile(temporary, path)
            temporary.unlink(missing_ok=True)
    except Exception:
        for original, backup in backups:
            if backup.exists():
                shutil.copy2(backup, original)
        print("ERROR: Write failed. Original files were restored.")
        raise

    print("SUCCESS. Updated:")
    for path in changed:
        print(f"  {path.relative_to(root)}")
    print("\nBackups:")
    for _, backup in backups:
        print(f"  {backup.relative_to(root)}")
    print("\nNotes:")
    print("- Vertical control is only marginally faster (2% more input acceleration and a 1.4% higher speed cap).")
    print("- Ground impact now triggers the existing tumble/crash death sequence.")
    print("- Wider route, obvious electrical hazard markers, and additional map landmarks.")
    print("- Three enemy types added with distinct attack behaviours; existing enemy models are mapped correctly.")
    print("- Bosses receive different visual silhouettes.")
    print("- Plane pilots are removed; the lobby plane is centred; player spawn is moved back.")
    print("- Egg hatching animation runs only after the server accepts the hatch.")
    print("- Sound/music hooks are installed, but you must add valid Roblox audio asset IDs.")
    print("- Test in Studio: this script does not execute Roblox gameplay.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
