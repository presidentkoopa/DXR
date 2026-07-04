![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DXR — Gravity Plate Update 

A fork of **DoomXR** (iAmErmac's QuestZDoom-based VR fork of GZDoom) rebuilt into a purpose-built VR light-gun / physical-melee game. Design rule throughout: **behavior lives in native C++ per-tic subsystems; ZScript is limited to data and thin override hooks.** Full technical accounting in [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

## Top 10 features

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

> [!WARNING]
> **Status: work-in-progress***

**Baseline vs. upstream DoomXR:** 439 files changed, +18,431 / −10,831 lines.

Yo some of this shit is native to the buiid I started from, but a shitload of this is new to DXR.
Just wait until I get portalstacking in here.
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

### Source Code & Licensing
Builds on the open-source foundations of **DoomXR** (iAmErmac), **QuestZDoom**, **UZDoom**, and **GZDoom**. Licensed under the **GPL v3**.
