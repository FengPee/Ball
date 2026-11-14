-- Purely visual, client-side effects. Nothing here affects gameplay.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Effects = {}

local folder = Instance.new("Folder")
folder.Name = "Effects"
folder.Parent = workspace

function Effects.rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Effects.tierColor(tier: number): Color3
	local t = Config.Tiers[tier]
	return t and Effects.rgb(t.color) or Color3.fromRGB(110, 110, 120)
end

local function anchorAt(pos: Vector3, lifetime: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Position = pos
	p.Parent = folder
	Debris:AddItem(p, lifetime)
	return p
end

function Effects.floatText(pos: Vector3, text: string, color: Color3, scale: number?)
	local s = scale or 1
	local anchor = anchorAt(pos, 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(4 * s, 0, 1.6 * s, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

-- Small burst of glowing chips flying out of a point.
function Effects.burst(pos: Vector3, color: Color3, count: number, size: number, speed: number, lifetime: number)
	for _ = 1, count do
		local p = Instance.new("Part")
		p.Size = Vector3.new(size, size, size)
		p.Color = color
		p.Material = Enum.Material.Neon
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = folder
		local a = math.random() * math.pi * 2
		p.AssemblyLinearVelocity = Vector3.new(math.cos(a) * speed, speed * (0.6 + math.random()), math.sin(a) * speed)
		p.AssemblyAngularVelocity = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 10)
		TweenService:Create(p, TweenInfo.new(lifetime), { Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		Debris:AddItem(p, lifetime)
	end
end

function Effects.hit(pos: Vector3, color: Color3)
	Effects.burst(pos, color, 4, 0.35, 14, 0.35)
end

function Effects.shatter(pos: Vector3, color: Color3, r: number)
	Effects.burst(pos, color, 10, r * 0.45, 20, 0.9)
	Effects.burst(pos, Color3.new(1, 1, 1), 5, 0.3, 26, 0.5)
end

-- Tall light beam over a plot's chest for rare rolls, visible from across the map.
function Effects.beam(pos: Vector3, color: Color3, seconds: number)
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(160, 0.5, 0.5)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Transparency = 0.2
	beam.Parent = folder
	TweenService:Create(beam, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = Vector3.new(160, 5, 5) }):Play()
	task.delay(seconds - 0.8, function()
		TweenService:Create(beam, TweenInfo.new(0.8), { Transparency = 1, Size = Vector3.new(160, 0.2, 0.2) }):Play()
	end)
	Debris:AddItem(beam, seconds)
	Effects.burst(pos + Vector3.new(0, 4, 0), color, 16, 0.6, 30, 1.4)
end

function Effects.chestPop(plot: number)
	local plots = workspace:FindFirstChild("Plots")
	local model = plots and plots:FindFirstChild("Plot" .. plot)
	local lid = model and model:FindFirstChild("Chest") and model.Chest:FindFirstChild("Lid")
	if not lid then
		return
	end
	local base = lid:GetAttribute("BaseCFrame") or lid.CFrame
	lid:SetAttribute("BaseCFrame", base)
	local up = TweenService:Create(lid, TweenInfo.new(0.15, Enum.EasingStyle.Back), { CFrame = base * CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(-25), 0, 0) })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(lid, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { CFrame = base }):Play()
	end)
end

local shakeUntil, shakeStrength = 0, 0
function Effects.shake(strength: number, seconds: number)
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

function Effects.shakeOffset(): CFrame
	local now = os.clock()
	if now > shakeUntil then
		shakeStrength = 0
		return CFrame.identity
	end
	local s = shakeStrength * (shakeUntil - now) * 4
	return CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s)
end

return Effects
