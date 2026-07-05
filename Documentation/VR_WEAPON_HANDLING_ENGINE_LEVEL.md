# Engine-Level VR Weapon Handling — Articulated Two-Hand + Manual Reload

**Status:** architecture spec. NATIVE-C++ mandate: these are first-class engine weapon subsystems, peers of
the grip arbiter / climb / hardpoints — NOT ZScript FSMs with keyword-offset hacks. Grounded in DOOM_FRESH
2026-07-04. Supersedes the hack-flavored `VR_MANUAL_RELOAD_HOTSPOTS_PLAN.md`.

## Governing principle
Both features are **native subsystems that run each tic in `P_PlayerThink`**, exactly like the ones already
there: `VR_ResolveGripOwner`, `VR_UpdateClimbing`, `VR_UpdateGravityGloves`, `VR_CalculateTwoHanding`,
`VR_UpdateHardpoints`, `VR_UpdateArmIK`. All state lives in `player_t` / a native weapon-runtime struct. All
logic is C++. **ZScript's ONLY role is per-weapon DATA declaration** — one line, mirroring how `AssignHardpoint`
already declares a hardpoint. No reload logic, no aim math, no FSM in ZScript.

---

## What is ALREADY native (do not rebuild — extend)
- **Articulated two-hand AIM is already engine-level.** `vk_openxrdevice.cpp:3331-3343` (and the GL twin
  `gl_openvr.cpp:2418`) compute the weapon's pitch/yaw from `(offHand.pos − mainHand.pos)` whenever
  `vr_two_hand_stabilized` is set — the barrel already points along the two-hand line, with recoil damping
  (`vr_stabilization_recoil_mult`). Articulation exists; it just needs a better *engage* condition + pivot.
- **Grip-intent arbiter** (`VR_ResolveGripOwner`, `player_t::vr_grip_owner[]`) — the native contention solver.
  `GRIP_TWOHAND` is already a defined owner slot. Reload and two-hand grabs become arbiter-owned contexts,
  so they never fight the other grip consumers.
- **Hardpoint subsystem** (`VR_UpdateHardpoints` + `AssignHardpoint` thunk) — the exact pattern both new
  subsystems mirror: native per-tic proximity/grip math, one-line ZScript declaration.
- **Two-hand proximity** (`VR_CalculateTwoHanding`) — currently PROXIMITY-only (off-hand near the barrel
  capsule, `vr_twohand_length`); reads no grip. To become "grab the handguard," it needs grip + a real
  foregrip point.
- **Arm IK** (`VR_UpdateArmIK`) — solves the visible arm to a target; the "smart hand snaps to the foregrip"
  render uses this, no new render code.

---

## The one native primitive both features need: HOTSPOTS
A weapon exposes named points on its mesh — `foregrip`, `magwell`, `rack` — that the engine resolves to world
space every tic. **Authored as empty bones in the IQM** (`hs_foregrip`, `hs_magwell`, `hs_rack`), read
natively. This is the *only* new low-level code, and it's tiny + read-only:

- **`GetBoneIndex(FName) -> int`** and **`GetBoneBindPos(int) -> DVector3`** native reads. The data already
  exists: `IQMModel::Joints[i].Translate` (bind-local) + `baseframe[i]` (parent-resolved), with joint names.
  Reachable via `modelData` / `VR_EnsureAvatarModelDataAndGetModel` (same seam `SetModelBonePose` uses).
- World position each tic = weapon-hand transform × bind-local hotspot. Same math the two-hand capsule runs.
- Static bind-pose lookup → zero per-tic solve, read-only → cannot destabilize render, **fully disjoint from
  the whip's bone-WRITE path** (the whip is unaffected).

No keyword-offset fallback. Hotspots are model data, resolved natively.

---

## Subsystem A — Articulated two-hand (native upgrade)
Engine changes, no ZScript logic:
1. **Engage on GRIP at the foregrip hotspot**, not bare proximity. `VR_CalculateTwoHanding` (or its successor)
   sets `vr_two_hand_stabilized` when: off-hand within a tight radius of the `foregrip` hotspot **AND** the
   arbiter grants that hand `GRIP_TWOHAND`. This is what makes it "grab the handguard," and it's contention-
   safe by construction (arbiter-owned).
2. **Pivot the articulation at the real foregrip.** The aim vector stays `offHand → mainHand`, but the render/
   hold pivots on the authored foregrip point, so the gun rotates about the handguard like a real long-arm.
3. **Smart-hand IK.** When engaged, target `VR_UpdateArmIK`'s off-hand at the `foregrip` world point so the
   visible hand locks onto the handguard instead of floating near the barrel.
4. Per-weapon handling feel (recoil mult, sway) reads native weapon data, not hard-coded.
5. **Off-hand-weapon -> vhand swap (the "busy off-hand" case).** The off-hand may be holding its OWN
   weapon (dual-wield). When it grips the main gun's `hs_foregrip`, the off-hand's weapon is **suspended**
   and the hand **renders as `vhand.iqm`** (bare hand on the pump) for as long as the foregrip is held; on
   release / pull-out, the off-hand weapon model + firing are restored (it was held in reserve, never dropped).
   - **Hotspot must be TINY (grip-gated + ~2u radius)** so a pistol drifting near the shotgun for aiming/
     reloading/gestures never hijacks the off-hand -- you only grab the pump when you deliberately squeeze on it.
   - While foregripping: the off-hand weapon's trigger is IGNORED (it's a support hand, not a firing hand).
   - One grip-arbiter context (`GRIP_TWOHAND` owns the off-hand): the hand is EITHER its weapon OR the foregrip,
     never both -- resolved per tic, so it can't fight climb/grab/pouch-reach.
   - Edge cases: main-weapon switch while foregripping -> drop two-hand, off-hand weapon returns; pouch-reach
     with a foregripping hand -> must release the foregrip first (arbiter forbids dual ownership).

---

## Subsystem B — Manual reload (new native FSM)
`VR_UpdateWeaponReload(player)` — a new C++ function in `p_user.cpp`, a peer of `VR_UpdateHardpoints`, called
in the `P_PlayerThink` consumer block. Entirely native:
- **State** on a native per-weapon runtime (extend `player_t` or a `VRWeaponRuntime` struct like
  `vr_hardpoints[]`): `reloadState`, `magSeated`, `chambered`, `roundsInMag`.
- **FSM** (box-mag reference style): `READY → (fire to empty) → EMPTY → magOut → magIn(seated) → racked → READY`.
  Each transition gated on the right hotspot proximity + grip ownership + gesture:
  - `magwell`: off-hand (holding a mag, or empty for "slap") reaches the magwell hotspot + grip → seat mag.
  - `rack`: hand grabs the `rack` hotspot (arbiter grip-owned) + pulls past a travel threshold → chamber.
- **Gestures are native** (hotspot proximity + `GetHandVelocity` + grip ownership), same primitives climb/
  hardpoints already use. No ZScript polling.
- **Reload styles** are native variants selected by per-weapon data: `boxmag` (seat+rack), `shell` (shotgun
  shell-by-shell), `break` (SxS/revolver), `internal`. Start with `boxmag`.
- **Flatscreen fallback**: the native path falls back to the existing button reload when `!PlayInVR` (standing
  rule), so non-VR play is unaffected.
- **Ammo**: seated-mag → ammo refill maps to the weapon's existing AmmoType natively.

---

## Subsystem C — Centralized ammo pouch + reload sourcing (native)
**Body-zone allocation (locked):** wrist hardpoints = spells/abilities; hip holsters = sword + whip;
shoulder holsters = ice picks. Reload therefore uses the **CHEST** — the one free natural VR reach.

- **One native reach zone**, chest-center, `HP_ANCHOR_BODY`, role = DISPENSER (not a holster — it hands out
  a clip rather than storing a weapon). Reach in + grip.
- **Weapon-aware sourcing:** on grab it spawns the CURRENT weapon's clip as a native held item (reuse the
  gravity-glove held slot). Real assets exist at `Desktop\BUGFIX\...\models\ammo_hand`: `mag_pistol.md3`,
  `mag_plasma.md3`, `mag_chaingun.md3`, `shot_shell.md3`/`shot_shell2.md3`, `pod_rocket.md3`, `pod_bfg.md3`,
  `pod_heat.md3`, `flame_can.md3`, `ammo_hand.md3`. Copy into the tree as held props (no rig needed → MD3 fine).
- **Ammo-gated, not pouch-counted:** the pouch draws from the weapon's existing reserve AmmoType. Empty
  reserve → no clip. Seated clip → refill the mag natively.

### Reload styles (native FSM variants, selected by per-weapon data)
- **boxmag** (pistol/plasma/chaingun): dry → grip pouch (clip in hand) → to `hs_magwell` → magnetic-assist
  snap+seat → grab `hs_rack` + pull → chamber → READY.
- **shell** (shotgun): pouch → shell → `hs_port` insert → repeat → pump to chamber. Rhythmic.
- **pod** (rocket/BFG): pouch → pod → `hs_breech` → close. One at a time.
- **canister** (flamethrower): `flame_can` swap at `hs_tank`.

### Smooth-feel requirements (the "near-AAA for ZDoom" bar)
- **Magnetic assist**: auto-align + snap the clip when inside the magwell radius (tunable `vr_reload_assist`;
  off = hardcore). This is the single biggest fiddly-vs-satisfying lever.
- **Real held clip** (gravity-glove slot), not a teleport-snap — visible travel to the gun.
- **Layered per-weapon feedback**: mag-out click, seat click+haptic, rack clack+haptic, chamber thunk.
- **Forgiving + soft-lock-proof**: generous hotspot radii; the FSM no-ops out-of-order gestures, never jams.

### Complete weapon -> reload map (verified roster + ammo types 2026-07-04)
| Weapon | Ammo | Style | Clip model | Status |
|---|---|---|---|---|
| Pistol | Clip | boxmag | mag_pistol | have |
| Chaingun | Clip | boxmag/belt | mag_chaingun | have |
| SMG | Clip | boxmag | reuse mag_pistol (or new mag_smg) | reuse |
| Rifle | Clip | boxmag | reuse mag_chaingun/new | reuse |
| Revolver | Clip | SPEEDLOADER/cylinder | NEW object (not a box mag) | needs model+style |
| Shotgun | Shell | shell-by-shell (tube) | shot_shell | have |
| SuperShotgun | Shell | break, load 2 | shot_shell/shot_shell2 | have |
| RocketLauncher | RocketAmmo | single-pod breech | pod_rocket | have |
| M79 | RocketAmmo | break, 1 round | reuse pod_rocket | reuse |
| PlasmaRifle | Cell | cell-mag | mag_plasma | have |
| ID24Incinerator | Cell | canister | pod_heat | have |
| BFG9000 | Cell | single-pod | pod_bfg | have |
| Flamethrower | Fuel | canister swap | flame_can | have |
| HandGrenade | GrenadeAmmo | pouch-dispense (grab+throw) | the grenade itself | natural |
| Fist/Chainsaw/ShieldSaw/CalamityBlade/VRSword/XRWhip/IceHook | -- | NONE (melee/VR tool) | -- | reload-less by design |
**Nothing orphaned:** 9 have their exact clip; ~3 reuse one; only the Revolver needs a genuinely new object.

### Reload MODES (the customization spine — global default + per-weapon override)
- **fullmanual** (chest pouch) — immersive default.
- **quickmag** (weapon-integrated) — spare mag/side-saddle/spare-rocket rides on an `hs_sparemag` hotspot;
  grab it off the gun (no chest reach), slap home, rack. Toggle: one-and-done (realism) vs refilling (arcade).
- **gesture** — single abstracted motion, no fetch (comfort/fast).
- **auto** — reload-on-empty, no reach (accessibility).
- **classic** — button reload (flatscreen/legacy).

### VR Options — extreme customization (global + per-weapon)
- `vr_reload_mode` (per-weapon override) — the 5 modes above.
- `vr_reload_assist` — magnetic-assist strength 0 (surgical/hardcore) .. max (snaps in).
- `vr_reload_chamber` — must-rack-every-time vs auto-chamber; tactical reload keeps the chambered round.
- Pouch placement sliders — chest height / forward / side (tune the zone to the player's torso).
- Fetch hand — handedness via `VR_PhysicalHandForSlot`.
- Shell-by-shell — auto-stop-at-full vs load-past.
- Per-step haptic intensity (mag click / rack / chamber).
- Fumble realism — dropped mags persist vs vanish.
- Mag-swap time scale (feel).
All exposed in a `VRReloadOptions` menu (mirrors `VRWhipOptions`/`VRGrabOptions`), inert-safe defaults.

### Options considered
1. **Centralized chest pouch (CHOSEN)** — immersive, uses the free real-estate, fits the reserved-zone map.
2. Weapon-integrated spare (slap a mag off the gun) — faster/less physical; viable per-weapon fallback.
3. **Comfort / quick-reload toggle** (single abstracted motion, skips the fetch) — accessibility layer ON TOP
   of #1 (`vr_reload_quick`), not a replacement.
Ship #1 as the system + #3 as a toggle.

## The ZScript surface (DATA ONLY — the whole modder API)
Per weapon, one declaration line, mirroring `AssignHardpoint`:
```
// engine reads the hs_* bones itself; this just says which style + which bones this weapon uses.
AssignWeaponHandling("boxmag");   // reload style; hotspots auto-read from the IQM's hs_foregrip/hs_magwell/hs_rack
```
That's it. No FSM, no offsets, no aim math in ZScript. Everything else is engine.

---

## Asset sourcing (which mesh per weapon)
Primary source = `Desktop\BUGFIX\doom-force-unleashed_devbuild\models` — fuller set AND **modular**: each gun
ships as separate meshes (e.g. `pistol/berreta.md3` + `berreta_mag.md3` + `berreta_mf.md3`; `bfg9000/` +
`bfg9000_pod.md3`; `shotgun/` + `shell.md3`). The separate **mag/pod = the held reload object directly** (no
mag-bone rig needed); the `_mf` = muzzle flash spawned at a flash hotspot. BUGFIX covers: pistol, shotgun,
ssg, chaingun, bfg9000, rocketlauncher, plasmarifle, chainsaw, shieldsaw, incinerator, heatwave(flamethrower).
- **Keep OUR models (BUGFIX lacks these):** Revolver (also needs the new speedloader), Rifle (m16), SMG, M79,
  HandGrenade.
- **VR tools stay on our IQM:** Fist(hands), VRSword (sword_steel), XRWhip (whip_rigged), IceHook (icehook), vhand.
- Pipeline is source-agnostic: chosen MD3 -> IQM, add `hs_*` hotspots, drop baked frames (procedural replaces).
  BUGFIX's separate mag/pod/flash meshes become held reload props + flash actors with zero extra rigging.

## Migration SAFETY (non-negotiable — never all-or-nothing)
- **KEEP every MD3. Delete nothing.** IQM versions live ALONGSIDE; modeldef points at one or the other.
- **Toggle-gated** (`vr_new_weapon_handling`, default OFF until proven) — OFF = today's behavior bit-for-bit
  (MD3 + classic button reload). ON = IQM + manual reload. Same escape-hatch pattern as `vr_grip_arbiter`.
- **Per-weapon rollout, not all-at-once.** Migrate ONE weapon (m16 box-mag) end-to-end, prove in-headset,
  then roll out one at a time. Unconverted weapons keep MD3 + classic reload independently.
- **Cost shape:** ONE C++ build for the foundation (bone-read + FSM + two-hand). After that, every model
  swap / hotspot is **pk3-only** (re-zip, no C++ recompile) — cheap, safe iteration.
- **Bail-out:** flip the CVar off + point modeldefs back at the MD3s (never moved). Instantly on today's build.

## Migration (each step compiles; native throughout)
1. **Hotspot reads** — `GetBoneIndex`/`GetBoneBindPos` thunks + `models_iqm` access. Prove on one IQM weapon.
2. **IQM-convert the gun models** (Pistol/Shotgun/Plasma/m16 MD3 → IQM) with `hs_*` empties; drop canned MD3
   reload frames (native reload replaces them), keep fire/idle poses.
3. **Articulated two-hand upgrade** — grip-at-foregrip engage + IK snap. (Aim math already native.)
4. **`VR_UpdateWeaponReload`** FSM + native weapon-runtime state; wire the `boxmag` style end-to-end on the m16.
5. **Mag object + chamber + ammo** integration (grabbable mag reuses the gravity-glove held slot).
6. Add `shell` / `break` styles as native FSM variants.

## Files (all native)
- `src/common/models/models_iqm.cpp` + `model_iqm.h` — expose bind-pose joint read.
- `src/scripting/vmthunks_actors.cpp` — `GetBoneIndex`/`GetBoneBindPos` + `AssignWeaponHandling` data thunk.
- `src/playsim/p_user.cpp` — `VR_UpdateWeaponReload` (new), upgrade `VR_CalculateTwoHanding`, call in P_PlayerThink.
- `src/playsim/d_player.h` — native weapon-runtime reload/chamber state (excluded from serializer, per rule).
- `vk_openxrdevice.cpp` / `gl_openvr.cpp` — pivot the existing two-hand articulation at the foregrip hotspot.
- `wadsrc/static/.../<weapon>.zs` — ONE `AssignWeaponHandling(...)` line each. No logic.

## Related
[[dxr-grip-arbiter-implemented]] · [[dxr-iqm-reload-mechanism]] · [[dxr-verified-quat-bone-hand-facts]] ·
[[hf-doomxr-iqm-tier1-no-bones]] · `DoomXR_VRSword_HandVelocity_Patch_Spec.md` (native-patch precedent).
Bone-read = Phase 1 dependency shared by BOTH subsystems → one build, not two.
