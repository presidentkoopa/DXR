# DoomXR — Game Design

The design vision for DoomXR's roguelite-arcade layer: a VR looter-shooter built on
native GZDoom/DoomXR, where you still play *Doom* but every kill feeds a stack of
interlocking systems — score chains, gold economy, crits, a difficulty director, loot
imprints — and **90 physical VR gestures** are the skilled input that drives all of it.

> **Status:** design synthesis, 2026-07-04. This captures a working vision, not shipped
> code. Numbers are deliberately left as "the user's balance call" — this documents
> *structure*, not tuning. Some referenced systems exist today (SDF combo, kill-reward
> bits, crits, the native Hardpoint holster); others are proposed seams.

> **Provenance note:** several mechanics here were understood by studying prototype
> systems in a `notforclaude` reference tree. Those are **inspiration only** —
> this document describes DoomXR's *own* native design, not a port. Where a proven
> pattern exists, it's named as a pattern, not lifted.

## Vision at a glance (the whole thing, compressed)

- **You play Doom.** Guns are normal pickups; a class is ~3 frames of one gun you cycle
  and level via loot imprints. BFG/rockets/plasma/chainsaw drop like always.
- **Your hands are the game.** ~90 VR gestures — how you kill, reload, finish, block,
  traverse — are the skilled input. They feed four "brains": the **combo chain**, the
  **crit/locational** layer, the **difficulty director**, and the **gold economy**.
- **You buy your art.** Gestures aren't handed over — you spawn with fists + class frames
  and **buy tools and moves with gold**. The 90 is shop stock, not a manual; you only ever
  hold the handful you chose.
- **Gestures run on one engine.** A native C++ detector reads a declarative
  `vr_gestures.json`; ZScript does the effects; an HTML editor authors the JSON (later).
  Build the engine, not 90 gestures.
- **The body is the interface.** 6 wrist ability slots (buyable/assignable), 4 utility
  tool holsters, a chest reload pouch, a belt grenade, and a gesture-summoned shieldsaw.
- **Skill escalates the game.** Dominating summons the difficulty director's bullet-time
  set-pieces — the arena where your bought gestures pay off. Getting good makes the game
  *bigger*, not emptier.
- **The map is a spatial roguelite.** Reconfigurable holodeck-style cube rooms (rotating,
  gravity-flipping) wired into a portal lattice — 8 exits per room to another arena, the
  shop, a bonus, or a joke. Your playstyle + optional goals nudge which portals open.

## Read in this order

1. [Core loop](01_core-loop.md) — the whole game on one page.
2. [Classes & loadout](02_classes-and-loadout.md) — Vanilla+, dual-weapon classes, the universal art kit.
3. [The gesture system](03_gesture-system.md) — 90 gestures as a gold-bought build tree.
4. [Scoring & the combo chain](04_scoring-combo.md) — the SDF damage-chain and the gold economy.
5. [Crits & locational damage](05_crits-locational.md) — the precision layer gestures plug into.
6. [The difficulty director (DDA)](06_difficulty-director-dda.md) — normalized time-to-kill, adaptive set-pieces.
7. [Economy & the shop](07_economy-shop.md) — gold, the SDF worldspace shop, what it sells.
8. [Encounter spikes](08_encounter-spikes.md) — captains, elites, curse tokens.
9. [Engine seams](09_engine-seams.md) — the native hooks this design needs (exists vs. proposed).
10. [Open questions](10_open-questions.md) — every unresolved fork, in one place.
11. [The gesture engine](11_gesture-engine.md) — **native C++ + `vr_gestures.json` + HTML editor.** The architecture.
12. [The hardpoint & loadout map](12_hardpoint-map.md) — wrist ability slots, tool holsters, the shieldsaw, the re-seed spec.
13. [Arenas & the run structure](13_arenas-and-run.md) — **reconfigurable holodeck rooms, the portal lattice, earned path control.** The level layer.
14. [Replay & capture](14_replay-capture.md) — a watchable, **horizon-locked stabilized** run video, rendered offline. Live view never touched.
15. [Gesture engine reference](15_gesture-engine-reference.md) — the **built code**: JSON schema, verbs, anchors, how to add a gesture, the ZScript hook, wiring status.

## The gesture catalog (companion)

The raw 90-gesture catalog lives next door in
[`../DoomXR_Gesture_Ideas/`](../DoomXR_Gesture_Ideas/) — browse it via
`gesture-catalog.html` (searchable, filterable) or the per-category `.md` files.
This design set explains *how those gestures fit the game*; the catalog is the
idea inventory itself.

## The one-sentence pitch

You pick a dual-weapon fighting style, you still play Doom, and everything you do
with your hands — how you kill, reload, finish, traverse, dodge — feeds a chain-score,
a gold economy, a crit layer, and a difficulty director that escalates to meet your
skill and hands you a bullet-time stage to show off on.
