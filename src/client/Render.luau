-- Draws every arena from server snapshots. Balls are smoothed toward the latest
-- server position, and hits are detected from HP drops so the client can add
-- squash, flash, hop and damage numbers without extra network traffic.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Codec = require(Shared:WaitForChild("Codec"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Render = {}
Render.localPlot = nil -- set by Main once the server tells us our plot
Render.onLocalHit = nil -- optional callback(damage) when our ball gets hit

local FLOOR_Y = Config.Arena.floorY
local PLAYER_COLOR = Color3.fromRGB(90, 215, 120)
local ENEMY_COLOR = Color3.fromRGB(235, 95, 110)
local BOSS_COLOR = Color3.fromRGB(150, 30, 60)
local WOOD = Color3.fromRGB(120, 85, 55)

local folder = Instance.new("Folder")
folder.Name = "Arenas"
folder.Parent = workspace

local visuals = {} -- [key] = visual
local arenaKeys = {} -- [plot] = { [key] = true }
local lastSeq = {} -- [plot] = seq

local function newPart(parent, size: Vector3, color: Color3, material, cf: CFrame)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Builds a weapon pointing along +X from the ball's centre. The model's pivot is
-- the ball centre, so rotating the pivot swings the weapon around the ball.
local function buildWeapon(kind: number, tier: number, wtype: number, r: number)
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local length = Config.weaponLength(kind, wtype)
	local color = Effects.tierColor(tier)
	local material = Enum.Material.Metal
	if tier == 1 then
		material = Enum.Material.Wood
	elseif tier >= 5 then
		material = Enum.Material.Neon
	end
	local start = r * 0.7
	local L = length + r * 0.3
	local th = (kind == 3) and 0.45 or 0.28 -- thickness
	local function at(x, z)
		return CFrame.new(start + x, 0, z or 0)
	end
	local name = Config.WeaponTypes[wtype].name
	if name == "Sword" then
		newPart(model, Vector3.new(L * 0.25, th, th), WOOD, Enum.Material.Wood, at(L * 0.125))
		newPart(model, Vector3.new(th * 1.2, th * 1.2, th * 4), color, material, at(L * 0.25))
		newPart(model, Vector3.new(L * 0.72, th * 0.6, th * 2), color, material, at(L * 0.25 + L * 0.36))
	elseif name == "Axe" then
		newPart(model, Vector3.new(L, th, th), WOOD, Enum.Material.Wood, at(L * 0.5))
		newPart(model, Vector3.new(L * 0.28, th * 0.8, th * 5), color, material, at(L * 0.84, th * 1.6))
	elseif name == "Mace" then
		newPart(model, Vector3.new(L * 0.8, th, th), WOOD, Enum.Material.Wood, at(L * 0.4))
		local head = newPart(model, Vector3.new(th * 5, th * 5, th * 5), color, material, at(L * 0.85))
		head.Shape = Enum.PartType.Ball
	else -- Skewer: a long thin stick with chunks of food on it
		newPart(model, Vector3.new(L, th * 0.55, th * 0.55), Color3.fromRGB(215, 190, 140), Enum.Material.Wood, at(L * 0.5))
		local foods = { Color3.fromRGB(240, 140, 50), Color3.fromRGB(110, 190, 70), Color3.fromRGB(150, 85, 60) }
		for i, f in foods do
			newPart(model, Vector3.new(th * 2.6, th * 2.6, th * 2.6), f, Enum.Material.SmoothPlastic, at(L * (0.3 + i * 0.15)))
		end
		newPart(model, Vector3.new(th * 1.4, th * 0.8, th * 0.8), color, material, at(L * 0.98))
	end
	model.WorldPivot = CFrame.identity
	return model
end

local function hpText(hp: number): string
	return Config.formatNumber(math.ceil(hp))
end

local function createVisual(plot: number, s)
	local v = {
		plot = plot,
		kind = s.kind,
		tier = s.tier,
		wtype = s.wtype,
		r = s.r,
		x = s.x,
		z = s.z,
		tx = s.x,
		tz = s.z,
		a = s.angle,
		ta = s.angle,
		hp = s.hp,
		maxHp = s.maxHp,
		hopT = 1,
		flash = 0,
	}
	local color = (s.kind == 1 and PLAYER_COLOR) or (s.kind == 3 and BOSS_COLOR) or ENEMY_COLOR
	v.color = color
	local model = Instance.new("Model")
	model.Name = "Ball"
	local ball = newPart(model, Vector3.new(s.r * 2, s.r * 2, s.r * 2), color, Enum.Material.SmoothPlastic, CFrame.new(s.x, FLOOR_Y + s.r, s.z))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = ball
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(s.r * 1.8, 0, s.r * 1.1, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = ball
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = hpText(s.hp)
	label.Parent = gui
	if s.kind == 1 then
		local ring = Instance.new("Highlight")
		ring.FillTransparency = 1
		ring.OutlineColor = Color3.new(1, 1, 1)
		ring.DepthMode = Enum.HighlightDepthMode.Occluded
		ring.Parent = model
	end
	model.Parent = folder
	v.model, v.ball, v.mesh, v.label = model, ball, mesh, label
	v.weapon = buildWeapon(s.kind, s.tier, s.wtype, s.r)
	v.weapon.Parent = model
	return v
end

local function destroyVisual(key)
	local v = visuals[key]
	if v then
		v.model:Destroy()
		visuals[key] = nil
	end
end

function Render.onSnapshot(b: buffer)
	local plot, seq, list = Codec.decode(b)
	if not Codec.isNewer(seq, lastSeq[plot]) then
		return -- unreliable events can arrive out of order
	end
	lastSeq[plot] = seq
	local seen = {}
	for _, s in list do
		local key = plot * 65536 + s.id
		seen[key] = true
		local v = visuals[key]
		if not v then
			v = createVisual(plot, s)
			visuals[key] = v
		elseif s.tier ~= v.tier or s.wtype ~= v.wtype then
			v.weapon:Destroy()
			v.tier, v.wtype = s.tier, s.wtype
			v.weapon = buildWeapon(s.kind, s.tier, s.wtype, s.r)
			v.weapon.Parent = v.model
		end
		local lost = v.hp - s.hp
		if lost > 0.5 then
			v.hopT = 0
			v.flash = 1
			local pos = Vector3.new(s.x, FLOOR_Y + s.r * 2 + 0.5, s.z)
			local big = lost >= v.maxHp * 0.25
			Effects.floatText(pos, "-" .. Config.formatNumber(lost), big and Color3.fromRGB(255, 230, 90) or Color3.new(1, 1, 1), big and 1.4 or 1)
			Effects.hit(pos, v.color)
			if s.kind == 1 and plot == Render.localPlot and Render.onLocalHit then
				Render.onLocalHit(lost)
			end
		end
		v.hp, v.maxHp = s.hp, s.maxHp
		v.tx, v.tz, v.ta = s.x, s.z, s.angle
		v.label.Text = hpText(s.hp)
	end
	local previous = arenaKeys[plot]
	if previous then
		for key in previous do
			if not seen[key] then
				destroyVisual(key)
			end
		end
	end
	arenaKeys[plot] = seen
end

function Render.clearArena(plot: number)
	local keys = arenaKeys[plot]
	if keys then
		for key in keys do
			destroyVisual(key)
		end
	end
	arenaKeys[plot] = nil
end

local TAU = math.pi * 2
RunService.RenderStepped:Connect(function(dt)
	local alpha = 1 - math.exp(-dt * 16)
	for _, v in visuals do
		v.x += (v.tx - v.x) * alpha
		v.z += (v.tz - v.z) * alpha
		local da = (v.ta - v.a + math.pi) % TAU - math.pi
		v.a += da * alpha
		v.hopT = math.min(1, v.hopT + dt / 0.3)
		v.flash = math.max(0, v.flash - dt * 6)
		local hop = math.sin(v.hopT * math.pi) * v.r * 0.45
		-- Squash on impact, then spring back.
		local squash = (1 - v.hopT) * 0.3
		v.mesh.Scale = Vector3.new(1 + squash, 1 - squash, 1 + squash)
		v.ball.Color = v.color:Lerp(Color3.new(1, 1, 1), v.flash)
		local centre = CFrame.new(v.x, FLOOR_Y + v.r + hop, v.z)
		v.ball.CFrame = centre
		v.weapon:PivotTo(centre * CFrame.Angles(0, -v.a, 0))
	end
end)

return Render
