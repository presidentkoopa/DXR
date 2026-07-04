# DXR vs. DoomXR — Definitive Change Reference

## Scope & Baseline

This document catalogs every material change between the pristine **DoomXR** engine
import and the current **DXR** fork HEAD.

| Fact | Value |
| --- | --- |
| Baseline commit | `92767dbf00` — "Initial backup of DoomXR engine source" |
| Comparison | pristine DoomXR import → current DXR HEAD |
| Files changed | 439 (291 added, 106 modified, 33 deleted, 9 renamed) |
| Line delta | **+18,431 / −10,831** |
| Lineage | GZDoom → **DoomXR** (QuestZDoom-based VR fork by iAmErmac) → **DXR** (this fork) |

DXR turns a general-purpose VR Doom engine into a purpose-built VR light-gun / melee
game: it adds a native first-person body avatar with arm IK, a full physics-driven VR
melee/grapple arsenal, per-actor directional gravity, a data-driven hardpoint holster
system, a central grip-ownership arbiter, and an expanded KEYWORDS.json metadata engine —
while **extracting** the inherited GITD/Radiance glow subsystem out of the core into a
standalone mod so the base engine renders plainly on its own.

---

## At-a-Glance: Subsystems

| Subsystem | Theme | Headline |
| --- | --- | --- |
| C++ engine: rendering / VR / models | VR interaction, engine capability | First-person body avatar + auto-fit, arm-IK render bridge, always-on dual hand models, in-world debug volumes, voxel culling, std140 UBO fix |
| C++ engine: playsim / gameplay | VR interaction, engine capability, bugfix | Directional gravity, hardpoint holsters, two-bone arm IK, grip arbiter, KEYWORDS.json engine, FString-memset crash fixes |
| ZScript: actors / weapons | Weapons, VR interaction | Whip, sword, shieldsaw, icehook, M79, gravity path; manual reload + alt-fire + VR-recoil overhaul; ~40 new native hooks |
| ZScript: radiance / ui / engine / effects | GITD refactor, bugfix | GITD/SDF ZScript extracted to mod; new holster markers + manual-reload mixin; correctness fixes |
| Shaders (.fp/.vp) | GITD refactor, engine capability | GITD cascade de-partied out of core main.fp; PS1 affine warp + gravity-path tile; ProcessTexel/Vulkan compile fixes |
| Config + models + assets | Weapons, config, assets | ~11 VR weapons wired (models + modeldef + CVARs + menus + PBR); null-deref fixes; GITD config carved out |
| Documentation | Docs | 31 design/audit dossiers (~7,235 lines) indexing planned + built features |

---

## 1. C++ Engine — Rendering / VR / Models

A native VR interaction/avatar layer bolted onto stock GZDoom rendering.

### 1.1 First-person VR body avatar ("OUR BODY") with auto-fit + decoupled facing
**What:** `HWSprite::Process` gains a `vr_show_body` cvar and an `IsVoxelCulled`/`vrBodyAvatar`
gate that lifts the stock first-person camera-actor cull (the two `fabs(vieworigin - ActorPos) < 2`
returns and the ceiling-portal return), so the local pawn's own IQM model draws at its own
position. `RenderModel` adds an `isVRBody` branch scaling only the local player model at its
feet, with `vr_body_scale` manual mode plus `vr_body_autofit` (default) reading
`r_viewpoint.CenterEyePos.Z`, smoothing it (0.03 lerp), and scaling the marine so its head sits
`vr_body_headroom` below the live HMD eye. Adds `vr_body_z` nudge and `vr_body_yaw` (default 90)
mesh-facing correction; decouples body yaw from HMD via `vr_body_facing_valid/_yaw`. Gates use
`(vr_mode!=0 || IsVR())` to work around `IsVR()` returning 0 in the render path.
**Why:** Player sees their own scaled, correctly-oriented body in first-person VR instead of
nothing; auto-fit matches any standing/seated height with no tuning.
**Files:** `hw_sprites.cpp`, `r_data/models.cpp` — ~2 files, ~120 lines + new cvars.

### 1.2 Arm-IK render/playsim bridge: joint introspection + procedural pose + published scale
**What:** `model.h` adds 4 virtual no-op joint accessors (`GetJointCount`/`GetJointBindTRS`/
`GetJointParent`/`FindJointByName`) so `VR_UpdateArmIK` can call them on any `FModel*` without
RTTI; `models_iqm.cpp` implements them against the private `Joints[]` bind pose (raw local TRS,
no swapYZ). `ProcessModelFrame` lets `modelData->useProceduralPose` + `proceduralPose` override
baked animation (feeds `CalculateBonesIQM`). Publishes `g_xr_vrBodyRenderScale` (render → playsim)
so `VR_UpdateArmIK` divides the world hand target by the exact render scale. Adds `vr_ik_*` and
`vr_hardpoint_*` cvars.
**Why:** Enables a native VR arm-IK/hardpoint subsystem and ZScript procedural bone posing (e.g.
the physics whip) coordinated with the avatar's render scale.
**Files:** `model.h`, `model_iqm.h`, `models_iqm.cpp`, `r_data/models.cpp`, `hw_vrmodes.cpp` — 5 files, ~110 lines.

### 1.3 Always-on dual VR hand models at both controllers
**What:** `DrawPlayerSprites` VR-hands block rewritten: forces both hand indices (0/1), resolves
`VRHandModel` state frames (Spawn/Grip/Climb/Point from `vr_hand_state`), borrows any valid
psprite as render context, skips a hand already fist-swapped, and calls `RenderHUDModel` with a
forced hand. `RenderHUDModel` gains a `forceHand` param so a hand can be positioned at a specific
controller via `GetWeaponTransform(hand)`. Fixes the DECOUPLEDANIMATIONS/MODELSAREATTACHMENTS
interaction that made `vhand.iqm` upload zero bones.
**Why:** VR hands are visible on both controllers even with an empty/psprite-less hand; previously
hands only showed when punching.
**Files:** `hw_weapon.cpp`, `r_data/models.cpp`, `models.h` — 3 files, ~150 lines rewritten.

### 1.4 In-world VR debug volumes (grab cones + interaction spheres)
**What:** `hw_weapon.cpp` adds batched tube-geometry helpers (`XR_FlushTubes` emitting a whole
primitive in one triangle-list draw — down from ~190 per-segment draws to ~8) plus
`DrawDebugWireCone/WireSphere` and solid additive-translucent variants. `DrawXRDebugCones` renders
grab-glove reach cones per hand, proximity spheres for catch/climb/two-hand, and the gravity-path
cast cone. New `vr_grab_debug_sphere_solid/cone_solid` cvars. Runs from `DrawLaserSightWorld`.
**Why:** Makes otherwise-invisible VR interaction volumes visible in-headset for tuning, replacing
a particle debug approach that never renders in VR stereo.
**Files:** `hw_weapon.cpp`, `hw_vrmodes.cpp` — ~300 new lines.

### 1.5 Distance-based voxel culling that reverts to flat sprite
**What:** `hw_sprites.cpp` adds `vr_voxel_cull_items/monsters` cvars and `IsVoxelCulled()`
(per-category distance, 0=uncapped, classified by `MF3_ISMONSTER`). `FindModelFrameRaw`/
`FindModelFrame` gain `forceVoxel/cullVoxel` params. Hard-excludes `PlayerPawn` from ever falling
through to a voxel replacement, protecting the native VR player IQM body from third-party voxel packs.
**Why:** Voxel monster/item packs can be distance-tuned for performance without hiding the actor,
and a loaded voxel pack can't steal the player-body render.
**Files:** `hw_sprites.cpp`, `r_data/models.cpp`, `models.h` — 3 files, ~40 lines + 2 cvars.

### 1.6 Analog grip (squeeze value) OpenXR input path
**What:** `vk_openxrdevice.cpp/.h` add `xrLeft/RightGripValueAction` (FLOAT_INPUT) bound to
squeeze value on Touch and Index profiles, a `GetActionFloat` helper, per-hand `xrGripValue[2]`
cache, and `GetGripValue(hand)`. `hw_vrmodes.h` adds virtual `VRMode::GetGripValue` returning
analog squeeze 0..1 (0 on click-only controllers).
**Why:** Exposes continuous grip strength to the playsim (used by the grip-intent arbiter's analog
commit/release thresholds).
**Files:** `vk_openxrdevice.cpp/.h`, `hw_vrmodes.h` — 3 files, ~40 lines.

### 1.7 Central grip-intent arbiter cvars + handedness-correct slot→controller mapping
**What:** `hw_vrmodes.cpp/.h` add the `VR_ResolveGripOwner` cvar surface (`vr_grip_arbiter` master
+ hysteresis, `vr_grip_commit_arm/release` analog rails, `vr_whip_grip_pump`, `vr_climb_z_slack`
reserved) and a shared `VR_PhysicalHandForSlot(slot)` mapping weapon-slot to physical L/R
controller via `vr_control_scheme`, byte-identical to `GetWeaponTransform` (fixes left-hander bug).
**Why:** One authority for which hand/consumer owns a grip, one handedness conversion.
**Files:** `hw_vrmodes.cpp/.h` — ~40 lines + 6 cvars + 1 exported function.

### 1.8 Two-hand grip capsule + retuned grab/climb radii + easy-grab scaling
**What:** Retunes/adds cvars: `vr_twohand_radius` 8→2 plus new `vr_twohand_length` 30 (forward
capsule down the barrel); `vr_grab_max_dist` 500→90 (gloves short-range vs. long whip);
`vr_climb_radius` 32→10; new `vr_easy_grab_props/scale` (0.5) exposing the formerly-hardcoded
half-mass throw/pull assist; new `vr_physics_powerups` exclusion mirroring `vr_physics_keys`.
**Why:** Tighter VR grip/grab/climb feel, assist/physics behaviors as user options.
**Files:** `hw_vrmodes.cpp` — ~8 cvars changed/added.

### 1.9 Weapon-parry: swing-gate + class-key lookup fix + profile out-param
**What:** `VR_CheckWeaponParry` lowercases the class name and prefixes `class:` (fixing
KeywordDispatcher key mismatch); adds `vr_parry_require_swing/threshold` gate averaging the
4-sample `vr_hand_vel_buffer`; adds `outProfile` out-param so callers read the resolved
`KeywordProfile` (per-weapon `parry_sound`) without a second lookup.
**Why:** Parry only triggers on real swing when configured, the profile key matches, callers apply
per-weapon overrides.
**Files:** `hw_vrmodes.cpp/.h` — ~40 lines, signature change.

### 1.10 Monster neon outlines + GITD-fog/regime UBO with std140 fix + per-scene cache
**What:** `StreamData` inserts `padding4/5/6` before `u_MSDFColor` to force the vec4 onto a 16B
boundary matching GLSL std140 (prevents a 12-byte shift corrupting all following GITD fog/regime
uniforms → black world + garbled glyphs); appends monster-neon-outline uniforms. Adds
`FNeonOutlineState`/`FVisualRegimeState` caches; `Reset` copies from them instead of hard-zeroing.
`StartScene` populates both caches once per scene/eye via `FindCVar`. `vk_shader.cpp` mirrors pads
+ fields; `hw_walls.cpp` skips `gflags&1` (air billboard) glow spots on walls.
**Why:** Monster silhouette outlines + live GITD-fog/regime control without a per-draw cvar hash
lookup; fixes a std140 misalignment corrupting the world render.
**Files:** `hw_renderstate.h`, `hw_drawinfo.cpp`, `vk_shader.cpp`, `hw_walls.cpp` — 4 files, ~200 lines.

### 1.11 Data-haze postprocess real depth linearization
**What:** `DataHazeUniforms` gains `LinearizeDepthA/B` + `InverseDepthRangeA/B` (same constants as
the SSAO LinearDepth pass), replacing the old `pow(rawDepth,8.0)` heuristic.
**Why:** Data-haze uses true map-unit depth so it's visible in close-quarters corridors instead of
collapsing to ~0 except at long range.
**Files:** `hw_postprocess.cpp/.h` — 2 files, ~20 lines.

### 1.12 Reusable world-space VR UI draw primitives
**What:** `hw_vrwheel.cpp/.h` expose `VRWorldUI_DrawQuad`/`DrawDisc` as public wrappers over the
wheel's internal `DrawWorldQuad/Disc`, so other native VR-UI renderers (e.g. `VRHardpointGrid_Draw`)
can reuse the vertex-buffer/render-state boilerplate.
**Files:** `hw_vrwheel.cpp/.h` — 2 files, ~20 lines.

### 1.13 Throttled VR diagnostic logging (temporary)
**What:** Per-process throttled `Printf` probes across the VR render path: `[VRBODY]`,
`[VRHANDS]`/`[VRHANDDRAW]`, `[VRHUDHAND]`, `[VRIK_RENDER]`/`[VRIK_RENDER2]`. Each capped ~12–24
lines, marked "remove once confirmed."
**Files:** `hw_sprites.cpp`, `hw_weapon.cpp`, `models.cpp`.

---

## 2. C++ Engine — Playsim / Gameplay / Scripting

A large native VR-interaction layer on stock GZDoom playsim, plus a cluster of crash fixes for
FString members clobbered by the engine's blanket memsets.

### 2.1 Per-actor directional gravity (GravityDir / GravityAnchor)
**What:** Added `DVector3 GravityDir` (unit 'down', zero = normal −Z) and `GravityAnchor` to
`AActor`, serialized in `Serialize`. `FallAndSink` rewritten: when `GravityDir` non-zero and
`MF_NOGRAVITY` clear, applies `Vel += GravityDir*grav` and returns, replacing native −Z fall/sink
even while grounded. `Tick`'s gravity gate also fires when `!GravityDir.isZero()`. An earlier
'virtual rest plane' clamp in `P_ZMovement` was removed. Exposed via `DEFINE_FIELD`.
**Why:** Enables gravity-cube/gravity-path traversal (ceiling-flip, wall-pull). Fixes the prior
core bug where GravityDir was set but never read for a grounded player. True wall-standing still
needs a plane-native collision pass (documented remaining work).
**Files:** `actor.h`, `p_mobj.cpp`, `vmthunks_actors.cpp`.

### 2.2 Native VR hardpoint / holster mount system
**What:** New `vr_hardpoint.h` defines `EHardpointAnchor` (body/wrist), `EHardpointAction`
(holster/ability), `FHardpointSlot`, `VR_MAX_HARDPOINTS=16`, `VR_ResolveHardpointWorldPos()`.
`FVRConfig` gains a static Hardpoints table (4 body weapon holsters: shoulders/hips + 3 wrist
ability mounts), overridable from `vr_hardpoints.json`. `player_t` gains `VRHardpointRuntime[]`
(GC-safe `TObjPtr stowedWeapon`), grip latch, lazy-init flag. `VR_Init/UpdateHardpoints` do
per-tic proximity + grip rising-edge draw/holster; DRAW brings up the stowed weapon, STOW
dispatches `PlayerPawn.VR_DoHolster`, ability slots dispatch `VR_HardpointAbility`. Gated to console
player for netcode. `PropagateMark` marks stowed weapons so GC doesn't collect them.
**Why:** Real physical holsters (shoulders/hips) + wrist-gauntlet ability mounts you draw/stow by
gripping near your body — a greenfield holster system. One-line modder API; all math native.
**Files:** `vr_hardpoint.h`, `vr_config.cpp/.h`, `d_player.h`, `p_user.cpp`, `vmthunks_actors.cpp`.

### 2.3 Hardpoint ZScript API thunks
**What:** `vmthunks_actors.cpp` adds `AssignHardpoint`, `ClearHardpoint`, `IsHardpointNear`,
`GetHardpointStowed`, `GetHardpointCount`, `GetHardpointAnchorType`, `GetHardpointWorldPos`,
`VR_HolsterHand` + factored native `VR_ResolveHardpointWorldPos` shared with the marker renderer.
**Why:** Exposes native hardpoint state to modders/UI so holster zones and visible markers stay in
sync with the mechanic.
**Files:** `vmthunks_actors.cpp`, `vr_hardpoint.h`.

### 2.4 Native two-bone arm IK + procedural IQM bone posing
**What:** `DActorModelData` gains `TArray<TRS> proceduralPose` + `useProceduralPose`, fed into
`CalculateBones`. `vmthunks_actors.cpp` adds `SetModelUseProceduralPose`/`SetModelBonePose` +
`XR_EnsureModelData`. `p_user.cpp` adds a full native two-bone shoulder/elbow IK solver
(`IK_MatTranslation/Rotation`, `QuatFromTo`, `WorldToModelLocal`, `IK_SolveTwoBoneArm`
law-of-cosines with reach clamp + pole vector) and `VR_UpdateArmIK` solving into `vr_ik_pose`
(rotation-only, model-local Y-up with swapYZ relabel, body-scale/yaw un-projection).
`p_actionfunctions.cpp` adds `VR_EnsureAvatarModelDataAndGetModel`. `SetArmIKEnabled` gates it.
**Why:** Drives a first-person 'our body' marine whose arms track the real controllers via IK — the
user's stated #1 priority. Still carries in-headset debug probes; not fully verified in headset.
**Files:** `p_user.cpp`, `actor.h`, `vmthunks_actors.cpp`, `p_actionfunctions.cpp`, `d_player.h`.

### 2.5 Decoupled body-avatar facing yaw
**What:** `player_t` gains `vr_body_facing_yaw/valid` (transient). `P_PlayerThink` holds rendered
body yaw steady within a 50° dead-zone while the head turns, then catches up — pawn `Angles.Yaw`
untouched (still HMD-slaved for gameplay + IK targets); only the body model render reads the
decoupled yaw.
**Why:** Fixes 'body spins with my head / no neck.'
**Files:** `d_player.h`, `p_user.cpp`.

### 2.6 Central grip-intent arbiter
**What:** New `EGripOwner` enum (NONE/CLIMB/GLOVE/WHIP/HARDPOINT/TWOHAND) + `VR_ResolveGripOwner`
run once per tic in `P_PlayerThink` before all grip consumers. Fills a canonical grip read, an
analog Schmitt-trigger commit gate (`vr_grip_commit_arm/release`), and publishes one owner per
physical hand by priority CLIMB>WHIP>GLOVE>HARDPOINT into new `player_t` fields. Master toggle
`vr_grip_arbiter`. Thunks `VR_GetGripOwner`, `VR_PhysicalHandForSlot`, `VR_SetWhipRopeAttached`,
`GetGripValue`. v1 conservative: only whip rope-pump obeys the verdict; climb/gloves keep legacy reads.
**Why:** Prevents multiple VR systems from fighting over the same grip; single decision site +
analog-squeeze commit gating.
**Files:** `p_user.cpp`, `d_player.h`, `vmthunks_actors.cpp`.

### 2.7 Whip-swing vs climb fling fix (single Vel writer)
**What:** `vr_whip_swing_live` published by the whip via `VR_SetWhipSwingLive` while a live pendulum
swing owns the pawn. `VR_UpdateClimbing` reads `P_VRWhipSwingActive` and yields: when the swing is
live, climb writes neither pawn Vel nor `MF_NOGRAVITY` — at most one Vel writer per tic.
**Why:** Closes the climb-vs-swing double-Vel-write fling and gravity-strip jerk.
**Files:** `p_user.cpp`, `d_player.h`, `vmthunks_actors.cpp`.

### 2.8 Ice Hook pick-climb (any solid wall)
**What:** `VR_UpdateClimbing` detects an IceHook in the gripping hand and marks ANY one-sided or
`ML_BLOCKING` two-sided line climbable regardless of KEYWORDS climbable-texture tagging, reusing
the existing velocity-driven climb pipeline + fling safety.
**Why:** Ice-climb fantasy: picks bite any solid wall (liquids excluded as floor planes).
**Files:** `p_user.cpp`.

### 2.9 KEYWORDS.json metadata engine expansion
**What:** `keyword_dispatcher` parses new/fixed namespaces: `kickback` (+ `ResolveKeywordKickback`
and PostBeginPlay applying `projectileKickback`), `role`/`trait`, `anatomy` (blood_color/sparks/
shatter/oil_color), `vulnerability` (multiplier/stun_duration), `ballistics` (bullet_drop/
air_resistance — previously never parsed), and the `weapons` namespace re-keyed to lowercase
`class:x` tokens with `parry_extent` + per-weapon `parry_sound`. `KeywordProfile` grew matching
fields. `ResolveMetadata` propagates bullet_drop/air_resistance.
**Why:** Data-driven per-actor/per-weapon behavior without hardcoding; fixes namespaces that never
matched the real tokens.
**Files:** `keyword_dispatcher.cpp/.h`, `p_mobj.cpp`.

### 2.10 Keywords actor property → list format + boot-crash fix
**What:** `DEFINE_PROPERTY(keywords)` changed from single-string `'S'` to comma-list `'L'`,
space-joining tokens. Combined with `info.cpp` `InitializeDefaults` placement-new reconstructing
`AActor::Keywords` and `vr_metadata` (a `KeywordProfile`) after the parent-copy memcpy/memset that
nulls their FString Chars pointers.
**Why:** ZScript can declare multiple keyword tokens per actor; fixes a confirmed no-text boot crash.
**Files:** `thingdef_properties.cpp`, `info.cpp`.

### 2.11 FString-in-memset crash fixes for map structures
**What:** `maploader.cpp` and `udmf.cpp` add placement-new reconstruction of `Keywords` FString
members on `sector_t`, `line_t`, `FMapThing` after the blanket memsets that zero their Chars
pointer, covering `LoadSectors/Things/Things2/LineDefs/2` and UDMF `ParseLinedef/ParseSector`.
**Why:** Same crash class as the FMapThing fix — FStrings in bulk-memset structs caused −4 write /
−12 read access violations.
**Files:** `maploader.cpp`, `udmf.cpp`.

### 2.12 VR weapon parry system expansion
**What:** `DoDamageMobj` scales a reflected projectile's velocity by `vr_parry_reflect_speed_mult`
(kinematic) and plays a per-weapon `parry_sound` from the resolved profile (falling back to
`vr/parry`) via updated `VR_CheckWeaponParry`. New CVARs `vr_parry_require_swing`,
`vr_parry_swing_threshold`, `vr_parry_reflect_speed_mult`.
**Why:** Skill-based swing-required parrying, faster reflected shots, per-weapon parry sounds
without touching projectile damage objects.
**Files:** `p_interaction.cpp`, `p_actionfunctions.cpp`.

### 2.13 Locational damage moved to ZScript (display-only native block)
**What:** The native locational-damage block no longer multiplies damage (head/leg mults removed);
it only spawns the HEADSHOT!/LEGSHOT! floating MSDF text. Multipliers moved to the ZScript
`VRLocationalArbiter` to avoid double-applying.
**Why:** Prevents double-application now that ZScript owns the math with torso handling and per-hand
combo tracking.
**Files:** `p_interaction.cpp`.

### 2.14 Gravity-glove grabbing improvements + grabprop opt-in
**What:** `VR_UpdateGravityGloves` gains a `flags:grabprop` Keywords opt-in so non-pickup/
non-missile actors (e.g. ExplosiveBarrel) are grabbable without making every monster grabbable.
`vr_easy_grab_props/scale` scales effective throw mass. Grabbed/caught items get `target=player`
for kill credit. Default `vr_catch_radius` 24u→3u. Invisible-in-VR particle debug drawing removed
in favor of `bForceShowVoxel` + the render-thread geometry path.
**Why:** Barrels become grabbable/throwable, catches feel tight, kill credit correct, dead particle
debug gone.
**Files:** `p_user.cpp`, `actor.h`.

### 2.15 Capsule two-hand stabilization test
**What:** `VR_CalculateTwoHanding` replaced the sphere-at-grip distance test with a capsule test
down the weapon barrel axis (project off-hand onto barrel forward, clamp to
`[grip, grip+vr_twohand_length]`, perpendicular tolerance).
**Why:** Off-hand engages when near the weapon's axis anywhere along its length — fewer accidental/
failed two-hand grips.
**Files:** `p_user.cpp`.

### 2.16 Runtime voxel-display override (bForceShowVoxel)
**What:** `AActor` gains `bool bForceShowVoxel` so an actor renders via its VOXELDEF voxel even when
`r_drawvoxels` is off; set on grab candidates, whip-caught props, held items.
**Files:** `actor.h`, `p_user.cpp`, `vmthunks_actors.cpp`.

### 2.17 New VR head/hand/held-item ZScript bindings
**What:** `p_actionfunctions.cpp` adds `GetHandVelocity` (smoothed buffer with remap + m→units
scale), `GetHeadPos` (CenterEyePos/Pos fallback), `GetHeadAngles` (HWAngles), and `VR_TrySetHeldItem`
(hand an actor into a hand's held-item slot for whip yank-catch). `vmthunks_actors.cpp` exports
`msdf_enabled/glitch/color`. A removed duplicate PlayerPawn-level `GetHandVelocity` is documented.
**Why:** Modders get local VR head pose, correctly-scaled hand velocity, and a way to hand yanked
props into the native held-item throw pipeline.
**Files:** `p_actionfunctions.cpp`, `vmthunks_actors.cpp`, `p_pspr.cpp`.

### 2.18 3D weapon-model state-sync fix
**What:** `DPSprite::SetState` replaced the broken `StaticGetStateName->FindState(FName)` lookup
(which returned a debug `Class.index` string that never matched a label, so every tic fell through
to Ready) with a scan of the weapon's own state-label anchors, re-syncing the 3D archetype state
only on a genuine label anchor.
**Why:** Fixes 3D weapon models being permanently frozen on the Ready pose during Fire/AltFire/
Reload for every weapon using the VR archetype hook.
**Files:** `p_pspr.cpp`.

### 2.19 Powerup blast-physics exclusion
**What:** `P_RadiusAttack` adds a `vr_physics_powerups` gate so Powerup-derived pickups
(soulsphere/megasphere/berserk/invuln) are excluded from blast-radius physics, mirroring Keys.
**Files:** `p_map.cpp`.

### 2.20 MSDF damage-counter null-guard crash fix
**What:** `RecordDamage` bails if `SpawnText` returns null (e.g. missing MSDF font atlas) before
dereferencing `TextThinker->MSDFColor`.
**Why:** Prevents a hard crash on the first damage event when the Arcade MSDF font fails to load.
**Files:** `vr_msdf_text.cpp`.

### 2.21 Minor fixes: menu thunk class, property-spam removal
**What:** `GetVRWeaponArchetype` re-scoped from `Menu` to `DMenu`; `zcc_compile_doom.cpp` removed a
per-property `DBG_PROP` Printf logging every actor property on every boot.
**Files:** `vr_weapon.cpp`, `zcc_compile_doom.cpp`.

---

## 3. ZScript — Actors / Weapons

A full suite of physics-driven VR melee/grapple weapons, throwables, a gravity-path traversal
power, and manual-reload / alt-fire / VR-recoil overhauls, riding on ~40 new native VR hooks.

### 3.1 XRWhip — physics VR bullwhip (Verlet rope + grapple + entangle-yank)
**What:** 1096-line `vr_whip.zs`: a 16-node mass-tapered Verlet rope hanging from the tracked hand
(`WHIP_GRAV/DAMP/ITERS`), cracking when the light tip goes supersonic (`WHIP_MACH1=333 u/tic`).
Fire injects a directed lash impulse; two-handing (off-hand within 48u of handle) couples off-hand
velocity into the chain. AltFire LineTraces a grapple limited to `ActiveWhip.Reach`: geometry hit →
`GM_ATTACHED` unified tension state (self-gravity + taut-line distance constraint = Indy pendulum
swing, reel-in on Fire, rope-length pumping on off-hand grip); monster hit → `GM_YANK`
entangle-yank (pull = `handSpeed*100/targetMass`, tumbles enemy, lands it in front for melee).
Rendered via `level.AddGlowPanel` neon billboards (no sprite assets); optional Tier-2 rigged IQM
driven per-tic via `SetModelUseProceduralPose/BonePose` over 21 bones. Pinball safeguards clamp
knockback. Publishes swing state to the grip arbiter.
**Why:** Swing/grapple/entangle traversal+combat weapon (Indiana Jones + Castlevania IV +
Bulletstorm feel); arbiter coordination stops whip and climb both writing pawn Vel.
**Files:** `vr_whip.zs`, `vr_whip_profile.zs`.

### 3.2 WhipProfile data-driven cosmetic/elemental identity
**What:** 205-line `vr_whip_profile.zs`: `WhipProfile` base + `Whip_Leather/Ember/Tesla` defining
`WhipModel`, `Reach` (300u), element/cosmetic fields. `XRWhip.BindWhip()` instantiates by CVar index.
**Why:** Whip look/element swappable as pure data, mirroring the sword's BladeProfile split.
**Files:** `vr_whip_profile.zs`.

### 3.3 VRSword — physical VR melee blade
**What:** 242-line `vr_sword.zs`: detects swings via `GetHandVelocity(hand)`, builds a collision
segment from AttackPos/OffhandPos + angle/pitch, runs a per-tic `BlockThingsIterator` broad-phase +
closest-point-on-segment narrow-phase, tracks `HitThisSwing`. `BindBlade()` swaps `BladeProfile` by
CVar. Provides `FireFlatscreen()` `LineAttack` fallback when `!player.PlayInVR` and gates the
vanilla face-target snap behind `vanilla_melee_attack`. Bullet/missile deflection comes free from
the `class:vrsword` keyword → KEYWORDS.json parry profile.
**Why:** First-class VR sword you physically swing; parries projectiles via native keywords; behaves
like a normal Doom melee weapon on flatscreen.
**Files:** `vr_sword.zs`, `vr_blade_profile.zs`.

### 3.4 BladeProfile + blade carrier actors
**What:** 163-line `vr_blade_profile.zs`: `BladeProfile` base + `Blade_Steel/Lightsaber/DragonsTooth`
+ carrier actors `VRSwordBladeSteel/Plasma/Nano`.
**Why:** Data-driven cosmetic/combat swap for the VR sword.
**Files:** `vr_blade_profile.zs`.

### 3.5 ShieldSaw — off-hand triple-mode block/saw/boomerang tool
**What:** 727-line `weaponshieldsaw.zs` (ported from the RLVR prototype to DoomXR bOffhandWeapon/
ALF_ISOFFHAND). Three modes: Block (`ProtectorShield` actor rides the hand, +SHOOTABLE/+AIMREFLECT,
spawns `DeflectShockwave` rings), Saw (circular melee ring), Throw (auto-aiming bouncing boomerang
that sticks briefly then homes back). Motion-throw gated on `GetHandVelocity` flick threshold.
`class:shieldsaw` keyword (avoids 'fist' substring) ties into parry/twohand.
**Why:** Defensive+offensive off-hand VR gadget; opt-in via `vr_start_with_shieldsaw`.
**Files:** `weaponshieldsaw.zs`.

### 3.6 IceHook — dual-purpose VR pick/thrown hook
**What:** 300-line `icehook.zs` (baked from standalone mod v1): Fire = melee pick (`A_CustomPunch`),
AltFire = throws a hook projectile that embeds where it hits (`IceHookStuck` anchor). Real
`icehook.iqm` + dedicated ICHK placeholder sprite (recolored fist copy). Given via `Player.StartItem`.
**Why:** Throwable ice-pick tool/weapon (with a future climb/grapple-pull layer anchored on
IceHookStuck); auto-given as a real default class.
**Files:** `icehook.zs`.

### 3.7 M79 grenade launcher
**What:** 235-line `weaponm79.zs` using `XR_ManualReload`; fires a tumbling 40mm grenade that arcs
under gravity, spins end-over-end (`nade.md3` via USEACTORPITCH) and detonates on impact; alt-fire
lobs a bouncy grenade. Shares slot 5 + RocketAmmo with the Rocket Launcher; flash → TNT1.
**Why:** New arcing-vs-bouncy grenade launcher from Skulltag M79 assets.
**Files:** `weaponm79.zs`, `doomplayer.zs`.

### 3.8 XR Gravity Path — off-hand traversal power
**What:** 698-line `vr_gravity_path.zs`: palm-out (`OffhandRoll`) sweep draws a walkway of discrete
rectangular SDF tiles (`XR_GravityPathNode` actors, grow animation, lock-flash). Entering a tile's
capture box lerps the player's gravity to that surface via native `GravityDir`+`GravityAnchor`
(wall/ceiling walking); leaving/grappling restores gravity. Tunables in `xr_gp_*` CVars.
**Why:** Prey/Inception-style gravity-walkway traversal built on the new native GravityDir core.
**Files:** `vr_gravity_path.zs`.

### 3.9 Shared VR thrown-item behaviours
**What:** 196-line `vr_thrown.zs`: `XRThrownSpin` (roll scaled by mass + throw speed),
`DeflectShockwave` (expanding shader ring via glow-billboard wgType 14), `ThrownChainsaw` (smart
multi-target boomerang that weaves through locked targets, cuts each, homes back).
**Files:** `vr_thrown.zs`.

### 3.10 Chainsaw boomerang-throw AltFire with target-locking
**What:** `weaponchainsaw.zs` adds `lockList/sawInFlight` + `UpdateChainsawLocks()` (hold AltFire to
acquire up to N in-cone monsters via FOV/CheckSight, drawing corner-bracket glow panels wgType 18);
`ThrowChainsaw()` launches a `ThrownChainsaw` carrying the queue. New lock CVars.
**Why:** Throwable multi-lock boomerang chainsaw; one saw out at a time.
**Files:** `weaponchainsaw.zs`.

### 3.11 Manual-reload chamber system on Pistol and M79
**What:** Both mix in `XR_ManualReload`: `XR_InitChamber`, `A_XR_CheckChamber` (auto-reload when
empty), `A_XR_TryFire` (dry-clicks when empty), `A_WeaponReady(WRF_ALLOWRELOAD)`, and a Reload state
driving the model's baked reload animation (Pistol PISR A-R, 18 frames), topping from reserve.
**Why:** VR-style ammo-chamber tracking + gesture/on-demand manual reloading on sidearms.
**Files:** `weaponpistol.zs`, `weaponm79.zs`.

### 3.12 Alt-fire modes added to conventional guns (CVar-gated)
**What:** New AltFire modes each guarded by a `vr_altfire_*` toggle (no-op when off): Pistol 3-round
burst, Rifle 3-round tight burst, Revolver 'fan the hammer' 3 rapid wide shots, SuperShotgun
single-barrel-fired-twice, PlasmaRifle alt-fire. Revolver/Rifle gained %o/%k obituaries.
**Why:** A second fire behavior per gun, selectable from the VR options menu.
**Files:** `weaponpistol.zs`, `weaponrifle.zs`, `weaponrevolver.zs`, `weaponssg.zs`, `weaponplasma.zs`.

### 3.13 VR muzzle-flash suppression + recoil normalization across the arsenal
**What:** Flash states across pistol/shotgun/ssg/smg/rifle/revolver/bfg/chaingun/plasma/rocket
switched from sprite frames to TNT1 (invisible) while keeping `A_Light1/2` muzzle light. Recoil
migrated from custom `A_VRRecoil` to stock `A_Recoil`; Flamethrower gained `A_Recoil(0.1)`. SMG fire
sound `weapons/smg`→`weapons/smgfire`. Several weapons added `A_DataSiphonEquip`/`A_CheckSpawnModel`;
plasma/rocket gained `ballistics:` keywords.
**Why:** VR-legible muzzle flashes (light only), unified recoil, wired model/equip hooks.
**Files:** `weaponshotgun.zs`, `weaponssg.zs`, `weaponsmg.zs`, `weaponbfg.zs`, `weaponchaingun.zs`, `weaponrlaunch.zs`.

### 3.14 Grenade weapon fixes + explosion polish
**What:** `weapongrenade.zs`: HandGrenade Select adds `A_DataSiphonEquip`, Spawn adds
`A_CheckSpawnModel`; `ThrownGrenade` uses `BounceSound` property; explosion adds an `AddGlowPanel`
neon flash + GBANG→EXP1 frames. Fixed `GrenadeHandler.NetworkProcess` signature
(NetworkEvent→ConsoleEvent). Disabled the broken RenderOverlay grenade-arc preview (play-scope
`LineTrace` from ui scope + a nonexistent `Screen.ProjectVector`).
**Why:** Fixes an invalid event signature and a scope-violating/nonexistent-API arc renderer.
**Files:** `weapongrenade.zs`.

### 3.15 Explosive barrel: VR-grabbable + throw-to-detonate
**What:** `doommisc.zs` ExplosiveBarrel: added `flags:grabprop` + `flags:throwable` keywords; Tick()
override detonates on contact when moving fast (`Vel > 10`), crediting the thrower via `target`.
Death layers the grenade fireball at 60% scale over the stock BEXP unless
`vr_barrel_vanilla_explosion`.
**Why:** Grab-and-throw barrels as impact bombs in VR; nicer explosion.
**Files:** `doommisc.zs`.

### 3.16 Incinerator optional ignite / ground-fire
**What:** `id24incinerator.zs`: opt-in `ignite` flag (`vr_incinerator_ignite`, off default) spawns
`IncineratorBurn` — a short-lived FLME ground fire dealing periodic Fire-type `A_Explode` area
damage for ~1.2s.
**Files:** `id24/id24incinerator.zs`.

### 3.17 Enemy hitscan-to-dodgeable-projectile option + kickback keyword tagging
**What:** `possessed.zs`: `A_VRHitscanOrDodgeable()` converts Zombieman/Shotgunguy/Chaingunguy
LineAttacks into a `VRDodgeableHitscan` straight-line projectile when `vr_enemy_hitscans` is off.
Across ~11 monster/projectile files, added `kickback:` keyword values (numeric or named
light/moderate/heavy/severe/extreme) tagging each attack's knockback.
**Why:** Optional VR-fair dodgeable fire + per-attack knockback tuning for the native kickback system.
**Files:** `possessed.zs`, `archvile.zs`, `bruiser.zs`, `cacodemon.zs`, `demon.zs`, `doomimp.zs`.

### 3.18 Actor.zs: ~40 new native VR engine hooks exposed to ZScript
**What:** Native fields `GravityDir/GravityAnchor` and `Keywords String` (renamed from
monsterKeywords, `msdf_color`→FVector3), plus ~35 methods: `GetHandVelocity`, `VR_TrySetHeldItem`,
`SetModelUseProceduralPose/BonePose`, `GetHeadPos/GetHeadAngles`, the full hardpoint mount system,
`GetGripValue`, `SetArmIKEnabled`, and the grip arbiter (`VR_SetWhipSwingLive/VR_GetGripOwner/
VR_PhysicalHandForSlot/VR_SetWhipRopeAttached` + GRIP_* consts).
**Why:** The engine-level substrate the new VR weapons/powers depend on.
**Files:** `actor.zs`.

### 3.19 PlayerPawn holster/ability virtual dispatch hooks
**What:** `player.zs` added virtuals dispatched via `IFVIRTUALPTRNAME`: `VR_DoHolster(hand,
slotIndex)` tears down the holstered hand's PSprite and nulls ReadyWeapon/OffhandWeapon;
`VR_HardpointAbility(hand, slotIndex)` is a no-op extension point (mods override to launch
whip/grenade/gravity-platform).
**Why:** Bridges native holster/hardpoint events into VM-only PSprite mutation; must stay virtual or
native `GetVirtualIndex` null-derefs.
**Files:** `player/player.zs`.

### 3.20 DoomPlayer loadout + VR testing rig updates
**What:** Player starts with VRSword + IceHook (no number-key slot); ShieldSaw added to slot 1, M79
to slot 5; XRWhip/ShieldSaw opt-in via WeaponReplacementHandler CVars. `VRTestingRig` now spawns
only on map `GRABMAP` (was MAP01) and spawns `HandGrenade` (fixed from nonexistent 'HandGrenades').
**Files:** `doomplayer.zs`, `shared/vr_testing.zs`.

---

## 4. ZScript — Radiance (GITD) / UI / Engine / Effects

The GITD/Radiance glow-FX and SDF/damage-counter ZScript was extracted to a standalone mod; the
retained engine ZScript gained VR holster markers, a manual-reload layer, and correctness fixes.

### 4.1 GITD / Radiance ZScript suite removed from core (moved to Radiance Control Panel mod)
**What:** Deleted 24 `radiance/*.zs` files (~8,000 lines) and their includes: the glow/dark/preset
engine (`gitd_glow.zs` 1018L, `gitd_dark.zs`, `gitd_presets.zs`, flatglow/bloom/shaderbridge), the
death-FX system (`gitd3_deathfx.zs` 1617L), combo/score UI, muzzle/brand/brass/buckshot FX, SDF
monster/junker scanners, and graveyard/GunBonsai `gy_*.zs` handlers. `libtooltipmenu`
Tooltips/TooltipOptionMenu KEPT (~29 non-GITD OptionMenu blocks depend on `TFLV_TooltipOptionMenu`).
**Why:** Pure consumers of native fields/sprites/shaders with no engine dependency; live in the mod
pk3 for iteration. Cross-pk3 class visibility means the mod's GITD_Options still resolves the
retained tooltip classes.
**Files:** `radiance/*.zs`, `zscript.txt`.

### 4.2 SDF / damage-counter UI ZScript removed from core (moved to Radiance mod)
**What:** Deleted `ui/vr_damage_counters.zs` (111L), `ui/vr_sdf_combos.zs` (118L),
`ui/vr_sdf_procedural.zs` (106L), `ui/sdf_gif_entity.zs` (67L). Native `msdf_enabled/color/glitch`
fields, `.fp` shaders, and gldefs bindings stayed in core.
**Why:** No engine dependency; the native SDF text plumbing remains.
**Files:** `ui/vr_damage_counters.zs`, `ui/vr_sdf_combos.zs`, `ui/vr_sdf_procedural.zs`, `ui/sdf_gif_entity.zs`.

### 4.3 VRBlackoutHandler removed; neon-outline feed now pure C++
**What:** Deleted `engine/vr_blackout.zs` (46L) which pushed blackout/radiance/neon CVars into
shader uniforms each WorldTick. Its body was dormant; the actual monster-neon-outline feed is now
handled entirely in C++ (`hw_drawinfo.cpp`).
**Files:** `engine/vr_blackout.zs`, `zscript.txt`.

### 4.4 VR hardpoint (holster/wrist) marker billboards — new engine feature
**What:** New `vr_hardpoint_markers.zs` (96L): `VRHardpointMarker` + handler spawn a
+FORCEXYBILLBOARD Add-blend glow sprite at every native hardpoint slot, reading geometry solely
through native queries (`GetHardpointCount/AnchorType/WorldPos`) so markers can't drift from the
real trigger. Wrist mounts render smaller than body holsters. Gated by `vr_hardpoint_markers_show`.
**Why:** Lets the VR player SEE where to reach to draw/stow a weapon or fire a wrist ability. Uses
billboard sprites because particles don't reach the VR stereo pass.
**Files:** `engine/vr_hardpoint_markers.zs`, `zscript.txt`.

### 4.5 XR_ManualReload mixin — chamber-gated VR manual reloading
**What:** New `vr_manual_reload.zs` (101L): mixin with `XRChamber/XRMagSize/XRReloading` state and
`XR_InitChamber`, `A_XR_CheckChamber`, `A_XR_TryFire` (chamber-gated + dry-click), `A_XR_StartReload`,
`A_XR_RefillChamber` (tops chamber from reserve near the end of the authored Reload animation).
Reserve ammo stays the only true resource; chamber is a sub-limit. `vr_manual_reload` default true;
OFF = vanilla.
**Why:** Per-weapon chamber counting so guns reload driven by the artist's baked MD3 frames, no new
motion authored.
**Files:** `engine/vr_manual_reload.zs`, `zscript.txt`.

### 4.6 Locational-damage arbiter rewritten to valid hit source + selectable crit sound
**What:** `vr_locational_damage.zs`: no longer reads the nonexistent `e.Thing.HitLocation`; derives
hit-Z from `e.Inflictor.Pos.Z` (same proxy the native system uses) and early-returns if no
inflictor. Fixed type errors. Added `vr_crit_sound` CVar (0=off, 1-4 select
`vr/critical_hit..4`).
**Why:** The original referenced a field that doesn't exist, so zone detection couldn't have worked;
now functional + crit-sound option.
**Files:** `engine/vr_locational_damage.zs`.

### 4.7 vr_weapon_helpers: drop broken A_VRRecoil, retune PlasmaBeam, fix API calls
**What:** Removed custom `A_VRRecoil` (mutated player pitch/angle directly), callers use native
`A_Recoil`. PlasmaBeam retuned to a fast thin beam (Speed 60→140) with LightBlue trail +
`AddGlowPanel` death flash. Fixed API mismatches: `SetSafeFlash 'i:'→'index:'`, `projectile.Damage=`
→`SetDamage()`, `A_FireBullets` called bare on StateProvider instead of invalid `player.mo.A_FireBullets`.
**Why:** Corrects calls that wouldn't compile/behave; plasma reads as a proper energy beam.
**Files:** `engine/vr_weapon_helpers.zs`.

### 4.8 Weapon replacement handler: M79 rocket swap + whip/shieldsaw starting kit
**What:** `vr_weapon_logic.zs`: `CheckReplacementEvent`→`ReplaceEvent`; added a RocketLauncher→M79
random replacement gated on `vr_weapon_m79_chance`; start-of-game GiveInventory of XRWhip
(`vr_start_with_whip`) and ShieldSaw (`vr_start_with_shieldsaw`).
**Files:** `engine/vr_weapon_logic.zs`.

### 4.9 zscript.txt manifest reorder + new-weapon registration
**What:** Reordered includes so helpers/manual-reload/hardpoint-markers and new weapons load after
Actor/StateProvider parse; registered `weaponm79, weaponshieldsaw, vr_thrown, vr_blade_profile,
vr_sword, vr_whip_profile, vr_whip, vr_gravity_path, icehook`. Removed Strife `weaponflamer.zs`
(case-insensitive class collision with the Doom FlameThrower).
**Files:** `zscript.txt`.

### 4.10 VRDeathHandler: reset fatal-glitch shader on level transition
**What:** Added a `WorldUnloaded` override force-clearing `deathSequenceActive/deathTimer` and
disabling the `fatal_exception` postprocess. Replaced `pmo.viewheight` (Actor) with
`players[consoleplayer].viewheight` (PlayerInfo).
**Why:** A map change mid-death-sequence previously left the glitch shader stuck on forever.
**Files:** `effects/vr_death_effects.zs`.

### 4.11 vr_rom_load: wall-clock scanline sweep fix (was permanent blackout)
**What:** Rewritten from WorldTick tick-accumulation to a UiTick + `MSTimeF()` wall-clock driver.
Activates only on `gamestate==GS_LEVEL`, computes scanline from elapsed seconds against per-fidelity
durations, finishes reliably.
**Why:** The old version paused while menus/title were up, leaving the scanline stuck and painting
the whole screen black-green — the ROM-load blackout bug.
**Files:** `ui/vr_rom_load.zs`.

### 4.12 VR weapon assignment menu: struct→class + native signature fix
**What:** `vr_weapon_menu.zs`: promoted a nested value `struct WeaponEntry` (illegal in Array by
value, used C++ `PClass`) to a top-level ui class holding `Class<Actor> cls`, allocated with
`new()`. `menu.zs` native `GetVRWeaponArchetype` signature `PClass`→`Class<Actor>`. Commented out
the archetype write-back (`Menu.SendConsoleCommand` doesn't exist in this fork).
**Why:** Makes the debug weapon-archetype scanner compile and display/cycle; write-back deferred.
**Files:** `ui/vr_weapon_menu.zs`, `engine/ui/menu/menu.zs`.

### 4.13 vr_voxel_assembly: PlayerInfo viewheight fix
**What:** VoxelParticle attraction target changed from `pmo.viewheight` to
`players[consoleplayer].viewheight` (viewheight is a PlayerInfo member, not Actor).
**Files:** `effects/vr_voxel_assembly.zs`.

---

## 5. Shaders (.fp / .vp)

The shader tree was largely "de-partied" — the ~1000-line GITD cascade pulled out of core, plus new
retro/gravity effects and a batch of compile-crash fixes.

### 5.1 PS1 affine texture-warp path (main.vp + main.fp + material funcs)
**What:** Added a second texcoord varying `vTexCoordAffine` at location 10 in `main.vp`, qualified
`noperspective` so it interpolates linearly in screen space; assigned the same value as `vTexCoord`.
`main.fp` declares the matching `noperspective in` and adds `GetAffineTexCoord()` returning the
affine coord when `uAffineWarp != 0` (uAffineWarp lives in the existing shared viewpoint UBO — no new
C++ plumbing). `func_normal/pbr/spec.fp` changed to `SetMaterialProps(material,
GetAffineTexCoord(vTexCoord.st))` so only the primary diffuse sample warps.
**Why:** Recreates the classic PS1 affine texture wobble on angled/large polygons — toggleable retro
regime.
**Files:** `main.vp`, `main.fp`, `func_normal.fp`, `func_pbr.fp`, `func_spec.fp`.

### 5.2 GITD neon/glow-spot/visual-regime cascade removed from core main.fp (de-partied)
**What:** Deleted ~1000 lines from `main.fp`: the whole wall/floor glow-spot cascade in
`getLightColor` (MAX_WALL_GLOW_SPOTS loop, ~30 procedural wgType shapes — 7-seg/SDF digits, air
panels, casings, shockwave rings, discs, smoke, corner brackets, oscilloscope, gauge, spectrum,
materialize skull, floor patterns), all the GITD neon-tube SDF helpers and ghost-stone `gy_sdf_*`,
and the full body of `applyVisualRegime` (9 full-screen regimes: System Shock, Tron grid, Blueprint,
Thermal, Digital Noir, LSD SDF-warp, Tetris voxel-stack). `applyVisualRegime` is now a passthrough
`return frag`. Only `gitd_hash/gitd_vnoise` kept (used by `applyOmniFog`).
**Why:** These moved to the Radiance Control Panel's `main.fp` override (loads last, wins); the core
engine now renders plainly when Radiance is absent — the "de-partied" baseline.
**Files:** `main.fp`.

### 5.3 Black-world fog bugfix — gate applyOmniFog on GITD fog mode
**What:** Replaced the unconditional `frag = applyOmniFog(frag, fogdist)` with: run `applyOmniFog`
only when `u_gitd_fog_mode > 0`; otherwise restore stock — plain `applyFog` only for coloured fog
(`uFogEnabled < 0`). Positive uFogEnabled is Doom light-diminishing whose uFogColor is black for
ordinary sectors, and the old code fogged everything toward black.
**Why:** Fixes the black-world render bug where ordinary sectors were fogged to black.
**Files:** `main.fp`.

### 5.4 Ripple/regime world-position rewritten to be Vulkan/SPIR-V legal
**What:** `applyVisualRegime` signature takes a `vec3 worldPos`. A new local `regimeWorldPos =
pixelpos.xyz` is declared ahead of the LEGACY_USER_SHADER branch so it's always in scope; the
reactive impact-ripple distortion writes into it instead of the dead `ripplePos` local and no longer
writes the read-only `pixelpos` input (which Vulkan/SPIR-V forbids).
**Why:** GL tolerated writing a shader input; Vulkan rejected it. Wires the ripple distortion through
a legal local so regimes sample the distorted position.
**Files:** `main.fp`.

### 5.5 monster_neon.fp converted from double-main() to ProcessTexel()
**What:** Rewrote `void main(){...FragColor=...}` to `vec4 ProcessTexel(){...return...}` (main.fp
already supplies main() for material shaders; a second main() produced a link error). Removed the
seven loose `uniform` declarations — they are StreamData fields resolved via #define aliases in the
shared prelude, so redeclaring them left them permanently unfed.
**Why:** Makes the blackout monster-neon-outline shader actually compile, link, and receive params.
**Files:** `monster_neon.fp`.

### 5.6 msdf_atlas.fp fixed — ProcessTexel() + defined screenPxRange
**What:** Converted to `ProcessTexel()`; added the previously-called-but-undefined `screenPxRange`
(canonical MSDF pixel-range using pxRange=2.0, textureSize, fwidth).
**Why:** Two latent compile errors (double-main + undeclared symbol) fixed.
**Files:** `msdf_atlas.fp`.

### 5.7 vr_damage_sdf.fp converted to ProcessTexel()
**What:** Changed to `ProcessTexel()`; added a comment warning never to write the literal strings
SetupMaterial/ProcessMaterial (the shader combiner does a naive substring scan and would skip
default material setup).
**Why:** Fixes the 'main already has a body' link error for the VR floating damage-number shader.
**Files:** `vr_damage_sdf.fp`.

### 5.8 vr_sdf_procedural.fp — ProcessTexel() + new gravity-path tile shape
**What:** Converted to `ProcessTexel()`; added an SDF branch keyed on `(hash & 512)` (Bit 9): a solid
flat rectangle inset from the tile's actor bounds so abutting tiles show a visible seam — a paved
walkway of discrete panels. The graveyard-marker branch became `else if`.
**Why:** Renders the XR gravity-path tiles as discrete seamed panels (physical connection, not a
blended ribbon).
**Files:** `vr_sdf_procedural.fp`.

### 5.9 data_haze.fp — true linear-depth volumetric march
**What:** Added `normalizeDepth()` using reflected `LinearizeDepthA/B` + `InverseDepthRangeA/B` to
convert raw depth to linear map-unit distance, replacing `pow(rawDepth,8.0)`. The 16-step ray-march
uses map-unit step sizes (maxRange=1024) and breaks when `currentDist` exceeds `linDist`.
**Why:** The old heuristic collapsed to ~0 for all but distant geometry; now haze accumulates with
distance in ordinary corridors.
**Files:** `pp/data_haze.fp`.

### 5.10 rom_load.fp — fixed undeclared ScreenSize crash
**What:** Replaced the boot-grid aspect term `120.0 * (ScreenSize.y / ScreenSize.x)` with a fixed
16:9 constant `120.0 * 0.5625`. `ScreenSize` is not provided to this PostProcess path and was an
undeclared identifier that hard-crashed the GLSL compile.
**Files:** `pp/rom_load.fp`.

### 5.11 Radiance bloomboost pre/post shaders deleted
**What:** Deleted `radiance/gitd_bloomboost_pre.fp` and `gitd_bloomboost_post.fp` (12-line
brightness/contrast/gamma passes), consistent with moving GITD effects out of the engine baseline.
**Files:** `radiance/gitd_bloomboost_pre.fp`, `radiance/gitd_bloomboost_post.fp`.

---

## 6. Config + Models + Assets

A pristine fork turned into a shippable VR arsenal: ~11 weapons + a body avatar fully wired (models +
modeldef frame maps + CVARs + menus + PBR/gldefs), dozens of null-deref/invisible-model fixes, and
the GITD config carved out.

### 6.1 First-person VR body avatar (marine_nohands.iqm)
**What:** New `Model DoomPlayer` binding `marine_nohands.iqm` (152-joint, 0-anim) + `marine_skin.png`,
using `modelsareattachments` (NOT DECOUPLEDANIMATIONS, which fails on 0-anim IQMs) so native arm IK
drives the arm bones each tic. Only living frames PLAY A-F mapped. New `marine/` dir (~4.4MB).
**Why:** An 'OUR BODY' first-person marine mirroring real controllers; no-hands variant avoids double
hands since `vhand.iqm` renders at the controllers.
**Files:** `modeldef.txt`, `models/marine/*`.

### 6.2 VR hand model render fix (modelsareattachments)
**What:** Added `modelsareattachments` to `Model VRHandModel`; `vhand.iqm` replaced/shrunk (378KB→193KB,
old kept as `.orig.bak`). Without the flag the fist-swap resolved a frame but uploaded no bones.
**Why:** VR hands were rendering invisibly on every weapon; the flag forces the 0-baked-frame rigged
IQM to upload its bind pose.
**Files:** `modeldef.txt`, `models/vhand.iqm`.

### 6.3 Universal 3D weapon shells re-bound to real actor classes + full frame animation
**What:** Every stock-weapon Model block renamed from dead `VR_*` names to actual ZScript classes
(Pistol, Shotgun, PlasmaRifle, SMG, Chaingun, RocketLauncher, BFG9000, SuperShotgun, Chainsaw, Rifle,
Revolver, Flamethrower, ID24Incinerator). Speculative sprite tables replaced with real per-state
frame maps decoded from each mesh's `.def`; `BaseFrame` added to register `A_SetAnimation('Reload')`;
Rifle/Revolver merged their firing-pose asset into Model 1; Pistol dir `brutalpistol/`→`pistol/`.
**Why:** The inherited blocks bound to nonexistent actor names so 3D models never showed / vanished
mid-fire.
**Files:** `modeldef.txt`, `models/weapons/pistol/*`.

### 6.4 XR Whip weapon assets + rigged IQM + build tool
**What:** New `xrwhip/` dir: `whip_rigged.iqm` (21-joint tapered leather chain), `XRWhipLeather.png`,
`whip_hero.png` (~5.8MB), and `build_whip.py` (761-line self-contained headless-Blender IQM builder
that also bakes the skin + hero render). `Model XRWhipRigged` registered (no FrameIndex yet — awaits
the procedural-bone patch).
**Files:** `models/weapons/xrwhip/*`, `modeldef.txt`.

### 6.5 XR Whip full CVAR + in-game menu exposure
**What:** ~20 new CVARs in CVARINFO (`vr_whip_profile`, `vr_whip_model=true`, crack/grapple/entangle
params, physics-audit safety clamps: `yank_pull_cap`, `yank_vel_ceiling`, `crack_knock_ceiling`,
`grapple_vel_ceiling`, `grapple_hit_cap/scale`). New `VRWhipOptions` menu + `WhipProfiles`
OptionValue. `vr_whip_model` was previously referenced with NO declaration — now declared + defaulted.
**Why:** First weapon with full in-menu tuning; exposes crack physics, grapple, and VR-comfort clamps.
**Files:** `CVARINFO`, `menudef.txt`.

### 6.6 Ice Hook weapon (baked-in from standalone mod)
**What:** New `icehook/` dir with `icehook.iqm` + full PBR set (skin/normal/metallic/roughness/ao).
`Model IceHook` bound to placeholder sprite ICHK A, scaled 0.2. `gldefs.txt` material entry attaching
PBR maps by name. New CVARs + `IceHookOptions` menu; prototype enabled/autogive CVars dropped
(StartItem is unconditional).
**Files:** `models/icehook/`, `modeldef.txt`, `gldefs.txt`, `CVARINFO`, `menudef.txt`.

### 6.7 VR Sword blades (3 swappable models) + parry-deflect data
**What:** New `vrsword/` dir: `sword_steel.iqm`, `saber_blade.iqm`, `dtooth_blade.iqm` + 6 skins.
`Model VRSword` (base/Steel) + per-class `VRSwordBladeSteel/Plasma/Nano` (each needs its own
FrameIndex VRSW A since `A_ChangeModel` redirects rather than bypasses the lookup) + an
`ID24CalamityBlade` reskin. New CVARs + a VRSword `parry_extent` (10/10/50) in KEYWORDS.json.
**Files:** `models/weapons/vrsword/`, `modeldef.txt`, `CVARINFO`, `KEYWORDS.json`.

### 6.8 Shield Saw weapon (ported from RLVR devbuild)
**What:** New `shieldsaw/` dir (~40 md3/png: shield, shieldsaw, shield_weapon, shield_saw + HD/normal/
metallic/roughness/ao/glow/brightmap). `Model ShieldSaw` (block-shield / active-saw) + `ThrownShieldSaw`
boomerang. New CVARs, `vr_start_with_shieldsaw`, chainsaw-boomerang lock CVARs. KEYWORDS.json ShieldSaw
`parry_extent` (12/12/4).
**Files:** `models/weapons/hud/shieldsaw/`, `modeldef.txt`, `CVARINFO`, `KEYWORDS.json`.

### 6.9 M79 grenade launcher + grenade weapon rework
**What:** New `m79/` dir (M79.md3 ~1.9MB + PBR maps). `Model M79` (GLAN ready / GLAF fire / GLR1 A-Z
baked reload), `M79Grenade` + `M79BounceGrenade` (nade.md3 USEACTORPITCH/ROLL tumble). HandGrenades
block renamed HandGrenade, remapped GRHO/GRTH→real JHND/JGRN sprites; ThrownGrenade split out; the
JGRN spawn fix cured a `numframes==0` bug silently corrupting ~1-in-5 rocket-ammo pickups into Unknown
props. New CVAR `vr_weapon_m79_chance` + menu slider.
**Files:** `models/weapons/hud/m79/`, `modeldef.txt`, `CVARINFO`, `menudef.txt`.

### 6.10 Thrown chainsaw boomerang model
**What:** New `Model ThrownChainsaw` reusing Chainsaw.md3 with USEACTORROLL/PITCH + NoInterpolation so
its Tick() spin renders; world-space. Paired with `vr_chainsaw_lock_max/range/cone/throw_dmg`.
**Files:** `modeldef.txt`, `CVARINFO`.

### 6.11 ammo_hand HUD reload-model set
**What:** New `hud/ammo_hand/` dir (~28 files): `ammo_hand.md3` + per-weapon magazine/clip/pod meshes
(mag_pistol/chaingun/plasma, pod_bfg/heat/rocket, shot_shell, flame_can) + albedo textures.
**Why:** Physical clip/magazine models for the gesture-driven manual-reload system.
**Files:** `models/weapons/hud/ammo_hand/`.

### 6.12 Weapon sound bank (~50 new OGG/WAV)
**What:** ~50 new files: barrel/explosion (dsbarex1-7, gbang1-8), flamethrower (dsflame, flamstop,
hf_burn*), grenade FSM, plasma (plcharge/plcool/plfire), revolver, m16shoot, smgfire, shield-saw
(ssawdraw/loop, shbounc/shdehit/shldhit/shwhoosh), VR sword swing/hit (vrsw_swing/hite/hitf/hith).
**Files:** `sounds/`.

### 6.13 New effect + weapon sprites
**What:** Barrel/explosion frames (EXP1A-N, EXPLA-H), flame patch (FLMEA-N), fire FX (FRFXA-P), M79
reload/aim frames (GLAF/GLAN/GLAP/GLR1 A-Z), 18 tiny PISR pistol-reload placeholders, ICHKA0
(byte-recolored fist), SIGLA0.
**Files:** `sprites/`.

### 6.14 Explosive barrel voxel + fancy explosion CVAR
**What:** `voxeldef.txt` bar1a/bar1b entries (AngleOffset 270) wiring barrel voxels to the custom
ExplosiveBarrel (works while held/thrown/whip-yanked). New CVAR `vr_barrel_vanilla_explosion` (default
off = grenade-style fireball) + menu toggle.
**Files:** `voxeldef.txt`, `CVARINFO`, `menudef.txt`.

### 6.15 Postprocess shader binding fixes (rom_load / fatal_exception)
**What:** In `gldefs.txt`, the two custom PostProcess shaders retargeted from invalid custom targets
to the valid `screen` target, given explicit Name fields, forced to GLSL 330, with their ZScript-driven
uniforms (`scanline_pos`, `u_FatalStrength`) explicitly declared — without which the `.fp` referenced
undeclared identifiers and HARD-CRASHED on new-game load / player death.
**Files:** `gldefs.txt`.

### 6.16 GITD/Radiance glow subsystem extracted to a separate mod
**What:** CVARINFO deleted ~150 `gitd_*/ddz_*/hf_glow_*/gy_*` CVARs; `menudef.txt` removed ~15 GITD
OptionMenu blocks; `gldefs.txt` moved BloomBoostPre/Post HardwareShaders out (brightmaps kept).
`vr_blackout_mode` removed.
**Why:** All glow-in-the-dark content moves to the Radiance Control Panel mod so the base engine's
default rendering is untouched without it.
**Files:** `CVARINFO`, `menudef.txt`, `gldefs.txt`.

### 6.17 Null-deref / undeclared-CVAR crash fixes
**What:** Declared CVARs read via unchecked `GetCVar().GetInt()/GetBool()`: `vr_visual_fidelity`
(flamethrower/rocket/voxel/rom-load), `sv_wallcheck` (voxel auto-rotate gate), `vr_ballistic_drop`
(menu toggle). Comments document which look-alike CVARs are native C++ and must NOT be redeclared.
**Why:** Prevents hard crashes the instant the flamethrower/rocket fired or a map loaded; makes the
bullet-drop toggle live.
**Files:** `CVARINFO`.

### 6.18 New gameplay/combat CVARs + menus
**What:** CVARINFO adds `vr_crit_sound`, `vr_manual_reload=true`, `vr_enemy_hitscans=true`,
`vr_hardpoint_markers_show`, `vr_incinerator_ignite`, `vr_whip_catch_damage`, retuned `vr_regime_*`/
`gitd_fog_*`, and the XR Gravity Path suite (`xr_gp_*` ~18 CVARs) with `XRGravityPathOptions`. menudef
adds VR Weapon Options, `VRBodyOptions`, `RV_Options` (Reikall's Voxels), a Debug: Give block, and
tooltip text across many menus.
**Files:** `CVARINFO`, `menudef.txt`.

### 6.19 KEYWORDS.json extended
**What:** Added a `kickback` namespace (trivial→extreme, 160..1350), renamed mass entries' `mass_max`
→`mass`, added ShieldSaw + VRSword entries (recoil/twohand_radius/parry_extent). Pretty-printed.
**Files:** `KEYWORDS.json`.

### 6.20 GIF-to-SDF atlas authoring tool
**What:** New `tools/sdf_authoring/gif_to_sdf_atlas.py` (156 lines): converts an animated GIF into a
full-color SDF sprite atlas (Valve-2007-style alpha distance-transform, RGB=color, A=SDF) + JSON
layout via Pillow/numpy/scipy, no C++ toolchain.
**Files:** `tools/sdf_authoring/gif_to_sdf_atlas.py`.

### 6.21 MSVC Release PDB emission
**What:** `CMakeLists.txt` adds an MSVC block emitting `/Zi` + `/DEBUG /OPT:REF /OPT:ICF` for Release
(debug info only, optimizations unchanged) so crash minidumps can be symbolized.
**Files:** `CMakeLists.txt`.

### 6.22 Docs: README rebrand + multi-session lane rules
**What:** README rebranded from 'DoomXR 2.0 The Wired' to 'UntitledVRLightGunGame', de-TRON-ified,
expanded weapon list. New `SESSION_LANES.md` documents the shader-lane vs non-shader-lane file
ownership split, the E:\DOOM_FRESH-canonical / C:-stale-mirror warning, and the one-build-at-a-time rule.
**Files:** `README.md`, `SESSION_LANES.md`.

---

## 7. Documentation (Design Docs Added)

The Documentation folder gained 31 design/audit dossiers (~7,235 lines, all additions) indexing DXR's
planned and built VR-engine features.

| Doc cluster | Files | Substance |
| --- | --- | --- |
| Gravity journey index + devlog | `00_GRAVITY_JOURNEY_READING_ORDER.md`, `GRAVITY_ENGINE_JOURNEY.md` | 12-doc reading guide + one-page arc; frames three engine "walls" (scalar gravity, non-rotating portals, scalar floorz); marks designed vs built vs compiled |
| Gravity-cube theory + autopsy | `GRAVITY_CUBE_THEORY.md`, `GRAVITY_PLAN_AUTOPSY.md` | Proves gravity is scalar in the lineage; specs the DVector3 GravityDir keystone; red-team ratifies the scoped one-function version that shipped |
| XR gravity-path power + ribbon + handoff | `XR_GRAVITY_PATH_POWER.md`, `XR_SDF_GRAVITY_RIBBON.md`, `XR_GRAVITY_HANDOFF.md` | Palm-out gravity-walkway power (→ vr_gravity_path.zs); SDF capsule + ribbon render mode bit 512; full session handoff (compiled clean exit 0, 2026-07-03; wall-standing deferred) |
| Live-spinning portal war (5 docs) | `PORTAL_STACKING_ROTATING_CUBES_PLAN.md`, `LIVE_SPINNING_PORTAL_GET_US_THERE.md`, `PORTAL_WAR_TEAM_VELOCITY.md`, `PORTAL_WAR_TEAM_BEDROCK.md`, `PORTAL_WAR_VERDICT.md` | INTERACTIVE portal on a rotating polyobject is `bHasPortals==1` (not gated by the ==2 rotation veto) → spins with zero C++; verdict ships the cheap version now, prices native seamless rotation at 14 days |
| Sphere battlefields | `SPHERE_BATTLEFIELDS.md` | Inside-sphere (~20 lines C++, two flat arenas render each other as inverted sky) + outside-sphere planetoid (zero C++, rotate-the-world illusion); kills the earlier rolled-SkyViewpoint idea |
| XR debug visualizers | `XR_DEBUG_VISUALIZERS.md` | In-headset debug shapes + toggles; documents the "particles invisible in VR" trap and the billboard-sprite fix |
| Physics whip design + master plan | `DoomXR_Physics_Whip.md`, `DoomXR_Whip_MASTER_PLAN.md` | Living design (v0.9) + phased build status table: Verlet rope/crack/lash/two-hand/grapple, rigged IQM, contextual yank, entangle, pinball safeguards, menu, Keywords kickback — all BUILT after a 2-round adversarial physics audit; not build-verified |
| Whip entangle/yank report + IQM rigging spec | `DoomXR_Whip_Entangle_Yank_Engine_Feature_Report.md`, `DoomXR_Whip_IQM_Rigging_Patch_Spec.md` | Bulletstorm-pull physics on existing Keywords/Mass/Climbing; corrects the "ZScript can't write IQM bones" dead-end, identifies the CalculateBonesIQM override seam + SetModelBonePose thunk |
| Sword slice dossier (4 docs) | `DXR_SWORD_SLICE_DOSSIER/0-3` | Exec summary + slice architecture (monsters are flat billboards → every cut is a static model-dismember-swap) + VR sword design + read-only shader-lane map |
| VR sword hand-velocity spec (SUPERSEDED) | `DoomXR_VRSword_HandVelocity_Patch_Spec.md` | Record of a mistake-and-fix: `Actor.GetHandVelocity` already existed; the correct call is `owner.GetHandVelocity(hand)` |
| Engine-level VR weapon handling + hand ruleset | `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`, `VR_WEAPON_HAND_RULESET.md` | Mandates two-hand aim + manual reload as NATIVE per-tic subsystems; source-of-truth contract for grab/equip/throw/catch/dual-wield (two never-talking tracking systems: physics-held vs equipped) |
| VR holster system plan | `DoomXR_Holster_System_Plan.md` | Greenfield reach-to-shoulder draw/stow; grounds it in the inert inherited `holster_slot` tag; active path is OpenXR not OpenVR |
| HF Neon Arcade plan | `HF_NEON_ARCADE_PLAN.md` | VR looter-shooter arcade loop; flags `MAX_WALL_GLOW_SPOTS=16` as self-imposed (Vulkan guaranteed-minimum, fixable) |
| Shader tweaks + main.fp feature map | `DoomXR_Shader_Tweaks_Proposal.md`, `GITD_MAIN_FP_SHADER_FEATURE_MAP.md` | Finishes the dangling ripple feature; 2066-line fragment-shader inventory for newcomers |
| Full engine capability audit | `DoomXR_Capability_Audit_FULL.txt` | 1161-line adversarial audit of 45 claims across 13 clusters — final tally 13 working / 17 partial / 11 declared-unwired / 4 absent; adversary overturned 9 |
| Status manifest / MSDF-as-actor | `status.txt` | North-star feature vision + MSDF-as-Actor architecture (shader-trick → AActor/StreamData for Vulkan compliance); notes the project currently crashes on launch due to shader-block placement |

---

## Cross-Cutting Themes

- **VR-first, flatscreen-safe.** Every physical weapon (whip/sword/shieldsaw) carries a
  button-triggered fallback (`FireFlatscreen`/`LineAttack`) and gates auto-face-target on
  `vanilla_melee_attack`, so the arsenal still works without a headset.
- **Native subsystem, ZScript one-liner.** The architecture standard is native per-tic subsystems
  (gravity, IK, hardpoints, grip arbiter, two-hand, parry, kickback) with ZScript limited to data
  declaration — codified in `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`.
- **Single-writer discipline.** The grip arbiter + whip-swing-live flag exist specifically to
  guarantee at most one writer per pawn `Vel` per tic, closing double-write fling bugs.
- **Particles don't reach VR stereo.** A recurring gotcha: debug cones/markers/UI must be real
  geometry or billboard sprite actors, never `P_SpawnParticle`.
- **Crash-hardening the inherited base.** A whole class of fixes address FString members clobbered by
  the engine's blanket memsets (placement-new in info.cpp/maploader/udmf) and null-deref reads of
  undeclared CVARs and missing font atlases.
- **De-partying.** The GITD/Radiance glow FX (ZScript, shaders, CVARs, menus) were extracted into a
  standalone Radiance Control Panel mod so the core renders plainly on its own.

---

## 8. VR Timing & Motion Smoothing — the 35 Hz bridge

Doom's game logic runs at a fixed **35 tics/sec**, but VR head/hand pose is sampled **per-frame on the
render thread** (90 Hz+). That mismatch produces jittery, noisy tracking if fed straight into gameplay.
DXR adds smoothing/normalization filters that turn the fast, noisy per-frame VR signal into stable
values the 35 Hz tick can consume. (The underlying "render motion smoothly *between* tics"
interpolation itself is inherited from GZDoom/QuestZDoom, not added here.)

### 8.1 Hand-velocity rolling buffer + tic-rate normalization
**What:** `player_t` carries a 4-sample rolling buffer `vr_hand_vel_buffer[hand][4]`, filled every tic
by `VR_UpdateGravityGloves` (`p_user.cpp`). `Actor.GetHandVelocity(hand)` averages the 4 samples,
remaps map space `(X,Z,Y)`, and scales by `vr_scale_meters_to_units / 35.0` — the `/35.0` converting
metres/sec into map-units **per tic**.
**Why:** raw per-frame controller velocity is noisy; a 4-sample average normalized to the 35 Hz tick
gives one stable number that every swing/flick/throw threshold reads (whip crack, sword swing,
ShieldSaw motion-throw, glove flick-throw). Without it, swing detection would trigger on tracking noise.
**Files:** `p_user.cpp`, `p_actionfunctions.cpp`, `d_player.h`.

### 8.2 Body-avatar height auto-fit exponential smoothing
**What:** `RenderModel` (`models.cpp`) smooths the live HMD eye-height with
`smoothedEye += (eyeAboveFeet - smoothedEye) * 0.03;` (an exponential lerp toward target each frame)
before deriving `bodyScale`.
**Why:** the avatar is scaled to your real standing height, but reading it smoothed stops the model
scale from pumping/jittering with per-frame head-bob. Code comment: "heavily smoothed, so no sync is
needed."
**Files:** `r_data/models.cpp`.

> Related timing note: the old README's "Dynamic Time Scaling" refers to a *separate* mechanism —
> matching a 3D weapon model's animation playback to the tic-duration of the active 2D weapon state
> (see §6.3 / the universal 3D-weapon framework), not to VR pose smoothing.

---

## 9. Native Hook Capabilities & Roadmap (current use → potential)

The value of the ~33-hook native surface (§2, §3.18) is that the hooks are **composable primitives** —
most "what's next" is recombining primitives already shipped, not new C++. What each group powers today
and unlocks next:

### 9.1 Pose & analog input reads
- **`GetHandVelocity`** — *Now:* whip crack (supersonic tip), sword swing gate, ShieldSaw/glove
  motion-throw, catch timing. *Next:* velocity-scaled damage curves, gesture recognition
  (chop/thrust/slash from the vector), "must actually swing it" enforcement, deflection timing windows,
  motion-charged abilities.
- **`GetHeadPos` / `GetHeadAngles`** — *Now:* body-avatar facing/IK targeting, head-relative render.
  *Next:* lean-to-peek cover, enemies targeting your real head, duck/dodge as real movement, gaze-to-
  highlight interaction, head-aim secondary mode, velocity-driven comfort vignette.
- **`GetGripValue`** — *Now:* the arbiter's analog commit/release Schmitt gate. *Next:* squeeze-force
  mechanics — heavier props need a firmer grip, chargeable/crush weapons, chainsaw throttle,
  white-knuckle climbing where grip strength = hold security.

### 9.2 Metadata & render fields
- **`GravityDir` / `GravityAnchor`** — *Now:* XR Gravity Path (wall/ceiling walking). *Next:* gravity-
  cube puzzles, gravity wells/black-hole hazards, magnetic boots, props/ragdolls falling to a flipped
  surface, folding "Inception" levels, per-enemy gravity (throw a monster off the ceiling).
- **`Keywords` (as a live field)** — *Now:* static per-actor tagging. *Next:* runtime re-tagging — an
  enemy that becomes `flammable` after an oil splash, difficulty rewriting vulnerability tokens live,
  wet-floor `climbable:false` state.
- **`msdf_color/enabled/glitch`** — *Now:* floating damage numbers, gravity-path tiles, SDF sigils.
  *Next:* sprite-less SDF monsters, wrist-HUD holograms, glitch-driven materialize/dissolve deaths,
  per-actor HP-state color shifts.

### 9.3 Procedural model / arm-IK
- **`SetModelUseProceduralPose` / `SetModelBonePose`** — *Now:* the XRWhip's 21-bone rope rig follows
  the Verlet sim per tic. *Next:* any script-driven rig — chain/flail, tentacles, a deforming rope
  ladder, procedural SDF-monster animation, a two-hand-tracked bow, cloth/banner sim, a held prop the
  arm visibly grips.
- **`SetArmIKEnabled`** — *Now:* body-avatar arms reach the controllers. *Next:* correct elbow bend on
  two-handed poses, visible reach when climbing/grabbing, IK feet, companion NPCs whose arms track aim.

### 9.4 Hardpoints (8 fns)
- *Now:* shoulder/hip weapon holsters + wrist ability mounts, reach-to-draw/stow, drift-proof markers
  (positions read from the same native routine the trigger uses). *Next:* full physical loadout (back
  quiver, belt grenades, forearm shield), body-relative inventory/health, physical reload pouches, gear-
  is-where-it-hangs loadout menus, co-op weapon hand-off via a shared slot.

### 9.5 Grip-intent arbiter (`VR_GetGripOwner` / `VR_PhysicalHandForSlot` / `VR_SetWhipSwingLive` / `VR_SetWhipRopeAttached` / `GRIP_*`)
- *Now:* one owner per hand; kills the whip-swing-vs-climb double-Vel-write fling; handedness-correct
  slot→controller. *Next:* the coordination substrate for **every** future grip mechanic — grappling
  hook, two-handed bow, rope-ladder climb, akimbo dual-wield, steering wheel/lever — each registered in
  the priority order instead of fighting existing consumers. `VR_PhysicalHandForSlot` makes every new
  mechanic left-hander-correct for free.

### 9.6 Held-item / throw (`VR_TrySetHeldItem`)
- *Now:* whip yank-catch lands an entangled enemy in your hand to throw. *Next:* catch-and-throw-back
  projectiles, disarm-and-steal enemy weapons, in-hand returning boomerang, juggling/combo mechanics,
  co-op item hand-off, general telekinetic grab.

### 9.7 Weapon-model mapping (`GetVRWeaponArchetype`)
- *Now:* the archetype scanner / universal-3D-model binding. *Next:* auto-map an unknown mod's weapons
  to the nearest archetype, a remap UI, per-mod model packs — the key to scaling "load any mod, get 3D
  models."

### 9.8 Modder virtual dispatch (`VR_DoHolster` / `VR_HardpointAbility`)
- *Now:* default holster teardown; ability slot is a no-op stub. *Next:* the sanctioned, C++-free
  extension seam — override `VR_HardpointAbility` to make a wrist slot launch a grappling hook, cast a
  spell, deploy a turret, or trigger a special.

### 9.9 Why this compounds
None of these is impressive alone; the leverage is composition. The whip already chains
`GetHandVelocity` (crack) → `SetModelBonePose` (rope render) → `VR_SetWhipSwingLive` (arbiter) →
`VR_TrySetHeldItem` (yank-catch) → throw. The **same stack recombined** is a grappling hook, fishing
rod, lasso, chain weapon, or rope bridge. DXR shipped a VR **interaction toolkit**, not just a weapon
list — the hooks are the primitives.

> **Verification caveat:** this section describes the *designed* capability of the hooks as they exist
> in source. The build is not yet headset-verified (known launch crash), so treat every "Next" as
> unlocked-on-paper until each hook is confirmed live in a headset.
