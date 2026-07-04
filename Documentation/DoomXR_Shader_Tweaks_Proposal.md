# DoomXR Shader Tweaks — Proposal
### Companion to `3_SHADER_SYSTEM_MAP.md` (in `DXR_SWORD_SLICE_DOSSIER\`) · 2026-07-03

**Status update:** §1 (ripple wiring) is now **IMPLEMENTED** in `wadsrc/static/shaders/glsl/main.fp` — see §1
below for the as-built diff summary. §2 (cut-plane clip) and §3 (blade glow — confirmed no-op) remain
proposal-only, unchanged. **Not yet build-verified** — needs a real compile of `E:\DoomXR-work\DOOM_FRESH`
before this can be trusted in headset (per the standing rule: this kind of C++/GLSL change isn't
grep-checkable the way pure ZScript is).

---

## 0. Scope and status

This is a **proposal, not a patch** — nothing has been edited. Shader files were previously a hands-off
reserved lane (`dxr-multisession-lanes`); this pass was done with explicit authorization to look and suggest.
All three items below were verified directly against the live `main.fp` / `hw_renderstate.h` this session
(fresh read, timestamps checked — `main.fp` last modified 2026-07-03 00:59, after the earlier read-only
recon, so line numbers here were re-confirmed, not assumed). Nothing here is a balance or feel change — all
three are either finishing already-started work or additive rendering primitives with zero effect until
something opts in.

---

## 1. Finish the dangling ripple-distortion wiring (bug-adjacent, not a new feature)

**Where:** `wadsrc/static/shaders/glsl/main.fp:1929-1950`, inside `main()`.

There's a "Reactive Impact Ripples" block already written, gated on `u_vr_ripples_enabled` and
`u_vr_ripple_scale` (both default to `0`/off — `hw_renderstate.h:414-415`). It computes a world-space
distortion offset:

```glsl
vec3 ripplePos = pixelpos.xyz + normalize(pixelpos.xyz - u_gitd_last_impact_pos) * ripple * 32.0 * u_vr_ripple_scale;
```

**...and then never uses it.** The variable falls out of scope at the end of the `if` block. The comment
sitting right above it says so outright:

> *"threading the distorted position into SetupMaterial/regime sampling is separate follow-up wiring work"*

**Confirmed by direct grep:** `ripplePos` appears exactly once in the entire file (line 1947) — it is
write-only. So today, even if a mod sets `u_vr_ripples_enabled=1` and dials in a scale, **the ripple has zero
visible effect** — the impact-time/impact-position tracking and the wave-shape math all run for nothing.

**AS-BUILT (implemented 2026-07-03):** `applyVisualRegime` now takes an explicit `vec3 worldPos` param —
**not** a default-argument, since GLSL has no default parameters (checked before implementing; C++ intuition
doesn't transfer here). There was exactly one call site (`main.fp:2019`, confirmed via grep — no overload was
needed), so the signature was changed directly rather than adding a second overload. The four internal reads
that represent "which world cell is this pixel in" (`distToPlayer`, the Tron grid, the LSD wave, and the
Tetris voxel grid — `main.fp` inside `applyVisualRegime`) now read `worldPos` instead of `pixelpos.xyz`
directly, so ripple distortion actually reaches all four regimes that sample world position.

A new `vec3 regimeWorldPos` local was hoisted to the **top of `main()`, before the `#ifndef
LEGACY_USER_SHADER` branch** — this matters: the ripple block itself lives inside that `#ifndef`, but the
call site is after the `#ifndef/#else/#endif` closes, so a variable declared only inside the `#ifndef` branch
would leave `regimeWorldPos` undeclared under the deprecated `LEGACY_USER_SHADER`/`ProcessMaterial()` path —
a real compile break that would only surface on old-style custom shaders, not the common path. Caught this
during implementation, not after; declaration was moved above the `#ifndef` so both branches compile.

Verified statically: exactly one definition + one call site (grep), no other file references
`applyVisualRegime`, brace count balanced (168/168) post-edit. **Not yet build-verified** — this needs an
actual compile to confirm the GLSL is well-formed; static checks can't catch everything a compiler will.

**Risk:** low, self-contained to one function + one call site + one new local. The one real gotcha (the
`LEGACY_USER_SHADER` scope issue above) was found and fixed during implementation.

---

## 2. World-space monster cut-plane clip (enables real-time slice rendering)

**Where it would live:** new discard/alpha logic near the top of `SetupMaterial`'s call chain in `main.fp`,
reading `pixelpos.xyz` (`main.fp:5`) against a plane.

**Data channel (already free, zero struct growth):** pack a plane normal + distance into the two spare
`int u_gitd_pad0` / `u_gitd_pad1` fields (`hw_renderstate.h:264-265`, confirmed still unused — both hardcoded
to `0` at `:417-418`) or the free `.w` lane of `u_gitd_last_impact_pos` (`:267`, currently only `.xyz` used).
No StreamData struct growth, no std140 re-sync across the Vulkan/GL/GLES trio required.

**What it does:** on a per-actor or per-draw basis, compute signed distance from `pixelpos.xyz` to a
world-space plane (point + normal); `discard` the fragment on one side. This is the mechanism
`2_VR_SWORD_DESIGN.md` and `3_SHADER_SYSTEM_MAP.md §6(a)` already scoped as the **Phase-2, continuous**
alternative to the model-swap slice approach — a live model or sprite gets a real cross-section clip instead
of swapping to a pre-baked "capped" mesh.

**Why propose it now rather than build it now:** the MVP build order deliberately ships the ZScript
model-dismember-swap first (needs zero shader edits) and only reaches for this if the swap doesn't read
convincingly in-headset. This entry exists so the concrete plumbing is written down and ready the moment
that decision is made, instead of re-deriving it later.

**VR correctness requirement (from §5 of the shader map, still binding):** must use per-eye `uCameraPos` for
any view-relative culling and must commit via an early return / `FragColor` write before the fragment
pipeline moves on — the stereo present stage (`present_row3d.fp` etc.) is 2D and cannot add or remove
geometry after the fact.

---

## 3. Blade glow/trail using the existing glow-spot pool (zero new bytes)

**Where:** ride the existing `uWallGlowSpots[16]` / `uWallGlowMask[16]` arrays (`hw_renderstate.h:202/206`,
confirmed unchanged) rather than adding new uniforms.

**What it does:** treat each blade (or a few points along its length during a swing) as a glow spot —
`.xy` = world center, `.z` = packed RGB, `.w` = radius — fed from ZScript via the same
`AddGlowSpotWiped`/`AddGlowPanel` calls the combo-meter and score-burst effects already use
(`gitd_combo.zs`, `gitd_scoreburst.zs`). The `wipeType`/`progress` fields in `uWallGlowMask` already support a
directional fade, which is exactly a trail-fade behavior for free.

**Why this one needs no shader-file edit at all:** the rendering side (`main.fp` wall-glow-spot loop, already
live) doesn't care what's populating the array — a blade segment looks like any other glow spot to the
fragment shader. **The entire implementation is ZScript-side** (spawning/updating glow spots per tic while
swinging) — this entry is here for completeness of the shader-tweaks review, but it confirms *no* shader lane
work is actually required for saber/Dragon's Tooth glow trails. Only worth touching the shader if the pool of
16 spots is found to be a real capacity constraint once particle effects + blade glow + combo meter + score
burst are all live simultaneously — in which case growing `MAX_WALL_GLOW_SPOTS` 16→32 (`hw_renderstate.h:178`)
is the fallback, but that forces a 3-backend prelude sync and shouldn't be reached for pre-emptively.

---

## 4. Priority / recommendation

1. **Finish the ripple wiring (§1) — DONE**, pending build verification. Benefits both GITD and the sword's
   impact feedback for free once the build confirms it links and a headset pass confirms it doesn't induce
   nausea (proximity-masked already, but verify with `u_vr_ripples_enabled=1` + a nonzero `u_vr_ripple_scale`
   before shipping it on by default).
2. **Cut-plane clip (§2)** — write it when/if the model-swap slice approach needs a Phase-2 upgrade. Don't
   build speculatively.
3. **Blade glow (§3)** — no shader action needed; flagged here only to confirm that conclusion, not as work.

Nothing here touches balance, feel, or gameplay values — all three are rendering-plumbing completions or
additive primitives that do nothing until something opts in.

**Ready when you are** — say the word and I'll implement §1 (and §2 if you want it done now rather than
deferred) directly in `E:\DoomXR-work\DOOM_FRESH`.
