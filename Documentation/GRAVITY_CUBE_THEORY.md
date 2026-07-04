# Gravity Cube Theory Report â€” Flippable, Portal-Linked Cubes in DoomXR

**For:** DoomXR / QZDoom engine fork
**Scope:** Design a cube-map where a button flips any/all cubes' gravity/orientation, cubes are linked by portals, and "all monsters n shit react."
**Source root cited throughout:** `C:\Users\Command\DoomXR\DoomXR-doomxr\DoomXR-doomxr\src` (line numbers verified against your tree).

---

## 1. TL;DR â€” the one-paragraph truth

DoomXR inherits GZDoom's physics, and in that engine **gravity is a scalar, not a vector.** `AActor::GetGravity()` (`src/playsim/actorinlines.h:86-90`) returns a single `double`, and the entire gravity model is `Vel.Z -= grav` inside `AActor::FallAndSink()` (`src/playsim/p_mobj.cpp:2967, 2971`). "Down" is not a variable anywhere â€” it is the literal `-Z` axis, baked into hundreds of comparisons: `floorz`/`ceilingz` are scalar Z heights (`src/playsim/actor.h:1168`), monster locomotion is an 8-direction XY compass LUT with zero Z term (`src/playsim/p_enemy.cpp:103-104, 558-559`), the blockmap is a 2D X/Y grid (`src/playsim/p_blockmap.h:38-39, 69`), and linked portals translate in XY + yaw only, never rotating the gravity/up-vector (`src/playsim/portal.cpp:237-240`). **Consequently: a "true" cube-flip where the player and monsters genuinely stand and walk on a wall requires an engine gravity-vector plus an AI/collision rewrite. But a *convincing fake* â€” props, gibs, projectiles and the player visibly falling toward a new "down," monsters converted to floaters or pre-oriented variants, and portal-anchored teleport-with-roll transitions â€” is shippable today in pure ZScript with no recompile.**

**Recommended path:** Ship the **pure-ZScript fake first** (Tier 1) to prove the game feel and the portal-cube layout. Then land **one keystone C++ patch** â€” turn scalar gravity into a `DVector3 GravityDir` (Tier 2) â€” which unlocks *real* physics for the player, props and projectiles under arbitrary gravity. Treat orientation-aware wall-walking monsters (Tier 3) as an optional deep dive; in the meantime use a **flying/floating monster roster** so Tier 2 alone makes the cubes feel alive. And bake in one hard VR invariant from day one: **the physical play-space floor cannot rotate**, so every flip is routed through a comfort transition, never a sustained in-flight camera roll.

---

## 2. Why this is hard â€” the hardcoded up-axis

Every subsystem you'd need to touch assumes `-Z` is down. This is not a knob; it's an architectural assumption. The exact code:

### 2.1 Gravity is a scalar on one axis
```cpp
// src/playsim/actorinlines.h:86-90  (verified verbatim)
inline double AActor::GetGravity() const
{
    if (flags & MF_NOGRAVITY) return 0;
    return Level->gravity * Sector->gravity * Gravity * 0.00125;
}
```
All three multipliers (`Level->gravity`, `Sector->gravity`, `Actor->Gravity`) are scalar doubles. The result is consumed exactly once per tick, per actor:
```cpp
// src/playsim/p_mobj.cpp:2967 / 2971  (verified verbatim â€” AActor::FallAndSink)
Vel.Z -= grav + grav;   // double gravity running off a ledge
...
Vel.Z -= grav;          // normal fall
```
`grav` is pulled at `p_mobj.cpp:2591` (`double grav = mo->GetGravity();`). **No other velocity component is ever touched by gravity.** `sv_gravity` (`p_mobj.cpp:156`, default 800) is likewise scalar.

### 2.2 Floor/ceiling are scalar Z, and clipping is a hard inequality
```cpp
// src/playsim/actor.h:1168
double floorz, ceilingz;   // closest together of contacted secs
```
```cpp
// src/playsim/p_mobj.cpp:2672   floor hit
if (mo->Z() <= mo->floorz + 2) ...
// src/playsim/p_mobj.cpp:2785   ceiling hit
if (mo->Top() > mo->ceilingz) ...
```
`floorz`/`ceilingz` cannot encode an arbitrary plane offset along a non-Z axis. There is no "floor" along `+X`. A sideways-gravity actor is literally "below floor" forever in Z terms and never rests.

### 2.3 Monster AI is a 2D compass
```cpp
// src/playsim/p_enemy.cpp:103-104
double xspeed[8] = { ... };   // cos of 8 compass dirs
double yspeed[8] = { ... };   // sin of 8 compass dirs
// src/playsim/p_enemy.cpp:558-559  (P_Move)
tryx = actor->X() + speed * xspeed[movedir];
tryy = actor->Y() + speed * yspeed[movedir];
```
`movedir` is one of 8 XY directions with **zero Z component**. `P_NewChaseDir` computes the target delta as a 2D `Vec2To` (`p_enemy.cpp:960/964`). There is no code path for a monster to path along a wall or ceiling. **"Monsters will just react" is false** â€” under sideways gravity a walker keeps pathing on the horizontal plane and floats or gets stuck. Dropoff/step avoidance is Z-only (`p_enemy.cpp:985` `floorz - dropoffz > MaxDropOffHeight`; post-move Z-snap `p_enemy.cpp:640-646`), so a rotated monster reads every real slope as an impassable Z cliff.

### 2.4 The blockmap and collision API are 2D by construction
```cpp
// src/playsim/p_blockmap.h:38-39, 69
int bmapwidth, bmapheight;         // no Z dimension
offset = y * bmapwidth + x;        // 2D bucket index
```
`P_CheckPosition` and `P_TryMove` take a **`const DVector2 &pos`** (`src/playsim/p_map.cpp:1793, 2343`) â€” the collision broadphase is horizontal by signature. Step-up (`p_map.cpp:2453` `tm.floorz - thing->Z() > MaxStepHeight`) and dropoff rejection (`p_map.cpp:2516`) are scalar Z.

### 2.5 Portals translate, they don't reorient
```cpp
// src/playsim/portal.cpp:237-240  (linked portals)
mSinRot = 0.; mCosRot = 1.; mAngleDiff = nullAngle;  // "no angular difference"
```
Linked line portal crossing (`p_map.cpp:2628-2639`) applies `mDisplacement` (a `DVector2`, `portal.h:187`) only â€” no Z transform, no velocity-Z transform, no up-vector carry. Sector-plane portals track a 2D displacement too and are **hard-disabled on sloped planes** (`portal.cpp:885-889`). `secplane_t::ZatPoint` divides by `-1/c` (`r_defs.h:315, 361`) and is undefined for a vertical plane â€” and it's called from the renderer, sound, AI and 3D-floor code, not just collision.

### 2.6 The friction / terminal-velocity / splash constants are all Vel.Z-sign
Two independent, axis-locked friction paths: XY friction `p_mobj.cpp:2533-2534` and a *separate* Z friction `p_mobj.cpp:2666`. Bounce-to-rest `fabs(Vel.Z) < Mass*GetGravity()/64` (`p_mobj.cpp:1890`). Hard-landing `Vel.Z < -23` (`p_mobj.cpp:2735`). Landing threshold `p_mobj.cpp:4379`. Every one silently misfires under rotated gravity.

**The pattern:** there is no single "gravity direction" seam to flip. Down is smeared across dozens of Vel.Z reads, scalar `floorz` comparisons, a 2D LUT, and a 2D blockmap. That's why the honest tiering below matters.

---

## 3. Tier 1 â€” Fake it in pure ZScript (ship this first / the MVP)

**Goal:** a cube can enter a state where its contents visibly obey a new "down," the camera rolls to match, and monsters "react," with **zero engine recompile.** This is genuinely shippable and is the right first milestone â€” it proves the layout, the button, the netevent plumbing and the feel.

### 3.1 What ZScript actually exposes (all read/write, no recompile)
- `Actor.Gravity` (double, `actor.zs:176`) and `+NOGRAVITY` â€” kill the engine's `-Z` pull. Note `Actor.Gravity == 0` auto-sets `MF_NOGRAVITY` (`p_mobj.cpp:4821`).
- `Actor.Vel` (vector3, `actor.zs:112`) â€” writable every tick; `A_ChangeVelocity` (`actions.zs:63`).
- `StaticEventHandler.WorldTick()` (`events.zs:177`) â€” per-tick play-context hook over all actors.
- `Level.CreateSectorTagIterator(tag)` + `Sector.snext` chain â€” enumerate "all actors in cube N."
- `A_SetViewRoll()` (`actor.zs:1276`, native `p_actionfunctions.cpp:3046`) â€” rolls the **player view only** (visual, no physics).
- `A_SetRoll` / `Actor.Roll` â€” visual sprite roll for props.

### 3.2 The mechanic
1. **Tag every cube's sectors.** A `GravityCube` ZScript zone object holds `Vector3 gravDir` (default `(0,0,-1)`), keyed by tag.
2. **On button press** (a `netevent`, so it's demo/net-safe), write the cube's new `gravDir`.
3. **WorldTick handler** iterates the cube's actors: sets `+NOGRAVITY`, then each tick does `vel += gravDir * g` (magnitude tuned to `sv_gravity` feel). Props, gibs, dropped items, projectiles now fall toward the new down.
4. **Player:** use `Gravity = 0` (not the flag â€” `bNoGravity` is force-reset every `PlayerThink`, `player.zs:1091-1093`) in a custom `PlayerPawn` tick that applies the same `vel += gravDir*g`. Roll the view with `A_SetViewRoll` on entry.
5. **Monsters:** pick a reaction model (Â§3.4).

### 3.3 The strongest Tier-1 variant: Ghost-Room Flip (no fake physics at all)
For anything where you want the player to **truly stand and walk** on the flipped face, don't fake gravity â€” **fake the room.** Build each logical cube twice: an upright instance **and a handbuilt inverted twin** (the same room modeled upside-down). "Flipping" re-points that cube's entry portals from instance A to twin Aâ€² and teleports occupants across with a comfort fade. **In-engine down never changes**, so `floorz`/`ceilingz`, the blockmap, and monster 2D pathfinding are all perfectly valid â€” monsters walk a genuine `-Z` floor in Aâ€². This is the *only* tier where wall-walking "works" today, because it's an illusion made of ordinary floors. It composes cleanly with the portal-cube grid (Â§6).

### 3.4 Monster reaction models (pick per-cube, cheapestâ†’richest)
- **Tier 0 â€“ Freeze/despawn:** remove or freeze monsters on flip; the fallback when a cube has no valid set for its new orientation.
- **Tier 1 â€“ Floater conversion:** `+NOGRAVITY +FLOAT` so they hover and keep attacking with 2D aim. The honest baseline for "they reacted" â€” they don't obey new gravity but don't fall through the wrong plane either.
- **Tier 2 â€“ Ragdoll-to-new-down:** `+NOGRAVITY` + scripted `vel += gravDir*g` so corpses/gibs/stunned monsters tumble toward the new floor and pile there. Sells the flip *physically* without needing them to stand or path.
- **Tier 3 â€“ Pre-oriented variants (the "Re-Gravitated Bestiary"):** ship six authored variants per monster â€” floor / ceiling / four walls â€” each with baked `SPAWNCEILING`, roll/pitch offsets, and a face-hugging glide (`A_ChangeVelocity` along the face plane). On flip, despawn the old set and spawn the matching-orientation set at the same XY. Looks correct per-face; combat is a scripted approximation (`A_Face` substitute keeps target in the local attack cone), not real navigation.

### 3.5 What will feel right vs. wrong (be honest)
**Feels right:** gibs/props/projectiles arcing toward the new down; a ceiling full of `SPAWNCEILING` demons that belong there; a teleport-with-fade flip; the Ghost-Room walk-on-the-ceiling illusion.
**Feels wrong / don't ship it:** any *sustained* player camera roll during roomscale VR walking (nausea, Â§7); expecting a Tier-1 monster to *pathfind* on a wall (it can't â€” `P_Move` is 2D); correct landing sounds, splashes, footstep terrain, fall damage on a flipped face (all gated on `Vel.Z` sign / `Z() <= floorz`, so they misfire); step-up/dropoff on tilted "floors" (monsters get stuck on `dropoffz` Z-cliffs).

---

## 4. Tier 2 â€” Engine gravity VECTOR (the keystone patch)

**This is the single highest-leverage change.** Turn the scalar into a direction and *all Newtonian actors* â€” player, props, gibs, projectiles â€” genuinely fall, arc and coast toward an arbitrary per-cube down. (Monster *navigation* is still 2D and stays flying/floating â€” that's Tier 3. Their falling/settling physics, however, becomes correct here.)

### 4.1 Data model
- Add `DVector3 GravityDir` to `sector_t` (`src/gamedata/r_defs.h:735` area), default `(0,0,-1)`. Parse from UDMF as `gravity_x/y/z` in `src/maploader/udmf.cpp` (keep scalar `gravity` = magnitude; parse legacy scalar as `(0,0,-1)*value` for back-compat).
- Expose `Actor.GravityDir` to ZScript (additive native field) so flips and VR reorientation are drivable without further recompiles.
- Handle serialization for the new field (`src/p_saveg.cpp`).

### 4.2 Core edit â€” the apply site
Split `GetGravity()` into **magnitude + direction** (`src/playsim/actorinlines.h:86-90`). In `AActor::FallAndSink()`:
```cpp
// was:  Vel.Z -= grav;              (p_mobj.cpp:2971)
//       Vel.Z -= grav + grav;       (p_mobj.cpp:2967)
// now:  Vel -= GravityDir * grav;    (and *2 for the ledge case)
```
**Critical gotcha the flat-GZDoom recon missed:** `FallAndSink` is gated by `Z() > floorz + 2` (the "am I off the floor?" check). That gate is a Z-height test â€” rework it to a **gravity-aligned distance** (`dot(actorCenter - floorPlaneOrigin, floorPlane.Normal)`) or gravity silently switches off whenever the actor is near the *Z* floor rather than its true gravity-aligned ground.

### 4.3 Downstream `-Z` hardcodes that must become dot-products
Each of these independently assumes down = `-Z`. Convert to `dot(Vel, normalize(GravityDir))` forms:
| What | Location |
|---|---|
| Bounce/rest terminal check `fabs(Vel.Z) < Mass*grav/64` | `p_mobj.cpp:1890` |
| Landing threshold `Vel.Z < Level->gravity*Sector->gravity*(-1./100)` | `p_mobj.cpp:4379` |
| Hard-landing / splash `Vel.Z < -23`, `P_HitFloor` gate | `p_mobj.cpp:2735, 2744` |
| Separate **Z-friction** pass `Vel.Z *= friction` | `p_mobj.cpp:2666` |
| XY friction (decouple from Z) | `p_mobj.cpp:2533-2534` |
| Floor/ceiling hit `Z() <= floorz+2` / `Top() > ceilingz` | `p_mobj.cpp:2672, 2785` |
| Jump (`Vel.Z += JumpZ`) and other player Vel.Z writes | `player.zs:1527/1531/1551/1583` |

### 4.4 VR-specific work this patch *must* include (not an afterthought)
The flat-GZDoom recons omit this entirely, but for DoomXR it's mandatory:
- **HMD positional feed** writes `player->mo->Vel = DVector3(hmd_side*s, hmd_forward*s, 0)` (`src/gl/stereo3d/gl_openxrdevice.cpp:699`) â€” Z is literally `0`. Rotate this into the gravity frame.
- **Lift/floor-snap glue** `Z() <= floorz+2` â†’ `SetZ(floorz)` in the VR path (`gl_openxrdevice.cpp:700-707`) is Z-hardcoded â€” rework to gravity-aligned.
- **Camera up-basis / comfort frame:** feed `GravityDir` into the view up-vector; **lerp** the player's comfort/up-vector to the new `GravityDir` on entry rather than snapping. Mismatched physics-vs-view flip is the classic nausea trap.

### 4.5 What Tier 2 unlocks
Player, all dynamic actors, dropped items, and projectiles obey arbitrary per-cube gravity. Combined with a **flying/floating monster roster** (Â§5 middle ground) and Ghost-Room twins for stand-on surfaces, this is a *shippable, believable* gravity-cube experience. **Effort:** the *apply* edit is small, but the honest scope is closer to 1â€“2 focused weeks once you count the Z-gate rework, all the `Vel.Z`-sign constants, and the VR frame â€” not a weekend.

---

## 5. Tier 3 â€” Orientation-aware AI & collision (the real dream)

This is what makes "everything reacts" *literally* true: monsters chase along walls and ceilings as their floor, respect local cliffs, and aim/melee in the local frame. It is a **navigation + collision subsystem rewrite**, not a patch.

### 5.1 What has to change
- **Rotate the AI basis:** the `xspeed[8]/yspeed[8]` LUT and `P_Move`/`P_NewChaseDir` (`p_enemy.cpp:103-104, 497, 952`) must operate in the plane **perpendicular to `GravityDir`** â€” rotate `movedir` into the local frame.
- **Recast the Z-only AI checks as dot-products:** post-move Z-snap (`p_enemy.cpp:640-646`), on-ground gate (`p_enemy.cpp:522-523`), `P_TryMove` step/dropoff (`p_map.cpp:2453, 2516`), `P_CheckMeleeRange` (`p_enemy.cpp:290-296`), and `A_Face` pitch (`p_enemy.cpp:3057-3088`).
- **Surface-normal floorz:** `P_FindFloorCeiling` must return a **plane/normal**, not just a scalar â€” `floorz`/`dropoffz` become signed distances along `GravityDir`. `secplane_t` already stores normals; but `ZatPoint`'s divide-by-`c` (`r_defs.h:315, 361`) is undefined for vertical planes and is called from renderer/sound/AI/3D-floors, so it must be generalized to a plane-project (this is the **Plane-Native Collision Substrate** â€” the deepest, fork-defining rewrite that also fixes slopes, 3D floors, crushers, liquids and `FLineOpening`'s scalar Z-range at `p_maputl.h:107-110`).
- **Blockmap:** the 2D grid (`p_blockmap.h`) either needs a 3D partition or per-actor swept queries so broadphase finds the "wall as floor" surface.

### 5.2 Honest cost
This is the full multi-week rewrite, high regression risk on *every existing map*, with **no precedent in the ZDoom lineage** (Prey 2006's wall-walk needed a heavily modified id Tech 4). The estimate is realistically **6â€“10+ weeks**, not the "4â€“6" a surface reading suggests, because `floorz/ceilingz/ZatPoint` are read in hundreds of sites.

### 5.3 The pragmatic middle ground (strongly recommended)
**Don't build Tier 3 to ship.** Instead: **design a flying/floating monster roster** â€” cacodemons, lost souls, pain elementals, and custom hovering variants â€” so that with Tier 2's correct gravity physics they *arc and settle* believably under any cube's down without ever needing wall-pathfinding. Reserve Tier 3 pieces for set-piece scripted encounters (a single hero wall-walker on a rail). This keeps "everything reacts" true in spirit while keeping Tier 2 as the real engineering ceiling.

**Monster reaction ladder across tiers:**
- Tiers 0â€“3 (pure ZScript): freeze / floater / ragdoll-to-new-down / pre-oriented variants.
- **Tier 4 (smallCpp):** with a real `GravityDir`, floater monsters and gibs actually arc and settle correctly via the patched `FallAndSink` â€” movement *physics* correct, navigation still 2D.
- **Tier 5 (largeCpp):** local-frame `P_Move`/`P_NewChaseDir` â€” monsters chase along the wall/ceiling.
- **Tier 6 (largeCpp+):** on the plane-native substrate â€” slopes, 3D floors, cross-gravity portals, correct splash/landing on any face.

---

## 6. The cube-portal map architecture

**Build each logical cube as its own portal group** so its interior is a self-contained XY coordinate space (`portal.cpp:920` `Displacements.Create(id)`; `CollectSectors`). Tag every cube's sectors so ZScript can address "all actors in cube N" via `SectorTagIterator`.

- **Horizontal tiling** (cubes side-by-side): linked **LINE** portals (`PORTT_LINKED`) on shared faces â€” **confirmed doable in pure MAPINFO/UDMF today**, gravity staying `-Z`, giving a seamless walkable grid of rooms.
- **Vertical stacking:** linked **SECTOR** portals (`PORTS_LINKEDPORTAL`) on floor/ceiling (flat planes only â€” sloped is rejected at load, `portal.cpp:885-889`).

**What "flip" swaps, per tier:**
- **pure ZScript / Ghost-Room:** each cube has two baked instances (upright + inverted twin). Flip re-points that cube's entry portals Aâ†’Aâ€² and teleports occupants across with a comfort fade. Down never changes; neighbors' portals must re-link to the twin's matching faces so the seam stays continuous.
- **pure ZScript / Fake-Thrust:** flip just writes a new `gravDir` into the cube's zone object; the `WorldTick` `+NOGRAVITY` thrust loop + monster-set swap do the rest. Portals stay put.
- **smallCpp:** each cube carries a per-group `GravityDir` (in `PortalGroup` metadata or its sectors' UDMF `gravity_x/y/z`). Flip writes that group's `GravityDir`; the Vector-Gravity Core makes occupants obey it.
- **The connective tissue â€” Portal Roll Transform:** linked portals currently force `mSinRot=0/mCosRot=1` and transform XY+yaw with no Vel.Z transform (`portal.cpp:237-240`; `p_map.cpp:2628-2639`). Add an optional **roll/pitch to `FLinePortal`** (guarded by a map flag for save-compat), extend `P_TranslatePortalAngle` to carry it, add a **Vel.Z-inclusive** velocity rotation, and **on crossing set the actor's `GravityDir` to the destination cube's**. This turns a bag of independently-flipped cubes into one continuous walkable space with different local downs per cube â€” the true "linked cubes that each flip" architecture. It *depends on Tier 2 existing*, or a rolled actor immediately falls/clips.

**Per-cube flip** = write one group's `GravityDir` + reorient occupants. **"Flip all"** = broadcast one netevent iterating every group. In both cases the portal-roll transform handles each seam.

---

## 7. VR reality check

**Hard invariant the engine cannot break: the physical play-space floor and the headset's real-world "up" are fixed to world `-Z`.** The HMD feed is XY-only (`gl_openxrdevice.cpp:699`, third component `0`; `qzdoom_common.cpp:119` `*up=0.0f`). `A_SetViewRoll` rotates the *rendered* view but **not** the VR tracking frame. So:

- **A sustained sideways/inverted camera roll fights the player's vestibular "down" and will nauseate.** Roomscale walking on a wall for a real human body is **not deliverable** at any C++ tier â€” the room floor can't rotate under them.
- **Therefore, never flip in open space mid-stride.** Route *every* flip through a **teleport-or-lerp comfort transition anchored to a portal plane** â€” a sub-second fade/vignette cut, so any vestibular mismatch is a cut, not a sustained inversion. A portal crossing is the ideal trigger because the player *expects* a threshold there.
- **Design each cube face with a defined comfortable standing orientation.** Don't ask the player to physically stand on a wall; instead teleport-reorient them so the new "floor" is the one they're already comfortably facing, and use short comfort-tunneled transitions to lerp the up-vector.
- **Offer a comfort mode** that flips the *world render* but pins the HUD/horizon reticle, for players who want the visual without the roll.

**Recommended VR-safe scheme:** Ghost-Room twins (or Tier-2 `GravityDir`) + portal-anchored teleport-with-reorient + per-cube comfortable-orientation authoring + a pinned-horizon comfort toggle. This is a permanent design constraint, not a bug to fix later.

---

## 8. Recommended build order

**â˜… The single highest-leverage first patch:** turning scalar gravity into `DVector3 GravityDir` and changing `Vel.Z -= grav` â†’ `Vel -= GravityDir*grav` in `FallAndSink` (with the Z-gate rework). Everything real depends on it.

1. **MVP (pure ZScript, days):** tagged gravity-cube sectors + `WorldTick` handler; **Ghost-Room Flip** for the walk-on-surface illusion; **Fake-Thrust** for prop/gib/projectile fall; monster reaction = Floater or Pre-oriented variants; **netevent button** (single-cube + "flip all"); **portal-anchored teleport-with-fade** transition. Ship it, feel it, lock the layout.
2. **Portal-cube grid (pure MAPINFO/UDMF):** horizontal `PORTT_LINKED` tiling + vertical `PORTS_LINKEDPORTAL` stacking; one portal group + tag set per cube. Confirmed-doable today.
3. **â˜… Vector-Gravity Core (smallCpp, ~1â€“2 wk):** `GravityDir` on sector + actor; UDMF `gravity_x/y/z`; `FallAndSink` vector apply + Z-gate rework; convert the `Vel.Z`-sign constants (Â§4.3); **VR frame work** (Â§4.4) in the same patch. Now player/props/projectiles obey real arbitrary gravity.
4. **Portal Roll Transform (smallCpp):** optional roll on `FLinePortal` + Vel.Z-inclusive velocity rotation + set `GravityDir` on crossing. Cubes become one continuous multi-down space.
5. **Flying-monster roster (design, pure ZScript):** hovering monster set so Tier 3 stays out of scope while the cubes still feel populated and reactive.
6. **(Optional, largeCpp) Orientation-aware AI:** local-frame `P_Move`/`P_NewChaseDir` for real wall-walkers, on set-pieces only.
7. **(Optional, largeCpp+) Plane-Native Collision Substrate:** retire scalar `floorz`/`ceilingz`/`ZatPoint`; correct slopes, 3D floors, crushers, liquids, splashes and cross-gravity portals on any face.

---

## 9. Open questions / risks (the showstoppers)

- **Monster navigation is 2D, full stop.** `xspeed[8]/yspeed[8]` + `P_Move` (`p_enemy.cpp:103-104, 558-559`) have no Z locomotion. "Monsters walk on the new floor" is Tier 3+ only; below that, use floaters/variants/ragdoll. **Decision needed:** commit to a flying roster (recommended) or budget the AI rewrite.
- **The blockmap is 2D** (`p_blockmap.h:38-39, 69`) and the collision API takes `DVector2` (`p_map.cpp:1793, 2343`). Real broadphase for a "wall as floor" needs a 3D partition or swept per-actor queries â€” the largest hidden cost of the deep tier.
- **`secplane_t::ZatPoint` divides by `-1/c`** (`r_defs.h:315, 361`) â€” undefined for vertical planes, and called far outside collision (renderer/sound/AI/3D-floors). Any true arbitrary-gravity substrate must generalize it.
- **Landing/splash/terrain/fall-damage are all `Vel.Z`-sign gated** (`p_mobj.cpp:2735, 2744, 4379`; `player.zs` fall logic). Until converted, a flipped face has no splashes, no footstep terrain, no fall damage, and can loop landing animation states. The Tier-2 "ragdoll gibs pile on the new floor" claim is shakier than it sounds until these are done.
- **`bNoGravity` is force-reset for the player every `PlayerThink`** (`player.zs:1091-1093`) and toggled by water â€” use `Gravity=0` / `+FLY` / an override, never the raw flag on the player.
- **Portals never carry orientation today** (`portal.cpp:237-240`; `p_map.cpp:2628-2639` XY-only). Cross-gravity seams *require* the Portal Roll Transform, which requires Tier 2 first.
- **VR floor is immovable.** No engine tier makes a human physically stand on a wall. Design around it (comfortable-orientation faces + teleport/lerp transitions) permanently.
- **Save-compat:** new `sector_t`/`FLinePortal` fields need serialization handling (`p_saveg.cpp`) and map-flag guards; `FLinePortal` is rebuilt at level load (`FinalizePortals`, `portal.cpp:323-333`), so runtime physics breakage â€” not save corruption â€” is the real risk there.

---

**Bottom line:** you can ship a genuinely convincing gravity-cube map *now* in pure ZScript (Ghost-Room + Fake-Thrust + floater/variant monsters + portal-teleport-with-roll), and you can make it *physically real for the player and everything Newtonian* with one keystone patch (`GravityDir` vector). Reserve full wall-walking monsters and the plane-native substrate for later â€” and treat the fixed VR floor as a design constraint you build *around*, not a wall you hit.

**Key files to open first:** `src/playsim/actorinlines.h:86` (GetGravity), `src/playsim/p_mobj.cpp:2591/2967/2971` (FallAndSink apply), `src/playsim/actor.h:1168` (floorz/ceilingz), `src/playsim/p_enemy.cpp:103/558` (2D AI), `src/playsim/p_map.cpp:1793/2343/2453` (2D collision API), `src/playsim/portal.cpp:237/885` (portal translate-only), `src/gl/stereo3d/gl_openxrdevice.cpp:699` (VR HMD feed).
