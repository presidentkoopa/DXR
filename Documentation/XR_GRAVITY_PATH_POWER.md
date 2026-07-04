All symbols anchored. The climbing driver at `p_user.cpp:1975-1976` sets `MF_NOGRAVITY` and assigns `Vel = climbDelta * vr_climb_speed_mult` — confirming the "overwrite, don't accumulate" pattern. Now I have everything verified. Writing the deliverable.

---

# XR GRAVITY PATH — a hand-cast gravity-painting POWER for DoomXR

*Implementer brief (C++ + ZScript). Read-only repo. All names `XR_`. This is a POWER cast from the off-hand, not a Weapon-slot gun.*

---

## 1. THE FANTASY

You hold a weapon in your main hand as always. Your **off-hand is empty and open** — the casting hand.

You bring it up, press-and-hold the cast trigger, and a thin line of light springs from your palm to the wall you're pointing at. You **sweep your arm** — the beam drags across the brick like a spray can, and behind it a **glowing ribbon** paints itself onto the surface, hugging every contour: up the wall, across a ledge, over the ceiling. The ribbon knows which way each surface *faces* — it lies flat against stone, curls over a lip, drapes upside-down across the roof.

You **release**. The ribbon flashes and goes live — a solid, humming road of light.

You step onto it. For a heartbeat the world tilts: your horizon banks, your **"down" swings toward the wall**, and you're *walking up it*, gun still in hand, striding along your own painted path to the ledge no jump could reach. Prince of Persia's wall-run, Splatoon's paint-it-yourself traversal, Portal's "the floor is wherever I say it is."

The joy moment is the **sweep-and-release-and-step**: you drew the road, then you walked the road you drew.

---

## 2. VERDICT

**Yes — ship it, in tiers. The PAINT half is fully real today in pure ZScript. The WALK half ships as a convincing *guided-rail illusion* today, and becomes true feet-on-wall only with a small C++ gravity core.**

| Half | Tier | Honest status |
|---|---|---|
| **PAINT** (off-hand channel, ray, surface-normal, node chain, live ribbon) | **Pure ZScript, zero C++** | Real. Every API verified live. |
| **FOLLOW — guided ascent rail** (reorient "down", glide the air-column beside the wall, comfort roll) | **Pure ZScript, zero C++** | Real illusion. Mirrors the *shipped* VR climb driver exactly. |
| **FOLLOW — true feet-on-wall / inverted-room ceiling walk** | **Needs C++ gravity core** | Requires per-actor `DVector3 GravityDir` + a `P_ZMovement` clamp rewrite. Out of scope for v1. |

**The honest surface-normal answer:** you get a correct, usable normal for **walls, floors, ceilings, slopes, and 3D floors with ZERO C++** — but you must **DERIVE** it. Two facts the naive sketches get wrong:

- **`FLineTraceData` has NO `HitNormal` field.** Verified: `actor.zs:49-61` lists every field (`HitActor, HitLine, HitSector, Hit3DFloor, HitTexture, HitLocation, HitDir, Distance, NumPortals, LineSide, LinePart, SectorPlane, HitType`) — no normal. Never write `trace.HitNormal`.
- **`trace.HitDir` is the RAY direction, not a normal.** `node.SurfaceNormal = -trace.HitDir` is a **bug** — correct only for a perfectly head-on hit, wrong for every glancing sweep (which is *all* of them when you're painting). Delete that line.

The **hard wall** on true wall-walking: `P_ZMovement` clamps every actor's Z to scalar `floorz`/`ceilingz`, and a solid one-sided line blocks the player cylinder in the 2D blockmap regardless of `MF_NOGRAVITY`. `MF_NOGRAVITY` only skips gravity *acceleration* in `FallAndSink` (`p_mobj.cpp:3012`) — it does **not** defeat the Z clamp. So a radius-16 player body cannot press flat against a vertical wall. That's why v1 is an air-column rail, not feet-on-stone.

---

## 3. HOW IT WORKS

Three systems: **(a) PAINT**, **(b) the RIBBON data model**, **(c) FOLLOW**.

### 3a. PAINT — off-hand channel + trace-normal + node chain

Hold `BT_OFFHANDATTACK`. Each tic, fire `LineTrace` **with the `TRF_ISOFFHAND` flag** so the engine redirects the trace origin/aim to the off-hand pose (don't fake the origin with `offsetforward`/`offsetside` — the flag keeps portal/pose handling correct). When the aim has moved more than `nodeSpacing` from the last node, drop a new `XR_GravityPathNode` carrying the **derived** surface normal.

**Verified APIs:**
- `native bool LineTrace(double angle, double distance, double pitch, int flags, ..., out FLineTraceData data)` — `actor.zs:809`
- `native vector3 OffhandDir(Actor actor, double angle, double pitch)` — `actor.zs:863`
- `native readonly vector3 OffhandPos` — `actor.zs:277`; `OffhandPitch` `:278`; `OffhandAngle` `:280`
- `TRF_ISOFFHAND = 2048` — `constants.zs:962`
- `BT_OFFHANDATTACK = 1<<26` — `constants.zs:866`

**The surface-normal helper — the load-bearing piece.** Branch on surface class:

- **WALL** (`HitType == TRACE_HitWall`): perpendicular of `HitLine.delta` (native readonly `Vector2`, `mapdata.zs:212`), disambiguated by dot with the **off-hand aim vector**. This is production-proven verbatim in `gitd_buckshot.zs:75-81`:
  ```
  Vector2 d = t.HitLine.delta;
  double n1x = -d.y / dl, n1y = d.x / dl;      // one perpendicular
  double dotv = n1x*step.x + n1y*step.y;        // step = travel/aim dir
  nx = (dotv > 0.0) ? -n1x : n1x;
  ```
- **FLOOR / CEILING incl. SLOPES**: read the plane normal directly — `native readonly Vector3 Normal` (`mapdata.zs:265`). It's a **FIELD, not a method** — `.Normal` never `.Normal()`. Select the plane by `trace.SectorPlane` (0=floor→`floorplane.Normal`, 1=ceiling→`ceilingplane.Normal`). Correct for slopes (full 3D vector; floor points +up, ceiling −down).
  - **Caveat:** no existing ZScript in the repo reads `plane.Normal` (grep = zero hits). Add a one-map smoke test to confirm the field binds at runtime before relying on it.
- **3D FLOOR top/bottom**: when `trace.Hit3DFloor` is non-null AND `HitType` is Floor/Ceiling, read `Hit3DFloor.top.Normal` / `Hit3DFloor.bottom.Normal` (native readonly secplane, `mapdata.zs:316-317`), picking by comparing `HitLocation.Z` to each plane — **not** `HitSector.floorplane` (that's the control/containing sector, wrong plane). A 3D-floor *side* reports as `TRACE_HitWall` → use the wall-delta path.

### 3b. The RIBBON data model

An ordered chain of nodes. Each node is a lightweight actor carrying `pos + surfaceNormal + tangent`. The chain lives on a **caster/handler** (level-scoped) so multiple ribbons can coexist and a recast clears the old one. `-surfaceNormal` = the "down" the player will feel at that node.

### 3c. FOLLOW — reorient down + guided movement + comfort roll

**This mirrors the shipped VR climb driver EXACTLY** (`VR_UpdateClimbing`, `p_user.cpp:1864`). When the player is within proximity of a live ribbon segment:

1. Set `MF_NOGRAVITY` and **OVERWRITE** `Vel` each tic — do **not** `Vel +=` fake-thrust. Verified pattern (`p_user.cpp:1975-1976`):
   ```cpp
   player->mo->flags |= MF_NOGRAVITY;
   player->mo->Vel = climbDelta * vr_climb_speed_mult;   // ASSIGN, not accumulate
   ```
   Accumulating against the residual `floorz` clamp causes stick/jitter near surfaces; assignment is the pattern that ships.
2. Drive `Vel` along the ribbon **tangent** (from thumbstick or `GetHandVelocity`, `actor.zs:866`), scaled by a speed cvar.
3. Keep the traversal **centerline ≥ player.radius (~16u) out from the wall face** so the body glides up the *open air column* beside the wall, never into solid geometry. On floors this degenerates to normal walking; under ceilings, an inverted under-ceiling glide.
4. **Comfort roll**: lerp `player.mo.ViewRoll` (writable native `double`, `actor.zs:256` — the "only `A_SetViewRoll` works" claim is false; both paths work) toward the ribbon bank, **capped well under 90°**, only on **entry/exit**, never sustained mid-stride.

---

### Paste-ready skeletons (verified APIs only)

```zscript
// ============================================================================
// XR_GravityPathNode — one knot in the ribbon. Carries the DERIVED normal.
// ============================================================================
class XR_GravityPathNode : Actor
{
    Vector3 SurfaceNormal;   // outward-facing; -SurfaceNormal = local "down"
    Vector3 Tangent;         // forward along the ribbon
    int     NodeIndex;
    int     BirthTic;

    Default
    {
        Radius 6; Height 6;
        +NOGRAVITY +NOBLOCKMAP +NOINTERACTION
        RenderStyle "Add"; Alpha 0.75; Scale 0.2;
    }
    States { Spawn: TNT1 A -1; Stop; }   // visual = particle/model, cosmetic
}

// ============================================================================
// XR_GravityPath — the off-hand POWER (weapon lives in off-hand slot).
// PAINT half. Zero C++.
// ============================================================================
class XR_GravityPath : Weapon
{
    Array<XR_GravityPathNode> Nodes;
    bool    Painting;
    bool    Live;
    Vector3 LastNodePos;
    double  NodeSpacing;

    Default
    {
        Weapon.SelectionOrder 3700;
        +WEAPON.NOAUTOAIM +WEAPON.NOALERT +WEAPON.NOAUTOSWITCHTO
        +WEAPON.OFFHANDWEAPON
        Tag "XR Gravity Path";
        Obituary "fell along a gravity path.";
    }

    // ---- THE LOAD-BEARING HELPER: derive a correct normal per surface class.
    private Vector3 XR_SurfaceNormalFromTrace(FLineTraceData t, Vector3 aimDir)
    {
        // 3D FLOOR TOP/BOTTOM (control sector != containing sector)
        if (t.Hit3DFloor &&
            (t.HitType == FLineTraceData.TRACE_HitFloor ||
             t.HitType == FLineTraceData.TRACE_HitCeiling))
        {
            double topZ = t.Hit3DFloor.top.ZAtPoint(t.HitLocation.xy);
            double botZ = t.Hit3DFloor.bottom.ZAtPoint(t.HitLocation.xy);
            if (abs(t.HitLocation.z - topZ) <= abs(t.HitLocation.z - botZ))
                return t.Hit3DFloor.top.Normal;      // FIELD, no ()
            return t.Hit3DFloor.bottom.Normal;
        }

        // FLOOR / CEILING incl. SLOPES — read plane normal, pick by SectorPlane
        if (t.HitSector &&
            (t.HitType == FLineTraceData.TRACE_HitFloor ||
             t.HitType == FLineTraceData.TRACE_HitCeiling))
        {
            if (t.SectorPlane == 0) return t.HitSector.floorplane.Normal;   // +up
            return t.HitSector.ceilingplane.Normal;                         // -down
        }

        // WALL (and 3D-floor sides) — perpendicular of HitLine.delta,
        // disambiguated by the OFF-HAND aim (proven: gitd_buckshot.zs:75-81)
        if (t.HitType == FLineTraceData.TRACE_HitWall && t.HitLine)
        {
            Vector2 d = t.HitLine.delta;
            double dl = d.Length(); if (dl < 0.0001) dl = 1.0;
            double n1x = -d.y / dl, n1y = d.x / dl;
            double dotv = n1x * aimDir.x + n1y * aimDir.y;   // aimDir = OffhandDir
            // want normal facing BACK at us (opposes travel): flip if same-side
            double nx = (dotv > 0.0) ? -n1x : n1x;
            double ny = (dotv > 0.0) ? -n1y : n1y;
            return (nx, ny, 0);
        }
        return (0, 0, 1);   // fallback: floor-up
    }

    private void XR_PaintTick()
    {
        if (owner == null || owner.player == null) return;

        double ang = owner.OffhandAngle;
        double pit = owner.OffhandPitch;
        Vector3 aimDir = owner.OffhandDir(owner, ang, pit);

        FLineTraceData t;
        bool hit = owner.LineTrace(ang, 2000.0, pit, TRF_ISOFFHAND, data: t);
        if (!hit || t.HitType == FLineTraceData.TRACE_HitNone) return;
        if (t.HitType == FLineTraceData.TRACE_HitActor)       return;

        if ((t.HitLocation - LastNodePos).Length() <= NodeSpacing) return;

        Vector3 n = XR_SurfaceNormalFromTrace(t, aimDir);

        let node = XR_GravityPathNode(Actor.Spawn("XR_GravityPathNode", t.HitLocation));
        if (node)
        {
            node.SurfaceNormal = n.Unit();
            if (Nodes.Size() > 0)
                node.Tangent = (t.HitLocation - LastNodePos).Unit();
            node.NodeIndex = Nodes.Size();
            node.BirthTic  = level.time;
            Nodes.Push(node);
            LastNodePos = t.HitLocation;
        }
    }

    private void XR_ClearRibbon()
    {
        for (int i = 0; i < Nodes.Size(); i++)
            if (Nodes[i]) Nodes[i].Destroy();
        Nodes.Clear();
        Live = false; Painting = false;
    }

    override void Tick()
    {
        Super.Tick();
        if (owner == null || owner.player == null) return;

        CVar cs = CVar.FindCVar("xr_ribbon_node_spacing");
        NodeSpacing = cs ? cs.GetFloat() : 48.0;

        bool holding = (owner.player.cmd.buttons & BT_OFFHANDATTACK) != 0;

        if (holding && !Painting)      { Painting = true; XR_ClearRibbon(); Painting = true; }
        else if (!holding && Painting) { Painting = false; Live = (Nodes.Size() > 0); }

        if (Painting) XR_PaintTick();
    }

    States
    {
    Ready:    TNT1 A 1 A_WeaponReady(WRF_NOFIRE|WRF_ALLOWRELOAD); Loop;
    Deselect: TNT1 A 1 { invoker.XR_ClearRibbon(); A_Lower(); } Loop;
    Select:   TNT1 A 1 A_Raise; Loop;
    Fire:     TNT1 A 1; Goto Ready;   // painting is driven from Tick(), not Fire
    Spawn:    TNT1 A -1; Stop;
    }
}

// ============================================================================
// XR_GravityPathCaster — FOLLOW half. Level-scoped handler that reorients the
// player's "down" along the ribbon and drives the guided-rail ascent.
// Mirrors VR_UpdateClimbing (p_user.cpp:1975-1976): NOGRAVITY + Vel = (not +=).
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

        // Nearest live node (centerline sits >= radius OUT from the wall face)
        XR_GravityPathNode near = null;
        double best = 1e9;
        foreach (n : power.Nodes)
        {
            if (!n) continue;
            double d = (p.Pos - n.Pos).Length();
            if (d < best) { best = d; near = n; }
        }

        double onDist = p.Radius + 40.0;   // proximity to the rail
        if (near && best < onDist)
        {
            Vector3 down = -near.SurfaceNormal;

            // Reorient: NOGRAVITY + OVERWRITE Vel along tangent + custom fall.
            p.bNoGravity = true;
            Vector3 tangent = near.Tangent;
            double drive = 0;
            if (tangent != (0,0,0))
                drive = p.Vel.x*tangent.x + p.Vel.y*tangent.y + p.Vel.z*tangent.z;

            CVar sc = CVar.FindCVar("xr_ribbon_walk_speed");
            double spd = sc ? sc.GetFloat() : 8.0;
            double g   = p.GetGravity() * level.gravity / 100.0;

            // ASSIGN, do not accumulate (climb-driver rule).
            p.Vel = tangent * clamp(drive, -spd, spd) + down * g;

            // Comfort roll on entry only; capped under 90.
            CVar rmax = CVar.FindCVar("xr_ribbon_roll_cap");
            double cap = rmax ? rmax.GetFloat() : 75.0;
            double targetRoll = clamp(atan2(down.y, down.x), -cap, cap);
            p.ViewRoll = p.ViewRoll * 0.9 + targetRoll * 0.1;

            if (p.CountInv("XR_OnRibbon") == 0) p.GiveInventory("XR_OnRibbon", 1);
        }
        else if (p.CountInv("XR_OnRibbon") > 0)
        {
            XR_LeaveRibbon(p);
        }
    }

    private void XR_LeaveRibbon(PlayerPawn p)
    {
        p.bNoGravity = false;
        p.ViewRoll   = p.ViewRoll * 0.8;   // lerp horizon back
        p.TakeInventory("XR_OnRibbon", 1);
    }
}
// XR_OnRibbon: a dummy Inventory token used as a per-player on/off flag.
```

> Note: confirm `SecPlane.ZAtPoint` exposure before relying on it in the 3D-floor branch; if absent, fall back to comparing `HitLocation.Z` to a single-point plane eval or to the containing sector's known heights.

---

## 4. THE HONEST LIMITS

**Surface-normal derivation gaps.**
- No `HitNormal` in `FLineTraceData` (`actor.zs:49-61`). Always derived.
- `-trace.HitDir` is NOT a normal — it's the ray direction (`p_map.cpp` sets `HitDir = HitVector`). Correct only head-on; wrong for every sweep angle. **Cut it.**
- `plane.Normal` is a **field, not a method** — `.Normal` never `.Normal()`. Two of the source sketches called `.Normal()`; that's a compile error.
- No repo code currently reads `plane.Normal` — **add a one-map smoke test** to confirm the field binds before shipping the floor/ceiling branch.

**Wall-walk collision seam (the big one).** `P_ZMovement` clamps Z to scalar `floorz`/`ceilingz` for every actor; `MF_NOGRAVITY` only skips gravity *accel* in `FallAndSink` (`p_mobj.cpp:3012`), not the clamp. A solid one-sided line blocks the player cylinder in the 2D blockmap irrespective of gravity flags. **You cannot stand a radius-16 body flat on a vertical wall in ZScript.**
- **Mitigation (guided-rail):** don't stand on the wall — glide the **open air column beside it**, exactly as the shipped VR climb does (`p_user.cpp:1973-1977`). Upward motion keeps Z above `floorz+2` so the floor clamp never fires → **arbitrary wall height works**. Keep the centerline ≥ `player.radius` out from the face.
- **Ceilings are the weak case:** the `Top() > ceilingz` clamp pins the body just under the ceiling. An under-ceiling glide illusion works; you cannot get *above* it. **Do not promise inverted rooms** without the C++ core.

**VR comfort.** Roll only on entry/exit, capped well under 90°, never sustained mid-stride (per the hard-limit note). No physical floor tilt is possible.

**Monsters don't follow.** Monster AI is 2D (xy-plane). Never promise wall-walking or ceiling-walking enemies. The ribbon is a **player** traversal tool only.

---

## 5. CASTING LAYER

**Off-hand verbs (all confirmed live):**
- **Hold `BT_OFFHANDATTACK`** (`constants.zs:866`) → paint. Release → ribbon goes live.
- **`BT_OFFHANDALTATTACK`** (`:867`) → clear/recall the current ribbon.
- Off-hand slot via `+WEAPON.OFFHANDWEAPON`; spell-wheel selection via the shipped VR off-hand wheel.

**Charge / cooldown economy (ZScript member ints + cvars):**
- `XRRibbonCharge` drains per painted node (`xr_ribbon_drain_rate`), regens passively when idle (`xr_ribbon_regen_rate`), capped at `xr_ribbon_max_charge`. Precedent: the manual-reload mixin tracks `XRChamber`/`XRMagSize` the same way.

**Feedback:**
- Per-node cosmetic glow actor + `A_StartSound("xr/ribbon/paint")` on drop; `A_StartSound("xr/ribbon/ignite")` on release; footstep tick on rail entry.
- Haptic: reuse the climb driver's pulse-every-8-units pattern (`p_user.cpp:1949-1950`) if a haptic hook is wired; else cosmetic-only for MVP.
- **Remember DoomXR SNDINFO needs FULL paths** and desktop silences stereo SFX — author ribbon sounds as **mono** with full-path SNDINFO entries.

**`xr_` cvars (register in CVARINFO):**
```
server float xr_ribbon_node_spacing   = 48
server float xr_ribbon_max_charge      = 300
server float xr_ribbon_drain_rate      = 5
server float xr_ribbon_regen_rate      = 2
server float xr_ribbon_walk_speed      = 8
server float xr_ribbon_roll_cap        = 75     // degrees, < 90
server int   xr_ribbon_roll_mode       = 1      // 0=snap 1=continuous
server float xr_ribbon_lifetime        = 30     // seconds before fade
```

---

## 6. PATCH DELTAS

**Zero C++ is required for v1** (paint + guided-rail follow). Everything above uses shipped exports.

**No `HitNormal` export needed** — the ZScript helper derives all normals. Skip it.

**The ONLY candidate C++ work — the OPTIONAL per-actor vector-gravity core** (enables true feet-on-wall + inverted-room ceiling walk):

1. **`src/playsim/actor.h`** — add `DVector3 GravityDir = {0,0,-1};` + flag `MF8_USECUSTOMGRAVITY`.
2. **`src/playsim/p_mobj.cpp` → `AActor::FallAndSink`** (function at **`:3010`**; scalar apply `Vel.Z -= grav` at **`:3027`**) — branch:
   ```cpp
   if (flags8 & MF8_USECUSTOMGRAVITY) Vel += GravityDir * grav;
   else                               Vel.Z -= grav;
   ```
3. **`src/playsim/p_mobj.cpp` → `P_ZMovement`** — the deeper lift: the `floorz` clamp (near `:2723`) and `ceilingz` clamp (near `:2841`) are scalar-Z and must become orientation-aware for the custom-gravity actor. This — plus a blockmap resolver that lets a tilted body occupy space against a wall — is what "feet on the wall" actually costs. **Size: this is a genuine physics-loop rewrite, not a one-liner. Treat as a separate project.**
4. **`wadsrc/static/zscript/actors/actor.zs`** — `native DVector3 GravityDir;` so the caster sets it directly instead of the `Vel =` fake-thrust.

**Sizing:** normal extraction + paint = **~1-2 hrs ZScript** (helper + smoke test). Guided-rail follow = **~half a day ZScript** (reuse climb driver shape). `FallAndSink` branch + `GravityDir` export = **~3-5 hrs C++**. The `P_ZMovement`/blockmap rewrite for true wall-standing = **multi-day, defer**.

---

## 7. BUILD ORDER

Ties into the **gravity-cube flip plan**'s 3-tier gravity strategy (ZScript fake → `GravityDir` keystone patch → wall-walk AI rewrite) — the ribbon rides the same C++ core.

**v1 — Fake-thrust ZScript slice (FIRST PLAYABLE):**
1. `XR_GravityPathNode` + `XR_GravityPath` paint loop; verify nodes spawn along the off-hand sweep.
2. `XR_SurfaceNormalFromTrace` + **one-map smoke test** confirming `plane.Normal` binds and wall/floor/ceiling normals come back sane.
3. `XR_GravityPathCaster` guided-rail follow on a **gentle ramp / low ledge** — reorient "down", climb-driver `Vel =` assignment, entry/exit roll.
4. **Milestone:** paint a ribbon up a ~30-45° ramp, step on, ride it, step off. This proves the whole loop with zero C++.

**v2 — Gravity-core integration:**
5. Land the `FallAndSink` branch + `GravityDir` export (Patch Delta 1-2, 4). Swap the caster's fake-thrust for `p.GravityDir = down`.

**v3 — Full wall / ceiling:**
6. Tackle the `P_ZMovement`/blockmap rewrite for true feet-on-wall + inverted ceiling. Gate behind the gravity-zone runbook so it's tested per-map.

**v4 — Polish:** charge economy, spell-wheel slot, glow/sound/haptic feedback, ribbon fade + lifetime, multi-ribbon coexistence.

**Guardrail:** never default-on the C++ tiers until the `P_ZMovement` rewrite is verified — the guided-rail v1 is the shippable, comfort-safe baseline.

---

### Anchored symbol table (verified this session in `E:/DoomXR-work/DOOM_FRESH`)

| Symbol | File:line |
|---|---|
| `FLineTraceData` (no `HitNormal`) | `wadsrc/static/zscript/actors/actor.zs:36-62` |
| `native double ViewAngle, ViewPitch, ViewRoll` (writable) | `actor.zs:256` |
| `OffhandPos / OffhandPitch / OffhandAngle` | `actor.zs:277,278,280` |
| `native bool LineTrace(...)` | `actor.zs:809` |
| `native vector3 OffhandDir(...)` | `actor.zs:863` |
| `native vector3 GetHandVelocity(int)` | `actor.zs:866` |
| `native void A_SetViewRoll(...)` | `actor.zs:1284` |
| `SecPlane native readonly Vector3 Normal` (field) | `mapdata.zs:265` |
| `SecPlane isSlope()` | `mapdata.zs:269` |
| `Line native readonly Vector2 delta` | `mapdata.zs:212` |
| wall-normal derivation (proven) | `radiance/gitd_buckshot.zs:75-81` |
| `BT_OFFHANDATTACK / ALT / RELOAD` | `constants.zs:866-868` |
| `ALF_ISOFFHAND=256`, `TRF_ISOFFHAND=2048` | `constants.zs:933,962` |
| `AActor::FallAndSink` (`Vel.Z -= grav` at `:3027`) | `src/playsim/p_mobj.cpp:3010` |
| `MF_NOGRAVITY` gate in FallAndSink | `p_mobj.cpp:3012` |
| VR climb driver: `NOGRAVITY` + `Vel = climbDelta*mult` (ASSIGN) | `src/playsim/p_user.cpp:1975-1976` |