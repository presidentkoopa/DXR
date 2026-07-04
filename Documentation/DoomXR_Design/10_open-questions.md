# 10 — Open questions

Every unresolved fork, in one place. Nothing here is decided; these are the design
choices still on the table.

## Economy & shop

- **Gold buys tools, moves, or both?** (Leaning: both — tool is the gate, moves are the
  cheap deepening.) → [07](07_economy-shop.md)
- **Where's the shop?** Between-map hub · in-world SDF vendor · or the difficulty director's
  set-piece *drops* a gold-priced gesture-card choice (reusing the card-dealer). The
  set-piece-reward option is the most loop-integrated. → [07](07_economy-shop.md)
- **Does dominance feed the gold economy directly?** i.e. dominate → richer bit-showers →
  more gold → more gestures, or is the bullet-time set-piece the *only* payout of
  dominance? → [04](04_scoring-combo.md), [06](06_difficulty-director-dda.md)
- **Is the universal art (whip/sword/shieldsaw/ice hooks) spawned or bought?** Lean
  version: spawn with fists + class frames, buy the rest. → [02](02_classes-and-loadout.md)

## Classes & weapons

- **Big guns: normal pickups, or gated?** Lean: normal Doom pickups for everyone; gate
  only the *empowered* mode behind a gesture (gun free, mastery costs a move). →
  [02](02_classes-and-loadout.md)
- **Is BFG a universal power weapon or its own class?** Lean: universal — everyone's big
  moment. → [02](02_classes-and-loadout.md)
- **Final dual-class roster?** Candidate: Pistol / Revolver / SMG / Shotgun / SSG / Rifle
  / Chaingun / Plasma — each with a distinct VR hand-motion identity. → [02](02_classes-and-loadout.md)
- **Do the 2 class frames start rolled Basic** (same as the loot floor), so the whole run
  is growing that one pair? (This matches the frame→imprint loop.) → [02](02_classes-and-loadout.md)

## Scoring & combo

- **Does the chain break on taking damage, or only on the timer?** This decides whether
  the defensive gestures (guard, flinch, dodge) are **combo tools** or just survival. →
  [04](04_scoring-combo.md)
- **Does a big combo bank shower richer gold**, tying the style number to the spend? →
  [04](04_scoring-combo.md)

## The difficulty director

- **Per-gun dominance (adaptive composition) or a single global dominance number to ship
  first?** Lean: global first, per-gun as the richer follow-up. → [06](06_difficulty-director-dda.md)
- **Balance/tuning:** dominance thresholds, dial speed, cooldowns, wave duration — all
  the user's call, deliberately unset here. → [06](06_difficulty-director-dda.md)
- **Is the abandoned difficulty director being picked back up as part of this work, or parked?**
  (The `Radiance.TierWave` native seam is the unblock either way.) → [06](06_difficulty-director-dda.md)

## Gestures

- **Fill the two missing verbs:** a distinct lob/underhand throw, and a weapon-to-weapon
  mid-air swap. Both are load-bearing under the class framing. → [03](03_gesture-system.md)
- **Net-safety pass:** which pose-only gestures get a required button-bit before any
  co-op/DM mode? → [03](03_gesture-system.md)
- **Which gestures are "starter/free" vs. gold-gated?** The shop needs a stock list with
  a free tier. → [03](03_gesture-system.md), [07](07_economy-shop.md)

## Engine

- **Priority order of the proposed native seams** — `Radiance.TierWave` and the
  `VR_HardpointAbility` wiring look like the two highest-leverage first moves. →
  [09](09_engine-seams.md)
