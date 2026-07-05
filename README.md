![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DXR — DIKX Update

*DIKX — **D**oom **I**nverse **K**inematics × **XR**: a first-person body that reaches where your hands do — and both of them stay full.*

A fork of **DoomXR** (iAmErmac's QuestZDoom-based VR fork of GZDoom) rebuilt into a purpose-built VR light-gun / physical-melee game. Design rule throughout: **behavior lives in native C++ per-tic subsystems; ZScript is limited to data and thin override hooks.** Full technical accounting in [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

## Top 15 features

1. **First-person body avatar with native arm IK** — your own 3D marine renders in-view; a two-bone C++ solver drives its arms to track your controllers, with auto-fit height.
2. **Physics bullwhip (XRWhip)** — a 16-node Verlet rope with a supersonic tip crack, taut-line grapple-swing, and entangle-yank that reels an enemy into your hand.
3. **Per-actor directional gravity** — walk on walls and ceilings via a palm-out power that paints an SDF walkway, built on a native `GravityDir` field.
4. **Universal 3D weapon models for any mod** — 3D shells sync to any loaded mod's weapon logic/sounds/damage with no per-mod patching; any mod, any weapon.
5. **Physical hardpoint holsters** — reach to your hip for a sword and whip, or your shoulders for climbing picks, or a wrist mount to fire an ability / spell; markers read the native trigger position so they can't drift. Extensive debug cones and spheres for customization.
6. **Swing-tracked melee that parries bullets** — VRSword and other weapons with adjusted collision for real per-tic segment collision + native keyword projectile deflection (plus ShieldSaw and IceHook).
7. **Composable native hook toolkit (~33 hooks)** — new VR mechanics are ZScript recombinations of existing primitives, not new C++ (see below).
8. **KEYWORDS.json behavior engine** — per-actor and per-weapon behavior (kickback, vulnerability, ballistics, parry) declared as data, resolved natively, no recompile.
9. **Grip-intent arbiter** — one owner per hand resolved by priority so climb / whip / gloves / holsters never fight over the same grip; handedness-correct.
10. **Analog + motion input to gameplay** — smoothed, tic-normalized hand velocity (swing/flick detection) and analog grip squeeze (0–1) exposed to scripts.
11. **Data-driven gesture engine** — a native per-tic classifier reads a per-hand motion-history ring buffer and names the verb (flick / thrust / slash / circle / reversal / …), matched against a declarative `vr_gestures.json` table; a fired gesture calls one `VR_GestureFired` ZScript hook. New gestures are a JSON row plus a script case — no recompile. The planned 90-gesture library (and a whole magic game's worth of sigils beyond it) ships as a JSON file, not 90 hardcoded C++ moves — one engine, infinite content.
12. **Manual per-weapon reload FSM** — physically break the action, eject the mag/shell, and reach to a chest pouch to pull a fresh one; a native bone-read + hotspot state machine (14 weapons wired) tracks the chamber and drives baked model frames. Rides a mixin so mod weapons inherit it; eject step, tactical mag-out hook, and ~25 options exposed.
13. **Physical throwing + mid-air catch** — throw any equipped weapon or held object at real controller velocity (`VR_ThrowEquippedWeapon`, mass-scaled), inject an actor into a hand's native held-item slot (`VR_TrySetHeldItem`), and catch → throw back — the whip's entangle-yank feeds straight into the same throw path. You can rip a grenade out of the air and pitch it back.
14. **Native SDF display + runtime shader layer** — ~30 procedural in-world displays (digits, gauges, oscilloscope, spectrum bars, shockwave rings, reticles, materialize skull) and resolution-independent true-MSDF glyphs, streamed per-frame as pure distance-field math with **zero sprites**; per-actor `msdf_*` fields route content, drop-in `.fp` shaders compile at runtime, and full-screen visual regimes (System Shock / Tron / Thermal / Digital Noir / …) ride a **world-space proximity mask** so they never warp screen-space near your face.
15. **Two-handed weapon stabilization** — bring your off-hand to any long gun's foregrip and the aim steadies through a **barrel-axis capsule test** (point-to-segment, per-weapon grip geometry from `KEYWORDS.json`), not a fixed second-grip point — so the natural forward grip engages and accidental two-hands don't.

> [!WARNING]
> **Status: work-in-progress***

**Baseline vs. upstream DoomXR:** 439 files changed, +18,431 / −10,831 lines.

Yo some of this shit is native to the buiid I started from, but a shitload of this is new to DXR.
Just wait until I get portalstacking in here.

---

## This is an engine fork, not a mod — the native C++ under it

The easy content layer (JSON, ZScript, browser editors) exists **because the hard engineering was paid up front.** The behavior of every VR system lives in a native C++ per-tic subsystem:

* **Two-bone arm-IK solver** — drives a first-person body avatar's arms to your controllers every tic, with auto-fit height.
* **Per-actor directional gravity** — `FallAndSink` rewritten so `GravityDir` applies even while grounded (wall-walk / ceiling-flip), on a real per-actor field.
* **Verlet-rope physics** — a 16-node bullwhip: supersonic-tip crack, two-hand coupling, taut-line grapple-swing, entangle-yank.
* **Grip-intent arbiter** — one grip owner per hand resolved once per tic under single-`Vel`-writer discipline, closing double-write fling bugs between climb / whip / gloves.
* **Native hardpoint system** — shoulder/hip holsters + wrist ability mounts, markers pulled from the same routine the trigger uses so they can't drift.
* **Manual-reload FSM** — per-weapon bone-read + hotspot + state machine driving baked model frames.
* **Universal 3D weapon-model interception** — a hook in `DPSprite::SetState` re-syncs any mod's weapon to an animated 3D shell, foreign-tic accurate, no per-mod patching.
* **Keyword dispatcher** — native token resolver applying `KEYWORDS.json` behavior with most-specific-match.
* **Data-driven gesture engine** — per-tic motion-history ring buffer + verb classifier matched against a JSON table.
* **35 Hz VR timing bridge** — 90 Hz+ VR pose filtered into stable gameplay values (velocity buffer, exponential height smooth).
* **SDF / shader pipeline** — true-MSDF glyphs, ~30 procedural in-world displays, full-screen visual regimes, all VR-safe.
* **Two-hand capsule stabilization** — off-hand foregrip resolved by a point-to-segment test down the weapon's barrel axis (perpendicular tolerance + forward length per weapon), replacing the sphere test that mis-fired.
* **Physical throw + held-item slots** — native injection of an actor into a hand's held slot and a mass-scaled weapon throw at real controller velocity; the entangle-yank → catch → throwback loop is one shared path.
* **Per-hand haptic pulses** — `VR_HapticPulse(hand, intensity, duration)` fired from swing / impact / parry / gesture events.
* **Net-deterministic VR input reduction** — 6DoF controller pose collapsed onto net-safe button bits (reload / grip / user) so VR actions stay multiplayer-deterministic instead of leaking render-thread pose into the sim.
* **VR-safe glow / SDF render plumbing** — per-frame `level.AddGlowPanel` streaming, per-actor `msdf_*` fields, and StreamData UBO uniforms carrying it to the shader — including the std140 alignment fix that cured the black-world corruption.
* **Procedural-bone model path** — `SetModelUseProceduralPose` + `SetModelBonePose(bone, TRS+quat)` push script-computed skeletons onto IQM models each tic (the arm-IK and the whip rig ride this).
* **Directional-gravity SDF walkway** — a palm-out power paints capture tiles that re-solve the player's `GravityDir`, with a rail-guard `MovePlayer` override that re-projects momentum onto the path basis (redirect, never speed).
* **Crash-hardening** — FString-in-`memset` fixes and null-deref guards across the actor / line / sector / mapthing paths; undeclared-CVAR fixes.

Design rule throughout: **behavior is native C++; ZScript and JSON are data and thin override hooks.** Baseline vs. upstream DoomXR: **439 files changed, +18,431 / −10,831 lines.** The native cost is paid; the content phase is script.

---

## VR & Input Interaction — native hook surface

Every VR subsystem is native C++ exposed to the VM through `Actor` (and two `PlayerPawn` virtuals). Complete script-facing surface:

**Metadata & render fields**
* `GravityDir` (vector3) — per-actor unit "down"; zero = stock −Z gravity.
* `GravityAnchor` (vector3) — reference point the directional-gravity solve pulls along.
* `Keywords` (String) — comma/space token list resolved against `KEYWORDS.json`.
* `msdf_color` / `msdf_enabled` / `msdf_glitch` — per-actor SDF tint, mode/shape-bit, glitch amount.

**Pose & analog input reads**
* `GetHandVelocity(hand)` → vector3 — smoothed controller velocity, metres→map-units/tic, for swing/flick thresholds.
* `GetHeadPos()` → vector3 — HMD center-eye world position.
* `GetHeadAngles()` → vector3 — HMD yaw/pitch/roll.
* `GetGripValue(hand)` → double — analog grip squeeze 0..1.

**Procedural model / arm-IK**
* `SetModelUseProceduralPose(enable)` — switch an IQM model from baked animation to script-driven bone TRS.
* `SetModelBonePose(boneIndex, tx,ty,tz, qx,qy,qz,qw)` — write one bone's model-local translation + quaternion.
* `SetArmIKEnabled(enable)` — toggle the two-bone arm-IK solver on the body avatar.

**Hardpoints (holsters / wrist mounts)**
* `AssignHardpoint(anchor, actionType, hand, ox,oy,oz, radius, weaponClass, abilityName, cells)` → slotIndex — register a mount.
* `ClearHardpoint(slotIndex)` — unregister.
* `IsHardpointNear(hand)` → slotIndex — mount the hand is inside the trigger radius of.
* `GetHardpointStowed(slotIndex)` → Actor — weapon holstered in a slot.
* `GetHardpointCount()` → int.
* `GetHardpointAnchorType(slotIndex)` → int — body vs. wrist.
* `GetHardpointWorldPos(slotIndex, forHand)` → vector3 — live position from the same routine the trigger uses (markers can't drift).
* `VR_HolsterHand(hand, slotIndex)` — force a draw/stow from script.

**Grip-intent arbiter** (one owner per hand, resolved once per tic)
* `VR_GetGripOwner(physHand)` → int — which system owns a hand's grip.
* `VR_PhysicalHandForSlot(slot)` → int — resolve a slot to the correct physical L/R controller (handedness-aware).
* `VR_SetWhipSwingLive(bool)` — publish that a live whip swing owns pawn velocity this tic (climb yields → single Vel writer).
* `VR_SetWhipRopeAttached(physHand, bool)` — inform the arbiter a hand's rope is anchored.
* `GRIP_NONE / GRIP_CLIMB / GRIP_GLOVE / GRIP_WHIP / GRIP_HARDPOINT / GRIP_TWOHAND` — the six owner identities.

**Held-item / throw**
* `VR_TrySetHeldItem(hand, item)` → bool — inject an actor into a hand's native held-item slot (whip yank-catch → throw).

**Weapon-model mapping**
* `GetVRWeaponArchetype(Class<Actor>)` → int (static) — 3D-model archetype for a weapon class.

**Modder virtual dispatch (`PlayerPawn`)** — reached via `IFVIRTUALPTRNAME`; must stay `virtual`.
* `VR_DoHolster(hand, slotIndex)` — invoked on stow; default tears down that hand's PSprite.
* `VR_HardpointAbility(hand, slotIndex)` — invoked when a wrist ability fires; no-op extension point.

### The hooks compose

The hooks are single-purpose primitives; new mechanics are recombinations, not new C++. The whip is a five-primitive pipeline: `GetHandVelocity` (crack) → render the rope → `VR_SetWhipSwingLive` (claim motion) → `VR_TrySetHeldItem` (catch) → throw. Swap the rope sim and drop/keep steps and the **same stack** is a grappling hook, fishing rod, lasso, chain flail, or rope bridge — each a ZScript file, zero recompiles. The native cost was paid up front; the content phase is script.

> The whip's visible rope is drawn today with **glow-panel billboards** (`level.AddGlowPanel`) following the Verlet sim. A `SetModelBonePose` path that pushes the sim onto a 21-bone rigged IQM runs each tic (`vr_whip_model` on by default), but that model is **not yet rendering** — its modeldef has no `FrameIndex` and it awaits the procedural-bone wiring. So the bone hook is called; the bone-driven *model* is not what you currently see.

---

## First-person body avatar — arm-IK by renderer matrix-inverse

DXR renders your own 3D marine in first person and drives its arms to your controllers every tic. The flagship trick is *how* the world→model-local conversion is done: instead of hand-rebuilding the transform chain (drawn yaw, body Z, body scale, coordinate swap) and dialing it in, the IK **inverts the renderer's own matrix.**

* **Publish the exact GPU matrix.** The renderer captures its finalized VR-body model matrix as a global — `VSMatrix g_xr_vrBodyObjectToWorld` (+ valid flag) — at `r_data/models.cpp:323`, the last mutation before `BeginDrawModel`. That's the *exact* matrix the GPU skins with, handed to the playsim through a lock-free render→playsim contract.
* **One inverse solves everything.** `VR_UpdateArmIK` (`playsim/p_user.cpp`) computes, per hand:
  `target_baseframe = swapYZ · objectToWorld⁻¹ · controller_world_GL`
  — where `swapYZ` is the Y/Z row-swap matching the IQM skinning convention and `controller_world_GL` is the raw GL columns (`m[12], m[13], m[14]`) of the controller transform. That single inverse subsumes the drawn body yaw, `vr_body_z`, `bodyScale`, **and** the coordinate swap — all inverted for free, no dialing. The hand lands on the controller *by construction*; an adversarial check proved `render(F⁻¹(ctrl)) == ctrl` to **1.6 × 10⁻¹⁴** (machine epsilon). Exact where hand-math never was.
* **Two-bone solver.** `IK_SolveTwoBoneArm` — a law-of-cosines shoulder/elbow solve in the model's baseframe; elbow direction from a pole vector; world-space joint rotations converted to parent-relative for the pose. An optional clamped stretch lets the arm exceed its natural span to reach.
* **Wrist orientation (the subtle fix).** `IK_ControllerModelRot` transforms the controller's forward/up basis as *directions* (`w=0`) through the **same** inverse, then re-orthonormalizes with a **reversed cross order** (`right = f × u`, not `u × f`) — because the inverse carries `swapYZ`, which is orientation-reversing (det −1); the naive order renders the palm **mirrored.** Reversing the cross yields a proper det +1 rotation.
* **Auto-fit height** (`r_data/models.cpp`): `bodyScale = clamp((smoothedEye − headroom) / neckH)`, where `neckH` is the measured bind model-Z of the `bip_neck` joint (63.64, parsed straight from the IQM). The neck-stump anchors at HMD eye height, feet on the floor — and the IK stays **scale-invariant**, because the matrix inverse undoes the same `bodyScale`.
* **Procedural-bone upload.** `marine_novr.iqm` is a 152-joint rig with **zero baked frames**; the IK writes a per-joint TRS into `proceduralPose` every tic and `CalculateBonesIQM` (`common/models/models_iqm.cpp`) applies it inside a `swapYZ` sandwich — the exact swap the IK inverse mirrors. Upload gate: `modelsareattachments` in the modeldef; `+DECOUPLEDANIMATIONS` alone *fails* on a 0-animation IQM.
* **The model.** A headless DOOM Eternal Slayer rip — neck stump, no head (you don't render your own face in first person), legs removed — 7 surfaces, each with its own per-part texture.

Net: your marine's arms reach exactly where your hands are because the solve is the **algebraic inverse of the draw**, not an approximation of it.

---

## Universal 3D Weapon Model framework (any mod, VR or flatscreen)

DXR replaces 2D weapon sprites with 3D IQM/MD3 models without the model knowing anything about the weapon driving it. A native interception in `DPSprite::SetState` re-syncs the attached model's animation state to the weapon's matching state-label anchor (Ready / Fire / Reload / …):

* **Mod-agnostic** — load any weapon/gameplay mod; its logic, sounds, damage, and effects drive; DXR supplies the animated 3D shell, no per-mod patching.
* **Foreign-tic accurate** — sync keys off the weapon's own state-label anchors, fixing the bug where models froze on Ready during Fire/Reload.
* **Flatscreen too** — a rendering/state feature, not a VR feature; non-VR mods get correct 3D weapon animation.
* **Real frame maps** — every stock-weapon model was re-bound to actual classes with per-state frame tables decoded from each mesh, plus `BaseFrame` for `A_SetAnimation('Reload')`.
* **Ships with ~11 weapons** modeled, so a bare mod inherits models immediately.

---

## Keyword metadata engine (`KEYWORDS.json`)

Native data layer attaching behavior to actors/weapons by string token instead of code:

* **No recompile, no ZScript** — designers tune per-actor/weapon behavior in one JSON file; the native `KeywordDispatcher` resolves tokens at load.
* **Namespaced/typed** — `kickback`, `role`/`trait`, `anatomy` (blood/spark/oil color), `vulnerability` (multiplier + stun), `ballistics` (bullet-drop, air-resistance), per-weapon `mass` / `twohand_radius` / `parry_extent` / `parry_sound`.
* **Most-specific-match** — tokens layer (actor + action + tier), so `[imp + headshot + tier_3]` beats a generic default.
* **Feeds real systems** — directional kickback, projectile parry/deflect, dodgeable-hitscan tagging, grab opt-in (`flags:grabprop`), climbable-surface tagging — one source, many consumers.

---

## Physics-driven VR arsenal

* **XRWhip** — Verlet-rope bullwhip: supersonic crack, two-hand coupling, grapple-swing, entangle-yank; optional 21-bone procedural rig.
* **VRSword** — swing-tracked blade with per-tic broad+narrow-phase segment collision; deflects projectiles via native keyword parry; Steel / Lightsaber / Dragon's-Tooth data-swap.
* **ShieldSaw** — off-hand block / saw / returning-boomerang tool with a shootable+reflect shield actor.
* **IceHook** — melee pick + thrown embedding hook; picks bite any solid wall for velocity-driven climbing.
* **M79 + manual reload** — arcing/bouncy grenade launcher on a chamber-tracked reload mixin driving baked model frames; CVar-gated alt-fires across the conventional guns.
* **XR Gravity Path** — palm-out power painting SDF walkway tiles that re-solve the player's `GravityDir`.

---

## Movement, world & engine systems

* **Per-actor directional gravity** — `FallAndSink` rewritten to apply `GravityDir` even while grounded (ceiling-flip / wall-pull).
* **Native hardpoint holsters** — shoulder/hip weapon holsters + wrist ability mounts, draw/stow by grip proximity, drift-proof markers.
* **Grip arbiter + single-Vel-writer discipline** — closes double-write fling bugs between climb, whip-swing, and gloves.
* **VR timing/smoothing (35 Hz bridge)** — per-frame VR pose (90 Hz+) is filtered into stable 35 Hz gameplay values: a 4-sample hand-velocity buffer normalized by `/35`, and an exponential body-height smooth.
* **Crash-hardening** — FString-in-`memset` fixes across sector/line/mapthing/actor, null-deref guards, undeclared-CVAR fixes.

---

## Visual capabilities (shader / SDF pipeline)

The GITD "glow-in-the-dark" visual layer ships as an overriding `main.fp` from the **[Radiance Control Panel](https://github.com/presidentkoopa/RadianceControlPanel)** companion mod; the base engine renders plainly without it. Capability set:

* **Localized glow-spots** — per-surface neon pools on walls/floors/ceilings, streamed per frame.
* **~30 procedural in-world display shapes** — SDF digits/panels, gauges, oscilloscope, spectrum bars, shockwave rings, reticles, materialize skull — all math, no sprites.
* **Full-screen visual regimes** — System Shock, Tron, Blueprint, Thermal, Digital Noir, LSD hue-warp, Tetris; VR-safe via a world-space proximity mask, never screen-space warp near the face.
* **True-MSDF + single-channel SDF** — resolution-independent glyphs/art; per-actor `msdf_*` fields route content to the right path.
* **PS1 affine texture-warp** (in-core) — `noperspective` UV path for retro wobble.
* **Omni-fog modes + monster neon outlines** (in-core) — height mist / spectral rim / bit-crush / vortex fog, and stencil silhouette outlines through the StreamData UBO (with the std140 alignment fix that cured the black-world corruption).

*Authoring:* `tools/sdf_authoring/gif_to_sdf_atlas.py` converts animated GIFs into SDF sprite atlases (Pillow/numpy/scipy, no C++ toolchain).

---

## Custom Shader Workflow (no engine recompile)

1. Place `.fp` files in your PK3 (e.g. `shaders/biohazard_sdf.fp`). Material shaders must define **`ProcessTexel()`**, not `main()`.
2. Bind via `GLDEFS`:
   ```text
   HardwareShader Texture "BIOHAZ0" { Shader "shaders/biohazard_sdf.fp" }
   ```
3. Control from ZScript via standard actors and shader uniforms. GLSL compiles at runtime.

---

## Author without recompiling — the content stack

DXR's rule — native behavior, data/script content — means most of the game is authored without touching C++. The full modder surface, by effort:

**Edit a JSON (no tools):**
* `KEYWORDS.json` — behavior-by-token for any actor / weapon / surface (kickback, vulnerability, ballistics, parry, mass, two-hand radius, grab + climb tags). The master data layer.
* `vr_gestures.json` — VR gestures: body anchor + motion-verb + gate button → a `VR_GestureFired` ZScript hook. New gesture = one row.
* `vr_hardpoints.json` — body holster (shoulders / hips) + wrist ability-mount layout.
* `vr_climb_textures.json` — which surfaces **bare-hand** climb can grab (the ice picks and whip ignore it — they grab any solid surface).
* `doomxr_weapons.json` — weapon → 3D-model archetype mapping.
* `sdf_combos.json` — in-world SDF display definitions.

**Run a Python pipeline:**
* `tools/weapon_iqm_build/` — MD3 → IQM conversion with **geometry-derived two-hand grip hotspots** + validation, driven by `weapon_roster.json`.
* `tools/sdf_authoring/gif_to_sdf_atlas.py` — animated GIF → resolution-independent SDF atlas.

**Point-and-click HTML editors (in a browser):**
* `tools/sdf_authoring/sdf_combo_authoring.html` — author SDF combo displays visually.
* `tools/sdf_authoring/sdf_upgrade_authoring.html` — author upgrade cards visually.

**Drop-in, bind, run (no recompile):**
* Custom `.fp` shaders — place in a pk3, bind via `GLDEFS`, GLSL compiles at runtime (see below).

Net: weapons, monsters, surfaces, gestures, holsters, HUD / SDF displays, and whole visual regimes are all **content** — one native engine, authored in JSON, ZScript, small pipelines, and a browser.

## And when data isn't enough — forward native access

Modding DXR isn't a sandbox. Every VR subsystem is native C++ **exposed forward to ZScript** as a composable hook toolkit (~33 hooks + modder virtuals) — you reach straight into the engine's primitives and recombine them into *new* mechanics, with C++-level power and zero C++. The bullwhip is five hooks in a row (`GetHandVelocity` → render rope → `VR_SetWhipSwingLive` → `VR_TrySetHeldItem` → throw); swap two steps and the **same stack** is a grappling hook, lasso, fishing rod, or chain flail. The gesture engine works the same way — a fired gesture hands off to a `VR_GestureFired` virtual you override. Full catalog in **[VR & Input Interaction — native hook surface](#vr--input-interaction--native-hook-surface)** above.

So there are two access levels on one engine: **author in data** for content, **compose native hooks** for mechanics — and neither needs a recompile.

---

### Source Code & Licensing
Builds on the open-source foundations of **DoomXR** (iAmErmac), **QuestZDoom**, **UZDoom**, and **GZDoom**. Licensed under the **GPL v3**.
