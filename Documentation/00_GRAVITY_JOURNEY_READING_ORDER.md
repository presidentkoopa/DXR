# Reading order — the Gravity / Portal / Sphere journey

*Everything else in this folder (whip, sword, holster, shader-tweaks, HF_neon) is a different project — skip it for this thread. Read these in order.*

**0. START HERE — [GRAVITY_ENGINE_JOURNEY.md](GRAVITY_ENGINE_JOURNEY.md)**
The one-page summary of the whole arc: the three walls the engine put up, how each got broken, what's actually built and compiled in right now, and what's next (spheres). Read this first for the map, then the numbered docs below for the territory.

---

## Part I — Gravity cubes (can a room's "down" change?)

**1. [GRAVITY_CUBE_THEORY.md](GRAVITY_CUBE_THEORY.md)**
The first investigation. Confirms gravity is a scalar (`Vel.Z -= grav`), not a direction — and theorizes the fix: turn it into a vector.

**2. [GRAVITY_PLAN_AUTOPSY.md](GRAVITY_PLAN_AUTOPSY.md)**
An adversarial red-team of doc #1 — assassins try to kill the plan with real code, a defense rebuts. Verdict: the *maximalist* rewrite is dead, but the *scoped* version (one function) survives and is cheap. This scoped version is what later got built into the engine.

---

## Part II — Portals (can rooms link and rotate?)

**3. [PORTAL_STACKING_ROTATING_CUBES_PLAN.md](PORTAL_STACKING_ROTATING_CUBES_PLAN.md)**
Studies Eternity's portal-group model and FishyClockwork's PolyPortalAssistant (source: `polyportalassistant-v1.3.1/`). Establishes: portal *groups* tile rooms; rotation of a live walk-through portal is the wall neither engine has crossed.

**4. [LIVE_SPINNING_PORTAL_GET_US_THERE.md](LIVE_SPINNING_PORTAL_GET_US_THERE.md)**
"Get us there" — the first assault on that wall. Finds the interactive-portal loophole (renders rotation live, not blocked by the rotation veto) vs. the deep "seamless linked" rewrite.

**5. [PORTAL_WAR_TEAM_VELOCITY.md](PORTAL_WAR_TEAM_VELOCITY.md)**
Army #1's battle report: the cheap path ships a spinning walk-through portal in ~4 days, no C++ required.

**6. [PORTAL_WAR_TEAM_BEDROCK.md](PORTAL_WAR_TEAM_BEDROCK.md)**
Army #2's battle report: where the cheap path visibly breaks (sound, sight, blockmap) — and the minimal *native* rotation-aware design that fixes it for real.

**7. [PORTAL_WAR_VERDICT.md](PORTAL_WAR_VERDICT.md)**
The referee's ruling. Both armies were right about different products: ship the 4-day spinning portal now; the "true seamless" version is a scoped 14-day job (not the 45–70 days first feared) if you ever need it.

*(Reference material used across Part II, not something to read start-to-end: `polyportalassistant-v1.3.1/zscript.zs` — the crossing-carrier mechanism DoomXR's `XR_PolyPortalCarrier` is adapted from; `polyportalassistant-v1.3.1.pk3` / `maps/MAP01.wad` — the proven demo map the loadable `XR_SpinPortal_Demo.pk3` stands on; `eternity-4.06.00/` — Eternity's own portal source, mined for the rotation truth and the group-link model.)*

---

## Part III — Spheres (can you fight on/in one?)

**8. [SPHERE_BATTLEFIELDS.md](SPHERE_BATTLEFIELDS.md)**
The reframe: no true curved geometry, but two flat arenas that render each other as an *inverted sky* gets you "look up and see the ground" for ~20 lines of C++; a rotating planetoid model gets you the outside-of-a-sphere fight for zero C++. **This is the next build.**


BULLSHIT! SHOOT FOR THE MOON. GET ME A CURVE.
---

## Part IV — The hand-cast power (paint gravity, walk it)

**9. [XR_GRAVITY_PATH_POWER.md](XR_GRAVITY_PATH_POWER.md)**
Specs the off-hand, palm-out gravity-painting power — verified surface-normal derivation, the walk/reorient driver. This became the `vr_gravity_path.zs` now in the engine.

**10. [XR_SDF_GRAVITY_RIBBON.md](XR_SDF_GRAVITY_RIBBON.md)**
Fuses the power with the SDF shader and the grapple — the neon-road visual layer, honestly scoped between "beaded now" and "seamless capsule union" (shader-lane, your call).

THIS IS WHY I WANT CURVES, RUNTIME GRAVITY WALKWAY DESIGN
---

## Part V — Seeing it (the debug layer)

**11. [XR_DEBUG_VISUALIZERS.md](XR_DEBUG_VISUALIZERS.md)**
The cones / spheres / rays / colors you turn on to SEE the VR interaction systems — grab reach, catch/climb/two-hand volumes, and the gravity cast. Explains the "particles are invisible in VR" trap that hid all of this, the real-geometry fix, what every shape and color means, and the exact menu/console toggles. Read this when you put the headset on and want to verify anything is actually where the code thinks it is.

## Part VI — Carry-forward (session handoff)

**12. [XR_GRAVITY_HANDOFF.md](XR_GRAVITY_HANDOFF.md)**
The exhaustive handoff written when the gravity lane merged into the unified session — full state of the design model, every file touched, what works vs. deferred (wall-standing), map/actor requirements, cvars, gotchas, and the recommended next steps (Tier-0 sphere-proxy wall-walk; Task #5 in-headset tuning). Start here if you're picking up the gravity system cold. **Build status: compiled CLEAN (exit 0) on 2026-07-03 — the whole GravityDir core + debug visualizers passed their first real compile.**

---

**After #10, the actual code landed** — the native `GravityDir` core, the SDF capsule primitive, and the gravity-path power are all in `E:\DoomXR-work\DOOM_FRESH` now, per doc #0. **As of 2026-07-03 it is BUILD-VERIFIED (compiles clean).**
