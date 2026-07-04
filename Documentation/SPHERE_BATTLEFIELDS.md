# SPHERE BATTLEFIELDS
## Fight on the outside of a sphere. Fight inside a hollow sphere. Look up and see the ground.

**Deliverable for the DoomXR implementer (C++ + ZScript). Tree: `E:/DoomXR-work/DOOM_FRESH`. All line numbers verified against the tree 2026-07-03.**

---

## 1. VERDICT

**Both battlefields ship. Neither needs the months-long radial-collision rewrite.**

| Battlefield | Tier | C++ required | Ships |
|---|---|---|---|
| **A. Inside the sphere** (look up, see the far side's ground, live fights on it) | Real geometry in the dome, mirrored live — *not* a painted sky | **~20 lines** (one renderer flag) + one wadsrc pk3 edit | **First.** 3–5 days to playable |
| **B. Outside the sphere** (planetoid under your boots, Mario Galaxy walk) | Rotate-the-world illusion, analytically-backed combat | **Zero** (pure ZScript + MODELDEF + assets) | Second. 5–8 days to playable |

Ship **A first**: it is one tiny, well-precedented renderer patch riding machinery that already works end-to-end (plane mirrors render sprites today), and it is the money shot. B is zero-C++ but has more *content* work (a float-vertex sphere mesh, quaternion driver, combat seam scripts) and more feel-tuning.

One plan from the earlier grounding is **dead and must not be built**: the "zero-C++ rolled SkyViewpoint" (pass `HWAngles.Roll = 180` during sky portal setup). Adversarial verification killed it three ways — see §2.2. What replaced it is better, cheaper to reason about, and VR-correct.

The gravity core's RADIAL mode is **not on the critical path** for either battlefield. It is the garnish (§3.5): gibs, shell casings, and debris raining "down" onto the planetoid surface. Both arenas keep every fighting actor on a flat, scalar-Z floor.

---

## 2. BATTLEFIELD A: INSIDE THE SPHERE (the money shot)

### 2.1 The shape of the trick

You cannot build a hollow sphere the player walks around inside — collision is scalar-Z (`floorz`/`ceilingz` are heights) and monsters are flat-ground AI. So you build the sphere the way a stage magician builds a levitation: **two flat bowls, each wearing the other as its sky.**

- **Bowl A** (your team): flat floor, gentle sloped rim (native slopes, ≤45°, `P_CheckSlopeWalk` in `src/playsim/p_map.cpp` handles it), ceiling flat = sky.
- **Bowl B** (their team): identical arena, built elsewhere in the map, right-side-up, normal −Z gravity, monsters fighting on its flat floor like it's any Doom map — because it is.
- Bowl A's ceiling sky is a **live skybox portal whose camera sits in Bowl B — rendered vertically inverted.** Look up from Bowl A: you see Bowl B's *ground* overhead, monsters standing on it feet-up-toward-you, muzzle flashes, the works. Bowl B gets the mirror-image arrangement.

Everything below is machinery that exists today, plus one small patch.

### 2.2 Why the "rolled SkyViewpoint" is dead (do not resurrect it)

The earlier grounding claimed you could flip the sky 180° from ZScript because `SetViewMatrix` honors roll. The roll application is real — `src/rendering/hwrenderer/scene/hw_drawinfo.cpp:443` (`mViewMatrix.rotate(angles.Roll.Degrees(), 0,0,1)`) — but the plan fails three independent ways:

1. **In VR, the HMD owns pitch/roll.** `gl/stereo3d/gl_openxrdevice.cpp`, `gl_openvr.cpp`, and `vulkan/stereo3d/vk_openxrdevice.cpp` overwrite `HWAngles.Pitch/Roll` from the headset pose every frame. Anything you inject is stomped.
2. **The live-geometry sky path only takes yaw.** `HWSkyboxPortal::Setup` (`hw_portal.cpp:706–756`) applies the SkyViewpoint actor's *yaw only* — verified at `hw_portal.cpp:729` (`vp.Angles.Yaw += ...`). The actor's pitch/roll never reach the view matrix, and there is no ZScript hook in portal setup.
3. **Geometry: roll can't do the job anyway.** Roll rotates about the view axis. A rolled camera in Bowl B looking up still sees Bowl B's *sky*, rotated. Putting the far side's *ground* overhead requires a **vertical inversion** of the sky view, which no roll produces.

### 2.3 The verified path: the inverted skybox portal (`PORTSF_INVERTED`)

The engine already knows how to render the world vertically inverted, with correct winding, culling, and sprites: **plane mirrors** (reflective floors). `HWPlaneMirrorPortal::Setup` (`hw_portal.cpp:910`) increments `state->PlaneMirrorFlag`, and `SetViewMatrix` negates the vertical axis via `planemult` (`hw_drawinfo.cpp:440,446–447`). Reflective floors render monsters upside-down in the reflection *today*. We borrow that flag inside the skybox portal.

**THE PATCH (~20 lines C++):**

1. Add `PORTSF_INVERTED` to `FSectorPortal::mFlags` (`src/playsim/portal.h`, next to the existing `PORTSF_SKYFLATONLY`/`PORTSF_INSKYBOX`), **or** add a `SkyViewpointInverted : SkyViewpoint` actor class (ZScript side: `wadsrc/static/zscript/actors/shared/skies.zs:37`) and check the class in setup. The flag route is cleaner.
2. In `HWSkyboxPortal::Setup` (`hw_portal.cpp:706`): when the portal carries the flag, `state->PlaneMirrorFlag++` before the `SetupView` call; decrement in `HWSkyboxPortal::Shutdown` (the block that clears `PORTSF_INSKYBOX` at `hw_portal.cpp:754` and `skyboxrecursion--` at `:756`).
3. **Optional stereo restore (1 line):** under the same flag, skip `di->RemoveMultiviewPositionParallax()` at `hw_portal.cpp:740`. Both sky paths deliberately kill positional stereo (`hw_drawinfo.cpp:543`: `rightView[12] = leftView[12]` etc.), which makes the dome an infinitely-far mono mural. The content here is real geometry with real view matrices, so keeping per-eye positions just works. *Honest alternative:* skip this line-item entirely and keep the overhead ground ≥ ~1000 units away — human stereo acuity is ~nil past 20–30 m, and "huge and far" is exactly what a planet interior should feel like.
4. **Chirality note:** a mirror flips handedness (Bowl B appears left-right mirrored overhead). For arena combat nobody will notice; if it ever matters (readable signage overhead), post-multiply a 180° world-X rotation into the multiview uniforms instead of mirroring — but the mirror is the established sprite-safe path. Start with the mirror.

**HMD comfort is intact by construction:** the inversion lives in the *portal's* view matrix only. `FRenderViewpoint::SetViewAngle` (`src/rendering/r_utility.cpp`, called at the top of every portal `SetupView`) recomputes only yaw; HMD pitch/roll pass through untouched. The player's camera never rolls. The *sky* is upside down; the *player* never is.

### 2.4 Per-sector sky + live swap — already pure ZScript

This half needs **zero C++** and is proven by shipping code:

- Per-sector sky resolution: `HWWall::SkyPlane` (`src/rendering/hwrenderer/scene/hw_sky.cpp:135`) resolves the sky *per sector* via the sector's portal; `PORTS_SKYVIEWPOINT` routes to `PORTALTYPE_SKYBOX` (`hw_sky.cpp:187–190`). Only the arena's dome sectors get the trick; the rest of the map keeps its normal sky.
- ZScript assignment precedent: `SkyPicker` (`wadsrc/static/zscript/actors/shared/skies.zs:91`) already writes `CurSector.Portals[sector.ceiling] = boxindex` (`skies.zs:127`) using the exported `Level.GetSkyboxPortal` (`src/playsim/portal.cpp:561`, `DEFINE_ACTION_FUNCTION(FLevelLocals, GetSkyboxPortal)`).
- **Live portal-target swap for free:** the sky camera's position is re-read *every frame* — `hw_portal.cpp:727`, `vp.Pos = origin->InterpolatedPosition(vp.TicFrac)`. Teleporting or gliding the SkyViewpoint actor per tic **is** a live target swap, no field writes. This also gives cheap body parallax: mirror the player's XY (scaled) onto the SkyViewpoint each tic and the overhead world shifts as they physically walk.
- One scope caveat: `Sector.Portals` is `native internal readonly` (`wadsrc/static/zscript/mapdata.zs:483`), writable from gzdoom.pk3 only. DoomXR builds its pk3 from in-tree wadsrc, so either drop the qualifier or ship a tiny helper class *inside wadsrc* that does the assignment. Pure pk3 edit — the user already rebuilds this pk3 routinely.

### 2.5 The equator travel seam (getting from Bowl A to Bowl B)

Crossing the "equator" is a **line portal**, the established pattern:

- `FLinePortal` (`src/playsim/portal.h`) carries `mAngleDiff`/`mCosRot`/`mSinRot`; `P_TranslatePortalXY`/`P_TranslatePortalVXVY`/`P_TranslatePortalAngle` (`src/playsim/portal.cpp`) rotate position, velocity, and facing on passage. Set type `PORTT_INTERACTIVE` or `PORTT_LINKED` (Line_SetPortal, special 156).
- Dress the crossing as a canyon/tunnel at the arena rim ("walk around the sphere's waist"). With `mAngleDiff = 180°` the traveler exits into Bowl B heading the mirrored way — which matches what they saw overhead.
- The proven spinning walk-through portal (interactive portal + polyobject, `EV_RotatePoly` in `src/playsim/po_man.h`) is available if you want the crossing to *feel* like being swept around the equator.
- The moment they cross, they're just standing in another flat Doom arena at −Z gravity, and the *other* bowl is now overhead. The illusion self-completes.

### 2.6 Artillery relay across the void

Lob a rocket "up" in Bowl A; it should come *down* in Bowl B. This is ZScript-only:

- Hitscans already stop at sky: on `TRACE_HitSky` (`src/playsim/p_trace.h`), puffs only spawn if `flags3 & MF3_SKYEXPLODE` (checked at `src/playsim/p_mobj.cpp` in `P_ExplodeMissile` and puff spawn paths). So bullets can't cheat across the void — correct: the far side is *kilometers* away in fiction.
- Projectiles: subclass with a ceiling-contact check (missile ceiling handling in `P_ZMovement`, `src/playsim/p_mobj.cpp:2841+`, or override `SpecialMissileHit`; belt-and-suspenders via a `WorldThingDied` EventHandler, `src/events.cpp`). On dome contact: record XY relative to arena center, kill the original quietly, spawn the twin projectile at Bowl B's dome apex at the mirrored XY with `Vel.Z` negated and XY velocity mirrored, after a flight-time delay proportional to fictional void distance.
- Because the dome shows Bowl B live, the observer *watches the shot they just fired arc down onto the enemy's ground overhead.* That's the sports-bar replay no other Doom map has.

### 2.7 What the player sees overhead — and the rim problem

Straight up: Bowl B's floor, live monsters/players standing on it, inverted. **This part is free once the patch lands.**

The honest debt is the **rim** — three seams, all solved architecturally (zero C++):

1. **Inverted-wall band:** at grazing elevation the sky stencil (which also covers upper sky-walls, `HWWall::SkyLine`, `hw_sky.cpp:219+`) shows Bowl B's *walls* upside-down butted against Bowl A's upright walls. **Fix: raise Bowl A's rim wall so sky is only exposed above ~35–45° elevation** — from there up the view is Bowl B's ground, which is the content you want.
2. **Parallax shear:** local walls move with the head, sky content doesn't (unless you apply §2.3.3). The junction "swims." Same fix — occlude the junction; plus put an emissive "equator band" (glow ring / fog bank / void gradient — GITD aesthetic slot) around the SkyViewpoint's horizon inside Bowl B so anything leaking at grazing angles is featureless atmosphere.
3. **Two skies meeting:** never give a dome sector and an ordinary `F_SKY1` sector a shared sightline (airlock geometry between arena and the rest of the map), or the per-surface sky split shows a hard cut.

Also: make both bowls **circularly symmetric** so yaw misalignment can't read as a seam, and force `gl_noskyboxes = 0` in mod defaults — that CVAR (`hw_sky.cpp:39,143`) silently degrades the whole trick to a flat sky.

### 2.8 Perf & recursion — verified affordable

- **One extra scene pass, not one per eye:** the multiview path renders the scene once for both eyes (`src/rendering/hwrenderer/scene/hw_entrypoint.cpp`, `renderSceneThisEye = !useMultiviewScene || eye_ix == 0`); portal re-setups re-derive the right-eye matrix from the left-eye delta (`hw_drawinfo.cpp:466+`).
- **Mutual recursion self-terminates gracefully:** `PORTSF_INSKYBOX` is set during a portal's own render (`hw_portal.cpp:723`) and `hw_sky.cpp:228` demotes a re-entered portal to a plain sky — no HOM, no black hole; hard cap `skyboxrecursion >= 3` (`hw_portal.cpp:711`). Worst frame staring straight up through both domes: main + twin + one nested twin ≈ 2 extra passes; normally 1. Same cost class as one mirror floor.
- Budget hygiene: keep Bowl B's visible geometry modest; place its SkyViewpoint so Bowl B's own dome fills little of the sky camera's view; if profiling ever flags the nested pass, give the innermost view a static texture.

### 2.9 Recipe, patch deltas, days

**Patch deltas (all C++ listed; everything else is ZScript/wadsrc/map):**
- `src/playsim/portal.h` — add `PORTSF_INVERTED` flag to `FSectorPortal`.
- `src/rendering/hwrenderer/scene/hw_portal.cpp:706–756` — `HWSkyboxPortal::Setup/Shutdown`: toggle `state->PlaneMirrorFlag` around `SetupView` when flag set; optionally skip `RemoveMultiviewPositionParallax()` at `:740` under the flag.
- `wadsrc/static/zscript/mapdata.zs:483` — relax `internal readonly` on `Sector.Portals` (or add an in-wadsrc helper). Optionally same for `SectorPortal` fields in `doombase.zs:434`.
- Plumbing to *set* the flag: either a `SkyViewpointInverted` actor checked in `Setup`, or arg/UDMF field on the portal — implementer's choice, trivial either way.

**Build steps:**
1. Land the patch. Sanity-test flatscreen: a box room whose ceiling sky shows a second room inverted. (Camera-texture path — `TexMan.SetCameraToTexture`, already exported at `src/scripting/vmthunks.cpp:71` — is your *flatscreen screenshot-verification* tool per the no-launch-VR workflow; it is **not** a VR deliverable, see §4.)
2. Build Bowl A + Bowl B: identical circular arenas, flat floors, sloped rims, rim walls occluding sky below ~40°. Place `SkyViewpointInverted` actors centered high over each bowl; bind with `Level.GetSkyboxPortal` + `Portals[ceiling]` assignment at map load.
3. Equator tunnel with interactive line portal (`mAngleDiff` 180°).
4. Artillery relay EventHandler + projectile subclass.
5. Equator glow-band dressing in each bowl (GITD assets), fog/`skyfog` melt at the last degrees.
6. User VR pass: stare-up comfort, rim seam hunt, relay timing feel.

**Days:** patch + flatscreen proof **1**; twin arenas + binding **1–2**; equator portal + relay **1**; dressing + VR iteration **1–2**. **Total: 3–5 days to a playable slice.**

---

## 3. BATTLEFIELD B: OUTSIDE THE SPHERE (planetoid)

### 3.1 The shape of the trick

Mario Galaxy, comfort-corrected: **the player never moves — the planet does.** The player stands on an invisible flat disc at world −Z, full normal physics, guns, monsters. Beneath them, a huge sphere *model* rotates so the surface scrolls under their feet. Props riding the surface are repositioned by the same rotation. Walking forward = the planet rolling backward. The horizon curves away in every direction because it genuinely is a sphere — just not one you collide with.

This is buildable **today, zero C++**, but the adversarial pass hardened five things that are *mandatory*, not polish:

### 3.2 The five load-bearing corrections

1. **The sphere must be OBJ or IQM, never MD3.** MD3 stores vertices as `int16/64` — `src/common/models/models_md3.cpp:239–241` (`LittleShort(vt[ii].x) / 64.f`): ±512-unit model-space cap, 0.0156-unit quantization that becomes visible *crawling ripple* on a scaled-up smooth curve, plus byte-normal banding. OBJ/IQM loaders exist in-tree (`src/common/models/models_obj.cpp`, `models_iqm.cpp`) and store float32. ~30–60k tris is plenty — it fills the screen regardless.

2. **`RenderRadius sphereRadius` on the core actor, or the planet vanishes.** The renderer only draws an actor if a sector in its `touching_renderthings` list is visited by the BSP walk (`src/rendering/hwrenderer/scene/hw_bsp.cpp:904,1040`); that list is built from `RenderRadius()` at link time (`src/playsim/p_maputl.cpp:498`). Default render radius means origin-subsector-only linking — pitch down at the far slope and the entire planet pops out of existence. Set the ZScript `RenderRadius` property to the sphere radius; the core never translates, so the wide link is a one-time cost.

3. **`+INTERPOLATEANGLES` is a nausea bug-fix, not polish.** Angle interpolation is OFF by default — `src/rendering/hwrenderer/scene/hw_sprites.cpp:1105`: *"disabled because almost none of the actual game code is even remotely prepared for this. If desired, use the INTERPOLATE flag."* Without `RF_INTERPOLATEANGLES`, the full-field ground plane snaps at 35 Hz inside a 90–120 Hz HMD — vomit-grade judder. With it, interpolation is wrap-safe (`AActor::InterpolatedAngles`, `src/playsim/actor.h:1507`) and `p_tick.cpp` (comment at `:151`) snapshots `Prev*` for *all* actors each tic so indirect movement interpolates correctly.

4. **Orientation is a quaternion, not Euler `+=`.** Walking rotates the sphere about the horizontal axis *perpendicular to the player's current heading* — an axis that changes whenever they turn. Euler accumulation doesn't compose arbitrary-axis rotations; after the second heading change the terrain drifts and gimbals. The engine exports quaternions to ZScript: `struct QuatStruct native` (`wadsrc/static/zscript/engine/base.zs:961`) with `FromAngles`/`AxisAngle`/`SLerp` (bound in `src/scripting/vm/vmnatives.cpp` or thereabouts — grep `QuatStruct` bindings). Per tic: `q = Quat.AxisAngle(walkAxis, moveSpeed / R) * q`, then decompose `q` to Yaw/Pitch/Roll **matching the renderer's exact order and signs** — `rotate(-yaw, 0,1,0)` → `rotate(pitch, 0,0,1)` → `rotate(-roll, 1,0,0)` at `src/r_data/models.cpp:166–168` — a one-time ~15-line atan2/asin derivation. Write via `A_SetAngle/SetPitch/SetRoll` with interpolation flags.

5. **MODELDEF flags:** `USEACTORPITCH USEACTORROLL` (processed at `models.cpp:132,138`) so the actor drives the mesh; `CORRECTPIXELSTRETCH` (`models.cpp:154,195`; `src/r_data/models.h:61`) or the 1.2 pixelstretch is applied *after* rotation and the sphere visibly breathes/squashes each revolution; `FORCECULLBACKFACES` (`models.h:62`) to GPU-cull the inside hemisphere; `NOPERPIXELLIGHTING` (`models.h:58`) if dynlight-heavy fights sit on it — bake shading into the skin (fits the GITD baked-glow aesthetic).

### 3.3 The ground you actually stand on

- **Invisible FF_SOLID 3D-floor disc** (no RENDER flags — `src/playsim/p_3dfloors.h`) at the sphere's apex tangent plane. Arena radius 256–512 on a sphere of R ≥ 4096 keeps the curvature drop `d = r²/2R` under ~2 units across the disc — below perception.
- **Author the walk band flat:** the great-circle strip that ever passes under the arena is constant-radius, low-relief in the mesh. For real hills, drive the disc's control-sector floor height to `h(θ)` each tic — a native interpolated plane move, so relief becomes *physically real* under the feet as it rolls in.
- **Edges:** invisible blocking lip (block-everything wall or taller 3D-floor ring) so monsters and players don't step off the disc into the model's interior; a ZScript reaper despawns debris past the rim.
- **Props ride the same quat:** store each rider's offset in sphere-local space; per tic, `SetOrigin(center + q.Rotate(offset), true)` — `moving=true` preserves interpolation (`p_maputl.cpp`, only clears interpolation when `!moving`), `+NOBLOCKMAP +NOGRAVITY +INTERPOLATEANGLES` keeps relink cost near-zero. Cap ~100 live riders. Chord-vs-arc interpolation error at believable walk speeds: ~0.002 units. Nothing.
- **Horizon spawn-in:** monsters teleport-in just past the visible horizon (~`√(2·R·h_disc)` units out along the surface, i.e., where the disc's tangent line grazes the sphere) and walk *up* onto the disc as the world rolls them into view. From the player's seat: enemies come over the planet's horizon. That's the fantasy, delivered by a spawn spot and a rotation.

### 3.4 Combat seam: the terrain is an analytic sphere

Models receive **no traces and no decals** — a shot past the disc edge sails through the visual terrain and puffs on the real sector floor deep "inside" the planet. But the terrain is a *perfect sphere*, so:

- Every shot gets a **ZScript ray–sphere solve** (closed form, ~10 flops): intersect the shot ray with the sphere, spawn puff/scorch as a flat-sprite oriented tangent at the solved point (parent it to the rotation so it rides the surface).
- 2–3 concentric invisible stepped 3D-floor rings around the disc so near-field splash damage and bouncy projectiles land sanely.
- Hitscans get the same solve via a `WorldHitscan`-adjacent hook or by giving weapons a custom puff whose `SpecialMissileHit`/spawn logic re-anchors to the sphere point.

### 3.5 Where the gravity core's RADIAL mode fits

Not on the critical path — the fight happens on the flat disc. RADIAL (away/toward an origin actor, from the in-flight gravity core spec) is the **rain layer**: gibs, casings, dropped items, and particles spawned above the horizon get RADIAL-toward-center gravity so they visibly *fall to the planet's surface* wherever they are on the visible hemisphere, then hand off to a rider-prop that pins them to the rotating skin. It's the detail that makes the planet read as a *place* instead of a screensaver. Ship the battlefield without it; slot it in the week RADIAL lands.

### 3.6 Feel — the honest part

- Ground optic flow of world-rotates-under-you is **mathematically identical to smooth locomotion**. No comfort gain for translation. The genuine, non-negotiable win is that the horizon **never tilts** (§5).
- **Never spin the planet in yaw.** A yaw spin under a stationary player rotates the entire visual field = forced smooth turning = the single worst VR vection case. Walking drives **pitch about the horizontal axis perpendicular to heading, passing under the player's actual XY** (recompute per tic — roomscale steps move the head off disc center); all turning is real HMD yaw or snap turn.
- **Sky toggle:** fixed skybox = comfort mode (a stable background is the standard vection damper) but reads "treadmill under a dome"; counter-rotating skybox (SkyViewpoint machinery, §2.4) = fidelity mode. Ship both, default comfort, per [hf-default-features-on] judgment call — the *core* here is the fixed sky.

### 3.7 Recipe, days

1. Sphere mesh (OBJ/IQM, float verts, baked shading, authored walk band) + MODELDEF (`USEACTORPITCH USEACTORROLL CORRECTPIXELSTRETCH FORCECULLBACKFACES`). — **1–2 days** (asset-dominated)
2. `PlanetoidCore` ZScript: quat state, walk-axis-from-input, decompose-to-Euler writer, `+INTERPOLATEANGLES`, `RenderRadius R`. — **1 day** (the decompose derivation is the only thinking)
3. Disc: invisible FF_SOLID + blocking lip + `h(θ)` control-sector driver. — **0.5 day**
4. Riders + horizon spawner + debris reaper. — **1 day**
5. Ray–sphere combat seam (puffs, scorches, splash rings). — **1 day**
6. VR feel pass: rotation speed vs. move input, sky toggle, judder hunt. — **1–2 days**

**Total: 5–8 days to a playable slice. Zero C++.**

---

## 4. WHAT IS ILLUSION vs REAL — the honest ledger

| Thing | Real or illusion | The truth |
|---|---|---|
| **A: Ground overhead with live fights** | **REAL geometry, really rendered** | The far arena is a genuine place; monsters really fight there; the dome renders it live every frame through a mirrored view matrix. Not a video, not a skybox painting. |
| **A: "It's one sphere"** | **Illusion** | It's two flat bowls that wear each other as sky. You can never fly across the void; the equator tunnel is the only road, and it's a portal. |
| **A: Stereo depth of the overhead world** | **Mono by default; real stereo is a 1-line opt-in** | Sky paths strip positional parallax (`hw_portal.cpp:740` → `hw_drawinfo.cpp:543`). Skip that call under the flag for true depth, or keep the far side ≥1000 units out where mono is imperceptible anyway. |
| **A: Overhead world is left-right mirrored** | **Real artifact of the mirror trick** | Chirality flips. Invisible in arena combat; fixable later with a world-X-rotation matrix variant if signage overhead ever matters. |
| **A: Shot arcs across the void** | **Illusion (relay)** | The projectile dies at dome contact; a scripted twin spawns falling from the other apex. Timed right, no one can tell. |
| **A: The rim** | **The one visible debt** | Inverted walls meet upright walls with parallax shear at grazing angles. Solved by occlusion architecture + glow band, not by code. Budget map-craft for it. |
| **B: The planet** | **Illusion (a model), with real physics on top** | You stand on an invisible flat disc; the sphere is a prop with no collision. But the disc is real Doom floor: real footing, real monsters, real explosions. |
| **B: Walking around the planet** | **Illusion** | You never move; the planet rolls. Retinal flow identical to smooth locomotion — no comfort *bonus* for movement, only the no-tilt win. |
| **B: Bullets hitting the terrain** | **Scripted-real** | Engine traces ignore models; every impact is an analytic ray–sphere solve + tangent flat-sprite. Indistinguishable if the solver is right, and the sphere makes the solver exact. |
| **B: Enemies over the horizon** | **Staged, then real** | Spawned just out of sight, rolled into view, then they're ordinary flat-ground monsters on the disc. |
| **Both: monsters** | **Always flat-ground 2D AI** | Nobody wall-walks. Nobody was promised wall-walking. |
| **Both: gravity** | **Scalar −Z everywhere that matters** | RADIAL mode is decoration (debris rain), not foundation. |

---

## 5. VR COMFORT WINS

Both designs are built on the same theorem: **the player's vestibular system is a stakeholder with veto power, and it only accepts one message — "the floor is level and you are upright."**

- **Battlefield A:** the inversion lives entirely in the *portal's* view matrix (`PlaneMirrorFlag` scoped to `HWSkyboxPortal::Setup/Shutdown`). HMD pitch/roll pass through every portal `SetupView` untouched (yaw-only recompute in `FRenderViewpoint::SetViewAngle`). Both bowls are ordinary −Z floors. The player *looks up* at an upside-down world with their own neck — which is exactly how looking up works, and costs nothing vestibularly. Sky content lacking head-parallax is even mildly *stabilizing* (distant-background effect).
- **Battlefield B:** the player actor never rotates, never rolls, never translates. The horizon line stays glued to gravity. Rotation is confined to pitch-under-feet (treadmill flow — the most tolerated artificial motion) and never yaw (the least tolerated). Snap-turn and real head-turn own all rotation.
- **The framing that matters:** given the hard constraint — physical floor can never tilt, sustained camera roll = nausea — *moving the world under a Z-up player is the correct architecture, not a compromise.* A "true" 6-DoF spherical-gravity engine that rolled the VR camera to match surface normals would be **worse** even if collision supported it for free. These designs aren't the fallback from the dream; on a headset, they *are* the dream, minus the vomit.

---

## 6. BUILD ORDER

Slots into the gravity-zone runbook and the portal-war outcomes (portals translate + yaw; target-swap + Ghost-Room twins proven; spinning walk-through proven; gravity core RADIAL in flight).

**Phase 1 — Battlefield A slice (days 1–5), ships first:**
1. `PORTSF_INVERTED` patch (`portal.h` + `hw_portal.cpp:706–756`) + wadsrc `readonly` relax (`mapdata.zs:483`). One build — respect the multi-session lane discipline: these files are renderer/playsim, **not** the user's shader lane (`.fp`/gldefs/`*_shader.cpp`/`hw_renderstate.h`), so clear to touch, but coordinate the single build slot.
2. Flatscreen proof: box room, inverted second room overhead. Screenshot-verify via camera-texture if needed (`TexMan.SetCameraToTexture`, `vmthunks.cpp:71` — its *only* job now; it is not a VR path).
3. Twin bowls + `SkyViewpointInverted` binding + equator tunnel portal.
4. Artillery relay handler. First playable: **stand in Bowl A, look up, watch imps die on the ceiling of the world, lob a rocket into their sky.**
5. User VR pass; rim-seam architecture iteration.

**Phase 2 — Battlefield B slice (days 6–13), zero C++, can overlap Phase 1's map-work days:**
1. Sphere asset + MODELDEF flags; `PlanetoidCore` quat driver; disc + lip. First playable: **stand still, roll the world, watch the horizon wheel.**
2. Horizon spawner + riders + ray–sphere combat seam. Second playable: **hold the pole of a planet against monsters cresting the horizon.**
3. Sky toggle + feel tuning with the user in the headset (assistant drives every tweak, per protocol).

**Phase 3 — convergence (when gravity core RADIAL lands):**
- Debris/gib rain onto the planetoid (B §3.5); away-from-center "inside-sphere down" experiments feed back into A's fiction.
- Stretch goal that needs no new tech: **put Battlefield B in Battlefield A's sky** — the twin bowl's SkyViewpoint gazing at a rotating planetoid model. Fight in the hollow sphere while a live planet war turns overhead. Every piece of that sentence is already on this page.

**Kill-switches / verification gates:**
- Gate A on the flatscreen inverted-room proof before any map-craft.
- Gate B on a 5-minute judder test (`+INTERPOLATEANGLES` on vs. off, user in headset) before building content on the sphere.
- Force `gl_noskyboxes 0` in mod defaults; version every rebuilt pk3 per standing rule.