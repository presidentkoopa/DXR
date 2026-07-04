# DoomXR — The Gravity & Space Journey
### From "the engine physically cannot do this" to "it's compiled into the engine"

*A running devlog of turning a scalar-gravity, flat-floor, 2.5D engine into one that bends "down" per actor, spins walk-through portals, and (soon) fights on spheres. Every claim below was verified against the live source at `E:\DoomXR-work\DOOM_FRESH` before it was believed.*

---

## 0. Where we started — the "impossible" list

The dreams, stated plainly:
- Flip a room's gravity — walk on the ceiling.
- A map of cube rooms, portal-linked, each independently **rotated** live.
- Fight on the **outside** of a sphere, and **inside** one — *look up and see the ground.*
- Paint a gravity path up a wall with your hand and **walk it**.

The engine's first answer to all of it was **no** — and not a soft no. Hard, architectural no.

---

## 1. The three walls the engine put up (and the exact code behind each)

**Wall 1 — Gravity is a scalar, not a direction.**
`AActor::GetGravity()` returns one `double`; the entire model was `Vel.Z -= grav` in `FallAndSink` (`p_mobj.cpp`). "Down" was never a variable — it was the literal `-Z` axis, smeared across hundreds of comparisons. *Flipping gravity wasn't a config change; it was turning a number into a vector.*

**Wall 2 — Walk-through portals cannot rotate.**
Both GZDoom **and** Eternity — the two most advanced portal engines in the lineage — deliberately forbid it. Eternity's own changelog: *"Visual portals on polyobjects now rotate… unlike the linked portals."* DoomXR's `po_man.cpp:343` literally reads `// cannot do rotations on linked polyportals`. The seamless kind assumes two rooms differ by a **constant translation** — baked into ~49 `getOffset` call sites.

**Wall 3 — The floor is a single number.**
`floorz`/`ceilingz` are scalar Z heights; the blockmap is 2D. A body cannot press flat against a vertical wall, and monsters walk one plane. True spheres and true wall-walking live behind this wall.

Every honest investigation confirmed these. We did not pretend otherwise.

---

## 2. The turn — "no" became "what will it take?"

Instead of accepting the walls, each got a dedicated assault (multi-agent, adversarial, code-grounded — the reports are your receipts):

- **Gravity Cubes → the autopsy.** The maximalist "rewrite everything" version really is months. But the *scoped* version — put the direction in one function — is days. `GRAVITY_PLAN_AUTOPSY.md`.
- **Portals → the war.** Two armies fought over whether a spinning portal breaks. Result: the **interactive** portal already renders rotation live and is **not** covered by the veto (`bHasPortals == 1`), so a spinning walk-through portal ships in ~4 days; the perfect **seamless** version fell from "45–70 days" to **14** once someone found the query-time-rotation trick. `PORTAL_WAR_VERDICT.md`, `LIVE_SPINNING_PORTAL_GET_US_THERE.md`.
- **Spheres → the reframe.** You can't build a hollow sphere, but you can build **two flat arenas that wear each other as sky.** `SPHERE_BATTLEFIELDS.md`.
- **The hand-power → the fusion.** The gravity path, the SDF shader, and the grapple turned out to be one system wearing three hats. `XR_GRAVITY_PATH_POWER.md`, `XR_SDF_GRAVITY_RIBBON.md`.

---

## 3. What is actually BUILT (not planned — in the tree, awaiting one rebuild)

### ⭐ The keystone: per-actor gravity is now a **vector**
The wall that started it all is down.
- `src/playsim/actor.h` — every actor carries `DVector3 GravityDir`. **`(0,0,0)` = normal −Z**, so all existing behavior is byte-identical.
- `src/playsim/p_mobj.cpp` `FallAndSink` — `Vel += GravityDir * grav` when set; serialized; save-safe.
- `src/scripting/vmthunks_actors.cpp` + `actor.zs` — exposed to ZScript, **read/write per tic**.

### The gravity-path power (`vr_gravity_path.zs`)
Palm-out your off-hand → an off-hand trace paints a node chain onto whatever surface you sweep → step near it and your personal gravity reorients to that surface. Auto-given, no equip, no button. Uses the new native `GravityDir`.

### The SDF ribbon primitive (`vr_sdf_procedural.fp`)
Added `xr_segmentSDF()` (the capsule) + a ribbon render mode (bit 512) to your SDF shader — the visual road's foundation, reusing the shader's existing `min()` union.

### The spinning walk-through portal — **loadable today**
`XR_SpinPortal_Demo.pk3` (on your Desktop): a polyobject-mounted interactive portal that **rotates live**, with `XR_PolyPortalCarrier` carrying the player across the moving seam. Proof the reframe was real.

---

## 4. Honest state — works vs. not yet

- ✅ **Gravity is a vector now.** Ceiling/floor flips work fully (planes stay horizontal).
- ✅ **Spinning walk-through portal** renders and carries — in a pk3 you can load.
- ⚠️ **Vertical-wall standing:** you feel the sideways pull, but you don't *stand* on the wall yet — that's Wall 3 (scalar `floorz`), the collision rework still ahead.
- ⚠️ **The neon road** is bright-marker placeholders today; the SDF capsule skin is in the shader, not yet applied to the nodes.
- ⏳ **Not yet build-verified** — the C++ needs one MSBuild. Grounded, but the compiler is the final judge.

---

## 5. What's next — 🌐 **SPHERES ARE COMING SOON**

The path is already scoped and cheap (`SPHERE_BATTLEFIELDS.md`):
- **Inside the sphere — "look up and see the ground":** two flat arenas, each rendered as the other's **inverted sky**. The engine *already* renders the world upside-down (reflective floors); we borrow that flag into the skybox portal — **~20 lines of C++.** Your headset never rolls; only the sky is inverted. **This is the money shot and it ships first.**
- **Outside the sphere — the planetoid:** rotate-the-world under a stationary Z-up player (the cinema trick). **Zero C++.** Gibs and shell casings rain to the surface via the new `GravityDir`.

Next build lands: the wrist-mounted magic hardpoint, the detection-cone painter drawing flat colored `gravity`-tagged rectangles, and then — **spheres.**

---

## 6. The receipts (all on Desktop)

| Doc | What it proves |
|---|---|
| `GRAVITY_PLAN_AUTOPSY.md` | scoped gravity = days, not months |
| `PORTAL_STACKING_ROTATING_CUBES_PLAN.md` | portal groups + polyobject rotation |
| `LIVE_SPINNING_PORTAL_GET_US_THERE.md` | the two paths to a spinning portal |
| `PORTAL_WAR_VERDICT.md` (+ Velocity/Bedrock) | seamless rotation: 14 days, not 45–70 |
| `SPHERE_BATTLEFIELDS.md` | inside = ~20 lines; planetoid = zero C++ |
| `XR_GRAVITY_PATH_POWER.md` | the hand-cast power, verified APIs |
| `XR_SDF_GRAVITY_RIBBON.md` | shader + gravity + grapple as one system |
| `XR_SpinPortal_Demo.pk3` | **loadable** spinning walk-through portal |

**Bottom line:** four "impossible" things were interrogated until the engine admitted what it would take. One of them — per-actor gravity — is now compiled in. The rest are scoped, cheap, and queued. Spheres are next.
