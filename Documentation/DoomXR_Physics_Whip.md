# DoomXR — Physics Whip & Engine Feature Map
### ⟳ LIVING DOCUMENT · v0.9 · 2026-07-03

> DoomXR is an **advanced-rendering VR engine** (GZDoom/QZDoom lineage) with a **unique motion-physics
> layer**: true per-hand linear **and angular** velocity tracking, mass-scaled throwing, VR climbing, and
> dual-hand pose exposed to script. This document (a) maps those unique features and (b) specifies a
> long-term **whip capability** built on them. Maintained and updated in place.

### 🎯 North star
An **Indiana Jones** whip that is also a **traversal verb**: crack enemies, **grapple + swing** across gaps,
**climb** the line (feeding DoomXR's climb system), **two-hand it Castlevania IV-style**, and grow into an
**enchanted, extendable** whip with elemental affixes and utility (disarm, pull, chain-crack). One rope core,
many features, shipped in tiers (§N).

**Status:** core + traversal + two-hand designed; implementation not started. Awaiting go-ahead to build **Route A** (pure ZScript). **Endgame:** ship the whip as a rigged **IQM model** (§Q).
**Class naming:** DoomXR-native `XRWhip*`. (No external-mod branding — this is an engine feature.)
**Engine paths:** everything is under `E:\DoomXR-work\DOOM_FRESH\`. Lane tags used throughout: 🔒 **shader** (owner-only — do NOT edit) · ✅ **non-shader** (open lane) · 📄 **reference** (read, don't edit). Full lane-tagged index in **§P**; lane rules in `E:\DoomXR-work\DOOM_FRESH\SESSION_LANES.md`.

### Change log
- **v0.9 (2026-07-03)** — **Swarm confidence + adversarial pass** on the three highest-risk model assumptions
  (companion spec §7). Results: (1) ZScript **`Quat` is a confirmed first-class type** — `*`, `.Conjugate()`,
  `.Inverse()`, `QuatStruct` factories all real (98/100), retiring the "might need manual Vector4 math" risk;
  (2) IQM bone axis **mechanism confirmed** — procedural TRS is consumed in **IQM Y-up** space (do NOT
  pre-swap), `BONE_FWD=(0,1,0)`, one 20-min empirical test to lock the exact axis (91/100); (3) **`MDL_FOLLOW`
  REFUTED — the flag was invented and does not exist**; real hand-tracking = world actors read
  `AttackPos`/`OffhandPos` + `SetOrigin()` each tic, precedent in `weaponshieldsaw.zs`/`gitd_dark.zs` (99/100).
  §Q strategy table + companion spec §3/§5/§7 updated accordingly.
- **v0.8 (2026-07-03)** — **Correction:** v0.7 wrongly framed "no ZScript bone-write thunk exists" as a dead
  end. Re-read the actual render pipeline first-person (not swarm paraphrase) and found the engine already has
  an unused override seam (`animationData` in `CalculateBonesIQM`) built for exactly this. Strategy D is now a
  fully specced, small, non-shader patch — see companion doc `DoomXR_Whip_IQM_Rigging_Patch_Spec.md` — not a
  hypothetical. General principle going forward: "no ZScript API for X" in this engine means "unwritten
  thunk," not "impossible" — that's how every other DoomXR capability (AttackPos, glow panels, dual-wield)
  got made.
- **v0.7 (2026-07-03)** — IQM deep-dive landed: usable model toolkit (`A_ChangeModel`/`SetAnimation`/MODELDEF/
  `surfaceskin`) confirmed; initial (later corrected) bone-write verdict.
- **v0.6 (2026-07-03)** — Added **§P Engine File Index** (every path lane-tagged 🔒/✅/📄) and **§Q the IQM-model
  endgame** ("make me Indiana Jones"); path-lane legend in header. IQM pipeline deep-dive in flight.
- **v0.5 (2026-07-03)** — Added **§O shader collaboration** (physics→light; free-today primitives vs the cord unlock).
- **v0.4 (2026-07-03)** — Folded the verified 20-agent DoomXR feature map into §A (motion, Wired/GITD render, API, Keywords) + caveats.
- **v0.3 (2026-07-03)** — Added the **vision & roadmap**: Castlevania IV two-hand free-swing (§L), Indiana
  Jones **grapple + climb** integration grounded in `VR_UpdateClimbing` (§M), and the tiered enchanted/
  extendable feature roadmap (§N).
- **v0.2 (2026-07-03)** — Rebranded DoomXR-native (`XRWhip*`); promoted to Desktop living doc; added the
  DoomXR Unique Feature Map (§A); feature survey in progress.
- **v0.1 (2026-07-03)** — Initial physics-whip spec from a 30-agent engine audit.

---

# §A. DoomXR — Unique Engine Feature Map

_Verified by a 20-agent survey with adversarial checks (2026-07-03). "unique" = genuinely fork-added vs stock GZDoom._

## A1. VR motion-physics layer
| Feature | What it does | Source | Script? |
|---|---|---|---|
| Per-hand **LINEAR** velocity | true runtime velocity, 10-sample avg | `vk_openxrdevice.cpp:4355` | native ⚠️ Vulkan/OpenXR **only** (GL has none) |
| Per-hand **ANGULAR** velocity | wrist twist from `XrSpaceVelocity` | `vk_openxrdevice.cpp:4369` | native ⚠️ **dead-plumbed** (captured, zero consumers) |
| **Mass-scaled throw** | `Vel = handVel·(40/35)·throwForce·(100/Mass)` | `p_user.cpp:1508` | native (`vr_throw_force=1`) |
| **Gravity-gloves grab** | cone-scan candidate targeting | `p_user.cpp:1562` | native (`vr_grab_max_dist=500`, `vr_grab_cone_angle=30`) |
| **Flick-pull / catch / bullet-snatch** | flick >10 m/s summons; grip snatches live projectiles | `p_user.cpp:1526,1767` | native (`vr_allow_bullet_snatching`, `vr_catch_radius=24`) |
| **Wall/texture CLIMB** | grip a `climb:` surface → `Vel = −handVel·mult`, NOGRAVITY | `p_user.cpp:1864` | native (`vr_climb_radius=32`, `vr_climb_speed_mult=1`) |
| **Two-hand stabilization** | hands within radius → steadies aim/recoil | `p_user.cpp:1305` | partial (`vr_two_handed_weapons=true`, `vr_twohand_radius=8`) |
| **VR recoil** | visual kick + aim-climb, no camera move | `hw_vrmodes.cpp:1144` | **yes** — via stock `A_Recoil`→`VR_ApplyRecoil` |
| **Weapon parry volume** | per-hand box test vs inflictor | `hw_vrmodes.cpp:1193` | native (`vr_parry_radius_mult=1.2`) |
| **Teleport · room-scale walk · crouch-by-height** | HMD-delta → `P_XYMovement`; duck IRL to crouch | `vk_openxrdevice.cpp:3736+` | native |
| **Hand-model state swap** | Idle/Grip/Climb/Point → `VRHandModel` states | `models.cpp:213` | partial (ZScript `VRHandModel` actor) |

**Unit chain:** `vr_vunits_per_meter = 34` (1 m = 34 units) · 35 tics/s · `vr_scale_meters_to_units = 40`
(throw velocity) → **1 map-unit/tic ≈ 1.03 m/s**, **Mach 1 ≈ 333 units/tic**.

## A2. Advanced rendering — the "Wired" / GITD stack (much of it ZScript-callable)
| Feature | What it does | Source | ZScript API |
|---|---|---|---|
| **GITD glow-spot registry** | lights-free localized emissive pools on floor/wall/air, re-published each tic | `g_levellocals.h:111` | `Level.AddGlowSpot` / `AddGlowSpotWiped` (`doombase.zs:423`), `Sector.SetGlowSpot` |
| **In-air glow PANELS** | camera-facing neon billboards; numbers & shapes | `hw_glowbillboards.cpp:39` | `Level.AddGlowPanel(col,rad,x,y,z,wipeType,prog,dirX,dirY,counter)` |
| **In-shader neon library** | baked SDF font atlas (`neonfont.png`, 8 fonts) + ~13 procedural primitives — wgType 14–26: shockwave ring, disc, stamped **damage number**, brackets, oscilloscope, CRT skull, **lightning bolt**… | `main.fp:716-1251` | selected via `AddGlowPanel` `wipeType`/`counter` |
| **World-space MSDF text** | 3D neon text: tribe palettes, glitch styles, behaviors | `vr_msdf_text.cpp:155` | `Actor.VR_SpawnMSDFText(keyword,text,life,scale,tribe)` |
| **Floating damage #s + wired impacts** | hit-driven MSDF numbers + SDF impact particles | `vr_msdf_text.cpp:348` | CVars `vr_show_damage_numbers`, `vr_wired_impacts` + `VR_SpawnWiredImpact` |
| **Per-actor neon/glitch shader** | enable/glitch/tint on any actor sprite | `actor.zs:221-223` | `msdf_enabled` / `msdf_glitch` / `msdf_color` |
| **Shader hot-swap** | a loose pk3's `main.fp` overrides the baked core shader | `main.fp` | build-time (no rebuild needed) |

## A3. Fork ZScript API a mod actually calls
- **Dual-hand pose** (readonly): `AttackPos/Angle/Pitch/Roll`, `OffhandPos/…`; gate on `OverrideAttackPosDir` — `actor.zs:272-280`.
- ⚠️ **`AttackDir()`/`OffhandDir()` return `(angle°, pitch°, 0)`, NOT a direction vector** (`actor.zs:861`) — build the dir from `cos/sin` yourself.
- **True dual-wield:** `player.OffhandWeapon` + `ALF_ISOFFHAND` (256) + `bOffhandWeapon` flag → shots route to the off hand.
- **Glow/text:** `AddGlowSpot`/`AddGlowSpotWiped`/`AddGlowPanel`, `VR_SpawnMSDFText`, `msdf_*` fields.
- **Stock but load-bearing:** `Mass`, `Vel`, `Thrust`, `Vel3DFromAngle`, `VelIntercept`, overridable `ApplyKickback`.

## A4. Keywords system (map/JSON-driven metadata)
Native `KeywordDispatcher` reads `KEYWORDS.json` → per-actor `KeywordProfile` driving **mass override, bullet-drop,
throwable/grab, climbable (`climb:<texture>` with per-surface speed), parry extents, two-hand weapon offsets,
pickup→`Wallet` currency, glow color/pulse, haptics** (`keyword_dispatcher.h`).
> ⚠️ **Not a ZScript API today:** the `Keywords "..."` actor property is a compiled **no-op** and there is no
> `native String Keywords`. It populates only from **map-thing / linedef / sector / texture** keywords + the JSON.
> → Grapple/climb surfaces are **map-authored** (works fine); a weapon can't declare its own Keywords in ZScript yet.

## A5. Caveats (so we don't build on sand)
- **Velocity layer is Vulkan/OpenXR ONLY** — GL OpenVR/OpenXR capture no velocity. → Route A (pose-delta) is the only
  universal hand-speed source; a Route B patch must add the GL path too.
- **Angular velocity is dead-plumbed** — captured & averaged, zero consumers. Exposing it (Route B) is its first real use.
- **IQM "decoupled animations" are STOCK GZDoom 4.12+**, not a DoomXR addition (correcting an earlier assumption).
- The standalone `VR_ThrowActor` helper is **never called**; the live throw is the inline `p_user.cpp` path.

## A6. What the whip leverages (feature → tier)
- **Pose** (A3) → rope root + two-hand pin (§L). **Climb** (A1/A4) → grapple reel + wall-handoff (§M).
- **Glow/MSDF** (A2) → crack shockwave ring (wgType 14), elemental glow, floating damage numbers (Tiers 3–4).
- **Mass/Vel/ApplyKickback** → momentum damage + knockback (§G). **OffhandWeapon** → whip can live in either hand.

---

# §B. Physics Whip — why it needs a real rebuild

The engine already has the physics to make a whip that behaves 1:1 with a real one. The existing prototype
(`E:\_whip`, 24-segment Verlet render) has three defects that keep it from being a real whip:

1. **The rope is cosmetic.** The sim renders a whip, but the *hit* is a straight `LineTrace` from the hand
   along aim — the simulated tip isn't where damage happens.
2. **The tip never accelerates.** Equal segment mass → no momentum wave → the tip never outruns the hand.
   A real whip cracks *because* the tip outruns the hand ~30×.
3. **Strength from the wrong number.** Damage scales off hand translation speed capped at ~49 m/s — a
   physically impossible hand speed — so full-power cracks are unreachable.

---

# §C. Real whip physics we model (1:1)

A whip cracks by **conservation of momentum down a taper**:
- Energy enters at the handle as a **rotational wrist flick** (angular, not a shove).
- A transverse **wave** travels toward the tip.
- Mass-per-length **falls toward the tip**; to conserve `p = m·v`, velocity **rises** →
  `v_tip ≈ v_root·√(M_total/m_tip)`. Real bullwhips amplify **~26–33×**.
- At **≥ 343 m/s (≈ 333 units/tic)** the tip goes supersonic → a small sonic boom = **the crack**.

So the sim must: **taper segment masses**, **drive the root with angular velocity**, let the wave amplify,
and **detect the supersonic tip**. Damage/knockback key off **tip momentum**, not hand speed.

---

# §D. Whip architecture (DoomXR-native)

```
XRWhipWeapon : Weapon         // thin shell: spawn/track controller, call DoCrack from Fire states
XRWhipController : Thinker     // THE BRAIN — one per equipped whip, runs every tic (DoEffect cadence)
XRWhipSegment : Actor          // one rendered link (TEND sprite, +ROLLSPRITE, additive glow)
XRWhipTip : Actor              // the popper/claw at the end (CLAW sprite)
```

**Per-tic loop in `XRWhipController`:**
1. **Read pose** — `AttackPos/Angle/Pitch/Roll`, gated on `OverrideAttackPosDir`.
2. **Derive hand kinematics** — linear `v_hand = ΔAttackPos`; **angular** `ω = Δ(Angle,Pitch,Roll)`;
   root drive `v_root = v_hand + ω × r_handle` (`r_handle ≈ 7 u ≈ 0.2 m`).
3. **Mass-tapered Verlet** (§E) — node 0 pinned to hand, node 1 gets the angular kick.
4. **Measure tip speed** + peak-hold.
5. **Crack test** (§F) — supersonic tip → crack event.
6. **Render** each segment along the curve (keep the current renderer; it's good).
7. **Swept-tip hit** (§G) — sweep the fast tip segments vs monsters; not a hand-ray.

---

# §E. Mass-tapered Verlet solver (makes it a *whip*)

Store the point cloud as parallel `double[]` component arrays (ZScript can't hold `Vector3[]`). Add a
per-node **inverse mass**.

```
N       = 24                       // enough nodes for the wave to amplify
restLen = REACH / N
for i in 0..N:
    tfrac  = i / N                  // 0 hand → 1 tip
    radius = lerp(R_BASE, R_TIP, tfrac)   // 1.0 → 0.12
    m[i]   = radius*radius          // mass ∝ diameter²
    w[i]   = (i==0) ? 0.0 : 1.0/m[i]      // node 0 = infinite mass (pinned to hand)
```

```
for s in 0..SUBSTEPS:                       // sub-step so the wave resolves at 35 Hz
   for i in 1..N:                            // Verlet integrate free nodes
       vel = (p[i]-pprev[i])*DAMPING; pprev[i]=p[i]
       p[i] += vel; p[i].z -= SAG_GRAVITY/SUBSTEPS
   for iter in 0..RELAX_ITERS:               // inverse-mass-weighted distance constraints
       p[0] = handPos; inject node-1 angular kick (v_root)
       for i in 0..N-1:
           d=p[i+1]-p[i]; L=d.Length(); diff=(L-restLen)/L*STIFFNESS; wsum=w[i]+w[i+1]
           p[i]   += d*(w[i]  /wsum)*diff
           p[i+1] -= d*(w[i+1]/wsum)*diff
       // optional two-hand bend: drag mid node toward OffhandPos
```

Because `w` grows toward the tip, a base impulse is passed down and **sped up** at each lighter node — the
emergent momentum wave the old whip lacked.

---

# §F. Crack detection — emergent + analytic

```
v_tip_est  = v_root * clamp(sqrt(M_total/m_tip), 1, A_MAX)   // A_MAX≈33, guaranteed-physics estimate
crackSpeed = max(v_tip_measured, v_tip_est)
if crackSpeed >= MACH(333) * CRACK_FRAC and cooldown==0:
    → CRACK: sonic-boom SFX at tip, bright FX/decal, open damage window K tics, snap visual, cooldown≈7
```
Damage/knockback in the window scale by tip kinetic energy `E = ½·m_tip·crackSpeed²`.

---

# §G. Hit, damage, knockback, grapple

**Swept-tip hit (fixes the cosmetic-rope defect):** each tic, for the last ~4 (fastest) nodes,
`LineTrace(lastPos[i] → p[i])` with segment thickness. Contact follows the rendered rope.

**Damage & knockback = tip momentum**, using DoomXR's inverse-mass convention so it feels like the rest of
the sandbox:
```
E_tip  = 0.5*m_tip*v_tip^2
damage = clamp(round(DMG_K*E_tip), DMG_MIN, DMG_MAX)
target.DamageMobj(owner, owner, damage, 'Whip')
target.Vel += tipDir * (m_tip*v_tip / target.Mass) * KNOCK_K   // heavy resists, light flies
```
**Grapple (cracked world hit):** spring the player toward the anchor — `player.Vel += (anchor-pos).Unit()*REEL_ACCEL` (capped) — tension on a line, not a teleport.

---

# §H. Optional engine patch — Route B (expose true velocity to script)

Route A ships on both backends today. Route B upgrades fidelity (crisp cracks + real wrist twist) with a
small, additive, low-risk patch — **rebuild required, only on explicit go-ahead**:
1. Add `native readonly Vector3 AttackVel, AttackAngVel, OffhandVel, OffhandAngVel;` + `DEFINE_FIELD`s
   (mirror the `AttackPos` block, `vmthunks_actors.cpp:2191`).
2. Write them each tic where `AttackPos` is written (`gl_openxrdevice.cpp:616-639`, etc.) from
   `GetHandVelocity` / `GetHandAngularVelocity`, world-rotated and scaled `·vr_vunits_per_meter/35`.
3. Add the missing `OpenVRMode::GetHandAngularVelocity` override (~5 lines) reading
   `controllers[c].pose.vAngularVelocity`.

The whip auto-detects these fields and falls back to differencing when absent — one mod build works everywhere.

---

# §I. Tuning table (single source of truth in `XRWhipCfg`)

| Const | Default | Meaning |
|---|---|---|
| `SEGMENTS (N)` | 24 | nodes |
| `REACH` | 128 u (~3.8 m) | full length |
| `SUBSTEPS` | 4 | solver steps/tic |
| `RELAX_ITERS` | 4 | constraint passes/substep |
| `R_BASE / R_TIP` | 1.0 / 0.12 | taper radii → mass ∝ r² |
| `A_MAX` | 33 | max taper amplification |
| `MACH` | 333 u/tic | crack threshold (343 m/s) |
| `CRACK_FRAC` | 0.85 | fraction of Mach to trigger |
| `SAG_GRAVITY` | 0.85 | gravity sag/tic |
| `DAMPING` | 0.88 | velocity retention |
| `r_handle` | 7 u (~0.2 m) | handle radius for ω→v_root |
| `DMG_K / DMG_MIN / DMG_MAX` | tune | energy→damage |
| `KNOCK_K` | tune | momentum→knockback |
| `crackCooldown` | 7 tics | anti machine-gun |

---

# §J. Build order (whip core)
1. **Route A** — mass-tapered Verlet + angular root drive + swept-tip hits + analytic crack + momentum
   damage/knockback. Pure ZScript, ships on OpenVR & OpenXR, zero engine risk.
2. Playtest & tune in VR (assistant drives edits, user tests in headset).
3. **Route B** (optional, on go-ahead) — expose true velocity for crisper cracks + real wrist twist.

---

# §K. Whip vision — the long-term capability

Not a single weapon — a **growing capability** on one rope core (`XRWhipController`). Two identities that
share the sim:

- **Combat (Castlevania IV):** two-hand free-swing, limp flail, wind-up heavy crack. §L
- **Traversal (Indiana Jones):** grapple an anchor, **swing** across gaps, **climb** the line, wall-handoff
  into DoomXR's native climb. §M

…then **enchanted & extendable**: magic length growth, elemental affixes, disarm/pull utility. §N

Everything below is grounded in verified DoomXR systems: dual-hand pose (`AttackPos`/`OffhandPos`), the
Keywords system, and the VR climb loop (`VR_UpdateClimbing`, `p_user.cpp:1864`).

---

# §L. Castlevania IV two-hand free-swing

**Goal:** hold the whip out and it *behaves* — dangles, wobbles, flails — and you can grab it with both
hands to aim, stretch, and load a big crack. CV4's 8-direction control becomes literal 6DoF.

**L1 — Free-swing / limp mode.** A held input drops the rope's `STIFFNESS` toward 0 → it fully ragdolls
under `SAG_GRAVITY` (the sim already sags). You physically wave it; low-speed contact = light lash
(§G swept hit). A flick out of limp re-tensions and can **crack** (§F). This *is* the CV4 dangle-whip.

**L2 — Two-hand grab (the "two-hand it" ask).** Off-hand grip pins a **second point** of the rope to
`OffhandPos` (a second Verlet constraint, alongside the node-0 hand pin). Now you can:
- **Stretch it taut** between both hands → precise aim / a horizontal "bar" (block, sweep).
- **Wind up** a two-handed crack: load the mid-rope by pulling hands apart, release the off-hand → the
  stored constraint energy dumps into the wave → a bigger tip speed / bigger crack.
- Consistent with the engine's `vr_two_handed_weapons` (default **true**) stabilization philosophy.

**Off-hand grip in ZScript:** grip isn't a script field; bind off-hand grip to a `+` action that sets a
controller flag (DoomXR's established grip-read pattern) — confirm the exact bind at build time. The whip
reads that flag + `OffhandPos` each tic.

---

# §M. Grapple + climb (Indiana Jones traversal)

Grounded in the native climb loop: `VR_UpdateClimbing` (`p_user.cpp:1864`) sets
`player.Vel = climbDelta · vr_climb_speed_mult` with `MF_NOGRAVITY` while a **gripped, climbable** surface is
in `vr_climb_radius`; climbable = Keywords (`climb:<texture>` / line / sector) with a per-surface speedMult.

**M0 — Hook.** A crack (§F) that hits a wall/ledge — or any surface tagged `grapple:`/`climb:` — sets an
**anchor** at `HitLocation`. The rope tip is pinned to the anchor (tip node becomes a second fixed point in
the sim → the line goes taut and renders as a real drawn rope).

**M1 — Reel / rope-climb ("climb the whip").** While gripping + pulling the hand, reel the player toward the
anchor. **Mirror the native climb math in ZScript:** set `MF_NOGRAVITY`, and
`player.Vel = handPullAlongLine · vr_climb_speed_mult`, where `handPullAlongLine` = the hand's per-tic
`AttackPos` delta projected onto the rope direction. (Native climb uses `GetHandVelocity`, which isn't
script-exposed, so we mirror it with the pose delta — same trick as the whip's velocity.) Pull hand toward
you → body climbs the rope toward the anchor. Reuses `vr_climb_speed_mult` for identical feel.

**M2 — Pendulum swing (Indy/CV4 gap-cross).** Anchored + hanging (not actively reeling): gravity **on**,
enforce a rope constraint each tic — if `|player − anchor| > ropeLen`, clamp distance and remove the outward
(radial) velocity component → the player **swings**. Release grip → keep the tangential velocity → a
**swing-jump** across the gap. Pure ZScript position/velocity constraint.

**M3 — Wall-handoff into native climb (zero new code).** If the anchor surface is itself a `climb:` Keyword
surface, M1's reel drops the player within `vr_climb_radius` → the **native `VR_UpdateClimbing` takes over**
seamlessly. Design ledges with `climb:` textures so whip → climb chains for free. This is the cleanest way
to "take advantage of our climb feature."

**CVars reused:** `vr_climb_radius`, `vr_climb_speed_mult`. **Tuning:** anchor persistence, max rope length /
tension, auto-release on ground or on button, haptic pulses (reuse `climb_texture` event).

**Route B option:** register the whip line as a transient "virtual climb anchor" inside `VR_UpdateClimbing`
so the reel uses the engine's real smoothed `GetHandVelocity` — better feel, small additive patch, on go-ahead.

---

# §N. Feature roadmap (tiers — each ships on the same rope core)

| Tier | Theme | Contents |
|---|---|---|
| **0** | **Core crack** (Route A) | mass-tapered Verlet, angular root drive, swept-tip hit, analytic supersonic crack, momentum damage/knockback |
| **1** | **Traversal** | grapple anchor (M0), reel/rope-climb (M1), pendulum swing + swing-jump (M2), wall-handoff to native climb (M3) |
| **2** | **Two-hand (CV4)** | free-swing/limp (L1), off-hand rope grab (L2), two-handed wind-up heavy crack |
| **3** | **Enchanted / extendable** | dynamic `REACH` growth (charged extend); length ↔ mass ↔ crack tradeoff; "magic" glow while extended |
| **4** | **Elemental enchants** | fire (ignite on crack), ice (root/slow), lightning (**chain-crack** to nearby foes) — hook the crack event + DoomXR glow/GITD FX + `DamageType`s |
| **5** | **Utility** | disarm (yank enemy weapon), pull items/levers at range (reuse gravity-gloves grab/throw), pull-self-to-point (short grapple dash) |

Build order: Tier 0 → 1 → 2 first (that's the Indy + CV4 core loop), then 3–5 as content. Route B (true
velocity / virtual climb anchor) can slot in anytime to sharpen feel.

---

# §O. Shader collaboration — how the render stack elevates the whip

**Principle:** the shader makes the whip's **physics visible** (momentum wave → supersonic tip → tension) and
carries the **enchanted/elemental** identity — all self-emissive (GITD, no dynamic lights), so it reads in the
dark. Lane split holds: **whip ZScript drives via the existing `AddGlowPanel`/`AddGlowSpot`/`msdf_*` bridge; the
shader owner adds shader-side primitives.** Lanes never cross.

## O1. Free today — zero shader change (ZScript drives existing primitives)
- **Crack shockwave** — `AddGlowPanel` **wgType 14** (ring) + **15** (disc flash) at the tip on crack = a visible sonic boom.
- **Electric / enchanted crack** — **wgType 26** (lightning bolt); chain-crack draws arcs between foes.
- **Damage feedback** — stamped number **wgType 16**, or `VR_SpawnMSDFText` floating number on hit; crit = bigger + `msdf_glitch`.
- **Light-painting** — drop `AddGlowSpot` pools on surfaces the tip sweeps over → the whip lights the room as you swing.
- **Grapple readout** — anchor reticle **wgType 18** (corner brackets) at the hook; tension shimmer **wgType 19** (oscilloscope).
- **"Wired" skin** — `msdf_glitch` / `msdf_color` on the segments/tip for the enchanted CRT shimmer.

## O2. Shader-owner lane — the one big unlock (+ polish)
- **Continuous speed-graded CORD (the headline).** Today the rope is 24 additive sprite quads (gaps, popping).
  A shader cord — a smooth tube between the node positions, thickness tapering base→tip, **emission color mapped
  to each segment's SPEED** (cool handle → white-hot supersonic tip) — makes the **momentum wave visible as light
  racing down the whip into the crack.** Cleanest bridge that stays in-lane: a **new `wgType` "cord segment"**
  consumed by the existing `DrawGlowBillboards` pass (ZScript still feeds it via `AddGlowPanel` — no new plumbing).
  Alt: a `uWhipNodes[32]` / `uWhipSpeed[32]` uniform + dedicated cord pass (mirrors `uWallGlowSpots[16]`).
- **Motion-blur tip trail** — a fading swept ribbon from the last N tip positions = the whip-crack streak.
- **VR post-process** — make sure the additive cord/crack survive the `getLightColor` **early-RETURN** (known VR
  gotcha, `main.fp:1047`) so the glow isn't swallowed in-headset.

## O3. Interface contract (what the whip hands the shader each tic)
`per-node world position[N]` · `per-node speed[N]` · `tip speed / crack flag` · `state (limp / taut / cracking)`
· `element (none/fire/ice/lightning)`. Published through the existing glow bridge; the shader renders. That's it.

---

# §P. Engine File Index — every path, lane-tagged

All paths relative to `E:\DoomXR-work\DOOM_FRESH\`. 🔒 shader (owner-only) · ✅ non-shader (open) · 📄 reference (read-only).

### Pose & firing API (what the whip reads each tic)
| File | Lane | Role | Key lines |
|---|---|---|---|
| `wadsrc\static\zscript\actors\actor.zs` | ✅ | `AttackPos/Angle/Pitch/Roll`, `OffhandPos/…`, `OverrideAttackPosDir`, `AttackDir/OffhandDir`, `Mass`, `Vel`, `Thrust`, `Vel3DFromAngle`, `VelIntercept`, `msdf_*` | 112,165,221-223,272-280,858-863 |
| `wadsrc\static\zscript\constants.zs` | ✅ | `ALF_ISOFFHAND = 256` | 933 |
| `wadsrc\static\zscript\actors\player\player.zs` | ✅ | `player.OffhandWeapon` (dual-wield) | 3139 |
| `src\scripting\vmthunks_actors.cpp` | ✅ | `DEFINE_FIELD`s: OverrideAttackPosDir(2190), AttackPos(2191-94), OffhandPos(2195-98), Mass(2088), Vel(2020), msdf(2064-66); Thrust/Vel3D thunks | 454-506, 2020-2198 |
| `src\playsim\p_actionfunctions.cpp` | ✅ | `AttackDir`/`OffhandDir` thunks (return angle,pitch,0!); `A_Recoil`→`VR_ApplyRecoil`; vr_ cvar defs | 91-99, 1311-1322, 5722-5740 |
| `src\playsim\actor.h` | ✅📄 | C++ fields: AttackPos/Angle/… (1671-1685), Mass, Vel, `Keywords` FString (1687), msdf (1301-1303) | 1301-1687 |
| `src\playsim\p_mobj.cpp` | ✅ | firing consumes AttackPos (7416/7427/7561); per-tic `DoEffect` gate `CF_PREDICTING` (4059); `VR_SpawnWiredImpact`(6407); `VR_SpawnMSDFText` DEFINE(7914) | see cells |
| `src\playsim\p_map.cpp` | ✅ | `OverrideAttackPosDir` branches in P_LineAttack/LineTrace/use | 4603,4786,4903,5204,6193 |

### VR motion / physics layer
| File | Lane | Role | Key lines |
|---|---|---|---|
| `src\playsim\p_user.cpp` | ✅ | velocity buffer(1486-94), **mass-throw**(1508-13), grab cone(1562), flick/catch(1526), bullet-snatch(1767), **CLIMB**(1864-1982), two-hand stabilize(1305) | 1305-1982 |
| `src\common\rendering\hwrenderer\data\hw_vrmodes.cpp` | ✅ | `VR_ThrowActor`(934, never called), VR recoil(1144), parry(1193), **CVar master block**: `vr_scale_meters_to_units=40`(388), `vr_vunits_per_meter=34`(400), `vr_throw_force=1`(486) | 356-574,934,1144,1193 |
| `src\common\rendering\hwrenderer\data\hw_vrmodes.h` | ✅ | `GetHandVelocity`/`GetHandAngularVelocity` virtuals (base=false), `VR_ThrowActor` decl | 172-184 |
| `src\common\rendering\vulkan\stereo3d\vk_openxrdevice.cpp` | ✅ | XrSpaceVelocity capture(3240-67), `GetHandVelocity`/`Angular`(4355-81), pose write(3753-73), teleport/crouch/room-scale(3736-3840) | 3240-4381 |
| `src\common\rendering\vulkan\stereo3d\vk_openxrdevice.h` | ✅ | velocity history ring buffers | 82-83,164-169 |
| `src\rendering\gl\stereo3d\gl_openvr.cpp` | ✅ | OpenVR `Controller` struct(865), `GetHandVelocity`(3034), WaitGetPoses(3123), pose store(3190); ⚠️ **no angular override** | 865-3190 |
| `src\gl\stereo3d\gl_openxrdevice.cpp` | ✅ | AttackPos/Offhand write(616-639), teleport(641); ⚠️ **no velocity capture (GL path)** | 616-641 |

### Glow / render bridge  (⚠️ `main.fp` + `hw_renderstate.h` are 🔒 shader lane)
| File | Lane | Role | Key lines |
|---|---|---|---|
| `wadsrc\static\zscript\doombase.zs` | ✅ | `Level.AddGlowSpot`(423) / `AddGlowSpotWiped`(426) / `AddGlowPanel`(429) | 423-429 |
| `wadsrc\static\zscript\mapdata.zs` | ✅ | `Sector.SetGlowSpot` | 545 |
| `src\scripting\vmthunks.cpp` | ✅ | native glow impls: AddGlowSpot(1145), Wiped(1166), AddGlowPanel(1184-1208) | 1136-1208 |
| `src\g_levellocals.h` | ✅ | `FGlowSpot` struct / `Level.GlowSpots` registry | 111 |
| `src\rendering\hwrenderer\scene\hw_glowbillboards.cpp` | ✅ | `DrawGlowBillboards` in-air panel pass; binds `neonfont.png` | 39,57 |
| `src\playsim\vr_msdf_text.cpp` | ✅ | world-space MSDF text engine; floating damage #s / wired impacts | 155,348 |
| `src\common\rendering\hwrenderer\data\hw_renderstate.h` | 🔒 | `SetWallGlowSpots`/`EnableWallGlow`, StreamData glow uniforms | 202,592-611 |
| `wadsrc\static\shaders\glsl\main.fp` | 🔒 | GITD glow cascade(866), neon SDF font(1251), procedural primitives wgType 14-26(716-1251), **VR early-RETURN gotcha(1047)** | 716-1251 |
| `wadsrc\static\gldefs.txt` · `…\vulkan\shaders\vk_shader.cpp` · `…\gl\gl_shader.cpp` · `…\gles\gles_shader.cpp` | 🔒 | shader compile/uniform plumbing | — |

### Playsim / Keywords
| File | Lane | Role | Key lines |
|---|---|---|---|
| `src\playsim\keyword_dispatcher.h` / `.cpp` | ✅📄 | Keywords: `IsClimbable`(`climb:<tex>`+speed), `IsThrowable`, mass, weapon offsets, parry extents; reads `KEYWORDS.json` | 53+ |
| `wadsrc\static\zscript\actors\interaction.zs` | ✅ | `ApplyKickback` (overridable knockback) | 41 |

### Model / IQM  — full patch spec in `DoomXR_Whip_IQM_Rigging_Patch_Spec.md`
| File | Lane | Role | Key lines |
|---|---|---|---|
| `src\r_data\models.cpp` | ✅ | `VRHandModel` state swap(213); **`ProcessModelFrame`** — render-time `animationData` build + the 1-line procedural-pose override hook (patch §2.2) | 213, 573-609 |
| `src\common\models\model.h` | ✅ | `FModel` base virtuals: `AttachAnimationData`/`PrecalculateFrame`/`CalculateBones` (the override seam) + new `NumBones`/`BoneName`/`BoneParent` (patch §2.3) | 107-111 |
| `src\common\models\model_iqm.h` | ✅ | `IQMModel` class: `Joints[]` (bind skeleton), `TRSData` (baked anim), `boneData` (GPU upload buffer) | 68-162 |
| `src\common\models\models_iqm.cpp` | ✅ | `CalculateBonesIQM` — **the seam**: `animationData ? *animationData : TRSData` | 680-740 |
| `src\common\utility\TRS.h` | ✅ | `TRS{translation,rotation(quat),scaling}` — the per-bone pose primitive | full file |
| `src\playsim\actor.h` | ✅ | `DActorModelData` — per-actor model state; patch adds `proceduralPose`/`useProceduralPose` (§2.1) | 733-752 |
| `src\playsim\p_actionfunctions.cpp` | ✅ | `A_ChangeModel`(5461), `SetAnimation`(5221); new bone thunks land beside these (§2.4) | 5221,5461 |
| `wadsrc\static\zscript\actors\actor.zs` | ✅ | model ZScript decls (~1235-1376); new `SetModelBonePose`/`GetModelBoneIndex` decls (§2.5) | ~1343 |
| `wadsrc\static\modeldef.txt` + `.iqm`/skin assets | asset | model binding + geometry | — |

### The whip itself (mod, not engine)
| File | Lane | Role |
|---|---|---|
| `wadsrc\static\zscript\xrwhip.zs` *(new)* | ✅ | the rebuilt whip — controller + segments + weapon |
| `E:\_whip\pk3\zscript\hf_whip.zs` | 📄 | the old prototype (reference; to be superseded) |

### Documentation set (this project's paper trail)
| File | Role |
|---|---|
| `C:\Users\Command\Desktop\Documentation\DoomXR_Physics_Whip.md` | this file — the living design doc |
| `C:\Users\Command\Desktop\Documentation\DoomXR_Whip_IQM_Rigging_Patch_Spec.md` | the Strategy-D bone-rigging patch spec (§Q companion) |

---

# §Q. Endgame — the whip as a rigged IQM model  ·  *"make me Indiana Jones"*

**Destination:** the whip is not sprites forever. It ends as a **real 3D leather bullwhip** — braided handle, a
thong that **tapers**, a fall + **popper** tip — rendered as **IQM** geometry so it reads as a physical object in
your hand in VR. The Indy fantasy is the whole point: crack it, grab with it, disarm a guard, **swing a gap**,
**climb** a ledge — with a whip that *looks and moves* like leather, in the dark, glowing where it matters.

**The pivotal question, precisely stated:** no ZScript thunk exists TODAY that writes an individual IQM bone
transform per tic — the 8 native model calls (`A_ChangeModel`, `SetAnimation`, …) only select named baked
animations. **But this is not a wall — it's an unwritten thunk**, exactly like every other DoomXR capability
(`AttackPos`, glow panels, `OffhandWeapon`) started as. Direct-read of the render pipeline (not secondhand
summary) found the engine **already has an unused extension seam built for exactly this**: `IQMModel::
CalculateBonesIQM` (`src\common\models\models_iqm.cpp:680`) takes an `animationData` override parameter and
literally does `animationData ? *animationData : TRSData` — if a custom per-bone pose buffer is handed in, the
existing interpolation/GPU-upload code renders it, unmodified. The only real gap is: nothing populates that
buffer from ZScript yet. **Full patch spec — exact structs, file:line, function signatures, the whip's per-tic
usage — is written up in the companion doc:**
`C:\Users\Command\Desktop\Documentation\DoomXR_Whip_IQM_Rigging_Patch_Spec.md`. It is a small, 100%
**non-shader-lane** patch (no `.fp`/`hw_renderstate.h` touched — bones still upload through the existing GPU
bone buffer).

| Strategy | How | Needs | Fidelity |
|---|---|---|---|
| **A. Segmented model chain** | N short IQM segments, each a world-actor `SetOrigin()`'d + oriented by the sim; anchor node reads `AttackPos`/`OffhandPos` each tic | nothing new — **swarm-verified working**, precedent code exists | high shape, seams between links |
| **B. Handle-model + shader cord** | IQM **handle only** (the part that doesn't bend) + the §O shader cord for the flexible thong | shader cord (§O2) | best-looking; hybrid |
| **C. Canned crack animations** | a set of pre-authored IQM whip-crack anims played via `SetAnimation` (like the reload system) | rigged anims; not physics-driven | cinematic but not 1:1 |
| **D. Procedural bones (the real answer)** | push the sim's 24 node transforms straight onto the model's bones each tic, riding the `animationData` seam | small non-shader engine patch — **spec'd + swarm-verified**, see companion doc | true 1:1 model whip |

**Recommendation:** ship **A/B** now for the instant leather-in-hand Indy look while the **D** patch is
implemented and tested in parallel — D is the actual destination, not a maybe.

**⚠️ `MDL_FOLLOW` does NOT exist** (swarm-refuted, 100%) — an earlier draft invented it. World-space actors
track the VR hand by **reading `AttackPos`/`OffhandPos` each tic and calling `SetOrigin()`** — no MODELDEF
flag; live precedent at `weaponshieldsaw.zs:89`, `gitd_dark.zs:361,367`. HUD weapon models get the exact
controller matrix in C++ (`RenderHUDModel`→`GetWeaponTransform`), which world actors don't — so a handle that
must be sub-frame-glued to the hand stays a PSprite layer.

**🔬 Swarm confidence audit (2026-07-03, 7-agent adversarial pass) — the three highest-risk assumptions:**
| Assumption | Verdict | Confidence |
|---|---|---|
| ZScript `Quat` type (`*`, `.Conjugate()`, `.Inverse()`, `QuatStruct.AxisAngle/FromAngles/SLerp`) | **CONFIRMED real, first-class** | 98/100 |
| IQM bone axis / `swapYZ` — procedural TRS written in **IQM Y-up**, `BONE_FWD=(0,1,0)` | mechanism CONFIRMED; exact axis pending a 20-min 2-bone test | 91/100 |
| `MDL_FOLLOW` flag | **REFUTED — fake; real mechanism = `SetOrigin` from `AttackPos`** | 99/100 |

Full detail in the companion patch spec §7. Net: Strategy A is now zero-patch de-risked; Strategy D's every
primitive is confirmed present, with only the bone rest-axis needing an empirical lock.

**Indy feel checklist (what "make me Indiana Jones" means concretely):**
- leather handle model in-hand, tracked 1:1 to the controller;
- a thong that **sags, whips, and cracks** with the momentum sim (§C–§F);
- **grab / disarm / pull** at range (Tier 5); **swing** and **climb** (§M);
- glowing crack + swept trail so it sings in a dark arena (§O);
- extend / enchant so it grows past a real whip into the "enchanted extendable" (Tiers 3–4).

**Usable model toolkit today (verified):** `A_ChangeModel(...)` (`p_actionfunctions.cpp:5461`) attaches/swaps
an IQM + skin + animation onto an actor at runtime; `SetAnimation(name, framerate, startFrame, loopFrame,
endFrame, interpolateTics, flags)` (`p_actionfunctions.cpp:5221`, needs `+DECOUPLEDANIMATIONS` + a MODELDEF
`baseframe`) plays named baked anims; MODELDEF directives `scale/offset/angleoffset/pitchoffset/rolloffset/
surfaceskin/baseframe/useactorpitch/useactorroll` (`src\r_data\models.cpp:873-1135`) control static
orientation and per-mesh skins. This toolkit alone is enough to build Strategies A/B/C today.
