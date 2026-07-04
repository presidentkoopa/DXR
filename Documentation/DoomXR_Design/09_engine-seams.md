# 09 — Engine seams (exists vs. proposed)

This design leans on native DoomXR hooks. Per the engine-level-native-first mandate,
authoritative state, net-safety, and core decision logic should be native C++ exposed to
modders — not ZScript workarounds. This is the seam inventory.

## Already exists (verified in the DoomXR tree)

| Seam | What it does | Used by |
|---|---|---|
| `GetHandVelocity(hand)` | per-tick linear hand velocity | most motion gestures |
| `OffhandPos/Dir/Pitch/Angle/Roll` | offhand orientation; palm-out already gates a cast | palm gestures, twirl, ADS |
| `VR_ResolveGripOwner` / `VR_GetGripOwner` | native grip-intent arbiter (NONE/CLIMB/GLOVE/WHIP/HARDPOINT/TWOHAND) | grip disambiguation |
| **Native Hardpoint system** (`vr_hardpoint.h`, `vr_config.cpp`) | shoulder/hip **holster** slots (draw/stow appears wired) + wrist **ability** mounts | body-mounted draws, wrist casts |
| `VR_HardpointAbility(hand, slotIndex)` | **stubbed empty** virtual — the wrist-tap fires it natively, nothing overrides it yet | the open seam for wrist abilities |
| `GetGripValue(hand)` · `IsHardpointNear` · `GetHardpointWorldPos` · `VR_HolsterHand` | hardpoint queries exposed to ZScript | holster/pouch logic |
| `VR_HapticPulse` | per-hand rumble | all haptic feedback |
| Two-hand **capsule** test | barrel-axis capsule (not sphere) — natural foregrip | two-hand gestures |
| First-person **IK arms** (marine IK skeleton) | real shoulder/elbow/wrist reach in headset | bone-anchored gesture ideas |
| Manual-reload FSM | native per-weapon bone-read + hotspot + reload state machine | reload-flourish gestures |
| `AActor.GravityDir` | native gravity vector; wall/ceiling walk | traversal gestures |
| SDF procedural text + glow-panel | worldspace neon UI primitive | score-burst, combo, shop, countdowns |
| Combo/damage-chain (SDF) | cumulative damage → bank peak → shard-burst | scoring ([04](04_scoring-combo.md)) |
| Kill-reward bits | 6-bit shatter incl. **gold** | economy ([07](07_economy-shop.md)) |
| Crit/headshot handler | locational (hit-height) crits; needs True-Bullet mode | precision ([05](05_crits-locational.md)) |

## Proposed new seams (this design implies)

| Seam | Purpose | Priority |
|---|---|---|
| `Radiance.TierWave(color, sweepMode, origin, durationTics)` | clean native shader control for the difficulty director — replaces direct glow-cvar poking | **high** — unblocks the difficulty director ([06](06_difficulty-director-dda.md)) |
| Per-gun **dominance** tracker | normalized `expected_TTK / actual_TTK` moving average, native so it's save/net-safe | high — the DDA signal |
| `VR_HardpointAbility` override (content) | wire the stubbed wrist-ability dispatch to real moves (whip quick-cast, etc.) | high — cheapest big win |
| Hand-intent arbiter growth | grow `VR_ResolveGripOwner` into a motion-**verb** classifier (SHOVE/GUARD/FLINCH/PLACE/CATCH) so gestures react to a verdict, not raw pose | medium — many gestures share it |
| Hand position/velocity **ring buffer** + `ClassifyGestureShape` | true shape recognition (circles, figure-eights) for lasso/sigil gestures | medium |
| `GetHandAngularVelocity(hand)` | rotational-rate signal (grenade spin-fuse, twirls) — today only linear velocity exists | medium |
| `GetIKBonePos(boneName)` | drift-free bone-anchored holsters off the IK skeleton (vs. derived, drifting anchors) | medium |
| Barrel-vs-actor overlap test | extend the two-hand capsule to test enemy hitboxes (bore-through, impale) | low |
| Directional/side haptic | per-side intensity for hit-direction + threat-bearing cues | low |

## The cross-lane caution

Multiple sessions share the DoomXR tree. The difficulty director's cvar-poking and the shader lane
already collide — which is *why* a native `Radiance.TierWave` seam matters (it removes the
shared-cvar race). Any work here must respect the shader-lane ownership rules and re-anchor
line numbers before editing. See the reload/ammo-pouch grip-seam contract for the same
pattern of cross-session coordination.
