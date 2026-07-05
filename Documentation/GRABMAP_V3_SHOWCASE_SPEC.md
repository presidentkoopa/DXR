# GRABMAP v3 — VR Feature-Showcase Ninja Course (build spec)

**Source:** distilled from a 10-agent design+red-team swarm (2026-07-04). Goal: evolve GRABMAP into a
ninja-warrior course where **each zone demonstrates a built DoomXR feature**, a walk-through **portal**
is a traversal element, and every zone is **notated with varied SDF shapes**. This is a *showcase*, not
a cacoward art map. The map cannot be headset-tested by the builder, so everything is reasoned +
geometry-validated.

Generator + validator live at `tools/testmaps/build_grabmap_v3.py` (Python UDMF generator; refuses to
emit the wad unless all validation checks pass). SDF signage ships as a loadable companion pk3.

---

## Arena
One big open-sky room: bounds x[-1800..1800], y[-1500..1850], floor 0, ceiling 800, ceiling = `F_SKY1`
(outdoor obstacle-course feel). Player start `(0,-1250)` facing north. **The course runs monotonically
NORTH** (each zone at a higher y-band) so zones can't overlap by construction. Keep ≥64u clearance from
every footprint to the perimeter wall.

Sky-ceiling caveat (found by red-team): `F_SKY1` has no real ceiling plane, so **portals and any
gravity-flip need their own real-ceiling (`CEIL1_1`) sub-sectors**, or you get sky bleeding through.

---

## Zones (course order, south → north)

| Zone | Feature shown | Works now? | Course role |
|---|---|---|---|
| **START / throw pit** | gravity-glove grab + **explosive-barrel VR throw** (Vel>10 detonate); auto-given loadout | now (grab is VR-only) | Spawn; hurl barrels into a zombie cluster before advancing |
| **CLIMB gauntlet** | texture-gated climbing (10 real climb textures + 1 `STARTAN2` no-climb control) | now | Climb any keyword pillar up onto the shelf; the control pillar visibly refuses |
| **WHIP chasm** | XRWhip grapple + pendulum swing (LineTrace, Reach 300); entangle-yank target | now (VR-only) | Grapple across a floor-0 gap to a 192 ledge; caged monster on a 512 pedestal |
| **ICEHOOK tower** | IceHook makes **any** wall climbable — overrides the texture gate | now (VR-only) | Climb a `STARTAN2` tower (the same texture that refused earlier) to a 384 ledge |
| **PORTAL** | static line-to-line **linked portal** (`Line_SetPortal` 156) — native, no ACS/polyobject | now | Walk through booth A → re-emitted at booth B; bidirectional, re-runnable |
| **GRAVITY** | XR_GravityPath palm-out paint-a-path + GravityDir tilt (VR-only, gesture) | now (VR-only) | Paint a floor→tilt→ledge route to a 512 goal ledge |
| **LEAP islands** | floating stair-step platforms (jump/parkour) | now | Hop 256/384/512/640 islands toward the gallery |
| **SDF gallery + FINISH** | all 9 SDF shapes in a row + gold finish beacon | now | Breather + the goal |
| **FIRING / PARRY spur** | VRSword parry + ShieldSaw vs caged shooters (VR swing-only) | now | Optional west detour; deflect projectiles/hitscan |

---

## The portal recipe (the key technical finding)
The draft assumed the portal line's own ID comes from an arg (arg1=self). **The red-team proved that's
wrong for this map:** `namespace="zdoom"` sets `isTranslated=false` (udmf.cpp:2529-2532), so the
arg-as-self-id path never runs. A line's own ID comes **only** from an explicit UDMF `id=` field
(udmf.cpp:913). Destination is matched by the target line's ID via `FindPortalDestination →
GetLineIdIterator(tag)` where `tag = args[0]` (specials.cpp:126, portal.cpp:189-204).

**Correct recipe:**
- Seam A: `special=156, args=(901,0,3,0,0), id=900`
- Seam B: `special=156, args=(900,0,3,0,0), id=901`
- `arg0` = the *other* line's id; the line's own id is the `id=` field; `arg1` unused=0; `arg2=3`
  (`PORTT_LINKED` → seamless see-through + walk-through + bidirectional); `arg3=0`.
- Both seams: axis-aligned, equal length, **never blocking**, floor+ceiling equal on both sides, real
  (non-sky) ceiling. Sealing geometry must **reuse the seam's vertex indices** so no dangling line.

Missing `id=` → the portal silently renders as a plain wall (no crash, just dead). Assert exactly one
`id=900` and one `id=901`.

---

## Bugs the red-team caught (the swarm's payoff)
1. **Fake climb textures** — `LADDER`, `METLADR`, `CLIMBABLE` are climb-*keyword* strings, **not real
   Doom2 IWAD textures**. Using them as wall textures = checkerboard, and it breaks the honest
   per-texture climb demo. Use only IWAD-real climb textures: `SUPPORT2 SUPPORT3 PIPE1 PIPE2 PIPE4 PIPE6
   METAL BROWN96 COMPTALL TEKWALL`.
2. **Portal `id=` requirement** (above) — would have shipped a dead portal.
3. **Sky-ceiling** breaks portals (sky bleed) and gravity-flip — needs real-ceiling sub-sectors.
4. **Gravity "auto ceiling-flip chamber" is a myth** — there is no tile-seeder on map load, and a
   ceiling tile is unreachable (needs feet within 28u of the face). Dropped; kept the VR palm-out
   paint-a-path. A no-rebuild ZScript floor-*tilt* tile-seeder is the only gesture-free option (a
   ceiling-only tile still won't work).
5. **Dangling-line / coincident-vertex crashes** — validator added to catch them before write.

---

## Build order
0. Add generator helpers (`platform`, `void_pillar`, `portal_booth`, `id` param on `LN`).
1. Build the validation harness (closure, dangling, coincident-vertex, gutters, thing-in-pillar,
   portal-linkage). Run it after **every** zone.
2. Arena at the new bounds; move player start to (0,-1250).
3. CLIMB pillars (real textures only) + shelf.
4. WHIP ledge + overhead anchor. *(west recovery stairs dropped — abutting platforms made coincident
   verts; a whip-fail just walks back.)*
5. ICEHOOK tower + ledge.
6. **PORTAL** (highest risk — validate linkage immediately).
7. GRAVITY goal ledge (no ceiling chamber).
8. LEAP islands.
9. FIRING/PARRY west pedestal.
10. SDF signage → companion pk3 (export marker coords from the validated generator; gate handler on
    `MapName ~== "GRABMAP"`; do **not** load two SDF pk3s at once = duplicate-class abort).
11. Load line: `-file GRABMAP.wad <sdf>.pk3 +map GRABMAP` (core doomxr.pk3 supplies whip/sword/hook/
    gravity). Ensure the play engine is the current `build/Release` build or whip/sword/hook no-op.

---

## Works now vs needs rebuild
**No rebuild (loadable):** static portal (with `id=` fix), climb, barrels/throw, whip, IceHook, sword/
shieldsaw parry, all 9 SDF shapes, the companion-pk3 SDF signage, the optional ZScript gravity
floor-tilt seeder.

**Needs a rebuild (or a current-dated exe):** SDF *text* signage via `SpawnSDFText` (native binding is
in source + should be in the 07-04 `build/Release`; only "rebuild" relative to a stale play-folder exe);
native box-mag reload / vhand-swap (gated off); identical-gun akimbo; the **spinning polyobject**
portal (no ACS compiler in repo — ship the demo's prebuilt `MAP01` as a bonus map instead).

## Residual risk flags
- Portal winding: wrong v1/v2 order = backwards/unreachable portal (non-crash) — flip if it's dead.
- Gravity is **VR-only** (hand tracking); nothing flatscreen-testable beyond geometry.
- Whip rope: Leather profile defaults to the buggy rigged-IQM rope — set `vr_whip_model 0` or
  `vr_whip_profile 1` for the SDF-chain rope (physics work regardless; visual only).
- Never use `P_SpawnParticle` for VR signage (invisible in VR stereo) — use `XRSDFShape` billboards.

---

*Status: spec finalized; v3 generator written + validator passing on the fixed portal geometry; final
`GRABMAP.wad` emit + SDF pk3 packaging was interrupted and is the remaining step.*
