# 05 — Crits & locational damage

DoomXR **has** a crit + headshot system already, built on locational (hit-height) damage.
This is the precision layer the aiming/precision gestures plug into.

## How it works

A single lightweight damage-time handler (no per-monster thinkers — cheap on slaughter
maps) decides crits and headshots when damage actually lands:

- **Projectile crits** are rolled **at spawn**: a player missile that rolls a crit gets
  tagged and its tracer **tinted** (colored crit tracers). The damage handler reads the
  tag on hit.
- **Hitscan / melee crits** roll at damage time.
- **Headshots = hit-height fraction.** `(inflictor.z − victim.z) / victim.height`; if
  that fraction is at/above `1 − head_zone`, it's a headshot. A curated **ignore list**
  (matched by name-substring so it catches modded variants) excludes all-head or
  weird-hitbox monsters (cacodemons, lost souls, pinkies, bosses that are body-targets).
- Bonus damage is applied as a **separate damage event** with a marker type (so it works
  for hitscan too, and doesn't recurse). Crit and headshot have separate multipliers.
- Feedback: crit/headshot **sounds + FX bursts**, and a damage-number pop.

## The one hard constraint

**Headshots require True-Bullet mode (`vr_shot_mode 0`).** The head-zone test needs a
real inflictor world-position to measure against the monster's height; other shot modes
don't provide it. Any gesture or design that leans on headshots must assume this mode.

## How gestures plug in

The precision gestures aren't cosmetic — they feed a scoring layer that already pays out:

- **Called Shot Point** — offhand designates a weak point / head; landing the kill there
  is exactly the headshot the crit layer scores (and headshot kills already drop **bonus
  bits**, tying precision to the gold economy in [07](07_economy-shop.md)).
- **ADS Focus** — sighting down the barrel could tighten spread/recoil in a short window,
  raising your effective crit/headshot rate.
- **Chamber Peek** — reads real weapon state; pairs with the marksman rifle class.

## Crossovers into the other brains

- **Crit → XP.** Crit/headshot bonus damage naturally grants more weapon XP (the leveling
  system awards XP from damage dealt), so precision *also* levels your class pair faster.
- **Crit → chain.** A crit is a big single hit — it spikes the combo chain's climb
  ([04](04_scoring-combo.md)).
- **Crit → dominance.** Fast, precise kills raise dominance, which the difficulty director reads
  ([06](06_difficulty-director-dda.md)).

So the precision layer is a hub: one accurate headshot feeds XP, the chain, the crit FX,
bonus gold bits, and the difficulty dial simultaneously.
