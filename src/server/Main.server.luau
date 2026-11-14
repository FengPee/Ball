-- Server entry point. Owns every player's arena simulation, rolls and save data.
-- Clients only send requests ("roll", "dash", ...) and draw what the server says.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rolls = require(Shared.Rolls)
local Sim = require(Shared.Sim)
local Codec = require(Shared.Codec)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)

-- Remotes ---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(class: string, name: string)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local SnapshotRE = remote("UnreliableRemoteEvent", "Snapshot") -- arena positions, 20x a second
local FxRE = remote("RemoteEvent", "Fx") -- kills, bosses, announcements
local StateRE = remote("RemoteEvent", "State") -- your keys, power, zone...
local RollRF = remote("RemoteFunction", "Roll")
local ActionRE = remote("RemoteEvent", "Action") -- equip, salvage, dash, zone, upgrade
remotes.Parent = ReplicatedStorage

World.build()

-- Sessions --------------------------------------------------------------------
local sessions = {} -- [Player] = session
local plotOwners = {} -- [plotIndex] = Player

local function claimPlot(player: Player): number?
	for i = 1, Config.Plot.count do
		if not plotOwners[i] then
			plotOwners[i] = player
			return i
		end
	end
	return nil
end

local function loadout(item)
	return { damage = Rolls.power(item), wtype = item.wtype, tier = item.tier }
end

local function pushState(s)
	local d = s.data
	local eq = d.equipped
	local nextZone = Config.Zones[d.zone + 1]
	StateRE:FireClient(s.player, {
		plot = s.plot,
		keys = d.keys,
		dust = d.dust,
		rolls = d.rolls,
		zone = d.zone,
		nextZonePower = nextZone and nextZone.power or nil,
		best = d.best,
		found = d.found,
		power = Rolls.power(eq),
		equippedName = Rolls.itemName(eq),
		equippedTier = eq.tier,
		level = eq.level,
		upgradeCost = Rolls.upgradeCost(eq),
		dashUnlocked = d.rolls >= Config.Ball.dashUnlockRolls,
		luck = s.luck,
		friends = s.friends,
	})
end

local function refreshStats(s)
	local eq = s.data.equipped
	s.arena:setLoadout(loadout(eq))
	s.powerStat.Value = Rolls.power(eq)
	s.bestStat.Value = Config.Tiers[s.data.best].name
	World.setOwner(s.plot, string.format("%s\nBest: %s", s.player.DisplayName, Config.Tiers[s.data.best].name))
end

local function salvagePending(s)
	if s.pending then
		s.data.dust += Rolls.salvageValue(s.pending)
		s.pending = nil
	end
end

-- Friend luck: +10% roll luck for each friend in your server.
local friendCache = {}
local function areFriends(a: Player, b: Player): boolean
	local k = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	if friendCache[k] == nil then
		local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
		friendCache[k] = ok and result or false
	end
	return friendCache[k]
end

local function recalcLuck()
	local list = Players:GetPlayers()
	for _, p in list do
		local s = sessions[p]
		if s then
			local friends = 0
			for _, q in list do
				if q ~= p and areFriends(p, q) then
					friends += 1
				end
			end
			s.friends = friends
			s.luck = Config.Rolls.baseLuck + math.min(friends * Config.Rolls.friendLuck, Config.Rolls.friendLuckCap)
			pushState(s)
		end
	end
end

local function placeCharacter(s, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and sessions[s.player] == s then
		character:PivotTo(World.plots[s.plot].spawnCFrame)
	end
end

local function onPlayerAdded(player: Player)
	local plot = claimPlot(player)
	if not plot then
		player:Kick("This server is full, please join another one.")
		return
	end
	local data, canSave = PlayerData.load(player)
	if not player.Parent then
		plotOwners[plot] = nil
		return
	end

	local center = World.plots[plot].center
	local s = {
		player = player,
		plot = plot,
		data = data,
		canSave = canSave,
		arena = Sim.new(center.X, center.Z, math.random),
		pending = nil,
		lastRoll = 0,
		lastZone = 0,
		keyProgress = 0,
		seq = 0,
		luck = Config.Rolls.baseLuck,
		friends = 0,
	}

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	s.powerStat = Instance.new("IntValue")
	s.powerStat.Name = "Power"
	s.powerStat.Parent = stats
	s.bestStat = Instance.new("StringValue")
	s.bestStat.Name = "Best"
	s.bestStat.Parent = stats
	stats.Parent = player

	sessions[player] = s
	s.arena:setZone(data.zone)
	World.setZone(plot, data.zone)
	refreshStats(s)

	player.CharacterAdded:Connect(function(character)
		placeCharacter(s, character)
	end)
	if player.Character then
		task.spawn(placeCharacter, s, player.Character)
	end

	pushState(s)
	task.spawn(recalcLuck)
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	salvagePending(s)
	sessions[player] = nil
	plotOwners[s.plot] = nil
	World.setOwner(s.plot, "Empty plot")
	World.setZone(s.plot, 1)
	FxRE:FireAllClients({ t = "clear", plot = s.plot })
	PlayerData.save(player, s.data, s.canSave)
	task.spawn(recalcLuck)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

-- Arena events ----------------------------------------------------------------
local function handleEvent(s, ev)
	if ev.type == "kill" then
		local d = s.data
		local keys = 0
		d.kills += 1
		if ev.kind == Sim.KIND_BOSS then
			keys = Config.Boss.keys
		else
			s.keyProgress += 1
			-- The very first kill always pays out, so the first roll comes fast.
			if d.kills == 1 or s.keyProgress >= Config.Zones[d.zone].killsPerKey then
				keys = 1
				s.keyProgress = 0
			end
		end
		d.keys += keys
		FxRE:FireAllClients({ t = "kill", plot = s.plot, x = ev.x, z = ev.z, r = ev.r, kind = ev.kind, keys = keys })
		if keys > 0 then
			pushState(s)
		end
	elseif ev.type == "boss" then
		FxRE:FireAllClients({ t = "boss", plot = s.plot })
	elseif ev.type == "down" then
		FxRE:FireClient(s.player, { t = "down", seconds = Config.Ball.respawn })
	end
end

local snapshotAcc = 0
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.05)
	for _, s in sessions do
		for _, ev in s.arena:step(dt) do
			handleEvent(s, ev)
		end
	end
	snapshotAcc += dt
	if snapshotAcc >= 1 / Config.Net.snapshotRate then
		snapshotAcc = 0
		for _, s in sessions do
			s.seq = (s.seq + 1) % 65536
			SnapshotRE:FireAllClients(Codec.encode(s.plot, s.seq, s.arena:entities()))
		end
	end
end)

-- Rolling ---------------------------------------------------------------------
RollRF.OnServerInvoke = function(player: Player)
	local s = sessions[player]
	if not s then
		return { ok = false, msg = "Still loading..." }
	end
	local now = os.clock()
	if now - s.lastRoll < Config.Rolls.minInterval then
		return { ok = false, msg = "Slow down!" }
	end
	local d = s.data
	if d.keys < 1 then
		return { ok = false, msg = "No keys! Defeat enemies to earn keys." }
	end
	s.lastRoll = now
	salvagePending(s)
	d.keys -= 1

	local item = Rolls.roll(d, s.luck, math.random)
	s.pending = item
	d.found[item.tier] = true
	local newBest = item.tier > d.best
	if newBest then
		d.best = item.tier
	end
	refreshStats(s)
	pushState(s)

	local tier = Config.Tiers[item.tier]
	if item.tier >= Config.Rolls.announceTier then
		-- Wait for the roll animation to finish before telling everyone.
		task.delay(2.2, function()
			FxRE:FireAllClients({
				t = "announce",
				plot = s.plot,
				name = player.DisplayName,
				tier = item.tier,
				item = Rolls.itemName(item),
				oneIn = tier.oneIn,
			})
		end)
	end

	local eq = d.equipped
	return {
		ok = true,
		tier = item.tier,
		wtype = item.wtype,
		name = Rolls.itemName(item),
		power = Rolls.power(item),
		oneIn = tier.oneIn,
		salvage = Rolls.salvageValue(item),
		currentName = Rolls.itemName(eq),
		currentTier = eq.tier,
		currentPower = Rolls.power(eq),
		newBest = newBest,
	}
end

-- Actions ---------------------------------------------------------------------
ActionRE.OnServerEvent:Connect(function(player: Player, action, arg)
	local s = sessions[player]
	if not s or type(action) ~= "string" then
		return
	end
	local d = s.data
	if action == "equip" then
		if s.pending then
			d.dust += Rolls.salvageValue(d.equipped)
			d.equipped = s.pending
			s.pending = nil
			refreshStats(s)
			pushState(s)
		end
	elseif action == "salvage" then
		if s.pending then
			salvagePending(s)
			pushState(s)
		end
	elseif action == "dash" then
		if d.rolls >= Config.Ball.dashUnlockRolls then
			s.arena:dash()
		end
	elseif action == "zone" then
		if type(arg) ~= "number" or (arg ~= 1 and arg ~= -1) then
			return
		end
		local now = os.clock()
		if now - s.lastZone < 1 then
			return
		end
		local target = d.zone + arg
		local zone = Config.Zones[target]
		if not zone then
			return
		end
		if arg > 0 and Rolls.power(d.equipped) < zone.power then
			FxRE:FireClient(player, { t = "toast", text = "Need " .. zone.power .. " power for " .. zone.name })
			return
		end
		s.lastZone = now
		d.zone = target
		s.keyProgress = 0
		s.arena:setZone(target)
		World.setZone(s.plot, target)
		FxRE:FireAllClients({ t = "clear", plot = s.plot })
		FxRE:FireClient(player, { t = "toast", text = "Entered " .. zone.name .. "!" })
		pushState(s)
	elseif action == "upgrade" then
		local cost = Rolls.upgradeCost(d.equipped)
		if d.dust >= cost then
			d.dust -= cost
			d.equipped.level += 1
			refreshStats(s)
			pushState(s)
		end
	end
end)

-- Saving ----------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(Config.Data.autosave)
		for player, s in sessions do
			task.spawn(PlayerData.save, player, s.data, s.canSave)
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for player, s in sessions do
		pending += 1
		task.spawn(function()
			salvagePending(s)
			PlayerData.save(player, s.data, s.canSave)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.1)
	end
end)
