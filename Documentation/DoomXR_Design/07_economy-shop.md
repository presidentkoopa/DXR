# 07 — Economy & the shop

## Gold is the currency

Gold drops as one of the six **kill-reward bits** ([04](04_scoring-combo.md)) and is the
single spendable resource. It's explicitly the "point-shop currency." Everything the
player buys — tools, gestures, upgrades — is priced in gold.

Two related resources keep their own jobs:
- **Score / combo peak** = the style readout + the difficulty director's dominance input. Not spent.
- **Curse-coins** = a side currency that lifts weapon curses 1:1.

## What gold buys

The economy is what makes the 90 gestures legible — you grow into a handful, you don't
receive a manual ([03](03_gesture-system.md)):

- **Abilities** (the wrist-slot loadout): the 6 wrist hardpoints ([12](12_hardpoint-map.md))
  are **buyable, assignable equip-slots** — the shop sells a pool (grav panels, jump-jets,
  + more), you assign three-per-hand and swap the loadout. This is the cleanest gold sink:
  a growing ability pool, three-per-hand at a time.
- **Tools** (the big purchases): whip, sword, shieldsaw, ice hooks. Buying a tool unlocks
  its whole gesture branch. (Tools holster; abilities slot to the wrist — see [12](12_hardpoint-map.md).)
- **Moves** (the cheap deepening): individual gestures on a tool you already own —
  *Lasso Wind-Up* on the whip, *Cylinder Flick Reload* on the revolver.
- (Optional) **Empowered big-gun modes** — the BFG drops free, but the overhead
  charge-ritual that unlocks its screen-clear is a purchase.

Recommended structure: **both** — the tool is the gate, the moves are the deepening.
(Fork in [10](10_open-questions.md).)

## The shop is now an SDF worldspace surface

The shop was historically blocked by in-game **OptionMenus**, which don't play nicely in
VR (they can't read the VR thumbstick cleanly, they float wrong). That's solved: the menu
layer is **SDF now** — the same procedural-text + glow-panel primitive as the score-burst
and combo digits. So the shop can:

- **Live in the world** — a vendor panel you walk up to, rendered in glow/SDF.
- **Be dealt as cards** — reuse the VR-safe **card-dealer** (already built for weapon/
  player level-ups): freeze the player, deal gold-priced gesture/upgrade cards, pick with
  the stick + fire. This is the strongest option because the tech already exists and is
  headset-proven.

## Where the shop appears (the fork)

Three candidate placements (not mutually exclusive):

1. **Between-map hub** — a calm shopping beat between levels.
2. **In-world vendor** — a walk-up SDF panel placed in the level.
3. **Set-piece reward** — the difficulty director's bullet-time set-piece ([06](06_difficulty-director-dda.md))
   *drops a gold-priced gesture-card choice* as its payout, dealt with the card-dealer.
   This ties the economy directly to dominance: play well → summon a set-piece → get
   offered a new move to buy.

Option 3 is the most integrated — it closes the core loop ([01](01_core-loop.md)) with no
separate "go shopping" mode.

## Gold sinks & sources (structure, not numbers)

- **Sources:** gold bits from kills (count scales with monster tier + boss status);
  richer bit-showers from big combo banks (proposed); captain/elite loot geysers pay gold
  directly ([08](08_encounter-spikes.md)).
- **Sinks:** tools, moves, empowered modes, re-rolls of loot frames, curse-lifting.

The design intent: gold is always flowing in from *playing well*, and always draining
into *new ways to play*. Never a dead resource.
