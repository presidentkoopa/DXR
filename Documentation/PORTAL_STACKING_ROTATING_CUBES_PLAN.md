# Portal Stacking + Independently-Rotatable Cube Rooms — DoomXR Plan

**Sources read:** Eternity 4.06.00 portal system (`source/p_portal.h`, `docs/new/editref.md` §13 Portals, `changelogs/ioan_changelog_1.txt`); FishyClockwork's **PolyPortalAssistant v1.3.1** (`zscript.zs`); DoomXR ZScript API confirmed against `E:\DoomXR-work\DOOM_FRESH\wadsrc\static\zscript`.

---

## 1. What "portal stacking" actually is (grounded)

Eternity's real model is **portal GROUPS**, not a single "stacking" toggle:
- `P_CreatePortalGroup(from)` / `P_GatherSectors` / `P_BuildLinkTable` / `P_MarkPolyobjPortalLinks` (`p_portal.h:80-101`). Each connected sector island becomes a **group with its own coordinate frame**; **linked portals** (`paramPortal_linked = 6`, `p_portal.h:71`) stitch groups so you see and walk through many seamlessly.
- "Stacking" = **tiling/overlaying many portal groups in the same physical map coordinates** — rooms that occupy the *same* XY, stacked and stitched by portals. This is how you get bigger-on-the-inside space and, for us, **a grid of cube rooms**.
- The classic portals in `editref.md` (plane 283-285, horizon 286-288, skybox 290-292, anchored 295-297, two-way anchored 344-345) are **non-interactive windows**. The walk-through one is the **linked/interactive** portal.

## 2. The rotation truth (the whole ballgame)

From Eternity's own changelog — the two most important lines in this entire investigation:
- `ioan_changelog_1.txt:875` — **"Visual portals on polyobjects now rotate along with the poly."**
- `ioan_changelog_1.txt:882` — **"...unlike the linked portals."**
- `ioan_changelog_1.txt:1204` — "linked portals can now **move** together with the sector surfaces."

**Translation:** even Eternity — the most advanced portal engine in the Doom lineage — rotates *visual* portals with a spinning polyobject but **NOT interactive/linked ones**, and lets linked portals **translate** (not rotate) at runtime. GZDoom/DoomXR is the same or weaker. **Neither engine natively spins a walk-through portal live.**

Nuance that matters for us: GZDoom line portals come in flavors — strict **linked** (must be parallel, translate-only, perfect rendering) vs **interactive/teleport** (`Line_SetPortal` type 1/2, **rotate by the yaw-angle between the two portal linedefs**, imperfect rendering). **Rotation requires the interactive flavor.** The user has explicitly deferred the rendering imperfection ("both eyes is a problem for later") — which is exactly the trade interactive portals make. So: **use interactive line portals for cube links; accept the render polish debt; gain rotation.**

## 3. The mechanism that unlocks rotatable cubes — PolyPortalAssistant

FishyClockwork's thinker is the missing piece both engines lack: **carrying actors across a portal seam that is itself moving/rotating.**

How it works (`zscript.zs`):
- A line portal is mounted on a **polyobject** (`Side.WALLF_POLYOBJ`, detected at load, line 34-38).
- Each tic *after everything else moves* (`ChangeStatNum(MAX_STATNUM-1)`, line 95), it checks whether the portal line swept **forward** (incl. rotation) over its previous position (`IsBack`, lines 151-160).
- If so, a `BlockThingsIterator` finds actors the line crossed (lines 171-186) and **manually teleports** them: `SetOrigin(TranslateCoordinates(pos, deltAng, dest))` where `deltAng = DeltaAngle(srcAng, destAng)` rotates **position, angle, AND velocity** (lines 202-220). It even adds an inward "pull" so you don't get stranded on the seam (line 223).

**Critical for us:** this is **pure ZScript, GPL-3.0**, and every API it calls is present in DoomXR (`IsLinePortal`, `GetPortalDestination`, `GetPortalAlignment`, `WALLF_POLYOBJ`, `TestMobjLocation`, `BlockThingsIterator` — verified in `mapdata.zs`/`actor.zs`). **It runs on DoomXR now, no recompile.** GZDoom/QZDoom is GPL-3, so the license is compatible — keep the header, credit FishyClockwork, rename `FC_` → `XR_`.

## 4. Re-evaluating spheres + linked portals + 2v2 netplay

- **Spheres:** unchanged from the earlier autopsy — no curved walkable geometry in a sector engine; a "sphere" stays an **instanced dome rendered as an orb**. Portal stacking does **not** rescue the literal sphere. But it makes the **cube** trivially real and stackable, which is the stronger pivot.
- **Linked portals:** confirmed — translate + yaw-rotate-by-linedef-angle (interactive flavor); live spin needs the assistant.
- **2v2 netplay:** portal crossing and `Polyobj_Rotate` are **deterministic playsim / map-thinker** → they replicate cleanly. The assistant is deterministic (runs in the sim, same on all peers). **The only netplay risk is the pre-existing VR-aim-pose checksum blindspot** (from the gravity autopsy, `g_game.cpp:1567`) — orthogonal to portals. **Verdict: netplay-or-not, the cube mechanic itself is net-safe.** Ship SP/co-op first; 2v2 after the VR-pose fix.

## 5. THE DESIGN — two architectures for "rotate any cube however I want"

### Architecture B — Portal-Target Swap (RECOMMENDED: discrete, comfortable, net-trivial)
- Each cube = a **portal group**; each of its (up to 6) faces has an interactive line portal.
- "Rotate cube 90°" = **re-target the face portals** (`Line_SetPortalTarget`) so face *N* now links where face *N+1* did, and set the cube's gravity vector to match.
- **Instant, discrete, deterministic** — a single netevent. No moving seam → **no VR nausea from a spinning portal**; you re-enter already reoriented.
- This is the robust, shippable "flip/rotate any or all cubes" path.

### Architecture A — Rotating Portal Ring (physical spin, the assistant's domain)
- Mount a cube's connecting portal lines on a polyobject ring; **`Polyobj_Rotate`** to spin; the **assistant carries actors across** the moving seam; yaw-delta reorients entry.
- Continuous and flashy, but a live moving seam is the **VR-nausea risk** — reserve for set-pieces, not the core loop.

### Marry to the gravity-vector core (the actual dream)
- Each cube carries a **per-group `GravityDir`** (from the gravity-zone runbook already drafted). Rotating the cube (A or B) rotates its `GravityDir`; entering reorients "down" with the **view-roll comfort transition**. Portal stacking gives the *space*; the gravity core gives the *down*. Together = independently-oriented cube rooms you walk between seamlessly.

## 6. What Eternity offers that DoomXR is weaker at (cherry-pick list — C++ only if needed)
- Explicit **portal-group + link table** (`P_CreatePortalGroup`, `P_BuildLinkTable`, `P_MarkPolyobjPortalLinks`, `gGroupPolyobject` in `p_portal.h`) — a cleaner model for tiling *many* cubes than GZDoom's implicit grouping. **Only port this to C++ if the ZScript+native-GZDoom path proves fragile at scale (many cubes).**
- Eternity robustly handles "polyobject portals capturing things" (`ioan_changelog_1.txt:1108`) — the exact problem the assistant solves in ZScript; Eternity is the reference if we need it in C++.

## 7. IMPLEMENTATION PLAN (build order)

**Group 0 — today, pure ZScript, NO recompile (loose mod pk3):**
1. Adopt PolyPortalAssistant as `XR_PolyPortal` (rename `FC_`→`XR_`, keep GPL header + credit).
2. Test map: two cube rooms joined by a polyobject-mounted interactive line portal. Walk between them; `Polyobj_Rotate` the connector; confirm the assistant carries you across.

**Group 1 — cube grid + logical rotation (ZScript + map):**
3. Build a 2×2 (then 3×3) grid of cube rooms as portal groups, each face an interactive portal.
4. `XR_CubeManager` EventHandler: per-cube orientation state; a **netevent to rotate cube *i*** via Architecture B (`Line_SetPortalTarget` remap), discrete 90° steps; a "rotate all" broadcast.

**Group 2 — marry gravity (depends on the gravity-zone core):**
5. Per-cube `GravityDir`; on rotate, update gravity + trigger the view-roll comfort lerp.

**Group 3 — netplay:**
6. Verify determinism in local co-op; enable 2v2 after the VR-pose checksum fix (orthogonal work).

**Group 4 — optional C++ (only if ZScript scales poorly):**
7. Port Eternity's portal-group link-table concepts for robust many-cube linking.

## 8. Honest risks / deferred
- **Both-eyes portal rendering: DEFERRED per user.** Interactive (rotatable) portals render imperfectly in VR stereo; accepted debt for now.
- **Live spin (Arch A) = VR nausea risk** → default to Arch B (discrete re-enter).
- **Polyobject-portal edge cases** (things straddling a moving seam) — the assistant addresses these but test crossing *while the poly moves*.
- **License:** PolyPortalAssistant is GPL-3; GZDoom/DoomXR is GPL-3 → compatible. Keep header, credit FishyClockwork.

---
**Bottom line:** "Portal stacking" = portal **groups** tiled in shared space. Independently-rotatable cube rooms are **buildable on DoomXR today in pure ZScript** by adopting the PolyPortalAssistant and driving cube reorientation via **discrete portal-target swaps** (comfortable, net-safe), with **physical polyobject spin** as an optional set-piece. Marry per-cube `GravityDir` and you have the dream — seamless, walk-between, independently-oriented rooms — without waiting on any C++.
