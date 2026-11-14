-- Offline tests for the pure game logic. Run from the repo root with a Luau runner:
--   luaurun tests/run.luau
-- Modules use `require(script.Parent.X)`, so fake `script` to point at src/shared.
script = { Parent = setmetatable({}, { __index = function(_, k) return "src/shared/" .. k end }) }

local Config = require("src/shared/Config")
local Rolls = require("src/shared/Rolls")
local Sim = require("src/shared/Sim")
local Codec = require("src/shared/Codec")

local failures = 0
local function check(cond, msg)
	if cond then
		print("  ok   " .. msg)
	else
		failures += 1
		print("  FAIL " .. msg)
	end
end

-- Seeded RNG so results are repeatable.
local function makeRng(seed)
	local r = Random and Random.new(seed)
	if r then
		return function()
			return r:NextNumber()
		end
	end
	math.randomseed(seed)
	return math.random
end

print("Roll odds (1,000,000 rolls, luck 1)")
do
	local rng = makeRng(42)
	local counts = {}
	local N = 1000000
	for _ = 1, N do
		local t = Rolls.rollTier(rng, 1)
		counts[t] = (counts[t] or 0) + 1
	end
	for i = 2, 5 do
		local expected = N / Config.Tiers[i].oneIn
		local got = counts[i] or 0
		print(string.format("    %-10s expected ~%7.0f got %7d", Config.Tiers[i].name, expected, got))
		check(math.abs(got - expected) / expected < 0.25, Config.Tiers[i].name .. " within 25% of 1 in " .. Config.Tiers[i].oneIn)
	end
	local luck2 = 0
	for _ = 1, N do
		if Rolls.rollTier(rng, 2) == 4 then
			luck2 += 1
		end
	end
	check(luck2 > (counts[4] or 0) * 1.6, "luck x2 roughly doubles Epic rate")
end

print("Scripted early rolls and pity")
do
	local rng = function() return 0.999 end -- worst luck possible: always Common
	local data = { rolls = 0, pity = 0 }
	local tiers = {}
	for i = 1, 6 do
		tiers[i] = Rolls.roll(data, 1, rng).tier
	end
	check(tiers[1] == 2, "roll 1 is Uncommon")
	check(tiers[2] == 1, "roll 2 can be Common")
	check(tiers[3] == 3, "roll 3 is Rare")
	check(tiers[6] == 4, "roll 6 is Epic")
	local pityHit = nil
	for i = 7, 200 do
		if Rolls.roll(data, 1, rng).tier >= 4 then
			pityHit = i
			break
		end
	end
	check(pityHit ~= nil and pityHit - 6 == Config.Rolls.pityAt, "pity guarantees Epic after " .. Config.Rolls.pityAt .. " dry rolls (got " .. tostring(pityHit and pityHit - 6) .. ")")
end

print("Items")
do
	local item = Rolls.makeItem(makeRng(7), 4)
	check(item.tier == 4 and item.level == 1, "item has tier and level")
	local before = Rolls.power(item)
	item.level = 3
	check(Rolls.power(item) > before, "upgrading raises power")
	check(Rolls.itemName({ tier = 1, wtype = 4, damage = 1, level = 1 }) == "Wooden Skewer", "names read well")
end

print("Snapshot codec")
do
	local ents = {
		{ id = 7, kind = 1, tier = 3, wtype = 2, r = 2.2, x = 110.5, z = -3.25, angle = 1.5, hp = 87.5, maxHp = 100 },
		{ id = 65000, kind = 3, tier = 0, wtype = 3, r = 3.6, x = -90, z = 40, angle = 6.1, hp = -5, maxHp = 9000 },
	}
	local b = Codec.encode(5, 65535, ents)
	check(buffer.len(b) < 900, "snapshot fits in an unreliable event (" .. buffer.len(b) .. " bytes)")
	local plot, seq, list = Codec.decode(b)
	check(plot == 5 and seq == 65535 and #list == 2, "header round-trips")
	check(list[1].id == 7 and math.abs(list[1].x - 110.5) < 1e-4 and math.abs(list[1].r - 2.2) < 1e-6, "entity fields round-trip")
	check(list[2].hp == 0, "negative hp clamps to 0")
	check(Codec.isNewer(0, 65535) and not Codec.isNewer(65535, 0), "sequence wrap-around")
	local full = {}
	for i = 1, 8 do
		full[i] = ents[1]
	end
	check(buffer.len(Codec.encode(1, 1, full)) < 900, "8-entity arena fits")
end

-- Runs one arena for `seconds` and reports pacing.
local function simulate(zoneIndex, item, seconds, seed)
	local arena = Sim.new(100, 50, makeRng(seed))
	arena:setLoadout({ damage = Rolls.power(item), wtype = item.wtype, tier = item.tier })
	arena:setZone(zoneIndex)
	local dt = 1 / 60
	local kills, bosses, downs, firstKill, hits = 0, 0, 0, nil, 0
	local outOfBounds = false
	local half = Config.Arena.half
	for step = 1, math.floor(seconds / dt) do
		for _, ev in arena:step(dt) do
			if ev.type == "kill" then
				kills += 1
				if ev.kind == 3 then
					bosses += 1
				end
				firstKill = firstKill or step * dt
			elseif ev.type == "down" then
				downs += 1
			elseif ev.type == "hit" then
				hits += 1
			end
		end
		for _, e in arena:entities() do
			if math.abs(e.x - 100) > half + 0.01 or math.abs(e.z - 50) > half + 0.01 or e.x ~= e.x then
				outOfBounds = true
			end
		end
	end
	return { kills = kills, bosses = bosses, downs = downs, firstKill = firstKill, hits = hits, oob = outOfBounds }
end

print("Pacing (simulated)")
do
	local zone1 = Config.Zones[1]
	local starter = Rolls.starterItem()
	local runs, kills, worstFirst, oob = 5, 0, 0, false
	for seed = 1, runs do
		local r = simulate(1, starter, 60, seed)
		kills += r.kills
		worstFirst = math.max(worstFirst, r.firstKill or 999)
		oob = oob or r.oob
	end
	kills /= runs
	print(string.format("    Zone 1, starter sword, 60s (avg of %d): %.1f kills, slowest first kill %.1fs", runs, kills, worstFirst))
	check(worstFirst < 20, "first kill (= first key) inside 20 seconds in every run")
	check(not oob, "balls stay inside the arena")
	local keysPerMin = 1 + (kills - 1) / zone1.killsPerKey
	print(string.format("    ~%.1f keys in the first minute", keysPerMin))
	check(keysPerMin >= 3 and keysPerMin <= 10, "3-10 keys in the first minute")

	local rare = { tier = 3, wtype = 1, damage = Config.Tiers[3].damage, level = 1 }
	local r2 = simulate(1, rare, 120, 2)
	print(string.format("    Zone 1, Rare sword, 120s: %d kills, %d bosses", r2.kills, r2.bosses))
	check(r2.bosses >= 1, "a boss appears and dies within 2 minutes on a Rare")
	check(r2.downs == 0, "nobody dies in zone 1")

	local epic = { tier = 4, wtype = 2, damage = 420, level = 1 }
	local r3 = simulate(2, epic, 120, 3)
	print(string.format("    Zone 2, ~420 power, 120s: %d kills, %d deaths", r3.kills, r3.downs))
	check(r3.kills >= 5, "zone 2 is beatable at its entry power")

	local weak = { tier = 1, wtype = 1, damage = 18, level = 1 }
	local r4 = simulate(2, weak, 60, 4)
	print(string.format("    Zone 2, starter sword, 60s: %d kills, %d deaths", r4.kills, r4.downs))
	check(r4.kills <= 1, "zone 2 is a wall for starter gear")
end

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURE(S)"))
if failures > 0 then
	error("tests failed")
end
