-- ============================================================================
--!nonstrict
-- WorldBuilder: procedural paper-craft scenery, enemies, bosses and pickups.
--
-- Each zone has its own recipe (`Style`) so the world changes character every
-- few thousand metres instead of only changing colour. Everything is built from
-- parts, so it streams in instantly and costs nothing to download.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local WorldBuilder = {}

local PAPER = Enum.Material.SmoothPlastic
local FOIL = Enum.Material.Foil
local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local WOOD = Enum.Material.Wood
local FABRIC = Enum.Material.Fabric
local GRASS = Enum.Material.Grass
local METAL = Enum.Material.CorrodedMetal

-- ------------------------------------------------------------- primitives ---
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

local function part(parent, name, size, pos, color, material, rx, ry, rz)
	local cf = CFrame.new(pos) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	return makePart(parent, "Part", name, size, cf, color, material)
end

local function wedge(parent, name, size, pos, color, material, rx, ry, rz)
	local cf = CFrame.new(pos) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	return makePart(parent, "WedgePart", name, size, cf, color, material)
end

local function ball(parent, name, diameter, pos, color, material)
	return makePart(parent, "Part", name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, material)
end

local function ellipsoid(parent, name, size, pos, color, material, rx, ry, rz)
	local p = makePart(
		parent,
		"Part",
		name,
		size,
		CFrame.new(pos) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0)),
		color,
		material
	)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(parent, name, size, pos, color, material, rx, ry, rz)
	local p = makePart(
		parent,
		"Part",
		name,
		size,
		CFrame.new(pos) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0)),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Uniformly scale a finished model around its primary part.
local function scaleModel(model: Model, scale: number)
	if scale == 1 or not model.PrimaryPart then
		return
	end
	local origin = model.PrimaryPart.CFrame
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= model.PrimaryPart then
			local offset = origin:PointToObjectSpace(d.CFrame.Position)
			d.CFrame = origin * CFrame.new(offset * scale) * (d.CFrame - d.CFrame.Position)
			d.Size = d.Size * scale
		end
	end
	model.PrimaryPart.Size = model.PrimaryPart.Size * scale
end

-- ---------------------------------------------------------------- clouds ---
function WorldBuilder.BuildCloud(position: Vector3, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Cloud"
	local white = Color3.fromRGB(255, 255, 255)
	local shade = Color3.fromRGB(224, 233, 244)
	local offsets = {
		{ Vector3.new(0, 0, 0), 4.6 },
		{ Vector3.new(3.6, 0.4, 0.5), 3.4 },
		{ Vector3.new(-3.7, 0.2, -0.4), 3.2 },
		{ Vector3.new(1.6, 1.0, 0.7), 2.8 },
		{ Vector3.new(-1.8, 0.9, -0.6), 2.6 },
		{ Vector3.new(0.2, -0.7, 0.2), 3.8 },
	}
	for i, entry in ipairs(offsets) do
		local size = entry[2] * scale
		local puff = ball(model, "Puff" .. i, size, position + entry[1] * scale, if i % 2 == 0 then shade else white, PAPER)
		puff.Size = Vector3.new(size, size * 0.62, size)
		puff.CastShadow = false
	end
	return model
end

-- ------------------------------------------------------------ zone pieces ---
local function groundStrip(parent, pathColor, groundColor, halfLength, centerZ, pathWidth)
	part(parent, "Path", Vector3.new(pathWidth, 1, halfLength * 2), Vector3.new(0, 0.2, centerZ), pathColor, PAPER)
	part(parent, "Ground", Vector3.new(420, 2, halfLength * 2), Vector3.new(0, -1, centerZ), groundColor, GRASS)
end

local function buildHouse(parent, position, wallColor, roofColor, rng)
	local house = Instance.new("Model")
	house.Name = "House"
	local w = 11 + rng:NextNumber() * 5
	local d = 10 + rng:NextNumber() * 4
	local h = 8 + rng:NextNumber() * 5

	part(house, "Walls", Vector3.new(w, h, d), position + Vector3.new(0, h / 2, 0), wallColor, PAPER)

	-- Low gable roof: two sloped panels with a ridge and eave trim. The edges
	-- are crisp paper folds, not tubes or cylinders.
	local roofHeight = h * 0.42
	local halfSpan = w / 2 + 1.2
	local slopeLength = math.sqrt(halfSpan * halfSpan + roofHeight * roofHeight)
	local roofAngle = math.atan2(roofHeight, halfSpan)
	for side = -1, 1, 2 do
		local roofCenter = position + Vector3.new(side * halfSpan / 2, h + roofHeight / 2, 0)
		local slab = part(house, "Roof", Vector3.new(slopeLength, 0.45, d + 2.4), roofCenter, roofColor, PAPER)
		slab.CFrame = CFrame.new(roofCenter) * CFrame.Angles(0, 0, -side * roofAngle)
		part(
			house,
			"EaveTrim",
			Vector3.new(0.45, 0.32, d + 2.6),
			position + Vector3.new(side * halfSpan, h + 0.16, 0),
			roofColor:Lerp(Color3.fromRGB(0, 0, 0), 0.18),
			PAPER
		)
	end
	part(house, "RoofCap", Vector3.new(0.9, 0.42, d + 2.6), position + Vector3.new(0, h + roofHeight, 0), roofColor:Lerp(Color3.fromRGB(0, 0, 0), 0.12), PAPER)
	for _, side in ipairs({ -1, 1 }) do
		part(
			house,
			"Gable",
			Vector3.new(w * 0.62, roofHeight * 0.58, 0.5),
			position + Vector3.new(0, h + roofHeight * 0.29, side * (d / 2 + 0.05)),
			wallColor,
			PAPER
		)
	end

	local doorColor = Color3.fromRGB(120, 82, 52)
	part(house, "Door", Vector3.new(2.6, 4.2, 0.4), position + Vector3.new(0, 2.1, d / 2 + 0.2), doorColor, WOOD)
	part(house, "DoorLintel", Vector3.new(3.2, 0.35, 0.6), position + Vector3.new(0, 4.3, d / 2 + 0.22), doorColor, WOOD)
	for _, side in ipairs({ -1, 1 }) do
		part(house, "DoorTrim", Vector3.new(0.28, 4.4, 0.6), position + Vector3.new(side * 1.45, 2.2, d / 2 + 0.22), doorColor, WOOD)
	end

	local glass = Color3.fromRGB(160, 214, 244)
	for _, side in ipairs({ -1, 1 }) do
		local windowPos = position + Vector3.new(side * w * 0.3, h * 0.62, d / 2 + 0.14)
		part(house, "WindowFrame" .. side, Vector3.new(3.2, 3.1, 0.3), windowPos, Color3.fromRGB(242, 238, 228), PAPER)
		part(house, "Window" .. side, Vector3.new(2.5, 2.4, 0.36), windowPos + Vector3.new(0, 0, 0.08), glass, GLASS)
		part(house, "WindowMullionV" .. side, Vector3.new(0.16, 2.4, 0.4), windowPos + Vector3.new(0, 0, 0.12), Color3.fromRGB(242, 238, 228), PAPER)
		part(house, "WindowMullionH" .. side, Vector3.new(2.5, 0.16, 0.4), windowPos + Vector3.new(0, 0, 0.12), Color3.fromRGB(242, 238, 228), PAPER)
		part(house, "WindowSill" .. side, Vector3.new(3.5, 0.25, 0.7), windowPos + Vector3.new(0, -1.7, 0.16), Color3.fromRGB(242, 238, 228), PAPER)
	end

	local chimneyTop = h + roofHeight * 0.62 + 1.55
	part(
		house,
		"Chimney",
		Vector3.new(1.5, 3.4, 1.5),
		position + Vector3.new(w * 0.28, chimneyTop - 1.7, -d * 0.18),
		Color3.fromRGB(170, 92, 78),
		PAPER
	)
	part(
		house,
		"ChimneyCap",
		Vector3.new(1.9, 0.3, 1.9),
		position + Vector3.new(w * 0.28, chimneyTop, -d * 0.18),
		Color3.fromRGB(140, 76, 66),
		PAPER
	)

	-- Paper-strip fence in front.
	local fenceColor = Color3.fromRGB(230, 224, 210)
	for i = -2, 2 do
		part(
			house,
			"FencePost",
			Vector3.new(0.28, 2.0, 0.28),
			position + Vector3.new(i * 2.4, 1.0, d / 2 + 2.2),
			fenceColor,
			PAPER
		)
	end
	for _, y in ipairs({ 0.65, 1.5 }) do
		part(
			house,
			"FenceRail",
			Vector3.new(w * 0.8, 0.22, 0.22),
			position + Vector3.new(0, y, d / 2 + 2.2),
			fenceColor,
			PAPER
		)
	end

	house.Parent = parent
	return house
end

local function buildTree(parent, position, leafColor, rng)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	local height = 5 + rng:NextNumber() * 3
	cylinder(tree, "Trunk", Vector3.new(height, 1.2, 1.2), position + Vector3.new(0, height / 2, 0), Color3.fromRGB(122, 84, 52), WOOD, 0, 0, 90)
	local crownY = height + 0.9
	ellipsoid(tree, "Canopy", Vector3.new(7.2, 6.0, 7.2), position + Vector3.new(0, crownY, 0), leafColor, GRASS)
	local side = if rng:NextNumber() > 0.5 then 1 else -1
	ellipsoid(
		tree,
		"CanopySide",
		Vector3.new(4.8, 4.2, 4.8),
		position + Vector3.new(side * 1.9, crownY + 0.7, 0.5),
		leafColor:Lerp(Color3.fromRGB(40, 70, 40), 0.08),
		GRASS
	)
	ellipsoid(
		tree,
		"CanopyTop",
		Vector3.new(4.2, 3.6, 4.2),
		position + Vector3.new(-side * 0.9, crownY + 1.7, -0.4),
		leafColor:Lerp(Color3.fromRGB(255, 255, 255), 0.06),
		GRASS
	)
	tree.Parent = parent
	return tree
end

local function buildPencil(parent, position, color, height)
	local pencil = Instance.new("Model")
	pencil.Name = "Pencil"
	cylinder(pencil, "Body", Vector3.new(height, 2.4, 2.4), position + Vector3.new(0, height / 2, 0), color, PAPER, 0, 0, 90)
	cylinder(pencil, "Tip", Vector3.new(1.5, 2.6, 2.6), position + Vector3.new(0, height + 0.7, 0), Color3.fromRGB(240, 205, 130), PAPER, 0, 0, 90)
	cylinder(pencil, "Lead", Vector3.new(1.0, 1.2, 1.2), position + Vector3.new(0, height + 1.7, 0), Color3.fromRGB(70, 68, 76), PAPER, 0, 0, 90)
	pencil.Parent = parent
	return pencil
end

local function buildNotebook(parent, position, color, size, rng)
	local nb = Instance.new("Model")
	nb.Name = "Notebook"
	part(nb, "Cover", size, position, color, PAPER)
	part(
		nb,
		"Pages",
		size * Vector3.new(0.94, 1.0, 0.94) + Vector3.new(0, 0.5, 0),
		position + Vector3.new(0, 0.55, 0),
		Color3.fromRGB(255, 255, 255),
		PAPER
	)
	-- Spiral binding along one edge.
	local count = math.clamp(math.floor(size.Z / 2.2), 3, 12)
	for i = 1, count do
		local z = position.Z - size.Z / 2 + (i - 0.5) * (size.Z / count)
		cylinder(nb, "Ring" .. i, Vector3.new(1.4, 0.3, 0.3), Vector3.new(position.X - size.X / 2 - 0.2, position.Y + size.Y / 2 + 0.2, z), Color3.fromRGB(150, 156, 170), METAL, 0, 0, 90)
	end
	nb.Parent = parent
	return nb
end

local function buildScissor(parent, position, scale, rng)
	local sc = Instance.new("Model")
	sc.Name = "Scissor"
	local metal = Color3.fromRGB(198, 202, 212)
	local handle = Color3.fromRGB(90, 150, 210)
	local blade = 9 * scale
	wedge(sc, "BladeA", Vector3.new(0.5 * scale, blade, 1.2 * scale), position + Vector3.new(0, 0, 0), metal, FOIL, 0, 0, 22)
	wedge(sc, "BladeB", Vector3.new(0.5 * scale, blade, 1.2 * scale), position + Vector3.new(0, 0, 0), metal, FOIL, 0, 0, -22)
	part(sc, "Pivot", Vector3.new(1.6, 1.6, 1.6) * scale, position + Vector3.new(0, -blade * 0.5, 0), Color3.fromRGB(120, 124, 134), METAL)
	cylinder(sc, "HandleL", Vector3.new(0.7, 3.4, 3.4) * scale, position + Vector3.new(-1.4, -blade * 0.85, 0) * scale, handle, PAPER, 0, 0, 90)
	cylinder(sc, "HandleR", Vector3.new(0.7, 3.4, 3.4) * scale, position + Vector3.new(1.4, -blade * 0.85, 0) * scale, handle, PAPER, 0, 0, 90)
	sc.Parent = parent
	return sc
end

local function buildInkwell(parent, position, scale)
	local ink = Instance.new("Model")
	ink.Name = "Inkwell"
	local dark = Color3.fromRGB(26, 22, 52)
	part(ink, "Bottle", Vector3.new(12, 14, 12) * scale, position + Vector3.new(0, 7 * scale, 0), dark, GLASS)
	part(ink, "Neck", Vector3.new(6, 5, 6) * scale, position + Vector3.new(0, 16 * scale, 0), dark, GLASS)
	cylinder(ink, "Cap", Vector3.new(2, 8, 8) * scale, position + Vector3.new(0, 19 * scale, 0), Color3.fromRGB(190, 170, 120), PAPER)
	part(ink, "Label", Vector3.new(8, 5, 0.3) * scale, position + Vector3.new(0, 8 * scale, 6.1 * scale), Color3.fromRGB(240, 236, 220), PAPER)
	ink.Parent = parent
	return ink
end

-- --------------------------------------------------------------- recipes ---
local recipes = {}

recipes.town = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 34)

	-- Gentle rolling hills behind the houses.
	for i = 1, 4 do
		local side = if i % 2 == 0 then 1 else -1
		ellipsoid(
			parent,
			"Hill" .. i,
			Vector3.new(130, 44, 96),
			Vector3.new(side * (150 + rng:NextInteger(0, 60)), -12, centerZ + rng:NextNumber(-halfLength, halfLength)),
			Color3.fromRGB(112, 178, 96),
			GRASS,
			0,
			rng:NextNumber(0, 90),
			0
		)
	end

	for i = 1, 7 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (34 + rng:NextInteger(0, 42))
		local z = centerZ - halfLength + (i + rng:NextNumber()) * (halfLength * 2 / 8)
		buildHouse(
			parent,
			Vector3.new(x, 0, z),
			Color3.fromRGB(226, 196, 150),
			Color3.fromHSV(rng:NextNumber(), 0.55, 0.8),
			rng
		)
	end

	for i = 1, 10 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (24 + rng:NextInteger(6, 34))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		buildTree(parent, Vector3.new(x, 0, z), Color3.fromRGB(92, 166, 86), rng)
	end

	-- Hanging cranes and clouds in the sky.
	for i = 1, 3 do
		local x = rng:NextNumber(-55, 55)
		local y = 42 + rng:NextNumber(0, 26)
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local crane = part(parent, "Crane", Vector3.new(9, 0.8, 9), Vector3.new(x, y, z), Color3.fromRGB(255, 255, 255), PAPER, 12, rng:NextNumber(0, 360), -10)
		crane.Name = "Crane"
	end
end

recipes.desk = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 38)

	-- Giant pencils sticking up like pillars, stacked notebooks, scissors and inkwells.
	local pencilColors = { Color3.fromRGB(255, 200, 50), Color3.fromRGB(80, 160, 240), Color3.fromRGB(235, 90, 90) }
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (32 + rng:NextInteger(0, 48))
		local z = centerZ - halfLength + (i + rng:NextNumber()) * (halfLength * 2 / 9)
		local c = pencilColors[((i - 1) % #pencilColors) + 1]
		buildPencil(parent, Vector3.new(x, 0, z), c, 18 + rng:NextNumber() * 18)
	end

	for i = 1, 6 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (30 + rng:NextInteger(0, 36))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		buildNotebook(parent, Vector3.new(x, 2, z), Color3.fromHSV(rng:NextNumber(), 0.5, 0.85), Vector3.new(18, 2.5, 24), rng)
	end

	for i = 1, 3 do
		local side = if i % 2 == 0 then 1 else -1
		buildScissor(parent, Vector3.new(side * (42 + i * 8), 8 + i * 4, centerZ + (i - 2) * 50), 1.4, rng)
	end

	for i = 1, 3 do
		local side = if i % 2 == 0 then 1 else -1
		buildInkwell(parent, Vector3.new(side * 46, 0, centerZ + rng:NextNumber(-halfLength, halfLength)), 1.3)
	end
end

recipes.canyon = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 34)

	-- Red-rock mesas and folded arches framing the corridor.
	local rock = Color3.fromRGB(204, 118, 76)
	local rockDark = Color3.fromRGB(168, 86, 54)
	for i = 1, 6 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (44 + rng:NextInteger(0, 44))
		local z = centerZ - halfLength + (i + rng:NextNumber()) * (halfLength * 2 / 7)
		local h = 24 + rng:NextNumber() * 26
		part(parent, "Mesa", Vector3.new(28, h, 32), Vector3.new(x, h / 2, z), rock, PAPER)
		part(parent, "MesaCap", Vector3.new(30, 3, 34), Vector3.new(x, h + 1.5, z), rockDark, PAPER)
	end

	-- Overhead folded ribbon arch.
	local arch = part(parent, "RibbonArch", Vector3.new(110, 4, 12), Vector3.new(0, 56, centerZ), Color3.fromRGB(240, 178, 120), PAPER, 0, 0, 0)
	arch.Name = "RibbonArch"
end

recipes.city = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 40)

	-- Tall paper towers with glowing trim bands.
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (36 + rng:NextInteger(0, 42))
		local z = centerZ - halfLength + (i + rng:NextNumber()) * (halfLength * 2 / 9)
		local h = 38 + rng:NextNumber() * 54
		part(parent, "Tower", Vector3.new(18, h, 18), Vector3.new(x, h / 2, z), Color3.fromRGB(220, 232, 248), PAPER)
		part(parent, "NeonBand", Vector3.new(18.6, 1.5, 18.6), Vector3.new(x, h * 0.75, z), zone.Accent, NEON)
	end
end

recipes.void = function(parent, zone, centerZ, halfLength, rng)
	-- Floating paper islands and neon rings in dark space; no ground.
	for i = 1, 10 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (24 + rng:NextInteger(0, 68))
		local y = 8 + rng:NextNumber() * 44
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		part(parent, "Island", Vector3.new(16, 4, 16), Vector3.new(x, y, z), Color3.fromRGB(54, 48, 86), PAPER, rng:NextNumber(-15, 15), rng:NextNumber(0, 360), rng:NextNumber(-15, 15))
		part(parent, "GlowRing", Vector3.new(18, 0.6, 18), Vector3.new(x, y + 2.2, z), zone.Accent, NEON)
	end
end

recipes.ocean = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 44)
	local deep = Color3.fromRGB(23, 38, 78)
	-- Layered islands, sea stacks and luminous tide markers give this zone a
	-- recognizable silhouette without putting scenery in the flight lane.
	for i = 1, 9 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (42 + rng:NextInteger(0, 32))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local width = rng:NextNumber(16, 28)
		local height = rng:NextNumber(10, 24)
		part(parent, "InkSeaStack", Vector3.new(width, height, width * 1.2), Vector3.new(x, height * 0.5 - 1, z), deep, FOIL, rng:NextNumber(-8, 8), rng:NextNumber(0, 360), rng:NextNumber(-8, 8))
		part(parent, "SeaFoamCap", Vector3.new(width * 1.08, 1.2, width * 1.28), Vector3.new(x, height + 0.1, z), zone.Accent, NEON)
	end
	for i = 1, 5 do
		local x = (if i % 2 == 0 then -1 else 1) * (38 + i * 5)
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local column = cylinder(parent, "TideBeacon", Vector3.new(20, 2.2, 2.2), Vector3.new(x, 10, z), Color3.fromRGB(62, 72, 112), FOIL, 0, 0, 90)
		part(parent, "BeaconLight", Vector3.new(2.8, 2.8, 2.8), Vector3.new(x, 21, z), zone.Accent, NEON)
		column.Name = "TideBeacon"
	end
	for i = 1, 4 do
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local x = rng:NextNumber(-30, 30)
		local ring = cylinder(parent, "CurrentRing", Vector3.new(0.6, 18, 18), Vector3.new(x, 26 + rng:NextNumber(0, 10), z), zone.Accent, NEON, 0, 0, 90)
		ring.Transparency = 0.35
	end
end

recipes.storm = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 42)
	local stormDark = Color3.fromRGB(36, 38, 54)
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (42 + rng:NextInteger(0, 42))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local h = rng:NextNumber(28, 58)
		part(parent, "StormSpire", Vector3.new(rng:NextNumber(10, 18), h, 16), Vector3.new(x, h * 0.5, z), stormDark, FOIL, rng:NextNumber(-12, 12), rng:NextNumber(-20, 20), rng:NextNumber(-12, 12))
		part(parent, "StormCap", Vector3.new(18, 1.1, 18), Vector3.new(x, h + 0.5, z), zone.Accent, NEON)
	end
	for i = 1, 5 do
		local x = rng:NextNumber(-48, 48)
		local y = rng:NextNumber(42, 62)
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local cloud = WorldBuilder.BuildCloud(Vector3.new(x, y, z), rng:NextNumber(1.5, 2.6))
		for _, d in ipairs(cloud:GetDescendants()) do
			if d:IsA("BasePart") then d.Color = stormDark end
		end
		cloud.Parent = parent
	end
	-- Angular lightning-bolt landmarks, offset from the central flight lane.
	for side = -1, 1, 2 do
		local x = side * rng:NextNumber(32, 48)
		local y = rng:NextNumber(30, 48)
		local z = centerZ + rng:NextNumber(-halfLength * 0.7, halfLength * 0.7)
		for segment = 1, 3 do
			local p = part(parent, "LightningShard", Vector3.new(1.3, 1.3, rng:NextNumber(7, 12)), Vector3.new(x, y - segment * 5, z + segment * 5), zone.Accent, NEON, 0, 0, side * 24)
			p.Transparency = 0.18
		end
	end
end

recipes.clouds = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 44)
	local gold = Color3.fromRGB(255, 188, 100)
	for i = 1, 10 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (36 + rng:NextInteger(0, 54))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local y = rng:NextNumber(4, 18)
		local island = part(parent, "CloudIsland", Vector3.new(rng:NextNumber(18, 30), 5, rng:NextNumber(22, 38)), Vector3.new(x, y, z), Color3.fromRGB(238, 222, 204), PAPER, rng:NextNumber(-8, 8), rng:NextNumber(0, 360), rng:NextNumber(-8, 8))
		part(parent, "GoldSeam", Vector3.new(island.Size.X * 0.88, 0.35, 0.6), island.Position + Vector3.new(0, 2.7, 0), gold, NEON)
	end
	for i = 1, 5 do
		local x = (i - 3) * 30 + rng:NextNumber(-8, 8)
		local y = rng:NextNumber(44, 60)
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local cloud = WorldBuilder.BuildCloud(Vector3.new(x, y, z), rng:NextNumber(1.5, 2.2))
		cloud.Parent = parent
	end
	for i = 1, 3 do
		local x = (i - 2) * 34
		local z = centerZ + rng:NextNumber(-halfLength * 0.7, halfLength * 0.7)
		local arch = part(parent, "SunRing", Vector3.new(2, 32, 32), Vector3.new(x, 28, z), gold, NEON, 0, 0, 90)
		arch.Transparency = 0.3
	end
end

recipes.fold = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 46)
	local dark = Color3.fromRGB(26, 24, 44)
	local gold = Color3.fromRGB(255, 202, 92)
	for i = 1, 12 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (34 + rng:NextInteger(0, 60))
		local z = centerZ + rng:NextNumber(-halfLength, halfLength)
		local h = rng:NextNumber(22, 52)
		local width = rng:NextNumber(12, 24)
		local fold = wedge(parent, "FoldedMonolith", Vector3.new(width, h, width * 0.8), Vector3.new(x, h * 0.5, z), dark, FOIL, rng:NextNumber(-10, 10), rng:NextNumber(0, 360), rng:NextNumber(-18, 18))
		part(parent, "FoldCrease", Vector3.new(width * 0.88, 0.5, 1), fold.Position + Vector3.new(0, h * 0.18, 0), gold, NEON, 0, 0, rng:NextNumber(-20, 20))
	end
	for i = 1, 4 do
		local z = centerZ + (i - 2.5) * 62
		local arch = part(parent, "OrigamiGate", Vector3.new(3, 44, 42), Vector3.new(0, 24, z), dark, FOIL, 0, 0, 90)
		arch.Transparency = 0.12
		part(parent, "GateCrest", Vector3.new(44, 2, 3), Vector3.new(0, 46, z), gold, NEON)
	end
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		local radius = rng:NextNumber(52, 76)
		local star = part(parent, "FoldStar", Vector3.new(1.2, 1.2, 1.2), Vector3.new(math.cos(angle) * radius, rng:NextNumber(12, 54), centerZ + math.sin(angle) * radius), gold, NEON)
		star.Shape = Enum.PartType.Ball
	end
end

recipes.prism = function(parent, zone, centerZ, halfLength, rng)
	groundStrip(parent, zone.Path, zone.Ground, halfLength, centerZ, 40)

	-- Rainbow faceted pillars and floating foil shards.
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (34 + rng:NextInteger(0, 44))
		local z = centerZ - halfLength + (i + rng:NextNumber()) * (halfLength * 2 / 9)
		local h = 28 + rng:NextNumber() * 42
		local col = Color3.fromHSV((i * 0.14 + rng:NextNumber() * 0.1) % 1, 0.75, 0.95)
		part(parent, "PrismPillar", Vector3.new(12, h, 12), Vector3.new(x, h / 2, z), col, FOIL, 0, rng:NextNumber(0, 45), 0)
	end
end

-- -------------------------------------------------------- flight barriers ---
local function buildElectricalBoundaries(parent, zone, centerZ, halfLength, rng)
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

-- ------------------------------------------------------------------ chunks ---
local function buildMapLandmarks(parent, zone, centerZ, halfLength, rng)
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

function WorldBuilder.BuildChunk(zoneId: string, centerZ: number, halfLength: number, seed: number): Model
	local zone = GameConfig.GetZoneById(zoneId) or GameConfig.Zones[1]
	local rng = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "Chunk_" .. zone.Id

	local recipe = recipes[zone.Style]
	if not recipe then
		warn(string.format("WorldBuilder: missing scenery recipe '%s' for zone '%s'", tostring(zone.Style), tostring(zone.Id)))
		model:Destroy()
		error("Missing WorldBuilder recipe: " .. tostring(zone.Style))
	end
	recipe(model, zone, centerZ, halfLength, rng)
	buildMapLandmarks(model, zone, centerZ, halfLength, rng)
	buildElectricalBoundaries(model, zone, centerZ, halfLength, rng)

	-- Floating clouds above the corridor in every zone except the void.
	if zone.Style == "town" or zone.Style == "canyon" then
		for i = 1, 5 do
			local x = (i - 3) * 34 + rng:NextNumber(-10, 10)
			local y = 52 + rng:NextNumber(0, 22)
			local z = centerZ + rng:NextNumber(-halfLength, halfLength)
			local cloud = WorldBuilder.BuildCloud(Vector3.new(x, y, z), 1.0 + rng:NextNumber() * 0.8)
			cloud.Parent = model
		end
	end

	return model
end

-- ---------------------------------------------------------------- enemies ---
local enemyBuilders = {}

enemyBuilders.InkBlob = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_InkBlob"
	local c = config.Color
	local body = ball(m, "Body", 5.2, Vector3.zero, c, PAPER)
	ellipsoid(m, "Top", Vector3.new(4.2, 3.2, 4.2), Vector3.new(0, 2.2, 0), c, PAPER)
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2
		ball(m, "Drop" .. i, 1.8, Vector3.new(math.cos(a) * 2.8, -1.2, math.sin(a) * 2.8), c, PAPER)
	end
	ball(m, "EyeL", 1.1, Vector3.new(-1.1, 0.6, 2.2), Color3.fromRGB(255, 255, 255), NEON)
	ball(m, "EyeR", 1.1, Vector3.new(1.1, 0.6, 2.2), Color3.fromRGB(255, 255, 255), NEON)
	ball(m, "PupilL", 0.5, Vector3.new(-1.1, 0.6, 2.7), Color3.fromRGB(20, 20, 30), PAPER)
	ball(m, "PupilR", 0.5, Vector3.new(1.1, 0.6, 2.7), Color3.fromRGB(20, 20, 30), PAPER)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.DartDrone = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_DartDrone"
	local c = config.Color
	local body = wedge(m, "Body", Vector3.new(2.2, 1.2, 6.2), Vector3.zero, c, PAPER, 0, 180, 0)
	wedge(m, "WingL", Vector3.new(3.6, 0.16, 3.0), Vector3.new(-2.4, 0, 0.4), config.Accent, PAPER, 0, 165, 0)
	wedge(m, "WingR", Vector3.new(3.6, 0.16, 3.0), Vector3.new(2.4, 0, 0.4), config.Accent, PAPER, 0, -165, 0)
	ball(m, "Eye", 1.1, Vector3.new(0, 0.2, 2.6), Color3.fromRGB(255, 80, 80), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.ScissorBot = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_ScissorBot"
	local c = config.Color
	local body = part(m, "Body", Vector3.new(4.4, 4.4, 4.4), Vector3.zero, c, FOIL)
	wedge(m, "BladeL", Vector3.new(1.0, 7.0, 2.0), Vector3.new(-2.6, 1.6, 2.8), Color3.fromRGB(220, 224, 232), FOIL, 45, 0, 20)
	wedge(m, "BladeR", Vector3.new(1.0, 7.0, 2.0), Vector3.new(2.6, 1.6, 2.8), Color3.fromRGB(220, 224, 232), FOIL, 45, 0, -20)
	ball(m, "EyeL", 1.2, Vector3.new(-1.1, 0.6, 2.3), Color3.fromRGB(255, 70, 70), NEON)
	ball(m, "EyeR", 1.2, Vector3.new(1.1, 0.6, 2.3), Color3.fromRGB(255, 70, 70), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.StaplerTank = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_StaplerTank"
	local c = config.Color
	local body = part(m, "Base", Vector3.new(7.4, 3.2, 9.6), Vector3.zero, c, PAPER)
	part(m, "Top", Vector3.new(6.8, 2.4, 9.0), Vector3.new(0, 2.4, -0.4), config.Accent, PAPER, -10, 0, 0)
	ball(m, "EyeL", 1.3, Vector3.new(-1.8, 1.4, 4.2), Color3.fromRGB(255, 80, 80), NEON)
	ball(m, "EyeR", 1.3, Vector3.new(1.8, 1.4, 4.2), Color3.fromRGB(255, 80, 80), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

enemyBuilders.ShredderWasp = function(config, scale)
	local m = Instance.new("Model")
	m.Name = "Enemy_ShredderWasp"
	local c = config.Color
	local body = ellipsoid(m, "Body", Vector3.new(3.2, 3.2, 6.4), Vector3.zero, c, PAPER)
	for i = -1, 1 do
		part(m, "Stripe" .. i, Vector3.new(3.4, 3.4, 1.0), Vector3.new(0, 0, i * 1.6), Color3.fromRGB(40, 42, 50), PAPER)
	end
	wedge(m, "WingL", Vector3.new(5.2, 0.14, 2.4), Vector3.new(-3.2, 1.2, 0), Color3.fromRGB(220, 240, 255), GLASS, 0, 0, 22)
	wedge(m, "WingR", Vector3.new(5.2, 0.14, 2.4), Vector3.new(3.2, 1.2, 0), Color3.fromRGB(220, 240, 255), GLASS, 0, 0, -22)
	ball(m, "EyeL", 1.1, Vector3.new(-1.1, 0.5, 2.6), Color3.fromRGB(255, 60, 60), NEON)
	ball(m, "EyeR", 1.1, Vector3.new(1.1, 0.5, 2.6), Color3.fromRGB(255, 60, 60), NEON)
	m.PrimaryPart = body
	scaleModel(m, scale)
	return m
end

local enemyBuilderAliases = {
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
end

-- ------------------------------------------------------------------ bosses ---
function WorldBuilder.BuildBoss(bossDef): Model
	local m = Instance.new("Model")
	m.Name = "Boss_" .. (bossDef.Name or "Boss")
	local main = bossDef.Color or Color3.fromRGB(240, 140, 160)
	local accent = bossDef.Accent or Color3.fromRGB(255, 220, 120)

	-- Giant folded golem / titan: wide shoulders, horned crown, glowing core.
	local torso = part(m, "Torso", Vector3.new(15, 16, 11), Vector3.zero, main, PAPER)
	part(m, "ChestBand", Vector3.new(15.6, 2.2, 11.6), Vector3.new(0, 2, 0), accent, NEON)
	part(m, "Head", Vector3.new(10, 9, 9), Vector3.new(0, 12.5, 0), main, PAPER)
	wedge(m, "HornL", Vector3.new(3, 8, 3), Vector3.new(-5.5, 18.5, 0), accent, PAPER, 0, 0, 24)
	wedge(m, "HornR", Vector3.new(3, 8, 3), Vector3.new(5.5, 18.5, 0), accent, PAPER, 0, 0, -24)
	part(m, "ArmL", Vector3.new(6, 15, 6), Vector3.new(-11, -1, 0), main, PAPER, 0, 0, 12)
	part(m, "ArmR", Vector3.new(6, 15, 6), Vector3.new(11, -1, 0), main, PAPER, 0, 0, -12)
	ball(m, "EyeL", 2.2, Vector3.new(-2.4, 13, 4.6), Color3.fromRGB(255, 60, 60), NEON)
	ball(m, "EyeR", 2.2, Vector3.new(2.4, 13, 4.6), Color3.fromRGB(255, 60, 60), NEON)
	local bossModel = bossDef.Model
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

	m.PrimaryPart = torso
	return m
end

-- ------------------------------------------------------------------ pickups ---
function WorldBuilder.BuildCoin(): Model
	local m = Instance.new("Model")
	m.Name = "Coin"
	local disc = cylinder(m, "Disc", Vector3.new(0.6, 3.2, 3.2), Vector3.zero, Color3.fromRGB(255, 204, 64), FOIL)
	cylinder(m, "Rim", Vector3.new(0.75, 2.5, 2.5), Vector3.zero, Color3.fromRGB(255, 232, 130), NEON)
	m.PrimaryPart = disc
	return m
end

return WorldBuilder
