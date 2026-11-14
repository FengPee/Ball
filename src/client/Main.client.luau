-- Client entry point: wires remotes, input and camera to the UI and renderer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Effects = require(script.Parent:WaitForChild("Effects"))
local Render = require(script.Parent:WaitForChild("Render"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local camera = workspace.CurrentCamera
local arenaCam = false
local myPlot = nil
local dashReadyAt = 0

local function plotCenter(plot: number): Vector3
	local x, z = Config.plotCenter(plot)
	return Vector3.new(x, Config.Arena.floorY, z)
end

local function setArenaCam(on: boolean)
	arenaCam = on and myPlot ~= nil
	if not arenaCam then
		camera.CameraType = Enum.CameraType.Custom
	end
	Ui.setCameraLabel(arenaCam)
end

-- Actions ---------------------------------------------------------------------
local function roll()
	local s = Ui.getState()
	if Ui.busy or not s then
		return
	end
	if s.keys < 1 then
		Ui.toast("No keys! Kills drop keys.")
		return
	end
	Ui.busy = true
	Effects.chestPop(s.plot)
	local ok, result = pcall(function()
		return Remotes.Roll:InvokeServer()
	end)
	if not ok or not result or not result.ok then
		Ui.toast(result and result.msg or "Roll failed, try again")
		Ui.busy = false
		return
	end
	Ui.playRoll(result, function(choice)
		Remotes.Action:FireServer(choice)
		Ui.busy = false
	end)
end

local function dash()
	local s = Ui.getState()
	if not s or not s.dashUnlocked then
		Ui.toast("Dash unlocks after " .. Config.Ball.dashUnlockRolls .. " chest rolls")
		return
	end
	local now = os.clock()
	if now < dashReadyAt then
		return
	end
	dashReadyAt = now + Config.Ball.dashCooldown
	Remotes.Action:FireServer("dash")
	Ui.dashCooldown(Config.Ball.dashCooldown)
end

Ui.build({
	roll = roll,
	dash = dash,
	upgrade = function()
		local s = Ui.getState()
		if s and s.dust < s.upgradeCost then
			Ui.toast("Salvage gear to get dust")
			return
		end
		Remotes.Action:FireServer("upgrade")
	end,
	zone = function(dir)
		Remotes.Action:FireServer("zone", dir)
	end,
	camera = function()
		setArenaCam(not arenaCam)
	end,
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		roll()
	elseif input.KeyCode == Enum.KeyCode.F then
		dash()
	elseif input.KeyCode == Enum.KeyCode.C then
		setArenaCam(not arenaCam)
	end
end)

-- Remotes ---------------------------------------------------------------------
Remotes.Snapshot.OnClientEvent:Connect(Render.onSnapshot)

Remotes.State.OnClientEvent:Connect(function(s)
	local first = myPlot == nil
	myPlot = s.plot
	Render.localPlot = s.plot
	Ui.setState(s)
	if first then
		setArenaCam(true) -- drop straight into watching your fight
	end
end)

local function systemMessage(message: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system then
		pcall(function()
			system:DisplaySystemMessage(message)
		end)
	end
end

Remotes.Fx.OnClientEvent:Connect(function(fx)
	if fx.t == "kill" then
		local pos = Vector3.new(fx.x, Config.Arena.floorY + fx.r, fx.z)
		local color = fx.kind == 3 and Color3.fromRGB(150, 30, 60) or Color3.fromRGB(235, 95, 110)
		Effects.shatter(pos, color, fx.r)
		if fx.plot == myPlot then
			if fx.keys > 0 then
				Effects.floatText(pos + Vector3.new(0, 3, 0), "+" .. fx.keys .. " KEY", Color3.fromRGB(255, 205, 60), 1.5)
			end
			Effects.shake(fx.kind == 3 and 1.5 or 0.35, fx.kind == 3 and 0.6 or 0.15)
			if fx.kind == 3 then
				Ui.toast("BOSS DEFEATED! +" .. fx.keys .. " keys", Color3.fromRGB(255, 205, 60))
			end
		end
	elseif fx.t == "boss" then
		if fx.plot == myPlot then
			Ui.toast("A BOSS APPEARED!", Color3.fromRGB(255, 90, 90))
			Effects.shake(1, 0.5)
		end
	elseif fx.t == "down" then
		Ui.toast("Your ball was knocked out! Back in " .. fx.seconds .. "s", Color3.fromRGB(255, 110, 110))
	elseif fx.t == "clear" then
		Render.clearArena(fx.plot)
	elseif fx.t == "toast" then
		Ui.toast(fx.text)
	elseif fx.t == "announce" then
		local tier = Config.Tiers[fx.tier]
		local color = Effects.tierColor(fx.tier)
		local hex = color:ToHex()
		systemMessage(string.format(
			'<font color="#%s"><b>%s rolled %s %s! (1 in %s)</b></font>',
			hex,
			fx.name,
			string.upper(tier.name),
			fx.item,
			Config.formatNumber(fx.oneIn)
		))
		local x, z = Config.plotCenter(fx.plot)
		local toPlaza = Vector3.new(-x, 0, -z).Unit
		local chestPos = Vector3.new(x, 0, z) + toPlaza * (Config.Arena.half + 6)
		Effects.beam(chestPos, color, 3 + fx.tier)
		if fx.plot ~= myPlot and fx.tier >= 6 then
			Ui.toast(fx.name .. " rolled " .. string.upper(tier.name) .. "!", color)
		end
	end
end)

Render.onLocalHit = function(damage)
	if damage >= 10 then
		Effects.shake(0.25, 0.12)
	end
end

-- Camera ----------------------------------------------------------------------
-- Arena cam: looking down at your stadium at an angle, from the chest side.
RunService:BindToRenderStep("ArenaCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if not arenaCam or not myPlot then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local center = plotCenter(myPlot)
	local toPlaza = Vector3.new(-center.X, 0, -center.Z).Unit
	local eye = center + toPlaza * 36 + Vector3.new(0, 50, 0)
	camera.CFrame = CFrame.lookAt(eye, center + toPlaza * 2) * Effects.shakeOffset()
end)

Players.LocalPlayer.CharacterAdded:Connect(function()
	if arenaCam then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end)
