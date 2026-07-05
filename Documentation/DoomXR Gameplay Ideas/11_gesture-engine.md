# 11 — The gesture engine (architecture)

**Committed architecture.** The gesture system is not 90 hand-coded features — it's **one
native engine that makes all 90 declarative JSON entries.** This is the anti-piecemeal
move: the hard part is a single focused C++ push, and after it lands, a new gesture is a
JSON object, not a sprint.

## Why one engine, not 90 gestures

Every gesture is the same shape: *read the hands → is this motion a verb → is the gate
button down → fire.* Build that once, in C++, and the gestures become data. Building them
one at a time is the wrong architecture, not just the slow one.

## The three layers (+1)

```
  C++  (vr_gesture.cpp)     →  DETECTION. ring buffers, anchors, verb/shape classifier.
                               Reads vr_gestures.json, evaluates each gesture's recipe per
                               tic, fires gesture_fired("<id>") when it hits.

  JSON (vr_gestures.json)   →  DEFINITION. one declarative object per gesture. No code.

  ZScript                   →  EFFECTS. the named action a fired gesture triggers
                               (spawn the whip lash, pop the powerup) — effects touch
                               weapons/actors, which live here.

  HTML editor (down the line) → AUTHORING. builds the JSON visually. Frozen-schema only.
```

**Who owns what:** C++ owns detection + dispatch. ZScript owns effects. JSON is the glue.

## What the native engine computes (per hand, per tic)

- **Ring buffers** — position, velocity, and angular velocity, ~1s of history. *This is
  the piece that doesn't exist yet and blocks half the catalog* (today only per-tick
  linear velocity is exposed).
- **Body anchors** — chest/hip/shoulder/temple/wrist/back, computed once. Derived from
  feet + viewheight + facing, so they drift — recipes use generous radii + context gates.
- **Motion-verb classifier** — `THRUST / ARC / CIRCLE / FLICK / SHOVE / GUARD / CATCH /
  PLACE / REVERSAL`. This is the grip arbiter (`VR_ResolveGripOwner`) grown from
  button-ownership into full motion-verb classification.
- **Shape recognition** — circle CW/CCW, figure-8, slash, lasso loop — off the buffer.

Exposed to ZScript as one clean surface: `VR_HandIntent(hand)`, `VR_ClassifyShape(hand)`,
`VR_AnchorNear(id, hand)`, plus the `gesture_fired` event.

## A gesture is data

```json
{
  "id": "pouch_reload",
  "anchor": "chest", "hand": "off",
  "motion": "flick", "gate": "BT_RELOAD",
  "dwell": 6, "radius": 22,
  "action": "pouch_reload"
}
```

Add the object → the gesture exists. The binding seam is one hop:
**native detects → `gesture_fired("pouch_reload")` → a ZScript action table runs it.**

## Why this is bigger than "customizable"

- **No recompile** to add, retune, or rebind — hot-load the JSON.
- **Every mod ships gestures** — a weapon pack drops its own `vr_gestures.json`.
- **Players share profiles** — export/import a moveset.
- **The 90-idea catalog becomes the default JSON** — the shop just flips `"owned": true`
  per entry ([07](07_economy-shop.md)). The build tree *is* the JSON.
- **Accessibility falls out** — rebind a hard flick to a button, widen a radius.

## Precedent (honest)

JSON-defined config is a **real DoomXR pattern**: `vr_hardpoints.json` (verified in
`vr_config.cpp` — overrides the native hardpoint slots) and `KEYWORDS.json` (climb
textures). The gesture JSON is the next instance of that.

The **HTML editor is a NEW DoomXR build**, not an existing precedent. (An earlier draft of
these docs wrongly cited an HF `hfcolors.json` + HTML editor as DoomXR's — that was from
an inspiration-only reference tree, not this engine. Corrected here.)

## Build order (disciplined, not hedged)

1. Build the native engine to **read JSON from day one** — cheap: a parser + the schema.
2. Ship a **hand-authored** `vr_gestures.json` (the catalog defaults).
3. Add the **visual editor only after the schema stops moving.** Building the UI early =
   chasing a format you'll change twice.

## The native seams this needs

See [09 — engine seams](09_engine-seams.md). The high-leverage ones: the position/velocity
ring buffer, the verb classifier (grow `VR_ResolveGripOwner`), `GetHandAngularVelocity`,
and the `gesture_fired` dispatch. Detection in C++, calls in ZScript.
