![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DXR — an Untitled VR Light-Gun / Melee Game (Engine Overhaul)

> [!WARNING]
> **Status: work-in-progress, not yet headset-verified.**
> Almost everything below is implemented at the code level but has **not** been fully play-tested in a headset — the build currently **crashes on launch** due to an unresolved shader uniform-block (UBO) placement bug being worked on separately. Treat this as an active reconstruction, not a shippable release. A file-by-file accounting of every change lives in [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

## What this is

DXR forks **DoomXR** (iAmErmac's QuestZDoom-based VR fork of GZDoom) into a purpose-built VR light-gun / physical-melee game. The design rule throughout: **behavior lives in native C++ per-tic subsystems; ZScript is limited to data declaration and thin override hooks.** Baseline vs. upstream DoomXR: **439 files changed, +18,431 / −10,831 lines.**

---

## VR & Input Interaction — native hook surface

Every VR subsystem is native C++ exposed to the VM through `Actor` (and two `PlayerPawn` virtuals). The complete script-facing surface added by DXR:

**Metadata & render fields**
* `GravityDir` (vector3) — per-actor unit "down" vector; zero = stock −Z gravity.
* `GravityAnchor` (vector3) — world reference point the directional-gravity solve pulls along.
* `Keywords` (String) — comma/space-joined metadata token list, resolved against `KEYWORDS.json`.
* `msdf_color` / `msdf_enabled` / `msdf_glitch` — per-actor SDF tint, mode/shape-bit selector, and glitch amount fed to the SDF material shaders.

**Pose & analog input reads**
* `GetHandVelocity(hand)` → vector3 — smoothed controller velocity, metres→map-units remapped, for swing/flick thresholds.
* `GetHeadPos()` → vector3 — HMD center-eye world position (falls back to actor pos off-VR).
* `GetHeadAngles()` → vector3 — HMD yaw/pitch/roll from the hardware angles.
* `GetGripValue(hand)` → double — analog grip squeeze 0..1 (0 on click-only controllers).

**Procedural model / arm-IK**
* `SetModelUseProceduralPose(enable)` — switch this actor's IQM model from baked animation to script-driven bone TRS.
* `SetModelBonePose(boneIndex, tx,ty,tz, qx,qy,qz,qw)` — write one bone's model-local translation + quaternion (drives the physics whip's rig).
* `SetArmIKEnabled(enable)` — toggle the native two-bone shoulder/elbow IK solver that aims the body-avatar arms at the controllers.

**Hardpoints (holsters / wrist mounts)**
* `AssignHardpoint(anchor, actionType, hand, ox,oy,oz, radius, weaponClass, abilityName, cells)` → slotIndex — register a body or wrist mount point.
* `ClearHardpoint(slotIndex)` — unregister a mount.
* `IsHardpointNear(hand)` → slotIndex — which mount (if any) the hand is currently inside the trigger radius of.
* `GetHardpointStowed(slotIndex)` → Actor — the weapon holstered in a slot.
* `GetHardpointCount()` → int — number of registered mounts.
* `GetHardpointAnchorType(slotIndex)` → int — body vs. wrist anchor class.
* `GetHardpointWorldPos(slotIndex, forHand)` → vector3 — a mount's live world position, computed by the *same* native routine the trigger uses so a rendered marker can't drift from the real zone.
* `VR_HolsterHand(hand, slotIndex)` — force a draw/stow on a slot from script.

**Grip-intent arbiter** (one owner per hand, resolved once per tic before any consumer)
* `VR_GetGripOwner(physHand)` → int — which system currently owns a hand's grip.
* `VR_PhysicalHandForSlot(slot)` → int — resolve a weapon slot to the correct physical L/R controller (handedness-aware, byte-identical to the transform path).
* `VR_SetWhipSwingLive(bool)` — publish that a live whip pendulum swing owns pawn velocity this tic (climbing reads it and yields, guaranteeing a single Vel writer).
* `VR_SetWhipRopeAttached(physHand, bool)` — inform the arbiter a hand's whip rope is anchored.
* `GRIP_NONE / GRIP_CLIMB / GRIP_GLOVE / GRIP_WHIP / GRIP_HARDPOINT / GRIP_TWOHAND` — the six owner identities, priority-ordered.

**Held-item / throw pipeline**
* `VR_TrySetHeldItem(hand, item)` → bool — hand an actor into a hand's native held-item slot (e.g. whip yank-catch → throw).

**Weapon-model mapping**
* `GetVRWeaponArchetype(Class<Actor>)` → int (static) — look up the 3D-model archetype registered for a weapon class.

**Modder virtual dispatch (`PlayerPawn`)** — native events reach these via `IFVIRTUALPTRNAME`; must stay `virtual`.
* `VR_DoHolster(hand, slotIndex)` — invoked when a hand stows a weapon; default tears down that hand's PSprite. Override to customize.
* `VR_HardpointAbility(hand, slotIndex)` — invoked when a wrist ability slot fires; no-op extension point (override to launch a whip / grenade / gravity platform / etc.).

---

## Universal 3D Weapon Model framework (works with *any* mod, VR or flatscreen)

DXR replaces 2D weapon sprites with 3D IQM/MD3 models **without the model needing to know anything about the weapon driving it.** The core is a native interception in `DPSprite::SetState`: when ZScript advances a weapon's pspr state, the engine re-synchronizes the attached 3D model's animation state to the matching label anchor (Ready / Fire / Reload / …). This means:

* **Mod-agnostic.** Load an arbitrary gameplay/weapon mod on top; its weapons fire with **its** logic, sounds, damage, and effects, while DXR supplies the animated 3D shell — no per-mod patching.
* **Foreign-tic accurate.** The sync keys off the weapon's own state-label anchors instead of a debug string that never matched, fixing the bug where models froze on the Ready pose during Fire/AltFire/Reload.
* **Flatscreen too.** This is a rendering/state feature, not a VR feature — non-VR mods get correct 3D weapon animation on a normal monitor.
* **Real frame maps.** Every stock-weapon model block was re-bound from dead placeholder names to actual ZScript classes, with per-state frame tables decoded from each mesh (not guessed), plus `BaseFrame` registration for `A_SetAnimation('Reload')`.
* **Ships with a set.** ~11 weapons (pistol, shotgun, SSG, SMG, chaingun, rifle, revolver, rocket, BFG, plasma, chainsaw + flamethrower/incinerator) come modeled, so a bare mod inherits models immediately.

---

## Keyword metadata engine (`KEYWORDS.json`)

A native data layer that attaches behavior to actors/weapons by string token instead of code. Why it matters:

* **No recompile, no ZScript.** Designers tune per-actor and per-weapon behavior by editing one JSON file; the native `KeywordDispatcher` resolves tokens at load. Modders ship their own token sets.
* **Namespaced and typed.** Parsed namespaces include `kickback` (knockback tiers trivial→extreme), `role`/`trait`, `anatomy` (blood/spark/shatter/oil color), `vulnerability` (damage multiplier + stun), `ballistics` (bullet-drop, air-resistance), and per-weapon `mass` / `twohand_radius` / `parry_extent` / `parry_sound`.
* **Most-specific-match resolution.** Tokens layer (actor + action + tier), so `[imp + headshot + tier_3]` can trigger a monster-specific reaction while generic tokens supply defaults.
* **Drives real systems, not cosmetics.** The same table feeds directional kickback, projectile parry/deflect, dodgeable-hitscan tagging, grab opt-in (`flags:grabprop`), and climbable-surface tagging — one metadata source, many consumers.
* **Crash-hardened.** The `keywords` actor property is a comma-list, and the FString members are placement-new reconstructed after the engine's bulk `memset` (which otherwise null-clobbered them and crashed on boot / map load).

---

## Physics-driven VR arsenal

* **XRWhip** — 16-node Verlet-rope bullwhip: supersonic tip crack, two-hand coupling, grapple-swing (taut-line pendulum), and entangle-yank; optional 21-bone procedural IQM rig.
* **VRSword** — swing-tracked blade with per-tic broad+narrow-phase segment collision; deflects projectiles via the native keyword parry; Steel / Lightsaber / Dragon's-Tooth data-swap.
* **ShieldSaw** — off-hand block / saw / returning-boomerang tool with a shootable+reflect shield actor.
* **IceHook** — melee pick + thrown embedding hook; picks bite any solid wall for velocity-driven climbing.
* **M79 + manual reload** — arcing/bouncy grenade launcher on a chamber-tracked reload mixin driving baked model frames; CVar-gated alt-fires added across the conventional guns.
* **XR Gravity Path** — palm-out power painting discrete SDF walkway tiles that re-solve the player's `GravityDir` for wall/ceiling walking.

---

## Movement, world & engine systems

* **Per-actor directional gravity** — `FallAndSink` rewritten to apply `GravityDir` even while grounded (ceiling-flip / wall-pull).
* **Native hardpoint holsters** — shoulder/hip weapon holsters + wrist ability mounts, draw/stow by grip proximity, with billboard markers driven off the native positions.
* **Grip arbiter + single-Vel-writer discipline** — closes the double-write fling bugs between climb, whip-swing, and gloves.
* **Crash-hardening** — FString-in-`memset` fixes across sector/line/mapthing/actor, null-deref guards, undeclared-CVAR fixes.

---

## Visual capabilities (shader / SDF pipeline)

The GITD "glow-in-the-dark" visual layer is delivered as an overriding `main.fp` shipped by the **[Radiance Control Panel](https://github.com/presidentkoopa/RadianceControlPanel)** companion mod; the base engine renders plainly without it. The capability set:

* **Localized glow-spots** — up to `MAX_WALL_GLOW_SPOTS` per-surface neon pools on walls/floors/ceilings, packed color+radius+type streamed per frame.
* **~30 procedural in-world display shapes** — SDF digits/number panels, gauges, oscilloscope traces, spectrum bars, shockwave rings, corner-bracket reticles, a materialize skull, casings/shards — all math, no sprites.
* **Full-screen visual regimes** — selectable world restylings: System Shock vector-frame, Tron data-grid, Blueprint CAD, Thermal, Digital Noir, LSD hue-warp, Tetris voxel-stack; VR-safe via a world-space proximity mask (never screen-space warp near the face).
* **True-MSDF and single-channel SDF** — resolution-independent glyphs/art via `msdf_atlas.fp` (median-of-RGB) and alpha-distance SDF atlases; per-actor `msdf_*` fields route content to the right path.
* **PS1 affine texture-warp** (in-core) — `noperspective` UV path for retro texture wobble, toggled with no C++ plumbing.
* **Omni-fog modes + monster neon outlines** (in-core) — height mist / spectral rim / bit-crush / vortex fog, and stencil silhouette outlines fed through the StreamData UBO (with the std140 16-byte alignment fix that cured the black-world corruption).

*Authoring:* a `tools/sdf_authoring/gif_to_sdf_atlas.py` converter turns animated GIFs into SDF sprite atlases (Pillow/numpy/scipy, no C++ toolchain).

---

## Custom Shader Workflow (no engine recompile)

1. Place `.fp` files in your PK3 (e.g. `shaders/biohazard_sdf.fp`). Material shaders must define **`ProcessTexel()`**, not `main()`.
2. Bind via `GLDEFS`:
   ```text
   HardwareShader Texture "BIOHAZ0" { Shader "shaders/biohazard_sdf.fp" }
   ```
3. Control from ZScript via standard actors and shader uniforms. GLSL compiles at runtime for rapid iteration.

---

### Source Code & Licensing
Builds on the open-source foundations of **DoomXR** (iAmErmac), **QuestZDoom**, **UZDoom**, and **GZDoom**. Licensed under the **GPL v3**.
