<!-- Generated 2026-07-04 by a 20-agent code-grounded swarm over E:/DoomXR-work/DOOM_FRESH. Every file:line was read + adversarially verified. -->

# DoomXR: What the Host Can Do That the Guest Cannot

## The Guest and the Host

ZScript is a guest. It is loaded once, its class table frozen at parse time, and it is clocked exactly once per 35Hz game tic inside a sandboxed VM that owns no memory, no OpenXR handle, no bone matrix, and no frame lifecycle. Everything it knows about your hands arrives as pre-cooked scalars that the host chose to hand it, a tic late, already collapsed to a single point.

C++ is the host. It owns the class registry (`PClass::CreateDerivedClass`), the render/present path (`xrWaitFrame` â†’ `xrLocateViews` â†’ `xrEndFrame`), the OpenXR action set and its `XrSpaceVelocity`, the `AttackPos`/`AttackDir` bridge that the fire-decision path consumes, and the IQM bone buffer (`DActorModelData::proceduralPose`) that the model renderer uploads to the GPU. The host runs at 90â€“120Hz on the render thread and can see `predictedDisplayTime` â€” the exact photon at which the frame will be seen.

Every sandbox wall is a door in C++. And in VR specifically, the highest-value doors are exactly the ones that hurt: the seam between *what the runtime knows at photon-time* and *what the 35Hz playsim commits a tic later* is where held objects swim behind your wrist, where fast swings tunnel through demons, where haptics arrive after the visual, and where aim originates from your last-tic pose. DoomXR has already walked through several of these doors â€” it writes `AttackPos`/`weaponangles` from a render-latched matrix (`vk_openxrdevice.cpp:3781`), runs native arm IK into `vr_ik_pose`, and fires ~30 gameplay haptic events natively. This document catalogs the walls, what already exists behind each, the seam, and the VR features each escape designs â€” grounded strictly in the verified recon, honest about what is shipped, what is dark-by-default, and what is a stub.

---

## The Six Walls

### Wall 1 â€” The Sim Clock (35Hz vs render rate)

**What it is.** The ZScript VM has exactly one entry point: `P_PlayerThink`, once per 35Hz tic (~28.5ms). It cannot subdivide its own tic, cannot run inside the frame lifecycle between `xrWaitFrame` and `xrEndFrame`, and cannot observe `predictedDisplayTime`. Everything time-sensitive in VR â€” pose, velocity, contact â€” lives on the other side of this wall at render rate.

**What EXISTS today.**
- Hands are located **once** at `SetUp` against a *stale* `predictedDisplayTime`: `xrLocateSpace(..., xrFrameState.predictedDisplayTime, ...)` at `vk_openxrdevice.cpp:3271`, called before this frame's `xrWaitFrame` refreshes it at `:4017`.
- The **head IS re-latched** after `xrLocateViews` (`updateHmdPose` again at `vk_openxrdevice.cpp:4053`), but there is **no second hand locate** â€” so held objects trail the fresh head by ~1 frame. Grep confirms zero reprojection/late-latch/spacewarp code anywhere in the tree.
- Real device velocity is already captured but under-used: `xrHandVelocities[2]` (`vk_openxrdevice.h:167`), ring buffers `xrHandLinearVelocityHistory[2][10]` (`:169`), captured at `vk_openxrdevice.cpp:3283-3299`. It is consumed *only* by `GetHandVelocity` (`:4389`) and `GetHandAngularVelocity` (`:4403`) for throw/parry â€” **never for pose extrapolation**.
- The refresh-rate clock for a dt clamp is real: `xrCurrentDisplayRefreshRate` (`vk_openxrdevice.h:266`), FB refresh-rate ext wired at `vk_openxrdevice.cpp:177-178/1852-1853/3886`.
- Arm IK solves once per tic in `VR_UpdateArmIK`, seeding `vr_ik_pose` from the full-skeleton bind every tic (`p_user.cpp:2924-2927`), overwriting only the arm chain, then glue-copying the whole array to `proceduralPose` at `p_user.cpp:3294`. So the virtual forearms update at 35Hz while the head updates at 90/120Hz.
- Melee/parry sample a **single point** per tic against the weapon transform (`hw_vrmodes.cpp:1311`, ellipsoid test `:1329-1332`) using a 4-sample smoothed swing velocity.

**The seam.** `GetHandTransform` (`vk_openxrdevice.cpp:5320`) rebuilds the render matrix from Euler-derived globals `weaponoffset`/`weaponangles` (`:5328-5348`). A late-latch re-queries `xrLocateSpace` for hands after `xrLocateViews` and re-derives only the held-object model matrix + IK wrist targets. A per-render-frame IK solve re-runs the cheap wrist-target + elbow-pole solve straight into the bone buffer. A swept collision test rings the pose history and traces the arc, not the point.

**VR features it designs.** Late-latch held-object & body reprojection; full-rate arm-IK decoupled from the sim; swept/continuous-collision melee & parry; sub-tic swing interpolation + hit-stop; velocity-extrapolated authoritative aim.

---

### Wall 2 â€” The Frozen Type System

**What it is.** ZScript classes are frozen at compile/load. The guest cannot author a new class, inject defaults, or reparent an existing mod's weapon. Runtime class creation, defaults injection, and the archetypeâ†’3D-model substitution are pure `PClass` machinery.

**What EXISTS today.**
- `FVRWeaponResolver` walks `AllClasses` and tags `vr_weapon_data` / `vr_taxonomy` / `vr_metadata` onto class **defaults** â€” every writer uses `GetDefaultByType` (`vr_weapon.cpp:55/95/239/273`). Boot order permits minting: `PClassActor::StaticInit()` (`d_main.cpp:3769`) precedes `FVRWeaponResolver::Init()` (`d_main.cpp:3770`).
- `PClass::CreateDerivedClass` is fully present (`dobjtype.cpp:539-591`): sets `bRuntimeClass=true` (`:574`), `Derive` (`:575`), copies virtuals for non-tentative classes (`:579-581`), with a name-collision `return nullptr` guard (`:561-565`).
- The four missing archetype base classes all exist as real ZScript `PClass`es: `Rifle` (`weaponrifle.zs:7`), `SMG` (`weaponsmg.zs:7`), `Revolver` (`weaponrevolver.zs:7`), `Flamethrower` (`weaponflame.zs:7`) â€” all `: DoomWeapon`. `GetActorClassForArchetype` already maps all four (`vr_weapon.cpp:143-146`); only `ResolveWeapons`'s `IsDescendantOf` chain (`vr_weapon.cpp:38-46`) omits them.

**The severance (proven, not hypothesized).** The whole 3D weapon shell is a **runtime no-op today.** Resolver writes `vr_weapon_data` only onto class *defaults*, but all five consumers read it off *live instances* (`hw_weapon.cpp:2007/2124`, `p_pspr.cpp:501/735`). The instance pointer is **always null**: `CreateNew` memcpy's the default (`dobjtype.cpp:431`), then `ConstructNative` runs `AActor`'s in-class initializer `vr_weapon_data = nullptr` (`actor.h:802-803`, `dobjtype.cpp:440`) â€” overwriting the copied pointer. Unlike its siblings `vr_taxonomy`/`vr_metadata`, which **are** re-resolved every `StaticSpawn` (`p_mobj.cpp:5075-5076`), `vr_weapon_data` has **no per-spawn resolve and no defaultâ†’instance copy anywhere.** The `!= Unknown` guards short-circuit on every real weapon.

**The seam.** Insert a per-instance `vr_weapon_data` resolve beside `p_mobj.cpp:5075-5076`. Beyond that, mint derived variant classes (two-hand / holster / akimbo) at load via `CreateDerivedClass`, and hot-swap the live instance so any mod weapon inherits VR handling.

**Landmine (must not miss).** The `info.cpp:521-532` placement-new reconstruction that fixed the Keywords/`vr_metadata` FString boot-crash covers **only** Keywords + `vr_metadata` â€” **not** `vr_weapon_data` (the comment at `info.cpp:519-520` says exactly this). So: (a) if the fix converts the field to an owned value/struct with FStrings (`VRWeaponData` contains 4 FStrings: ModelName/SkinName/CustomReloadState), it **must** be added to that reconstruction block or it re-creates the boot-crash; (b) minted subclasses will **shallow-copy (alias)** the parent's `VRWeaponData` heap object via `info.cpp:486` â€” each minted default needs a **fresh** allocation before stamping variant flags, or you mutate the parent archetype's shared struct. Do **not** build on `A_CheckSpawnModel` â€” it is a confirmed empty stub (`vr_weapon_helpers.zs:165-172`, only a `// Logic to swap...` comment; 12 Spawn-state callers).

**VR features it designs.** Universal mod-weapon VR handling (grip hotspots, two-hand foregrip, reload FSM, 3D-model swap injected onto any loaded weapon); scavenged per-instance weapon quirks; completed archetype taxonomy.

---

### Wall 3 â€” The Field/API Allowlist

**What it is.** ZScript sees only the native fields and functions someone explicitly marshaled through a `DEFINE_FIELD`/`DEFINE_ACTION_FUNCTION` thunk. Anything the device captures but nobody thunked is invisible to the guest â€” a one-way gap.

**What EXISTS today.**
- Haptics are **fully built** and fire natively on ~30 gameplay events. `VR_HapticEvent` (`hw_vrmodes.cpp:1036`) â†’ `vrmode->Vibrate(duration, position, vibIntensity)` â†’ `ProcessHaptics` â†’ `xrApplyHapticFeedback` (`vk_openxrdevice.cpp:5405/5443`). Reload FSM already fires it: `reload_seat` (`p_user.cpp:2515`), `reload_rack` (`:2547`), `reload_chamber` (`:2562`); parry fires it (`p_interaction.cpp:1649`); snatch/deflect/hardpoint/climb all wired.
- **But there is genuinely no inbound ZScriptâ†’haptic thunk.** Grep `DEFINE_ACTION_FUNCTION.*(Vibrate|Haptic)` over all `src` = **zero matches.** This is the one real, clean, low-risk unlock in the haptic subsystem.
- Analog **grip** is *already* exposed: `GetGripValue` thunk (`vmthunks_actors.cpp:2585`), native decl (`actor.zs:909`), tic-mirrored into `player_t::vr_grip_value` (`p_user.cpp:1474`).
- Analog **trigger** is **not**: `xrSelectAction` is a BOOLEAN action (`vk_openxrdevice.cpp:2015`), read via `GetActionBoolean` (`:3106`); no `xrTriggerValue` member exists. `GetActionFloat` helper already exists (`:1186`).
- Angular velocity is **~80% built**: OpenXR captures it into `xrHandAngularVelocityHistory` (`vk_openxrdevice.cpp:3291`) and implements `GetHandAngularVelocity` (`:4403`), declared virtual in the base (`hw_vrmodes.h:173`). Only a VM thunk + `actor.zs` decl are missing (plus a small OpenVR override â€” OpenVR reads `pose.vVelocity` at `gl_openvr.cpp:3042` but does not override angular).
- `GetHandVelocity` thunk is a live working template (`p_actionfunctions.cpp:5861`), reading `vr_hand_vel_buffer` and remapping to map space `DVector3(avg.X, avg.Z, avg.Y) * (vr_scale_meters_to_units/35.0)`.

**The seam.** Add thunks that call `VRMode::GetVRModeCached(false)->Vibrate(...)` / `->GetHandAngularVelocity(...)`, mirroring `GetGripValue`. Add an `xrTriggerValueAction` + `xrTriggerValue[2]` + poll + `player_t` mirror + `GetTriggerValue` thunk (a new POD `float[2]` is FString-clobber-safe).

**Two landmines the API MUST fix or document.**
1. **The channel/intensity contract is systematically buggy at the `VR_HapticEvent` layer.** `VR_HapticEvent`'s `position` 1(left)/2(right) is **incompatible** with `Vibrate`'s channel 0(left)/1(right): position 1 â†’ `Vibrate(ch1)` â†’ RIGHT, and position 2 â†’ `Vibrate(ch2â†’clamp1)` â†’ RIGHT (`vk_openxrdevice.cpp:5483-5496`). **Both 1 and 2 hit the RIGHT actuator** â€” `VR_HapticEvent` can never address the left hand for a single-hand event. Proof in one function: `p_map.cpp:4770` calls `Vibrate(150, rightHanded?1:0, 0.8)` (correct 0=L/1=R) while `:4771` calls `VR_HapticEvent(..., rightHanded?2:1, ...)` â€” two incompatible conventions on the same fire event. A ZScript thunk must convert a 0/1 hand index â†’ 1/2 position, **not** pass it through raw. Additionally, `VR_HapticEvent`'s 3rd arg is `int intensity` with `vibIntensity = intensity/100.0f`, so three sites pass a truncating float literal `1.0` â†’ int 1 â†’ **0.01 amplitude** (near-silent): parry (`p_interaction.cpp:1649`) and snatch (`p_user.cpp:2062`). The parry site *also* passes a hand-index `i` (0/1 from `hw_vrmodes.cpp:1334`) where a 0/1/2 position is expected â€” so a mainhand parry (i=0) routes to "both hands."
2. A raw-double 0..1 thunk must **not** reuse `VR_HapticEvent`'s `/100` scaling; it must call `Vibrate` directly (duration is hardcoded `0.05f` inside `VR_HapticEvent`), and must **cap its own duration** â€” `ProcessHaptics` clamps amplitude but not duration, so a runaway loop buzzes indefinitely.

**VR features it designs.** Modder-callable haptic pulses; correct left-hand haptics; analog trigger for progressive-pull mechanics; hand angular velocity for whip-crack/slice-force/parry-gating.

---

### Wall 4 â€” The Cooked-Input Abstraction

**What it is.** The guest never sees raw 6DoF pose. It sees `AttackPos`/`AttackDir` â€” a single point and vector the host already collapsed for the current tic â€” plus a handful of derived scalars. The lossy Euler round-trip and the single-point collapse are structural: the sandbox is fed cooked input.

**What EXISTS today.**
- The device writes `AttackPos`/`AttackPitch`/`AttackAngle`/`AttackRoll` + `Offhand*` inside `UpdateControllerState` on the render path, **ungated** (`vk_openxrdevice.cpp:3781-3802`), with zero `vr_aim_through_tic`/`gametic` reference in the file.
- The consumer fork is real at every fire site: `OverrideAttackPosDir` swaps `Angles` for `AttackDir`/`OffhandDir` at `P_LineAttack` (`p_map.cpp:4786-4801`), `P_AimLineAttack` (`:4598-4613`), `P_LineTrace` (`:5204-5219`), `RailAttack` (`:5668-5685`), `P_SpawnPlayerMissile` (`p_mobj.cpp:7586-7611`). `MapWeaponDir` already subtracts `actor->Angles.Yaw/Pitch` (`hw_vrmodes.cpp:941-942`) â€” aim is already expressed body-relative.
- Two-hand stabilized aim is already solved in the render thread (`vk_openxrdevice.cpp:3331-3348`) because the sim can't.
- The Euler round-trip is lossy: `OpenVREulerAnglesFromQuaternion(location.pose.orientation)` (`:3311`) then floats baked as `angles[YAW/PITCH/ROLL]` (`:3312-3317`). The raw `XrPosef` (`xrHandPoses[2]`, `vk_openxrdevice.h:165`) and `XrSpaceVelocity` (`:167`) are already stored, so a full 6DoF sample struct is additive.

**The seam.** Carry a full quaternion pose + velocity + `XrTime` sample instead of the Euler globals, exposed via a `GetHandPose6DoF` virtual+thunk (return-by-value, safe â€” added to the render class `VKOpenXRDeviceMode`, not `AActor`, so the InitializeDefaults FString-clobber does not apply). Extend the two-hand render solve to a full rigid barrel transform (rear hand = pivot, front hand = direction), read the muzzle bone offset from the weapon IQM, and write muzzle-world-pos â†’ `AttackPos` + true barrel vector â†’ `AttackDir`.

**Scope note.** The Euler globals are read across **7 files**, not 3: `hw_vrmodes.cpp`, `vk_openxrdevice.cpp`, `gl_openxrdevice.cpp`, `QzDoom/qzdoom_common.cpp`, `QzDoom/VrCommon.h`, `gl_openvr.cpp`, and `hw_weapon.cpp` (the actual gun-render read â€” **not** `p_user.cpp`; recon originally named the wrong IK file). Any struct swap must keep `weaponoffset`/`weaponangles` byte-identical for all 7 or audit each. That is why the full-sample refactor is "L, plausible," not "M."

**VR features it designs.** True two-hand articulated weapons firing from the muzzle; predicted-pose authoritative aim; lossless 6DoF for modders.

---

### Wall 5 â€” GC / VM Lifetime & Serialization

**What it is.** The VM's object lifetime is GC-managed; native fields live or die with the C++ `AActor`. Serialization is an explicit allowlist â€” a field is saved only if someone wrote it into `Serialize`. Transient render-derived VR state is *deliberately* excluded, and that exclusion is a load-bearing convention, not an oversight.

**What EXISTS today.**
- `AActor::Serialize` serializes **only** `A("Keywords", Keywords)` (`p_mobj.cpp:393`) among the VR fields â€” no `vr_weapon_data`, `vr_taxonomy`, or `vr_metadata`. Siblings are harmless because they re-resolve every `StaticSpawn`; `vr_weapon_data` is the odd one out precisely because it has no such resolve.
- `player_t::Serialize` lives at `p_user.cpp:3812` (**not** `p_saveg.cpp`) and serializes **zero** VR transient buffers: `vr_prev_hand_pos`, `vr_hand_vel_buffer`, `vr_held_items`, `vr_ik_pose`, `vr_grip_owner`. `d_player.h:561-585` documents the standing convention explicitly: transient render-derived VR state MUST be excluded from the serializer list or it re-opens the VR-aim-leak/desync antipattern.
- `vr_grip_owner` is explicitly excluded (`d_player.h:572-573`) as transient client-presentation state.
- The system already uses GC `TObjPtr` (`d_player.h:475`) precisely because raw `AActor*` go dangling.

**The seam.** Serialize only the archetype **int** and re-derive the `FState*` render cache on load via `PostSerialize` (the archetype is deterministic from the class default: `ResolveWeapons` keys off `IsDescendantOf`, `vr_weapon.cpp:38-46`; `FState*` is not stable across load). For new transient fields â€” grab caches, `vr_grip_target[2]`, swing hit-sets â€” the correct action is to **NOT touch the serializer**, the opposite of adding save/load code. Any raw `AActor*` hit-set must use `TObjPtr` or validate before deref (an actor can be destroyed mid-swing).

**VR features it designs.** Correct save/load of resolved weapon shells (client-local render cache); dangling-safe per-swing hit accumulators; safe minted-class serialization.

---

### Wall 6 â€” Determinism-as-Cost (the net boundary)

**What it is.** The multiplayer wire only ever carries `usercmd_t {buttons, 6 shorts}` (`d_protocol.h:64-73`). Anything richer â€” 6DoF pose, render-rate velocity â€” cannot cross deterministically. Every render-fed field is client-local and non-deterministic by construction. This is the wall the net-sanitize mission (memory) exists to manage.

**What EXISTS today.**
- **Confirmed wire bug:** `PackUserCmd` `byte[3] = (buttons>>21)&0xFF` (`d_protocol.cpp:265`) covers only bits 21â€“28; the continuation mask `0xFFE00000` (`:275`) fires for bits 29/30 but the byte carrying them drops them. `BT_VR_LGRIP = 1<<29` / `BT_VR_RGRIP = 1<<30` (`d_event.h:78-79`) are set into the local ucmd (`g_game.cpp:851-852`) but **never reach a peer.** The enum warns "up to 29 buttons" (`d_event.h:38`).
- The tic-gate idiom is shipped on both other backends: `vr_aim_through_tic` default false (`hw_vrmodes.cpp:640`); mono gate `hw_vrmodes.cpp:984-998`; OpenVR gate `gl_openvr.cpp:3275-3279`. **The OpenXR path is the one that lacks it** â€” the `:3781` write is ungated.
- **Critical ordering truth:** `VKOpenXRDeviceMode::SetUp` calls `super::SetUp()` (`:2841`), whose tic-gated block (`hw_vrmodes.cpp:985-998`) *already* writes `AttackPos = PosAtZ(shootz)` per-tic â€” then `UpdateControllerState` (`:3781`, ungated) **unconditionally clobbers it** every frame. So on the OpenXR path the base per-tic latch is **dead on arrival**, and the net-sanitize STEP 1 is effectively not running on the shipping path.
- **The containment is an accident, not a boundary.** Recon's claim that the `consoleplayer` gate uniformly contains all pose reads is **FALSE**: `VR_UpdateGravityGloves` (`p_user.cpp:1693`), `VR_UpdateClimbing` (`p_user.cpp:3303`), and `VR_UpdateArmIK` have **no** `consoleplayer` gate and run for every player copy in `P_PlayerThink` (`:1616-1621`). They are safe today only because `GetWeaponTransform`/`GetHandVelocity` read a single local device singleton and single-player only thinks `players[consoleplayer]`. In real P2P this applies **local** hand velocity/pose to **remote** pawns' held items â€” a genuine live desync source. The newer subsystems (`VR_UpdateHardpoints` `p_user.cpp:2223`, `VR_UpdateWeaponReload` `:2443`) *do* apply the gate; the older ones do not.

**The seam.** Gate the `:3781` write on `gametic != s_lastAimTic` (mirroring the shipped mono/OpenVR gates). Extend the ucmd packer to a 5th byte and the self-sizing continuation walk in `SkipTicCmd` (`d_protocol.cpp:421-433` â€” **not** `Net_SkipCommand`/`d_net.cpp`, which has no `DEM_USERCMD` case). Reduce 6DoF aim to a quantized yaw/pitch delta relative to body (`MapWeaponDir` is already the clean reduction point). Add the `consoleplayer` gate to gloves/climb/IK â€” not merely centralize the existing ones.

**Trap.** The ROLL slot (`ucmd.roll`) that a net-aim-delta would "reuse" is a **live ZScript-readable input** (`MODINPUT_ROLL`/`INPUT_ROLL`, `p_things.cpp:558/567`), merely never *written* by `G_BuildTiccmd`. It is free-in-practice but not private; a mod may read it. A new packed short pair is safer but is a full protocol/save/demo break requiring a version bump and bit-identical quantization across peers.

**VR features it designs.** Working VR grips in multiplayer; net-safe authoritative aim; deterministic climb/fling; the whole P2P DM net-sanitize goal.

---

## Proposed Engine Alterations

Consolidated, deduped, sorted by leverage (impact Ã— certainty Ã· regression risk). "Seam" column marks the recon verdict: **CONFIRMED** = real seam + confirmed feasibility; **PLAUSIBLE** = real seam, feasibility plausible; **DOUBTFUL** = real seam but deep/hazardous or (one case) seam not found.

### Tier A â€” High leverage, confirmed seam, low regression

| # | Alteration | VR feature unlocked | Mechanism | Files | Effort | Netplay | Seam |
|---|---|---|---|---|---|---|---|
| A1 | **Per-instance `vr_weapon_data` resolve at spawn** | The entire 3D weapon-shell + anim sync goes from no-op to live | Add defaultâ†’instance resolve beside the sibling re-resolve; or convert field to owned value member | `p_mobj.cpp:5075-5076`, `actor.h:802`, (`info.cpp:521-532` if owned-value) | Sâ€“M | none | **CONFIRMED** |
| A2 | **Expose haptics to ZScript** (`VR_Vibrate`/`VR_HapticPulse` thunk) | Modders can buzz controllers; FSM auto-fire already done | Thunk â†’ `GetVRModeCached(false)->Vibrate(dur, position, amp)`; convert 0/1 handâ†’1/2 position; cap duration; skip `/100` | `vmthunks_actors.cpp` | S | none | **CONFIRMED** |
| A3 | **Gate the OpenXR `AttackPos` write on `vr_aim_through_tic`** | Net-sanitize STEP 1 finally runs on the shipping path; prereq for A9/A10 | Wrap `:3781` write in `gametic != s_lastAimTic` guard mirroring `hw_vrmodes.cpp:985-998` | `vk_openxrdevice.cpp:3781` | S | fixes desync | **CONFIRMED** |
| A4 | **Fix parry/snatch haptic intensity + channel contract** | Left-hand haptics work; parry/snatch stop being near-silent | Pass corrected float amp; convert hand-indexâ†’position; sweep `:1649`, `:2062` | `p_interaction.cpp:1649`, `p_user.cpp:2062`, `hw_vrmodes.cpp:1046` | S | none | **CONFIRMED** |
| A5 | **Extend ucmd packer to carry bits 29/30** (VR grips) | VR grip buttons reach peers in MP | 5th byte in `PackUserCmd`/`UnpackUserCmd`; extend continuation walk | `d_protocol.cpp:219/265/275`, `d_protocol.cpp:421-433` (`SkipTicCmd`) | S | fixes MP | **CONFIRMED** |
| A6 | **Expose bone scaling in `SetModelBonePose`** | ZScript zero-scale bone = dismember-by-hiding | Add `sx/sy/sz` params defaulted to 1.0; stop force-writing `(1,1,1)` at `:2428` | `vmthunks_actors.cpp:2428`, `actor.zs:877` | S | none | **CONFIRMED** |
| A7 | **Complete archetype taxonomy + retire `A_CheckSpawnModel` stub** | Rifle/SMG/Revolver/Flamethrower get 3D VR shells | Add 4 `else if IsDescendantOf` lines; optionally delete 12-caller stub | `vr_weapon.cpp:38-46`, `vr_weapon_helpers.zs:165-172` | S | none | **CONFIRMED** |
| A8 | **Expose hand angular velocity to ZScript** | Whip-crack, slice-force, parry-gating read true wrist snap | Thunk mirroring `GetHandVelocity` calling `GetHandAngularVelocity`; + OpenVR override | `p_actionfunctions.cpp:5861`(pattern), `actor.zs`, `gl_openvr.cpp` | S | sanitize if used for damage | **CONFIRMED** (OpenXR) |

### Tier B â€” High leverage, confirmed/plausible seam, moderate effort or coupling

| # | Alteration | VR feature unlocked | Mechanism | Files | Effort | Netplay | Seam |
|---|---|---|---|---|---|---|---|
| B1 | **Late-latch hand poses after `xrLocateViews`** | Held weapon/forearms snap to photon-time; gun stops swimming behind wrist | Factor `updateHandPose` (`:3261-3319`) + two-hand override (`:3331-3348`) into `RelocateHandPoses()`, call after `:4053` | `vk_openxrdevice.cpp:3261-3348/4053` | Mâ€“L | presentation-only | **CONFIRMED** (requires A3 first) |
| B2 | **Native per-tic weapon bone articulation writer** | Slide/cylinder/charging-handle follows off-hand during reload | Write `proceduralPose` on weapon actor from `hs_rack` travel; shares PSprite render path (`models.cpp:469â†’790`) | `p_user.cpp:2546-2553`, `models.cpp:792` | L | none | **PLAUSIBLE** (ships dark; `vr_new_weapon_handling` off) |
| B3 | **Full-rate arm-IK solve decoupled from 35Hz** | Forearms track hands frame-perfectly (user's #1 priority) | Keep tic solve as anchor; re-run wrist-target + pole IK per render frame into bone buffer | `p_user.cpp` (IK), `models.cpp` | L | presentation-only | **PLAUSIBLE** |
| B4 | **Velocity-extrapolate held-object transform to `predictedDisplayTime`** | Held object points where the barrel actually is at fire/photon time | New construction off raw `XrPosef`+`XrSpaceVelocity`; run after yaw-derotation (`:3305-3308`) | `vk_openxrdevice.cpp` (new path), `models.cpp:379` | M | needs A3; sanitize aim | **PLAUSIBLE** (transform-space complexity; requires A3) |
| B5 | **Unified per-tic grabbable spatial-hash cache** | One broadphase for both hands; kills duplicate blockmap walk | Scan once, Z-band pre-filter, feed superset to per-hand cone re-score at `:1863-1880` | `p_user.cpp:1698/1847-1848`, `d_player.h` (new transient field) | M | omit new field from serialize | **CONFIRMED** (new cvar, default OFF) |
| B6 | **Two-hand articulated weapon: aim from the muzzle** | Rifles/spears steer by front hand, fire from barrel tip | Extend render two-hand solve to rigid transform; read muzzle bone offset; write `AttackPos`/`AttackDir` | `vk_openxrdevice.cpp:3331`, `models_iqm.cpp`, `p_map.cpp` | L | sanitize aim | **PLAUSIBLE** |
| B7 | **Swept-volume melee (continuous collision)** | Fast slashes connect where the blade passed; no ghost swings | Ring-buffer render pose; sweep capsule last-ticâ†’this-tic via `Trace()`; generalize dead block to `MF_SHOOTABLE` | `p_user.cpp:2090-2143`, `p_map.cpp:4715`, `p_maputl.h:322` | L | derive from sanitized per-tic data | **CONFIRMED** (dead block real; needs radius term + box padding + Z test) |
| B8 | **Serialize `vr_weapon_data` render-cache (archetype int) + re-derive on load** | Resolved weapon shell survives save/load | Serialize archetype int only; `PostSerialize` re-derive `FState*` | `p_mobj.cpp`(Serialize), `p_user.cpp:3812` | S | client-local cache | **CONFIRMED** (depends on A1) |
| B9 | **Load-scan minting of two-hand/holster/akimbo variant classes** | Any loaded mod weapon gains VR handling automatically | `CreateDerivedClass` per archetype at load; stamp variant flags on **fresh** `VRWeaponData` per minted default | `dobjtype.cpp:539-591`, `vr_weapon.cpp`, `info.cpp:486` | L | mint order must be deterministic across peers | **PLAUSIBLE** (aliasing landmine) |

### Tier C â€” Real seam, high effort / high regression / deep surgery

| # | Alteration | VR feature unlocked | Mechanism | Files | Effort | Netplay | Seam |
|---|---|---|---|---|---|---|---|
| C1 | **Carry full 6DoF quaternion+velocity+XrTime hand sample** | Lossless pose to modders; substrate for B4/B6 | Per-hand struct + `GetHandPose6DoF` virtual/thunk; keep Euler globals byte-identical for 7 consumers | `vk_openxrdevice.cpp`, 6 other consumer files | L | none (render class) | **PLAUSIBLE** (7-file cross-backend surface) |
| C2 | **Swept parry: test projectile PATH vs blade path** | Bat fast projectiles back; reflect about blade normal | `prevPos = Pos()-Vel`; blade side needs B7's ring buffer | `hw_vrmodes.cpp:1311`, `p_interaction.cpp:1634-1641` | L | highest net sensitivity; sanitize reflect | **PLAUSIBLE** |
| C3 | **Swept-volume projectile catch/deflect (un-stub disabled block)** | Snatch/deflect bullets along hand segment | Un-comment `:2090-2143`; **add** manual box padding (no `Expand`) + Z-band test | `p_user.cpp:2090-2143` | M | client-local; deflect kill-credit | **PLAUSIBLE** (broadphase under-covered as written) |
| C4 | **Extend native IK to layered upper-body chain** (spine/clavicle/head-look) | Full-body avatar torso/head follow | Drive already-resolved `collar` joint (`p_user.cpp:2936`); compose head-look with body-facing yaw, don't double-apply | `p_user.cpp:2787-2800/2924-2927`, `models.cpp:223` | XL | presentation-only | **PLAUSIBLE** (under-constrained) |
| C5 | **Two live instances for akimbo (dual-wield same class)** | Independent per-hand reload/fire | `VR_EquipToHand` (`p_user.cpp:1681`) branch; **duplicate** the single-slot reload FSM cache per hand | `p_user.cpp`, `d_player.h:520-541` | L+ | one-instance-per-class ammo assumption | **DOUBTFUL** |
| C6 | **Networked aim-delta channel (yaw/pitch offset in ucmd)** | Net-safe 6DoF aim in DM | Reduce via `MapWeaponDir`; new packed short pair (protocol bump) â€” avoid the live ROLL slot | `p_map.cpp`(consumers), `d_protocol.cpp`, `g_game.cpp` | L | full protocol/save/demo break | **PLAUSIBLE** |
| C7 | **Quantize/network hand velocity for climb/fling** | Deterministic climb & throw in MP | Sanitize `GetHandVelocity`/`GetHandAngularVelocity` at net boundary; tic finite-diff | `p_user.cpp:1724/3303`, net layer | M | breaks determinism; depends on C6 | **PLAUSIBLE** (feel change â†’ flag to user) |
| C8 | **Add analog TRIGGER float action** | Progressive-pull trigger mechanics | New `xrTriggerValueAction` before `xrAttachSessionActionSets` (`:2201`); `xrTriggerValue[2]` + mirror + thunk | `vk_openxrdevice.cpp:2015-2201`, `d_player.h`, `p_user.cpp:1474` | Sâ€“M | none | **PLAUSIBLE** |
| C9 | **Haptic waveform/envelope layer (freq + ramp)** | Metal clang vs soft thud vs metallic ring | Extend per-hand state; eval envelope in `ProcessHaptics`; freq best-effort (most runtimes ignore) | `vk_openxrdevice.cpp:5394-5470` | M | none (device-local) | **PLAUSIBLE** (shared mutable state, allocation-free) |
| C10 | **Fake finger-curl pose blend from grip scalar** | Fingers close around gripped objects | nlerp bindâ†’closed from `vr_grip_value`; no-op if mitten rig | `p_user.cpp:2924-2927`, `models_iqm.cpp:560` (un-static `InterpolateBone`) | Sâ€“M | none | **PLAUSIBLE** (cosmetic) |
| C11 | **Formalize consoleplayer pose gate into one accessor** | Prevent silent MP desync from ungated pose reads | ADD the gate to gloves/climb/IK, not just centralize | `p_user.cpp:1693/3303`, IK | M | closes real desync | **CONFIRMED** (premise correction: containment is accidental) |
| C12 | **Generic `VR_ApplyHandImpulse` (telekinesis primitive)** | Force-push/pull via hand motion | `self->Vel += remapped hand-vel`; same `(X,Z,Y)` map remap as `GetHandVelocity` | `p_actionfunctions.cpp:5861`(pattern), `p_user.cpp:1727` | S | sanitize-required (client-local buffer) | **CONFIRMED** |
| C13 | **Hand-proximity native field-patch hook** | Touch-reactive world (radius/solidity swap) | `VR_UpdateHandProximity` after `p_user.cpp:1617`; blockmap broad-phase; `bVRTouchable` as real `DEFINE_FLAG`/`DEFINE_FIELD` (not a bare bool like `bForceShowVoxel`) | `p_user.cpp:1617/1719`, `actor.h` | Mâ€“L | none | **PLAUSIBLE** |
| C14 | **GravityDir wall-walk plane-native rest clamp** | Stand/walk on vertical walls | Plane clamp in `FallAndSink`/`P_ZMovement` gated on `GravityDir.isZero()` | `p_mobj.cpp:2725-2732/3027-3031/4437-4440` | XL | breaks determinism | **DOUBTFUL** (documented removed-then-reverted regression) |
| C15 | **Sub-tic swing interpolation + hit-stop** | Fast flicks register; blade "bites" | Sub-sample swing into K micro-segments for sweep; local render/haptic hit-stop only | `p_user.cpp`(ring buffer), `p_map.cpp` | M | keep hit-stop local, resolve damage deterministic | **PLAUSIBLE** |
| C16 | **Release-velocity sampling modes (peak/most-recent)** | Throws land where flung; whip reads wrist snap | New `vr_throw_vel_mode` cvar; mode 0 = today's 4-sample average | `p_user.cpp:1727-1732/1756/1796`, `hw_vrmodes.cpp` | S | none (mode 0 = parity) | **CONFIRMED** |
| C17 | **Per-swing hit accumulator + angular tip sweep** | No double-hits; blade-tip reach | `vr_swing_hitset[2]` (`TObjPtr`); tip = `AttackPos + AttackDir()*bladeLength`; **omit from serialize** | `d_player.h:442-444`, `actor.zs:864` | M | none | **PLAUSIBLE** |

### Explicitly do NOT pursue

| Item | Why | Verdict |
|---|---|---|
| **Grabbable-membership dirty list (skip blockmap walks)** | No single flag-change chokepoint exists â€” `MF_MISSILE`/`MF_SPECIAL` set/cleared across many uncoordinated sites; `flags:grabprop` is a load-time Keywords string, a third membership source; missed invalidation â†’ freed-actor deref. B5 alone removes the duplicate walk. | **DOUBTFUL â€” seam NOT found**; only justified by profiling that doesn't exist |
| **Decouple compositor submit from the blocking fence wait** | `xrBeginFrame`/`xrEndFrame` must pair 1:1 on one thread; ~9 `xrEndFrame` sites (incl. error bailouts) must all move together; `xrFrameInProgress` is an unsynchronized bool; existing `vr_openxr_sync_mode` gate only defers the *desktop mirror*, not the XR submit. | **DOUBTFUL â€” XL spec-hazard** |
| **Build anything on `A_CheckSpawnModel`** | Confirmed empty stub (`vr_weapon_helpers.zs:165-172`). | Dead |

---

## Bold Cross-Cutting Moves

The strongest ideas from the three design lenses. Each fuses render/input + playsim + a runtime seam that ZScript structurally cannot cross.

**1. Late-Latch Held-Object & Body Reprojection.** Between the pose read at `SetUp` and photon-out, the runtime already has a newer predicted pose, but only the *head* is re-latched (`:4053`). Re-query `xrLocateSpace` for both hands right before `xrEndFrame` and re-derive **only** the held-weapon model matrix and IK wrist targets; the world stays where the eye buffer drew it, the hands snap to photon-time. *Why only native:* ZScript never sees `predictedDisplayTime`, cannot call `xrLocateSpace`, and physically cannot execute inside the frame lifecycle between `xrWaitFrame` and `xrEndFrame`. *VR payoff:* the "my gun lags my wrist on fast flicks" tell â€” the single biggest 1:1-hand fidelity killer â€” disappears. (Requires A3 first; keep presentation-only per `d_player.h:561`.)

**2. Latch true OpenXR controller velocity (linear + angular) as first-class fields.** The engine already captures `XrSpaceVelocity` into ring buffers (`:3283-3299/3291`) and exposes `GetHandVelocity`/`GetHandAngularVelocity` â€” the substrate is *built*; the gaps are only a thunk + `actor.zs` decl for angular, and an OpenVR override. This becomes the shared substrate for throw speed, whip/sword momentum, parry-swing gating, and impact-haptic intensity. *Why only native:* `XrSpaceVelocity` exists only at the OpenXR call site; position-delta reconstruction in the sandbox is capped at sim rate and yields no true angular velocity at all. *VR payoff:* every "how hard/fast did I move" mechanic stops feeling mushy and one-frame-late.

**3. Swept-volume continuous-collision melee.** A real VR sword covers 1â€“2m between two 35Hz tics, so fast swings tunnel through thin enemies. Ring-buffer the render-rate pose history and sweep a capsule from last-tic to this-tic transform through the native `Trace()` path â€” first solid contact along the arc wins. The dead swept block already exists (`p_user.cpp:2090-2143`); un-stubbing it requires the missing `thing->radius` term, manual box padding (no `Expand` on `FBoundingBox`), and a Z-band test. *Why only native:* ZScript sees the one collapsed `AttackPos` per tic, cannot access intra-tic pose history, and cannot inject a swept trace. *VR payoff:* fast slashes connect where the blade visibly passed â€” the biggest presence-killer in VR melee, gone.

**4. Per-contact impact haptics driven by the actual hit.** Haptics today are fixed presets (`Vibrate(150, hand, 0.8)`, `p_map.cpp:4769`), but `ProcessHaptics` already re-issues pulses per render frame â€” the envelope plumbing exists. On a resolved swept-melee/parry contact, emit `{hand, energy = f(hand velocity, target material)}` seeding a short attack-decay envelope: sharp spike on wall, soft thud on flesh, metallic ring on parry. *Why only native:* `ProcessHaptics` samples a live envelope at 90â€“120Hz; ZScript fires a discrete 35Hz event and cannot shape a per-frame amplitude curve. *VR payoff:* the hand *feels* the material and the force. (First fix the channel/intensity contract â€” see Wall 3.)

**5. Two-hand articulated weapon firing from the muzzle.** `weaponStabilised` (`vk_openxrdevice.cpp:3331`) already fuses both controller poses but collapses them to one `weaponangles`, and the shot still leaves the wrist. Extend the render-side solve to a full rigid transform (rear hand = pivot, front hand = direction), read the muzzle bone offset from the weapon IQM, and write muzzle-world-pos â†’ `AttackPos` + barrel vector â†’ `AttackDir`. *Why only native:* the two-controller fusion and IQM bone offsets both live render-side; `AttackPos`/`AttackDir` are native fields; ZScript sees only the collapsed pose. *VR payoff:* the difference between "gun glued to a controller" and "holding a weapon in two hands."

**6. Runtime weapon transmutation: mint a derived PClass per grab.** Extend `FVRWeaponResolver` from tagging defaults to *minting* a derived `PClass` the first time a weapon of a given archetype is grabbed, injecting grip hotspots, two-hand foregrip, reload FSM, and 3D-model swap as real defaults, then hot-swapping the live instance. Any mod authored years later that knows nothing about DoomXR becomes a first-class VR object automatically. *Why only native:* ZScript classes are frozen at load; `CreateDerivedClass` + `InitializeDefaults` is native-only. *VR payoff:* load any weapon mod and every gun already grips, reloads, and renders as a 3D object â€” zero per-mod patching. *(XL, highest blast radius; each minted default needs a fresh `VRWeaponData` allocation, and mint order must be deterministic across peers.)*

**7. GravityDir traversal grammar authored by hands and gaze.** `AActor::GravityDir` is already integrated in the mobj physics loop (`p_mobj.cpp:3027-3029/4437`). A two-hand "plant" gesture drops a gravity well; a palm-out push reorients local gravity; grabbing a wall rotates the *player's* `GravityDir` for wall-walk. Because gravity is per-actor, thrown props, shells, blood, and enemies all fall toward whatever the player just authored. *Why only native:* ZScript can set gravity *scale* but not a per-actor *direction* `DVector3`; palm-out gating needs render-thread `OffhandRoll`; rewriting the player's own fall vector inside the mobj step is off-limits to script. *VR payoff:* traversal becomes a spatial language you speak with your body. *(Nausea vector â€” comfort-gate hard; enemy AI assumes âˆ’Z; note the wall-walk *rest* clamp itself is C14/DOUBTFUL.)*

**8. Full-rate arm-IK decoupled from the sim.** Keep the tic solve as the authoritative anchor (elbow hint, twist, clamp) but re-run the cheap wrist-target + elbow-pole solve per render frame from the freshest hand pose, straight into the bone buffer. The full-skeleton bind seed already runs every tic (`p_user.cpp:2924-2927`), so no new upload path is needed. *Why only native:* IQM has no bone R/W from ZScript, and a per-render-frame solve must run outside the single 35Hz `P_PlayerThink` entry point. *VR payoff:* forearms track your real hands frame-perfectly â€” the user's #1-priority full-body avatar goes from "a body model is attached to me" to "those are my arms." *(Reuse the tic solve's clamps to avoid elbow-singularity pop; historically fragile scale/coordinate bookkeeping â€” see the divide-by-live-render-scale fix in memory.)*

**9. Predicted-pose intent layer for aim + parry.** Publish, each tic, one extrapolated present-time snapshot: `AttackPos`/`AttackDir` extrapolated forward with `XrSpaceVelocity` to the sim-commit instant, the two-hand-braced barrel line, and a parry plane from blade orientation + angular velocity. A bullet fired mid-swing goes where the barrel is *now*; a deflect registers against the plane the sword is actually sweeping. *Why only native:* only the render/OpenXR layer holds the predicted pose and velocity; the sim's view is a tic old by construction. *VR payoff:* tight hand-to-world coupling â€” the difference between convincing and floaty VR. *(Must produce one sanitized net-safe value per tic â€” see the determinism tax; requires A3.)*

**10. Procedural hurtbox skeleton from live IK bones.** Read the live bone matrices back into native swept collision capsules: the player's IK arms become real interaction volumes (forearm block, shoulder-check), and a grabbed enemy's bones become limb-level grab handles. Combined with GravityDir, a grabbed enemy can be swung by one arm into a gravity well. *Why only native:* ZScript reads named IQM anims but cannot read back per-bone *world* matrices to build collision from them, and the IK pose is written render-side. *VR payoff:* the leap from "floating gun" to embodied VR. *(XL; per-bone capsule collision is CPU-heavy and can interpenetrate; skeletal read-back must sync with the render pose.)*

---

## The Determinism Tax

The wire carries only `usercmd_t {buttons, 6 shorts}`. Every VR feature that reaches for render-rate pose or velocity is, by construction, non-deterministic and must be paid for at the net boundary before it touches damage, movement, or authoritative aim. The single most dangerous misconception to carry forward: **the `consoleplayer` containment is an accident, not an enforced boundary.** Today's safety rests on "a single local device singleton + single-player only thinks the console pawn," not on the gate being applied everywhere. `VR_UpdateGravityGloves`, `VR_UpdateClimbing`, and `VR_UpdateArmIK` are **ungated** and run for every player copy â€” in real P2P they apply local hand velocity/pose to remote pawns.

**Confirmed net bugs to fix first:**
- The ucmd grip-bit drop (bits 29/30, `d_protocol.cpp:265`) â€” grips never reach peers. **(A5)**
- The OpenXR `AttackPos` write is ungated (`vk_openxrdevice.cpp:3781`), clobbering the base per-tic latch every frame â€” net-sanitize STEP 1 is effectively dead on the shipping path. **(A3)**

**What the sanitize layer must cover:**

| Source | Field(s) | Requirement |
|---|---|---|
| Render-latched 6DoF pose | `AttackPos`/`AttackDir`/`Offhand*` | Gate write on `gametic != s_lastAimTic` (A3); optionally reduce to a quantized body-relative yaw/pitch delta on the wire (C6) with a protocol version bump and bit-identical quantization |
| Render-rate velocity ring | `GetHandVelocity`/`GetHandAngularVelocity` | Quantize + sanitize before any climb/fling/throw/damage use (C7); a tic finite-difference *will* feel different â€” flag to the user, do not tune silently (no-balance-decisions rule) |
| Swept melee / parry | swept contact result | Derive from the **same sanitized per-tic data on all peers**, inside the deterministic sim step â€” never off render samples directly in MP (B7/C2) |
| Reflected projectiles (parry) | projectile velocity/ownership/kill-credit | Deterministic off sanitized per-tic swing data or it is both a desync **and** a DM exploit (C2) |
| Minted classes | class identity/order | Mint order must be identical on all peers (`PClass::AllClasses` iteration) or save/net desyncs (B9) |
| Grip-arbiter targeting | `vr_grip_target[2]`, grab caches | New `AActor*`/pose-derived `player_t` fields MUST be omitted from the `FSerializer <<` list (the transient-exclusion rule at `d_player.h:561-573`) â€” same rule that guards the existing VR-aim leak (B5/C2 of grip lens) |

**What is NOT a net cost:** haptics (device-thread output, no sim state â€” A2/A4/C9), presentation-only late-latch and IK (B1/B3, excluded from save/net by convention), the render-cache serialize-the-int approach (B8, client-local re-derive). And note: transient VR buffers require **zero** save/load code â€” the correct action is to *not* touch `player_t::Serialize` (`p_user.cpp:3812`), the opposite of adding serialization. Any earlier "touch `p_saveg.cpp`" guidance is backwards.

---

## Recommended Next 3

Weighing the prior candidates (late-latch, continuous-collision melee, haptics-as-a-layer) against what the code actually shows:

### 1. A1 â€” Per-instance `vr_weapon_data` resolve at spawn *(the keystone)*

This is the highest-leverage single change in the entire recon, and it is **CONFIRMED** with a proven severance, not a hypothesis. The entire 3D weapon-shell + animation-sync subsystem is a **runtime no-op today** â€” the resolver writes only to class defaults (`GetDefaultByType`, `vr_weapon.cpp:55/95/239/273`), every consumer reads live instances (`hw_weapon.cpp:2007/2124`, `p_pspr.cpp:501/735`), and the instance pointer is always null because no defaultâ†’instance resolve exists (unlike its siblings at `p_mobj.cpp:5075-5076`). One insertion point beside the sibling resolve turns a dead subsystem live. Effort Sâ€“M, netplay impact **none** (tagging is default-only and deterministic). It unblocks B8 (serialize), B9 (minting), and everything downstream. **Caveat:** if you take the cleaner owned-value route, you MUST add `VRWeaponData` to the `info.cpp:521-532` placement-new block or re-create the FString boot-crash; the pointer-copy route must free in `OnDestroy` (`actor.h:808`) to avoid a per-spawn leak.

### 2. A3 â†’ B1 â€” Gate the OpenXR `AttackPos` write, then late-latch held objects *(paired)*

A3 is a **CONFIRMED**, low-risk, behaviorally-inert-when-off (CVAR default false) fix that finishes net-sanitize STEP 1 on the shipping path â€” and it is the **hard prerequisite** for late-latch. Today `UpdateControllerState` (`:3781`) unconditionally clobbers the base per-tic `AttackPos` latch every frame; gating it on `gametic != s_lastAimTic` (mirroring the shipped mono/OpenVR gates at `hw_vrmodes.cpp:985-998`) severs the fresh render pose from the authoritative aim. **Only after that** can B1 late-latch the hands after `xrLocateViews` without leaking photon-time pose into `AttackPos` â€” because `GetHandTransform` and the `AttackPos` write read the *same* `weaponoffset`/`weaponangles` globals. B1 is the single biggest presence win (held weapon/forearms stop swimming a frame behind the wrist), it is **CONFIRMED** mechanically (factor `updateHandPose` `:3261-3319` + the two-hand override `:3331-3348` into `RelocateHandPoses()`, call after `:4053`), and it is presentation-only per the documented `vr_ik_pose` rule (`d_player.h:561`). Sequence is non-negotiable: **A3 first, then B1.** Do this pair before any velocity-extrapolation (B4), which is the more speculative follow-on.

### 3. A2 + A4 â€” Haptics as a callable layer, with the channel contract fixed

Haptics are the cleanest unlock in the tree: the outbound C++â†’device path is fully built and fires on ~30 gameplay events, and the *only* missing seam is the inbound ZScript thunk (grep `DEFINE_ACTION_FUNCTION.*(Vibrate|Haptic)` = zero). A2 is a ~6-line addition mirroring `GetGripValue`. But it **must ship with A4**, because the channel/intensity contract is systematically broken *underneath* any API you expose: `VR_HapticEvent` position 1 and 2 **both** route to the RIGHT actuator (`vk_openxrdevice.cpp:5483-5496`), and three sites truncate a `1.0` float to a near-silent `0.01` amplitude. If you expose haptics to modders without fixing this, every ZScript author inherits an API where "left" silently means "right." Both are effort S, netplay impact **none** (device-thread output). The A2 thunk must convert a 0/1 hand index â†’ 1/2 position, skip `VR_HapticEvent`'s `/100` scaling by calling `Vibrate` directly, and cap its own duration (`ProcessHaptics` clamps amplitude but not duration). The richer envelope layer (C9) and predictive contact-haptics bus are natural follow-ons once the primitive and the contract are correct.

**Why these three over the alternatives.** A1 is the largest live-vs-dead delta in the codebase and gates a whole subsystem tree. A3â†’B1 pays down a confirmed net bug *and* delivers the top presence win, in the correct dependency order the recon proved is coupled. A2+A4 is the lowest-risk, highest-certainty modder unlock, and it forces the haptic-contract fix that any future haptic work (impact envelopes, parry rings, latch pops) depends on. All three are CONFIRMED seams with none-to-net-positive netplay impact. Continuous-collision melee (B7) is the natural fourth â€” it is CONFIRMED and high-payoff â€” but it carries real implementation debt the recon surfaced (missing `thing->radius` term, no `FBoundingBox::Expand`, missing Z-band test, and a per-swing hit-set to avoid double-hits), so it is a deliberate second wave, not a first.
