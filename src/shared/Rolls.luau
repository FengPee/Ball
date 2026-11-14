-- Chest rolls, items and upgrade maths. Pure logic so it can be tested outside Roblox.
-- Always run rolls on the server: the client only ever sees the result.
local Config = require(script.Parent.Config)

local Rolls = {}

export type Item = { tier: number, wtype: number, damage: number, level: number }

-- Picks a tier. Checks from rarest down, so each tier really is "1 in oneIn / luck".
function Rolls.rollTier(rng: () -> number, luck: number, minTier: number?): number
	local floor = minTier or 1
	for i = #Config.Tiers, 2, -1 do
		if rng() < luck / Config.Tiers[i].oneIn then
			return math.max(i, floor)
		end
	end
	return math.max(1, floor)
end

function Rolls.makeItem(rng: () -> number, tier: number): Item
	local wtype = math.floor(rng() * #Config.WeaponTypes) + 1
	local spread = 0.85 + rng() * 0.3
	local damage = Config.Tiers[tier].damage * Config.WeaponTypes[wtype].dmgMult * spread
	return { tier = tier, wtype = wtype, damage = math.floor(damage + 0.5), level = 1 }
end

-- Rolls one item for a player's save data, applying scripted early rolls and pity.
-- Mutates data.rolls and data.pity.
function Rolls.roll(data, luck: number, rng: () -> number): Item
	data.rolls += 1
	local minTier = Config.Rolls.scripted[data.rolls] or 1
	if data.pity + 1 >= Config.Rolls.pityAt then
		minTier = math.max(minTier, Config.Rolls.pityTier)
	end
	local tier = Rolls.rollTier(rng, luck, minTier)
	if tier >= Config.Rolls.pityTier then
		data.pity = 0
	else
		data.pity += 1
	end
	return Rolls.makeItem(rng, tier)
end

function Rolls.power(item: Item): number
	return math.floor(item.damage * (1 + Config.Upgrade.bonusPerLevel * (item.level - 1)) + 0.5)
end

function Rolls.itemName(item: Item): string
	return Config.Tiers[item.tier].material .. " " .. Config.WeaponTypes[item.wtype].name
end

function Rolls.salvageValue(item: Item): number
	return item.tier * item.tier * 2 + (item.level - 1) * 2
end

function Rolls.upgradeCost(item: Item): number
	return item.level * Config.Upgrade.costPerLevel * item.tier
end

function Rolls.starterItem(): Item
	return { tier = 1, wtype = 1, damage = Config.Tiers[1].damage, level = 1 }
end

return Rolls
