-- ============================================================================
--!nonstrict
-- Effects: tracers, bursts, floating numbers, screen flashes and sound.
--
-- Every effect cleans itself up. Sound IDs are left blank until you upload
-- audio to Roblox and paste the asset IDs; nothing errors when an ID is empty.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Effects = {}

local MUSIC_TRACKS = {
	town = "",
	canyon = "",
	ocean = "",
	storm = "",
	clouds = "",
	fold = "",
}
local currentMusic: Sound? = nil
local currentMusicKey: string? = nil

local SOUNDS = {
	Fire = "",
	Hit = "",
	Explosion = "",
	Coin = "",
	Boost = "",
	Click = "",
	Upgrade = "",
	Death = "",
	Boss = "",
}

local folder: Folder
local function ensureFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "FlightEffects"
		folder.Parent = workspace
	end
	return folder
end

local function part(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, lifetime: number): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ensureFolder()
	Debris:AddItem(p, lifetime)
	return p
end

function Effects.Play(name: string, pitch: number?, volume: number?)
	local id = SOUNDS[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = (pitch or 1) * (0.94 + math.random() * 0.12)
	sound.Volume = volume or 0.4
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

function Effects.PlayMusic(trackName: string?)
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

function Effects.MuzzleFlash(origin: Vector3, direction: Vector3, color: Color3?)
	if direction.Magnitude < 1e-4 then
		return
	end
	local c = color or Color3.fromRGB(255, 230, 160)
	local flash = part(
		Vector3.new(0.52, 0.52, 1.25),
		CFrame.lookAt(origin, origin + direction.Unit),
		c,
		Enum.Material.Neon,
		0.075
	)
	flash.Transparency = 0.12
	TweenService:Create(flash, TweenInfo.new(0.075, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, 0.08, 1.8),
		Transparency = 1,
	}):Play()
end

function Effects.Tracer(fromPos: Vector3, toPos: Vector3, color: Color3?)
	local delta = toPos - fromPos
	local dist = delta.Magnitude
	if dist < 0.2 then
		return
	end
	local c = color or Color3.fromRGB(255, 255, 255)
	local beam = part(Vector3.new(0.38, 0.38, dist), CFrame.lookAt(fromPos, toPos) * CFrame.new(0, 0, -dist * 0.5), c, Enum.Material.Neon, 0.19)
	TweenService:Create(beam, TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.025, 0.025, dist),
		Transparency = 1,
	}):Play()
end

function Effects.Burst(origin: Vector3, color: Color3?, count: number?, speed: number?)
	local c = color or Color3.fromRGB(255, 210, 90)
	local n = count or 10
	local spd = speed or 14
	for _ = 1, n do
		local dir = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
		if dir.Magnitude < 0.05 then
			dir = Vector3.yAxis
		else
			dir = dir.Unit
		end
		local s = 0.45 + math.random() * 0.55
		local p = part(Vector3.new(s, s, s), CFrame.new(origin) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), c, Enum.Material.Neon, 0.35)
		local target = origin + dir * (spd * (0.5 + math.random() * 0.7))
		TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = target,
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		}):Play()
	end
end

function Effects.Explosion(origin: Vector3, color: Color3?, radius: number?)
	local c = color or Color3.fromRGB(255, 190, 80)
	local r = radius or 16
	local ring = part(Vector3.new(1, 1, 1), CFrame.new(origin), c, Enum.Material.Neon, 0.35)
	ring.Shape = Enum.PartType.Ball
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(r, r, r),
		Transparency = 1,
	}):Play()
	Effects.Burst(origin, c, 18, r * 0.9)
end

function Effects.Impact(origin: Vector3, color: Color3?)
	local c = color or Color3.fromRGB(255, 230, 150)
	local flash = part(Vector3.new(0.7, 0.7, 0.7), CFrame.new(origin), c, Enum.Material.Neon, 0.18)
	flash.Shape = Enum.PartType.Ball
	TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.2, 4.2, 4.2),
		Transparency = 1,
	}):Play()
	Effects.Burst(origin, c, 7, 8)
end

function Effects.CoinPop(origin: Vector3)
	Effects.Burst(origin, Color3.fromRGB(255, 210, 75), 6, 9)
end

function Effects.ReviveBurst(origin: Vector3)
	Effects.Explosion(origin, Color3.fromRGB(110, 235, 160), 22)
end

function Effects.DeathBurst(origin: Vector3)
	Effects.Explosion(origin, Color3.fromRGB(255, 95, 95), 26)
end

function Effects.DamageNumber(origin: Vector3, amount: number, color: Color3?)
	local anchor = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(origin + Vector3.new(math.random() * 3 - 1.5, 2, 0)), color or Color3.new(1, 1, 1), Enum.Material.Neon, 0.7)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 34)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 20
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	label.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 5, 0),
	}):Play()
	task.delay(0.35, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- Aircraft speed trail
function Effects.AttachTrail(target: BasePart, color: Color3?, lifetime: number?)
	if not target or not target:IsA("BasePart") then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "FlightTrailTop"
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = target

	local a1 = Instance.new("Attachment")
	a1.Name = "FlightTrailBottom"
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = target

	local trail = Instance.new("Trail")
	trail.Name = "FlightSpeedTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Lifetime = math.clamp(lifetime or 0.3, 0.05, 2)
	trail.WidthScale = NumberSequence.new(0.8, 0.05)
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.Parent = target

	return trail
end

-- Aircraft engine exhaust
function Effects.AttachExhaust(target: BasePart, color: Color3?)
	if not target or not target:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightExhaustAttachment"
	attachment.Parent = target

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FlightExhaust"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(
		color or Color3.fromRGB(255, 220, 150),
		Color3.fromRGB(255, 110, 45)
	)
	emitter.Rate = 24
	emitter.Lifetime = NumberRange.new(0.12, 0.28)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.LightEmission = 0.85
	emitter.Size = NumberSequence.new(0.45, 0)
	emitter.Transparency = NumberSequence.new(0.15, 1)
	emitter.Parent = attachment

	return emitter
end

return Effects