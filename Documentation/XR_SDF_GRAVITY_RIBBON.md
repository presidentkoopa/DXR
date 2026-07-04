> **CORRECTION (user, overrides the grapple design below):** the grapple does NOT hook the road nodes. You WALK onto the road (proximity -> reorient). The grapple fires ANYWHERE at normal geometry and DETACHES you from the road, restoring normal gravity + pulling you to the hook point. Therefore: nodes do NOT need +SHOOTABLE / the NOBLOCKMAP fix / an enlarged hook box for grappling. The grapple integration is a single hook: on grapple-fire, clear the road-follow state and restore gravity. Read section 3c accordingly.

This is the definitive confirmation of the std140 padding trap — the exact 12-byte corruption warning is in the source comment. I now have everything verified. Writing the deliverable.

---

# XR SDF GRAVITY RIBBON

*Paint SDF segments onto geometry that union into a walkable, grapplable 3D neon path.*
**Audience: the implementer (ZScript + shader-lane). Repo is READ-ONLY; every claim below is anchored to a live `E:/DoomXR-work/DOOM_FRESH` symbol I grepped, not to the spec.**

---

## 1. THE VISION IN ONE PARAGRAPH

You hold your palm out, and with the off-hand you *draw* on the world — sweep the arm across the floor, up a wall, across the ceiling, and a chain of glowing neon segments lays itself down flush on whatever surface your aim traces. Those segments read as **one continuous neon road** arcing through 3D space. Then you *use* it two ways: **step onto it and walk** — gravity reorients so "down" becomes the surface you painted, and you stride up the wall along the ribbon like it's a floor — or **grapple-hook onto it** from across the room, jump, and reel yourself into the wall you painted. Floor → wall → ceiling, one unbroken glowing path, walkable and hookable. That is the target.

---

## 2. YES / NO VERDICT

**YES — the *road* and the *hook* are real, shippable in loose-pk3 ZScript today. The *seamless glowing skin* is an illusion at v1 and needs a shader-lane BUILD to become real.** Break it down by claim:

| Claim | Verdict | Why (live symbol) |
|---|---|---|
| Paint a node chain floor→wall→ceiling with correct surface normals | **YES, now** | Off-hand `LineTrace(...TRF_ISOFFHAND...)`; wall normal = perp of `HitLine.delta` proven at `gitd_buckshot.zs:75-81`; floor/ceiling = `SecPlane.Normal` (`mapdata.zs:265`). |
| Walk it — gravity reorients, guided rail | **YES, now** | Mirrors the shipped VR climb driver: `VR_UpdateClimbing` (`p_user.cpp:1864`) does `flags |= MF_NOGRAVITY; Vel = climbDelta * mult;` at `p_user.cpp:1912-1913` — **overwrite Vel, don't accumulate**. Zero C++. |
| Grapple-hook onto a painted node | **YES, now — after fixing a self-nullifying flag bug** (see §3c). | `XRWhip.StartGrappleFromAim` branches on `TRACE_HitActor && bShootable` (`vr_whip.zs:341`); `flags=0` trace uses actor mask `MF_SHOOTABLE` (`p_map.cpp:5268`). |
| Separate per-node quads **visually UNION into one seamless ribbon** | **NO at v1 — this is the honest part.** | `vr_sdf_procedural.fp:52` works **only in per-quad local UV** (`vTexCoord.st * 2.0 - 1.0`). Its `d = min(d, d2)` (lines 99/106) unions two shapes *inside one quad*, never across quads. Abutting quads render as N independent glowing sprites → **beaded seam, not a constant-width ribbon.** |
| `AddGlowPanel` lays quads **flat** on floor/wall/ceiling | **NO — refuted against the renderer.** | `hw_glowbillboards.cpp:145` hardcodes `float uY = h;` (world-up) and the comment at `:106` says *"in both modes up stays world-up, so the panel is vertical (no pitch/roll)."* `dirX/dirY` only changes **yaw**. A floor/ceiling/slope quad **cannot be laid flat** through this primitive. |

**The honest "seamless union" answer:**
- **v1 (no build):** overlap soft radial glow discs ~50% like the XRWhip cord — an honestly-**beaded neon tube**. Do *not* call it a seamless constant-width ribbon; with the current primitives it is not one.
- **v2 (build):** the *real* seamless ribbon is a **world-space capsule-union shader** — add `sdCapsule()` + a `u_XR_PathNodes[16]` world-space node array to `StreamData`, and every fragment on every quad samples the **same** capsule chain. That makes the ribbon genuinely continuous (corners are just `min()` of two capsules meeting at the shared node). This is **not built today** (grep confirms no `sdCapsule`, no node array in the `.fp` or in `StreamData`).

So: **the power works and is fun at v1; the "one continuous neon road" *look* is a v2 shader build.** Ship v1 honestly, upgrade the skin later.

---

## 3. THE THREE LAYERS

### (a) THE ROAD — ZScript node chain (walk + grapple logic). **Loose-pk3, ships now.**

The nodes *are* the road. Paint them, walk them, hook them. Four bugs from the spec skeleton are fixed inline below (call-outs marked ⚠️FIX).

```zscript
// ============================================================================
// XR_GravityPathNode — one knot in the ribbon.
// ⚠️FIX #1 (fatal): NO +NOBLOCKMAP. A NOBLOCKMAP actor is never linked into the
//   blockmap (p_maputl.cpp:508 gates linking on !(flags & MF_NOBLOCKMAP)), so it
//   can NEVER produce TRACE_HitActor — +SHOOTABLE would be dead. Drop it.
// ⚠️FIX #2: enlarge the HOOK box (Radius/Height) — the visual stays small via Scale.
//   Trace hit-test uses the actor bbox; a 12u box is unhookable mid-jump at range 900.
// ============================================================================
class XR_GravityPathNode : Actor
{
    Vector3 SurfaceNormal;   // outward-facing; -SurfaceNormal = local "down"
    Vector3 Tangent;         // forward along the ribbon
    int     NodeIndex;
    int     BirthTic;

    Default
    {
        Radius 18; Height 16;                    // FIX #2: hookable box (visual is Scale-driven)
        +NOGRAVITY +NOINTERACTION +SHOOTABLE     // FIX #1: NOBLOCKMAP REMOVED; +SHOOTABLE kept
        +DONTSPLASH +NOBLOOD +NODAMAGETHRUST
        RenderStyle "None";                      // rendering is done by AddGlowPanel (see skin)
    }
    States { Spawn: TNT1 A -1; Stop; }
}

// ============================================================================
// XR_GravityPath — off-hand POWER: the PAINT loop.
// ============================================================================
class XR_GravityPath : Weapon
{
    Array<XR_GravityPathNode> Nodes;
    bool    Painting, Live;
    Vector3 LastNodePos;
    double  NodeSpacing;

    Default
    {
        Weapon.SelectionOrder 3700;
        +WEAPON.NOAUTOAIM +WEAPON.NOALERT +WEAPON.NOAUTOSWITCHTO
        +WEAPON.OFFHANDWEAPON
        Tag "XR Gravity Path";
    }

    // THE LOAD-BEARING HELPER — derive the correct normal per surface class.
    // FLineTraceData has NO HitNormal (actor.zs:36-62); we derive it.
    private Vector3 XR_SurfaceNormalFromTrace(FLineTraceData t, Vector3 aimDir)
    {
        // 3D-FLOOR top/bottom — Hit3DFloor.top/bottom.Normal, pick by Z-distance
        if (t.Hit3DFloor &&
            (t.HitType == FLineTraceData.TRACE_HitFloor ||
             t.HitType == FLineTraceData.TRACE_HitCeiling))
        {
            double topZ = t.Hit3DFloor.top.ZAtPoint(t.HitLocation.xy);
            double botZ = t.Hit3DFloor.bottom.ZAtPoint(t.HitLocation.xy);
            return (abs(t.HitLocation.z - topZ) <= abs(t.HitLocation.z - botZ))
                 ? t.Hit3DFloor.top.Normal : t.Hit3DFloor.bottom.Normal;
        }
        // FLOOR / CEILING incl. SLOPES — SecPlane.Normal (mapdata.zs:265)
        if (t.HitSector &&
            (t.HitType == FLineTraceData.TRACE_HitFloor ||
             t.HitType == FLineTraceData.TRACE_HitCeiling))
        {
            return (t.SectorPlane == 0) ? t.HitSector.floorplane.Normal
                                        : t.HitSector.ceilingplane.Normal;
        }
        // WALL — perp of HitLine.delta, disambiguated by off-hand aim
        // (PROVEN verbatim at gitd_buckshot.zs:75-81)
        if (t.HitType == FLineTraceData.TRACE_HitWall && t.HitLine)
        {
            Vector2 d = t.HitLine.delta;
            double dl = d.Length(); if (dl < 0.0001) dl = 1.0;
            double n1x = -d.y / dl, n1y = d.x / dl;
            double dotv = n1x * aimDir.x + n1y * aimDir.y;
            return (dotv > 0.0) ? (-n1x, -n1y, 0) : (n1x, n1y, 0);
        }
        return (0, 0, 1); // fallback: floor-up
    }

    private void XR_PaintTick()
    {
        if (owner == null || owner.player == null) return;

        double  ang    = owner.OffhandAngle;              // actor.zs:280
        double  pit    = owner.OffhandPitch;              // actor.zs:278
        Vector3 aimDir = owner.OffhandDir(owner, ang, pit); // actor.zs:863

        FLineTraceData t;
        // TRF_ISOFFHAND=2048 (constants.zs:962) — real hand origin + portal-correct.
        if (!owner.LineTrace(ang, 2000.0, pit, TRF_ISOFFHAND, data: t)) return;
        if (t.HitType == FLineTraceData.TRACE_HitNone)  return;
        if (t.HitType == FLineTraceData.TRACE_HitActor) return;

        if ((t.HitLocation - LastNodePos).Length() <= NodeSpacing) return;

        Vector3 n = XR_SurfaceNormalFromTrace(t, aimDir).Unit();

        // ⚠️FIX #3: OFFSET OUT from the surface by >= node radius so the SHOOTABLE
        //   box clears the wall plane (else ML_BLOCKEVERYTHING geometry occludes the
        //   node and the grapple trace hits the WALL first). Buckshot offsets +1.5u
        //   (gitd_buckshot.zs:84); we need >= our radius (18) → use 20u.
        Vector3 spawnPos = t.HitLocation + n * 20.0;

        let node = XR_GravityPathNode(Actor.Spawn("XR_GravityPathNode", spawnPos));
        if (node)
        {
            node.SurfaceNormal = n;
            if (Nodes.Size() > 0)
                node.Tangent = (t.HitLocation - LastNodePos).Unit();
            node.NodeIndex = Nodes.Size();
            node.BirthTic  = level.time;
            Nodes.Push(node);
            LastNodePos = t.HitLocation;   // spacing measured on the SURFACE, not the offset centerline
        }
    }

    private void XR_ClearRibbon()
    {
        for (int i = 0; i < Nodes.Size(); i++) if (Nodes[i]) Nodes[i].Destroy();
        Nodes.Clear(); Live = false; Painting = false;
    }

    override void Tick()
    {
        Super.Tick();
        if (owner == null || owner.player == null) return;

        CVar cs = CVar.FindCVar("xr_ribbon_node_spacing");
        NodeSpacing = cs ? cs.GetFloat() : 48.0;

        bool holding = (owner.player.cmd.buttons & BT_OFFHANDATTACK) != 0; // constants.zs:866
        if (holding && !Painting)      { XR_ClearRibbon(); Painting = true; }
        else if (!holding && Painting) { Painting = false; Live = (Nodes.Size() > 0); }
        if (Painting) XR_PaintTick();
    }

    States
    {
    Ready:    TNT1 A 1 A_WeaponReady(WRF_NOFIRE|WRF_ALLOWRELOAD); Loop;
    Deselect: TNT1 A 1 { invoker.XR_ClearRibbon(); A_Lower(); } Loop;
    Select:   TNT1 A 1 A_Raise; Loop;
    Fire:     TNT1 A 1; Goto Ready;
    Spawn:    TNT1 A -1; Stop;
    }
}

// ============================================================================
// XR_GravityPathCaster — the WALK driver. StaticEventHandler.
// Mirrors VR_UpdateClimbing (p_user.cpp:1912-1913): MF_NOGRAVITY + Vel = (ASSIGN).
// ============================================================================
class XR_GravityPathCaster : StaticEventHandler
{
    override void WorldTick()
    {
        PlayerInfo pi = players[consoleplayer];
        if (!pi || !pi.mo) return;
        PlayerPawn p = PlayerPawn(pi.mo);
        if (!p) return;

        let power = XR_GravityPath(p.FindInventory("XR_GravityPath"));
        if (!power || !power.Live || power.Nodes.Size() == 0)
        {
            if (p.bNoGravity && p.CountInv("XR_OnRibbon") > 0) XR_LeaveRibbon(p);
            return;
        }

        // Nearest live node. (Node centerline sits 20u OUT from the surface — FIX #3 —
        // so the walk "down" = -SurfaceNormal places the player standing OFF the wall,
        // not clipped into it. This resolves the sketch's internal contradiction.)
        XR_GravityPathNode near = null; double best = 1e9;
        foreach (n : power.Nodes)
        {
            if (!n) continue;
            double d = (p.Pos - n.Pos).Length();
            if (d < best) { best = d; near = n; }
        }

        double onDist = p.Radius + 40.0;
        if (near && best < onDist)
        {
            Vector3 down    = -near.SurfaceNormal;
            Vector3 tangent =  near.Tangent;

            p.bNoGravity = true;
            double drive = (tangent != (0,0,0))
                ? p.Vel.x*tangent.x + p.Vel.y*tangent.y + p.Vel.z*tangent.z : 0;

            CVar sc = CVar.FindCVar("xr_ribbon_walk_speed");
            double spd = sc ? sc.GetFloat() : 8.0;
            double g   = p.GetGravity() * level.gravity / 100.0;

            // ASSIGN, not += (climb-driver rule, p_user.cpp:1913).
            p.Vel = tangent * clamp(drive, -spd, spd) + down * g;

            CVar rmax = CVar.FindCVar("xr_ribbon_roll_cap");
            double cap = rmax ? rmax.GetFloat() : 75.0;
            double targetRoll = clamp(atan2(down.y, down.x), -cap, cap);
            p.ViewRoll = p.ViewRoll * 0.9 + targetRoll * 0.1; // comfort lerp, capped < 90

            if (p.CountInv("XR_OnRibbon") == 0) p.GiveInventory("XR_OnRibbon", 1);
        }
        else if (p.CountInv("XR_OnRibbon") > 0) XR_LeaveRibbon(p);
    }

    private void XR_LeaveRibbon(PlayerPawn p)
    {
        p.bNoGravity = false;
        p.ViewRoll   = p.ViewRoll * 0.8;
        p.TakeInventory("XR_OnRibbon", 1);
    }
}

class XR_OnRibbon : Inventory
{ Default { +INVENTORY.UNDROPPABLE; MaxAmount 1; } }
```

### (b) THE SKIN — SDF shader ribbon. **Two tiers: overlap-blend (now) vs node-array union (build).**

**Tier 0 — the honest v1 skin (loose-pk3, no shader edit):** render the road with `level.AddGlowPanel` the same way XRWhip draws its cord (`vr_whip.zs:403-415`). One soft radial disc per node, spacing < radius so the additive halos overlap into a tube.

```zscript
// Add to XR_GravityPathNode.Tick() — v1 cosmetic (NO shader, NO build):
override void Tick()
{
    Super.Tick();
    if (!master && NodeIndex > 0) { /* orphan cleanup if desired */ }
    // wipeType 15 = full soft disc (gitd_paneltest.zs / vr_whip cord precedent).
    // dirX/dirY = (nx,ny) sticks the YAW to the wall; (0,0) = camera-facing on floor/ceiling.
    // ⚠️HONEST LIMIT: the disc is ALWAYS a vertical/camera-facing billboard
    //   (hw_glowbillboards.cpp:145 uY=h). On floors/ceilings it stands UP, it does
    //   NOT lie flat. That's the primitive's ceiling — accept a beaded tube, not a decal.
    Color col = Color(255, 40, 230, 255); // cyan neon
    bool wallish = abs(SurfaceNormal.z) < 0.5;
    double dx = wallish ? SurfaceNormal.x : 0.0;
    double dy = wallish ? SurfaceNormal.y : 0.0;
    level.AddGlowPanel(col, 26.0, pos.x, pos.y, pos.z, 15, 1.0, dx, dy, NodeIndex);
}
```

**Tier 1 — the REAL seamless skin (shader-lane BUILD, bakes into `doomxr.pk3`).** Extend `vr_sdf_procedural.fp` with a 3D capsule SDF and a **world-space** node array so every fragment samples one continuous field. Union across quads becomes a `min()` of capsules that meet exactly at shared nodes → genuinely seamless, corners included.

```glsl
// ==== vr_sdf_procedural.fp — SHADER-LANE, must rebuild doomxr.pk3 (Vulkan) ====
// Uses ProcessTexel(), NOT main(). (Do NOT write the two forbidden material fn
// names anywhere — the naive substring scan breaks the link.)

// 1) 3D capsule primitive (port of vr_damage_sdf.fp:3-6 segment SDF to 3D):
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// 2) New StreamData uniforms (see build split for the C++ mirror + std140 trap):
//    vec4  u_XR_PathNodes[16];   // xyz = world pos, w = radius
//    int   u_XR_PathNodeCount;

vec4 ProcessTexel() {
    vec2 uv = vTexCoord.st * 2.0 - 1.0;   // existing per-quad UV (kept for endpoints)
    float d = 1e10;

    // --- existing point-shape logic stays for cap/endpoint glyphs (lines 90-107) ---
    // int hash = int(u_IsMSDF); ... circle/box/hex/star ...

    // --- NEW: world-space continuous ribbon. Reconstruct the fragment world pos.
    //   main.fp already carries pixelpos / vWorldNormal (main.fp:322/643/656) — read it,
    //   do NOT try to rebuild from local uv (that's why the beading happens today). ---
    vec3 worldP = pixelpos.xyz;
    for (int i = 0; i < u_XR_PathNodeCount - 1; ++i) {
        vec3  a = u_XR_PathNodes[i].xyz;
        vec3  b = u_XR_PathNodes[i+1].xyz;
        float r = u_XR_PathNodes[i].w;
        d = min(d, sdCapsule(worldP, a, b, r));   // SAME field on every quad → seamless
    }

    float alpha = smoothstep(0.02, 0.0, d);
    float glow  = exp(-5.0 * abs(d));             // existing glow (line 120)
    return vec4(u_MSDFColor.rgb * (alpha + glow * 0.5),
                (alpha + glow * 0.3) * vColor.a * u_MSDFColor.a);
}
```

### (c) THE HOOK — grapple onto nodes. **Loose-pk3, ships now (after the flag fix in §3a).**

Extend `XRWhip.StartGrappleFromAim` (`vr_whip.zs:328-354`) with a nearest-node cone selector *before* the normal LineTrace branch. Static nodes correctly take the **GM_REEL** path (pull the *player* toward the anchor); the `GM_YANK`/`bShootable`-victim branch is for monsters and is irrelevant here.

```zscript
// Insert at the TOP of XRWhip.StartGrappleFromAim(), before the owner.LineTrace call:
XR_GravityPath ribPower = XR_GravityPath(owner.player.mo.FindInventory("XR_GravityPath"));
if (!grappleActive && ribPower && ribPower.Live && ribPower.Nodes.Size() > 0)
{
    // Aim-cone nearest-node select — removes the need for pixel-precise ray/box hits.
    // (Necessary: the grapple trace uses flags=0, so it originates at BODY CENTER,
    //  not OffhandPos — p_map.cpp:5204 — so ray precision alone is unreliable mid-jump.)
    Vector3 hp = owner.pos + (0,0,owner.Height*0.5);
    Vector3 aim = owner.OffhandDir(owner, owner.OffhandAngle, owner.OffhandPitch);
    XR_GravityPathNode best = null; double bestScore = 0.80; // cos-cone gate
    double bestDist = WHIP_GRAPPLE_RANGE;
    foreach (n : ribPower.Nodes)
    {
        if (!n) continue;
        Vector3 to = n.Pos - hp; double dist = to.Length();
        if (dist > WHIP_GRAPPLE_RANGE || dist < 1) continue;
        double c = to.Unit() dot aim;               // alignment with aim
        if (c > bestScore) { bestScore = c; best = n; bestDist = dist; }
    }
    if (best)
    {
        grappleAnchor = best.Pos; grappleMode = GM_REEL; grappleActive = true;
        grappleTimer  = WHIP_GRAPPLE_TIME;
        if (!owner.bNoGravity) { owner.bNoGravity = true; grappleSetNoGrav = true; }
        return;                                      // skip the normal trace branch
    }
}
```

⚠️**FIX #4 — the bNoGravity handoff.** Grapple and walk both own `bNoGravity` + overwrite `Vel`. `EndGrapple` (`vr_whip.zs:395`) clears `bNoGravity` unconditionally → drops you off the ribbon the instant you arrive. Gate it:

```zscript
// In XRWhip.EndGrapple(), replace the unconditional clear with:
if (grappleSetNoGrav && owner.CountInv("XR_OnRibbon") == 0)
    owner.bNoGravity = false;   // only release gravity if NOT already standing on a ribbon
grappleSetNoGrav = false;
// And make the caster's on-rail distance (p.Radius+40 ≈ 56u) >= grapple arrival (56u,
// vr_whip.zs:367) so the handoff window overlaps with no ungoverned tick.
```

---

## 4. BUILD SPLIT

| Piece | Lane | Ships how |
|---|---|---|
| `XR_GravityPathNode`, `XR_GravityPath` (paint), `XR_GravityPathCaster` (walk), `XR_OnRibbon` | **ZScript, loose-pk3** | Now. All APIs are shipped exports: `LineTrace`/`FLineTraceData` (`actor.zs:36-62,809`), `OffhandDir/Pitch/Angle` (`actor.zs:277,278,280,863`), `SecPlane.Normal` (`mapdata.zs:265`), `bNoGravity`/`Vel`, `AddGlowPanel` (`vmthunks.cpp:1184`). |
| Grapple-into-node (XRWhip extension), bNoGravity handoff fix | **ZScript, loose-pk3** | Now. Pure `vr_whip.zs` edit + `+SHOOTABLE` node flag. |
| **Tier-0 skin** (overlap-blend glow tube via `AddGlowPanel`) | **ZScript, loose-pk3** | Now. Honest beaded tube. |
| **Tier-1 skin** (`sdCapsule` + `u_XR_PathNodes[16]` world-space union) | **Shader-lane BUILD → `doomxr.pk3`** | Requires: (1) `vr_sdf_procedural.fp` edit; (2) mirror the array into `StreamData` in **both** `hw_renderstate.h:224-234` **and** the GLSL struct in `vk_shader.cpp`; (3) push per-frame node positions from ZScript via a `GITDShader`-style native bridge; (4) full engine rebuild. **Vulkan ignores loose-pk3 `.fp` overrides** — this cannot be a loose mod. |
| Flat-on-FLOOR/CEILING quads (true decal orientation) | **User's shader/renderer lane** | Either `+FLATSPRITE` actors (`gitd3_deathfx.zs:92` — horizontal only, no SDF glow) **or** extend `AddGlowPanel` to take a full `DVector3` normal and replace the hardcoded `uY=h` world-up (`hw_glowbillboards.cpp:145`) with a surface-aligned up-vector (~20 lines, build lane). |
| True feet-on-wall gravity (vs guided rail) | **Engine/build lane, DEFERRED** | v1 is a guided rail via `Vel`-overwrite; real per-actor gravity direction is the `GravityDir` core patch — out of scope for first playable. |

**HARD-RULE compliance:** shader files are the user's lane — this deliverable **proposes** the `.fp`/`StreamData` additions, it does **not** claim to have edited them. All shader work is flagged BUILD (Vulkan rule). Custom `.fp` uses `ProcessTexel()`; the two forbidden material-function names appear nowhere. Placement is flat-oriented quads, and §5 is explicit that the current primitive can't fully honor "flat on surface" for floor/ceiling.

---

## 5. HONEST LIMITS

1. **Seam continuity is fake at v1.** `vr_sdf_procedural.fp:52` is strictly per-quad local UV; `min(d,d2)` (lines 99/106) unions shapes *within one quad* only. Adjacent quads are independent sprites → beaded seam. **At a floor→wall corner it's worst:** UV discontinuity *and* orientation discontinuity stack → a dark gap or a doubled bright bead exactly at the corner, plus z-fighting. Only the Tier-1 world-space capsule union removes it (corner = `min()` of two capsules sharing a node). **Densify nodes at corners** (halve spacing when the derived normal turns >30° between traces).

2. **Flat-on-surface is not fully achievable through `AddGlowPanel`.** `hw_glowbillboards.cpp:145` hardcodes world-up (`uY=h`); the comment at `:106` confirms panels are *always vertical*. `dirX/dirY` sets yaw only. So floor, ceiling, and slope segments **cannot lie flat** via this primitive — they stand up as vertical/camera-facing billboards. Honoring HARD RULE 5 ("flat oriented quads on the surface") for non-vertical surfaces needs `+FLATSPRITE` (horizontal only, no glow) or a renderer patch (build lane).

3. **VR perf is fill-bound, not slot-bound.** The `StreamData`/`uDataIndex` UBO caps at ~64 entries — but the real risk is **additive overdraw**: every panel is `RenderStyle Add`, and dozens of overlapping soft-glow quads run the full `ProcessTexel` (with `fract`/`sin` noise, `.fp:83,111`) at **2× pixels in stereo**, feeding bloom. **Cap concurrent visible panels to ~16-24** (cull by distance in the caster's existing nearest-node loop) and keep radius modest. Tier-1 collapses N sprites into a handful of large quads sampling one field — strictly cheaper.

4. **std140 UBO alignment is a live landmine.** The Tier-1 node array goes *before* `u_MSDFColor` in `StreamData`. The C++ struct at `hw_renderstate.h:224-234` already carries the fix for the *current* fields — three explicit `padding` ints, with a source comment warning that without them *"every field after it (all GITD fog/regime uniforms) shifts 12 bytes → corrupt reads (black world + mis-coloured glyph spray)."* A `vec4[16]` is naturally 16B-aligned, but you **must** mirror it byte-identically in both `hw_renderstate.h` and the GLSL `StreamData` in `vk_shader.cpp`, and keep the existing pads intact.

5. **True wall-walk still needs the gravity core.** v1 "walk" is a guided rail — `MF_NOGRAVITY` + `Vel`-overwrite along the tangent, exactly like `VR_UpdateClimbing` (`p_user.cpp:1912-1913`). It *feels* like walking the surface but it is not per-actor gravity reorientation. Real feet-on-wall/upside-down-ceiling is the `GravityDir` engine patch, deferred.

---

## 6. BUILD ORDER

**v1 — ZScript road + grapple + honest tube skin (loose-pk3, playable now). ← FIRST PLAYABLE MILESTONE.**
1. `XR_GravityPathNode` with the **fixed** Default block (`+NOGRAVITY +NOINTERACTION +SHOOTABLE`, **no `+NOBLOCKMAP`**, Radius 18).
2. `XR_SurfaceNormalFromTrace()` — hand-verify on 3 surface classes on a smoke-test map (add one, since `SecPlane.Normal` has no existing repo caller to lean on).
3. `XR_GravityPath` paint loop — nodes spawn every ~48u, offset 20u out from the surface (FIX #3), normals point outward.
4. `XR_GravityPathCaster` walk driver — `Vel = tangent*drive + down*g` (ASSIGN). Test on a gentle ramp first.
5. Grapple: XRWhip nearest-node cone selector + `EndGrapple` bNoGravity gate (FIX #4).
6. Tier-0 skin: `AddGlowPanel` disc per node (wipeType 15, 50% overlap).
   → **Milestone:** paint an L up a wall, walk it, jump-and-hook it, reel in, land. Entirely loose-pk3.

**v2 — Tier-1 SDF ribbon skin (shader-lane BUILD).**
7. Add `sdCapsule()` + `u_XR_PathNodes[16]` + `u_XR_PathNodeCount` to `vr_sdf_procedural.fp`.
8. Mirror the array into `StreamData` (`hw_renderstate.h` **and** `vk_shader.cpp`), std140-correct; add a `GITDShader`-style native to push node positions per frame.
9. Rebuild `doomxr.pk3`. → seamless world-space ribbon.

**v3 — flat-on-surface upgrade (renderer lane).** Extend `AddGlowPanel` to a full `DVector3` normal + surface-aligned up-vector (or `+FLATSPRITE` fallback for horizontals).

**v4 — polish.** Corner node densification, per-segment color/pulse via `u_MSDFColor`/`u_MSDFGlitch`, charge economy cvars (`xr_ribbon_*`), true `GravityDir` wall-walk (deferred engine core).

---

**Key file:symbol anchors (all verified live):** `wadsrc/static/shaders/glsl/vr_sdf_procedural.fp:52,99,106,120` (per-quad UV + union + glow) · `src/rendering/hwrenderer/scene/hw_glowbillboards.cpp:106,145` (world-up hardcode) · `src/scripting/vmthunks.cpp:1184` (`AddGlowPanel` sig, 2D dir only) · `src/playsim/p_user.cpp:1864,1912-1913` (`VR_UpdateClimbing` NOGRAVITY+Vel=) · `src/playsim/p_map.cpp:5268,5270` (trace mask MF_SHOOTABLE + ML_BLOCKEVERYTHING) · `src/playsim/p_maputl.cpp:508` (NOBLOCKMAP skips blockmap link) · `wadsrc/static/zscript/radiance/gitd_buckshot.zs:75-81,84` (wall-normal + 1.5u offset) · `wadsrc/static/zscript/actors/doom/vr_whip.zs:341,367,395,403-415` (grapple branch, arrival, EndGrapple, cord) · `src/common/rendering/hwrenderer/data/hw_renderstate.h:224-234` (MSDF uniforms + std140 padding trap) · `wadsrc/static/gldefs.txt:11-13` (SIGL→shader bind).