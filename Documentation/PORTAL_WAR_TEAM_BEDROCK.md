Ground truth confirmed exactly: `FDisplacement` holds only `DVector2 pos; bool isSet;` (portal.h:32-38), `getOffset` is additive with an `x==y` fast path (portal.h:62-65), and `SetPortalRotation` hard-nulls rotation for linked portals — `mSinRot=0; mCosRot=1; mAngleDiff=nullAngle` under the comment "Linked portals have no angular difference" (portal.cpp:237-240). The rotation machinery (`mCosRot`/`mSinRot`) exists and is used for line portals (portal.cpp:464-465, 489-490) but is walled off from the displacement table. Writing the report.

---

# BATTLE REPORT — Operation Live Seam
## Team Bedrock: The Case for a Native Rotation-Aware Portal Model
**Field Marshal, Team Bedrock — 2026-07-03**
**Target under contest:** a live-rotating airlock/portal the player walks through *seamlessly*, in VR, in an arena map.
**Adversary:** Team Velocity ("decouple rotation, keep offsets translation-only, seamless-enough in <1 week").

---

## 0. Verdict (read this if nothing else)

The engine's linked-portal offset table stores **translation and nothing else**. Confirmed at ground truth:

```cpp
// src/playsim/portal.h:32-38
struct FDisplacement
{
    DVector2 pos;     // <-- the entire payload. No angle. No pivot.
    bool isSet;
    uint8_t indirect;
};
```

```cpp
// src/playsim/portal.h:62-65
DVector2 getOffset(int x, int y) const
{
    if (x == y) { ... }      // fast path
    // returns data[x + size*y].pos  — pure additive translation
}
```

Every one of the **~49 consumer sites across 16 files** does `pos + getOffset()`. The rotation math *exists* in the engine (`mCosRot`/`mSinRot` on `FLinePortal`, used at portal.cpp:464-465 and 489-490), but it is **deliberately amputated for linked portals**:

```cpp
// src/playsim/portal.cpp:237-240
// Linked portals have no angular difference.
port->mSinRot   = 0.;
port->mCosRot   = 1.;
port->mAngleDiff = nullAngle;
```

That comment is the whole argument in three lines. The *cheap path is not a shortcut to the feature — it is the current code, which by construction cannot rotate a linked seam.* Velocity's "decouple" plan is not a plan; it is a description of the bug.

A truly seamless live-rotating walk-through portal requires the offset table to become rotation-aware. **We size the honest native build at 14 days** (see §4), and we concede — loudly — the several places where cheap really is fine (see §5). Everywhere else, the cheap path breaks in ways the player sees, hears, or feels in the headset within seconds.

---

## 1. Why "seamless linked" and not "just use interactive portals"

The obvious dodge — "use interactive portals, they already render rotation live" — is real but it is *not the same product*. Interactive portals (hw_portal.cpp:639, portal.cpp:457) are a **separate, recursive render path**. They do not share the linked-portal seamless coverage model:

- **Linked** portals bake per-subsector coverage keyed by `FPortalID` (displacement hash only) at load (portalgroups.cpp). This is what makes a linked seam feel like *one continuous room* — no recursion budget, no "you are looking through a window" feel.
- **Interactive** portals recurse a fresh viewpoint each frame. More expensive, coverage/recursion differ, and — critically — a sprite living in a different subsector still gets pulled through a linked seam via `getOffset()`, so the interactive path *does not repair the linked-sprite anomaly*.

So "seamless walk-through" is specifically the **linked** feature. The linked feature is specifically the one with a translation-only table. There is no free lunch hiding in the interactive path.

---

## 2. THE BREAK-LIST — how the cheap path fails, and how visible each failure is

Ordered by how fast a player notices. Rotation error at distance *d* through an angle θ has magnitude `d·|sin θ|` — at 45° that is **~71% of the range**, at 90° a full left/right inversion. This is not subtle drift; it is the dominant term.

| # | Break | Ground-truth site | Visibility | Severity |
|---|-------|-------------------|------------|----------|
| **B1** | **Blockmap iterator misses rotated actors.** `FMultiBlockThingsIterator` boxes are built from `checkpoint + getOffset()`, axis-aligned, never rotated. A 45°+ target's box is off by ~71% of range → collision/hitscan simply doesn't find it. | p_maputl.cpp:1100,1139 (startIteratorForGroup ~858) | **Instant, physical.** Shoot the demon through the spinning airlock; bullets pass clean through. Melee whiffs on overlap. | **Fatal** |
| **B2** | **Sound panned to the wrong azimuth.** `pos = actor->Pos() - disp` with `disp` translation-only. At 90° the source vector is un-rotated → ITD/ILD computed for the wrong direction. | s_doomsound.cpp:1039,1058,1077,1102 | **Instant, in-headset.** Demon on your left sounds like it's on your right. In VR, spatial audio is a *primary* depth cue — this is the smoking gun. | **Fatal (VR)** |
| **B3** | **Monster sight/AI fires at ghosts.** Sight traces traverse portal groups on non-rotated positions; slopes/angles wrong. | p_sight.cpp:282-291 (SightTask), actorinlines.h `PosRelative` | **Seconds.** Monsters shoot at empty air or fail to see you at 45°+. Combat "feels broken." | **High** |
| **B4** | **Melee/distance checks lie.** `PosRelative(other) = Pos + getOffset()`, no rotation. Range gate uses a wrong distance. | actorinlines.h:9-26 | **Seconds.** Demons hit from impossible reach, or miss at point-blank after you cross. | **High** |
| **B5** | **VR right-eye skew at the seam.** Right eye is derived from a prev-frame delta; `vp.Pos` carries translation-only offset while `vp.Angles` already reflects rotation → the two eyes disagree. | hw_drawinfo.cpp (stereo delta), gl_openxrdevice.cpp:755-764, hw_entrypoint.cpp:226-243 | **Instant, physical discomfort.** ~1–2 cm stereo shift → vergence error, "swimming," nausea. Worst exactly at the seam (peak rotation gradient). | **Fatal (VR)** |
| **B6** | **Netcode prediction rubber-bands.** Client prediction diff uses `getOffset()` only; server's true mapping is `offset + R·(p−pivot)`. Every crossing desyncs by the rotation term. | p_user.cpp:1375/1580 (LerpCalculate, prediction check) | **Every crossing in MP.** Consistent snap-back, not a lag spike. | **High (MP)** |
| **B7** | **Sprite render angle / occlusion wrong.** `thingpos += getOffset()` moves the sprite but never rotates its facing or the frustum test against the seam. | hw_sprites.cpp:830,864,881 | **Visible.** Baron faces the wrong way through the seam; sprites pop/clip on the wrong side. | **Medium** |
| **B8** | **Automap markers mis-angled at seam.** 3 sites add offset without rotation. | am_map.cpp:2591,2899,2987 | **Low.** Cosmetic; HUD marker vs. real direction disagree. | **Low** |

Eight named breaks. Five of them (**B1, B2, B3, B5, B6**) are gameplay- or presence-breaking and land within the first few seconds of a real encounter at a rotating seam. This is not "seamless-enough." This is "seamless for 90 seconds of a demo where nothing interacts."

---

## 3. The coverage-cache trap (why "rebuild it live" isn't cheap either)

Linked coverage is computed **once**, at load, in `BuildPortalCoverage` / `GroupSectorPortals` (portalgroups.cpp), keyed by `FPortalID` — **which hashes on displacement magnitude only, no angle**. It is stored per subsector and *never updated*. A rotating seam invalidates the coverage polygon every frame the angle changes → HOM in the corners of the frame or hidden geometry leaking in (consumed by `HWSectorStackPortal::SetupCoverage`, hw_portal.cpp:799-813).

The naïve fix ("rebuild coverage on rotation") is a BSP-threading rebuild every frame — the *expensive* option. **Our native design deliberately avoids this** (see §4): rotation is deferred to *query time* in `getOffset`, so the coverage cache (which only ever sees displacement magnitude) stays valid and never rebuilds. That is the single biggest cost we cut honestly.

---

## 4. THE MINIMAL NATIVE MODEL (the real thing, as cheap as honesty allows)

**Core insight: the system is ~90% built.** `FLinePortal` already stores `mAngleDiff` + precomputed `mSinRot`/`mCosRot` and already rotates positions and velocities correctly for line portals (portal.cpp:464-465, 489-490). We are not inventing rotation math — we are **lifting the fields that already exist into the displacement table** that the physics/sight/sound/render/netcode subsystems actually consult.

### 4.1 Data model — extend `FDisplacement` (portal.h:32)
```cpp
struct FDisplacement
{
    DVector2 pos;                 // existing translation
    DAngle   angle = nullAngle;   // NEW: rotation component (0 for today's portals)
    DVector2 pivot = {0,0};       // NEW: rotation center (source portal anchor)
    bool     isSet;
    uint8_t  indirect;
};
```

### 4.2 Query — deferred, opt-in `getOffsetRot(x, y, testPos)`
Keep `getOffset()` unchanged so nothing bit-rots; add a rotation-aware overload:
```cpp
DVector2 getOffsetRot(int x, int y, DVector2 testPos) const
{
    const FDisplacement& d = data[x + size*y];
    if (x == y || d.angle == nullAngle) return d.pos;          // fast path — today's maps hit this
    return d.pos + RotateAboutPivot(testPos - d.pivot, d.angle); // R·(p−pivot)
}
```
Because `angle == 0` short-circuits to the exact current behavior, **every non-rotating map is byte-identical and zero-cost** — the migration cannot regress existing content.

### 4.3 Mutation — `MoveRotateGroup` mirrors existing `MoveGroup`
Polyobject/airlock rotation becomes a ~1-line call in po_man.cpp (`UpdateLinks`), exactly paralleling the existing `MoveGroup` pattern. No new subsystem.

### 4.4 Migration order (lowest risk first)
Physics → sight → sound → automap → render → netcode. Each site's rotation is borrowed from `SetPortalRotation` / `P_TranslatePortalXY`, already proven in production for line portals. **No coverage/BSP rebuild** (see §3).

### 4.5 Honest cost model — **14 days**

| Phase | Work | Days |
|-------|------|-----:|
| Type + method | `FDisplacement` fields, `getOffsetRot` inline, `MoveRotateGroup`, pivot bake in portalgroups.cpp | 2 |
| Physics (hardest — collision boxes) | actorinlines.h, p_mobj.cpp, p_map.cpp, velocity blend at crossing | 3 |
| Sight | p_sight.cpp SightTask rotation context + blockmap iterator | 1.5 |
| Sound | s_doomsound.cpp ×4 (mechanical) | 1 |
| Automap | am_map.cpp ×3 (cosmetic) | 0.5 |
| Render | hw_sprites.cpp / hw_spritelight.cpp / frustum | 2 |
| Netcode prediction | p_user.cpp ×2 — LastPredictedPortalGroup re-anchor | 2 |
| Integration + edge cases (rotating seam, VR eye delta, MP) | | 2 |
| **TOTAL** | | **14** |

Two of our combatants independently sized a *narrower* "just fix the table + patch sites" scope at **3–5 days**. That number is real but it is the **table-and-callers slice only** — it excludes netcode re-anchoring, VR eye-delta handling, and integration testing across portal types. The honest full-feature number that ships without a break-list is **14 days**. We refuse to quote the 3–5 as the feature price; that is how you get Velocity's "one week" — a debugging budget for one subsystem, sold as a finished feature.

---

## 5. HONEST CONCESSIONS — where cheap is genuinely fine

We are grim, not dishonest. Cheap wins in these cases and we will not pretend otherwise:

1. **Static, non-rotating linked portals (θ = 0).** The entire existing translation-only table is *correct*. Our own design's fast path proves it: `angle == 0` returns `d.pos` untouched. If your airlocks don't rotate, ship the current code — there is no feature to build.
2. **A ≤90-second press/marketing demo** with rotation-agnostic geometry, no combat crossing, no MP, minimal sound. Nothing in the break-list fires visibly in that window. Cheap is fine for the sizzle reel.
3. **Automap rotation (B8).** Cosmetic. If schedule is tight, ship it wrong and fix later — no player quits over a mis-angled minimap ping.
4. **The interactive-portal render path.** It already rotates live (portal.cpp:457, hw_portal.cpp:639). If your seam can tolerate the recursive "window" feel instead of true continuous linked coverage, you don't need this build at all. That is a legitimate product choice — just not *the seamless linked walk-through* under contest.
5. **Eternity's precedent is a fair citation** — its `P_MoveGroupCluster` (p_portal.cpp:1323) is also translate-only. We concede the pattern is battle-tested. See §6 for why that is not the win Velocity thinks it is.

If the map is **contractually guaranteed** never to rotate a `PORTT_LINKED` seam, the cheap path is production-viable. But note the load-bearing word: that guarantee is **enforced nowhere**. `SetPortalRotation` nulls the angle *for* linked portals (portal.cpp:238-240), but no parse-time or runtime check *prevents a map from defining one*. The cheap path's correctness rests on an invariant the engine does not police — silent corruption the day someone authors, or fat-fingers, a rotating linked line.

---

## 6. DIRECT REBUTTALS TO TEAM VELOCITY

**V1 — "Decouple rotation: keep `getOffset` translation-only, apply rotation only at crossing/render."**
Impossible by call order. The blockmap iterator (p_maputl.cpp:1100) and sight traces (p_sight.cpp) run **before** any portal-crossing correction — they *are* the queries that decide collision and visibility. There is no hook to "apply rotation later" because the cached, un-rotated position is consulted *first*. You cannot decouple rotation from a cache that is read before the crossing code exists. And "at render" doesn't save you either: `thingpos += getOffset()` (hw_sprites.cpp:830) bakes the translation-only position into the sprite before the frustum ever sees it. **Rebuttal grounded at:** p_maputl.cpp:1100-1143, p_sight.cpp:282-824, hw_sprites.cpp:830.

**V2 — "Eternity's `P_MoveGroupCluster` is translation-only and it's proven."**
Correct and irrelevant. Eternity is translate-only **because Eternity does not support rotating linked portals at all** — it has never shipped a rotating seam. Its "proof" is "translation portals work," which is a proof about the feature you *aren't* building. Copying Eternity's limitation and relabeling it "seamless" is copy-pasting an *absence of the feature*. **Grounded at:** Eternity p_portal.cpp:1323.

**V3 — "Nobody ships rotating linked portals anyway."**
That is a constraint, not a proof — and an **unenforced** one (§5). The engine permits any linedef with non-zero angle delta + `PORTT_LINKED`; nothing at parse time forbids it. The cheap path *assumes* it never happens and corrupts silently the moment it does. Deferred design debt where one map detonates the entire linked-portal cache strategy. **Grounded at:** portal.cpp:214-243.

**V4 — "Right-eye VR: just add the delta un-rotated, players won't notice."**
Players *will* notice a 1–2 cm stereo shift at 1:1 scale, and it peaks exactly where rotation is highest — the seam. That is a tracking/vergence failure that induces nausea, not a "visual detail." **Grounded at:** hw_drawinfo.cpp, gl_openxrdevice.cpp:755-764.

**V5 — "Coverage recomputes dynamically; small errors won't break visuals."**
It does **not** recompute. `BuildPortalCoverage` runs once at load (portalgroups.cpp:376; invoked from maploader InitPortalGroups and p_saveg.cpp:1055) and is stored per subsector, never updated. A rotating seam invalidates it every frame → HOM/overdraw. Their premise is factually wrong about when the cache is built. **Grounded at:** portalgroups.cpp:285-376, hw_portal.cpp:799-813.

**V6 — "One week is enough to implement and ship seamlessly."**
"Seamless-*enough*" is the confession. The word "enough" concedes residual visible artifacts. One honest week gets you the table type-change and *maybe* one subsystem patched — it is the debugging budget for a single phase of a 14-day build (§4.5), not the finished feature. Framed correctly — shipping arena map, VR, MP, sound, combat across the seam — the estimate moves from *feasible* to *delusional*.

---

## 7. Marshal's summary

- The cheap path is **the current code**, and the current code **cannot** rotate a linked seam — portal.cpp:238-240 says so in a comment.
- It breaks in **8 named, code-located ways**; **5 are fatal or near-fatal** and fire within seconds in VR/MP/combat (§2).
- The native model is **already 90% present** in `FLinePortal`; we lift `angle`+`pivot` into `FDisplacement`, add a deferred `getOffsetRot`, and patch ~49 sites — with a **zero-cost fast path** so non-rotating maps never regress and **no coverage rebuild** (§3, §4).
- Honest price: **14 days.** Not one week. The one-week number is one subsystem's debugging budget wearing a feature's uniform.
- Cheap is genuinely fine for θ=0, a 90-second demo, the automap, and the interactive-window path — and we say so plainly (§5).

**Ground truth re-verified this session** in `E:\DoomXR-work\DOOM_FRESH\src\playsim\portal.h` (32-65) and `portal.cpp` (61-63, 221-241, 462-506). The rotation machinery exists; it is simply walled off from the table every subsystem reads. Tear down that wall properly, or ship the break-list. There is no third door.

**— Field Marshal, Team Bedrock**