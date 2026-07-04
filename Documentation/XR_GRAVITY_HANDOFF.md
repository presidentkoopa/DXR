# XR Gravity System — Session Handoff

*Written 2026-07-03 for the session absorbing the localized-gravity / gravity-path lane. This is the complete carry-forward. Companion reading: docs #9 (XR_GRAVITY_PATH_POWER), #10 (XR_SDF_GRAVITY_RIBBON), #11 (XR_DEBUG_VISUALIZERS), and the memory file `dxr-gravitydir-core-implemented.md` (even more granular). Source backup before all of this: `E:\DoomXR-work\DOOM_FRESH_srcbackup_gravdir_20260703_042045`.*

---

## 0. One-paragraph status

A per-actor **directional gravity vector** is implemented natively in the engine, plus a VR **hand-cast power** that paints walkable tiles onto any surface and reorients the player's gravity to stand on them. **Nothing is build-verified** — there is no headless compile in this environment, so the pending rebuild is the first real compile of all the C++. Everything is statically verified; the two new debug-render functions passed adversarial swarm review. Floor and ceiling gravity work; **wall-standing is deliberately NOT finished** (needs a collision rewrite — see §7, do not blind-implement it).

---

## 1. The design model (how gravity is represented and applied)

**Core idea:** gravity stops being a scalar (`Vel.Z -= grav`) and becomes a per-actor unit vector `GravityDir` pointing "down."

- `AActor::GravityDir` — `DVector3`, added in `actor.h` right after `Vel`. **Unit vector = the direction the actor falls.** `grav` is positive, so to stand on a surface with normal `N`, set `GravityDir = -N`.
- **`(0,0,0) is a sentinel = "use normal −Z gravity."** This makes every existing actor byte-identical: zero-init (same as `Vel`) means untouched actors behave exactly as before. This sentinel is the safety spine of the whole design — never remove it.
- `AActor::GravityAnchor` — a second `DVector3`, now **DORMANT** (it fed an earlier rest-clamp that was reverted). Harmless, still serialized, left in place. Ignore it unless you revive plane-clamping.

**Where it's applied (all in `p_mobj.cpp`):**
1. **`FallAndSink` (~3016)** — a top block runs *before* the grounded gate:
   ```cpp
   if (!GravityDir.isZero() && !(flags & MF_NOGRAVITY)) { Vel += GravityDir * grav; return; }
   ```
   This is the critical fix: directional gravity applies **even while grounded**, so the instant you attach to a tile you get pulled toward it. (Without it, a still player on the floor runs neither the Z-movement nor FallAndSink path and never reorients.)
2. **Outer `P_ZMovement` gate (~4437)** — extended to `if (Vel.Z != 0 || BlockingMobj || Z() != floorz || !GravityDir.isZero())` so `P_ZMovement` (hence `FallAndSink`) actually runs for a grounded gravity actor.
3. **Floor clamp** — reverted to the plain native `if (mo->Z() <= mo->floorz + 2)`.
4. **Ceiling clamp** — reverted to the unconditional native `if (mo->Top() > mo->ceilingz)`. The native ceiling clamp zeroes upward `Vel.Z`, which is exactly what makes ceiling-standing stable for free.

**IMPORTANT history:** an earlier "virtual rest-plane" clamp (using `GravityAnchor`) was **reverted** — it glued the player to the tile anchor and floated them off real floors. The native floor+ceiling clamps handle both correctly once gravity is *applied*. Don't re-add a custom clamp without solving that.

**Serialize / bindings:** `A("gravitydir",…)` + `A("gravityanchor",…)` in Serialize (save-safe: absent key → zero → normal); `DEFINE_FIELD(AActor, GravityDir/GravityAnchor)` in `vmthunks_actors.cpp`; `native vector3 GravityDir/GravityAnchor;` in `actor.zs`. So ZScript can read AND write `owner.GravityDir` per tic.

---

## 2. Behavior outcomes (reasoned from code, NOT yet tested in-headset)

| Surface | Result | Why |
|---|---|---|
| **Floor** | Normal walking | The power hands back to native (`GravityDir=0`) when the target normal faces up (`curGrav.z < -0.985`) |
| **Ceiling** | ✅ Works — player rises, native ceiling clamp catches, stable hang | Native `Top()>ceilingz` clamp zeroes upward Vel.Z |
| **Wall** | ⚠️ Sideways **pull only**, no true standing | Native clamps are world-Z; a horizontal "down" has no plane to rest against — see §7 |
| **Direct floor→ceiling 180° flip** | Snaps at midpoint | nlerp of two antipodal unit vectors passes through zero-length; gradual floor→wall→ceiling paths are fine |

---

## 3. The ZScript power — `wadsrc/static/zscript/actors/doom/vr_gravity_path.zs`

- **`XR_GravityPath : Inventory`** — the power itself, `DoEffect` runs per-tick (real C++ loop, `p_mobj.cpp:4096`).
  - **Cast gate = palm-out gesture, NO button:** `abs(owner.OffhandRoll)` must be within `(xr_gp_palm_lo=45, xr_gp_palm_hi=135)`. This is intentional — zero buttons so it coexists with grip contexts.
  - When gated + aiming: off-hand `LineTrace(TRF_ISOFFHAND)` from `OffhandPos` along `OffhandDir` → paints a chain of tiles with the surface normal derived from the hit.
  - **Attach = capture-box** (`FindCaptureTile`): per-tile slab on the walkable face (footprint length×width + margin, × capture-height along the normal); feet must be on the face side (`up in [-6, capH]`); fall-catch gate; nearest-by-height wins.
  - **Mount = lerp:** `curGrav` nlerps toward the tile's `-normal` at `1/(35*lerp_time)` per tic; each tick sets `owner.GravityDir = curGrav` (or `0` if floor-facing). Leaving → snap to `GravityDir=0`.
- **`XR_GravityPathNode : Actor`** — the TILE. `+FLATSPRITE +ROLLCENTER`. `XR_Orient()` derives Yaw/Pitch/Roll from SurfaceNormal + Tangent. `XR_BeginGrow()` = the fire-and-extrude spawn (seed square anchored at the previous tile's edge → smoothstep-extrudes to full length over `xr_gp_grow_time`, guaranteeing edge-to-edge abutment from tick 0). **Pitch formula is `atan2(horiz, n.z)`** (corrected — the earlier `atan2(-n.z,horiz)` gave zero tilt for walls).
- **`XR_GravityBeam : XR_GravityPathNode`** — live hand→aim-hit paint beam; `Alpha=0` (hidden, not destroyed) when idle.
- **`XR_GravityEmitter : Actor`** — wrist orb, `+FORCEXYBILLBOARD`, follows `OffhandPos`, pulses while casting.
- **`XR_GravityDebugMark : Actor`** — colored debug markers (`BAL1` sprite + `RenderStyle Stencil` + `SetShade`), gated by `xr_gp_debug`. **Uses sprite actors, NOT particles** (see §6).
- **`XR_GravityPathGiver : EventHandler`** — auto-gives the power. Registered in `mapinfo/common.txt:8` AddEventHandlers.
- **`extend class DoomPlayer { override void MovePlayer() }`** — **Rail Guard.** After `Super.MovePlayer()`, re-projects `vel` onto the attached tile's tangent basis (via `XR_GetRailDirection`, which blends toward the neighbor tile near edges), gated by `xr_gp_railguard`. **Must be a MovePlayer override, not DoEffect** — `STAT_PLAYER`(53) ticks before `STAT_INVENTORY`(57) and native MovePlayer recomputes Vel every tick, so a DoEffect Vel-write would lose the race. (GravityDir survives late writes only because nothing else touches it.)

Registered: `zscript.txt:170` include + `common.txt:8` handler.

---

## 4. Shader + sprite (SHADER LANE — normally hands-off, edited here under direct user direction)

- `wadsrc/static/shaders/glsl/vr_sdf_procedural.fp` — bit-512 tile mode = inset `boxSDF` (solid rect with a small inset so tile seams show). Bound to sprite **SIGLA0** via `gldefs.txt` HardwareShader. Uniforms `u_MSDF*` come from actor `msdf_enabled/msdf_glitch/msdf_color`.
- **`wadsrc/static/sprites/SIGLA0.png` — 64×64 white, REQUIRED.** The SDF material binds to sprite SIGLA0; without this file the tiles/emitter/beam render blank. **It is UNTRACKED in git (`??`) — the pk3 pack step MUST include untracked sprites** or the whole visual is invisible. This is the #1 silent-failure risk on the rebuild.

---

## 5. Requirements & map/actor needs

- **VR-only.** The power reads `OffhandPos`/`OffhandRoll`, valid only when `OverrideAttackPosDir` is set (real VR hand tracking). In flatscreen it's a **silent no-op** (no fallback path). The debug visualizers (§6) have the same VR gate.
- **No map format, no special tags, no actor requirements.** The power is auto-given by the EventHandler. Any map works. (An old idea to tag drawn rectangles with a "gravity" tag was dropped — tiles are spawned actors, not map geometry.)

---

## 6. Debug visualizers — the OTHER half of this lane (`hw_weapon.cpp`)

Because **particles do not render in the VR stereo view** (the engine's `P_SpawnParticle` grab debug was invisible — this is why the user could never see grab gloves), all debug viz is **real geometry**. Full detail in doc #11.

- Primitives: `DrawDebugTube` (line), `DrawDebugWireCone`, `DrawDebugWireSphere`, `DrawDebugSolidSphere` (UV-sphere), `DrawDebugSolidCone` (2-strip). Dispatcher `DrawXRDebugCones` → called from `DrawLaserSightWorld` at `hw_drawinfo.cpp:1308` (inside `DM_MAINVIEW`, once per eye, NOT gated by laser settings).
- Cones: cyan grab reach (both hands), orange gravity cast (off-hand, `xr_gp_debug`). Spheres: green catch (`vr_catch_radius`), blue climb (`vr_climb_radius`), yellow two-hand (`vr_twohand_radius`) — drawn at the real hand positions (`AttackPos`/`OffhandPos`), the same points the interaction checks in `p_user.cpp` use.
- `STYLE_Add` maps to `glBlendFunc(GL_SRC_ALPHA, GL_ONE)` → it **does** honor the SetColor alpha (verified), so low alphas keep overlapping shells color-distinct.
- Cvars: `vr_grab_debug` (master), `vr_grab_debug_cone`, `vr_grab_debug_sphere`, `vr_grab_debug_cone_solid` + `vr_grab_debug_sphere_solid` (both NEW, `CVAR`-defined at the top of `hw_weapon.cpp`), `xr_gp_debug`. All wired into the **VR Grab Settings** menu this session, plus new Climb/Two-Hand radius sliders.
- Both solid additions were adversarially swarm-verified → **ship-as-is, 0 blockers.**

---

## 7. What's NOT done — wall-standing (do NOT blind-implement)

Wall tiles only *pull* sideways because GZDoom collision is a world-Z-aligned cylinder clamped to real `floorz`/`ceilingz` — a horizontal "down" has no plane to rest against. The **recommended VR approach** (theorized, grounded in the real tree, not yet built):

1. **Collision — sphere proxy.** On mount, `A_SetSize(radius, ~2*radius, testpos)` (confirmed available, `actor.zs:1331`) → a sphere collides identically in any orientation, and horizontal gravity + native XY wall-collision already rests it at radius off the wall. Invisible cost in VR first-person. **Pure ZScript, no C++.**
2. **Orientation — compose a gravity-frame roll into the viewpoint.** The VR render already speaks roll: `#define ROLL 2`, `mountTransform.rotate(-controllerRoll,0,0,1)`, `vr_hud_fixed_roll`, and the `GetViewShift(FRenderViewpoint&)` hook (all in `hw_vrmodes.cpp`). Composing a `GravityDir`-derived rotation onto the viewpoint basis is small new C++ at a roll-aware seam, NOT a rewrite. `QuatStruct.FromAngles` is native (used in `vr_whip.zs:354`).
3. **Movement — tangent-plane projection.** Extend the Rail Guard override to project desired velocity into the surface tangent plane.
4. **The real hard problem is VR comfort** (world-rotation nausea), not collision — vignette, snap-vs-smooth toggle, player-initiated flips.
5. **180° flip fix:** use `Quat.FromAngles` about an explicit axis, or route floor→wall→ceiling through an intermediate normal. Never interpolate a direct 180°.
6. **Alternative for authored spaces (the battlesphere):** portal-room facets (reuse the portal-stacking work, docs #3–7) — every surface is a real `floorz`, native physics, zero gravity hacks.

Recommended next build: **Tier 0** = sphere-proxy + tangent Rail Guard, no camera roll (world looks tilted but you're comfortable). Pure ZScript, ships fast, tells you in-headset whether magnetized wall-walking *feels* right before investing renderer C++.

---

## 8. Open task & known gotchas

- **Task #5 (needs a headset, can't verify blind):** tile `Scale` factor `XR_BASE_PX` (the SIGL sprite's real pixel size is unknown — grep found no such asset, so Scale-to-world-units may be off) and the FLATSPRITE **roll-sign handedness** (one-line flip if tiles render mirrored). Both are one-liners once you can see them.
- **`xr_gp_capture_h` MUST stay > player radius (~16)** or you oscillate on mount. Menu floor is 18, default 28.
- **nlerp degenerates on a direct 180° flip** (see §2/§7).
- **VR-only silent no-op** in flatscreen — expected, not a bug.
- **`SIGLA0.png` untracked** — must be packed (§4).
- `hw_weapon.cpp` is the one shared-engine file with uncommitted edits — diff shows only additions, zero deletions, so it's safe to merge unless another lane also touched it.

---

## 9. Cvars (all in `CVARINFO`, menu in `menudef.txt` → XRGravityPathOptions + VR Grab Settings)

`xr_gp_`: color, tile_width, tile_length, cast_dist, capture_h, capture_margin, lerp_time, fall_catch, alpha, max_tiles, beam_width, palm_lo(45), palm_hi(135), grow_time(0.15), debug(false), railguard(true).
Debug: `vr_grab_debug`, `vr_grab_debug_cone`, `vr_grab_debug_sphere`, `vr_grab_debug_cone_solid`, `vr_grab_debug_sphere_solid`, `xr_gp_debug`.

---

## 10. Verification status

Static only — **no compile has ever run.** If the rebuild breaks, suspect in order: `p_mobj.cpp` (FallAndSink restructure + 4 gate edits) → `hw_weapon.cpp` (5 new static fns + 2 CVARs) → `vr_gravity_path.zs` (ZScript). Two adversarial swarms cleared the debug-render code; the gravity core rests on the sentinel-safety argument (zero-init DVector3 = byte-identical existing behavior). Full granular record in memory `dxr-gravitydir-core-implemented.md`.
