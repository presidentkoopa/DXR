# 12 — The hardpoint & loadout map

The physical spec: what lives where on the body, what you draw vs. cast vs. cycle. This is
the **re-seed target** for the native hardpoint table ([09](09_engine-seams.md)).

## The core split

- **Guns don't holster.** A class is ~3 frames of one gun → **next/prev weapon cycle**
  (or the watch-wheel). No shoulder/hip gun slots at all.
- **Body slots are for tools and abilities**, never guns.

## The map

### Wrist ability slots — 6, mirrored

| Hand | Slots | Reached by |
|---|---|---|
| Main hand | above · below · **outer** side | offhand taps it (`hand=1`) |
| Offhand | above · below · **outer** side (opposite) | main hand taps it (`hand=0`) |

The "side" slot faces **outward** on each hand, which is why the offhand's is the
"opposite" side — true mirror images. These are **buyable, assignable equip-slots** for
abilities (grav panels, jump-jets, + TBD). A wrist-tap fires whatever's assigned.

**This is the shop's loadout layer** ([07](07_economy-shop.md)): the gold shop sells a
pool of abilities; the player assigns three-per-hand into the wrist slots and swaps the
loadout. `VR_HardpointAbility(hand, slot)` dispatches the assigned ability.

### Utility holsters — 4

2 hips + 2 shoulders. Generic **drawn-tool** slots — hold the whip, sword, ice picks.
Assignable (any tool in any slot). These are the four already seeded in the code, just
re-labeled from "gun holster" to "utility."

### Chest — ammo pouch

The existing reload keystone (reach-and-grab → the manual-reload FSM).

### Belt — quick grenade slot (new)

Waist **front-center** — pluck a grenade off your belt, primed on pull. Front-center so
the reach can't be confused with the chest pouch (above it) or the hip holsters (to the
sides). *Alt:* a chest bandolier diagonal strap — more "Rambo," but tighter radii since
it's near the pouch. Recommendation: belt.

## The shieldsaw — a gesture, not a slot

The shieldsaw isn't holstered or forearm-mounted — it's a **gesture-summoned two-tier
block ability:**

| Tier | Activation | Effect | Throw |
|---|---|---|---|
| **1 — light** | single (offhand) arm **raised**, outer forearm toward threat | one-side buckler; **other hand keeps shooting** | single-arm forward fling (Cap toss) |
| **2 — full** | **both** forearms crossed in an **X** in front of the face | full frontal deflect | fling arms **apart** (outward velocity spike) |

- **Deflect** splits by shot type: **projectiles** reflect back (a parry — ties to
  True-Bullet mode, [05](05_crits-locational.md)); **hitscan** only blocks (nothing to
  bounce).
- **Thrown = exposed** — no guard until it boomerangs back (reuse the sword return).
- **Net-clean:** pose enables the deflect, the velocity spike triggers the throw.
- **Passes hands-full:** you can X-block with a gun in each hand; the single-arm tier is
  literally fire-while-blocking.
- Optionally the throw **vector** aims it (spread up-left → flies up-left).

## Coexistence on the offhand forearm

Three gestures share the offhand forearm and don't collide — distinguished by
**raised-vs-lowered + which face points where:**

| Gesture | Pose |
|---|---|
| Watch-wheel (planned) | arm **lowered/relaxed**, inner wrist rotated **toward your eyes**, dwell |
| Single buckler | arm **raised**, outer forearm **toward the threat** |
| Two-hand X | **both** forearms raised + crossed |

Lowered-and-looking vs. raised-and-guarding is night-and-day to detect. No discriminator
hack needed.

## Full count

- **6** wrist ability slots (3/hand, mirrored) — buyable/assignable abilities
- **4** utility holsters (hip ×2, shoulder ×2) — drawn tools (ice picks, whip, sword)
- **1** chest ammo pouch (reload)
- **1** belt grenade slot (new)
- shieldsaw = a gesture (no slot)
- guns = next/prev cycle (no slot)

## Re-seed delta vs. current code

The native table today ([`vr_config.cpp`](../../src/playsim/vr_config.cpp), if reading in
the engine tree) seeds `rShoulder`/`lShoulder` + `rHip`/`lHip` + the **offhand** wrist trio
+ the chest pouch. To hit this spec:

- **Add** the 3 **main-hand** wrist slots (`hand=1`).
- **Add** the belt grenade slot.
- **Keep** the 4 body holsters — re-label them "utility."
- **Already exist:** offhand wrist trio, chest pouch.
- **No slot needed:** shieldsaw (gesture), guns (cycle).

Do the re-seed **before** building the gesture engine on top, or it inherits the wrong
anchors. Ship it either as changed native defaults or as the default `vr_hardpoints.json`.

## Open calls

- Grenade: **belt** (rec) vs. bandolier.
- Deflect: reflect projectiles vs. block-only, and whether hitscan gets any mitigation.
- Whether the shieldsaw is a **shop purchase** (an ability you buy) or a core universal.
