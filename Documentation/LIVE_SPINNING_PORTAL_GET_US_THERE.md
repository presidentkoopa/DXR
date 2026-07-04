Every load-bearing citation is now verified against the live tree. Eternity's `P_MoveGroupCluster` (p_portal.cpp:1323) confirms translate-only (`link->x -= dx; link->y -= dy`, no angle). The interactive render path (portal.cpp:452-506) confirms per-crossing `SetPortalRotation` + `mSinRot/mCosRot` application on `PORTF_POLYOBJ`. Writing the deliverable.

---

# GET US THERE — Live-Spinning Walk-Through Portal for DoomXR

**Target:** DoomXR (GZDoom/QZDoom fork) at `E:/DoomXR-work/DOOM_FRESH`
**Blueprint reference:** Eternity 4.06.00 at `C:/Users/Command/Desktop/Documentation/eternity-4.06.00/source` (architecture only — different engine, not droppable)
**All line numbers re-anchored against the live tree this session.**

---

## 1. VERDICT

**Yes — you can spin a walk-through portal live, this week, at single-eye fidelity, via Option 1 (an INTERACTIVE portal on a rotating polyobject).** The engine already carries every piece of rotation machinery this needs: `FLinePortal` holds `mAngleDiff/mSinRot/mCosRot`, the render path recomputes them per portal-render pass from live linedef geometry, and — critically — **an interactive-only portal polyobject is `bHasPortals == 1`, which is NOT gated by the `== 2` rotation block at `po_man.cpp:343`/`:655`, so it can already rotate with zero C++ change.** The single genuine gap is actor-crossing of a *moving* portal line (the `po_man.cpp:1110` Fixme), and that is already solved externally in pure ZScript by FishyClockwork's PolyPortalAssistant (`SetOrigin` + `deltaAng`). **Highest-leverage first move: build the map — one polyobject carrying a two-sided interactive portal linedef, a `Polyobj_Rotate` driver, and the ZScript crossing assistant — and confirm the spin renders and the player carries. No engine build required to see it move.** Option 2 (a *linked* portal that spins seamlessly — the real prize both engines dodge) is a months-long C++ campaign against an engine-wide coordinate invariant, and should only be attempted after Option 1 proves the feel justifies it.

---

## 2. WHY BOTH ENGINES STOP SHORT

Both GZDoom-lineage and Eternity make the *same* architectural bet for their fast, seamless "linked" portals: **the two portal groups differ by a constant translation only.** That bet is baked so deeply that rotation is forbidden rather than merely unimplemented.

### The DoomXR code wall

**Wall 1 — the rotation gate (`po_man.cpp:343`, `:655`).** Re-verified verbatim:

```cpp
// EV_RotatePoly, po_man.cpp:343
if (poly->bHasPortals == 2)
{
    // cannot do rotations on linked polyportals.
    break;
}
```
```cpp
// EV_OpenPolyDoor (PODOOR_SWING), po_man.cpp:655
if (poly->bHasPortals == 2 && type == PODOOR_SWING)
{
    // cannot do rotations on linked polyportals.
    break;
}
```

`bHasPortals` is assigned in `maploader/polyobjects.cpp:264-265`:
```cpp
int type = port->mType == PORTT_LINKED ? 2 : 1;
if (po->bHasPortals < type) po->bHasPortals = (uint8_t)type;
```
So **`2` == carries a LINKED portal; `1` == INTERACTIVE only.** The gate is type-discriminating: it bans rotation *only* for linked-portal polys. This is the crux that makes Option 1 free and Option 2 hard.

**Wall 2 — linked portals force zero rotation (`portal.cpp:235-241`).** `SetPortalRotation` computes a live angle for every portal type *except* linked, which it hard-zeroes:

```cpp
// portal.cpp:218  (guard)
if (port->mType != PORTT_LINKED)
{
    DAngle angle = dst->Delta().Angle() - line->Delta().Angle() + DAngle::fromDeg(180.);   // :222 live geometry
    port->mSinRot = sindeg(angle.Degrees());
    port->mCosRot = cosdeg(angle.Degrees());
    port->mAngleDiff = angle;
    ...
}
else
{
    // Linked portals have no angular difference.  :237-240
    port->mSinRot = 0.;
    port->mCosRot = 1.;
    port->mAngleDiff = nullAngle;
}
```

**Wall 3 — the static link-offset table has no angle.** `portal.h:32-38`:
```cpp
struct FDisplacement { DVector2 pos; bool isSet; uint8_t indirect; };
```
`FDisplacementTable::MoveGroup(int grp, DVector2 delta)` (`portal.h:72-79`) translates only:
```cpp
data[grp + size*i].pos -= delta;
data[i + grp*size].pos += delta;
```
`FPolyObj::UpdateLinks()` (`po_man.cpp:806-834`) — the live-recompute seam — refreshes `mDisplacement` and calls `MoveGroup`, but **never touches `mAngleDiff/mSinRot/mCosRot`**:
```cpp
port->mDisplacement = port->mDestination->v2->fPos() - port->mOrigin->v1->fPos();   // :819
...
Level->Displacements.MoveGroup(destgroup, delta);   // :828  translation only
```
And `getOffset()` (`portal.h:62-70`) is consumed **additively at ~49 sites across 16 files** — blockmap iterator (`p_maputl.cpp`), clip/physics (`p_map.cpp`, `p_mobj.cpp`, `actorinlines.h`), sound (`s_doomsound.cpp` ×4), automap (`am_map.cpp` ×3), render (`hw_sprites.cpp`), and **netcode prediction (`p_user.cpp` ×2)**. Every one bakes in "far group = near group + constant vector."

**Wall 4 — the crossing Fixme (`po_man.cpp:1110`).** Re-verified:
```cpp
if (ld->isLinePortal())
{
    // Fixme: this still needs to figure out if the polyobject move made the player cross the portal line.
    if (P_TryMove(mobj, mobj->Pos().XY(), false))   // :1111  re-validates CURRENT pos only
    { continue; }
}
```
Native C++ does not detect or apply a crossing *caused by the portal line itself moving*. It only re-checks the actor's current position.

### Eternity stops one step short too

Eternity's `P_MoveGroupCluster` (`p_portal.cpp:1323`, "Moves a polyobject portal cluster, updating link offsets") is the seamless-translation trick — and it is **pure translation**:
```cpp
link->x -= dx;  link->y -= dy;                          // :1344-1345
backlink->x = -link->x; backlink->y = -link->y;         // :1352-1353
```
`gGroupPolyobject` (`p_portal.cpp:81`) binds each portal group to its polyobject owner, and `P_MarkPolyobjPortalLinks` (`:1070`) wires it — but the offset itself is `linkoffset_t{x,y,z}`, no angle, no matrix. Eternity's changelog line "Visual portals on polyobjects now rotate" refers to `R_ANCHORED` **visual** portals (render-side rotation via `portaltransform_t::updateFromLines`), **not** its `R_LINKED` walk-through portals. **Neither engine rotates a linked walk-through seam. That is the untrodden ground.**

---

## 3. OPTION 1 — SPIN IT NOW (interactive portal + rotating poly + assistant)

This is the playable-this-week path. **For an interactive-only portal polyobject, the render transform already tracks the spin frame-by-frame with no engine patch.**

### Why it already works (verified chain)

1. **Not gated.** Interactive-only poly → `bHasPortals == 1` (`polyobjects.cpp:264`) → sails past the `== 2` checks at `po_man.cpp:343`/`:655`. `EV_RotatePoly` spawns its `DRotatePoly` thinker normally.
2. **Legal home.** Interactive portals are explicitly permitted on polyobject linedefs — `UpdatePortal` (`portal.cpp:253`) only downgrades to visual when there's no back-sector **and** `!(sidedef[0]->Flags & WALLF_POLYOBJ)`. A poly linedef is a valid interactive-portal home.
3. **Live render transform, no cache.** Per portal-render pass, `HWLineToLinePortal::Setup` (`hw_portal.cpp:639-647`) calls `P_TranslatePortalXY/Angle/Z` on `origin = glport->lines[0]->mOrigin`. Each of those calls `if (port->mFlags & PORTF_POLYOBJ) SetPortalRotation(port)` (`portal.cpp:457`, `:504`) which recomputes `mAngleDiff/mSinRot/mCosRot` from **current** linedef geometry (`dst->Delta().Angle() - line->Delta().Angle()`, `portal.cpp:222`). `RotatePolyobj` moves the vertices, then `UpdateBBox → AdjustLine` (`po_man.cpp:836-843`) refreshes `Delta` — so the viewpoint transform follows the spin.
4. **Clip stays consistent.** `RotatePolyobj` does `UnLinkPolyobj` → move verts → `UpdateBBox` → `LinkPolyobj` → `ClearSubsectorLinks` every rotation tic; blockmap/subsector linkage is rebuilt with the geometry.
5. **Save/load safe.** `DRotatePoly` serializes via `DPolyAction`; rotation fields are recomputed on demand, never cached across save.

**PORTF_POLYOBJ is the one authoring correctness check:** `SetPortalRotation` sets it only when `line->sidedef[0]->Flags & WALLF_POLYOBJ` (`portal.cpp:226`). Confirm your portal linedef's front side actually carries `WALLF_POLYOBJ` at spawn (the polyobject builder assigns it) — otherwise the per-frame recompute never fires and the portal renders frozen.

### The map recipe (UDMF)

- One polyobject built from an **`Polyobj_StartLine` / `Polyobj_ExplicitLine`** loop, including a **two-sided linedef** flagged with the interactive line-portal special (`Line_SetPortal` with type = **interactive/passable**, NOT linked). Point it at a destination portal linedef elsewhere in the map.
- Give the portal linedef a back-sector (empty space behind it) so `UpdatePortal` keeps it traversable (`portal.cpp:253`).
- Drive it with a **`Polyobj_Rotate` / `Polyobj_RotateContinuous`** special (`EV_RotatePoly`) at a slow, comfort-safe rate (see §5). Anchor the poly's `StartSpot` so it spins about its own center.
- **Do NOT put a linked portal on the same poly** — that re-arms `bHasPortals == 2` and re-blocks rotation for the whole object.

### The ZScript crossing assistant — `XR_PolyPortal`

Native C++ won't carry the player across the moving line (`po_man.cpp:1110` Fixme). Port FishyClockwork's PolyPortalAssistant pattern:

- A per-map `EventHandler` (or a thinker actor parented to the poly's `StartSpot`) that each tic:
  1. Reads the poly's current angle delta this tic (`Δang`).
  2. For each tracked actor near the portal linedef, tests old-side vs new-side of the *moved* line (mirror `P_PointOnLineSidePrecise` used at `hw_portal.cpp:648`).
  3. On a crossing, does `SetOrigin(destPos, true)` computed from `P_TranslatePortal*` semantics and adds `port->mAngleDiff` to the actor's `Angle` (the `SetOrigin + deltaAng` move).
- v1 scope: **player actor only** (matches FishyClockwork). Monsters/projectiles/hitscans crossing the spinning interactive seam are untested in this fork — note as a known limit.

### What works vs what looks wrong (v1)

- **Works:** the portal visibly spins; you see a live-rotating view *through* it (single-eye); you can walk through and land carried + re-angled; blockmap/clip and save/load hold.
- **Looks wrong (deferred):** both-eyes VR stereo. The right eye is derived from a previous-frame delta in `hw_drawinfo.cpp`, which is imperfect for a rotating portal. User has explicitly deferred this — single-eye is the accepted v1 target.

---

## 4. OPTION 2 — THE REAL PRIZE (a LINKED portal that rotates, seamless)

A linked portal keeps groups coordinate-consistent so physics/sound/render/netcode treat "far group" as "near group + constant vector." **Rotation destroys that invariant globally.** The 4-edit "demo patch" below will compile and make a linked poly *visibly spin* — but it renders and collides **wrong**, silently. Ship it only knowing that.

### The 4-edit demo patch (spins, but broken — do not mistake for the feature)

1. **`portal.cpp:235-241`** — let `SetPortalRotation` compute the angle for `PORTT_LINKED` too (remove the zero-branch; drop the `!= PORTT_LINKED` guard at `:218`). Math already reads live geometry, so it recomputes correctly.
2. **`po_man.cpp:806-834`** — in `UpdateLinks()`, after recomputing `mDisplacement` (`:819`), call `SetPortalRotation(port)` for each `PORTT_LINKED` portal so `mAngleDiff/mSinRot/mCosRot` track the spin.
3. **`po_man.cpp:343`, `:655`** — remove/relax the `bHasPortals == 2` gate (or convert to a per-linedef loop bailing only when a portal is truly non-rotatable).
4. **`DRotatePoly::Tick`** (`po_man.cpp:293-316`) — it does **not** call `UpdateLinks` after `RotatePolyobj`. Add that call (translation thinkers already do at `:397`/`:474`/`:568`), or inline a portal-rotation refresh after the vertex update, so the angle cache refreshes on a rotation tic.

### The honest breakage list (why the demo isn't the feature)

Each item below is a real, verified engine-invariant break the adversarial pass surfaced:

- **(a) `getOffset` is additive at ~49 sites / 16 files.** Blockmap (`p_maputl.cpp` ×3), clip/physics (`p_map.cpp`, `p_mobj.cpp`, `actorinlines.h` ×4), monster sight (`p_sight.cpp`), sound (`s_doomsound.cpp` ×4), automap (`am_map.cpp` ×3), render (`hw_sprites.cpp`), **netcode prediction (`p_user.cpp` ×2)**, ZScript-exposed (`vmthunks.cpp`). Each does `pos + getOffset(...)`. With a rotated seam the true mapping is `offset + R·(p − pivot)` — and the table stores **no pivot**. Making linked rotation *correct* means converting every additive site to rotate-then-translate. That's the engine-wide change, not a struct tweak.
- **(b) Displacement-keyed baked coverage goes stale.** `portalgroups.cpp` keys groups by `mDisplacement` (`FPortalID`) and bakes per-subsector `portalcoverage` at load. A rotating seam invalidates that visibility cache every tic. "Render picks it up automatically" is **true for interactive, false for linked** — linked rendering leans on the displacement-keyed coverage that interactive re-transform bypasses.
- **(c) Crossing is worse than the Fixme.** The `:1110` Fixme is only player-carry. The deeper break is the blockmap/clip iterator translating coordinates into the neighbor group by a constant `getOffset` — with a rotated seam, hitscans, monster sight, and thing collision compute wrong positions across the seam. The ZScript assistant does nothing for hitscan/blockmap math.
- **(d) Determinism/netcode.** `p_user.cpp` uses `getOffset` in client-side movement **prediction**. A rotating offset means prediction and authoritative sim must agree on the seam angle at the same tic or the player desyncs across the portal — directly at odds with this fork's VR-netplay goal. Rotation state must be fully derived from the serialized poly angle (never cached un-serialized) and made tick-aligned.

### Extend the model (if you truly commit)

- Add `DAngle mAngleDiff; double mSinRot, mCosRot;` (plus a pivot) to `FDisplacement` (`portal.h:32`).
- Give `MoveGroup` a rotation overload: forward link `+angleDelta`, backlink `−angleDelta`, recompute cos/sin — Eternity's `P_MoveGroupCluster` (`p_portal.cpp:1323`) is the structural template, extended from `dx/dy` to `dx/dy/dθ` about a pivot.
- Introduce a rotation-aware `getOffsetRot(x, y, pos)` and migrate the ~49 additive sites subsystem-by-subsystem (physics → sight → sound → automap → render → netcode).
- Rebuild or bypass displacement-keyed coverage per rotation (or exclude rotating seams from the coverage cache).

### Sizing

**Demo (spins, broken): ~days** (the 4 edits). **Correct seamless linked rotation: months**, touching ~19 files across physics/sight/blockmap/sound/automap/render/netcode — and arguably the wrong substrate. Option 1 gets a live-spinning walk-through portal *without any of this* because interactive portals re-transform per crossing (`P_TranslatePortalXY`, `portal.cpp:457-468`) and never assumed parallel groups.

---

## 5. VR / RENDER CAVEATS (deferred but noted)

- **Stereo (both-eyes) through a rotating portal is imperfect.** The right eye is derived from a previous-frame delta in `hw_drawinfo.cpp` — fine for a static seam, laggy/skewed for a spinning one. Deferred by the user. Later fix: compute the right-eye portal transform independently (re-run `P_TranslatePortal*` with the right-eye viewpoint) instead of deriving it from the left eye's prior frame. Single-eye is correct today.
- **Comfort.** Continuous rotation of what fills the view is a nausea risk in-headset. Start slow (a few deg/sec), test snap-hold variants, and gate rotation speed behind a cvar for playtesting. This is a *feel* dial to tune in VR, not a code correctness issue.
- **Off-screen staleness (harmless).** `SetPortalRotation` recomputes only when `P_TranslatePortal*` runs (render or crossing). If the poly spins off-screen with no traversal, `mAngleDiff` is stale until next render — harmless for rendering (recomputed before use), but any gameplay logic reading `mAngleDiff` directly must trigger a translate first.

---

## 6. BUILD ORDER

1. **Option 1, map + ZScript only (this week).** Author the interactive-portal poly + `Polyobj_Rotate` driver + `XR_PolyPortal` crossing assistant. **No engine build.** Confirm: portal spins, view-through is live single-eye, player carries + re-angles, comfort is bearable in-headset. Verify `WALLF_POLYOBJ` is set on the portal linedef's front side or nothing rotates.
2. **Tune the feel in VR.** Rotation rate, snap vs continuous, assistant lag under fast spin / high velocity. This is the go/no-go gate: if the feel doesn't earn it, stop here — you already have a shipping live-spinning walk-through portal.
3. **Only if the feel justifies it → Option 2.** Do the 4-edit demo first to *see* a linked seam spin, then decide whether to fund the months-long correctness campaign (rotation-aware `getOffset`, coverage rebuild, crossing, netcode determinism). Do not accept the spinning demo as evidence the feature works.

**Tie-ins already on Desktop:** this dovetails with the **gravity-cube flip plan** (portal-linked flippable cubes) — a rotating walk-through portal is the same "moving portal seam" primitive that plan's tier-2 `GravityDir` patch will want, and Option 1's `XR_PolyPortal` assistant is directly reusable as the cube-face crossing carrier. It also feeds **portal-stacking**: interactive poly-portals compose without the coverage-cache constraint that blocks stacked linked portals. Prototype Option 1 small, prove the crossing carrier, then let both plans share it.

---

### Re-anchored citation index (verified live this session)

| Symbol | File:line |
|---|---|
| `EV_RotatePoly` rotation gate | `po_man.cpp:343` |
| `EV_OpenPolyDoor` SWING gate | `po_man.cpp:655` |
| `FPolyObj::UpdateLinks` (displacement-only) | `po_man.cpp:806-834` |
| `bHasPortals == 2` branch | `po_man.cpp:808` |
| `UpdateBBox → AdjustLine` | `po_man.cpp:836-843` |
| Crossing Fixme | `po_man.cpp:1110-1111` |
| `SetPortalRotation` (linked zero-branch) | `portal.cpp:214-243` (`:235-241`) |
| Live angle math | `portal.cpp:222` |
| `UpdatePortal` (poly-legal traversable) | `portal.cpp:253` |
| `P_TranslatePortalXY` (per-crossing rotate) | `portal.cpp:452-468` (`:457`) |
| `P_TranslatePortalAngle` | `portal.cpp:499-506` (`:504`) |
| `FDisplacement` / `MoveGroup` (no angle) | `portal.h:32-38`, `:72-79` |
| `getOffset` additive | `portal.h:62-70` (~49 uses / 16 files) |
| `bHasPortals` / type assignment | `polyobjects.cpp:181`, `:264-265` |
| Render Setup calls `P_TranslatePortal*` | `hw_portal.cpp:639-648` |
| Eternity translate-only cluster-move | `eternity .../p_portal.cpp:1323-1358` |
| Eternity group→poly binding | `eternity .../p_portal.cpp:81`, `:1070` |