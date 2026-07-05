# 06 — The difficulty director (DDA)

The difficulty director is the dial-moving brain: it watches how well you're playing and, when
you're dominating, **tiers up the monsters** (Radiance recolors the room) and **stages a
bullet-time set-piece**. It's the system that turns skill into spectacle.

## The intended goal (what it's *for*)

Track **player time-to-kill, per gun**, as the skill signal → dynamically change the
**color tier** of monsters and **spawn set-piece events**. The recolor is driven through
Radiance (the map/glow shader) at specific times and intensities.

## Why the first attempt never landed: raw TTK is noise

Raw time-to-kill can't be thresholded. A pistol dropping an imp in 0.4s and the same
pistol chipping a baron for 8s are the gun performing *identically* — but raw TTK reads
one as "overpowered" and one as "useless." The dial jerks on **encounter composition,
not skill**. That's the bug.

## The fix: normalize TTK into a scale-free dominance signal

You already have every number needed (the weapon's rolled damage + fire-delay stats give
DPS; the monster carries SpawnHealth):

```
expected_TTK = monster.SpawnHealth / gun_DPS       // what this gun "should" take
dominance    = expected_TTK / actual_TTK           // >1 = faster than expected
```

Now dominance is **scale-free**: crushing a baron and crushing an imp both read ~1.5 if
you're over-performing, and neither inflates just because a monster was weak. Roll it as
a **moving average per gun over the last handful of kills**. *That's* the stable dial
signal the raw version lacked — it measures the player, not the monster.

> Thresholds (what counts as "dominating," how fast the dial moves, cooldowns) are the
> user's balance call — this documents the *signal*, not the tuning.

## What the dial does when it crosses threshold — the LOCKDOWN

The proven set-piece choreography (VR-safe throughout):

1. **Lock-in** — freeze via **bullet-time** (monsters + projectiles slow; the player
   keeps moving + head-tracking — the same VR-safe freeze the captain fight uses), and
   slam the glow to black.
2. **3 → 2 → 1** countdown (beeps + worldspace SDF digits).
3. **Execute** one of:
   - **Color Wave** — an expanding ring sweeps outward from the player, flashing every
     monster it passes up to the new tier; the whole room recolors for the duration.
   - **Hotspots** — upgrade-squares drop (monsters walking in tier up), half the room
     hyper-focuses the player, and floor-seams open and rise tiered monsters (masked by
     smoke). Runs **until those risen enemies are cleared.**
4. **Lift** — the map returns to its preset; monsters keep their bumped tier.

## Per-gun is the payoff, not just a global bump

Because dominance is tracked **per gun**, the set-piece can *answer the specific gun*
you're crushing with — you're shredding with the shotgun, so it spawns tankier
mid-rangers that punish point-blank and reward a reposition. TTK-per-gun's real value is
**adaptive encounter composition**, not "make everything redder." (A single global
dominance number is the ship-it-first version; per-gun is the richer follow-up — fork in
[10](10_open-questions.md).)

## The real blocker: shader control is a missing native seam

The prototype **pokes the glow cvars directly** (`glow_color_floor` / `glow_color_ceil`),
snapshotting and restoring them by string. That's why it felt uncontrollable — it stomps
global cvars, races the shader lane and anything else touching glow, and there's no clean
"sweep the room to red tier N for 6 seconds" call.

**Proposed fix — a native Radiance seam:**

```
Radiance.TierWave(color, sweepMode, originPos, durationTics)
```

One call that owns the push/restore internally. The director *requests* a wave; Radiance
*decides how the shader animates it*, timed and clean. Turns "poke a cvar and pray" into
"declare intent" — the same native-first move as the grip arbiter. See [09](09_engine-seams.md).

## The feedback loop with gestures

Once dominance is a real signal, gestures become an **input to the dial**: a whip-yank
chain, a called-shot headshot, a banked finisher — all spike dominance → summon a harder
wave *with a bullet-time window* → which is exactly the arena where those same gestures
pay off. Skill doesn't trivialize the game; it escalates it into a stage you're equipped
for. That's DDA that feels like a reward, not elastic punishment.
