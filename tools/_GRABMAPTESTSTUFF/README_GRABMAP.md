# GRABMAP — DoomXR VR test range

A real, hand-built UDMF test map (replaces the old code-spawned `VRTestingRig`).
Current generator is **`build_grabmap_v5.py`** (v4 course + SPIN PORTAL, fully self-contained).
Regenerate with: `python build_grabmap_v5.py <out1.wad> [out2.wad ...]`

## v5: fully self-contained, no companion pk3s
Earlier versions needed `XRTestMenu.pk3` / `XRSDFShowcase.pk3` / `GRAVCOASTER.pk3` /
`XR_SpinPortal.pk3` loaded alongside as separate `-file` args. v5 embeds all of that straight
into GRABMAP.wad's own `ZSCRIPT` lump (it's just an archive-global lump, works fine in a bare
WAD, no pk3 needed):
- `XRTestMenuHandler` — pulled from the **core** copy at `wadsrc/static/zscript/ui/vr_test_menu.zs`,
  which existed in the engine source tree but was never added to `zscript.txt`, so it was dead code
  until now. Left as an orphaned core file rather than wired in globally — GRABMAP is the only
  thing that uses it right now, and wiring it into every map isn't obviously wanted yet.
- `XRSDFShape` (the glowing signage billboards) and `XR_GravPlank` (the gravity-coaster plank
  actor) — genuinely "pure ZScript consumers" of already-native fields/classes, so per this
  project's own convention (see the comment above `vr_death_effects.zs` in `zscript.txt`) they
  belong in map/mod content, not baked into the engine. `XR_GravityPathNode` itself — the actual
  gravity mechanic — **is already native/core** (`wadsrc/static/zscript/actors/doom/vr_gravity_path.zs`);
  only the thin per-map orientation wrapper (`XR_GravPlank`) was ever map-side content.
- `XR_PolyPortalCarrier` — folded in from `XR_SpinPortal.pk3` (FishyClockwork's GPL-3.0
  "Polyobject Line Portal Assistant", DoomXR-renamed FC_→XR_). Fills a real native gap: the
  engine only carries an actor across a portal line when the ACTOR crosses it, not when the LINE
  itself moves/rotates under a stationary actor (`po_man.cpp:1110`). Registered per-map via
  `EventHandlers = "XR_PolyPortalCarrierHandler"` in this map's ZMAPINFO block.

## SPIN PORTAL zone (new in v5, simplified from XR_SpinPortal.pk3)
A single square polyobject spins in place forever (`Polyobj_RotateLeft` in an embedded `SCRIPTS`
ACS script, shipped as **plain source, no compiled BEHAVIOR** — GZDoom's built-in ACS compiler
builds it at map load). One edge of the spinning square is a live `Line_SetPortal` seam to a
static alcove a short walk east; `XR_PolyPortalCarrier` sweeps you through when the rotating seam
passes over you. This is a **simplified single-doorway version** of `XR_SpinPortal.pk3`'s original
MAP01 demo, which was a 4-sided rotating cube linking to 4 separate destinations — that full
version wasn't ported, just the core moving-portal mechanic.
**⚠ Untested** — no engine available to launch here. If it doesn't rotate, check the console for
an ACS compile error first; if the portal doesn't carry you through, that's the ZScript thinker
side to debug next.

## v4 zones (full showcase course)
- **START/throw pit** — barrels + zombie cluster, grab-and-throw practice.
- **CLIMB gauntlet** — 10 real climb textures + 1 non-climbable control pillar (see below).
- **WHIP chasm** — stair-stepped ledges (128/256/384/512) + a static tall platform + a detached
  recovery island, for grapple/swing practice.
- **ICEHOOK tower** — free-climb pillar + ledge.
- **PORTAL** — two linked static booths (`Line_SetPortal`).
- **GRAVITY goal ledge** — VR paint-a-path target platform.
- **LEAP islands** — four stepped-height jump platforms.
- **SDF gallery + finish beacon**.
- **FIRING/PARRY spur** — imp + hitscan zombie for parry practice.
- **RELOAD RANGE** (new in v4) — firing box with a weapon dispensary behind it (shotgun,
  chaingun, rocket launcher, plasma rifle + matching ammo caches) and four zombie dummies at
  increasing range (1000/1200/1400/1600 units) plus a rear imp, so a single reload rarely
  covers the whole line — built to stress-test the manual-reload FSM under pressure.
- **AERIAL GRAVITY COASTER** — walk-up ramp from the arena floor into a full gravity-panel
  rollercoaster (banked sweep, vertical loop, corkscrew) above the whole course.

## What's in it
- **Climb pillars** — a row of 14 one-sided columns along the back wall, each textured with a
  different name so you can climb-test each. Climbability is driven **purely by the wall texture**
  (the live check is `climb:<texturename>` against the KEYWORDS.json climb namespace), so the last
  pillar is a deliberate **non-climbable control**.

  Order **left → right** (west → east):
  1. SUPPORT2  2. SUPPORT3  3. PIPE1  4. PIPE2  5. PIPE4  6. PIPE6
  7. LADDER  8. METLADR  9. CLIMBABLE  10. METAL  11. BROWN96  12. COMPTALL  13. TEKWALL
  14. **STARTAN2 (control — should NOT climb)**

  A pillar shown with a missing/placeholder texture = that name has no loadable texture in the WAD
  set; it tells you the name isn't backed by an actual texture (still a valid data point).

- **Whip platforms** — four stair-stepped ledges up the east side at floor heights 128 / 256 / 384 /
  512, under a 640-tall ceiling. Grapple up onto them, or swing between them.

- **Tall west platform** — a static raised sector (floor 256) as a high whip-grapple target.
  (A perpetual lift was dropped from v1: it required a trigger line, and a lone dangling two-sided
  trigger line crashed the node builder on load. Re-add a moving lift only as part of connected
  geometry, or via a sector action, never as a free-floating 2-sided line.)

## How it loads
Standalone WAD, loaded via the launcher with `-file GRABMAP.wad +map GRABMAP` — **no pk3/engine
rebuild needed** for the map itself (it carries its own ZMAPINFO). The playable copy lives next to the
exe at `build/Release/GRABMAP.wad`; this folder holds the version-controlled source + generator.

## Note
Removing the old `VRTestingRig` prop-spawner is a ZScript change (vr_testing.zs gutted +
deregistered from mapinfo/common.txt) — that only takes effect after the **doomxr.pk3 is rebuilt**.
Until then, loading GRABMAP with the current pk3 will ALSO drop the old rig's ring of props around
you. Harmless; they vanish after the next pk3 build.
