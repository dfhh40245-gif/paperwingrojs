-- ============================================================================
--!nonstrict
-- PaperWings UI: hangar, HUD, shop, quests, daily rewards, codes and results.
--
-- One ScreenGui, five layers:
--   menu    the hangar overlay (before a run)
--   hud     in-flight readouts
--   shop    tabbed store (upgrades, planes, weapons, pets, shields, eggs, passes)
--   results end-of-run summary
--   modal   quests / codes / pass details, with a shared backdrop
--
-- Everything is built from code so the place has no UI assets to keep in sync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Quests = require(Shared:WaitForChild("Quests"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Utility = require(Shared:WaitForChild("Utility"))

local State = require(script.Parent:WaitForChild("State"))
local Flight = require(script.Parent:WaitForChild("Flight"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local UI = {}

-- ---------------------------------------------------------------- palette ---
local C = {
	Ink = Color3.fromRGB(30, 34, 46),
	InkSoft = Color3.fromRGB(74, 82, 100),
	Paper = Color3.fromRGB(250, 247, 238),
	PaperDim = Color3.fromRGB(228, 225, 214),
	Sun = Color3.fromRGB(255, 200, 74),
	Sky = Color3.fromRGB(72, 158, 222),
	Mint = Color3.fromRGB(88, 202, 132),
	Coral = Color3.fromRGB(240, 96, 96),
	Grape = Color3.fromRGB(170, 110, 226),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(128, 136, 150),
}

local FONT = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

-- ------------------------------------------------------------------ state ---
local gui: ScreenGui
local scaler: UIScale
local menu: Frame
local hud: Frame
local shopFrame: Frame
local resultsFrame: Frame
local modal: Frame
local modalTitle: TextLabel
local modalBody: ScrollingFrame

local shopContent: ScrollingFrame
local shopTabs: { [string]: TextButton } = {}
local currentTab = "Upgrades"
local shopOpen = false
local modalOpen = false

local hudRefs = {}
local menuRefs = {}
local resultsRefs = {}
local toastBox: Frame
local toastLabel: TextLabel
local toastToken = 0

local lastZoneName: string? = nil
local lastMilestone = -1
local lastComboShown = 0
local lastServerResult: any = nil
local bossShown = false
local leaderboardData: any = nil
local leaderboardOpen = false
local lastHealth = 0
local lastStreakTier = 0
local bindingCaptureAction: string? = nil
local bindingButtons: { [string]: TextButton } = {}
local pendingEggId: string? = nil

local STREAKS = {
	[2] = "DOUBLE KILL",
	[3] = "TRIPLE KILL",
	[5] = "RAMPAGE",
	[8] = "UNSTOPPABLE",
	[12] = "PAPER LEGEND",
}

-- ---------------------------------------------------------------- helpers ---
local function new(className: string, props, parent: Instance?): any
	local obj = Instance.new(className)
	for key, value in pairs(props or {}) do
		obj[key] = value
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function corner(obj: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, obj)
end

local function outline(obj: Instance, color: Color3?, thickness: number?, transparency: number?)
	new("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = transparency or 0,
	}, obj)
end

local function gradient(obj: Instance, top: Color3, bottom: Color3, rotation: number?)
	new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, obj)
end

local function text(parent: Instance, props): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextColor3 = C.White,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return new("TextLabel", base, parent)
end

local function button(parent: Instance, props, onClick): TextButton
	local base = {
		Font = FONT,
		TextSize = 18,
		TextColor3 = C.White,
		BackgroundColor3 = C.Sky,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local b = new("TextButton", base, parent)
	corner(b, 12)
	outline(b, C.Ink, 2)
	local scale = new("UIScale", { Scale = 1 }, b)
	local function tweenScale(value: number)
		TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = value }):Play()
	end

	local baseColor = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Disabled") then
			return
		end
		tweenScale(1.035)
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = baseColor:Lerp(C.White, 0.16) }):Play()
	end)
	b.MouseLeave:Connect(function()
		tweenScale(1)
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = baseColor }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("Disabled") then
			return
		end
		tweenScale(0.95)
	end)
	b.MouseButton1Up:Connect(function()
		tweenScale(if b:GetAttribute("Disabled") then 1 else 1.035)
	end)
	b.Activated:Connect(function()
		if b:GetAttribute("Disabled") then
			return
		end
		Effects.Play("Click", nil, 0.25)
		onClick()
	end)
	return b
end

local function setDisabled(b: TextButton, disabled: boolean, tint: Color3?)
	b:SetAttribute("Disabled", disabled)
	b.BackgroundColor3 = if disabled then C.PaperDim else (tint or C.Sky)
	b.TextColor3 = if disabled then C.Muted else C.White
end

local function card(parent: Instance, props)
	local base = {
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local f = new("Frame", base, parent)
	corner(f, 18)
	outline(f, C.Ink, 3)
	return f
end

-- Thin rounded bar; returns the fill frame so callers can size it.
local function bar(parent: Instance, props)
	local track = new("Frame", {
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
	}, parent)
	for key, value in pairs(props or {}) do
		track[key] = value
	end
	corner(track, 8)
	outline(track, C.White, 1, 0.6)
	local fill = new("Frame", {
		BackgroundColor3 = C.Mint,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, track)
	corner(fill, 7)
	return track, fill
end

local function currencyIcon(parent: Instance, name: string, y: number, color: Color3, diamond: boolean?)
	local icon = new("Frame", {
		Name = name,
		Position = UDim2.new(0, 14, 0, y),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = if diamond then 45 else 0,
	}, parent)
	corner(icon, if diamond then 3 else 7)
	outline(icon, C.Ink, 1.5, 0.15)
	return icon
end

local function fmt(n): string
	return Utility.FormatNumber(tonumber(n) or 0)
end

local function toast(message: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = tostring(message)
	toastBox.Visible = true
	toastBox.BackgroundTransparency = 0.05
	TweenService:Create(toastBox, TweenInfo.new(0.15), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()
	task.delay(2.6, function()
		if token ~= toastToken then
			return
		end
		TweenService:Create(toastBox, TweenInfo.new(0.25), { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, 8) }):Play()
		task.delay(0.3, function()
			if token == toastToken then
				toastBox.Visible = false
			end
		end)
	end)
end

UI.Toast = toast

-- --------------------------------------------------------------- screens ---
local function buildHud()
	hud = new("Frame", { Name = "HUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)

	-- Distance + zone, top centre.
	local score = card(hud, {
		Name = "Score",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 300, 0, 86),
		BackgroundColor3 = C.Ink,
	})
	outline(score, C.White, 2, 0.4)

	-- Escape hatch so a run can be banked instead of waiting to die.
	button(hud, {
		Name = "EndRun",
		Position = UDim2.new(0, 16, 0, 14),
		Size = UDim2.new(0, 112, 0, 40),
		Text = "END RUN",
		TextSize = 13,
		BackgroundColor3 = C.Coral,
	}, function()
		Flight.EndRun("quit")
	end)
	hudRefs.distance = text(score, {
		Name = "Distance",
		Text = "0 m",
		Size = UDim2.new(1, 0, 0, 52),
		Font = FONT,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.White,
	})
	hudRefs.zone = text(score, {
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

	-- Wallet, top right.
	local wallet = card(hud, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.new(0, 186, 0, 74),
		BackgroundColor3 = C.Ink,
	})
	outline(wallet, C.White, 1, 0.5)
	hudRefs.coins = text(wallet, {
		Name = "Coins",
		Position = UDim2.new(0, 34, 0, 6),
		Size = UDim2.new(1, -44, 0, 30),
		Text = "0",
		Font = FONT,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Sun,
	})
	currencyIcon(wallet, "CoinsIcon", 14, C.Sun, false)
	hudRefs.gems = text(wallet, {
		Name = "Gems",
		Position = UDim2.new(0, 34, 0, 38),
		Size = UDim2.new(1, -44, 0, 28),
		Text = "0",
		Font = FONT,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Sky,
	})
	currencyIcon(wallet, "GemsIcon", 45, C.Sky, true)

	-- Health, bottom centre.
	local healthTrack = card(hud, {
		Name = "Health",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0, 340, 0, 30),
		BackgroundColor3 = C.Ink,
	})
	outline(healthTrack, C.White, 2, 0.4)
	local _, healthFill = bar(healthTrack, {
		Position = UDim2.new(0, 5, 0, 5),
		Size = UDim2.new(1, -10, 1, -10),
		BackgroundColor3 = C.Ink,
	})
	healthFill.BackgroundColor3 = C.Mint
	hudRefs.healthFill = healthFill
	hudRefs.healthText = text(healthTrack, {
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		Text = "100",
		Font = FONT,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.White,
	})

	-- Boss bar, above the health bar.
	local boss = card(hud, {
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.new(0, 400, 0, 22),
		BackgroundColor3 = C.Ink,
		Visible = false,
	})
	local _, bossFill = bar(boss, {
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(1, -8, 1, -8),
	})
	bossFill.BackgroundColor3 = C.Coral
	hudRefs.bossBar = boss
	hudRefs.bossFill = bossFill
	hudRefs.bossName = text(boss, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = "BOSS",
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Combo badge, left middle.
	local combo = card(hud, {
		Name = "Combo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.new(0, 132, 0, 62),
		BackgroundColor3 = C.Sun,
		Visible = false,
	})
	hudRefs.comboBox = combo
	hudRefs.comboText = text(combo, {
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 34),
		Text = "x1.0",
		Font = FONT,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink,
	})
	text(combo, {
		Name = "Caption",
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "COMBO",
		Font = FONT,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink,
	})

	-- Boost meter, bottom right.
	local boost = card(hud, {
		Name = "Boost",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.new(0, 190, 0, 42),
		BackgroundColor3 = C.Ink,
	})
	local _, boostFill = bar(boost, {
		Position = UDim2.new(0, 6, 0, 6),
		Size = UDim2.new(1, -12, 0, 12),
	})
	boostFill.BackgroundColor3 = C.Sky
	hudRefs.boostFill = boostFill
	hudRefs.boostLabel = text(boost, {
		Name = "Hint",
		Position = UDim2.new(0, 8, 0, 20),
		Size = UDim2.new(1, -16, 0, 18),
		Text = "BOOST  SHIFT",
		Font = FONT,
		TextSize = 11,
		TextColor3 = C.White,
	})

	-- Revive pips, bottom left.
	hudRefs.revives = text(hud, {
		Name = "Revives",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.new(0, 200, 0, 26),
		Text = "",
		Font = FONT,
		TextSize = 14,
		TextColor3 = C.Mint,
		TextStrokeTransparency = 0.4,
	})

	-- Touch boost button: touch players have no Shift key.
	if UserInputService.TouchEnabled then
		local boostButton = button(hud, {
			Name = "BoostButton",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -18, 1, -112),
			Size = UDim2.new(0, 132, 0, 72),
			Text = "BOOST",
			TextSize = 18,
			BackgroundColor3 = C.Sky,
			ZIndex = 5,
		}, function()
			Flight.SetBoostHeld(true)
			task.delay(0.15, function()
				if not UserInputService.TouchEnabled then
					Flight.SetBoostHeld(false)
				end
			end)
		end)
		boostButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Flight.SetBoostHeld(true)
			end
		end)
		boostButton.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Flight.SetBoostHeld(false)
			end
		end)
	end

	-- Big centre banners (zone change, milestones).
	hudRefs.banner = text(hud, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 620, 0, 70),
		Text = "",
		Font = FONT,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = C.Ink,
	})

	-- Kill-streak callout under the combo badge.
	hudRefs.streak = text(hud, {
		Name = "Streak",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 44),
		Size = UDim2.new(0, 300, 0, 30),
		Text = "",
		Font = FONT,
		TextSize = 20,
		TextColor3 = C.Sun,
		TextTransparency = 1,
		TextStrokeTransparency = 0.1,
		TextStrokeColor3 = C.Ink,
	})

	-- Full-screen damage flash and a low-health vignette.
	hudRefs.flash = new("Frame", {
		Name = "DamageFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 40, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, hud)

	local vignette = new("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, hud)
	hudRefs.vignette = vignette
	hudRefs.vignetteStroke = new("UIStroke", {
		Color = Color3.fromRGB(255, 30, 30),
		Thickness = 90,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 0.6,
	}, vignette)
end

local function showBanner(message: string)
	local label = hudRefs.banner
	if not label then
		return
	end
	label.Text = message
	label.TextTransparency = 0
	label.Position = UDim2.new(0.5, 0, 0.3, 0)
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.26, 0),
	}):Play()
	task.delay(1.3, function()
		if label.Text == message then
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

-- ------------------------------------------------------------------ menu ---
local function buildMenu()
	-- Fully transparent: the hangar itself is the menu backdrop.
	menu = new("Frame", {
		Name = "Menu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
	}, gui)

	-- Title block, top left.
	local title = text(menu, {
		Name = "Title",
		Position = UDim2.new(0, 38, 0, 58),
		Size = UDim2.new(0, 460, 0, 96),
		Text = "PAPER\nWINGS",
		Font = FONT,
		TextSize = 54,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = C.Ink,
	})
	text(menu, {
		Name = "Tagline",
		Position = UDim2.new(0, 42, 0, 192),
		Size = UDim2.new(0, 520, 0, 24),
		Text = "FLY FARTHER.  HIT HARDER.  COME BACK STRONGER.",
		Font = FONT,
		TextSize = 13,
		TextColor3 = C.Sun,
		TextStrokeTransparency = 0.55,
		TextStrokeColor3 = C.Ink,
	})

	menuRefs.hangar = text(menu, {
		Name = "HangarName",
		Position = UDim2.new(0, 42, 0, 252),
		Size = UDim2.new(0, 620, 0, 24),
		Text = "CARDBOARD HANGAR",
		Font = FONT,
		TextSize = 16,
		TextColor3 = C.Mint,
		TextStrokeTransparency = 0.45,
		TextStrokeColor3 = C.Ink,
	})
	menuRefs.stats = text(menu, {
		Name = "HomeStats",
		Position = UDim2.new(0, 42, 0, 278),
		Size = UDim2.new(0, 620, 0, 22),
		Text = "PETS 0  •  BOSSES 0  •  FLIGHTS 0",
		Font = FONT_REG,
		TextSize = 13,
		TextColor3 = C.White,
		TextTransparency = 0.12,
		TextStrokeTransparency = 0.7,
		TextStrokeColor3 = C.Ink,
	})

	-- Slow paper confetti, behind every control.
	local decor = new("Frame", {
		Name = "PaperBits",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, menu)
	for index = 1, 14 do
		local bit = new("Frame", {
			Name = "Bit" .. index,
			Size = UDim2.fromOffset(6 + (index % 4) * 3, 12 + (index % 3) * 5),
			Position = UDim2.fromScale((index * 0.071) % 1, math.random() * 90 / 100),
			Rotation = math.random(-40, 40),
			BackgroundColor3 = ({ C.Sun, C.Mint, C.Sky, C.Coral, C.Grape })[(index % 5) + 1],
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, decor)
		corner(bit, 2)
		task.spawn(function()
			while bit.Parent do
				bit.Rotation = math.random(-40, 40)
				local tween = TweenService:Create(bit, TweenInfo.new(6 + (index % 5) * 1.7, Enum.EasingStyle.Linear), {
					Position = UDim2.fromScale(bit.Position.X.Scale, 1.1),
					Rotation = bit.Rotation + 220,
				})
				tween:Play()
				tween.Completed:Wait()
				bit.Position = UDim2.fromScale((index * 0.071) % 1, -0.12)
				task.wait(0.2)
			end
		end)
	end

	-- Live-ops event badge (weekend rush, midweek gems, ...).
	menuRefs.event = text(menu, {
		Name = "Event",
		Position = UDim2.new(0, 42, 0, 222),
		Size = UDim2.new(0, 560, 0, 26),
		Text = "",
		Font = FONT,
		TextSize = 14,
		TextColor3 = C.Mint,
		TextStrokeTransparency = 0.45,
		TextStrokeColor3 = C.Ink,
		Visible = false,
	})

	-- First-flight onboarding. Hidden after the first completed run.
	local tutorial = card(menu, {
		Name = "Tutorial",
		Position = UDim2.new(0, 38, 0.5, -70),
		Size = UDim2.new(0, 372, 0, 152),
		BackgroundColor3 = C.Ink,
		Visible = false,
	})
	menuRefs.tutorial = tutorial
	text(tutorial, {
		Name = "Title",
		Position = UDim2.new(0, 18, 0, 8),
		Size = UDim2.new(1, -36, 0, 26),
		Text = "YOUR FIRST FLIGHT",
		Font = FONT,
		TextSize = 15,
		TextColor3 = C.Sun,
	})
	local tutorialLines = {
		"W accelerates; S brakes; A/D turn",
		"Q/E controls altitude",
		"Mouse aims; hold left click to spray",
		"Use a U-turn to fly back the other way",
	}
	for index, line in ipairs(tutorialLines) do
		text(tutorial, {
			Name = "Line" .. index,
			Position = UDim2.new(0, 18, 0, 34 + (index - 1) * 27),
			Size = UDim2.new(1, -36, 0, 24),
			Text = tostring(index) .. "  " .. line,
			Font = FONT_BOLD,
			TextSize = 13,
			TextColor3 = C.White,
		})
	end

	-- Stat plates, top right.
	local levelPlate = card(menu, {
		Name = "LevelPlate",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 58),
		Size = UDim2.new(0, 236, 0, 46),
		BackgroundColor3 = C.Ink,
	})
	menuRefs.level = text(levelPlate, {
		Name = "Level",
		Size = UDim2.fromScale(1, 1),
		Text = "LEVEL 1",
		Font = FONT,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local wallet = card(menu, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 112),
		Size = UDim2.new(0, 236, 0, 76),
		BackgroundColor3 = C.Ink,
	})
	menuRefs.coins = text(wallet, {
		Name = "Coins",
		Position = UDim2.new(0, 34, 0, 6),
		Size = UDim2.new(1, -44, 0, 30),
		Text = "0",
		Font = FONT,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Sun,
	})
	currencyIcon(wallet, "CoinsIcon", 14, C.Sun, false)
	menuRefs.gems = text(wallet, {
		Name = "Gems",
		Position = UDim2.new(0, 34, 0, 38),
		Size = UDim2.new(1, -44, 0, 28),
		Text = "0",
		Font = FONT,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Sky,
	})
	currencyIcon(wallet, "GemsIcon", 45, C.Sky, true)

	-- Personal best strip.
	menuRefs.best = text(menu, {
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -168),
		Size = UDim2.new(0, 520, 0, 28),
		Text = "PERSONAL BEST  0 m",
		Font = FONT,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = C.Ink,
	})

	-- Primary actions.
	local actions = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(0, 560, 0, 68),
		BackgroundTransparency = 1,
	}, menu)
	menuRefs.actions = actions
	local fly = button(actions, {
		Name = "Fly",
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 268, 1, 0),
		Text = "FLY",
		TextSize = 30,
		BackgroundColor3 = C.Mint,
	}, function()
    print("[PaperWings] FLY BUTTON CLICKED")
    print("[PaperWings] Data loaded:", State.Data ~= nil)
    print("[PaperWings] Stats loaded:", State.Stats ~= nil)

    local ok, err = xpcall(function()
        Flight.StartRun()
    end, debug.traceback)

    if not ok then
        warn("[PaperWings] STARTUP ERROR:\n" .. tostring(err))
    end

    print("[PaperWings] IsRunning:", Flight.IsRunning())
end)
	outline(fly, C.Ink, 3)
	local shop = button(actions, {
		Name = "Shop",
		Position = UDim2.new(1, -268, 0, 0),
		Size = UDim2.new(0, 268, 1, 0),
		Text = "SHOP",
		TextSize = 30,
		BackgroundColor3 = C.Sky,
	}, function()
		UI.OpenShop()
	end)

	-- Secondary actions.
	local secondary = new("Frame", {
		Name = "Secondary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.new(0, 796, 0, 48),
		BackgroundTransparency = 1,
	}, menu)
	local secondaryDefs = {
		{ Name = "Quests", Label = "QUESTS", Color = C.Grape, Action = function()
			UI.OpenQuests()
		end },
		{ Name = "Daily", Label = "DAILY", Color = C.Sun, Action = function()
			Remotes.Get(Remotes.ClaimDaily):FireServer()
		end },
		{ Name = "Rankings", Label = "RANKINGS", Color = C.Sky, Action = function()
			UI.OpenLeaderboard()
		end },
		{ Name = "Codes", Label = "CODES", Color = C.InkSoft, Action = function()
			UI.OpenCodes()
		end },
		{ Name = "Rebirth", Label = "REBIRTH", Color = C.Coral, Action = function()
			Remotes.Get(Remotes.Rebirth):FireServer()
		end },
		{ Name = "Settings", Label = "SETTINGS", Color = C.InkSoft, Action = function()
			UI.OpenSettings()
		end },
	}
	for index, def in ipairs(secondaryDefs) do
		local b = button(secondary, {
			Name = def.Name,
			Position = UDim2.new(0, (index - 1) * 132, 0, 0),
			Size = UDim2.new(0, 126, 0, 46),
			Text = def.Label,
			TextSize = 13,
			BackgroundColor3 = def.Color,
		}, def.Action)
		menuRefs[def.Name] = b
	end

	text(menu, {
		Name = "Controls",
		Position = UDim2.new(0, 40, 1, -26),
		Size = UDim2.new(0, 560, 0, 22),
		Text = "WASD MOVE  •  Q/E ALTITUDE  •  MOUSE AIM + HOLD TO FIRE  •  SHIFT BOOST",
		Font = FONT,
		TextSize = 12,
		TextColor3 = C.White,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = C.Ink,
	})
end

-- ------------------------------------------------------------------ shop ---
local renderers = {}

local function addRow(titleText: string, descText: string, actionText: string, color: Color3, enabled: boolean, onClick)
	local row = card(shopContent, {
		Name = titleText,
		Size = UDim2.new(1, -12, 0, 84),
		BackgroundColor3 = C.Paper,
	})
	local stripe = new("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, row)
	corner(stripe, 6)
	text(row, {
		Name = "Title",
		Position = UDim2.new(0, 20, 0, 8),
		Size = UDim2.new(1, -210, 0, 28),
		Text = titleText,
		Font = FONT,
		TextSize = 18,
		TextColor3 = C.Ink,
	})
	text(row, {
		Name = "Desc",
		Position = UDim2.new(0, 20, 0, 38),
		Size = UDim2.new(1, -210, 0, 38),
		Text = descText,
		Font = FONT_REG,
		TextSize = 13,
		TextColor3 = C.InkSoft,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local action = button(row, {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 178, 0, 46),
		Text = actionText,
		TextSize = 14,
		BackgroundColor3 = color,
	}, function()
		if not enabled then
			return
		end
		if pendingEggId then
			toast("PLEASE WAIT FOR THE EGG HATCH")
			return
		end
		onClick()
	end)
	if not enabled then
		setDisabled(action, true)
	end
	return row, action
end

renderers.Upgrades = function()
	for _, kind in ipairs(GameConfig.UpgradeOrder) do
		local cfg = GameConfig.Upgrades[kind]
		local level = (State.Data.Upgrades[kind]) or 1
		local cost = GameConfig.UpgradeCost(kind, level)
		local canAfford = State.Coins() >= cost
		local maxLevel = if cfg.Max == math.huge then math.huge else math.floor(cfg.Max / cfg.PerLevel) + 1
		local actionText = if level >= maxLevel then "MAXED" else "UPGRADE  " .. fmt(cost)
		addRow(
			string.format("%s  •  LV %d", string.upper(cfg.Name), level),
			string.format("%s  (+%d%% per level)", cfg.Desc, math.floor(cfg.PerLevel * 100)),
			actionText,
			if level >= maxLevel then C.Muted else (canAfford and C.Mint or C.Coral),
			level < maxLevel and canAfford,
			function()
				Remotes.Get(Remotes.Purchase):FireServer({ Action = "upgrade", Id = kind })
			end
		)
	end
end

renderers.Planes = function()
	local ids = {}
	for id in pairs(GameConfig.Planes) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local plane = GameConfig.Planes[id]
		local unlocked = State.Data.UnlockedPlanes[id]
		local equipped = State.Data.EquippedPlane == id
		local levelOk = State.Level() >= (plane.UnlockLevel or 0)
		local actionText
		local enabled = true
		if equipped then
			actionText = "EQUIPPED"
			enabled = false
		elseif unlocked then
			actionText = "EQUIP"
		elseif plane.RequiresPass then
			actionText = "GAMEPASS"
			enabled = false
		elseif not levelOk then
			actionText = "LV " .. plane.UnlockLevel
			enabled = false
		else
			actionText = "BUY  " .. plane.Cost .. " GEMS"
			enabled = State.Gems() >= plane.Cost
		end
		addRow(plane.Name, string.format("%s   SPD %.2f • HP %.2f • DMG %.2f", plane.Desc, plane.SpeedMult, plane.HealthMult, plane.DamageMult), actionText, plane.Color, enabled, function()
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "plane", Id = id })
		end)
	end
end

renderers.Weapons = function()
	local ids = {}
	for id in pairs(GameConfig.Weapons) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local weapon = GameConfig.Weapons[id]
		local unlocked = State.Data.UnlockedWeapons[id]
		local equipped = State.Data.EquippedWeapon == id
		local actionText
		local enabled = true
		if equipped then
			actionText = "EQUIPPED"
			enabled = false
		elseif unlocked then
			actionText = "EQUIP"
		elseif weapon.RequiresPass then
			actionText = "GAMEPASS"
			enabled = false
		else
			actionText = "BUY  " .. weapon.Cost .. " GEMS"
			enabled = State.Gems() >= weapon.Cost
		end
		local shots = math.max(1, math.floor(weapon.Projectiles or 1))
		local shotText = if shots == 1 then "1 SHOT" else (shots .. " SHOTS")
		addRow(weapon.Name, string.format("%s   DMG x%.2f • RATE %.2fs • %s", weapon.Desc, weapon.DamageMult, weapon.FireInterval, shotText), actionText, weapon.Color, enabled, function()
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "weapon", Id = id })
		end)
	end
end

renderers.Pets = function()
	local ids = {}
	for id in pairs(GameConfig.Allies) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local limit = State.Data.AllyLimit or GameConfig.MaxAllies
	for _, id in ipairs(ids) do
		local ally = GameConfig.Allies[id]
		local owned = State.Data.UnlockedAllies[id]
		local equipped = table.find(State.Data.Allies, id) ~= nil
		local actionText
		local enabled = true
		if equipped then
			actionText = "IN SQUAD"
			enabled = false
		elseif owned then
			actionText = "ADD TO SQUAD"
			enabled = #State.Data.Allies < limit
		else
			actionText = "BUY  " .. ally.Cost .. " GEMS"
			enabled = State.Gems() >= ally.Cost and #State.Data.Allies < limit
		end
		addRow(ally.Name, string.format("%s   DMG %d • RATE %.1fs%s", ally.Desc, ally.Damage, ally.FireInterval, ally.Splash and " • SPLASH" or ""), actionText, ally.Color, enabled, function()
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "ally", Id = id })
		end)
	end
	text(shopContent, {
		Name = "SquadInfo",
		Size = UDim2.new(1, -12, 0, 30),
		Text = string.format("SQUAD %d / %d   •   BUY MORE SLOTS WITH THE ALLY SQUAD PASS", #State.Data.Allies, limit),
		Font = FONT,
		TextSize = 12,
		TextColor3 = C.Muted,
	})
end

renderers.Shields = function()
	local ids = {}
	for id in pairs(GameConfig.Shields) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local shield = GameConfig.Shields[id]
		local unlocked = State.Data.UnlockedShields[id]
		local equipped = State.Data.EquippedShield == id
		local actionText
		local enabled = true
		if equipped then
			actionText = "EQUIPPED"
			enabled = false
		elseif unlocked then
			actionText = "EQUIP"
		else
			actionText = "BUY  " .. shield.Cost .. " GEMS"
			enabled = State.Gems() >= shield.Cost
		end
		local reduction = math.floor((1 - 1 / shield.Mult) * 100 + 0.5)
		local desc = if id == "None"
			then shield.Desc
			else string.format("%s   TAKES %d%% LESS DAMAGE", shield.Desc, reduction)
		addRow(shield.Name, desc, actionText, C.Sky, enabled, function()
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "shield", Id = id })
		end)
	end
end

local function playEggHatch(eggId: string, resultMessage: string?)
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

renderers.Eggs = function()
	local ids = {}
	for id in pairs(GameConfig.Eggs) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local egg = GameConfig.Eggs[id]
		addRow(egg.Name, "HATCH A RANDOM PET  •  LUCK IMPROVES THE ODDS", "HATCH  " .. egg.Cost .. " GEMS", egg.Color or C.Grape, State.Gems() >= egg.Cost, function()
			if pendingEggId then
				toast("AN EGG IS ALREADY HATCHING")
				return
			end
			pendingEggId = id
			Remotes.Get(Remotes.Purchase):FireServer({ Action = "egg", Id = id })
		end)
	end
end

renderers.Hangars = function()
	for _, id in ipairs(GameConfig.HangarOrder) do
		local hangar = GameConfig.Hangars[id]
		local equipped = State.Data.EquippedHangar == id
		addRow(
			hangar.Name,
			string.format("%s  •  FEATURED EGG: %s  •  HOME ZONE: %s", hangar.Tagline, hangar.Egg, hangar.Zone),
			if equipped then "EQUIPPED" else "MAKE HOME",
			hangar.Accent or C.Grape,
			not equipped,
			function()
				Remotes.Get(Remotes.Purchase):FireServer({ Action = "hangar", Id = id })
			end
		)
	end
end

renderers.Prestige = function()
	for _, kind in ipairs(GameConfig.PrestigeOrder) do
		local entry = GameConfig.Prestige[kind]
		local rank = (State.Data.Prestige and State.Data.Prestige[kind]) or 0
		local maxed = rank >= entry.Max
		local cost = GameConfig.PrestigeCost(kind, rank)
		addRow(
			string.format("%s  •  RANK %d/%d", entry.Name, rank, entry.Max),
			entry.Desc .. "  •  PERMANENT (SURVIVES REBIRTH)",
			if maxed then "MAXED" else ("BUY  " .. cost .. " GEMS"),
			C.Grape,
			not maxed and State.Gems() >= cost,
			function()
				Remotes.Get(Remotes.Purchase):FireServer({ Action = "prestige", Id = kind })
			end
		)
	end
end

renderers.Passes = function()
	local owned = State.Data.OwnedPasses or {}
	for _, key in ipairs(Monetization.GamepassOrder) do
		local pass = Monetization.Gamepasses[key]
		local has = owned[key] == true
		addRow(
			pass.Name,
			table.concat(pass.PerkLines, "   •   "),
			if has then "OWNED" else (Monetization.IsConfigured(pass.Id) and ("BUY  " .. pass.Price .. " R$") or "COMING SOON"),
			pass.Color,
			not has and Monetization.IsConfigured(pass.Id),
			function()
				Remotes.Get(Remotes.PromptPass):FireServer(key)
			end
		)
	end

	local header = text(shopContent, {
		Name = "ProductHeader",
		Size = UDim2.new(1, -12, 0, 34),
		Text = "COIN AND GEM PACKS",
		Font = FONT,
		TextSize = 15,
		TextColor3 = C.Ink,
	})
	header.TextXAlignment = Enum.TextXAlignment.Left

	for _, key in ipairs(Monetization.ProductOrder) do
		local product = Monetization.Products[key]
		addRow(
			product.Name,
			product.Description,
			if Monetization.IsConfigured(product.Id) then ("BUY  " .. product.Price .. " R$") else "COMING SOON",
			C.PaperDim,
			Monetization.IsConfigured(product.Id),
			function()
				Remotes.Get(Remotes.PromptProduct):FireServer(key)
			end
		)
	end
end

local function clearShop()
	for _, child in ipairs(shopContent:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

function UI.RefreshShop()
	if not shopOpen or not State.Data then
		return
	end
	clearShop()
	local render = renderers[currentTab]
	if render then
		render()
	end
end

function UI.SelectTab(tab: string)
	currentTab = tab
	for name, tabButton in pairs(shopTabs) do
		local active = name == tab
		tabButton.BackgroundColor3 = if active then C.Sky else C.PaperDim
		tabButton.TextColor3 = if active then C.White else C.InkSoft
	end
	UI.RefreshShop()
end

local function buildShop()
	shopFrame = card(gui, {
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 900, 0, 540),
		BackgroundColor3 = C.Paper,
		Visible = false,
	})
	shopFrame.ZIndex = 10

	text(shopFrame, {
		Name = "Title",
		Position = UDim2.new(0, 22, 0, 12),
		Size = UDim2.new(1, -120, 0, 40),
		Text = "FLIGHT SHOP",
		Font = FONT,
		TextSize = 26,
		TextColor3 = C.Ink,
	})
	text(shopFrame, {
		Name = "Subtitle",
		Position = UDim2.new(0, 24, 0, 50),
		Size = UDim2.new(1, -60, 0, 24),
		Text = "Spend coins on power, gems on style.",
		Font = FONT_REG,
		TextSize = 12,
		TextColor3 = C.Muted,
	})
	local close = button(shopFrame, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.new(0, 44, 0, 40),
		Text = "X",
		TextSize = 18,
		BackgroundColor3 = C.Coral,
	}, function()
		UI.CloseShop()
	end)

	local tabBar = new("Frame", {
		Name = "Tabs",
		Position = UDim2.new(0, 14, 0, 82),
		Size = UDim2.new(1, -28, 0, 42),
		BackgroundTransparency = 1,
	}, shopFrame)
	local tabs = { "Upgrades", "Prestige", "Planes", "Weapons", "Pets", "Shields", "Eggs", "Hangars", "Passes" }
	for index, name in ipairs(tabs) do
		local width = 92
		local b = button(tabBar, {
			Name = name,
			Position = UDim2.new(0, (index - 1) * (width + 4), 0, 0),
			Size = UDim2.new(0, width, 1, 0),
			Text = name,
			TextSize = 12,
			BackgroundColor3 = if name == currentTab then C.Sky else C.PaperDim,
		}, function()
			UI.SelectTab(name)
		end)
		shopTabs[name] = b
	end

	shopContent = new("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.new(0, 14, 0, 132),
		Size = UDim2.new(1, -28, 1, -146),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Sky,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, shopFrame)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, shopContent)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, shopContent)
end

-- --------------------------------------------------------------- results ---
local function buildResults()
	resultsFrame = card(gui, {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 480, 0, 430),
		BackgroundColor3 = C.Paper,
		Visible = false,
	})
	resultsFrame.ZIndex = 12

	text(resultsFrame, {
		Name = "Title",
		Position = UDim2.new(0, 0, 0, 14),
		Size = UDim2.new(1, 0, 0, 44),
		Text = "FLIGHT OVER",
		Font = FONT,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink,
	})

	local stats = new("Frame", {
		Name = "Stats",
		Position = UDim2.new(0, 30, 0, 68),
		Size = UDim2.new(1, -60, 0, 240),
		BackgroundTransparency = 1,
	}, resultsFrame)
	local rows = {
		{ Key = "Distance", Label = "DISTANCE", Color = C.Sky },
		{ Key = "Kills", Label = "TARGETS", Color = C.Ink },
		{ Key = "Coins", Label = "COINS", Color = C.Sun },
		{ Key = "Gems", Label = "GEMS", Color = C.Grape },
		{ Key = "Combo", Label = "BEST COMBO", Color = C.Mint },
	}
	for index, row in ipairs(rows) do
		resultsRefs[row.Key] = text(stats, {
			Name = row.Key,
			Position = UDim2.new(0, 0, 0, (index - 1) * 46),
			Size = UDim2.new(1, 0, 0, 42),
			Text = row.Label .. "  0",
			Font = FONT,
			TextSize = 20,
			TextColor3 = row.Color,
		})
	end

	local again = button(resultsFrame, {
		Name = "Again",
		Position = UDim2.new(0, 20, 1, -78),
		Size = UDim2.new(0, 205, 0, 56),
		Text = "FLY AGAIN",
		TextSize = 20,
		BackgroundColor3 = C.Mint,
	}, function()
		UI.CloseResults()
		Flight.StartRun()
	end)

	local shop = button(resultsFrame, {
		Name = "Shop",
		Position = UDim2.new(1, -225, 1, -78),
		Size = UDim2.new(0, 205, 0, 56),
		Text = "UPGRADE",
		TextSize = 20,
		BackgroundColor3 = C.Sky,
	}, function()
		UI.CloseResults()
		menu.Visible = true
		UI.OpenShop()
	end)

	resultsRefs.subtitle = text(resultsFrame, {
		Name = "Subtitle",
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		Font = FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
end

-- ----------------------------------------------------------------- modal ---
local function buildModal()
	modal = new("Frame", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		Visible = false,
	}, gui)
	modal.ZIndex = 20

	local panel = card(modal, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 560, 0, 470),
		BackgroundColor3 = C.Paper,
	})
	panel.ZIndex = 21

	modalTitle = text(panel, {
		Name = "Title",
		Position = UDim2.new(0, 22, 0, 14),
		Size = UDim2.new(1, -90, 0, 40),
		Text = "TITLE",
		Font = FONT,
		TextSize = 24,
		TextColor3 = C.Ink,
	})
	modalTitle.ZIndex = 22

	local close = button(panel, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.new(0, 42, 0, 38),
		Text = "X",
		TextSize = 17,
		BackgroundColor3 = C.Coral,
	}, function()
		UI.CloseModal()
	end)
	close.ZIndex = 23

	modalBody = new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.new(0, 18, 0, 64),
		Size = UDim2.new(1, -36, 1, -80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	modalBody.ZIndex = 22
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, modalBody)
end

local function openModal(titleText: string, build)
	if not modal then
		return
	end
	modalOpen = true
	modal.Visible = true
	modalTitle.Text = titleText
	for _, child in ipairs(modalBody:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	build(modalBody)
end

-- ------------------------------------------------------------------- hud ---
local function updateHud(hp, maxHp, dist, coins, gems, kills, zoneName, bossFrac, comboSteps, comboMult, boost, revives, boosting, wrongWay)
	if not hud.Visible then
		lastHealth = hp
		lastStreakTier = 0
	end
	hud.Visible = true
	menu.Visible = false
	resultsFrame.Visible = false

	local fraction = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
	hudRefs.healthFill.Size = UDim2.fromScale(fraction, 1)
	hudRefs.healthFill.BackgroundColor3 = C.Coral:Lerp(C.Mint, fraction)
	hudRefs.healthText.Text = string.format("%d / %d", math.ceil(hp), math.ceil(maxHp))

	-- Damage flash, and a pulsing vignette when the run is nearly over.
	if lastHealth > 0 and hp < lastHealth - 0.5 then
		hudRefs.flash.BackgroundTransparency = 0.72
		TweenService:Create(hudRefs.flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
	lastHealth = hp

	if fraction < 0.3 and hp > 0 then
		hudRefs.vignette.Visible = true
		hudRefs.vignetteStroke.Transparency = 0.5 + 0.25 * math.abs(math.sin(os.clock() * 3))
	else
		hudRefs.vignette.Visible = false
	end
	hudRefs.distance.Text = fmt(dist) .. " m"
	hudRefs.zone.Text = string.upper(zoneName or "PAPER TOWN")
	hudRefs.wrongWay.Visible = wrongWay == true
	hudRefs.coins.Text = fmt(coins)
	hudRefs.gems.Text = fmt(gems)

	if bossFrac and bossFrac > 0 then
		if not bossShown then
			bossShown = true
			showBanner("BOSS INCOMING")
		end
		hudRefs.bossBar.Visible = true
		hudRefs.bossFill.Size = UDim2.fromScale(math.clamp(bossFrac, 0, 1), 1)
	else
		bossShown = false
		hudRefs.bossBar.Visible = false
	end

	local steps = comboSteps or 0
	if steps >= 2 then
		hudRefs.comboBox.Visible = true
		hudRefs.comboText.Text = string.format("x%.1f", comboMult or 1)
		if steps ~= lastComboShown then
			lastComboShown = steps
			hudRefs.comboBox.Size = UDim2.new(0, 142, 0, 66)
			TweenService:Create(hudRefs.comboBox, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.new(0, 132, 0, 62) }):Play()
		end
	else
		hudRefs.comboBox.Visible = false
		lastComboShown = 0
		lastStreakTier = 0
	end

	-- Kill-streak callouts ("TRIPLE KILL", "RAMPAGE", ...).
	local streakText = STREAKS[steps]
	if streakText and steps > lastStreakTier then
		lastStreakTier = steps
		local label = hudRefs.streak
		label.Text = streakText
		label.Position = UDim2.new(0, 18, 0.5, 52)
		TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 0, Position = UDim2.new(0, 18, 0.5, 44) }):Play()
		task.delay(0.9, function()
			if label.Text == streakText then
				TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
		end)
	end

	local charge = math.clamp(boost or 0, 0, GameConfig.Boost.ChargeMax)
	hudRefs.boostFill.Size = UDim2.new(charge / GameConfig.Boost.ChargeMax, 0, 1, 0)
	hudRefs.boostFill.BackgroundColor3 = if boosting then C.Sun else C.Sky
	hudRefs.boostLabel.Text = if boosting then "BOOSTING" else "BOOST  SHIFT"

	if (revives or 0) > 0 then
		hudRefs.revives.Text = "REVIVES  " .. tostring(revives)
	else
		hudRefs.revives.Text = ""
	end

	if zoneName and zoneName ~= lastZoneName then
		lastZoneName = zoneName
		showBanner(string.upper(zoneName))
	end

	local milestone = math.floor((dist or 0) / 1000)
	if milestone > lastMilestone then
		lastMilestone = milestone
		if milestone > 0 then
			showBanner(fmt(milestone * 1000) .. " m")
		end
	end
end

local function updateResults(result)
	if not result then
		return
	end
	resultsFrame.Visible = true
	menu.Visible = false
	hud.Visible = false
	resultsRefs.Distance.Text = "DISTANCE  " .. fmt(result.Distance) .. " m"
	resultsRefs.Kills.Text = "TARGETS  " .. tostring(result.Kills or 0)
	resultsRefs.Coins.Text = "COINS  " .. fmt(result.Coins) .. (lastServerResult and "  (saved)" or "")
	resultsRefs.Gems.Text = "GEMS  " .. fmt(result.Gems)
	resultsRefs.Combo.Text = "BEST COMBO  x" .. tostring(result.BestCombo or 0)
	if result.Boss then
		resultsRefs.subtitle.Text = "BOSS DEFEATED  •  " .. tostring(result.Boss.Name)
	else
		resultsRefs.subtitle.Text = if result.Reason == "death" then "SHOT DOWN  •  TRY AGAIN" else "RUN COMPLETE"
	end
end

-- ---------------------------------------------------------------- refresh ---
function UI.RefreshTop()
	local data = State.Data
	if not data or not menuRefs.level then
		return
	end
	menuRefs.coins.Text = fmt(data.Coins)
	menuRefs.gems.Text = fmt(data.Gems)
	local streak = tonumber(data.DailyStreak) or 0
	menuRefs.level.Text = string.format(
		"LEVEL %d   •   FLIGHTS %d%s",
		State.Level(),
		data.Runs or 0,
		if streak > 0 then string.format("   •   STREAK %d", streak) else ""
	)
	menuRefs.best.Text = "PERSONAL BEST  " .. fmt(data.BestDistance) .. " m"
	if menuRefs.tutorial then
		menuRefs.tutorial.Visible = (tonumber(data.Runs) or 0) == 0
	end
	local hangar = GameConfig.Hangars[data.EquippedHangar or "Cardboard"] or GameConfig.Hangars.Cardboard
	if menuRefs.hangar then
		menuRefs.hangar.Text = string.format("%s  •  %s", hangar.Name, string.upper(hangar.Egg))
		menuRefs.hangar.TextColor3 = hangar.Accent
	end
	if menuRefs.stats then
		local petCount = 0
		for _ in pairs(data.UnlockedAllies or {}) do
			petCount += 1
		end
		local bossCount = 0
		for _ in pairs(data.BossesBeaten or {}) do
			bossCount += 1
		end
		menuRefs.stats.Text = string.format("PETS %d  •  BOSSES %d  •  FLIGHTS %d", petCount, bossCount, tonumber(data.Runs) or 0)
	end
	if menuRefs.event then
		local event = data.Event
		if event and event.Name then
			menuRefs.event.Text = "EVENT  •  " .. tostring(event.Name) .. "  —  " .. tostring(event.Desc or "")
			menuRefs.event.Visible = true
		else
			menuRefs.event.Visible = false
		end
	end
	if menuRefs.Rebirth then
		menuRefs.Rebirth.Visible = data.CanRebirth == true
	end
end

function UI.OpenShop()
	if not State.Data then
		return
	end
	shopOpen = true
	shopFrame.Visible = true
	menu.Visible = true
	if menuRefs.actions then
		menuRefs.actions.Visible = false
	end
	UI.SelectTab(currentTab)
end

function UI.CloseShop()
	shopOpen = false
	if shopFrame then
		shopFrame.Visible = false
	end
	if menuRefs.actions then
		menuRefs.actions.Visible = true
	end
end

function UI.OpenQuests()
	openModal("DAILY QUESTS", function(parent)
		local data = State.Data
		if not data or not data.Quests then
			return
		end
		for index, entry in ipairs(data.Quests.List) do
			local template = nil
			for _, candidate in ipairs(Quests.Templates) do
				if candidate.Id == entry.Id then
					template = candidate
					break
				end
			end
			if template then
				local row = card(parent, {
					Name = template.Id,
					Size = UDim2.new(1, -12, 0, 92),
					BackgroundColor3 = C.PaperDim,
				})
				text(row, {
					Name = "Text",
					Position = UDim2.new(0, 16, 0, 8),
					Size = UDim2.new(1, -160, 0, 26),
					Text = Quests.QuestText(template),
					Font = FONT,
					TextSize = 16,
					TextColor3 = C.Ink,
				})
				text(row, {
					Name = "Progress",
					Position = UDim2.new(0, 16, 0, 34),
					Size = UDim2.new(1, -160, 0, 20),
					Text = string.format("%d / %d   •   +%d coins, +%d gems", entry.Progress, template.Amount, template.Coins, template.Gems),
					Font = FONT_REG,
					TextSize = 12,
					TextColor3 = C.InkSoft,
				})
				local track, fill = bar(row, {
					Position = UDim2.new(0, 16, 0, 62),
					Size = UDim2.new(1, -190, 0, 14),
				})
				fill.Size = UDim2.fromScale(math.clamp(entry.Progress / template.Amount, 0, 1), 1)
				fill.BackgroundColor3 = if entry.Claimed then C.Muted else C.Mint

				local complete = entry.Progress >= template.Amount
				local claim
				claim = button(row, {
					Name = "Claim",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 150, 0, 46),
					Text = if entry.Claimed then "CLAIMED" else (complete and "CLAIM" or "IN PROGRESS"),
					TextSize = 14,
					BackgroundColor3 = if complete and not entry.Claimed then C.Mint else C.PaperDim,
				}, function()
					Remotes.Get(Remotes.ClaimQuest):FireServer(index)
					claim.Text = "CLAIMED"
					fill.BackgroundColor3 = C.Muted
					setDisabled(claim, true)
				end)
				if entry.Claimed or not complete then
					setDisabled(claim, true)
				end
			end
		end

		text(parent, {
			Name = "AchievementHeader",
			Size = UDim2.new(1, -12, 0, 36),
			Text = "ACHIEVEMENTS",
			Font = FONT,
			TextSize = 15,
			TextColor3 = C.Ink,
		})

		for _, achievement in ipairs(Quests.Achievements) do
			local unlocked = data.Achievements and data.Achievements[achievement.Id] == true
			local row = card(parent, {
				Name = achievement.Id,
				Size = UDim2.new(1, -12, 0, 56),
				BackgroundColor3 = if unlocked then Color3.fromRGB(226, 246, 232) else C.PaperDim,
			})
			text(row, {
				Name = "Name",
				Position = UDim2.new(0, 16, 0, 6),
				Size = UDim2.new(0.65, 0, 0, 24),
				Text = (if unlocked then "✓  " else "") .. achievement.Name,
				Font = FONT,
				TextSize = 15,
				TextColor3 = if unlocked then C.Mint else C.Ink,
			})
			text(row, {
				Name = "Reward",
				Position = UDim2.new(0, 16, 0, 30),
				Size = UDim2.new(1, -32, 0, 20),
				Text = string.format("+%d coins, +%d gems", achievement.Coins or 0, achievement.Gems or 0),
				Font = FONT_REG,
				TextSize = 12,
				TextColor3 = C.InkSoft,
			})
		end
	end)
end

function UI.OpenSettings()
	bindingCaptureAction = nil
	table.clear(bindingButtons)
	local labels = {
		{ "Forward", "ACCELERATE" },
		{ "Backward", "BRAKE" },
		{ "Left", "TURN LEFT" },
		{ "Right", "TURN RIGHT" },
		{ "Descend", "DESCEND" },
		{ "Ascend", "ASCEND" },
		{ "Fire", "KEYBOARD FIRE (MOUSE 1 ALWAYS WORKS)" },
		{ "Boost", "BOOST" },
	}
	local function refreshBindingButton(action: string)
		local b = bindingButtons[action]
		if b and b.Parent then
			local key = Flight.GetBindings()[action]
			b.Text = key and key.Name or "UNBOUND"
		end
	end

	openModal("FLIGHT SETTINGS", function(parent)
		text(parent, {
			Name = "Intro",
			Size = UDim2.new(1, -12, 0, 42),
			Text = "Select a binding, then press the new keyboard key. Mouse 1 remains the primary fire control.",
			Font = FONT_REG,
			TextSize = 13,
			TextColor3 = C.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Center,
		})
		for _, definition in ipairs(labels) do
			local action, labelText = definition[1], definition[2]
			local row = card(parent, {
				Name = "Binding_" .. action,
				Size = UDim2.new(1, -12, 0, 48),
				BackgroundColor3 = C.PaperDim,
			})
			text(row, {
				Name = "Label",
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -160, 1, 0),
				Text = labelText,
				Font = FONT_BOLD,
				TextSize = 11,
				TextColor3 = C.Ink,
				TextWrapped = true,
			})
			local keyButton: TextButton
			keyButton = button(row, {
				Name = "Key",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0, 128, 0, 36),
				Text = Flight.GetBindings()[action].Name,
				TextSize = 13,
				BackgroundColor3 = C.Sky,
			}, function()
				bindingCaptureAction = action
				keyButton.Text = "PRESS A KEY..."
			end)
			bindingButtons[action] = keyButton
		end

		button(parent, {
			Name = "ResetBindings",
			Size = UDim2.new(1, -12, 0, 46),
			Text = "RESET DEFAULT CONTROLS",
			TextSize = 14,
			BackgroundColor3 = C.Coral,
		}, function()
			Flight.ResetBindings()
			bindingCaptureAction = nil
			for action in pairs(bindingButtons) do refreshBindingButton(action) end
			toast("Default controls restored for this session")
		end)

		text(parent, {
			Name = "PersistenceNote",
			Size = UDim2.new(1, -12, 0, 34),
			Text = "Control changes currently last for this play session. Account-level saving requires the server settings handler.",
			Font = FONT_REG,
			TextSize = 11,
			TextColor3 = C.Muted,
			TextWrapped = true,
		})
	end)
end

function UI.OpenCodes()
	openModal("REDEEM A CODE", function(parent)
		local box = new("TextBox", {
			Name = "Input",
			Size = UDim2.new(1, -12, 0, 56),
			BackgroundColor3 = C.White,
			BorderSizePixel = 2,
			BorderColor3 = C.Ink,
			Font = FONT,
			TextSize = 22,
			PlaceholderText = "TYPE CODE",
			Text = "",
			ClearTextOnFocus = false,
			TextColor3 = C.Ink,
		}, parent)
		box.PlaceholderColor3 = C.Muted
		corner(box, 10)

		button(parent, {
			Name = "Redeem",
			Size = UDim2.new(1, -12, 0, 54),
			Text = "REDEEM",
			TextSize = 20,
			BackgroundColor3 = C.Mint,
		}, function()
			Remotes.Get(Remotes.RedeemCode):FireServer(box.Text)
			box.Text = ""
		end)

		text(parent, {
			Name = "Hint",
			Size = UDim2.new(1, -12, 0, 40),
			Text = "Codes come from the group wall and update videos.",
			Font = FONT_REG,
			TextSize = 13,
			TextColor3 = C.Muted,
			TextWrapped = true,
		})
	end)
end

-- ------------------------------------------------------------ leaderboard ---
local MEDALS = {
	Color3.fromRGB(255, 205, 80),
	Color3.fromRGB(206, 212, 222),
	Color3.fromRGB(206, 150, 96),
}

local function renderLeaderboard(parent)
	if not leaderboardData then
		text(parent, {
			Name = "Loading",
			Size = UDim2.new(1, -12, 0, 60),
			Text = "LOADING RANKINGS...",
			Font = FONT,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Muted,
		})
		return
	end

	local entries = leaderboardData.Entries or {}
	if #entries == 0 then
		text(parent, {
			Name = "Empty",
			Size = UDim2.new(1, -12, 0, 80),
			Text = "NO FLIGHTS RECORDED YET.\nBE THE FIRST TO SET A RECORD.",
			Font = FONT,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Muted,
			TextWrapped = true,
		})
	end

	for _, entry in ipairs(entries) do
		local rank = tonumber(entry.Rank) or 0
		local row = card(parent, {
			Name = "Rank" .. rank,
			Size = UDim2.new(1, -12, 0, 54),
			BackgroundColor3 = if rank <= 3 then C.PaperDim else C.Paper,
		})
		text(row, {
			Name = "Rank",
			Position = UDim2.new(0, 14, 0, 0),
			Size = UDim2.new(0, 54, 1, 0),
			Text = "#" .. tostring(rank),
			Font = FONT,
			TextSize = 18,
			TextColor3 = MEDALS[rank] or C.InkSoft,
		})
		text(row, {
			Name = "Name",
			Position = UDim2.new(0, 64, 0, 0),
			Size = UDim2.new(1, -220, 1, 0),
			Text = tostring(entry.Name or "Pilot"),
			Font = FONT_BOLD,
			TextSize = 16,
			TextColor3 = C.Ink,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(row, {
			Name = "Distance",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 0),
			Size = UDim2.new(0, 150, 1, 0),
			Text = fmt(entry.Distance) .. " m",
			Font = FONT,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Sky,
		})
	end

	text(parent, {
		Name = "Personal",
		Size = UDim2.new(1, -12, 0, 46),
		Text = "YOUR BEST   " .. fmt(leaderboardData.Personal or 0) .. " m",
		Font = FONT,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink,
	})
end

function UI.OpenLeaderboard()
	leaderboardOpen = true
	openModal("TOP FLIGHTS", renderLeaderboard)
	Remotes.Get(Remotes.RequestLeaderboard):FireServer()
end

function UI.CloseModal()
	modalOpen = false
	leaderboardOpen = false
	bindingCaptureAction = nil
	if modal then
		modal.Visible = false
	end
end

function UI.CloseResults()
	if resultsFrame then
		resultsFrame.Visible = false
	end
	if menu then
		menu.Visible = true
	end
	lastServerResult = nil
end

function UI.CloseAll()
	UI.CloseShop()
	UI.CloseModal()
	if resultsFrame then
		resultsFrame.Visible = false
	end
end

-- Exercises every tab, modal and HUD path once. Wired to the DevSelfTest flag;
-- prints a PASS/FAIL line so an automated playtest can catch UI errors that
-- only happen on a screen nobody opened.
function UI.SelfTest(): string
	local results = {}
	local function check(name: string, fn)
		local ok, err = pcall(fn)
		table.insert(results, name .. (ok and "=ok" or ("=FAIL:" .. tostring(err))))
	end

	check("menu", function()
		menu.Visible = true
	end)
	check("shop", function()
		UI.OpenShop()
	end)
	for _, tab in ipairs({ "Upgrades", "Prestige", "Planes", "Weapons", "Pets", "Shields", "Eggs", "Hangars", "Passes" }) do
		check(tab, function()
			UI.SelectTab(tab)
		end)
	end
	check("closeShop", function()
		UI.CloseShop()
	end)
	check("quests", function()
		UI.OpenQuests()
	end)
	check("closeModal", function()
		UI.CloseModal()
	end)
	check("codes", function()
		UI.OpenCodes()
	end)
	check("closeModal2", function()
		UI.CloseModal()
	end)
	check("settings", function()
		UI.OpenSettings()
	end)
	check("closeSettings", function()
		UI.CloseModal()
	end)
	check("leaderboard", function()
		UI.OpenLeaderboard()
	end)
	check("closeModal3", function()
		UI.CloseModal()
	end)
	check("hud", function()
		updateHud(80, 100, 1234, 500, 5, 12, "PAPER TOWN", 0.4, 5, 1.2, 50, 1, true)
	end)
	check("results", function()
		updateResults({ Distance = 1234, Kills = 12, Coins = 500, Gems = 5, BestCombo = 5, Reason = "death" })
	end)
	check("closeResults", function()
		UI.CloseResults()
	end)

	return table.concat(results, " | ")
end

-- ------------------------------------------------------------------- init ---
function UI.Init()
	if gui and gui.Parent then
		gui:Destroy()
	end

	gui = new("ScreenGui", {
		Name = "PaperWingsUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	scaler = new("UIScale", { Scale = 1 }, gui)
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			scaler.Scale = math.clamp(math.min(camera.ViewportSize.X / 1200, camera.ViewportSize.Y / 760), 0.55, 1)
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	toastBox = card(gui, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 420, 0, 46),
		BackgroundColor3 = C.Ink,
		Visible = false,
	})
	toastBox.ZIndex = 40
	toastLabel = text(toastBox, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	buildMenu()
	buildHud()
	buildShop()
	buildResults()
	buildModal()

	State.OnLoaded(function()
		UI.RefreshTop()
		UI.RefreshShop()
	end)
	State.OnUpdate(function()
		UI.RefreshTop()
		UI.RefreshShop()
	end)
	State.OnRunUpdate(function(...)
    print("[PaperWings] HUD EVENT RECEIVED")
    updateHud(...)
    print("[PaperWings] HUD visible:", hud.Visible)
    print("[PaperWings] Menu visible:", menu.Visible)
end)
	State.OnRunEnded(function(result)
		lastServerResult = nil
		updateResults(result)
		UI.RefreshTop()
	end)
	State.OnNotify(function(message)
		toast(message)
	end)

	Remotes.Get(Remotes.LeaderboardData).OnClientEvent:Connect(function(payload)
		leaderboardData = payload
		if leaderboardOpen and modalOpen then
			openModal("TOP FLIGHTS", renderLeaderboard)
		end
	end)

	Remotes.Get(Remotes.ShopSync).OnClientEvent:Connect(function(success, message)
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
	end)

	Remotes.Get(Remotes.RunEvent).OnClientEvent:Connect(function(kind, payload)
		if kind == "Ended" then
			lastServerResult = payload
			-- The results screen opens with the client's local estimate (which
			-- includes coin pickups the server does not pay). Once the
			-- authoritative payout arrives, rewrite the numbers so the player
			-- never sees a figure that is not what actually hit their balance.
			if payload and resultsFrame.Visible then
				resultsRefs.Distance.Text = "DISTANCE  " .. fmt(payload.Distance) .. " m"
				resultsRefs.Kills.Text = "TARGETS  " .. tostring(payload.Kills or 0)
				resultsRefs.Coins.Text = "COINS  " .. fmt(payload.Coins)
				resultsRefs.Gems.Text = "GEMS  " .. fmt(payload.Gems)
				resultsRefs.subtitle.Text = "REWARDS SAVED"
			end
			UI.RefreshTop()
			UI.RefreshShop()
		elseif kind == "Rebirth" then
			Effects.Play("Upgrade", nil, 0.6)
			showBanner("REBIRTH " .. tostring(payload and payload.Rebirths or ""))
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if bindingCaptureAction and input.UserInputType == Enum.UserInputType.Keyboard then
			local action = bindingCaptureAction
			bindingCaptureAction = nil
			local ok, message = Flight.SetBinding(action, input.KeyCode)
			if ok then
				local b = bindingButtons[action]
				if b then b.Text = input.KeyCode.Name end
				toast("Updated " .. action .. " binding")
			else
				local b = bindingButtons[action]
				if b then b.Text = Flight.GetBindings()[action].Name end
				toast(message)
			end
			return
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			if modalOpen then
				UI.CloseModal()
			elseif shopOpen then
				UI.CloseShop()
			end
		end
	end)

	UI.RefreshTop()

	-- Dev hook: run the UI smoke test once when ReplicatedStorage.DevSelfTest
	-- exists. Absent in a published place.
	if ReplicatedStorage:FindFirstChild("DevSelfTest") then
		task.delay(3, function()
			print("[UI] selftest " .. UI.SelfTest())
		end)
	end
end

return UI
