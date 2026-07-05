# 01 — The core loop

The whole game is one feedback loop. Every system in the other docs is a stage of it.

```
   pick a CLASS (a dual-weapon fighting style)
            │
            ▼
   PLAY DOOM  ──►  kill monsters with skill (aim, gestures, positioning)
            │
            ├──►  KILL BITS shatter out  ──►  gold, health, armor, ammo, CND, curse-coin
            │                                        │
            │                                        ▼
            │                                   spend GOLD
            │                                        │
            ├──►  DAMAGE CHAIN climbs (SDF combo)     │  buy TOOLS (whip/sword/etc)
            │        └─ bank the PEAK on kill/break   │  buy MOVES (gestures) off owned tools
            │                                          ▼
            ├──►  CRITS / HEADSHOTS (locational)   your GESTURE KIT grows
            │        └─ precision gestures cash in       │
            │                                             ▼
            └──►  DOMINANCE rises (fast, clean kills)  ──► gestures feed the chain,
                     │                                     the crits, and the dominance dial
                     ▼
        THE DIFFICULTY DIRECTOR reacts to dominance
                     │
                     ├──► tiers up monsters (Radiance recolors the room)
                     └──► stages a BULLET-TIME SET-PIECE  ◄── the arena where flashy
                              │                                gestures pay off hardest
                              ▼
                     drops LOOT + a gesture/upgrade card
                              │
                              ▼
                     FRAME → IMPRINT loot loop deepens your class pair
                              │
                              └────────────────► back to PLAY DOOM, stronger, styling harder
```

## Why it holds together

Three properties make this a loop and not a pile of features:

1. **One skill signal drives everything.** "How well are you playing right now" is a
   single measurable thing — clean, fast kills. It climbs the combo chain, it triggers
   the difficulty director, and it's what gestures amplify. You don't tune five dials; you tune one.

2. **Skill escalates the game instead of trivializing it.** Most action games get easier
   as you master them. Here, dominating *summons* the difficulty director's harder waves — but the
   difficulty director pays you back with a bullet-time set-piece and loot, which is precisely the
   moment your bought gestures shine. Getting good makes the game *bigger*, not emptier.

3. **Gold closes the ring.** Kills → gold → gestures → better kills. The 90 gestures
   aren't a manual dropped on the player; they're a shop the player grows into. That's
   what keeps 90 moves from drowning anyone — you only ever hold the handful you bought.

## The four "brains" gestures feed

Every gesture is worth buying because it feeds at least one live system:

| Brain | What it wants | Gestures that serve it |
|---|---|---|
| **Combo chain** ([04](04_scoring-combo.md)) | sustained damage, chain not breaking | whip-yank (chain a new target), finishers (spike the bank), mobility (keep the window open) |
| **Crit/locational** ([05](05_crits-locational.md)) | precision, weak-point hits | Called Shot Point, Chamber Peek, ADS Focus |
| **The difficulty director** ([06](06_difficulty-director-dda.md)) | a clean read of dominance | anything that raises your kill-speed; then the set-piece rewards flashy play |
| **Gold economy** ([07](07_economy-shop.md)) | conversion of kills into spend | loot-vacuum sweep, trophy pouch-toss (rake in bits) |

See [03 — the gesture system](03_gesture-system.md) for how the kit is split (universal
art vs. class art) and bought.
