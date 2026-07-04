# DoomXR — Blade Slicing + VR Sword Dossier
*Three read-only swarm recons of `E:\DoomXR-work\DOOM_FRESH` (presidentkoopa/DoomXR-2.0-The-Wired), 2026-07-03. ~1.57M subagent tokens, 23 agents, all claims file:line-verified against the live tree. Nothing was edited or built.*

## The four documents
1. **1_SLICE_ARCHITECTURE.md** — how to break the sprite/pixel dependency and cut monsters in half. Ranked approaches + MVP.
2. **2_VR_SWORD_DESIGN.md** — the VR sword weapon: swing→hit pipeline, the swappable **BladeProfile** schema, Steel / Lightsaber / Dragon's Tooth as pure data, MVP build order.
3. **3_SHADER_SYSTEM_MAP.md** — full read-only map of the shader lane: pipeline/load-order, material contract, uniform channels, GITD effect catalog, VR stereo rules.
4. **`../DoomXR_VRSword_HandVelocity_Patch_Spec.md`** — the actual GetHandVelocity→ZScript patch (step 1 of the build order below), independently re-verified 2026-07-03 against live source (not just the swarm's citations). Read this before implementing step 1 — it corrects one bug pattern in the existing code that's easy to copy by accident.
5. **`../DoomXR_Shader_Tweaks_Proposal.md`** — now that shader-lane review is authorized: a dangling, half-finished ripple-distortion feature in `main.fp` (writes `ripplePos`, never reads it — comment admits it's unfinished), plus the concrete cut-plane-clip and blade-glow plumbing from §6 above, elevated to a ready-to-build spec.

## The five facts everything hangs on
1. **The sprite dependency is two-layered.** Monsters render as flat camera-facing quads (`hw_sprites.cpp:456`) AND hit detection is a 2D radius-only trace that **ignores Height entirely** (`p_maputl.cpp:1245-1274`) — no hit-Z, no surface, no bone. Model geometry is immutable post-load. So every viable "cut" is a disguised swap, not a true dynamic mesh split.
2. **The engine ALREADY tracks hand velocity — it just isn't in ZScript.** `VRMode::GetHandVelocity()` (`gl_openvr.cpp:3034-3048`, OpenVR `vVelocity`), a 4-sample per-hand ring buffer `player_t::vr_hand_vel_buffer[2][4]` (`d_player.h:441-442`), and a proven swing gate `flickSpeed > 10.0` (`p_user.cpp:1532`). **One ~1-hour `DEFINE_ACTION_FUNCTION` binding exposes it to ZScript — non-shader playsim lane, the single highest-leverage patch in this whole plan.** Fallback: derive from `AttackPos` deltas (works today, jittery unless `vr_aim_through_tic=1`).
3. **Winning slice approach: model-dismember-swap.** Real 3D model via MODELDEF → on gated swing: 1-2 tic pre-baked capped-cross-section flash → spawn two half-model gib actors flying apart (ice.zs:144-160 pattern). 100% supported pipeline (`FindModelFrame`, models.cpp:435), zero shader-lane edits, zero IQM bone work. Cost is art (3 meshes × N planes per monster), not code.
4. **The sword is one weapon + swappable data.** `VRSword : Weapon` owns Tick()-driven blade-segment tracking, tip-speed hysteresis gate, swept substep collision, damage; `BladeProfile` (data class) supplies model/glow/trail/sounds/damageType/behavior flags + ONE virtual (`ModifyDamage`). New blade per game = one data subclass, zero weapon edits. Contact emits a `BladeHitContact` record (hitPos + cutNormal from `swingDir × bladeDir`) — the seam the slice track consumes.
5. **Blade glow needs NO shader edits.** ZScript already feeds `uWallGlowSpots[16]` via `AddGlowSpotWiped`/`AddGlowPanel` — the saber/Tooth glow trail rides that today. The Phase-2 *continuous shader cut-plane* is the only shader-lane item: ~8 bytes packed into the spare `u_gitd_pad0/1` (`hw_renderstate.h:264-265`), fragment `discard` on `pixelpos.xyz` signed distance — needs shader-owner sign-off; ship the model-swap first and decide if it's even needed.

## Build order (fused MVP)
1. ~~**[C++ playsim]** Bind `GetHandVelocity(hand)` → ZScript~~ — **NOT NEEDED.** Already exists:
   `Actor.GetHandVelocity(int hand)` (`actor.zs:866`), correctly tic-smoothed + coordinate-remapped, already
   used live in `weaponshieldsaw.zs:479`. A duplicate/incorrect version briefly existed here and was removed
   — see `DoomXR_VRSword_HandVelocity_Patch_Spec.md` for the full account. Just call
   `owner.GetHandVelocity(hand)` in the sword's `Tick()`.
2. **[zscript] DONE, pending build.** `VRSword` Tick() segment scan + tip-speed gate (`vr_sword_swing_on/off`
   CVars) + broad-phase `BlockThingsIterator.CreateFromPos` + closest-point-on-segment narrow phase →
   damages a monster with a bare swing. File: `wadsrc/static/zscript/actors/doom/vr_sword.zs`.
3. **[zscript] DONE, pending build.** `BladeProfile` (`vr_blade_profile.zs`) + `BindBlade()`; `A_ChangeModel`
   cosmetic swap; `vr_sword_blade` CVar → Steel / Lightsaber / Dragon's Tooth on one weapon, each a pure-data
   subclass (Dragon's Tooth also overrides `ModifyDamage` for its armor-ignoring near-instant kill).
   **Not yet the swept-substepping / LineTrace-precision upgrade** — this is the simpler single-tic-sample
   collision test; fast swings between two tics can still tunnel through a target. Deferred deliberately
   until this baseline is proven in-headset (see the file's own header comment).
4. **[assets+modeldef]** ONE pose-simple monster (imp/zombie, avoid IQM decoupled-anim): whole / capped / UpperHalf / LowerHalf meshes, waist plane.
5. **[zscript]** `DoSlice()`: flash → two half-actors + `TraceBleed`/`SpawnBlood` along blade angle. Wire to `OnBladeContact`.
6. **Headset test** — de-risk trick: hardcode `DoSlice` onto the monster's Death state FIRST to validate the visual illusion before any velocity work.

## Key decisions still open
- Native velocity binding vs AttackPos deltas (recommend: **bind it**).
- Cut height is fake (trace has no hit-Z): snap to pre-baked plane vs approximate from `AttackPos.Z`.
- Saber deflect scope: all missiles vs enemy-only; mirror vs bounce-to-shooter.
- Dragon's Tooth one-touch: non-boss only? cooldown?
- Blade-on-psprite `modelindex:1` vs separate attached actor (model-lane confirm).
- Haptics: no ZScript rumble hook exists — defer or small `A_VRRumble` C++ patch.
- N cut planes: 1 for MVP, 4 for ship; curate which monsters are sliceable.

## Known swarm gaps (honesty log)
- *procedural-mesh-cut* design agent failed (retry cap) — moot: recon proved runtime mesh geometry is immutable/private, so a true dynamic cut needs engine work regardless; ranked last by construction.
- *damage-feel-and-feedback* facet agent failed (rate limit) — feel section in doc 2 was synthesized from the other three facets; thresholds are explicitly starting estimates for in-headset tuning.
