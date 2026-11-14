-- One player's arena: balls bouncing on a flat floor with weapons orbiting them.
-- Runs on the server only. Pure maths on x/z numbers (no Roblox physics), so it is
-- cheap, deterministic enough to test, and the client can't cheat it.
local Config = require(script.Parent.Config)

local KIND_PLAYER, KIND_ENEMY, KIND_BOSS = 1, 2, 3

local Sim = {}
Sim.__index = Sim

function Sim.new(cx: number, cz: number, rng: () -> number)
	local self = setmetatable({}, Sim)
	self.cx, self.cz = cx, cz
	self.half = Config.Arena.half
	self.rng = rng
	self.time = 0
	self.nextId = 0
	self.player = nil
	self.enemies = {}
	self.zone = 1
	self.killsSinceBoss = 0
	self.bossAlive = false
	self.spawnTimer = 0.5
	self.dashReady = 0
	return self
end

function Sim:_id(): number
	self.nextId = self.nextId % 65000 + 1
	return self.nextId
end

function Sim:_randomDir(): (number, number)
	local a = self.rng() * math.pi * 2
	return math.cos(a), math.sin(a)
end

-- loadout = { damage, wtype, tier }
function Sim:setLoadout(loadout)
	local p = self.player
	if not p then
		local dx, dz = self:_randomDir()
		p = {
			id = self:_id(),
			kind = KIND_PLAYER,
			x = self.cx,
			z = self.cz,
			vx = dx * Config.Ball.speed,
			vz = dz * Config.Ball.speed,
			r = Config.Ball.radius,
			speed = Config.Ball.speed,
			hp = Config.Ball.hp,
			maxHp = Config.Ball.hp,
			angle = 0,
			spinDir = 1,
			hitCd = {},
			alive = true,
		}
		self.player = p
	end
	local wt = Config.WeaponTypes[loadout.wtype]
	p.dmg = loadout.damage
	p.wtype = loadout.wtype
	p.tier = loadout.tier
	p.length = Config.weaponLength(KIND_PLAYER, loadout.wtype)
	p.spin = wt.spin
	p.cooldown = wt.cooldown
end

function Sim:setZone(zone: number)
	self.zone = zone
	self.enemies = {}
	self.killsSinceBoss = 0
	self.bossAlive = false
	self.spawnTimer = 0.5
	local p = self.player
	if p then
		p.hp = p.maxHp
		p.alive = true
		p.hitCd = {}
	end
end

function Sim:_spawnEnemy(boss: boolean)
	local zone = Config.Zones[self.zone]
	local r = boss and Config.Boss.radius or Config.Enemy.radius
	local p = self.player
	local x, z = self.cx, self.cz
	for _ = 1, 12 do
		x = self.cx + (self.rng() * 2 - 1) * (self.half - r)
		z = self.cz + (self.rng() * 2 - 1) * (self.half - r)
		if not p or (x - p.x) ^ 2 + (z - p.z) ^ 2 > 100 then
			break
		end
	end
	local wtype = boss and Config.Boss.weaponType or (math.floor(self.rng() * 3) + 1)
	local wt = Config.WeaponTypes[wtype]
	local hp = boss and zone.bossHp or (zone.enemyHp[1] + self.rng() * (zone.enemyHp[2] - zone.enemyHp[1]))
	hp = math.floor(hp)
	local speed = boss and Config.Boss.speed or Config.Enemy.speed
	local dx, dz = self:_randomDir()
	local kind = boss and KIND_BOSS or KIND_ENEMY
	local e = {
		id = self:_id(),
		kind = kind,
		x = x,
		z = z,
		vx = dx * speed,
		vz = dz * speed,
		r = r,
		speed = speed,
		hp = hp,
		maxHp = hp,
		dmg = boss and zone.bossDmg or zone.enemyDmg,
		wtype = wtype,
		tier = 0,
		length = Config.weaponLength(kind, wtype),
		spin = boss and Config.Boss.spin or wt.spin * Config.Enemy.spinScale,
		cooldown = wt.cooldown,
		angle = self.rng() * math.pi * 2,
		spinDir = self.rng() < 0.5 and -1 or 1,
		hitCd = {},
		alive = true,
	}
	table.insert(self.enemies, e)
	if boss then
		self.bossAlive = true
	end
	return e
end

function Sim:_nearestEnemy(x: number, z: number)
	local best, bestD = nil, math.huge
	for _, e in self.enemies do
		local d = (e.x - x) ^ 2 + (e.z - z) ^ 2
		if d < bestD then
			best, bestD = e, d
		end
	end
	return best
end

local function pointSegDist(px, pz, x1, z1, x2, z2): number
	local dx, dz = x2 - x1, z2 - z1
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((px - x1) * dx + (pz - z1) * dz) / len2, 0, 1)
	end
	local qx, qz = x1 + dx * t, z1 + dz * t
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end

-- Attacker `a` swings at target `b`. Returns true on a hit.
function Sim:_tryHit(a, b, events): boolean
	if b.hp <= 0 then
		return false
	end
	local ca, sa = math.cos(a.angle), math.sin(a.angle)
	local x1, z1 = a.x + ca * a.r * 0.6, a.z + sa * a.r * 0.6
	local x2, z2 = a.x + ca * (a.r + a.length), a.z + sa * (a.r + a.length)
	if pointSegDist(b.x, b.z, x1, z1, x2, z2) > b.r then
		return false
	end
	local last = a.hitCd[b.id]
	if last and self.time - last < a.cooldown then
		return false
	end
	a.hitCd[b.id] = self.time
	b.hp -= a.dmg
	-- Knock the target away from the attacker and flip the attacker's spin.
	local nx, nz = b.x - a.x, b.z - a.z
	local d = math.sqrt(nx * nx + nz * nz)
	if d > 0.001 then
		local kb = Config.Knockback * (b.kind == KIND_BOSS and 0.35 or 1)
		b.vx += nx / d * kb
		b.vz += nz / d * kb
	end
	a.spinDir = -a.spinDir
	table.insert(events, { type = "hit", attacker = a.id, target = b.id, dmg = a.dmg, x = b.x, z = b.z })
	return true
end

function Sim:dash(): boolean
	local p = self.player
	if not p or not p.alive or self.time < self.dashReady then
		return false
	end
	local dx, dz = p.vx, p.vz
	local e = self:_nearestEnemy(p.x, p.z)
	if e then
		dx, dz = e.x - p.x, e.z - p.z
	end
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.001 then
		dx, dz, d = 1, 0, 1
	end
	p.vx, p.vz = dx / d * Config.Ball.dashSpeed, dz / d * Config.Ball.dashSpeed
	p.dashUntil = self.time + Config.Ball.dashTime
	self.dashReady = self.time + Config.Ball.dashCooldown
	return true
end

function Sim:step(dt: number)
	local events = {}
	self.time += dt
	local t = self.time
	local zone = Config.Zones[self.zone]
	local p = self.player
	if not p then
		return events
	end

	-- Respawn and regen
	if not p.alive and t >= p.respawnAt then
		p.alive = true
		p.hp = p.maxHp
		p.x, p.z = self.cx, self.cz
		table.insert(events, { type = "respawn" })
	end
	if p.alive then
		p.hp = math.min(p.maxHp, p.hp + Config.Ball.regen * dt)
	end

	-- Spawning
	self.spawnTimer -= dt
	if self.spawnTimer <= 0 then
		self.spawnTimer = Config.Enemy.spawnInterval
		if self.killsSinceBoss >= zone.bossEvery and not self.bossAlive then
			self:_spawnEnemy(true)
			self.killsSinceBoss = 0
			table.insert(events, { type = "boss" })
		elseif #self.enemies < zone.maxEnemies then
			self:_spawnEnemy(false)
		end
	end

	local all = {}
	if p.alive then
		table.insert(all, p)
	end
	for _, e in self.enemies do
		table.insert(all, e)
	end

	-- Movement
	local minX, maxX = self.cx - self.half, self.cx + self.half
	local minZ, maxZ = self.cz - self.half, self.cz + self.half
	for _, e in all do
		local target = e.speed
		if e.dashUntil and t < e.dashUntil then
			target = Config.Ball.dashSpeed
		end
		local other, homing
		if e == p then
			other, homing = self:_nearestEnemy(p.x, p.z), Config.Ball.homing
		elseif p.alive then
			other, homing = p, Config.Enemy.homing
		end
		if other then
			local dx, dz = other.x - e.x, other.z - e.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.01 then
				e.vx += dx / d * homing * dt
				e.vz += dz / d * homing * dt
			end
		end
		local s = math.sqrt(e.vx * e.vx + e.vz * e.vz)
		if s < 0.01 then
			e.vx, e.vz = self:_randomDir()
			s = 1
		end
		local ns = s + (target - s) * math.min(1, dt * 2.5)
		e.vx, e.vz = e.vx / s * ns, e.vz / s * ns
		e.x += e.vx * dt
		e.z += e.vz * dt
		if e.x - e.r < minX then
			e.x, e.vx = minX + e.r, math.abs(e.vx)
		elseif e.x + e.r > maxX then
			e.x, e.vx = maxX - e.r, -math.abs(e.vx)
		end
		if e.z - e.r < minZ then
			e.z, e.vz = minZ + e.r, math.abs(e.vz)
		elseif e.z + e.r > maxZ then
			e.z, e.vz = maxZ - e.r, -math.abs(e.vz)
		end
		e.angle = (e.angle + e.spin * e.spinDir * dt) % (math.pi * 2)
	end

	-- Ball-to-ball bounces (equal-mass elastic along the contact normal)
	for i = 1, #all do
		local a = all[i]
		for j = i + 1, #all do
			local b = all[j]
			local dx, dz = b.x - a.x, b.z - a.z
			local d = math.sqrt(dx * dx + dz * dz)
			local overlap = a.r + b.r - d
			if overlap > 0 and d > 0.001 then
				local nx, nz = dx / d, dz / d
				a.x -= nx * overlap / 2
				a.z -= nz * overlap / 2
				b.x += nx * overlap / 2
				b.z += nz * overlap / 2
				local rel = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz
				if rel > 0 then
					a.vx -= rel * nx
					a.vz -= rel * nz
					b.vx += rel * nx
					b.vz += rel * nz
				end
			end
		end
	end

	-- Weapon hits
	if p.alive then
		for _, e in self.enemies do
			self:_tryHit(p, e, events)
			if p.hp > 0 then
				self:_tryHit(e, p, events)
			end
		end
	end

	-- Deaths
	for i = #self.enemies, 1, -1 do
		local e = self.enemies[i]
		if e.hp <= 0 then
			table.remove(self.enemies, i)
			p.hitCd[e.id] = nil
			if e.kind == KIND_BOSS then
				self.bossAlive = false
			else
				self.killsSinceBoss += 1
			end
			table.insert(events, { type = "kill", id = e.id, kind = e.kind, x = e.x, z = e.z, r = e.r })
		end
	end
	if p.alive and p.hp <= 0 then
		if zone.canDie then
			p.alive = false
			p.respawnAt = t + Config.Ball.respawn
			table.insert(events, { type = "down", x = p.x, z = p.z })
		else
			p.hp = 1
		end
	end

	return events
end

-- Everything the client needs to draw this arena.
function Sim:entities()
	local list = {}
	local p = self.player
	if p and p.alive then
		table.insert(list, p)
	end
	for _, e in self.enemies do
		table.insert(list, e)
	end
	return list
end

Sim.KIND_PLAYER, Sim.KIND_ENEMY, Sim.KIND_BOSS = KIND_PLAYER, KIND_ENEMY, KIND_BOSS

return Sim
