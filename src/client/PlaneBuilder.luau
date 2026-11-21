-- ============================================================================
--!nonstrict
-- PlaneBuilder: builds the player's plane, allies, bosses and pets from parts.
--
-- Shape language: everything is folded paper. Panels are thin wedges layered at
-- slightly different angles, fold lines are thin accent strips, and engines are
-- the only neon elements so the eye reads motion first.
--
-- Forward is -Z. Every plane exposes named parts so Flight can animate:
--   "AileronL" / "AileronR"  bank with steering
--   "Propeller"              spins while flying
--   "Glow"                   engine/exhaust emitter anchor

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local PlaneBuilder = {}

local PAPER = Enum.Material.SmoothPlastic
local FOIL = Enum.Material.Foil
local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local WOOD = Enum.Material.Wood

local function makePart(parent, className, name, size, cframe, color, material): BasePart
	local p = Instance.new(className)
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or PAPER
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Axis-aligned block at (x, y, z), optionally rotated (degrees).
local function block(parent, name, size, x, y, z, color, material, rx, ry, rz)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	return makePart(parent, "Part", name, size, cf, color, material)
end

local function wedge(parent, name, size, x, y, z, color, material, rx, ry, rz)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	return makePart(parent, "WedgePart", name, size, cf, color, material)
end

local function ball(parent, name, diameter, x, y, z, color, material)
	local p = makePart(
		parent,
		"Part",
		name,
		Vector3.new(diameter, diameter, diameter),
		CFrame.new(x, y, z),
		color,
		material
	)
	p.Shape = Enum.PartType.Ball
	return p
end

local function ellipsoid(parent, name, size, x, y, z, color, material, rx, ry, rz)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	local p = makePart(parent, "Part", name, size, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(parent, name, size, x, y, z, color, material, rx, ry, rz)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	local p = makePart(parent, "Part", name, size, cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function trim(parent, name, size, x, y, z, color, rx, ry, rz)
	return block(parent, name, size, x, y, z, color, NEON, rx, ry, rz)
end

-- A wing made of three tapering panels. Returns the aileron part.
local function wing(parent, side: number, opts)
	local color = opts.color
	local accent = opts.accent
	local rootX = opts.rootX or 1.2
	local span = opts.span or 3.0
	local sweep = opts.sweep or 10
	local dihedral = opts.dihedral or 4
	local thickness = opts.thickness or 0.16
	local chord = opts.chord or 3.4
	local y = opts.y or 0.1
	local z = opts.z or 0.2

	local x1 = side * (rootX + span * 0.5)
	local x2 = side * (rootX + span * 0.9)
	local x3 = side * (rootX + span * 1.25)

	local root = wedge(
		parent,
		"WingRoot",
		Vector3.new(span, thickness, chord),
		x1,
		y,
		z,
		color,
		PAPER,
		0,
		side * sweep * 0.35,
		side * dihedral
	)
	local mid = wedge(
		parent,
		"WingMid",
		Vector3.new(span * 0.8, thickness * 0.9, chord * 0.78),
		x2,
		y + 0.06,
		z + 0.25,
		color,
		PAPER,
		0,
		side * sweep * 0.7,
		side * dihedral * 1.15
	)
	wedge(
		parent,
		"WingTip",
		Vector3.new(span * 0.5, thickness * 0.8, chord * 0.55),
		x3,
		y + 0.12,
		z + 0.5,
		accent,
		PAPER,
		0,
		side * sweep,
		side * dihedral * 1.4
	)

	-- Fold lines: two thin strips that catch the light along the paper crease.
	block(parent, "FoldLine", Vector3.new(span * 0.95, 0.05, 0.08), x1, y + thickness * 0.55, z + 0.9, accent, PAPER)
	block(
		parent,
		"FoldLine2",
		Vector3.new(span * 0.7, 0.05, 0.08),
		x2,
		y + 0.1,
		z + 1.0,
		accent,
		PAPER,
		0,
		side * sweep * 0.7,
		side * dihedral * 1.15
	)

	-- Wingtip light.
	local light = block(parent, "WingLight", Vector3.new(0.28, 0.28, 0.28), x3, y + 0.2, z + 0.55, accent, NEON)

	-- Aileron sits behind the trailing edge and banks with the plane.
	local aileron = block(
		parent,
		if side > 0 then "AileronR" else "AileronL",
		Vector3.new(span * 0.85, 0.1, 0.75),
		x1,
		y,
		z + chord * 0.55,
		accent,
		PAPER,
		0,
		side * sweep * 0.35,
		side * dihedral
	)

	root.CanCollide = false
	return aileron, light
end

local function propeller(parent, x, y, z, color)
	local hub = block(parent, "PropHub", Vector3.new(0.3, 0.3, 0.3), x, y, z, color, FOIL)
	local disc = block(parent, "Propeller", Vector3.new(2.6, 2.6, 0.08), x, y, z - 0.12, color, GLASS, 0, 0, 0)
	disc.Transparency = 0.72
	disc.CastShadow = false
	return hub, disc
end

-- ---------------------------------------------------------------- planes ---
local builders = {}

builders.Classic = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_Classic"
	local c, a = config.Color, config.Accent

	-- Folded dart fuselage: three stacked wedges give a proper keel silhouette.
	local body = wedge(model, "Body", Vector3.new(1.9, 1.0, 5.6), 0, 0, 0, c, PAPER)
	wedge(model, "BodyTop", Vector3.new(1.5, 0.7, 4.2), 0, 0.45, 0.2, c, PAPER)
	wedge(model, "Nose", Vector3.new(1.1, 0.55, 2.0), 0, -0.05, -3.4, a, PAPER)
	block(model, "Keel", Vector3.new(0.12, 1.3, 3.4), 0, -0.55, 0.4, a, PAPER)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 3.2, chord = 3.6, sweep = 12, dihedral = 5, z = 0.3 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 3.2, chord = 3.6, sweep = 12, dihedral = 5, z = 0.3 })

	-- Tail assembly.
	wedge(model, "TailFin", Vector3.new(0.16, 1.7, 1.7), 0, 0.9, 2.5, c, PAPER)
	block(model, "TailFinTrim", Vector3.new(0.2, 0.25, 1.5), 0, 1.6, 2.6, a, NEON)
	wedge(model, "StabilizerL", Vector3.new(1.6, 0.12, 1.0), -1.5, 0.35, 2.5, c, PAPER, 0, -8, 0)
	wedge(model, "StabilizerR", Vector3.new(1.6, 0.12, 1.0), 1.5, 0.35, 2.5, c, PAPER, 0, 8, 0)

	-- Canopy and cockpit.
	local canopy = ellipsoid(model, "Canopy", Vector3.new(1.15, 0.8, 1.7), 0, 0.8, -0.6, Color3.fromRGB(170, 220, 255), GLASS)
	canopy.Transparency = 0.35
	block(model, "CockpitRim", Vector3.new(1.15, 0.12, 1.6), 0, 0.55, -0.6, a, PAPER)

	-- Paper pilot: two parts, just enough to read as a person at speed.
	ellipsoid(model, "PilotBody", Vector3.new(0.55, 0.7, 0.5), 0, 0.95, -0.15, Color3.fromRGB(60, 110, 200), PAPER)
	ball(model, "PilotHead", 0.44, 0, 1.42, -0.15, Color3.fromRGB(255, 205, 148), PAPER)

	-- Nose tip light and engine glow.
	block(model, "Glow", Vector3.new(0.5, 0.3, 0.3), 0, 0.05, -4.35, a, NEON)
	block(model, "EngineGlow", Vector3.new(0.7, 0.25, 0.7), 0, 0.1, 2.95, a, NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

builders.Glider = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_Glider"
	local c, a = config.Color, config.Accent

	-- No fuselage: a keel and a huge delta wing, like a paper hang glider.
	local body = block(model, "Body", Vector3.new(0.8, 0.5, 4.6), 0, 0, 0.2, c, PAPER)
	wedge(model, "Keel", Vector3.new(0.24, 1.1, 3.8), 0, -0.45, 0.4, a, PAPER)
	block(model, "Nose", Vector3.new(0.5, 0.3, 1.2), 0, 0, -2.4, a, PAPER)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 4.4, chord = 4.6, sweep = 6, dihedral = 7, rootX = 0.8 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 4.4, chord = 4.6, sweep = 6, dihedral = 7, rootX = 0.8 })

	-- Crossbar and hang strap.
	block(model, "Crossbar", Vector3.new(9.4, 0.16, 0.16), 0, 0.35, 0.3, a, FOIL)
	block(model, "StrapA", Vector3.new(0.1, 1.0, 0.1), -0.35, -0.35, -0.4, Color3.fromRGB(70, 70, 80), PAPER, 0, 0, 8)
	block(model, "StrapB", Vector3.new(0.1, 1.0, 0.1), 0.35, -0.35, -0.4, Color3.fromRGB(70, 70, 80), PAPER, 0, 0, -8)

	-- Tiny harness pilot.
	ellipsoid(model, "PilotBody", Vector3.new(0.5, 0.8, 0.45), 0, -0.9, -0.15, Color3.fromRGB(90, 160, 120), PAPER)
	ball(model, "PilotHead", 0.42, 0, -0.35, -0.15, Color3.fromRGB(255, 205, 148), PAPER)

	-- Tail ribbons.
	wedge(model, "Tail", Vector3.new(0.14, 1.1, 1.8), 0, 0.6, 2.6, a, PAPER)
	block(model, "Glow", Vector3.new(0.6, 0.2, 0.2), 0, 0.05, 2.9, a, NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

builders.Bomber = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_Bomber"
	local c, a = config.Color, config.Accent

	-- Boxy cardboard fuselage with visible corrugation strips.
	local body = block(model, "Body", Vector3.new(2.6, 2.0, 6.4), 0, 0, 0, c, PAPER)
	block(model, "Nose", Vector3.new(2.2, 1.6, 1.6), 0, -0.1, -3.6, a, PAPER)
	for i = -1, 1 do
		block(model, "Rib" .. i, Vector3.new(2.7, 0.12, 0.3), 0, 1.02, i * 1.8, Color3.fromRGB(110, 78, 50), PAPER)
	end
	block(model, "Belly", Vector3.new(2.0, 0.6, 4.6), 0, -1.05, 0.2, Color3.fromRGB(120, 85, 55), PAPER)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 3.6, chord = 3.2, sweep = 4, dihedral = 2, thickness = 0.3, rootX = 1.4 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 3.6, chord = 3.2, sweep = 4, dihedral = 2, thickness = 0.3, rootX = 1.4 })

	-- Twin engine nacelles with props.
	for i = -1, 1, 2 do
		cylinder(model, "Nacelle", Vector3.new(2.2, 0.95, 0.95), i * 2.6, 0.05, 0.4, a, FOIL, 0, 90, 0)
		propeller(model, i * 2.6, 0.05, -0.8, Color3.fromRGB(60, 60, 66))
	end

	-- Tail: big vertical fin plus stabilizers.
	wedge(model, "TailFin", Vector3.new(0.2, 2.1, 1.9), 0, 1.1, 2.9, c, PAPER)
	block(model, "TailFinTrim", Vector3.new(0.24, 0.3, 1.7), 0, 2.0, 3.0, a, NEON)
	block(model, "Stabilizer", Vector3.new(4.2, 0.18, 1.3), 0, 0.6, 3.0, c, PAPER)

	-- Cockpit glass and gun turret.
	local canopy = ellipsoid(model, "Canopy", Vector3.new(1.7, 0.95, 1.7), 0, 1.15, -1.7, Color3.fromRGB(170, 220, 255), GLASS)
	canopy.Transparency = 0.4
	ball(model, "Turret", 0.8, 0, -1.35, -1.4, a, FOIL)
	block(model, "Glow", Vector3.new(0.8, 0.3, 0.3), 0, 0, -4.45, a, NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

builders.OrigamiCrane = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_OrigamiCrane"
	local c, a = config.Color, config.Accent

	-- Long folded neck and swept crane wings.
	local body = wedge(model, "Body", Vector3.new(1.2, 0.9, 3.6), 0, 0, 0.4, c, PAPER)
	block(model, "Neck", Vector3.new(0.42, 2.0, 0.42), 0, 0.9, -2.2, c, PAPER, 14, 0, 0)
	block(model, "NeckTop", Vector3.new(0.38, 0.9, 0.38), 0, 1.9, -2.5, c, PAPER, 8, 0, 0)
	ellipsoid(model, "Head", Vector3.new(0.65, 0.6, 1.0), 0, 2.35, -2.8, a, PAPER)
	wedge(model, "Beak", Vector3.new(0.2, 0.2, 0.9), 0, 2.3, -3.4, Color3.fromRGB(255, 190, 90), PAPER)
	ball(model, "Eye", 0.18, -0.2, 2.45, -2.95, Color3.fromRGB(30, 30, 40), NEON)
	ball(model, "Eye2", 0.18, 0.2, 2.45, -2.95, Color3.fromRGB(30, 30, 40), NEON)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 3.8, chord = 3.0, sweep = 18, dihedral = 8, rootX = 0.8, z = 0.6 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 3.8, chord = 3.0, sweep = 18, dihedral = 8, rootX = 0.8, z = 0.6 })

	-- Fan tail.
	wedge(model, "TailFanL", Vector3.new(1.4, 0.1, 1.6), -0.8, 0.3, 2.6, a, PAPER, 0, -20, 0)
	wedge(model, "TailFanR", Vector3.new(1.4, 0.1, 1.6), 0.8, 0.3, 2.6, a, PAPER, 0, 20, 0)
	block(model, "Glow", Vector3.new(0.5, 0.25, 0.5), 0, 0.1, 2.9, a, NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

builders.Jetstream = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_Jetstream"
	local c, a = config.Color, config.Accent

	-- Sleek swept delta; the only plane with an obvious jet intake and nozzle.
	local body = wedge(model, "Body", Vector3.new(1.7, 0.9, 6.2), 0, 0, 0, c, PAPER)
	wedge(model, "Spine", Vector3.new(1.0, 0.5, 4.4), 0, 0.6, 0.4, c, PAPER)
	wedge(model, "Nose", Vector3.new(0.6, 0.6, 2.4), 0, 0, -3.9, a, FOIL)
	block(model, "Intake", Vector3.new(1.1, 0.5, 0.6), 0, -0.5, -2.6, Color3.fromRGB(40, 44, 52), FOIL)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 3.4, chord = 3.0, sweep = 26, dihedral = 3, rootX = 1.0 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 3.4, chord = 3.0, sweep = 26, dihedral = 3, rootX = 1.0 })

	-- Twin canted tails.
	wedge(model, "TailL", Vector3.new(0.14, 1.5, 1.5), -0.7, 0.9, 2.7, c, PAPER, 0, 0, 18)
	wedge(model, "TailR", Vector3.new(0.14, 1.5, 1.5), 0.7, 0.9, 2.7, c, PAPER, 0, 0, -18)
	block(model, "TailTrim", Vector3.new(1.7, 0.18, 0.2), 0, 1.55, 2.8, a, NEON)

	-- Canopy.
	local canopy = ellipsoid(model, "Canopy", Vector3.new(1.0, 0.68, 2.1), 0, 0.62, -1.2, Color3.fromRGB(120, 210, 255), GLASS)
	canopy.Transparency = 0.25

	-- Nozzle + afterburner glow.
	cylinder(model, "Nozzle", Vector3.new(0.5, 0.95, 0.95), 0, 0, 3.15, Color3.fromRGB(50, 52, 60), FOIL, 0, 90, 0)
	local glow = ball(model, "Glow", 0.75, 0, 0, 3.55, a, NEON)
	glow.Transparency = 0.15
	block(model, "Glow2", Vector3.new(0.45, 0.45, 1.2), 0, 0, 4.1, Color3.fromRGB(255, 255, 255), NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

builders.GoldenFold = function(config)
	local model = Instance.new("Model")
	model.Name = "Plane_GoldenFold"
	local c, a = config.Color, config.Accent

	-- Layered golden folds: three stacked wing layers, each slightly offset.
	local body = wedge(model, "Body", Vector3.new(1.8, 1.0, 5.8), 0, 0, 0, c, FOIL)
	wedge(model, "BodyTop", Vector3.new(1.4, 0.7, 4.6), 0, 0.5, 0, a, FOIL)

	local aileronL = wing(model, -1, { color = c, accent = a, span = 3.6, chord = 3.8, sweep = 14, dihedral = 6 })
	local aileronR = wing(model, 1, { color = c, accent = a, span = 3.6, chord = 3.8, sweep = 14, dihedral = 6 })

	-- Second and third wing layers for a feathered look.
	for layer = 1, 2 do
		local y = 0.18 + layer * 0.22
		local spread = 0.55 * layer
		wedge(model, "LayerL" .. layer, Vector3.new(2.4, 0.1, 2.6), -2.4 - spread, y, 0.9, a, FOIL, 0, 10, -4)
		wedge(model, "LayerR" .. layer, Vector3.new(2.4, 0.1, 2.6), 2.4 + spread, y, 0.9, a, FOIL, 0, -10, 4)
	end

	-- Crown tail.
	wedge(model, "TailFin", Vector3.new(0.18, 2.0, 1.9), 0, 1.1, 2.6, c, FOIL)
	block(model, "Crown", Vector3.new(1.1, 0.35, 0.35), 0, 2.05, 2.7, a, NEON)
	block(model, "CrownL", Vector3.new(0.3, 0.7, 0.3), -0.5, 2.2, 2.7, a, NEON, 0, 0, 22)
	block(model, "CrownR", Vector3.new(0.3, 0.7, 0.3), 0.5, 2.2, 2.7, a, NEON, 0, 0, -22)

	local canopy = ellipsoid(model, "Canopy", Vector3.new(1.05, 0.68, 1.6), 0, 0.75, -0.7, Color3.fromRGB(255, 240, 190), GLASS)
	canopy.Transparency = 0.3

	block(model, "Glow", Vector3.new(1.0, 0.4, 0.9), 0, 0, 2.95, a, NEON)
	block(model, "Glow2", Vector3.new(0.4, 0.4, 2.0), 0, 0, -3.2, Color3.fromRGB(255, 255, 255), NEON)

	model.PrimaryPart = body
	return model, aileronL, aileronR
end

-- ---------------------------------------------------------- finish details ---
-- Consistent small-scale aircraft details make each procedural silhouette read
-- as a finished vehicle rather than a stack of plain wedges. These details are
-- intentionally non-colliding and remain part of the model pivot.
local function addAircraftFinish(model: Model, config, planeId: string)
	local accent = config.Accent or Color3.fromRGB(220, 230, 245)
	local darkMetal = Color3.fromRGB(48, 54, 66)
	local lightMetal = Color3.fromRGB(176, 188, 204)

	-- Fold/paint bands on both wings and small insignia discs.
	for side = -1, 1, 2 do
		local stripe = block(model, "WingFinishStripe", Vector3.new(0.34, 0.075, 2.15), side * 3.35, 0.22, 0.05, accent, FOIL, 0, side * 8, side * 2)
		stripe.Transparency = 0.04
		local insignia = ellipsoid(model, "WingInsignia", Vector3.new(0.72, 0.12, 0.72), side * 4.05, 0.24, -0.45, accent, FOIL)
		insignia.Transparency = 0.08
		block(model, "WingTipMark", Vector3.new(0.42, 0.12, 0.62), side * 5.0, 0.25, 0.65, Color3.fromRGB(248, 246, 232), PAPER)
	end

	-- Reinforced belly rails and two runway wheels make the aircraft feel grounded.
	for side = -1, 1, 2 do
		block(model, "LandingStrut", Vector3.new(0.16, 0.9, 0.16), side * 0.82, -0.78, 0.78, lightMetal, FOIL, 0, 0, side * -8)
		local wheel = cylinder(model, "LandingWheel", Vector3.new(0.42, 0.72, 0.72), side * 0.82, -1.18, 0.78, darkMetal, FOIL)
		wheel.CanCollide = false
		cylinder(model, "WheelHub", Vector3.new(0.44, 0.24, 0.24), side * 0.82, -1.18, 0.78, lightMetal, FOIL)
	end

	-- Small navigation lamps and panel seams, color-coded by wing side.
	block(model, "NavigationLightL", Vector3.new(0.3, 0.24, 0.42), -5.05, 0.22, 0.65, Color3.fromRGB(255, 78, 78), NEON)
	block(model, "NavigationLightR", Vector3.new(0.3, 0.24, 0.42), 5.05, 0.22, 0.65, Color3.fromRGB(90, 220, 255), NEON)
	block(model, "RearPanelSeam", Vector3.new(0.12, 0.06, 1.2), 0, 0.5, 1.65, accent, FOIL)
	block(model, "NosePanelSeam", Vector3.new(0.08, 0.07, 1.1), 0, 0.48, -2.4, accent, FOIL)

	-- A second tail marker provides a readable silhouette from behind.
	local tail = model:FindFirstChild("TailFin", true)
	if tail and tail:IsA("BasePart") then
		block(model, "TailMark", Vector3.new(0.22, 0.35, 1.1), 0, 1.15, 2.7, accent, FOIL)
	end

	model:SetAttribute("FinishProfile", "PaperWings_Refined_01")
	model:SetAttribute("PlaneId", planeId)
end

-- ---------------------------------------------------------------- public ---
function PlaneBuilder.BuildPlane(planeId: string): Model
	local config = GameConfig.Planes[planeId] or GameConfig.Planes.Classic
	local build = builders[planeId] or builders.Classic
	local model, aileronL, aileronR = build(config)
	model.Name = "Plane_" .. planeId
	addAircraftFinish(model, config, planeId)

	-- Flight animates these; missing ones simply never move.
	if aileronL then
		aileronL:SetAttribute("BaseAngle", 0)
	end
	if aileronR then
		aileronR:SetAttribute("BaseAngle", 0)
	end
	model:SetAttribute("PlaneId", planeId)
	return model
end

-- ---------------------------------------------------------------- allies ---
local allyBuilders = {}

allyBuilders.Bird = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_Bird"
	local c = config.Color
	local body = ellipsoid(model, "Body", Vector3.new(0.8, 0.8, 2.0), 0, 0, 0, c, PAPER)
	ball(model, "Head", 0.62, 0, 0.08, -1.0, c, PAPER)
	wedge(model, "WingL", Vector3.new(2.2, 0.12, 1.5), -1.1, 0.1, 0.15, c, PAPER, 0, 18, -12)
	wedge(model, "WingR", Vector3.new(2.2, 0.12, 1.5), 1.1, 0.1, 0.15, c, PAPER, 0, -18, 12)
	wedge(model, "Tail", Vector3.new(0.7, 0.1, 0.9), 0, 0.05, 1.1, c, PAPER)
	block(model, "Beak", Vector3.new(0.18, 0.18, 0.5), 0, 0.1, -1.35, Color3.fromRGB(255, 190, 90), PAPER)
	ball(model, "EyeL", 0.14, -0.2, 0.22, -1.2, Color3.fromRGB(30, 30, 40), NEON)
	ball(model, "EyeR", 0.14, 0.2, 0.22, -1.2, Color3.fromRGB(30, 30, 40), NEON)
	model.PrimaryPart = body
	return model
end

allyBuilders.Wingman = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_Wingman"
	local c = config.Color
	local body = wedge(model, "Body", Vector3.new(0.7, 0.4, 2.6), 0, 0, 0, c, PAPER)
	local aileronL = wing(model, -1, { color = c, accent = Color3.fromRGB(255, 255, 255), span = 1.3, chord = 1.4, sweep = 10, dihedral = 4, rootX = 0.35, thickness = 0.1, z = 0.2 })
	local aileronR = wing(model, 1, { color = c, accent = Color3.fromRGB(255, 255, 255), span = 1.3, chord = 1.4, sweep = 10, dihedral = 4, rootX = 0.35, thickness = 0.1, z = 0.2 })
	wedge(model, "Tail", Vector3.new(0.12, 0.6, 0.7), 0, 0.3, 1.1, c, PAPER)
	block(model, "Glow", Vector3.new(0.3, 0.2, 0.3), 0, 0, 1.3, Color3.fromRGB(255, 220, 120), NEON)
	model.PrimaryPart = body
	return model
end

allyBuilders.InkSpirit = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_InkSpirit"
	local c = config.Color
	local body = ball(model, "Body", 1.5, 0, 0, 0, c, NEON)
	body.Transparency = 0.15
	-- Wobbly droplets orbiting the core.
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2
		local drop = ball(
			model,
			"Drop" .. i,
			0.5,
			math.cos(angle) * 1.0,
			math.sin(angle * 1.3) * 0.5,
			math.sin(angle) * 1.0,
			config.Accent,
			NEON
		)
		drop.Transparency = 0.25
	end
	ball(model, "EyeL", 0.36, -0.4, 0.25, -0.72, Color3.fromRGB(255, 255, 255), NEON)
	ball(model, "EyeR", 0.36, 0.4, 0.25, -0.72, Color3.fromRGB(255, 255, 255), NEON)
	model.PrimaryPart = body
	return model
end

allyBuilders.Dragon = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_Dragon"
	local c = config.Color
	local body = ellipsoid(model, "Body", Vector3.new(1.2, 1.2, 3.0), 0, 0, 0, c, PAPER)
	ball(model, "Head", 0.95, 0, 0.15, -1.8, c, PAPER)
	ellipsoid(model, "Snout", Vector3.new(0.55, 0.45, 0.75), 0, 0.05, -2.4, config.Accent, PAPER)
	wedge(model, "WingL", Vector3.new(2.8, 0.14, 1.9), -1.5, 0.15, 0, c, PAPER, 0, 20, -14)
	wedge(model, "WingR", Vector3.new(2.8, 0.14, 1.9), 1.5, 0.15, 0, c, PAPER, 0, -20, 14)
	ball(model, "EyeL", 0.2, -0.26, 0.3, -2.05, Color3.fromRGB(255, 230, 120), NEON)
	ball(model, "EyeR", 0.2, 0.26, 0.3, -2.05, Color3.fromRGB(255, 230, 120), NEON)
	for i = 1, 3 do
		ball(model, "Tail" .. i, 0.55 - i * 0.1, 0, 0.05 + i * 0.06, 1.6 + i * 0.5, c, PAPER)
	end
	block(model, "Glow", Vector3.new(0.5, 0.3, 0.4), 0, 0, -2.7, Color3.fromRGB(255, 140, 60), NEON)
	model.PrimaryPart = body
	return model
end

allyBuilders.PaperWolf = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_PaperWolf"
	local c = config.Color
	local body = ellipsoid(model, "Body", Vector3.new(0.9, 0.9, 2.4), 0, 0, 0, c, PAPER)
	ball(model, "Head", 0.8, 0, 0.25, -1.4, c, PAPER)
	ellipsoid(model, "Snout", Vector3.new(0.45, 0.4, 0.65), 0, 0.15, -1.95, config.Accent, PAPER)
	ellipsoid(model, "EarL", Vector3.new(0.26, 0.46, 0.26), -0.24, 0.62, -1.3, config.Accent, PAPER, 0, 0, 12)
	ellipsoid(model, "EarR", Vector3.new(0.26, 0.46, 0.26), 0.24, 0.62, -1.3, config.Accent, PAPER, 0, 0, -12)
	wedge(model, "WingL", Vector3.new(1.6, 0.12, 1.2), -0.9, 0.1, 0.5, c, PAPER, 0, 14, -10)
	wedge(model, "WingR", Vector3.new(1.6, 0.12, 1.2), 0.9, 0.1, 0.5, c, PAPER, 0, -14, 10)
	ellipsoid(model, "Tail", Vector3.new(0.34, 0.34, 1.2), 0, 0.3, 1.5, config.Accent, PAPER, -16, 0, 0)
	ball(model, "EyeL", 0.15, -0.22, 0.32, -1.65, Color3.fromRGB(255, 220, 120), NEON)
	ball(model, "EyeR", 0.15, 0.22, 0.32, -1.65, Color3.fromRGB(255, 220, 120), NEON)
	model.PrimaryPart = body
	return model
end

allyBuilders.StarMoth = function(config)
	local model = Instance.new("Model")
	model.Name = "Ally_StarMoth"
	local c = config.Color
	local body = ellipsoid(model, "Body", Vector3.new(0.8, 0.8, 1.8), 0, 0, 0, c, NEON)
	-- Two large angled wing plates with glowing edges.
	for side = -1, 1, 2 do
		local w = wedge(model, "Wing" .. side, Vector3.new(3.4, 0.12, 2.6), side * 1.7, 0.1, 0, c, GLASS, 0, side * -22, side * 6)
		w.Transparency = 0.25
		block(model, "WingEdge" .. side, Vector3.new(3.2, 0.08, 0.12), side * 1.7, 0.14, 0.9, config.Accent, NEON, 0, side * -22, 0)
	end
	ball(model, "Head", 0.5, 0, 0.1, -1.0, config.Accent, NEON)
	block(model, "AntennaL", Vector3.new(0.06, 0.7, 0.06), -0.2, 0.6, -1.2, config.Accent, NEON, 0, 0, 18)
	block(model, "AntennaR", Vector3.new(0.06, 0.7, 0.06), 0.2, 0.6, -1.2, config.Accent, NEON, 0, 0, -18)
	model.PrimaryPart = body
	return model
end

function PlaneBuilder.BuildAlly(allyId: string): Model
	local config = GameConfig.Allies[allyId]
	local build = allyBuilders[allyId]
	if not config or not build then
		return nil :: any
	end
	local model = build(config)
	model.Name = "Ally_" .. allyId
	return model
end

return PlaneBuilder
