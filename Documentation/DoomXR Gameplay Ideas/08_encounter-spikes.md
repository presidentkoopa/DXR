# 08 — Encounter spikes (captains, elites, curse tokens)

These are the arcade spikes that make gestures and loot *matter* — the moments the core
loop ([01](01_core-loop.md)) pays out hardest.

## Captains (the orb-champion miniboss)

A strong monster is promoted to a **Captain**, wrapped in N tethered **orb-champions**
(nearby monsters). Each orb lends the boss **one buff while alive**, its color saying
which:

| Orb | Color | Effect on the boss |
|---|---|---|
| Shield | orange | takes reduced damage |
| Regen | pink | heals over time |
| Rage | red | always-fast (hyper-aggressive) |

**Kill an orb-champion → its orb POPS:**
- strips that buff off the boss,
- erupts a **loot geyser** (pickups + a direct **gold** payout),
- triggers **bullet-time** (slows monsters + projectiles, not the player),
- the whole room goes **HOT** (every monster always-fast).

Pop all orbs → the boss is naked → finish it. Stop popping → the hot room at full speed
eats you. **Bullet-time is both the reward and the only tool to survive the escalation it
caused** — and it's exactly the window where your bought gestures shine (a whip-yank to
the next orb, a called-shot, a finisher).

## Elites (the legendary champion)

A normal monster, marked legendary, quietly carries a **dormant champion**. Hurt it to
~40% HP and it **erupts** — the transform wakes the champion (color, aura, pentagram,
buffs). On death it drops the class's loot:

- **Frame-fill phase** (you hold < 6 frames of your class weapon): drops the next frame
  as a junk-floor roll to collect.
- **Imprint phase** (you hold all 6): drops an **imprint token** you stamp onto a held
  frame (hold-USE; grip modifier targets the offhand frame). "The real rolls begin."

This is the engine of the frame → imprint loop ([02](02_classes-and-loadout.md)).

## Curse tokens

A boss-tier monster drops an activatable **curse-token** — walk over it, then activate to
**lift one curse** on your held main-hand weapon (clears one locked rolled-stat). Lifting
the last curse flips the frame **divine**. If the held gun has no curse to lift, the
token isn't consumed (so it's never wasted).

## How the spikes feed the loop

| Spike | Feeds |
|---|---|
| Captain orb-pop | gold geyser (economy) + bullet-time (gesture arena) + room-hot (dominance pressure) |
| Elite death | the frame → imprint loot loop (class progression) |
| Curse token | de-risks cursed loot → lets you keep chasing high tiers |
| The difficulty director's set-piece ([06](06_difficulty-director-dda.md)) | *summons* these spikes when you dominate |

The difficulty director is the conductor; captains and elites are the instruments it cues.
