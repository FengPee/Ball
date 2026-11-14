-- All 2D interface, built in code: stats, best-drop bar, buttons, the rolling
-- tier list and the equip/salvage popup. Works with mouse, touch and keys.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Ui = {}
Ui.busy = false -- true while a roll is animating or waiting for a choice

local FONT = Enum.Font.FredokaOne
local DARK = Color3.fromRGB(28, 30, 40)
local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(255, 205, 60)

local gui
local refs = {}
local state = nil
local callbacks = {}

local function new(class: string, props, children)
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(radius: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(thickness: number?, color: Color3?)
	return new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	if props.TextStrokeTransparency == nil then
		props.TextStrokeTransparency = 0.5
	end
	return new("TextLabel", props)
end

local function button(props, onClick)
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	props.AutoButtonColor = true
	props.TextStrokeTransparency = 0.4
	local b = new("TextButton", props, { corner(14), stroke(3) })
	new("UITextSizeConstraint", { MaxTextSize = 34, Parent = b })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = b,
	})
	local scale = new("UIScale", { Parent = b })
	b.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		onClick()
	end)
	return b
end

local function pop(inst: GuiObject)
	local scale = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

---------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------
local function buildHud()
	-- Stats, top left
	local stats = new("Frame", {
		Name = "Stats",
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.25,
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(0, 170, 0, 128),
		Parent = gui,
	}, { corner(12), stroke(2) })
	new("UIListLayout", { Padding = UDim.new(0, 2), Parent = stats })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), Parent = stats })
	local function stat(name)
		return text({ Name = name, Size = UDim2.new(1, -10, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Parent = stats })
	end
	refs.power = stat("Power")
	refs.keys = stat("Keys")
	refs.dust = stat("Dust")
	refs.luck = stat("Luck")

	-- Best drop bar, top centre
	local bar = new("Frame", {
		Name = "BestDrop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 360, 0, 58),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.25,
		Parent = gui,
	}, { corner(12), stroke(2) })
	text({ Text = "BEST DROP", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 2), Parent = bar })
	local slots = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 22),
		Size = UDim2.new(1, -16, 0, 28),
		Parent = bar,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = slots,
	})
	refs.slots = {}
	for i = 1, #Config.Tiers do
		local slot = new("Frame", {
			Size = UDim2.new(0, 34, 0, 28),
			BackgroundColor3 = Color3.fromRGB(60, 62, 75),
			Parent = slots,
		}, { corner(6), stroke(2) })
		local q = text({ Text = "?", Size = UDim2.fromScale(1, 1), Parent = slot })
		refs.slots[i] = { frame = slot, label = q }
	end
	refs.zoneLabel = text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.new(0, 360, 0, 26),
		TextStrokeTransparency = 0.2,
		Parent = gui,
	})

	-- Main roll button, bottom centre
	refs.roll = button({
		Name = "Roll",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 230, 0, 70),
		BackgroundColor3 = YELLOW,
		TextColor3 = WHITE,
		Text = "OPEN CHEST",
		Parent = gui,
	}, function()
		callbacks.roll()
	end)
	refs.hint = text({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -94),
		Size = UDim2.new(0, 320, 0, 34),
		TextColor3 = YELLOW,
		TextStrokeTransparency = 0,
		Text = "",
		Parent = gui,
	})

	refs.dash = button({
		Name = "Dash",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -130, 1, -16),
		Size = UDim2.new(0, 110, 0, 60),
		BackgroundColor3 = Color3.fromRGB(80, 140, 255),
		Text = "DASH [F]",
		Parent = gui,
	}, function()
		callbacks.dash()
	end)
	refs.dashCover = new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		ZIndex = 3,
		Parent = refs.dash,
	}, { corner(14) })

	refs.upgrade = button({
		Name = "Upgrade",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 130, 1, -16),
		Size = UDim2.new(0, 130, 0, 60),
		BackgroundColor3 = Color3.fromRGB(160, 90, 255),
		Text = "UPGRADE",
		Parent = gui,
	}, function()
		callbacks.upgrade()
	end)

	-- Zone and camera controls, right side
	local side = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 210),
		Parent = gui,
	})
	new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = side })
	refs.nextZone = button({
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.fromRGB(70, 190, 110),
		Text = "NEXT ZONE",
		Parent = side,
	}, function()
		callbacks.zone(1)
	end)
	refs.prevZone = button({
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(90, 95, 110),
		Text = "< BACK",
		Parent = side,
	}, function()
		callbacks.zone(-1)
	end)
	refs.camera = button({
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(90, 95, 110),
		Text = "CAMERA [C]",
		Parent = side,
	}, function()
		callbacks.camera()
	end)

	refs.toast = text({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0.8, 0, 0, 48),
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		Parent = gui,
	})
end

local function buildRollPanel()
	local panel = new("Frame", {
		Name = "RollPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 330, 0, 50 + #Config.Tiers * 34),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, { corner(14), stroke(4, YELLOW) })
	refs.rollTitle = text({
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 4),
		Text = "Rolling...",
		TextColor3 = YELLOW,
		TextStrokeTransparency = 0,
		ZIndex = 11,
		Parent = panel,
	})
	refs.rows = {}
	for i, tier in Config.Tiers do
		local color = Effects.rgb(tier.color)
		local row = new("Frame", {
			Position = UDim2.new(0, 10, 0, 44 + (i - 1) * 34),
			Size = UDim2.new(1, -20, 0, 30),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.7,
			ZIndex = 11,
			Parent = panel,
		}, { corner(8) })
		local rowStroke = stroke(0, WHITE)
		rowStroke.Parent = row
		text({
			Text = tier.name,
			Size = UDim2.new(0.6, 0, 1, -6),
			Position = UDim2.new(0, 8, 0, 3),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 0.2,
			ZIndex = 12,
			Parent = row,
		})
		text({
			Text = "1 in " .. Config.formatNumber(tier.oneIn),
			Size = UDim2.new(0.4, -10, 1, -10),
			Position = UDim2.new(0.6, 0, 0, 5),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.2,
			ZIndex = 12,
			Parent = row,
		})
		refs.rows[i] = { frame = row, stroke = rowStroke }
	end
	refs.rollPanel = panel
end

local function card(parent, title, x)
	local f = new("Frame", {
		Position = UDim2.new(x, 6, 0, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		BackgroundColor3 = Color3.fromRGB(45, 48, 62),
		ZIndex = 21,
		Parent = parent,
	}, { corner(10) })
	text({ Text = title, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 4), ZIndex = 22, Parent = f })
	local name = text({ Size = UDim2.new(1, -10, 0, 30), Position = UDim2.new(0, 5, 0, 30), ZIndex = 22, Parent = f })
	local power = text({ Size = UDim2.new(1, -10, 0, 30), Position = UDim2.new(0, 5, 0, 64), ZIndex = 22, Parent = f })
	return { frame = f, name = name, power = power }
end

local function buildResultPopup()
	local popup = new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 420, 0, 290),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(16) })
	refs.resultStroke = stroke(5, YELLOW)
	refs.resultStroke.Parent = popup
	refs.resultTitle = text({
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.new(0, 0, 0, 8),
		TextStrokeTransparency = 0,
		ZIndex = 21,
		Parent = popup,
	})
	refs.resultOdds = text({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 60),
		TextColor3 = Color3.fromRGB(200, 200, 210),
		ZIndex = 21,
		Parent = popup,
	})
	local cards = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 90),
		Size = UDim2.new(1, -20, 0, 104),
		ZIndex = 21,
		Parent = popup,
	})
	refs.cardOld = card(cards, "EQUIPPED", 0)
	refs.cardNew = card(cards, "NEW", 0.5)
	refs.equip = button({
		Position = UDim2.new(0, 16, 1, -76),
		Size = UDim2.new(0.5, -24, 0, 60),
		BackgroundColor3 = Color3.fromRGB(70, 190, 110),
		Text = "EQUIP",
		ZIndex = 21,
		Parent = popup,
	}, function()
		Ui.finishRoll("equip")
	end)
	refs.salvage = button({
		Position = UDim2.new(0.5, 8, 1, -76),
		Size = UDim2.new(0.5, -24, 0, 60),
		BackgroundColor3 = Color3.fromRGB(110, 110, 125),
		Text = "SALVAGE",
		ZIndex = 21,
		Parent = popup,
	}, function()
		Ui.finishRoll("salvage")
	end)
	refs.result = popup
end

function Ui.build(cbs)
	callbacks = cbs
	gui = new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	buildHud()
	buildRollPanel()
	buildResultPopup()
	Ui.refresh()
end

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------
function Ui.setState(s)
	local oldKeys = state and state.keys or 0
	state = s
	Ui.refresh()
	if s.keys > oldKeys and not Ui.busy then
		pop(refs.roll)
	end
end

function Ui.getState()
	return state
end

function Ui.refresh()
	if not state then
		refs.power.Text = "Loading..."
		return
	end
	local s = state
	refs.power.Text = "Power " .. Config.formatNumber(s.power)
	refs.keys.Text = "Keys " .. s.keys
	refs.dust.Text = "Dust " .. Config.formatNumber(s.dust)
	local luckText = string.format("Luck x%.1f", s.luck)
	if s.friends > 0 then
		luckText ..= " (" .. s.friends .. " friend" .. (s.friends > 1 and "s" or "") .. ")"
	end
	refs.luck.Text = luckText

	for i, slot in refs.slots do
		if s.found[i] then
			slot.frame.BackgroundColor3 = Effects.tierColor(i)
			slot.label.Text = ""
		else
			slot.frame.BackgroundColor3 = Color3.fromRGB(60, 62, 75)
			slot.label.Text = "?"
		end
		slot.frame:FindFirstChildOfClass("UIStroke").Color = (i == s.best) and WHITE or Color3.new(0, 0, 0)
	end

	local zone = Config.Zones[s.zone]
	refs.zoneLabel.Text = string.format("Zone %d: %s   |   %s Lv.%d", s.zone, zone.name, s.equippedName, s.level)
	refs.zoneLabel.TextColor3 = Effects.tierColor(s.equippedTier)

	refs.roll.Text = "OPEN CHEST  (" .. s.keys .. ")"
	refs.roll.BackgroundColor3 = s.keys > 0 and YELLOW or Color3.fromRGB(120, 115, 100)

	if s.rolls == 0 and s.keys > 0 then
		refs.hint.Text = "Open the chest! [E]"
	elseif s.rolls == 0 then
		refs.hint.Text = "Your ball fights on its own. Kills drop keys!"
	elseif s.nextZonePower and s.power >= s.nextZonePower and s.zone == 1 then
		refs.hint.Text = "You're strong enough for the next zone!"
	else
		refs.hint.Text = ""
	end

	refs.dash.Visible = true
	refs.dash.Text = s.dashUnlocked and "DASH [F]" or "LOCKED"
	refs.dash.BackgroundColor3 = s.dashUnlocked and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(90, 95, 110)

	refs.upgrade.Text = "UPGRADE (" .. Config.formatNumber(s.upgradeCost) .. " dust)"
	refs.upgrade.BackgroundColor3 = s.dust >= s.upgradeCost and Color3.fromRGB(160, 90, 255) or Color3.fromRGB(90, 95, 110)

	if s.nextZonePower then
		local ready = s.power >= s.nextZonePower
		refs.nextZone.Visible = true
		refs.nextZone.Text = ready and "NEXT ZONE >" or ("NEXT ZONE\nneeds " .. Config.formatNumber(s.nextZonePower))
		refs.nextZone.BackgroundColor3 = ready and Color3.fromRGB(70, 190, 110) or Color3.fromRGB(90, 95, 110)
	else
		refs.nextZone.Visible = false
	end
	refs.prevZone.Visible = s.zone > 1
end

---------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------
local toastToken = 0
function Ui.toast(message: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	refs.toast.Text = message
	refs.toast.TextColor3 = color or WHITE
	refs.toast.TextTransparency = 0
	pop(refs.toast)
	task.delay(2.2, function()
		if token == toastToken then
			TweenService:Create(refs.toast, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

function Ui.dashCooldown(seconds: number)
	refs.dashCover.Size = UDim2.fromScale(1, 1)
	TweenService:Create(refs.dashCover, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
end

function Ui.setCameraLabel(on: boolean)
	refs.camera.Text = on and "FREE CAM [C]" or "ARENA CAM [C]"
end

---------------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------------
local onChoice = nil

local function highlight(i: number?)
	for j, row in refs.rows do
		local on = j == i
		row.frame.BackgroundTransparency = on and 0 or 0.7
		row.stroke.Thickness = on and 3 or 0
	end
end

-- Animates the tier list landing on `result.tier`, then shows the popup.
-- `choose(choice)` is called with "equip" or "salvage".
function Ui.playRoll(result, choose)
	onChoice = choose
	local tier = result.tier
	local n = #Config.Tiers
	refs.rollPanel.Visible = true
	refs.rollTitle.Text = "Rolling..."
	refs.rollTitle.TextColor3 = YELLOW
	pop(refs.rollPanel)

	-- Rarer results get a longer, tenser spin with a tease of the tier above.
	local steps = 12 + math.min(tier, 6) * 2
	for step = 1, steps do
		local i
		if step == steps then
			i = tier
		elseif step == steps - 1 and tier < n then
			i = tier + 1
		else
			i = math.random(1, math.min(n, tier + 3))
		end
		highlight(i)
		task.wait(0.04 + (step / steps) ^ 3 * 0.32)
	end
	local tierInfo = Config.Tiers[tier]
	local color = Effects.rgb(tierInfo.color)
	refs.rollTitle.Text = string.upper(tierInfo.name) .. "!"
	refs.rollTitle.TextColor3 = color
	pop(refs.rollTitle)
	if tier >= 4 then
		Effects.shake(0.6 + tier * 0.15, 0.5)
	end
	task.wait(0.7)
	refs.rollPanel.Visible = false
	highlight(nil)

	-- Result popup
	refs.resultTitle.Text = string.upper(tierInfo.name) .. "!" .. (result.newBest and "  NEW BEST!" or "")
	refs.resultTitle.TextColor3 = color
	refs.resultStroke.Color = color
	refs.resultOdds.Text = "1 in " .. Config.formatNumber(result.oneIn)
	refs.cardOld.name.Text = result.currentName
	refs.cardOld.name.TextColor3 = Effects.tierColor(result.currentTier)
	refs.cardOld.power.Text = Config.formatNumber(result.currentPower) .. " power"
	refs.cardNew.name.Text = result.name
	refs.cardNew.name.TextColor3 = color
	local better = result.power > result.currentPower
	refs.cardNew.power.Text = Config.formatNumber(result.power) .. " power " .. (better and "▲" or "▼")
	refs.cardNew.power.TextColor3 = better and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 110, 110)
	refs.salvage.Text = "SALVAGE +" .. result.salvage
	refs.equip.BackgroundColor3 = better and Color3.fromRGB(70, 190, 110) or Color3.fromRGB(90, 95, 110)
	refs.salvage.BackgroundColor3 = better and Color3.fromRGB(90, 95, 110) or Color3.fromRGB(70, 190, 110)
	refs.result.Visible = true
	pop(refs.result)
end

function Ui.finishRoll(choice: string)
	if not refs.result.Visible then
		return
	end
	refs.result.Visible = false
	local cb = onChoice
	onChoice = nil
	if cb then
		cb(choice)
	end
end

return Ui
