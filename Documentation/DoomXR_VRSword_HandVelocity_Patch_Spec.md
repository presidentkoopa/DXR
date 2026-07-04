# DoomXR VR Sword — Hand Velocity Native Binding Patch Spec
### Technical companion to `DXR_SWORD_SLICE_DOSSIER\2_VR_SWORD_DESIGN.md` · 2026-07-03

**Status: SUPERSEDED — this patch is not needed.** While implementing it, discovered that a *different*
concurrent session had already added the correct native — `Actor.GetHandVelocity(int hand)`, declared at
`wadsrc/static/zscript/actors/actor.zs:866`, backed by `DEFINE_ACTION_FUNCTION(AActor, GetHandVelocity)` at
`src/playsim/p_actionfunctions.cpp:5748` — and it's already live in a shipping weapon
(`weaponshieldsaw.zs:479`, `owner.GetHandVelocity(bOffhandWeapon ? 1 : 0)`).

**My version, briefly landed in `p_pspr.cpp`/`player.zs`, was both a duplicate AND objectively wrong** and has
been removed:
- It called `VRMode::GetHandVelocity` directly — raw, current-tic controller velocity.
- The correct existing native instead reads `player_t::vr_hand_vel_buffer[hand][]` (the 4-tic smoothed
  average, already populated every tic by `VR_UpdateGravityGloves`), then applies an **(X,Z,Y) coordinate
  remap and a `vr_scale_meters_to_units / 35.0` unit scale** — both steps my version skipped entirely.
- Practically: my version would have returned velocity in the wrong coordinate space and units, silently
  breaking any weapon's flick-speed threshold check that assumes the existing convention (as `ShieldSaw`
  does, comparing directly against `10.0`).

**Original open decision (§5, expose validity or not) is moot** — the sword should just call
`owner.GetHandVelocity(hand)` directly, same as `ShieldSaw` already does. No patch needed here. Kept this
document as a record of the mistake and the fix, per this session's own standard of not silently reverting
without explanation.

---

## 0. What this patch does

Exposes the engine's already-computed VR hand velocity to ZScript as `PlayerPawn.GetHandVelocity(int hand)`.
Today the value exists only in C++ (`p_user.cpp`), feeding one feature (flick-throw). This patch adds one new
native function so any ZScript weapon — starting with the VR sword — can read a clean, pre-smoothed swing
speed instead of differencing `AttackPos` deltas by hand. Verified directly against
`E:\DoomXR-work\DOOM_FRESH` this session, not taken from the earlier swarm report at face value.

**Lane:** non-shader (`p_pspr.cpp` + `actor.zs`) — my lane per `dxr-multisession-lanes`, no shader-owner
sign-off needed. **Effort:** ~1 hour C++ + rebuild to verify link.

---

## 1. What already exists — verified by direct read

- `OpenVRMode::GetHandVelocity(int hand, DVector3& outLinear) const` — `gl_openvr.cpp:3034`, reads OpenVR's
  `pose.vVelocity`.
- `VKOpenXRDeviceMode::GetHandVelocity(...)` — `vk_openxrdevice.cpp:4355`. **Confirmed both backends implement
  it** (this was a real open question, not assumed) — OpenXR is not a stub.
- Base class default — `hw_vrmodes.h:172`: `virtual bool GetHandVelocity(int hand, DVector3& outLinear) const
  { return false; }`. Flatscreen/non-VR mode safely no-ops.
- Consumer + smoothing — `p_user.cpp:1486-1494`: raw velocity is pushed into a 4-sample rolling buffer
  (`player_t::vr_hand_vel_buffer[2][4]`, `player_t::vr_hand_vel_index[2]`) and averaged into `handVelocity`
  every tic, for both hands.
- Proven consumer pattern — `p_user.cpp:1532-1533`: `flickSpeed = handVelocity.Length(); if (flickSpeed >
  10.0)` gates the flick-throw. This is the exact shape a sword swing-gate should mirror.
- **Hand indexing is a raw `0`/`1` int, not a named enum anywhere in this codebase** (checked
  `p_local.h`/`constants.zs` — only flag bits like `ALF_ISOFFHAND` exist, no `VR_MAINHAND`/`VR_OFFHAND`
  constant). Match this convention; don't invent a new enum.
- **No existing "VR" pseudo-class exposed to ZScript** to hang this off of. The established pattern is a
  native directly on `APlayerPawn`, e.g. `DEFINE_ACTION_FUNCTION(APlayerPawn, CheckWeaponButtons)` at
  `p_pspr.cpp:874` — `PARAM_SELF_PROLOGUE(AActor); PARAM_INT(hand)`. This patch mirrors that shape exactly.

---

## 2. The patch

**`src/playsim/p_pspr.cpp`** — add adjacent to `CheckWeaponButtons`:

```cpp
DEFINE_ACTION_FUNCTION(APlayerPawn, GetHandVelocity)
{
    PARAM_SELF_PROLOGUE(AActor);
    PARAM_INT(hand);
    DVector3 vel(0, 0, 0);
    bool valid = VRMode::GetVRModeCached(false)->GetHandVelocity(hand, vel);
    ACTION_RETURN_VEC3(vel);   // see §3.1 — return the bool too, don't drop it
}
```

**`wadsrc/static/zscript/actors/actor.zs`** — add near `AttackPos` (`:272-279`):

```
native vector3 GetHandVelocity(int hand);
```

That's the whole binding surface. The ZScript sword reads `owner.GetHandVelocity(0 /*or 1 offhand*/)` per tic
and takes `.Length()` for tip-speed style gating (per `2_VR_SWORD_DESIGN.md` §2 — gate on **derived tip
speed**, not raw hand speed, since the tip whips faster than the hand on a flick).

---

## 3. Three things the naive copy-paste gets wrong

### 3.1 The bool return is silently dropped at one of the two existing call sites — don't repeat that
`GetHandVelocity` returns `bool` (tracking validity this tic — can go false on a brief occlusion/loss).
- `p_user.cpp:1936` **checks it**: `if (VRMode::GetVRModeCached(false)->GetHandVelocity(hand, handVel))`.
- `p_user.cpp:1486` **ignores it**: calls it, discards the return, always uses whatever ended up in
  `rawVelocity` (possibly stale/zero) and pushes it into the smoothing buffer regardless.

If the sword's swing binding mirrors the second (discarded) pattern, a brief tracking hiccup mid-swing reads
as "hand stopped," the gate never arms, and the cut is silently dropped with no error — reads as "the sword
just didn't work that swing" with no diagnosable cause. **Fix:** either surface the bool to ZScript
(`ACTION_RETURN_BOOL` + a `bool valid` out-param via `PARAM_POINTER`, or simplest — a paired
`bool HasValidHandVelocity(int hand)` native) or, at minimum, have the C++ side skip the buffer push on
`false` rather than overwrite with a stale zero. **Decide before wiring the sword's gate to this** — this is
a correctness call, not a style preference.

### 3.2 This is global hardware state, not a per-actor property — document the ceiling now
`VRMode::GetVRModeCached()` is one global singleton reflecting *the local headset's* controller state. Calling
`somePawn.GetHandVelocity(hand)` returns the same value regardless of which `PlayerPawn` it's called on — it
is **not** "that pawn's hand," it's "my hand," full stop. Harmless today (single-player, one real headset).
This is the same architectural fact already flagged in memory (`vr-aim-leak-location`,
`net-sanitize-mission`) — render-thread VR state reaches gameplay without going through netcode. **Do not**
build the sword's hit-registration or damage authority on an assumption that this will ever be correct for a
remote player. If multiplayer sword combat is ever wanted, this call needs to move behind whatever
net-sanitize eventually does for `AttackPos`/`AttackDir` — track it as the same future migration, not a new
one.

### 3.3 Verifying this compiles needs a real build, not the usual grep trick
The standing method for confirming a ZScript change is safe (`zscript-compile-check-method`) is grepping
`gzdoom.pk3`'s bundled zscript for a matching native signature — that only works because pure-ZScript edits
don't touch the compiler. **This patch adds new C++** (`DEFINE_ACTION_FUNCTION` + a `native` declaration that
must link against it). A typo in the param list, a missing include, or a signature mismatch between the C++
macro and the `.zs` declaration fails at **link time**, not at the grep-check stage. This patch is not
verified until it has gone through an actual build of `E:\DoomXR-work\DOOM_FRESH` — flagging so the build
being assembled now is the actual verification step, not a formality after the fact.

---

## 4. What this unblocks

- `VR_Sword.Tick()` swing-speed gate (`2_VR_SWORD_DESIGN.md` §2) — reads clean, pre-smoothed velocity instead
  of `AttackPos` deltas (which are jittery unless `vr_aim_through_tic=1`).
- Any other swing/flick/throw-gated ZScript feature going forward — this is the one general-purpose hook,
  not a sword-specific one. The whip (`doomxr-whip-vision`) and future gesture work in
  `dxr-vr-gesture-catalog` can consume the same native instead of re-deriving velocity per feature.

## 5. Open decision — RESOLVED

§3.1 resolved: shipped both natives. `PlayerPawn.GetHandVelocity(int hand = 0)` returns the smoothed vector;
`PlayerPawn.HasValidHandVelocity(int hand = 0)` returns the tracking-valid bool. The sword's `Tick()` gate
should check the latter before trusting a near-zero reading as "swing stopped" rather than "tracking hiccup."

## 6. Build verification (not yet done)

Static checks passed: no name collisions with existing natives, brace count balanced pre/post edit in
`p_pspr.cpp` (210/210), `ACTION_RETURN_VEC3`/`ACTION_RETURN_BOOL` macro usage confirmed against existing call
sites in `p_actionfunctions.cpp`. **None of this substitutes for an actual compile** — per §3.3, this is new
C++ + a new ZScript native declaration, and a signature mismatch between the two only surfaces at link time.
This patch is not trustworthy in-headset until it survives a real build of `E:\DoomXR-work\DOOM_FRESH`.
