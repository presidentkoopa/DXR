All load-bearing facts are now confirmed against the real repo. Two notable ground-truth corrections to the debate:

1. The `vr_aim_through_tic` latch (defense's "already mid-remediation" claim for `net`) is **real and present** at gl_openvr.cpp:3271-3289 — but the gate at 3285 (`GetWeaponTransform(...) && aimThisFrame`) only latches the AttackPos *write*, and the checksum still excludes AttackPos. So the defense is right that scaffolding exists, and the prosecution is right that it's default-off and checksum-blind.
2. The `SoundListener` struct at i_soundinternal.h:101 genuinely stores only `position/velocity/angle` — but the up-vector `orient[3..5]=(0,1,0)` at oalsound.cpp:1759-1761 is the real single intervention point, exactly as the defense argued.

I have enough to write the autopsy.

---

# AUTOPSY REPORT: DoomXR Gravity-Vector Plan

## 1. VERDICT IN ONE LINE

**The F0 core LIVES — but only in a de-maximalized form.** The plan as *pitched* (full arbitrary-axis gravity across every actor, collision, AI, water, and render path) is DEAD on cost; the plan as *actually scoped* (localized `Vel.Z -= grav` swap in one function + per-actor/per-room application, world-geometry showcases) survives with real but survivable wounds. Every lethality-5 "keystone kill" was overturned or reduced on the real code.

---

## 2. THE BODY COUNT

| Rank | Pillar | Surviving Lethality | Status | One-line reason |
|------|--------|:---:|:---:|---|
| 1 | **F0-core** | 2 | **WOUNDED** | Gravity is genuinely funneled through *one* function (`FallAndSink`, p_mobj.cpp:3023/3027) — but VR HMD-feed rotation + `viewz` offset are real chores, and every "arbitrary-axis" subsystem kill only lands if you refuse to scope. |
| 2 | **radial (F1)** | 2 | **WOUNDED** | The lethality-5 keystone (normalize NaN) is **dead on arrival** — `Unit()` is guarded (vectors.h:645). What survives is the same F0 vectorization + scoping radial to Showcase B only. |
| 3 | **carry** | 2 | **WOUNDED** | Polyobject-sphere is DEAD (XY-only, po_man.cpp:899-913), but actor-on-actor vertical carry already exists (MF2_ONMOBJ / P_PushUp). Only horizontal drag is a genuine gap. |
| 4 | **net** | 2 | **WOUNDED** | Attacked the wrong target (VR-pose replication, not gravity). Gravity state already rides the checksum; the pose gap is orthogonal and half-remediated (`vr_aim_through_tic` exists, default-off). |
| 5 | **blindside (audio)** | 2 | **WOUNDED** | Listener orientation *does* only store yaw, but expands to a full 6-float AL basis one layer down (oalsound.cpp:1759). One up-vector = the whole fix. Overreached on VR_GetMove and pitch "double-apply." |
| 6 | **scale (F6)** | 1 | **LIVE** | Per-player shrink via VR cvars is a fiction — but nobody needs it. `Scale`/`radius`/`Height` are per-actor (actor.h) and collision reads them per-actor. Ship it. |
| 7 | **render (F4)** | 0 | **LIVE** | Entirely a strawman. The mono-camera-texture limit is real but **irrelevant** — showcases are world geometry through the per-eye main pass. Nothing to fix. |

No pillar's *code claims* were fabricated. Several pillars' *conclusions* were — the fight was almost entirely over **scope**, not facts.

---

## 3. THE DEADLIEST FINDING

**The consistency checksum is blind to VR aim pose — and that hole is real, but it is NOT a gravity hole.**

> `g_game.cpp:1567` computes the netgame checksum from `mo->X()+Y()+Z() + Yaw.BAMs() + Pitch.BAMs() ^ health` only. `AttackPos` (written from the render thread at gl_openvr.cpp:3287-3289) is excluded, so pose-driven hit divergence goes **silent until kill-count desync becomes visible.**

Why this is the scariest *true* fact that changes the plan: it means the **gravity refactor is safe on the wire** (Vel/Z/floorz all ride the checksum), but it also means the **existing VR firing path is already a latent netplay desync**, and layering per-actor `GravityDir` on top adds a second un-checksummed, un-serialized per-actor field unless you explicitly add it to `Serialize()` and the checksum. The `vr_aim_through_tic` latch (gl_openvr.cpp:3276) proves the maintainer already knows — but it's **default-off** (`hw_vrmodes.cpp`) and only latches the *write*, not the checksum. **Any 2v2 showcase must treat netplay determinism as an explicit, gated deliverable, not an assumption.**

---

## 4. PER-FEATURE GO / NO-GO

| Feature | Ruling | Reason + surviving mitigation |
|---|---|---|
| **F0 — sign-flip / per-actor gravity** | **BUILD-WITH-MITIGATION** | Gravity is localized to `FallAndSink` (3023/3027) + one bullet-drop line (2650). Scope: (a) per-room sign-flip for Gravity Cubes (flip one grav sign — zero dot-product work); (b) per-pawn `GravityDir` for the two Sphere-Arena players only. Leave collision/3D-floors/heightsec/AI in native scalar-Z. Add `GravityDir` to `Serialize()`. |
| **F0 — VR HMD-feed rotation into gravity frame** | **PROTOTYPE-FIRST** | Real chore, not a rewrite. `viewz` offset (p_user.cpp) is a ~3-line local edit; HMD roll *is* already tracked (`doTrackHmdRoll=true`). But "rotate the world around a room-locked player" is a comfort question no code review can settle — **spike it in a headset before committing.** |
| **F1 — radial gravity** | **BUILD-WITH-MITIGATION** | NaN keystone is dead (`Unit()` guarded, vectors.h:645). Formula `(ball.Pos-actor.Pos).Unit()*grav` at center yields zero-gravity for one tick, not corruption. Cache `GravityDir` per-actor per-tick in `FallAndSink`. **Strictly scope to Showcase B players.** |
| **F4 — dome via camera texture in VR** | **CUT (as camera-texture); BUILD as world geometry** | Camera textures are hard-mono in VR (hw_vrmodes.cpp:654) — real. But render the dome/sphere as **world geometry**; it flows through the per-eye main pass (hw_entrypoint.cpp:515) for free. The camera-texture design was never in the plan. |
| **F6 — per-player shrink** | **BUILD** | Per-player VR-cvar scale is a myth, but unneeded. Shrink the body via per-actor `Scale`/`radius`/`Height` + `A_SetSize`; collision reads them per-actor (p_map.cpp:1893). Zero cvar/netcode work. Local view-scale feel is that client's own GLOBALCONFIG. |
| **F8 — 4-player determinism w/ VR pose** | **PROTOTYPE-FIRST** | The one genuinely dangerous pillar. Gravity is checksum-covered; **VR pose is not.** Ship SP/co-op-authoritative first. For netplay: default `vr_aim_through_tic` ON, gate `OverrideAttackPosDir` off + force thumbstick locomotion when `netgame && vr_teleport`. Do NOT attempt pose serialization for v1. |
| **Showcase A — Gravity Cubes** | **BUILD-WITH-MITIGATION** | Portal-linked rooms + per-room sign-flip. Planes stay horizontal (Z still "up," only accel sign flips) → collision/3D-floors/heightsec untouched. Cheapest real gravity feature in the whole plan. **Build this first.** |
| **Showcase B — Sphere Arena (2v2 radial)** | **PROTOTYPE-FIRST** | Depends on F1 + carry + net simultaneously. Each is survivable alone; the *stack* is unproven. The engine realities (2D AI, 2D blockmap, scalar floorz) are pre-accepted and confined to the ±Z teammates — but that assignment must be tested, not assumed. |
| **carry (riders on bouncing ball)** | **BUILD-WITH-MITIGATION** | Vertical carry is free via MF2_ONMOBJ (rider Z snapped to `onmo->Top()`, P_ZMovement) + P_PushUp on up-stroke. Carrier = `+SOLID +ACTLIKEBRIDGE` mobj, **NOT** a polyobject. Horizontal drag is the one real gap: add carrier XY-vel delta to each ONMOBJ rider in the carrier's `Tick`. |
| **blindside — spatial audio** | **BUILD** | Cheap, self-contained. Carry `GravityDir` into `SoundListener`, then in `oalsound.cpp:1759-1761` set `up = -GravityDir` (mapped to OpenAL axes) instead of `(0,1,0)`. ~6 float assignments in an already-per-frame function. Leave the `{X,Z,Y}` swap alone. |

---

## 5. DE-RISK ORDER (spike these BEFORE committing weeks)

**Spike 1 — Gravity Cubes sign-flip room (½–1 day).** In `FallAndSink`, flip the sign of `grav` per portal-linked room (a room tag → sign lookup). Zero dot-product math, zero subsystem touch. This proves the *cheapest* real-gravity feature works and de-risks Showcase A end-to-end. If sign-flip alone feels good in VR, you've shipped a showcase for one day of work.

**Spike 2 — Single-actor radial gravity, flatscreen first (1 day).** One player pawn, `Vel -= (ballPos - actor.Pos).Unit() * grav` cached per tick, on a normal sector floor (planes intact, `ZatPoint` untouched). Verify: no NaN at ball center (already guarded), no infinite slide (bounded arena), physics stable. **Run flatscreen before VR** — separate the physics question from the vestibular question.

**Spike 3 — VR HMD-frame rotation comfort test (½ day, headset-mandatory).** Take Spike 2 into the headset and rotate the *rendered* view into the gravity frame while the physical floor stays fixed. This is the single unmeasurable risk in the plan — the vestibular mismatch (real floor can't tilt) that **no grep can resolve.** If this nauseates, radial gravity is a design problem, not an engineering one, and you want to know *now*, not after the collision/AI/net work.

*(Deliberately deferred: no camera-texture perf spike is needed — F4-as-camera-texture is cut. No per-player-scale spike — F6 is stock per-actor `Scale`.)*

---

## 6. WHAT TO CUT TONIGHT

Stop planning around these — their defenses **failed** or the feature was never real:

- **CUT: polyobject-as-sphere.** DEAD on real code — `DoMovePolyobj` (po_man.cpp:899-913) adds only `pos.X`/`pos.Y`, no Z term. A polyobject physically cannot be a bouncing ball. The defense *conceded* this ("kill stands"). Use a `+SOLID +ACTLIKEBRIDGE` mobj instead.
- **CUT: F4 dome-via-camera-texture.** The camera-texture path is hard-mono in VR and was a strawman the plan never required. Render as world geometry. Delete every note about camera/canvas-texture domes, per-instance live cameras, and the 2-3ms-per-dome budget — none of it applies.
- **CUT: per-player VR-cvar scale system.** `vr_vunits_per_meter_p1` et al. don't exist and **shouldn't be built.** The whole "months of work / per-player cvar refactor / network-replicate scale" plan is solving a problem shrink never had. Per-actor `Scale`/`radius`/`Height` already exist and already replicate implicitly (size travels with the actor). Any planning doc proposing per-player render-scale cvars should be shredded.
- **STOP treating "arbitrary-axis everything" as the F0 target.** The maximalist F0 (rewrite collision, 3D-floors, heightsec, monster AI compass, blockmap for any gravity direction) is a genuine multi-week rewrite and is the **only** version where the lethality-5 kills land. It is not what the plan needs. Scope F0 to sign-flip rooms + per-pawn radial and the "50+ site rewrite" evaporates.

**Bottom line:** the good ideas (sign-flip Gravity Cubes, per-actor shrink, world-geometry showcases, gravity-aware audio up-vector, free vertical rider-carry) are cheap and real. The scary parts (radial physics stability, VR vestibular comfort, netplay pose determinism) are the *only* three things worth spiking before you commit — and two of the three can only be answered inside a headset.