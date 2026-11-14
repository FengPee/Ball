# Build brief: Weapon Balls (Roblox)

You are building a Roblox game from this brief. It is self-contained: everything you need is here.
A working reference implementation exists in the GitHub repo `fengpee/ball`, branch
`claude/cool-hypatia-lcx6ws` (folders `src/shared`, `src/server`, `src/client`). If you can read
it, use it; if not, build from this document.

## 1. The game in one paragraph

Each player owns a plot with a walled arena on it, like a Beyblade stadium. Their ball bounces
around the arena by itself with a weapon orbiting it, fighting red enemy balls. Kills drop keys.
Keys open a chest that rolls a weapon on a 9-tier rarity ladder shown as "1 in X". Better weapons
mean more damage, which unlocks harder zones. Rare rolls are announced to the whole server.
Genre: RNG/loot progression plus auto-battler, with co-op and social features layered on later.

## 2. Hard rules

- **Server-authoritative.** The server runs all combat maths and all rolls. Clients only send
  requests (roll, equip, salvage, dash, change zone, upgrade) and draw what the server tells them.
  Validate every remote argument and rate-limit rolls.
- **Combat is 2D logic, 3D visuals.** Balls move only on X/Z inside a rectangle. Do not use
  Roblox physics for combat; simulate with plain numbers on the server.
- **World is 3D.** Players walk around as avatars. The arena is a physical walled pit on the plot.
- **Original assets only.** Do not copy names, art or tier lists from any existing game.
- **Never sell random items for Robux.** Sell boosts (luck, key multipliers, auto-roll) instead.
- **Luau**, `--!strict` optional. Keep all tunable numbers in one shared `Config` module.

## 3. Architecture

```
ReplicatedStorage/Shared   (ModuleScripts, pure Luau, no Roblox APIs except `buffer`)
  Config   all numbers, tier list, weapon types, zones, helper functions
  Rolls    tier rolling, item creation, power, names, salvage, upgrade cost
  Sim      one arena's simulation (one instance per player)
  Codec    packs/unpacks arena snapshots into a buffer
ServerScriptService/Server
  Main (Script)   remotes, sessions, game loop, roll/action handlers, saving loop
  World           builds the map in code
  PlayerData      DataStore load/save with defaults and reconcile
StarterPlayer/StarterPlayerScripts/Client
  Main (LocalScript)  wires remotes, input, camera
  Render   draws all arenas from snapshots with smoothing and hit effects
  Effects  damage numbers, sparks, shatter, beam, chest pop, camera shake
  Ui       HUD, best-drop bar, roll animation, equip/salvage popup
```

Remotes (created by the server in `ReplicatedStorage.Remotes`):

| Name | Type | Direction | Payload |
|---|---|---|---|
| Snapshot | UnreliableRemoteEvent | server → all clients | buffer (see §7), one per arena, 20 Hz |
| Fx | RemoteEvent | server → clients | `{t="kill"|"boss"|"down"|"clear"|"toast"|"announce", ...}` |
| State | RemoteEvent | server → one client | that player's keys, dust, power, zone, found tiers, etc. |
| Roll | RemoteFunction | client → server | returns roll result table |
| Action | RemoteEvent | client → server | `"equip"`, `"salvage"`, `"dash"`, `"upgrade"`, `"zone", ±1` |

## 4. Config values (starting numbers; tune in playtests)

**Tiers** (name, oneIn, RGB colour, base damage, material word used in item names):

| # | Name | 1 in | Colour | Damage | Material |
|---|---|---|---|---|---|
| 1 | Common | 1 | 200,200,205 | 18 | Wooden |
| 2 | Uncommon | 4 | 110,220,110 | 45 | Bronze |
| 3 | Rare | 15 | 90,190,255 | 110 | Steel |
| 4 | Epic | 60 | 170,90,255 | 240 | Amethyst |
| 5 | Legendary | 300 | 255,170,50 | 520 | Golden |
| 6 | Mythic | 2,000 | 255,70,110 | 1,150 | Crimson |
| 7 | Celestial | 12,000 | 120,255,230 | 2,600 | Starforged |
| 8 | Cosmic | 80,000 | 80,60,230 | 6,000 | Void |
| 9 | Eternal | 500,000 | 255,255,255 | 15,000 | Eternal |

**Weapon types** (length in studs, spin in rad/s, damage multiplier, per-target hit cooldown s):
Sword 5.0 / 5.5 / 1.0 / 0.35 · Axe 4.4 / 4.2 / 1.3 / 0.45 · Mace 4.0 / 3.4 / 1.6 / 0.55 ·
Skewer 6.5 / 4.8 / 0.85 / 0.30 (a stick with food chunks on it).

**Zones:**

| Zone | Power to enter | Enemy HP | Enemy dmg | Max enemies | Kills per key | Boss every | Boss HP | Boss dmg | Can die | Floor RGB |
|---|---|---|---|---|---|---|---|---|---|---|
| Meadow | 0 | 25-50 | 3 | 4 | 2 | 10 kills | 700 | 5 | no | 120,180,95 |
| Ember Pit | 400 | 450-1000 | 16 | 5 | 2 | 14 | 9,000 | 25 | yes | 170,95,65 |
| Frost Vault | 2,500 | 3,500-8,000 | 60 | 6 | 2 | 14 | 80,000 | 120 | yes | 150,195,230 |

**Player ball:** radius 2.2, speed 20, HP 100, regen 4/s, homing 14, dash speed 60 for 0.35 s,
dash cooldown 3 s, dash unlocks after 2 rolls, respawn 3 s.
**Enemy:** radius 1.8, speed 14, homing 9, spawn every 1.0 s up to max, weapon length ×0.85,
spin ×0.8, weapon type random among Sword/Axe/Mace.
**Boss:** radius 3.6, speed 10, Mace, weapon length ×1.7, spin 2.2, takes 35% knockback, drops 3 keys.
**Knockback:** 26. **Arena:** inner half-width 24, wall height 2.5, wall thickness 1.2, floor top Y 1.2.
**Plots:** 8 in a ring of radius 110 around the origin, each 72×72. Plot i centre angle =
(i−1)/8 × 2π.
**Rolls:** base luck 1, +0.1 luck per friend in server (cap +0.5), pity: guaranteed Epic+ after 80
rolls without one, scripted minimum tier for roll #1 = Uncommon, #3 = Rare, #6 = Epic,
announce Epic+, minimum 0.25 s between rolls.
**Upgrade:** cost = level × 6 × tier dust, +10% damage per level.
**Network:** 20 snapshots/s. **Saving:** autosave every 90 s.

## 5. Rolls (Rolls module)

- `rollTier(rng, luck, minTier)`: for i = 9 down to 2, if `rng() < luck / oneIn[i]` return
  `max(i, minTier)`; otherwise return `max(1, minTier)`. This makes "1 in X" literally true.
- `roll(data, luck, rng)`: `data.rolls += 1`; minTier = scripted[data.rolls] or 1; if
  `data.pity + 1 >= 80` raise minTier to 4. Roll. If tier ≥ 4 reset pity, else pity += 1.
  Make item.
- Item = `{tier, wtype, damage, level=1}`, wtype random 1-4,
  damage = round(tierDamage × typeMult × random(0.85..1.15)).
- `power(item)` = round(damage × (1 + 0.1 × (level − 1))).
- `itemName` = material + " " + weapon type, e.g. "Wooden Skewer".
- `salvageValue` = tier² × 2 + (level − 1) × 2.
- Starter item: Common Sword, 18 damage.

## 6. Arena simulation (Sim module)

One `Sim.new(cx, cz, rng)` per player. Entities are tables:
`{id, kind (1 player, 2 enemy, 3 boss), x, z, vx, vz, r, speed, hp, maxHp, dmg, wtype, tier
(0 for enemies), length, spin, spinDir (±1), angle, cooldown, hitCd = {[targetId]=time}, alive}`.
Ids are 1-65000, wrapping.

`setLoadout({damage, wtype, tier})` creates the player ball at the arena centre on first call,
otherwise updates it. `setZone(z)` clears enemies, resets boss counters, heals the player.

`step(dt)` each server Heartbeat (clamp dt to 0.05), returning a list of events:
1. Respawn the player if dead and its timer passed; regen HP.
2. Spawn timer: every 1 s, spawn a boss if kills since last boss ≥ bossEvery and none alive
   (emit `boss` event), else spawn an enemy if below max. Spawn ≥10 studs from the player.
3. Movement for each live ball: steer toward its target (player → nearest enemy, enemy → player)
   by homing × dt; ease speed toward its base speed (or dash speed while dashing) with factor
   `min(1, dt × 2.5)`; move; reflect off the four walls; advance `angle += spin × spinDir × dt`.
4. Ball-ball collisions: push overlapping pairs apart equally and exchange velocity along the
   contact normal (equal-mass elastic) if approaching.
5. Weapon hits: the weapon is the segment from `r × 0.6` to `r + length` along `angle` from the
   ball centre. If the target's centre is within the target's radius of that segment and the
   per-target cooldown passed: subtract damage, knock the target away from the attacker,
   **flip the attacker's spinDir** (this is what makes fights look lively), emit `hit`.
   Check player → each enemy and each enemy → player.
6. Deaths: remove dead enemies, emit `kill {kind, x, z, r}`, count toward boss. If the player
   hits 0 HP: in zones that can kill, mark dead for 3 s and emit `down`; otherwise set HP to 1.

`dash()`: if alive and off cooldown, set velocity toward the nearest enemy at dash speed.
`entities()`: list of live balls for snapshots.

## 7. Snapshot packing (Codec)

UnreliableRemoteEvents are capped around 1,000 bytes, so pack each arena into a buffer:
header 4 bytes (plot u8, count u8, seq u16), then 26 bytes per entity:
id u16, kind u8, tier u8, wtype u8, radius×10 u8, x f32, z f32, angle f32, hp f32 (clamped ≥0),
maxHp f32. Clients drop packets whose seq is not newer than the last one for that plot
(handle wrap-around at 65,536).

## 8. Server Main

- Build the world, create remotes, then handle `PlayerAdded` (also loop existing players).
- On join: claim the first free plot (kick if full), load data, create the Sim at the plot centre,
  create `leaderstats` with Power (IntValue) and Best (StringValue), set zone and loadout,
  teleport the character to the plot spawn on every `CharacterAdded`, push State, recompute
  friend luck (`IsFriendsWith` in pcall, cached).
- Kill events: data.kills += 1. Boss gives 3 keys. Otherwise key progress += 1 and award a key at
  killsPerKey, **always award a key on the player's very first kill**. Broadcast `Fx kill`
  with keys awarded; push State when keys change.
- Roll handler: check session, rate limit, keys ≥ 1; auto-salvage any unclaimed previous roll;
  spend a key; roll; store as `pending`; mark tier found and update best; return
  `{ok, tier, wtype, name, power, oneIn, salvage, currentName, currentTier, currentPower, newBest}`.
  For Epic+ broadcast `Fx announce {plot, name, tier, item, oneIn}` after 2.2 s so it lands
  after the client's roll animation.
- Actions: `equip` swaps pending in and salvages the old weapon into dust; `salvage` turns
  pending into dust; `dash` only if unlocked; `zone ±1` rate-limited to 1/s and power-gated,
  clears the arena and tells clients to `clear` that plot; `upgrade` spends dust.
- Snapshots: every 1/20 s, fire one encoded buffer per arena to all clients.
- On leave: salvage pending, save, free the plot, reset its sign and floor, broadcast `clear`.
- Autosave every 90 s; `BindToClose` saves everyone (wait up to 25 s).

## 9. World (built in code on server start)

Grass ground 420×420 (top at Y 0); a round plaza of radius 32 at the centre with a sign
"WORLD BOSS ARENA – coming next update"; a hidden neutral SpawnLocation at the plaza. Per plot:
a concrete pad, an arena floor whose top is at Y 1.2 coloured by zone, four dark walls, a chest
(red body, red lid named `Lid`, gold trim and lock) placed between the arena and the plaza
facing the arena, a floating owner sign ("Name / Best: Epic", or "Empty plot"), and a spawn
point on the plaza side facing the arena.

## 10. Client

**Render:** for each snapshot, create or update a visual per entity (key = plot × 65536 + id).
- Ball: a Part with a sphere `SpecialMesh` (so it can squash; Ball-shaped parts must stay
  uniform). Green for the player with a white outline Highlight, red for enemies, dark red boss.
- A BillboardGui in studs (`UDim2.new(r*1.8, 0, r*1.1, 0)`, AlwaysOnTop) shows HP like "2.4k".
- Weapon: a Model of anchored, non-colliding parts built along +X from the ball centre with
  `WorldPivot = CFrame.identity`; Common uses Wood, Uncommon–Epic Metal, Legendary+ Neon in tier
  colour; enemies use grey Metal. Rebuild when tier/wtype changes.
- Every RenderStepped: smooth position and angle toward the latest snapshot with
  `alpha = 1 − exp(−dt × 16)` (shortest-path for angle). Pivot the weapon with
  `CFrame.new(x, floorY + r + hop, z) * CFrame.Angles(0, −angle, 0)`; note the minus sign.
- When HP drops: hop (sine over 0.3 s), squash the mesh, flash white, float a damage number
  (yellow and bigger if ≥25% of max HP), spark burst.
- Remove entities missing from a newer snapshot of their arena; `Fx clear` removes a whole arena.

**Effects:** floating text, neon chip bursts with Debris cleanup, shatter on kill, a tall neon
beam over the roller's chest for Epic+ (lasts 3 + tier seconds), chest lid pop on roll, camera
shake (big on boss kills and rare rolls).

**Camera:** after the first State arrives, switch to arena cam: Scriptable, eye at
`centre + toPlaza × 36 + (0, 50, 0)`, looking at the arena centre, plus shake. C toggles back
to the normal camera.

**UI** (ScreenGui, ResetOnSpawn false, FredokaOne font, rounded corners, black strokes,
buttons that squish when pressed; must work on phones):
- Top left: Power, Keys, Dust, Luck (with friend count).
- Top centre: "BEST DROP" bar of 9 slots, "?" until found, filled with tier colour, best outlined
  white. Below it: "Zone 1: Meadow | Wooden Sword Lv.1" in the weapon's tier colour.
- Bottom centre: big yellow OPEN CHEST (n) button (grey with 0 keys), with a hint above it:
  "Your ball fights on its own. Kills drop keys!" then "Open the chest! [E]" until the first roll.
- Bottom left: DASH [F] (shows LOCKED until unlocked, cooldown overlay). Bottom right:
  UPGRADE (cost dust).
- Right side: NEXT ZONE (shows "needs 400" when too weak), BACK (zone > 1), CAMERA [C].
- Toasts in the upper middle for boss spawned/defeated, knocked out, zone entered, errors.
- **Roll animation:** a panel listing all 9 tiers with their "1 in X". A highlight jumps between
  rows (only up to 3 tiers above the result), slowing down over 12 + 2 × min(tier, 6) steps; the
  second-to-last step teases the tier above; it lands on the result, the title becomes
  "EPIC!" in tier colour. After 0.7 s show the result popup.
- **Result popup:** tier title (+ "NEW BEST!"), "1 in X", two cards (EQUIPPED vs NEW with power
  and ▲/▼), EQUIP and SALVAGE +n buttons; the better choice is coloured green.
- Announcements: system chat message via `TextChatService.TextChannels.RBXSystem:
  DisplaySystemMessage` with rich-text colour, plus the beam; Mythic+ also toasts for others.
- Keys: E roll, F dash, C camera.

## 11. Saving (PlayerData)

DataStore key `p_<UserId>` in store `BallGame_v1`. Data:
`{v=1, keys, dust, rolls, pity, kills, zone, best, found = {bool × 9}, equipped = item}`.
Reconcile loaded data against defaults (wrong types fall back to defaults, invalid items to the
starter). Retry loads 3 times in live servers, once in Studio. If loading failed, **never save**
over the player's real data. In Studio, saving needs a published place with "Enable Studio Access
to API Services" on; the game must still run without it.

## 12. First five minutes (what the numbers above are tuned to produce)

| Time | Player experience |
|---|---|
| 0:00 | Spawns on their plot, camera already on their arena, ball fighting. No menus. |
| ~0:15 | First kill gives a key; the chest button pulses. |
| ~0:30 | First roll: guaranteed Uncommon, compare popup, one tap to equip. |
| 1:00-2:00 | Third roll guaranteed Rare; dash unlocks. |
| ~2:00 | First boss arrives, drops 3 keys; sixth roll guaranteed Epic and announced to the server. |
| 3:00-5:00 | Someone else's rare roll appears in chat with a beam; the next zone shows a power target slightly out of reach. |

Never let the player die or roll a downgrade without choice in zone 1, and show no shop popups
early.

## 13. Acceptance checks

Write offline tests for the pure modules (run in any Luau runtime) and confirm:
- Over 1,000,000 rolls at luck 1, Rare/Epic/Legendary land within 25% of 1-in-15/60/300;
  luck 2 roughly doubles Epic.
- With an always-Common RNG, rolls 1, 3 and 6 give Uncommon, Rare, Epic; pity triggers Epic on
  exactly the 80th dry roll.
- A packed 8-entity snapshot is under 900 bytes and round-trips exactly.
- Simulating zone 1 with the starter sword (average of 5 seeds, 60 s, dt 1/60): first kill within
  20 s every run, 3-10 keys in the first minute, balls never leave the arena.
- A Rare sword kills a boss within 2 minutes in zone 1 with no deaths; zone 2 is beatable at
  ~420 power and a wall for the starter sword.

Then in Studio: Play solo and with 2-4 local test players, check the Output window for errors,
check every button on a phone-sized emulator, and judge whether the fights look good.

## 14. Not in this version (build next, in this order)

1. World boss in the plaza every 15 minutes, all balls in the server fight it, rewards by damage.
2. Daily login streak chest, offline keys (cap 2 h), daily quests.
3. Rebirth for a permanent luck multiplier; index rewards per item found.
4. Game passes: 2× keys, auto-roll, permanent luck, server luck boosts.
5. Trading, then opt-in PvP duels with power brackets.
6. Analytics funnel for the first five minutes; targets: 85% roll once, 60% still playing at 5
   minutes, day-1 retention ≥15%, day-7 ≥4%, average session ≥12 minutes.
