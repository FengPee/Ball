-- Builds the map in code: grass, the central plaza, and 8 plots in a ring.
-- Each plot has a walled arena (the "stadium"), a chest and an owner sign.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local World = {}
World.plots = {}

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

local function billboard(parent, text, size, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function buildChest(parent, cf)
	local chest = Instance.new("Model")
	chest.Name = "Chest"
	part({
		Name = "Body",
		Size = Vector3.new(4.5, 2.4, 3.2),
		CFrame = cf * CFrame.new(0, 1.2, 0),
		Color = Color3.fromRGB(190, 40, 45),
		Material = Enum.Material.SmoothPlastic,
		Parent = chest,
	})
	part({
		Name = "Lid",
		Size = Vector3.new(4.7, 1.1, 3.4),
		CFrame = cf * CFrame.new(0, 2.95, 0),
		Color = Color3.fromRGB(220, 60, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = chest,
	})
	part({
		Name = "Lock",
		Size = Vector3.new(0.9, 1.1, 0.3),
		CFrame = cf * CFrame.new(0, 2.3, -1.75),
		Color = Color3.fromRGB(255, 205, 60),
		Material = Enum.Material.Neon,
		Parent = chest,
	})
	for _, x in { -2.1, 2.1 } do
		part({
			Name = "Trim",
			Size = Vector3.new(0.35, 3.6, 3.5),
			CFrame = cf * CFrame.new(x, 1.8, 0),
			Color = Color3.fromRGB(255, 205, 60),
			Material = Enum.Material.SmoothPlastic,
			Parent = chest,
		})
	end
	chest.Parent = parent
	return chest
end

local function buildPlot(index, parent)
	local cx, cz = Config.plotCenter(index)
	local center = Vector3.new(cx, 0, cz)
	local toPlaza = Vector3.new(-cx, 0, -cz).Unit
	local half = Config.Arena.half
	local wall = Config.Arena.wallThickness
	local floorY = Config.Arena.floorY

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)

	part({
		Name = "Pad",
		Size = Vector3.new(Config.Plot.size, 0.6, Config.Plot.size),
		Position = center + Vector3.new(0, 0.3, 0),
		Color = Color3.fromRGB(205, 200, 185),
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	local floor = part({
		Name = "ArenaFloor",
		Size = Vector3.new(half * 2 + wall * 2, floorY - 0.6, half * 2 + wall * 2),
		Position = center + Vector3.new(0, (floorY + 0.6) / 2, 0),
		Color = rgb(Config.Zones[1].floor),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local wallY = floorY + Config.Arena.wallHeight / 2
	local wallColor = Color3.fromRGB(55, 60, 75)
	for _, s in { -1, 1 } do
		part({
			Name = "Wall",
			Size = Vector3.new(half * 2 + wall * 2, Config.Arena.wallHeight, wall),
			Position = center + Vector3.new(0, wallY, s * (half + wall / 2)),
			Color = wallColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		part({
			Name = "Wall",
			Size = Vector3.new(wall, Config.Arena.wallHeight, half * 2),
			Position = center + Vector3.new(s * (half + wall / 2), wallY, 0),
			Color = wallColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	local chestPos = center + toPlaza * (half + 6) + Vector3.new(0, 0.6, 0)
	local chestCf = CFrame.lookAt(chestPos, Vector3.new(cx, chestPos.Y, cz))
	buildChest(model, chestCf)

	local signAnchor = part({
		Name = "SignAnchor",
		Size = Vector3.new(1, 1, 1),
		Position = chestPos + Vector3.new(0, 9, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	local ownerLabel = billboard(signAnchor, "Empty plot", UDim2.new(16, 0, 3, 0), 220)

	local spawnPos = center + toPlaza * (half + 11) + Vector3.new(0, 3.5, 0)
	model.Parent = parent

	World.plots[index] = {
		index = index,
		center = center,
		chestPos = chestPos,
		spawnCFrame = CFrame.lookAt(spawnPos, Vector3.new(cx, spawnPos.Y, cz)),
		model = model,
		floor = floor,
		ownerLabel = ownerLabel,
	}
end

function World.build()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.5
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)

	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	part({
		Name = "Ground",
		Size = Vector3.new(420, 2, 420),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(95, 160, 80),
		Material = Enum.Material.Grass,
		Parent = map,
	})
	part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 64, 64),
		CFrame = CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(230, 225, 210),
		Material = Enum.Material.Slate,
		Parent = map,
	})
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.9, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = map
	local bossSign = part({
		Name = "BossSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 12, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = map,
	})
	billboard(bossSign, "WORLD BOSS ARENA\ncoming next update", UDim2.new(26, 0, 6, 0), 400)

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = workspace
	for i = 1, Config.Plot.count do
		buildPlot(i, plots)
	end
end

function World.setOwner(index: number, text: string)
	local plot = World.plots[index]
	if plot then
		plot.ownerLabel.Text = text
	end
end

function World.setZone(index: number, zone: number)
	local plot = World.plots[index]
	if plot then
		plot.floor.Color = rgb(Config.Zones[zone].floor)
	end
end

return World
