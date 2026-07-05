![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DXR — DIKX Update - "DIKX IN BOTH HANDS!"

*DIKX — **D**oom **I**nverse **K**inematics × **XR** *

This is proabably all snakeoil bullshit but if you read any of this it should be technical accounting: [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md) because all the  shit is there for verification.

A fork of **DoomXR** (iAmErmac's QuestZDoom-based VR fork of GZDoom) rebuilt into a purpose-built VR light-gun / physical-melee game. Design rule throughout: **behavior lives in native C++ per-tic subsystems; ZScript and JSON are data and thin override hooks.**

---

fuck me. most major breakthrough was ik model, sorta, ditched the lower half. 

almost got player holding weapon okay. physical reloading might work? 

good luck with this shitshow, lol

---

> [!WARNING]
> **Status: work-in-progress.** Some systems await a full rebuild to activate.

**Baseline vs. upstream DoomXR:** 439 files changed, +18,431 / −10,831 lines. Full file-by-file technical accounting: [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

---

## Top 15 — look what you can do

! If you think I verified any of these, lol !

1. **[Your own body, and its arms actually reach](#1-your-own-body-and-its-arms-actually-reach)** — a first-person 3D marine whose arms track your controllers *exactly*, because the solve is the algebraic inverse of the renderer's own matrix.
2. **[A real physics bullwhip](#2-a-real-physics-bullwhip)** — a Verlet rope with a supersonic tip-crack, grapple-swing, and an entangle-yank that reels an enemy into your hand.
3. **[Walk on the walls and ceiling](#3-walk-on-the-walls-and-ceiling)** — a palm-out power paints a glowing walkway and flips your gravity onto it; per-actor "down" is a real field.
4. **[Reload by hand](#4-reload-by-hand)** — eject the mag, reach to your chest for a fresh one, seat it, rack the charging handle. A native per-weapon state machine, 14 guns.
5. **[Throw anything, catch anything](#5-throw-anything-catch-anything)** — hurl any gun at real arm speed; rip a grenade out of the air and pitch it back.
6. **[Impact momentum — everything has mass](#6-impact-momentum--everything-has-mass)** — throw a heavy body into a light one and it *slides*; eat a rocket and *you* get shoved. Force = mass × velocity, on everything including you.
7. **[Grab, punch, and throw enemies](#7-grab-punch-and-throw-enemies)** — off-hand grab a monster, main-hand beat it, then hurl the body into a crowd to stagger them.
8. **[Melee that parries bullets](#8-melee-that-parries-bullets)** — swing-tracked sword/shieldsaw/ice-hook with real per-tic blade collision that deflects incoming shots.
9. **[Physical holsters on your body](#9-physical-holsters-on-your-body)** — hip for a blade, shoulder for climbing picks, wrist for an ability; markers can't drift because they read the trigger itself.
10. **[3D models for ANY weapon mod](#10-3d-models-for-any-weapon-mod)** — load any weapon mod and DXR gives its guns animated 3D shells, foreign-tic accurate, zero per-mod patching.
11. **[Behavior as data — KEYWORDS.json](#11-behavior-as-data--keywordsjson)** — tag a monster "weak to headshots," a wall "climbable," a gun "kicks hard," all in one JSON file, resolved natively.
12. **[The gesture engine — your hands are the input](#12-the-gesture-engine--your-hands-are-the-input)** — draw a circle to cast, flick at your chest to reload; motions become verbs, and new gestures are a line of JSON.
13. **[Holographic displays out of pure math](#13-holographic-displays-out-of-pure-math)** — ~30 in-world SDF gauges/digits/oscilloscopes and razor-sharp text, zero sprites, plus hot-loaded full-screen visual regimes.
14. **[Two-handed stabilization that feels real](#14-two-handed-stabilization-that-feels-real)** — grab a long gun's foregrip and the aim steadies through a barrel-axis capsule test, per-weapon grip geometry.
15. **[Build your own VR mechanic, no C++](#15-build-your-own-vr-mechanic-no-c)** — ~33 native hooks compose into new mechanics in ZScript; the whip is 5 hooks in a row, and so is a grappling hook or a fishing rod.

---

## This is an engine fork, not a mod — the native C++ under it

The easy content layer (JSON, ZScript, browser editors) exists **because the hard engineering was paid up front.** The behavior of every VR system lives in a native per-tic C++ subsystem. Beyond the 15 above, the load-bearing plumbing:

* **Grip-intent arbiter** — one grip owner per hand resolved once per tic under single-`Vel`-writer discipline, so climb / whip / gloves / holsters never fight over the same hand (and the fling bugs that caused are gone). Handedness-correct.
* **Analog + motion input to gameplay** — smoothed, tic-normalized hand velocity (swing/flick thresholds) and analog grip squeeze (0–1) exposed to scripts as real gameplay signals.
* **35 Hz VR determinism bridge** — 90 Hz+ controller pose filtered into stable gameplay values (a 4-sample velocity buffer normalized by `/35`, an exponential body-height smooth), and 6DoF pose reduced onto net-safe button bits so VR actions stay multiplayer-deterministic.
* **Procedural-bone model path** — `SetModelUseProceduralPose` + `SetModelBonePose(bone, TRS+quat)` push script-computed skeletons onto IQM models each tic (the arm-IK and the whip rig both ride this).
* **VR-safe glow/SDF render plumbing** — per-frame `level.AddGlowPanel` streaming, per-actor `msdf_*` fields, StreamData UBO uniforms (with the std140 alignment fix that cured the black-world corruption).
* **Crash-hardening** — FString-in-`memset` fixes and null-deref guards across the actor / line / sector / mapthing paths; undeclared-CVAR fixes.

**Want the receipts?** Every subsystem, every exact file, is in [`DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

---

## 1. Your own body, and its arms actually reach

DXR renders your 3D marine in first person and drives its arms to your controllers every tic. The flagship trick is *how*: instead of hand-rebuilding the transform chain (drawn yaw, body height, scale, coordinate swap) and dialing it in, the IK **inverts the renderer's own matrix.**

The renderer publishes its finalized VR-body model matrix — the *exact* one the GPU skins with — and the IK does one operation: `target = swapYZ · objectToWorld⁻¹ · controller`. That single inverse cancels the drawn yaw, the body Z, the scale, and the coordinate swap **all at once**, for free. The hand lands on the controller *by construction* — an adversarial check proved the round-trip exact to **1.6 × 10⁻¹⁴**, machine epsilon. It's exact where hand-math never was.

On top of that: a law-of-cosines two-bone shoulder/elbow solver with a pole-vector elbow and an optional stretch to over-reach; a wrist fix that re-orthonormalizes with a *reversed* cross-product to cancel the swap's mirror (otherwise the palm renders inside-out); and auto-fit height that anchors the neck stump at your eye level and stays scale-invariant because the inverse undoes the same scale. The model's a headless DOOM Eternal Slayer rip — no head, because you don't look at your own face.

*Your arms reach exactly where your hands are because the solve is the algebraic inverse of the draw, not an approximation of it.*

## 2. A real physics bullwhip

The whip (XRWhip) is a 16-node Verlet rope, not an animation. Sling your arm and the tip goes **supersonic** and cracks; hold it taut against an anchor and it becomes a grapple-swing you ride; catch an enemy in the lash and the **entangle-yank** reels them into melee. Two-hand it for control.

The clever part is the architecture: the whip is *five native hooks in a row* — read hand velocity (crack) → render the rope → claim pawn motion for the swing → catch into a held slot → throw. Swap the rope sim and drop or keep steps and the **same stack** is a grappling hook, a fishing rod, a lasso, a chain flail, or a rope bridge. Each is a ZScript file, zero recompiles.

## 3. Walk on the walls and ceiling

Gravity is a per-actor field (`GravityDir`), not a global constant. Hold your palm out and a power paints a glowing SDF walkway across a surface; step onto it and your personal "down" re-solves onto that surface — you walk up the wall, across the ceiling, upside down. `FallAndSink` was rewritten so it applies even while grounded (that's what makes ceiling-hang work), and a rail-guard movement override re-projects your momentum onto the path's own basis so it *redirects* your run without ever changing your speed or feel.

## 4. Reload by hand

No reload button — you do it. Eject the mag, reach to a pouch on your chest, pull a fresh one, seat it in the well, rack the charging handle. A native five-state machine per weapon runs it, and 14 guns opt in with a single mixin line.

Every player-driven step is a real gesture: seating needs a fresh grip *at the gun* (a magnetic assist softly guides the mag the last inch, because VR reach is imprecise — but it never moves *you*). The rack is *directional* — it projects your hand's motion onto the barrel axis and tracks the max, so a real backward pull chambers a round but a sideways wiggle does nothing, and tracking jitter can't cancel a good pull. Four haptic beats mark the rhythm. And the **juice** is stacked on top: spent mags physically fall and litter the floor and can *damage a monster you fling one into*; a perfect-timing window pops a neon bonus; tactical reloads keep the chambered round; you can toss-and-catch a mag hands-free, or whip-yank ammo straight into the gun for an instant reload.

## 5. Throw anything, catch anything

Any equipped weapon or held object throws at your **real controller velocity**, mass-scaled — chuck a pistol across the room. The engine can inject any actor into a hand's held-item slot, so you can **catch** things too: rip a live grenade out of the air and pitch it back through the exact same throw path the whip's yank-catch uses. One shared pipeline: yank → catch → throwback.

## 6. Impact momentum — everything has mass

A moving body shoves whatever it hits by **mass × velocity ÷ target-mass**, clamped — and it applies to *everything, including you.* Throw a heavy corpse into a light imp and the imp slides across the floor. A heavy target barely budges. Take a rocket and *you* get physically shoved backward. It hooks the engine's kickback thrust seam so it's global — every collision in the game suddenly has weight behind it, tunable with a few cvars.

## 7. Grab, punch, and throw enemies

Off-hand **grab** a monster, main-hand **beat it down** (with a weapon or your fist), then **hurl the body** into a crowd to stagger everything it hits. It's a full VR grapple loop — grab, strike, throw — and the thrown body carries the impact-momentum physics above, so tossing a big enemy into a pack actually knocks them around.

## 8. Melee that parries bullets

VRSword, ShieldSaw, and IceHook are swing-tracked with real **per-tic segment collision** (broad + narrow phase down the blade), so it's your actual swing that connects, not a hitbox pulse. And with the right keyword a blade **deflects incoming projectiles** — time a swing and knock a shot out of the air. The sword hot-swaps profile (Steel / Lightsaber / Dragon's-Tooth) as data; the shieldsaw blocks, saws, and throws as a returning boomerang; the ice-hook bites any solid wall for velocity-driven climbing.

## 9. Physical holsters on your body

Reach to a spot on your body and draw what's there: hip for a sword or whip, shoulders for climbing picks, a wrist mount to fire an ability or spell. The slot markers **can't drift** because they read position from the exact same routine the draw-trigger uses. Body slots (shoulders/hips) and wrist ability-mounts are a native system, and the whole layout is overridable in `vr_hardpoints.json`.

## 10. 3D models for ANY weapon mod

DXR replaces flat weapon sprites with animated 3D models **without the model knowing anything about the mod driving it.** A native interception in `DPSprite::SetState` re-syncs the model's animation to the weapon's own state (Ready / Fire / Reload / …). Load any weapon or gameplay mod — its logic, sounds, damage, and effects drive; DXR supplies the animated 3D shell. It's foreign-tic accurate (fixes the classic "model frozen on Ready during Fire" bug), works in flatscreen too, and ships with ~11 weapons modeled so a bare mod inherits models instantly.

## 11. Behavior as data — KEYWORDS.json

Attach behavior to any monster, weapon, or surface with words. Tag an imp "weak to headshots," a wall "climbable," a gun "kicks back hard," a monster's blood a color — all in one JSON file, resolved natively at load. It's namespaced and typed (kickback, vulnerability, ballistics with bullet-drop and air-resistance, per-weapon mass and two-hand radius and parry sound), and **most-specific-match** wins, so `[imp + headshot + tier_3]` beats a generic default. One data file feeds directional kickback, projectile parry, dodgeable-hitscan tagging, grab opt-in, and climbable surfaces. No code, no recompile.

## 12. The gesture engine — your hands are the input

Draw a circle in the air to arm a spell. Flick at your chest to reload. Trace a lasso to wind up the whip. Your hand *motions* are first-class input — and it all runs on **one engine, not ninety hardcoded moves.**

Every tic a native classifier watches each hand's recent motion and names the *verb* — flick, thrust, slash, circle, reversal. A plain JSON table maps "this verb, at this body spot, with this button → fire this action." Match a row, it calls one script hook. So a new gesture isn't code — it's **a line of JSON and a script case, no recompile.** The planned 90-gesture library ships as a data file; a whole *magic game's* worth of sigils could ship as another. One engine, infinite moves.

## 13. Holographic displays out of pure math

Every neon readout in the game — score digits, gauges, an oscilloscope, spectrum bars, shockwave rings, reticles, a materializing skull, ~30 shapes — is drawn as **signed-distance-field math, zero sprites**, so it's razor-sharp at any size and streams per frame. Text is true-MSDF, resolution-independent. On top of that, drop-in `.fp` shaders compile at runtime and whole full-screen visual regimes (System Shock / Tron / Thermal / Digital Noir / …) ride a **world-space proximity mask** so they never warp screen-space right in front of your face — the thing that makes most fullscreen VR effects nauseating.

## 14. Two-handed stabilization that feels real

Bring your off-hand to a long gun's foregrip and the aim steadies — but the detection is a **barrel-axis capsule test** (point-to-segment down the actual barrel, with per-weapon grip geometry from `KEYWORDS.json`), not a fixed second-grip point. So the natural forward grip engages where the gun actually is, and you don't trigger a two-hand hold by accident with your hand near your face.

## 15. Build your own VR mechanic, no C++

Every VR subsystem is native C++ **exposed forward to ZScript** as a composable toolkit — ~33 hooks plus modder virtuals. You reach straight into the engine's primitives and recombine them into *new* mechanics with C++-level power and zero C++. The bullwhip is five hooks in a row; swap two steps and the same stack is a grappling hook, lasso, or fishing rod. The gesture engine hands a fired gesture to a virtual you override. Two access levels on one engine: **author in data** for content, **compose native hooks** for mechanics — and neither needs a recompile.

Full hook catalog and the modding surface are below.

---

## Native hook surface (the ~33)

Every VR subsystem is native C++ exposed to the VM through `Actor` (and two `PlayerPawn` virtuals). Complete script-facing surface:

**Metadata & render fields**
* `GravityDir` / `GravityAnchor` (vector3) — per-actor unit "down" + the reference point the solve pulls along.
* `Keywords` (String) — token list resolved against `KEYWORDS.json`.
* `msdf_color` / `msdf_enabled` / `msdf_glitch` — per-actor SDF tint, mode/shape-bit, glitch amount.

**Pose & analog input**
* `GetHandVelocity(hand)` → vector3 · `GetHeadPos()` / `GetHeadAngles()` → vector3 · `GetGripValue(hand)` → double (analog squeeze 0..1).

**Procedural model / arm-IK**
* `SetModelUseProceduralPose(enable)` · `SetModelBonePose(bone, tx,ty,tz, qx,qy,qz,qw)` · `SetArmIKEnabled(enable)`.

**Hardpoints**
* `AssignHardpoint(...)` → slot · `ClearHardpoint` · `IsHardpointNear(hand)` · `GetHardpointStowed` · `GetHardpointCount` · `GetHardpointAnchorType` · `GetHardpointWorldPos(slot, forHand)` · `VR_HolsterHand`.

**Grip-intent arbiter**
* `VR_GetGripOwner(physHand)` · `VR_PhysicalHandForSlot(slot)` · `VR_SetWhipSwingLive(bool)` · `VR_SetWhipRopeAttached(physHand, bool)` · owner ids `GRIP_NONE/CLIMB/GLOVE/WHIP/HARDPOINT/TWOHAND`.

**Held-item / throw / weapon-model / feedback**
* `VR_TrySetHeldItem(hand, item)` · `GetVRWeaponArchetype(class)` (static) · `VR_HapticPulse(hand, intensity, duration)` · `level.AddGlowPanel(...)` · `level.SpawnSDFText(...)`.

**Modder virtual dispatch (`PlayerPawn`)** — reached via `IFVIRTUALPTRNAME`; keep `virtual`.
* `VR_DoHolster(hand, slot)` · `VR_HardpointAbility(hand, slot)`.

---

## Author without recompiling — the content stack

Most of the game is authored without touching C++, by effort:

**Edit a JSON (no tools):** `KEYWORDS.json` (behavior by token) · `vr_gestures.json` (gestures) · `vr_hardpoints.json` (holster/wrist layout) · `vr_climb_textures.json` (bare-hand climbable surfaces — picks and whip grab anything) · `doomxr_weapons.json` (weapon → 3D-model archetype) · `sdf_combos.json` (in-world SDF displays).

**Run a Python pipeline:** `tools/weapon_iqm_build/` (MD3 → IQM with geometry-derived two-hand grip hotspots + validation) · `tools/sdf_authoring/gif_to_sdf_atlas.py` (animated GIF → SDF atlas).

**Point-and-click HTML editors:** `sdf_combo_authoring.html` · `sdf_upgrade_authoring.html`.

**Drop-in, no recompile:** custom `.fp` shaders — place in a pk3, bind via `GLDEFS` (`ProcessTexel()`, not `main()`), GLSL compiles at runtime.

The GITD "glow-in-the-dark" visual layer ships as an overriding `main.fp` from the **[Radiance Control Panel](https://github.com/presidentkoopa/RadianceControlPanel)** companion; the base engine renders plainly without it.

---

### Source Code & Licensing
Builds on the open-source foundations of **DoomXR** (iAmErmac), **QuestZDoom**, **UZDoom**, and **GZDoom**. Licensed under the **GPL v3**.
