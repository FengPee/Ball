# Weapon Balls (working title)

A Roblox game prototype: your ball fights by itself in a walled arena on your plot,
kills drop keys, keys open a chest that rolls weapons on a 9-tier rarity ladder.

## Play it in Roblox Studio

**Quickest:** download `build/WeaponBalls.rbxlx`, open it in Roblox Studio and press **Play**.
The map, plots and arenas are built by the server script when the game starts, so the
edit view looks empty until you press Play.

To test with several players: Studio > **Test** tab > Clients and Servers > 2-4 players > Start.

**For development (live sync):** install [Rojo](https://rojo.space) and its Studio plugin, run
`rojo serve` in this folder, then click Connect in the plugin. Edits to `src/` appear in Studio
instantly. Rebuild the place file with `rojo build -o build/WeaponBalls.rbxlx`.

**Saving progress:** saving only works in a published place with Game Settings > Security >
"Enable Studio Access to API Services" turned on. Without it the game still runs; progress
just resets each session.

## Controls

| Action | Key | Button |
|---|---|---|
| Open chest | E | OPEN CHEST |
| Dash at nearest enemy (unlocks after 2 rolls) | F | DASH |
| Arena camera / free camera | C | CAMERA |

## What's in this version

- 8 plots in a ring around a central plaza, each with a walled arena and a chest
- Server-run 2D ball physics (bounces, knockback, orbiting weapons that flip spin on hit)
- 4 weapon types (Sword, Axe, Mace, Skewer), 9 rarity tiers shown as "1 in X"
- Chest rolls with luck, a pity counter and scripted first rolls (Uncommon, Rare, then Epic)
- Equip / salvage popup, dust, weapon upgrades
- 3 zones gated by power; zone 1 can't kill you; bosses every 10-14 kills for 3 keys
- Server-wide announcements and a light beam for Epic+ rolls, +10% luck per friend in the server
- Best-drop bar, leaderboard (Power, Best), DataStore saving

## Not built yet

World boss in the plaza, daily rewards and streaks, offline keys, rebirth, trading, PvP duels,
game passes, analytics. All numbers to tune live in `src/shared/Config.luau`.

## Layout

```
src/shared/   Config, Rolls, Sim (arena physics), Codec (network packing): pure Luau, tested
src/server/   Main (game loop, remotes), World (map builder), PlayerData (saving)
src/client/   Main (input, camera), Render (draws arenas), Effects, Ui
tests/run.luau  Offline tests: roll odds, pity, packing, simulated pacing
```
