# 03 — The gesture system

VR motion is DoomXR's most underused surface. There are ~90 catalogued gestures
([`../DoomXR_Gesture_Ideas/`](../DoomXR_Gesture_Ideas/)). This doc is how they become a
*game system* instead of a menu.

## The core idea: gestures are a gold-bought build tree

You never spawn holding 90 moves. You spawn with fists + your class frames, and you
**buy your art with gold** ([07](07_economy-shop.md)):

- **Gold buys a TOOL** (whip, sword, shieldsaw, ice hooks). Owning the tool unlocks its
  gesture branch.
- **Gold (or a dealt upgrade card) buys the deeper MOVES on a tool you own.** You have
  the revolver; *Cylinder Flick Reload* and *Fanning* are purchases on top. You have the
  whip; *Lasso Wind-Up* and *Whip-Yank Ground Pound* are purchases on top.

Result: the player only ever sees the ~8 gestures they *chose*. The 90 is the shop
stock, not the tutorial. This is the single most important design move in the whole
project — it's what makes a huge gesture library legible.

## The two-tier split

| Tier | Owned by | Examples |
|---|---|---|
| **Universal art** | every class (bought, not class-locked) | whip grapple/yank/swing · sword slice/parry/throw · shieldsaw block/rev · ice-hook climb · fist glory-kills · jump/dodge/traversal |
| **Class art** | only your dual pair's dialect | quickdraw, twirl, cylinder-flick, pump-rack, akimbo draw, spin-up, ADS |

Picking a class never locks you out of the fun VR toys — it decides which **gunfighting
dialect** you master. (See the per-class gesture columns in [02](02_classes-and-loadout.md).)

## How a gesture is detected (the proven template)

Every gesture follows one shape, which is what makes it net-safe and non-accidental:

> **proximity-to-a-body-anchor is an ENABLING FILTER; a real button-bit is the TRIGGER.**

Reaching the chest *enables* the pouch reload; the reload button-bit *confirms* it.
Copy that everywhere. Body anchors (chest/hip/shoulder/temple/wrist/back) are **derived**
from feet + viewheight + facing — they **drift** on lean/crouch/turn, so use generous
radii + context gates (what's held, palm-facing dot, dwell, button), never tight geometry.

Signals available: `GetHandVelocity(hand)` (per-tick linear velocity), the offhand
orientation set (`OffhandPos/Dir/Pitch/Angle/Roll`), the grip-intent arbiter
(`VR_GetGripOwner`), and haptics (`VR_HapticPulse`). See [09](09_engine-seams.md).

> **How this is actually built:** gestures are not hand-coded one at a time. A native
> engine detects them from a declarative `vr_gestures.json`; ZScript does the effects.
> This is the anti-piecemeal architecture — see **[11 — the gesture engine](11_gesture-engine.md)**.
> Where each gesture physically lives on the body is **[12 — the hardpoint map](12_hardpoint-map.md)**.

## Two design rules every gesture must pass

Surfaced by the catalog's critique pass; both are visible per-card in the HTML catalog:

1. **Net-safety (⚠).** A gesture that fires a real gameplay effect off *pose alone*
   (no button) is not multiplayer-deterministic. Anything net-relevant must bottom out
   on a real button-bit before any DM/co-op mode. Pose can *enable*; a bit must *confirm*.
2. **Hands-full (✋).** A gesture that assumes an empty/open hand breaks the
   fire-while-hands-full keystone. Prefer gestures you can do *with a gun in hand*. Ones
   that need a free hand (two-hand pry, bare-hand catch) must be clearly situational.

## How gestures feed the four brains

This is *why* a gesture is worth gold — it's an input to a live system, not flavor:

- **Combo chain** ([04](04_scoring-combo.md)): a whip-yank drags a fresh target into
  your *live* chain (the chain travels); a finisher banks at a boosted multiplier;
  mobility gestures keep the chain window open while you reposition.
- **Crit/locational** ([05](05_crits-locational.md)): *Called Shot Point* designates a
  weak point; precision gestures cash in headshots the crit layer already scores.
- **The difficulty director** ([06](06_difficulty-director-dda.md)): gestures spike your kill-speed →
  dominance rises → a bullet-time set-piece is staged → that slow-mo window is exactly
  where the flashy gestures pay off. Styling summons the spectacle.
- **Gold economy** ([07](07_economy-shop.md)): a loot-vacuum backhand sweep / trophy
  pouch-toss rakes in the bit-shower a big kill drops.

## Where the catalog lives

- Searchable/filterable: [`../DoomXR_Gesture_Ideas/gesture-catalog.html`](../DoomXR_Gesture_Ideas/gesture-catalog.html)
- Per-category detail + top picks + gaps: the `.md` files in that folder.
- Each idea carries: anchor · trigger · effect · vibe-fit · engine cost · net-safety /
  hands-full flags · top-pick marker.

## Known gaps (from the critique pass)

Two holes matter more under this framing:

- **No distinct lob/underhand throw** — the grenade/utility classes want it.
- **No weapon-to-weapon mid-air swap** — the dual-class juggling fantasy wants it.

Both move from "nice to have" to "a style is missing a core verb."
