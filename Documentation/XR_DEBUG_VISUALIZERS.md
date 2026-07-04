# XR Debug Visualizers — cones, spheres, rays, colors

*Doc #11 in the gravity series. This one is not about the gravity power itself — it's the **debug layer** you turn on to SEE what the VR interaction systems are doing: where your grab reaches, where catch/climb/two-hand trigger, and where the gravity power casts. Everything here is opt-in, drawn as real geometry, and safe to ship off.*

---

## 0. The one thing to know first: particles are invisible in VR

DoomXR's hardware/stereo renderer has **no particle draw path**. Anything drawn with `P_SpawnParticle` (or ZScript `Level.SpawnParticle` / `A_SpawnParticle`) shows on a flat desktop screen but **never reaches the VR eyes**.

This is *why you could never see the grab-glove debug*: the engine's original `vr_grab_debug` drew its cone and sphere with `P_SpawnParticle` (p_user.cpp ~1619/1638/1651). The toggle worked, the code ran — you just saw nothing in the headset.

**The fix, and the rule for all VR debug forever:** draw with **real geometry** (triangle strips / tubes), never particles. Everything below is real geometry. It renders in both eyes.

---

## 1. The three primitives

Everything is built from one line primitive — a thin camera-facing **tube** (`DrawDebugTube`, factored out of the laser-beam code). From that:

| Primitive | Built from | Used for |
|---|---|---|
| **Ray / line** | one tube | the aim direction itself |
| **Cone** | wireframe = 4 edge lines + 2 rings; solid = 2 triangle strips (lateral + base cap) | directional reach volumes |
| **Sphere** | wireframe = 3 orthogonal rings; solid = UV-sphere, 10 latitude bands | proximity volumes |

Every shape can draw as **wireframe** (crisp outline) and/or **solid** (faint additive glow fill). You choose per-shape.

---

## 2. The "ray": what the cones are built around

Each hand has an **aim ray** — `GetLaserBeamControllerDirection(hand)` — the same direction the laser sight uses. It's the spine of the grab cone: the cone is just that ray widened by the grab angle out to the grab distance.

The **gravity power** casts a similar ray from the *off-hand* (an off-hand `LineTrace` with `TRF_ISOFFHAND`), gated by the palm-out gesture rather than a button. Its debug cone is the narrow orange one.

So when you see a cone, read it as: *"this is the ray my hand is pointing, and how wide/far it counts."*

---

## 3. What every shape and color MEANS

This is the decoder ring. Colors are fixed and semantic — same color always means the same thing.

### Cones (directional — a ray widened)
| Cone | Color | Angle / length from | Meaning |
|---|---|---|---|
| Grab reach, both hands | 🔵 cyan | `vr_grab_cone_angle` × `vr_grab_max_dist` | The funnel that decides which **far** item you're pointing at to pull. |
| Gravity cast, off-hand | 🟠 orange | narrow 6° × `xr_gp_cast_dist` | Where the palm-out gravity power will paint tiles. Only with the gravity debug on. |

### Spheres (proximity — a distance test made visible)
| Sphere | Color | Radius | Meaning — reach in and… |
|---|---|---|---|
| Catch / snatch | 🟢 green | `vr_catch_radius` (24) | …grab a near item / snatch a bullet. Both hands. |
| Climb | 🔵 blue | `vr_climb_radius` (32) | …grip a climbable surface. Both hands. |
| Two-hand | 🟡 yellow | `vr_twohand_radius` (8) | …if your *off*-hand enters this bubble on the main hand, the weapon two-hand-stabilizes. Main hand only. |

**The mental model:** *grab-at-a-distance is the **cone**; the up-close interactions are the **spheres**.* Every sphere is drawn **exactly where the game runs its `distance ≤ radius` test** — so if an interaction isn't triggering, the sphere tells you whether your hand was actually inside the volume. That's the whole point.

---

## 4. Turning it on

### From the menu (do this — no console in the headset)
- **VR Options → VR Grab Settings**
  - *Grab Debug* — master on/off
  - *Aim Cones* / *Interaction Spheres* — which shapes
  - *Solid Fill Cones* / *Solid Fill Spheres* — wireframe-only vs. wireframe + glow fill
  - *Interaction Radii* → *Climb Reach*, *Two-Hand Reach* — resize those spheres (and their interactions)
- **VR Options → Gravity Path → Draw Debug Overlay** — the orange gravity cast cone + tile markers

### From the console (equivalent)
```
vr_grab_debug 1              // master: cones + spheres
vr_grab_debug_cone 1         // aim cones
vr_grab_debug_sphere 1       // interaction spheres
vr_grab_debug_cone_solid 1   // fill the cones (0 = wireframe only)
vr_grab_debug_sphere_solid 1 // fill the spheres (0 = wireframe rings only)
xr_gp_debug 1                // gravity cast cone + path markers
```
All default to a sensible state: the sub-toggles default **on**, so `vr_grab_debug 1` alone lights up everything.

---

## 5. How it renders (and why it's trustworthy)

- **Real geometry, both eyes.** Drawn in `DrawXRDebugCones` → `DrawLaserSightWorld`, called at hw_drawinfo.cpp:1308 inside `DM_MAINVIEW`, **once per eye**, after the world and before the wheel. Not gated by any laser setting.
- **Additive glow that honors alpha.** Render style is `STYLE_Add` = `glBlendFunc(GL_SRC_ALPHA, GL_ONE)` — so the low fill alphas (0.07–0.22) actually attenuate; overlapping shells at one hand stay color-distinct instead of blowing out to white. Additive is order-independent, so no sorting needed.
- **Occluded by the world (depth test on, depth write off).** The shapes sit at true world depth — a sphere behind a wall is hidden, which keeps their *position* honest. (If you ever want see-through-walls debug, it's a one-line `EnableDepthTest(false)`.)
- **Drawn at the real hand positions.** Centers are `AttackPos` / `OffhandPos`, which in the VR active path are overwritten with the true per-hand controller translations — the same source the grab/catch/climb checks read. The viz is truthful, not approximate.

---

## 6. Limits (honest)

1. **VR only.** The whole thing early-returns unless `OverrideAttackPosDir` is set (real VR hand tracking). Flatscreen shows nothing — correct, but know it when testing.
2. **The throw-trajectory arc is still particles** — so the throw arc is desktop-only, not yet ported to geometry. Everything else (cones, spheres) is VR-visible.
3. **The grab cone is big.** `vr_grab_max_dist` defaults 500u, so its solid fill is a large, deliberately *faint* (alpha 0.07) cyan haze. That's intentional — turn *Solid Fill Cones* off for a clean wireframe funnel if it's distracting.

---

## 7. Files

| File | What's in it |
|---|---|
| `src/rendering/hwrenderer/scene/hw_weapon.cpp` | All the geometry: `DrawDebugTube`, `DrawDebugWireCone`, `DrawDebugWireSphere`, `DrawDebugSolidSphere`, `DrawDebugSolidCone`, `DrawXRDebugCones`; the `vr_grab_debug_*_solid` cvars |
| `src/playsim/p_user.cpp` | The **actual** grab/catch/climb/two-hand interaction checks (the source of truth the spheres mirror); the old particle-based debug (desktop only) |
| `wadsrc/static/menudef.txt` | The VR Grab Settings toggles + Interaction Radii sliders |
| `hw_vrmodes.cpp` / `p_actionfunctions.cpp` | Definitions of `vr_grab_debug*`, `vr_*_radius` cvars |

---

## 8. Verification

Because there's no headless compile here, the new geometry was checked by two adversarial review swarms reading the real source against the proven laser-beam / tube precedents:
- **Solid spheres** — 5 lenses (mesh topology, vertex API, blending, compile/link, VR truthfulness) → **ship-as-is, 0 blockers.** Key finding: `STYLE_Add` does honor the alpha (so no white-out).
- **Solid cones** — 2 focused lenses (shape fidelity vs the wireframe cone, compile/wiring) → **ship-as-is, 0 blockers.** The solid cone's rim math is line-identical to the wireframe cone, so the fill sits exactly under the outline.

Neither is compiled yet — first real compile rides the next engine rebuild. If anything errors, it's in `hw_weapon.cpp` and it's a localized fix.
