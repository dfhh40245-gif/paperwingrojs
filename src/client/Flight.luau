-- ============================================================================
--!strict
-- Flight: client-side Paper Wings run controller.
-- Owns presentation, flight movement, streamed scenery and combat feedback.
-- The server must independently validate all rewards and run results.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Utility = require(Shared:WaitForChild("Utility"))

local PlaneBuilder = require(script.Parent:WaitForChild("PlaneBuilder"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local State = require(script.Parent:WaitForChild("State"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Flight = {}

type SpawnOptions = {
	Position: Vector3?,
	ScaleMult: number?,
	HealthMult: number?,
	Generation: number?,
}

-- ------------------------------------------------------------- tunables ----
local CHUNK_LENGTH = 200
local CHUNK_HALF = CHUNK_LENGTH / 2
local WORLD_AHEAD = 4 -- chunks generated ahead
local WORLD_BEHIND = 2 -- chunks kept behind
local MAX_CHUNK_BUILDS_PER_FRAME = 2 -- spreads scenery cost across frames
local CHUNK_RETRY_DELAY = 1 -- seconds before a failed chunk build is retried

local HANGAR_SPAWN = CFrame.new(0, 5.3, 32)
local HANGAR_PLANE_PARK = CFrame.new(-38, 7, 6) * CFrame.Angles(0, -math.pi / 2, 0)
local FLIGHT_CAMERA_OFFSET = Vector3.new(0, 9, 22)
local PLAYER_PLANE_SCALE = 1.18
local CAMERA_SHAKE_DECAY = 2.5 -- shake units lost per second
local ZONE_LIGHTING_TWEEN_TIME = 2 -- seconds to blend between zone lighting

-- Free-flight physics. Input accelerates the aircraft; velocity is never
-- teleported to a mouse-derived target position.
local FLIGHT_ACCELERATION = 92
local AIR_DRAG = 0.48
local GROUND_DRAG = 1.4
local GROUND_IDLE_DRAG = 8.5
local GRAVITY = 38
local VERTICAL_DRAG = 0.12
local MAX_VERTICAL_SPEED_FACTOR = 0.72
local MAX_BANK_ANGLE = math.rad(28)
local BOUNDARY_MARGIN = 1.8
local CRASH_GRAVITY = 62

local MAX_ACTIVE_ENEMIES = 48
local MAX_ENEMY_PROJECTILES = 60
local DEFAULT_PROJECTILE_DAMAGE = 8
local CONTACT_COOLDOWN = 1.0
local BOSS_CONTACT_COOLDOWN = 1.25

-- Ink Blobs split when the player shoots them dead. Children never split again.
local MAX_SPLIT_GENERATION = 1
local SPLIT_CHILD_COUNT = 2
local SPLIT_HEALTH_MULT = 0.45
local SPLIT_SCALE_MULT = 0.55

-- Boss encounter. The boss paces the plane at a standoff distance instead of
-- drifting past it, strafes, and fires aimed volleys.
local BOSS_SPAWN_STANDOFF = 140
local BOSS_ENRAGE_RATIO = 0.4
local BOSS_FIRE_INTERVAL = 2.6
local BOSS_ENRAGED_FIRE_INTERVAL = 1.4
local BOSS_VOLLEY = 3
local BOSS_ENRAGED_VOLLEY = 5
local BOSS_VOLLEY_SPREAD = math.rad(9)
local BOSS_PROJECTILE_SPEED = 60

-- The default PlayerModule controls (mobile thumbstick, jump button) overlap
-- flight input. Set this to false if another system manages them.
local DISABLE_DEFAULT_CONTROLS_DURING_RUN = true

local COIN_BASE_ROTATION = CFrame.Angles(0, math.rad(90), 0)

-- Used only if GameConfig has neither the equipped weapon nor "Dart".
local FALLBACK_WEAPON = {
	Color = Color3.fromRGB(255, 255, 255),
	FireInterval = 0.25,
	DamageMult = 1,
	RangeMult = 1,
}

-- The default camera follows the character's HumanoidRootPart. We park the
-- (hidden) avatar at the focus point and use CameraOffset to frame the shot.
local function setCameraTarget(rootCFrame: CFrame, offset: Vector3)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
		root.CFrame = rootCFrame
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = offset
	end
end

-- Run state
local running = false
local planeModel: Model?
local hangar: Model?
local hangarThemeId: string? = nil
local hangarEggs: { any } = {}
local hangarPlaneBase: CFrame? = nil
local allyUnits: { any } = {} -- { Id, Model, Timer } per equipped ally
local sceneryFolder: Folder?
local enemiesFolder: Folder?
local coinsFolder: Folder?
local projectilesFolder: Folder?
local atmosphere: Atmosphere?
local sky: Sky?

local planePos = Vector3.new(0, GameConfig.Corridor.PlaneGroundClearance or 2.3, 0)
local planeVelocity = Vector3.zero
local planeRotation = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1))
local bank = 0
local grounded = true
local crashing = false
local crashElapsed = 0
local crashReason = "boundary"
local distance = 0
local health = 100
local maxHealth = 100
local speed = 56
local damage = 10
local kills = 0
local coinsCollected = 0
local gemsCollected = 0
local runTime = 0
local lastFire = 0
local lastSpawn = 0
local lastCoinSpawn = 0
local lastMilestone = 0
local cameraShake = 0
local bossRecord: any? = nil
local bossActive = false
local beatenBossZones: { [string]: boolean } = {}
local bossSpawnedZones: { [string]: boolean } = {} -- zones whose boss was attempted this run
local zone = GameConfig.Zones[1]
local chunks: { [number]: Model } = {}
local chunkRetryAt: { [number]: number } = {}
local enemies: { any } = {}
local coins: { any } = {}
local projectiles: { any } = {}
local stats: any = nil
local runWeapon: any = FALLBACK_WEAPON
local runDamageMultiplier = 1

-- Run modifiers resolved once per run from State.Stats.
local shieldMult = 1
local magnetRadius = GameConfig.CoinPickupRadius
local freeRevives = 0
local paidRevives = 0
local invulnerableUntil = 0

-- Combo: kills in quick succession raise the payout multiplier.
local comboSteps = 0
local comboTimer = 0
local maxCombo = 0

-- Boost: charged by kills, spent for a burst of speed.
local boostCharge = 0
local boosting = false
local boostHeld = false
local touchBoost = false

local connection: RBXScriptConnection?
local characterAddedConnection: RBXScriptConnection?
local inputBeganConnection: RBXScriptConnection?
local inputChangedConnection: RBXScriptConnection?
local inputEndedConnection: RBXScriptConnection?
local focusReleasedConnection: RBXScriptConnection?
local characterDescendantConnection: RBXScriptConnection?
local hangarIdleConnection: RBXScriptConnection?
local initialized = false

local keyBindings: { [string]: Enum.KeyCode } = {
	Forward = Enum.KeyCode.W,
	Backward = Enum.KeyCode.S,
	Left = Enum.KeyCode.A,
	Right = Enum.KeyCode.D,
	Descend = Enum.KeyCode.Q,
	Ascend = Enum.KeyCode.E,
	Fire = Enum.KeyCode.Space, -- optional keyboard fire; left mouse remains primary
	Boost = Enum.KeyCode.LeftShift,
}
local fireHeld = false
local fireMode: string? = nil
local fireScreenPos: Vector2? = nil
local fireSources: { [string]: boolean } = { touch = false, mouse = false, keyboard = false }
local activeTouch: InputObject? = nil
local lastTouch: Vector2? = nil
local lastRunUpdate = 0
local characterHidden = false
local controlsDisabledByFlight = false
local characterVisuals: { [Instance]: any } = setmetatable({}, { __mode = "k" })
local lightingTweens: { Tween } = {}
local originalLighting: any = nil
local originalAtmosphere: Atmosphere? = nil
local originalSky: Sky? = nil

-- -------------------------------------------------------------- utilities ----
local function activeCamera(): Camera?
	camera = workspace.CurrentCamera or camera
	return camera
end

local function screenCenterPosition(): Vector2
	local currentCamera = activeCamera()
	if not currentCamera then
		return Vector2.zero
	end
	local inset = GuiService:GetGuiInset()
	local viewport = currentCamera.ViewportSize
	return Vector2.new(viewport.X * 0.5 + inset.X, viewport.Y * 0.5 + inset.Y)
end

local function bossHealthRatio(): number
	if bossActive and bossRecord and bossRecord.MaxHealth and bossRecord.MaxHealth > 0 then
		return math.clamp(bossRecord.Health / bossRecord.MaxHealth, 0, 1)
	end
	return 0
end

local function comboMultiplier(): number
	return 1 + math.min(GameConfig.Combo.MaxBonus, comboSteps * GameConfig.Combo.BonusPerKill)
end

-- The UI does not need a Heartbeat event every frame. This throttle keeps HUD
-- updates responsive without forcing expensive UI work at 60+ calls per second.
local function emitRunUpdate(force: boolean?)
	local now = os.clock()
	if not force and now - lastRunUpdate < 0.1 then
		return
	end
	lastRunUpdate = now
	State.EmitRunUpdate(
		health,
		maxHealth,
		distance,
		coinsCollected,
		gemsCollected,
		kills,
		zone.Name,
		bossHealthRatio(),
		comboSteps,
		comboMultiplier(),
		boostCharge,
		freeRevives + paidRevives,
		boosting
	)
end

-- Runs a builder that lives in another module without letting its errors take
-- down the Heartbeat loop. Returns nil (after warning) on failure.
local function safeCall(label: string, fn: any, ...: any): any
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("Flight: %s failed: %s", label, tostring(result)))
		return nil
	end
	return result
end

-- A missing or misbehaving remote must not abort run start/end half-way.
local function fireServer(remoteKey: any, ...: any)
	local args = table.pack(...)
	local ok, err = pcall(function()
		Remotes.Get(remoteKey):FireServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn(string.format("Flight: could not fire remote %s: %s", tostring(remoteKey), tostring(err)))
	end
end

-- Disables Roblox's default movement UI during a run and re-enables it only if
-- this script was the one that disabled it.
local function setDefaultControlsEnabled(enabled: boolean)
	if not DISABLE_DEFAULT_CONTROLS_DURING_RUN then
		return
	end
	if enabled and not controlsDisabledByFlight then
		return
	end
	if not enabled and controlsDisabledByFlight then
		return
	end

	local ok, err = pcall(function()
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local controls = (require(moduleScript) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
			controlsDisabledByFlight = not enabled
		end
	end)
	if not ok then
		warn("Flight: could not toggle default controls: " .. tostring(err))
	end
end


local function rememberLightingDefaults()
	if originalLighting then
		return
	end

	originalAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere") :: Atmosphere?
	originalSky = Lighting:FindFirstChildOfClass("Sky") :: Sky?
	originalLighting = {
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		Atmosphere = if originalAtmosphere then {
			Color = originalAtmosphere.Color,
			Density = originalAtmosphere.Density,
			Offset = originalAtmosphere.Offset,
			Decay = originalAtmosphere.Decay,
			Glare = originalAtmosphere.Glare,
			Haze = originalAtmosphere.Haze,
		} else nil,
		Sky = if originalSky then {
			SkyboxBk = originalSky.SkyboxBk,
			SkyboxDn = originalSky.SkyboxDn,
			SkyboxFt = originalSky.SkyboxFt,
			SkyboxLf = originalSky.SkyboxLf,
			SkyboxRt = originalSky.SkyboxRt,
			SkyboxUp = originalSky.SkyboxUp,
		} else nil,
	}
end

local function restoreLightingDefaults()
	if not originalLighting then
		return
	end

	Lighting.FogColor = originalLighting.FogColor
	Lighting.FogEnd = originalLighting.FogEnd
	Lighting.FogStart = originalLighting.FogStart
	Lighting.Ambient = originalLighting.Ambient
	Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	Lighting.Brightness = originalLighting.Brightness

	if originalAtmosphere and originalAtmosphere.Parent then
		local data = originalLighting.Atmosphere
		if data then
			originalAtmosphere.Color = data.Color
			originalAtmosphere.Density = data.Density
			originalAtmosphere.Offset = data.Offset
			originalAtmosphere.Decay = data.Decay
			originalAtmosphere.Glare = data.Glare
			originalAtmosphere.Haze = data.Haze
		end
	elseif atmosphere then
		atmosphere:Destroy()
		atmosphere = nil
	end

	if originalSky and originalSky.Parent then
		local data = originalLighting.Sky
		if data then
			originalSky.SkyboxBk = data.SkyboxBk
			originalSky.SkyboxDn = data.SkyboxDn
			originalSky.SkyboxFt = data.SkyboxFt
			originalSky.SkyboxLf = data.SkyboxLf
			originalSky.SkyboxRt = data.SkyboxRt
			originalSky.SkyboxUp = data.SkyboxUp
		end
	elseif sky then
		sky:Destroy()
		sky = nil
	end
end

-- ------------------------------------------------------------- lighting ----
local function ensureAtmosphere()
	if not atmosphere then
		atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") :: Atmosphere?
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Parent = Lighting
		end
	end
	if not sky then
		sky = Lighting:FindFirstChildOfClass("Sky") :: Sky?
		if not sky then
			sky = Instance.new("Sky")
			sky.Parent = Lighting
		end
	end
end

local function cancelLightingTweens()
	for _, tween in ipairs(lightingTweens) do
		tween:Cancel()
	end
	table.clear(lightingTweens)
end

local function tweenProperties(target: Instance, goals: { [string]: any }, duration: number)
	local tween = TweenService:Create(
		target,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goals
	)
	table.insert(lightingTweens, tween)
	tween:Play()
end

-- Zone changes blend fog/ambient/atmosphere instead of snapping. The first
-- zone of a run is applied instantly so the player never sees hangar lighting.
local function applyZoneLighting(z: any, instant: boolean?)
	cancelLightingTweens()
	Lighting.Brightness = 2

	if instant then
		Lighting.FogColor = z.FogColor
		Lighting.FogEnd = z.FogEnd
		Lighting.FogStart = z.FogEnd * 0.15
		Lighting.Ambient = z.Ambient
		Lighting.OutdoorAmbient = z.Ambient
		if atmosphere then
			atmosphere.Color = z.SkyBottom
			atmosphere.Density = 0.32
		end
	else
		tweenProperties(Lighting, {
			FogColor = z.FogColor,
			FogEnd = z.FogEnd,
			FogStart = z.FogEnd * 0.15,
			Ambient = z.Ambient,
			OutdoorAmbient = z.Ambient,
		}, ZONE_LIGHTING_TWEEN_TIME)
		if atmosphere then
			tweenProperties(atmosphere, {
				Color = z.SkyBottom,
				Density = 0.32,
			}, ZONE_LIGHTING_TWEEN_TIME)
		end
	end

	if sky then
		sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
		sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
		sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
		sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
		sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
		sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	end
end

-- ------------------------------------------------------ character visuals ----
-- The plane represents the player during a run. Each part's original
-- transparency and collision state is remembered so accessories and
-- intentionally invisible parts are restored exactly on return to the hangar.
-- (LocalTransparencyModifier is owned by the camera scripts, so it is left alone.)
local function applyPartVisibility(part: BasePart, hidden: boolean)
	if hidden then
		if not characterVisuals[part] then
			characterVisuals[part] = {
				Transparency = part.Transparency,
				CanCollide = part.CanCollide,
			}
		end
		part.Transparency = 1
		part.CanCollide = false
	else
		local original = characterVisuals[part]
		if original then
			part.Transparency = original.Transparency
			part.CanCollide = original.CanCollide
			characterVisuals[part] = nil
		end
	end
end

local function applyCharacterVisibility(character: Model, hidden: boolean)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			applyPartVisibility(descendant, hidden)
		end
	end
end

-- ---------------------------------------------------------------- input ----
local function readInput(): Vector3
	local x, y, forward = 0, 0, 0
	if UserInputService.KeyboardEnabled then
		if UserInputService:IsKeyDown(keyBindings.Forward) then forward += 1 end
		if UserInputService:IsKeyDown(keyBindings.Backward) then forward -= 1 end
		if UserInputService:IsKeyDown(keyBindings.Left) then x -= 1 end
		if UserInputService:IsKeyDown(keyBindings.Right) then x += 1 end
		if UserInputService:IsKeyDown(keyBindings.Ascend) then y += 1 end
		if UserInputService:IsKeyDown(keyBindings.Descend) then y -= 1 end
	end

	-- Roblox world forward for this project is -Z. Mouse position is deliberately
	-- absent here: it is reserved exclusively for aiming.
	local movement = Vector3.new(x, y, -forward)
	if movement.Magnitude > 1 then
		movement = movement.Unit
	end
	return movement
end

-- Fire intent is tracked per source so releasing one input (for example the
-- mouse) does not cancel another that is still held (for example Space).
local function refreshFireState()
	if fireSources.touch then
		fireMode = "touch"
	elseif fireSources.mouse then
		fireMode = "mouse"
	elseif fireSources.keyboard then
		fireMode = "keyboard"
	else
		fireMode = nil
	end

	fireHeld = fireMode ~= nil
	if not fireHeld then
		fireScreenPos = nil
	end
end

local function resetPointerInput()
	fireSources.touch = false
	fireSources.mouse = false
	fireSources.keyboard = false
	activeTouch = nil
	lastTouch = nil
	refreshFireState()
end

-- --------------------------------------------------------------- hangar ----
local function hideCharacter()
	characterHidden = true
	local character = player.Character
	if not character then
		return
	end

	applyCharacterVisibility(character, true)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
end

-- Restores visuals only. Positioning is owned by setCameraTarget, and
-- WalkSpeed is deliberately untouched so other systems' speed changes survive.
local function showCharacter()
	characterHidden = false
	local character = player.Character
	if not character then
		return
	end
	applyCharacterVisibility(character, false)
end

local function hidePartIfNeeded(instance: Instance)
	if characterHidden and instance.Parent and instance:IsA("BasePart") then
		applyPartVisibility(instance, true)
	end
end

-- Handles one added part at a time. Rescanning the whole character for every
-- added accessory part was quadratic during spawn.
local function watchCharacter(character: Model)
	characterVisuals = setmetatable({}, { __mode = "k" })
	if characterDescendantConnection then
		characterDescendantConnection:Disconnect()
		characterDescendantConnection = nil
	end

	characterDescendantConnection = character.DescendantAdded:Connect(function(descendant)
		if characterHidden then
			task.defer(hidePartIfNeeded, descendant)
		end
	end)
end

local function buildHangar(requestedTheme: string?)
	local themeId = requestedTheme or (State.Data and State.Data.EquippedHangar) or "Cardboard"
	local theme = GameConfig.Hangars[themeId] or GameConfig.Hangars.Cardboard
	if hangar and hangarThemeId == themeId then
		return
	end
	if hangar then
		hangar:Destroy()
	end
	hangarThemeId = themeId
	hangarEggs = {}
	hangar = Instance.new("Model")
	hangar.Name = "Hangar"

	local accent = theme.Accent
	local wall = theme.Wall
	local trim = theme.Trim

	local function p(size, cf, color, material, transparency, canCollide)
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = cf
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Transparency = transparency or 0
		part.Anchored = true
		part.CanCollide = canCollide ~= false
		part.Parent = hangar
		return part
	end

	local function cylinder(diameter, height, cf, color, material, transparency)
		local part = p(Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, transparency)
		part.Shape = Enum.PartType.Cylinder
		return part
	end

	-- Room shell: 180 x 170, high walls and no jump so nobody can leave.
	p(Vector3.new(180, 2, 170), CFrame.new(0, 2, 0), trim)
	p(Vector3.new(160, 0.3, 112), CFrame.new(0, 3.08, 10), theme.Floor)
	p(Vector3.new(3, 66, 172), CFrame.new(-89.5, 35, 0), wall)
	p(Vector3.new(3, 66, 172), CFrame.new(89.5, 35, 0), wall)
	p(Vector3.new(183, 66, 3), CFrame.new(0, 35, -85.5), wall)
	p(Vector3.new(183, 66, 3), CFrame.new(0, 35, 85.5), wall)

	-- Neon wall strips give every hangar a distinct silhouette.
	p(Vector3.new(0.4, 1.2, 150), CFrame.new(-89.2, 9, 0), accent, Enum.Material.Neon)
	p(Vector3.new(0.4, 1.2, 150), CFrame.new(89.2, 9, 0), accent, Enum.Material.Neon)
	p(Vector3.new(176, 0.4, 0.4), CFrame.new(0, 52, -84.8), accent, Enum.Material.Neon)

	-- Exposed roof trusses (the sky stays open above them).
	for i = -5, 5 do
		p(Vector3.new(1.4, 1.4, 150), CFrame.new(i * 16, 55, 0), trim)
	end
	p(Vector3.new(176, 1, 1), CFrame.new(0, 58, -46), trim)
	p(Vector3.new(176, 1, 1), CFrame.new(0, 58, 46), trim)

	-- Feature banners on the back wall double as real-world hangar switchers.
	local bannerIndex = 0
	for _, key in ipairs(GameConfig.HangarOrder) do
		local hangarKey = key
		bannerIndex += 1
		local hangarCfg = GameConfig.Hangars[hangarKey]
		local x = -47 + (bannerIndex - 1) * 19
		p(Vector3.new(14.5, 19.5, 0.5), CFrame.new(x, 33, -83.8), trim, Enum.Material.SmoothPlastic, 0, false)
		local banner = p(Vector3.new(12.5, 17.5, 0.3), CFrame.new(x, 33, -83.45), hangarCfg.Accent, Enum.Material.SmoothPlastic, 0, false)
		if hangarKey == themeId then
			p(Vector3.new(2, 18.5, 0.2), CFrame.new(x - 6.8, 33, -83.4), Color3.new(1, 1, 1), Enum.Material.Neon, 0, false)
			p(Vector3.new(2, 18.5, 0.2), CFrame.new(x + 6.8, 33, -83.4), Color3.new(1, 1, 1), Enum.Material.Neon, 0, false)
		end
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.CanvasSize = Vector2.new(250, 350)
		surface.LightInfluence = 0
		surface.Parent = banner
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = string.upper(hangarCfg.Name)
		label.TextColor3 = Color3.fromRGB(30, 34, 46)
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = surface
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if hangarKey == themeId then "HOME" else "SET HOME"
		prompt.ObjectText = hangarCfg.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.2
		prompt.Parent = banner
		prompt.Triggered:Connect(function()
			if running then
				return
			end
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "hangar", Id = hangarKey })
		end)
	end

	-- Plane display pad on the left; the centre belongs to the hatchery.
	p(Vector3.new(30, 1.4, 30), CFrame.new(-54, 3.9, -4), trim)
	p(Vector3.new(26, 1, 26), CFrame.new(-54, 4.8, -4), theme.Floor)
	p(Vector3.new(30, 1, 1.6), CFrame.new(-54, 8.5, 10.8), accent, Enum.Material.Neon, 0, false)
	p(Vector3.new(1.6, 1, 11), CFrame.new(-68.4, 8.5, 5.2), accent, Enum.Material.Neon, 0, false)
	local planeSign = p(Vector3.new(11, 3.5, 0.4), CFrame.new(-54, 12, 9.6), trim)
	local signSurface = Instance.new("SurfaceGui")
	signSurface.Face = Enum.NormalId.Front
	signSurface.CanvasSize = Vector2.new(300, 100)
	signSurface.Parent = planeSign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.Text = "YOUR PLANE"
	signLabel.TextColor3 = accent
	signLabel.TextScaled = true
	signLabel.Parent = signSurface

	-- Central hatchery ring.
	cylinder(46, 0.5, CFrame.new(0, 3.2, -18), accent, Enum.Material.Neon, 0.15)
	cylinder(41, 0.45, CFrame.new(0, 3.35, -18), theme.Floor, Enum.Material.SmoothPlastic, 0)
	cylinder(7, 1.2, CFrame.new(0, 3.8, -18), trim)
	local beacon = p(Vector3.new(2.4, 12, 2.4), CFrame.new(0, 10, -18), theme.Floor)
	local orb = p(Vector3.new(5, 5, 5), CFrame.new(0, 17, -18), accent, Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	p(Vector3.new(10, 0.7, 10), CFrame.new(0, 5, -18), accent, Enum.Material.Neon, 0.3)
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = accent
	beaconLight.Brightness = 2
	beaconLight.Range = 34
	beaconLight.Parent = orb
	beacon.Name = "Beacon"
	orb.Name = "BeaconOrb"

	local function makeEggPod(eggId: string, position: Vector3, featured: boolean)
		local eggCfg = GameConfig.Eggs[eggId]
		if not eggCfg then
			return
		end
		local pod = Instance.new("Model")
		pod.Name = "EggPod_" .. eggId
		pod.Parent = hangar
		local base = cylinder(if featured then 12 else 9, 1.2, CFrame.new(position + Vector3.new(0, 0.6, 0)), trim)
		base.Parent = pod
		local ring = cylinder(if featured then 11 else 8, 0.4, CFrame.new(position + Vector3.new(0, 1.25, 0)), eggCfg.Color, Enum.Material.Neon, 0.1)
		ring.Parent = pod
		local egg = Instance.new("Part")
		egg.Name = "Egg"
		egg.Size = if featured then Vector3.new(6.5, 8.5, 6.5) else Vector3.new(5, 6.5, 5)
		egg.CFrame = CFrame.new(position + Vector3.new(0, if featured then 5.8 else 4.8, 0))
		egg.Color = eggCfg.Color
		egg.Material = Enum.Material.SmoothPlastic
		egg.Shape = Enum.PartType.Ball
		egg.Anchored = true
		egg.CanCollide = false
		egg.Parent = pod
		local shine = Instance.new("Part")
		shine.Name = "Shine"
		shine.Size = Vector3.new(1.4, 3.4, 1.4)
		shine.CFrame = egg.CFrame * CFrame.new(-1.8, 1.5, -1.5) * CFrame.Angles(0.3, 0, 0.35)
		shine.Color = Color3.new(1, 1, 1)
		shine.Material = Enum.Material.Neon
		shine.Transparency = 0.25
		shine.Anchored = true
		shine.CanCollide = false
		shine.Parent = pod

		local labelGui = Instance.new("BillboardGui")
		labelGui.Size = UDim2.fromOffset(if featured then 270 else 210, 54)
		labelGui.StudsOffset = Vector3.new(0, if featured then 6.4 else 5.2, 0)
		labelGui.AlwaysOnTop = false
		labelGui.MaxDistance = 48
		labelGui.Parent = egg
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
		label.BackgroundTransparency = 0.2
		label.Text = string.format("%s  •  %d GEMS", string.upper(eggCfg.Name), eggCfg.Cost)
		label.TextColor3 = eggCfg.Color
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Parent = labelGui
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = label

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "HATCH"
		prompt.ObjectText = string.format("%s • %d gems", eggCfg.Name, eggCfg.Cost)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0.25
		prompt.RequiresLineOfSight = false
		prompt.Parent = egg
		prompt.Triggered:Connect(function()
			if running then
				return
			end
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "egg", Id = eggId })
			Effects.Burst(egg.Position, eggCfg.Color, 20, 16)
			Effects.Play("Coin", nil, 0.35)
			prompt.Enabled = false
			local original = egg.Size
			TweenService:Create(egg, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = original * 1.28,
			}):Play()
			task.delay(0.3, function()
				if egg.Parent then
					TweenService:Create(egg, TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
						Size = original,
					}):Play()
				end
			end)
			task.delay(0.9, function()
				if prompt.Parent then
					prompt.Enabled = true
				end
			end)
		end)

		table.insert(hangarEggs, {
			Egg = egg,
			Base = egg.CFrame,
			Phase = math.random() * math.pi * 2,
			Featured = featured,
		})
	end

	makeEggPod(theme.Egg or "Common", Vector3.new(0, 3, -30), true)
	makeEggPod("Common", Vector3.new(-18, 3, -22), false)
	makeEggPod("Rare", Vector3.new(18, 3, -22), false)

	-- Lounge corner: couch, table, rug and lamp.
	p(Vector3.new(44, 0.2, 32), CFrame.new(56, 3.14, 16), trim)
	p(Vector3.new(24, 3.2, 9), CFrame.new(56, 4.8, 18), theme.Floor)
	p(Vector3.new(24, 9, 2.4), CFrame.new(56, 7.8, 22.2), theme.Floor)
	p(Vector3.new(3, 6, 9), CFrame.new(44.5, 6, 18), theme.Floor)
	p(Vector3.new(3, 6, 9), CFrame.new(67.5, 6, 18), theme.Floor)
	p(Vector3.new(10, 1.1, 7), CFrame.new(56, 5.4, 7), trim)
	p(Vector3.new(5.5, 0.4, 5.5), CFrame.new(56, 6.2, 7), accent, Enum.Material.Neon, 0.35, false)
	for i = 0, 2 do
		p(Vector3.new(7, 2, 6), CFrame.new(51 + i * 5, 5.8, 18), wall)
	end
	local lampPole = p(Vector3.new(0.7, 14, 0.7), CFrame.new(75, 10, 25), trim)
	local lampShade = p(Vector3.new(6, 4, 6), CFrame.new(75, 17, 25), accent, Enum.Material.Neon, 0.15)
	lampShade.Shape = Enum.PartType.Ball
	local lampLight = Instance.new("PointLight")
	lampLight.Color = accent
	lampLight.Brightness = 2
	lampLight.Range = 30
	lampLight.Parent = lampShade
	lampPole.Name = "LampPole"

	-- Lockers and trophy case.
	for i = 0, 3 do
		p(Vector3.new(9, 17, 6), CFrame.new(-78 + i * 10, 11.5, 48), trim)
		p(Vector3.new(0.4, 1.2, 1.2), CFrame.new(-78 + i * 10, 11.5, 44.8), accent, Enum.Material.Neon, 0, false)
	end
	p(Vector3.new(24, 1.2, 8), CFrame.new(68, 3.8, -62), trim)
	p(Vector3.new(24, 13, 1.4), CFrame.new(68, 10, -66), trim)
	for i = -1, 1 do
		local trophy = p(Vector3.new(2.6, 4 + (i + 1) * 1.2, 2.6), CFrame.new(68 + i * 6, 6.6, -62), accent, Enum.Material.Neon, 0.1, false)
		trophy.Name = "Trophy"
	end

	-- Big windows on the side walls let the theme sky in.
	for _, side in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			p(Vector3.new(0.35, 18, 20), CFrame.new(side * 87.9, 30, i * 26), theme.Sky, Enum.Material.Glass, 0.35, false)
			p(Vector3.new(0.5, 1, 21), CFrame.new(side * 87.7, 21, i * 26), trim, Enum.Material.SmoothPlastic, 0, false)
			p(Vector3.new(0.5, 1, 21), CFrame.new(side * 87.7, 39, i * 26), trim, Enum.Material.SmoothPlastic, 0, false)
		end
	end

	-- Theme-specific set dressing.
	if themeId == "Ember" then
		for _, x in ipairs({ -70, 70 }) do
			for _, z in ipairs({ -46, 34 }) do
				local brazier = cylinder(4, 3, CFrame.new(x, 5.5, z), trim)
				local fire = p(Vector3.new(3, 2, 3), CFrame.new(x, 7.5, z), accent, Enum.Material.Neon, 0.05, false)
				fire.Shape = Enum.PartType.Ball
				local light = Instance.new("PointLight")
				light.Color = accent
				light.Brightness = 2.4
				light.Range = 28
				light.Parent = fire
				local emitter = Instance.new("ParticleEmitter")
				emitter.Color = ColorSequence.new(accent, Color3.fromRGB(255, 220, 120))
				emitter.Rate = 10
				emitter.Lifetime = NumberRange.new(0.4, 0.9)
				emitter.Speed = NumberRange.new(2, 5)
				emitter.Size = NumberSequence.new(0.5, 0)
				emitter.Parent = fire
				brazier.Name = "Brazier"
			end
		end
	elseif themeId == "Flash" then
		for i = -2, 2 do
			p(Vector3.new(18, 0.5, 0.5), CFrame.new(0, 49, i * 24), accent, Enum.Material.Neon, 0, false)
		end
		p(Vector3.new(2, 18, 1), CFrame.new(-60, 27, -83), Color3.new(1, 1, 1), Enum.Material.Neon, 0, false).CFrame =
			CFrame.new(-60, 27, -83) * CFrame.Angles(0, 0, math.rad(28))
	elseif themeId == "Tide" then
		p(Vector3.new(34, 0.2, 24), CFrame.new(56, 3.1, -34), Color3.fromRGB(80, 200, 220), Enum.Material.Glass, 0.3, false)
		p(Vector3.new(36, 1.2, 1.2), CFrame.new(56, 3.4, -46), trim)
		p(Vector3.new(1.2, 1.2, 24), CFrame.new(39, 3.4, -34), trim)
		for i = 1, 5 do
			local coral = p(Vector3.new(1.4, 3 + (i % 3) * 2, 1.4), CFrame.new(46 + i * 4, 4.5, -40 + (i % 3) * 5), Color3.fromRGB(255, 130, 160), Enum.Material.Neon, 0.15, false)
			coral.CFrame *= CFrame.Angles(math.rad(12), 0, math.rad(-12))
		end
	elseif themeId == "Void" then
		for i = 1, 12 do
			local angle = i / 12 * math.pi * 2
			local radius = 32 + (i % 3) * 9
			local star = p(Vector3.new(0.6, 0.6, 0.6), CFrame.new(math.cos(angle) * radius, 3.2, -34 + math.sin(angle) * radius), accent, Enum.Material.Neon, 0, false)
			star.Name = "Star"
		end
		for i = 1, 4 do
			local orbPart = p(Vector3.new(3, 3, 3), CFrame.new(-64 + i * 30, 20 + (i % 2) * 8, -46), accent, Enum.Material.Neon, 0.1, false)
			orbPart.Shape = Enum.PartType.Ball
			local light = Instance.new("PointLight")
			light.Color = accent
			light.Brightness = 1.4
			light.Range = 22
			light.Parent = orbPart
		end
	elseif themeId == "Umbra" then
		for i = -1, 1 do
			p(Vector3.new(4, 24, 4), CFrame.new(i * 16, 15, -75), trim).CFrame *= CFrame.Angles(0, 0, math.rad(i * 6))
			p(Vector3.new(4.5, 1, 4), CFrame.new(i * 16, 27.5, -75), accent, Enum.Material.Neon, 0, false)
		end
	else
		for i = 1, 8 do
			local size = 6 + (i % 3) * 3
			local box = p(Vector3.new(size, size, size), CFrame.new(-72 + (i % 4) * 7, 3 + size / 2, 56 - math.floor(i / 4) * 9), Color3.fromRGB(176, 136, 92))
			box.CFrame *= CFrame.Angles(0, math.rad(i * 13), 0)
			box.Name = "CardboardBox"
		end
		local crane = p(Vector3.new(11, 1.2, 11), CFrame.new(0, 44, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 0, false)
		crane.CFrame *= CFrame.Angles(math.rad(10), math.rad(20), math.rad(-8))
		crane.Name = "HangingCrane"
	end

	-- Plants (all themes need a little life).
	for _, spot in ipairs({ { -78, 3, -70 }, { 78, 3, 72 }, { -30, 3, 62 } }) do
		cylinder(6, 3, CFrame.new(spot[1], spot[2] + 1.5, spot[3]), trim)
		local leaves = p(Vector3.new(7, 8, 7), CFrame.new(spot[1], spot[2] + 7, spot[3]), Color3.fromRGB(96, 156, 84), Enum.Material.SmoothPlastic, 0, false)
		leaves.Shape = Enum.PartType.Ball
	end

	hangar.Parent = workspace
end

local function buildMenuPlane()
	if planeModel then
		planeModel:Destroy()
		planeModel = nil
	end

	local planeId = (State.Data and State.Data.EquippedPlane) or "Classic"
	local model = PlaneBuilder.BuildPlane(planeId)
	if not model then
		warn("Flight: PlaneBuilder could not build plane '" .. tostring(planeId) .. "'.")
		return
	end

	planeModel = model
	planeModel:ScaleTo(PLAYER_PLANE_SCALE)
	planeModel.Parent = workspace
	hangarPlaneBase = HANGAR_PLANE_PARK
	planeModel:PivotTo(HANGAR_PLANE_PARK)
end

-- Allies are stored as records so a model that fails to build can never shift
-- the remaining allies onto the wrong config (the old parallel arrays could).
local function destroyAllyUnits()
	for _, unit in ipairs(allyUnits) do
		if unit.Model then
			unit.Model:Destroy()
		end
	end
	table.clear(allyUnits)
end

local function buildAllyUnits(allyIds: any)
	destroyAllyUnits()
	if type(allyIds) ~= "table" then
		return
	end

	for _, allyId in ipairs(allyIds) do
		local model = safeCall("PlaneBuilder.BuildAlly", PlaneBuilder.BuildAlly, allyId)
		if model then
			model.Parent = workspace
			local cfg = GameConfig.Allies[allyId]
			table.insert(allyUnits, {
				Id = allyId,
				Model = model,
				-- Staggered start so allies do not all fire on the same frame.
				Timer = if cfg then math.random() * math.max(0.1, cfg.FireInterval or 1) else 0,
			})
		end
	end
end

local function placeAlliesInHangar()
	local spots = {
		Vector3.new(-40, 6, 4),
		Vector3.new(-34, 6, 12),
		Vector3.new(-44, 6, 14),
		Vector3.new(-30, 6, 2),
		Vector3.new(-38, 6, -2),
	}
	for index, unit in ipairs(allyUnits) do
		local spot = spots[((index - 1) % #spots) + 1] or spots[1]
		local base = CFrame.lookAt(spot, Vector3.new(0, 6, -16))
		unit.HangarBase = base
		unit.HangarPhase = index * 1.7
		if unit.Model then
			unit.Model:PivotTo(base)
		end
	end
end

local function buildMenuAllies()
	buildAllyUnits(State.Data and State.Data.Allies)
	placeAlliesInHangar()
end

local function applyHangarLighting(theme: any)
	Lighting.Brightness = 2.2
	Lighting.Ambient = theme.Wall:Lerp(Color3.new(1, 1, 1), 0.55)
	Lighting.OutdoorAmbient = theme.Sky:Lerp(Color3.new(1, 1, 1), 0.35)
end

local function placeCharacterInHangar()
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	showCharacter()
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = HANGAR_SPAWN
	humanoid.WalkSpeed = 16
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = true
	humanoid.CameraOffset = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local currentCamera = activeCamera()
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
		currentCamera.CameraSubject = humanoid
		currentCamera.FieldOfView = 70
	end
end

local function showHangar(keepCharacterPosition: boolean?)
	local themeId = (State.Data and State.Data.EquippedHangar) or "Cardboard"
	buildHangar(themeId)
	local theme = GameConfig.Hangars[themeId] or GameConfig.Hangars.Cardboard
	if hangar then
		hangar.Parent = workspace
	end
	hangarPlaneBase = HANGAR_PLANE_PARK
	if planeModel then
		planeModel:PivotTo(HANGAR_PLANE_PARK)
	end
	placeAlliesInHangar()

	cancelLightingTweens()
	restoreLightingDefaults()
	applyHangarLighting(theme)
	if keepCharacterPosition then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	else
		placeCharacterInHangar()
	end
end

local function hideHangar()
	if hangar then
		hangar.Parent = nil
	end
end

-- Subtle life in the home: parked planes bob, allies breathe, eggs float.
local function updateHangarIdle()
	if running or not hangar or not hangar.Parent then
		return
	end
	local now = os.clock()
	for _, unit in ipairs(allyUnits) do
		if unit.Model and unit.HangarBase then
			local phase = unit.HangarPhase or 0
			local bob = math.sin(now * 1.6 + phase) * 0.5
			local roll = math.rad(math.sin(now * 1.2 + phase) * 3)
			unit.Model:PivotTo(unit.HangarBase * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, roll))
		end
	end
	for _, eggRecord in ipairs(hangarEggs) do
		if eggRecord.Egg and eggRecord.Egg.Parent then
			local bob = math.sin(now * 1.4 + eggRecord.Phase) * 0.35
			eggRecord.Egg.CFrame = eggRecord.Base * CFrame.new(0, bob, 0)
		end
	end
	if planeModel and hangarPlaneBase then
		planeModel:PivotTo(hangarPlaneBase * CFrame.new(0, math.sin(now * 1.1) * 0.35, 0))
	end
end

-- --------------------------------------------------------------- chunks ----
local function chunkFor(z: number): number
	return math.floor(z / CHUNK_LENGTH)
end

-- Returns true if a build was attempted (so the caller can budget per frame).
local function tryBuildChunk(idx: number, now: number): boolean
	if chunks[idx] then
		return false
	end
	local retryAt = chunkRetryAt[idx]
	if retryAt and now < retryAt then
		return false
	end

	local centerZ = (idx + 0.5) * CHUNK_LENGTH
	local dist = -centerZ * GameConfig.MetersPerStud
	local targetZone = GameConfig.GetZoneForDistance(math.max(0, dist))
	local model = safeCall("WorldBuilder.BuildChunk", WorldBuilder.BuildChunk, targetZone.Id, centerZ, CHUNK_HALF, idx * 7919 + 13)
	if model and sceneryFolder then
		model.Parent = sceneryFolder
		chunks[idx] = model
		chunkRetryAt[idx] = nil
	else
		if model then
			model:Destroy()
		end
		chunkRetryAt[idx] = now + CHUNK_RETRY_DELAY
	end
	return true
end

-- Chunks nearest the plane are built first, and only `maxBuilds` per call, so
-- a slow chunk can never stall a frame or leave a gap right ahead of the plane.
local function ensureChunks(maxBuilds: number?)
	if not sceneryFolder or not sceneryFolder.Parent then
		return
	end

	local budget = maxBuilds or MAX_CHUNK_BUILDS_PER_FRAME
	local now = os.clock()
	local playerChunk = chunkFor(planePos.Z)
	local builds = 0

	for idx = playerChunk, playerChunk - WORLD_AHEAD, -1 do
		if builds >= budget then
			break
		end
		if tryBuildChunk(idx, now) then
			builds += 1
		end
	end
	for idx = playerChunk + 1, playerChunk + WORLD_BEHIND do
		if builds >= budget then
			break
		end
		if tryBuildChunk(idx, now) then
			builds += 1
		end
	end

	for idx, model in pairs(chunks) do
		if idx < playerChunk - WORLD_AHEAD - 1 or idx > playerChunk + WORLD_BEHIND + 1 then
			model:Destroy()
			chunks[idx] = nil
			chunkRetryAt[idx] = nil
		end
	end
end


-- ----------------------------------------------------- damage & projectiles ----
-- Single entry point for player damage so feedback is always consistent.
-- Shields divide incoming damage; the plane's own `Mult` never boosts it.
local function damagePlayer(amount: number)
	if amount <= 0 or runTime < invulnerableUntil then
		return
	end

	local mitigated = amount / math.max(1, shieldMult)
	health = math.max(0, health - mitigated)
	cameraShake = math.min(1, cameraShake + math.clamp(mitigated / math.max(maxHealth, 1) * 4, 0.2, 0.6))
	Effects.Burst(planePos, Color3.fromRGB(255, 80, 80), 10, 12)
	Effects.DamageNumber(planePos, mitigated, Color3.fromRGB(255, 120, 120))
	Effects.Play("Hit", nil, 0.4)
	emitRunUpdate(true)
end

-- `direction` is only used when `homing` is false.
local function spawnEnemyProjectile(
	origin: Vector3,
	direction: Vector3?,
	projectileSpeed: number,
	projectileDamage: number,
	homing: boolean,
	size: number?
)
	if not projectilesFolder or not projectilesFolder.Parent then
		return
	end
	if #projectiles >= MAX_ENEMY_PROJECTILES then
		return
	end

	local diameter = size or 1.4
	local part = Instance.new("Part")
	part.Name = "EnemyProjectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Color = Color3.fromRGB(220, 60, 60)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(origin)
	part.Parent = projectilesFolder

	table.insert(projectiles, {
		Part = part,
		Pos = origin,
		Direction = direction,
		Homing = homing,
		Speed = projectileSpeed,
		Damage = projectileDamage,
		T = 0,
	})
end

local function clearEnemyProjectiles()
	for _, projectile in ipairs(projectiles) do
		if projectile.Part then
			projectile.Part:Destroy()
		end
	end
	table.clear(projectiles)
end

-- -------------------------------------------------------------- enemies ----
local function randomSpawnPosition(): Vector3
	local corridor = GameConfig.Corridor
	local x = (math.random() * 2 - 1) * corridor.HalfWidth * 0.9
	local y = corridor.MinHeight + math.random() * (corridor.MaxHeight - corridor.MinHeight) * 0.7
	local z = planePos.Z - (120 + math.random() * 120)
	return Vector3.new(x, y, z)
end

local function clampToCorridor(position: Vector3): Vector3
	local corridor = GameConfig.Corridor
	return Vector3.new(
		Utility.Clamp(position.X, -corridor.HalfWidth, corridor.HalfWidth),
		Utility.Clamp(position.Y, corridor.MinHeight, corridor.MaxHeight),
		position.Z
	)
end

-- Returns the new enemy record, or nil if nothing was spawned. Split children
-- use `options` so they are built correctly the first time instead of being
-- patched afterwards.
local function spawnEnemy(enemyId: string, options: SpawnOptions?): any?
	local cfg = GameConfig.Enemies[enemyId]
	if not cfg or not enemiesFolder or not enemiesFolder.Parent then
		return nil
	end
	if #enemies >= MAX_ACTIVE_ENEMIES then
		return nil
	end

	local opts: SpawnOptions = options or {}
	local scaleMult = opts.ScaleMult or 1
	-- The scale multiplier is applied relative to the enemy's configured scale.
	-- (Model:ScaleTo is absolute, so scaling a built model to 0.55 could make
	-- a child larger than a parent whose configured scale is below 0.55.)
	local buildScale = if scaleMult == 1 then cfg.Scale else (cfg.Scale or 1) * scaleMult
	local model = safeCall("WorldBuilder.BuildEnemy", WorldBuilder.BuildEnemy, enemyId, buildScale)
	if not model then
		return nil
	end

	local position = clampToCorridor(opts.Position or randomSpawnPosition())
	model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	model.Parent = enemiesFolder

	local healthMult = GameConfig.EnemyHealthMult(distance)
	local damageMult = GameConfig.EnemyDamageMult(distance)
	local scaledHealth = math.max(1, (cfg.Health or 1) * healthMult * (opts.HealthMult or 1))

	local record = {
		Model = model,
		Id = enemyId,
		Cfg = cfg,
		Pos = position,
		BaseX = position.X,
		BaseY = position.Y,
		Health = scaledHealth,
		MaxHealth = scaledHealth,
		Speed = math.max(0, cfg.Speed or 0),
		Damage = math.max(0, (cfg.Damage or 0) * damageMult),
		T = math.random() * 10,
		Alive = true,
		Boss = false,
		Generation = opts.Generation or 0,
		FireTimer = math.max(0.1, cfg.FireInterval or 2),
		NextContactDamage = 0,
	}
	table.insert(enemies, record)
	return record
end

-- Finds the next boss that is allowed to start: right zone, distance reached,
-- not already beaten or attempted this run.
local function findBossDefinition(requireDistance: boolean): any?
	for _, definition in ipairs(GameConfig.Bosses) do
		if definition.Zone == zone.Id
			and not beatenBossZones[definition.Zone]
			and not bossSpawnedZones[definition.Zone]
			and (not requireDistance or distance >= definition.Distance) then
			return definition
		end
	end
	return nil
end

local function spawnBoss(bossDef: any)
	if bossActive or not enemiesFolder or not enemiesFolder.Parent then
		return
	end

	-- Mark the zone as attempted up front: if the boss cannot be built, the
	-- Heartbeat loop must not retry (and warn) on every frame.
	bossSpawnedZones[bossDef.Zone] = true

	local cfg = GameConfig.Enemies.EraserGolem or { Health = 170, Damage = 22 }
	local model = safeCall("WorldBuilder.BuildBoss", WorldBuilder.BuildBoss, bossDef)
	if not model then
		return
	end

	local y = (GameConfig.Corridor.MinHeight + GameConfig.Corridor.MaxHeight) / 2
	local position = Vector3.new(0, y, planePos.Z - BOSS_SPAWN_STANDOFF)
	model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	model.Parent = enemiesFolder

	local bossHealth = math.max(1, bossDef.Health or cfg.Health or 1)
	local bossDamage = math.max(0, bossDef.Damage or cfg.Damage or 0)
	local record = {
		Model = model,
		Id = bossDef.Name,
		Cfg = cfg,
		Pos = position,
		Health = bossHealth,
		MaxHealth = bossHealth,
		Speed = 0,
		Damage = bossDamage,
		ProjectileDamage = bossDef.ProjectileDamage or math.max(DEFAULT_PROJECTILE_DAMAGE, bossDamage * 0.35),
		T = 0,
		Alive = true,
		Boss = true,
		BossDef = bossDef,
		Standoff = BOSS_SPAWN_STANDOFF,
		Phase = math.random() * math.pi * 2,
		FireTimer = BOSS_FIRE_INTERVAL,
		NextContactDamage = 0,
	}
	table.insert(enemies, record)
	bossActive = true
	bossRecord = record

	cameraShake = math.min(1, cameraShake + 0.5)
	Effects.Play("Boss", nil, 0.7)
	Effects.Explosion(position, (bossDef.Accent or Color3.fromRGB(255, 200, 120)), 18)
end

local function releaseBossIfNeeded(record: any)
	if record.Boss and bossRecord == record then
		bossActive = false
		bossRecord = nil
	end
end

-- Removes an enemy silently (no effects, no rewards, no splitting). Used for
-- enemies that simply flew past the plane.
local function despawnEnemy(record: any)
	if not record or not record.Alive then
		return
	end

	record.Alive = false
	releaseBossIfNeeded(record)
	if record.Model then
		record.Model:Destroy()
		record.Model = nil
	end
end

local function killEnemy(record: any, awardCoins: boolean)
	if not record or not record.Alive then
		return
	end

	record.Alive = false
	local position: Vector3 = record.Pos
	local isBoss: boolean = record.Boss
	local cfg = record.Cfg
	local generation: number = record.Generation or 0

	-- Only enemies the player shoots down split, and only for a limited number
	-- of generations. Ramming or despawning must never create replacements:
	-- previously every split child could split again, and a blob that touched
	-- the plane or passed it produced an endless, exponentially growing chain.
	if awardCoins and record.Id == "InkBlob" and not isBoss and generation < MAX_SPLIT_GENERATION then
		for _ = 1, SPLIT_CHILD_COUNT do
			spawnEnemy("InkBlob", {
				Position = position + Vector3.new(
					(math.random() * 2 - 1) * 6,
					math.random() * 4,
					(math.random() * 2 - 1) * 6
				),
				ScaleMult = SPLIT_SCALE_MULT,
				HealthMult = SPLIT_HEALTH_MULT,
				Generation = generation + 1,
			})
		end
	end

	if awardCoins then
		kills += 1
		comboSteps = math.min(GameConfig.Combo.MaxSteps, comboSteps + 1)
		maxCombo = math.max(maxCombo, comboSteps)
		comboTimer = GameConfig.Combo.Window
		boostCharge = math.min(GameConfig.Boost.ChargeMax, boostCharge + GameConfig.Boost.ChargePerKill)

		local payout = comboMultiplier()
		if isBoss and record.BossDef then
			local definition = record.BossDef
			coinsCollected += math.floor((definition.Coins or 0) * payout)
			gemsCollected += definition.Gems or 0
			beatenBossZones[definition.Zone] = true
		else
			coinsCollected += math.floor(((cfg and cfg.Coins) or 0) * payout)
			gemsCollected += (cfg and cfg.Gems) or 0
		end
	end

	if isBoss then
		-- Leftover boss shots should not punish the player after the victory.
		clearEnemyProjectiles()
		releaseBossIfNeeded(record)
		Effects.Explosion(position, (cfg and cfg.Accent) or Color3.fromRGB(255, 220, 140), 26)
		Effects.Play("Explosion", nil, 0.6)
	else
		Effects.Burst(position, (cfg and cfg.Color) or Color3.new(1, 1, 1), 14, 14)
	end
	Effects.Play("Hit", nil, 0.35)

	if record.Model then
		record.Model:Destroy()
		record.Model = nil
	end
end

local function spawnCoins()
	if not coinsFolder or not coinsFolder.Parent then
		return
	end

	local corridor = GameConfig.Corridor
	local count = 5
	local baseX = (math.random() * 2 - 1) * corridor.HalfWidth * 0.6
	local baseY = corridor.MinHeight + math.random() * (corridor.MaxHeight - corridor.MinHeight) * 0.6
	local baseZ = planePos.Z - 130

	for i = 1, count do
		local position = Vector3.new(baseX, baseY, baseZ - i * 7)
		local coin = safeCall("WorldBuilder.BuildCoin", WorldBuilder.BuildCoin)
		if coin then
			coin:PivotTo(CFrame.new(position) * COIN_BASE_ROTATION)
			coin.Parent = coinsFolder
			table.insert(coins, {
				Model = coin,
				Pos = position,
				Value = 2,
				T = math.random() * 6,
			})
		end
	end
end

-- --------------------------------------------------------------- combat ----
local function nearestEnemyInRange(): any?
	local best: any = nil
	local bestDistance = GameConfig.FireRange
	for _, enemy in ipairs(enemies) do
		if enemy.Alive then
			local candidateDistance = (enemy.Pos - planePos).Magnitude
			if candidateDistance < bestDistance then
				best = enemy
				bestDistance = candidateDistance
			end
		end
	end
	return best
end

local function targetEnemyAtScreen(screenPos: Vector2?): any?
	local weaponRange = GameConfig.FireRange * (runWeapon.RangeMult or 1)
	local currentCamera = activeCamera()
	if not currentCamera then
		return nil
	end

	local aimPoint = screenPos or screenCenterPosition()
	local aimRay = currentCamera:ScreenPointToRay(aimPoint.X, aimPoint.Y)
	local rayOrigin = planePos
	local rayDirection = aimRay.Direction.Unit
	local best: any = nil
	local bestAlongRay = weaponRange

	-- Aim is a true 3D ray from the camera through the cursor. There is no
	-- forward-Z or aircraft-heading restriction, so targets can be acquired
	-- while the aircraft is facing sideways or backwards.
	for _, enemy in ipairs(enemies) do
		if enemy.Alive then
			local toEnemy = enemy.Pos - rayOrigin
			local alongRay = toEnemy:Dot(rayDirection)
			if alongRay > 0 and alongRay < bestAlongRay then
				local closestPoint = rayOrigin + rayDirection * alongRay
				local missDistance = (enemy.Pos - closestPoint).Magnitude
				local radius = if enemy.Boss then 11 else math.max(4.5, (enemy.Cfg.Scale or 1) * 3.2)
				if missDistance <= radius then
					best = enemy
					bestAlongRay = alongRay
				end
			end
		end
	end
	return best
end

-- Weapon, plane, shield and ally multipliers are resolved once per run in
-- StartRun (runDamageMultiplier); only health and speed vary per shot.
local function fireWeapon(screenPos: Vector2?, forcedTarget: any?)
	if not running or not stats then
		return
	end

	local weapon = runWeapon
	local currentCamera = activeCamera()
	local aimPoint = screenPos or screenCenterPosition()
	local aimRay = if currentCamera then currentCamera:ScreenPointToRay(aimPoint.X, aimPoint.Y) else nil
	local aimDirection = if aimRay then aimRay.Direction.Unit else planeRotation.LookVector
	local target = forcedTarget or targetEnemyAtScreen(screenPos)
	local forward = if planeModel and planeModel.Parent then planeModel:GetPivot().LookVector else planeRotation.LookVector
	local muzzle = planePos + forward * 4.2
	Effects.MuzzleFlash(muzzle, aimDirection, weapon.Color)
	local healthBonus = 1 + math.clamp(health / math.max(maxHealth, 1), 0, 1) * 0.25
	local finalDamage = math.max(0, damage * runDamageMultiplier * (1 + speed / 200) * healthBonus)

	-- Weapon shape matters: base projectiles, extra projectiles from the Triple
	-- Shot pass (at reduced damage), piercing targets, and double-hit throws.
	local baseShots = math.max(1, math.floor(weapon.Projectiles or 1))
	local extraShots = math.max(0, math.floor((stats.ExtraProjectiles or 0)))
	local pierce = math.max(0, math.floor(weapon.Pierce or 0))
	local hitsTwice = weapon.HitsTwice == true
	local totalShots = baseShots + extraShots

	for shot = 1, totalShots do
		-- Extra (gamepass) projectiles hit softer so the pass is a bonus, not a
		-- free doubling of every weapon.
		local shotDamage = if shot > baseShots then finalDamage * 0.6 else finalDamage
		if hitsTwice then
			shotDamage *= 2
		end

		local spreadOffset = Vector3.new((shot - (totalShots + 1) / 2) * 0.45, 0, 0)

		local hitList = {}
		if target and target.Alive then
			table.insert(hitList, target)
			-- Pierce: nearest enemies clustered around the primary target.
			if pierce > 0 then
				for _, other in ipairs(enemies) do
					if #hitList >= 1 + pierce then
						break
					end
					if other.Alive and other ~= target and (other.Pos - target.Pos).Magnitude < 30 then
						table.insert(hitList, other)
					end
				end
			end
		end

		if #hitList == 0 then
			local range = GameConfig.FireRange * (weapon.RangeMult or 1)
			Effects.Tracer(muzzle + spreadOffset, muzzle + aimDirection * range, weapon.Color)
		else
			for _, enemy in ipairs(hitList) do
				Effects.Tracer(muzzle + spreadOffset, enemy.Pos, weapon.Color)
				enemy.Health -= shotDamage
				Effects.DamageNumber(enemy.Pos, shotDamage, weapon.Color)
				if enemy.Health <= 0 then
					killEnemy(enemy, true)
				end
			end
		end
	end

	Effects.Play("Fire", nil, 0.22)
end

local function updateAllies(dt: number)
	if not stats then
		return
	end

	for index, unit in ipairs(allyUnits) do
		local cfg = GameConfig.Allies[unit.Id]
		local model = unit.Model
		if cfg and model and model.Parent then
			local side = (index % 2 == 0) and 1 or -1
			local allyPosition = planePos + Vector3.new(
				side * (6 + math.floor((index - 1) / 2) * 2),
				-1.5 + ((index - 1) % 3) * 1.5,
				2.5
			)
			model:PivotTo(CFrame.lookAt(allyPosition, allyPosition + Vector3.new(0, 0, -1)))

			local fireInterval = math.max(0.1, cfg.FireInterval or 1)
			unit.Timer += dt
			if unit.Timer >= fireInterval then
				unit.Timer %= fireInterval
				local target = nearestEnemyInRange()
				if target then
					local allyDamage = math.max(0, cfg.Damage or 0)
					Effects.Tracer(allyPosition + Vector3.new(0, 0, -2), target.Pos, cfg.Color)
					target.Health -= allyDamage

					if cfg.Splash then
						for _, other in ipairs(enemies) do
							if other.Alive and other ~= target
								and (other.Pos - target.Pos).Magnitude < cfg.Splash then
								other.Health -= allyDamage * 0.6
								if other.Health <= 0 then
									killEnemy(other, true)
								end
							end
						end
					end

					if target.Health <= 0 then
						killEnemy(target, true)
					end
				end
			end
		end
	end
end

-- ------------------------------------------------------------- main loop ---
-- How far ahead of the plane the boss holds position. Always inside weapon range.
local function bossStandoff(): number
	local range = GameConfig.FireRange
	return math.min(math.clamp(range * 0.5, 30, 90), range * 0.8)
end

-- The plane outruns anything that merely walks toward it, so the boss keeps a
-- fixed distance ahead (easing toward it), sways across the corridor and fires
-- aimed volleys. Previously it drifted past the plane within ~3 seconds and was
-- discarded unrewarded, and it could never be defeated or return.
local function updateBoss(boss: any, dt: number)
	local halfWidth = GameConfig.Corridor.HalfWidth

	boss.Standoff = Utility.Lerp(boss.Standoff, bossStandoff(), 1 - math.exp(-dt * 1.5))
	local sway = math.sin(boss.T * 0.8 + boss.Phase) * halfWidth * 0.6
	local targetX = Utility.Clamp(planePos.X * 0.5 + sway, -halfWidth * 0.9, halfWidth * 0.9)
	boss.Pos = Vector3.new(
		Utility.Lerp(boss.Pos.X, targetX, math.clamp(dt * 2, 0, 1)),
		Utility.Lerp(boss.Pos.Y, planePos.Y, math.clamp(dt * 0.5, 0, 1)),
		planePos.Z - boss.Standoff
	)

	boss.FireTimer -= dt
	if boss.FireTimer > 0 then
		return
	end

	local enraged = bossHealthRatio() <= BOSS_ENRAGE_RATIO
	boss.FireTimer = if enraged then BOSS_ENRAGED_FIRE_INTERVAL else BOSS_FIRE_INTERVAL
	local volley = if enraged then BOSS_ENRAGED_VOLLEY else BOSS_VOLLEY
	local projectileSpeed = math.max(1, boss.Cfg.ProjectileSpeed or BOSS_PROJECTILE_SPEED)

	-- Lead the shot: the plane flies toward the boss while the projectile closes.
	local travelTime = (planePos - boss.Pos).Magnitude / (projectileSpeed + math.max(1, planeVelocity.Magnitude))
	local aimPoint = planePos + planeVelocity * travelTime
	local aimVector: Vector3 = aimPoint - boss.Pos
	if aimVector.Magnitude < 1e-3 then
		return
	end
	local baseDirection = aimVector.Unit

	for shot = 1, volley do
		local angle = (shot - (volley + 1) / 2) * BOSS_VOLLEY_SPREAD
		local direction = CFrame.Angles(0, angle, 0):VectorToWorldSpace(baseDirection)
		spawnEnemyProjectile(boss.Pos, direction, projectileSpeed, boss.ProjectileDamage, false, 2.2)
	end
end

local function updateEnemies(dt: number)
	local corridor = GameConfig.Corridor

	-- Reverse iteration makes removals safe and avoids skipping entries.
	-- Newly split children are appended and will be processed on the next frame.
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
			if behavior == "zigzag" then
				local baseX = enemy.BaseX or enemy.Pos.X
				local baseY = enemy.BaseY or enemy.Pos.Y
				enemy.Pos = Vector3.new(
					Utility.Clamp(baseX + math.sin(enemy.T * 3) * 22, -corridor.HalfWidth, corridor.HalfWidth),
					Utility.Clamp(baseY + math.cos(enemy.T * 2) * 8, corridor.MinHeight, corridor.MaxHeight),
					enemy.Pos.Z + enemy.Speed * dt
				)
			elseif behavior == "ranged" then
				enemy.Pos += Vector3.new(0, 0, enemy.Speed * 0.5 * dt)
				enemy.FireTimer -= dt
				if enemy.FireTimer <= 0 and enemy.Pos.Z < planePos.Z - 20 then
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
			else
				enemy.Pos += Vector3.new(0, 0, enemy.Speed * dt)
			end

			-- Enemies track the plane gently without letting zigzag motion drift away.
			if behavior ~= "zigzag" then
				enemy.Pos = Vector3.new(
					Utility.Lerp(enemy.Pos.X, planePos.X, math.clamp(dt * 0.35, 0, 1)),
					Utility.Lerp(enemy.Pos.Y, planePos.Y, math.clamp(dt * 0.25, 0, 1)),
					enemy.Pos.Z
				)
			end
		end

		if enemy.Model and enemy.Model.Parent then
			enemy.Model:PivotTo(CFrame.lookAt(enemy.Pos, enemy.Pos + Vector3.new(0, 0, 1)))
		end

		-- Contact damage is rate-limited. A boss is not destroyed just because
		-- it touched the plane; tanks and bosses can only damage once per cooldown.
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

		-- Enemies that fly past the plane vanish quietly. The boss never does:
		-- it keeps pace with the plane until it is defeated.
		if enemy.Alive and not enemy.Boss and (enemy.Pos - planePos).Magnitude > 300 then
			despawnEnemy(enemy)
		end

		if not enemy.Alive then
			table.remove(enemies, index)
		end
	end
end

local function distanceToSegment(point: Vector3, startPoint: Vector3, endPoint: Vector3): number
	local segment = endPoint - startPoint
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= 1e-6 then
		return (point - startPoint).Magnitude
	end

	local t = math.clamp((point - startPoint):Dot(segment) / lengthSquared, 0, 1)
	return (point - (startPoint + segment * t)).Magnitude
end

local function updateProjectiles(dt: number)
	for index = #projectiles, 1, -1 do
		local projectile = projectiles[index]
		local oldPosition: Vector3 = projectile.Pos

		-- Homing shots steer at the plane every frame; boss volleys fly straight
		-- along the direction they were fired so they can be dodged.
		local direction: Vector3
		if projectile.Homing or not projectile.Direction then
			local toPlane = planePos - oldPosition
			direction = if toPlane.Magnitude > 1e-4 then toPlane.Unit else Vector3.zero
		else
			direction = projectile.Direction
		end

		local newPosition = oldPosition + direction * projectile.Speed * dt
		projectile.Pos = newPosition
		projectile.T += dt

		if projectile.Part and projectile.Part.Parent then
			projectile.Part.CFrame = CFrame.new(newPosition)
		end

		-- Segment test so fast projectiles cannot tunnel through the plane on a
		-- long frame.
		local hit = distanceToSegment(planePos, oldPosition, newPosition) < 3.5
		if hit then
			damagePlayer(projectile.Damage or DEFAULT_PROJECTILE_DAMAGE)
		end

		if hit or projectile.T > 6 or (newPosition - planePos).Magnitude > 260 then
			if projectile.Part then
				projectile.Part:Destroy()
			end
			table.remove(projectiles, index)
		end
	end
end

local function updateCoins(dt: number)
	for index = #coins, 1, -1 do
		local coin = coins[index]
		local model = coin.Model

		if not model or not model.Parent then
			table.remove(coins, index)
			continue
		end

		coin.T += dt

		-- Magnet: coins inside the pickup radius drift toward the plane. The
		-- pull strengthens as they get closer, which reads as "vacuuming".
		local toPlane = planePos - coin.Pos
		local distanceToPlane = toPlane.Magnitude
		if distanceToPlane < magnetRadius and distanceToPlane > 0.1 then
			local pull = math.clamp((magnetRadius - distanceToPlane) / magnetRadius, 0, 1)
			local step = math.min(distanceToPlane, (12 + 40 * pull) * dt)
			coin.Pos += toPlane.Unit * step
			distanceToPlane = (coin.Pos - planePos).Magnitude
		end

		-- Flip around the vertical axis and bob.
		local bob = math.sin(coin.T * 4) * 0.4
		model:PivotTo(
			CFrame.new(coin.Pos + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, coin.T * 3, 0)
				* COIN_BASE_ROTATION
		)

		if distanceToPlane < 3.6 then
			coinsCollected += coin.Value
			Effects.CoinPop(coin.Pos)
			Effects.Play("Coin", nil, 0.3)
			Effects.DamageNumber(coin.Pos, coin.Value, Color3.fromRGB(255, 220, 90))
			model:Destroy()
			table.remove(coins, index)
		elseif (coin.Pos - planePos).Magnitude > 300 then
			model:Destroy()
			table.remove(coins, index)
		end
	end
end

local function updateZone()
	local newZone = GameConfig.GetZoneForDistance(distance)
	if newZone ~= zone then
		zone = newZone
		applyZoneLighting(zone)
		emitRunUpdate(true)
	end
end

local function updateCamera(dt: number)
	local currentCamera = activeCamera()
	if not currentCamera then
		return
	end

	if currentCamera.CameraType ~= Enum.CameraType.Scriptable then
		currentCamera.CameraType = Enum.CameraType.Scriptable
	end

	local shakeOffset = Vector3.zero
	if cameraShake > 0.01 then
		local amplitude = cameraShake * cameraShake * 1.2
		shakeOffset = Vector3.new((math.random() * 2 - 1) * amplitude, (math.random() * 2 - 1) * amplitude, 0)
		cameraShake = math.max(0, cameraShake - dt * CAMERA_SHAKE_DECAY)
	end

	local forward = planeRotation.LookVector
	local up = planeRotation.UpVector
	local right = planeRotation.RightVector
	local cameraPosition = planePos - forward * FLIGHT_CAMERA_OFFSET.Z + up * FLIGHT_CAMERA_OFFSET.Y + right * FLIGHT_CAMERA_OFFSET.X + shakeOffset
	local lookTarget = planePos + forward * 13 + up * 1.5
	currentCamera.CFrame = CFrame.lookAt(cameraPosition, lookTarget, up)
end

-- Spends one revive (gamepass charge first, then a purchased token) and puts the
-- player back in the air. Returns false when no revive is available.
local function tryRevive(): boolean
	local usingPaid = false
	if freeRevives > 0 then
		freeRevives -= 1
	elseif paidRevives > 0 then
		paidRevives -= 1
		usingPaid = true
	else
		return false
	end

	if usingPaid then
		fireServer(Remotes.UseRevive)
	end

	health = maxHealth * 0.5
	crashing = false
	crashElapsed = 0
	planePos = Vector3.new(planePos.X, math.max(planePos.Y, (GameConfig.Corridor.PlaneGroundClearance or 2.3) + 10), planePos.Z)
	planeVelocity = Vector3.new(0, 18, 0)
	invulnerableUntil = runTime + 2.5
	cameraShake = 0
	comboSteps = 0
	Effects.ReviveBurst(planePos)
	emitRunUpdate(true)
	return true
end

local function update(dt: number)
	if not running then
		return
	end
	-- Avoid large simulation jumps after a frame hitch, especially for collision
	-- checks and lerp factors.
	dt = math.clamp(dt, 0, 0.1)
	runTime += dt

	-- A crash is a short physical sequence, not an instant teleport/death.
	if crashing then
		crashElapsed += dt
		planeVelocity += Vector3.new(0, -CRASH_GRAVITY, 0) * dt
		planePos += planeVelocity * dt
		local floorY = GameConfig.Corridor.GroundY + (GameConfig.Corridor.PlaneGroundClearance or 2.3)
		if planePos.Y <= floorY then
			planePos = Vector3.new(planePos.X, floorY, planePos.Z)
			planeVelocity = Vector3.zero
			health = 0
		end
		if planeModel and planeModel.Parent then
			local tumble = CFrame.Angles(crashElapsed * 5.8, crashElapsed * 3.7, crashElapsed * 8.2)
			planeModel:PivotTo(CFrame.new(planePos) * planeRotation.Rotation * tumble)
		end
		ensureChunks()
		updateEnemies(dt)
		updateProjectiles(dt)
		updateCoins(dt)
		updateCamera(dt)
		emitRunUpdate()
		if health <= 0 then
			if tryRevive() then
				return
			end
			Flight.EndRun("death")
		end
		return
	end

	local moveInput = readInput()
	local corridor = GameConfig.Corridor

	-- Boost: charge is earned by kills and spent in a burst of speed.
	boostHeld = touchBoost or UserInputService:IsKeyDown(keyBindings.Boost)
	if boostHeld and boostCharge > 0 and (boosting or boostCharge >= GameConfig.Boost.MinChargeToStart) then
		boosting = true
		boostCharge = math.max(0, boostCharge - GameConfig.Boost.DrainPerSecond * dt)
		if boostCharge <= 0 then boosting = false end
	else
		boosting = false
	end

	local currentSpeed = speed * (if boosting then GameConfig.Boost.SpeedMult else 1)
	if RunService:IsStudio() and ReplicatedStorage:GetAttribute("DevFreezeDistance") then
		currentSpeed = 0
	end

	local floorY = corridor.GroundY + (corridor.PlaneGroundClearance or 2.3)
	local wasGrounded = grounded
	local acceleration = FLIGHT_ACCELERATION * (if boosting then 1.18 else 1)
	planeVelocity += moveInput * acceleration * dt
	planeVelocity += Vector3.new(0, -GRAVITY, 0) * dt

	-- Air resistance preserves a little glide; runway friction brings the plane
	-- fully to rest. No input means horizontal velocity decays and gravity lands it.
	local hasHorizontalInput = Vector3.new(moveInput.X, 0, moveInput.Z).Magnitude > 0.01
	local drag = if wasGrounded then (if hasHorizontalInput then GROUND_DRAG else GROUND_IDLE_DRAG) else AIR_DRAG
	planeVelocity = Vector3.new(
		planeVelocity.X * math.exp(-drag * dt),
		planeVelocity.Y * math.exp(-VERTICAL_DRAG * dt),
		planeVelocity.Z * math.exp(-drag * dt)
	)

	local horizontalVelocity = Vector3.new(planeVelocity.X, 0, planeVelocity.Z)
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

	local nextPosition = planePos + planeVelocity * dt
	local boundaryX = corridor.HalfWidth - BOUNDARY_MARGIN
	local boundaryY = corridor.MaxHeight - BOUNDARY_MARGIN
	local hitSide = math.abs(nextPosition.X) >= boundaryX
	local hitCeiling = nextPosition.Y >= boundaryY
	if hitSide or hitCeiling then
		planePos = Vector3.new(
			math.clamp(nextPosition.X, -boundaryX, boundaryX),
			math.min(nextPosition.Y, boundaryY),
			nextPosition.Z
		)
		local crashFloor = corridor.GroundY + (corridor.PlaneGroundClearance or 2.3)
		if planePos.Y <= crashFloor + 0.25 then
			planePos = Vector3.new(planePos.X, crashFloor + 7, planePos.Z)
		end
		crashing = true
		crashElapsed = 0
		crashReason = if hitSide then "side barrier" else "upper barrier"
		planeVelocity = Vector3.new(planeVelocity.X * 0.25, -math.max(18, math.abs(planeVelocity.Y) * 0.45), planeVelocity.Z * 0.3)
		resetPointerInput()
		Effects.Explosion(planePos, Color3.fromRGB(100, 220, 255), 15)
		Effects.Play("Hit", nil, 0.65)
		State.EmitNotify("ELECTRICAL BARRIER — " .. string.upper(crashReason) .. " — CRITICAL DAMAGE")
	else
		planePos = nextPosition
	end

	-- Ground contact is safe. Landing clamps downward velocity and lets friction
	-- settle the aircraft instead of treating the runway as a lethal boundary.
	if planePos.Y <= floorY then
		planePos = Vector3.new(planePos.X, floorY, planePos.Z)
		if planeVelocity.Y < 0 then planeVelocity = Vector3.new(planeVelocity.X, 0, planeVelocity.Z) end
		grounded = true
	else
		grounded = false
	end

	-- Record furthest forward progress. Reversing does not erase a run's distance.
	distance = math.max(distance, math.max(0, -planePos.Z * GameConfig.MetersPerStud))

	-- Combo decays when the player stops killing.
	if comboSteps > 0 then
		comboTimer -= dt
		if comboTimer <= 0 then
			comboSteps = 0
			comboTimer = 0
		end
	end

	-- The aircraft faces its actual 3D velocity. With no meaningful movement it
	-- preserves the last heading; lateral input produces a natural bank.
	local targetBank = -moveInput.X * MAX_BANK_ANGLE
	bank = Utility.Lerp(bank, targetBank, math.clamp(dt * 4.5, 0, 1))
	if planeVelocity.Magnitude > 2 then
		local direction = planeVelocity.Unit
		local upReference = if math.abs(direction:Dot(Vector3.yAxis)) > 0.97 then Vector3.zAxis else Vector3.yAxis
		planeRotation = CFrame.lookAt(planePos, planePos + direction, upReference) * CFrame.Angles(0, 0, bank)
	elseif grounded then
		local restingForward = Vector3.new(planeRotation.LookVector.X, 0, planeRotation.LookVector.Z)
		if restingForward.Magnitude < 0.1 then
			restingForward = Vector3.new(0, 0, -1)
		else
			restingForward = restingForward.Unit
		end
		planeRotation = CFrame.lookAt(planePos, planePos + restingForward, Vector3.yAxis)
	else
		planeRotation = CFrame.new(planePos) * planeRotation.Rotation
	end
	if planeModel and planeModel.Parent then
		planeModel:PivotTo(planeRotation)
		local propeller = planeModel:FindFirstChild("Propeller", true)
		if propeller and propeller:IsA("BasePart") then
			propeller.CFrame = propeller.CFrame * CFrame.Angles(0, 0, math.rad(1500 * dt))
		end
	end

	ensureChunks()
	updateZone()

	if RunService:IsStudio() then
		local jump = ReplicatedStorage:GetAttribute("DevJumpMeters")
		if typeof(jump) == "number" then
			ReplicatedStorage:SetAttribute("DevJumpMeters", nil)
			local targetDistance = math.clamp(jump, 0, 100000)
			distance = targetDistance
			planePos = Vector3.new(planePos.X, planePos.Y, -targetDistance / GameConfig.MetersPerStud)
			planeRotation = CFrame.new(planePos) * planeRotation.Rotation
			ensureChunks()
			updateZone()
		end

		if ReplicatedStorage:GetAttribute("DevSpawnBoss") == true and not bossActive then
			ReplicatedStorage:SetAttribute("DevSpawnBoss", nil)
			local bossDefinition = GameConfig.GetBossForZone("PaperTown")
			if bossDefinition then
				spawnBoss(bossDefinition)
			end
		end
	end

	-- The player fires manually. Holding the mouse, touching the screen, or
	-- holding Space fires at that point; nearby enemies snap into the shot.
	if fireHeld and stats then
		if fireMode == "mouse" then
			fireScreenPos = UserInputService:GetMouseLocation()
		elseif fireMode == "touch" and lastTouch then
			fireScreenPos = lastTouch
		elseif fireMode == "keyboard" then
			fireScreenPos = screenCenterPosition()
		end

		local fireRateMultiplier = math.max(1, tonumber(stats.FireRateMultiplier) or 1)
		local fireInterval = math.max(0.09, (runWeapon.FireInterval or 0.25) * 1.35 / fireRateMultiplier)
		local now = os.clock()
		if now - lastFire >= fireInterval then
			lastFire = now
			fireWeapon(fireScreenPos)
		end
	end

	-- Spawn interval shrinks with distance (more enemies) down to a floor.
	lastSpawn += dt
	local spawnInterval = math.max(0.7, 1.8 - distance / 4000)
	local enemyPool = zone.Enemies
	if lastSpawn >= spawnInterval and not bossActive
		and type(enemyPool) == "table" and #enemyPool > 0 then
		lastSpawn %= spawnInterval
		spawnEnemy(enemyPool[math.random(1, #enemyPool)])
	end

	lastCoinSpawn += dt
	if lastCoinSpawn >= 2.2 then
		lastCoinSpawn %= 2.2
		spawnCoins()
	end

	-- Force a HUD update at each 1000 m milestone.
	local milestone = math.floor(distance / 1000)
	if milestone > lastMilestone then
		lastMilestone = milestone
		emitRunUpdate(true)
	end

	-- Each configured boss zone may start one encounter per run.
	if not bossActive then
		local bossDefinition = findBossDefinition(true)
		if bossDefinition then
			spawnBoss(bossDefinition)
		end
	end

	updateEnemies(dt)
	updateProjectiles(dt)
	updateCoins(dt)
	updateAllies(dt)
	emitRunUpdate()
	updateCamera(dt)

	if health <= 0 then
		if tryRevive() then
			return
		end
		Flight.EndRun("death")
	end
end

local function clearRunWorld()
	for _, folder in pairs({ sceneryFolder, enemiesFolder, coinsFolder, projectilesFolder }) do
		if folder then
			folder:Destroy()
		end
	end

	sceneryFolder = nil
	enemiesFolder = nil
	coinsFolder = nil
	projectilesFolder = nil

	table.clear(chunks)
	table.clear(chunkRetryAt)
	table.clear(enemies)
	table.clear(coins)
	table.clear(projectiles)
end


-- ------------------------------------------------------------ lifecycle ----
function Flight.IsRunning(): boolean
	return running
end

function Flight.GetBindings(): { [string]: Enum.KeyCode }
	return table.clone(keyBindings)
end

function Flight.SetBinding(action: string, keyCode: Enum.KeyCode): (boolean, string)
	if not keyBindings[action] then
		return false, "Unknown control"
	end
	if typeof(keyCode) ~= "EnumItem" or keyCode.EnumType ~= Enum.KeyCode then
		return false, "Choose a keyboard key"
	end
	if keyCode == Enum.KeyCode.Unknown or keyCode == Enum.KeyCode.Escape then
		return false, "That key cannot be assigned"
	end
	for otherAction, otherKey in pairs(keyBindings) do
		if otherAction ~= action and otherKey == keyCode then
			return false, "That key is already assigned to " .. otherAction
		end
	end
	keyBindings[action] = keyCode
	return true, ""
end

function Flight.ResetBindings()
	keyBindings = {
		Forward = Enum.KeyCode.W,
		Backward = Enum.KeyCode.S,
		Left = Enum.KeyCode.A,
		Right = Enum.KeyCode.D,
		Descend = Enum.KeyCode.Q,
		Ascend = Enum.KeyCode.E,
		Fire = Enum.KeyCode.Space,
		Boost = Enum.KeyCode.LeftShift,
	}
end

-- Held by the on-screen boost button on touch devices.
function Flight.SetBoostHeld(held: boolean)
	touchBoost = held == true
end

function Flight.StartRun()
	if running then
		return
	end
	if not State.Data or not State.Stats then
		warn("Flight: StartRun called before player data and stats were loaded.")
		return
	end

	stats = State.Stats
	rememberLightingDefaults()

	-- Resolve the loadout once per run instead of on every shot.
	runWeapon = GameConfig.Weapons[stats.WeaponId or "Dart"] or GameConfig.Weapons.Dart or FALLBACK_WEAPON
	local shieldCfg = GameConfig.Shields[stats.ShieldId] or GameConfig.Shields.None
	local planeCfg = GameConfig.Planes[stats.PlaneId] or GameConfig.Planes.Classic
	local supporters = stats.Pets or stats.Allies or {}
	runDamageMultiplier = (if planeCfg then planeCfg.DamageMult or 1 else 1)
		* (runWeapon.DamageMult or 1)
		* (1 + #supporters * 0.15)

	-- Shields divide incoming damage; they never change outgoing damage.
	shieldMult = math.max(1, (shieldCfg and shieldCfg.Mult) or 1)
	magnetRadius = math.max(GameConfig.CoinPickupRadius, tonumber(stats.MagnetRadius) or GameConfig.CoinPickupRadius)
	freeRevives = math.max(0, math.floor(tonumber(stats.Revives) or 0))
	paidRevives = math.max(0, math.floor(tonumber(State.Data.ReviveTokens) or 0))
	invulnerableUntil = 0
	comboSteps = 0
	comboTimer = 0
	maxCombo = 0
	boostCharge = 0
	boosting = false
	boostHeld = false

	-- Reset all per-run state before creating new instances.
	running = true
	distance = 0
	maxHealth = math.max(1, tonumber(stats.MaxHealth) or 100)
	health = maxHealth
	speed = math.max(1, tonumber(stats.Speed) or 56)
	damage = math.max(0, tonumber(stats.Damage) or 10)
	kills = 0
	coinsCollected = 0
	gemsCollected = 0
	runTime = 0
	lastFire = 0
	lastSpawn = 0
	lastCoinSpawn = 0
	lastMilestone = 0
	lastRunUpdate = 0
	cameraShake = 0
	bossActive = false
	bossRecord = nil
	beatenBossZones = {}
	bossSpawnedZones = {}
	zone = GameConfig.Zones[1]
	planePos = Vector3.new(0, GameConfig.Corridor.GroundY + (GameConfig.Corridor.PlaneGroundClearance or 2.3), 0)
	planeVelocity = Vector3.zero
	planeRotation = CFrame.lookAt(planePos, planePos + Vector3.new(0, 0, -1))
	grounded = true
	crashing = false
	crashElapsed = 0
	bank = 0
	resetPointerInput()

	clearRunWorld()

	sceneryFolder = Instance.new("Folder")
	sceneryFolder.Name = "Scenery"
	sceneryFolder.Parent = workspace

	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace

	coinsFolder = Instance.new("Folder")
	coinsFolder.Name = "Coins"
	coinsFolder.Parent = workspace

	projectilesFolder = Instance.new("Folder")
	projectilesFolder.Name = "Projectiles"
	projectilesFolder.Parent = workspace

	if planeModel then
		planeModel:Destroy()
		planeModel = nil
	end
	local planeId = State.Data.EquippedPlane or "Classic"
	local builtPlane = safeCall("PlaneBuilder.BuildPlane", PlaneBuilder.BuildPlane, planeId)
	if not builtPlane then
		running = false
		clearRunWorld()
		warn("Flight: Failed to create the equipped plane; run was cancelled.")
		showHangar()
		return
	end
	planeModel = builtPlane
	builtPlane:ScaleTo(PLAYER_PLANE_SCALE)
	builtPlane.Parent = workspace
	builtPlane:PivotTo(planeRotation)

	-- Engine glow and speed trails, so the plane feels like it is moving.
	local body = builtPlane.PrimaryPart
	if body then
		Effects.AttachTrail(body, (planeCfg and planeCfg.Accent) or Color3.fromRGB(255, 255, 255), 0.3)
	end
	local glow = builtPlane:FindFirstChild("Glow", true)
	if glow and glow:IsA("BasePart") then
		Effects.AttachExhaust(glow, (planeCfg and planeCfg.Accent) or Color3.fromRGB(255, 220, 150))
	end

	buildAllyUnits(stats.Allies or State.Data.Allies)

	hideHangar()
	hideCharacter()
	ensureAtmosphere()
	applyZoneLighting(zone, true)
	setDefaultControlsEnabled(false)

	setCameraTarget(CFrame.new(planePos), FLIGHT_CAMERA_OFFSET)
	ensureChunks(math.huge) -- build the whole initial window before the first frame
	updateCamera(0) -- take the flight camera immediately, not on the first Heartbeat

	fireServer(Remotes.RequestStart)

	if connection then
		connection:Disconnect()
		connection = nil
	end
	connection = RunService.Heartbeat:Connect(update)

	emitRunUpdate(true)
end

function Flight.EndRun(reason: string)
	if not running then
		return
	end

	running = false
	resetPointerInput()
	cameraShake = 0

	if connection then
		connection:Disconnect()
		connection = nil
	end

	if reason == "death" then
		Effects.DeathBurst(planePos)
		Effects.Play("Death", nil, 0.5)
	end

	-- Send only the summary. The server remains authoritative for rewards.
	local newlyBeatenBossZone: string? = nil
	for _, definition in ipairs(GameConfig.Bosses) do
		local alreadyBeaten = State.Data
			and State.Data.BossesBeaten
			and State.Data.BossesBeaten[definition.Zone]
		if beatenBossZones[definition.Zone] and not alreadyBeaten then
			newlyBeatenBossZone = definition.Zone
			break
		end
	end

	fireServer(Remotes.RunResult, {
		Distance = math.floor(distance),
		Kills = kills,
		BossZone = newlyBeatenBossZone,
		Combo = comboSteps,
	})

	clearRunWorld()
	bossActive = false
	bossRecord = nil
	setDefaultControlsEnabled(true)

	-- Rebuild the hangar plane from scratch: the flight copy carries trails and
	-- exhaust emitters that would keep puffing while parked on the pedestal.
	if planeModel then
		planeModel:Destroy()
		planeModel = nil
	end
	buildMenuPlane()
	buildMenuAllies()
	showHangar()

	State.EmitRunEnded({
		Reason = reason,
		Distance = math.floor(distance),
		Kills = kills,
		Coins = coinsCollected,
		Gems = gemsCollected,
		Combo = comboSteps,
		BestCombo = maxCombo,
	})
end

-- Rebuilds the hangar plane and allies from the current player data. Call this
-- after the player equips a different plane or ally in the menu.
function Flight.RefreshHangar()
	if running then
		return
	end
	buildMenuPlane()
	buildMenuAllies()
end

function Flight.Init()
	if initialized then
		return
	end
	initialized = true

	rememberLightingDefaults()
	buildHangar()
	buildMenuPlane()
	buildMenuAllies()
	showHangar()
	if not hangarIdleConnection then
		hangarIdleConnection = RunService.Heartbeat:Connect(updateHangarIdle)
	end

	if player.Character then
		watchCharacter(player.Character)
	end
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
	end
	characterAddedConnection = player.CharacterAdded:Connect(function(character)
		watchCharacter(character)
		task.defer(function()
			if characterHidden or running then
				hideCharacter()
				setCameraTarget(CFrame.new(planePos), FLIGHT_CAMERA_OFFSET)
			else
				placeCharacterInHangar()
			end
		end)
	end)

	State.OnLoaded(function()
		if not running then
			buildMenuPlane()
			buildMenuAllies()
			showHangar()
		end

		-- Dev hook: when ReplicatedStorage.DevAutoRun is a true BoolValue the
		-- first run starts by itself. Used by automated playtests; absent in a
		-- published place it does nothing.
		local flag = ReplicatedStorage:FindFirstChild("DevAutoRun")
		if flag and flag:IsA("BoolValue") and flag.Value and not running then
			task.delay(0.75, function()
				if not running then
					Flight.StartRun()
				end
			end)
		end
	end)

	State.OnUpdate(function(data)
		if running or not data then
			return
		end
		local equipped = data.EquippedHangar or "Cardboard"
		if equipped ~= hangarThemeId then
			showHangar(true)
		end
	end)

	inputBeganConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not running then
			return
		end

		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch then
			-- Only the first finger steers and fires; extra fingers are ignored
			-- so lifting one cannot cancel the other.
			if activeTouch then
				return
			end
			activeTouch = input
			lastTouch = Vector2.new(input.Position.X, input.Position.Y)
			fireScreenPos = lastTouch
			fireSources.touch = true
		elseif inputType == Enum.UserInputType.MouseButton1 then
			fireSources.mouse = true
		elseif inputType == Enum.UserInputType.Keyboard and input.KeyCode == keyBindings.Fire then
			fireSources.keyboard = true
		else
			return
		end
		refreshFireState()
	end)

	inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
		if running and activeTouch and input == activeTouch then
			lastTouch = Vector2.new(input.Position.X, input.Position.Y)
			if fireSources.touch then
				fireScreenPos = lastTouch
			end
		end
	end)

	inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch then
			if input ~= activeTouch then
				return
			end
			activeTouch = nil
			lastTouch = nil
			fireSources.touch = false
		elseif inputType == Enum.UserInputType.MouseButton1 then
			fireSources.mouse = false
		elseif inputType == Enum.UserInputType.Keyboard and input.KeyCode == keyBindings.Fire then
			fireSources.keyboard = false
		else
			return
		end
		refreshFireState()
	end)

	-- Releasing a button while the window is unfocused never delivers InputEnded,
	-- which used to leave the weapon firing forever.
	focusReleasedConnection = UserInputService.WindowFocusReleased:Connect(resetPointerInput)
end

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

-- Tears the controller down completely (hot reloads, tests). It does not send
-- RunResult, so a run in progress is abandoned rather than reported.
function Flight.Destroy()
	running = false
	disconnect(connection)
	connection = nil
	disconnect(characterAddedConnection)
	characterAddedConnection = nil
	disconnect(inputBeganConnection)
	inputBeganConnection = nil
	disconnect(inputChangedConnection)
	inputChangedConnection = nil
	disconnect(inputEndedConnection)
	inputEndedConnection = nil
	disconnect(focusReleasedConnection)
	focusReleasedConnection = nil
	disconnect(characterDescendantConnection)
	characterDescendantConnection = nil
	disconnect(hangarIdleConnection)
	hangarIdleConnection = nil

	resetPointerInput()
	clearRunWorld()
	cancelLightingTweens()
	restoreLightingDefaults()
	setDefaultControlsEnabled(true)
	showCharacter()

	-- Hand the avatar and camera back to Roblox's defaults.
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	end
	local currentCamera = activeCamera()
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end

	destroyAllyUnits()
	if planeModel then
		planeModel:Destroy()
		planeModel = nil
	end
	if hangar then
		hangar:Destroy()
		hangar = nil
	end
	hangarThemeId = nil
	hangarEggs = {}

	initialized = false
end

return Flight
