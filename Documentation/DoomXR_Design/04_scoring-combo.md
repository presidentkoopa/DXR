# 04 — Scoring & the combo chain

DoomXR's score is **not** a scorecard of named multiplier slots. It's a **damage chain**,
rendered in the SDF glow system, that you sustain and bank.

## The chain, mechanically

1. **You keep damaging a monster → a cumulative damage number CLIMBS**, drawn with the
   GITD glow-shader digits floating above the monster's head (the same glow-number
   primitive as the floor kill counter — VR-safe, no sprites, no dynamic light).
2. **The chain has a break window.** Each tic without a hit ages the chain; the number
   visibly *dims* as it nears breaking ("hurry, it's slipping").
3. **On kill or chain-break, the PEAK is banked** — a `combo-bank` event awards points
   (peak × a score-multiplier cvar), and a **score-burst** display fires at the spot the
   chain ended: the digits scatter, then **converge/assemble** in mid-air, hold, and fade.
4. Two independent modes coexist on purpose: per-shot damage pops *and* the cumulative
   chain tracker. Filterable (all monsters / champions / bosses).

The feel: *don't let go.* Sustain the beating, bank big, watch the shards assemble.

## Why this changes how gestures score

Because the score is a **chain**, a gesture's job is to **keep the chain alive or spike
the bank**, not to tick a named bonus. The clean hooks:

- **Chain travel** — a whip-yank drags a *fresh* target into the *existing* live chain
  instead of starting a new one. The chain moves across the room with you.
- **Bank spikes** — a finisher (glory-kill, saw bore-through, overhead slam) banks at a
  boosted score-multiplier. Reward the flashy close.
- **Window maintenance** — ice-hook/jump/dodge traversal keeps the break-window open
  while you reposition, so **mobility is combo maintenance**, not a break from it.

## The gold economy is the other half of scoring

Points are the *style* readout; **gold is the spendable currency.** They come from
different places and do different jobs:

- **Score / combo peak** → the arcade dopamine + the difficulty director's dominance read
  ([06](06_difficulty-director-dda.md)). It's the "how well am I playing" number.
- **Gold** → dropped as one of the **kill-reward bits** ([07](07_economy-shop.md)) and
  *spent* on tools and gestures.

A big banked chain should feel like it also *pays* — a fat combo bank could shower richer
bits (more gold). That ties the style number to the spend directly (open fork:
[10](10_open-questions.md)).

## The six kill-reward bits

Every monster shatters into weighted bits (count scales with monster color-tier and boss
status; all cvar-weighted):

| Bit | Color | Effect |
|---|---|---|
| Health | red | +HP |
| Armor | blue | +armor |
| Ammo | green | +ammo for the held weapon |
| CND repair | silver | +1 condition to both held weapons |
| **Gold** | gold | **the shop currency** |
| Curse-coin | bronze | lifts one curse tier on a held cursed weapon |

Visuals are SNES scale-bob + a soft additive glow-child sharing the bit's sprite pivot
(never a dynamic light, per the GITD rule). The **loot-vacuum** / **pouch-toss** gestures
are the physical way you rake these in.

## Presentation is all SDF / glow

The combo digits, the score-burst assemble, the shop ([07](07_economy-shop.md)) — all
ride the SDF procedural text + glow-panel system. This is deliberate: one consistent
neon presentation language, and it's the same tech that unblocked the shop from being an
un-VR-friendly OptionMenu.
