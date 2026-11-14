-- All tunable numbers live here. Pure data: no Roblox APIs, so it runs in tests too.
local Config = {}

-- Rarity ladder. `oneIn` is shown to players as "1 in X". Colors are RGB 0-255.
Config.Tiers = {
	{ name = "Common", oneIn = 1, color = { 200, 200, 205 }, damage = 18, material = "Wooden" },
	{ name = "Uncommon", oneIn = 4, color = { 110, 220, 110 }, damage = 45, material = "Bronze" },
	{ name = "Rare", oneIn = 15, color = { 90, 190, 255 }, damage = 110, material = "Steel" },
	{ name = "Epic", oneIn = 60, color = { 170, 90, 255 }, damage = 240, material = "Amethyst" },
	{ name = "Legendary", oneIn = 300, color = { 255, 170, 50 }, damage = 520, material = "Golden" },
	{ name = "Mythic", oneIn = 2000, color = { 255, 70, 110 }, damage = 1150, material = "Crimson" },
	{ name = "Celestial", oneIn = 12000, color = { 120, 255, 230 }, damage = 2600, material = "Starforged" },
	{ name = "Cosmic", oneIn = 80000, color = { 80, 60, 230 }, damage = 6000, material = "Void" },
	{ name = "Eternal", oneIn = 500000, color = { 255, 255, 255 }, damage = 15000, material = "Eternal" },
}

-- Weapon types change how the weapon orbits and hits. Skewer is the long, fast, weaker one.
Config.WeaponTypes = {
	{ name = "Sword", length = 5.0, spin = 5.5, dmgMult = 1.0, cooldown = 0.35 },
	{ name = "Axe", length = 4.4, spin = 4.2, dmgMult = 1.3, cooldown = 0.45 },
	{ name = "Mace", length = 4.0, spin = 3.4, dmgMult = 1.6, cooldown = 0.55 },
	{ name = "Skewer", length = 6.5, spin = 4.8, dmgMult = 0.85, cooldown = 0.3 },
}

-- Zones are arena upgrades on your own plot. `power` is the requirement to enter.
Config.Zones = {
	{
		name = "Meadow",
		power = 0,
		enemyHp = { 25, 50 },
		enemyDmg = 3,
		maxEnemies = 4,
		killsPerKey = 2,
		bossEvery = 10,
		bossHp = 700,
		bossDmg = 5,
		canDie = false, -- nobody dies in the first zone
		floor = { 120, 180, 95 },
	},
	{
		name = "Ember Pit",
		power = 400,
		enemyHp = { 450, 1000 },
		enemyDmg = 16,
		maxEnemies = 5,
		killsPerKey = 2,
		bossEvery = 14,
		bossHp = 9000,
		bossDmg = 25,
		canDie = true,
		floor = { 170, 95, 65 },
	},
	{
		name = "Frost Vault",
		power = 2500,
		enemyHp = { 3500, 8000 },
		enemyDmg = 60,
		maxEnemies = 6,
		killsPerKey = 2,
		bossEvery = 14,
		bossHp = 80000,
		bossDmg = 120,
		canDie = true,
		floor = { 150, 195, 230 },
	},
}

Config.Ball = {
	radius = 2.2,
	speed = 20,
	hp = 100,
	regen = 4, -- hp per second
	homing = 14, -- steering toward nearest enemy
	dashSpeed = 60,
	dashTime = 0.35,
	dashCooldown = 3,
	dashUnlockRolls = 2, -- dash unlocks after this many chest rolls
	respawn = 3,
}

Config.Enemy = {
	radius = 1.8,
	speed = 14,
	homing = 9,
	spawnInterval = 1.0,
	weaponScale = 0.85,
	spinScale = 0.8,
}

Config.Boss = {
	radius = 3.6,
	speed = 10,
	weaponType = 3,
	weaponScale = 1.7,
	spin = 2.2,
	keys = 3,
}

Config.Knockback = 26

Config.Arena = {
	half = 24, -- inner half-width in studs
	wallHeight = 2.5,
	wallThickness = 1.2,
	floorY = 1.2, -- top surface of every arena floor
}

Config.Plot = {
	count = 8,
	ringRadius = 110,
	size = 72,
}

Config.Rolls = {
	baseLuck = 1,
	friendLuck = 0.1, -- extra luck per friend in the server
	friendLuckCap = 0.5,
	pityAt = 80, -- guaranteed Epic+ after this many rolls without one
	pityTier = 4,
	-- Scripted minimum tier for early rolls so the first minutes always feel good.
	scripted = { [1] = 2, [3] = 3, [6] = 4 },
	announceTier = 4, -- Epic and above are announced to the server
	minInterval = 0.25,
}

Config.Upgrade = {
	costPerLevel = 6, -- dust cost = level * costPerLevel * tier
	bonusPerLevel = 0.1, -- +10% damage per level
}

Config.Net = {
	snapshotRate = 20,
}

Config.Data = {
	storeName = "BallGame_v1",
	autosave = 90,
}

function Config.plotCenter(index: number): (number, number)
	local angle = (index - 1) / Config.Plot.count * math.pi * 2
	return math.cos(angle) * Config.Plot.ringRadius, math.sin(angle) * Config.Plot.ringRadius
end

-- Weapon length for an entity kind (1 player, 2 enemy, 3 boss).
function Config.weaponLength(kind: number, wtype: number): number
	local base = Config.WeaponTypes[wtype].length
	if kind == 2 then
		return base * Config.Enemy.weaponScale
	elseif kind == 3 then
		return base * Config.Boss.weaponScale
	end
	return base
end

function Config.formatNumber(n: number): string
	if n >= 1e9 then
		return string.format("%.2fb", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fm", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

return Config
