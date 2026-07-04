Confirmed: `vr_hand_vel_buffer[2][4]` exists at d_player.h:441-442 (the "4-sample buffer" is real), and the ZScript search for a GetHandVelocity native binding returns **nothing** â€” confirming the critical claim that swing velocity is NOT exposed to ZScript. FindModelFrame per-state selection confirmed at models.cpp:435/1250. All load-bearing claims verified. Here is the brief.

---

# Dynamically Slicing Monsters in DoomXR â€” Architecture Brief

*All citations verified against `E:/DoomXR-work/DOOM_FRESH` on 2026-07-03. Reserved shader-lane files flagged where touched.*

## 1. The real problem

DoomXR monsters are **flat billboards with cylinder collision**, and the two layers are fully decoupled. Rendering builds a 4-corner camera-facing quad per frame (`HWSprite::CalculateVertices`, hw_sprites.cpp:456) â€” a 2D card with zero depth, so "cutting" it reveals nothing behind. Hit detection is worse: `LineAttack` (actor.zs:807) resolves through a 2D trace that tests the ray only against the actor's `radius` square in XY and **ignores `Height` entirely** (p_maputl.cpp:1245-1274), returning an `FTranslatedLineTarget` with no hit-Z, no surface, no bone. And model geometry is **immutable post-load** â€” `mVertices`/`mIndices` are private and never re-uploaded (models recon; `FModel::LoadGeometry` runs once). So there is no engine path to erase voxels, split a mesh, or place a cut at the real blade-entry height. **"Breaking the dependency" concretely means: give the monster a genuine 3D volume that survives being cut open (real mesh or a fragment-discard shader), and decouple that visual cut from the cylinder hit-test â€” because the hit-test can never tell you *where* the blade entered.** Every viable approach is therefore a *disguised static swap*, not a true dynamic cut.

## 2. VR velocity reality

**There is no per-tic swing-velocity vector in ZScript.** Confirmed by grep: no `GetHandVelocity`/`HandVelocity` native is bound anywhere in `wadsrc/static/zscript/`. The real velocity lives in C++ only:

- `VRMode::GetHandVelocity(hand, outLinear)` is called **only** in native code at p_user.cpp:1486 and p_user.cpp:1936. It is a pure 3D linear velocity (m/s) from OpenVR `vVelocity` / OpenXR history.
- A **4-sample per-hand ring buffer** exists in playsim: `player_t::vr_hand_vel_buffer[2][4]` and `vr_hand_vel_index[2]` (d_player.h:441-442). p_user.cpp:1492-1494 averages the 4 samples into `handVelocity`.
- The **existing swing-gate precedent** you should mirror: p_user.cpp:1532-1533 computes `flickSpeed = handVelocity.Length()` and fires on `flickSpeed > 10.0`. Throw force reuses the same vector (p_user.cpp:1513).

What **is** in ZScript: `AttackPos` (DVector3), `AttackAngle`, `AttackPitch`, `AttackRoll`, all readonly natives on the actor (actor.h:1671-1676), valid only when `OverrideAttackPosDir` is set (actor.h:1671). `AttackPos` updates per-frame, or per-tic when `vr_aim_through_tic=1`.

**Building the two signals:**
- **Swing-speed gate (trigger):** Two options. (a) *Zero-C++:* sample `AttackPos` each tic, keep a small history on the weapon, gate on `(AttackPos - prevAttackPos).Length()/tic > threshold`. Jittery at render-rate unless `vr_aim_through_tic=1`. (b) *One-hour C++:* add one `DEFINE_ACTION_FUNCTION` wrapping `VRMode::GetHandVelocity` (the value already computed at p_user.cpp:1486) â†’ clean `handVelocity.Length()` in ZScript, mirroring the proven `flickSpeed>10.0` gate. **Recommend (b)** â€” it is non-shader playsim code (your lane), tiny, and removes the single biggest quality risk.
- **Cut-plane-from-direction:** plane point = `AttackPos`; plane normal = `normalize(cross(bladeForward, velocityDir))`, where `bladeForward` comes from `AttackAngle/AttackPitch/AttackRoll` and `velocityDir` from the same velocity source. `AttackRoll` lets a wrist-rolled blade rotate the cut. If you stay pure-ZScript, quantize to N discrete planes; the shader path can use the continuous plane directly.

## 3. Ranked approaches â€” (feasibility Ã— VR-fit / effort)

1. **model-dismember-swap â€” BUILD THIS.** *Real 3D models via MODELDEF; on a gated swing, flash a pre-baked capped-cross-section frame for 1-2 tics, then spawn two independent half-actors that fly apart.* Highest feasibility: 100% within supported pipelines (per-state model selection is real â€” `FindModelFrame(actor, state.sprite, state.Frame)` at models.cpp:435/1250), reuses the proven ice-chunk spawn+velocity pattern (ice.zs:144-160). Zero shader-lane dependency. Cost is **art, not code** (3 meshes Ã— N planes per monster). Best effort/reward ratio.

2. **Material-shader world-space cut â€” powerful, but shader-lane-blocked.** *Custom `ProcessTexel()` discards fragments on one side of a per-actor world plane, revealing a cross-section on the live model/sprite before the half-actor swap.* Genuinely dynamic (continuous cut angle/height, no pre-baked planes) and the injection site is real â€” the per-actor `Keywords` outline block at hw_sprites.cpp:311-392 is the exact template, and `discard`/`pixelpos.xyz` are proven usable (main.fp:1912/1959/2038). But it **requires adding `uSlicePlane` to `StreamData`**, which means byte-identical edits across `hw_renderstate.h` (:180-237, note the explicit "KEEP byte-identical" warning at :237) plus the per-backend GLSL preludes in `vk_shader.cpp`/`gl_shader.cpp`/`gles_shader.cpp` â€” **all RESERVED, all need shader-owner sign-off**. The `.fp` itself is reserved too. Higher effort, blocking external dependency. **Phase 2, not MVP.**

3. **ZScript half-actor swap on sprites only (from the gore recon) â€” cheapest, weakest.** *No models: just `LineAttack` â†’ spawn pre-made upper/lower gib actors, no visual on the live monster.* Trivial (days, pure ZScript, ice/serpent patterns). But it does **not break the sprite dependency** â€” the live monster is still a flat card at the moment of the cut, so the "slice" reads as a pop into two chunks. Fine as a *fallback gore tier*, not a slicing solution.

4. **`test` stub â€” N/A.** Placeholder, no content.

## 4. Recommended MVP â€” one monster, cut in half, in VR

**Rendering:** model-dismember-swap (approach #1). **Swing detection:** approach (b) â€” the one-hour native velocity binding â€” so your gate is the clean `handVelocity.Length()` mirror of p_user.cpp:1532, not fragile `AttackPos` deltas.

**Ordered first steps (each names lane + files):**

1. **[C++ playsim â€” your lane]** Add one `DEFINE_ACTION_FUNCTION` (or a `native` on PlayerPawn) wrapping `VRMode::GetHandVelocity` (source value at p_user.cpp:1486) to expose `GetHandVelocity(hand)` â†’ DVector3 to ZScript. *Not a shader file â€” no owner approval needed.* ~1 hour.
2. **[assets + modeldef â€” your lane]** Pick ONE pose-simple monster (imp/zombie; avoid decoupled-anim IQM per your memory note â€” baked IQM frames are broken). Author 4 meshes for a single **horizontal waist** plane: whole body, capped-waist body, `UpperHalf`, `LowerHalf`. Wire all four through MODELDEF as distinct sprite-frame entries (selection is per-state via `FindModelFrame`, models.cpp:435).
3. **[zscript â€” your lane]** Create `UpperHalf`/`LowerHalf` gib actor classes, each pointing at its half-model MODELDEF, copying the ice-chunk spawn+velocity block (ice.zs:144-160: `Spawn` at `Vec3Offset`, `Vel.Z = (pos.Z - origin.Z)/Height`).
4. **[zscript â€” your lane]** Add `DoSlice(double bladeNormalAngle, double bladeSpeed)` on the monster: `SetStateLabel` â†’ 2-tic capped-flash state; `A_NoBlocking`; spawn the two halves with `VelFromAngle(speed, bladeNormalAngleÂ±90)` (actor.zs:859) + inherited `Vel` + Z separation; `TraceBleed` on the `FTranslatedLineTarget` + `SpawnBlood` along the blade angle (`SXF_USEBLOODCOLOR`); destroy original after the flash.
5. **[zscript â€” your lane]** VR sword weapon: on swing, `LineAttack(..., LAF_ISMELEEATTACK, victim)` (actor.zs:807); gate on `GetHandVelocity(hand).Length() > ~10.0`; on hit call `victim.DoSlice(AttackAngle, speed)`.
6. **Playtest in VR:** confirm whole â†’ capped-flash â†’ two-halves reads as a cut, not a teleport. Tune the flash tics. *Only then* generalize to N=4 planes and more monsters.

**Fastest way to SEE it:** you can prove the visual illusion *before* touching velocity â€” hardcode `DoSlice` onto the monster's `Death` state so any kill triggers the wholeâ†’cappedâ†’halves swap. If that reads as a cut in VR, the model pipeline is validated; then bolt on the swing gate (steps 1/5). This de-risks art vs. input independently.

**Dependency flags:**
- **Shader-owner:** MVP needs **none** â€” approach #1 deliberately avoids `main.fp`/`StreamData`. Only the Phase-2 material-shader cut (approach #2) triggers the reserved-lane sign-off across `hw_renderstate.h`/`vk_shader.cpp`/`gl_shader.cpp`/`gles_shader.cpp` + a new `monster_slice.fp` (and the substring-scan trap: never write `SetupMaterial`/`ProcessMaterial` even in comments).
- **IQM-bone-patch:** **not required** for MVP and should be avoided â€” pick an MD3/OBJ or pose-simple monster so the state-driven model swap doesn't fight decoupled-anim frames (per your `dxr-iqm-reload-mechanism` memory: no ZScript bone R/W, baked IQM poses broken).

## 5. Open questions / risks (need a decision or a verify-build)

- **Cut height is fake.** The 2D trace has no hit-Z (p_maputl.cpp:1245-1274; `FTranslatedLineTarget` carries no height), so the plane snaps to a pre-baked height â€” a neck swing may render a waist cut. *Mitigation to decide:* approximate hit-Z from `AttackPos.Z` vs actor center to pick among vertical-offset variants, or accept snapping for MVP.
- **Velocity binding: build it or derive it?** Recommend the 1-hour native (step 1). If you insist on pure-ZScript, you must accept `vr_aim_through_tic=1` and delta-`AttackPos` jitter. **Decide before step 1.**
- **Content explosion.** 3 meshes Ã— N planes Ã— monster count. Only viable on a *curated* sliceable set. Decide N (recommend N=1 for MVP, N=4 for ship) and which monsters.
- **Flash timing.** The wholeâ†’cappedâ†’halves swap is instantaneous; 1-2 tics must be tuned in-headset or it reads as a pop. Verify-build required â€” cannot be judged from code.
- **Net-play latch.** If this ever goes multiplayer, latch the plane on the tic `LineAttack` fires (not per render frame), since `AttackPos` updates at render rate unless `vr_aim_through_tic=1`.
- **Phase-2 gate.** Whether to pursue the shader cut (approach #2) at all depends on whether the static model swap *looks* convincing enough in VR. Ship #1 first, then decide if the continuous shader cut is worth the reserved-lane coordination.

**Bottom line:** Build **model-dismember-swap** with the **1-hour native velocity binding**. It touches only your lanes (zscript / modeldef / assets / non-shader C++), reuses verified patterns (ice.zs:144-160, actor.zs:807/859, models.cpp:435), needs zero shader-owner approval and zero IQM-bone patch, and can show a monster cut in half in VR within the first prototype.
