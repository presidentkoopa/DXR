# 02 — Classes & loadout

## The key correction

A **class is not a character** — it's a **dual-weapon fighting style**. You don't pick
"the gunslinger guy"; you pick *dual revolvers* and that pairing is your specialization,
your loot chase, and your gunfighting dialect. Crucially:

- **The melee/traversal art is universal.** Every marine can use fists, whip, sword,
  shieldsaw, and ice hooks. These are not class weapons — they're the shared VR toolkit
  (mostly *bought with gold*, see [07](07_economy-shop.md)).
- **The class is only the ranged pair** — the two guns you specialize, loot frames for,
  and level via imprints ([08](08_encounter-spikes.md)).
- **You still play Doom.** Rockets, plasma, BFG, chainsaw, flamethrower drop as normal
  pickups for everyone. (Optionally gate the *empowered* version of a big gun behind a
  gesture — the gun is free, the mastery costs a move — but that's a design fork, see
  [10](10_open-questions.md).)

## The spawn kit (everyone)

- **Two fists** (the IQM first-person marine hands — real IK arms).
- **Two ice hooks** (climb / grapple traversal).
- **Whip** (grapple, swing, yank, crack).
- **Shieldsaw** (melee + block).
- **Sword** (slice, parry, throwable boomerang).
- **Two class frames** — your dual signature pair, each rolled at the loot floor (Basic).

> Whether the universal art (whip/sword/shieldsaw/ice hooks) is *spawned* or *bought
> with gold* is an economy decision — see [07](07_economy-shop.md). The lean version:
> spawn with fists + class frames, buy the rest.

> **Where it all physically lives** (guns cycle, tools holster, abilities slot to the
> wrist, shieldsaw is a gesture) is the full **[12 — hardpoint & loadout map](12_hardpoint-map.md)**.
> Guns notably do **not** holster — a class is ~3 frames on next/prev cycle.

## Vanilla+ (the default class)

The classic reliable set: full arsenal across all slots, **modified by cvars** — e.g. a
rifle-start toggle swaps the starting pistol for a rifle, a grenades toggle removes the
starting hand grenade, a chance-cvar can swap the chainsaw for a flamethrower at spawn.
Vanilla+ is the "just play Doom" baseline; the dual classes are the specializations.

## The dual-weapon classes

Each dual class carries **only its signature ranged pair** (plus the shared melee kit).
Slots 2/3/4 hold that weapon's **six frames** (base pair + four loot variants) — you
don't get a different gun, you get *better versions of your gun*. Candidate roster, each
chosen because it plays **physically different in VR**, not just stat-different:

| Class | VR hand-motion identity | Class-art gestures (bought) |
|---|---|---|
| **Dual Pistol** | fast, spray, akimbo | akimbo draw, cross-draw dual-wield |
| **Dual Revolver** | fan, cylinder-flick reload | Gunslinger Twirl, Cylinder Flick Reload, Called Shot |
| **Dual SMG** | suppressive spray | akimbo draw, jam-clear rack |
| **Dual Shotgun** | pump-rack rhythm | Shell-Ejector Showboat, Boot Shove Kill |
| **Dual Super Shotgun** | break-action reload (crack, load two, snap) | the reload *is* the gesture — highest-skill in VR |
| **Dual Rifle** | precise semi-auto cadence | Chamber Peek, ADS Focus, Called Shot |
| **Dual Chaingun / Minigun** | spin-up, hold the line | spin-up hold, over-the-shoulder draw |
| **Dual Plasma** | heat / vent management | vent gesture, ADS focus |

**BFG:** treat as a **universal power weapon**, not a class — everyone's "big moment"
gun, unlocked in feel by the overhead charge-ritual gesture.

## The frame → imprint loot loop (per class)

Your class pair levels through loot, not a skill tree:

1. You start with **two Basic frames** (white-tier signature guns) — the loot floor.
2. While you hold fewer than the full **six frames**, elites drop the next frame as a
   junk-floor roll (Cursed / Trash / Basic) you collect.
3. Once you hold **all six frames**, "the real rolls begin" — elites drop **imprints**
   you physically stamp onto a held frame (hold-USE near the drop; grip modifier targets
   the offhand frame). Imprints **accrue** — stats compound, sockets pile up, the
   headline rarity rises. A frame only loses its build by breaking or being discarded.
4. **8 rarity tiers:** Cursed / Trash / Basic (junk floor) → Common / Uncommon /
   Advanced / Designer / Prototype (the real climb, each granting more upgrade sockets).
   Cursed rolls **lock** rolled stats (curses); curse-coins and curse-tokens lift them;
   lifting the last curse flips a frame **divine**.

The point: you don't chase a *bigger* gun, you chase a *better version of your one pair*.
That's what "specialize in dual weapons and level them up" means mechanically.

See [08 — encounter spikes](08_encounter-spikes.md) for how elites/captains feed this.
