from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one matching section, found {count}. No files were changed.")
    return source.replace(old, new, 1)


def replace_between(source: str, start: str, end: str, replacement: str, label: str) -> str:
    start_at = source.find(start)
    if start_at < 0:
        raise RuntimeError(f"{label}: start marker not found. No files were changed.")
    end_at = source.find(end, start_at + len(start))
    if end_at < 0:
        raise RuntimeError(f"{label}: end marker not found. No files were changed.")
    return source[:start_at] + replacement + source[end_at:]


def transform_flight(source: str) -> str:
    source = replace_once(
        source,
        "local MAX_VERTICAL_SPEED_FACTOR = 0.72\n",
        """local MAX_VERTICAL_SPEED_FACTOR = 0.74
local VERTICAL_CONTROL_MULTIPLIER = 1.08
local BRAKE_DRAG = 4.5
local TURN_RATE = math.rad(90)
local ENEMY_WAKE_DISTANCE = 115
local ENEMY_STANDOFF_DISTANCE = 8
local ENEMY_TRACKING_RATE = 2
local ENEMY_MIN_APPROACH_SPEED = 14
""",
        "flight tuning constants",
    )

    source = replace_once(
        source,
        "local planeRotation = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1))\n",
        """local planeRotation = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1))
local headingYaw = 0
local wrongWay = false
""",
        "flight heading state",
    )

    source = replace_between(
        source,
        "local function readInput(): Vector3\n",
        "-- Fire intent is tracked per source",
        """local function readInput(): Vector3
	local x, y, throttle = 0, 0, 0
	if UserInputService.KeyboardEnabled then
		if UserInputService:IsKeyDown(keyBindings.Forward) then throttle = 1 end
		if UserInputService:IsKeyDown(keyBindings.Left) then x -= 1 end
		if UserInputService:IsKeyDown(keyBindings.Right) then x += 1 end
		if UserInputService:IsKeyDown(keyBindings.Ascend) then y += 1 end
		if UserInputService:IsKeyDown(keyBindings.Descend) then y -= 1 end
	end

	-- Backward is a brake, not reverse thrust. Mouse input remains dedicated to aiming.
	return Vector3.new(x, y, throttle)
end

""",
        "readInput function",
    )

    source = replace_once(
        source,
        "\t\tFireTimer = math.max(0.1, cfg.FireInterval or 2),\n\t\tNextContactDamage = 0,\n",
        "\t\tFireTimer = math.max(0.1, cfg.FireInterval or 2),\n\t\tNextContactDamage = 0,\n\t\tEngaged = false,\n\t\tPassed = false,\n",
        "enemy state fields",
    )

    enemies_function = """local function updateEnemies(dt: number)
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

			-- Once the plane passes an enemy, it becomes passive and stays behind.
			if not enemy.Passed and aheadDistance <= 0 then
				enemy.Passed = true
			elseif not enemy.Passed and aheadDistance <= ENEMY_WAKE_DISTANCE then
				enemy.Engaged = true
			end

			if not enemy.Passed then
				local nextX = enemy.Pos.X
				local nextY = enemy.Pos.Y
				local nextZ = enemy.Pos.Z
				local playerMoving = Vector3.new(planeVelocity.X, 0, planeVelocity.Z).Magnitude > 3

				if enemy.Engaged and playerMoving then
					-- Move toward the plane, then hold a small distance ahead of it.
					local desiredZ = planePos.Z - ENEMY_STANDOFF_DISTANCE
					local approachSpeed = math.max(enemy.Speed or 0, ENEMY_MIN_APPROACH_SPEED)
					if nextZ < desiredZ then
						nextZ = math.min(desiredZ, nextZ + approachSpeed * dt)
					end

					local targetX = planePos.X
					local targetY = planePos.Y
					if behavior == "zigzag" then
						targetX += math.sin(enemy.T * 2.2) * 4
						targetY += math.cos(enemy.T * 1.6) * 2
					end

					local alpha = math.clamp(dt * ENEMY_TRACKING_RATE, 0, 1)
					nextX = Utility.Lerp(nextX, targetX, alpha)
					nextY = Utility.Lerp(nextY, targetY, alpha)
				elseif not enemy.Engaged and behavior == "zigzag" then
					-- Before engagement, zigzag laterally without moving along the course.
					local baseX = enemy.BaseX or enemy.Pos.X
					local baseY = enemy.BaseY or enemy.Pos.Y
					nextX = Utility.Clamp(
						baseX + math.sin(enemy.T * 3) * 22,
						-corridor.HalfWidth,
						corridor.HalfWidth
					)
					nextY = Utility.Clamp(
						baseY + math.cos(enemy.T * 2) * 8,
						corridor.MinHeight,
						corridor.MaxHeight
					)
				end

				-- When the player brakes to a stop, an engaged enemy freezes too.
				if enemy.Engaged and not playerMoving then
					nextX, nextY, nextZ = enemy.Pos.X, enemy.Pos.Y, enemy.Pos.Z
				end
				enemy.Pos = clampToCorridor(Vector3.new(nextX, nextY, nextZ))
			end

			-- Ranged enemies fire only while engaged and still ahead of the plane.
			if behavior == "ranged" and enemy.Engaged and not enemy.Passed then
				enemy.FireTimer -= dt
				if enemy.FireTimer <= 0
					and enemy.Pos.Z < planePos.Z - ENEMY_STANDOFF_DISTANCE * 0.75 then
					enemy.FireTimer = math.max(0.1, enemy.Cfg.FireInterval or 2)
					spawnEnemyProjectile(
						enemy.Pos,
						nil,
						math.max(1, enemy.Cfg.ProjectileSpeed or 40),
						enemy.Cfg.ProjectileDamage or DEFAULT_PROJECTILE_DAMAGE,
						true,
						nil
					)
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
				if behavior == "tank" then
					enemy.Health -= 20
					if enemy.Health <= 0 then
						killEnemy(enemy, true)
					end
				else
					killEnemy(enemy, false)
				end
			end
		end

		if enemy.Alive and not enemy.Boss and (enemy.Pos - planePos).Magnitude > 300 then
			despawnEnemy(enemy)
		end

		if not enemy.Alive then
			table.remove(enemies, index)
		end
	end
end

"""
    source = replace_between(
        source,
        "local function updateEnemies(dt: number)\n",
        "local function distanceToSegment(",
        enemies_function,
        "enemy update function",
    )

    physics = """\tlocal floorY = corridor.GroundY + (corridor.PlaneGroundClearance or 2.3)
	local wasGrounded = grounded
	local braking = UserInputService.KeyboardEnabled
		and UserInputService:IsKeyDown(keyBindings.Backward)
	local throttle = if braking then 0 else moveInput.Z

	-- Steering changes the aircraft's heading and curves its existing momentum.
	local yawDelta = -moveInput.X * TURN_RATE * dt
	headingYaw = (headingYaw + yawDelta) % (math.pi * 2)
	local horizontalVelocity = Vector3.new(planeVelocity.X, 0, planeVelocity.Z)
	if horizontalVelocity.Magnitude > 0.01 and math.abs(yawDelta) > 0 then
		local rotated = CFrame.Angles(0, yawDelta, 0):VectorToWorldSpace(horizontalVelocity)
		planeVelocity = Vector3.new(rotated.X, planeVelocity.Y, rotated.Z)
	end

	local forwardDirection = CFrame.Angles(0, headingYaw, 0).LookVector
	wrongWay = forwardDirection:Dot(Vector3.new(0, 0, -1)) < -0.25

	-- W accelerates along the nose. S cuts thrust and applies stronger drag.
	local acceleration = FLIGHT_ACCELERATION * (if boosting then 1.18 else 1)
	planeVelocity += forwardDirection * (throttle * acceleration) * dt
	planeVelocity += Vector3.new(
		0,
		moveInput.Y * acceleration * VERTICAL_CONTROL_MULTIPLIER - GRAVITY,
		0
	) * dt

	local drag = if wasGrounded then GROUND_IDLE_DRAG else AIR_DRAG
	if throttle > 0.01 and wasGrounded then
		drag = GROUND_DRAG
	end
	if braking then
		drag = if wasGrounded then GROUND_IDLE_DRAG else BRAKE_DRAG
	end

	planeVelocity = Vector3.new(
		planeVelocity.X * math.exp(-drag * dt),
		planeVelocity.Y * math.exp(-VERTICAL_DRAG * dt),
		planeVelocity.Z * math.exp(-drag * dt)
	)

	horizontalVelocity = Vector3.new(planeVelocity.X, 0, planeVelocity.Z)
	local maxHorizontal = math.max(8, currentSpeed)
	if horizontalVelocity.Magnitude > maxHorizontal then
		horizontalVelocity = horizontalVelocity.Unit * maxHorizontal
		planeVelocity = Vector3.new(horizontalVelocity.X, planeVelocity.Y, horizontalVelocity.Z)
	end

	planeVelocity = Vector3.new(
		planeVelocity.X,
		math.clamp(planeVelocity.Y, -currentSpeed * MAX_VERTICAL_SPEED_FACTOR, currentSpeed * MAX_VERTICAL_SPEED_FACTOR),
		planeVelocity.Z
	)

"""
    source = replace_between(
        source,
        "\tlocal floorY = corridor.GroundY + (corridor.PlaneGroundClearance or 2.3)\n\tlocal wasGrounded = grounded\n",
        "\tlocal nextPosition = planePos + planeVelocity * dt\n",
        physics,
        "movement physics block",
    )

    rotation = """\t-- The plane follows its steered heading while retaining its vertical pitch.
	local targetBank = -moveInput.X * MAX_BANK_ANGLE
	bank = Utility.Lerp(bank, targetBank, math.clamp(dt * 4.5, 0, 1))
	local forwardDirection = CFrame.Angles(0, headingYaw, 0).LookVector
	local facingDirection = (
		forwardDirection * math.max(Vector3.new(planeVelocity.X, 0, planeVelocity.Z).Magnitude, 2)
		+ Vector3.yAxis * planeVelocity.Y
	).Unit
	local upReference = if math.abs(facingDirection:Dot(Vector3.yAxis)) > 0.97 then Vector3.zAxis else Vector3.yAxis
	planeRotation = CFrame.lookAt(planePos, planePos + facingDirection, upReference)
		* CFrame.Angles(0, 0, bank)
"""
    source = replace_between(
        source,
        "\t-- The aircraft faces its actual 3D velocity.",
        "\tif planeModel and planeModel.Parent then\n",
        rotation,
        "plane rotation block",
    )

    baseplate_helpers = """-- Hide the default Studio Baseplate locally while procedural flight scenery is active.
local hiddenBaseplate: BasePart? = nil
local previousBaseplateTransparency: number? = nil

local function hideDefaultBaseplate()
	local candidate = workspace:FindFirstChild("Baseplate")
	if candidate and candidate:IsA("BasePart") then
		hiddenBaseplate = candidate
		previousBaseplateTransparency = candidate.LocalTransparencyModifier
		candidate.LocalTransparencyModifier = 1
	end
end

local function restoreDefaultBaseplate()
	if hiddenBaseplate and hiddenBaseplate.Parent and previousBaseplateTransparency ~= nil then
		hiddenBaseplate.LocalTransparencyModifier = previousBaseplateTransparency
	end
	hiddenBaseplate = nil
	previousBaseplateTransparency = nil
end

"""
    source = replace_once(
        source,
        "-- ------------------------------------------------------------ lifecycle ----\n",
        baseplate_helpers + "-- ------------------------------------------------------------ lifecycle ----\n",
        "Baseplate helper insertion",
    )

    source = replace_once(
        source,
        "\tplaneRotation = CFrame.lookAt(planePos, planePos + Vector3.new(0, 0, -1))\n\tgrounded = true\n",
        "\tplaneRotation = CFrame.lookAt(planePos, planePos + Vector3.new(0, 0, -1))\n\theadingYaw = 0\n\twrongWay = false\n\tgrounded = true\n",
        "reset heading at run start",
    )

    source = replace_once(
        source,
        "\tbuildAllyUnits(stats.Allies or State.Data.Allies)\n\n\thideHangar()\n",
        "\tbuildAllyUnits(stats.Allies or State.Data.Allies)\n\n\thideDefaultBaseplate()\n\thideHangar()\n",
        "hide Baseplate during flight",
    )

    source = replace_once(
        source,
        "\tclearRunWorld()\n\tbossActive = false\n",
        "\tclearRunWorld()\n\trestoreDefaultBaseplate()\n\tbossActive = false\n",
        "restore Baseplate after flight",
    )

    source = replace_once(
        source,
        "\t\tfreeRevives + paidRevives,\n\t\tboosting\n\t)\n",
        "\t\tfreeRevives + paidRevives,\n\t\tboosting,\n\t\twrongWay\n\t)\n",
        "send wrong-way state to HUD",
    )

    for token in (
        "local function updateEnemies(dt: number)",
        "Engaged = false",
        "Passed = false",
        "BRAKE_DRAG",
        "headingYaw = 0",
        "hideDefaultBaseplate()",
        "restoreDefaultBaseplate()",
        "wrongWay",
    ):
        if token not in source:
            raise RuntimeError(f"Flight validation failed: missing {token!r}. No files were changed.")
    return source


def transform_ui(source: str) -> str:
    source = replace_once(
        source,
        """\thudRefs.zone = text(score, {
		Name = "Zone",
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "PAPER TOWN",
		Font = FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Sun,
	})
""",
        """\thudRefs.zone = text(score, {
		Name = "Zone",
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "PAPER TOWN",
		Font = FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Sun,
	})

	hudRefs.wrongWay = text(hud, {
		Name = "WrongWay",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.new(0, 310, 0, 34),
		Text = "WRONG WAY — TURN AROUND",
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.White,
		BackgroundColor3 = C.Coral,
		BackgroundTransparency = 0.05,
		TextStrokeTransparency = 0.5,
		Visible = false,
		ZIndex = 10,
	})
	corner(hudRefs.wrongWay, 8)
	outline(hudRefs.wrongWay, C.Ink, 2, 0.15)
""",
        "wrong-way HUD creation",
    )

    source = replace_once(
        source,
        "local function updateHud(hp, maxHp, dist, coins, gems, kills, zoneName, bossFrac, comboSteps, comboMult, boost, revives, boosting)\n",
        "local function updateHud(hp, maxHp, dist, coins, gems, kills, zoneName, bossFrac, comboSteps, comboMult, boost, revives, boosting, wrongWay)\n",
        "HUD update parameter",
    )
    source = replace_once(
        source,
        '\thudRefs.zone.Text = string.upper(zoneName or "PAPER TOWN")\n',
        '\thudRefs.zone.Text = string.upper(zoneName or "PAPER TOWN")\n\thudRefs.wrongWay.Visible = wrongWay == true\n',
        "toggle wrong-way HUD",
    )
    source = replace_once(
        source,
        """\tlocal tutorialLines = {
		"WASD moves; Q/E controls altitude",
		"Mouse aims; hold left click to spray",
		"Use the runway, then climb to take off",
		"Avoid the electrical side walls and ceiling",
	}
""",
        """\tlocal tutorialLines = {
		"W accelerates; S brakes; A/D turn",
		"Q/E controls altitude",
		"Mouse aims; hold left click to spray",
		"Use a U-turn to fly back the other way",
	}
""",
        "flight tutorial text",
    )
    source = replace_once(
        source,
        """\tlocal labels = {
		{ "Forward", "MOVE FORWARD" },
		{ "Backward", "MOVE BACKWARD" },
		{ "Left", "STRAFE LEFT" },
		{ "Right", "STRAFE RIGHT" },
		{ "Descend", "DESCEND" },
		{ "Ascend", "ASCEND" },
		{ "Fire", "KEYBOARD FIRE (MOUSE 1 ALWAYS WORKS)" },
		{ "Boost", "BOOST" },
	}
""",
        """\tlocal labels = {
		{ "Forward", "ACCELERATE" },
		{ "Backward", "BRAKE" },
		{ "Left", "TURN LEFT" },
		{ "Right", "TURN RIGHT" },
		{ "Descend", "DESCEND" },
		{ "Ascend", "ASCEND" },
		{ "Fire", "KEYBOARD FIRE (MOUSE 1 ALWAYS WORKS)" },
		{ "Boost", "BOOST" },
	}
""",
        "flight settings labels",
    )

    for token in ('Name = "WrongWay"', "WRONG WAY", '{ "Backward", "BRAKE" }'):
        if token not in source:
            raise RuntimeError(f"UI validation failed: missing {token!r}. No files were changed.")
    return source


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply the Paper Wings flight/map/enemy fixes to your local Rojo project.")
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Project root containing src/client (defaults to current folder).")
    parser.add_argument("--dry-run", action="store_true", help="Validate the changes without writing files.")
    args = parser.parse_args()

    root = args.repo.expanduser().resolve()
    flight_path = root / "src" / "client" / "Flight.luau"
    ui_path = root / "src" / "client" / "UI.luau"

    if not flight_path.is_file() or not ui_path.is_file():
        print("ERROR: Could not find src/client/Flight.luau and src/client/UI.luau.")
        print(f"Project folder checked: {root}")
        print("Run this script from the repository root, or pass --repo <project-folder>.")
        return 2

    try:
        original_flight = flight_path.read_text(encoding="utf-8")
        original_ui = ui_path.read_text(encoding="utf-8")
        updated_flight = transform_flight(original_flight)
        updated_ui = transform_ui(original_ui)
    except Exception as exc:
        print(f"ERROR: {exc}")
        return 1

    if args.dry_run:
        print("DRY RUN PASSED. Both files match the expected source and all changes validated.")
        print("No files were written.")
        return 0

    flight_backup = flight_path.with_suffix(flight_path.suffix + ".before_flight_update.bak")
    ui_backup = ui_path.with_suffix(ui_path.suffix + ".before_flight_update.bak")
    if flight_backup.exists() or ui_backup.exists():
        print("ERROR: A backup file already exists. Rename or move it before running this script again.")
        print(f"Checked: {flight_backup} and {ui_backup}")
        return 3

    try:
        shutil.copy2(flight_path, flight_backup)
        shutil.copy2(ui_path, ui_backup)
        flight_path.write_text(updated_flight, encoding="utf-8", newline="\n")
        ui_path.write_text(updated_ui, encoding="utf-8", newline="\n")
    except Exception:
        # Restore both originals if either write fails.
        if flight_backup.exists():
            shutil.copy2(flight_backup, flight_path)
        if ui_backup.exists():
            shutil.copy2(ui_backup, ui_path)
        raise

    print("SUCCESS: Updated the complete Flight.luau and UI.luau files.")
    print("Backups created:")
    print(f"  {flight_backup}")
    print(f"  {ui_backup}")
    print("Next: open the project in Roblox Studio/Rojo and test the map, W/S, A/D, wrong-way warning, and enemy behaviour.")
    print("The changes have not been runtime-tested in Roblox Studio.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
