# 15 — Gesture engine reference (the built code)

Concrete reference for the first-cut native engine. The *why* is [11](11_gesture-engine.md);
this is the *how* — schema, vocabulary, wiring — matching the actual code.

> **Status:** first cut, written 2026-07-04, **not yet compiled**. Inert (new files, not in
> the build) until the 3 wires below land on a verifiable build.

## Files

- `src/playsim/vr_gesture.h` — engine interface (ring buffer, verbs, anchors, def struct, API).
- `src/playsim/vr_gesture.cpp` — implementation (ring math, classifier, JSON loader, dispatch).
- `vr_gestures.json` — the gesture table. Lives **next to `doomxr.exe`** at runtime, read like
  `vr_hardpoints.json`.

## `vr_gestures.json` schema

Top level: `{ "gestures": [ … ] }`. Each entry:

| field | type | values | default |
|---|---|---|---|
| `id` | string | unique name | **required** |
| `anchor` | string | `none` `chest` `hip_l` `hip_r` `shoulder_l` `shoulder_r` `temple` `wrist_main` `wrist_off` `belt` `back` | `none` |
| `hand` | string | `main` `off` `either` | `either` |
| `motion` | string | a verb (below) or `none` | `none` |
| `gate` | int | button-bit; `0` = pose-only (**not multiplayer-safe**) | `0` |
| `radius` | number | map units to the anchor | `24` |
| `dwell` | int | tics the condition must hold before firing | `0` |
| `action` | string | ZScript action name | `= id` |
| `owned` | bool | the shop flips this per player | `true` |

Keys starting `_` (`_comment`, `_readme`) are ignored — use them for notes (JSON has no
comments).

## Motion verbs

**Implemented** (classified from one hand's buffer):
`flick` · `thrust` · `slash` · `circle_cw` · `circle_ccw` · `reversal`

**Stubbed** (need the context pass — cross-hand or actor overlap, not yet written):
`shove` · `guard` · `catch` · `place` · `arc`

`none` = match any motion (fire on anchor + gate + dwell alone).

## Anchors

Derived body positions (feet + view-height + yaw-rotated offset). `wrist_main` / `wrist_off`
resolve directly to the hand positions. *TODO: unify with the hardpoint system's
`GetHardpointWorldPos` so anchors have one source of truth ([12](12_hardpoint-map.md)).*

## Adding a gesture (no recompile)

Add an object to the `gestures` array, reload. Done. Example:

```json
{ "id": "temple_flashlight", "anchor": "temple", "hand": "off",
  "motion": "flick", "gate": 0, "radius": 16, "dwell": 3, "action": "flashlight" }
```

## The effect hook (ZScript)

When a gesture fires, native calls **`VR_GestureFired(Name id, int hand)`** on the player
pawn. Write the virtual + an action table:

```zscript
override void VR_GestureFired(Name id, int hand)
{
    switch (id)
    {
        case 'pouch_reload':  DoPouchReload(hand);   break;
        case 'belt_grenade':  DoBeltGrenade(hand);   break;
        // ...
    }
}
```

## Read API (optional polling)

For content that wants to react to raw state rather than a fired event:
`VR_HandIntent(hand)` → current verb; `VR_AnchorNear(anchor, hand)` → bool. *(Thunks pending
— see wiring.)*

## Wiring status

- **Done (inert):** the 3 files above.
- **Pending — needs a verified build:**
  1. add `vr_gesture.cpp` to `CMakeLists.txt`;
  2. one call `FVRGestureEngine::Get().Update(player)` in `P_PlayerThink` (`p_user.cpp` —
     coordinated with the IK lane);
  3. the `VR_GestureFired` virtual on the player in `player.zs`.
- **Later:** the `VR_HandIntent` / `VR_AnchorNear` thunks (`vmthunks_actors.cpp` + `actor.zs`).

## Tuning

Verb thresholds (flick speed, thrust displacement) are hardcoded `const`s in `ClassifyVerb`
for the first cut. Move to CVars or per-gesture JSON fields when tuning against real headset
motion.
