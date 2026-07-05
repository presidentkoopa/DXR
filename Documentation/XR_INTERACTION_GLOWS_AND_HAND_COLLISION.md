# XR Interaction Glows + Hand-World Collision

*The "where do I put my hand / what am I about to touch" layer. One shared glow primitive answers that question across every VR hand system — walls, grab targets, two-hand grips, holsters, reload, catch, throw, and whip/hook aim — plus the hand physically stops at walls instead of clipping through. All ships ON by default, each toggleable. ZERO dynamic lights (uses the native GlowSpots gradient path).*

*Companion to [XR_DEBUG_VISUALIZERS.md](XR_DEBUG_VISUALIZERS.md). That doc is the opt-in DEBUG geometry layer; this is the always-on PLAYER-FACING feedback layer.*

---

## 0. The two things to know first

**1. Particles are invisible in VR.** The stereo renderer has no `P_SpawnParticle` draw path — anything drawn with particles shows on the flat desktop mirror but never reaches the headset. Two features in this pass were *already coded* but drew with particles, so they were silently invisible in VR the whole time: the **catch/snatch spark** and the **throw-trajectory arc preview**. This pass fixes both by routing them through glow spots. (Same rule as the debug doc: never particles for anything that must be seen in VR.)

**2. There is exactly ONE glow primitive.** Every feature here calls one shared helper:

```cpp
// p_user.cpp, near VR_UpdateHandCollision
static void VR_PushWorldGlow(FLevelLocals* lvl, const DVector3& pos, PalEntry color, double radius);
```

It pushes a single airborne/billboard `FGlowSpot` (the same construction `AddGlowPanel` uses) at a world position. `Level->GlowSpots` is cleared every game tic (p_tick.cpp) and rebuilt by every publisher, so a feature just re-pushes each tic it wants the glow visible — **no lifetime or staleness bookkeeping anywhere.** Body-anchored, weapon-riding, and free-floating spots all work because the position is recomputed fresh every tic regardless.

The wall-touch glow (`VR_UpdateHandCollision`) is the one exception: it uses a wall-plane spot (`planeFlags = 4`) anchored to the linedef, not the billboard helper.

---

## 1. Hand-world collision (walls)

`VR_UpdateHandCollision(player_t*)` — p_user.cpp, called each tic in the VR update chain right after climb/gloves.

Reuses the **exact** blockmap query `VR_UpdateClimbing` already runs: `FBoundingBox(handPos, searchRadius)` + `FBlockLinesIterator`, finding the nearest solid wall segment (one-sided, or two-sided with `ML_BLOCKING`). A sector floor/ceiling Z-gate ensures the wall only counts within the hand's actual height.

Two things come out of it each tic, per hand:

- **A wall glow** that grows as the hand approaches and is colored by surface type:
  - **Blue** (`vr_hand_glow_color`) — a plain solid wall.
  - **Green** (`vr_hand_glow_climb_color`) — a KEYWORDS-tagged *climbable* surface (same `KeywordDispatcher::IsClimbable` test the climb system uses: line Keywords → `"climb:<tex>"` → sector Keywords). Most solid walls are NOT climbable, so this tells the player which is grippable before they commit a grip.
  - The two are thresholded independently: climbable at the real `vr_climb_radius` (where you'd actually grip), plain solid at `vr_hand_collision_radius`.
- **A haptic bump** on first contact (`hand_climb_range` / `hand_wall_touch`).

### 1a. Clamp hand at wall (IK integration)

Detection alone just glows — the rendered hand still clips through the wall. The **clamp** (toggle `vr_hand_ik_clamp`, default ON) fixes that:

- `VR_UpdateHandCollision` publishes `player->vr_hand_collision_clamp_pos[hand]` (d_player.h) each tic: when touching, the hand's XY pulled back to sit exactly at the contact radius from the wall (keeping the controller's real Z so vertical reach still tracks); otherwise the raw hand pos.
- `VR_UpdateArmIK` reads it **immediately after** its two `GetWeaponTransform` calls fill `rightXf`/`leftXf`, overriding only the translation floats (`m[12]`, `m[13]`, `m[14]`) of a hand flagged `vr_hand_touching_wall[slot]`, via `const_cast<float*>(xf.get())`. Nothing else in the fragile Finv/baseframe IK solve changes.

**Contract with the foregrip-pin (IK/body lane):** the clamp is gated `!(slot == VR_OFFHAND && vr_foregrip_engaged)`. Rule: **a foregripping off-hand always stays on the gun, a free hand clamps at the wall** — so the clamp and the two-hand foregrip pin can never fight over the same hand in the same tic.

---

## 2. The glow features (native)

All in p_user.cpp, each hooked into the code that already computes the relevant world position — no new spatial queries.

| Feature | Where it hooks | Color (default) | Notes |
|---|---|---|---|
| **Grab-target highlight** | `VR_UpdateGravityGloves`, where `vr_grab_candidate`/`bForceShowVoxel` is set | white | Glows the actor the aim-cone currently has selected, before you squeeze. Works on any model type (the old `bForceShowVoxel` only helped voxel actors). |
| **Two-hand stabilize** | `VR_CalculateTwoHanding`, both engage sites | yellow (matches two-hand debug sphere) | Glows the off-hand grip point (`vr_foregrip_world` on the native path; the computed capsule point on the legacy path). |
| **Hardpoint draw/stow** | new `VR_UpdateHardpointGlow`, per-tic | magenta (body) / violet (wrist) | Mirrors `IsHardpointNear`'s distance test; world pos via the shared `VR_ResolveHardpointWorldPos` (do NOT recompute anchor math). Proximity ramp like the wall glow. |
| **Reload magwell/rack** | box-mag reload FSM (`VR_UpdateWeaponReload`) | cyan | Magwell glows in `VRRL_EMPTY`/`VRRL_MAG_OUT`, rack glows in `VRRL_MAG_IN`. **Box-mag style only** this pass — shell/cylinder/canister styles dispatch elsewhere and are untouched. |
| **Catch / snatch** *(bugfix)* | bullet-snatch site, gated by existing `vr_catch_spark` | green (matches catch debug sphere) | Replaces the invisible `P_SpawnParticle` burst. Reuses the existing toggle — no new enable cvar. |
| **Throw-arc preview** *(bugfix)* | throw preview loop in `VR_UpdateGravityGloves` | amber | Replaces two invisible `P_SpawnParticle` calls. Strided — one spot every 4th of the 40 integration steps (~10 spots), not all 40. |

---

## 3. The whip / hook aim preview (ZScript)

The laser sight already answers "where am I aiming" for guns; the whip and Ice Hook had no equivalent. Both now glow their attach/land point every tic while readied:

- **Whip** — `vr_whip.zs` `Tick()`, in the not-grappling branch. Runs the *identical* `LineTrace` that `StartGrappleFromAim` fires (same hand/angle/pitch source, same `ActiveWhip.Reach`), so the preview can never promise a catch the real fire wouldn't also land. Gated `vr_whip_preview_enable`.
- **Ice Hook** — `icehook.zs` `Tick()`. A genuinely new forward trace (there was no pre-fire resolution to mirror — `A_IceHookThrow` just spawns a physical projectile). Fixed generous range cap since the projectile flies until impact. Gated `vr_icehook_preview_enable`.

Both draw via `Level.AddGlowPanel` (the ZScript-exposed native billboard glow) — same primitive as the native features, no C++ needed.

---

## 4. Grab-weight sliders — dead UI made real

The `VRGrabOptions` menu had three sliders — **Distance / Alignment / Mass Penalty Weight** — whose own tooltips admitted "no code reads this cvar so it is currently inert." They weren't just unread: `vr_grab_weight_dist/align/mass` were **not declared as real CVars anywhere** outside menudef.txt.

Now declared for real (hw_vrmodes.cpp) and wired into the candidate-scoring formula in `VR_UpdateGravityGloves`:

```cpp
double normDist    = sqrt(distSq) / vr_grab_max_dist;
double alignFactor = 1.0 + (dot - 1.0) * vr_grab_weight_align;              // default 1.0 -> exactly `dot`
double distFactor  = 1.0 + ((1.0 - normDist) - 1.0) * vr_grab_weight_dist;  // default 1.0 -> exactly `1-normDist`
double itemMass    = mo->Mass > 0 ? mo->Mass : 100.0;
double massPenalty = 1.0 - vr_grab_weight_mass * clamp(itemMass/1000.0, 0.0, 1.0); // default 0.0 -> no penalty
double score       = alignFactor * distFactor * massPenalty;
```

At the defaults (`dist=1, align=1, mass=0`) this collapses **bit-for-bit** to the old formula (`dot * (1-normDist)`, no mass term). It's a dead-code fix, not a balance change — behavior only shifts once a player actually moves a slider. Tooltips updated to match.

---

## 5. CVars

Declared in `hw_vrmodes.cpp` beside the existing `vr_hand_glow_*` block, `EXTERN_CVAR`'d in `p_user.cpp`. Every native glow feature follows the same shape as the shipped hand-collision cvars: an `_enable` bool + color (+ radius/range where relevant).

| Group | CVars |
|---|---|
| Hand collision (shipped earlier) | `vr_hand_collision`, `vr_hand_collision_radius`, `vr_hand_collision_glow`, `vr_hand_glow_range`, `vr_hand_glow_min_radius`, `vr_hand_glow_max_radius`, `vr_hand_glow_color`, `vr_hand_glow_climb_color` |
| Clamp | `vr_hand_ik_clamp` |
| Catch | `vr_catch_glow_radius`, `vr_catch_glow_color` (enable = existing `vr_catch_spark`) |
| Throw arc | `vr_throw_arc_glow_enable`, `vr_throw_arc_glow_radius`, `vr_throw_arc_glow_color` |
| Grab target | `vr_grab_highlight_enable`, `vr_grab_highlight_radius`, `vr_grab_highlight_color` |
| Two-hand | `vr_twohand_glow_enable`, `vr_twohand_glow_radius`, `vr_twohand_glow_color` |
| Hardpoint | `vr_hardpoint_glow_enable`, `vr_hardpoint_glow_range`, `vr_hardpoint_glow_min_radius`, `vr_hardpoint_glow_max_radius`, `vr_hardpoint_glow_color_body`, `vr_hardpoint_glow_color_wrist` |
| Reload | `vr_reload_glow_enable`, `vr_reload_glow_radius`, `vr_reload_glow_color` |
| Grab weights | `vr_grab_weight_dist`, `vr_grab_weight_align`, `vr_grab_weight_mass` |
| Whip/hook preview (ZScript-read) | `vr_whip_preview_enable/_color/_radius`, `vr_icehook_preview_enable/_color/_radius` |

## 6. Menu

- **VR Options → Hand and World Collision** — gains the "Clamp Hand At Wall" toggle.
- **VR Options → Interaction Glows** (new submenu) — toggle/color/size for grab-target, two-hand, hardpoint, reload, catch, and throw-arc glows.
- **Whip Options / Ice Hook Options** — each gains its preview toggle + color + size (weapon-specific, so they live with the weapon, not the general glow menu).
- **Grab Options** — the three grab-weight slider tooltips corrected (no longer claim to be inert).

menudef.txt is runtime-parsed data — the menu changes need no rebuild; the CVars and native logic do.

---

## 7. Build / lane notes

- **Not compiled** — the rebuild is the IK/body lane's (the single rebuild lane). This work was handed to them to fold into one rebuild alongside their crash-hardening.
- One build-blocker was caught and fixed during this pass: a 3-arg `max<double>(a, b, c)` (MSVC reads the 3rd arg as a comparator → C2064). All such call sites are now nested `max(max(a,b), c)`; the whole `src/` tree was swept for the pattern afterward.
- `VR_UpdateArmIK` still carries the IK lane's `[VRIK_*]` debug Printfs; whether they stay through the clamp bring-up is their call.
